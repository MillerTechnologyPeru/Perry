import Glibc
import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSKeyedUnarchiver: the object graph an NSKeyedArchiver wrote, a binary
// property list of "$objects" with UID references. Foundation's own classes
// are rebuilt directly; any other class gets -initWithCoder: with the
// unarchiver, as Core Data's model descriptions are loaded from .mom files.

/// A binary property list's values, with the UIDs keyed archives use.
indirect enum ArchiveValue {
    case null
    case bool(Bool)
    case integer(Int64)
    case real(Double)
    case date(Double)
    case data([UInt8])
    case string(String)
    case uid(Int)
    case array([ArchiveValue])
    case dictionary([String: ArchiveValue])
}

/// Reads binary property lists ("bplist00").
struct BinaryPropertyList {
    let bytes: [UInt8]
    let offsetSize: Int
    let referenceSize: Int
    let offsets: [Int]
    let top: Int

    init?(_ bytes: [UInt8]) {
        guard bytes.count > 40, Array(bytes[0..<8]) == Array("bplist00".utf8) else { return nil }
        let trailer = bytes.count - 32
        let offsetSize = Int(bytes[trailer + 6]), referenceSize = Int(bytes[trailer + 7])
        func number(_ at: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 << 8 | Int(bytes[at + $1]) }
        }
        let count = number(trailer + 8, 8), topObject = number(trailer + 16, 8), table = number(trailer + 24, 8)
        guard offsetSize > 0, referenceSize > 0, table + count * offsetSize <= trailer else { return nil }
        self.bytes = bytes
        self.offsetSize = offsetSize
        self.referenceSize = referenceSize
        offsets = (0..<count).map { number(table + $0 * offsetSize, offsetSize) }
        top = topObject
    }

    private func number(_ at: Int, _ size: Int) -> Int {
        (0..<size).reduce(0) { $0 << 8 | Int(bytes[at + $1]) }
    }

    /// An integer's, a real number's or a date's bytes: as many as 64 bits,
    /// more than an Int holds on armv7.
    private func wide(_ at: Int, _ size: Int) -> UInt64 {
        (0..<size).reduce(0) { $0 << 8 | UInt64(bytes[at + $1]) }
    }

    /// A length from the marker's low nibble, or the integer after it.
    private func length(_ at: Int) -> (count: Int, start: Int) {
        let low = Int(bytes[at] & 0x0f)
        guard low == 0x0f else { return (low, at + 1) }
        let size = 1 << Int(bytes[at + 1] & 0x0f)
        return (number(at + 2, size), at + 2 + size)
    }

    func value(_ index: Int) -> ArchiveValue {
        guard index < offsets.count else { return .null }
        let at = offsets[index]
        let marker = bytes[at]
        switch marker >> 4 {
        case 0x0:
            return marker == 0x09 ? .bool(true) : marker == 0x08 ? .bool(false) : .null
        case 0x1:
            let size = 1 << Int(marker & 0x0f)
            // A 16-byte integer's low 8 bytes are its value.
            let raw = wide(size > 8 ? at + 1 + size - 8 : at + 1, min(size, 8))
            return .integer(size >= 8 ? Int64(bitPattern: raw) : Int64(raw))
        case 0x2:
            let size = 1 << Int(marker & 0x0f)
            let raw = wide(at + 1, min(size, 8))
            return .real(size == 4 ? Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw))) : Double(bitPattern: raw))
        case 0x3:
            return .date(Double(bitPattern: wide(at + 1, 8)))
        case 0x4:
            let (count, start) = length(at)
            return .data(Array(bytes[start..<start + count]))
        case 0x5:
            let (count, start) = length(at)
            return .string(String(decoding: bytes[start..<start + count], as: UTF8.self))
        case 0x6:
            let (count, start) = length(at)
            let units = (0..<count).map { UInt16(bytes[start + 2 * $0]) << 8 | UInt16(bytes[start + 2 * $0 + 1]) }
            return .string(String(decoding: units, as: UTF16.self))
        case 0x8:
            return .uid(number(at + 1, Int(marker & 0x0f) + 1))
        case 0xA, 0xC:
            let (count, start) = length(at)
            return .array((0..<count).map { value(number(start + $0 * referenceSize, referenceSize)) })
        case 0xD:
            let (count, start) = length(at)
            var entries: [String: ArchiveValue] = [:]
            for i in 0..<count {
                if case .string(let key) = value(number(start + i * referenceSize, referenceSize)) {
                    entries[key] = value(number(start + (count + i) * referenceSize, referenceSize))
                }
            }
            return .dictionary(entries)
        default:
            return .null
        }
    }
}

