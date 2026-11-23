import Darwin

// The constants of <xpc/xpc.h> that are macros over the addresses of the
// library's data (the object types, the two booleans, the connection
// errors) or its constant strings, and the helpers the Swift types use to
// read and make objects.

// MARK: Data symbols

@_silgen_name("_xpc_type_connection") private func typeConnection()
@_silgen_name("_xpc_type_endpoint") private func typeEndpoint()
@_silgen_name("_xpc_type_null") private func typeNull()
@_silgen_name("_xpc_type_bool") private func typeBool()
@_silgen_name("_xpc_type_int64") private func typeInt64()
@_silgen_name("_xpc_type_uint64") private func typeUInt64()
@_silgen_name("_xpc_type_double") private func typeDouble()
@_silgen_name("_xpc_type_date") private func typeDate()
@_silgen_name("_xpc_type_data") private func typeData()
@_silgen_name("_xpc_type_string") private func typeString()
@_silgen_name("_xpc_type_uuid") private func typeUUID()
@_silgen_name("_xpc_type_fd") private func typeFD()
@_silgen_name("_xpc_type_shmem") private func typeShmem()
@_silgen_name("_xpc_type_array") private func typeArray()
@_silgen_name("_xpc_type_dictionary") private func typeDictionary()
@_silgen_name("_xpc_type_error") private func typeError()
@_silgen_name("_xpc_type_activity") private func typeActivity()
@_silgen_name("_xpc_type_rich_error") private func typeRichError()
@_silgen_name("_xpc_type_bundle") private func typeBundle()
@_silgen_name("_xpc_type_file_transfer") private func typeFileTransfer()
@_silgen_name("_xpc_type_mach_recv") private func typeMachReceive()
@_silgen_name("_xpc_type_mach_send") private func typeMachSend()
@_silgen_name("_xpc_type_mach_send_once") private func typeMachSendOnce()
@_silgen_name("_xpc_type_pipe") private func typePipe()
@_silgen_name("_xpc_type_pointer") private func typePointer()
@_silgen_name("_xpc_type_serializer") private func typeSerializer()
@_silgen_name("_xpc_type_service") private func typeService()
@_silgen_name("_xpc_type_service_instance") private func typeServiceInstance()

@_silgen_name("_xpc_bool_true") private func boolTrue()
@_silgen_name("_xpc_bool_false") private func boolFalse()
@_silgen_name("_xpc_error_connection_interrupted") private func errorInterrupted()
@_silgen_name("_xpc_error_connection_invalid") private func errorInvalid()
@_silgen_name("_xpc_error_termination_imminent") private func errorTerminationImminent()
@_silgen_name("_xpc_error_peer_code_signing_requirement") private func errorPeerRequirement()
@_silgen_name("_xpc_error_key_description") private func errorKeyDescription()
@_silgen_name("_xpc_event_key_name") private func eventKeyName()

/// A symbol's address.
private func address(_ symbol: @convention(thin) () -> Void) -> OpaquePointer {
    unsafeBitCast(symbol, to: OpaquePointer.self)
}

/// The object at a symbol's address.
private func object(_ symbol: @convention(thin) () -> Void) -> xpc_object_t {
    unsafeBitCast(symbol, to: xpc_object_t.self)
}

/// The string a symbol's constant pointer points to.
private func string(_ symbol: @convention(thin) () -> Void) -> UnsafePointer<CChar> {
    unsafeBitCast(symbol, to: UnsafePointer<UnsafePointer<CChar>>.self).pointee
}

public var XPC_TYPE_CONNECTION: xpc_type_t { address(typeConnection) }
public var XPC_TYPE_ENDPOINT: xpc_type_t { address(typeEndpoint) }
public var XPC_TYPE_NULL: xpc_type_t { address(typeNull) }
public var XPC_TYPE_BOOL: xpc_type_t { address(typeBool) }
public var XPC_TYPE_INT64: xpc_type_t { address(typeInt64) }
public var XPC_TYPE_UINT64: xpc_type_t { address(typeUInt64) }
public var XPC_TYPE_DOUBLE: xpc_type_t { address(typeDouble) }
public var XPC_TYPE_DATE: xpc_type_t { address(typeDate) }
public var XPC_TYPE_DATA: xpc_type_t { address(typeData) }
public var XPC_TYPE_STRING: xpc_type_t { address(typeString) }
public var XPC_TYPE_UUID: xpc_type_t { address(typeUUID) }
public var XPC_TYPE_FD: xpc_type_t { address(typeFD) }
public var XPC_TYPE_SHMEM: xpc_type_t { address(typeShmem) }
public var XPC_TYPE_ARRAY: xpc_type_t { address(typeArray) }
public var XPC_TYPE_DICTIONARY: xpc_type_t { address(typeDictionary) }
public var XPC_TYPE_ERROR: xpc_type_t { address(typeError) }
public var XPC_TYPE_ACTIVITY: xpc_type_t { address(typeActivity) }
public var XPC_TYPE_RICH_ERROR: xpc_type_t { address(typeRichError) }
public var XPC_TYPE_BUNDLE: xpc_type_t { address(typeBundle) }
public var XPC_TYPE_FILE_TRANSFER: xpc_type_t { address(typeFileTransfer) }
public var XPC_TYPE_MACH_RECV: xpc_type_t { address(typeMachReceive) }
public var XPC_TYPE_MACH_SEND: xpc_type_t { address(typeMachSend) }
public var XPC_TYPE_MACH_SEND_ONCE: xpc_type_t { address(typeMachSendOnce) }
public var XPC_TYPE_PIPE: xpc_type_t { address(typePipe) }
public var XPC_TYPE_POINTER: xpc_type_t { address(typePointer) }
public var XPC_TYPE_SERIALIZER: xpc_type_t { address(typeSerializer) }
public var XPC_TYPE_SERVICE: xpc_type_t { address(typeService) }
public var XPC_TYPE_SERVICE_INSTANCE: xpc_type_t { address(typeServiceInstance) }

