import Crypto
import _CryptoExtras
import FoundationEssentials
import Glibc
import PerryObjCInterop
import X509

// SecCertificate, SecPolicy and SecTrust over swift-certificates. Trust
// evaluation builds and checks a chain with its Verifier (RFC 5280 at the
// verify date, and the server's name for SSL policies), then explains a
// failure with the OSStatus Security reports: a host name mismatch when the
// chain alone verifies, an expired or not-yet-valid certificate when one in
// the chain is outside its validity, and otherwise an untrusted chain.

// MARK: - Certificates

final class CertificateState {
    let der: Data
    let certificate: Certificate

    init?(der: Data) {
        guard let certificate = try? Certificate(derEncoded: Array(der)) else { return nil }
        self.der = der
        self.certificate = certificate
    }

    /// The subject's values for an attribute type, by its dotted OID.
    private func subjectValues(_ oid: String) -> [String] {
        certificate.subject.flatMap { rdn in
            rdn.filter { String(describing: $0.type) == oid }.map { String(describing: $0.value) }
        }
    }

    var commonName: String? { subjectValues("2.5.4.3").first }

    /// The common name, else an email address, else the organizational
    /// unit or organization, as SecCertificateCopySubjectSummary chooses.
    var summary: String? {
        commonName ?? emails.first ?? subjectValues("2.5.4.11").first ?? subjectValues("2.5.4.10").first
    }

    /// The subject's emailAddress attributes, then the alternative names'.
    var emails: [String] {
        var emails = subjectValues("1.2.840.113549.1.9.1")
        if let names = try? certificate.extensions.subjectAlternativeNames {
            for case .rfc822Name(let email) in names where !emails.contains(email) { emails.append(email) }
        }
        return emails
    }

    var serial: Data { Data(certificate.serialNumber.bytes) }

    var key: KeyState? {
        if let key = P256.Signing.PublicKey(certificate.publicKey) { return try? KeyState.make(
            type: ItemKeys.kSecAttrKeyTypeECSECPrimeRandom, isPrivate: false, data: key.x963Representation) }
        if let key = P384.Signing.PublicKey(certificate.publicKey) { return try? KeyState.make(
            type: ItemKeys.kSecAttrKeyTypeECSECPrimeRandom, isPrivate: false, data: key.x963Representation) }
        if let key = P521.Signing.PublicKey(certificate.publicKey) { return try? KeyState.make(
            type: ItemKeys.kSecAttrKeyTypeECSECPrimeRandom, isPrivate: false, data: key.x963Representation) }
        if let key = _RSA.Signing.PublicKey(certificate.publicKey) { return try? KeyState.make(
            type: ItemKeys.kSecAttrKeyTypeRSA, isPrivate: false, data: key.pkcs1DERRepresentation) }
        return nil
    }

    func isValid(at date: Date) -> Bool { certificate.notValidBefore <= date && date <= certificate.notValidAfter }
}

@ObjCClass("__SecCertificate")
final class SecCertificateObject: NSObject {
    static let states = StateTable<CertificateState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecCertificateObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecCertificateObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.certificate }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = SecCertificateObject.states[other?.objcObject] else { return false }
        return SecCertificateObject.states[objcObject]?.der == other.der
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: SecCertificateObject.states[objcObject]?.der.hashValue ?? 0) }

    @ObjCMethod("description")
    func description() -> String { "<cert(\(objcObject)) s: \(SecCertificateObject.states[objcObject]?.summary ?? "")>" }
}

enum Certificates {
    static func state(_ object: UnsafeMutableRawPointer?) -> CertificateState? { SecCertificateObject.states[object] }

    static func object(_ state: CertificateState) -> UnsafeMutableRawPointer {
        let object = SecCertificateObject.objCClass.ownedInstance()
        SecCertificateObject.states.set(object, state)
        return object
    }

