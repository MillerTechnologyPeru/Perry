// ObjCBool: Objective-C's BOOL as Swift sees it. It is a signed char on an
// Intel Mac (and Mac Catalyst there) and a C bool everywhere else, and
// the struct's single stored value is laid out the same way.

@frozen public struct ObjCBool: ExpressibleByBooleanLiteral, Sendable {
#if (os(macOS) || targetEnvironment(macCatalyst)) && (arch(x86_64) || arch(i386))
    @usableFromInline
    internal var _value: Int8

    @_transparent
    public init(_ value: Bool) {
        _value = value ? 1 : 0
    }

    @_transparent
    public var boolValue: Bool {
        _value != 0
    }
#else
    @usableFromInline
    internal var _value: Bool

    @_transparent
    public init(_ value: Bool) {
        _value = value
    }

    @_transparent
    public var boolValue: Bool {
        _value
    }
#endif

    @_transparent
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension ObjCBool: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(reflecting: boolValue)
    }
}

extension ObjCBool: CustomStringConvertible {
    public var description: String {
        boolValue ? "true" : "false"
    }
}

extension ObjCBool: BitwiseCopyable {}

// What the compiler calls to bridge Bool and BOOL across C calls.
@_transparent
public func _convertBoolToObjCBool(_ x: Bool) -> ObjCBool {
    ObjCBool(x)
}

@_transparent
public func _convertObjCBoolToBool(_ x: ObjCBool) -> Bool {
    x.boolValue
}

@available(*, unavailable, message: "Use 'Bool' value 'true' instead")
public var YES: ObjCBool {
    ObjCBool(true)
}

@available(*, unavailable, message: "Use 'Bool' value 'false' instead")
public var NO: ObjCBool {
    ObjCBool(false)
}