public var XPC_ERROR_KEY_DESCRIPTION: UnsafePointer<CChar> { string(errorKeyDescription) }
public var XPC_EVENT_KEY_NAME: UnsafePointer<CChar> { string(eventKeyName) }

public var XPC_BOOL_TRUE: xpc_object_t { object(boolTrue) }
public var XPC_BOOL_FALSE: xpc_object_t { object(boolFalse) }

/// XPC_ARRAY_APPEND, (size_t)-1: the index that appends.
public var XPC_ARRAY_APPEND: size_t { -1 }

public var XPC_ERROR_CONNECTION_INTERRUPTED: xpc_object_t { object(errorInterrupted) }
public var XPC_ERROR_CONNECTION_INVALID: xpc_object_t { object(errorInvalid) }
public var XPC_ERROR_TERMINATION_IMMINENT: xpc_object_t { object(errorTerminationImminent) }
public var XPC_ERROR_PEER_CODE_SIGNING_REQUIREMENT: xpc_object_t { object(errorPeerRequirement) }

// MARK: Reference counting

/// Retains an object, for C code that releases it; Swift code needs
/// neither.
public func xpc_retain(_ object: xpc_object_t) -> xpc_object_t {
    _ = Unmanaged.passUnretained(object as AnyObject).retain()
    return object
}

public func xpc_release(_ object: xpc_object_t) {
    Unmanaged.passUnretained(object as AnyObject).release()
}

// MARK: Reading and making objects

extension OS_xpc_object {
    /// Whether the object is of the type given.
    internal func isType(_ type: xpc_type_t) -> Bool {
        xpc_get_type(self) == type
    }
}

/// An object's value, as Swift reads it.
internal enum Objects {
    static func bool(_ object: xpc_object_t?) -> Bool? {
        guard let object, object.isType(XPC_TYPE_BOOL) else { return nil }
        return xpc_bool_get_value(object)
    }

    static func integer<T: BinaryInteger>(_ object: xpc_object_t?, as type: T.Type) -> T? {
        guard let object else { return nil }
        if object.isType(XPC_TYPE_INT64) { return T(exactly: xpc_int64_get_value(object)) }
        if object.isType(XPC_TYPE_UINT64) { return T(exactly: xpc_uint64_get_value(object)) }
        return nil
    }

    static func floatingPoint<T: BinaryFloatingPoint>(_ object: xpc_object_t?, as type: T.Type) -> T? {
        guard let object, object.isType(XPC_TYPE_DOUBLE) else { return nil }
        return T(xpc_double_get_value(object))
    }

    static func string(_ object: xpc_object_t?) -> String? {
        guard let object, object.isType(XPC_TYPE_STRING), let chars = xpc_string_get_string_ptr(object) else { return nil }
        return String(cString: chars)
    }

    static func uuid(_ object: xpc_object_t?) -> uuid_t? {
        guard let object, object.isType(XPC_TYPE_UUID), let bytes = xpc_uuid_get_bytes(object) else { return nil }
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { $0.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: 16)) }
        return uuid
    }

    static func makeUUID(_ uuid: uuid_t) -> xpc_object_t {
        withUnsafeBytes(of: uuid) { xpc_uuid_create($0.bindMemory(to: UInt8.self).baseAddress!) }
    }

    static func dictionary(_ object: xpc_object_t?) -> XPCDictionary? {
        guard let object, object.isType(XPC_TYPE_DICTIONARY) else { return nil }
        return XPCDictionary(object)
    }

    static func array(_ object: xpc_object_t?) -> XPCArray? {
        guard let object, object.isType(XPC_TYPE_ARRAY) else { return nil }
        return XPCArray(object)
    }

    static func endpoint(_ object: xpc_object_t?) -> XPCEndpoint? {
        guard let object, object.isType(XPC_TYPE_ENDPOINT) else { return nil }
        return XPCEndpoint(object)
    }

    /// The object's description, from xpc_copy_description.
    static func describe(_ object: xpc_object_t) -> String {
        let description = xpc_copy_description(object)
        defer { free(description) }
        return String(cString: description)
    }
}
