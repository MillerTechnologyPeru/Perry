// DarwinBoolean: MacTypes' Boolean, an unsigned char, as Swift sees it.

@frozen public struct DarwinBoolean: ExpressibleByBooleanLiteral, Sendable {
    @usableFromInline
    internal var _value: UInt8

    @_transparent
    public init(_ value: Bool) {
        _value = value ? 1 : 0
    }

    @_transparent
    public var boolValue: Bool {
        _value != 0
    }

    @_transparent
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension DarwinBoolean: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(reflecting: boolValue)
    }
}

extension DarwinBoolean: CustomStringConvertible {
    public var description: String {
        boolValue ? "true" : "false"
    }
}

extension DarwinBoolean: Equatable {
    @_transparent
    public static func == (lhs: DarwinBoolean, rhs: DarwinBoolean) -> Bool {
        lhs.boolValue == rhs.boolValue
    }
}

extension DarwinBoolean: BitwiseCopyable {}

// What the compiler calls to bridge Bool and Boolean across C calls.
@_transparent
public func _convertBoolToDarwinBoolean(_ x: Bool) -> DarwinBoolean {
    DarwinBoolean(x)
}

@_transparent
public func _convertDarwinBooleanToBool(_ x: DarwinBoolean) -> Bool {
    x.boolValue
}
