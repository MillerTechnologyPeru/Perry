import CPerryGeometry
import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSAttributedString and NSMutableAttributedString: UTF-16 text and runs
// of attribute dictionaries. Adjacent runs with equal attributes merge, so
// an effective range is a whole run, as Darwin reports it.

/// One run: a length and its attributes, an immutable dictionary.
struct AttributeRun {
    var length: Int
    var attributes: id
}

final class AttributedStorage {
    var units: [UInt16] = []
    var runs: [AttributeRun] = []

    init(units: [UInt16], attributes: id?) {
        self.units = units
        let dictionary = attributes.map { ObjC.send($0, Selectors.copyWithZone, nil)! } ?? Dictionaries.make([])
        runs = units.isEmpty ? [] : [AttributeRun(length: units.count, attributes: dictionary)]
        if units.isEmpty { ObjC.release(dictionary) }
    }

    init(copying other: AttributedStorage) {
        units = other.units
        runs = other.runs.map { AttributeRun(length: $0.length, attributes: ObjC.retain($0.attributes)!) }
    }

    deinit {
        runs.forEach { ObjC.release($0.attributes) }
    }

    var string: String { String(decoding: units, as: UTF16.self) }

    static func equal(_ a: id, _ b: id) -> Bool { a == b || ObjC.sendBool(a, Selectors.isEqual, b) }

    /// The run holding `index`, and where it starts.
    func run(at index: Int) -> (index: Int, start: Int)? {
        var start = 0
        for (position, run) in runs.enumerated() {
            if index < start + run.length { return (position, start) }
            start += run.length
        }
        return nil
    }

    func merge() {
        var merged: [AttributeRun] = []
        for run in runs where run.length > 0 {
            if let last = merged.last, AttributedStorage.equal(last.attributes, run.attributes) {
                merged[merged.count - 1].length += run.length
                ObjC.release(run.attributes)
            } else {
                merged.append(run)
            }
        }
        for run in runs where run.length == 0 { ObjC.release(run.attributes) }
        runs = merged
    }

    /// Splits runs so `index` falls on a boundary; the run index there.
    @discardableResult
    func split(at index: Int) -> Int {
        var start = 0
        for position in runs.indices {
            let run = runs[position]
            if index == start { return position }
            if index < start + run.length {
                runs[position].length = index - start
                runs.insert(AttributeRun(length: start + run.length - index, attributes: ObjC.retain(run.attributes)!),
                            at: position + 1)
                return position + 1
            }
            start += run.length
        }
        return runs.count
    }

    /// Changes each run's attributes in `range`.
    func update(_ range: NSRange, _ change: ([(key: id, value: id)]) -> [(key: id, value: id)]) {
        let start = Int(range.location), end = start + Int(range.length)
        guard start < end else { return }
        let first = split(at: start), last = split(at: end)
        for position in first..<last {
            let entries = change(Dictionaries.entries(runs[position].attributes))
            let replaced = Dictionaries.make(entries)
            ObjC.release(runs[position].attributes)
            runs[position].attributes = replaced
        }
        merge()
    }

    /// Replaces characters, with `attributes` for the new ones, or those
    /// of the first replaced character (or the one before) when nil.
    func replace(_ range: NSRange, with text: [UInt16], attributes: [AttributeRun]?) {
        let start = Int(range.location), end = start + Int(range.length)
        let inherited = run(at: start < units.count ? start : max(0, start - 1)).map { runs[$0.index].attributes }
        units.replaceSubrange(start..<end, with: text)
        let first = split(at: start), last = split(at: end)
        let removed = runs[first..<last]
        var inserted: [AttributeRun]
        if let attributes {
            inserted = attributes.map { AttributeRun(length: $0.length, attributes: ObjC.retain($0.attributes)!) }
        } else if !text.isEmpty {
            inserted = [AttributeRun(length: text.count, attributes: ObjC.retain(inherited ?? Dictionaries.autoreleased([]))!)]
        } else {
            inserted = []
        }
        runs.replaceSubrange(first..<last, with: inserted)
        removed.forEach { ObjC.release($0.attributes) }
        merge()
    }

    /// The characters become `text`: what changed between the two is
    /// replaced, so the characters around it keep their attributes, as an
    /// edit through -mutableString does.
    func replaceChanged(with text: [UInt16]) {
        var prefix = 0
        while prefix < units.count, prefix < text.count, units[prefix] == text[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < units.count - prefix, suffix < text.count - prefix,
              units[units.count - 1 - suffix] == text[text.count - 1 - suffix] { suffix += 1 }
        let range = NSRange(location: UInt(prefix), length: UInt(units.count - prefix - suffix))
        guard range.length > 0 || text.count - prefix - suffix > 0 else { return }
        replace(range, with: Array(text[prefix..<text.count - suffix]), attributes: nil)
    }

    /// The runs of `range`, cut to it.
    func runs(in range: NSRange) -> [AttributeRun] {
        var result: [AttributeRun] = []
        var start = 0
        let lower = Int(range.location), upper = lower + Int(range.length)
        for run in runs {
            let end = start + run.length
            let from = max(start, lower), to = min(end, upper)
            if from < to { result.append(AttributeRun(length: to - from, attributes: run.attributes)) }
            start = end
        }
        return result
    }
}

enum AttributedStrings {
    nonisolated(unsafe) static var stringClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

