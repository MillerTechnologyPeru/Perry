import CPerryFoundation
import Glibc
import PerryObjCInterop
import Synchronization

/// NSDecimal crosses by value as Darwin passes it: the C struct of 20
/// bytes, which arm64 and x86_64 pass and return through memory.
extension NSDecimal: ObjCStructure {
    public typealias ObjCType = NSDecimal
    public static var objCTypeEncoding: String { "{?=b8b4b1b1b18[8S]}" }

    init(_ decimal: PerryDecimal) {
        self.init()
        withUnsafeMutableBytes(of: &self) { decimal.store(to: $0.baseAddress!) }
    }

    var decimal: PerryDecimal {
        var copy = self
        return withUnsafeBytes(of: &copy) { PerryDecimal(bytes: $0.baseAddress!) }
    }
}

/// A decimal number's NSDecimal, kept beside the NSNumber state its
/// storage holds (the nearest double, for what reads any number by its
/// NumberStorage): valid while that storage is the object's.
final class DecimalNumberValue: @unchecked Sendable {
    let number: NumberStorage
    let decimal: PerryDecimal

    init(number: NumberStorage, decimal: PerryDecimal) {
        self.number = number
        self.decimal = decimal
    }
}

enum DecimalNumbers {
    nonisolated(unsafe) static let decimalNumberClass: Class? = ObjC.getClass("NSDecimalNumber")
    nonisolated(unsafe) static let handlerClass: Class? = ObjC.getClass("NSDecimalNumberHandler")

    /// Each decimal number's value, by address.
    private static let values = Mutex<[UInt: DecimalNumberValue]>([:])

    /// The NSDecimal of any NSNumber: a decimal number's own; an integer's
    /// exactly; a double's as Darwin's -decimalValue makes it.
    static func decimal(of object: id?) -> PerryDecimal {
        guard let object else { return .nan }
        let number = Numbers.storage(object)
        if let stored = Storage.get(object, as: NumberStorage.self),
           let value = values.withLock({ $0[UInt(bitPattern: object)] }), value.number === stored {
            return value.decimal
        }
        switch number.value {
        case .signed(let value): return PerryDecimal(value)
        case .unsigned(let value): return PerryDecimal(value)
        case .bool(let value): return PerryDecimal(UInt64(value ? 1 : 0))
        case .double(let value): return PerryDecimal(value)
        }
    }

    /// Gives an allocated number the value.
    static func set(_ object: id, _ decimal: PerryDecimal) {
        let number = NumberStorage(.double(decimal.doubleValue))
        Storage.set(object, number)
        values.withLock { $0[UInt(bitPattern: object)] = DecimalNumberValue(number: number, decimal: decimal) }
    }

    static func forget(_ object: id) {
        _ = values.withLock { $0.removeValue(forKey: UInt(bitPattern: object)) }
    }

    /// A new autoreleased decimal number of `cls`.
    static func make(_ cls: id?, _ decimal: PerryDecimal) -> id? {
        guard let object = Storage.allocate(cls ?? decimalNumberClass.map { UnsafeMutableRawPointer($0) }) else { return nil }
        set(object, decimal)
        return ObjC.autorelease(object)
    }

    /// The decimal separator a locale argument gives: an NSLocale's, or a
    /// dictionary's NSLocaleDecimalSeparator or NSDecimalSeparator entry;
    /// "." without one.
    static func separator(_ locale: id?) -> String {
        guard let locale else { return "." }
        for key in [LocaleKeys.NSLocaleDecimalSeparator, "NSDecimalSeparator"] {
            if let separator = Strings.value(of: ObjC.send(locale, Selectors.objectForKey, Strings.autoreleased(key))),
               !separator.isEmpty {
                return separator
            }
        }
        return "."
    }

    /// What a string reads as: not a number unless it starts with one.
    static func parse(_ string: String?, locale: id?) -> PerryDecimal {
        guard let string else { return .nan }
        return PerryDecimal.parse(Array(string.utf8), separator: Array(separator(locale).utf8)).value ?? .nan
    }

    // MARK: Behaviors

    /// The thread dictionary key Darwin keeps a thread's default behavior
    /// under.
    static let behaviorKey = "NSDecimalNumberBehaviors"

    private static let sharedHandler = Mutex<UInt>(0)

