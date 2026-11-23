// Codable values as XPC objects, for the messages XPCSession sends and
// XPCReceivedMessage decodes: a keyed container is a dictionary, an
// unkeyed one an array, and single values the scalar objects (Bool,
// int64, uint64, double, string); XPC's own types are stored as their
// objects.

/// The object a value encodes to.
internal func encodeObject<T: Encodable>(_ value: T, userInfo: [CodingUserInfoKey: Any] = [:]) throws -> xpc_object_t {
    try ObjectEncoder(codingPath: [], userInfo: userInfo).child(value, at: [])
}

/// A value decoded from an object.
internal func decodeObject<T: Decodable>(_ type: T.Type, from object: xpc_object_t, userInfo: [CodingUserInfoKey: Any] = [:]) throws -> T {
    try ObjectDecoder(object: object, codingPath: [], userInfo: userInfo).child(type, object, at: [])
}

/// The object of a value XPC stores as itself.
private func directObject<T>(_ value: T) -> xpc_object_t? {
    switch value {
    case let dictionary as XPCDictionary: return dictionary.object
    case let array as XPCArray: return array.object
    case let endpoint as XPCEndpoint: return endpoint._endpoint
    default: return nil
    }
}

/// A value of a type XPC stores as itself.
private func directValue<T>(_ object: xpc_object_t) -> T? {
    if T.self == XPCDictionary.self { return Objects.dictionary(object) as? T }
    if T.self == XPCArray.self { return Objects.array(object) as? T }
    if T.self == XPCEndpoint.self { return Objects.endpoint(object) as? T }
    return nil
}

// MARK: Encoding

internal final class ObjectEncoder: Encoder {
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    /// What the value encoded as, once it has.
    var result: xpc_object_t?

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let dictionary = result.flatMap { $0.isType(XPC_TYPE_DICTIONARY) ? $0 : nil } ?? xpc_dictionary_create(nil, nil, 0)
        result = dictionary
        return KeyedEncodingContainer(KeyedEncoder(dictionary: dictionary, encoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        let array = result.flatMap { $0.isType(XPC_TYPE_ARRAY) ? $0 : nil } ?? xpc_array_create(nil, 0)
        result = array
        return UnkeyedEncoder(array: array, encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleEncoder(encoder: self)
    }

    /// The object of a child value at a path.
    func child<T: Encodable>(_ value: T, at path: [any CodingKey]) throws -> xpc_object_t {
        if let object = directObject(value) { return object }
        if let object = scalar(value) { return object }
        let encoder = ObjectEncoder(codingPath: path, userInfo: userInfo)
        try value.encode(to: encoder)
        return encoder.result ?? xpc_dictionary_create(nil, nil, 0)
    }
}

/// The object of a scalar value: a Bool, a number or a string.
private func scalar<T>(_ value: T) -> xpc_object_t? {
    switch value {
    case let value as Bool: return xpc_bool_create(value)
    case let value as String: return xpc_string_create(value)
    case let value as Double: return xpc_double_create(value)
    case let value as Float: return xpc_double_create(Double(value))
    case let value as any SignedInteger & FixedWidthInteger: return xpc_int64_create(Int64(value))
    case let value as any UnsignedInteger & FixedWidthInteger: return xpc_uint64_create(UInt64(value))
    default: return nil
    }
}

private struct KeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let dictionary: xpc_object_t
    let encoder: ObjectEncoder
    let codingPath: [any CodingKey]

    func encodeNil(forKey key: Key) throws {
        xpc_dictionary_set_value(dictionary, key.stringValue, xpc_null_create())
    }

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        xpc_dictionary_set_value(dictionary, key.stringValue, try encoder.child(value, at: codingPath + [key]))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let nested = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(dictionary, key.stringValue, nested)
        return KeyedEncodingContainer(KeyedEncoder<NestedKey>(dictionary: nested, encoder: encoder, codingPath: codingPath + [key]))
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let nested = xpc_array_create(nil, 0)
        xpc_dictionary_set_value(dictionary, key.stringValue, nested)
        return UnkeyedEncoder(array: nested, encoder: encoder, codingPath: codingPath + [key])
    }

