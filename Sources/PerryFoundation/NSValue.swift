import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSValue: a copy of a C value, with its Objective-C type encoding.

/// An NSValue's bytes and type.
final class ValueStorage {
    let bytes: [UInt8]
    let type: String
    /// objCType: valid as long as the value.
    let cType: UnsafeMutablePointer<CChar>

    init(bytes: [UInt8], type: String) {
        self.bytes = bytes
        self.type = type
        cType = strdup(type)
    }

    deinit {
        free(cType)
    }
}

enum Values {
    nonisolated(unsafe) static var valueClass: Class!

    static func storage(_ object: id?) -> ValueStorage? {
        Storage.get(object, as: ValueStorage.self)
    }

    /// A new value of `cls` copying `size` bytes, +1.
    static func make(_ cls: UnsafeMutableRawPointer, bytes: UnsafeRawPointer?, type: String) -> id? {
        guard let size = TypeEncoding.size(of: type) else {
            foundationFatal("+[NSValue valueWithBytes:objCType:] cannot handle type encoding '\(type)'")
        }
        let copied = bytes.map { Array(UnsafeRawBufferPointer(start: $0, count: size)) } ?? Array(repeating: 0, count: size)
        guard let object = Storage.allocate(cls) else { return nil }
        Storage.set(object, ValueStorage(bytes: copied, type: type))
        return object
    }
}

/// Sizes of Objective-C type encodings, laid out as C lays out the types on
/// arm64 (pointers are a word in a 32-bit program): "i" is 4 bytes, "{_NSRange=QQ}" 16, "[4c]" 4.
enum TypeEncoding {
    static func size(of encoding: String) -> Int? {
        var parser = Parser(bytes: Array(encoding.utf8))
        guard let (size, _) = parser.type(), parser.index == parser.bytes.count else { return nil }
        return size
    }

    struct Parser {
        let bytes: [UInt8]
        var index = 0

        /// What an object, a class, a selector or a pointer takes.
        static let word = MemoryLayout<UnsafeRawPointer>.size

        private var current: Character? { index < bytes.count ? Character(UnicodeScalar(bytes[index])) : nil }

        private mutating func number() -> Int {
            var value = 0
            while let c = current, let digit = c.wholeNumberValue {
                value = value * 10 + digit
                index += 1
            }
            return value
        }

        private static func align(_ value: Int, _ alignment: Int) -> Int {
            (value + alignment - 1) / alignment * alignment
        }

        /// One type: its size and alignment.
        mutating func type() -> (Int, Int)? {
            // Qualifiers: const, in, inout, out, bycopy, byref, oneway, atomic.
            while let c = current, "rnNoORVAj".contains(c) { index += 1 }
            guard let c = current else { return nil }
            index += 1
            switch c {
            case "c", "C", "B": return (1, 1)
            case "s", "S": return (2, 2)
            case "i", "I", "l", "L", "f": return (4, 4)
            case "q", "Q", "d", "D": return (8, 8)
            case "*", "#", ":": return (Self.word, Self.word)
            case "v": return (0, 1)
            case "@":
                if current == "?" {
                    index += 1                          // a block
                } else if current == "\"" {
                    index += 1                          // @"ClassName"
                    while let c = current, c != "\"" { index += 1 }
                    index += 1
                }
                return (Self.word, Self.word)
            case "^":
                // A pointer to any type; only the pointee needs skipping.
                guard type() != nil || current == "?" else { return nil }
                if current == "?" { index += 1 }
                return (Self.word, Self.word)
            case "?":
                return (0, 1)
            case "[":
                let count = number()
                guard let (size, alignment) = type(), current == "]" else { return nil }
                index += 1
                return (count * size, alignment)
            case "{", "(":
                let close: Character = c == "{" ? "}" : ")"
                // The tag name, then "=" and the members, which may be absent.
                while let c = current, c != "=", c != close { index += 1 }
                var size = 0, alignment = 1
                if current == "=" {
                    index += 1
                    // A struct lays its members out in order; a union overlaps them.
                    while current != close, current != nil {
                        guard let (memberSize, memberAlignment) = type() else { return nil }
                        alignment = max(alignment, memberAlignment)
                        size = close == ")" ? max(size, memberSize) : Self.align(size, memberAlignment) + memberSize
                    }
                }
                guard current == close else { return nil }
                index += 1
                return (Self.align(size, alignment), alignment)
            case "b":
                // A bit-field: counted as whole bytes.
                let bits = number()
                return ((bits + 7) / 8, 1)
            default:
                return nil
            }
        }
    }
}