    static func storage(_ object: id?) -> AttributedStorage? { Storage.get(object, as: AttributedStorage.self) }

    static func make(_ storage: AttributedStorage, mutable: Bool) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(mutable ? mutableClass : stringClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }

    static func check(_ range: NSRange, _ length: Int, _ method: String) {
        guard Int(range.location) + Int(range.length) <= length else {
            Exceptions.raise(name: "NSRangeException", reason: "-[NSAttributedString \(method)]: Range or index out of bounds (range {\(range.location), \(range.length)}, length \(length))")
        }
    }
}

/// NSAttributedString.
@ObjCClass("NSAttributedString")
public class NSAttributedString: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        AttributedStrings.stringClass = cls.storage
        cls.addMethod("localizedAttributedStringWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_localizedAttributedStringWithFormat), isClassMethod: true)
        cls.addMethod("localizedAttributedStringWithFormat:options:", types: "@32@0:8@16Q24",
                      implementation: variadicEntry(perry_imp_localizedAttributedStringWithFormatOptions), isClassMethod: true)
        cls.addMethod("localizedAttributedStringWithFormat:context:", types: "@32@0:8@16@24",
                      implementation: variadicEntry(perry_imp_localizedAttributedStringWithFormatContext), isClassMethod: true)
        // Five fixed arguments: armv7's entry points take four.
        #if !arch(arm)
        cls.addMethod("localizedAttributedStringWithFormat:options:context:", types: "@40@0:8@16Q24@32",
                      implementation: variadicEntry(perry_imp_localizedAttributedStringWithFormatOptionsContext), isClassMethod: true)
        cls.addMethod("initWithFormat:options:locale:", types: "@40@0:8@16Q24@32",
                      implementation: variadicEntry(perry_imp_attributedInitWithFormat), isClassMethod: false)
        #endif
        // Six: x86_64's take five.
        #if !arch(arm) && !arch(x86_64)
        cls.addMethod("initWithFormat:options:locale:context:", types: "@48@0:8@16Q24@32@40",
                      implementation: variadicEntry(perry_imp_attributedInitWithFormatContext), isClassMethod: false)
        #endif
    }

