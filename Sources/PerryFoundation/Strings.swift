import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An NSString's contents.
final class StringStorage {
    /// Changes only for NSMutableString.
    var value: String {
        didSet {
            free(cString)
            cString = nil
        }
    }
    private var cString: UnsafeMutablePointer<CChar>?

    init(_ value: String) {
        self.value = value
    }

    deinit {
        free(cString)
    }

    /// UTF8String: valid as long as the string.
    var utf8: UnsafePointer<CChar> {
        if let cString { return UnsafePointer(cString) }
        let created = strdup(value)!
        cString = created
        return UnsafePointer(created)
    }
}

enum Strings {
    nonisolated(unsafe) static var stringClass: Class!
    nonisolated(unsafe) static var constantClass: Class!

    /// String literals: { isa, flags, characters, length }. Flag 0x10 marks
    /// UTF-16 characters; otherwise they are NUL-terminated ASCII.
    private static func constantValue(_ object: id) -> String {
        let flags = object.load(fromByteOffset: 8, as: UInt64.self)
        let characters = object.load(fromByteOffset: 16, as: UnsafeRawPointer?.self)
        let length = object.load(fromByteOffset: 24, as: Int.self)
        guard let characters, length > 0 else { return "" }
        if flags & 0x10 != 0 {
            return String(decoding: UnsafeBufferPointer(start: characters.assumingMemoryBound(to: UInt16.self), count: length),
                          as: UTF16.self)
        }
        return String(decoding: UnsafeBufferPointer(start: characters.assumingMemoryBound(to: UInt8.self), count: length),
                      as: UTF8.self)
    }

    /// The contents of an NSString, or nil if `object` is not one.
    static func value(of object: id?) -> String? {
        guard let object, ObjC.isKind(object, of: stringClass) else { return nil }
        if ObjC.objectGetClass(object) == constantClass {
            return constantValue(object)
        }
        return Storage.get(object, as: StringStorage.self)?.value ?? ""
    }

    /// UTF-16 literals have no C string; keep one per literal.
    nonisolated(unsafe) private static var literalUTF8: [UInt: StringStorage] = [:]

    static func utf8(_ object: id) -> UnsafePointer<CChar>? {
        if ObjC.objectGetClass(object) == constantClass {
            let flags = object.load(fromByteOffset: 8, as: UInt64.self)
            if flags & 0x10 == 0 {
                return object.load(fromByteOffset: 16, as: UnsafePointer<CChar>?.self)
            }
            let key = UInt(bitPattern: object)
            if let cached = literalUTF8[key] { return cached.utf8 }
            let storage = StringStorage(constantValue(object))
            literalUTF8[key] = storage
            return storage.utf8
        }
        return (Storage.get(object, as: StringStorage.self) ?? StringStorage("")).utf8
    }

    /// A new NSString, retained (+1).
    static func make(_ value: String) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(stringClass))!
        Storage.set(object, StringStorage(value))
        return object
    }

    /// A new autoreleased NSString, as convenience constructors return.
    static func autoreleased(_ value: String) -> id {
        ObjC.autorelease(make(value))!
    }

    /// FNV-1a over UTF-16, so equal strings hash equally in every process.
    static func hash(_ value: String) -> UInt {
        var hash: UInt = 0xcbf2_9ce4_8422_2325
        for unit in value.utf16 {
            hash = (hash ^ UInt(unit)) &* 0x100_0000_01b3
        }
        return hash
    }

    /// NSComparisonResult for a literal (code point) comparison.
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.unicodeScalars), right = Array(rhs.unicodeScalars)
        for (a, b) in zip(left, right) where a != b {
            return a.value < b.value ? -1 : 1
        }
        return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
    }

    static func install(superclass: Class) {
        let string = ClassDefinition(PERRY_CLASS_NSString, name: "NSString", superclass: superclass,
                                     StorageAllocation.self, NSStringMethods.self)
        stringClass = string.cls
        string.addMethod("stringWithFormat:", types: "@24@0:8@16",
                         implementation: variadicEntry(perry_imp_stringWithFormat), isClassMethod: true)
        string.addMethod("initWithFormat:", types: "@24@0:8@16",
                         implementation: variadicEntry(perry_imp_initWithFormat), isClassMethod: false)
        string.addMethod("stringByAppendingFormat:", types: "@24@0:8@16",
                         implementation: variadicEntry(perry_imp_stringByAppendingFormat), isClassMethod: false)

        // String literals: immortal, read in place.
        constantClass = ClassDefinition(PERRY_CLASS_NSConstantString, name: "__NSCFConstantString",
                                        superclass: string.cls, ImmortalMethods.self).cls
    }

    /// Leading integer, as -integerValue reads it ("42abc" is 42).
    static func integerPrefix(_ value: String) -> Int {
        value.withCString { strtol($0, nil, 10) }
    }
}

@ObjCImplementation
enum NSStringMethods {
    private static func value(_ object: id?) -> String { Strings.value(of: object) ?? "" }

    private static func set(_ object: id?, _ value: String) -> id? {
        if let object { Storage.set(object, StringStorage(value)) }
        return object
    }

    // MARK: Creating

    @ObjCClassMethod("string")
    static func string(_ cls: id?) -> id? { Strings.autoreleased("") }

    @ObjCClassMethod("stringWithString:")
    static func string(_ cls: id?, string other: id?) -> id? { Strings.autoreleased(value(other)) }

