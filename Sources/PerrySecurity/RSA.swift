import Crypto
import _CryptoExtras
import FoundationEssentials

// RSA as Security offers it: PKCS #1 v1.5 and PSS signatures over messages
// or digests, raw signatures, and PKCS #1 v1.5, OAEP and raw encryption.
// _CryptoExtras covers some of these and not others, so the encodings
// (RFC 8017) are done here over the two raw operations: the private one by
// BoringSSL (blind signing's, which is unpadded and blinded), the public
// one, whose exponent is public, by a Montgomery exponentiation below.

enum RSAError: Error {
    case invalidKey, invalidInput, unsupported, verifyFailed
}

/// A hash Security names: SHA-1, SHA-224 (which swift-crypto lacks),
/// SHA-256, SHA-384 or SHA-512.
enum HashKind: Int {
    case sha1 = 20, sha224 = 28, sha256 = 32, sha384 = 48, sha512 = 64

    var length: Int { rawValue }

    func hash(_ data: Data) throws -> Data {
        switch self {
        case .sha1: return Data(Insecure.SHA1.hash(data: data))
        case .sha256: return Data(SHA256.hash(data: data))
        case .sha384: return Data(SHA384.hash(data: data))
        case .sha512: return Data(SHA512.hash(data: data))
        case .sha224: throw RSAError.unsupported
        }
    }

    /// The DER DigestInfo prefix for PKCS #1 v1.5 signatures.
    var digestInfoPrefix: [UInt8] {
        switch self {
        case .sha1: return [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14]
        case .sha224: return [0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04,
                              0x05, 0x00, 0x04, 0x1c]
        case .sha256: return [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01,
                              0x05, 0x00, 0x04, 0x20]
        case .sha384: return [0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02,
                              0x05, 0x00, 0x04, 0x30]
        case .sha512: return [0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03,
                              0x05, 0x00, 0x04, 0x40]
        }
    }

    /// MGF1: hashes of the seed and a counter, to `length` bytes.
    func mask(_ seed: Data, length: Int) throws -> Data {
        var output = Data()
        var counter: UInt32 = 0
        while output.count < length {
            var block = seed
            withUnsafeBytes(of: counter.bigEndian) { block.append(contentsOf: $0) }
            output.append(try hash(block))
            counter += 1
        }
        return output.prefix(length)
    }
}

private func randomBytes(_ count: Int, nonZero: Bool = false) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in
        nonZero ? UInt8.random(in: 1...255, using: &generator) : UInt8.random(in: 0...255, using: &generator)
    })
}

private func xor(_ a: Data, _ b: Data) -> Data {
    Data(zip(a, b).map { $0 ^ $1 })
}

/// An RSA key from Apple's external representation (PKCS #1 DER).
struct RSAKey {
    let isPrivate: Bool
    let der: Data
    let modulus: [UInt8]
    let exponent: [UInt8]

    init(der: Data, isPrivate: Bool) throws {
        self.isPrivate = isPrivate
        self.der = der
        let publicDER = isPrivate ? try _RSA.Signing.PrivateKey(unsafeDERRepresentation: der).publicKey.pkcs1DERRepresentation : der
        let primitives = try _RSA.BlindSigning.PublicKey<SHA384>(unsafeDERRepresentation: publicDER).getKeyPrimitives()
        modulus = Array(primitives.modulus.drop { $0 == 0 })
        exponent = Array(primitives.publicExponent)
    }

    static func generate(bits: Int) throws -> RSAKey {
        guard (1024...8192).contains(bits), bits % 8 == 0 else { throw RSAError.invalidInput }
        let key = try _RSA.Signing.PrivateKey(unsafeKeySize: _RSA.Signing.KeySize(bitCount: bits))
        return try RSAKey(der: key.derRepresentation, isPrivate: true)
    }

    var publicKey: RSAKey {
        get throws {
            guard isPrivate else { return self }
            return try RSAKey(der: _RSA.Signing.PrivateKey(unsafeDERRepresentation: der).publicKey.pkcs1DERRepresentation,
                              isPrivate: false)
        }
    }

