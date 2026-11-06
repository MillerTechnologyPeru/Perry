import Crypto
import FoundationEssentials
import PerryObjCInterop

// SecKey: RSA keys (RSA.swift) and elliptic-curve keys on P-256, P-384 and
// P-521 (CryptoKit's types), in Apple's external representations, with
// the algorithms Security names by string.

// MARK: - Elliptic curves

enum Curve: Int {
    case p256 = 256, p384 = 384, p521 = 521

    var scalarSize: Int { self == .p256 ? 32 : self == .p384 ? 48 : 66 }
    var publicSize: Int { 1 + 2 * scalarSize }

    init?(publicSize: Int) {
        switch publicSize {
        case 65: self = .p256
        case 97: self = .p384
        case 133: self = .p521
        default: return nil
        }
    }

    init?(privateSize: Int) {
        switch privateSize {
        case 97: self = .p256
        case 145: self = .p384
        case 199: self = .p521
        default: return nil
        }
    }
}

/// A digest given as bytes, for ECDSA over digests the caller made.
struct RawDigest: Digest {
    static var byteCount: Int { 32 }
    let bytes: [UInt8]

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> Array<UInt8>.Iterator { bytes.makeIterator() }
    var description: String { "RawDigest(\(bytes.count) bytes)" }
}

/// An elliptic-curve key in X9.63 form: 04 ‖ X ‖ Y, then K if private.
struct ECKey {
    let curve: Curve
    let isPrivate: Bool
    let x963: Data

    init(x963: Data, isPrivate: Bool) throws {
        guard let curve = isPrivate ? Curve(privateSize: x963.count) : Curve(publicSize: x963.count),
              x963.first == 4 else { throw RSAError.invalidKey }
        self.curve = curve
        self.isPrivate = isPrivate
        self.x963 = x963
        // Validates the point (and scalar).
        _ = try publicPoint()
    }

    static func generate(_ curve: Curve) throws -> ECKey {
        switch curve {
        case .p256: return try ECKey(x963: P256.Signing.PrivateKey().x963Representation, isPrivate: true)
        case .p384: return try ECKey(x963: P384.Signing.PrivateKey().x963Representation, isPrivate: true)
        case .p521: return try ECKey(x963: P521.Signing.PrivateKey().x963Representation, isPrivate: true)
        }
    }

    func publicPoint() throws -> Data {
        guard isPrivate else {
            switch curve {
            case .p256: return try P256.Signing.PublicKey(x963Representation: x963).x963Representation
            case .p384: return try P384.Signing.PublicKey(x963Representation: x963).x963Representation
            case .p521: return try P521.Signing.PublicKey(x963Representation: x963).x963Representation
            }
        }
        switch curve {
        case .p256: return try P256.Signing.PrivateKey(x963Representation: x963).publicKey.x963Representation
        case .p384: return try P384.Signing.PrivateKey(x963Representation: x963).publicKey.x963Representation
        case .p521: return try P521.Signing.PrivateKey(x963Representation: x963).publicKey.x963Representation
        }
    }

    var publicKey: ECKey { get throws { try ECKey(x963: publicPoint(), isPrivate: false) } }

    /// DER, or r ‖ s with `raw`.
    func sign(digest: Data, raw: Bool) throws -> Data {
        guard isPrivate else { throw RSAError.invalidKey }
        let digest = RawDigest(bytes: Array(digest))
        switch curve {
        case .p256:
            let signature = try P256.Signing.PrivateKey(x963Representation: x963).signature(for: digest)
            return raw ? signature.rawRepresentation : signature.derRepresentation
        case .p384:
            let signature = try P384.Signing.PrivateKey(x963Representation: x963).signature(for: digest)
            return raw ? signature.rawRepresentation : signature.derRepresentation
        case .p521:
            let signature = try P521.Signing.PrivateKey(x963Representation: x963).signature(for: digest)
            return raw ? signature.rawRepresentation : signature.derRepresentation
        }
    }

    func verify(digest: Data, signature: Data, raw: Bool) throws -> Bool {
        let digest = RawDigest(bytes: Array(digest))
        let point = try publicPoint()
        switch curve {
        case .p256:
            let signature = raw ? try P256.Signing.ECDSASignature(rawRepresentation: signature)
                                : try P256.Signing.ECDSASignature(derRepresentation: signature)
            return try P256.Signing.PublicKey(x963Representation: point).isValidSignature(signature, for: digest)
        case .p384:
            let signature = raw ? try P384.Signing.ECDSASignature(rawRepresentation: signature)
                                : try P384.Signing.ECDSASignature(derRepresentation: signature)
            return try P384.Signing.PublicKey(x963Representation: point).isValidSignature(signature, for: digest)
        case .p521:
            let signature = raw ? try P521.Signing.ECDSASignature(rawRepresentation: signature)
                                : try P521.Signing.ECDSASignature(derRepresentation: signature)
            return try P521.Signing.PublicKey(x963Representation: point).isValidSignature(signature, for: digest)
        }
    }

