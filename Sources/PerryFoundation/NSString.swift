import CPerryFoundation
import Glibc
import PerryObjCInterop
import Synchronization

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
        // Another library's subclass keeps its own characters, even when it
        // was made with NSString's -init.
        if let primitive = primitiveValue(of: object) {
            return primitive
        }
        return Storage.get(object, as: StringStorage.self)?.value ?? ""
    }

    nonisolated(unsafe) private static let lengthSelector = ObjC.selector("length")
    nonisolated(unsafe) private static let getCharactersSelector = ObjC.selector("getCharacters:range:")

    /// The contents of a string of a subclass this library does not
    /// define, such as Swift's bridged strings, which keep their own
    /// characters: through the primitive methods it overrides, as NSString
    /// subclasses do. Nil if it overrides none.
    private static func primitiveValue(of object: id) -> String? {
        let cls = ObjC.objectGetClass(object)
        guard ObjC.methodImplementation(cls, lengthSelector) != ObjC.methodImplementation(stringClass, lengthSelector) else {
            return nil
        }
        let length = Int(ObjC.sendUInt(object, lengthSelector))
        guard length > 0 else { return "" }
        typealias GetCharacters = @convention(c) (id?, SEL, UnsafeMutablePointer<UInt16>?, UInt, UInt) -> Void
        let units = [UInt16](unsafeUninitializedCapacity: length) { buffer, count in
            unsafeBitCast(ObjC.msgSend, to: GetCharacters.self)(object, getCharactersSelector, buffer.baseAddress, 0, UInt(length))
            count = length
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// UTF-16 literals have no C string; keep one per literal, made by
    /// whichever thread asks first.
    private static let literalUTF8 = Mutex<[UInt: StringStorage]>([:])

    static func utf8(_ object: id) -> UnsafePointer<CChar>? {
        if ObjC.objectGetClass(object) == constantClass {
            let flags = object.load(fromByteOffset: 8, as: UInt64.self)
            if flags & 0x10 == 0 {
                return object.load(fromByteOffset: 16, as: UnsafePointer<CChar>?.self)
            }
            let key = UInt(bitPattern: object)
            return literalUTF8.withLock { literals in
                if let cached = literals[key] { return cached.utf8 }
                let storage = StringStorage(constantValue(object))
                literals[key] = storage
                return storage.utf8
            }
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

    /// A new autoreleased string of `cls`: convenience constructors make
    /// their receiver's class, so +[NSMutableString string] is mutable.
    static func autoreleased(_ value: String, of cls: UnsafeMutableRawPointer?) -> id {
        guard let cls, let object = Storage.allocate(cls) else { return autoreleased(value) }
        Storage.set(object, StringStorage(value))
        return ObjC.autorelease(object)!
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


    /// Compares runs of digits by their value ("file9" before "file10").
    static func numericCompare(_ lhs: String, _ rhs: String) -> Int {
        var a = Array(lhs.unicodeScalars)[...], b = Array(rhs.unicodeScalars)[...]
        func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
        while let x = a.first, let y = b.first {
            if isDigit(x) && isDigit(y) {
                let left = a.prefix(while: isDigit), right = b.prefix(while: isDigit)
                let l = left.drop { $0 == "0" }, r = right.drop { $0 == "0" }
                if l.count != r.count { return l.count < r.count ? -1 : 1 }
                for (p, q) in zip(l, r) where p != q { return p.value < q.value ? -1 : 1 }
                a = a.dropFirst(left.count)
                b = b.dropFirst(right.count)
            } else {
                if x != y { return x.value < y.value ? -1 : 1 }
                a = a.dropFirst()
                b = b.dropFirst()
            }
        }
        return a.isEmpty && b.isEmpty ? 0 : (a.isEmpty ? -1 : 1)
    }

    /// Leading integer, as -integerValue reads it ("42abc" is 42).
    static func integerPrefix(_ value: String) -> Int {
        value.withCString { strtol($0, nil, 10) }
    }
}

/// NSString.
@ObjCClass("NSString")
public class NSString: NSObject {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSString__") func isNSString__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Strings.stringClass = cls.storage
        cls.addMethod("stringWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_stringWithFormat), isClassMethod: true)
        // Formatting isn't localized here, so it is stringWithFormat:.
        cls.addMethod("localizedStringWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_stringWithFormat), isClassMethod: true)
        cls.addMethod("initWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_initWithFormat), isClassMethod: false)
        cls.addMethod("stringByAppendingFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_stringByAppendingFormat), isClassMethod: false)
    }

    /// The receiver's contents.
    var value: String { Strings.value(of: objcObject) ?? "" }

    private func setValue(_ value: String) -> Self {
        Storage.set(objcObject, StringStorage(value))
        return self
    }

    // MARK: Creating

    /// Swift's standard library bridges a short ASCII string through this,
    /// for a tagged-pointer string; strings here are objects, which it takes
    /// as well. Returned retained, as its name says.
    @ObjCClassMethod("newTaggedNSStringWithASCIIBytes_:length_:")
    static func newTaggedString(_ cls: ObjCClass, bytes: UnsafePointer<UInt8>?, length: Int) -> UnsafeMutableRawPointer? {
        guard let bytes else { return nil }
        return Strings.make(String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self))
    }

    @ObjCClassMethod("string")
    static func empty(_ cls: ObjCClass) -> ObjCObject { ObjCObject(Strings.autoreleased("", of: cls.pointer)) }

    @ObjCClassMethod("stringWithString:")
    static func string(_ cls: ObjCClass, with other: String) -> ObjCObject {
        ObjCObject(Strings.autoreleased(other, of: cls.pointer))
    }

    @ObjCClassMethod("stringWithUTF8String:")
    static func string(_ cls: ObjCClass, utf8 bytes: UnsafePointer<CChar>?) -> ObjCObject? {
        bytes.map { ObjCObject(Strings.autoreleased(String(cString: $0), of: cls.pointer)) }
    }

    @ObjCMethod("init")
    func initialize() -> Self { setValue("") }

    @ObjCMethod("initWithString:")
    func initialize(string other: String) -> Self { setValue(other) }

    @ObjCMethod("initWithUTF8String:")
    func initialize(utf8 bytes: UnsafePointer<CChar>?) -> Self? { bytes.map { setValue(String(cString: $0)) } }

    /// NSStringEncoding; String's own conversion to NSString relies on this.
    @ObjCMethod("initWithBytes:length:encoding:")
    func initialize(bytes: UnsafeRawPointer?, length: UInt, encoding: UInt) -> Self? {
        StringEncoding.decode(UnsafeRawBufferPointer(start: bytes, count: Int(length)), encoding).map(setValue)
    }

    /// The bytes are copied, so the string frees them at once when it would
    /// own them. A string that cannot be made leaves them to the caller.
    @ObjCMethod("initWithBytesNoCopy:length:encoding:freeWhenDone:")
    func initialize(bytesNoCopy bytes: UnsafeMutableRawPointer?, length: UInt, encoding: UInt, freeWhenDone: Bool) -> Self? {
        guard let string = initialize(bytes: bytes, length: length, encoding: encoding) else { return nil }
        if freeWhenDone { free(bytes) }
        return string
    }

    /// A Darwin va_list is a pointer to the argument slots.
    @ObjCMethod("initWithFormat:arguments:", types: "@32@0:8@16*24")
    func initialize(format: String, arguments: UnsafeRawPointer?) -> Self {
        guard let arguments else { return setValue(format) }
        var darwin = DarwinArguments(arguments)
        return setValue(Format.string(format, &darwin))
    }

    /// Formats as initWithFormat:arguments: does; the locale is not applied.
    @ObjCMethod("initWithFormat:locale:arguments:", types: "@40@0:8@16@24*32")
    func initialize(format: String, locale: ObjCObject?, arguments: UnsafeRawPointer?) -> Self {
        initialize(format: format, arguments: arguments)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Strings.stringClass)
    }

    // MARK: Contents

    @ObjCMethod("length")
    func length() -> UInt { UInt(value.utf16.count) }

    @ObjCMethod("characterAtIndex:")
    func character(at index: UInt) -> UInt16 {
        let units = Array(value.utf16)
        guard Int(index) < units.count else {
            foundationFatal("-[NSString characterAtIndex:]: Range or index out of bounds")
        }
        return units[Int(index)]
    }

    @ObjCMethod("UTF8String")
    func utf8String() -> UnsafePointer<CChar>? { Strings.utf8(objcObject) }

    @ObjCMethod("description")
    func description() -> NSString { self }

    @ObjCMethod("copy")
    func copy() -> NSString { self }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSString { self }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> ObjCObject {
        ObjCObject(objCOwned: MutableStrings.make(value))
    }

    // MARK: Comparing

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.objcObject == objcObject || Strings.value(of: other.objcObject) == value
    }

    @ObjCMethod("isEqualToString:")
    func isEqual(toString other: String?) -> Bool { other == value }

    @ObjCMethod("hash")
    func hash() -> UInt { Strings.hash(value) }

    @ObjCMethod("compare:")
    func compare(_ other: String) -> Int { Strings.compare(value, other) }

    @ObjCMethod("hasPrefix:")
    func hasPrefix(_ prefix: String) -> Bool { value.hasPrefix(prefix) }

    @ObjCMethod("hasSuffix:")
    func hasSuffix(_ suffix: String) -> Bool { value.hasSuffix(suffix) }

    // MARK: Deriving

    @ObjCMethod("stringByAppendingString:")
    func appending(_ other: String) -> String { value + other }

    /// Cut or padded to `length` UTF-16 units, the pad repeating from
    /// `start`, as Foundation's.
    @ObjCMethod("stringByPaddingToLength:withString:startingAtIndex:")
    func padding(toLength length: UInt, with pad: String, startingAt start: UInt) -> String {
        var units = Array(value.utf16)
        if units.count >= Int(length) { return String(decoding: units.prefix(Int(length)), as: UTF16.self) }
        let padUnits = Array(pad.utf16)
        guard !padUnits.isEmpty else { return value }
        var index = Int(start) % padUnits.count
        while units.count < Int(length) {
            units.append(padUnits[index])
            index = (index + 1) % padUnits.count
        }
        return String(decoding: units, as: UTF16.self)
    }

    @ObjCMethod("uppercaseString")
    func uppercased() -> String { value.uppercased() }

    @ObjCMethod("lowercaseString")
    func lowercased() -> String { value.lowercased() }

    @ObjCMethod("integerValue")
    func integerValue() -> Int { Strings.integerPrefix(value) }

    @ObjCMethod("intValue")
    func intValue() -> Int32 { Int32(truncatingIfNeeded: Strings.integerPrefix(value)) }

    @ObjCMethod("doubleValue")
    func doubleValue() -> Double { value.withCString { strtod($0, nil) } }
}

/// String literals: { isa, flags, characters, length }, read in place.
@ObjCClass("__NSCFConstantString")
final class NSCFConstantString: NSString {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Strings.constantClass = cls.markingStatic().storage
    }
}

// MARK: - Variadic methods

@c
public func perry_foundation_stringWithFormat(_ cls: id?, _ cmd: SEL?, _ format: id?,
                                              _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return nil }
    var darwin = DarwinArguments(arguments)
    return Strings.autoreleased(Format.string(Strings.value(of: format) ?? "", &darwin), of: cls)
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
