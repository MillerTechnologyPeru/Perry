import CPerryFoundation
import Glibc

/// An NSString's contents.
final class StringStorage {
    let value: String
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
        let string = ClassDefinition(PERRY_CLASS_NSString, name: "NSString", superclass: superclass)
        stringClass = string.cls

        string.classMethod("alloc", "@16@0:8", { cls, _ in Storage.allocate(cls) } as IMPObject)
        string.classMethod("allocWithZone:", "@24@0:8^v16", { cls, _, _ in Storage.allocate(cls) } as IMPObjectObject)
        string.classMethod("string", "@16@0:8", { _, _ in Strings.autoreleased("") } as IMPObject)
        string.classMethod("stringWithString:", "@24@0:8@16", { _, _, other in
            Strings.autoreleased(Strings.value(of: other) ?? "")
        } as IMPObjectObject)
        string.classMethod("stringWithUTF8String:", "@24@0:8r*16", { _, _, bytes in
            guard let bytes else { return nil }
            return Strings.autoreleased(String(cString: bytes.assumingMemoryBound(to: CChar.self)))
        } as IMPObjectObject)
        string.classMethod("stringWithFormat:", "@24@0:8@16", address: unsafeBitCast(
            perry_imp_stringWithFormat as @convention(c) () -> Void, to: UnsafeRawPointer.self))

        string.method("init", "@16@0:8", { object, _ in
            if let object { Storage.set(object, StringStorage("")) }
            return object
        } as IMPObject)
        string.method("initWithString:", "@24@0:8@16", { object, _, other in
            if let object { Storage.set(object, StringStorage(Strings.value(of: other) ?? "")) }
            return object
        } as IMPObjectObject)
        string.method("initWithUTF8String:", "@24@0:8r*16", { object, _, bytes in
            guard let object, let bytes else { return nil }
            Storage.set(object, StringStorage(String(cString: bytes.assumingMemoryBound(to: CChar.self))))
            return object
        } as IMPObjectObject)
        string.method("initWithFormat:", "@24@0:8@16", address: unsafeBitCast(
            perry_imp_initWithFormat as @convention(c) () -> Void, to: UnsafeRawPointer.self))
        string.method("initWithFormat:arguments:", "@32@0:8@16*24", { object, _, format, arguments in
            guard let object, let arguments else { return object }
            var darwin = DarwinArguments(arguments)
            Storage.set(object, StringStorage(Format.string(Strings.value(of: format) ?? "", &darwin)))
            return object
        } as @convention(c) (id?, SEL, id?, UnsafeRawPointer?) -> id?)
        string.method("dealloc", "v16@0:8", { object, _ in
            guard let object else { return }
            Storage.set(object, nil)
            ObjC.superDealloc(object, from: Strings.stringClass)
        } as IMPVoid)

        string.method("length", "Q16@0:8", { object, _ in
            UInt(Strings.value(of: object)?.utf16.count ?? 0)
        } as IMPUInt)
        string.method("characterAtIndex:", "S24@0:8Q16", { object, _, index in
            let units = Array((Strings.value(of: object) ?? "").utf16)
            guard Int(index) < units.count else {
                foundationFatal("-[NSString characterAtIndex:]: Range or index out of bounds")
            }
            return units[Int(index)]
        } as @convention(c) (id?, SEL, UInt) -> UInt16)
        string.method("UTF8String", "r*16@0:8", { object, _ in
            object.flatMap(Strings.utf8)
        } as @convention(c) (id?, SEL) -> UnsafePointer<CChar>?)
        string.method("description", "@16@0:8", { object, _ in object } as IMPObject)
        string.method("copy", "@16@0:8", { object, _ in ObjC.retain(object) } as IMPObject)
        string.method("copyWithZone:", "@24@0:8^v16", { object, _, _ in ObjC.retain(object) } as IMPObjectObject)
        string.method("isEqual:", "B24@0:8@16", { object, _, other in
            object == other || (Strings.value(of: other).map { $0 == Strings.value(of: object) } ?? false)
        } as IMPBoolObject)
        string.method("isEqualToString:", "B24@0:8@16", { object, _, other in
            object == other || Strings.value(of: object) == Strings.value(of: other)
        } as IMPBoolObject)
        string.method("hash", "Q16@0:8", { object, _ in
            Strings.hash(Strings.value(of: object) ?? "")
        } as IMPUInt)
        string.method("compare:", "q24@0:8@16", { object, _, other in
            Strings.compare(Strings.value(of: object) ?? "", Strings.value(of: other) ?? "")
        } as IMPIntObject)
        string.method("hasPrefix:", "B24@0:8@16", { object, _, other in
            (Strings.value(of: object) ?? "").hasPrefix(Strings.value(of: other) ?? "")
        } as IMPBoolObject)
        string.method("hasSuffix:", "B24@0:8@16", { object, _, other in
            (Strings.value(of: object) ?? "").hasSuffix(Strings.value(of: other) ?? "")
        } as IMPBoolObject)
        string.method("stringByAppendingString:", "@24@0:8@16", { object, _, other in
            Strings.autoreleased((Strings.value(of: object) ?? "") + (Strings.value(of: other) ?? ""))
        } as IMPObjectObject)
        string.method("stringByAppendingFormat:", "@24@0:8@16", address: unsafeBitCast(
            perry_imp_stringByAppendingFormat as @convention(c) () -> Void, to: UnsafeRawPointer.self))
        string.method("uppercaseString", "@16@0:8", { object, _ in
            Strings.autoreleased((Strings.value(of: object) ?? "").uppercased())
        } as IMPObject)
        string.method("lowercaseString", "@16@0:8", { object, _ in
            Strings.autoreleased((Strings.value(of: object) ?? "").lowercased())
        } as IMPObject)
        string.method("integerValue", "q16@0:8", { object, _ in
            Strings.integerPrefix(Strings.value(of: object) ?? "")
        } as IMPInt)
        string.method("intValue", "i16@0:8", { object, _ in
            Int32(truncatingIfNeeded: Strings.integerPrefix(Strings.value(of: object) ?? ""))
        } as @convention(c) (id?, SEL) -> Int32)
        string.method("doubleValue", "d16@0:8", { object, _ in
            (Strings.value(of: object) ?? "").withCString { strtod($0, nil) }
        } as @convention(c) (id?, SEL) -> Double)
        string.register()

        // String literals: immortal, read in place.
        let constant = ClassDefinition(PERRY_CLASS_NSConstantString, name: "__NSCFConstantString", superclass: string.cls)
        constantClass = constant.cls
        constant.method("retain", "@16@0:8", { object, _ in object } as IMPObject)
        constant.method("release", "Vv16@0:8", { _, _ in } as IMPVoid)
        constant.method("autorelease", "@16@0:8", { object, _ in object } as IMPObject)
        constant.method("retainCount", "Q16@0:8", { _, _ in UInt.max } as IMPUInt)
        constant.register()
    }

    /// Leading integer, as -integerValue reads it ("42abc" is 42).
    static func integerPrefix(_ value: String) -> Int {
        value.withCString { strtol($0, nil, 10) }
    }
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
