import CPerrySecurity
import FoundationEssentials
import Glibc
import PerryObjCInterop

// Network's TLS settings and results: sec_protocol_options_t,
// sec_protocol_metadata_t, and the sec_identity_t, sec_trust_t and
// sec_certificate_t objects they carry. Network's provider (libPerryNetwork)
// runs TLS with Secure Transport's SSLContext and calls the perry_ functions
// at the end of this file to apply the options to a context, to run the
// program's verify block, and to read what the handshake agreed on.

/// tls_protocol_version_t to SSLProtocol, and back.
private func sslProtocol(_ version: UInt16) -> Int32? {
    switch version {
    case 0x0301: return 4
    case 0x0302: return 7
    case 0x0303: return 8
    case 0x0304: return 10
    default: return nil
    }
}

private func tlsVersion(_ sslProtocol: Int32) -> UInt16 {
    switch sslProtocol {
    case 4: return 0x0301
    case 7: return 0x0302
    case 8: return 0x0303
    case 10: return 0x0304
    default: return 0
    }
}

final class SecProtocolOptionsState: @unchecked Sendable {
    var minimumVersion: UInt16 = 0
    var maximumVersion: UInt16 = 0
    var applicationProtocols: [String] = []
    var ciphersuites: [UInt16] = []
    var ciphersuiteGroups: [UInt16] = []
    /// The SecIdentity (+1) a server, or a client asked for one, presents.
    var identity: UnsafeMutableRawPointer?
    var serverName: String?
    var peerAuthenticationRequired = true
    var peerAuthenticationOptional = false
    var ticketsEnabled = true
    var resumptionEnabled = true
    var falseStartEnabled = false
    var verifyBlock: ObjCBlock?
    var verifyQueue: UnsafeMutableRawPointer?
    var challengeBlock: ObjCBlock?
    var challengeQueue: UnsafeMutableRawPointer?

    deinit {
        ObjCRuntime.release(identity)
        ObjCRuntime.release(verifyQueue)
        ObjCRuntime.release(challengeQueue)
    }
}

@ObjCClass("OS_sec_object")
open class SecObject: NSObject {}

@ObjCClass("OS_sec_protocol_options")
final class SecProtocolOptionsObject: SecObject {
    static let states = StateTable<SecProtocolOptionsState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecProtocolOptionsObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecProtocolOptionsObject.objCClass.pointer)
    }
}

final class SecProtocolMetadataState: @unchecked Sendable {
    var negotiatedProtocol: UnsafeMutablePointer<CChar>?
    var version: UInt16 = 0
    var ciphersuite: UInt16 = 0
    var serverName: UnsafeMutablePointer<CChar>?
    var peerCertificates: [Data] = []

    deinit {
        free(negotiatedProtocol)
        free(serverName)
    }
}

@ObjCClass("OS_sec_protocol_metadata")
final class SecProtocolMetadataObject: SecObject {
    static let states = StateTable<SecProtocolMetadataState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecProtocolMetadataObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecProtocolMetadataObject.objCClass.pointer)
    }
}

/// sec_identity_t, sec_trust_t and sec_certificate_t: each holds the
/// Security object it was made from (+1).
final class SecWrapperState: @unchecked Sendable {
    let reference: UnsafeMutableRawPointer
    let certificates: UnsafeMutableRawPointer?

    init(_ reference: UnsafeMutableRawPointer, certificates: UnsafeMutableRawPointer? = nil) {
        self.reference = ObjCRuntime.retain(reference)!
        self.certificates = ObjCRuntime.retain(certificates)
    }

    deinit {
        ObjCRuntime.release(reference)
        ObjCRuntime.release(certificates)
    }
}

@ObjCClass("OS_sec_identity")
final class SecIdentityWrapperObject: SecObject {
    static let states = StateTable<SecWrapperState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecIdentityWrapperObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecIdentityWrapperObject.objCClass.pointer)
    }
}

@ObjCClass("OS_sec_trust")
final class SecTrustWrapperObject: SecObject {
    static let states = StateTable<SecWrapperState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecTrustWrapperObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecTrustWrapperObject.objCClass.pointer)
    }
}

@ObjCClass("OS_sec_certificate")
final class SecCertificateWrapperObject: SecObject {
    static let states = StateTable<SecWrapperState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SecCertificateWrapperObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SecCertificateWrapperObject.objCClass.pointer)
    }
}