    /// One certificate or an array of them.
    static func list(_ object: UnsafeMutableRawPointer?) -> [UnsafeMutableRawPointer] {
        guard let object else { return [] }
        if state(object) != nil { return [object] }
        let wrapped = NSObject(object)
        guard wrapped.isArray else { return [] }
        return NSArray(object).elements.map(\.objcObject).filter { state($0) != nil }
    }
}

@c(_SecCertificateGetTypeID) public func SecCertificateGetTypeID() -> UInt { TypeIDs.certificate }

@c(_SecCertificateCreateWithData)
public func SecCertificateCreateWithData(_ allocator: UnsafeRawPointer?, _ data: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let bytes = Keys.data(data), let state = CertificateState(der: bytes) else { return nil }
    return Certificates.object(state)
}

@c(_SecCertificateCopyData)
public func SecCertificateCopyData(_ certificate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Certificates.state(certificate).flatMap { Keys.returned($0.der) }
}

@c(_SecCertificateCopySubjectSummary)
public func SecCertificateCopySubjectSummary(_ certificate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Certificates.state(certificate)?.summary.flatMap { ObjCRuntime.retain(NSObject.string($0).objcObject) }
}

@c(_SecCertificateCopyCommonName)
public func SecCertificateCopyCommonName(_ certificate: UnsafeMutableRawPointer?,
                                         _ name: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let state = Certificates.state(certificate) else { return Status.param }
    name?.pointee = state.commonName.flatMap { ObjCRuntime.retain(NSObject.string($0).objcObject) }
    return 0
}

@c(_SecCertificateCopyEmailAddresses)
public func SecCertificateCopyEmailAddresses(_ certificate: UnsafeMutableRawPointer?,
                                             _ emails: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let state = Certificates.state(certificate) else { return Status.param }
    emails?.pointee = ObjCRuntime.retain(NSMutableArray.of(state.emails.map(NSObject.string)).objcObject)
    return 0
}

@c(_SecCertificateCopySerialNumberData)
public func SecCertificateCopySerialNumberData(_ certificate: UnsafeMutableRawPointer?,
                                               _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let state = Certificates.state(certificate) else {
        Status.report(error, Status.param)
        return nil
    }
    return Keys.returned(state.serial)
}

@c(_SecCertificateCopyKey)
public func SecCertificateCopyKey(_ certificate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Certificates.state(certificate)?.key.map(Keys.object)
}

@c(_SecCertificateCopyPublicKey)
public func SecCertificateCopyPublicKey(_ certificate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    SecCertificateCopyKey(certificate)
}

// MARK: - Policies

final class PolicyState {
    let oid: String
    let ssl: Bool
    let server: Bool
    let hostname: String?

    init(oid: String, ssl: Bool, server: Bool, hostname: String?) {
        self.oid = oid
        self.ssl = ssl
        self.server = server
        self.hostname = hostname
    }
}

@ObjCClass("__SecPolicy")
final class SecPolicyObject: NSObject {
    static let states = StateTable<PolicyState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecPolicyObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecPolicyObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.policy }
}

enum Policies {
    static func object(_ state: PolicyState) -> UnsafeMutableRawPointer {
        let object = SecPolicyObject.objCClass.ownedInstance()
        SecPolicyObject.states.set(object, state)
        return object
    }

    static func list(_ object: UnsafeMutableRawPointer?) -> [PolicyState] {
        guard let object else { return [] }
        if let state = SecPolicyObject.states[object] { return [state] }
        guard NSObject(object).isArray else { return [] }
        return NSArray(object).elements.compactMap { SecPolicyObject.states[$0.objcObject] }
    }
}

@c(_SecPolicyGetTypeID) public func SecPolicyGetTypeID() -> UInt { TypeIDs.policy }

@c(_SecPolicyCreateSSL)
public func SecPolicyCreateSSL(_ server: Bool, _ hostname: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Policies.object(PolicyState(oid: ItemKeys.kSecPolicyAppleSSL, ssl: true, server: server,
                                hostname: hostname.map { String(objCArgument: $0) }))
}

