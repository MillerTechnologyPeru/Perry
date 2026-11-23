import Darwin
import System

// XPCArray: an XPC array with typed subscripts, as XPCDictionary has. An
// index of XPC_ARRAY_APPEND (or the count) appends when setting.

public struct XPCArray {
    /// The array object.
    internal let object: xpc_object_t

    public init(_ value: xpc_object_t) {
        object = value
    }

    public init() {
        object = xpc_array_create(nil, 0)
    }

    public func withUnsafeUnderlyingArray<ReturnType>(_ closure: (xpc_object_t) throws -> ReturnType) rethrows -> ReturnType {
        try closure(object)
    }

    /// The value at an index, or nil past the end.
    internal func value(_ index: Int) -> xpc_object_t? {
        guard index >= 0, index < xpc_array_get_count(object) else { return nil }
        return xpc_array_get_value(object, index)
    }

    /// Sets the value at an index; nil sets a null object, as an array
    /// can't hold nothing.
    internal func set(_ index: Int, _ value: xpc_object_t?) {
        xpc_array_set_value(object, index == xpc_array_get_count(object) ? XPC_ARRAY_APPEND : index, value ?? xpc_null_create())
    }
}

extension XPCArray {
    public subscript(index: Int, as type: Bool.Type = Bool.self) -> Bool? {
        Objects.bool(value(index))
    }

    public subscript(index: Int) -> Bool? {
        get { Objects.bool(value(index)) }
        set { set(index, newValue.map { xpc_bool_create($0) }) }
    }

    public subscript(index: Int, as type: Bool.Type = Bool.self, default defaultValue: @autoclosure () -> Bool) -> Bool {
        Objects.bool(value(index)) ?? defaultValue()
    }
}

extension XPCArray {
    public subscript<T: BinaryInteger>(index: Int, as type: T.Type = T.self) -> T? {
        Objects.integer(value(index), as: T.self)
    }

    public subscript<T: SignedInteger>(index: Int) -> T? {
        get { Objects.integer(value(index), as: T.self) }
        set { set(index, newValue.map { xpc_int64_create(Int64($0)) }) }
    }

    public subscript<T: UnsignedInteger>(index: Int) -> T? {
        get { Objects.integer(value(index), as: T.self) }
        set { set(index, newValue.map { xpc_uint64_create(UInt64($0)) }) }
    }
}

extension XPCArray {
    public subscript<T: BinaryFloatingPoint>(index: Int, as type: T.Type = T.self) -> T? {
        Objects.floatingPoint(value(index), as: T.self)
    }

    public subscript<T: BinaryFloatingPoint>(index: Int) -> T? {
        get { Objects.floatingPoint(value(index), as: T.self) }
        set { set(index, newValue.map { xpc_double_create(Double($0)) }) }
    }

