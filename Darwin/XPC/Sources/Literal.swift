// XPCLiteralValue: a value of a dictionary literal, made into the XPC
// object it will be stored as.

public struct XPCLiteralValue {
    /// The object.
    internal let object: xpc_object_t

    public init(_ object: xpc_object_t) {
        self.object = object
    }

    public init(_ value: String) {
        object = xpc_string_create(value)
    }

    public init<T: SignedInteger>(_ value: T) {
        object = xpc_int64_create(Int64(value))
    }

    public init<T: UnsignedInteger>(_ value: T) {
        object = xpc_uint64_create(UInt64(value))
    }

    public init<T: BinaryFloatingPoint>(_ value: T) {
        object = xpc_double_create(Double(value))
    }

    public init(_ value: Bool) {
        object = xpc_bool_create(value)
    }

    public init(_ value: XPCDictionary) {
        object = value.object
    }
}

extension XPCLiteralValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension XPCLiteralValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension XPCLiteralValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension XPCLiteralValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value)
    }
}

extension XPCDictionary: ExpressibleByDictionaryLiteral {
    public typealias Key = String
    public typealias Value = XPCLiteralValue

    public init(dictionaryLiteral elements: (String, XPCLiteralValue)...) {
        self.init()
        for (key, value) in elements {
            set(key, value.object)
        }
    }
}
