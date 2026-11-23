// NWError: the errors of the Network framework, by their domain, made
// from the C API's nw_error_t.

import Darwin
import Foundation
import Security
import dnssd

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public enum NWError: Error, CustomDebugStringConvertible, Equatable {
    /// An error of the POSIX domain, an errno value.
    case posix(POSIXErrorCode)
    /// A DNSServiceErrorType of dns_sd.h.
    case dns(DNSServiceErrorType)
    /// A TLS error, an errSSL OSStatus of Security.
    case tls(OSStatus)
    /// An error of Wi-Fi Aware (macOS and iOS 26).
    case wifiAware(Int32)

    public var debugDescription: String {
        switch self {
        case .posix(let code):
            return "POSIXErrorCode(rawValue: \(code.rawValue)): \(String(cString: strerror(code.rawValue)))"
        case .dns(let code):
            return "DNSServiceErrorType(rawValue: \(code)): \(dnsErrorName(code))"
        case .tls(let status):
            return "OSStatus(rawValue: \(status)): \(tlsErrorText(status))"
        case .wifiAware(let code):
            return "Wi-Fi Aware error \(code)"
        }
    }

    public static func == (a: NWError, b: NWError) -> Bool {
        switch (a, b) {
        case let (.posix(x), .posix(y)): return x == y
        case let (.dns(x), .dns(y)): return x == y
        case let (.tls(x), .tls(y)): return x == y
        case let (.wifiAware(x), .wifiAware(y)): return x == y
        default: return false
        }
    }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension NWError: CustomNSError {
    public var errorCode: Int {
        switch self {
        case .posix(let code): return Int(code.rawValue)
        case .dns(let code): return Int(code)
        case .tls(let status): return Int(status)
        case .wifiAware(let code): return Int(code)
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: debugDescription]
    }

    public var _domain: String {
        switch self {
        case .posix: return kNWErrorDomainPOSIX as String
        case .dns: return kNWErrorDomainDNS as String
        case .tls: return kNWErrorDomainTLS as String
        case .wifiAware:
            if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
                return kNWErrorDomainWiFiAware as String
            }
            return "kNWErrorDomainWiFiAware"
        }
    }
}

/// The names of dns_sd.h's errors.
private func dnsErrorName(_ code: DNSServiceErrorType) -> String {
    switch Int(code) {
    case kDNSServiceErr_NoError: return "NoError"
    case kDNSServiceErr_Unknown: return "Unknown"
    case kDNSServiceErr_NoSuchName: return "NoSuchName"
    case kDNSServiceErr_NoMemory: return "NoMemory"
    case kDNSServiceErr_BadParam: return "BadParam"
    case kDNSServiceErr_BadReference: return "BadReference"
    case kDNSServiceErr_BadState: return "BadState"
    case kDNSServiceErr_BadFlags: return "BadFlags"
    case kDNSServiceErr_Unsupported: return "Unsupported"
    case kDNSServiceErr_NotInitialized: return "NotInitialized"
    case kDNSServiceErr_AlreadyRegistered: return "AlreadyRegistered"
    case kDNSServiceErr_NameConflict: return "NameConflict"
    case kDNSServiceErr_Invalid: return "Invalid"
    case kDNSServiceErr_Firewall: return "Firewall"
    case kDNSServiceErr_Incompatible: return "Incompatible"
    case kDNSServiceErr_BadInterfaceIndex: return "BadInterfaceIndex"
    case kDNSServiceErr_Refused: return "Refused"
    case kDNSServiceErr_NoSuchRecord: return "NoSuchRecord"
    case kDNSServiceErr_NoAuth: return "NoAuth"
    case kDNSServiceErr_NoSuchKey: return "NoSuchKey"
    case kDNSServiceErr_NATTraversal: return "NATTraversal"
    case kDNSServiceErr_DoubleNAT: return "DoubleNAT"
    case kDNSServiceErr_BadTime: return "BadTime"
    case kDNSServiceErr_BadSig: return "BadSig"
    case kDNSServiceErr_BadKey: return "BadKey"
    case kDNSServiceErr_Transient: return "Transient"
    case kDNSServiceErr_ServiceNotRunning: return "ServiceNotRunning"
    case kDNSServiceErr_NATPortMappingUnsupported: return "NATPortMappingUnsupported"
    case kDNSServiceErr_NATPortMappingDisabled: return "NATPortMappingDisabled"
    case kDNSServiceErr_NoRouter: return "NoRouter"
    case kDNSServiceErr_PollingMode: return "PollingMode"
    case kDNSServiceErr_Timeout: return "Timeout"
    case kDNSServiceErr_DefunctConnection: return "DefunctConnection"
    case kDNSServiceErr_PolicyDenied: return "PolicyDenied"
    case kDNSServiceErr_NotPermitted: return "NotPermitted"
    default: return "Unknown"
    }
}

/// Security's text for a TLS status, or its number without one.
private func tlsErrorText(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) {
        return message as String
    }
    return "OSStatus \(status)"
}

extension NWError {
    /// The error of a C API error, nil without one.
    init?(_ error: nw_error_t?) {
        guard let error else { return nil }
        let code = nw_error_get_error_code(error)
        switch nw_error_get_error_domain(error) {
        case nw_error_domain_posix:
            self = .posix(POSIXErrorCode(rawValue: code) ?? .EINVAL)
        case nw_error_domain_dns:
            self = .dns(DNSServiceErrorType(code))
        case nw_error_domain_tls:
            self = .tls(OSStatus(code))
        case nw_error_domain_t(rawValue: 4):
            // nw_error_domain_wifi_aware
            self = .wifiAware(code)
        default:
            self = .posix(POSIXErrorCode(rawValue: code) ?? .EINVAL)
        }
    }
}