    /// +[NSDecimalNumberHandler defaultDecimalNumberHandler]: one, for
    /// good, rounding plainly with no scale and raising on everything but
    /// lost precision.
    static var defaultHandler: id? {
        let handler = sharedHandler.withLock { shared -> UInt in
            if shared != 0 { return shared }
            guard let handler = Storage.allocate(handlerClass.map { UnsafeMutableRawPointer($0) }) else { return 0 }
            Storage.set(handler, DecimalHandlerStorage())
            shared = UInt(bitPattern: handler)
            return shared
        }
        return UnsafeMutableRawPointer(bitPattern: handler)
    }

    /// The current thread's default behavior.
    static var defaultBehavior: id? {
        if let dictionary = Threads.storage(Threads.current)?.threadDictionary,
           let behavior = ObjC.send(dictionary, Selectors.objectForKey, Strings.autoreleased(behaviorKey)) {
            return behavior
        }
        return defaultHandler
    }

    static func setDefaultBehavior(_ behavior: id?) {
        guard let dictionary = Threads.storage(Threads.current)?.threadDictionary else { return }
        // As Darwin's, a nil behavior raises in -setObject:forKey:.
        _ = ObjC.send(dictionary, ObjC.selector("setObject:forKey:"), behavior, Strings.autoreleased(behaviorKey))
    }

    /// A behavior's rounding mode and scale.
    static func rounding(_ behavior: id?) -> (mode: UInt, scale: Int16) {
        guard let behavior else { return (0, Int16.max) }
        let object = NSObject(objCReturnValue: behavior).unsafeCast(to: DecimalBehaviorObject.self)
        return (object.roundingMode(), object.scale())
    }

    /// -exceptionDuringOperation:error:leftOperand:rightOperand:, whose
    /// result, when not nil, stands for the operation's.
    static func exception(_ behavior: id?, operation: String, error: UInt, left: id?, right: id?) -> id? {
        typealias Send = @convention(c) (id?, SEL, SEL, UInt, id?, id?) -> id?
        return unsafeBitCast(ObjC.msgSend, to: Send.self)(behavior, ObjC.selector("exceptionDuringOperation:error:leftOperand:rightOperand:"),
                                                          ObjC.selector(operation), error, left, right)
    }
}

/// NSDecimalNumber: an NSDecimal, 38 digits and an exponent, as an
/// NSNumber whose type is double. Arithmetic is NSDecimalAdd's and the
/// others', rounded and checked by a behavior: the one given, or the
/// thread's default, NSDecimalNumberHandler's, which raises on overflow,
/// underflow and division by zero.
@ObjCClass("NSDecimalNumber")
public class NSDecimalNumber: NSNumber {
    private var decimal: PerryDecimal { DecimalNumbers.decimal(of: objcObject) }

    private static func number(_ cls: ObjCClass, _ decimal: PerryDecimal) -> NSDecimalNumber {
        NSDecimalNumber(objCReturnValue: DecimalNumbers.make(cls.pointer, decimal))
    }

    /// Results are NSDecimalNumbers whatever the receiver's class.
    private static func number(_ decimal: PerryDecimal) -> NSDecimalNumber {
        NSDecimalNumber(objCReturnValue: DecimalNumbers.make(nil, decimal))
    }

    /// NSDecimalNumber's own constants, by selector: made once, of a class
    /// that retain and release leave be, as Foundation's are shared and
    /// immortal, since programs keep them without retaining them (Flow Free
    /// keeps notANumber in a static). A subclass's are new each time.
    private static let constants = Mutex<[String: UInt]>([:])

    private static func constant(_ cls: ObjCClass, _ value: PerryDecimal, _ name: String = #function) -> NSDecimalNumber {
        guard cls.pointer == NSDecimalNumber.objCClass.pointer else { return number(cls, value) }
        let object = constants.withLock { constants -> UInt? in
            if let object = constants[name] { return object }
            guard let object = Storage.allocate(PerryConstantDecimalNumber.objCClass.pointer) else { return nil }
            DecimalNumbers.set(object, value)
            constants[name] = UInt(bitPattern: object)
            return UInt(bitPattern: object)
        }
        guard let object = object.flatMap({ UnsafeMutableRawPointer(bitPattern: $0) }) else { return number(cls, value) }
        return NSDecimalNumber(objcObject: object, ownership: .retain)
    }

