import CPerryFoundation
import Glibc

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
        let number = ClassDefinition(PERRY_CLASS_NSNumber, name: "NSNumber", superclass: superclass)
        numberClass = number.cls

        number.classMethod("alloc", "@16@0:8", { cls, _ in Storage.allocate(cls) } as IMPObject)
        number.classMethod("allocWithZone:", "@24@0:8^v16", { cls, _, _ in Storage.allocate(cls) } as IMPObjectObject)

        typealias SignedFactory = @convention(c) (id?, SEL, Int64) -> id?
        typealias UnsignedFactory = @convention(c) (id?, SEL, UInt64) -> id?
        typealias Int32Factory = @convention(c) (id?, SEL, Int32) -> id?
        typealias UInt32Factory = @convention(c) (id?, SEL, UInt32) -> id?
        // Narrow integer arguments are read at their declared width: the
        // caller need not extend them to the full register.
        for (name, encoding) in [("Integer", "q"), ("Long", "q"), ("LongLong", "q")] {
            number.classMethod("numberWith\(name):", "@24@0:8\(encoding)16", { cls, _, value in
                Numbers.make(cls, .signed(value))
            } as SignedFactory)
            number.method("initWith\(name):", "@24@0:8\(encoding)16", { object, _, value in
                Numbers.initialize(object, .signed(value))
            } as SignedFactory)
        }
        for name in ["UnsignedInteger", "UnsignedLong", "UnsignedLongLong"] {
            number.classMethod("numberWith\(name):", "@24@0:8Q16", { cls, _, value in
                Numbers.make(cls, .unsigned(value))
            } as UnsignedFactory)
            number.method("initWith\(name):", "@24@0:8Q16", { object, _, value in
                Numbers.initialize(object, .unsigned(value))
            } as UnsignedFactory)
        }
        number.classMethod("numberWithInt:", "@20@0:8i16", { cls, _, value in
            Numbers.make(cls, .signed(Int64(value)))
        } as Int32Factory)
        number.method("initWithInt:", "@20@0:8i16", { object, _, value in
            Numbers.initialize(object, .signed(Int64(value)))
        } as Int32Factory)
        number.classMethod("numberWithUnsignedInt:", "@20@0:8I16", { cls, _, value in
            Numbers.make(cls, .unsigned(UInt64(value)))
        } as UInt32Factory)
        number.classMethod("numberWithShort:", "@20@0:8s16", { cls, _, value in
            Numbers.make(cls, .signed(Int64(Int16(truncatingIfNeeded: value))))
        } as Int32Factory)
        number.classMethod("numberWithChar:", "@20@0:8c16", { cls, _, value in
            Numbers.make(cls, .signed(Int64(Int8(truncatingIfNeeded: value))))
        } as Int32Factory)
        number.classMethod("numberWithBool:", "@20@0:8B16", { cls, _, value in
            Numbers.make(cls, .bool(value))
        } as @convention(c) (id?, SEL, Bool) -> id?)
        number.method("initWithBool:", "@20@0:8B16", { object, _, value in
            Numbers.initialize(object, .bool(value))
        } as @convention(c) (id?, SEL, Bool) -> id?)
        number.classMethod("numberWithDouble:", "@24@0:8d16", { cls, _, value in
            Numbers.make(cls, .double(value))
        } as @convention(c) (id?, SEL, Double) -> id?)
        number.method("initWithDouble:", "@24@0:8d16", { object, _, value in
            Numbers.initialize(object, .double(value))
        } as @convention(c) (id?, SEL, Double) -> id?)
        number.classMethod("numberWithFloat:", "@20@0:8f16", { cls, _, value in
            Numbers.make(cls, .double(Double(value)))
        } as @convention(c) (id?, SEL, Float) -> id?)

        number.method("dealloc", "v16@0:8", { object, _ in
            guard let object else { return }
            Storage.set(object, nil)
            ObjC.superDealloc(object, from: Numbers.numberClass)
        } as IMPVoid)

        number.method("integerValue", "q16@0:8", { object, _ in Int(Numbers.storage(object).int64) } as IMPInt)
        number.method("longValue", "q16@0:8", { object, _ in Int(Numbers.storage(object).int64) } as IMPInt)
        number.method("longLongValue", "q16@0:8", { object, _ in Int(Numbers.storage(object).int64) } as IMPInt)
        number.method("unsignedIntegerValue", "Q16@0:8", { object, _ in
            UInt(truncatingIfNeeded: Numbers.storage(object).int64)
        } as IMPUInt)
        number.method("intValue", "i16@0:8", { object, _ in
            Int32(truncatingIfNeeded: Numbers.storage(object).int64)
        } as @convention(c) (id?, SEL) -> Int32)
        number.method("boolValue", "B16@0:8", { object, _ in Numbers.storage(object).int64 != 0 }
                      as @convention(c) (id?, SEL) -> Bool)
        number.method("doubleValue", "d16@0:8", { object, _ in Numbers.storage(object).double }
                      as @convention(c) (id?, SEL) -> Double)
        number.method("floatValue", "f16@0:8", { object, _ in Float(Numbers.storage(object).double) }
                      as @convention(c) (id?, SEL) -> Float)
        number.method("stringValue", "@16@0:8", { object, _ in
            Strings.autoreleased(Numbers.storage(object).description)
        } as IMPObject)
        number.method("description", "@16@0:8", { object, _ in
            Strings.autoreleased(Numbers.storage(object).description)
        } as IMPObject)
        number.method("compare:", "q24@0:8@16", { object, _, other in
            Numbers.storage(object).compare(Numbers.storage(other))
        } as IMPIntObject)
        number.method("isEqualToNumber:", "B24@0:8@16", { object, _, other in
            Numbers.storage(object).compare(Numbers.storage(other)) == 0
        } as IMPBoolObject)
        number.method("isEqual:", "B24@0:8@16", { object, _, other in
            guard ObjC.isKind(other, of: Numbers.numberClass) else { return false }
            return Numbers.storage(object).compare(Numbers.storage(other)) == 0
        } as IMPBoolObject)
        number.method("hash", "Q16@0:8", { object, _ in
            UInt(bitPattern: Int(Numbers.storage(object).int64))
        } as IMPUInt)
        number.method("copyWithZone:", "@24@0:8^v16", { object, _, _ in ObjC.retain(object) } as IMPObjectObject)
        number.register()

        // Static numbers: immortal, read in place.
        func constant(_ which: perry_foundation_class_id, _ name: String) -> Class {
            let definition = ClassDefinition(which, name: name, superclass: number.cls)
            definition.method("retain", "@16@0:8", { object, _ in object } as IMPObject)
            definition.method("release", "Vv16@0:8", { _, _ in } as IMPVoid)
            definition.method("autorelease", "@16@0:8", { object, _ in object } as IMPObject)
            definition.method("retainCount", "Q16@0:8", { _, _ in UInt.max } as IMPUInt)
            definition.register()
            return definition.cls
        }
        constantIntegerClass = constant(PERRY_CLASS_NSConstantIntegerNumber, "NSConstantIntegerNumber")
        constantDoubleClass = constant(PERRY_CLASS_NSConstantDoubleNumber, "NSConstantDoubleNumber")
        constantFloatClass = constant(PERRY_CLASS_NSConstantFloatNumber, "NSConstantFloatNumber")
        booleanClass = constant(PERRY_CLASS_NSCFBoolean, "__NSCFBoolean")
    }
}
