// Generates a provider's entry points from its Objective-C declarations.
//
//     PerryProviderGenerator <output.swift> <source.swift>...
//
// Reads every @ObjCClass class, @ObjCCategory extension and @ObjCConstants
// type in the sources and writes perry_provider_startup, which registers
// the @ObjCProtocol protocols, defines the classes (superclasses first) and
// adds the protocols they adopt, adds the categories and exports the
// constants, and perry_provider_symbol, which hands the loader storage for
// the classes and slots for the constants. Optional global functions add provider steps:
//
//     func providerWillStart(_ info: perry_startup_info) -> Bool  // before; false stops
//     func providerDidStart(_ info: perry_startup_info)           // after
//     func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? // other imports
//
// A class that declares `class func didDefineObjCClass(_:)` in its own body
// has it called right after the class is defined; one that declares
// `objCInstanceVariables` gets them before the class is registered.
//
// A declaration inside #if, #elseif or #else is generated under the same
// condition, so code for one platform (macOS's, say) can be compiled out of
// another's provider.

import Foundation
import SwiftParser
import SwiftSyntax

struct ClassDeclaration {
    let name: String
    let objCName: String
    let superclass: String?
    /// The other types it inherits: protocols, some of them Objective-C's.
    let adopted: [String]
    let hasSetUp: Bool
    let hasInstanceVariables: Bool
    /// The #if condition it is declared under, if any.
    let condition: String?
}

struct ProtocolDeclaration {
    let name: String
    let objCName: String
    let parent: String?
    let condition: String?
}

struct CategoryDeclaration {
    let typeName: String
    let name: String
    let condition: String?
}

struct ConstantTableDeclaration {
    let name: String
    let condition: String?
}

/// The condition the #if clauses around a declaration compile it under:
/// each enclosing clause's own condition, with the earlier clauses of its
/// #if not taken. nil outside any #if.
func compilationCondition(of node: some SyntaxProtocol) -> String? {
    var terms: [String] = []
    var current: Syntax? = Syntax(node)
    while let syntax = current {
        if let clause = syntax.as(IfConfigClauseSyntax.self), let list = clause.parent?.as(IfConfigClauseListSyntax.self) {
            var clauseTerms: [String] = []
            for earlier in list {
                if earlier.id == clause.id { break }
                if let condition = earlier.condition { clauseTerms.append("!(\(condition.trimmedDescription))") }
            }
            if let condition = clause.condition { clauseTerms.append("(\(condition.trimmedDescription))") }
            terms.insert(contentsOf: clauseTerms, at: 0)
        }
        current = syntax.parent
    }
    return terms.isEmpty ? nil : terms.joined(separator: " && ")
}

/// Lines generated for a declaration, under its #if condition when it has one.
func conditional(_ condition: String?, _ lines: [String]) -> [String] {
    guard let condition, !lines.isEmpty else { return lines }
    return ["#if \(condition)"] + lines + ["#endif"]
}

/// An array constant's declaration and elements. An array literal can't hold
/// #if, so one with conditional elements is built by a closure instead.
func arrayDeclaration(_ declaration: String, _ type: String, _ elements: [(value: String, condition: String?)]) -> [String] {
    guard elements.contains(where: { $0.condition != nil }) else {
        return ["\(declaration): \(type) = ["] + elements.map { "    \($0.value)," } + ["]"]
    }
    return ["\(declaration): \(type) = {", "    var elements: \(type) = []"]
        + elements.flatMap { conditional($0.condition, ["    elements.append(\($0.value))"]) }
        + ["    return elements", "}()"]
}

final class Collector: SyntaxVisitor {
    var classes: [ClassDeclaration] = []
    var protocols: [ProtocolDeclaration] = []
    var categories: [CategoryDeclaration] = []
    var constantTables: [ConstantTableDeclaration] = []
    var hasWillStart = false
    var hasDidStart = false
    var hasSymbol = false

    init() { super.init(viewMode: .sourceAccurate) }