    /// The largest mantissa, 2^128 - 1, at the largest exponent.
    private static var largest: PerryDecimal {
        var value = PerryDecimal()
        value.exponent = Int32(Int8.max)
        value.length = UInt32(PerryDecimal.maxSize)
        value.isCompact = true
        value.mantissa = Array(repeating: 0xffff, count: PerryDecimal.maxSize)
        return value
    }

    @ObjCClassMethod("zero") static func zero(_ cls: ObjCClass) -> NSDecimalNumber { constant(cls, .zero) }
    @ObjCClassMethod("one") static func one(_ cls: ObjCClass) -> NSDecimalNumber { constant(cls, PerryDecimal(UInt64(1))) }
    @ObjCClassMethod("notANumber") static func notANumber(_ cls: ObjCClass) -> NSDecimalNumber { constant(cls, .nan) }
    @ObjCClassMethod("maximumDecimalNumber")
    static func maximum(_ cls: ObjCClass) -> NSDecimalNumber { constant(cls, largest) }
    @ObjCClassMethod("minimumDecimalNumber")
    static func minimum(_ cls: ObjCClass) -> NSDecimalNumber {
        var value = largest
        value.isNegative = true
        return constant(cls, value)
    }

    // MARK: Creating

    @ObjCClassMethod("decimalNumberWithString:")
    static func decimalNumber(_ cls: ObjCClass, string: String?) -> NSDecimalNumber {
        number(cls, DecimalNumbers.parse(string, locale: nil))
    }

    @ObjCClassMethod("decimalNumberWithString:locale:")
    static func decimalNumber(_ cls: ObjCClass, string: String?, locale: ObjCObject?) -> NSDecimalNumber {
        number(cls, DecimalNumbers.parse(string, locale: locale?.id))
    }

    /// Not a number for a negative zero mantissa, as on Darwin.
    @ObjCClassMethod("decimalNumberWithMantissa:exponent:isNegative:")
    static func decimalNumber(_ cls: ObjCClass, mantissa: UInt64, exponent: Int16, isNegative: Bool) -> NSDecimalNumber {
        number(cls, PerryDecimal(mantissa: mantissa, exponent: exponent, isNegative: isNegative))
    }

    @ObjCClassMethod("decimalNumberWithDecimal:")
    static func decimalNumber(_ cls: ObjCClass, decimal: NSDecimal) -> NSDecimalNumber { number(cls, decimal.decimal) }

    /// An -init…'s result, +1, as the receiver is released when the method
    /// returns.
    private func setValue(_ decimal: PerryDecimal) -> UnsafeMutableRawPointer? {
        DecimalNumbers.set(objcObject, decimal)
        return ObjC.retain(objcObject)
    }

    @ObjCMethod("initWithString:")
    func initialize(string: String?) -> UnsafeMutableRawPointer? { setValue(DecimalNumbers.parse(string, locale: nil)) }

    @ObjCMethod("initWithString:locale:")
    func initialize(string: String?, locale: ObjCObject?) -> UnsafeMutableRawPointer? {
        setValue(DecimalNumbers.parse(string, locale: locale?.id))
    }

    @ObjCMethod("initWithMantissa:exponent:isNegative:")
    func initialize(mantissa: UInt64, exponent: Int16, isNegative: Bool) -> UnsafeMutableRawPointer? {
        setValue(PerryDecimal(mantissa: mantissa, exponent: exponent, isNegative: isNegative))
    }

    @ObjCMethod("initWithDecimal:")
    func initialize(decimal: NSDecimal) -> UnsafeMutableRawPointer? { setValue(decimal.decimal) }

    /// NSNumber's initializers keep the value as a decimal: a double's
    /// digits as Darwin's -initWithDouble: takes them.
    @ObjCMethod("initWithDouble:")
    override func initialize(double: Double) -> UnsafeMutableRawPointer? { setValue(PerryDecimal(double)) }

    @ObjCMethod("initWithFloat:")
    override func initialize(float: Float) -> UnsafeMutableRawPointer? { setValue(PerryDecimal(Double(float))) }

    @ObjCMethod("dealloc")
    override func dealloc() {
        DecimalNumbers.forget(objcObject)
        if let cls = DecimalNumbers.decimalNumberClass { ObjC.superDealloc(objcObject, from: cls) }
    }

    // MARK: Default behavior

