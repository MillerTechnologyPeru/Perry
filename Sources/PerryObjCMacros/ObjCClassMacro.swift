import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @ObjCClass exposes a Swift class to Objective-C, and @ObjCCategory adds a
// Swift class's methods to an existing Objective-C class. For each
// @ObjCMethod and @ObjCClassMethod function with a body they generate a C
// thunk that converts the receiver and arguments through ObjCValue
// (PerryObjCInterop), calls the function and converts the result, plus
// registerObjCMethods(_:). A method function without a body calls the
// selector instead: the method macros give it a body that sends the message,
// as @ObjCProperty does for a property's accessors.

@main
struct PerryObjCMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObjCClassMacro.self,
        ObjCWrapperMacro.self,
        ObjCCategoryMacro.self,
        ObjCConstantsMacro.self,
        ObjCMethodMacro.self,
        ObjCPropertyMacro.self,
    ]
}

struct ObjCMacroDiagnostic: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "PerryObjCMacros", id: "objc") }
    var severity: DiagnosticSeverity { .error }
}

struct ObjCMacroError: Error {
    let message: String
    let node: Syntax

    init(_ message: String, at node: some SyntaxProtocol) {
        self.message = message
        self.node = Syntax(node)
    }

    func diagnose(in context: some MacroExpansionContext) {
        context.diagnose(Diagnostic(node: node, message: ObjCMacroDiagnostic(message: message)))
    }
}

// MARK: - Reading declarations

/// The type name to use in `T.ObjCType` and `T(objCArgument:)`: optionals
/// spelled out, `Self` replaced by the wrapper type.
func metatype(_ type: TypeSyntax, selfType: String?) -> String {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return "Optional<\(metatype(optional.wrappedType, selfType: selfType))>"
    }
    if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return "Optional<\(metatype(unwrapped.wrappedType, selfType: selfType))>"
    }
    let text = type.trimmedDescription
    if text == "Self", let selfType { return selfType }
    return text
}

/// Objective-C's ownership families, from the selector's first word.
enum SelectorFamily {
    case alloc, new, copy, mutableCopy, initializer, memoryManagement, none

    init(_ selector: String) {
        let memory: Set<String> = ["retain", "release", "autorelease", "retainCount", "dealloc", "_tryRetain",
                                   "_isDeallocating", "allowsWeakReference", "retainWeakReference"]
        if memory.contains(selector) {
            self = .memoryManagement
            return
        }
        let name = selector.drop { $0 == "_" }
        func starts(_ word: String) -> Bool {
            guard name.hasPrefix(word) else { return false }
            let next = name.dropFirst(word.count).first
            return next == nil || !(next!.isLowercase)
        }
        if starts("alloc") { self = .alloc }
        else if starts("new") { self = .new }
        else if starts("mutableCopy") { self = .mutableCopy }
        else if starts("copy") { self = .copy }
        else if starts("init") { self = .initializer }
        else { self = .none }
    }

    /// Results of these methods are +1.
    var returnsOwned: Bool {
        switch self {
        case .alloc, .new, .copy, .mutableCopy, .initializer: return true
        default: return false
        }
    }
}

/// A function marked @ObjCMethod or @ObjCClassMethod.
struct ObjCMethodDeclaration {
    let selector: String
    let explicitTypes: String?
    let isClassMethod: Bool
    let name: String
    let parameters: [FunctionParameterSyntax]
    let returnType: TypeSyntax?
    /// An implementation's leading ObjCClass parameter, for the receiver.
    let takesClass: Bool
    /// Has no body: calls the selector rather than implementing it.
    let isCall: Bool

    var family: SelectorFamily { SelectorFamily(selector) }

    /// The parameters that are the selector's arguments.
    var arguments: ArraySlice<FunctionParameterSyntax> { takesClass ? parameters.dropFirst() : parameters[...] }

    static func attribute(in attributes: AttributeListSyntax) -> AttributeSyntax? {
        for element in attributes {
            if case .attribute(let attribute) = element,
               let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               name == "ObjCMethod" || name == "ObjCClassMethod" {
                return attribute
            }
        }
        return nil
    }