private func options(_ object: UnsafeMutableRawPointer?) -> SecProtocolOptionsState? { SecProtocolOptionsObject.states[object] }
private func metadata(_ object: UnsafeMutableRawPointer?) -> SecProtocolMetadataState? { SecProtocolMetadataObject.states[object] }

@c(_sec_retain)
public func sec_retain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(object) }

@c(_sec_release)
public func sec_release(_ object: UnsafeMutableRawPointer?) {
    if let object { ObjCRuntime.release(object) }
}

// MARK: - Wrappers

@c(_sec_identity_create)
public func sec_identity_create(_ identity: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let identity, Identities.state(identity) != nil else { return nil }
    let object = SecIdentityWrapperObject.objCClass.ownedInstance()
    SecIdentityWrapperObject.states.set(object, SecWrapperState(identity))
    return object
}

@c(_sec_identity_create_with_certificates)
public func sec_identity_create_with_certificates(_ identity: UnsafeMutableRawPointer?, _ certificates: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let identity, Identities.state(identity) != nil else { return nil }
    let object = SecIdentityWrapperObject.objCClass.ownedInstance()
    SecIdentityWrapperObject.states.set(object, SecWrapperState(identity, certificates: certificates))
    return object
}

@c(_sec_identity_copy_ref)
public func sec_identity_copy_ref(_ identity: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(SecIdentityWrapperObject.states[identity]?.reference)
}

@c(_sec_identity_copy_certificates_ref)
public func sec_identity_copy_certificates_ref(_ identity: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(SecIdentityWrapperObject.states[identity]?.certificates)
}

@c(_sec_trust_create)
public func sec_trust_create(_ trust: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let trust else { return nil }
    let object = SecTrustWrapperObject.objCClass.ownedInstance()
    SecTrustWrapperObject.states.set(object, SecWrapperState(trust))
    return object
}

@c(_sec_trust_copy_ref)
public func sec_trust_copy_ref(_ trust: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(SecTrustWrapperObject.states[trust]?.reference)
}

@c(_sec_certificate_create)
public func sec_certificate_create(_ certificate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let certificate, Certificates.state(certificate) != nil else { return nil }
    let object = SecCertificateWrapperObject.objCClass.ownedInstance()
    SecCertificateWrapperObject.states.set(object, SecWrapperState(certificate))
    return object
}

@c(_sec_certificate_copy_ref)
public func sec_certificate_copy_ref(_ certificate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(SecCertificateWrapperObject.states[certificate]?.reference)
}

// MARK: - Options

@c(_sec_protocol_options_get_default_min_tls_protocol_version)
public func sec_protocol_options_get_default_min_tls_protocol_version() -> UInt16 { 0x0301 }

@c(_sec_protocol_options_get_default_max_tls_protocol_version)
public func sec_protocol_options_get_default_max_tls_protocol_version() -> UInt16 { 0x0304 }

@c(_sec_protocol_options_get_default_min_dtls_protocol_version)
public func sec_protocol_options_get_default_min_dtls_protocol_version() -> UInt16 { 0xFEFF }

@c(_sec_protocol_options_get_default_max_dtls_protocol_version)
public func sec_protocol_options_get_default_max_dtls_protocol_version() -> UInt16 { 0xFEFD }

@c(_sec_protocol_options_set_min_tls_protocol_version)
public func sec_protocol_options_set_min_tls_protocol_version(_ object: UnsafeMutableRawPointer?, _ version: UInt16) {
    options(object)?.minimumVersion = version
}

@c(_sec_protocol_options_set_max_tls_protocol_version)
public func sec_protocol_options_set_max_tls_protocol_version(_ object: UnsafeMutableRawPointer?, _ version: UInt16) {
    options(object)?.maximumVersion = version
}

@c(_sec_protocol_options_get_min_tls_protocol_version)
public func sec_protocol_options_get_min_tls_protocol_version(_ object: UnsafeMutableRawPointer?) -> UInt16 {
    options(object)?.minimumVersion ?? 0
}

@c(_sec_protocol_options_get_max_tls_protocol_version)
public func sec_protocol_options_get_max_tls_protocol_version(_ object: UnsafeMutableRawPointer?) -> UInt16 {
    options(object)?.maximumVersion ?? 0
}

/// The deprecated SSLProtocol forms.
@c(_sec_protocol_options_set_tls_min_version)
public func sec_protocol_options_set_tls_min_version(_ object: UnsafeMutableRawPointer?, _ version: Int32) {
    options(object)?.minimumVersion = tlsVersion(version)
}

