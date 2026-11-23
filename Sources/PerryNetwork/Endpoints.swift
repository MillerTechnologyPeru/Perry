import Glibc
import PerryObjCInterop

// Endpoints (addresses, host names and ports, Bonjour services, URLs),
// interfaces, TXT records and group descriptors. Addresses cross the C API
// in Darwin's sockaddr layout (a length byte, then the family: AF_INET 2,
// AF_INET6 30) and are kept in Linux's for the sockets.

// MARK: - Addresses

/// A socket address in Linux's layout.
struct SocketAddress: Equatable, Hashable {
    var bytes: [UInt8]

    var family: Int32 { bytes.count >= 2 ? Int32(bytes.withUnsafeBytes { $0.load(as: sa_family_t.self) }) : Int32(AF_UNSPEC) }
    var length: socklen_t { socklen_t(bytes.count) }

    init(linux pointer: UnsafeRawPointer, length: Int) {
        bytes = Array(UnsafeRawBufferPointer(start: pointer, count: length))
    }

    init?(storage: sockaddr_storage, length: socklen_t) {
        var copy = storage
        let count = Int(length)
        guard count >= 2 else { return nil }
        bytes = withUnsafeBytes(of: &copy) { Array($0.prefix(count)) }
    }

    /// From Darwin's layout.
    init?(darwin pointer: UnsafeRawPointer?) {
        guard let pointer else { return nil }
        let family = pointer.load(fromByteOffset: 1, as: UInt8.self)
        switch family {
        case 2:
            var address = sockaddr_in()
            withUnsafeMutableBytes(of: &address) { $0.copyMemory(from: UnsafeRawBufferPointer(start: pointer, count: MemoryLayout<sockaddr_in>.size)) }
            address.sin_family = sa_family_t(AF_INET)
            bytes = withUnsafeBytes(of: &address) { Array($0) }
        case 30:
            var address = sockaddr_in6()
            withUnsafeMutableBytes(of: &address) { $0.copyMemory(from: UnsafeRawBufferPointer(start: pointer, count: MemoryLayout<sockaddr_in6>.size)) }
            address.sin6_family = sa_family_t(AF_INET6)
            bytes = withUnsafeBytes(of: &address) { Array($0) }
        default:
            return nil
        }
    }

    /// An IPv4 or IPv6 address and port from their text, without lookups.
    init?(numeric host: String, port: UInt16) {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result, let address = first.pointee.ai_addr else { return nil }
        defer { freeaddrinfo(result) }
        self.init(linux: address, length: Int(first.pointee.ai_addrlen))
        self.port = port
    }

    static func any(family: Int32, port: UInt16) -> SocketAddress {
        if family == AF_INET {
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            return SocketAddress(linux: &address, length: MemoryLayout<sockaddr_in>.size)
        }
        var address = sockaddr_in6()
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        return SocketAddress(linux: &address, length: MemoryLayout<sockaddr_in6>.size)
    }

    /// Darwin's layout.
    var darwinBytes: [UInt8] {
        var copy = bytes
        guard copy.count >= 2 else { return copy }
        if family == AF_INET {
            copy[0] = UInt8(MemoryLayout<sockaddr_in>.size)
            copy[1] = 2
        } else if family == AF_INET6 {
            copy[0] = UInt8(MemoryLayout<sockaddr_in6>.size)
            copy[1] = 30
        }
        return copy
    }