    init(_ declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax) throws {
        isClassMethod = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "ObjCClassMethod"
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
              let first = arguments.first, first.label == nil,
              let selector = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
              !selector.isEmpty else {
            throw ObjCMacroError("the selector must be a string literal", at: attribute)
        }
        self.selector = selector
        explicitTypes = arguments.dropFirst().first { $0.label?.text == "types" }
            .flatMap { $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue }

        let signature: FunctionSignatureSyntax
        let modifiers: DeclModifierListSyntax
        if let function = declaration.as(FunctionDeclSyntax.self) {
            signature = function.signature
            modifiers = function.modifiers
            name = function.name.text
            isCall = function.body == nil
            if function.genericParameterClause != nil {
                throw ObjCMacroError("Objective-C methods cannot be generic", at: function.name)
            }
        } else if let initializer = declaration.as(InitializerDeclSyntax.self) {
            throw ObjCMacroError("implement init methods as functions that return Self, not as Swift initializers",
                                 at: initializer.initKeyword)
        } else {
            throw ObjCMacroError("@ObjCMethod applies to functions and initializers", at: attribute)
        }

        if signature.effectSpecifiers?.asyncSpecifier != nil || signature.effectSpecifiers?.throwsClause != nil {
            throw ObjCMacroError("Objective-C methods cannot be async or throw", at: signature)
        }
        let isStatic = modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
        if isClassMethod && !isStatic {
            throw ObjCMacroError("@ObjCClassMethod applies to static functions", at: attribute)
        }
        if !isClassMethod && isStatic {
            throw ObjCMacroError("@ObjCMethod applies to instance methods; use @ObjCClassMethod", at: attribute)
        }
        parameters = Array(signature.parameterClause.parameters)
        returnType = signature.returnClause?.type
        for parameter in parameters where parameter.type.is(AttributedTypeSyntax.self) {
            throw ObjCMacroError("inout and attributed parameters are not supported", at: parameter)
        }
        takesClass = !isCall && isClassMethod && parameters.first?.type.trimmedDescription == "ObjCClass"
        if isCall {
            for parameter in parameters where (parameter.secondName ?? parameter.firstName).tokenKind == .wildcard {
                throw ObjCMacroError("name the parameter: the message send passes it", at: parameter)
            }
        }

        let colons = selector.filter { $0 == ":" }.count
        let count = takesClass ? parameters.count - 1 : parameters.count
        guard colons == count else {
            throw ObjCMacroError(
                "selector '\(selector)' takes \(colons) argument\(colons == 1 ? "" : "s"), but the function takes \(count)",
                at: signature.parameterClause)
        }
    }

    /// The C signature of the method: receiver, _cmd, then arguments.
    func cSignature(selfType: String?) -> String {
        let arguments = arguments.map { "\(metatype($0.type, selfType: selfType)).ObjCType" }
        return "@convention(c) (" + (["UnsafeMutableRawPointer?", "UnsafeRawPointer?"] + arguments).joined(separator: ", ")
            + ") -> " + cReturnType(selfType: selfType)
    }

    func cReturnType(selfType: String?) -> String {
        return returnType.map { "\(metatype($0, selfType: selfType)).ObjCType" } ?? "Void"
    }

    /// `ObjCTypeEncoding.method(…)`, or the explicit encoding.
    func typesExpression(selfType: String?) -> String {
        if let explicitTypes { return literal(explicitTypes) }
        let result = returnType.map { "\(metatype($0, selfType: selfType)).self" } ?? "nil"
        let arguments = arguments.map { "\(metatype($0.type, selfType: selfType)).self" }
        return "ObjCTypeEncoding.method(returning: \(result), arguments: [\(arguments.joined(separator: ", "))])"
    }

    /// The message send that is a call's body.
    var sendStatements: [String] {
        let arguments = parameters.map { parameter in
            (type: metatype(parameter.type, selfType: nil), value: (parameter.secondName ?? parameter.firstName).text)
        }
        return messageSend(selector, toClass: isClassMethod, arguments: arguments,
                           returning: returnType.map { metatype($0, selfType: nil) })
    }

    /// Call arguments, labelled as the Swift declaration labels them.
    func callArguments(_ values: [String]) -> String {
        zip(parameters, values).map { parameter, value in
            let label = parameter.firstName.text
            return label == "_" ? value : "\(label): \(value)"
        }.joined(separator: ", ")
    }
}