@c(_SecPolicyCreateBasicX509)
public func SecPolicyCreateBasicX509() -> UnsafeMutableRawPointer? {
    Policies.object(PolicyState(oid: ItemKeys.kSecPolicyAppleX509Basic, ssl: false, server: false, hostname: nil))
}

@c(_SecPolicyCreateRevocation)
public func SecPolicyCreateRevocation(_ flags: UInt) -> UnsafeMutableRawPointer? {
    Policies.object(PolicyState(oid: ItemKeys.kSecPolicyAppleRevocation, ssl: false, server: false, hostname: nil))
}

@c(_SecPolicyCreateWithProperties)
public func SecPolicyCreateWithProperties(_ identifier: UnsafeMutableRawPointer?,
                                          _ properties: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let oid = identifier.map { String(objCArgument: $0) } ?? ItemKeys.kSecPolicyAppleX509Basic
    let dictionary = properties.map { NSDictionary($0) }
    let name = dictionary?.object(ItemKeys.kSecPolicyName).flatMap { $0.isString ? $0.stringValue : nil }
    let client = dictionary?.object(ItemKeys.kSecPolicyClient)?.truth ?? false
    return Policies.object(PolicyState(oid: oid, ssl: oid == ItemKeys.kSecPolicyAppleSSL, server: !client, hostname: name))
}

@c(_SecPolicyCopyProperties)
public func SecPolicyCopyProperties(_ policy: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = SecPolicyObject.states[policy] else { return nil }
    var entries: [(String, NSObject)] = [(ItemKeys.kSecPolicyOid, NSObject.string(state.oid))]
    if let hostname = state.hostname { entries.append((ItemKeys.kSecPolicyName, NSObject.string(hostname))) }
    if state.ssl && !state.server { entries.append((ItemKeys.kSecPolicyClient, NSNumber.make(bool: true))) }
    return ObjCRuntime.retain(NSMutableDictionary.of(entries).objcObject)
}

// MARK: - Trust

final class TrustState {
    var certificates: [UnsafeMutableRawPointer]
    var policies: [PolicyState]
    var anchors: [UnsafeMutableRawPointer]?
    var anchorsOnly = false
    var verifyDate: Date?
    /// After evaluation: SecTrustResultType, the failure and the chain.
    var result: UInt32 = 0
    var status: Int32 = 0
    var chain: [UnsafeMutableRawPointer] = []

    init(certificates: [UnsafeMutableRawPointer], policies: [PolicyState]) {
        self.certificates = certificates
        self.policies = policies
        certificates.forEach { _ = ObjCRuntime.retain($0) }
    }

    deinit {
        (certificates + (anchors ?? []) + chain).forEach { ObjCRuntime.release($0) }
    }

    func setAnchors(_ list: [UnsafeMutableRawPointer]?) {
        list?.forEach { _ = ObjCRuntime.retain($0) }
        anchors?.forEach { ObjCRuntime.release($0) }
        anchors = list
    }

    func setChain(_ list: [UnsafeMutableRawPointer]) {
        list.forEach { _ = ObjCRuntime.retain($0) }
        chain.forEach { ObjCRuntime.release($0) }
        chain = list
    }

    /// Evaluates once per change; the result stays until then.
    func evaluate() {
        let date = verifyDate ?? Date()
        let leaves = certificates.compactMap(Certificates.state)
        let anchorStates = (anchors ?? []).compactMap(Certificates.state)
        // Custom anchors replace the system's roots unless anchors-only is
        // turned back off; anchors-only without any trusts nothing.
        let useSystem = !anchorsOnly
        let ssl = policies.first { $0.ssl }
        let outcome = TrustEvaluation.run(leaves: leaves, anchors: anchorStates, useSystem: useSystem, date: date,
                                          hostname: ssl?.server == true ? ssl?.hostname : nil)
        status = outcome.status
        result = outcome.status == 0 ? 4 : 5   // unspecified, recoverable trust failure
        let all = certificates + (anchors ?? [])
        let built = outcome.chain.compactMap { der in all.first { Certificates.state($0)?.der == der } }
        setChain(built.isEmpty ? certificates : built)
    }
}

final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

