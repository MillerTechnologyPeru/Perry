// NWTXTRecord: a DNS-SD TXT record's key and value pairs, in order, kept
// as Swift values and turned to and from the record's wire format (each
// entry a length byte and "key=value") for the C API's nw_txt_record_t.
// Keys compare without regard to case, as DNS-SD's do.

import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct NWTXTRecord: Sendable {
    /// The value of a key.
    public enum Entry: Hashable, CustomDebugStringConvertible, Sendable {
        /// The key has no value ("key").
        case none
        /// The key's value is empty ("key=").
        case empty
        case string(String)
        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        case data(Data)

        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public var data: Data? {
            switch self {
            case .none: return nil
            case .empty: return Data()
            case .string(let string): return Data(string.utf8)
            case .data(let data): return data
            }
        }

        @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
        public init(_ data: Data?) {
            guard let data else {
                self = .none
                return
            }
            self = data.isEmpty ? .empty : .data(data)
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .none: hasher.combine(0)
            case .empty: hasher.combine(1)
            case .string(let string):
                hasher.combine(2)
                hasher.combine(Data(string.utf8))
            case .data(let data):
                hasher.combine(2)
                hasher.combine(data)
            }
        }

        /// Entries are equal when their bytes are: a string and data of
        /// its UTF-8 are the same value.
        public static func == (lhs: Entry, rhs: Entry) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none), (.empty, .empty): return true
            case (.none, _), (_, .none), (.empty, _), (_, .empty): return false
            default: return lhs.bytes == rhs.bytes
            }
        }

        public var debugDescription: String {
            switch self {
            case .none: return "none"
            case .empty: return "empty"
            case .string(let string): return "string(\(string))"
            case .data(let data): return "data(\(data.count) bytes)"
            }
        }

        /// The entry's value bytes, nil for none.
        var bytes: Data? {
            switch self {
            case .none: return nil
            case .empty: return Data()
            case .string(let string): return Data(string.utf8)
            case .data(let data): return data
            }
        }

        /// The value as a string, if it is UTF-8 (nil for none).
        var string: String? {
            switch self {
            case .none: return nil
            case .empty: return ""
            case .string(let string): return string
            case .data(let data): return String(data: data, encoding: .utf8)
            }
        }
    }

    /// The pairs, in the order they were set.
    var pairs: [(key: String, value: Entry)] = []

    public init(_ dictionary: [String: String] = [:]) {
        for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
            setEntry(value.isEmpty ? .empty : .string(value), for: key)
        }
    }

    @available(macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
    public init(_ dataDictionary: [String: Data]) {
        for (key, value) in dataDictionary.sorted(by: { $0.key < $1.key }) {
            setEntry(Entry(value), for: key)
        }
    }

    @available(macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
    public init(_ entryDictionary: [String: Entry]) {
        for (key, value) in entryDictionary.sorted(by: { $0.key < $1.key }) {
            setEntry(value, for: key)
        }
    }

    /// A record of its wire format.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public init(_ data: Data) {
        self.init(wireFormat: data)
    }

    init(wireFormat data: Data) {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            offset += 1
            let end = Swift.min(offset + length, bytes.count)
            let item = bytes[offset..<end]
            offset = end
            guard !item.isEmpty else { continue }
            if let equals = item.firstIndex(of: UInt8(ascii: "=")) {
                let key = String(decoding: item[item.startIndex..<equals], as: UTF8.self)
                let value = Data(item[(equals + 1)...])
                if value.isEmpty {
                    setEntry(.empty, for: key)
                } else if let string = String(data: value, encoding: .utf8) {
                    setEntry(.string(string), for: key)
                } else if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                    setEntry(.data(value), for: key)
                }
            } else {
                setEntry(.none, for: String(decoding: item, as: UTF8.self))
            }
        }
    }

    private func position(of key: String) -> Int? {
        let folded = key.lowercased()
        return pairs.firstIndex { $0.key.lowercased() == folded }
    }

    @discardableResult
    public mutating func removeEntry(key: String) -> Bool {
        guard let index = position(of: key) else { return false }
        pairs.remove(at: index)
        return true
    }

    public func getEntry(for key: String) -> Entry? {
        position(of: key).map { pairs[$0].value }
    }

    @available(macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
    public var entries: [String: Entry] {
        Dictionary(pairs.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// The record's wire format.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public var data: Data { wireFormat }

    var wireFormat: Data {
        var data = Data()
        for (key, value) in pairs {
            var item = Data(key.utf8)
            if let bytes = value.bytes {
                item.append(UInt8(ascii: "="))
                item.append(bytes)
            }
            let length = Swift.min(item.count, 255)
            data.append(UInt8(length))
            data.append(item.prefix(length))
        }
        return data
    }

    /// Sets a key's entry; false if the key can't be in a TXT record
    /// (empty, not ASCII, with an "=", or too long).
    @discardableResult
    public mutating func setEntry(_ entry: Entry, for key: String) -> Bool {
        guard !key.isEmpty, key.utf8.count <= 255, key.allSatisfy({ $0.isASCII && $0 != "=" }) else {
            return false
        }
        if let index = position(of: key) {
            pairs[index] = (key, entry)
        } else {
            pairs.append((key, entry))
        }
        return true
    }

    public subscript(key: String) -> String? {
        get { getEntry(for: key)?.string }
        set {
            if let newValue {
                setEntry(newValue.isEmpty ? .empty : .string(newValue), for: key)
            } else {
                removeEntry(key: key)
            }
        }
    }

    public var dictionary: [String: String] {
        var dictionary: [String: String] = [:]
        for (key, value) in pairs where dictionary[key] == nil {
            dictionary[key] = value.string ?? ""
        }
        return dictionary
    }

    @available(macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
    public var dataDictionary: [String: Data] {
        var dictionary: [String: Data] = [:]
        for (key, value) in pairs where dictionary[key] == nil {
            dictionary[key] = value.bytes ?? Data()
        }
        return dictionary
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NWTXTRecord: Equatable {
    /// Records are equal when they have the same keys with the same values.
    public static func == (lhs: NWTXTRecord, rhs: NWTXTRecord) -> Bool {
        guard lhs.pairs.count == rhs.pairs.count else { return false }
        return lhs.pairs.allSatisfy { rhs.getEntry(for: $0.key) == $0.value }
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NWTXTRecord: Collection {
    public typealias Element = (key: String, value: Entry)

    public subscript(position: Index) -> Element {
        pairs[position.offset]
    }

    public struct Index: Comparable {
        let offset: Int

        public static func == (lhs: Index, rhs: Index) -> Bool { lhs.offset == rhs.offset }

        public static func < (lhs: Index, rhs: Index) -> Bool { lhs.offset < rhs.offset }
    }

    public var startIndex: Index { Index(offset: 0) }

    public var endIndex: Index { Index(offset: pairs.count) }

    public func index(after i: Index) -> Index { Index(offset: i.offset + 1) }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias Indices = DefaultIndices<NWTXTRecord>
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias Iterator = IndexingIterator<NWTXTRecord>
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public typealias SubSequence = Slice<NWTXTRecord>
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NWTXTRecord: CustomDebugStringConvertible {
    public var debugDescription: String {
        "[" + pairs.map { pair -> String in
            switch pair.value {
            case .none: return pair.key
            default: return "\(pair.key)=\(pair.value.string ?? "<\(pair.value.bytes?.count ?? 0) bytes>")"
            }
        }.joined(separator: ", ") + "]"
    }
}

// MARK: - The C API's TXT records

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NWTXTRecord {
    init(_ record: nw_txt_record_t) {
        var data = Data()
        _ = nw_txt_record_access_bytes(record) { bytes, length in
            data = Data(bytes: bytes, count: length)
            return true
        }
        self.init(wireFormat: data)
    }

    var nw: nw_txt_record_t {
        guard !pairs.isEmpty else { return nw_txt_record_create_dictionary() }
        let bytes = [UInt8](wireFormat)
        return bytes.withUnsafeBufferPointer { buffer in
            nw_txt_record_create_with_bytes(buffer.baseAddress!, buffer.count)
        }
    }
}

// MARK: - Decoding

/// Decodes a Decodable type from a TXT record: each stored property is a
/// key, its value read from the entry's text (a key without a value is
/// true as a Bool).
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct TXTRecordDecoder: Sendable {
    public init() {}

    public func decode<T>(_ type: T.Type, from txtRecord: NWTXTRecord) throws -> T where T: Decodable {
        try T(from: TXTDecoder(record: txtRecord, codingPath: []))
    }
}

private struct TXTDecoder: Decoder {
    let record: NWTXTRecord
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        KeyedDecodingContainer(TXTKeyedContainer<Key>(record: record, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, .init(codingPath: codingPath, debugDescription: "A TXT record holds keys and values, not a list"))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(Any.self, .init(codingPath: codingPath, debugDescription: "A TXT record holds keys and values, not a single value"))
    }
}

/// The text of one entry, decoded as a single value.
private struct TXTValueDecoder: Decoder, SingleValueDecodingContainer {
    let entry: NWTXTRecord.Entry
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        throw DecodingError.typeMismatch([String: Any].self, .init(codingPath: codingPath, debugDescription: "A TXT record value is not nested"))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, .init(codingPath: codingPath, debugDescription: "A TXT record value is not a list"))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer { self }

    func decodeNil() -> Bool { entry == .none }

    private func text() throws -> String {
        guard let text = entry.string else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "The value is not text"))
        }
        return text
    }

    private func number<N>(_ make: (String) -> N?) throws -> N {
        let text = try text()
        guard let value = make(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "\"\(text)\" is not a \(N.self)"))
        }
        return value
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        if entry == .none { return true }
        switch try text().lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off", "": return false
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "The value is not a Bool"))
        }
    }

    func decode(_ type: String.Type) throws -> String { try text() }
    func decode(_ type: Double.Type) throws -> Double { try number { Double($0) } }
    func decode(_ type: Float.Type) throws -> Float { try number { Float($0) } }
    func decode(_ type: Int.Type) throws -> Int { try number { Int($0) } }
    func decode(_ type: Int8.Type) throws -> Int8 { try number { Int8($0) } }
    func decode(_ type: Int16.Type) throws -> Int16 { try number { Int16($0) } }
    func decode(_ type: Int32.Type) throws -> Int32 { try number { Int32($0) } }
    func decode(_ type: Int64.Type) throws -> Int64 { try number { Int64($0) } }
    func decode(_ type: UInt.Type) throws -> UInt { try number { UInt($0) } }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try number { UInt8($0) } }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try number { UInt16($0) } }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try number { UInt32($0) } }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try number { UInt64($0) } }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        if type == Data.self, let bytes = entry.bytes {
            return bytes as! T
        }
        return try T(from: self)
    }
}

