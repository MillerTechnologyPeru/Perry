// P-256 key agreement: private keys made at random or from their X9.63 or
// raw form, public keys from their X9.63, raw or DER form, and the shared
// secret of a private key and another's public key (ECDH), from which keys
// are derived with HKDF or the X9.63 KDF. The keys and the exchange are
// Security's (SecKeyCreateRandomKey, SecKeyCopyKeyExchangeResult).

public import Foundation
import Security

/// The DER SubjectPublicKeyInfo prefix of a P-256 public key: the
/// id-ecPublicKey and prime256v1 object identifiers, then the bit string
/// the uncompressed point fills.
private let p256SubjectPublicKeyInfoPrefix = Data([
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
    0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
])

/// A Security key of the curve from its X9.63 form.
private func secKey(x963 data: Data, isPrivate: Bool) throws -> SecKey {
    let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass: isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
    ]
    guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, nil) else {
        throw CryptoKitError.incorrectParameterSize
    }
    return key
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension P256 {
    public enum KeyAgreement: Sendable {
        public struct PublicKey: Sendable {
            /// 0x04, then x and y.
            let point: Data

            public init<D: ContiguousBytes>(x963Representation: D) throws {
                point = try CurveKind.p256.point(x963: bytes(contiguous: x963Representation))
            }

            public init<D: ContiguousBytes>(rawRepresentation: D) throws {
                point = try CurveKind.p256.point(x963: Data([0x04]) + bytes(contiguous: rawRepresentation))
            }

            @available(iOS 14.0, macOS 11.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
            public init<Bytes: RandomAccessCollection>(derRepresentation: Bytes) throws where Bytes.Element == UInt8 {
                point = try CurveKind.p256.point(der: Data(derRepresentation))
            }

            public var x963Representation: Data { point }
            public var rawRepresentation: Data { Data(point.dropFirst()) }

            @available(iOS 14.0, macOS 11.0, watchOS 7.0, tvOS 14.0, macCatalyst 14.0, *)
            public var derRepresentation: Data { p256SubjectPublicKeyInfoPrefix + point }
        }

        public struct PrivateKey: Sendable {
            /// 0x04, then x, y and the scalar.
            let x963: Data

            public init(compactRepresentable: Bool = true) {
                let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256]
                guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
                      let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
                    fatalError("CryptoKit: a P-256 key couldn't be made")
                }
                x963 = data
            }

            public init<D: ContiguousBytes>(x963Representation: D) throws {
                let data = bytes(contiguous: x963Representation)
                guard data.count == 1 + 3 * CurveKind.p256.coordinateSize, data.first == 0x04 else {
                    throw CryptoKitError.incorrectKeySize
                }
                _ = try secKey(x963: data, isPrivate: true)
                x963 = data
            }

            public var x963Representation: Data { x963 }
            public var rawRepresentation: Data { Data(x963.suffix(CurveKind.p256.coordinateSize)) }

            public var publicKey: PublicKey {
                // The point is what precedes the scalar.
                try! PublicKey(x963Representation: Data(x963.prefix(1 + 2 * CurveKind.p256.coordinateSize)))
            }

            public func sharedSecretFromKeyAgreement(with publicKeyShare: PublicKey) throws -> SharedSecret {
                let mine = try secKey(x963: x963, isPrivate: true)
                let theirs = try secKey(x963: publicKeyShare.point, isPrivate: false)
                var error: Unmanaged<CFError>?
                guard let shared = SecKeyCopyKeyExchangeResult(mine, .ecdhKeyExchangeStandard, theirs, [:] as CFDictionary, &error) as Data? else {
                    throw CryptoKitError.underlyingCoreCryptoError(error: -1)
                }
                return SharedSecret(bytes: Array(shared))
            }
        }
    }
}

/// The secret two parties' keys agree on, from which keys are derived.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public struct SharedSecret: ContiguousBytes, Sendable {
    let bytes: [UInt8]

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    /// A key derived with HKDF (RFC 5869).
    public func hkdfDerivedSymmetricKey<H: HashFunction, Salt: DataProtocol, SharedInfo: DataProtocol>(
        using hashFunction: H.Type, salt: Salt, sharedInfo: SharedInfo, outputByteCount: Int
    ) -> SymmetricKey {
        let pseudoRandomKey = hmac(H.self, key: Array(salt), message: bytes)
        var output: [UInt8] = []
        var previous: [UInt8] = []
        var counter: UInt8 = 1
        while output.count < outputByteCount {
            previous = hmac(H.self, key: pseudoRandomKey, message: previous + Array(sharedInfo) + [counter])
            output += previous
            counter &+= 1
        }
        return SymmetricKey(data: Array(output.prefix(outputByteCount)))
    }

    /// A key derived with the ANSI X9.63 key derivation function.
    public func x963DerivedSymmetricKey<H: HashFunction, SharedInfo: DataProtocol>(
        using hashFunction: H.Type, sharedInfo: SharedInfo, outputByteCount: Int
    ) -> SymmetricKey {
        var output: [UInt8] = []
        var counter: UInt32 = 1
        while output.count < outputByteCount {
            var hasher = H()
            let counterBytes = Swift.withUnsafeBytes(of: counter.bigEndian) { Array($0) }
            hasher.update(data: bytes + counterBytes + Array(sharedInfo))
            output += hasher.finalize().withUnsafeBytes { Array($0) }
            counter += 1
        }
        return SymmetricKey(data: Array(output.prefix(outputByteCount)))
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension SharedSecret: Hashable {
    public static func == (lhs: SharedSecret, rhs: SharedSecret) -> Bool {
        lhs.bytes.count == rhs.bytes.count && zip(lhs.bytes, rhs.bytes).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}

/// HMAC (RFC 2104) with any of the hash functions.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
private func hmac<H: HashFunction>(_: H.Type, key: [UInt8], message: [UInt8]) -> [UInt8] {
    let blockSize = H.blockByteCount
    var key = key
    if key.count > blockSize { key = H.hash(data: key).withUnsafeBytes { Array($0) } }
    key += [UInt8](repeating: 0, count: blockSize - key.count)
    var inner = H()
    inner.update(data: key.map { $0 ^ 0x36 } + message)
    let innerDigest = inner.finalize().withUnsafeBytes { Array($0) }
    var outer = H()
    outer.update(data: key.map { $0 ^ 0x5c } + innerDigest)
    return outer.finalize().withUnsafeBytes { Array($0) }
}
