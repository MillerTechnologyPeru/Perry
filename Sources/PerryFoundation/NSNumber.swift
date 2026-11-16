import CPerryFoundation
import Glibc
import PerryObjCInterop
import Synchronization

/// An NSNumber's value.
final class NumberStorage {
    enum Value {
        case signed(Int64)
        case unsigned(UInt64)
        case double(Double)
        case bool(Bool)
    }

    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var int64: Int64 {
        switch value {
        case .signed(let v): return v
        case .unsigned(let v): return Int64(truncatingIfNeeded: v)
        // As the processor converts: the nearest integer within range, and
        // 0 for NaN (Foundation does not trap on a double out of range).
        case .double(let v): return v.isNaN ? 0 : v >= 9.223372036854775807e18 ? Int64.max : v <= -9.223372036854775808e18 ? Int64.min : Int64(v)
        case .bool(let v): return v ? 1 : 0
        }
    }

    var double: Double {
        switch value {
        case .signed(let v): return Double(v)
        case .unsigned(let v): return Double(v)
        case .double(let v): return v
        case .bool(let v): return v ? 1 : 0
        }
    }

    var isFloatingPoint: Bool {
        if case .double = value { return true }
        return false
    }

    var description: String {
        switch value {
        case .signed(let v): return String(v)
        case .unsigned(let v): return String(v)
        case .bool(let v): return v ? "1" : "0"
        case .double(let v):
            // Foundation prints the shortest form that round-trips.
            if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
            var text = "\(v)"
            if text.hasSuffix(".0") { text.removeLast(2) }
            return text
        }
    }

    func compare(_ other: NumberStorage) -> Int {
        if !isFloatingPoint && !other.isFloatingPoint {
            if case .unsigned(let a) = value, case .unsigned(let b) = other.value {
                return a < b ? -1 : (a == b ? 0 : 1)
            }
            let a = int64, b = other.int64
            return a < b ? -1 : (a == b ? 0 : 1)
        }
        let a = double, b = other.double
        return a < b ? -1 : (a == b ? 0 : 1)
    }
}

/// The type encodings -objCType returns, which live as long as the process.
enum NumberTypes {
    nonisolated(unsafe) static let signed = UnsafePointer(strdup("q")!)
    nonisolated(unsafe) static let unsigned = UnsafePointer(strdup("Q")!)
    nonisolated(unsafe) static let double = UnsafePointer(strdup("d")!)
    nonisolated(unsafe) static let bool = UnsafePointer(strdup("c")!)
}

/// CoreFoundation's constant numbers (kCFNumberNaN and the infinities), kept
/// alive for the process.
@ObjCConstants
enum NumberConstants {
    nonisolated(unsafe) static let kCFNumberNaN: UnsafeMutableRawPointer? = constant(.nan)
    nonisolated(unsafe) static let kCFNumberPositiveInfinity: UnsafeMutableRawPointer? = constant(.infinity)
    nonisolated(unsafe) static let kCFNumberNegativeInfinity: UnsafeMutableRawPointer? = constant(-.infinity)

    private static func constant(_ value: Double) -> UnsafeMutableRawPointer? {
        ObjC.retain(Numbers.make(nil, .double(value)))
    }
}

enum Numbers {
    nonisolated(unsafe) static var numberClass: Class!
    nonisolated(unsafe) static var constantIntegerClass: Class!
    nonisolated(unsafe) static var constantDoubleClass: Class!
    nonisolated(unsafe) static var constantFloatClass: Class!
    nonisolated(unsafe) static var booleanClass: Class!
    /// The class of the small numbers kept for good.
    nonisolated(unsafe) static var keptClass: Class?

