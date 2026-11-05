import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSAttributedString's Markdown: the options, source positions and
// presentation intents Foundation's importer records, and the initializers
// that turn Markdown's runs (Markdown.swift) into an attributed string.

final class MarkdownOptionsStorage {
    var allowsExtendedAttributes = false
    /// NSAttributedStringMarkdownInterpretedSyntax.
    var interpretedSyntax = 0
    /// NSAttributedStringMarkdownParsingFailurePolicy: 0 returns an error,
    /// 1 returns what could be parsed.
    var failurePolicy = 0
    var languageCode: String?
    var appliesSourcePositionAttributes = false
    /// Private, for Swift's AttributedString: extended attributes are left
    /// as their sources, which Swift decodes into its attribute scopes, and
    /// empty Markdown is an empty string rather than nil.
    var importsForSwift = false

    init() {}

    init(copying other: MarkdownOptionsStorage) {
        allowsExtendedAttributes = other.allowsExtendedAttributes
        interpretedSyntax = other.interpretedSyntax
        failurePolicy = other.failurePolicy
        languageCode = other.languageCode
        appliesSourcePositionAttributes = other.appliesSourcePositionAttributes
        importsForSwift = other.importsForSwift
    }

    var parsing: Markdown.Options {
        Markdown.Options(syntax: Markdown.Syntax(rawValue: interpretedSyntax) ?? .full,
                         extendedAttributes: allowsExtendedAttributes, sourcePositions: appliesSourcePositionAttributes)
    }
}

final class MarkdownPositionStorage {
    let position: Markdown.Position

    init(_ position: Markdown.Position) {
        self.position = position
    }
}

/// A presentation intent: its kind and values, and the intent it is nested
/// in (retained).
final class PresentationIntentStorage {
    let kind: Markdown.Kind
    let identity: Int
    let parent: id?
    let indentationLevel: Int

    init(_ kind: Markdown.Kind, identity: Int, parent: id?) {
        self.kind = kind
        self.identity = identity
        self.parent = parent.flatMap { ObjC.retain($0) }
        indentationLevel = Markdown.indentationLevel(of: kind, inside: MarkdownObjects.intent(parent)?.indentationLevel)
    }

    deinit {
        parent.map { ObjC.release($0) }
    }

    /// The same kind and values, and the same of the intents around it;
    /// identities are compared too unless `identities` is false.
    func matches(_ other: PresentationIntentStorage, identities: Bool) -> Bool {
        if self === other { return true }
        guard kind == other.kind, !identities || identity == other.identity else { return false }
        switch (MarkdownObjects.intent(parent), MarkdownObjects.intent(other.parent)) {
        case (nil, nil): return true
        case let (a?, b?): return a.matches(b, identities: identities)
        default: return false
        }
    }
}

enum MarkdownObjects {
    nonisolated(unsafe) static var optionsClass: Class!
    nonisolated(unsafe) static var positionClass: Class!
    nonisolated(unsafe) static var intentClass: Class!

    /// The private attribute that holds a run's extended attribute sources
    /// for Swift's AttributedString: an array of strings, outermost first.
    static let extendedAttributeSourcesKey = "NSMarkdownExtendedAttributeSources"

    /// Extended attributes' Markdown names that are Foundation's keys.
    static let extendedAttributeKeys = [
        "inflect": "NSInflect",
        "morphology": "NSMorphology",
        "inflectionAlternative": "NSInflectionAlternative",
        "agreeWithConcept": "NSInflectionAgreementConcept",
        "agreeWithArgument": "NSInflectionAgreementArgument",
        "referentConcept": "NSInflectionReferentConcept",
        "formatNumber": "NSLocalizedNumberFormat",
    ]

    static func options(_ object: id?) -> MarkdownOptionsStorage? { Storage.get(object, as: MarkdownOptionsStorage.self) }
    static func intent(_ object: id?) -> PresentationIntentStorage? { Storage.get(object, as: PresentationIntentStorage.self) }
    static func position(_ object: id?) -> Markdown.Position? { Storage.get(object, as: MarkdownPositionStorage.self)?.position }