/// An unarchiving in progress.
final class UnarchiverStorage {
    let objects: [ArchiveValue]
    let top: [String: ArchiveValue]
    /// The next key for unkeyed coding: "$0", "$1", and so on.
    var unkeyed = 0
    /// Decoded objects by UID, retained; also those still being decoded, so
    /// cycles resolve to them.
    var decoded: [Int: id] = [:]
    /// The archived object whose -initWithCoder: is running, innermost last.
    var stack: [[String: ArchiveValue]] = []
    var requiresSecureCoding = false
    /// Why decoding failed, retained: the first error -failWithError: was
    /// given, until a top-level decode takes it. While there is one, every
    /// decode gives nil or zero.
    var error: id?
    /// NSDecodingFailurePolicy: raise an exception 0, which unarchivers
    /// made with -initForReadingWithData: have; set the error and return 1,
    /// which -initForReadingFromData:error: sets.
    var failurePolicy = 0
    /// Top-level decodes in progress, which take failures as errors
    /// whatever the policy.
    var topLevel = 0
    /// The classes each decode in progress allows, innermost last: nil for
    /// a -decodeObjectForKey: inside an object's -initWithCoder:, which
    /// checks none here.
    var allowedStack: [[id]?] = []
    /// setClass:forClassName:'s substitutions for this unarchiver.
    var classes: [String: UnsafeMutableRawPointer] = [:]
    /// The NSKeyedUnarchiverDelegate, not retained.
    var delegate: id?
    var finished = false

    /// The class to decode an archived class name as: this unarchiver's
    /// substitute, then every unarchiver's, then the class of that name.
    func resolve(_ name: String) -> UnsafeMutableRawPointer? {
        if let cls = classes[name] ?? Unarchivers.classes[name] { return cls }
        return name.withCString { ObjC.getClass($0) }.map(UnsafeMutableRawPointer.init)
    }

    init?(_ data: [UInt8]) {
        guard let (value, _) = PropertyLists.parse(data), case .dictionary(let root) = value,
              case .array(let objects)? = root["$objects"], case .dictionary(let top)? = root["$top"] else { return nil }
        self.objects = objects
        self.top = top
    }

    deinit {
        for object in decoded.values { ObjC.release(object) }
        ObjC.release(error)
    }

    /// The current object's (or the top level's) value for a key; none
    /// once decoding has failed.
    func field(_ key: String) -> ArchiveValue? {
        guard error == nil else { return nil }
        return (stack.last ?? top)[key]
    }

    /// The classes in force: those of the innermost decode that gave some.
    var allowedClasses: [id]? {
        allowedStack.last(where: { $0 != nil }) ?? nil
    }

    // MARK: Failing

    /// Fails the decode: raises with the raise policy outside a top-level
    /// decode, otherwise keeps the first error.
    func fail(with failure: id?) {
        if failurePolicy == 0 && topLevel == 0 {
            Exceptions.raise(name: "NSInvalidUnarchiveOperationException", reason: Errors.localizedDescription(failure))
        }
        guard error == nil, let failure else { return }
        error = ObjC.retain(failure)
    }

    func fail(_ debugDescription: String) { fail(with: Coders.corrupt(debugDescription)) }

    // MARK: Decoding

    /// The object for a key, decoded allowing `classes` (nil: whatever
    /// -decodeObjectForKey: allows).
    func decode(_ key: String, classes: [id]?) -> id? {
        // Securely, a decode of no classes at the top level allows none;
        // inside an object's -initWithCoder: it checks none.
        let allowed = classes ?? (requiresSecureCoding && stack.isEmpty ? [] : nil)
        allowedStack.append(allowed)
        defer { allowedStack.removeLast() }
        return object(field(key))
    }