    /// A number's value, read from the static layouts of literals and
    /// kCFBooleanTrue/False, or from the storage of allocated numbers.
    static func storage(_ object: id?) -> NumberStorage {
        guard let object else { return NumberStorage(.signed(0)) }
        switch ObjC.objectGetClass(object) {
        case constantIntegerClass:
            let encoding = object.load(fromByteOffset: DarwinLayout.numberEncoding, as: UnsafePointer<CChar>?.self)?.pointee ?? 0
            let raw = object.loadUnaligned(fromByteOffset: DarwinLayout.integerNumberValue, as: UInt64.self)
            // Unsigned encodings: C, S, I, L, Q.
            if "CSILQ".utf8.contains(UInt8(bitPattern: encoding)) {
                return NumberStorage(.unsigned(raw))
            }
            return NumberStorage(.signed(Int64(bitPattern: raw)))
        case constantDoubleClass:
            return NumberStorage(.double(object.loadUnaligned(fromByteOffset: DarwinLayout.floatingNumberValue, as: Double.self)))
        case constantFloatClass:
            return NumberStorage(.double(Double(object.load(fromByteOffset: DarwinLayout.floatingNumberValue, as: Float.self))))
        case booleanClass:
            return NumberStorage(.bool(object.load(fromByteOffset: 8, as: UInt64.self) != 0))
        default:
            return Storage.get(object, as: NumberStorage.self) ?? NumberStorage(.signed(0))
        }
    }

    /// The numbers kept for good, by kind and value. Darwin's small numbers
    /// are tagged pointers, which are never deallocated, and programs count
    /// on it: one kept with OBJC_ASSOCIATION_ASSIGN is read long after its
    /// last release. So small whole numbers and booleans are each made
    /// once and never freed.
    private struct Kept: Hashable {
        let kind: UInt8
        let bits: UInt64
    }
    private static let kept = Mutex<[Kept: UInt]>([:])

    static func isKept(_ value: NumberStorage.Value) -> Bool { keptKey(value) != nil }

    private static func keptKey(_ value: NumberStorage.Value) -> Kept? {
        switch value {
        case .signed(let number): return (-1024...4096).contains(number) ? Kept(kind: 0, bits: UInt64(bitPattern: number)) : nil
        case .unsigned(let number): return number <= 4096 ? Kept(kind: 1, bits: number) : nil
        case .double(let number):
            return number == number.rounded() && abs(number) <= 4096 ? Kept(kind: 2, bits: number.bitPattern) : nil
        case .bool(let flag): return Kept(kind: 3, bits: flag ? 1 : 0)
        }
    }

    static func make(_ cls: id?, _ value: NumberStorage.Value) -> id? {
        if cls == nil || cls == UnsafeMutableRawPointer(numberClass), let key = keptKey(value) {
            if let known = kept.withLock({ $0[key] }) { return UnsafeMutableRawPointer(bitPattern: known) }
            // An instance of the class whose retain and release do nothing,
            // as a tagged pointer's do: a release too many, harmless on
            // Darwin, must not free a number the table still gives out.
            guard let object = Storage.allocate(UnsafeMutableRawPointer(keptClass ?? numberClass)) else { return nil }
            Storage.set(object, NumberStorage(value))
            // The table's reference is never released; another thread's
            // number for the same value, made meanwhile, is the one kept.
            let stored = kept.withLock { table -> UInt in
                if let existing = table[key] { return existing }
                table[key] = UInt(bitPattern: object)
                return UInt(bitPattern: object)
            }
            if stored != UInt(bitPattern: object) { ObjC.release(object) }
            return UnsafeMutableRawPointer(bitPattern: stored)
        }
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(numberClass)) else { return nil }
        Storage.set(object, NumberStorage(value))
        return ObjC.autorelease(object)
    }

    static func initialize(_ object: id?, _ value: NumberStorage.Value) -> id? {
        if let object { Storage.set(object, NumberStorage(value)) }
        return object
    }


    /// A new number wrapped for returning, +0.
    static func wrapped(_ cls: ObjCClass, _ value: NumberStorage.Value) -> NSNumber {
        NSNumber(objCReturnValue: make(cls.pointer, value))
    }
}

