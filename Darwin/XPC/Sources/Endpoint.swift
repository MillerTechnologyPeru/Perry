// XPCEndpoint: a connection's address, as a value. It codes as its object
// in an XPC message and can't be coded by other coders.

public struct XPCEndpoint {
    /// The endpoint object.
    public let _endpoint: xpc_endpoint_t

    public init(_ endpoint: xpc_endpoint_t) {
        _endpoint = endpoint
    }
}

extension XPCEndpoint: Equatable, Hashable {
    public static func == (a: XPCEndpoint, b: XPCEndpoint) -> Bool {
        xpc_equal(a._endpoint, b._endpoint)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(xpc_hash(_endpoint))
    }
}

extension XPCEndpoint: CustomDebugStringConvertible {
    public var debugDescription: String {
        Objects.describe(_endpoint)
    }
}

extension XPCEndpoint: Codable {
    public func encode(to encoder: any Encoder) throws {
        guard let encoder = encoder as? ObjectEncoder else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                         debugDescription: "An XPCEndpoint is encoded only in an XPC message"))
        }
        encoder.result = _endpoint
    }

    public init(from decoder: any Decoder) throws {
        guard let decoder = decoder as? ObjectDecoder, decoder.object.isType(XPC_TYPE_ENDPOINT) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "An XPCEndpoint is decoded only from an XPC message"))
        }
        _endpoint = decoder.object
    }
}

extension XPCEndpoint: @unchecked Sendable {}