    @ObjCClassMethod("defaultBehavior")
    static func defaultBehavior(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { DecimalNumbers.defaultBehavior }

    /// For the current thread, in its dictionary, as on Darwin.
    @ObjCClassMethod("setDefaultBehavior:")
    static func setDefaultBehavior(_ cls: ObjCClass, behavior: ObjCObject?) { DecimalNumbers.setDefaultBehavior(behavior?.id) }

    // MARK: Values

    @ObjCMethod("decimalValue") func decimalNumberValue() -> NSDecimal { NSDecimal(decimal) }

    @ObjCMethod("objCType") override func objCType() -> UnsafePointer<CChar>? { NumberTypes.double }
    @ObjCMethod("doubleValue") override func doubleValue() -> Double { decimal.doubleValue }
    @ObjCMethod("floatValue") override func floatValue() -> Float { Float(decimal.doubleValue) }

    /// The whole part, wrapped to 64 bits, as Darwin's -longLongValue.
    private var wrapped: UInt64 {
        let value = decimal
        guard value.length > 0 else { return 0 }
        var words = value.words
        if value.exponent < 0 {
            for _ in 0 ..< -Int(value.exponent) where !words.isEmpty {
                words = (try? PerryDecimal.integerDivide(words, byShort: 10).quotient) ?? []
            }
        }
        var result = words.prefix(4).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (16 * UInt64($1.offset)) }
        if value.exponent > 0 {
            for _ in 0 ..< Int(value.exponent) { result = result &* 10 }
        }
        return value.isNegative ? 0 &- result : result
    }

    /// The narrower types convert from the double, as Darwin's do on
    /// arm64: out of range saturates, not a number is zero.
    private var saturatedInt32: Int32 {
        let value = decimal.doubleValue
        if value.isNaN { return 0 }
        return value >= 2147483647 ? .max : value <= -2147483648 ? .min : Int32(value)
    }

    private var saturatedUInt32: UInt32 {
        let value = decimal.doubleValue
        if value.isNaN || value <= 0 { return 0 }
        return value >= 4294967295 ? .max : UInt32(value)
    }

    @ObjCMethod("longLongValue") override func longLongValue() -> Int64 { Int64(bitPattern: wrapped) }
    @ObjCMethod("longValue") override func longValue() -> Int { Int(truncatingIfNeeded: Int64(bitPattern: wrapped)) }
    @ObjCMethod("integerValue") override func integerValue() -> Int { Int(truncatingIfNeeded: Int64(bitPattern: wrapped)) }
    @ObjCMethod("unsignedLongLongValue") override func unsignedLongLongValue() -> UInt64 { wrapped }
    @ObjCMethod("unsignedLongValue") override func unsignedLongValue() -> UInt { UInt(truncatingIfNeeded: wrapped) }
    @ObjCMethod("unsignedIntegerValue") override func unsignedIntegerValue() -> UInt { UInt(truncatingIfNeeded: wrapped) }
    @ObjCMethod("intValue") override func intValue() -> Int32 { saturatedInt32 }
    @ObjCMethod("unsignedIntValue") override func unsignedIntValue() -> UInt32 { saturatedUInt32 }

    // Darwin's shorter accessors, signed or not, are intValue narrowed, and
    // they return intValue's 32 bits as they are: code that uses the whole
    // register, as `int x = n.shortValue` does on arm64, sees 0x7fffffff for
    // the short of 123456789012345678.9, and 0xffffffff for the unsigned
    // short of -1, where a format's %hd and %hu print -1 and 65535.
    override func shortValue() -> Int16 { Int16(truncatingIfNeeded: saturatedInt32) }
    override func charValue() -> Int8 { Int8(truncatingIfNeeded: saturatedInt32) }
    override func unsignedShortValue() -> UInt16 { UInt16(truncatingIfNeeded: saturatedInt32) }
    override func unsignedCharValue() -> UInt8 { UInt8(truncatingIfNeeded: saturatedInt32) }
    @ObjCMethod("shortValue", types: "s16@0:8") func darwinShortValue() -> Int32 { saturatedInt32 }
    @ObjCMethod("charValue", types: "c16@0:8") func darwinCharValue() -> Int32 { saturatedInt32 }
    @ObjCMethod("unsignedShortValue", types: "S16@0:8") func darwinUnsignedShortValue() -> Int32 { saturatedInt32 }
    @ObjCMethod("unsignedCharValue", types: "C16@0:8") func darwinUnsignedCharValue() -> Int32 { saturatedInt32 }
    @ObjCMethod("boolValue") override func boolValue() -> Bool { decimal.length != 0 }

