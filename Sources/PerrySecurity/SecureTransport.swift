import CPerrySecurity
import FoundationEssentials
import Glibc
import PerryObjCInterop

// Secure Transport (SSLContext), Darwin's deprecated TLS API, over the
// system's OpenSSL (CPerrySecurity's tls.c). The program's SSLReadFunc and
// SSLWriteFunc carry the records, as on Darwin. The server's chain is checked
// against the system's roots and the peer domain name once the handshake is
// done, unless the program asked to check it itself
// (kSSLSessionOptionBreakOnServerAuth): then SSLHandshake answers
// errSSLPeerAuthCompleted once, SSLCopyPeerTrust gives the chain, and the
// next SSLHandshake finishes. Without OpenSSL no context can be made, so a
// connection that asks for one fails at once.

private let errSSLInternal: Int32 = -9810
private let paramErr: Int32 = -50
private let unimplemented: Int32 = -4

/// SSLSessionOption.
private let breakOnServerAuth: Int32 = 0

extension TypeIDs {
    static let sslContext: UInt = 0x5345_0007
}

final class SSLContextState {
    let tls: OpaquePointer
    var peerName: String?

    init(tls: OpaquePointer) { self.tls = tls }

    deinit { perry_tls_free(tls) }
}

@ObjCClass("__SSLContext")
final class SSLContextObject: NSObject {
    static let states = StateTable<SSLContextState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SSLContextObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SSLContextObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.sslContext }
}

private func context(_ object: UnsafeMutableRawPointer?) -> SSLContextState? { SSLContextObject.states[object] }

/// A call on a context, or paramErr for one that doesn't exist.
private func with(_ object: UnsafeMutableRawPointer?, _ body: (SSLContextState) -> Int32) -> Int32 {
    guard let state = context(object) else { return paramErr }
    return body(state)
}

nonisolated(unsafe) private var warned = false

@c(_SSLContextGetTypeID) public func SSLContextGetTypeID() -> UInt { TypeIDs.sslContext }

/// side: kSSLServerSide (0) or kSSLClientSide (1).
@c(_SSLCreateContext)
public func SSLCreateContext(_ allocator: UnsafeRawPointer?, _ side: Int32, _ type: Int32) -> UnsafeMutableRawPointer? {
    guard type == 0 /* kSSLStreamType */, let tls = perry_tls_create(side == 0 ? 1 : 0) else {
        if !warned {
            warned = true
            securityWarning(type == 0
                ? "SSLCreateContext: OpenSSL (libssl.so.3) isn't available; TLS connections through Secure Transport fail"
                : "SSLCreateContext: DTLS isn't implemented")
        }
        return nil
    }
    let object = SSLContextObject.objCClass.ownedInstance()
    SSLContextObject.states.set(object, SSLContextState(tls: tls))
    return object
}

@c(_SSLNewContext)
public func SSLNewContext(_ isServer: Bool, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return paramErr }
    out.pointee = SSLCreateContext(nil, isServer ? 0 : 1, 0)
    return out.pointee == nil ? errSSLInternal : 0
}

@c(_SSLDisposeContext)
public func SSLDisposeContext(_ object: UnsafeMutableRawPointer?) -> Int32 {
    guard context(object) != nil else { return paramErr }
    ObjCRuntime.release(object)
    return 0
}

@c(_SSLSetIOFuncs)
public func SSLSetIOFuncs(_ object: UnsafeMutableRawPointer?, _ read: perry_tls_io?, _ write: perry_tls_io?) -> Int32 {
    with(object) { perry_tls_set_io($0.tls, read, write) }
}

@c(_SSLSetConnection)
public func SSLSetConnection(_ object: UnsafeMutableRawPointer?, _ connection: UnsafeRawPointer?) -> Int32 {
    with(object) { perry_tls_set_connection($0.tls, connection) }
}

@c(_SSLGetConnection)
public func SSLGetConnection(_ object: UnsafeMutableRawPointer?, _ connection: UnsafeMutablePointer<UnsafeRawPointer?>?) -> Int32 {
    with(object) {
        connection?.pointee = perry_tls_connection($0.tls)
        return 0
    }
}