    var storage: AttributedStorage {
        if let storage = AttributedStrings.storage(objcObject) { return storage }
        let storage = AttributedStorage(units: [], attributes: nil)
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: AttributedStrings.stringClass)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, AttributedStorage(units: [], attributes: nil))
        return self
    }

    /// No string is an empty one: Xcode's value transformers make
    /// attributed strings of a binding's value even when it is nil.
    @ObjCMethod("initWithString:")
    func initialize(string: String?) -> Self {
        Storage.set(objcObject, AttributedStorage(units: Array((string ?? "").utf16), attributes: nil))
        return self
    }

    /// The format with the arguments formatted into it, as
    /// AttributedFormatting formats; the locale is not applied.
    @ObjCMethod("initWithFormat:options:locale:arguments:", types: "@48@0:8@16Q24@32*40")
    func initialize(format: ObjCObject?, options: UInt, locale: ObjCObject?, arguments: UnsafeRawPointer?) -> Self {
        Storage.set(objcObject, AttributedFormatting.format(format?.objcObject, options: options, arguments: arguments))
        return self
    }

    /// As without the context: inflection is not applied here.
    @ObjCMethod("initWithFormat:options:locale:context:arguments:", types: "@56@0:8@16Q24@32@40*48")
    func initialize(format: ObjCObject?, options: UInt, locale: ObjCObject?, context: ObjCObject?, arguments: UnsafeRawPointer?) -> Self {
        initialize(format: format, options: options, locale: locale, arguments: arguments)
    }

    /// The string with its inflection rules applied: they need Apple's
    /// morphology data, so it is a copy, as Darwin gives for text with
    /// none.
    @ObjCMethod("attributedStringByInflectingString")
    func inflectingString() -> UnsafeMutableRawPointer? {
        AttributedStrings.make(AttributedStorage(copying: storage), mutable: false).flatMap { ObjC.autorelease($0) }
    }

    /// From a keyed archive or nib: the string and its attributes.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        let decode = { (key: String) in ObjC.send(coder.id, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased(key)) }
        let text = decode("NSString").flatMap { Strings.value(of: $0) } ?? ""
        let attributes = decode("NSAttributes").flatMap { ObjC.isKind($0, of: Dictionaries.dictionaryClass) ? $0 : nil }
        Storage.set(objcObject, AttributedStorage(units: Array(text.utf16), attributes: attributes))
        return self
    }

    /// To a keyed archive: the string, and the attributes when one run has
    /// them all (as a formatter's symbols in a nib do).
    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        typealias EncodeObject = @convention(c) (id?, SEL, id?, id?) -> Void
        let encode = unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)
        encode(coder.id, ObjC.selector("encodeObject:forKey:"), Strings.autoreleased(storage.string), Strings.autoreleased("NSString"))
        if storage.runs.count == 1 {
            encode(coder.id, ObjC.selector("encodeObject:forKey:"), storage.runs[0].attributes, Strings.autoreleased("NSAttributes"))
        }
    }

    @ObjCMethod("initWithString:attributes:")
    func initialize(string: String?, attributes: ObjCObject?) -> Self {
        Storage.set(objcObject, AttributedStorage(units: Array((string ?? "").utf16), attributes: attributes?.id))
        return self
    }

    // MARK: Documents

    /// The string of a document's bytes: RTF's text, or plain text. There
    /// are no document attributes to give back.
    private func initialize(document bytes: [UInt8]?, attributes: UnsafeMutablePointer<id?>?) -> Self? {
        attributes?.pointee = nil
        guard let bytes else { return nil }
        Storage.set(objcObject, AttributedStorage(units: Array(RTF.documentText(bytes).utf16), attributes: nil))
        return self
    }

    private static func fileBytes(_ path: String?) -> [UInt8]? {
        path.flatMap { FileManager.default.contents(atPath: $0) }.map(Array.init)
    }

    @ObjCMethod("initWithPath:documentAttributes:")
    func initialize(path: String?, documentAttributes: UnsafeMutablePointer<id?>?) -> Self? {
        initialize(document: Self.fileBytes(path), attributes: documentAttributes)
    }

    @ObjCMethod("initWithURL:documentAttributes:")
    func initialize(url: ObjCObject?, documentAttributes: UnsafeMutablePointer<id?>?) -> Self? {
        initialize(document: Self.fileBytes(URLs.url(url?.id)?.path), attributes: documentAttributes)
    }

    @ObjCMethod("initWithURL:options:documentAttributes:error:")
    func initialize(url: ObjCObject?, options: ObjCObject?, documentAttributes: UnsafeMutablePointer<id?>?,
                    error: UnsafeMutablePointer<id?>?) -> Self? {
        initialize(document: Self.fileBytes(URLs.url(url?.id)?.path), attributes: documentAttributes)
    }

    @ObjCMethod("initWithRTF:documentAttributes:")
    func initialize(rtf data: ObjCObject?, documentAttributes: UnsafeMutablePointer<id?>?) -> Self? {
        initialize(document: data.map { Array(DataObjects.data($0.id)) }, attributes: documentAttributes)
    }

    @ObjCMethod("initWithData:options:documentAttributes:error:")
    func initialize(data: ObjCObject?, options: ObjCObject?, documentAttributes: UnsafeMutablePointer<id?>?,
                    error: UnsafeMutablePointer<id?>?) -> Self? {
        initialize(document: data.map { Array(DataObjects.data($0.id)) }, attributes: documentAttributes)
    }

    @ObjCMethod("initWithAttributedString:")
    func initialize(attributedString other: ObjCObject) -> Self {
        let source = AttributedStrings.storage(other.id) ?? AttributedStorage(units: [], attributes: nil)
        Storage.set(objcObject, AttributedStorage(copying: source))
        return self
    }

    @ObjCMethod("string") func string() -> String { storage.string }
    @ObjCMethod("length") func length() -> UInt { UInt(storage.units.count) }

    private func attributes(at index: UInt, effective: UnsafeMutablePointer<NSRange>?, method: String) -> id {
        guard let (position, start) = storage.run(at: Int(index)) else {
            Exceptions.raise(name: "NSRangeException", reason: "-[NSAttributedString \(method)]: Range or index out of bounds")
        }
        let run = storage.runs[position]
        effective?.pointee = NSRange(location: UInt(start), length: UInt(run.length))
        return run.attributes
    }

    @ObjCMethod("attributesAtIndex:effectiveRange:")
    func attributes(at index: UInt, effectiveRange: UnsafeMutablePointer<NSRange>?) -> UnsafeMutableRawPointer {
        attributes(at: index, effective: effectiveRange, method: "attributesAtIndex:effectiveRange:")
    }

    @ObjCMethod("attributesAtIndex:longestEffectiveRange:inRange:")
    func attributes(at index: UInt, longestEffectiveRange: UnsafeMutablePointer<NSRange>?, in limit: NSRange) -> UnsafeMutableRawPointer {
        var effective = NSRange(location: 0, length: 0)
        let found = attributes(at: index, effective: &effective, method: "attributesAtIndex:longestEffectiveRange:inRange:")
        let start = max(effective.location, limit.location)
        let end = min(effective.location + effective.length, limit.location + limit.length)
        longestEffectiveRange?.pointee = NSRange(location: start, length: end - start)
        return found
    }

    /// One attribute's value, and the range over which it is the same.
    @ObjCMethod("attribute:atIndex:effectiveRange:")
    func attribute(_ name: ObjCObject, at index: UInt, effectiveRange: UnsafeMutablePointer<NSRange>?) -> UnsafeMutableRawPointer? {
        // A subclass that keeps the text itself (Xcode's long attributed
        // string) answers the primitive, which this is then made of: the
        // value in its attributes at the index, over the runs around it
        // that have the same value.
        let primitive = ObjC.selector("attributesAtIndex:effectiveRange:")
        if ObjC.overrides(objcObject, primitive, of: AttributedStrings.stringClass) {
            typealias Primitive = @convention(c) (id?, SEL, UInt, UnsafeMutablePointer<NSRange>?) -> id?
            let attributes = unsafeBitCast(ObjC.msgSend, to: Primitive.self)
            typealias Length = @convention(c) (id?, SEL) -> UInt
            let length = unsafeBitCast(ObjC.msgSend, to: Length.self)(objcObject, ObjC.selector("length"))
            var range = NSRange(location: 0, length: 0)
            let value = attributes(objcObject, primitive, index, &range).flatMap { Dictionaries.value($0, for: name.id) }
            guard let effectiveRange else { return value }
            let same = { (other: id?) -> Bool in
                value == nil ? other == nil : other.map { AttributedStorage.equal($0, value!) } ?? false
            }
            var start = range.location, end = range.location + range.length
            while start > 0 {
                var before = NSRange(location: 0, length: 0)
                guard same(attributes(objcObject, primitive, start - 1, &before).flatMap { Dictionaries.value($0, for: name.id) }),
                      before.location < start else { break }
                start = before.location
            }
            while end < length {
                var after = NSRange(location: 0, length: 0)
                guard same(attributes(objcObject, primitive, end, &after).flatMap { Dictionaries.value($0, for: name.id) }),
                      after.location + after.length > end else { break }
                end = after.location + after.length
            }
            effectiveRange.pointee = NSRange(location: start, length: end - start)
            return value
        }
        guard let (position, _) = storage.run(at: Int(index)) else {
            Exceptions.raise(name: "NSRangeException", reason: "-[NSAttributedString attribute:atIndex:effectiveRange:]: Range or index out of bounds")
        }
        let value = Dictionaries.value(storage.runs[position].attributes, for: name.id)
        if let effectiveRange {
            let same = { (run: AttributeRun) -> Bool in
                let other = Dictionaries.value(run.attributes, for: name.id)
                return value == nil ? other == nil : other.map { AttributedStorage.equal($0, value!) } ?? false
            }
            var first = position, last = position
            while first > 0, same(storage.runs[first - 1]) { first -= 1 }
            while last + 1 < storage.runs.count, same(storage.runs[last + 1]) { last += 1 }
            let start = storage.runs[..<first].reduce(0) { $0 + $1.length }
            let length = storage.runs[first...last].reduce(0) { $0 + $1.length }
            effectiveRange.pointee = NSRange(location: UInt(start), length: UInt(length))
        }
        return value
    }

    @ObjCMethod("attribute:atIndex:longestEffectiveRange:inRange:")
    func attribute(_ name: ObjCObject, at index: UInt, longestEffectiveRange: UnsafeMutablePointer<NSRange>?,
                   in limit: NSRange) -> UnsafeMutableRawPointer? {
        var effective = NSRange(location: 0, length: 0)
        let value = attribute(name, at: index, effectiveRange: &effective)
        let start = max(effective.location, limit.location)
        let end = min(effective.location + effective.length, limit.location + limit.length)
        longestEffectiveRange?.pointee = NSRange(location: start, length: end - start)
        return value
    }

    @ObjCMethod("attributedSubstringFromRange:")
    func attributedSubstring(from range: NSRange) -> UnsafeMutableRawPointer? {
        AttributedStrings.check(range, storage.units.count, "attributedSubstringFromRange:")
        let sub = AttributedStorage(units: Array(storage.units[Int(range.location)..<Int(range.location + range.length)]),
                                    attributes: nil)
        sub.runs.forEach { ObjC.release($0.attributes) }
        sub.runs = storage.runs(in: range).map { AttributeRun(length: $0.length, attributes: ObjC.retain($0.attributes)!) }
        return ObjC.autorelease(AttributedStrings.make(sub, mutable: false))
    }

    /// Options: NSAttributedStringEnumerationReverse (2).
    private func enumerate(_ range: NSRange, _ options: UInt, _ body: (AttributeRun, NSRange) -> Bool) {
        AttributedStrings.check(range, storage.units.count, "enumerateAttributesInRange:options:usingBlock:")
        var pieces: [(AttributeRun, NSRange)] = []
        var start = Int(range.location)
        for run in storage.runs(in: range) {
            // A block may change the attributes as it goes, which replaces
            // these dictionaries.
            _ = ObjC.retain(run.attributes)
            pieces.append((run, NSRange(location: UInt(start), length: UInt(run.length))))
            start += run.length
        }
        defer { pieces.forEach { ObjC.release($0.0.attributes) } }
        if options & 2 != 0 { pieces.reverse() }
        for (run, range) in pieces where !body(run, range) { return }
    }

    @ObjCMethod("enumerateAttributesInRange:options:usingBlock:")
    func enumerateAttributes(in range: NSRange, options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id, NSRange, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        enumerate(range, options) { run, range in
            var stop = false
            invoke(block.id, run.attributes, range, &stop)
            return !stop
        }
    }

    /// Runs where one attribute is the same are reported together.
    @ObjCMethod("enumerateAttribute:inRange:options:usingBlock:")
    func enumerateAttribute(_ name: ObjCObject, in range: NSRange, options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id?, NSRange, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        var groups: [(id?, NSRange)] = []
        enumerate(range, 0) { run, range in
            let value = Dictionaries.value(run.attributes, for: name.id)
            if let last = groups.last, last.0 == nil ? value == nil : value.map({ AttributedStorage.equal($0, last.0!) }) ?? false {
                groups[groups.count - 1].1.length += range.length
            } else {
                groups.append((value.flatMap { ObjC.retain($0) }, range))
            }
            return true
        }
        defer { groups.forEach { if let value = $0.0 { ObjC.release(value) } } }
        if options & 2 != 0 { groups.reverse() }
        for (value, range) in groups {
            var stop = false
            invoke(block.id, value, range, &stop)
            if stop { return }
        }
    }

    @ObjCMethod("isEqualToAttributedString:")
    func isEqual(toAttributedString other: ObjCObject?) -> Bool {
        guard let other = AttributedStrings.storage(other?.id) else { return false }
        let mine = storage
        return mine.units == other.units && mine.runs.count == other.runs.count
            && zip(mine.runs, other.runs).allSatisfy { $0.length == $1.length && AttributedStorage.equal($0.attributes, $1.attributes) }
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, ObjC.isKind(other.id, of: AttributedStrings.stringClass) else { return false }
        return isEqual(toAttributedString: other)
    }

    @ObjCMethod("hash") func hash() -> UInt { Strings.hash(storage.string) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        AttributedStrings.make(AttributedStorage(copying: storage), mutable: false)
    }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        AttributedStrings.make(AttributedStorage(copying: storage), mutable: true)
    }

    /// Darwin's form: each run's text, then its attributes in braces.
    @ObjCMethod("description")
    func description() -> String {
        var text = ""
        var start = 0
        for run in storage.runs {
            text += String(decoding: storage.units[start..<start + run.length], as: UTF16.self)
            text += Format.describe(run.attributes)
            start += run.length
        }
        return text
    }
}