@c(_sec_protocol_options_set_tls_max_version)
public func sec_protocol_options_set_tls_max_version(_ object: UnsafeMutableRawPointer?, _ version: Int32) {
    options(object)?.maximumVersion = tlsVersion(version)
}

@c(_sec_protocol_options_add_tls_application_protocol)
public func sec_protocol_options_add_tls_application_protocol(_ object: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) {
    guard let name else { return }
    options(object)?.applicationProtocols.append(String(cString: name))
}

@c(_sec_protocol_options_append_tls_ciphersuite)
public func sec_protocol_options_append_tls_ciphersuite(_ object: UnsafeMutableRawPointer?, _ suite: UInt16) {
    options(object)?.ciphersuites.append(suite)
}

/// The deprecated SSLCipherSuite form: the same numbers.
@c(_sec_protocol_options_add_tls_ciphersuite)
public func sec_protocol_options_add_tls_ciphersuite(_ object: UnsafeMutableRawPointer?, _ suite: UInt16) {
    options(object)?.ciphersuites.append(suite)
}

/// Groups only narrow OpenSSL's defaults on Darwin; here they are kept.
@c(_sec_protocol_options_append_tls_ciphersuite_group)
public func sec_protocol_options_append_tls_ciphersuite_group(_ object: UnsafeMutableRawPointer?, _ group: UInt16) {
    options(object)?.ciphersuiteGroups.append(group)
}

@c(_sec_protocol_options_add_tls_ciphersuite_group)
public func sec_protocol_options_add_tls_ciphersuite_group(_ object: UnsafeMutableRawPointer?, _ group: UInt16) {
    options(object)?.ciphersuiteGroups.append(group)
}

@c(_sec_protocol_options_set_local_identity)
public func sec_protocol_options_set_local_identity(_ object: UnsafeMutableRawPointer?, _ identity: UnsafeMutableRawPointer?) {
    guard let state = options(object) else { return }
    let reference = ObjCRuntime.retain(SecIdentityWrapperObject.states[identity]?.reference)
    ObjCRuntime.release(state.identity)
    state.identity = reference
}

@c(_sec_protocol_options_set_tls_server_name)
public func sec_protocol_options_set_tls_server_name(_ object: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) {
    options(object)?.serverName = name.map { String(cString: $0) }
}

@c(_sec_protocol_options_set_peer_authentication_required)
public func sec_protocol_options_set_peer_authentication_required(_ object: UnsafeMutableRawPointer?, _ required: Bool) {
    options(object)?.peerAuthenticationRequired = required
}

@c(_sec_protocol_options_set_peer_authentication_optional)
public func sec_protocol_options_set_peer_authentication_optional(_ object: UnsafeMutableRawPointer?, _ optional: Bool) {
    options(object)?.peerAuthenticationOptional = optional
}

/// Session tickets and resumption: OpenSSL keeps no sessions between
/// contexts here, so these are kept and every handshake is a full one.
@c(_sec_protocol_options_set_tls_tickets_enabled)
public func sec_protocol_options_set_tls_tickets_enabled(_ object: UnsafeMutableRawPointer?, _ enabled: Bool) {
    options(object)?.ticketsEnabled = enabled
}

@c(_sec_protocol_options_set_tls_resumption_enabled)
public func sec_protocol_options_set_tls_resumption_enabled(_ object: UnsafeMutableRawPointer?, _ enabled: Bool) {
    options(object)?.resumptionEnabled = enabled
}

@c(_sec_protocol_options_set_tls_false_start_enabled)
public func sec_protocol_options_set_tls_false_start_enabled(_ object: UnsafeMutableRawPointer?, _ enabled: Bool) {
    options(object)?.falseStartEnabled = enabled
}

@c(_sec_protocol_options_set_tls_ocsp_enabled)
public func sec_protocol_options_set_tls_ocsp_enabled(_ object: UnsafeMutableRawPointer?, _ enabled: Bool) {}

@c(_sec_protocol_options_set_tls_sct_enabled)
public func sec_protocol_options_set_tls_sct_enabled(_ object: UnsafeMutableRawPointer?, _ enabled: Bool) {}

@c(_sec_protocol_options_set_tls_renegotiation_enabled)
public func sec_protocol_options_set_tls_renegotiation_enabled(_ object: UnsafeMutableRawPointer?, _ enabled: Bool) {}