/// Statements that send `selector` to `self` (the object, or for a class
/// method the class) through objc_msgSend cast to the method's C signature,
/// converting the arguments and the result through ObjCValue. init methods
/// consume the receiver, so they get a new reference; results of alloc,
/// new, copy and init methods are owned.
func messageSend(_ selector: String, toClass: Bool, arguments: [(type: String, value: String)],
                 returning returnType: String?) -> [String] {
    let family = SelectorFamily(selector)
    let receiver = toClass ? "self.objCClass.pointer"
        : family == .initializer ? "ObjCRuntime.retain(objcObject)" : "objcObject"
    // A type alias cannot name Self.ObjCType; every wrapper's is an object pointer.
    func cType(_ type: String) -> String {
        type == "Self" || type == "Optional<Self>" ? "UnsafeMutableRawPointer?" : "\(type).ObjCType"
    }
    let cArguments = ["UnsafeMutableRawPointer?", "UnsafeRawPointer?"] + arguments.map { cType($0.type) }
    let send = "message(" + ([receiver, "ObjCRuntime.selector(\(literal(selector)))"]
        + arguments.map { "\($0.value).objCArgument()" }).joined(separator: ", ") + ")"
    var statements = [
        "typealias Message = @convention(c) (\(cArguments.joined(separator: ", "))) -> \(returnType.map(cType) ?? "Void")",
        "let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)",
    ]
    let conversion = family.returnsOwned ? "objCOwned" : "objCReturnValue"
    if returnType == "Optional<Self>" {
        statements.append("return \(send).map { Self(\(conversion): $0) }")
    } else if let returnType {
        statements.append("return \(returnType)(\(conversion): \(send))")
    } else {
        statements.append(send)
    }
    return statements
}

func literal(_ string: String) -> String {
    "\"" + string.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
}

// MARK: - @ObjCClass

public struct ObjCClassMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            ObjCMacroError("@ObjCClass applies to a class", at: node).diagnose(in: context)
            return []
        }
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let className = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            ObjCMacroError("the class name must be a string literal", at: node).diagnose(in: context)
            return []
        }
        guard let superclass = classDecl.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription else {
            ObjCMacroError("an @ObjCClass class inherits from its Objective-C superclass's class, such as NSObject",
                           at: classDecl.name).diagnose(in: context)
            return []
        }
        let access = accessLevel(of: classDecl)
        return [
            "\(raw: access)override class var objCClassName: String { \(literal: className) }",
            "\(raw: access)override class var objCSuperclassName: String? { \(raw: superclass).objCClassName }",
            registerMethods(classDecl, access: access),
        ]
    }

    static func accessLevel(of classDecl: ClassDeclSyntax) -> String {
        classDecl.modifiers.contains { [.keyword(.public), .keyword(.open)].contains($0.name.tokenKind) } ? "public " : ""
    }

    /// registerObjCMethods(_:) for the @ObjCMethod and @ObjCClassMethod
    /// functions in the class body.
    static func registerMethods(_ classDecl: ClassDeclSyntax, access: String) -> DeclSyntax {
        var registrations: [String] = []
        for member in classDecl.memberBlock.members {
            let decl = member.decl
            guard let attributes = decl.asProtocol(WithAttributesSyntax.self)?.attributes,
                  let attribute = ObjCMethodDeclaration.attribute(in: attributes),
                  let method = try? ObjCMethodDeclaration(decl, attribute: attribute), !method.isCall else {
                continue    // errors are reported by @ObjCMethod; calls are not implementations
            }
            registrations.append(registration(method, typeName: classDecl.name.text))
        }
        let body = registrations.map { "    " + $0 }.joined(separator: "\n")
        return """
            \(raw: access)override class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {
            \(raw: body)
            }
            """
    }

    /// `registrar.addMethod(…)` with a thunk that converts the receiver and
    /// arguments, calls the function and converts its result.
    static func registration(_ method: ObjCMethodDeclaration, typeName: String) -> String {
        var closureParameters = ["receiver: UnsafeMutableRawPointer?", "_: UnsafeRawPointer?"]
        var values: [String] = method.takesClass ? ["ObjCClass(receiver!)"] : []
        for (index, parameter) in method.arguments.enumerated() {
            let type = metatype(parameter.type, selfType: typeName)
            closureParameters.append("a\(index): \(type).ObjCType")
            values.append("\(type)(objCArgument: a\(index))")
        }
        let returnType = method.cReturnType(selfType: typeName)

        var body: [String] = []
        let target: String
        if method.isClassMethod {
            target = typeName
        } else {
            // init methods consume the receiver; retain, release and dealloc
            // must not retain it; everything else holds a reference.
            let ownership: String
            switch method.family {
            case .initializer: ownership = ".adopt"
            case .memoryManagement: ownership = ".borrow"
            default: ownership = ".retain"
            }
            body.append("let this = \(typeName)(objcObject: receiver!, ownership: \(ownership))")
            target = "this"
        }
        let call = "\(target).\(method.name)(\(method.callArguments(values)))"
        if method.returnType != nil {
            let conversion = method.family.returnsOwned ? "objCOwnedReturnValue" : "objCReturnValue"
            body.append("return \(call).\(conversion)()")
        } else {
            body.append(call)
        }

        let thunk = "{ (\(closureParameters.joined(separator: ", "))) -> \(returnType) in "
            + body.joined(separator: "; ") + " } as " + method.cSignature(selfType: typeName)
        return "registrar.addMethod(\(literal(method.selector)), types: \(method.typesExpression(selfType: typeName)), "
            + "implementation: unsafeBitCast(\(thunk), to: UnsafeRawPointer.self), isClassMethod: \(method.isClassMethod))"
    }
}