/// NSMutableAttributedString.
@ObjCClass("NSMutableAttributedString")
public class NSMutableAttributedString: NSAttributedString {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        AttributedStrings.mutableClass = cls.storage
        cls.addMethod("appendLocalizedFormat:", types: "v24@0:8@16",
                      implementation: variadicEntry(perry_imp_appendLocalizedFormat), isClassMethod: false)
    }

    /// The characters as an NSMutableString: changes to it change the
    /// attributed string, as Foundation's proxy does.
    @ObjCMethod("mutableString")
    func mutableString() -> UnsafeMutableRawPointer? {
        let string = MutableStrings.make("")
        MutableStrings.storage(string).attributed = storage
        return ObjC.autorelease(string)
    }

    @ObjCMethod("replaceCharactersInRange:withString:")
    func replaceCharacters(in range: NSRange, with string: String) {
        AttributedStrings.check(range, storage.units.count, "replaceCharactersInRange:withString:")
        storage.replace(range, with: Array(string.utf16), attributes: nil)
    }

    @ObjCMethod("replaceCharactersInRange:withAttributedString:")
    func replaceCharacters(in range: NSRange, withAttributedString other: ObjCObject) {
        AttributedStrings.check(range, storage.units.count, "replaceCharactersInRange:withAttributedString:")
        let source = AttributedStrings.storage(other.id) ?? AttributedStorage(units: [], attributes: nil)
        storage.replace(range, with: source.units, attributes: source.runs)
    }

    @ObjCMethod("insertAttributedString:atIndex:")
    func insert(_ other: ObjCObject, at index: UInt) {
        replaceCharacters(in: NSRange(location: index, length: 0), withAttributedString: other)
    }

    @ObjCMethod("appendAttributedString:")
    func append(_ other: ObjCObject) {
        replaceCharacters(in: NSRange(location: UInt(storage.units.count), length: 0), withAttributedString: other)
    }

    @ObjCMethod("deleteCharactersInRange:")
    func deleteCharacters(in range: NSRange) {
        AttributedStrings.check(range, storage.units.count, "deleteCharactersInRange:")
        storage.replace(range, with: [], attributes: [])
    }

    @ObjCMethod("setAttributedString:")
    func setAttributedString(_ other: ObjCObject) {
        replaceCharacters(in: NSRange(location: 0, length: UInt(storage.units.count)), withAttributedString: other)
    }

    @ObjCMethod("setAttributes:range:")
    func setAttributes(_ attributes: ObjCObject?, range: NSRange) {
        AttributedStrings.check(range, storage.units.count, "setAttributes:range:")
        let entries = Dictionaries.entries(attributes?.id)
        storage.update(range) { _ in entries }
    }

    @ObjCMethod("addAttribute:value:range:")
    func addAttribute(_ name: ObjCObject?, value: ObjCObject?, range: NSRange) {
        // Darwin raises for a nil value; a program that gets here with one
        // on this system only (a font or an image it could not load) goes
        // on without the attribute.
        guard let name, let value else {
            foundationWarning("-[NSMutableAttributedString addAttribute:value:range:] with nil, ignored")
            return
        }
        // No characters, nothing to change, wherever the range is: what a
        // search that found nothing gives ({NSNotFound, 0}) is let by.
        guard range.length > 0 else { return }
        AttributedStrings.check(range, storage.units.count, "addAttribute:value:range:")
        storage.update(range) { entries in
            entries.filter { !AttributedStorage.equal($0.key, name.id) } + [(key: name.id, value: value.id)]
        }
    }

    @ObjCMethod("addAttributes:range:")
    func addAttributes(_ attributes: ObjCObject, range: NSRange) {
        // No characters, nothing to change, wherever the range is: what a
        // search that found nothing gives ({NSNotFound, 0}) is let by.
        guard range.length > 0 else { return }
        AttributedStrings.check(range, storage.units.count, "addAttributes:range:")
        let added = Dictionaries.entries(attributes.id)
        storage.update(range) { entries in
            entries.filter { entry in !added.contains { AttributedStorage.equal($0.key, entry.key) } } + added
        }
    }

    @ObjCMethod("removeAttribute:range:")
    func removeAttribute(_ name: ObjCObject, range: NSRange) {
        // No characters, nothing to change, wherever the range is: what a
        // search that found nothing gives ({NSNotFound, 0}) is let by.
        guard range.length > 0 else { return }
        AttributedStrings.check(range, storage.units.count, "removeAttribute:range:")
        storage.update(range) { entries in entries.filter { !AttributedStorage.equal($0.key, name.id) } }
    }

    @ObjCMethod("beginEditing") func beginEditing() {}
    @ObjCMethod("endEditing") func endEditing() {}
}

