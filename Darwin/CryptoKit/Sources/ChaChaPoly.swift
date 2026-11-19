// ChaCha20-Poly1305 (RFC 8439): the ChaCha20 stream cipher, and Poly1305
// over 26-bit limbs, as the AEAD of the RFC joins them.

public import Foundation
import CommonCrypto

/// An implementation of the cipher suite ChaCha20-Poly1305.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
public enum ChaChaPoly: Sendable {
    static let tagByteCount = 16
    static let nonceByteCount = 12

    public static func seal<Plaintext, AuthenticatedData>(
        _ message: Plaintext, using key: SymmetricKey, nonce: ChaChaPoly.Nonce? = nil,
        authenticating authenticatedData: AuthenticatedData
    ) throws -> ChaChaPoly.SealedBox where Plaintext: DataProtocol, AuthenticatedData: DataProtocol {
        let nonce = nonce ?? Nonce()
        let (ciphertext, tag) = try ChaCha20Poly1305Cipher(key: key.bytes)
            .seal(Array(message), nonce: nonce.bytes, authenticating: Array(authenticatedData))
        return SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
    }

    public static func seal<Plaintext>(
        _ message: Plaintext, using key: SymmetricKey, nonce: ChaChaPoly.Nonce? = nil
    ) throws -> ChaChaPoly.SealedBox where Plaintext: DataProtocol {
        try seal(message, using: key, nonce: nonce, authenticating: [UInt8]())
    }

    public static func open<AuthenticatedData>(
        _ sealedBox: ChaChaPoly.SealedBox, using key: SymmetricKey, authenticating authenticatedData: AuthenticatedData
    ) throws -> Data where AuthenticatedData: DataProtocol {
        let bytes = Array(sealedBox.combined)
        let ciphertextEnd = bytes.count - tagByteCount
        return Data(try ChaCha20Poly1305Cipher(key: key.bytes).open(
            Array(bytes[nonceByteCount ..< ciphertextEnd]), nonce: Array(bytes[..<nonceByteCount]),
            tag: Array(bytes[ciphertextEnd...]), authenticating: Array(authenticatedData)))
    }

