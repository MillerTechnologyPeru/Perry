import CPerryFoundation
import Glibc
import PerryObjCInterop

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
        case .double(let v): return v.isFinite ? Int64(v) : 0
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

enum Numbers {
    nonisolated(unsafe) static var numberClass: Class!
    nonisolated(unsafe) static var constantIntegerClass: Class!
    nonisolated(unsafe) static var constantDoubleClass: Class!
    nonisolated(unsafe) static var constantFloatClass: Class!
    nonisolated(unsafe) static var booleanClass: Class!

    /// A number's value, read from the static layouts of literals and
    /// kCFBooleanTrue/False, or from the storage of allocated numbers.
    static func storage(_ object: id?) -> NumberStorage {
        guard let object else { return NumberStorage(.signed(0)) }
        switch ObjC.objectGetClass(object) {
        case constantIntegerClass:
            let encoding = object.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self)?.pointee ?? 0
            let raw = object.load(fromByteOffset: 16, as: UInt64.self)
            // Unsigned encodings: C, S, I, L, Q.
            if "CSILQ".utf8.contains(UInt8(bitPattern: encoding)) {
                return NumberStorage(.unsigned(raw))
            }
            return NumberStorage(.signed(Int64(bitPattern: raw)))
        case constantDoubleClass:
            return NumberStorage(.double(object.load(fromByteOffset: 8, as: Double.self)))
        case constantFloatClass:
            return NumberStorage(.double(Double(object.load(fromByteOffset: 8, as: Float.self))))
        case booleanClass:
            return NumberStorage(.bool(object.load(fromByteOffset: 8, as: UInt64.self) != 0))
        default:
            return Storage.get(object, as: NumberStorage.self) ?? NumberStorage(.signed(0))
        }
    }

    static func make(_ cls: id?, _ value: NumberStorage.Value) -> id? {
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
@ObjCClass("NSNumber")
public class NSNumber: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Numbers.numberClass = cls.storage
    }

    private var number: NumberStorage { Numbers.storage(objcObject) }

    private func setValue(_ value: NumberStorage.Value) -> Self {
        Storage.set(objcObject, NumberStorage(value))
        return self
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

    @ObjCMethod("initWithInteger:") func initialize(integer: Int) -> Self { setValue(.signed(Int64(integer))) }
    @ObjCMethod("initWithLongLong:") func initialize(longLong: Int64) -> Self { setValue(.signed(longLong)) }
    @ObjCMethod("initWithUnsignedInteger:") func initialize(unsignedInteger: UInt) -> Self { setValue(.unsigned(UInt64(unsignedInteger))) }
    @ObjCMethod("initWithInt:") func initialize(int: Int32) -> Self { setValue(.signed(Int64(int))) }
    @ObjCMethod("initWithBool:") func initialize(bool: Bool) -> Self { setValue(.bool(bool)) }
    @ObjCMethod("initWithDouble:") func initialize(double: Double) -> Self { setValue(.double(double)) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Numbers.numberClass)
    }

    // MARK: Values

    @ObjCMethod("integerValue") func integerValue() -> Int { Int(number.int64) }
    @ObjCMethod("longValue") func longValue() -> Int { Int(number.int64) }
    @ObjCMethod("longLongValue") func longLongValue() -> Int64 { number.int64 }
    @ObjCMethod("unsignedIntegerValue") func unsignedIntegerValue() -> UInt { UInt(truncatingIfNeeded: number.int64) }
    @ObjCMethod("intValue") func intValue() -> Int32 { Int32(truncatingIfNeeded: number.int64) }
    @ObjCMethod("boolValue") func boolValue() -> Bool { number.int64 != 0 || number.double != 0 }

    /// The value's type encoding: "q" and "Q" for integers, "d" for
    /// floating point, "c" for booleans (CFBoolean), as Darwin reports.
    @ObjCMethod("objCType")
    func objCType() -> UnsafePointer<CChar>? {
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
    @ObjCMethod("description") func description() -> String { number.description }

    // MARK: Comparing

    @ObjCMethod("compare:")
    func compare(_ other: NSNumber) -> Int { number.compare(Numbers.storage(other.id)) }

    @ObjCMethod("isEqualToNumber:")
    func isEqual(toNumber other: NSNumber?) -> Bool { other.map { compare($0) == 0 } ?? false }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSNumber.self) else { return false }
        return compare(other.unsafeCast(to: NSNumber.self)) == 0
    }

    /// Equal numbers hash equally whatever their type.
    @ObjCMethod("hash")
    func hash() -> UInt {
        if number.double == number.double.rounded() { return UInt(bitPattern: Int(number.int64)) }
        return UInt(truncatingIfNeeded: number.double.bitPattern)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSNumber { self }
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

/// kCFBooleanTrue and kCFBooleanFalse: { isa, uint64 value }.
@ObjCClass("__NSCFBoolean")
final class NSCFBoolean: NSNumber {
    /// Set-up after the class is defined.
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Numbers.booleanClass = cls.markingStatic().storage
    }
}