/// Foundation's attributed string keys (iOS 15 and later), which Swift's
/// AttributedString attributes convert through, with Darwin's values.
@ObjCConstants
enum AttributedStringKeys {
    static let NSAlternateDescriptionAttributeName = "NSAlternateDescription"
    static let NSImageURLAttributeName = "NSImageURL"
    static let NSInflectionAgreementArgumentAttributeName = "NSInflectionAgreementArgument"
    static let NSInflectionAgreementConceptAttributeName = "NSInflectionAgreementConcept"
    static let NSInflectionAlternativeAttributeName = "NSInflectionAlternative"
    static let NSInflectionReferentConceptAttributeName = "NSInflectionReferentConcept"
    static let NSInflectionRuleAttributeName = "NSInflect"
    static let NSInlinePresentationIntentAttributeName = "NSInlinePresentationIntent"
    static let NSLanguageIdentifierAttributeName = "NSLanguage"
    static let NSListItemDelimiterAttributeName = "NSListItemDelimiter"
    static let NSLocalizedNumberFormatAttributeName = "NSLocalizedNumberFormat"
    static let NSMarkdownSourcePositionAttributeName = "NSMarkdownSourcePosition"
    static let NSMorphologyAttributeName = "NSMorphology"
    static let NSPresentationIntentAttributeName = "NSPresentationIntent"
    static let NSReplacementIndexAttributeName = "NSReplacementIndex"
}