private struct TXTKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let record: NWTXTRecord
    let codingPath: [any CodingKey]

    var allKeys: [Key] { record.pairs.compactMap { Key(stringValue: $0.key) } }

    func contains(_ key: Key) -> Bool { record.getEntry(for: key.stringValue) != nil }

    private func entry(_ key: Key) throws -> NWTXTRecord.Entry {
        guard let entry = record.getEntry(for: key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No key \"\(key.stringValue)\" in the TXT record"))
        }
        return entry
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let entry = record.getEntry(for: key.stringValue) else { return true }
        return entry == .none
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        try TXTValueDecoder(entry: entry(key), codingPath: codingPath + [key]).decode(type)
    }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        guard let entry = record.getEntry(for: key.stringValue) else { return nil }
        return try TXTValueDecoder(entry: entry, codingPath: codingPath + [key]).decode(type)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        throw DecodingError.typeMismatch([String: Any].self, .init(codingPath: codingPath + [key], debugDescription: "A TXT record value is not nested"))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, .init(codingPath: codingPath + [key], debugDescription: "A TXT record value is not a list"))
    }

    func superDecoder() throws -> any Decoder { TXTDecoder(record: record, codingPath: codingPath) }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        TXTValueDecoder(entry: try entry(key), codingPath: codingPath + [key])
    }
}