// MARK: - @ObjCWrapper

/// A wrapper for a class another library defines: its names, and only
/// methods that call the class's.
public struct ObjCWrapperMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            ObjCMacroError("@ObjCWrapper applies to a class", at: node).diagnose(in: context)
            return []
        }
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let className = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            ObjCMacroError("the class name must be a string literal", at: node).diagnose(in: context)
            return []
        }
        guard let superclass = classDecl.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription else {
            ObjCMacroError("an @ObjCWrapper class inherits from its Objective-C superclass's class, such as NSObject",
                           at: classDecl.name).diagnose(in: context)
            return []
        }
        for member in classDecl.memberBlock.members {
            guard let attributes = member.decl.asProtocol(WithAttributesSyntax.self)?.attributes,
                  let attribute = ObjCMethodDeclaration.attribute(in: attributes),
                  let method = try? ObjCMethodDeclaration(member.decl, attribute: attribute), !method.isCall else { continue }
            ObjCMacroError("a wrapper's methods call the class's and have no body; implement methods with @ObjCClass or @ObjCCategory",
                           at: attribute).diagnose(in: context)
        }
        let access = ObjCClassMacro.accessLevel(of: classDecl)
        return [
            "\(raw: access)override class var objCClassName: String { \(literal: className) }",
            "\(raw: access)override class var objCSuperclassName: String? { \(raw: superclass).objCClassName }",
        ]
    }
}

// MARK: - @ObjCCategory

public struct ObjCCategoryMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let extensionDecl = declaration.as(ExtensionDeclSyntax.self) else {
            ObjCMacroError("@ObjCCategory applies to an extension of an Objective-C class's wrapper", at: node)
                .diagnose(in: context)
            return []
        }
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let name = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
              let first = name.first, first.isLetter || first == "_",
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            ObjCMacroError("the category name must be a string literal that is a Swift identifier", at: node)
                .diagnose(in: context)
            return []
        }
        let typeName = extensionDecl.extendedType.trimmedDescription
        let access = extensionDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        var registrations: [String] = []
        for member in extensionDecl.memberBlock.members {
            let decl = member.decl
            guard let attributes = decl.asProtocol(WithAttributesSyntax.self)?.attributes,
                  let attribute = ObjCMethodDeclaration.attribute(in: attributes),
                  let method = try? ObjCMethodDeclaration(decl, attribute: attribute), !method.isCall else {
                continue    // errors are reported by @ObjCMethod; calls are not implementations
            }
            registrations.append(ObjCClassMacro.registration(method, typeName: typeName))
        }
        let body = registrations.map { "    " + $0 }.joined(separator: "\n")
        return [
            """
            /// Installs the \(raw: name) category's methods into `registrar`.
            \(raw: access)static func registerObjCCategory\(raw: name)(_ registrar: any ObjCMethodRegistrar) {
            \(raw: body)
            }
            """,
            """
            /// Adds the \(raw: name) category's methods to \(raw: typeName)'s class.
            \(raw: access)static func addObjCCategory\(raw: name)() {
                registerObjCCategory\(raw: name)(objCClass)
            }
            """,
        ]
    }
}

