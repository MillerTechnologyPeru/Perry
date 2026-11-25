import CPerrySecurity
import FoundationEssentials
import PerryObjCInterop

// Ways Mac programs loosen a trust's or a Secure Transport connection's
// checks. SecTrustSetOptions keeps the trust's SecTrustOptionFlags; with
// kSecTrustOptionAllowExpired a chain that fails is checked again at a
// time when every certificate the trust was made with is valid, so an
// expired or not yet valid one passes, as Darwin's evaluation lets it. The
// other flags change nothing here: there is no network fetching or
// revocation checking to turn on, and implicit anchors and trust settings
// are the system's roots already. SSLSetEnableCertVerify,
// SSLSetAllowsExpiredCerts and SSLSetAllowsAnyRoot are kept by the TLS
// engine (tls.c), which applies them when the handshake checks the chain.

enum TrustOptions {
    /// kSecTrustOptionAllowExpired.
    static let allowExpired: UInt32 = 0x1

    /// A failed evaluation again, at the time nearest the verify date when
    /// every certificate given is valid; nil when there is no such time or
    /// the chain still fails.
    static func runAllowingExpired(leaves: [CertificateState], anchors: [CertificateState], useSystem: Bool, date: Date,
                                   hostname: String?) -> (status: Int32, chain: [Data])? {
        guard let start = leaves.map(\.certificate.notValidBefore).max(), let end = leaves.map(\.certificate.notValidAfter).min(),
              start <= end else { return nil }
        let time = min(max(date, start), end)
        guard time != date else { return nil }
        let outcome = TrustEvaluation.run(leaves: leaves, anchors: anchors, useSystem: useSystem, date: time, hostname: hostname)
        return outcome.status == 0 ? outcome : nil
    }
}

/// OSStatus SecTrustSetOptions(SecTrustRef, SecTrustOptionFlags).
@c(_SecTrustSetOptions)
public func SecTrustSetOptions(_ object: UnsafeMutableRawPointer?, _ options: UInt32) -> Int32 {
    guard let state = SecTrustObject.states[object] else { return Status.param }
    state.options = options
    state.result = 0
    return 0
}

// MARK: - Secure Transport's chain checks

private func verifyOption(_ object: UnsafeMutableRawPointer?, _ option: Int32, _ value: Bool) -> Int32 {
    guard let state = SSLContextObject.states[object] else { return Status.param }
    return perry_tls_set_verify_option(state.tls, option, value ? 1 : 0)
}

private func verifyOption(_ object: UnsafeMutableRawPointer?, _ option: Int32, _ value: UnsafeMutablePointer<UInt8>?) -> Int32 {
    guard let state = SSLContextObject.states[object], let value else { return Status.param }
    value.pointee = perry_tls_verify_option(state.tls, option) != 0 ? 1 : 0
    return 0
}

/// Turned off, the server's chain isn't checked at all: the program checks
/// it itself after the handshake.
@c(_SSLSetEnableCertVerify)
public func SSLSetEnableCertVerify(_ object: UnsafeMutableRawPointer?, _ enable: UInt8) -> Int32 {
    verifyOption(object, Int32(PERRY_TLS_VERIFY), enable != 0)
}

@c(_SSLGetEnableCertVerify)
public func SSLGetEnableCertVerify(_ object: UnsafeMutableRawPointer?, _ enable: UnsafeMutablePointer<UInt8>?) -> Int32 {
    verifyOption(object, Int32(PERRY_TLS_VERIFY), enable)
}

/// Expired and not yet valid certificates pass.
@c(_SSLSetAllowsExpiredCerts)
public func SSLSetAllowsExpiredCerts(_ object: UnsafeMutableRawPointer?, _ allows: UInt8) -> Int32 {
    verifyOption(object, Int32(PERRY_TLS_ALLOW_EXPIRED), allows != 0)
}

@c(_SSLGetAllowsExpiredCerts)
public func SSLGetAllowsExpiredCerts(_ object: UnsafeMutableRawPointer?, _ allows: UnsafeMutablePointer<UInt8>?) -> Int32 {
    verifyOption(object, Int32(PERRY_TLS_ALLOW_EXPIRED), allows)
}

/// A chain that ends at a root the system doesn't trust, or at none, passes.
@c(_SSLSetAllowsAnyRoot)
public func SSLSetAllowsAnyRoot(_ object: UnsafeMutableRawPointer?, _ allows: UInt8) -> Int32 {
    verifyOption(object, Int32(PERRY_TLS_ALLOW_ANY_ROOT), allows != 0)
}

@c(_SSLGetAllowsAnyRoot)
public func SSLGetAllowsAnyRoot(_ object: UnsafeMutableRawPointer?, _ allows: UnsafeMutablePointer<UInt8>?) -> Int32 {
    verifyOption(object, Int32(PERRY_TLS_ALLOW_ANY_ROOT), allows)
}