    var bits: Int {
        guard let top = modulus.first else { return 0 }
        return (modulus.count - 1) * 8 + (8 - top.leadingZeroBitCount)
    }

    var blockSize: Int { modulus.count }

    // MARK: Raw operations

    /// m^d mod n, for an input of the modulus's size below the modulus.
    func privateOperation(_ input: Data) throws -> Data {
        guard isPrivate, input.count == blockSize else { throw RSAError.invalidInput }
        let key = try _RSA.BlindSigning.PrivateKey<SHA384>(unsafeDERRepresentation: der)
        return Data(try key.blindSignature(for: input).rawRepresentation)
    }

    /// m^e mod n.
    func publicOperation(_ input: Data) throws -> Data {
        guard input.count == blockSize else { throw RSAError.invalidInput }
        let result = Montgomery(modulus: modulus).power(Array(input), exponent)
        guard !result.isEmpty else { throw RSAError.invalidInput }
        return Data(result)
    }

    // MARK: Signatures

    /// PKCS #1 v1.5: DigestInfo with the hash, or the input as it is.
    func signPKCS1(_ digest: Data, hash: HashKind?) throws -> Data {
        let payload = (hash.map { Data($0.digestInfoPrefix) } ?? Data()) + digest
        guard payload.count + 11 <= blockSize else { throw RSAError.invalidInput }
        let padded = Data([0, 1]) + Data(repeating: 0xff, count: blockSize - payload.count - 3) + Data([0]) + payload
        return try privateOperation(padded)
    }

    func verifyPKCS1(_ digest: Data, signature: Data, hash: HashKind?) throws -> Bool {
        guard signature.count == blockSize else { return false }
        let payload = (hash.map { Data($0.digestInfoPrefix) } ?? Data()) + digest
        guard payload.count + 11 <= blockSize else { return false }
        let expected = Data([0, 1]) + Data(repeating: 0xff, count: blockSize - payload.count - 3) + Data([0]) + payload
        return try publicOperation(signature) == expected
    }

    /// EMSA-PSS with MGF1 and a salt as long as the hash.
    func signPSS(_ digest: Data, hash: HashKind) throws -> Data {
        let emBits = bits - 1
        let emLength = (emBits + 7) / 8
        let salt = randomBytes(hash.length)
        guard emLength >= hash.length * 2 + 2 else { throw RSAError.invalidInput }
        let h = try hash.hash(Data(repeating: 0, count: 8) + digest + salt)
        let db = Data(repeating: 0, count: emLength - salt.count - hash.length - 2) + Data([1]) + salt
        var masked = xor(db, try hash.mask(h, length: db.count))
        masked[masked.startIndex] &= UInt8(0xff >> (8 * emLength - emBits))
        let encoded = masked + h + Data([0xbc])
        return try privateOperation(Data(repeating: 0, count: blockSize - encoded.count) + encoded)
    }

    func verifyPSS(_ digest: Data, signature: Data, hash: HashKind) throws -> Bool {
        guard signature.count == blockSize else { return false }
        let emBits = bits - 1
        let emLength = (emBits + 7) / 8
        let encoded = try publicOperation(signature).suffix(emLength)
        guard encoded.count == emLength, encoded.last == 0xbc, emLength >= hash.length * 2 + 2 else { return false }
        let masked = Data(encoded.prefix(emLength - hash.length - 1))
        let h = Data(encoded.dropFirst(emLength - hash.length - 1).prefix(hash.length))
        guard masked.first! & ~UInt8(0xff >> (8 * emLength - emBits)) == 0 else { return false }
        var db = xor(masked, try hash.mask(h, length: masked.count))
        db[db.startIndex] &= UInt8(0xff >> (8 * emLength - emBits))
        let zeros = emLength - 2 * hash.length - 2
        guard db.prefix(zeros).allSatisfy({ $0 == 0 }), db[db.startIndex + zeros] == 1 else { return false }
        let salt = db.suffix(hash.length)
        return try hash.hash(Data(repeating: 0, count: 8) + digest + salt) == h
    }