    /// The ECDH shared secret with `peer`'s public point.
    func sharedSecret(with peer: ECKey) throws -> SharedSecret {
        guard isPrivate, peer.curve == curve else { throw RSAError.invalidKey }
        let point = try peer.publicPoint()
        switch curve {
        case .p256:
            return try P256.KeyAgreement.PrivateKey(x963Representation: x963)
                .sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: point))
        case .p384:
            return try P384.KeyAgreement.PrivateKey(x963Representation: x963)
                .sharedSecretFromKeyAgreement(with: P384.KeyAgreement.PublicKey(x963Representation: point))
        case .p521:
            return try P521.KeyAgreement.PrivateKey(x963Representation: x963)
                .sharedSecretFromKeyAgreement(with: P521.KeyAgreement.PublicKey(x963Representation: point))
        }
    }
}

extension SharedSecret {
    var bytes: Data { withUnsafeBytes { Data($0) } }

    func x963(_ hash: HashKind, sharedInfo: Data, count: Int) throws -> Data {
        let key: SymmetricKey
        switch hash {
        case .sha1: key = x963DerivedSymmetricKey(using: Insecure.SHA1.self, sharedInfo: sharedInfo, outputByteCount: count)
        case .sha256: key = x963DerivedSymmetricKey(using: SHA256.self, sharedInfo: sharedInfo, outputByteCount: count)
        case .sha384: key = x963DerivedSymmetricKey(using: SHA384.self, sharedInfo: sharedInfo, outputByteCount: count)
        case .sha512: key = x963DerivedSymmetricKey(using: SHA512.self, sharedInfo: sharedInfo, outputByteCount: count)
        case .sha224: throw RSAError.unsupported
        }
        return key.withUnsafeBytes { Data($0) }
    }
}

/// ECIES as Apple builds it: an ephemeral key's public point, then AES-GCM
/// cipher text and its 16-byte tag. The X9.63 KDF over the shared secret,
/// with the ephemeral point as shared info, gives the AES key (16 bytes
/// below P-384, 32 from it) and, for the variable-IV variants, the 16-byte
/// IV that is otherwise zero.
enum ECIES {
    static func keySize(_ curve: Curve) -> Int { curve == .p256 ? 16 : 32 }

    static func keys(_ secret: SharedSecret, _ hash: HashKind, ephemeral: Data, curve: Curve,
                     variableIV: Bool) throws -> (SymmetricKey, AES.GCM.Nonce) {
        let size = keySize(curve)
        let material = try secret.x963(hash, sharedInfo: ephemeral, count: size + (variableIV ? 16 : 0))
        let iv = variableIV ? material.suffix(16) : Data(repeating: 0, count: 16)
        return (SymmetricKey(data: material.prefix(size)), try AES.GCM.Nonce(data: iv))
    }

    static func encrypt(_ message: Data, to recipient: ECKey, hash: HashKind, variableIV: Bool) throws -> Data {
        let ephemeral = try ECKey.generate(recipient.curve)
        let point = try ephemeral.publicPoint()
        let (key, nonce) = try keys(ephemeral.sharedSecret(with: recipient), hash, ephemeral: point,
                                    curve: recipient.curve, variableIV: variableIV)
        let box = try AES.GCM.seal(message, using: key, nonce: nonce)
        return point + box.ciphertext + box.tag
    }

    static func decrypt(_ cipher: Data, with key: ECKey, hash: HashKind, variableIV: Bool) throws -> Data {
        let size = key.curve.publicSize
        guard cipher.count >= size + 16 else { throw RSAError.invalidInput }
        let point = Data(cipher.prefix(size))
        let ephemeral = try ECKey(x963: point, isPrivate: false)
        let (symmetric, nonce) = try keys(key.sharedSecret(with: ephemeral), hash, ephemeral: point, curve: key.curve,
                                          variableIV: variableIV)
        let body = cipher.dropFirst(size)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body.dropLast(16), tag: body.suffix(16))
        return try AES.GCM.open(box, using: symmetric)
    }
}

// MARK: - Algorithms

/// A SecKeyAlgorithm, parsed from its name ("algid:sign:RSA:message-PSS:SHA256:SHA256:32").
enum Algorithm {
    enum Signature { case pkcs1, pss, rsaRaw, x962, rfc4754 }
    enum Encryption { case pkcs1, oaep, raw }

    case sign(Signature, hash: HashKind?, message: Bool, rsa: Bool)
    case encrypt(Encryption, hash: HashKind?)
    case ecies(hash: HashKind, variableIV: Bool)
    case exchange(hash: HashKind?)

    static func hash(_ name: Substring?) -> HashKind? {
        switch name {
        case "SHA1": return .sha1
        case "SHA224": return .sha224
        case "SHA256": return .sha256
        case "SHA384": return .sha384
        case "SHA512": return .sha512
        default: return nil
        }
    }