    /// A new intent (+1).
    static func makeIntent(_ kind: Markdown.Kind, identity: Int, parent: id?, cls: id? = nil) -> id? {
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(intentClass)) else { return nil }
        Storage.set(object, PresentationIntentStorage(kind, identity: identity, parent: parent))
        return object
    }

    /// NSFileReadCorruptFileError, as Foundation reports Markdown it cannot
    /// read: text that is not UTF-8, or extended attributes that are not
    /// JSON5.
    static func corrupt() -> id? {
        Errors.autoreleased(domain: Errors.cocoaDomain, code: 259,
                            description: "The file couldn’t be opened because it isn’t in the correct format.")
    }

    /// Markdown as an attributed string's storage, or nil with `error` set.
    static func storage(_ markdown: String, options: MarkdownOptionsStorage, baseURL: URL?,
                        error: UnsafeMutablePointer<id?>?) -> AttributedStorage? {
        let runs = Markdown.parse(markdown, options.parsing)
        let keys = Keys.shared
        var intents: [ObjectIdentifier: id] = [:]
        defer { intents.values.forEach { ObjC.release($0) } }
        func intent(_ block: Markdown.Block) -> id? {
            if let made = intents[ObjectIdentifier(block)] { return made }
            let parent = block.parent.flatMap(intent)
            let made = makeIntent(block.kind, identity: block.identity, parent: parent)
            intents[ObjectIdentifier(block)] = made
            return made
        }

        var units: [UInt16] = []
        var attributeRuns: [AttributeRun] = []
        defer { attributeRuns.forEach { ObjC.release($0.attributes) } }
        for run in runs {
            let attributes = run.attributes
            var entries: [(key: id, value: id)] = []
            if attributes.inline != 0, let number = Numbers.make(nil, .unsigned(UInt64(attributes.inline))) {
                entries.append((keys.inlinePresentationIntent, number))
            }
            if let block = attributes.block, let object = intent(block) {
                entries.append((keys.presentationIntent, object))
            }
            if let link = attributes.link, let url = URL(string: link, relativeTo: baseURL), let object = URLs.autoreleased(url) {
                entries.append((keys.link, object))
            }
            if let image = attributes.imageURL, let url = URL(string: image, relativeTo: baseURL),
               let object = URLs.autoreleased(url) {
                entries.append((keys.imageURL, object))
            }
            if let description = attributes.alternateDescription {
                entries.append((keys.alternateDescription, Strings.autoreleased(description)))
            }
            if let delimiter = attributes.listItemDelimiter {
                entries.append((keys.listItemDelimiter, Strings.autoreleased(delimiter)))
            }
            if let position = attributes.position, let object = Storage.allocate(UnsafeMutableRawPointer(positionClass)) {
                Storage.set(object, MarkdownPositionStorage(position))
                entries.append((keys.sourcePosition, ObjC.autorelease(object)!))
            }
            if !attributes.extended.isEmpty {
                if options.importsForSwift {
                    entries.append((Strings.autoreleased(extendedAttributeSourcesKey),
                                    Arrays.autoreleased(attributes.extended.map { Strings.autoreleased($0) })))
                } else {
                    for source in attributes.extended {
                        guard let decoded = extendedAttributes(source) else {
                            if options.failurePolicy == 0 {
                                error?.pointee = corrupt()
                                return nil
                            }
                            continue
                        }
                        // Inner attributes win over outer ones.
                        entries.removeAll { entry in decoded.contains { AttributedStorage.equal($0.key, entry.key) } }
                        entries += decoded
                    }
                }
            }
            units += run.text.utf16
            attributeRuns.append(AttributeRun(length: run.text.utf16.count, attributes: Dictionaries.make(entries)))
        }
        let storage = AttributedStorage(units: units, attributes: nil)
        storage.runs.forEach { ObjC.release($0.attributes) }
        storage.runs = attributeRuns
        attributeRuns = []
        storage.merge()
        return storage
    }

    /// ^[…](source)'s attributes: the source is a JSON5 object's members
    /// without the braces. Foundation's own names become its keys; other
    /// names are kept as they are.
    static func extendedAttributes(_ source: String) -> [(key: id, value: id)]? {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        guard case .dictionary(let members)? = try? decoder.decode(PropertyValue.self, from: Data("{\(source)}".utf8)) else {
            return nil
        }
        return members.sorted { $0.key < $1.key }.compactMap { name, value in
            value.object().map { (key: Strings.autoreleased(extendedAttributeKeys[name] ?? name), value: $0) }
        }
    }

    /// The attribute names, made once.
    final class Keys: @unchecked Sendable {
        static let shared = Keys()
        let inlinePresentationIntent = Strings.make("NSInlinePresentationIntent")
        let presentationIntent = Strings.make("NSPresentationIntent")
        let link = Strings.make("NSLink")
        let imageURL = Strings.make("NSImageURL")
        let alternateDescription = Strings.make("NSAlternateDescription")
        let listItemDelimiter = Strings.make("NSListItemDelimiter")
        let sourcePosition = Strings.make("NSMarkdownSourcePosition")
    }
}

