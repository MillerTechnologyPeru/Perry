// AES in Galois/Counter Mode (NIST SP 800-38D): counter-mode encryption
// with AES blocks from CommonCrypto's ECB mode, authenticated by GHASH,
// multiplication in GF(2^128) done here bit by bit.

public import Foundation
import CommonCrypto

/// A container for Advanced Encryption Standard (AES) ciphers.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum AES: Sendable {}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension AES {
    /// The Advanced Encryption Standard (AES) Galois Counter Mode (GCM)
    /// cipher suite.
    public enum GCM: Sendable {
        static let tagByteCount = 16
        static let defaultNonceByteCount = 12

        public static func seal<Plaintext, AuthenticatedData>(
            _ message: Plaintext, using key: SymmetricKey, nonce: AES.GCM.Nonce? = nil,
            authenticating authenticatedData: AuthenticatedData
        ) throws -> AES.GCM.SealedBox where Plaintext: DataProtocol, AuthenticatedData: DataProtocol {
            let nonce = nonce ?? Nonce()
            let (ciphertext, tag) = try GCMCipher(key: key.bytes)
                .seal(Array(message), nonce: nonce.bytes, authenticating: Array(authenticatedData))
            return SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        }

        public static func seal<Plaintext>(
            _ message: Plaintext, using key: SymmetricKey, nonce: AES.GCM.Nonce? = nil
        ) throws -> AES.GCM.SealedBox where Plaintext: DataProtocol {
            try seal(message, using: key, nonce: nonce, authenticating: [UInt8]())
        }

        public static func open<AuthenticatedData>(
            _ sealedBox: AES.GCM.SealedBox, using key: SymmetricKey, authenticating authenticatedData: AuthenticatedData
        ) throws -> Data where AuthenticatedData: DataProtocol {
            Data(try GCMCipher(key: key.bytes).open(sealedBox.ciphertextBytes, nonce: sealedBox.nonce.bytes,
                                                    tag: sealedBox.tagBytes, authenticating: Array(authenticatedData)))
        }

        public static func open(_ sealedBox: AES.GCM.SealedBox, using key: SymmetricKey) throws -> Data {
            try open(sealedBox, using: key, authenticating: [UInt8]())
        }
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension AES.GCM {
    /// A value used once during a cryptographic operation and then
    /// discarded.
    public struct Nonce: ContiguousBytes, Sequence, Sendable {
        let bytes: [UInt8]

        /// A random 12-byte nonce.
        public init() {
            var bytes = [UInt8](repeating: 0, count: AES.GCM.defaultNonceByteCount)
            _ = CCRandomGenerateBytes(&bytes, bytes.count)
            self.bytes = bytes
        }

        /// A nonce of at least 12 bytes.
        public init<D>(data: D) throws where D: DataProtocol {
            guard data.count >= AES.GCM.defaultNonceByteCount else { throw CryptoKitError.incorrectParameterSize }
            bytes = Array(data)
        }

        public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
            try bytes.withUnsafeBytes(body)
        }

        public var count: Int { bytes.count }

        public func makeIterator() -> Array<UInt8>.Iterator { bytes.makeIterator() }

        public typealias Element = IndexingIterator<Array<UInt8>>.Element
        public typealias Iterator = Array<UInt8>.Iterator
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension AES.GCM {
    /// A secure container for your data that you can access using a cipher.
    public struct SealedBox: Sendable {
        let nonceValue: AES.GCM.Nonce
        let ciphertextBytes: [UInt8]
        let tagBytes: [UInt8]

        init(nonce: AES.GCM.Nonce, ciphertext: [UInt8], tag: [UInt8]) {
            nonceValue = nonce
            ciphertextBytes = ciphertext
            tagBytes = tag
        }

        public var tag: Data { Data(tagBytes) }
        public var ciphertext: Data { Data(ciphertextBytes) }
        public var nonce: AES.GCM.Nonce { nonceValue }

        /// The nonce, ciphertext and tag together, when the nonce is the
        /// default 12 bytes.
        public var combined: Data? {
            guard nonceValue.count == AES.GCM.defaultNonceByteCount else { return nil }
            return Data(nonceValue.bytes + ciphertextBytes + tagBytes)
        }

        @usableFromInline
        internal init(combined: Data) {
            let bytes = Array(combined)
            let nonceCount = AES.GCM.defaultNonceByteCount
            nonceValue = try! AES.GCM.Nonce(data: bytes[..<nonceCount])
            ciphertextBytes = Array(bytes[nonceCount ..< bytes.count - AES.GCM.tagByteCount])
            tagBytes = Array(bytes[(bytes.count - AES.GCM.tagByteCount)...])
        }

        @inlinable
        public init<D>(combined: D) throws where D: DataProtocol {
            let aesGCMOverhead = 12 + 16
            if combined.count < aesGCMOverhead {
                throw CryptoKitError.incorrectParameterSize
            }
            self.init(combined: Data(combined))
        }

        public init<C, T>(nonce: AES.GCM.Nonce, ciphertext: C, tag: T) throws where C: DataProtocol, T: DataProtocol {
            guard tag.count == AES.GCM.tagByteCount else { throw CryptoKitError.incorrectParameterSize }
            self.init(nonce: nonce, ciphertext: Array(ciphertext), tag: Array(tag))
        }
    }
}

// MARK: - The cipher

/// A 128-bit block as two big-endian halves, for GF(2^128) arithmetic.
struct Block128: Equatable {
    var high: UInt64
    var low: UInt64

    static let zero = Block128(high: 0, low: 0)

    init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// The block in `bytes` at `offset`, zero-padded past the end.
    init(_ bytes: [UInt8], at offset: Int = 0) {
        var high: UInt64 = 0, low: UInt64 = 0
        for i in 0 ..< 16 {
            let byte = offset + i < bytes.count ? UInt64(bytes[offset + i]) : 0
            if i < 8 { high = high << 8 | byte } else { low = low << 8 | byte }
        }
        self.init(high: high, low: low)
    }

    var bytes: [UInt8] {
        (0 ..< 8).map { UInt8(truncatingIfNeeded: high >> (56 - 8 * $0)) }
            + (0 ..< 8).map { UInt8(truncatingIfNeeded: low >> (56 - 8 * $0)) }
    }

    static func ^ (a: Block128, b: Block128) -> Block128 {
        Block128(high: a.high ^ b.high, low: a.low ^ b.low)
    }

    /// Multiplication in GCM's field: bits are taken most significant
    /// first, and R = 0xe1 || 0^120 reduces.
    func multiplied(by y: Block128) -> Block128 {
        var z = Block128.zero
        var v = y
        for i in 0 ..< 128 {
            let bit = i < 64 ? (high >> (63 - i)) & 1 : (low >> (127 - i)) & 1
            if bit == 1 { z = z ^ v }
            let carry = v.low & 1
            v.low = v.low >> 1 | v.high << 63
            v.high >>= 1
            if carry == 1 { v.high ^= 0xe100_0000_0000_0000 }
        }
        return z
    }
}

/// GCM over one AES key.
struct GCMCipher {
    let key: [UInt8]
    let hashKey: Block128

    init(key: [UInt8]) throws {
        guard [16, 24, 32].contains(key.count) else { throw CryptoKitError.incorrectKeySize }
        self.key = key
        hashKey = Block128(try Self.encryptBlocks(key, [UInt8](repeating: 0, count: 16)))
    }

    /// AES applied to each 16-byte block of `input`.
    static func encryptBlocks(_ key: [UInt8], _ input: [UInt8]) throws -> [UInt8] {
        guard !input.isEmpty else { return [] }
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, input, input.count, &output, output.count, &moved)
        guard status == kCCSuccess, moved == input.count else {
            throw CryptoKitError.underlyingCoreCryptoError(error: Int32(status))
        }
        return output
    }

    /// GHASH of the authenticated data and ciphertext, each zero-padded to
    /// blocks, then their lengths in bits.
    func ghash(_ aad: [UInt8], _ ciphertext: [UInt8]) -> Block128 {
        var y = Block128.zero
        for data in [aad, ciphertext] {
            var offset = 0
            while offset < data.count {
                y = (y ^ Block128(data, at: offset)).multiplied(by: hashKey)
                offset += 16
            }
        }
        let lengths = Block128(high: UInt64(aad.count) * 8, low: UInt64(ciphertext.count) * 8)
        return (y ^ lengths).multiplied(by: hashKey)
    }

    /// The pre-counter block: a 12-byte nonce then 1, or else the nonce's
    /// GHASH.
    func initialCounter(_ nonce: [UInt8]) -> Block128 {
        if nonce.count == 12 {
            return Block128(nonce + [0, 0, 0, 1])
        }
        return ghash([], nonce)
    }

    /// `data` XORed with the key stream from the counter after `j0`, the
    /// low 32 bits incrementing.
    func counterMode(_ data: [UInt8], from j0: Block128) throws -> [UInt8] {
        guard !data.isEmpty else { return [] }
        let blockCount = (data.count + 15) / 16
        var counters: [UInt8] = []
        counters.reserveCapacity(blockCount * 16)
        var counter = j0
        for _ in 0 ..< blockCount {
            let next = UInt32(truncatingIfNeeded: counter.low) &+ 1
            counter.low = counter.low & 0xffff_ffff_0000_0000 | UInt64(next)
            counters += counter.bytes
        }
        let stream = try Self.encryptBlocks(key, counters)
        return zip(data, stream).map { $0 ^ $1 }
    }

    func tag(_ aad: [UInt8], _ ciphertext: [UInt8], _ j0: Block128) throws -> [UInt8] {
        let mask = try Self.encryptBlocks(key, j0.bytes)
        return zip(ghash(aad, ciphertext).bytes, mask).map { $0 ^ $1 }
    }

    func seal(_ plaintext: [UInt8], nonce: [UInt8], authenticating aad: [UInt8]) throws -> ([UInt8], [UInt8]) {
        let j0 = initialCounter(nonce)
        let ciphertext = try counterMode(plaintext, from: j0)
        return (ciphertext, try tag(aad, ciphertext, j0))
    }

    func open(_ ciphertext: [UInt8], nonce: [UInt8], tag expected: [UInt8], authenticating aad: [UInt8]) throws -> [UInt8] {
        let j0 = initialCounter(nonce)
        let computed = try tag(aad, ciphertext, j0)
        guard computed.count == expected.count,
              zip(computed, expected).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else {
            throw CryptoKitError.authenticationFailure
        }
        return try counterMode(ciphertext, from: j0)
    }
}