enum TrustEvaluation {
    /// Runs swift-certificates' async verifier to completion.
    static func wait<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let done = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
        sem_init(done, 0, 0)
        defer {
            sem_destroy(done)
            done.deallocate()
        }
        nonisolated(unsafe) let signal = done
        Task.detached {
            box.value = await body()
            sem_post(signal)
        }
        while sem_wait(done) != 0 {}
        return box.value!
    }

    static func verify(_ leaves: [Certificate], anchors: [Certificate], useSystem: Bool, date: Date,
                       hostname: String?) -> [Certificate]? {
        guard let leaf = leaves.first else { return nil }
        let intermediates = Array(leaves.dropFirst())
        return wait {
            let roots = useSystem ? CertificateStore.systemTrustRoots.appending(contentsOf: anchors) : CertificateStore(anchors)
            var verifier = Verifier(rootCertificates: roots) {
                RFC5280Policy(validationTime: date)
                if let hostname { ServerIdentityPolicy(serverHostname: hostname, serverIP: nil) }
            }
            let result = await verifier.validate(leafCertificate: leaf, intermediates: CertificateStore(intermediates))
            if case .validCertificate(let chain) = result { return chain }
            return nil
        }
    }

    static func run(leaves: [CertificateState], anchors: [CertificateState], useSystem: Bool, date: Date,
                    hostname: String?) -> (status: Int32, chain: [Data]) {
        let certificates = leaves.map(\.certificate), roots = anchors.map(\.certificate)
        if let chain = verify(certificates, anchors: roots, useSystem: useSystem, date: date, hostname: hostname) {
            let ders = chain.map { built in (leaves + anchors).first { $0.certificate == built }?.der ?? Data() }
            return (0, ders)
        }
        if hostname != nil, verify(certificates, anchors: roots, useSystem: useSystem, date: date, hostname: nil) != nil {
            return (Status.hostNameMismatch, [])
        }
        if let outside = leaves.first(where: { !$0.isValid(at: date) }) {
            return (date > outside.certificate.notValidAfter ? Status.certificateExpired : Status.certificateNotValidYet, [])
        }
        return (Status.notTrusted, [])
    }
}

@ObjCClass("__SecTrust")
final class SecTrustObject: NSObject {
    static let states = StateTable<TrustState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecTrustObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecTrustObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.trust }
}

private func trust(_ object: UnsafeMutableRawPointer?) -> TrustState? { SecTrustObject.states[object] }

@c(_SecTrustGetTypeID) public func SecTrustGetTypeID() -> UInt { TypeIDs.trust }

@c(_SecTrustCreateWithCertificates)
public func SecTrustCreateWithCertificates(_ certificates: UnsafeMutableRawPointer?, _ policies: UnsafeMutableRawPointer?,
                                           _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    let list = Certificates.list(certificates)
    guard !list.isEmpty, let out else { return Status.param }
    let policyList = Policies.list(policies)
    let object = SecTrustObject.objCClass.ownedInstance()
    SecTrustObject.states.set(object, TrustState(certificates: list, policies: policyList.isEmpty
        ? [PolicyState(oid: ItemKeys.kSecPolicyAppleX509Basic, ssl: false, server: false, hostname: nil)] : policyList))
    out.pointee = object
    return 0
}

@c(_SecTrustSetAnchorCertificates)
public func SecTrustSetAnchorCertificates(_ object: UnsafeMutableRawPointer?, _ anchors: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    state.setAnchors(anchors.map { Certificates.list($0) })
    if anchors != nil { state.anchorsOnly = true }
    state.result = 0
    return 0
}

/// Only false lets the system's roots back in beside custom anchors.
@c(_SecTrustSetAnchorCertificatesOnly)
public func SecTrustSetAnchorCertificatesOnly(_ object: UnsafeMutableRawPointer?, _ only: Bool) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    state.anchorsOnly = only
    state.result = 0
    return 0
}