    init?(_ name: String) {
        let parts = name.split(separator: ":")
        guard parts.count >= 3, parts[0] == "algid" else { return nil }
        let part = { (index: Int) -> Substring? in index < parts.count ? parts[index] : nil }
        switch (parts[1], parts[2]) {
        case ("sign", "RSA"):
            guard let mode = part(3) else { return nil }
            if mode == "raw" { self = .sign(.rsaRaw, hash: nil, message: false, rsa: true); return }
            let message = mode.hasPrefix("message-")
            let scheme: Signature = mode.hasSuffix("PSS") ? .pss : .pkcs1
            let hash = Algorithm.hash(part(4))
            if (message || scheme == .pss) && hash == nil { return nil }
            self = .sign(scheme, hash: hash, message: message, rsa: true)
        case ("sign", "ECDSA"):
            guard let mode = part(3) else { return nil }
            if mode == "RFC4754" { self = .sign(.rfc4754, hash: nil, message: false, rsa: false); return }
            let message = mode.hasPrefix("message-")
            let scheme: Signature = mode.hasSuffix("RFC4754") ? .rfc4754 : .x962
            let hash = Algorithm.hash(part(4))
            if message && hash == nil { return nil }
            self = .sign(scheme, hash: hash, message: message, rsa: false)
        case ("encrypt", "RSA"):
            switch part(3) {
            case "raw": self = .encrypt(.raw, hash: nil)
            case "PKCS1": self = .encrypt(.pkcs1, hash: nil)
            case "OAEP":
                guard let hash = Algorithm.hash(part(4)), parts.count == 5 else { return nil }
                self = .encrypt(.oaep, hash: hash)
            default: return nil
            }
        case ("encrypt", "ECIES"):
            guard let hash = Algorithm.hash(part(5)), let cipher = part(6), cipher.hasPrefix("AESGCM") else { return nil }
            self = .ecies(hash: hash, variableIV: cipher == "AESGCM-KDFIV")
        case ("keyexchange", "ECDH"), ("keyexchange", "ECDHC"):
            if parts.count == 3 { self = .exchange(hash: nil); return }
            guard part(3) == "KDFX963", let hash = Algorithm.hash(part(4)) else { return nil }
            self = .exchange(hash: hash)
        default:
            return nil
        }
    }
}

// MARK: - SecKey

/// SecKeyOperationType.
enum KeyOperation: Int {
    case sign = 0, verify = 1, encrypt = 2, decrypt = 3, keyExchange = 4
}

final class KeyState {
    enum Material {
        case rsa(RSAKey)
        case ec(ECKey)
    }

    let material: Material
    var label: String?
    var tag: Data?

    init(_ material: Material) {
        self.material = material
    }

    var isPrivate: Bool {
        switch material {
        case .rsa(let key): return key.isPrivate
        case .ec(let key): return key.isPrivate
        }
    }

    var isRSA: Bool {
        if case .rsa = material { return true }
        return false
    }

    var bits: Int {
        switch material {
        case .rsa(let key): return key.bits
        case .ec(let key): return key.curve.rawValue
        }
    }

    var blockSize: Int {
        switch material {
        case .rsa(let key): return key.blockSize
        case .ec(let key): return key.curve.scalarSize
        }
    }

    /// Apple's external representation.
    var external: Data {
        switch material {
        case .rsa(let key): return key.der
        case .ec(let key): return key.x963
        }
    }

    var publicKey: KeyState {
        get throws {
            switch material {
            case .rsa(let key): return KeyState(.rsa(try key.publicKey))
            case .ec(let key): return KeyState(.ec(try key.publicKey))
            }
        }
    }

    /// SecKeyCreateWithData's input, by type ("42" RSA, "73" EC) and class.
    static func make(type: String, isPrivate: Bool, data: Data) throws -> KeyState {
        if type == ItemKeys.kSecAttrKeyTypeRSA { return KeyState(.rsa(try RSAKey(der: data, isPrivate: isPrivate))) }
        if type == ItemKeys.kSecAttrKeyTypeECSECPrimeRandom { return KeyState(.ec(try ECKey(x963: data, isPrivate: isPrivate))) }
        throw RSAError.unsupported
    }

    func supports(_ operation: KeyOperation, _ algorithm: Algorithm) -> Bool {
        switch (operation, algorithm) {
        case (.sign, .sign(_, _, _, let rsa)): return isPrivate && rsa == isRSA
        case (.verify, .sign(_, _, _, let rsa)): return rsa == isRSA
        case (.encrypt, .encrypt): return !isPrivate && isRSA
        case (.decrypt, .encrypt): return isPrivate && isRSA
        case (.encrypt, .ecies): return !isPrivate && !isRSA
        case (.decrypt, .ecies): return isPrivate && !isRSA
        case (.keyExchange, .exchange): return isPrivate && !isRSA
        default: return false
        }
    }

