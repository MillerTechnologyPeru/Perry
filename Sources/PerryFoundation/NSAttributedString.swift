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
            foundationFatal("-[NSAttributedString \(method)]: Range or index out of bounds")
        }
    }
}

/// NSAttributedString.
@ObjCClass("NSAttributedString")
public class NSAttributedString: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        AttributedStrings.stringClass = cls.storage
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

    @ObjCMethod("initWithString:")
    func initialize(string: String) -> Self {
        Storage.set(objcObject, AttributedStorage(units: Array(string.utf16), attributes: nil))
        return self
    }

    @ObjCMethod("initWithString:attributes:")
    func initialize(string: String, attributes: ObjCObject?) -> Self {
        Storage.set(objcObject, AttributedStorage(units: Array(string.utf16), attributes: attributes?.id))
        return self
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
            foundationFatal("-[NSAttributedString \(method)]: Range or index out of bounds")
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
        guard let (position, _) = storage.run(at: Int(index)) else {
            foundationFatal("-[NSAttributedString attribute:atIndex:effectiveRange:]: Range or index out of bounds")
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
            pieces.append((run, NSRange(location: UInt(start), length: UInt(run.length))))
            start += run.length
        }
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
                groups.append((value, range))
            }
            return true
        }
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
public final class NSMutableAttributedString: NSAttributedString {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        AttributedStrings.mutableClass = cls.storage
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
    func addAttribute(_ name: ObjCObject, value: ObjCObject, range: NSRange) {
        AttributedStrings.check(range, storage.units.count, "addAttribute:value:range:")
        storage.update(range) { entries in
            entries.filter { !AttributedStorage.equal($0.key, name.id) } + [(key: name.id, value: value.id)]
        }
    }

    @ObjCMethod("addAttributes:range:")
    func addAttributes(_ attributes: ObjCObject, range: NSRange) {
        AttributedStrings.check(range, storage.units.count, "addAttributes:range:")
        let added = Dictionaries.entries(attributes.id)
        storage.update(range) { entries in
            entries.filter { entry in !added.contains { AttributedStorage.equal($0.key, entry.key) } } + added
        }
    }

    @ObjCMethod("removeAttribute:range:")
    func removeAttribute(_ name: ObjCObject, range: NSRange) {
        AttributedStrings.check(range, storage.units.count, "removeAttribute:range:")
        storage.update(range) { entries in entries.filter { !AttributedStorage.equal($0.key, name.id) } }
    }

    @ObjCMethod("beginEditing") func beginEditing() {}
    @ObjCMethod("endEditing") func endEditing() {}
}
