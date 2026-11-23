import Glibc
import PerryObjCInterop

// nw_error_t: a domain (POSIX, DNS, TLS) and a code, in Darwin's numbering:
// errno values as Darwin has them, DNSServiceErrorType and OSStatus. The
// socket calls' Linux errno is translated where it is read.

/// nw_error_domain_t.
enum ErrorDomain {
    static let posix: Int32 = 1
    static let dns: Int32 = 2
    static let tls: Int32 = 3
    static let wifiAware: Int32 = 4
}

/// An error, as connections keep it until it is handed out.
struct NetworkError: Equatable {
    let domain: Int32
    let code: Int32

    static func posix(darwin code: Int32) -> NetworkError { NetworkError(domain: ErrorDomain.posix, code: code) }
    static func posix(linux code: Int32) -> NetworkError { .posix(darwin: DarwinErrno.from(linux: code)) }
    static func dns(_ code: Int32) -> NetworkError { NetworkError(domain: ErrorDomain.dns, code: code) }
    static func tls(_ status: Int32) -> NetworkError { NetworkError(domain: ErrorDomain.tls, code: status) }

    /// ECANCELED, as Darwin numbers it.
    static let cancelled = NetworkError.posix(darwin: 89)
    /// EPROTONOSUPPORT.
    static let protocolNotSupported = NetworkError.posix(darwin: 43)
    /// kDNSServiceErr_NoSuchRecord, what a name that doesn't resolve gives.
    static let noSuchRecord = NetworkError.dns(-65554)

    /// A new nw_error_t (+1).
    func object() -> UnsafeMutableRawPointer {
        NWObjects.make(NWErrorObject.objCClass, ErrorState(self))
    }
}

final class ErrorState: NWState {
    let error: NetworkError
    init(_ error: NetworkError) { self.error = error }
}

@ObjCClass("OS_nw_error")
open class NWErrorObject: NWObject {}

@c(_nw_error_get_error_domain)
public func nw_error_get_error_domain(_ error: UnsafeMutableRawPointer?) -> Int32 {
    NWObjects.state(error, ErrorState.self)?.error.domain ?? 0
}

@c(_nw_error_get_error_code)
public func nw_error_get_error_code(_ error: UnsafeMutableRawPointer?) -> Int32 {
    NWObjects.state(error, ErrorState.self)?.error.code ?? 0
}

/// The error as a CFError, in the domain's kNWErrorDomain.
@c(_nw_error_copy_cf_error)
public func nw_error_copy_cf_error(_ error: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = NWObjects.state(error, ErrorState.self),
          let cls = "NSError".withCString({ ObjCRuntime.functions.getClass($0) }) else { return nil }
    let domain: String
    switch state.error.domain {
    case ErrorDomain.dns: domain = ErrorDomains.kNWErrorDomainDNS
    case ErrorDomain.tls: domain = ErrorDomains.kNWErrorDomainTLS
    case ErrorDomain.wifiAware: domain = ErrorDomains.kNWErrorDomainWiFiAware
    default: domain = ErrorDomains.kNWErrorDomainPOSIX
    }
    let made = NSObject(cls).errorWithDomain(domain, code: Int(state.error.code), userInfo: nil)
    return ObjCRuntime.retain(made.objcObject)
}

extension NSObject {
    @ObjCMethod("errorWithDomain:code:userInfo:")
    func errorWithDomain(_ domain: String, code: Int, userInfo: NSObject?) -> NSObject
}

@ObjCConstants
enum ErrorDomains {
    static let kNWErrorDomainPOSIX = "kNWErrorDomainPOSIX"
    static let kNWErrorDomainDNS = "kNWErrorDomainDNS"
    static let kNWErrorDomainTLS = "kNWErrorDomainTLS"
    static let kNWErrorDomainWiFiAware = "kNWErrorDomainWiFiAware"
}

/// Darwin's errno numbers for Linux's: the same up to ERANGE, then not.
enum DarwinErrno {
    private static let table: [Int32: Int32] = [
        EAGAIN: 35, EINPROGRESS: 36, EALREADY: 37, ENOTSOCK: 38, EDESTADDRREQ: 39, EMSGSIZE: 40,
        EPROTOTYPE: 41, ENOPROTOOPT: 42, EPROTONOSUPPORT: 43, ESOCKTNOSUPPORT: 44, ENOTSUP: 45,
        EPFNOSUPPORT: 46, EAFNOSUPPORT: 47, EADDRINUSE: 48, EADDRNOTAVAIL: 49, ENETDOWN: 50,
        ENETUNREACH: 51, ENETRESET: 52, ECONNABORTED: 53, ECONNRESET: 54, ENOBUFS: 55, EISCONN: 56,
        ENOTCONN: 57, ESHUTDOWN: 58, ETOOMANYREFS: 59, ETIMEDOUT: 60, ECONNREFUSED: 61, ELOOP: 62,
        ENAMETOOLONG: 63, EHOSTDOWN: 64, EHOSTUNREACH: 65, ENOTEMPTY: 66, ENOSYS: 78, EOVERFLOW: 84,
        ECANCELED: 89, EILSEQ: 92, EBADMSG: 94, ENODATA: 96, EPROTO: 100, ETIME: 101, EDEADLK: 11,
    ]

    static func from(linux code: Int32) -> Int32 {
        if code <= 34 && code != EDEADLK { return code }
        return table[code] ?? 22
    }
}