/// NSAttributedStringMarkdownParsingOptions.
@ObjCClass("NSAttributedStringMarkdownParsingOptions")
public final class NSAttributedStringMarkdownParsingOptions: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MarkdownObjects.optionsClass = cls.storage
    }

    var storage: MarkdownOptionsStorage {
        if let storage = MarkdownObjects.options(objcObject) { return storage }
        let storage = MarkdownOptionsStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MarkdownObjects.optionsClass)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, MarkdownOptionsStorage())
        return self
    }

    @ObjCMethod("allowsExtendedAttributes") func allowsExtendedAttributes() -> Bool { storage.allowsExtendedAttributes }
    @ObjCMethod("setAllowsExtendedAttributes:") func setAllowsExtendedAttributes(_ value: Bool) { storage.allowsExtendedAttributes = value }
    @ObjCMethod("interpretedSyntax") func interpretedSyntax() -> Int { storage.interpretedSyntax }
    @ObjCMethod("setInterpretedSyntax:") func setInterpretedSyntax(_ value: Int) { storage.interpretedSyntax = value }
    @ObjCMethod("failurePolicy") func failurePolicy() -> Int { storage.failurePolicy }
    @ObjCMethod("setFailurePolicy:") func setFailurePolicy(_ value: Int) { storage.failurePolicy = value }
    @ObjCMethod("languageCode") func languageCode() -> String? { storage.languageCode }
    @ObjCMethod("setLanguageCode:") func setLanguageCode(_ value: String?) { storage.languageCode = value }
    @ObjCMethod("appliesSourcePositionAttributes") func appliesSourcePositionAttributes() -> Bool {
        storage.appliesSourcePositionAttributes
    }
    @ObjCMethod("setAppliesSourcePositionAttributes:") func setAppliesSourcePositionAttributes(_ value: Bool) {
        storage.appliesSourcePositionAttributes = value
    }

    /// Private, for Swift's AttributedString(markdown:).
    @ObjCMethod("_perryImportForSwift") func importForSwift() {
        storage.importsForSwift = true
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(MarkdownObjects.optionsClass)) else { return nil }
        Storage.set(object, MarkdownOptionsStorage(copying: storage))
        return object
    }
}