    /// A top-level decode: failures come back as `out`'s error, which the
    /// unarchiver gives up, rather than as exceptions; a key with no value
    /// is NSCoderValueNotFoundError.
    func decodeTopLevel(_ key: String, classes: [id]?, error out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> id? {
        topLevel += 1
        let object = decode(key, classes: classes)
        topLevel -= 1
        if let failure = error {
            error = nil
            out?.pointee = ObjC.autorelease(failure)
            return nil
        }
        if object == nil, field(key) == nil {
            out?.pointee = Coders.missing()
        }
        return object
    }

    /// The class names of an archived object, most specific first.
    func classNames(_ object: [String: ArchiveValue]) -> [String] {
        guard case .uid(let index)? = object["$class"], index < objects.count,
              case .dictionary(let info) = objects[index] else { return [] }
        if case .array(let names)? = info["$classes"] {
            return names.compactMap { if case .string(let name) = $0 { return name } else { return nil } }
        }
        if case .string(let name)? = info["$classname"] { return [name] }
        return []
    }

    /// The object a value refers to, +0 (kept alive by the unarchiver).
    func object(_ value: ArchiveValue?) -> id? {
        guard let value, error == nil else { return nil }
        switch value {
        case .uid(let index): return object(at: index)
        default: return plain(value)
        }
    }

    /// The archived object a UID refers to, when it is one: its fields.
    func archived(_ value: ArchiveValue?) -> [String: ArchiveValue]? {
        guard case .uid(let index)? = value, index < objects.count, case .dictionary(let fields) = objects[index] else { return nil }
        return fields
    }

    /// Whether an object archived with these class names may be decoded:
    /// securely, its class must be one of the classes in force or a
    /// subclass of one, and support secure coding. Values kept in the
    /// archive as themselves (strings, numbers, data) are not checked,
    /// as Darwin doesn't.
    private func permitted(_ names: [String]) -> Bool {
        guard requiresSecureCoding, let allowed = allowedStack.last ?? nil,
              let cls = names.lazy.compactMap({ self.resolve($0) }).first else { return true }
        let target = cls.assumingMemoryBound(to: perry_class_storage.self)
        if allowed.contains(where: { Unarchivers.isSubclass(target, of: $0) }), Unarchivers.supportsSecureCoding(cls) { return true }
        let names = allowed.map { ObjC.name(ofClass: $0) }.sorted().joined(separator: ", ")
        fail("value was of unexpected class '\(ObjC.name(ofClass: cls))'. Allowed classes are '{(\(names))}'.")
        return false
    }

    private func object(at index: Int) -> id? {
        if index == 0 { return nil }                        // "$null"
        if let done = decoded[index] { return done }
        guard index < objects.count else { return nil }
        guard case .dictionary(let archived) = objects[index] else {
            guard let value = plain(objects[index]) else { return nil }
            let result = delegated(ObjC.retain(value)!)
            decoded[index] = result
            return result
        }
        let names = classNames(archived)
        guard permitted(names) else { return nil }
        if let builtIn = foundationObject(names, archived) {
            let result = delegated(ObjC.retain(builtIn)!)
            decoded[index] = result
            return result
        }
        // Any other class: the first in the hierarchy that is registered,
        // or the one the delegate gives.
        guard let cls = names.lazy.compactMap({ self.resolve($0) }).first ?? substitute(names) else {
            fail("cannot decode object of class (\(names.first ?? "?")) for key; the class may be defined in source code or a library that is not linked")
            return nil
        }
        guard let allocated = ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")) else { return nil }
        decoded[index] = allocated
        stack.append(archived)
        var result = ObjC.send(allocated, ObjC.selector("initWithCoder:"), unarchiver)
        stack.removeLast()
        if let made = result, KeyValueCoding.responds(made, ObjC.selector("awakeAfterUsingCoder:")),
           let replaced = ObjC.send(made, ObjC.selector("awakeAfterUsingCoder:"), unarchiver), replaced != made {
            ObjC.retain(replaced)
            ObjC.release(made)
            result = replaced
        }
        decoded[index] = result.map(delegated)
        return decoded[index]
    }

    /// The delegate's -unarchiver:cannotDecodeObjectOfClassName:originalClasses:.
    private func substitute(_ names: [String]) -> UnsafeMutableRawPointer? {
        let selector = ObjC.selector("unarchiver:cannotDecodeObjectOfClassName:originalClasses:")
        guard let delegate, let unarchiver, KeyValueCoding.responds(delegate, selector) else { return nil }
        typealias F = @convention(c) (id?, SEL, id?, id?, id?) -> id?
        return unsafeBitCast(ObjC.msgSend, to: F.self)(delegate, selector, unarchiver, Strings.autoreleased(names.first ?? ""),
                                                       Arrays.autoreleased(names.map { Strings.autoreleased($0) }))
    }

    /// A decoded object (+1) as the delegate's -unarchiver:didDecodeObject:
    /// has it (+1).
    private func delegated(_ object: id) -> id {
        let selector = ObjC.selector("unarchiver:didDecodeObject:")
        guard let delegate, let unarchiver, KeyValueCoding.responds(delegate, selector),
              let replacement = ObjC.send(delegate, selector, unarchiver, object), replacement != object else { return object }
        let replace = ObjC.selector("unarchiver:willReplaceObject:withObject:")
        if KeyValueCoding.responds(delegate, replace) {
            typealias F = @convention(c) (id?, SEL, id?, id?, id?) -> Void
            unsafeBitCast(ObjC.msgSend, to: F.self)(delegate, replace, unarchiver, object, replacement)
        }
        ObjC.retain(replacement)
        ObjC.release(object)
        return replacement
    }

    /// The unarchiver object, set while it decodes.
    var unarchiver: id?

    /// Plain property list values: strings, numbers, data.
    private func plain(_ value: ArchiveValue) -> id? {
        switch value {
        case .null: return nil
        case .bool(let flag): return perry_foundation_boolean(flag ? 1 : 0)
        case .integer(let number): return Numbers.make(nil, .signed(number))
        case .real(let number): return Numbers.make(nil, .double(number))
        case .date(let seconds): return Dates.autoreleased(seconds)
        case .data(let bytes): return DataObjects.autoreleased(Data(bytes))
        case .string(let text): return Strings.autoreleased(text)
        case .uid(let index): return object(at: index)
        case .array(let values): return Arrays.autoreleased(values.compactMap(object))
        case .dictionary: return nil
        }
    }

    private func references(_ value: ArchiveValue?) -> [id] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap(object)
    }