    public subscript<T: BinaryFloatingPoint>(index: Int, as type: T.Type = T.self, default defaultValue: @autoclosure () -> T) -> T {
        Objects.floatingPoint(value(index), as: T.self) ?? defaultValue()
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension XPCArray {
    /// A data value's bytes, which live as long as the dictionary holds
    /// the value.
    public subscript(index: Int, as type: RawSpan.Type = RawSpan.self) -> RawSpan? {
        @_lifetime(borrow self)
        get { dataSpan(value(index)) }
    }

    public subscript(index: Int) -> RawSpan? {
        @_lifetime(borrow self)
        get { dataSpan(value(index)) }
        set {
            if let span = newValue { set(index, makeData(span)) } else { set(index, nil) }
        }
    }

    @_lifetime(borrow self)
    private func dataSpan(_ value: xpc_object_t?) -> RawSpan? {
        guard let value, value.isType(XPC_TYPE_DATA), let bytes = xpc_data_get_bytes_ptr(value) else { return nil }
        let span = RawSpan(_unsafeStart: bytes, byteCount: xpc_data_get_length(value))
        return _overrideLifetime(span, borrowing: self)
    }
}

extension XPCArray {
    public subscript(index: Int, as type: String.Type = String.self) -> String? {
        Objects.string(value(index))
    }

    public subscript(index: Int) -> String? {
        get { Objects.string(value(index)) }
        set { set(index, newValue.map { xpc_string_create($0) }) }
    }
}

extension XPCArray {
    public subscript(index: Int, as type: uuid_t.Type = uuid_t.self) -> uuid_t? {
        Objects.uuid(value(index))
    }

    public subscript(index: Int) -> uuid_t? {
        get { Objects.uuid(value(index)) }
        set { set(index, newValue.map(Objects.makeUUID)) }
    }

    public subscript(index: Int, as type: uuid_t.Type = uuid_t.self, default defaultValue: @autoclosure () -> uuid_t) -> uuid_t {
        Objects.uuid(value(index)) ?? defaultValue()
    }
}

extension XPCArray {
    /// A duplicate of a file descriptor value, which the caller closes.
    public subscript(index: Int, as type: FileDescriptor.Type = FileDescriptor.self) -> FileDescriptor? {
        fileDescriptor(value(index))
    }

    public subscript(index: Int) -> FileDescriptor? {
        get { fileDescriptor(value(index)) }
        set { set(index, newValue.flatMap { xpc_fd_create($0.rawValue) }) }
    }

    public subscript(index: Int, as type: FileDescriptor.Type = FileDescriptor.self,
                     default defaultValue: @autoclosure () -> FileDescriptor) -> FileDescriptor {
        fileDescriptor(value(index)) ?? defaultValue()
    }
}


extension XPCArray {
    public subscript(index: Int, as type: XPCDictionary.Type = XPCDictionary.self) -> XPCDictionary? {
        Objects.dictionary(value(index))
    }

    public subscript(index: Int) -> XPCDictionary? {
        get { Objects.dictionary(value(index)) }
        set { set(index, newValue?.object) }
    }
}

extension XPCArray {
    public subscript(index: Int, as type: XPCArray.Type = XPCArray.self) -> XPCArray? {
        Objects.array(value(index))
    }

    public subscript(index: Int) -> XPCArray? {
        get { Objects.array(value(index)) }
        set { set(index, newValue?.object) }
    }

    public subscript(index: Int, as type: XPCArray.Type = XPCArray.self, default defaultValue: @autoclosure () -> XPCArray) -> XPCArray {
        Objects.array(value(index)) ?? defaultValue()
    }
}

extension XPCArray {
    public subscript(index: Int, as type: XPCEndpoint.Type = XPCEndpoint.self) -> XPCEndpoint? {
        Objects.endpoint(value(index))
    }

    public subscript(index: Int) -> XPCEndpoint? {
        get { Objects.endpoint(value(index)) }
        set { set(index, newValue?._endpoint) }
    }

    public subscript(index: Int, as type: XPCEndpoint.Type = XPCEndpoint.self,
                     default defaultValue: @autoclosure () -> XPCEndpoint) -> XPCEndpoint {
        Objects.endpoint(value(index)) ?? defaultValue()
    }
}

extension XPCArray {
    public subscript(index: Int, as type: any OS_xpc_object.Type = xpc_object_t.self) -> xpc_object_t? {
        value(index)
    }

    /// The value, if it is of the type given.
    public subscript(index: Int, as type: xpc_type_t) -> xpc_object_t? {
        guard let value = value(index), value.isType(type) else { return nil }
        return value
    }

    public subscript(index: Int) -> xpc_object_t? {
        get { value(index) }
        set { set(index, newValue) }
    }
}


extension XPCArray {
    public func copy(into destination: XPCArray) {
        forEach { (_: Int, value: xpc_object_t) in xpc_array_append_value(destination.object, value) }
    }

    public var isEmpty: Bool {
        count == 0
    }

    public var count: Int {
        xpc_array_get_count(object)
    }

    public func forEach(_ body: (_ index: Int, _ value: xpc_object_t) throws -> Void) rethrows {
        var failure: (any Error)?
        try withoutActuallyEscaping(body) { body in
            _ = xpc_array_apply(object) { index, value in
                do {
                    try body(index, value)
                    return true
                } catch {
                    failure = error
                    return false
                }
            }
            if let failure { throw failure }
        }
    }

    public typealias IndexValuePair = (index: Int, value: xpc_object_t)

    public func forEach(_ body: (IndexValuePair) throws -> Void) rethrows {
        try forEach { (index: Int, value: xpc_object_t) in try body((index: index, value: value)) }
    }

    public func map<ReturnType>(_ transform: (IndexValuePair) throws -> ReturnType) rethrows -> [ReturnType] {
        var results: [ReturnType] = []
        try forEach { (index: Int, value: xpc_object_t) in results.append(try transform((index: index, value: value))) }
        return results
    }
}

extension XPCArray: Equatable {
    public static func == (lhs: XPCArray, rhs: XPCArray) -> Bool {
        xpc_equal(lhs.object, rhs.object)
    }
}

extension XPCArray: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(xpc_hash(object))
    }
}

extension XPCArray: CustomDebugStringConvertible {
    public var debugDescription: String {
        Objects.describe(object)
    }
}