    // MARK: Encryption

    func encryptPKCS1(_ message: Data) throws -> Data {
        guard message.count + 11 <= blockSize else { throw RSAError.invalidInput }
        let padding = randomBytes(blockSize - message.count - 3, nonZero: true)
        return try publicOperation(Data([0, 2]) + padding + Data([0]) + message)
    }

    func decryptPKCS1(_ cipher: Data) throws -> Data {
        let block = try privateOperation(cipher)
        guard block.count == blockSize, block[block.startIndex] == 0, block[block.startIndex + 1] == 2,
              let separator = block.dropFirst(2).firstIndex(of: 0), separator - block.startIndex >= 10 else {
            throw RSAError.invalidInput
        }
        return Data(block[(separator + 1)...])
    }

    func encryptOAEP(_ message: Data, hash: HashKind) throws -> Data {
        let k = blockSize, hLength = hash.length
        guard message.count + 2 * hLength + 2 <= k else { throw RSAError.invalidInput }
        let labelHash = try hash.hash(Data())
        let db = labelHash + Data(repeating: 0, count: k - message.count - 2 * hLength - 2) + Data([1]) + message
        let seed = randomBytes(hLength)
        let maskedDB = xor(db, try hash.mask(seed, length: k - hLength - 1))
        let maskedSeed = xor(seed, try hash.mask(maskedDB, length: hLength))
        return try publicOperation(Data([0]) + maskedSeed + maskedDB)
    }

    func decryptOAEP(_ cipher: Data, hash: HashKind) throws -> Data {
        let k = blockSize, hLength = hash.length
        let block = try privateOperation(cipher)
        guard block.count == k, block.first == 0, k >= 2 * hLength + 2 else { throw RSAError.invalidInput }
        let maskedSeed = Data(block.dropFirst().prefix(hLength))
        let maskedDB = Data(block.dropFirst(1 + hLength))
        let seed = xor(maskedSeed, try hash.mask(maskedDB, length: hLength))
        let db = xor(maskedDB, try hash.mask(seed, length: maskedDB.count))
        guard db.prefix(hLength) == (try hash.hash(Data())),
              let one = db.dropFirst(hLength).firstIndex(where: { $0 != 0 }), db[one] == 1 else {
            throw RSAError.invalidInput
        }
        return Data(db[(one + 1)...])
    }

    /// Raw: the input left-padded to the modulus's size.
    func encryptRaw(_ message: Data) throws -> Data {
        guard message.count <= blockSize else { throw RSAError.invalidInput }
        return try publicOperation(Data(repeating: 0, count: blockSize - message.count) + message)
    }

    func decryptRaw(_ cipher: Data) throws -> Data {
        try privateOperation(cipher)
    }
}

// MARK: - Montgomery exponentiation

/// Modular exponentiation with Montgomery multiplication on 64-bit limbs,
/// least significant first, for the public operation.
struct Montgomery {
    let n: [UInt64]
    let byteCount: Int
    let n0: UInt64          // -n⁻¹ mod 2⁶⁴
    let rSquared: [UInt64]  // R² mod n, R = 2^(64·limbs)

    init(modulus: [UInt8]) {
        n = Montgomery.limbs(modulus)
        byteCount = modulus.count
        // Newton's iteration for n[0]⁻¹ mod 2⁶⁴.
        var inverse: UInt64 = 1
        for _ in 0..<6 { inverse = inverse &* (2 &- n[0] &* inverse) }
        n0 = 0 &- inverse
        // R² mod n by doubling 1 2·64·limbs times, reducing as it goes.
        var value = [UInt64](repeating: 0, count: n.count)
        value[0] = 1
        for _ in 0..<(2 * 64 * n.count) { value = Montgomery.doubleMod(value, n) }
        rSquared = value
    }