    var port: UInt16 {
        get {
            guard family == AF_INET || family == AF_INET6, bytes.count >= 4 else { return 0 }
            return UInt16(bigEndian: bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: UInt16.self) })
        }
        set {
            guard family == AF_INET || family == AF_INET6, bytes.count >= 4 else { return }
            let value = newValue.bigEndian
            withUnsafeBytes(of: value) { bytes[2] = $0[0]; bytes[3] = $0[1] }
        }
    }

    /// The address without its port, as text ("127.0.0.1", "::1", "fe80::1%eth0").
    var host: String {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = bytes.withUnsafeBytes {
            getnameinfo($0.baseAddress!.assumingMemoryBound(to: sockaddr.self), length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
        }
        return status == 0 ? String(cString: buffer) : "?"
    }

    var description: String { family == AF_INET6 ? "[\(host)]:\(port)" : "\(host):\(port)" }

    var isMulticast: Bool {
        if family == AF_INET, bytes.count >= 8 { return bytes[4] & 0xF0 == 0xE0 }
        if family == AF_INET6, bytes.count >= 24 { return bytes[8] == 0xFF }
        return false
    }

    var isLoopback: Bool {
        if family == AF_INET, bytes.count >= 8 { return bytes[4] == 127 }
        if family == AF_INET6, bytes.count >= 24 { return bytes[8..<23].allSatisfy { $0 == 0 } && bytes[23] == 1 }
        return false
    }

    func withPointer<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        bytes.withUnsafeBytes { body($0.baseAddress!.assumingMemoryBound(to: sockaddr.self), length) }
    }

    /// The address a socket is bound to or connected to.
    static func local(_ fd: Int32) -> SocketAddress? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        return status == 0 ? SocketAddress(storage: storage, length: length) : nil
    }

    static func remote(_ fd: Int32) -> SocketAddress? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &length) } }
        return status == 0 ? SocketAddress(storage: storage, length: length) : nil
    }
}

/// A port from its text: a number, or a service name ("https").
func portNumber(_ text: String?) -> UInt16 {
    guard let text, !text.isEmpty else { return 0 }
    if let number = UInt16(text) { return number }
    if let service = getservbyname(text, "tcp") ?? getservbyname(text, "udp") {
        return UInt16(bigEndian: UInt16(truncatingIfNeeded: service.pointee.s_port))
    }
    return 0
}

// MARK: - Endpoints

/// nw_endpoint_type_t.
enum EndpointType {
    static let invalid: Int32 = 0
    static let address: Int32 = 1
    static let host: Int32 = 2
    static let bonjourService: Int32 = 3
    static let url: Int32 = 4
}

final class EndpointState: NWState {
    let type: Int32
    let address: SocketAddress?
    /// The address in Darwin's layout, for nw_endpoint_get_address.
    private let darwinAddress: UnsafeMutableRawPointer?
    let hostname: HeldCString
    let port: UInt16
    let bonjourName: HeldCString
    let bonjourType: HeldCString
    let bonjourDomain: HeldCString
    let url: HeldCString
    let urlPath: String
    let urlScheme: String
    var txtRecord: UnsafeMutableRawPointer?
    var interface: UnsafeMutableRawPointer?

    init(type: Int32, address: SocketAddress? = nil, hostname: String? = nil, port: UInt16 = 0,
         bonjour: (String?, String?, String?) = (nil, nil, nil), url: String? = nil, urlScheme: String = "", urlPath: String = "/") {
        self.type = type
        self.address = address
        if let address {
            let bytes = address.darwinBytes
            let storage = UnsafeMutableRawPointer.allocate(byteCount: max(bytes.count, MemoryLayout<sockaddr_storage>.size), alignment: 8)
            storage.initializeMemory(as: UInt8.self, repeating: 0, count: max(bytes.count, MemoryLayout<sockaddr_storage>.size))
            bytes.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            darwinAddress = storage
        } else {
            darwinAddress = nil
        }
        self.hostname = HeldCString(hostname)
        self.port = address?.port ?? port
        bonjourName = HeldCString(bonjour.0)
        bonjourType = HeldCString(bonjour.1)
        bonjourDomain = HeldCString(bonjour.2)
        self.url = HeldCString(url)
        self.urlScheme = urlScheme
        self.urlPath = urlPath
    }

    deinit {
        darwinAddress?.deallocate()
        ObjCRuntime.release(txtRecord)
        ObjCRuntime.release(interface)
    }

    var darwinAddressPointer: UnsafeRawPointer? { darwinAddress.map(UnsafeRawPointer.init) }

    /// The host name or address text, for logs and descriptions.
    var hostText: String {
        if let address { return address.host }
        if let name = hostname.value { return String(cString: name) }
        if let name = bonjourName.value { return String(cString: name) }
        return "?"
    }