    /// The digest an algorithm signs: the hash of a message, or the input.
    private func digest(_ data: Data, hash: HashKind?, message: Bool) throws -> Data {
        guard message, let hash else { return data }
        return try hash.hash(data)
    }

    func sign(_ algorithm: Algorithm, _ data: Data) throws -> Data {
        guard case .sign(let scheme, let hash, let message, _) = algorithm else { throw RSAError.unsupported }
        let digest = try digest(data, hash: hash, message: message)
        switch (material, scheme) {
        case (.rsa(let key), .pkcs1): return try key.signPKCS1(digest, hash: hash)
        case (.rsa(let key), .pss): return try key.signPSS(digest, hash: hash!)
        case (.rsa(let key), .rsaRaw): return try key.privateOperation(Data(repeating: 0, count: max(0, key.blockSize - data.count)) + data)
        case (.ec(let key), .x962): return try key.sign(digest: digest, raw: false)
        case (.ec(let key), .rfc4754): return try key.sign(digest: digest, raw: true)
        default: throw RSAError.unsupported
        }
    }

    func verify(_ algorithm: Algorithm, _ data: Data, signature: Data) throws -> Bool {
        guard case .sign(let scheme, let hash, let message, _) = algorithm else { throw RSAError.unsupported }
        let digest = try digest(data, hash: hash, message: message)
        switch (material, scheme) {
        case (.rsa(let key), .pkcs1): return try key.publicKey.verifyPKCS1(digest, signature: signature, hash: hash)
        case (.rsa(let key), .pss): return try key.publicKey.verifyPSS(digest, signature: signature, hash: hash!)
        case (.rsa(let key), .rsaRaw):
            return try key.publicKey.publicOperation(signature) == Data(repeating: 0, count: max(0, key.blockSize - data.count)) + data
        case (.ec(let key), .x962): return (try? key.verify(digest: digest, signature: signature, raw: false)) ?? false
        case (.ec(let key), .rfc4754): return (try? key.verify(digest: digest, signature: signature, raw: true)) ?? false
        default: throw RSAError.unsupported
        }
    }

    func encrypt(_ algorithm: Algorithm, _ data: Data) throws -> Data {
        switch (material, algorithm) {
        case (.rsa(let key), .encrypt(.pkcs1, _)): return try key.encryptPKCS1(data)
        case (.rsa(let key), .encrypt(.oaep, let hash)): return try key.encryptOAEP(data, hash: hash!)
        case (.rsa(let key), .encrypt(.raw, _)): return try key.encryptRaw(data)
        case (.ec(let key), .ecies(let hash, let variableIV)):
            return try ECIES.encrypt(data, to: key.publicKey, hash: hash, variableIV: variableIV)
        default: throw RSAError.unsupported
        }
    }

    func decrypt(_ algorithm: Algorithm, _ data: Data) throws -> Data {
        switch (material, algorithm) {
        case (.rsa(let key), .encrypt(.pkcs1, _)): return try key.decryptPKCS1(data)
        case (.rsa(let key), .encrypt(.oaep, let hash)): return try key.decryptOAEP(data, hash: hash!)
        case (.rsa(let key), .encrypt(.raw, _)): return try key.decryptRaw(data)
        case (.ec(let key), .ecies(let hash, let variableIV)):
            return try ECIES.decrypt(data, with: key, hash: hash, variableIV: variableIV)
        default: throw RSAError.unsupported
        }
    }

    func exchange(_ algorithm: Algorithm, with peer: KeyState, requested: Int?, sharedInfo: Data) throws -> Data {
        guard case .ec(let key) = material, case .ec(let other) = peer.material,
              case .exchange(let hash) = algorithm else { throw RSAError.unsupported }
        let secret = try key.sharedSecret(with: other)
        guard let hash else { return secret.bytes }
        return try secret.x963(hash, sharedInfo: sharedInfo, count: requested ?? key.curve.scalarSize)
    }