    func superEncoder() -> any Encoder {
        DeferredEncoder(codingPath: codingPath, userInfo: encoder.userInfo) { [dictionary] in
            xpc_dictionary_set_value(dictionary, "super", $0)
        }
    }

    func superEncoder(forKey key: Key) -> any Encoder {
        DeferredEncoder(codingPath: codingPath + [key], userInfo: encoder.userInfo) { [dictionary] in
            xpc_dictionary_set_value(dictionary, key.stringValue, $0)
        }
    }
}

private struct UnkeyedEncoder: UnkeyedEncodingContainer {
    let array: xpc_object_t
    let encoder: ObjectEncoder
    let codingPath: [any CodingKey]

    var count: Int { xpc_array_get_count(array) }

    private var nextKey: any CodingKey { IndexKey(count) }

    func encodeNil() throws {
        xpc_array_append_value(array, xpc_null_create())
    }

    func encode<T: Encodable>(_ value: T) throws {
        xpc_array_append_value(array, try encoder.child(value, at: codingPath + [nextKey]))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let nested = xpc_dictionary_create(nil, nil, 0)
        let path = codingPath + [nextKey]
        xpc_array_append_value(array, nested)
        return KeyedEncodingContainer(KeyedEncoder<NestedKey>(dictionary: nested, encoder: encoder, codingPath: path))
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let nested = xpc_array_create(nil, 0)
        let path = codingPath + [nextKey]
        xpc_array_append_value(array, nested)
        return UnkeyedEncoder(array: nested, encoder: encoder, codingPath: path)
    }

    func superEncoder() -> any Encoder {
        // Holds the array's place, filled when the encoder is done.
        let index = count
        xpc_array_append_value(array, xpc_null_create())
        return DeferredEncoder(codingPath: codingPath + [IndexKey(index)], userInfo: encoder.userInfo) { [array] in
            xpc_array_set_value(array, index, $0)
        }
    }
}

private struct SingleEncoder: SingleValueEncodingContainer {
    let encoder: ObjectEncoder

    var codingPath: [any CodingKey] { encoder.codingPath }

    func encodeNil() throws {
        encoder.result = xpc_null_create()
    }

    func encode<T: Encodable>(_ value: T) throws {
        encoder.result = try encoder.child(value, at: codingPath)
    }
}

/// An encoder that stores its result where its owner says when it goes.
private final class DeferredEncoder: Encoder {
    private let encoder: ObjectEncoder
    private let store: (xpc_object_t) -> Void

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any], store: @escaping (xpc_object_t) -> Void) {
        encoder = ObjectEncoder(codingPath: codingPath, userInfo: userInfo)
        self.store = store
    }

    deinit {
        store(encoder.result ?? xpc_dictionary_create(nil, nil, 0))
    }

    var codingPath: [any CodingKey] { encoder.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { encoder.userInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        encoder.container(keyedBy: type)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        encoder.unkeyedContainer()
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        encoder.singleValueContainer()
    }
}

private struct IndexKey: CodingKey {
    let intValue: Int?
    var stringValue: String { "Index \(intValue ?? 0)" }

    init(_ index: Int) {
        intValue = index
    }

    init?(stringValue: String) {
        return nil
    }

    init?(intValue: Int) {
        self.intValue = intValue
    }
}

// MARK: Decoding

internal struct ObjectDecoder: Decoder {
    let object: xpc_object_t
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard object.isType(XPC_TYPE_DICTIONARY) else {
            throw mismatch([String: Any].self, "a dictionary")
        }
        return KeyedDecodingContainer(KeyedDecoder(dictionary: object, decoder: self))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard object.isType(XPC_TYPE_ARRAY) else {
            throw mismatch([Any].self, "an array")
        }
        return UnkeyedDecoder(array: object, decoder: self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleDecoder(decoder: self)
    }

    func mismatch(_ type: Any.Type, _ expected: String) -> DecodingError {
        .typeMismatch(type, .init(codingPath: codingPath, debugDescription: "Expected \(expected), found \(Objects.describe(object))"))
    }

