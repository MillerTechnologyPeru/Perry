import Darwin
import System

// XPCDictionary: an XPC dictionary with typed subscripts. Reading a key as
// a type gives nil when the value is missing or of another type; setting
// nil removes the key.

public struct XPCDictionary {
    /// The dictionary object.
    internal let object: xpc_object_t

    public init(_ value: xpc_object_t) {
        object = value
    }

    public init() {
        object = xpc_dictionary_create(nil, nil, 0)
    }

    public func withUnsafeUnderlyingDictionary<ReturnType>(_ closure: (xpc_object_t) throws -> ReturnType) rethrows -> ReturnType {
        try closure(object)
    }

    /// The value at a key.
    internal func value(_ key: String) -> xpc_object_t? {
        xpc_dictionary_get_value(object, key)
    }

    /// Sets the value at a key, or removes it for nil.
    internal func set(_ key: String, _ value: xpc_object_t?) {
        xpc_dictionary_set_value(object, key, value)
    }
}

extension XPCDictionary {
    public subscript(key: String, as type: Bool.Type = Bool.self) -> Bool? {
        Objects.bool(value(key))
    }

    public subscript(key: String) -> Bool? {
        get { Objects.bool(value(key)) }
        set { set(key, newValue.map { xpc_bool_create($0) }) }
    }

    public subscript(key: String, as type: Bool.Type = Bool.self, default defaultValue: @autoclosure () -> Bool) -> Bool {
        Objects.bool(value(key)) ?? defaultValue()
    }
}

extension XPCDictionary {
    public subscript<T: BinaryInteger>(key: String, as type: T.Type = T.self) -> T? {
        Objects.integer(value(key), as: T.self)
    }

    public subscript<T: SignedInteger>(key: String) -> T? {
        get { Objects.integer(value(key), as: T.self) }
        set { set(key, newValue.map { xpc_int64_create(Int64($0)) }) }
    }

    public subscript<T: UnsignedInteger>(key: String) -> T? {
        get { Objects.integer(value(key), as: T.self) }
        set { set(key, newValue.map { xpc_uint64_create(UInt64($0)) }) }
    }
}

extension XPCDictionary {
    public subscript<T: BinaryFloatingPoint>(key: String, as type: T.Type = T.self) -> T? {
        Objects.floatingPoint(value(key), as: T.self)
    }

    public subscript<T: BinaryFloatingPoint>(key: String) -> T? {
        get { Objects.floatingPoint(value(key), as: T.self) }
        set { set(key, newValue.map { xpc_double_create(Double($0)) }) }
    }