// MARK: - @ObjCConstants

/// Collects a type's `static let` constants into an ObjCConstantTable.
public struct ObjCConstantsMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        var constants: [(name: String, value: ExprSyntax?)] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.let),
                  variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                constants.append((name, binding.initializer?.value))
            }
        }
        let names = Set(constants.map(\.name))
        let access = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        let entries = constants.map { constant -> String in
            let value: String
            if constant.value?.is(StringLiteralExprSyntax.self) == true {
                value = ".string(\(constant.name))"
            } else if let reference = constant.value?.as(DeclReferenceExprSyntax.self),
                      names.contains(reference.baseName.text) {
                value = ".alias(\(literal(reference.baseName.text)))"
            } else {
                value = ".object({ \(constant.name) })"
            }
            return "        (\(literal(constant.name)), \(value)),"
        }
        var members: [DeclSyntax] = ["""
            \(raw: access)static var objCConstants: [(name: String, value: ObjCConstantValue)] {
                [
            \(raw: entries.joined(separator: "\n"))
                ]
            }
            """]
        for constant in constants {
            members.append("""
                /// \(raw: constant.name)'s exported object.
                \(raw: access)static var \(raw: constant.name)Object: UnsafeMutableRawPointer {
                    ObjCConstantExports.shared.object(\(literal: constant.name))
                }
                """)
        }
        return members
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): ObjCConstantTable {}")]
    }
}

// MARK: - @ObjCMethod and @ObjCClassMethod

/// Checks a method function. A function with a body implements the
/// selector and keeps its body; one without gets a body that sends the
/// message.
public struct ObjCMethodMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        let method: ObjCMethodDeclaration
        do {
            method = try ObjCMethodDeclaration(declaration, attribute: node)
        } catch let error as ObjCMacroError {
            error.diagnose(in: context)
            return declaration.body.map { Array($0.statements) } ?? ["fatalError()"]
        }
        if let body = declaration.body { return Array(body.statements) }
        return method.sendStatements.map { "\(raw: $0)" }
    }
}

// MARK: - @ObjCProperty

/// Gives a property accessors that send its getter and, unless it is
/// read-only, its setter (`setName:`).
public struct ObjCPropertyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              variable.bindingSpecifier.tokenKind == .keyword(.var),
              let binding = variable.bindings.first, variable.bindings.count == 1,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let type = binding.typeAnnotation?.type,
              binding.accessorBlock == nil, binding.initializer == nil else {
            ObjCMacroError("@ObjCProperty applies to a `var` with a type and no value or accessors", at: node)
                .diagnose(in: context)
            return []
        }
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        func argument(_ label: String) -> ExprSyntax? { arguments?.first { $0.label?.text == label }?.expression }
        let getter = argument("getter")?.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? name
        let readonly = argument("readonly")?.as(BooleanLiteralExprSyntax.self)?.literal.tokenKind == .keyword(.true)
        let isClassProperty = variable.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        let typeName = metatype(type, selfType: nil)

        func accessor(_ kind: String, _ statements: [String]) -> AccessorDeclSyntax {
            "\(raw: kind) {\n\(raw: statements.map { "    " + $0 }.joined(separator: "\n"))\n}"
        }
        var accessors = [accessor("get", messageSend(getter, toClass: isClassProperty, arguments: [],
                                                     returning: typeName))]
        if !readonly {
            let setter = "set" + name.prefix(1).uppercased() + name.dropFirst() + ":"
            accessors.append(accessor("set", messageSend(setter, toClass: isClassProperty,
                                                         arguments: [(typeName, "newValue")], returning: nil)))
        }
        return accessors
    }
}
