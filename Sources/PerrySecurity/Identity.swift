import CPerrySecurity
import FoundationEssentials
import Glibc
import PerryObjCInterop

// SecIdentity: a certificate with its private key, as PKCS #12 data holds
// them. A program reads one with SecPKCS12Import and gives it to a TLS
// connection as its client certificate (SSLSetCertificate, or a stream's
// kCFStreamSSLCertificates).

final class IdentityState {
    /// The private key as DER: PKCS #1 for RSA, SEC 1 for an elliptic curve
    /// key.
    let key: Data
    let isRSA: Bool
    /// The certificates as DER, the key's own first, then the rest the
    /// data came with.
    let certificates: [Data]

    init(key: Data, isRSA: Bool, certificates: [Data]) {
        (self.key, self.isRSA, self.certificates) = (key, isRSA, certificates)
    }
}

@ObjCClass("__SecIdentity")
final class SecIdentityObject: NSObject {
    static let states = StateTable<IdentityState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecIdentityObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecIdentityObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.identity }

    @ObjCMethod("description")
    func description() -> String { "<SecIdentityRef: \(objcObject)>" }
}

enum Identities {
    static func state(_ object: UnsafeMutableRawPointer?) -> IdentityState? { SecIdentityObject.states[object] }

    /// A new SecIdentity (+1).
    static func object(_ state: IdentityState) -> UnsafeMutableRawPointer {
        let object = SecIdentityObject.objCClass.ownedInstance()
        SecIdentityObject.states.set(object, state)
        return object
    }

    /// The identity kSecImportItemIdentity's place in a list holds: the
    /// first of the list that is one. A client certificate list is an
    /// identity, then any certificates to send after its own.
    static func first(in list: UnsafeMutableRawPointer?) -> IdentityState? {
        guard let list else { return nil }
        if let state = state(list) { return state }
        guard NSObject(list).isArray else { return nil }
        return NSArray(list).elements.lazy.compactMap { state($0.objcObject) }.first
    }
}

@c(_SecIdentityGetTypeID) public func SecIdentityGetTypeID() -> UInt { TypeIDs.identity }

@c(_SecIdentityCopyCertificate)
public func SecIdentityCopyCertificate(_ identity: UnsafeMutableRawPointer?,
                                       _ certificate: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let certificate, let state = Identities.state(identity), let der = state.certificates.first,
          let made = CertificateState(der: der) else { return Status.param }
    certificate.pointee = Certificates.object(made)
    return Status.success
}

/// The private key, for an RSA identity; an elliptic curve one's is used
/// for TLS but not given out as a SecKey yet.
@c(_SecIdentityCopyPrivateKey)
public func SecIdentityCopyPrivateKey(_ identity: UnsafeMutableRawPointer?,
                                      _ key: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let key, let state = Identities.state(identity) else { return Status.param }
    guard state.isRSA, let made = try? KeyState.make(type: ItemKeys.kSecAttrKeyTypeRSA, isPrivate: true, data: state.key) else {
        securityWarning("SecIdentityCopyPrivateKey: the identity's key can't be given as a SecKey")
        return Status.unimplemented
    }
    key.pointee = Keys.object(made)
    return Status.success
}

/// SecPKCS12Import: the identity in PKCS #12 data, read with the
/// passphrase in the options: an array of one dictionary with the identity,
/// its certificate chain and a trust for it. errSecAuthFailed (-25293) for
/// a wrong passphrase, errSecDecode (-26275) for data that can't be read.
@c(_SecPKCS12Import)
public func SecPKCS12Import(_ data: UnsafeMutableRawPointer?, _ options: UnsafeMutableRawPointer?,
                            _ items: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    items?.pointee = nil
    guard let bytes = Keys.data(data), !bytes.isEmpty else { return Status.param }
    var passphrase: String?
    if let options, NSObject(options).isDictionary,
       let value = NSDictionary(options).object(ItemKeys.kSecImportExportPassphrase), value.isString {
        passphrase = value.stringValue
    }
    var parsed = perry_pkcs12()
    let result = bytes.withUnsafeBytes { raw -> Int32 in
        let pointer = raw.bindMemory(to: UInt8.self).baseAddress
        if let passphrase { return passphrase.withCString { perry_pkcs12_parse(pointer, raw.count, $0, &parsed) } }
        return perry_pkcs12_parse(pointer, raw.count, nil, &parsed)
    }
    if getenv("PERRY_STREAM_TRACE") != nil {
        securityWarning("SecPKCS12Import: \(bytes.count) bytes, \(passphrase == nil ? "no" : "a") passphrase: "
                        + (["read", "can't be read", "wrong passphrase", "no OpenSSL"][Int(min(max(result, 0), 3))]))
    }
    switch result {
    case 0: break
    case 2: return -25293
    case 3:
        securityWarning("SecPKCS12Import: OpenSSL can't be loaded")
        return Status.unimplemented
    default: return -26275
    }
    defer { perry_pkcs12_free(&parsed) }
    let certificates = (0..<parsed.count).map { Data(bytes: parsed.certificates[$0]!, count: parsed.certificate_lengths[$0]) }
    let state = IdentityState(key: Data(bytes: parsed.key, count: parsed.key_length), isRSA: parsed.key_type == 6,
                              certificates: certificates)
    let identity = Identities.object(state)
    defer { ObjCRuntime.release(identity) }
    let chain = certificates.compactMap { CertificateState(der: $0) }.map(Certificates.object)
    defer { chain.forEach { ObjCRuntime.release($0) } }
    var entries: [(String, NSObject)] = [(ItemKeys.kSecImportItemIdentity, NSObject(identity)),
                                         (ItemKeys.kSecImportItemCertChain, NSMutableArray.of(chain.map { NSObject($0) }))]
    if !chain.isEmpty {
        let trust = SecTrustObject.objCClass.ownedInstance()
        let policy = PolicyState(oid: ItemKeys.kSecPolicyAppleX509Basic, ssl: false, server: false, hostname: nil)
        SecTrustObject.states.set(trust, TrustState(certificates: chain, policies: [policy]))
        entries.append((ItemKeys.kSecImportItemTrust, NSObject(objCOwned: trust)))
    }
    if let summary = chain.first.flatMap({ Certificates.state($0)?.summary }) {
        entries.append((ItemKeys.kSecImportItemLabel, NSObject.string(summary)))
    }
    let item = NSMutableDictionary.of(entries)
    items?.pointee = ObjCRuntime.retain(NSMutableArray.of([item]).objcObject)
    return Status.success
}
