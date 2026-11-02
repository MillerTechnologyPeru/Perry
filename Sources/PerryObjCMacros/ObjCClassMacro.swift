import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @ObjCClass exposes a Swift class to Objective-C: for each @ObjCMethod and
// @ObjCClassMethod function in its body it generates a C thunk that converts
// the receiver and arguments through ObjCValue (PerryObjCInterop), calls the
// function and converts the result, plus the class's names and
// registerObjCMethods(_:). The method macros only check their functions.

@main
struct PerryObjCMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObjCClassMacro.self,
        ObjCMethodMacro.self,
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
            if function.body == nil {
                throw ObjCMacroError("an Objective-C method needs a body: it implements the selector", at: function.name)
            }
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
        takesClass = isClassMethod && parameters.first?.type.trimmedDescription == "ObjCClass"

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

    /// Call arguments, labelled as the Swift declaration labels them.
    func callArguments(_ values: [String]) -> String {
        zip(parameters, values).map { parameter, value in
            let label = parameter.firstName.text
            return label == "_" ? value : "\(label): \(value)"
        }.joined(separator: ", ")
    }
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
        let typeName = classDecl.name.text
        let access = classDecl.modifiers.contains { [.keyword(.public), .keyword(.open)].contains($0.name.tokenKind) }
            ? "public " : ""

        var registrations: [String] = []
        for member in classDecl.memberBlock.members {
            let decl = member.decl
            guard let attributes = decl.asProtocol(WithAttributesSyntax.self)?.attributes,
                  let attribute = ObjCMethodDeclaration.attribute(in: attributes),
                  let method = try? ObjCMethodDeclaration(decl, attribute: attribute) else {
                continue    // errors are reported by @ObjCMethod
            }
            registrations.append(registration(method, typeName: typeName))
        }
        let body = registrations.map { "    " + $0 }.joined(separator: "\n")
        return [
            "\(raw: access)override class var objCClassName: String { \(literal: className) }",
            "\(raw: access)override class var objCSuperclassName: String? { \(raw: superclass).objCClassName }",
            """
            \(raw: access)override class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {
            \(raw: body)
            }
            """,
        ]
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

// MARK: - @ObjCMethod and @ObjCClassMethod

/// Marks a function as implementing a selector, and checks it.
public struct ObjCMethodMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        do {
            _ = try ObjCMethodDeclaration(declaration, attribute: node)
        } catch let error as ObjCMacroError {
            error.diagnose(in: context)
        }
        return []
    }
}