/// NSNumber.
/// A number is a value, as on Darwin, where code that takes either asks
/// whether what it has is an NSValue.
@ObjCClass("NSNumber")
public class NSNumber: NSValue {
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSNumber__") func isNSNumber__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Numbers.numberClass = cls.storage
    }

    private var number: NumberStorage { Numbers.storage(objcObject) }

    /// An -init…'s result, +1, as the receiver is released when the method
    /// returns: the number kept for good for a small value (see
    /// Numbers.kept), in place of the one allocated, or the receiver.
    private func setValue(_ value: NumberStorage.Value) -> UnsafeMutableRawPointer? {
        if ObjC.objectGetClass(objcObject) == Numbers.numberClass, Numbers.isKept(value),
           let kept = Numbers.make(nil, value) {
            return ObjC.retain(kept)
        }
        Storage.set(objcObject, NumberStorage(value))
        return ObjC.retain(objcObject)
    }

    // MARK: Creating. Narrow integer arguments are read at their declared
    // width: the caller need not extend them to the full register.

    @ObjCClassMethod("numberWithInteger:")
    static func number(_ cls: ObjCClass, integer: Int) -> NSNumber { Numbers.wrapped(cls, .signed(Int64(integer))) }

    @ObjCClassMethod("numberWithLong:")
    static func number(_ cls: ObjCClass, long: Int) -> NSNumber { Numbers.wrapped(cls, .signed(Int64(long))) }

    @ObjCClassMethod("numberWithLongLong:")
    static func number(_ cls: ObjCClass, longLong: Int64) -> NSNumber { Numbers.wrapped(cls, .signed(longLong)) }

    @ObjCClassMethod("numberWithUnsignedInteger:")
    static func number(_ cls: ObjCClass, unsignedInteger: UInt) -> NSNumber {
        Numbers.wrapped(cls, .unsigned(UInt64(unsignedInteger)))
    }

    @ObjCClassMethod("numberWithUnsignedLong:")
    static func number(_ cls: ObjCClass, unsignedLong: UInt) -> NSNumber { Numbers.wrapped(cls, .unsigned(UInt64(unsignedLong))) }

    @ObjCClassMethod("numberWithUnsignedLongLong:")
    static func number(_ cls: ObjCClass, unsignedLongLong: UInt64) -> NSNumber { Numbers.wrapped(cls, .unsigned(unsignedLongLong)) }

    @ObjCClassMethod("numberWithInt:")
    static func number(_ cls: ObjCClass, int: Int32) -> NSNumber { Numbers.wrapped(cls, .signed(Int64(int))) }

    @ObjCClassMethod("numberWithUnsignedInt:")
    static func number(_ cls: ObjCClass, unsignedInt: UInt32) -> NSNumber { Numbers.wrapped(cls, .unsigned(UInt64(unsignedInt))) }

    @ObjCClassMethod("numberWithUnsignedShort:")
    static func number(_ cls: ObjCClass, unsignedShort: UInt16) -> NSNumber { Numbers.wrapped(cls, .unsigned(UInt64(unsignedShort))) }

    @ObjCClassMethod("numberWithUnsignedChar:")
    static func number(_ cls: ObjCClass, unsignedChar: UInt8) -> NSNumber { Numbers.wrapped(cls, .unsigned(UInt64(unsignedChar))) }

    @ObjCClassMethod("numberWithShort:")
    static func number(_ cls: ObjCClass, short: Int16) -> NSNumber { Numbers.wrapped(cls, .signed(Int64(short))) }

    @ObjCClassMethod("numberWithChar:")
    static func number(_ cls: ObjCClass, char: Int8) -> NSNumber { Numbers.wrapped(cls, .signed(Int64(char))) }

    @ObjCClassMethod("numberWithBool:")
    static func number(_ cls: ObjCClass, bool: Bool) -> NSNumber { Numbers.wrapped(cls, .bool(bool)) }

    @ObjCClassMethod("numberWithDouble:")
    static func number(_ cls: ObjCClass, double: Double) -> NSNumber { Numbers.wrapped(cls, .double(double)) }

    @ObjCClassMethod("numberWithFloat:")
    static func number(_ cls: ObjCClass, float: Float) -> NSNumber { Numbers.wrapped(cls, .double(Double(float))) }

    @ObjCMethod("initWithInteger:") func initialize(integer: Int) -> UnsafeMutableRawPointer? { setValue(.signed(Int64(integer))) }
    @ObjCMethod("initWithLongLong:") func initialize(longLong: Int64) -> UnsafeMutableRawPointer? { setValue(.signed(longLong)) }
    @ObjCMethod("initWithUnsignedInteger:") func initialize(unsignedInteger: UInt) -> UnsafeMutableRawPointer? { setValue(.unsigned(UInt64(unsignedInteger))) }
    @ObjCMethod("initWithInt:") func initialize(int: Int32) -> UnsafeMutableRawPointer? { setValue(.signed(Int64(int))) }
    @ObjCMethod("initWithBool:") func initialize(bool: Bool) -> UnsafeMutableRawPointer? { setValue(.bool(bool)) }
    @ObjCMethod("initWithDouble:") func initialize(double: Double) -> UnsafeMutableRawPointer? { setValue(.double(double)) }
    @ObjCMethod("initWithFloat:") func initialize(float: Float) -> UnsafeMutableRawPointer? { setValue(.double(Double(float))) }
    @ObjCMethod("initWithLong:") func initialize(long: Int) -> UnsafeMutableRawPointer? { setValue(.signed(Int64(long))) }
    @ObjCMethod("initWithUnsignedLong:") func initialize(unsignedLong: UInt) -> UnsafeMutableRawPointer? { setValue(.unsigned(UInt64(unsignedLong))) }
    @ObjCMethod("initWithUnsignedLongLong:") func initialize(unsignedLongLong: UInt64) -> UnsafeMutableRawPointer? { setValue(.unsigned(unsignedLongLong)) }
    @ObjCMethod("initWithUnsignedInt:") func initialize(unsignedInt: UInt32) -> UnsafeMutableRawPointer? { setValue(.unsigned(UInt64(unsignedInt))) }
    @ObjCMethod("initWithShort:") func initialize(short: Int16) -> UnsafeMutableRawPointer? { setValue(.signed(Int64(short))) }
    @ObjCMethod("initWithUnsignedShort:") func initialize(unsignedShort: UInt16) -> UnsafeMutableRawPointer? { setValue(.unsigned(UInt64(unsignedShort))) }
    @ObjCMethod("initWithChar:") func initialize(char: Int8) -> UnsafeMutableRawPointer? { setValue(.signed(Int64(char))) }
    @ObjCMethod("initWithUnsignedChar:") func initialize(unsignedChar: UInt8) -> UnsafeMutableRawPointer? { setValue(.unsigned(UInt64(unsignedChar))) }

    @ObjCMethod("dealloc")
    override func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Numbers.numberClass)
    }

    // MARK: Values

    @ObjCMethod("integerValue") func integerValue() -> Int { Int(number.int64) }
    @ObjCMethod("longValue") func longValue() -> Int { Int(number.int64) }
    @ObjCMethod("longLongValue") func longLongValue() -> Int64 { number.int64 }
    @ObjCMethod("unsignedIntegerValue") func unsignedIntegerValue() -> UInt { UInt(truncatingIfNeeded: number.int64) }
    @ObjCMethod("intValue") func intValue() -> Int32 { Int32(truncatingIfNeeded: number.int64) }
    @ObjCMethod("unsignedIntValue") func unsignedIntValue() -> UInt32 { UInt32(truncatingIfNeeded: number.int64) }
    @ObjCMethod("unsignedLongValue") func unsignedLongValue() -> UInt { UInt(truncatingIfNeeded: number.int64) }
    @ObjCMethod("unsignedLongLongValue") func unsignedLongLongValue() -> UInt64 { UInt64(truncatingIfNeeded: number.int64) }
    @ObjCMethod("shortValue") func shortValue() -> Int16 { Int16(truncatingIfNeeded: number.int64) }
    @ObjCMethod("unsignedShortValue") func unsignedShortValue() -> UInt16 { UInt16(truncatingIfNeeded: number.int64) }
    @ObjCMethod("charValue") func charValue() -> Int8 { Int8(truncatingIfNeeded: number.int64) }
    @ObjCMethod("unsignedCharValue") func unsignedCharValue() -> UInt8 { UInt8(truncatingIfNeeded: number.int64) }
    @ObjCMethod("boolValue") func boolValue() -> Bool { number.int64 != 0 || number.double != 0 }

    /// NSValue's: the value as its type encoding has it.
    @ObjCMethod("getValue:")
    override func getValue(_ buffer: UnsafeMutableRawPointer?) {
        guard let buffer else { return }
        switch number.value {
        case .signed(let value): buffer.storeBytes(of: value, as: Int64.self)
        case .unsigned(let value): buffer.storeBytes(of: value, as: UInt64.self)
        case .double(let value): buffer.storeBytes(of: value, as: Double.self)
        case .bool(let value): buffer.storeBytes(of: value ? 1 : 0, as: Int8.self)
        }
    }

    @ObjCMethod("getValue:size:")
    override func getValue(_ buffer: UnsafeMutableRawPointer?, size: UInt) { getValue(buffer) }

    /// The value's type encoding: "q" and "Q" for integers, "d" for
    /// floating point, "c" for booleans (CFBoolean), as Darwin reports.
    @ObjCMethod("objCType")
    override func objCType() -> UnsafePointer<CChar>? {
        switch number.value {
        case .signed: return NumberTypes.signed
        case .unsigned: return NumberTypes.unsigned
        case .double: return NumberTypes.double
        case .bool: return NumberTypes.bool
        }
    }
    @ObjCMethod("doubleValue") func doubleValue() -> Double { number.double }
    @ObjCMethod("floatValue") func floatValue() -> Float { Float(number.double) }
    @ObjCMethod("stringValue") func stringValue() -> String { number.description }
    @ObjCMethod("description") override func description() -> String { number.description }

    // MARK: Comparing

    @ObjCMethod("compare:")
    func compare(_ other: NSNumber) -> Int { number.compare(Numbers.storage(other.id)) }

    @ObjCMethod("isEqualToNumber:")
    func isEqual(toNumber other: NSNumber?) -> Bool { other.map { compare($0) == 0 } ?? false }

    @ObjCMethod("isEqual:")
    override func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSNumber.self) else { return false }
        return compare(other.unsafeCast(to: NSNumber.self)) == 0
    }

    /// Equal numbers hash equally whatever their type.
    @ObjCMethod("hash")
    override func hash() -> UInt {
        // Truncated, as a 64-bit value does not fit a 32-bit hash.
        if number.double == number.double.rounded() { return UInt(truncatingIfNeeded: number.int64) }
        return UInt(truncatingIfNeeded: number.double.bitPattern)
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSNumber { self }
}