    /// SecKeyCopyAttributes' dictionary.
    var attributes: [(String, NSObject)] {
        let isPrivate = self.isPrivate
        let ec = !isRSA
        var entries: [(String, NSObject)] = [
            (ItemKeys.kSecAttrKeyClass, NSObject.string(isPrivate ? ItemKeys.kSecAttrKeyClassPrivate : ItemKeys.kSecAttrKeyClassPublic)),
            (ItemKeys.kSecAttrKeyType, NSObject.string(isRSA ? ItemKeys.kSecAttrKeyTypeRSA : ItemKeys.kSecAttrKeyTypeECSECPrimeRandom)),
            (ItemKeys.kSecAttrKeySizeInBits, NSNumber.make(int64: Int64(bits))),
            (ItemKeys.kSecAttrEffectiveKeySize, NSNumber.make(int64: Int64(bits))),
            (ItemKeys.kSecAttrCanSign, NSNumber.make(bool: isPrivate)),
            (ItemKeys.kSecAttrCanVerify, NSNumber.make(bool: !isPrivate)),
            (ItemKeys.kSecAttrCanEncrypt, NSNumber.make(bool: !isPrivate)),
            (ItemKeys.kSecAttrCanDecrypt, NSNumber.make(bool: isPrivate)),
            (ItemKeys.kSecAttrCanDerive, NSNumber.make(bool: isPrivate && ec)),
            (ItemKeys.kSecAttrCanWrap, NSNumber.make(bool: !isPrivate)),
            (ItemKeys.kSecAttrCanUnwrap, NSNumber.make(bool: isPrivate)),
            (ItemKeys.kSecAttrIsPermanent, NSNumber.make(bool: false)),
            (ItemKeys.kSecValueData, NSData.of(external)),
        ]
        if let applicationLabel = try? Keys.applicationLabel(self) {
            entries.append((ItemKeys.kSecAttrApplicationLabel, NSData.of(applicationLabel)))
        }
        if let label { entries.append((ItemKeys.kSecAttrLabel, NSObject.string(label))) }
        if let tag { entries.append((ItemKeys.kSecAttrApplicationTag, NSData.of(tag))) }
        return entries
    }
}

/// SecKey objects.
@ObjCClass("__SecKey")
final class SecKeyObject: NSObject {
    static let states = StateTable<KeyState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecKeyObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecKeyObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.key }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let mine = SecKeyObject.states[objcObject], let theirs = SecKeyObject.states[other?.objcObject] else { return false }
        return mine.isPrivate == theirs.isPrivate && mine.external == theirs.external
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: SecKeyObject.states[objcObject]?.external.hashValue ?? 0) }

    @ObjCMethod("description")
    func description() -> String {
        guard let state = SecKeyObject.states[objcObject] else { return "<SecKeyRef>" }
        return "<SecKeyRef algorithm id: \(state.isRSA ? 1 : 3), key type: \(state.isRSA ? "RSA" : "ECSECPrimeRandom")"
            + "\(state.isPrivate ? "PrivateKey" : "PublicKey"), version: 4, block size: \(state.bits) bits, addr: \(objcObject)>"
    }
}

/// CFTypeIDs of Security's types.
enum TypeIDs {
    static let key: UInt = 0x5345_0001
    static let certificate: UInt = 0x5345_0002
    static let trust: UInt = 0x5345_0003
    static let policy: UInt = 0x5345_0004
    static let accessControl: UInt = 0x5345_0005
    static let identity: UInt = 0x5345_0006
}

enum Keys {
    /// A new SecKey (+1) for a key.
    static func object(_ state: KeyState) -> UnsafeMutableRawPointer {
        let object = SecKeyObject.objCClass.ownedInstance()
        SecKeyObject.states.set(object, state)
        return object
    }

    static func state(_ object: UnsafeMutableRawPointer?) -> KeyState? { SecKeyObject.states[object] }

    /// kSecAttrApplicationLabel: the SHA-1 of the public key (of its X9.63
    /// point for EC, its PKCS #1 encoding for RSA).
    static func applicationLabel(_ key: KeyState) throws -> Data {
        try HashKind.sha1.hash(key.publicKey.external)
    }

    static func algorithm(_ name: UnsafeMutableRawPointer?) -> Algorithm? {
        name.flatMap { Algorithm(String(objCArgument: $0)) }
    }

    static func data(_ object: UnsafeMutableRawPointer?) -> Data? {
        guard let object else { return nil }
        return NSData(object).data
    }

    static func returned(_ data: Data) -> UnsafeMutableRawPointer? {
        ObjCRuntime.retain(NSData.of(data).objcObject)
    }

    /// The key size and type in a parameters dictionary.
    static func parameters(_ dictionary: NSDictionary) -> (type: String, bits: Int)? {
        guard let type = dictionary.object(ItemKeys.kSecAttrKeyType), type.isString else { return nil }
        let bits = dictionary.object(ItemKeys.kSecAttrKeySizeInBits)?.integer
            ?? (type.stringValue == ItemKeys.kSecAttrKeyTypeRSA ? 2048 : 256)
        return (type.stringValue, bits)
    }
}

// MARK: - Functions

@c(_SecKeyGetTypeID) public func SecKeyGetTypeID() -> UInt { TypeIDs.key }