@c(_sec_protocol_options_set_tls_is_fallback_attempt)
public func sec_protocol_options_set_tls_is_fallback_attempt(_ object: UnsafeMutableRawPointer?, _ fallback: Bool) {}

@c(_sec_protocol_options_set_verify_block)
public func sec_protocol_options_set_verify_block(_ object: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?,
                                                  _ queue: UnsafeMutableRawPointer?) {
    guard let state = options(object) else { return }
    state.verifyBlock = block.map { ObjCBlock(objCArgument: $0) }
    let held = ObjCRuntime.retain(queue)
    ObjCRuntime.release(state.verifyQueue)
    state.verifyQueue = held
}

/// The block that picks a client identity when the server asks for one:
/// kept, though OpenSSL here sends the identity set beforehand.
@c(_sec_protocol_options_set_challenge_block)
public func sec_protocol_options_set_challenge_block(_ object: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?,
                                                     _ queue: UnsafeMutableRawPointer?) {
    guard let state = options(object) else { return }
    state.challengeBlock = block.map { ObjCBlock(objCArgument: $0) }
    let held = ObjCRuntime.retain(queue)
    ObjCRuntime.release(state.challengeQueue)
    state.challengeQueue = held
}

@c(_sec_protocol_options_are_equal)
public func sec_protocol_options_are_equal(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) -> Bool {
    if first == second { return true }
    guard let a = options(first), let b = options(second) else { return false }
    return a.minimumVersion == b.minimumVersion && a.maximumVersion == b.maximumVersion
        && a.applicationProtocols == b.applicationProtocols && a.ciphersuites == b.ciphersuites
        && a.identity == b.identity && a.serverName == b.serverName
        && a.peerAuthenticationRequired == b.peerAuthenticationRequired && a.ticketsEnabled == b.ticketsEnabled
}

// MARK: - Metadata

@c(_sec_protocol_metadata_get_negotiated_protocol)
public func sec_protocol_metadata_get_negotiated_protocol(_ object: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    metadata(object)?.negotiatedProtocol.map { UnsafePointer($0) }
}

@c(_sec_protocol_metadata_get_negotiated_tls_protocol_version)
public func sec_protocol_metadata_get_negotiated_tls_protocol_version(_ object: UnsafeMutableRawPointer?) -> UInt16 {
    metadata(object)?.version ?? 0
}

@c(_sec_protocol_metadata_get_negotiated_protocol_version)
public func sec_protocol_metadata_get_negotiated_protocol_version(_ object: UnsafeMutableRawPointer?) -> Int32 {
    sslProtocol(metadata(object)?.version ?? 0) ?? 0
}

@c(_sec_protocol_metadata_get_negotiated_tls_ciphersuite)
public func sec_protocol_metadata_get_negotiated_tls_ciphersuite(_ object: UnsafeMutableRawPointer?) -> UInt16 {
    metadata(object)?.ciphersuite ?? 0
}

@c(_sec_protocol_metadata_get_negotiated_ciphersuite)
public func sec_protocol_metadata_get_negotiated_ciphersuite(_ object: UnsafeMutableRawPointer?) -> UInt16 {
    metadata(object)?.ciphersuite ?? 0
}

@c(_sec_protocol_metadata_get_server_name)
public func sec_protocol_metadata_get_server_name(_ object: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    metadata(object)?.serverName.map { UnsafePointer($0) }
}

/// Session tickets aren't kept, so early data is never accepted.
@c(_sec_protocol_metadata_get_early_data_accepted)
public func sec_protocol_metadata_get_early_data_accepted(_ object: UnsafeMutableRawPointer?) -> Bool { false }

/// The peer's certificates, leaf first, each as a sec_certificate_t.
@c(_sec_protocol_metadata_access_peer_certificate_chain)
public func sec_protocol_metadata_access_peer_certificate_chain(_ object: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let state = metadata(object), let block else { return false }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
    let invoke = unsafeBitCast(block.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size + 8, as: UnsafeRawPointer.self), to: Invoke.self)
    for der in state.peerCertificates {
        guard let certificate = CertificateState(der: der) else { continue }
        let reference = Certificates.object(certificate)
        let wrapper = sec_certificate_create(reference)
        invoke(block, wrapper)
        ObjCRuntime.release(wrapper)
        ObjCRuntime.release(reference)
    }
    return true
}