// MARK: - CFAttributedString

/// An attributed string with the attributes over all of it, +1.
@c(_CFAttributedStringCreate)
public func CFAttributedStringCreate(_ allocator: UnsafeRawPointer?, _ string: id?, _ attributes: id?) -> id? {
    guard let text = Strings.value(of: string) else { return nil }
    return AttributedStrings.make(AttributedStorage(units: Array(text.utf16), attributes: attributes), mutable: false)
}

/// An empty mutable attributed string, +1.
@c(_CFAttributedStringCreateMutable)
public func CFAttributedStringCreateMutable(_ allocator: UnsafeRawPointer?, _ maxLength: Int) -> id? {
    AttributedStrings.make(AttributedStorage(units: [], attributes: nil), mutable: true)
}

/// A mutable copy of an attributed string, +1.
@c(_CFAttributedStringCreateMutableCopy)
public func CFAttributedStringCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ maxLength: Int, _ string: id?) -> id? {
    ObjC.send(string, ObjC.selector("mutableCopy"))
}

/// A copy of an attributed string, +1.
@c(_CFAttributedStringCreateCopy)
public func CFAttributedStringCreateCopy(_ allocator: UnsafeRawPointer?, _ string: id?) -> id? {
    ObjC.send(string, ObjC.selector("copy"))
}

private func nsRange(_ range: PerryCFRange) -> PerryRange {
    PerryRange(location: UInt(max(0, range.location)), length: UInt(max(0, range.length)))
}

@DarwinC("_CFAttributedStringReplaceString")
public func CFAttributedStringReplaceString(_ string: id?, _ range: PerryCFRange, _ replacement: id?) {
    typealias F = @convention(c) (id?, SEL, PerryRange, id?) -> Void
    unsafeBitCast(ObjC.msgSend, to: F.self)(string, ObjC.selector("replaceCharactersInRange:withString:"), nsRange(range),
                                            replacement ?? Strings.autoreleased(""))
}

@DarwinC("_CFAttributedStringReplaceAttributedString")
public func CFAttributedStringReplaceAttributedString(_ string: id?, _ range: PerryCFRange, _ replacement: id?) {
    typealias F = @convention(c) (id?, SEL, PerryRange, id?) -> Void
    unsafeBitCast(ObjC.msgSend, to: F.self)(string, ObjC.selector("replaceCharactersInRange:withAttributedString:"), nsRange(range), replacement)
}