/// NSAttributedStringMarkdownSourcePosition.
@ObjCClass("NSAttributedStringMarkdownSourcePosition")
public final class NSAttributedStringMarkdownSourcePosition: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MarkdownObjects.positionClass = cls.storage
    }

    var position: Markdown.Position {
        MarkdownObjects.position(objcObject) ?? Markdown.Position(startLine: 0, startColumn: 0, endLine: 0, endColumn: 0)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MarkdownObjects.positionClass)
    }

    @ObjCMethod("initWithStartLine:startColumn:endLine:endColumn:")
    func initialize(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) -> Self {
        Storage.set(objcObject, MarkdownPositionStorage(Markdown.Position(startLine: startLine, startColumn: startColumn,
                                                                          endLine: endLine, endColumn: endColumn)))
        return self
    }

    @ObjCMethod("startLine") func startLine() -> Int { position.startLine }
    @ObjCMethod("startColumn") func startColumn() -> Int { position.startColumn }
    @ObjCMethod("endLine") func endLine() -> Int { position.endLine }
    @ObjCMethod("endColumn") func endColumn() -> Int { position.endColumn }

    /// The source's characters in `string`, the Markdown the position is
    /// in, as UTF-16 offsets: from the first byte of the start column to
    /// the end of the character at the end column.
    @ObjCMethod("rangeInString:")
    func range(in string: String) -> NSRange {
        let position = position
        let bytes = Array(string.utf8)
        func offset(line: Int, column: Int) -> Int? {
            guard line >= 1, column >= 1 else { return nil }
            var start = 0, current = 1
            while current < line {
                guard let newline = bytes[start...].firstIndex(of: UInt8(ascii: "\n")) else { return nil }
                start = newline + 1
                current += 1
            }
            let offset = start + column - 1
            return offset <= bytes.count ? offset : nil
        }
        guard let start = offset(line: position.startLine, column: position.startColumn),
              var end = offset(line: position.endLine, column: position.endColumn), start <= end else {
            return NSRange(location: notFound, length: 0)
        }
        // Past the end column's character and its continuation bytes.
        if end < bytes.count { end += 1 }
        while end < bytes.count, bytes[end] & 0xC0 == 0x80 { end += 1 }
        let utf8 = string.utf8
        guard let lower = utf8.index(utf8.startIndex, offsetBy: start, limitedBy: utf8.endIndex),
              let upper = utf8.index(utf8.startIndex, offsetBy: end, limitedBy: utf8.endIndex) else {
            return NSRange(location: notFound, length: 0)
        }
        return URLComponentsObjects.range(lower..<upper, in: string)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, let position = MarkdownObjects.position(other.id) else { return false }
        return position == self.position
    }

    @ObjCMethod("hash")
    func hash() -> UInt {
        let p = position
        return UInt(bitPattern: p.startLine &* 31 &+ p.startColumn &* 17 &+ p.endLine &* 7 &+ p.endColumn)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSAttributedStringMarkdownSourcePosition { self }

    @ObjCMethod("description")
    func description() -> String {
        let p = position
        return "<NSAttributedStringMarkdownSourcePosition \(objcObject)> \(p.startLine):\(p.startColumn)-\(p.endLine):\(p.endColumn)"
    }
}