@c(_sec_protocol_metadata_peers_are_equal)
public func sec_protocol_metadata_peers_are_equal(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) -> Bool {
    guard let a = metadata(first), let b = metadata(second) else { return false }
    return a.peerCertificates == b.peerCertificates
}

@c(_sec_protocol_metadata_challenge_parameters_are_equal)
public func sec_protocol_metadata_challenge_parameters_are_equal(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) -> Bool {
    metadata(first) != nil && metadata(second) != nil
}

// MARK: - For Network's provider

/// New options (+1) with Darwin's defaults.
@c(_perry_sec_protocol_options_create)
public func perry_sec_protocol_options_create() -> UnsafeMutableRawPointer? {
    let object = SecProtocolOptionsObject.objCClass.ownedInstance()
    SecProtocolOptionsObject.states.set(object, SecProtocolOptionsState())
    return object
}

/// Applies the options to a Secure Transport context before its
/// handshake; `verifies` is set when the handshake should stop for
/// perry_sec_protocol_verify. 0, or the OSStatus of what failed.
@c(_perry_sec_protocol_configure)
public func perry_sec_protocol_configure(_ object: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?, _ isServer: Bool,
                                         _ verifies: UnsafeMutablePointer<Bool>?) -> Int32 {
    verifies?.pointee = false
    guard let context, SSLContextObject.states[context] != nil else { return -50 }
    guard let state = options(object) else { return 0 }
    if let minimum = sslProtocol(state.minimumVersion) {
        let status = SSLSetProtocolVersionMin(context, minimum)
        if status != 0 { return status }
    }
    if let maximum = sslProtocol(state.maximumVersion) {
        let status = SSLSetProtocolVersionMax(context, maximum)
        if status != 0 { return status }
    }
    if !state.applicationProtocols.isEmpty {
        var wire: [UInt8] = []
        for name in state.applicationProtocols {
            let bytes = Array(name.utf8)
            guard !bytes.isEmpty, bytes.count < 256 else { continue }
            wire.append(UInt8(bytes.count))
            wire += bytes
        }
        if let tls = SSLContextObject.states[context]?.tls {
            let status = perry_tls_set_alpn(tls, wire, UInt32(wire.count))
            if status != 0 { return status }
        }
    }
    if !state.ciphersuites.isEmpty {
        let status = state.ciphersuites.withUnsafeBufferPointer { SSLSetEnabledCiphers(context, $0.baseAddress, $0.count) }
        if status != 0 { return status }
    }
    if let identity = state.identity {
        let status = SSLSetCertificate(context, identity)
        if status != 0 { return status }
    }
    if !isServer, let name = state.serverName {
        let status = name.withCString { SSLSetPeerDomainName(context, $0, strlen($0)) }
        if status != 0 { return status }
    }
    // A verify block, or a client that doesn't check its server, takes the
    // check over from Secure Transport.
    if !isServer, state.verifyBlock != nil || !state.peerAuthenticationRequired {
        _ = SSLSetSessionOption(context, 0, true)
        verifies?.pointee = true
    }
    return 0
}

/// Runs the verify block (or, with none, trusts the peer) and calls
/// `callback(info, trusted)` once, from any thread.
@c(_perry_sec_protocol_verify)
public func perry_sec_protocol_verify(_ object: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?,
                                      _ protocolMetadata: UnsafeMutableRawPointer?,
                                      _ callback: (@convention(c) (UnsafeMutableRawPointer?, Bool) -> Void)?,
                                      _ info: UnsafeMutableRawPointer?) {
    guard let callback else { return }
    guard let state = options(object), let verify = state.verifyBlock else {
        callback(info, true)
        return
    }
    var trust: UnsafeMutableRawPointer?
    _ = SSLCopyPeerTrust(context, &trust)
    let wrapper = trust.flatMap { sec_trust_create($0) }
    ObjCRuntime.release(trust)
    let heldMetadata = ObjCRuntime.retain(protocolMetadata)
    let completion = VerifyCompletion.block { trusted in callback(info, trusted) }
    let work = { () -> Void in
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                           UnsafeMutableRawPointer?) -> Void
        verify.function(as: Invoke.self)(verify.object, heldMetadata, wrapper, completion)
        ObjCRuntime.release(completion)
        ObjCRuntime.release(wrapper)
        ObjCRuntime.release(heldMetadata)
    }
    guard let async = Dispatch.async else {
        work()
        return
    }
    let box = Unmanaged.passRetained(VerifyCompletion.Work(work)).toOpaque()
    async(state.verifyQueue ?? Dispatch.mainQueue, box) { pointer in
        guard let pointer else { return }
        Unmanaged<VerifyCompletion.Work>.fromOpaque(pointer).takeRetainedValue().body()
    }
}