    private func attribute(_ name: String, in attributes: AttributeListSyntax) -> AttributeSyntax? {
        for element in attributes {
            if case .attribute(let attribute) = element,
               attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == name {
                return attribute
            }
        }
        return nil
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if let objCClass = attribute("ObjCClass", in: node.attributes),
           let objCName = objCClass.arguments?.as(LabeledExprListSyntax.self)?.first?
               .expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            let hasSetUp = node.memberBlock.members.contains {
                $0.decl.as(FunctionDeclSyntax.self)?.name.text == "didDefineObjCClass"
            }
            let hasInstanceVariables = node.memberBlock.members.contains {
                $0.decl.as(VariableDeclSyntax.self)?.bindings.contains {
                    $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "objCInstanceVariables"
                } ?? false
            }
            let inherited = (node.inheritanceClause?.inheritedTypes ?? []).map(\.type.trimmedDescription)
            classes.append(ClassDeclaration(
                name: node.name.text,
                objCName: objCName,
                superclass: inherited.first,
                adopted: Array(inherited.dropFirst()),
                hasSetUp: hasSetUp,
                hasInstanceVariables: hasInstanceVariables,
                condition: compilationCondition(of: node)))
        }
        addConstantTable(node.name.text, node, node.attributes)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        if let objCProtocol = attribute("ObjCProtocol", in: node.attributes),
           let objCName = objCProtocol.arguments?.as(LabeledExprListSyntax.self)?.first?
               .expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            let parent = node.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription)
                .first { $0 != "AnyObject" }
            protocols.append(ProtocolDeclaration(name: node.name.text, objCName: objCName, parent: parent,
                                                 condition: compilationCondition(of: node)))
        }
        return .skipChildren
    }

    private func addConstantTable(_ name: String, _ node: some SyntaxProtocol, _ attributes: AttributeListSyntax) {
        if attribute("ObjCConstants", in: attributes) != nil {
            constantTables.append(ConstantTableDeclaration(name: name, condition: compilationCondition(of: node)))
        }
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        addConstantTable(node.name.text, node, node.attributes)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addConstantTable(node.name.text, node, node.attributes)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let category = attribute("ObjCCategory", in: node.attributes),
           let arguments = category.arguments?.as(LabeledExprListSyntax.self),
           let name = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            let addedAtStartup = arguments.first { $0.label?.text == "addedAtStartup" }?
                .expression.as(BooleanLiteralExprSyntax.self)?.literal.tokenKind != .keyword(.false)
            if addedAtStartup {
                categories.append(CategoryDeclaration(typeName: node.extendedType.trimmedDescription, name: name,
                                                      condition: compilationCondition(of: node)))
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only top-level functions count as provider steps: a source file
        // holds a list of code block items, each holding one declaration.
        if node.parent?.parent?.parent?.is(SourceFileSyntax.self) == true {
            if node.name.text == "providerWillStart" { hasWillStart = true }
            if node.name.text == "providerDidStart" { hasDidStart = true }
            if node.name.text == "providerSymbol" { hasSymbol = true }
        }
        return .skipChildren
    }
}