/// NSValue.
@ObjCClass("NSValue")
public class NSValue: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSValue__") func isNSValue__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Values.valueClass = cls.storage
    }

    private var storage: ValueStorage? { Values.storage(objcObject) }

    @ObjCClassMethod("valueWithBytes:objCType:")
    static func value(_ cls: ObjCClass, bytes: UnsafeRawPointer?, objCType type: UnsafePointer<CChar>?) -> NSValue? {
        Values.make(cls.pointer, bytes: bytes, type: type.map { String(cString: $0) } ?? "").map(NSValue.init(objCOwned:))
    }

    @ObjCClassMethod("value:withObjCType:")
    static func value(_ cls: ObjCClass, _ bytes: UnsafeRawPointer?, withObjCType type: UnsafePointer<CChar>?) -> NSValue? {
        value(cls, bytes: bytes, objCType: type)
    }

    @ObjCMethod("initWithBytes:objCType:")
    func initialize(bytes: UnsafeRawPointer?, objCType type: UnsafePointer<CChar>?) -> Self {
        let type = type.map { String(cString: $0) } ?? ""
        guard let size = TypeEncoding.size(of: type) else {
            foundationFatal("-[NSValue initWithBytes:objCType:] cannot handle type encoding '\(type)'")
        }
        let copied = bytes.map { Array(UnsafeRawBufferPointer(start: $0, count: size)) } ?? Array(repeating: 0, count: size)
        Storage.set(objcObject, ValueStorage(bytes: copied, type: type))
        return self
    }

    @ObjCClassMethod("valueWithPointer:")
    static func value(_ cls: ObjCClass, pointer: UnsafeRawPointer?) -> NSValue? {
        var pointer = pointer
        return value(cls, bytes: &pointer, objCType: "^v")
    }

    @ObjCClassMethod("valueWithNonretainedObject:")
    static func value(_ cls: ObjCClass, nonretainedObject object: UnsafeMutableRawPointer?) -> NSValue? {
        var object = object
        return value(cls, bytes: &object, objCType: "@")
    }

    @ObjCClassMethod("valueWithRange:")
    static func value(_ cls: ObjCClass, range: NSRange) -> NSValue? {
        var range = range
        return value(cls, bytes: &range, objCType: NSRange.objCTypeEncoding)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Values.valueClass)
    }

    @ObjCMethod("objCType") func objCType() -> UnsafePointer<CChar>? { storage.map { UnsafePointer($0.cType) } }

    @ObjCMethod("getValue:")
    func getValue(_ buffer: UnsafeMutableRawPointer?) {
        guard let storage, let buffer else { return }
        storage.bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    }

    /// Copies the value if `size` is its size, as Foundation requires.
    @ObjCMethod("getValue:size:")
    func getValue(_ buffer: UnsafeMutableRawPointer?, size: UInt) {
        guard let storage else { return }
        guard Int(size) == storage.bytes.count else {
            foundationFatal("-[NSValue getValue:size:]: size \(size) does not match the value's \(storage.bytes.count)")
        }
        getValue(buffer)
    }

    private func load<Value>(_ type: Value.Type) -> Value? {
        guard let storage, storage.bytes.count >= MemoryLayout<Value>.size else { return nil }
        return storage.bytes.withUnsafeBytes { $0.loadUnaligned(as: Value.self) }
    }

    @ObjCMethod("pointerValue") func pointerValue() -> UnsafeMutableRawPointer? { load(UnsafeMutableRawPointer?.self) ?? nil }

    @ObjCMethod("nonretainedObjectValue")
    func nonretainedObjectValue() -> UnsafeMutableRawPointer? { load(UnsafeMutableRawPointer?.self) ?? nil }

    @ObjCMethod("rangeValue") func rangeValue() -> NSRange { load(NSRange.self) ?? NSRange(location: 0, length: 0) }

    @ObjCMethod("isEqualToValue:")
    func isEqual(toValue other: NSValue?) -> Bool {
        guard let other else { return false }
        guard let a = storage, let b = Values.storage(other.objcObject) else { return other.objcObject == objcObject }
        return a.type == b.type && a.bytes == b.bytes
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other, other.is(NSValue.self) else { return false }
        return isEqual(toValue: other.unsafeCast(to: NSValue.self))
    }

    @ObjCMethod("hash")
    func hash() -> UInt {
        storage?.bytes.reduce(UInt(5381)) { ($0 &* 33) &+ UInt($1) } ?? 0
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSValue { self }

    /// "NSRange: {1, 2}" for ranges; otherwise the bytes as NSData
    /// describes them.
    @ObjCMethod("description")
    func description() -> String {
        guard let storage else { return "" }
        if storage.type == NSRange.objCTypeEncoding, let range = load(NSRange.self) {
            return "NSRange: {\(range.location), \(range.length)}"
        }
        return DataObjects.description(Data(storage.bytes))
    }
}