    var description: String {
        switch type {
        case EndpointType.address: return address?.description ?? "?"
        case EndpointType.host: return "\(hostText):\(port)"
        case EndpointType.url: return url.value.map { String(cString: $0) } ?? "?"
        case EndpointType.bonjourService:
            let name = bonjourName.value.map { String(cString: $0) } ?? ""
            let kind = bonjourType.value.map { String(cString: $0) } ?? ""
            let domain = bonjourDomain.value.map { String(cString: $0) } ?? ""
            return "\(name).\(kind)\(domain)"
        default: return "?"
        }
    }

    /// True for a URL whose scheme encrypts (https, wss).
    var urlIsSecure: Bool { urlScheme == "https" || urlScheme == "wss" }
}

@ObjCClass("OS_nw_endpoint")
open class NWEndpointObject: NWObject {}

enum Endpoints {
    static func state(_ endpoint: UnsafeMutableRawPointer?) -> EndpointState? { NWObjects.state(endpoint, EndpointState.self) }

    /// A new endpoint (+1).
    static func make(_ state: EndpointState) -> UnsafeMutableRawPointer { NWObjects.make(NWEndpointObject.objCClass, state) }

    static func make(address: SocketAddress) -> UnsafeMutableRawPointer {
        make(EndpointState(type: EndpointType.address, address: address))
    }

    /// The same endpoint again, as a new object (+1).
    static func copy(_ endpoint: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(endpoint) }
}

@c(_nw_endpoint_get_type)
public func nw_endpoint_get_type(_ endpoint: UnsafeMutableRawPointer?) -> Int32 { Endpoints.state(endpoint)?.type ?? EndpointType.invalid }

/// A host endpoint; a numeric host is an address endpoint, as on Darwin.
@c(_nw_endpoint_create_host)
public func nw_endpoint_create_host(_ host: UnsafePointer<CChar>?, _ port: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let host else { return nil }
    let name = String(cString: host)
    let number = portNumber(port.map { String(cString: $0) })
    if let address = SocketAddress(numeric: name, port: number) { return Endpoints.make(address: address) }
    return Endpoints.make(EndpointState(type: EndpointType.host, hostname: name, port: number))
}

@c(_nw_endpoint_create_address)
public func nw_endpoint_create_address(_ address: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let parsed = SocketAddress(darwin: address) else { return nil }
    return Endpoints.make(address: parsed)
}

@c(_nw_endpoint_create_bonjour_service)
public func nw_endpoint_create_bonjour_service(_ name: UnsafePointer<CChar>?, _ type: UnsafePointer<CChar>?,
                                               _ domain: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name, let type else { return nil }
    return Endpoints.make(EndpointState(type: EndpointType.bonjourService,
                                        bonjour: (String(cString: name), String(cString: type), domain.map { String(cString: $0) } ?? "local.")))
}

/// A URL endpoint: its host and port (the scheme's, when it names none)
/// are what a connection reaches.
@c(_nw_endpoint_create_url)
public func nw_endpoint_create_url(_ url: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let url else { return nil }
    let text = String(cString: url)
    guard let schemeEnd = text.firstRange(of: "://") else { return nil }
    let scheme = text[..<schemeEnd.lowerBound].lowercased()
    var rest = text[schemeEnd.upperBound...]
    var path = "/"
    if let slash = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
        path = String(rest[slash...])
        if !path.hasPrefix("/") { path = "/" + path }
        rest = rest[..<slash]
    }
    if let at = rest.lastIndex(of: "@") { rest = rest[rest.index(after: at)...] }
    var host = String(rest)
    var port: UInt16 = ["https": 443, "wss": 443, "http": 80, "ws": 80, "ftp": 21][scheme] ?? 0
    if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
        let after = host[host.index(after: close)...]
        if after.hasPrefix(":"), let number = UInt16(after.dropFirst()) { port = number }
        host = String(host[host.index(after: host.startIndex)..<close])
    } else if let colon = host.lastIndex(of: ":"), let number = UInt16(host[host.index(after: colon)...]) {
        port = number
        host = String(host[..<colon])
    }
    guard !host.isEmpty else { return nil }
    return Endpoints.make(EndpointState(type: EndpointType.url, hostname: host, port: port, url: text, urlScheme: scheme, urlPath: path))
}