/// What the handshake agreed on (+1).
@c(_perry_sec_protocol_metadata_create)
public func perry_sec_protocol_metadata_create(_ context: UnsafeMutableRawPointer?, _ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let context, let tls = SSLContextObject.states[context]?.tls else { return nil }
    let state = SecProtocolMetadataState()
    var selected: UnsafePointer<UInt8>?
    let length = perry_tls_alpn(tls, &selected)
    if let selected, length > 0 {
        state.negotiatedProtocol = strdup(String(decoding: UnsafeBufferPointer(start: selected, count: length), as: UTF8.self))
    }
    state.version = tlsVersion(perry_tls_negotiated_protocol(tls))
    var cipher: UInt16 = 0
    if perry_tls_negotiated_cipher(tls, &cipher) == 0 { state.ciphersuite = cipher }
    if let name = SSLContextObject.states[context]?.peerName ?? options(object)?.serverName { state.serverName = strdup(name) }
    for index in 0..<perry_tls_peer_certificates(tls) {
        let size = perry_tls_peer_certificate(tls, index, nil, 0)
        var der = [UInt8](repeating: 0, count: size)
        if size > 0, perry_tls_peer_certificate(tls, index, &der, size) == size { state.peerCertificates.append(Data(der)) }
    }
    let created = SecProtocolMetadataObject.objCClass.ownedInstance()
    SecProtocolMetadataObject.states.set(created, state)
    return created
}

/// sec_protocol_verify_complete_t blocks, which call back once however
/// often they are called.
enum VerifyCompletion {
    final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    final class Box {
        let body: (Bool) -> Void
        private var called = false
        private let lock = Lock()
        init(_ body: @escaping (Bool) -> Void) { self.body = body }

        func call(_ value: Bool) {
            let first = lock.withLock { () -> Bool in
                defer { called = true }
                return !called
            }
            if first { body(value) }
        }
    }

    private static let word = MemoryLayout<UnsafeRawPointer>.size
    private static let invokeOffset = word + 8
    private static let descriptorOffset = invokeOffset + word
    private static let boxOffset = descriptorOffset + word
    private static let size = boxOffset + word

    private static let copyHelper: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { _, source in
        guard let source else { return }
        _ = Unmanaged<Box>.fromOpaque(source.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).retain()
    }

    private static let disposeHelper: @convention(c) (UnsafeRawPointer?) -> Void = { block in
        guard let block else { return }
        Unmanaged<Box>.fromOpaque(block.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).release()
    }

    private static let invoke: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void = { block, value in
        guard let block else { return }
        Unmanaged<Box>.fromOpaque(block.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).takeUnretainedValue().call(value)
    }

    nonisolated(unsafe) private static let descriptor: UnsafeMutableRawPointer = {
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 4 * word, alignment: word)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(size), toByteOffset: word, as: UInt.self)
        descriptor.storeBytes(of: unsafeBitCast(copyHelper, to: UnsafeRawPointer.self), toByteOffset: 2 * word, as: UnsafeRawPointer.self)
        descriptor.storeBytes(of: unsafeBitCast(disposeHelper, to: UnsafeRawPointer.self), toByteOffset: 3 * word, as: UnsafeRawPointer.self)
        return descriptor
    }()

    /// A heap block (+1) that calls `body`.
    static func block(_ body: @escaping (Bool) -> Void) -> UnsafeMutableRawPointer? {
        guard let mallocBlockClass = Dispatch.mallocBlockClass, let block = malloc(size) else { return nil }
        block.storeBytes(of: mallocBlockClass, as: UnsafeMutableRawPointer.self)
        // BLOCK_NEEDS_FREE | BLOCK_HAS_COPY_DISPOSE, one reference.
        block.storeBytes(of: Int32(1 << 24 | 1 << 25 | 2), toByteOffset: word, as: Int32.self)
        block.storeBytes(of: Int32(0), toByteOffset: word + 4, as: Int32.self)
        block.storeBytes(of: unsafeBitCast(invoke, to: UnsafeRawPointer.self), toByteOffset: invokeOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: descriptorOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(Unmanaged.passRetained(Box(body)).toOpaque()), toByteOffset: boxOffset, as: UnsafeRawPointer.self)
        return block
    }
}