    /// NSDecimalString's digits: "NaN", "0", "-12.34".
    @ObjCMethod("description") override func description() -> String { decimal.string() }
    @ObjCMethod("stringValue") override func stringValue() -> String { decimal.string() }

    /// With the locale's decimal separator (an NSLocale or a dictionary).
    @ObjCMethod("descriptionWithLocale:")
    func decimalNumberDescription(locale: ObjCObject?) -> String { decimal.string(separator: DecimalNumbers.separator(locale?.id)) }

    // MARK: Comparing

    /// By value, against any number: not a number is less than every
    /// number and equal to itself.
    @ObjCMethod("compare:")
    override func compare(_ other: NSNumber) -> Int { PerryDecimal.compare(decimal, DecimalNumbers.decimal(of: other.id)) }

    @ObjCMethod("isEqualToNumber:")
    override func isEqual(toNumber other: NSNumber?) -> Bool { other.map { compare($0) == 0 } ?? false }

    @ObjCMethod("isEqual:")
    override func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSNumber.self) else { return false }
        return compare(other.unsafeCast(to: NSNumber.self)) == 0
    }

    // MARK: Arithmetic

    /// An operation as Darwin's NSDecimalNumber does it: computed in the
    /// behavior's rounding mode; on an error, the behavior's
    /// -exceptionDuringOperation:… asked (it raises, or gives a number to
    /// use, or nil for not a number); then rounded to its scale.
    private func perform(_ selector: String, _ other: NSNumber?, _ behavior: ObjCObject?,
                         _ operation: (PerryDecimal, PerryDecimal.Rounding) throws -> (result: PerryDecimal, lossOfPrecision: Bool))
        -> NSDecimalNumber {
        let behavior = behavior?.id ?? DecimalNumbers.defaultBehavior
        let (mode, scale) = DecimalNumbers.rounding(behavior)
        let rounding = PerryDecimal.Rounding(mode: mode)
        var result: PerryDecimal
        var code: UInt = 0
        do {
            let outcome = try operation(decimal, rounding)
            result = outcome.result
            if outcome.lossOfPrecision { code = 1 }
        } catch {
            result = .nan
            code = (error as? PerryDecimal.Failure)?.code ?? 3
        }
        if code != 0, let behavior,
           let replacement = DecimalNumbers.exception(behavior, operation: selector, error: code, left: objcObject, right: other?.id) {
            return NSDecimalNumber(objCReturnValue: replacement)
        }
        result = (try? result.round(scale: Int(scale), rounding: rounding)) ?? result
        return NSDecimalNumber.number(result)
    }

    @ObjCMethod("decimalNumberByAdding:")
    func adding(_ other: NSNumber?) -> NSDecimalNumber { adding(other, withBehavior: nil) }

    @ObjCMethod("decimalNumberByAdding:withBehavior:")
    func adding(_ other: NSNumber?, withBehavior behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberByAdding:withBehavior:", other, behavior) {
            try $0.add(DecimalNumbers.decimal(of: other?.id), rounding: $1)
        }
    }

    @ObjCMethod("decimalNumberBySubtracting:")
    func subtracting(_ other: NSNumber?) -> NSDecimalNumber { subtracting(other, withBehavior: nil) }

    @ObjCMethod("decimalNumberBySubtracting:withBehavior:")
    func subtracting(_ other: NSNumber?, withBehavior behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberBySubtracting:withBehavior:", other, behavior) {
            try $0.subtract(DecimalNumbers.decimal(of: other?.id), rounding: $1)
        }
    }

    @ObjCMethod("decimalNumberByMultiplyingBy:")
    func multiplying(by other: NSNumber?) -> NSDecimalNumber { multiplying(by: other, withBehavior: nil) }

    @ObjCMethod("decimalNumberByMultiplyingBy:withBehavior:")
    func multiplying(by other: NSNumber?, withBehavior behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberByMultiplyingBy:withBehavior:", other, behavior) {
            try $0.multiply(DecimalNumbers.decimal(of: other?.id), rounding: $1)
        }
    }

    @ObjCMethod("decimalNumberByDividingBy:")
    func dividing(by other: NSNumber?) -> NSDecimalNumber { dividing(by: other, withBehavior: nil) }

    @ObjCMethod("decimalNumberByDividingBy:withBehavior:")
    func dividing(by other: NSNumber?, withBehavior behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberByDividingBy:withBehavior:", other, behavior) {
            (try $0.divide(DecimalNumbers.decimal(of: other?.id), rounding: $1), false)
        }
    }

    @ObjCMethod("decimalNumberByRaisingToPower:")
    func raising(toPower power: UInt) -> NSDecimalNumber { raising(toPower: power, withBehavior: nil) }

    @ObjCMethod("decimalNumberByRaisingToPower:withBehavior:")
    func raising(toPower power: UInt, withBehavior behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberByRaisingToPower:withBehavior:", nil, behavior) {
            (try $0.power(Int(truncatingIfNeeded: power), rounding: $1), false)
        }
    }

    @ObjCMethod("decimalNumberByMultiplyingByPowerOf10:")
    func multiplying(byPowerOf10 power: Int16) -> NSDecimalNumber { multiplying(byPowerOf10: power, withBehavior: nil) }

    @ObjCMethod("decimalNumberByMultiplyingByPowerOf10:withBehavior:")
    func multiplying(byPowerOf10 power: Int16, withBehavior behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberByMultiplyingByPowerOf10:withBehavior:", nil, behavior) {
            decimal, _ in (try decimal.multiply(byPowerOf10: Int(power)), false)
        }
    }

    @ObjCMethod("decimalNumberByRoundingAccordingToBehavior:")
    func rounding(accordingTo behavior: ObjCObject?) -> NSDecimalNumber {
        perform("decimalNumberByRoundingAccordingToBehavior:", nil, behavior) { value, _ in (value, false) }
    }
}

