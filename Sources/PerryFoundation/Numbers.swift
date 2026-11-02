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

    static func install(superclass: Class) {
        let number = ClassDefinition(PERRY_CLASS_NSNumber, name: "NSNumber", superclass: superclass,
                                     StorageAllocation.self, NSNumberMethods.self)
        numberClass = number.cls
        // Static numbers: immortal, read in place.
        func constant(_ which: perry_foundation_class_id, _ name: String) -> Class {
            ClassDefinition(which, name: name, superclass: number.cls, ImmortalMethods.self).cls
        }
        constantIntegerClass = constant(PERRY_CLASS_NSConstantIntegerNumber, "NSConstantIntegerNumber")
        constantDoubleClass = constant(PERRY_CLASS_NSConstantDoubleNumber, "NSConstantDoubleNumber")
        constantFloatClass = constant(PERRY_CLASS_NSConstantFloatNumber, "NSConstantFloatNumber")
        booleanClass = constant(PERRY_CLASS_NSCFBoolean, "__NSCFBoolean")
    }
}

@ObjCImplementation
enum NSNumberMethods {
    private static func value(_ object: id?) -> NumberStorage { Numbers.storage(object) }

    // MARK: Creating. Narrow integer arguments are read at their declared
    // width: the caller need not extend them to the full register.

    @ObjCClassMethod("numberWithInteger:")
    static func number(_ cls: id?, integer: Int) -> id? { Numbers.make(cls, .signed(Int64(integer))) }

    @ObjCClassMethod("numberWithLong:")
    static func number(_ cls: id?, long: Int) -> id? { Numbers.make(cls, .signed(Int64(long))) }

    @ObjCClassMethod("numberWithLongLong:")
    static func number(_ cls: id?, longLong: Int64) -> id? { Numbers.make(cls, .signed(longLong)) }

    @ObjCClassMethod("numberWithUnsignedInteger:")
    static func number(_ cls: id?, unsignedInteger: UInt) -> id? { Numbers.make(cls, .unsigned(UInt64(unsignedInteger))) }

    @ObjCClassMethod("numberWithUnsignedLong:")
    static func number(_ cls: id?, unsignedLong: UInt) -> id? { Numbers.make(cls, .unsigned(UInt64(unsignedLong))) }

    @ObjCClassMethod("numberWithUnsignedLongLong:")
    static func number(_ cls: id?, unsignedLongLong: UInt64) -> id? { Numbers.make(cls, .unsigned(unsignedLongLong)) }

    @ObjCClassMethod("numberWithInt:")
    static func number(_ cls: id?, int: Int32) -> id? { Numbers.make(cls, .signed(Int64(int))) }

    @ObjCClassMethod("numberWithUnsignedInt:")
    static func number(_ cls: id?, unsignedInt: UInt32) -> id? { Numbers.make(cls, .unsigned(UInt64(unsignedInt))) }

    @ObjCClassMethod("numberWithShort:")
    static func number(_ cls: id?, short: Int16) -> id? { Numbers.make(cls, .signed(Int64(short))) }

    @ObjCClassMethod("numberWithChar:")
    static func number(_ cls: id?, char: Int8) -> id? { Numbers.make(cls, .signed(Int64(char))) }

    @ObjCClassMethod("numberWithBool:")
    static func number(_ cls: id?, bool: Bool) -> id? { Numbers.make(cls, .bool(bool)) }

    @ObjCClassMethod("numberWithDouble:")
    static func number(_ cls: id?, double: Double) -> id? { Numbers.make(cls, .double(double)) }

    @ObjCClassMethod("numberWithFloat:")
    static func number(_ cls: id?, float: Float) -> id? { Numbers.make(cls, .double(Double(float))) }

    @ObjCMethod("initWithInteger:")
    static func initialize(_ object: id?, integer: Int) -> id? { Numbers.initialize(object, .signed(Int64(integer))) }

    @ObjCMethod("initWithLongLong:")
    static func initialize(_ object: id?, longLong: Int64) -> id? { Numbers.initialize(object, .signed(longLong)) }

    @ObjCMethod("initWithUnsignedInteger:")
    static func initialize(_ object: id?, unsignedInteger: UInt) -> id? {
        Numbers.initialize(object, .unsigned(UInt64(unsignedInteger)))
    }

    @ObjCMethod("initWithInt:")
    static func initialize(_ object: id?, int: Int32) -> id? { Numbers.initialize(object, .signed(Int64(int))) }

    @ObjCMethod("initWithBool:")
    static func initialize(_ object: id?, bool: Bool) -> id? { Numbers.initialize(object, .bool(bool)) }

    @ObjCMethod("initWithDouble:")
    static func initialize(_ object: id?, double: Double) -> id? { Numbers.initialize(object, .double(double)) }

    @ObjCMethod("dealloc")
    static func dealloc(_ object: id?) {
        guard let object else { return }
        Storage.set(object, nil)
        ObjC.superDealloc(object, from: Numbers.numberClass)
    }

    // MARK: Values

    @ObjCMethod("integerValue")
    static func integerValue(_ object: id?) -> Int { Int(value(object).int64) }

    @ObjCMethod("longValue")
    static func longValue(_ object: id?) -> Int { Int(value(object).int64) }

    @ObjCMethod("longLongValue")
    static func longLongValue(_ object: id?) -> Int64 { value(object).int64 }

    @ObjCMethod("unsignedIntegerValue")
    static func unsignedIntegerValue(_ object: id?) -> UInt { UInt(truncatingIfNeeded: value(object).int64) }

    @ObjCMethod("intValue")
    static func intValue(_ object: id?) -> Int32 { Int32(truncatingIfNeeded: value(object).int64) }

    @ObjCMethod("boolValue")
    static func boolValue(_ object: id?) -> Bool { value(object).int64 != 0 || value(object).double != 0 }

    @ObjCMethod("doubleValue")
    static func doubleValue(_ object: id?) -> Double { value(object).double }

    @ObjCMethod("floatValue")
    static func floatValue(_ object: id?) -> Float { Float(value(object).double) }

    @ObjCMethod("stringValue")
    static func stringValue(_ object: id?) -> id? { Strings.autoreleased(value(object).description) }

    @ObjCMethod("description")
    static func description(_ object: id?) -> id? { Strings.autoreleased(value(object).description) }

    // MARK: Comparing

    @ObjCMethod("compare:")
    static func compare(_ object: id?, _ other: id?) -> Int { value(object).compare(value(other)) }

    @ObjCMethod("isEqualToNumber:")
    static func isEqual(_ object: id?, toNumber other: id?) -> Bool { value(object).compare(value(other)) == 0 }

    @ObjCMethod("isEqual:")
    static func isEqual(_ object: id?, _ other: id?) -> Bool {
        ObjC.isKind(other, of: Numbers.numberClass) && value(object).compare(value(other)) == 0
    }

    /// Equal numbers hash equally whatever their type.
    @ObjCMethod("hash")
    static func hash(_ object: id?) -> UInt {
        let number = value(object)
        if number.double == number.double.rounded() { return UInt(bitPattern: Int(number.int64)) }
        return UInt(truncatingIfNeeded: number.double.bitPattern)
    }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(object) }
}
