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
            let raw = UInt64(truncatingIfNeeded: number(at + 1, min(size, 8)))
            return .integer(size == 8 ? Int64(bitPattern: raw) : Int64(raw))
        case 0x2:
            let size = 1 << Int(marker & 0x0f)
            let raw = UInt64(truncatingIfNeeded: number(at + 1, size))
            return .real(size == 4 ? Double(Float(bitPattern: UInt32(raw))) : Double(bitPattern: raw))
        case 0x3:
            return .date(Double(bitPattern: UInt64(truncatingIfNeeded: number(at + 1, 8))))
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

    init?(_ data: [UInt8]) {
        guard let (value, _) = PropertyLists.parse(data), case .dictionary(let root) = value,
              case .array(let objects)? = root["$objects"], case .dictionary(let top)? = root["$top"] else { return nil }
        self.objects = objects
        self.top = top
    }

    deinit {
        for object in decoded.values { ObjC.release(object) }
    }

    /// The current object's (or the top level's) value for a key.
    func field(_ key: String) -> ArchiveValue? {
        (stack.last ?? top)[key]
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
        guard let value else { return nil }
        switch value {
        case .uid(let index): return object(at: index)
        default: return plain(value)
        }
    }

    private func object(at index: Int) -> id? {
        if index == 0 { return nil }                        // "$null"
        if let done = decoded[index] { return done }
        guard index < objects.count else { return nil }
        guard case .dictionary(let archived) = objects[index] else {
            let value = plain(objects[index])
            if let value { decoded[index] = ObjC.retain(value) }
            return value
        }
        let names = classNames(archived)
        if let builtIn = foundationObject(names, archived) {
            decoded[index] = ObjC.retain(builtIn)
            return builtIn
        }
        // Any other class: the first in the hierarchy that is registered.
        guard let cls = names.lazy.compactMap({ name in name.withCString { ObjC.getClass($0) } }).first else {
            foundationFatal("*** -[NSKeyedUnarchiver decodeObjectForKey:]: cannot decode object of class (\(names.first ?? "?"))")
        }
        guard let allocated = ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")) else { return nil }
        decoded[index] = allocated
        stack.append(archived)
        let result = ObjC.send(allocated, ObjC.selector("initWithCoder:"), unarchiver)
        stack.removeLast()
        if let result {
            if result != allocated { decoded[index] = result }
        } else {
            decoded[index] = nil
        }
        return result
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
            if case .data(let bytes)? = archived["NS.data"] { return DataObjects.autoreleased(Data(bytes)) }
            return DataObjects.autoreleased(Data())
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
}

enum Unarchivers {
    nonisolated(unsafe) static var unarchiverClass: Class!

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
}

