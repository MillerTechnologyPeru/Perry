import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// Macros for implementing Objective-C classes in Swift.
//
//     @ObjCImplementation
//     enum NSStringMethods {
//         @ObjCMethod("characterAtIndex:")
//         static func character(_ string: id?, at index: UInt) -> UInt16 { … }
//     }
//
// @ObjCImplementation generates `register(_:)`, which installs every marked
// method through an ObjCMethodRegistrar. Each method gets a C-convention
// thunk that takes the receiver, then _cmd, then the arguments, and a type
// encoding derived from its Swift types. @ObjCMethod and @ObjCClassMethod
// check each signature against its selector.

@main
struct PerryObjCMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObjCImplementationMacro.self,
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
}

/// One method marked with @ObjCMethod or @ObjCClassMethod.
struct ObjCMethod {
    let selector: String
    let types: String
    let isClassMethod: Bool
    let function: FunctionDeclSyntax

    /// The marking attribute, or nil if the function has none.
    static func attribute(of function: FunctionDeclSyntax) -> AttributeSyntax? {
        for element in function.attributes {
            if case .attribute(let attribute) = element,
               let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               name == "ObjCMethod" || name == "ObjCClassMethod" {
                return attribute
            }
        }
        return nil
    }

    /// Reads and checks a marked method.
    init(_ function: FunctionDeclSyntax, attribute: AttributeSyntax) throws {
        self.function = function
        isClassMethod = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "ObjCClassMethod"

        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
              let first = arguments.first, first.label == nil,
              let selector = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
              !selector.isEmpty else {
            throw ObjCMacroError(message: "the selector must be a string literal", node: Syntax(attribute))
        }
        self.selector = selector
        var explicitTypes: String?
        for argument in arguments.dropFirst() where argument.label?.text == "types" {
            guard let value = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                throw ObjCMacroError(message: "types: must be a string literal", node: Syntax(argument))
            }
            explicitTypes = value
        }

        guard function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
            throw ObjCMacroError(message: "Objective-C methods must be static functions", node: Syntax(function.name))
        }
        if function.signature.effectSpecifiers?.asyncSpecifier != nil
            || function.signature.effectSpecifiers?.throwsClause != nil {
            throw ObjCMacroError(message: "Objective-C methods cannot be async or throw", node: Syntax(function.signature))
        }
        if function.genericParameterClause != nil {
            throw ObjCMacroError(message: "Objective-C methods cannot be generic", node: Syntax(function.name))
        }
        let parameters = Array(function.signature.parameterClause.parameters)
        guard !parameters.isEmpty else {
            throw ObjCMacroError(message: "the first parameter must be the receiver (self)", node: Syntax(function.signature))
        }
        for parameter in parameters where parameter.type.is(AttributedTypeSyntax.self) {
            throw ObjCMacroError(message: "inout and attributed parameters are not supported", node: Syntax(parameter))
        }
        let colons = selector.filter { $0 == ":" }.count
        guard colons == parameters.count - 1 else {
            throw ObjCMacroError(
                message: "selector '\(selector)' takes \(colons) argument\(colons == 1 ? "" : "s"), but the function takes \(parameters.count - 1) after the receiver",
                node: Syntax(function.signature.parameterClause))
        }

        if let explicitTypes {
            types = explicitTypes
        } else {
            types = try TypeEncoding.methodTypes(
                returning: function.signature.returnClause?.type,
                arguments: parameters.dropFirst().map(\.type))
        }
    }

    /// `registrar.addMethod(…)` with a C-convention thunk.
    func registration(typeName: String) -> String {
        let parameters = Array(function.signature.parameterClause.parameters)
        let returnType = function.signature.returnClause?.type.trimmedDescription ?? "Void"
        var closureParameters = ["receiver: \(parameters[0].type.trimmedDescription)", "_: UnsafeRawPointer?"]
        var convention = [parameters[0].type.trimmedDescription, "UnsafeRawPointer?"]
        var call: [String] = []
        for (index, parameter) in parameters.enumerated() {
            let name = index == 0 ? "receiver" : "a\(index)"
            if index > 0 {
                closureParameters.append("\(name): \(parameter.type.trimmedDescription)")
                convention.append(parameter.type.trimmedDescription)
            }
            let label = parameter.firstName.text
            call.append(label == "_" ? name : "\(label): \(name)")
        }
        let thunk = "{ (\(closureParameters.joined(separator: ", "))) -> \(returnType) in "
            + "\(typeName).\(function.name.text)(\(call.joined(separator: ", "))) }"
            + " as @convention(c) (\(convention.joined(separator: ", "))) -> \(returnType)"
        return "registrar.addMethod(\(literal(selector)), types: \(literal(types)), "
            + "implementation: unsafeBitCast(\(thunk), to: UnsafeRawPointer.self), "
            + "isClassMethod: \(isClassMethod))"
    }

    private func literal(_ string: String) -> String {
        "\"" + string.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}