/// Protocols ordered so each comes after the one it refines.
func refinedFirst(_ protocols: [ProtocolDeclaration]) -> [ProtocolDeclaration] {
    let byName = Dictionary(protocols.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    var ordered: [ProtocolDeclaration] = []
    var placed: Set<String> = []
    func place(_ declaration: ProtocolDeclaration) {
        guard !placed.contains(declaration.name) else { return }
        placed.insert(declaration.name)
        if let parent = declaration.parent, let refined = byName[parent] { place(refined) }
        ordered.append(declaration)
    }
    protocols.forEach(place)
    return ordered
}

/// Classes ordered so each comes after its superclass when both are here.
func superclassesFirst(_ classes: [ClassDeclaration]) -> [ClassDeclaration] {
    let byName = Dictionary(classes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    var ordered: [ClassDeclaration] = []
    var placed: Set<String> = []
    func place(_ declaration: ClassDeclaration) {
        guard !placed.contains(declaration.name) else { return }
        placed.insert(declaration.name)
        if let superclass = declaration.superclass, let parent = byName[superclass] {
            place(parent)
        }
        ordered.append(declaration)
    }
    classes.forEach(place)
    return ordered
}

let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first else {
    FileHandle.standardError.write(Data("usage: PerryProviderGenerator <output.swift> <source.swift>...\n".utf8))
    exit(2)
}

let collector = Collector()
for path in arguments.dropFirst().sorted() {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    collector.walk(Parser.parse(source: source))
}

var lines: [String] = [
    "// Generated by PerryProviderPlugin from this module's @ObjCClass,",
    "// @ObjCCategory and @ObjCConstants declarations. Do not edit.",
    "",
    "import PerryInterface",
    "import PerryObjCInterop",
    "",
]

let constants = collector.constantTables.sorted { $0.name < $1.name }
let classes = superclassesFirst(collector.classes)
if !classes.isEmpty {
    lines += [
        "/// The Objective-C classes this module defines.",
    ] + arrayDeclaration("private let perryObjCClassNames", "[String]",
                         classes.map { ("\"\($0.objCName)\"", $0.condition) }) + [
        "",
    ]
}
if !constants.isEmpty {
    lines += [
        "/// The constant tables of this module's @ObjCConstants types.",
    ] + arrayDeclaration("nonisolated(unsafe) private let perryObjCConstantTables", "[any ObjCConstantTable.Type]",
                         constants.map { ("\($0.name).self", $0.condition) }) + [
        "",
    ]
}
if !classes.isEmpty || !constants.isEmpty {
    lines += [
        "/// Hands the loader storage for each class and a slot for each constant",
        "/// while images bind.",
        "@c",
        "public func perry_provider_symbol(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {",
        "    guard let name else { return nil }",
        "    let symbol = String(cString: name)",
    ]
    if !classes.isEmpty {
        lines += [
            "    ObjCClassExports.shared.register(perryObjCClassNames)",
            "    if let storage = ObjCClassExports.shared.symbol(symbol) { return storage }",
        ]
    }
    if !constants.isEmpty {
        lines += [
            "    ObjCConstantExports.shared.register(perryObjCConstantTables)",
            "    if let slot = ObjCConstantExports.shared.symbol(symbol) { return slot }",
        ]
    }
    lines.append(collector.hasSymbol ? "    return providerSymbol(symbol)" : "    return nil")
    lines += ["}", ""]
}

lines += [
    "/// Defines this module's classes, adds its categories and exports its",
    "/// constants, before any Mach-O code runs.",
    "@c",
    "public func perry_provider_startup(_ info: UnsafePointer<perry_startup_info>?) {",
    "    guard let info else { return }",
]
if collector.hasWillStart {
    lines.append("    guard providerWillStart(info.pointee) else { return }")
}
let protocols = refinedFirst(collector.protocols)
if !protocols.isEmpty {
    lines += ["", "    // Protocols, refined protocols first."]
    lines += protocols.flatMap { conditional($0.condition, ["    Any\($0.name).defineObjCProtocol()"]) }
}
if !classes.isEmpty {
    lines += ["", "    // Classes, superclasses first."]
    for declaration in classes {
        let ivars = declaration.hasInstanceVariables ? "\(declaration.name).addObjCInstanceVariables" : ""
        let line = declaration.hasSetUp
            ? "    \(declaration.name).didDefineObjCClass(\(declaration.name).defineObjCClass(\(ivars)))"
            : "    \(declaration.name).defineObjCClass(\(ivars))"
        lines += conditional(declaration.condition, [line])
    }
}
let protocolNames = Dictionary(protocols.map { ($0.name, $0.objCName) }, uniquingKeysWith: { first, _ in first })
let conformances = classes.flatMap { declaration in
    declaration.adopted.compactMap { protocolNames[$0] }.map { (declaration, $0) }
}
if !conformances.isEmpty {
    lines += ["", "    // Classes' adopted protocols."]
    lines += conformances.flatMap {
        conditional($0.0.condition, ["    ObjCRuntime.addProtocol(named: \"\($0.1)\", to: \($0.0.name).objCClass)"])
    }
}
if !collector.categories.isEmpty {
    lines += ["", "    // Categories."]
    lines += collector.categories.flatMap { conditional($0.condition, ["    \($0.typeName).addObjCCategory\($0.name)()"]) }
}
if !constants.isEmpty {
    lines += [
        "",
        "    // Constants.",
        "    ObjCConstantExports.shared.register(perryObjCConstantTables)",
        "    ObjCConstantExports.shared.export()",
    ]
}
if collector.hasDidStart {
    lines += ["", "    providerDidStart(info.pointee)"]
}
lines += ["}", ""]

let output = lines.joined(separator: "\n")
// Leave an unchanged file alone, so its dependents do not rebuild.
if (try? String(contentsOfFile: outputPath, encoding: .utf8)) != output {
    try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
}
