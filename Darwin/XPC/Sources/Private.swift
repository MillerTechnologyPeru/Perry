import Darwin

// Members the SDK's XPC library exports beyond its public interface,
// where their types say what they do: byte-array values, UUID objects,
// dictionary coding and replies, and audit tokens' fields.

@_silgen_name("xpc_dictionary_get_audit_token")
private func dictionaryAuditToken(_ dictionary: xpc_object_t, _ token: UnsafeMutablePointer<audit_token_t>)

/// The UUID of a UUID object.
public func xpc_uuid_get_uuid(_ object: xpc_object_t) -> uuid_t? {
    Objects.uuid(object)
}

public func xpc_uuid_create_with_uuid(_ uuid: uuid_t) -> xpc_object_t {
    Objects.makeUUID(uuid)
}

/// A data object's bytes.
private func bytes(_ object: xpc_object_t?) -> [UInt8]? {
    guard let object, object.isType(XPC_TYPE_DATA) else { return nil }
    let count = xpc_data_get_length(object)
    guard count > 0, let start = xpc_data_get_bytes_ptr(object) else { return [] }
    return Array(UnsafeRawBufferPointer(start: start, count: count))
}

private func data(_ bytes: [UInt8]) -> xpc_object_t {
    bytes.withUnsafeBytes { xpc_data_create($0.baseAddress, $0.count) }
}

extension XPCDictionary {
    public subscript(key: String, as type: [UInt8].Type = [UInt8].self) -> [UInt8]? {
        bytes(value(key))
    }

    public subscript(key: String) -> [UInt8]? {
        get { bytes(value(key)) }
        set { set(key, newValue.map(data)) }
    }

    public func contains(key: String) -> Bool {
        value(key) != nil
    }

    /// A reply made for the message this dictionary is.
    public func createReply() -> XPCDictionary? {
        xpc_dictionary_create_reply(object).map(XPCDictionary.init)
    }

    /// Sends this reply to the sender of the message it was made for.
    public func sendReply() {
        guard let connection = xpc_dictionary_get_remote_connection(object) else { return }
        xpc_connection_send_message(connection, object)
    }

    public func encode<T: Encodable>(_ value: T, forKey key: String, withUserInfo userInfo: [CodingUserInfoKey: Any]) throws {
        set(key, try encodeObject(value, userInfo: userInfo))
    }

    public func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        try encode(value, forKey: key, withUserInfo: [:])
    }

    public func decode<T: Decodable>(as type: T.Type, forKey key: String, withUserInfo userInfo: [CodingUserInfoKey: Any]) throws -> T {
        guard let object = value(key) else {
            throw DecodingError.valueNotFound(type, .init(codingPath: [], debugDescription: "No value for \(key)"))
        }
        return try decodeObject(type, from: object, userInfo: userInfo)
    }

    public func decode<T: Decodable>(as type: T.Type, forKey key: String) throws -> T {
        try decode(as: type, forKey: key, withUserInfo: [:])
    }

    /// The audit token of the message's sender.
    public var auditToken: audit_token_t {
        var token = audit_token_t()
        dictionaryAuditToken(object, &token)
        return token
    }
}

extension XPCReceivedMessage {
    public var auditToken: audit_token_t {
        dictionary.auditToken
    }
}

// An audit token's words: the audit user, the effective and real user and
// group, the process, its audit session and its exec count.
extension audit_token_t {
    private func word(_ index: Int) -> UInt32 {
        withUnsafeBytes(of: val) { $0.load(fromByteOffset: index * 4, as: UInt32.self) }
    }

    public var auid: UInt32 { word(0) }
    public var euid: UInt32 { word(1) }
    public var egid: UInt32 { word(2) }
    public var ruid: UInt32 { word(3) }
    public var rgid: UInt32 { word(4) }
    public var pid: UInt32 { word(5) }
    public var asid: UInt32 { word(6) }
    public var execcnt: UInt32 { word(7) }

    /// Whether the token is not INVALID_AUDIT_TOKEN_VALUE.
    public var isValid: Bool {
        (0..<8).contains { word($0) != .max }
    }

    /// Whether both tokens name the same process: its ID and exec count.
    public func fromSameProcessAs(_ other: audit_token_t) -> Bool {
        pid == other.pid && execcnt == other.execcnt
    }
}