    /// Foundation's classes, from their archived keys.
    private func foundationObject(_ names: [String], _ archived: [String: ArchiveValue]) -> id? {
        guard let name = names.first else { return nil }
        let mutable = name.hasPrefix("NSMutable")
        switch name {
        case "NSString", "NSMutableString":
            let text: String
            if case .string(let s)? = archived["NS.string"] { text = s }
            else if case .data(let bytes)? = archived["NS.bytes"] { text = String(decoding: bytes, as: UTF8.self) }
            else { text = "" }
            return mutable ? ObjC.autorelease(MutableStrings.make(text)) : Strings.autoreleased(text)
        case "NSArray", "NSMutableArray":
            return Arrays.autoreleased(references(archived["NS.objects"]),
                                       cls: mutable ? UnsafeMutableRawPointer(Arrays.mutableClass) : nil)
        case "NSSet", "NSMutableSet":
            return Sets.autoreleased(references(archived["NS.objects"]),
                                     cls: mutable ? UnsafeMutableRawPointer(Sets.mutableClass) : nil)
        case "NSDictionary", "NSMutableDictionary":
            let keys = references(archived["NS.keys"]), values = references(archived["NS.objects"])
            return Dictionaries.autoreleased(Array(zip(keys, values)).map { (key: $0.0, value: $0.1) },
                                             cls: mutable ? UnsafeMutableRawPointer(Dictionaries.mutableClass) : nil)
        case "NSDate":
            if case .real(let seconds)? = archived["NS.time"] { return Dates.autoreleased(seconds) }
            return Dates.autoreleased(0.0)
        case "NSData", "NSMutableData":
            let bytes: [UInt8]
            if case .data(let stored)? = archived["NS.data"] { bytes = stored } else { bytes = [] }
            return DataObjects.autoreleased(Data(bytes), cls: mutable ? UnsafeMutableRawPointer(DataObjects.mutableClass) : nil)
        case "NSNull":
            return Nulls.null
        case "NSURL":
            let relative = Strings.value(of: object(archived["NS.relative"])) ?? ""
            let base = Strings.value(of: object(archived["NS.base"])).flatMap { URL(string: $0) }
            return URLs.autoreleased(URL(string: relative, relativeTo: base))
        case "NSUUID":
            guard case .data(let bytes)? = archived["NS.uuidbytes"], bytes.count == 16 else { return nil }
            let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            return ObjC.autorelease(UUIDs.initialize(ObjC.send(UnsafeMutableRawPointer(UUIDs.uuidClass), ObjC.selector("alloc")), uuid))
        default:
            return nil
        }
    }

    /// The root object: "root" in $top.
    func root() -> id? { object(top["root"]) }

    /// -unarchiverWillFinish: and -unarchiverDidFinish:, once.
    func finish() {
        guard !finished else { return }
        finished = true
        guard let delegate, let unarchiver else { return }
        for name in ["unarchiverWillFinish:", "unarchiverDidFinish:"] where KeyValueCoding.responds(delegate, ObjC.selector(name)) {
            _ = ObjC.send(delegate, ObjC.selector(name), unarchiver)
        }
    }
}

enum Unarchivers {
    nonisolated(unsafe) static var unarchiverClass: Class!
    /// +setClass:forClassName:'s substitutions, for every unarchiver.
    nonisolated(unsafe) static var classes: [String: UnsafeMutableRawPointer] = [:]

    static func storage(_ object: id?) -> UnarchiverStorage? {
        Storage.get(object, as: UnarchiverStorage.self)
    }

    /// An unarchiver for `data`, autoreleased; nil if it is not an archive.
    static func make(_ data: id?) -> id? {
        guard let storage = UnarchiverStorage(Array(DataObjects.data(data))),
              let object = Storage.allocate(UnsafeMutableRawPointer(unarchiverClass)) else { return nil }
        storage.unarchiver = object
        Storage.set(object, storage)
        return ObjC.autorelease(object)
    }