@c(_SecKeyCreateRandomKey)
public func SecKeyCreateRandomKey(_ parameters: UnsafeMutableRawPointer?,
                                  _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let parameters, let (type, bits) = Keys.parameters(NSDictionary(parameters)) else {
        Status.report(error, Status.param)
        return nil
    }
    let state: KeyState
    do {
        if type == ItemKeys.kSecAttrKeyTypeRSA {
            state = KeyState(.rsa(try RSAKey.generate(bits: bits)))
        } else if type == ItemKeys.kSecAttrKeyTypeECSECPrimeRandom, let curve = Curve(rawValue: bits) {
            state = KeyState(.ec(try ECKey.generate(curve)))
        } else {
            Status.report(error, Status.param, "Key generation failed: unsupported key size \(bits)")
            return nil
        }
    } catch _ {
        Status.report(error, Status.param)
        return nil
    }
    // Private key attributes: a label, a tag, and permanence in the keychain.
    let dictionary = NSDictionary(parameters)
    let privateAttributes = dictionary.object(ItemKeys.kSecPrivateKeyAttrs).map { NSDictionary($0.objcObject) }
    for source in [dictionary, privateAttributes].compactMap({ $0 }) {
        if let label = source.object(ItemKeys.kSecAttrLabel), label.isString { state.label = label.stringValue }
        if let tag = source.object(ItemKeys.kSecAttrApplicationTag) {
            state.tag = tag.isData ? NSData(tag.objcObject).data : tag.isString ? Data(tag.stringValue.utf8) : nil
        }
    }
    let permanent = (privateAttributes?.object(ItemKeys.kSecAttrIsPermanent) ?? dictionary.object(ItemKeys.kSecAttrIsPermanent))?.truth ?? false
    if permanent {
        let status = Keychain.shared.add(key: state, attributes: privateAttributes)
        if status != Status.success {
            Status.report(error, status)
            return nil
        }
        // macOS keeps the pair's public key beside it, with the same label
        // and tag unless the public key's attributes give their own; apps
        // (Xbox Live's Xal) look both up.
        if let publicState = try? state.publicKey {
            let publicAttributes = dictionary.object(ItemKeys.kSecPublicKeyAttrs).map { NSDictionary($0.objcObject) }
            (publicState.label, publicState.tag) = (state.label, state.tag)
            if let label = publicAttributes?.object(ItemKeys.kSecAttrLabel), label.isString { publicState.label = label.stringValue }
            if let tag = publicAttributes?.object(ItemKeys.kSecAttrApplicationTag) {
                publicState.tag = tag.isData ? NSData(tag.objcObject).data : tag.isString ? Data(tag.stringValue.utf8) : nil
            }
            let added = Keychain.shared.add(key: publicState, attributes: publicAttributes)
            if added != Status.success && added != Status.duplicateItem { securityWarning("SecKeyCreateRandomKey: the public key wasn't kept: \(added)") }
        }
    }
    return Keys.object(state)
}

@c(_SecKeyCreateWithData)
public func SecKeyCreateWithData(_ data: UnsafeMutableRawPointer?, _ attributes: UnsafeMutableRawPointer?,
                                 _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let bytes = Keys.data(data), let attributes,
          let type = NSDictionary(attributes).object(ItemKeys.kSecAttrKeyType), type.isString,
          let keyClass = NSDictionary(attributes).object(ItemKeys.kSecAttrKeyClass) else {
        securityWarning("SecKeyCreateWithData: no data, or no key type or class in the attributes")
        Status.report(error, Status.param)
        return nil
    }
    let isPrivate = keyClass.stringValue == ItemKeys.kSecAttrKeyClassPrivate
    let state: KeyState
    do {
        state = try KeyState.make(type: type.stringValue, isPrivate: isPrivate, data: bytes)
    } catch let failure {
        let prefix = bytes.prefix(8).map { String($0, radix: 16) }.joined(separator: " ")
        securityWarning("SecKeyCreateWithData: a \(isPrivate ? "private" : "public") key of type \(type.stringValue), "
                        + "\(bytes.count) bytes (\(prefix)…), can't be read: \(failure)")
        Status.report(error, Status.decode, "Failed to create key from data")
        return nil
    }
    return Keys.object(state)
}

/// OSStatus SecKeyGeneratePair(CFDictionaryRef, SecKeyRef *, SecKeyRef *):
/// SecKeyCreateRandomKey's older form, which also keeps the public key in
/// the keychain when its attributes ask for that.
@c(_SecKeyGeneratePair)
public func SecKeyGeneratePair(_ parameters: UnsafeMutableRawPointer?, _ publicKey: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                               _ privateKey: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    var error: UnsafeMutableRawPointer?
    guard let parameters, let created = SecKeyCreateRandomKey(parameters, &error) else {
        return error.map { Int32(truncatingIfNeeded: NSObject(objcObject: $0, ownership: .adopt).sendErrorCode()) } ?? Status.param
    }
    guard let state = Keys.state(created), let publicState = try? state.publicKey else { return Status.param }
    let publicAttributes = NSDictionary(parameters).object(ItemKeys.kSecPublicKeyAttrs).map { NSDictionary($0.objcObject) }
    if let publicAttributes {
        if let label = publicAttributes.object(ItemKeys.kSecAttrLabel), label.isString { publicState.label = label.stringValue }
        if let tag = publicAttributes.object(ItemKeys.kSecAttrApplicationTag) {
            publicState.tag = tag.isData ? NSData(tag.objcObject).data : tag.isString ? Data(tag.stringValue.utf8) : nil
        }
        if publicAttributes.object(ItemKeys.kSecAttrIsPermanent)?.truth ?? false {
            // SecKeyCreateRandomKey keeps it already when the pair is permanent.
            let status = Keychain.shared.add(key: publicState, attributes: publicAttributes)
            if status != Status.success && status != Status.duplicateItem { return status }
        }
    }
    privateKey?.pointee = created
    publicKey?.pointee = Keys.object(publicState)
    return Status.success
}

