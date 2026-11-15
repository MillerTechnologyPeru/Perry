// The NIST curves' signature checking: public keys from their X9.63 or DER
// form, ECDSA signatures from their DER or raw form, and whether a
// signature is a key's over some data. The checking itself is Security's
// (SecKeyVerifySignature), which hashes the data as CryptoKit does: with
// SHA-256 for P-256, SHA-384 for P-384 and SHA-512 for P-521.

public import Foundation
import Security

/// What the three curves' types share: a coordinate's size in bytes.
enum CurveKind {
    case p256, p384, p521

    var coordinateSize: Int {
        switch self {
        case .p256: return 32
        case .p384: return 48
        case .p521: return 66
        }
    }

    var algorithm: SecKeyAlgorithm {
        switch self {
        case .p256: return .ecdsaSignatureMessageX962SHA256
        case .p384: return .ecdsaSignatureMessageX962SHA384
        case .p521: return .ecdsaSignatureMessageX962SHA512
        }
    }

    /// The uncompressed point, 0x04 then both coordinates, checked for
    /// its size.
    func point(x963 data: Data) throws -> Data {
        guard data.count == 1 + 2 * coordinateSize, data.first == 0x04 else { throw CryptoKitError.incorrectParameterSize }
        return data
    }

    /// The point a SubjectPublicKeyInfo ends with.
    func point(der data: Data) throws -> Data {
        let size = 1 + 2 * coordinateSize
        guard data.count > size else { throw CryptoKitError.incorrectParameterSize }
        return try point(x963: Data(data.suffix(size)))
    }

    /// A DER ECDSA signature from r and s, each a coordinate wide.
    func der(raw: Data) throws -> Data {
        guard raw.count == 2 * coordinateSize else { throw CryptoKitError.incorrectParameterSize }
        func integer(_ bytes: Data) -> [UInt8] {
            var value = Array(bytes.drop { $0 == 0 })
            if value.isEmpty { value = [0] }
            if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return [0x02] + length(value.count) + value
        }
        func length(_ count: Int) -> [UInt8] {
            count < 0x80 ? [UInt8(count)] : count < 0x100 ? [0x81, UInt8(count)] : [0x82, UInt8(count >> 8), UInt8(count & 0xff)]
        }
        let body = integer(raw.prefix(coordinateSize)) + integer(raw.suffix(coordinateSize))
        return Data([0x30] + length(body.count) + body)
    }

    /// r and s, each a coordinate wide, from a DER ECDSA signature.
    func raw(der: Data) throws -> Data {
        var bytes = Array(der)[...]
        func take() throws -> UInt8 {
            guard let first = bytes.popFirst() else { throw CryptoKitError.incorrectParameterSize }
            return first
        }
        func length() throws -> Int {
            let first = try take()
            if first < 0x80 { return Int(first) }
            var value = 0
            for _ in 0..<Int(first & 0x7f) { value = value << 8 | Int(try take()) }
            return value
        }
        func integer() throws -> [UInt8] {
            guard try take() == 0x02 else { throw CryptoKitError.incorrectParameterSize }
            let count = try length()
            guard bytes.count >= count else { throw CryptoKitError.incorrectParameterSize }
            let value = Array(bytes.prefix(count).drop { $0 == 0 })
            bytes = bytes.dropFirst(count)
            guard value.count <= coordinateSize else { throw CryptoKitError.incorrectParameterSize }
            return [UInt8](repeating: 0, count: coordinateSize - value.count) + value
        }
        guard try take() == 0x30 else { throw CryptoKitError.incorrectParameterSize }
        _ = try length()
        return Data(try integer() + integer())
    }