@c(_SSLSetPeerDomainName)
public func SSLSetPeerDomainName(_ object: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?, _ length: Int) -> Int32 {
    with(object) { state in
        var peer: String?
        if let name, length > 0 {
            let bytes = UnsafeRawBufferPointer(start: name, count: length)
            // The length may count a terminating NUL.
            peer = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let status = perry_tls_set_peer_name(state.tls, peer)
        if status == 0 { state.peerName = peer }
        return status
    }
}

@c(_SSLGetPeerDomainNameLength)
public func SSLGetPeerDomainNameLength(_ object: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<Int>?) -> Int32 {
    with(object) {
        length?.pointee = $0.peerName?.utf8.count ?? 0
        return 0
    }
}

@c(_SSLGetPeerDomainName)
public func SSLGetPeerDomainName(_ object: UnsafeMutableRawPointer?, _ name: UnsafeMutablePointer<CChar>?,
                                 _ length: UnsafeMutablePointer<Int>?) -> Int32 {
    with(object) { state in
        guard let name, let length else { return paramErr }
        let bytes = Array((state.peerName ?? "").utf8)
        guard bytes.count <= length.pointee else { return paramErr }
        bytes.withUnsafeBytes { UnsafeMutableRawPointer(name).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        length.pointee = bytes.count
        return 0
    }
}

/// A session to resume: OpenSSL's tickets aren't kept between contexts, so
/// each connection has a full handshake, as when Secure Transport's cache
/// has nothing for the ID.
@c(_SSLSetPeerID)
public func SSLSetPeerID(_ object: UnsafeMutableRawPointer?, _ peerID: UnsafeRawPointer?, _ length: Int) -> Int32 {
    with(object) { _ in peerID == nil && length > 0 ? paramErr : 0 }
}

@c(_SSLSetProtocolVersionMin)
public func SSLSetProtocolVersionMin(_ object: UnsafeMutableRawPointer?, _ version: Int32) -> Int32 {
    with(object) { perry_tls_set_version($0.tls, 0, version) }
}

@c(_SSLSetProtocolVersionMax)
public func SSLSetProtocolVersionMax(_ object: UnsafeMutableRawPointer?, _ version: Int32) -> Int32 {
    with(object) { perry_tls_set_version($0.tls, 1, version) }
}

@c(_SSLGetProtocolVersionMin)
public func SSLGetProtocolVersionMin(_ object: UnsafeMutableRawPointer?, _ version: UnsafeMutablePointer<Int32>?) -> Int32 {
    with(object) {
        version?.pointee = perry_tls_version_limit($0.tls, 0)
        return 0
    }
}

@c(_SSLGetProtocolVersionMax)
public func SSLGetProtocolVersionMax(_ object: UnsafeMutableRawPointer?, _ version: UnsafeMutablePointer<Int32>?) -> Int32 {
    with(object) {
        version?.pointee = perry_tls_version_limit($0.tls, 1)
        return 0
    }
}

/// Only kSSLSessionOptionBreakOnServerAuth changes anything; the other
/// options (false start, one-byte records, renegotiation) are OpenSSL's.
@c(_SSLSetSessionOption)
public func SSLSetSessionOption(_ object: UnsafeMutableRawPointer?, _ option: Int32, _ value: Bool) -> Int32 {
    with(object) { option == breakOnServerAuth ? perry_tls_set_break_on_server_auth($0.tls, value ? 1 : 0) : 0 }
}

@c(_SSLGetSessionOption)
public func SSLGetSessionOption(_ object: UnsafeMutableRawPointer?, _ option: Int32, _ value: UnsafeMutablePointer<Bool>?) -> Int32 {
    with(object) {
        value?.pointee = option == breakOnServerAuth && perry_tls_break_on_server_auth($0.tls) != 0
        return 0
    }
}

/// A client certificate isn't sent: a server that requires one ends the
/// handshake.
@c(_SSLSetCertificate)
public func SSLSetCertificate(_ object: UnsafeMutableRawPointer?, _ certificates: UnsafeRawPointer?) -> Int32 {
    with(object) { _ in certificates == nil ? 0 : unimplemented }
}

@c(_SSLSetALPNProtocols)
public func SSLSetALPNProtocols(_ object: UnsafeMutableRawPointer?, _ protocols: UnsafeMutableRawPointer?) -> Int32 {
    with(object) { state in
        guard let protocols, NSObject(protocols).isArray else { return paramErr }
        var wire: [UInt8] = []
        for element in NSArray(protocols).elements where element.isString {
            let name = Array(element.stringValue.utf8)
            guard !name.isEmpty, name.count < 256 else { return paramErr }
            wire.append(UInt8(name.count))
            wire += name
        }
        return perry_tls_set_alpn(state.tls, wire, UInt32(wire.count))
    }
}

@c(_SSLCopyALPNProtocols)
public func SSLCopyALPNProtocols(_ object: UnsafeMutableRawPointer?, _ protocols: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    with(object) { state in
        var selected: UnsafePointer<UInt8>?
        let length = perry_tls_alpn(state.tls, &selected)
        guard let selected, length > 0 else {
            protocols?.pointee = nil
            return 0
        }
        let name = String(decoding: UnsafeBufferPointer(start: selected, count: length), as: UTF8.self)
        protocols?.pointee = ObjCRuntime.retain(NSMutableArray.of([NSObject.string(name)]).objcObject)
        return 0
    }
}

@c(_SSLHandshake)
public func SSLHandshake(_ object: UnsafeMutableRawPointer?) -> Int32 {
    with(object) { perry_tls_handshake($0.tls) }
}

@c(_SSLGetSessionState)
public func SSLGetSessionState(_ object: UnsafeMutableRawPointer?, _ state: UnsafeMutablePointer<Int32>?) -> Int32 {
    with(object) {
        state?.pointee = perry_tls_state($0.tls)
        return 0
    }
}

@c(_SSLRead)
public func SSLRead(_ object: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?, _ length: Int,
                    _ processed: UnsafeMutablePointer<Int>?) -> Int32 {
    processed?.pointee = 0
    return with(object) { state in
        guard let data else { return length == 0 ? 0 : paramErr }
        var count = 0
        let status = perry_tls_read(state.tls, data, length, &count)
        processed?.pointee = count
        return status
    }
}

@c(_SSLWrite)
public func SSLWrite(_ object: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer?, _ length: Int,
                     _ processed: UnsafeMutablePointer<Int>?) -> Int32 {
    processed?.pointee = 0
    return with(object) { state in
        guard data != nil || length == 0 else { return paramErr }
        var count = 0
        let status = perry_tls_write(state.tls, data, length, &count)
        processed?.pointee = count
        return status
    }
}

@c(_SSLGetBufferedReadSize)
public func SSLGetBufferedReadSize(_ object: UnsafeMutableRawPointer?, _ size: UnsafeMutablePointer<Int>?) -> Int32 {
    with(object) {
        size?.pointee = perry_tls_buffered($0.tls)
        return 0
    }
}

@c(_SSLClose)
public func SSLClose(_ object: UnsafeMutableRawPointer?) -> Int32 {
    with(object) { perry_tls_close($0.tls) }
}

/// The server's chain, with an SSL policy for the peer domain name.
@c(_SSLCopyPeerTrust)
public func SSLCopyPeerTrust(_ object: UnsafeMutableRawPointer?, _ trust: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let trust else { return paramErr }
    trust.pointee = nil
    return with(object) { state in
        var certificates: [UnsafeMutableRawPointer] = []
        for index in 0..<perry_tls_peer_certificates(state.tls) {
            let length = perry_tls_peer_certificate(state.tls, index, nil, 0)
            var der = [UInt8](repeating: 0, count: length)
            guard length > 0, perry_tls_peer_certificate(state.tls, index, &der, length) == length,
                  let certificate = CertificateState(der: Data(der)) else { continue }
            certificates.append(Certificates.object(certificate))
        }
        defer { certificates.forEach { ObjCRuntime.release($0) } }
        // No chain yet (before the handshake): no trust, and no error.
        guard !certificates.isEmpty else { return 0 }
        let policy = PolicyState(oid: ItemKeys.kSecPolicyAppleSSL, ssl: true, server: true, hostname: state.peerName)
        let created = SecTrustObject.objCClass.ownedInstance()
        SecTrustObject.states.set(created, TrustState(certificates: certificates, policies: [policy]))
        trust.pointee = created
        return 0
    }
}

@c(_SSLGetNegotiatedCipher)
public func SSLGetNegotiatedCipher(_ object: UnsafeMutableRawPointer?, _ cipher: UnsafeMutablePointer<UInt16>?) -> Int32 {
    with(object) { state in
        guard let cipher else { return paramErr }
        return perry_tls_negotiated_cipher(state.tls, cipher)
    }
}

@c(_SSLGetNegotiatedProtocolVersion)
public func SSLGetNegotiatedProtocolVersion(_ object: UnsafeMutableRawPointer?, _ version: UnsafeMutablePointer<Int32>?) -> Int32 {
    with(object) {
        version?.pointee = perry_tls_negotiated_protocol($0.tls)
        return 0
    }
}

@c(_SSLGetNumberSupportedCiphers)
public func SSLGetNumberSupportedCiphers(_ object: UnsafeMutableRawPointer?, _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    with(object) {
        count?.pointee = perry_tls_ciphers($0.tls, nil, 0)
        return 0
    }
}

@c(_SSLGetSupportedCiphers)
public func SSLGetSupportedCiphers(_ object: UnsafeMutableRawPointer?, _ ciphers: UnsafeMutablePointer<UInt16>?,
                                   _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    with(object) { state in
        guard let ciphers, let count else { return paramErr }
        let total = perry_tls_ciphers(state.tls, ciphers, count.pointee)
        guard total <= count.pointee else { return paramErr }
        count.pointee = total
        return 0
    }
}

@c(_SSLGetNumberEnabledCiphers)
public func SSLGetNumberEnabledCiphers(_ object: UnsafeMutableRawPointer?, _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    SSLGetNumberSupportedCiphers(object, count)
}

@c(_SSLGetEnabledCiphers)
public func SSLGetEnabledCiphers(_ object: UnsafeMutableRawPointer?, _ ciphers: UnsafeMutablePointer<UInt16>?,
                                 _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    SSLGetSupportedCiphers(object, ciphers, count)
}

@c(_SSLSetEnabledCiphers)
public func SSLSetEnabledCiphers(_ object: UnsafeMutableRawPointer?, _ ciphers: UnsafePointer<UInt16>?, _ count: Int) -> Int32 {
    with(object) { state in
        guard let ciphers, count > 0 else { return paramErr }
        return perry_tls_set_ciphers(state.tls, ciphers, count)
    }
}