@c(_SecKeyCopyPublicKey)
public func SecKeyCopyPublicKey(_ key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Keys.state(key), let publicKey = try? state.publicKey else { return nil }
    return Keys.object(publicKey)
}

@c(_SecKeyCopyExternalRepresentation)
public func SecKeyCopyExternalRepresentation(_ key: UnsafeMutableRawPointer?,
                                             _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let state = Keys.state(key) else {
        Status.report(error, Status.param)
        return nil
    }
    return Keys.returned(state.external)
}

@c(_SecKeyCopyAttributes)
public func SecKeyCopyAttributes(_ key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = Keys.state(key) else { return nil }
    return ObjCRuntime.retain(NSMutableDictionary.of(state.attributes).objcObject)
}

@c(_SecKeyGetBlockSize)
public func SecKeyGetBlockSize(_ key: UnsafeMutableRawPointer?) -> Int {
    Keys.state(key)?.blockSize ?? 0
}

@c(_SecKeyIsAlgorithmSupported)
public func SecKeyIsAlgorithmSupported(_ key: UnsafeMutableRawPointer?, _ operation: Int, _ algorithm: UnsafeMutableRawPointer?) -> Bool {
    guard let state = Keys.state(key), let operation = KeyOperation(rawValue: operation),
          let algorithm = Keys.algorithm(algorithm) else { return false }
    return state.supports(operation, algorithm)
}

private func perform(_ key: UnsafeMutableRawPointer?, _ operation: KeyOperation, _ algorithmName: UnsafeMutableRawPointer?,
                     _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ body: (KeyState, Algorithm) throws -> Data)
    -> UnsafeMutableRawPointer? {
    guard let state = Keys.state(key), let algorithm = Keys.algorithm(algorithmName) else {
        Status.report(error, Status.param)
        return nil
    }
    guard state.supports(operation, algorithm) else {
        let name = algorithmName.map { String(objCArgument: $0) } ?? ""
        Status.report(error, Status.param, "\(name) not supported for this key")
        return nil
    }
    do {
        return Keys.returned(try body(state, algorithm))
    } catch _ {
        Status.report(error, Status.param, "operation failed")
        return nil
    }
}

@c(_SecKeyCreateSignature)
public func SecKeyCreateSignature(_ key: UnsafeMutableRawPointer?, _ algorithm: UnsafeMutableRawPointer?,
                                  _ data: UnsafeMutableRawPointer?,
                                  _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    perform(key, .sign, algorithm, error) { state, algorithm in try state.sign(algorithm, Keys.data(data) ?? Data()) }
}

@c(_SecKeyVerifySignature)
public func SecKeyVerifySignature(_ key: UnsafeMutableRawPointer?, _ algorithmName: UnsafeMutableRawPointer?,
                                  _ data: UnsafeMutableRawPointer?, _ signature: UnsafeMutableRawPointer?,
                                  _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    guard let state = Keys.state(key), let algorithm = Keys.algorithm(algorithmName),
          state.supports(.verify, algorithm) else {
        Status.report(error, Status.param)
        return false
    }
    let valid = (try? state.verify(algorithm, Keys.data(data) ?? Data(), signature: Keys.data(signature) ?? Data())) ?? false
    if !valid { Status.report(error, Status.verifyFailed, "signature verification failed") }
    return valid
}

@c(_SecKeyCreateEncryptedData)
public func SecKeyCreateEncryptedData(_ key: UnsafeMutableRawPointer?, _ algorithm: UnsafeMutableRawPointer?,
                                      _ data: UnsafeMutableRawPointer?,
                                      _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    perform(key, .encrypt, algorithm, error) { state, algorithm in try state.encrypt(algorithm, Keys.data(data) ?? Data()) }
}

@c(_SecKeyCreateDecryptedData)
public func SecKeyCreateDecryptedData(_ key: UnsafeMutableRawPointer?, _ algorithm: UnsafeMutableRawPointer?,
                                      _ data: UnsafeMutableRawPointer?,
                                      _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    perform(key, .decrypt, algorithm, error) { state, algorithm in try state.decrypt(algorithm, Keys.data(data) ?? Data()) }
}

