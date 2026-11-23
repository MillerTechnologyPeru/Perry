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
//
// On ppc __darwin_<function> instead takes Darwin's arguments where Darwin's
// ABI leaves them, under Linux's rules (DarwinCMacro.ppcEntry): a double or
// float as itself, in a floating-point register on both, followed by words
// standing for the general registers Darwin skips for it; a 64-bit integer
// and a structure as their words. Results pass the same on both. When the
// arguments would go past r10 or f8, where the two ABIs' stack areas differ,
// it is exported as perry_ppc_moved_<name> with the ObjCType signature, and
// perry_ppc_types_<name> gives its type encoding, so the loader moves its
// arguments for it (ppc_abi.c).

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
        let bare = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
        let objCTypeEntry = """
            func __darwin_\(name)(\(darwinParameters.joined(separator: ", ")))\(darwinResult) {
                \(darwinBody)
            }
            """
        let ppc: String
        if let entry = ppcEntry(name: name, parameters: parameters, result: result) {
            ppc = "@c(\(symbol)) \(access)" + entry
        } else {
            // Past the registers: the ObjCType signature, which the loader
            // moves Darwin's arguments to by its encoding.
            let encoding = ([result.map { converted.contains($0) ? "\($0).objCTypeEncoding" : "\"i\"" } ?? "\"v\""]
                + parameters.map { converted.contains($0.type.trimmedDescription) ? "\($0.type.trimmedDescription).objCTypeEncoding" : "\"i\"" })
                .joined(separator: " + ")
            ppc = """
                @c(perry_ppc_moved_\(bare)) \(access)\(objCTypeEntry)
                @c(perry_ppc_types_\(bare)) \(access)func __darwin_types_\(name)() -> UnsafePointer<CChar>? {
                    PPCWords.cString(\(encoding))
                }
                """
        }
        return [
            """
            #if arch(powerpc)
            \(raw: ppc)
            #else
            @c(\(raw: symbol)) \(raw: access)\(raw: objCTypeEntry)
            #endif
            """,
            """
            @c(\(raw: native)) \(raw: access)func __native_\(raw: name)(\(raw: nativeParameters.joined(separator: ", ")))\(raw: result.map { " -> \($0)" } ?? "") {
                \(raw: name)(\(raw: nativeArguments.joined(separator: ", ")))
            }
            """,
        ]
    }

    // MARK: - ppc

    /// How 32-bit ppc Darwin passes a converted type: a double or float in a
    /// floating-point register, which also takes one or two words of the
    /// general registers; a 64-bit integer or a structure in its words. On
    /// ppc a CGFloat is a float.
    enum PPCKind {
        case double, float, words(Int), pair
    }

    static let ppcKinds: [String: PPCKind] = [
        "CGFloat": .float, "Float": .float, "Double": .double, "TimeInterval": .double,
        "Int64": .pair, "UInt64": .pair,
        "CGPoint": .words(2), "CGSize": .words(2), "CGRect": .words(4), "CGAffineTransform": .words(6),
        "UIEdgeInsets": .words(4), "CATransform3D": .words(16), "CAFrameRateRange": .words(3),
        "CLLocationCoordinate2D": .words(4), "MKCoordinateSpan": .words(4), "MKCoordinateRegion": .words(8),
        "MKMapPoint": .words(4), "MKMapSize": .words(4), "MKMapRect": .words(8),
    ]

    /// __darwin_<name> for ppc, with parameters where Darwin leaves its
    /// arguments, or nil when they go past r10 or f8.
    static func ppcEntry(name: String, parameters: [FunctionParameterSyntax], result: String?) -> String? {
        var list: [String] = []
        var arguments: [String] = []
        // A structure result's pointer comes first, in r3, on both.
        var words = result.flatMap { ppcKinds[$0] }.map { kind -> Int in if case .words = kind { return 1 } else { return 0 } } ?? 0
        var floats = 0
        for (index, parameter) in parameters.enumerated() {
            let type = parameter.type.trimmedDescription
            let label = parameter.firstName.text
            func labeled(_ value: String) -> String { label == "_" ? value : "\(label): \(value)" }
            switch ppcKinds[type] {
            case .double?:
                list += ["_ a\(index): \(type)", "_ a\(index)_skip0: UInt32", "_ a\(index)_skip1: UInt32"]
                arguments.append(labeled("a\(index)"))
                words += 2
                floats += 1
            case .float?:
                list += ["_ a\(index): \(type)", "_ a\(index)_skip0: UInt32"]
                arguments.append(labeled("a\(index)"))
                words += 1
                floats += 1
            case .pair?:
                list += ["_ a\(index)_high: UInt32", "_ a\(index)_low: UInt32"]
                arguments.append(labeled("\(type)(truncatingIfNeeded: UInt64(a\(index)_high) << 32 | UInt64(a\(index)_low))"))
                words += 2
            case .words(let count)?:
                let names = (0..<count).map { "a\(index)_w\($0)" }
                list += names.map { "_ \($0): UInt32" }
                arguments.append(labeled("PPCWords.load(\(type).self, [\(names.joined(separator: ", "))])"))
                words += count
            case nil:
                list.append("_ a\(index): \(type)")
                arguments.append(labeled("a\(index)"))
                words += 1
            }
        }
        guard words <= 8, floats <= 8 else { return nil }
        let returns = result.map { " -> \($0)" } ?? ""
        return "func __darwin_\(name)(\(list.joined(separator: ", ")))\(returns) {\n    \(name)(\(arguments.joined(separator: ", ")))\n}"
    }
}