/// NSPresentationIntent: what a block of Markdown is, inside the blocks
/// around it.
@ObjCClass("NSPresentationIntent")
public final class NSPresentationIntent: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MarkdownObjects.intentClass = cls.storage
    }

    var storage: PresentationIntentStorage {
        MarkdownObjects.intent(objcObject) ?? PresentationIntentStorage(.paragraph, identity: 0, parent: nil)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MarkdownObjects.intentClass)
    }

    private static func make(_ cls: ObjCClass, _ kind: Markdown.Kind, _ identity: Int, _ parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        ObjC.autorelease(MarkdownObjects.makeIntent(kind, identity: identity, parent: parent?.id, cls: cls.pointer))
    }

    @ObjCClassMethod("paragraphIntentWithIdentity:nestedInsideIntent:")
    static func paragraph(_ cls: ObjCClass, identity: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .paragraph, identity, parent)
    }

    @ObjCClassMethod("headerIntentWithIdentity:level:nestedInsideIntent:")
    static func header(_ cls: ObjCClass, identity: Int, level: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .header(level: level), identity, parent)
    }

    @ObjCClassMethod("codeBlockIntentWithIdentity:languageHint:nestedInsideIntent:")
    static func codeBlock(_ cls: ObjCClass, identity: Int, languageHint: String?, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .codeBlock(languageHint: languageHint), identity, parent)
    }

    @ObjCClassMethod("thematicBreakIntentWithIdentity:nestedInsideIntent:")
    static func thematicBreak(_ cls: ObjCClass, identity: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .thematicBreak, identity, parent)
    }

    @ObjCClassMethod("orderedListIntentWithIdentity:nestedInsideIntent:")
    static func orderedList(_ cls: ObjCClass, identity: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .orderedList, identity, parent)
    }

    @ObjCClassMethod("unorderedListIntentWithIdentity:nestedInsideIntent:")
    static func unorderedList(_ cls: ObjCClass, identity: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .unorderedList, identity, parent)
    }

    @ObjCClassMethod("listItemIntentWithIdentity:ordinal:nestedInsideIntent:")
    static func listItem(_ cls: ObjCClass, identity: Int, ordinal: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .listItem(ordinal: ordinal), identity, parent)
    }

    @ObjCClassMethod("blockQuoteIntentWithIdentity:nestedInsideIntent:")
    static func blockQuote(_ cls: ObjCClass, identity: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .blockQuote, identity, parent)
    }

    /// NSPresentationIntentTableColumnAlignment for each column.
    @ObjCClassMethod("tableIntentWithIdentity:columnCount:alignments:nestedInsideIntent:")
    static func table(_ cls: ObjCClass, identity: Int, columnCount: Int, alignments: ObjCObject?,
                      parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        let given = Arrays.elements(alignments?.id).map { Int(truncatingIfNeeded: Numbers.storage($0).int64) }
        guard given.count == columnCount else {
            foundationFatal("+[NSPresentationIntent tableIntentWithIdentity:columnCount:alignments:nestedInsideIntent:]: "
                            + "column count does not match count of alignments")
        }
        return make(cls, .table(alignments: given), identity, parent)
    }

    @ObjCClassMethod("tableHeaderRowIntentWithIdentity:nestedInsideIntent:")
    static func tableHeaderRow(_ cls: ObjCClass, identity: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .tableHeaderRow, identity, parent)
    }

    @ObjCClassMethod("tableRowIntentWithIdentity:row:nestedInsideIntent:")
    static func tableRow(_ cls: ObjCClass, identity: Int, row: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .tableRow(row: row), identity, parent)
    }

    @ObjCClassMethod("tableCellIntentWithIdentity:column:nestedInsideIntent:")
    static func tableCell(_ cls: ObjCClass, identity: Int, column: Int, parent: ObjCObject?) -> UnsafeMutableRawPointer? {
        make(cls, .tableCell(column: column), identity, parent)
    }

    @ObjCMethod("intentKind") func intentKind() -> Int { storage.kind.rawValue }
    @ObjCMethod("parentIntent") func parentIntent() -> UnsafeMutableRawPointer? { storage.parent }
    @ObjCMethod("identity") func identity() -> Int { storage.identity }
    @ObjCMethod("indentationLevel") func indentationLevel() -> Int { storage.indentationLevel }

    @ObjCMethod("ordinal")
    func ordinal() -> Int {
        if case .listItem(let ordinal) = storage.kind { return ordinal }
        return 0
    }

    @ObjCMethod("columnAlignments")
    func columnAlignments() -> UnsafeMutableRawPointer? {
        guard case .table(let alignments) = storage.kind else { return nil }
        return Arrays.autoreleased(alignments.compactMap { Numbers.make(nil, .signed(Int64($0))) })
    }

    @ObjCMethod("columnCount")
    func columnCount() -> Int {
        if case .table(let alignments) = storage.kind { return alignments.count }
        return 0
    }

    @ObjCMethod("headerLevel")
    func headerLevel() -> Int {
        if case .header(let level) = storage.kind { return level }
        return 0
    }

    @ObjCMethod("languageHint")
    func languageHint() -> String? {
        if case .codeBlock(let hint) = storage.kind { return hint }
        return nil
    }

    @ObjCMethod("column")
    func column() -> Int {
        if case .tableCell(let column) = storage.kind { return column }
        return 0
    }

    @ObjCMethod("row")
    func row() -> Int {
        if case .tableRow(let row) = storage.kind { return row }
        return 0
    }

    /// The same kinds and values as `other`'s, whatever their identities.
    @ObjCMethod("isEquivalentToPresentationIntent:")
    func isEquivalent(to other: ObjCObject?) -> Bool {
        guard let other = MarkdownObjects.intent(other?.id) else { return false }
        return storage.matches(other, identities: false)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other = MarkdownObjects.intent(other?.id) else { return false }
        return storage.matches(other, identities: true)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: storage.identity &+ storage.kind.rawValue) }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSPresentationIntent { self }

    /// Each intent on a line, innermost first, as Foundation describes
    /// them: "<NSPresentationIntent 0x…>: ListItem (id 2) ordinal 3, indent 1".
    @ObjCMethod("description")
    func description() -> String {
        var lines: [String] = []
        var object: id? = objcObject
        while let current = object, let intent = MarkdownObjects.intent(current) {
            lines.append("<NSPresentationIntent \(current)>: " + Self.describe(intent))
            object = intent.parent
        }
        return lines.joined(separator: "\n ")
    }

    static func describe(_ intent: PresentationIntentStorage) -> String {
        let identity = "(id \(intent.identity))", indent = "indent \(intent.indentationLevel)"
        switch intent.kind {
        case .paragraph: return "Paragraph \(identity)"
        case .header(let level): return "Header \(identity) (\(level)) \(indent)"
        case .orderedList: return "OrderedList \(identity) \(indent)"
        case .unorderedList: return "UnorderedList \(identity) \(indent)"
        case .listItem(let ordinal): return "ListItem \(identity) ordinal \(ordinal), \(indent)"
        case .codeBlock(let hint): return "CodeBlock \(identity) (\(hint ?? "no hint")) \(indent)"
        case .blockQuote: return "BlockQuote \(identity)"
        case .thematicBreak: return "ThematicBreak \(identity)"
        case .table(let alignments):
            let names = alignments.map { ["left", "center", "right"][min(max($0, 0), 2)] }
            return "Table \(identity) \(alignments.count) columns, alignment " + names.joined(separator: ", ")
        case .tableHeaderRow: return "TableHeaderRow \(identity)"
        case .tableRow(let row): return "TableRow \(identity) # \(row)"
        case .tableCell(let column): return "TableCell \(identity) # \(column)"
        }
    }
}