    @ObjCClassMethod("stringWithUTF8String:")
    static func string(_ cls: id?, utf8 bytes: UnsafePointer<CChar>?) -> id? {
        bytes.map { Strings.autoreleased(String(cString: $0)) }
    }

    @ObjCMethod("init")
    static func initialize(_ object: id?) -> id? { set(object, "") }

    @ObjCMethod("initWithString:")
    static func initialize(_ object: id?, string other: id?) -> id? { set(object, value(other)) }

    @ObjCMethod("initWithUTF8String:")
    static func initialize(_ object: id?, utf8 bytes: UnsafePointer<CChar>?) -> id? {
        guard let bytes else { return nil }
        return set(object, String(cString: bytes))
    }

    /// A Darwin va_list is a pointer to the argument slots.
    @ObjCMethod("initWithFormat:arguments:", types: "@32@0:8@16*24")
    static func initialize(_ object: id?, format: id?, arguments: UnsafeRawPointer?) -> id? {
        guard let arguments else { return object }
        var darwin = DarwinArguments(arguments)
        return set(object, Format.string(value(format), &darwin))
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ object: id?) {
        guard let object else { return }
        Storage.set(object, nil)
        ObjC.superDealloc(object, from: Strings.stringClass)
    }

    // MARK: Contents

    @ObjCMethod("length")
    static func length(_ object: id?) -> UInt { UInt(value(object).utf16.count) }

    @ObjCMethod("characterAtIndex:")
    static func character(_ object: id?, at index: UInt) -> UInt16 {
        let units = Array(value(object).utf16)
        guard Int(index) < units.count else {
            foundationFatal("-[NSString characterAtIndex:]: Range or index out of bounds")
        }
        return units[Int(index)]
    }

    @ObjCMethod("UTF8String")
    static func utf8String(_ object: id?) -> UnsafePointer<CChar>? { object.flatMap(Strings.utf8) }

    @ObjCMethod("description")
    static func description(_ object: id?) -> id? { object }

    @ObjCMethod("copy")
    static func copy(_ object: id?) -> id? { ObjC.retain(object) }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(object) }

    @ObjCMethod("mutableCopyWithZone:")
    static func mutableCopy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? {
        MutableStrings.make(value(object))
    }

    // MARK: Comparing

    @ObjCMethod("isEqual:")
    static func isEqual(_ object: id?, _ other: id?) -> Bool {
        object == other || Strings.value(of: other).map { $0 == value(object) } ?? false
    }

    @ObjCMethod("isEqualToString:")
    static func isEqual(_ object: id?, toString other: id?) -> Bool {
        object == other || value(object) == value(other)
    }

    @ObjCMethod("hash")
    static func hash(_ object: id?) -> UInt { Strings.hash(value(object)) }

    @ObjCMethod("compare:")
    static func compare(_ object: id?, _ other: id?) -> Int { Strings.compare(value(object), value(other)) }

    @ObjCMethod("hasPrefix:")
    static func hasPrefix(_ object: id?, _ other: id?) -> Bool { value(object).hasPrefix(value(other)) }

    @ObjCMethod("hasSuffix:")
    static func hasSuffix(_ object: id?, _ other: id?) -> Bool { value(object).hasSuffix(value(other)) }

    // MARK: Deriving

    @ObjCMethod("stringByAppendingString:")
    static func appending(_ object: id?, _ other: id?) -> id? {
        Strings.autoreleased(value(object) + value(other))
    }

    @ObjCMethod("uppercaseString")
    static func uppercased(_ object: id?) -> id? { Strings.autoreleased(value(object).uppercased()) }

    @ObjCMethod("lowercaseString")
    static func lowercased(_ object: id?) -> id? { Strings.autoreleased(value(object).lowercased()) }

    @ObjCMethod("integerValue")
    static func integerValue(_ object: id?) -> Int { Strings.integerPrefix(value(object)) }

    @ObjCMethod("intValue")
    static func intValue(_ object: id?) -> Int32 { Int32(truncatingIfNeeded: Strings.integerPrefix(value(object))) }

    @ObjCMethod("doubleValue")
    static func doubleValue(_ object: id?) -> Double { value(object).withCString { strtod($0, nil) } }
}

// MARK: - Variadic methods

@c
public func perry_foundation_stringWithFormat(_ cls: id?, _ cmd: SEL?, _ format: id?,
                                              _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return nil }
    var darwin = DarwinArguments(arguments)
    return Strings.autoreleased(Format.string(Strings.value(of: format) ?? "", &darwin))
}

@c
public func perry_foundation_initWithFormat(_ object: id?, _ cmd: SEL?, _ format: id?,
                                            _ arguments: UnsafeRawPointer?) -> id? {
    guard let object, let arguments else { return object }
    var darwin = DarwinArguments(arguments)
    Storage.set(object, StringStorage(Format.string(Strings.value(of: format) ?? "", &darwin)))
    return object
}

@c
public func perry_foundation_stringByAppendingFormat(_ object: id?, _ cmd: SEL?, _ format: id?,
                                                     _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return nil }
    var darwin = DarwinArguments(arguments)
    let suffix = Format.string(Strings.value(of: format) ?? "", &darwin)
    return Strings.autoreleased((Strings.value(of: object) ?? "") + suffix)
}