    static func error() -> ObjCObject {
        ObjCObject(Errors.autoreleased(domain: Errors.cocoaDomain, code: 4864,
                                       description: "The data couldn’t be read because it isn’t in the correct format.")!)
    }

    /// The classes of a set of them, or of an array (NSSecureUnarchiveFromDataTransformer's).
    static func classList(_ object: id?) -> [id] {
        guard let object else { return [] }
        return ObjC.isKind(object, of: Arrays.arrayClass) ? Arrays.elements(object) : Sets.elements(object)
    }

    /// Whether `cls` is `ancestor` or a subclass of it.
    static func isSubclass(_ cls: Class, of ancestor: id) -> Bool {
        var current: Class? = cls
        while let c = current {
            if UnsafeMutableRawPointer(c) == ancestor { return true }
            current = c.pointee.superclass
        }
        return false
    }

    /// Prefixes of Apple's frameworks' classes, which this library's
    /// frameworks reimplement without all declaring +supportsSecureCoding:
    /// taken as supporting it, as Darwin's do.
    private static let frameworkPrefixes = ["NS", "_NS", "__NS", "UI", "_UI", "CA", "CL", "CK", "MK", "AV", "UN", "UT", "WK", "CN", "EK"]

    /// Whether a class answers YES to +supportsSecureCoding.
    static func supportsSecureCoding(_ cls: id) -> Bool {
        let selector = ObjC.selector("supportsSecureCoding")
        if ObjC.sendBool(cls, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector)) {
            return ObjC.sendBool(cls, selector, nil)
        }
        let name = ObjC.name(ofClass: cls)
        return frameworkPrefixes.contains { name.hasPrefix($0) }
    }

    /// The root of an archive decoded on its own, the class methods' way:
    /// securely (or not), failures as errors; retained and autoreleased.
    static func unarchive(_ data: id?, classes: [id]?, secure: Bool, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> id? {
        guard let unarchiver = make(data), let storage = storage(unarchiver) else {
            error?.pointee = Coders.corrupt()
            return nil
        }
        storage.requiresSecureCoding = secure
        storage.failurePolicy = 1
        let object = storage.decodeTopLevel("root", classes: classes, error: error)
        storage.finish()
        return object.flatMap { ObjC.autorelease(ObjC.retain($0)) }
    }
}