@c(_SecTrustCopyCustomAnchorCertificates)
public func SecTrustCopyCustomAnchorCertificates(_ object: UnsafeMutableRawPointer?,
                                                 _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    out?.pointee = state.anchors.map { ObjCRuntime.retain(NSMutableArray.of($0.map(NSObject.init)).objcObject)! }
    return 0
}

@c(_SecTrustSetVerifyDate)
public func SecTrustSetVerifyDate(_ object: UnsafeMutableRawPointer?, _ date: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = trust(object), let date else { return Status.param }
    state.verifyDate = NSDate(date).date
    state.result = 0
    return 0
}

@c(_SecTrustGetVerifyTime)
public func SecTrustGetVerifyTime(_ object: UnsafeMutableRawPointer?) -> Double {
    (trust(object)?.verifyDate ?? Date()).timeIntervalSinceReferenceDate
}

@c(_SecTrustSetPolicies)
public func SecTrustSetPolicies(_ object: UnsafeMutableRawPointer?, _ policies: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    state.policies = Policies.list(policies)
    state.result = 0
    return 0
}

@c(_SecTrustCopyPolicies)
public func SecTrustCopyPolicies(_ object: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    out?.pointee = ObjCRuntime.retain(NSMutableArray.of(state.policies.map {
        NSObject(objCOwned: Policies.object($0))
    }).objcObject)
    return 0
}

@c(_SecTrustSetNetworkFetchAllowed)
public func SecTrustSetNetworkFetchAllowed(_ object: UnsafeMutableRawPointer?, _ allowed: Bool) -> Int32 { 0 }

@c(_SecTrustSetOCSPResponse)
public func SecTrustSetOCSPResponse(_ object: UnsafeMutableRawPointer?, _ response: UnsafeMutableRawPointer?) -> Int32 { 0 }

private func evaluated(_ state: TrustState) -> TrustState {
    if state.result == 0 { state.evaluate() }
    return state
}

@c(_SecTrustEvaluateWithError)
public func SecTrustEvaluateWithError(_ object: UnsafeMutableRawPointer?,
                                      _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    guard let state = trust(object) else {
        Status.report(error, Status.param)
        return false
    }
    let result = evaluated(state)
    if result.status != 0 { Status.report(error, result.status) }
    return result.status == 0
}

@c(_SecTrustEvaluate)
public func SecTrustEvaluate(_ object: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<UInt32>?) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    result?.pointee = evaluated(state).result
    return 0
}

@c(_SecTrustGetTrustResult)
public func SecTrustGetTrustResult(_ object: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<UInt32>?) -> Int32 {
    guard let state = trust(object) else { return Status.param }
    result?.pointee = state.result
    return 0
}

/// Evaluates, then calls the block on `queue` with the trust, the result
/// and any error: void (^)(SecTrustRef, bool, CFErrorRef).
@c(_SecTrustEvaluateAsyncWithError)
public func SecTrustEvaluateAsyncWithError(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?,
                                           _ block: UnsafeMutableRawPointer?) -> Int32 {
    guard let object, let block, let async = Dispatch.async else { return Status.param }
    _ = ObjCRuntime.retain(object)
    let copy = ObjCRuntime.functions.retainBlock(block)
    let context = UnsafeMutablePointer<(UnsafeMutableRawPointer, UnsafeMutableRawPointer?)>.allocate(capacity: 1)
    context.initialize(to: (object, copy))
    async(queue, UnsafeMutableRawPointer(context), { pointer in
        guard let pointer else { return }
        let (trust, block) = pointer.assumingMemoryBound(to: (UnsafeMutableRawPointer, UnsafeMutableRawPointer?).self).move()
        pointer.deallocate()
        var error: UnsafeMutableRawPointer?
        let trusted = SecTrustEvaluateWithError(trust, &error)
        if let block {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Bool, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(block.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Invoke.self)(block, trust, trusted, error)
            ObjCRuntime.release(block)
        }
        ObjCRuntime.release(error)
        ObjCRuntime.release(trust)
    })
    return 0
}