/// Objective-C type encodings for the Swift types methods use.
enum TypeEncoding {
    /// Encoding and argument size (arguments narrower than int take 4).
    static func encode(_ type: TypeSyntax) -> (code: String, size: Int)? {
        var text = type.trimmedDescription.filter { !$0.isWhitespace }
        while text.hasSuffix("?") || text.hasSuffix("!") {
            text.removeLast()
        }
        switch text {
        case "id", "ObjectPointer", "ObjCObject": return ("@", 8)
        case "Class", "ClassPointer": return ("#", 8)
        case "SEL", "Selector": return (":", 8)
        case "ObjCBlock", "Block": return ("@?", 8)
        case "UnsafeRawPointer", "UnsafeMutableRawPointer", "OpaquePointer": return ("^v", 8)
        case "UnsafePointer<CChar>", "UnsafePointer<Int8>": return ("r*", 8)
        case "UnsafeMutablePointer<CChar>", "UnsafeMutablePointer<Int8>": return ("*", 8)
        case "Bool": return ("B", 4)
        case "Int", "Int64": return ("q", 8)
        case "UInt", "UInt64": return ("Q", 8)
        case "Int32": return ("i", 4)
        case "UInt32": return ("I", 4)
        case "Int16": return ("s", 4)
        case "UInt16": return ("S", 4)
        case "Int8", "CChar": return ("c", 4)
        case "UInt8": return ("C", 4)
        case "Double", "CGFloat": return ("d", 8)
        case "Float": return ("f", 4)
        case "Void", "()": return ("v", 0)
        case "NSRange", "_NSRange": return ("{_NSRange=QQ}", 16)
        default: break
        }
        for (prefix, marker) in [("UnsafeMutablePointer<", "^"), ("UnsafePointer<", "r^")] where text.hasPrefix(prefix) && text.hasSuffix(">") {
            let pointee = String(text.dropFirst(prefix.count).dropLast())
            let inner = encode(TypeSyntax(stringLiteral: pointee))?.code ?? "v"
            return (marker + inner, 8)
        }
        return nil
    }

    /// A method's encoding: return type, frame size, then each argument at
    /// its offset, as clang writes them: "S24@0:8Q16".
    static func methodTypes(returning returnType: TypeSyntax?, arguments: [TypeSyntax]) throws -> String {
        let result: String
        if let returnType {
            guard let encoded = encode(returnType) else {
                throw ObjCMacroError(message: "cannot encode return type '\(returnType.trimmedDescription)'; pass types:", node: Syntax(returnType))
            }
            result = encoded.code
        } else {
            result = "v"
        }
        var offset = 16
        var encodedArguments = "@0:8"
        for argument in arguments {
            guard let encoded = encode(argument) else {
                throw ObjCMacroError(message: "cannot encode parameter type '\(argument.trimmedDescription)'; pass types:", node: Syntax(argument))
            }
            encodedArguments += "\(encoded.code)\(offset)"
            offset += encoded.size
        }
        return "\(result)\(offset)\(encodedArguments)"
    }
}

/// @ObjCImplementation: generates `register(_:)` and the ObjCMethodTable
/// conformance.
public struct ObjCImplementationMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let typeName = typeName(of: declaration) else {
            context.diagnose(Diagnostic(node: node, message: ObjCMacroDiagnostic(
                message: "@ObjCImplementation applies to an enum, struct or class")))
            return []
        }
        var registrations: [String] = []
        for member in declaration.memberBlock.members {
            guard let function = member.decl.as(FunctionDeclSyntax.self),
                  let attribute = ObjCMethod.attribute(of: function),
                  let method = try? ObjCMethod(function, attribute: attribute) else {
                continue    // @ObjCMethod reports the error at the method
            }
            registrations.append(method.registration(typeName: typeName))
        }
        let isPublic = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let body = registrations.map { "    " + $0 }.joined(separator: "\n")
        return ["""
            \(raw: isPublic ? "public " : "")static func register(_ registrar: some ObjCMethodRegistrar) {
            \(raw: body)
            }
            """]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): ObjCMethodTable {}")]
    }

    private static func typeName(of declaration: some DeclGroupSyntax) -> String? {
        if let decl = declaration.as(EnumDeclSyntax.self) { return decl.name.text }
        if let decl = declaration.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = declaration.as(ClassDeclSyntax.self) { return decl.name.text }
        return nil
    }
}

/// @ObjCMethod and @ObjCClassMethod: mark a method and check it. They
/// generate nothing themselves.
public struct ObjCMethodMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: ObjCMacroDiagnostic(
                message: "@ObjCMethod applies to a static function")))
            return []
        }
        do {
            _ = try ObjCMethod(function, attribute: node)
        } catch let error as ObjCMacroError {
            context.diagnose(Diagnostic(node: error.node, message: ObjCMacroDiagnostic(message: error.message)))
        }
        return []
    }
}