/// @42: { isa, const char *encoding, int64 value }.
@ObjCClass("NSConstantIntegerNumber")
final class NSConstantIntegerNumber: NSNumber {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Numbers.constantIntegerClass = cls.markingStatic().storage
    }
}

/// @2.5: { isa, double value }.
@ObjCClass("NSConstantDoubleNumber")
final class NSConstantDoubleNumber: NSNumber {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Numbers.constantDoubleClass = cls.markingStatic().storage
    }
}

/// @2.5f: { isa, float value }.
@ObjCClass("NSConstantFloatNumber")
final class NSConstantFloatNumber: NSNumber {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Numbers.constantFloatClass = cls.markingStatic().storage
    }
}

/// The small numbers kept for good (Numbers.kept): numbers like any other,
/// but never retained, released or freed, as Darwin's tagged pointer
/// numbers are not.
@ObjCClass("__NSCFNumber")
final class NSKeptNumber: NSNumber {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NSObject.registerObjCCategoryImmortal(cls)
        Numbers.keptClass = cls.storage
    }
}

/// kCFBooleanTrue and kCFBooleanFalse: { isa, uint64 value }.
@ObjCClass("__NSCFBoolean")
final class NSCFBoolean: NSNumber {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Numbers.booleanClass = cls.markingStatic().storage
    }
}