    func isValid(signature der: Data, for data: Data, point: Data) -> Bool {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(point as CFData, attributes as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(key, algorithm, data as CFData, der as CFData, nil)
    }
}

func bytes<D: DataProtocol>(_ data: D) -> Data { Data(data) }
func bytes<D: ContiguousBytes>(contiguous data: D) -> Data { data.withUnsafeBytes { Data($0) } }

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum P256: Sendable {
    public enum Signing: Sendable {
        public struct ECDSASignature: Sendable {
            public var rawRepresentation: Data

            public init<D: DataProtocol>(rawRepresentation: D) throws {
                let raw = bytes(rawRepresentation)
                guard raw.count == 2 * CurveKind.p256.coordinateSize else { throw CryptoKitError.incorrectParameterSize }
                self.rawRepresentation = raw
            }

            public init<D: DataProtocol>(derRepresentation: D) throws {
                rawRepresentation = try CurveKind.p256.raw(der: bytes(derRepresentation))
            }

            public var derRepresentation: Data { (try? CurveKind.p256.der(raw: rawRepresentation)) ?? Data() }

            public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
                try rawRepresentation.withUnsafeBytes(body)
            }
        }

        public struct PublicKey: Sendable {
            let point: Data

            public init<D: ContiguousBytes>(x963Representation: D) throws {
                point = try CurveKind.p256.point(x963: bytes(contiguous: x963Representation))
            }

            public init<D: ContiguousBytes>(rawRepresentation: D) throws {
                point = try CurveKind.p256.point(x963: Data([0x04]) + bytes(contiguous: rawRepresentation))
            }

            public init<Bytes: RandomAccessCollection>(derRepresentation: Bytes) throws where Bytes.Element == UInt8 {
                point = try CurveKind.p256.point(der: Data(derRepresentation))
            }

            public var x963Representation: Data { point }
            public var rawRepresentation: Data { Data(point.dropFirst()) }

            public func isValidSignature<D: DataProtocol>(_ signature: ECDSASignature, for data: D) -> Bool {
                CurveKind.p256.isValid(signature: signature.derRepresentation, for: bytes(data), point: point)
            }
        }
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum P384: Sendable {
    public enum Signing: Sendable {
        public struct ECDSASignature: Sendable {
            public var rawRepresentation: Data

            public init<D: DataProtocol>(rawRepresentation: D) throws {
                let raw = bytes(rawRepresentation)
                guard raw.count == 2 * CurveKind.p384.coordinateSize else { throw CryptoKitError.incorrectParameterSize }
                self.rawRepresentation = raw
            }

            public init<D: DataProtocol>(derRepresentation: D) throws {
                rawRepresentation = try CurveKind.p384.raw(der: bytes(derRepresentation))
            }

            public var derRepresentation: Data { (try? CurveKind.p384.der(raw: rawRepresentation)) ?? Data() }

            public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
                try rawRepresentation.withUnsafeBytes(body)
            }
        }

        public struct PublicKey: Sendable {
            let point: Data

            public init<D: ContiguousBytes>(x963Representation: D) throws {
                point = try CurveKind.p384.point(x963: bytes(contiguous: x963Representation))
            }

            public init<D: ContiguousBytes>(rawRepresentation: D) throws {
                point = try CurveKind.p384.point(x963: Data([0x04]) + bytes(contiguous: rawRepresentation))
            }

            public init<Bytes: RandomAccessCollection>(derRepresentation: Bytes) throws where Bytes.Element == UInt8 {
                point = try CurveKind.p384.point(der: Data(derRepresentation))
            }

            public var x963Representation: Data { point }
            public var rawRepresentation: Data { Data(point.dropFirst()) }

            public func isValidSignature<D: DataProtocol>(_ signature: ECDSASignature, for data: D) -> Bool {
                CurveKind.p384.isValid(signature: signature.derRepresentation, for: bytes(data), point: point)
            }
        }
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum P521: Sendable {
    public enum Signing: Sendable {
        public struct ECDSASignature: Sendable {
            public var rawRepresentation: Data

            public init<D: DataProtocol>(rawRepresentation: D) throws {
                let raw = bytes(rawRepresentation)
                guard raw.count == 2 * CurveKind.p521.coordinateSize else { throw CryptoKitError.incorrectParameterSize }
                self.rawRepresentation = raw
            }

            public init<D: DataProtocol>(derRepresentation: D) throws {
                rawRepresentation = try CurveKind.p521.raw(der: bytes(derRepresentation))
            }

            public var derRepresentation: Data { (try? CurveKind.p521.der(raw: rawRepresentation)) ?? Data() }

            public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
                try rawRepresentation.withUnsafeBytes(body)
            }
        }

        public struct PublicKey: Sendable {
            let point: Data

            public init<D: ContiguousBytes>(x963Representation: D) throws {
                point = try CurveKind.p521.point(x963: bytes(contiguous: x963Representation))
            }

            public init<D: ContiguousBytes>(rawRepresentation: D) throws {
                point = try CurveKind.p521.point(x963: Data([0x04]) + bytes(contiguous: rawRepresentation))
            }

            public init<Bytes: RandomAccessCollection>(derRepresentation: Bytes) throws where Bytes.Element == UInt8 {
                point = try CurveKind.p521.point(der: Data(derRepresentation))
            }

            public var x963Representation: Data { point }
            public var rawRepresentation: Data { Data(point.dropFirst()) }

            public func isValidSignature<D: DataProtocol>(_ signature: ECDSASignature, for data: D) -> Bool {
                CurveKind.p521.isValid(signature: signature.derRepresentation, for: bytes(data), point: point)
            }
        }
    }
}