    /// A child value at a path.
    func child<T: Decodable>(_ type: T.Type, _ object: xpc_object_t, at path: [any CodingKey]) throws -> T {
        if let value: T = directValue(object) { return value }
        let child = ObjectDecoder(object: object, codingPath: path, userInfo: userInfo)
        if let value = try child.scalar(type) { return value }
        return try T(from: child)
    }

    /// A scalar of the type, if it is one.
    func scalar<T>(_ type: T.Type) throws -> T? {
        func value<V>(_ value: V?) throws -> T {
            guard let value else { throw mismatch(type, "\(type)") }
            return value as! T
        }
        switch type {
        case is Bool.Type: return try value(Objects.bool(object))
        case is String.Type: return try value(Objects.string(object))
        case is Double.Type: return try value(Objects.floatingPoint(object, as: Double.self))
        case is Float.Type: return try value(Objects.floatingPoint(object, as: Float.self))
        case let integer as any FixedWidthInteger.Type: return try value(integerValue(integer))
        default: return nil
        }
    }

    private func integerValue<I: FixedWidthInteger>(_ type: I.Type) -> I? {
        Objects.integer(object, as: I.self)
    }
}

private struct KeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dictionary: xpc_object_t
    let decoder: ObjectDecoder

    var codingPath: [any CodingKey] { decoder.codingPath }

    var allKeys: [Key] {
        XPCDictionary(dictionary).keys.compactMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        xpc_dictionary_get_value(dictionary, key.stringValue) != nil
    }

    private func value(_ key: Key) throws -> xpc_object_t {
        guard let value = xpc_dictionary_get_value(dictionary, key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No value for \(key.stringValue)"))
        }
        return value
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try value(key).isType(XPC_TYPE_NULL)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decoder.child(type, value(key), at: codingPath + [key])
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try ObjectDecoder(object: value(key), codingPath: codingPath + [key], userInfo: decoder.userInfo).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try ObjectDecoder(object: value(key), codingPath: codingPath + [key], userInfo: decoder.userInfo).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        ObjectDecoder(object: xpc_dictionary_get_value(dictionary, "super") ?? xpc_null_create(),
                      codingPath: codingPath, userInfo: decoder.userInfo)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        ObjectDecoder(object: try value(key), codingPath: codingPath + [key], userInfo: decoder.userInfo)
    }
}

private struct UnkeyedDecoder: UnkeyedDecodingContainer {
    let array: xpc_object_t
    let decoder: ObjectDecoder
    var currentIndex = 0

    init(array: xpc_object_t, decoder: ObjectDecoder) {
        self.array = array
        self.decoder = decoder
    }

    var codingPath: [any CodingKey] { decoder.codingPath }
    var count: Int? { xpc_array_get_count(array) }
    var isAtEnd: Bool { currentIndex >= xpc_array_get_count(array) }

    private mutating func next() throws -> (xpc_object_t, [any CodingKey]) {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any.self, .init(codingPath: codingPath, debugDescription: "No more values"))
        }
        defer { currentIndex += 1 }
        return (xpc_array_get_value(array, currentIndex), codingPath + [IndexKey(currentIndex)])
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd, xpc_array_get_value(array, currentIndex).isType(XPC_TYPE_NULL) else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let (object, path) = try next()
        return try decoder.child(type, object, at: path)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let (object, path) = try next()
        return try ObjectDecoder(object: object, codingPath: path, userInfo: decoder.userInfo).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let (object, path) = try next()
        return try ObjectDecoder(object: object, codingPath: path, userInfo: decoder.userInfo).unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder {
        let (object, path) = try next()
        return ObjectDecoder(object: object, codingPath: path, userInfo: decoder.userInfo)
    }
}

private struct SingleDecoder: SingleValueDecodingContainer {
    let decoder: ObjectDecoder

    var codingPath: [any CodingKey] { decoder.codingPath }

    func decodeNil() -> Bool {
        decoder.object.isType(XPC_TYPE_NULL)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decoder.child(type, decoder.object, at: codingPath)
    }
}
