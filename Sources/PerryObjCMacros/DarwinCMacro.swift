import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// @DarwinC("_CGRectMake") exports a Swift function as a C function under its
// Darwin name, as @c(_CGRectMake) would, with Darwin's calling convention for
// the values whose conventions differ: floating point, 64-bit integers and
// structures of them. Its peer __darwin_<function> takes and returns those
// as their ObjCType and ObjCResultType (PerryObjCInterop), which on arm64 are
// the types themselves and on armv7 the words 32-bit Darwin passes; other
// types pass through unchanged. A second peer, __native_<function>, exports
// the function unchanged as perry_native_<name>, for other providers, which
// call it as Swift would.

public struct DarwinCMacro: PeerMacro {
    /// The types whose Darwin convention can differ from Linux's, which
    /// conform to ObjCValue.
    static let converted: Set<String> = [
        "CGFloat", "Double", "Float", "Int64", "UInt64", "TimeInterval",
        "CGPoint", "CGSize", "CGRect", "CGAffineTransform", "UIEdgeInsets", "CATransform3D", "CAFrameRateRange",
        "CLLocationCoordinate2D", "MKCoordinateSpan", "MKCoordinateRegion", "MKMapPoint", "MKMapSize", "MKMapRect",
    ]

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            ObjCMacroError("@DarwinC applies to a function", at: node).diagnose(in: context)
            return []
        }
        guard let symbol = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression
            .as(StringLiteralExprSyntax.self)?.representedLiteralValue,
              symbol.first == "_" || symbol.first?.isLetter == true,
              symbol.allSatisfy({ $0 == "_" || $0.isLetter || $0.isNumber }) else {
            ObjCMacroError("@DarwinC takes the C name as a string literal, such as \"_CGRectMake\"", at: node)
                .diagnose(in: context)
            return []
        }
        let name = function.name.text
        let access = function.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        let parameters = Array(function.signature.parameterClause.parameters)
        let result = function.signature.returnClause?.type.trimmedDescription

        var darwinParameters: [String] = []
        var nativeParameters: [String] = []
        var darwinArguments: [String] = []
        var nativeArguments: [String] = []
        for (index, parameter) in parameters.enumerated() {
            let type = parameter.type.trimmedDescription
            let label = parameter.firstName.text
            func labeled(_ value: String) -> String { label == "_" ? value : "\(label): \(value)" }
            nativeParameters.append("_ a\(index): \(type)")
            nativeArguments.append(labeled("a\(index)"))
            if converted.contains(type) {
                darwinParameters.append("_ a\(index): \(type).ObjCType")
                darwinArguments.append(labeled("\(type)(objCArgument: a\(index))"))
            } else {
                darwinParameters.append("_ a\(index): \(type)")
                darwinArguments.append(labeled("a\(index)"))
            }
        }
        let call = "\(name)(\(darwinArguments.joined(separator: ", ")))"
        let darwinResult: String
        let darwinBody: String
        if let result, converted.contains(result) {
            darwinResult = " -> \(result).ObjCResultType"
            darwinBody = "\(result).objCResult(\(call).objCReturnValue())"
        } else {
            darwinResult = result.map { " -> \($0)" } ?? ""
            darwinBody = call
        }
        let native = "perry_native_" + (symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol)
        return [
            """
            @c(\(raw: symbol)) \(raw: access)func __darwin_\(raw: name)(\(raw: darwinParameters.joined(separator: ", ")))\(raw: darwinResult) {
                \(raw: darwinBody)
            }
            """,
            """
            @c(\(raw: native)) \(raw: access)func __native_\(raw: name)(\(raw: nativeParameters.joined(separator: ", ")))\(raw: result.map { " -> \($0)" } ?? "") {
                \(raw: name)(\(raw: nativeArguments.joined(separator: ", ")))
            }
            """,
        ]
    }
}
