// NWEndpoint: where a connection goes or comes from, and its conversion to
// and from the C API's nw_endpoint_t.

import Darwin
import Foundation

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public enum NWEndpoint: Hashable, CustomDebugStringConvertible, Sendable {
    case hostPort(host: Host, port: Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    case unix(path: String)
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    case url(_: URL)
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    case opaque(_: nw_endpoint_t)

    public enum Host: Hashable, CustomDebugStringConvertible, ExpressibleByStringLiteral, Sendable {
        public typealias StringLiteralType = String

        case name(String, NWInterface?)
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)

        public init(stringLiteral: StringLiteralType) {
            self.init(stringLiteral)
        }

        /// An address if the string is one, else a host name (with the
        /// interface after a "%").
        public init(_ string: String) {
            if let address = IPv4Address(string) {
                self = .ipv4(address)
            } else if let address = IPv6Address(string) {
                self = .ipv6(address)
            } else if let percent = string.firstIndex(of: "%"),
                      let interface = NWInterface(name: String(string[string.index(after: percent)...])) {
                self = .name(String(string[..<percent]), interface)
            } else {
                self = .name(string, nil)
            }
        }

        public var interface: NWInterface? {
            switch self {
            case .name(_, let interface): return interface
            case .ipv4(let address): return address.interface
            case .ipv6(let address): return address.interface
            }
        }

        public var debugDescription: String {
            switch self {
            case .name(let name, let interface):
                return interface.map { "\(name)%\($0.name)" } ?? name
            case .ipv4(let address): return address.debugDescription
            case .ipv6(let address): return address.debugDescription
            }
        }

        public static func == (a: Host, b: Host) -> Bool {
            switch (a, b) {
            case let (.name(x, xi), .name(y, yi)): return x == y && xi == yi
            case let (.ipv4(x), .ipv4(y)): return x == y
            case let (.ipv6(x), .ipv6(y)): return x == y
            default: return false
            }
        }

        @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
        public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
        @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
        public typealias UnicodeScalarLiteralType = StringLiteralType

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .name(let name, let interface):
                hasher.combine(0)
                hasher.combine(name)
                hasher.combine(interface)
            case .ipv4(let address):
                hasher.combine(1)
                hasher.combine(address)
            case .ipv6(let address):
                hasher.combine(2)
                hasher.combine(address)
            }
        }
    }

    public struct Port: Hashable, CustomDebugStringConvertible, ExpressibleByIntegerLiteral, RawRepresentable, Sendable {
        public typealias IntegerLiteralType = UInt16

        public static let any: Port = 0
        public static let ssh: Port = 22
        public static let smtp: Port = 25
        public static let http: Port = 80
        public static let pop: Port = 110
        public static let imap: Port = 143
        public static let https: Port = 443
        public static let imaps: Port = 993
        public static let socks: Port = 1080

        public let rawValue: UInt16

        /// A port number, or the port of a service of /etc/services.
        public init?(_ service: String) {
            if let number = UInt16(service) {
                rawValue = number
            } else if let entry = getservbyname(service, "tcp") ?? getservbyname(service, "udp") {
                rawValue = UInt16(bigEndian: UInt16(truncatingIfNeeded: entry.pointee.s_port))
            } else {
                return nil
            }
        }

        public init(integerLiteral value: IntegerLiteralType) {
            rawValue = value
        }

        public init?(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public var debugDescription: String { String(rawValue) }

        @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
        public typealias RawValue = UInt16
    }

    public var interface: NWInterface? {
        switch self {
        case .hostPort(let host, _): return host.interface
        case .service(_, _, _, let interface): return interface
        default: return nil
        }
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public var txtRecord: NWTXTRecord? {
        guard case .opaque(let endpoint) = self,
              let record = nw_endpoint_copy_txt_record(endpoint) else { return nil }
        return NWTXTRecord(record)
    }

    /// The endpoint with another port, for a host and port one (or a C
    /// API one that is an address or a host).
    @available(macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4, *)
    public init?(copying endpoint: NWEndpoint, newPort: Port) {
        switch endpoint.resolvedOpaque {
        case .hostPort(let host, _):
            self = .hostPort(host: host, port: newPort)
        default:
            return nil
        }
    }

    public static func == (lhs: NWEndpoint, rhs: NWEndpoint) -> Bool {
        switch (lhs, rhs) {
        case let (.hostPort(h1, p1), .hostPort(h2, p2)):
            return h1 == h2 && p1 == p2
        case let (.service(n1, t1, d1, i1), .service(n2, t2, d2, i2)):
            return n1 == n2 && t1 == t2 && d1 == d2 && i1 == i2
        case let (.unix(a), .unix(b)):
            return a == b
        case let (.url(a), .url(b)):
            return a == b
        case let (.opaque(a), .opaque(b)):
            return a === b || a.description == b.description
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .hostPort(let host, let port):
            hasher.combine(0)
            hasher.combine(host)
            hasher.combine(port)
        case .service(let name, let type, let domain, let interface):
            hasher.combine(1)
            hasher.combine(name)
            hasher.combine(type)
            hasher.combine(domain)
            hasher.combine(interface)
        case .unix(let path):
            hasher.combine(2)
            hasher.combine(path)
        case .url(let url):
            hasher.combine(3)
            hasher.combine(url)
        case .opaque(let endpoint):
            hasher.combine(4)
            hasher.combine(endpoint.description)
        }
    }

    public var debugDescription: String {
        switch self {
        case .hostPort(let host, let port):
            if case .ipv6 = host {
                return "[\(host.debugDescription)]:\(port.rawValue)"
            }
            return "\(host.debugDescription):\(port.rawValue)"
        case .service(let name, let type, let domain, _):
            return "\(name).\(type).\(domain)"
        case .unix(let path):
            return path
        case .url(let url):
            return url.absoluteString
        case .opaque(let endpoint):
            return endpoint.description
        }
    }
}

// MARK: - The C API's endpoints

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NWEndpoint {
    /// The endpoint of a C API one: a case of its kind, or opaque for a
    /// kind without one.
    init(_ endpoint: nw_endpoint_t) {
        switch nw_endpoint_get_type(endpoint) {
        case nw_endpoint_type_address:
            if let value = NWEndpoint(address: nw_endpoint_get_address(endpoint)) {
                self = value
                return
            }
        case nw_endpoint_type_host:
            let name = String(cString: nw_endpoint_get_hostname(endpoint))
            self = .hostPort(host: .name(name, nil), port: Port(integerLiteral: nw_endpoint_get_port(endpoint)))
            return
        case nw_endpoint_type_bonjour_service:
            let name = String(cString: nw_endpoint_get_bonjour_service_name(endpoint))
            let type = String(cString: nw_endpoint_get_bonjour_service_type(endpoint))
            let domain = String(cString: nw_endpoint_get_bonjour_service_domain(endpoint))
            self = .service(name: name, type: type, domain: domain, interface: nil)
            return
        case nw_endpoint_type_url:
            if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *),
               let url = URL(string: String(cString: nw_endpoint_get_url(endpoint))) {
                self = .url(url)
                return
            }
        default:
            break
        }
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            self = .opaque(endpoint)
        } else {
            self = .unix(path: "")
        }
    }

    /// The endpoint of a socket address: IPv4, IPv6 (scoped to its
    /// interface) or a local socket.
    init?(address: UnsafePointer<sockaddr>) {
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            let value = UnsafeRawPointer(address).load(as: sockaddr_in.self)
            self = .hostPort(host: .ipv4(IPv4Address(value.sin_addr)), port: Port(integerLiteral: UInt16(bigEndian: value.sin_port)))
        case AF_INET6:
            let value = UnsafeRawPointer(address).load(as: sockaddr_in6.self)
            let interface = NWInterface(index: Int(value.sin6_scope_id))
            self = .hostPort(host: .ipv6(IPv6Address(value.sin6_addr, interface: interface)), port: Port(integerLiteral: UInt16(bigEndian: value.sin6_port)))
        case AF_UNIX:
            let path = UnsafeRawPointer(address).withMemoryRebound(to: sockaddr_un.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sun_path) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
            }
            self = .unix(path: path)
        default:
            return nil
        }
    }

    /// A C API endpoint resolved back to its case when it has one.
    var resolvedOpaque: NWEndpoint {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *), case .opaque(let endpoint) = self {
            let value = NWEndpoint(endpoint)
            if case .opaque = value { return self }
            return value
        }
        return self
    }

    /// The C API's endpoint of this one.
    var nw: nw_endpoint_t {
        switch self {
        case .hostPort(let host, let port):
            switch host {
            case .ipv4(let address):
                var value = sockaddr_in()
                value.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                value.sin_family = sa_family_t(AF_INET)
                value.sin_port = port.rawValue.bigEndian
                value.sin_addr = address.address
                return withUnsafePointer(to: &value) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { nw_endpoint_create_address($0) }
                }
            case .ipv6(let address):
                var value = sockaddr_in6()
                value.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                value.sin6_family = sa_family_t(AF_INET6)
                value.sin6_port = port.rawValue.bigEndian
                value.sin6_addr = address.address
                value.sin6_scope_id = UInt32(address.interface?.index ?? 0)
                return withUnsafePointer(to: &value) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { nw_endpoint_create_address($0) }
                }
            case .name(let name, let interface):
                let host = interface.map { "\(name)%\($0.name)" } ?? name
                return nw_endpoint_create_host(host, String(port.rawValue))
            }
        case .service(let name, let type, let domain, _):
            return nw_endpoint_create_bonjour_service(name, type, domain)
        case .unix(let path):
            var value = sockaddr_un()
            value.sun_family = sa_family_t(AF_UNIX)
            let capacity = MemoryLayout.size(ofValue: value.sun_path)
            withUnsafeMutableBytes(of: &value.sun_path) { raw in
                for (index, byte) in path.utf8.prefix(capacity - 1).enumerated() {
                    raw[index] = byte
                }
            }
            value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            return withUnsafePointer(to: &value) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { nw_endpoint_create_address($0) }
            }
        case .url(let url):
            return nw_endpoint_create_url(url.absoluteString)
        case .opaque(let endpoint):
            return endpoint
        }
    }
}