@c(_nw_endpoint_get_address)
public func nw_endpoint_get_address(_ endpoint: UnsafeMutableRawPointer?) -> UnsafeRawPointer? {
    Endpoints.state(endpoint)?.darwinAddressPointer
}

@c(_nw_endpoint_get_hostname)
public func nw_endpoint_get_hostname(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    guard let state = Endpoints.state(endpoint), state.type == EndpointType.host || state.type == EndpointType.url else { return nil }
    return state.hostname.value
}

@c(_nw_endpoint_get_port)
public func nw_endpoint_get_port(_ endpoint: UnsafeMutableRawPointer?) -> UInt16 { Endpoints.state(endpoint)?.port ?? 0 }

@c(_nw_endpoint_get_url)
public func nw_endpoint_get_url(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? { Endpoints.state(endpoint)?.url.value }

@c(_nw_endpoint_get_bonjour_service_name)
public func nw_endpoint_get_bonjour_service_name(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    Endpoints.state(endpoint)?.bonjourName.value
}

@c(_nw_endpoint_get_bonjour_service_type)
public func nw_endpoint_get_bonjour_service_type(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    Endpoints.state(endpoint)?.bonjourType.value
}

@c(_nw_endpoint_get_bonjour_service_domain)
public func nw_endpoint_get_bonjour_service_domain(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    Endpoints.state(endpoint)?.bonjourDomain.value
}

/// The address as text, for the caller to free.
@c(_nw_endpoint_copy_address_string)
public func nw_endpoint_copy_address_string(_ endpoint: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    guard let address = Endpoints.state(endpoint)?.address else { return nil }
    return copiedCString(address.host)
}

@c(_nw_endpoint_copy_port_string)
public func nw_endpoint_copy_port_string(_ endpoint: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    guard let state = Endpoints.state(endpoint) else { return nil }
    return copiedCString(String(state.port))
}

@c(_nw_endpoint_copy_txt_record)
public func nw_endpoint_copy_txt_record(_ endpoint: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(Endpoints.state(endpoint)?.txtRecord)
}

// MARK: - Interfaces

/// nw_interface_type_t.
enum InterfaceType {
    static let other: Int32 = 0
    static let wifi: Int32 = 1
    static let cellular: Int32 = 2
    static let wired: Int32 = 3
    static let loopback: Int32 = 4
}

final class InterfaceState: NWState {
    let name: HeldCString
    let nameText: String
    let index: UInt32
    let type: Int32

    init(name: String, index: UInt32, type: Int32) {
        self.name = HeldCString(name)
        nameText = name
        self.index = index
        self.type = type
    }
}

@ObjCClass("OS_nw_interface")
open class NWInterfaceObject: NWObject {}

/// A network interface the system has, as /sys and getifaddrs show it.
struct InterfaceInfo: Equatable {
    let name: String
    let index: UInt32
    let type: Int32
    var hasIPv4: Bool
    var hasIPv6: Bool
    var addresses: [SocketAddress]

    /// A new nw_interface_t (+1).
    func object() -> UnsafeMutableRawPointer {
        NWObjects.make(NWInterfaceObject.objCClass, InterfaceState(name: name, index: index, type: type))
    }
}

enum Interfaces {
    static func state(_ interface: UnsafeMutableRawPointer?) -> InterfaceState? { NWObjects.state(interface, InterfaceState.self) }

    /// The interfaces that are up, in the order the system lists them.
    static func current() -> [InterfaceInfo] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var result: [InterfaceInfo] = []
        var entry = list
        while let current = entry {
            defer { entry = current.pointee.ifa_next }
            let flags = current.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, let namePointer = current.pointee.ifa_name else { continue }
            let name = String(cString: namePointer)
            var index = result.firstIndex { $0.name == name }
            if index == nil {
                let type = flags & UInt32(IFF_LOOPBACK) != 0 ? InterfaceType.loopback : kind(of: name)
                result.append(InterfaceInfo(name: name, index: if_nametoindex(namePointer), type: type, hasIPv4: false, hasIPv6: false, addresses: []))
                index = result.count - 1
            }
            if let address = current.pointee.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                if family == AF_INET {
                    result[index!].hasIPv4 = true
                    result[index!].addresses.append(SocketAddress(linux: address, length: MemoryLayout<sockaddr_in>.size))
                } else if family == AF_INET6 {
                    result[index!].hasIPv6 = true
                    result[index!].addresses.append(SocketAddress(linux: address, length: MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
        return result.filter { $0.hasIPv4 || $0.hasIPv6 }
    }

    /// Wi-Fi when the kernel says the link is wireless, wired for other
    /// Ethernet devices, other for virtual links (tunnels, bridges).
    static func kind(of name: String) -> Int32 {
        if access("/sys/class/net/\(name)/wireless", F_OK) == 0 || access("/sys/class/net/\(name)/phy80211", F_OK) == 0 {
            return InterfaceType.wifi
        }
        if name.hasPrefix("wwan") || name.hasPrefix("rmnet") { return InterfaceType.cellular }
        if access("/sys/class/net/\(name)/device", F_OK) == 0 { return InterfaceType.wired }
        return InterfaceType.other
    }

    /// The interface that has `address`, for a connection's path.
    static func with(address: SocketAddress?) -> InterfaceInfo? {
        let all = current()
        guard let address else { return nil }
        var bare = address
        bare.port = 0
        return all.first { $0.addresses.contains { candidate in var plain = candidate; plain.port = 0; return plain.host == bare.host } }
    }
}

@c(_nw_interface_get_type)
public func nw_interface_get_type(_ interface: UnsafeMutableRawPointer?) -> Int32 { Interfaces.state(interface)?.type ?? InterfaceType.other }

@c(_nw_interface_get_name)
public func nw_interface_get_name(_ interface: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? { Interfaces.state(interface)?.name.value }

@c(_nw_interface_get_index)
public func nw_interface_get_index(_ interface: UnsafeMutableRawPointer?) -> UInt32 { Interfaces.state(interface)?.index ?? 0 }

@c(_nw_interface_create_with_index)
public func nw_interface_create_with_index(_ index: UInt32) -> UnsafeMutableRawPointer? {
    Interfaces.current().first { $0.index == index }?.object()
}

@c(_nw_interface_create_with_name)
public func nw_interface_create_with_name(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let text = String(cString: name)
    return Interfaces.current().first { $0.name == text }?.object()
}

// MARK: - TXT records

final class TXTRecordState: NWState {
    var bytes: [UInt8]
    let isDictionary: Bool
    init(_ bytes: [UInt8], isDictionary: Bool) {
        self.bytes = bytes
        self.isDictionary = isDictionary
    }
}

@ObjCClass("OS_nw_txt_record")
open class NWTXTRecordObject: NWObject {}

@c(_nw_txt_record_create_with_bytes)
public func nw_txt_record_create_with_bytes(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutableRawPointer? {
    guard let bytes else { return nil }
    return NWObjects.make(NWTXTRecordObject.objCClass, TXTRecordState(Array(UnsafeBufferPointer(start: bytes, count: length)), isDictionary: false))
}

@c(_nw_txt_record_create_dictionary)
public func nw_txt_record_create_dictionary() -> UnsafeMutableRawPointer? {
    NWObjects.make(NWTXTRecordObject.objCClass, TXTRecordState([], isDictionary: true))
}

/// The block reads the record's bytes; its answer is returned.
@c(_nw_txt_record_access_bytes)
public func nw_txt_record_access_bytes(_ record: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) -> Bool {
    guard let state = NWObjects.state(record, TXTRecordState.self), let block = ObjCBlock.from(block) else { return false }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<UInt8>?, Int) -> Bool
    let bytes = state.bytes
    return bytes.withUnsafeBufferPointer { block.function(as: Invoke.self)(block.object, $0.baseAddress, $0.count) }
}

@c(_nw_txt_record_copy)
public func nw_txt_record_copy(_ record: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = NWObjects.state(record, TXTRecordState.self) else { return nil }
    return NWObjects.make(NWTXTRecordObject.objCClass, TXTRecordState(state.bytes, isDictionary: state.isDictionary))
}

@c(_nw_txt_record_is_dictionary)
public func nw_txt_record_is_dictionary(_ record: UnsafeMutableRawPointer?) -> Bool {
    NWObjects.state(record, TXTRecordState.self)?.isDictionary ?? false
}

// MARK: - Group descriptors

final class GroupDescriptorState: NWState {
    let isMulticast: Bool
    var endpoints: [UnsafeMutableRawPointer] = []
    var disableUnicastTraffic = false
    var specificSource: UnsafeMutableRawPointer?

    init(isMulticast: Bool) { self.isMulticast = isMulticast }

    deinit {
        endpoints.forEach { ObjCRuntime.release($0) }
        ObjCRuntime.release(specificSource)
    }
}

@ObjCClass("OS_nw_group_descriptor")
open class NWGroupDescriptorObject: NWObject {}

/// A multicast group: one or more group addresses with the port to join on.
@c(_nw_group_descriptor_create_multicast)
public func nw_group_descriptor_create_multicast(_ group: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let address = Endpoints.state(group)?.address, address.isMulticast, let group else { return nil }
    let state = GroupDescriptorState(isMulticast: true)
    state.endpoints.append(ObjCRuntime.retain(group)!)
    return NWObjects.make(NWGroupDescriptorObject.objCClass, state)
}

/// A multiplex group, which QUIC carries: made, but no group starts on it.
@c(_nw_group_descriptor_create_multiplex)
public func nw_group_descriptor_create_multiplex(_ remote: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let remote else { return nil }
    let state = GroupDescriptorState(isMulticast: false)
    state.endpoints.append(ObjCRuntime.retain(remote)!)
    return NWObjects.make(NWGroupDescriptorObject.objCClass, state)
}

@c(_nw_group_descriptor_add_endpoint)
public func nw_group_descriptor_add_endpoint(_ descriptor: UnsafeMutableRawPointer?, _ endpoint: UnsafeMutableRawPointer?) -> Bool {
    guard let state = NWObjects.state(descriptor, GroupDescriptorState.self), let endpoint else { return false }
    if state.isMulticast, Endpoints.state(endpoint)?.address?.isMulticast != true { return false }
    state.endpoints.append(ObjCRuntime.retain(endpoint)!)
    return true
}

@c(_nw_group_descriptor_enumerate_endpoints)
public func nw_group_descriptor_enumerate_endpoints(_ descriptor: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let state = NWObjects.state(descriptor, GroupDescriptorState.self), let block = ObjCBlock.from(block) else { return }
    for endpoint in state.endpoints where !block.test(endpoint) { break }
}

@c(_nw_multicast_group_descriptor_set_disable_unicast_traffic)
public func nw_multicast_group_descriptor_set_disable_unicast_traffic(_ descriptor: UnsafeMutableRawPointer?, _ disable: Bool) {
    NWObjects.state(descriptor, GroupDescriptorState.self)?.disableUnicastTraffic = disable
}

@c(_nw_multicast_group_descriptor_get_disable_unicast_traffic)
public func nw_multicast_group_descriptor_get_disable_unicast_traffic(_ descriptor: UnsafeMutableRawPointer?) -> Bool {
    NWObjects.state(descriptor, GroupDescriptorState.self)?.disableUnicastTraffic ?? false
}

@c(_nw_multicast_group_descriptor_set_specific_source)
public func nw_multicast_group_descriptor_set_specific_source(_ descriptor: UnsafeMutableRawPointer?, _ source: UnsafeMutableRawPointer?) {
    guard let state = NWObjects.state(descriptor, GroupDescriptorState.self) else { return }
    let held = ObjCRuntime.retain(source)
    ObjCRuntime.release(state.specificSource)
    state.specificSource = held
}