/// NSKeyedUnarchiver.
@ObjCClass("NSKeyedUnarchiver")
public class NSKeyedUnarchiver: NSCoder {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Unarchivers.unarchiverClass = cls.storage
        CoderGeometry.add(to: cls)
    }

    private var storage: UnarchiverStorage? { Unarchivers.storage(objcObject) }

    @ObjCClassMethod("setClass:forClassName:")
    static func setClass(_ cls: UnsafeMutableRawPointer?, forClassName name: String) { Unarchivers.classes[name] = cls }
    @ObjCClassMethod("classForClassName:")
    static func classForClassName(_ name: String) -> UnsafeMutableRawPointer? { Unarchivers.classes[name] }
    @ObjCMethod("setClass:forClassName:")
    func setClass(_ cls: UnsafeMutableRawPointer?, forClassName name: String) { storage?.classes[name] = cls }
    @ObjCMethod("classForClassName:")
    func classForClassName(_ name: String) -> UnsafeMutableRawPointer? { storage?.classes[name] }

    /// The root object, unchecked; nil if the data is not an archive.
    @ObjCClassMethod("unarchiveObjectWithData:")
    static func unarchive(_ data: ObjCObject?) -> ObjCObject? {
        guard let unarchiver = Unarchivers.make(data?.objcObject) else { return nil }
        return Unarchivers.storage(unarchiver)?.root().map(ObjCObject.init)
    }

    /// The root object of the archive in a file, or nil if the file cannot
    /// be read.
    @ObjCClassMethod("unarchiveObjectWithFile:")
    static func unarchive(file path: String?) -> ObjCObject? {
        guard let path, let data = try? Data(contentsOf: URL(filePath: path)) else { return nil }
        return unarchive(DataObjects.owned(DataStorage(data)))
    }

    /// The root object, unchecked, or nil and the error.
    @ObjCClassMethod("unarchiveTopLevelObjectWithData:error:")
    static func unarchiveTopLevel(_ data: ObjCObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        Unarchivers.unarchive(data?.objcObject, classes: nil, secure: false, error: error)
    }

    /// The root object decoded securely as one of the class.
    @ObjCClassMethod("unarchivedObjectOfClass:fromData:error:")
    static func unarchived(ofClass cls: UnsafeMutableRawPointer?, from data: ObjCObject?,
                           error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        Unarchivers.unarchive(data?.objcObject, classes: [cls].compactMap { $0 }, secure: true, error: error)
    }

    @ObjCClassMethod("unarchivedObjectOfClasses:fromData:error:")
    static func unarchived(ofClasses classes: UnsafeMutableRawPointer?, from data: ObjCObject?,
                           error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        Unarchivers.unarchive(data?.objcObject, classes: Unarchivers.classList(classes), secure: true, error: error)
    }

    @ObjCClassMethod("unarchivedArrayOfObjectsOfClass:fromData:error:")
    static func unarchivedArray(ofClass cls: UnsafeMutableRawPointer?, from data: ObjCObject?,
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        unarchivedArray([cls].compactMap { $0 }, data?.objcObject, error)
    }

    @ObjCClassMethod("unarchivedArrayOfObjectsOfClasses:fromData:error:")
    static func unarchivedArray(ofClasses classes: UnsafeMutableRawPointer?, from data: ObjCObject?,
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        unarchivedArray(Unarchivers.classList(classes), data?.objcObject, error)
    }

    /// An array root of the classes; another root is error 4864.
    private static func unarchivedArray(_ classes: [id], _ data: id?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> id? {
        guard let array = Unarchivers.unarchive(data, classes: classes + [UnsafeMutableRawPointer(Arrays.arrayClass)], secure: true,
                                                error: error) else { return nil }
        guard ObjC.isKind(array, of: Arrays.arrayClass) else {
            error?.pointee = Coders.corrupt("The root object isn’t an array.")
            return nil
        }
        return array
    }

    @ObjCClassMethod("unarchivedDictionaryWithKeysOfClass:objectsOfClass:fromData:error:")
    static func unarchivedDictionary(keysOfClass keyClass: UnsafeMutableRawPointer?, objectsOfClass objectClass: UnsafeMutableRawPointer?,
                                     from data: ObjCObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        unarchivedDictionary([keyClass].compactMap { $0 }, [objectClass].compactMap { $0 }, data?.objcObject, error)
    }

    @ObjCClassMethod("unarchivedDictionaryWithKeysOfClasses:objectsOfClasses:fromData:error:")
    static func unarchivedDictionary(keysOfClasses keyClasses: UnsafeMutableRawPointer?, objectsOfClasses objectClasses: UnsafeMutableRawPointer?,
                                     from data: ObjCObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        unarchivedDictionary(Unarchivers.classList(keyClasses), Unarchivers.classList(objectClasses), data?.objcObject, error)
    }

    /// A dictionary root whose keys and objects are each of their classes;
    /// anything else is error 4864.
    private static func unarchivedDictionary(_ keys: [id], _ objects: [id], _ data: id?,
                                             _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> id? {
        let classes: [id] = keys + objects + [UnsafeMutableRawPointer(Dictionaries.dictionaryClass!)]
        guard let dictionary = Unarchivers.unarchive(data, classes: classes, secure: true, error: error) else { return nil }
        guard ObjC.isKind(dictionary, of: Dictionaries.dictionaryClass),
              Dictionaries.entries(dictionary).allSatisfy({ Coders.isKind($0.key, of: keys) && Coders.isKind($0.value, of: objects) }) else {
            error?.pointee = Coders.corrupt("The root object isn’t a dictionary of the expected classes.")
            return nil
        }
        return dictionary
    }

    /// Securely, failures setting the error.
    @ObjCMethod("initForReadingFromData:error:")
    func initialize(data: ObjCObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self? {
        guard let storage = UnarchiverStorage(Array(DataObjects.data(data?.objcObject))) else {
            error?.pointee = Unarchivers.error().objCReturnValue()
            return nil
        }
        storage.unarchiver = objcObject
        storage.requiresSecureCoding = true
        storage.failurePolicy = 1
        Storage.set(objcObject, storage)
        return self
    }

    /// Not securely, failures raising.
    @ObjCMethod("initForReadingWithData:")
    func initialize(data: ObjCObject?) -> Self? {
        guard let storage = UnarchiverStorage(Array(DataObjects.data(data?.objcObject))) else { return nil }
        storage.unarchiver = objcObject
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Unarchivers.unarchiverClass)
    }

    @ObjCMethod("allowsKeyedCoding") override func allowsKeyedCoding() -> Bool { true }
    @ObjCMethod("requiresSecureCoding") override func requiresSecureCoding() -> Bool { storage?.requiresSecureCoding ?? false }
    @ObjCMethod("setRequiresSecureCoding:") func setRequiresSecureCoding(_ value: Bool) { storage?.requiresSecureCoding = value }
    /// Tells the delegate decoding is done, once.
    @ObjCMethod("finishDecoding") func finishDecoding() { storage?.finish() }
    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { storage?.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { storage?.delegate = delegate }

    /// Why decoding failed, if it did: nil until -failWithError: is sent.
    @ObjCMethod("error") func error() -> id? { storage?.error }
    /// With the raise policy outside a top-level decode, an exception;
    /// otherwise the first error is kept.
    @ObjCMethod("failWithError:")
    func fail(with error: id?) { storage?.fail(with: error) }
    @ObjCMethod("decodingFailurePolicy") func decodingFailurePolicy() -> Int { storage?.failurePolicy ?? 0 }
    @ObjCMethod("setDecodingFailurePolicy:") func setDecodingFailurePolicy(_ policy: Int) { storage?.failurePolicy = policy }

    /// The classes being decoded, as a set: those of the innermost decode
    /// of classes in progress.
    @ObjCMethod("allowedClasses")
    func allowedClasses() -> UnsafeMutableRawPointer? { storage?.allowedClasses.map { Sets.autoreleased($0) } }

    @ObjCMethod("containsValueForKey:")
    func containsValue(forKey key: String) -> Bool { storage?.field(key) != nil }

    /// Securely at the top level, only a value kept as itself (a string,
    /// number or data); inside an object's -initWithCoder:, any object.
    @ObjCMethod("decodeObjectForKey:")
    func decodeObject(forKey key: String) -> ObjCObject? {
        storage?.decode(key, classes: nil).map(ObjCObject.init)
    }

    @ObjCMethod("decodeObjectOfClass:forKey:")
    func decodeObject(ofClass cls: UnsafeMutableRawPointer?, forKey key: String) -> ObjCObject? {
        storage?.decode(key, classes: [cls].compactMap { $0 }).map(ObjCObject.init)
    }

    @ObjCMethod("decodeObjectOfClasses:forKey:")
    func decodeObject(ofClasses classes: UnsafeMutableRawPointer?, forKey key: String) -> ObjCObject? {
        storage?.decode(key, classes: classes.map { Unarchivers.classList($0) }).map(ObjCObject.init)
    }

    /// The object, or nil and the error, which the unarchiver gives up.
    @ObjCMethod("decodeTopLevelObjectOfClasses:forKey:error:")
    func decodeTopLevelObject(ofClasses classes: UnsafeMutableRawPointer?, forKey key: String,
                              error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        storage?.decodeTopLevel(key, classes: classes.map { Unarchivers.classList($0) }, error: error).map(ObjCObject.init)
    }

    /// The next unkeyed object, as a top-level decode.
    @ObjCMethod("decodeTopLevelObjectAndReturnError:")
    func decodeTopLevelObject(error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        storage?.decodeTopLevel(nextKey(), classes: nil, error: error).map(ObjCObject.init)
    }

    // MARK: Unkeyed coding, under generated keys

    private func nextKey() -> String {
        guard let storage else { return "$0" }
        defer { storage.unkeyed += 1 }
        return "$\(storage.unkeyed)"
    }

    @ObjCMethod("decodeObject") func decodeNextObject() -> ObjCObject? { decodeObject(forKey: nextKey()) }

    @ObjCMethod("decodeValueOfObjCType:at:")
    func decodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeMutableRawPointer?) {
        guard let type, let address else { return }
        let encoding = ArchiveTypes.bare(Array(UnsafeRawBufferPointer(start: type, count: strlen(type))))
        if encoding.first == UInt8(ascii: "[") {
            let (count, element) = ArchiveTypes.array(encoding)
            decodeArray(element, count: count, at: address)
            return
        }
        store(storage?.field(nextKey()), encoding, at: address)
    }

    /// A value as -encodeValueOfObjCType:at: archived it, into `address`.
    private func store(_ value: ArchiveValue?, _ type: [UInt8], at address: UnsafeMutableRawPointer) {
        var integer: Int64 = 0, real = 0.0
        switch value {
        case .integer(let number)?: (integer, real) = (number, Double(number))
        case .real(let number)?: (integer, real) = (Int64(number), number)
        case .bool(let flag)?: (integer, real) = (flag ? 1 : 0, flag ? 1 : 0)
        default: break
        }
        switch type.first {
        case UInt8(ascii: "c"): address.storeBytes(of: Int8(truncatingIfNeeded: integer), as: Int8.self)
        case UInt8(ascii: "C"), UInt8(ascii: "B"): address.storeBytes(of: UInt8(truncatingIfNeeded: integer), as: UInt8.self)
        case UInt8(ascii: "s"): address.storeBytes(of: Int16(truncatingIfNeeded: integer), as: Int16.self)
        case UInt8(ascii: "S"): address.storeBytes(of: UInt16(truncatingIfNeeded: integer), as: UInt16.self)
        case UInt8(ascii: "i"): address.storeBytes(of: Int32(truncatingIfNeeded: integer), as: Int32.self)
        case UInt8(ascii: "I"): address.storeBytes(of: UInt32(truncatingIfNeeded: integer), as: UInt32.self)
        case UInt8(ascii: "l"), UInt8(ascii: "L"): address.storeBytes(of: Int32(truncatingIfNeeded: integer), as: Int32.self)
        case UInt8(ascii: "q"), UInt8(ascii: "Q"): address.storeBytes(of: integer, as: Int64.self)
        case UInt8(ascii: "f"): address.storeBytes(of: Float(real), as: Float.self)
        case UInt8(ascii: "d"): address.storeBytes(of: real, as: Double.self)
        case UInt8(ascii: "@"):
            // Returned retained, as -decodeValueOfObjCType:at: gives objects.
            let object = storage?.object(value)
            address.storeBytes(of: ObjC.retain(object), as: UnsafeMutableRawPointer?.self)
        case UInt8(ascii: "*"):
            let string = Strings.value(of: storage?.object(value))
            address.storeBytes(of: string.map { UnsafePointer(strdup($0)!) }, as: UnsafePointer<CChar>?.self)
        default:
            foundationFatal("-[NSKeyedUnarchiver decodeValueOfObjCType:at:]: unsupported type \(String(decoding: type, as: UTF8.self))")
        }
    }

    /// A C array as -encodeArrayOfObjCType:count:at: archives it, an
    /// _NSKeyedCoderOldStyleArray of its elements under "$0", "$1"….
    private func decodeArray(_ element: [UInt8], count: Int, at address: UnsafeMutableRawPointer) {
        guard let storage, let fields = storage.archived(storage.field(nextKey())) else { return }
        let size = ArchiveTypes.layout(element).size
        let archived: Int
        if case .integer(let stored)? = fields["NS.count"] { archived = Int(stored) } else { archived = 0 }
        for index in 0..<min(count, archived) {
            store(fields["$\(index)"], element, at: address + index * size)
        }
    }

    @ObjCMethod("decodeArrayOfObjCType:count:at:")
    func decodeArray(ofObjCType type: UnsafePointer<CChar>?, count: UInt, at address: UnsafeMutableRawPointer?) {
        guard let type, let address else { return }
        decodeArray(ArchiveTypes.bare(Array(UnsafeRawBufferPointer(start: type, count: strlen(type)))), count: Int(count), at: address)
    }

    /// Bytes -encodeBytes:length: archived, kept while the autorelease
    /// pool is.
    @ObjCMethod("decodeBytesWithReturnedLength:")
    func decodeBytes(returnedLength length: UnsafeMutablePointer<UInt>?) -> UnsafeRawPointer? {
        decodeBytes(forKey: nextKey(), length: length)
    }

    @ObjCMethod("decodeDataObject")
    func decodeDataObject() -> ObjCObject? { decodeNextObject() }

    @ObjCMethod("decodeBytesForKey:returnedLength:")
    func decodeBytes(forKey key: String, length: UnsafeMutablePointer<UInt>?) -> UnsafeRawPointer? {
        guard case .data(let bytes)? = storage?.field(key) else {
            length?.pointee = 0
            return nil
        }
        length?.pointee = UInt(bytes.count)
        let data = DataObjects.autoreleased(Data(bytes))
        return ObjC.send(data, ObjC.selector("bytes")).map { UnsafeRawPointer($0) }
    }

    private func number(_ key: String) -> (Int64, Double)? {
        switch storage?.field(key) {
        case .integer(let value)?: return (value, Double(value))
        case .real(let value)?: return (Int64(value), value)
        case .bool(let value)?: return (value ? 1 : 0, value ? 1 : 0)
        default: return nil
        }
    }

    @ObjCMethod("decodeBoolForKey:") func decodeBool(forKey key: String) -> Bool { (number(key)?.0 ?? 0) != 0 }
    @ObjCMethod("decodeIntegerForKey:") func decodeInteger(forKey key: String) -> Int { Int(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeIntForKey:") func decodeInt(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeInt32ForKey:") func decodeInt32(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeInt64ForKey:") func decodeInt64(forKey key: String) -> Int64 { number(key)?.0 ?? 0 }
    @ObjCMethod("decodeDoubleForKey:") func decodeDouble(forKey key: String) -> Double { number(key)?.1 ?? 0 }
    @ObjCMethod("decodeFloatForKey:") func decodeFloat(forKey key: String) -> Float { Float(number(key)?.1 ?? 0) }
}
