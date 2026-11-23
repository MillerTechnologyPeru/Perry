// IPv4Address and IPv6Address: addresses as their bytes in network order,
// with the interface a link-local one is scoped to, parsed and printed
// with inet_pton and inet_ntop.

import Darwin
import Foundation

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public protocol IPAddress: Sendable {
    var rawValue: Data { get }
    init?(_ rawValue: Data, _ interface: NWInterface?)
    init?(_ string: String)
    var interface: NWInterface? { get }
    var isLoopback: Bool { get }
    var isLinkLocal: Bool { get }
    var isMulticast: Bool { get }
}

/// An address string split at its "%" into the address and the interface
/// it names (by name or index); nil when the interface doesn't exist.
private func splitScope(_ string: String) -> (address: String, interface: NWInterface?)? {
    guard let percent = string.firstIndex(of: "%") else {
        return (string, nil)
    }
    let scope = String(string[string.index(after: percent)...])
    let interface = Int(scope).flatMap { NWInterface(index: $0) } ?? NWInterface(name: scope)
    guard let interface else { return nil }
    return (String(string[..<percent]), interface)
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct IPv4Address: IPAddress, Hashable, CustomDebugStringConvertible {
    public static let any = IPv4Address(bytes: (0, 0, 0, 0))
    public static let broadcast = IPv4Address(bytes: (255, 255, 255, 255))
    public static let loopback = IPv4Address(bytes: (127, 0, 0, 1))
    public static let allHostsGroup = IPv4Address(bytes: (224, 0, 0, 1))
    public static let allRoutersGroup = IPv4Address(bytes: (224, 0, 0, 2))
    public static let allReportsGroup = IPv4Address(bytes: (224, 0, 0, 22))
    public static let mdnsGroup = IPv4Address(bytes: (224, 0, 0, 251))

    /// The address in network byte order.
    let address: in_addr

    private init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        var address = in_addr()
        withUnsafeMutableBytes(of: &address) { raw in
            raw[0] = bytes.0
            raw[1] = bytes.1
            raw[2] = bytes.2
            raw[3] = bytes.3
        }
        self.address = address
        interface = nil
    }

    init(_ address: in_addr, interface: NWInterface? = nil) {
        self.address = address
        self.interface = interface
    }

    private var bytes: [UInt8] {
        withUnsafeBytes(of: address) { Array($0) }
    }

    public var isLoopback: Bool { bytes[0] == 127 }

    public var isLinkLocal: Bool { bytes[0] == 169 && bytes[1] == 254 }

    public var isMulticast: Bool { (224...239).contains(bytes[0]) }

    public var rawValue: Data { Data(bytes) }

    public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
        guard rawValue.count == MemoryLayout<in_addr>.size else { return nil }
        var address = in_addr()
        withUnsafeMutableBytes(of: &address) { _ = rawValue.copyBytes(to: $0) }
        self.init(address, interface: interface)
    }

    public init?(_ string: String) {
        guard let (text, interface) = splitScope(string) else { return nil }
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        self.init(address, interface: interface)
    }

    public let interface: NWInterface?

    public static func == (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.address.s_addr == rhs.address.s_addr && lhs.interface == rhs.interface
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(address.s_addr)
        hasher.combine(interface)
    }

    public var debugDescription: String {
        var address = self.address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
        let text = String(cString: buffer)
        return interface.map { "\(text)%\($0.name)" } ?? text
    }
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct IPv6Address: IPAddress, Hashable, CustomDebugStringConvertible {
    public static let any = IPv6Address(bytes: [])
    /// IPv6 has no broadcast; this is the all-nodes group of the link, ff02::1.
    public static let broadcast = IPv6Address(bytes: [0xff, 0x02] + Array(repeating: 0, count: 13) + [1])
    public static let loopback = IPv6Address(bytes: Array(repeating: 0, count: 15) + [1])
    public static let nodeLocalNodes = IPv6Address(bytes: [0xff, 0x01] + Array(repeating: 0, count: 13) + [1])
    public static let linkLocalNodes = IPv6Address(bytes: [0xff, 0x02] + Array(repeating: 0, count: 13) + [1])
    public static let linkLocalRouters = IPv6Address(bytes: [0xff, 0x02] + Array(repeating: 0, count: 13) + [2])

    /// The scope of a multicast address, its scope field's value.
    public enum Scope: UInt8 {
        case nodeLocal
        case linkLocal
        case siteLocal
        case organizationLocal
        case global

        public init?(rawValue: UInt8) {
            switch rawValue {
            case 1: self = .nodeLocal
            case 2: self = .linkLocal
            case 5: self = .siteLocal
            case 8: self = .organizationLocal
            case 14: self = .global
            default: return nil
            }
        }

        @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
        public typealias RawValue = UInt8

        public var rawValue: UInt8 {
            switch self {
            case .nodeLocal: 1
            case .linkLocal: 2
            case .siteLocal: 5
            case .organizationLocal: 8
            case .global: 14
            }
        }
    }

    /// The address's 16 bytes.
    let address: in6_addr

    private init(bytes: [UInt8]) {
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { raw in
            for (index, byte) in bytes.prefix(16).enumerated() {
                raw[index] = byte
            }
        }
        self.address = address
        interface = nil
    }

    init(_ address: in6_addr, interface: NWInterface? = nil) {
        self.address = address
        self.interface = interface
    }

    private var bytes: [UInt8] {
        withUnsafeBytes(of: address) { Array($0) }
    }

    public var isAny: Bool { bytes.allSatisfy { $0 == 0 } }

    public var isLoopback: Bool { bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1 }

    /// ::a.b.c.d, other than :: and ::1.
    public var isIPv4Compatabile: Bool {
        let bytes = self.bytes
        return bytes[0..<12].allSatisfy { $0 == 0 } && !(bytes[12..<15].allSatisfy { $0 == 0 } && bytes[15] <= 1)
    }

    /// ::ffff:a.b.c.d
    public var isIPv4Mapped: Bool {
        let bytes = self.bytes
        return bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
    }

    public var asIPv4: IPv4Address? {
        guard isIPv4Mapped || isIPv4Compatabile else { return nil }
        return IPv4Address(Data(bytes[12..<16]), interface)
    }

    /// 2002::/16
    public var is6to4: Bool { bytes[0] == 0x20 && bytes[1] == 0x02 }

    /// fe80::/10
    public var isLinkLocal: Bool { bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 }

    public var isMulticast: Bool { bytes[0] == 0xff }

    public var multicastScope: Scope? {
        guard isMulticast else { return nil }
        return Scope(rawValue: bytes[1] & 0x0f)
    }

    /// fc00::/7
    @available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
    public var isUniqueLocal: Bool { bytes[0] & 0xfe == 0xfc }

    public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
        guard rawValue.count == MemoryLayout<in6_addr>.size else { return nil }
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { _ = rawValue.copyBytes(to: $0) }
        self.init(address, interface: interface)
    }

    public init?(_ string: String) {
        var text = string
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = String(text[text.index(after: text.startIndex)..<close])
        }
        guard let (address, interface) = splitScope(text) else { return nil }
        var value = in6_addr()
        guard inet_pton(AF_INET6, address, &value) == 1 else { return nil }
        self.init(value, interface: interface)
    }

    public let interface: NWInterface?

    public var rawValue: Data { Data(bytes) }

    public static func == (lhs: IPv6Address, rhs: IPv6Address) -> Bool {
        lhs.bytes == rhs.bytes && lhs.interface == rhs.interface
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes)
        hasher.combine(interface)
    }

    public var debugDescription: String {
        var address = self.address
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count))
        let text = String(cString: buffer)
        return interface.map { "\(text)%\($0.name)" } ?? text
    }
}