/// What an NSDecimalNumberBehaviors object answers.
@ObjCWrapper("NSObject")
final class DecimalBehaviorObject: NSObject {
    @ObjCMethod("roundingMode") func roundingMode() -> UInt
    @ObjCMethod("scale") func scale() -> Int16
}

final class DecimalHandlerStorage {
    var mode: UInt = 0
    var scale: Int16 = Int16.max
    var raiseOnExactness = false
    var raiseOnOverflow = true
    var raiseOnUnderflow = true
    var raiseOnDivideByZero = true
    /// The fields the handler was unarchived with, to archive it again.
    var archived: ArchivedFields?
}

/// A shared NSDecimalNumber constant, never freed.
@ObjCClass("_PerryConstantDecimalNumber")
final class PerryConstantDecimalNumber: NSDecimalNumber {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
    }
}

/// NSDecimalNumberHandler: a rounding mode, a scale, and which errors
/// raise: NSDecimalNumberExactnessException, …OverflowException,
/// …UnderflowException and …DivideByZeroException, with Darwin's reasons.
@ObjCClass("NSDecimalNumberHandler")
public final class NSDecimalNumberHandler: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
    }

    private var storage: DecimalHandlerStorage {
        if let storage = Storage.get(objcObject, as: DecimalHandlerStorage.self) { return storage }
        let storage = DecimalHandlerStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    private static func make(_ cls: ObjCClass) -> NSDecimalNumberHandler? {
        Storage.allocate(cls.pointer).map { NSDecimalNumberHandler(objCOwned: $0) }
    }

    /// One, shared: plain rounding, no scale, raising on overflow,
    /// underflow and division by zero.
    @ObjCClassMethod("defaultDecimalNumberHandler")
    static func defaultHandler(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { DecimalNumbers.defaultHandler }

    @ObjCClassMethod("decimalNumberHandlerWithRoundingMode:scale:raiseOnExactness:raiseOnOverflow:raiseOnUnderflow:raiseOnDivideByZero:")
    static func handler(_ cls: ObjCClass, roundingMode: UInt, scale: Int16, raiseOnExactness: Bool, raiseOnOverflow: Bool,
                        raiseOnUnderflow: Bool, raiseOnDivideByZero: Bool) -> NSDecimalNumberHandler? {
        let handler = make(cls)
        handler?.set(roundingMode: roundingMode, scale: scale, raiseOnExactness: raiseOnExactness, raiseOnOverflow: raiseOnOverflow,
                     raiseOnUnderflow: raiseOnUnderflow, raiseOnDivideByZero: raiseOnDivideByZero)
        return handler
    }

    private func set(roundingMode: UInt, scale: Int16, raiseOnExactness: Bool, raiseOnOverflow: Bool, raiseOnUnderflow: Bool,
                     raiseOnDivideByZero: Bool) {
        let storage = self.storage
        storage.mode = roundingMode
        storage.scale = scale
        storage.raiseOnExactness = raiseOnExactness
        storage.raiseOnOverflow = raiseOnOverflow
        storage.raiseOnUnderflow = raiseOnUnderflow
        storage.raiseOnDivideByZero = raiseOnDivideByZero
    }

    /// -init: the default handler's settings.
    @ObjCMethod("init") func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("initWithRoundingMode:scale:raiseOnExactness:raiseOnOverflow:raiseOnUnderflow:raiseOnDivideByZero:")
    func initialize(roundingMode: UInt, scale: Int16, raiseOnExactness: Bool, raiseOnOverflow: Bool, raiseOnUnderflow: Bool,
                    raiseOnDivideByZero: Bool) -> Self {
        set(roundingMode: roundingMode, scale: scale, raiseOnExactness: raiseOnExactness, raiseOnOverflow: raiseOnOverflow,
            raiseOnUnderflow: raiseOnUnderflow, raiseOnDivideByZero: raiseOnDivideByZero)
        return self
    }

    private static let archivedFields: [ArchivedFields.Field] = [
        ("NS.roundingmode", .integer), ("NS.scale", .integer), ("NS.raise.exactness", .bool), ("NS.raise.overflow", .bool),
        ("NS.raise.underflow", .bool), ("NS.raise.dividebyzero", .bool),
    ]

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        let fields = ArchivedFields(coder: coder.id, fields: Self.archivedFields)
        if let mode = fields.integer("NS.roundingmode") { storage.mode = UInt(max(0, mode)) }
        if let scale = fields.integer("NS.scale") { storage.scale = Int16(truncatingIfNeeded: scale) }
        storage.archived = fields
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        if let archived = storage.archived { return archived.encode(coder: coder.id) }
        typealias EncodeInteger = @convention(c) (id?, SEL, Int, id?) -> Void
        let integer = unsafeBitCast(ObjC.msgSend, to: EncodeInteger.self)
        integer(coder.id, ObjC.selector("encodeInteger:forKey:"), Int(storage.mode), Strings.autoreleased("NS.roundingmode"))
        if storage.scale != Int16.max {
            integer(coder.id, ObjC.selector("encodeInteger:forKey:"), Int(storage.scale), Strings.autoreleased("NS.scale"))
        }
    }

    @ObjCMethod("roundingMode") func roundingMode() -> UInt { storage.mode }
    @ObjCMethod("scale") func scale() -> Int16 { storage.scale }

    /// Raises the error's exception if the handler raises on it; nil, for
    /// not a number, otherwise.
    @ObjCMethod("exceptionDuringOperation:error:leftOperand:rightOperand:")
    func exception(_ operation: UnsafeRawPointer?, error: UInt, left: ObjCObject?, right: ObjCObject?) -> UnsafeMutableRawPointer? {
        let storage = self.storage
        switch error {
        case 1 where storage.raiseOnExactness:
            Exceptions.raise(name: DecimalNumberExceptions.NSDecimalNumberExactnessException, reason: "NSDecimalNumber exactness exception")
        case 2 where storage.raiseOnUnderflow:
            Exceptions.raise(name: DecimalNumberExceptions.NSDecimalNumberUnderflowException, reason: "NSDecimalNumber underflow exception")
        case 3 where storage.raiseOnOverflow:
            Exceptions.raise(name: DecimalNumberExceptions.NSDecimalNumberOverflowException, reason: "NSDecimalNumber overflow exception")
        case 4 where storage.raiseOnDivideByZero:
            Exceptions.raise(name: DecimalNumberExceptions.NSDecimalNumberDivideByZeroException,
                             reason: "NSDecimalNumber divide by zero exception")
        default:
            return nil
        }
    }
}

/// NSDecimalNumber's exception names.
@ObjCConstants
enum DecimalNumberExceptions {
    static let NSDecimalNumberExactnessException = "NSDecimalNumberExactnessException"
    static let NSDecimalNumberOverflowException = "NSDecimalNumberOverflowException"
    static let NSDecimalNumberUnderflowException = "NSDecimalNumberUnderflowException"
    static let NSDecimalNumberDivideByZeroException = "NSDecimalNumberDivideByZeroException"
}