/// Sets one attribute over a range, or removes it for a NULL value.
@DarwinC("_CFAttributedStringSetAttribute")
public func CFAttributedStringSetAttribute(_ string: id?, _ range: PerryCFRange, _ name: id?, _ value: id?) {
    guard let name else { return }
    if let value {
        typealias F = @convention(c) (id?, SEL, id?, id?, PerryRange) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(string, ObjC.selector("addAttribute:value:range:"), name, value, nsRange(range))
    } else {
        typealias F = @convention(c) (id?, SEL, id?, PerryRange) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(string, ObjC.selector("removeAttribute:range:"), name, nsRange(range))
    }
}

/// Sets the attributes over a range: added to those there, or in place of
/// them when `clear` is set.
@DarwinC("_CFAttributedStringSetAttributes")
public func CFAttributedStringSetAttributes(_ string: id?, _ range: PerryCFRange, _ attributes: id?, _ clear: Bool) {
    typealias F = @convention(c) (id?, SEL, id?, PerryRange) -> Void
    unsafeBitCast(ObjC.msgSend, to: F.self)(string, ObjC.selector(clear ? "setAttributes:range:" : "addAttributes:range:"),
                                            attributes, nsRange(range))
}

@DarwinC("_CFAttributedStringRemoveAttribute")
public func CFAttributedStringRemoveAttribute(_ string: id?, _ range: PerryCFRange, _ name: id?) {
    CFAttributedStringSetAttribute(string, range, name, nil)
}

@c(_CFAttributedStringBeginEditing) public func CFAttributedStringBeginEditing(_ string: id?) {}
@c(_CFAttributedStringEndEditing) public func CFAttributedStringEndEditing(_ string: id?) {}

@c(_CFAttributedStringGetLength)
public func CFAttributedStringGetLength(_ string: id?) -> Int {
    AttributedStrings.storage(string)?.units.count ?? 0
}

/// Darwin's concrete classes, which attributed strings are instances of
/// there. Code that hooks the methods (crash guards do) looks the classes up
/// by these names and finds the methods they inherit, which are the ones
/// every attributed string here runs.
@ObjCClass("NSConcreteAttributedString")
public final class NSConcreteAttributedString: NSAttributedString {}

@ObjCClass("NSConcreteMutableAttributedString")
public final class NSConcreteMutableAttributedString: NSMutableAttributedString {}

/// The string, +0, held by an autorelease pool as the attributed string's is.
@c(_CFAttributedStringGetString)
public func CFAttributedStringGetString(_ string: id?) -> id? {
    ObjC.send(string, ObjC.selector("string"))
}

// MARK: - Formatting

/// Formats of attributed strings: the format's text keeps its attributes;
/// each specifier's text takes the attributes of the specifier's first
/// character, and an NSAttributedString argument of %@ keeps its own,
/// over those (NSAttributedStringFormattingInsertArgumentAttributesWithoutMerging,
/// option 1: instead of them). The locale is not applied, nor inflection.
enum AttributedFormatting {
    static let withoutMerging: UInt = 1

    /// The end of the specifier starting with "%" at `start`: flags,
    /// position, width, precision, length and conversion.
    private static func specifierEnd(_ units: [UInt16], _ start: Int) -> Int {
        var index = start + 1
        let modifiers = Set("-+ #0'123456789$.*hlqLzjt".utf16)
        while index < units.count, modifiers.contains(units[index]) { index += 1 }
        return min(index + 1, units.count)
    }

    /// The position a specifier names ("%2$@" is 2), if it does.
    private static func position(_ specifier: [UInt16]) -> Int? {
        let digits = specifier.dropFirst().prefix { (0x30...0x39).contains($0) }
        guard !digits.isEmpty, specifier.dropFirst(digits.count + 1).first == 0x24 else { return nil }   // $
        return Int(String(decoding: digits, as: UTF16.self))
    }

    /// One dictionary of both runs' attributes, the argument's winning; +1.
    private static func merged(_ base: id, _ top: id, options: UInt) -> id {
        if options & withoutMerging != 0 { return ObjC.retain(top)! }
        var entries = Dictionaries.entries(base)
        for entry in Dictionaries.entries(top) {
            entries.removeAll { AttributedStorage.equal($0.key, entry.key) }
            entries.append(entry)
        }
        return Dictionaries.make(entries)
    }

