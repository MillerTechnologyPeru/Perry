// Swift's numbers and Bool bridge to NSNumber, as Darwin's Foundation
// declares: each converts to a number holding its value, and back from any
// number, truncating; the conditional conversion succeeds when the value is
// exactly representable.


extension Int8: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.int8Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.int8Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = Int8(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int8(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int8(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int8?) {
        result = Int8(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int8?) -> Bool {
        result = Int8(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int8 {
        source.map { Int8(truncating: $0) } ?? 0
    }
}

extension UInt8: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.uint8Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.uint8Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = UInt8(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt8(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt8(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt8?) {
        result = UInt8(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt8?) -> Bool {
        result = UInt8(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt8 {
        source.map { UInt8(truncating: $0) } ?? 0
    }
}

extension Int16: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.int16Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.int16Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = Int16(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int16(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int16(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int16?) {
        result = Int16(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int16?) -> Bool {
        result = Int16(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int16 {
        source.map { Int16(truncating: $0) } ?? 0
    }
}

extension UInt16: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.uint16Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.uint16Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = UInt16(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt16(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt16(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt16?) {
        result = UInt16(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt16?) -> Bool {
        result = UInt16(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt16 {
        source.map { UInt16(truncating: $0) } ?? 0
    }
}

extension Int32: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.int32Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.int32Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = Int32(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int32(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int32(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int32?) {
        result = Int32(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int32?) -> Bool {
        result = Int32(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int32 {
        source.map { Int32(truncating: $0) } ?? 0
    }
}

extension UInt32: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.uint32Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.uint32Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = UInt32(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt32(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt32(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt32?) {
        result = UInt32(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt32?) -> Bool {
        result = UInt32(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt32 {
        source.map { UInt32(truncating: $0) } ?? 0
    }
}

extension Int64: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.int64Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.int64Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = Int64(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int64(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int64(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int64?) {
        result = Int64(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int64?) -> Bool {
        result = Int64(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int64 {
        source.map { Int64(truncating: $0) } ?? 0
    }
}

extension UInt64: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.uint64Value
    }

    public init(truncating number: __shared NSNumber) {
        self = number.uint64Value
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = UInt64(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt64(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt64(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt64?) {
        result = UInt64(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt64?) -> Bool {
        result = UInt64(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt64 {
        source.map { UInt64(truncating: $0) } ?? 0
    }
}

extension Int: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.intValue
    }

    public init(truncating number: __shared NSNumber) {
        self = number.intValue
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = Int(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = Int(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Int?) {
        result = Int(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Int?) -> Bool {
        result = Int(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int {
        source.map { Int(truncating: $0) } ?? 0
    }
}

extension UInt: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.uintValue
    }

    public init(truncating number: __shared NSNumber) {
        self = number.uintValue
    }

    public init?(exactly number: __shared NSNumber) {
        // Exact when the number's value, as a double or as a 64-bit
        // integer, is this type's.
        if let value = UInt(exactly: number.doubleValue), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt(exactly: number.int64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        if let value = UInt(exactly: number.uint64Value), NSNumber(value: value).isEqual(to: number) { self = value; return }
        return nil
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt?) {
        result = UInt(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout UInt?) -> Bool {
        result = UInt(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> UInt {
        source.map { UInt(truncating: $0) } ?? 0
    }
}

extension Float: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.floatValue
    }

    public init(truncating number: __shared NSNumber) {
        self = number.floatValue
    }

    public init?(exactly number: __shared NSNumber) {
        let value = number.floatValue
        guard value.isNaN ? number.doubleValue.isNaN : Double(value) == number.doubleValue else { return nil }
        self = value
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Float?) {
        result = Float(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Float?) -> Bool {
        result = Float(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Float {
        source.map { Float(truncating: $0) } ?? 0
    }
}

extension Double: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.doubleValue
    }

    public init(truncating number: __shared NSNumber) {
        self = number.doubleValue
    }

    public init?(exactly number: __shared NSNumber) {
        let value = number.doubleValue
        guard value.isNaN ? number.doubleValue.isNaN : Double(value) == number.doubleValue else { return nil }
        self = value
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Double?) {
        result = Double(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Double?) -> Bool {
        result = Double(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Double {
        source.map { Double(truncating: $0) } ?? 0
    }
}

extension Bool: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = number.boolValue
    }

    public init(truncating number: __shared NSNumber) {
        self = number.boolValue
    }

    public init?(exactly number: __shared NSNumber) {
        switch number.int64Value {
        case 0 where number.doubleValue == 0: self = false
        case 1 where number.doubleValue == 1: self = true
        default: return nil
        }
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: self)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout Bool?) {
        result = Bool(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout Bool?) -> Bool {
        result = Bool(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Bool {
        source.map { Bool(truncating: $0) } ?? false
    }
}

extension CGFloat: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNumber

    @available(swift, deprecated: 4, renamed: "init(truncating:)")
    public init(_ number: __shared NSNumber) {
        self = CGFloat(number.doubleValue)
    }

    public init(truncating number: __shared NSNumber) {
        self = CGFloat(number.doubleValue)
    }

    public init?(exactly number: __shared NSNumber) {
        guard let value = Double(exactly: number) else { return nil }
        self = CGFloat(value)
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNumber {
        NSNumber(value: Double(self))
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNumber, result: inout CGFloat?) {
        result = CGFloat(truncating: x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNumber, result: inout CGFloat?) -> Bool {
        result = CGFloat(exactly: x)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> CGFloat {
        source.map { CGFloat(truncating: $0) } ?? 0
    }
}

extension NSNumber {
    @nonobjc
    public convenience init(integerLiteral value: Int) {
        self.init(value: value)
    }

    @nonobjc
    public convenience init(floatLiteral value: Double) {
        self.init(value: value)
    }

    @nonobjc
    public convenience init(booleanLiteral value: Bool) {
        self.init(value: value)
    }
}