    public subscript<T: BinaryFloatingPoint>(key: String, as type: T.Type = T.self, default defaultValue: @autoclosure () -> T) -> T {
        Objects.floatingPoint(value(key), as: T.self) ?? defaultValue()
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension XPCDictionary {
    /// A data value's bytes, which live as long as the dictionary holds
    /// the value.
    public subscript(key: String, as type: RawSpan.Type = RawSpan.self) -> RawSpan? {
        @_lifetime(borrow self)
        get { dataSpan(value(key)) }
    }

    public subscript(key: String) -> RawSpan? {
        @_lifetime(borrow self)
        get { dataSpan(value(key)) }
        set {
            if let span = newValue { set(key, makeData(span)) } else { set(key, nil) }
        }
    }

    @_lifetime(borrow self)
    private func dataSpan(_ value: xpc_object_t?) -> RawSpan? {
        guard let value, value.isType(XPC_TYPE_DATA), let bytes = xpc_data_get_bytes_ptr(value) else { return nil }
        let span = RawSpan(_unsafeStart: bytes, byteCount: xpc_data_get_length(value))
        return _overrideLifetime(span, borrowing: self)
    }
}

/// A data object with a span's bytes.
@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
internal func makeData(_ span: RawSpan) -> xpc_object_t {
    span.withUnsafeBytes { xpc_data_create($0.baseAddress, $0.count) }
}

extension XPCDictionary {
    public subscript(key: String, as type: String.Type = String.self) -> String? {
        Objects.string(value(key))
    }

    public subscript(key: String) -> String? {
        get { Objects.string(value(key)) }
        set { set(key, newValue.map { xpc_string_create($0) }) }
    }
}

extension XPCDictionary {
    public subscript(key: String, as type: uuid_t.Type = uuid_t.self) -> uuid_t? {
        Objects.uuid(value(key))
    }

    public subscript(key: String) -> uuid_t? {
        get { Objects.uuid(value(key)) }
        set { set(key, newValue.map(Objects.makeUUID)) }
    }

    public subscript(key: String, as type: uuid_t.Type = uuid_t.self, default defaultValue: @autoclosure () -> uuid_t) -> uuid_t {
        Objects.uuid(value(key)) ?? defaultValue()
    }
}

extension XPCDictionary {
    /// A duplicate of a file descriptor value, which the caller closes.
    public subscript(key: String, as type: FileDescriptor.Type = FileDescriptor.self) -> FileDescriptor? {
        fileDescriptor(value(key))
    }

    public subscript(key: String) -> FileDescriptor? {
        get { fileDescriptor(value(key)) }
        set { set(key, newValue.flatMap { xpc_fd_create($0.rawValue) }) }
    }

    public subscript(key: String, as type: FileDescriptor.Type = FileDescriptor.self,
                     default defaultValue: @autoclosure () -> FileDescriptor) -> FileDescriptor {
        fileDescriptor(value(key)) ?? defaultValue()
    }
}

/// A duplicate of a file descriptor object's descriptor.
internal func fileDescriptor(_ object: xpc_object_t?) -> FileDescriptor? {
    guard let object, object.isType(XPC_TYPE_FD) else { return nil }
    let fd = xpc_fd_dup(object)
    return fd < 0 ? nil : FileDescriptor(rawValue: fd)
}

extension XPCDictionary {
    public subscript(key: String, as type: XPCDictionary.Type = XPCDictionary.self) -> XPCDictionary? {
        Objects.dictionary(value(key))
    }

    public subscript(key: String) -> XPCDictionary? {
        get { Objects.dictionary(value(key)) }
        set { set(key, newValue?.object) }
    }
}

extension XPCDictionary {
    public subscript(key: String, as type: XPCArray.Type = XPCArray.self) -> XPCArray? {
        Objects.array(value(key))
    }

    public subscript(key: String) -> XPCArray? {
        get { Objects.array(value(key)) }
        set { set(key, newValue?.object) }
    }

    public subscript(key: String, as type: XPCArray.Type = XPCArray.self, default defaultValue: @autoclosure () -> XPCArray) -> XPCArray {
        Objects.array(value(key)) ?? defaultValue()
    }
}

extension XPCDictionary {
    public subscript(key: String, as type: XPCEndpoint.Type = XPCEndpoint.self) -> XPCEndpoint? {
        Objects.endpoint(value(key))
    }

    public subscript(key: String) -> XPCEndpoint? {
        get { Objects.endpoint(value(key)) }
        set { set(key, newValue?._endpoint) }
    }
}

extension XPCDictionary {
    public subscript(key: String, as type: any OS_xpc_object.Type = xpc_object_t.self) -> xpc_object_t? {
        value(key)
    }

    /// The value, if it is of the type given.
    public subscript(key: String, as type: xpc_type_t) -> xpc_object_t? {
        guard let value = value(key), value.isType(type) else { return nil }
        return value
    }

    public subscript(key: String) -> xpc_object_t? {
        get { value(key) }
        set { set(key, newValue) }
    }
}

extension XPCDictionary {
    /// Copies every key and value into another dictionary.
    public func copy(into destination: XPCDictionary) {
        forEach { key, value in destination.set(key, value) }
    }

    @discardableResult
    public func removeValue(forKey key: String) -> xpc_object_t? {
        let removed = value(key)
        set(key, nil)
        return removed
    }

    public var isEmpty: Bool {
        count == 0
    }

    public var count: Int {
        xpc_dictionary_get_count(object)
    }

    public func forEach(_ body: (_ key: String, _ value: xpc_object_t) throws -> Void) rethrows {
        // The applier is a block that can't throw: the first error stops
        // it and is thrown after.
        var failure: (any Error)?
        try withoutActuallyEscaping(body) { body in
            _ = xpc_dictionary_apply(object) { key, value in
                do {
                    try body(String(cString: key), value)
                    return true
                } catch {
                    failure = error
                    return false
                }
            }
            if let failure { throw failure }
        }
    }

    public typealias KeyValuePair = (key: String, value: xpc_object_t)

    public func forEach(_ body: (KeyValuePair) throws -> Void) rethrows {
        try forEach { (key: String, value: xpc_object_t) in try body((key: key, value: value)) }
    }

    public func map<ReturnType>(_ transform: (KeyValuePair) throws -> ReturnType) rethrows -> [ReturnType] {
        var results: [ReturnType] = []
        try forEach { (key: String, value: xpc_object_t) in results.append(try transform((key: key, value: value))) }
        return results
    }

    public var keys: [String] {
        map { $0.key }
    }

    public var values: [xpc_object_t] {
        map { $0.value }
    }
}

extension XPCDictionary {
    /// Sends a reply to the message this dictionary is: a reply made for
    /// it, holding the reply's keys and values, to its sender.
    public func reply(_ reply: XPCDictionary) {
        guard let made = xpc_dictionary_create_reply(object), let connection = xpc_dictionary_get_remote_connection(object) else {
            return
        }
        reply.copy(into: XPCDictionary(made))
        xpc_connection_send_message(connection, made)
    }
}

extension XPCDictionary: Equatable {
    public static func == (lhs: XPCDictionary, rhs: XPCDictionary) -> Bool {
        xpc_equal(lhs.object, rhs.object)
    }
}

extension XPCDictionary: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(xpc_hash(object))
    }
}

extension XPCDictionary: CustomDebugStringConvertible {
    public var debugDescription: String {
        Objects.describe(object)
    }
}