    static func format(_ format: id?, options: UInt, arguments: UnsafeRawPointer?) -> AttributedStorage {
        let source = AttributedStrings.storage(format) ?? AttributedStorage(units: Array((Strings.value(of: format) ?? "").utf16), attributes: nil)
        let units = source.units
        let result = AttributedStorage(units: [], attributes: nil)
        func attributesAt(_ index: Int) -> id {
            source.run(at: index).map { source.runs[$0.index].attributes } ?? Dictionaries.autoreleased([])
        }
        func append(_ text: [UInt16], _ dictionary: id) {
            guard !text.isEmpty else { return }
            result.units += text
            result.runs.append(AttributeRun(length: text.count, attributes: ObjC.retain(dictionary)!))
        }
        var darwin = arguments.map { DarwinArguments($0) }
        var index = 0, literalStart = 0
        func flushLiteral(_ end: Int) {
            for run in source.runs(in: NSRange(location: UInt(literalStart), length: UInt(end - literalStart))) {
                result.units += units[literalStart..<literalStart + run.length]
                result.runs.append(AttributeRun(length: run.length, attributes: ObjC.retain(run.attributes)!))
                literalStart += run.length
            }
        }
        while index < units.count {
            guard units[index] == 0x25 else { index += 1; continue }   // %
            flushLiteral(index)
            let end = specifierEnd(units, index)
            let specifier = Array(units[index..<end])
            let attributes = attributesAt(index)
            if specifier == [0x25, 0x25] {
                append([0x25], attributes)
            } else if specifier.last == 0x40, darwin != nil {   // @
                let object: id?
                if let position = position(specifier) {
                    var positional = darwin!.at(position)
                    object = positional.nextPointer()
                } else {
                    object = darwin!.nextPointer()
                }
                if let object, ObjC.isKind(object, of: AttributedStrings.stringClass), let inserted = AttributedStrings.storage(object) {
                    var offset = 0
                    for run in inserted.runs {
                        let dictionary = merged(attributes, run.attributes, options: options)
                        append(Array(inserted.units[offset..<offset + run.length]), dictionary)
                        ObjC.release(dictionary)
                        offset += run.length
                    }
                } else {
                    append(Array((Strings.value(of: object) ?? Format.describe(object)).utf16), attributes)
                }
            } else if darwin != nil {
                append(Array(Format.string(String(decoding: specifier, as: UTF16.self), &darwin!).utf16), attributes)
            } else {
                append(specifier, attributes)
            }
            index = end
            literalStart = end
        }
        flushLiteral(units.count)
        result.merge()
        return result
    }

    /// An autoreleased attributed string of `cls`, the formatted format.
    static func autoreleased(_ cls: id?, _ format: id?, options: UInt, arguments: UnsafeRawPointer?) -> id? {
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(AttributedStrings.stringClass)) else { return nil }
        Storage.set(object, AttributedFormatting.format(format, options: options, arguments: arguments))
        return ObjC.autorelease(object)
    }
}

/// + (instancetype)localizedAttributedStringWithFormat:(NSAttributedString *)format, ...
@c
public func perry_foundation_localizedAttributedStringWithFormat(_ cls: id?, _ cmd: SEL?, _ format: id?,
                                                                 _ arguments: UnsafeRawPointer?) -> id? {
    AttributedFormatting.autoreleased(cls, format, options: 0, arguments: arguments)
}

/// + (instancetype)localizedAttributedStringWithFormat:options:, ...
@c
public func perry_foundation_localizedAttributedStringWithFormatOptions(_ cls: id?, _ cmd: SEL?, _ format: id?, _ options: UInt,
                                                                        _ arguments: UnsafeRawPointer?) -> id? {
    AttributedFormatting.autoreleased(cls, format, options: options, arguments: arguments)
}

/// + (instancetype)localizedAttributedStringWithFormat:context:, ...: the
/// context, for inflection, is not applied.
@c
public func perry_foundation_localizedAttributedStringWithFormatContext(_ cls: id?, _ cmd: SEL?, _ format: id?, _ context: id?,
                                                                        _ arguments: UnsafeRawPointer?) -> id? {
    AttributedFormatting.autoreleased(cls, format, options: 0, arguments: arguments)
}

/// + (instancetype)localizedAttributedStringWithFormat:options:context:, ...
@c
public func perry_foundation_localizedAttributedStringWithFormatOptionsContext(_ cls: id?, _ cmd: SEL?, _ format: id?, _ options: UInt,
                                                                               _ context: id?, _ arguments: UnsafeRawPointer?) -> id? {
    AttributedFormatting.autoreleased(cls, format, options: options, arguments: arguments)
}

/// - (instancetype)initWithFormat:options:locale:, ...
@c
public func perry_foundation_attributedInitWithFormat(_ object: id?, _ cmd: SEL?, _ format: id?, _ options: UInt, _ locale: id?,
                                                      _ arguments: UnsafeRawPointer?) -> id? {
    guard let object else { return nil }
    Storage.set(object, AttributedFormatting.format(format, options: options, arguments: arguments))
    return object
}

/// - (instancetype)initWithFormat:options:locale:context:, ...
@c
public func perry_foundation_attributedInitWithFormatContext(_ object: id?, _ cmd: SEL?, _ format: id?, _ options: UInt, _ locale: id?,
                                                             _ context: id?, _ arguments: UnsafeRawPointer?) -> id? {
    perry_foundation_attributedInitWithFormat(object, cmd, format, options, locale, arguments)
}

/// - (void)appendLocalizedFormat:(NSAttributedString *)format, ...
@c
public func perry_foundation_appendLocalizedFormat(_ object: id?, _ cmd: SEL?, _ format: id?, _ arguments: UnsafeRawPointer?) {
    guard let object, let storage = AttributedStrings.storage(object) else { return }
    let formatted = AttributedFormatting.format(format, options: 0, arguments: arguments)
    storage.replace(NSRange(location: UInt(storage.units.count), length: 0), with: formatted.units, attributes: formatted.runs)
}