@c(_SecKeyCopyKeyExchangeResult)
public func SecKeyCopyKeyExchangeResult(_ key: UnsafeMutableRawPointer?, _ algorithm: UnsafeMutableRawPointer?,
                                        _ peer: UnsafeMutableRawPointer?, _ parameters: UnsafeMutableRawPointer?,
                                        _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    perform(key, .keyExchange, algorithm, error) { state, algorithm in
        guard let other = Keys.state(peer) else { throw RSAError.invalidKey }
        let dictionary = parameters.map { NSDictionary($0) }
        let requested = dictionary?.object(ItemKeys.kSecKeyKeyExchangeParameterRequestedSize)?.integer
        let sharedInfo = dictionary?.object(ItemKeys.kSecKeyKeyExchangeParameterSharedInfo).map { NSData($0.objcObject).data } ?? Data()
        return try state.exchange(algorithm, with: other, requested: requested, sharedInfo: sharedInfo)
    }
}

// MARK: - The older padding API

/// SecPadding: none 0, PKCS1 1, OAEP 2, then PKCS1 with a DigestInfo.
private func paddedAlgorithm(_ padding: UInt32, signing: Bool, rsa: Bool) -> Algorithm? {
    if !rsa { return signing ? .sign(.x962, hash: nil, message: false, rsa: false) : nil }
    switch padding {
    case 0: return signing ? .sign(.rsaRaw, hash: nil, message: false, rsa: true) : .encrypt(.raw, hash: nil)
    case 1: return signing ? .sign(.pkcs1, hash: nil, message: false, rsa: true) : .encrypt(.pkcs1, hash: nil)
    case 2: return signing ? nil : .encrypt(.oaep, hash: .sha1)
    case 0x8002: return .sign(.pkcs1, hash: .sha1, message: false, rsa: true)
    case 0x8003: return .sign(.pkcs1, hash: .sha224, message: false, rsa: true)
    case 0x8004: return .sign(.pkcs1, hash: .sha256, message: false, rsa: true)
    case 0x8005: return .sign(.pkcs1, hash: .sha384, message: false, rsa: true)
    case 0x8006: return .sign(.pkcs1, hash: .sha512, message: false, rsa: true)
    default: return nil
    }
}

private func output(_ data: Data, _ buffer: UnsafeMutablePointer<UInt8>?, _ length: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let buffer, let length, data.count <= length.pointee else { return Status.param }
    data.copyBytes(to: buffer, count: data.count)
    length.pointee = data.count
    return 0
}

@c(_SecKeyRawSign)
public func SecKeyRawSign(_ key: UnsafeMutableRawPointer?, _ padding: UInt32, _ data: UnsafePointer<UInt8>?, _ length: Int,
                          _ signature: UnsafeMutablePointer<UInt8>?, _ signatureLength: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let state = Keys.state(key), let data, let algorithm = paddedAlgorithm(padding, signing: true, rsa: state.isRSA),
          let signed = try? state.sign(algorithm, Data(bytes: data, count: length)) else { return Status.param }
    return output(signed, signature, signatureLength)
}

@c(_SecKeyRawVerify)
public func SecKeyRawVerify(_ key: UnsafeMutableRawPointer?, _ padding: UInt32, _ data: UnsafePointer<UInt8>?, _ length: Int,
                            _ signature: UnsafePointer<UInt8>?, _ signatureLength: Int) -> Int32 {
    guard let state = Keys.state(key), let data, let signature,
          let algorithm = paddedAlgorithm(padding, signing: true, rsa: state.isRSA) else { return Status.param }
    let valid = (try? state.verify(algorithm, Data(bytes: data, count: length),
                                   signature: Data(bytes: signature, count: signatureLength))) ?? false
    return valid ? 0 : Status.verifyFailed
}

@c(_SecKeyEncrypt)
public func SecKeyEncrypt(_ key: UnsafeMutableRawPointer?, _ padding: UInt32, _ plain: UnsafePointer<UInt8>?, _ length: Int,
                          _ cipher: UnsafeMutablePointer<UInt8>?, _ cipherLength: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let state = Keys.state(key), let plain, let algorithm = paddedAlgorithm(padding, signing: false, rsa: state.isRSA),
          let encrypted = try? state.encrypt(algorithm, Data(bytes: plain, count: length)) else { return Status.param }
    return output(encrypted, cipher, cipherLength)
}

@c(_SecKeyDecrypt)
public func SecKeyDecrypt(_ key: UnsafeMutableRawPointer?, _ padding: UInt32, _ cipher: UnsafePointer<UInt8>?, _ length: Int,
                          _ plain: UnsafeMutablePointer<UInt8>?, _ plainLength: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let state = Keys.state(key), let cipher, let algorithm = paddedAlgorithm(padding, signing: false, rsa: state.isRSA),
          let decrypted = try? state.decrypt(algorithm, Data(bytes: cipher, count: length)) else { return Status.param }
    return output(decrypted, plain, plainLength)
}

extension NSObject {
    @ObjCMethod("code") func sendErrorCode() -> Int
}