    public static func open(_ sealedBox: ChaChaPoly.SealedBox, using key: SymmetricKey) throws -> Data {
        try open(sealedBox, using: key, authenticating: [UInt8]())
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension ChaChaPoly {
    /// A sealed box: the nonce, the ciphertext and the tag, together.
    @frozen public struct SealedBox: Sendable {
        public let combined: Data

        public var tag: Data { combined.suffix(ChaChaPoly.tagByteCount) }

        public var ciphertext: Data {
            combined.dropFirst(ChaChaPoly.nonceByteCount).dropLast(ChaChaPoly.tagByteCount)
        }

        public var nonce: ChaChaPoly.Nonce {
            try! ChaChaPoly.Nonce(data: combined.prefix(ChaChaPoly.nonceByteCount))
        }

        @inlinable
        public init<D>(combined: D) throws where D: DataProtocol {
            let chachaPolyOverhead = 12 + 16
            if combined.count < chachaPolyOverhead {
                throw CryptoKitError.incorrectParameterSize
            }
            self.combined = Data(combined)
        }

        public init<C, T>(nonce: ChaChaPoly.Nonce, ciphertext: C, tag: T) throws where C: DataProtocol, T: DataProtocol {
            guard tag.count == ChaChaPoly.tagByteCount else { throw CryptoKitError.incorrectParameterSize }
            self.init(nonce: nonce, ciphertext: Array(ciphertext), tag: Array(tag))
        }

        init(nonce: ChaChaPoly.Nonce, ciphertext: [UInt8], tag: [UInt8]) {
            combined = Data(nonce.bytes + ciphertext + tag)
        }
    }
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *)
extension ChaChaPoly {
    /// A value used once during a cryptographic operation and then
    /// discarded.
    public struct Nonce: ContiguousBytes, Sequence, Sendable {
        let bytes: [UInt8]

        /// A random 12-byte nonce.
        public init() {
            var bytes = [UInt8](repeating: 0, count: ChaChaPoly.nonceByteCount)
            _ = CCRandomGenerateBytes(&bytes, bytes.count)
            self.bytes = bytes
        }

        /// A nonce of exactly 12 bytes.
        public init<D>(data: D) throws where D: DataProtocol {
            guard data.count == ChaChaPoly.nonceByteCount else { throw CryptoKitError.incorrectParameterSize }
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

// MARK: - The cipher

/// ChaCha20 and Poly1305 over one 256-bit key.
struct ChaCha20Poly1305Cipher {
    let key: [UInt8]

    init(key: [UInt8]) throws {
        guard key.count == 32 else { throw CryptoKitError.incorrectKeySize }
        self.key = key
    }

    private static func load32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func store32(_ value: UInt32, into bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }

    /// The 64-byte block of ChaCha20 for a block counter.
    func block(counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        var initial = [UInt32](repeating: 0, count: 16)
        initial[0] = 0x6170_7865
        initial[1] = 0x3320_646e
        initial[2] = 0x7962_2d32
        initial[3] = 0x6b20_6574
        for i in 0 ..< 8 { initial[4 + i] = Self.load32(key, 4 * i) }
        initial[12] = counter
        for i in 0 ..< 3 { initial[13 + i] = Self.load32(nonce, 4 * i) }
        var x = initial

        @inline(__always) func quarter(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            x[a] = x[a] &+ x[b]; x[d] ^= x[a]; x[d] = x[d] << 16 | x[d] >> 16
            x[c] = x[c] &+ x[d]; x[b] ^= x[c]; x[b] = x[b] << 12 | x[b] >> 20
            x[a] = x[a] &+ x[b]; x[d] ^= x[a]; x[d] = x[d] << 8 | x[d] >> 24
            x[c] = x[c] &+ x[d]; x[b] ^= x[c]; x[b] = x[b] << 7 | x[b] >> 25
        }
        for _ in 0 ..< 10 {
            quarter(0, 4, 8, 12); quarter(1, 5, 9, 13); quarter(2, 6, 10, 14); quarter(3, 7, 11, 15)
            quarter(0, 5, 10, 15); quarter(1, 6, 11, 12); quarter(2, 7, 8, 13); quarter(3, 4, 9, 14)
        }
        var output: [UInt8] = []
        output.reserveCapacity(64)
        for i in 0 ..< 16 { Self.store32(x[i] &+ initial[i], into: &output) }
        return output
    }

    /// `data` XORed with the key stream from block counter 1.
    func crypt(_ data: [UInt8], nonce: [UInt8]) -> [UInt8] {
        var output = data
        var counter: UInt32 = 1
        var offset = 0
        while offset < data.count {
            let stream = block(counter: counter, nonce: nonce)
            for i in 0 ..< min(64, data.count - offset) { output[offset + i] ^= stream[i] }
            offset += 64
            counter &+= 1
        }
        return output
    }

    /// The tag over the associated data and ciphertext, each padded to 16
    /// bytes, then their lengths, under the one-time key from block 0.
    func tag(_ aad: [UInt8], _ ciphertext: [UInt8], nonce: [UInt8]) -> [UInt8] {
        var poly = Poly1305(key: Array(block(counter: 0, nonce: nonce)[..<32]))
        func padded(_ data: [UInt8]) -> [UInt8] { data + [UInt8](repeating: 0, count: (16 - data.count % 16) % 16) }
        func length(_ count: Int) -> [UInt8] { (0 ..< 8).map { UInt8(truncatingIfNeeded: UInt64(count) >> UInt64(8 * $0)) } }
        poly.update(padded(aad) + padded(ciphertext) + length(aad.count) + length(ciphertext.count))
        return poly.finish()
    }

    func seal(_ plaintext: [UInt8], nonce: [UInt8], authenticating aad: [UInt8]) throws -> ([UInt8], [UInt8]) {
        guard nonce.count == 12 else { throw CryptoKitError.incorrectParameterSize }
        let ciphertext = crypt(plaintext, nonce: nonce)
        return (ciphertext, tag(aad, ciphertext, nonce: nonce))
    }

    func open(_ ciphertext: [UInt8], nonce: [UInt8], tag expected: [UInt8], authenticating aad: [UInt8]) throws -> [UInt8] {
        guard nonce.count == 12 else { throw CryptoKitError.incorrectParameterSize }
        let computed = tag(aad, ciphertext, nonce: nonce)
        guard computed.count == expected.count,
              zip(computed, expected).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else {
            throw CryptoKitError.authenticationFailure
        }
        return crypt(ciphertext, nonce: nonce)
    }
}

/// Poly1305: arithmetic modulo 2^130 - 5 in five 26-bit limbs.
struct Poly1305 {
    private var r = [UInt32](repeating: 0, count: 5)
    private var h = [UInt32](repeating: 0, count: 5)
    private var pad = [UInt32](repeating: 0, count: 4)
    private var buffer: [UInt8] = []

    private static func load32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    init(key: [UInt8]) {
        r[0] = Self.load32(key, 0) & 0x3ff_ffff
        r[1] = (Self.load32(key, 3) >> 2) & 0x3ff_ff03
        r[2] = (Self.load32(key, 6) >> 4) & 0x3ff_c0ff
        r[3] = (Self.load32(key, 9) >> 6) & 0x3f0_3fff
        r[4] = (Self.load32(key, 12) >> 8) & 0x00f_ffff
        for i in 0 ..< 4 { pad[i] = Self.load32(key, 16 + 4 * i) }
    }

    mutating func update(_ data: [UInt8]) {
        buffer += data
        var offset = 0
        while buffer.count - offset >= 16 {
            process(Array(buffer[offset ..< offset + 16]), hibit: 1 << 24)
            offset += 16
        }
        buffer.removeFirst(offset)
    }

    /// Adds a block, as a number with `hibit` above it, to the accumulator
    /// and multiplies by r.
    private mutating func process(_ block: [UInt8], hibit: UInt32) {
        let r0 = UInt64(r[0]), r1 = UInt64(r[1]), r2 = UInt64(r[2]), r3 = UInt64(r[3]), r4 = UInt64(r[4])
        let s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5
        let h0 = UInt64(h[0] &+ (Self.load32(block, 0) & 0x3ff_ffff))
        let h1 = UInt64(h[1] &+ ((Self.load32(block, 3) >> 2) & 0x3ff_ffff))
        let h2 = UInt64(h[2] &+ ((Self.load32(block, 6) >> 4) & 0x3ff_ffff))
        let h3 = UInt64(h[3] &+ ((Self.load32(block, 9) >> 6) & 0x3ff_ffff))
        let h4 = UInt64(h[4] &+ ((Self.load32(block, 12) >> 8) | hibit))

        var d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
        var d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
        var d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
        var d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
        var d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0

        var carry = d0 >> 26; d0 &= 0x3ff_ffff
        d1 += carry; carry = d1 >> 26; d1 &= 0x3ff_ffff
        d2 += carry; carry = d2 >> 26; d2 &= 0x3ff_ffff
        d3 += carry; carry = d3 >> 26; d3 &= 0x3ff_ffff
        d4 += carry; carry = d4 >> 26; d4 &= 0x3ff_ffff
        d0 += carry * 5; carry = d0 >> 26; d0 &= 0x3ff_ffff
        d1 += carry

        h = [UInt32(d0), UInt32(d1), UInt32(d2), UInt32(d3), UInt32(d4)]
    }

    /// The 16-byte tag.
    mutating func finish() -> [UInt8] {
        if !buffer.isEmpty {
            // The last, short block has a one after it instead of the high bit.
            process(buffer + [1] + [UInt8](repeating: 0, count: 15 - buffer.count), hibit: 0)
            buffer = []
        }
        var h0 = h[0], h1 = h[1], h2 = h[2], h3 = h[3], h4 = h[4]
        var carry = h1 >> 26; h1 &= 0x3ff_ffff
        h2 &+= carry; carry = h2 >> 26; h2 &= 0x3ff_ffff
        h3 &+= carry; carry = h3 >> 26; h3 &= 0x3ff_ffff
        h4 &+= carry; carry = h4 >> 26; h4 &= 0x3ff_ffff
        h0 &+= carry &* 5; carry = h0 >> 26; h0 &= 0x3ff_ffff
        h1 &+= carry

        // h - (2^130 - 5), taken if h is not less than it.
        var g0 = h0 &+ 5; carry = g0 >> 26; g0 &= 0x3ff_ffff
        var g1 = h1 &+ carry; carry = g1 >> 26; g1 &= 0x3ff_ffff
        var g2 = h2 &+ carry; carry = g2 >> 26; g2 &= 0x3ff_ffff
        var g3 = h3 &+ carry; carry = g3 >> 26; g3 &= 0x3ff_ffff
        var g4 = h4 &+ carry &- (1 << 26)
        var mask = (g4 >> 31) &- 1
        g0 &= mask; g1 &= mask; g2 &= mask; g3 &= mask; g4 &= mask
        mask = ~mask
        h0 = (h0 & mask) | g0
        h1 = (h1 & mask) | g1
        h2 = (h2 & mask) | g2
        h3 = (h3 & mask) | g3
        h4 = (h4 & mask) | g4

        // h modulo 2^128, plus the pad.
        let words = [h0 | h1 << 26, h1 >> 6 | h2 << 20, h2 >> 12 | h3 << 14, h3 >> 18 | h4 << 8]
        var tag: [UInt8] = []
        var sum: UInt64 = 0
        for i in 0 ..< 4 {
            sum = UInt64(words[i]) + UInt64(pad[i]) + (sum >> 32)
            for shift in stride(from: 0, to: 32, by: 8) { tag.append(UInt8(truncatingIfNeeded: sum >> UInt64(shift))) }
        }
        return tag
    }
}