@c(_SecTrustGetCertificateCount)
public func SecTrustGetCertificateCount(_ object: UnsafeMutableRawPointer?) -> Int {
    guard let state = trust(object) else { return 0 }
    return state.result == 0 ? state.certificates.count : state.chain.count
}

@c(_SecTrustGetCertificateAtIndex)
public func SecTrustGetCertificateAtIndex(_ object: UnsafeMutableRawPointer?, _ index: Int) -> UnsafeMutableRawPointer? {
    guard let state = trust(object) else { return nil }
    let list = state.result == 0 ? state.certificates : state.chain
    return index >= 0 && index < list.count ? list[index] : nil
}

@c(_SecTrustCopyCertificateChain)
public func SecTrustCopyCertificateChain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = trust(object) else { return nil }
    let list = evaluated(state).chain
    return ObjCRuntime.retain(NSMutableArray.of(list.map(NSObject.init)).objcObject)
}

@c(_SecTrustCopyKey)
public func SecTrustCopyKey(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = trust(object), let leaf = state.certificates.first else { return nil }
    return SecCertificateCopyKey(leaf)
}

@c(_SecTrustCopyPublicKey)
public func SecTrustCopyPublicKey(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    SecTrustCopyKey(object)
}

@c(_SecTrustCopyResult)
public func SecTrustCopyResult(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = trust(object) else { return nil }
    let result = evaluated(state)
    return ObjCRuntime.retain(NSMutableDictionary.of([
        (ItemKeys.kSecTrustResultValue, NSNumber.make(int64: Int64(result.result))),
        (ItemKeys.kSecTrustEvaluationDate, NSDate.of(state.verifyDate ?? Date())),
    ]).objcObject)
}

/// Exceptions: an opaque token that, set back, accepts this chain.
@c(_SecTrustCopyExceptions)
public func SecTrustCopyExceptions(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = trust(object), let leaf = state.certificates.first.flatMap(Certificates.state) else { return nil }
    return Keys.returned((try? HashKind.sha256.hash(leaf.der)) ?? Data())
}

@c(_SecTrustSetExceptions)
public func SecTrustSetExceptions(_ object: UnsafeMutableRawPointer?, _ exceptions: UnsafeMutableRawPointer?) -> Bool {
    guard let state = trust(object), let leaf = state.certificates.first.flatMap(Certificates.state),
          let token = Keys.data(exceptions), token == (try? HashKind.sha256.hash(leaf.der)) else { return false }
    state.status = 0
    state.result = 1   // proceed
    return true
}

// MARK: - The system's anchors

/// The system's trusted roots: the distribution's CA bundle, as Darwin's
/// keychain of anchors. Read once.
enum SystemAnchors {
    static let bundles = ["/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem"]

    static let certificates: [Data] = {
        for path in bundles {
            guard let file = fopen(path, "r") else { continue }
            defer { fclose(file) }
            var text = ""
            var line = [CChar](repeating: 0, count: 4096)
            while fgets(&line, Int32(line.count), file) != nil { text += String(cString: line) }
            return ders(pem: text)
        }
        return []
    }()

    /// The DER of each certificate in a PEM file.
    static func ders(pem: String) -> [Data] {
        var result: [Data] = [], body: String?
        for line in pem.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("-----BEGIN CERTIFICATE-----") { body = "" }
            else if line.hasPrefix("-----END CERTIFICATE-----") {
                if let text = body, let der = Data(base64Encoded: text) { result.append(der) }
                body = nil
            } else if body != nil { body! += line.trimmingCharacters(in: .whitespaces) }
        }
        return result
    }
}

/// The anchors a trust uses when none are set: the system's roots.
@c(_SecTrustCopyAnchorCertificates)
public func SecTrustCopyAnchorCertificates(_ anchors: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let anchors else { return Status.param }
    let objects = SystemAnchors.certificates.compactMap { CertificateState(der: $0) }.map(Certificates.object)
    anchors.pointee = ObjCRuntime.retain(NSMutableArray.of(objects.map(NSObject.init)).objcObject)
    objects.forEach { ObjCRuntime.release($0) }
    return 0
}