/// Attributed strings from Markdown.
@ObjCCategory("NSAttributedStringCreateFromMarkdown")
extension NSAttributedString {
    private func setMarkdown(_ markdown: String, options: ObjCObject?, baseURL: NSURL?,
                             error: UnsafeMutablePointer<id?>?) -> Self? {
        let options = MarkdownObjects.options(options?.id) ?? MarkdownOptionsStorage()
        // Foundation makes no string of empty Markdown, and reports no error.
        if markdown.isEmpty, !options.importsForSwift { return nil }
        guard let storage = MarkdownObjects.storage(markdown, options: options, baseURL: baseURL?.url, error: error) else {
            return nil
        }
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("initWithMarkdownString:options:baseURL:error:")
    func initialize(markdownString: String, options: ObjCObject?, baseURL: NSURL?, error: UnsafeMutablePointer<id?>?) -> Self? {
        setMarkdown(markdownString, options: options, baseURL: baseURL, error: error)
    }

    /// UTF-8 Markdown.
    @ObjCMethod("initWithMarkdown:options:baseURL:error:")
    func initialize(markdown: NSData, options: ObjCObject?, baseURL: NSURL?, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let text = String(validating: markdown.data, as: UTF8.self) else {
            error?.pointee = MarkdownObjects.corrupt()
            return nil
        }
        return setMarkdown(text, options: options, baseURL: baseURL, error: error)
    }

    @ObjCMethod("initWithContentsOfMarkdownFileAtURL:options:baseURL:error:")
    func initialize(contentsOfMarkdownFile url: NSURL, options: ObjCObject?, baseURL: NSURL?,
                    error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let data = NSData.contents(of: url) else {
            error?.pointee = NSData.readError(url.url.isFileURL && access(url.url.path, F_OK) == 0)
            return nil
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            error?.pointee = MarkdownObjects.corrupt()
            return nil
        }
        return setMarkdown(text, options: options, baseURL: baseURL, error: error)
    }
}