    static func limbs(_ bytes: [UInt8]) -> [UInt64] {
        let count = max(1, (bytes.count + 7) / 8)
        var limbs = [UInt64](repeating: 0, count: count)
        for (index, byte) in bytes.reversed().enumerated() {
            limbs[index / 8] |= UInt64(byte) << (8 * UInt64(index % 8))
        }
        return limbs
    }

    static func bytes(_ limbs: [UInt64], count: Int) -> [UInt8] {
        (0..<count).reversed().map { index in UInt8(truncatingIfNeeded: limbs[index / 8] >> (8 * UInt64(index % 8))) }
    }

    static func compare(_ a: [UInt64], _ b: [UInt64]) -> Int {
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
        return 0
    }

    static func subtract(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var result = a
        var borrow: UInt64 = 0
        for i in 0..<a.count {
            let (d1, o1) = a[i].subtractingReportingOverflow(b[i])
            let (d2, o2) = d1.subtractingReportingOverflow(borrow)
            result[i] = d2
            borrow = (o1 || o2) ? 1 : 0
        }
        return result
    }

    static func doubleMod(_ value: [UInt64], _ n: [UInt64]) -> [UInt64] {
        var result = value
        var carry: UInt64 = 0
        for i in 0..<value.count {
            let next = value[i] >> 63
            result[i] = value[i] << 1 | carry
            carry = next
        }
        if carry == 1 || compare(result, n) >= 0 { result = subtract(result, n) }
        return result
    }

    /// a·b·R⁻¹ mod n (CIOS).
    func multiply(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        let count = n.count
        var t = [UInt64](repeating: 0, count: count + 2)
        for i in 0..<count {
            var carry: UInt64 = 0
            for j in 0..<count {
                let (high, low) = a[j].multipliedFullWidth(by: b[i])
                let (sum1, o1) = t[j].addingReportingOverflow(low)
                let (sum2, o2) = sum1.addingReportingOverflow(carry)
                t[j] = sum2
                carry = high &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            let (s, o) = t[count].addingReportingOverflow(carry)
            t[count] = s
            t[count + 1] = o ? 1 : 0
            let m = t[0] &* n0
            let (high0, low0) = m.multipliedFullWidth(by: n[0])
            let (_, overflow0) = t[0].addingReportingOverflow(low0)
            carry = high0 &+ (overflow0 ? 1 : 0)
            for j in 1..<count {
                let (high, low) = m.multipliedFullWidth(by: n[j])
                let (sum1, o1) = t[j].addingReportingOverflow(low)
                let (sum2, o2) = sum1.addingReportingOverflow(carry)
                t[j - 1] = sum2
                carry = high &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            let (s2, o2) = t[count].addingReportingOverflow(carry)
            t[count - 1] = s2
            t[count] = t[count + 1] &+ (o2 ? 1 : 0)
        }
        var result = Array(t[0..<count])
        if t[count] != 0 || Montgomery.compare(result, n) >= 0 { result = Montgomery.subtract(result, n) }
        return result
    }

    /// base^exponent mod n as big-endian bytes of the modulus's size; empty
    /// if the base is not below the modulus.
    func power(_ base: [UInt8], _ exponent: [UInt8]) -> [UInt8] {
        var b = Montgomery.limbs(base)
        if b.count < n.count { b += [UInt64](repeating: 0, count: n.count - b.count) }
        guard b.count == n.count, Montgomery.compare(b, n) < 0 else { return [] }
        var one = [UInt64](repeating: 0, count: n.count)
        one[0] = 1
        var result = multiply(one, rSquared)        // 1 in Montgomery form
        let baseMontgomery = multiply(b, rSquared)
        for byte in exponent {
            for bit in stride(from: 7, through: 0, by: -1) {
                result = multiply(result, result)
                if (byte >> UInt8(bit)) & 1 == 1 { result = multiply(result, baseMontgomery) }
            }
        }
        result = multiply(result, one)
        return Montgomery.bytes(result, count: byteCount)
    }
}