/// NSKeyedUnarchiver.
@ObjCClass("NSKeyedUnarchiver")
public class NSKeyedUnarchiver: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Unarchivers.unarchiverClass = cls.storage
    }

    private var storage: UnarchiverStorage? { Unarchivers.storage(objcObject) }

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

    @ObjCClassMethod("unarchiveTopLevelObjectWithData:error:")
    static func unarchiveTopLevel(_ data: ObjCObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        guard let object = unarchive(data) else {
            error?.pointee = Unarchivers.error().objCReturnValue()
            return nil
        }
        return object
    }

    @ObjCClassMethod("unarchivedObjectOfClass:fromData:error:")
    static func unarchived(ofClass cls: ObjCClass?, from data: ObjCObject?,
                           error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        checked(unarchiveTopLevel(data, error: error), [cls?.pointer].compactMap { $0 }, error: error)
    }

    /// The object if it is one of `classes`; otherwise nil and error 4864.
    private static func checked(_ object: ObjCObject?, _ classes: [UnsafeMutableRawPointer],
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        guard let object else { return nil }
        if classes.contains(where: { ObjC.isKind(object.objcObject, of: $0.assumingMemoryBound(to: perry_class_storage.self)) }) { return object }
        error?.pointee = Unarchivers.error().objCReturnValue()
        return nil
    }

    @ObjCClassMethod("unarchivedObjectOfClasses:fromData:error:")
    static func unarchived(ofClasses classes: ObjCObject?, from data: ObjCObject?,
                           error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        let allowed = classes.map { Sets.elements($0.objcObject) } ?? []
        return checked(unarchiveTopLevel(data, error: error), allowed, error: error)
    }

    @ObjCMethod("initForReadingFromData:error:")
    func initialize(data: ObjCObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self? {
        guard let storage = UnarchiverStorage(Array(DataObjects.data(data?.objcObject))) else {
            error?.pointee = Unarchivers.error().objCReturnValue()
            return nil
        }
        storage.unarchiver = objcObject
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("initForReadingWithData:")
    func initialize(data: ObjCObject?) -> Self? { initialize(data: data, error: nil) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Unarchivers.unarchiverClass)
    }

    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { true }
    @ObjCMethod("requiresSecureCoding") func requiresSecureCoding() -> Bool { storage?.requiresSecureCoding ?? false }
    @ObjCMethod("setRequiresSecureCoding:") func setRequiresSecureCoding(_ value: Bool) { storage?.requiresSecureCoding = value }
    @ObjCMethod("finishDecoding") func finishDecoding() {}

    @ObjCMethod("containsValueForKey:")
    func containsValue(forKey key: String) -> Bool { storage?.field(key) != nil }

    @ObjCMethod("decodeObjectForKey:")
    func decodeObject(forKey key: String) -> ObjCObject? {
        storage.flatMap { $0.object($0.field(key)) }.map(ObjCObject.init)
    }

    // MARK: Unkeyed coding, under generated keys

    private func nextKey() -> String {
        guard let storage else { return "$0" }
        defer { storage.unkeyed += 1 }
        return "$\(storage.unkeyed)"
    }

    @ObjCMethod("decodeObject") func decodeObject() -> ObjCObject? { decodeObject(forKey: nextKey()) }

    @ObjCMethod("decodeValueOfObjCType:at:")
    func decodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeMutableRawPointer?) {
        guard let type, let address else { return }
        let key = nextKey()
        let (integer, real) = number(key) ?? (0, 0)
        switch UInt8(bitPattern: type.pointee) {
        case UInt8(ascii: "c"): address.storeBytes(of: Int8(truncatingIfNeeded: integer), as: Int8.self)
        case UInt8(ascii: "C"), UInt8(ascii: "B"): address.storeBytes(of: UInt8(truncatingIfNeeded: integer), as: UInt8.self)
        case UInt8(ascii: "s"): address.storeBytes(of: Int16(truncatingIfNeeded: integer), as: Int16.self)
        case UInt8(ascii: "S"): address.storeBytes(of: UInt16(truncatingIfNeeded: integer), as: UInt16.self)
        case UInt8(ascii: "i"): address.storeBytes(of: Int32(truncatingIfNeeded: integer), as: Int32.self)
        case UInt8(ascii: "I"): address.storeBytes(of: UInt32(truncatingIfNeeded: integer), as: UInt32.self)
        case UInt8(ascii: "l"), UInt8(ascii: "q"), UInt8(ascii: "L"), UInt8(ascii: "Q"): address.storeBytes(of: integer, as: Int64.self)
        case UInt8(ascii: "f"): address.storeBytes(of: Float(real), as: Float.self)
        case UInt8(ascii: "d"): address.storeBytes(of: real, as: Double.self)
        case UInt8(ascii: "@"):
            // Returned retained, as -decodeValueOfObjCType:at: gives objects.
            let object = decodeObject(forKey: key)?.id
            address.storeBytes(of: ObjC.retain(object), as: UnsafeMutableRawPointer?.self)
        case UInt8(ascii: "*"):
            let string = Strings.value(of: decodeObject(forKey: key)?.id)
            address.storeBytes(of: string.map { UnsafePointer(strdup($0)!) }, as: UnsafePointer<CChar>?.self)
        default:
            foundationFatal("-[NSKeyedUnarchiver decodeValueOfObjCType:at:]: unsupported type \(String(cString: type))")
        }
    }

    @ObjCMethod("decodeObjectOfClass:forKey:")
    func decodeObject(ofClass cls: ObjCClass?, forKey key: String) -> ObjCObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeObjectOfClasses:forKey:")
    func decodeObject(ofClasses classes: ObjCObject?, forKey key: String) -> ObjCObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeArrayOfObjectsOfClass:forKey:")
    func decodeArray(ofClass cls: ObjCClass?, forKey key: String) -> ObjCObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeArrayOfObjectsOfClasses:forKey:")
    func decodeArray(ofClasses classes: ObjCObject?, forKey key: String) -> ObjCObject? { decodeObject(forKey: key) }

    @ObjCMethod("decodeDictionaryWithKeysOfClass:objectsOfClass:forKey:")
    func decodeDictionary(keysOfClass keys: ObjCClass?, objectsOfClass objects: ObjCClass?, forKey key: String) -> ObjCObject? {
        decodeObject(forKey: key)
    }

    @ObjCMethod("decodeDictionaryWithKeysOfClasses:objectsOfClasses:forKey:")
    func decodeDictionary(keysOfClasses keys: ObjCObject?, objectsOfClasses objects: ObjCObject?, forKey key: String) -> ObjCObject? {
        decodeObject(forKey: key)
    }

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

    @ObjCMethod("decodeTopLevelObjectForKey:error:")
    func decodeTopLevelObject(forKey key: String, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> ObjCObject? {
        decodeObject(forKey: key)
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
    @ObjCMethod("decodeIntegerForKey:") func decodeInteger(forKey key: String) -> Int { Int(number(key)?.0 ?? 0) }
    @ObjCMethod("decodeIntForKey:") func decodeInt(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeInt32ForKey:") func decodeInt32(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: number(key)?.0 ?? 0) }
    @ObjCMethod("decodeInt64ForKey:") func decodeInt64(forKey key: String) -> Int64 { number(key)?.0 ?? 0 }
    @ObjCMethod("decodeDoubleForKey:") func decodeDouble(forKey key: String) -> Double { number(key)?.1 ?? 0 }
    @ObjCMethod("decodeFloatForKey:") func decodeFloat(forKey key: String) -> Float { Float(number(key)?.1 ?? 0) }
}
