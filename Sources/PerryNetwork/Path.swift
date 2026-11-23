import Glibc
import PerryObjCInterop

// Paths and the path monitor, over the system's interfaces (getifaddrs and
// /sys) and routing table (/proc/net/route, /proc/net/ipv6_route). A path
// is satisfied when an interface the monitor may use has a default route;
// the interfaces with one come first. A started monitor calls its update
// handler on its queue at once and again whenever the path changes; it
// looks every two seconds.

/// nw_path_status_t.
enum PathStatus {
    static let invalid: Int32 = 0
    static let satisfied: Int32 = 1
    static let unsatisfied: Int32 = 2
    static let satisfiable: Int32 = 3
}

/// The default routes: the interfaces they leave through and their gateways.
enum Routes {
    struct Route {
        let interface: String
        let gateway: SocketAddress?
        let isIPv6: Bool
    }

    static func defaults() -> [Route] {
        var routes: [Route] = []
        if let table = read("/proc/net/route") {
            // Iface Destination Gateway Flags ...: RTF_UP is 1.
            for line in table.split(separator: "\n").dropFirst() {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count > 3, fields[1] == "00000000", let flags = Int(fields[3], radix: 16), flags & 1 != 0,
                      fields[0] != "lo" else { continue }
                var gateway: SocketAddress?
                if let value = UInt32(fields[2], radix: 16), value != 0 {
                    var address = sockaddr_in()
                    address.sin_family = sa_family_t(AF_INET)
                    address.sin_addr.s_addr = value
                    gateway = SocketAddress(linux: &address, length: MemoryLayout<sockaddr_in>.size)
                }
                routes.append(Route(interface: String(fields[0]), gateway: gateway, isIPv6: false))
            }
        }
        if let table = read("/proc/net/ipv6_route") {
            // Destination, prefix length, source, prefix length, next hop, metric, ..., flags, interface.
            for line in table.split(separator: "\n") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count >= 10, fields[0] == String(repeating: "0", count: 32), fields[1] == "00",
                      let flags = Int(fields[8], radix: 16), flags & 1 != 0, fields[9] != "lo" else { continue }
                var gateway: SocketAddress?
                let hop = Array(fields[4].utf8)
                if hop.count == 32, fields[4] != Substring(String(repeating: "0", count: 32)) {
                    var address = sockaddr_in6()
                    address.sin6_family = sa_family_t(AF_INET6)
                    withUnsafeMutableBytes(of: &address.sin6_addr) { bytes in
                        for index in 0..<16 { bytes[index] = UInt8(String(decoding: hop[index * 2..<index * 2 + 2], as: UTF8.self), radix: 16) ?? 0 }
                    }
                    address.sin6_scope_id = if_nametoindex(String(fields[9]))
                    gateway = SocketAddress(linux: &address, length: MemoryLayout<sockaddr_in6>.size)
                }
                routes.append(Route(interface: String(fields[9]), gateway: gateway, isIPv6: true))
            }
        }
        return routes
    }

    static func hasNameServer() -> Bool {
        guard let text = read("/etc/resolv.conf") else { return false }
        return text.split(separator: "\n").contains { $0.hasPrefix("nameserver") }
    }

    private static func read(_ path: String) -> String? {
        guard let file = fopen(path, "r") else { return nil }
        defer { fclose(file) }
        var text = ""
        var buffer = [CChar](repeating: 0, count: 4096)
        while fgets(&buffer, Int32(buffer.count), file) != nil { text += String(cString: buffer) }
        return text
    }
}

/// What a path is: a snapshot of the interfaces and routes.
struct PathInfo: Equatable {
    var status: Int32
    var interfaces: [InterfaceInfo]
    var gateways: [SocketAddress] = []
    var hasIPv4 = false
    var hasIPv6 = false
    var hasDNS = false
    var local: SocketAddress?
    var remote: SocketAddress?

    init(status: Int32, interfaces: [InterfaceInfo], local: SocketAddress? = nil, remote: SocketAddress? = nil) {
        self.status = status
        self.interfaces = interfaces
        self.local = local
        self.remote = remote
        if status == PathStatus.satisfied {
            let routes = Routes.defaults()
            let names = Set(interfaces.map(\.name))
            hasIPv4 = routes.contains { !$0.isIPv6 && names.contains($0.interface) } || interfaces.contains { $0.type == InterfaceType.loopback }
            hasIPv6 = routes.contains { $0.isIPv6 && names.contains($0.interface) }
            gateways = routes.filter { names.contains($0.interface) }.compactMap(\.gateway)
            hasDNS = Routes.hasNameServer()
        }
    }

    /// The system's path now, for a monitor that wants `required` (0: any)
    /// and none of `prohibited`.
    static func current(required: Int32, prohibited: [Int32]) -> PathInfo {
        let routes = Routes.defaults()
        let routed = Set(routes.map(\.interface))
        var interfaces = Interfaces.current().filter { interface in
            if prohibited.contains(interface.type) { return false }
            if required != 0 { return interface.type == required }
            return interface.type != InterfaceType.loopback
        }
        interfaces.sort { routed.contains($0.name) && !routed.contains($1.name) }
        let satisfied = required == InterfaceType.loopback ? !interfaces.isEmpty : interfaces.contains { routed.contains($0.name) }
        return PathInfo(status: satisfied ? PathStatus.satisfied : PathStatus.unsatisfied, interfaces: satisfied ? interfaces : [])
    }

    /// A new nw_path_t (+1).
    func object() -> UnsafeMutableRawPointer { NWObjects.make(NWPathObject.objCClass, PathState(self)) }
}

final class PathState: NWState {
    let info: PathInfo
    init(_ info: PathInfo) { self.info = info }
}

@ObjCClass("OS_nw_path")
open class NWPathObject: NWObject {}

final class PathMonitorState: NWState {
    let lock = Lock()
    let requiredType: Int32
    var prohibitedTypes: [Int32] = []
    var queue: UnsafeMutableRawPointer?
    var handler: ObjCBlock?
    var cancelHandler: ObjCBlock?
    var started = false
    var cancelled = false
    var last: PathInfo?

    init(requiredType: Int32) { self.requiredType = requiredType }

    deinit { ObjCRuntime.release(queue) }
}

@ObjCClass("OS_nw_path_monitor")
open class NWPathMonitorObject: NWObject {}

private func monitor(_ object: UnsafeMutableRawPointer?) -> PathMonitorState? { NWObjects.state(object, PathMonitorState.self) }
private func path(_ object: UnsafeMutableRawPointer?) -> PathInfo? { NWObjects.state(object, PathState.self)?.info }

@c(_nw_path_monitor_create)
public func nw_path_monitor_create() -> UnsafeMutableRawPointer? {
    NWObjects.make(NWPathMonitorObject.objCClass, PathMonitorState(requiredType: 0))
}

@c(_nw_path_monitor_create_with_type)
public func nw_path_monitor_create_with_type(_ type: Int32) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWPathMonitorObject.objCClass, PathMonitorState(requiredType: type))
}

/// The wired interfaces an Ethernet channel could use.
@c(_nw_path_monitor_create_for_ethernet_channel)
public func nw_path_monitor_create_for_ethernet_channel() -> UnsafeMutableRawPointer? {
    NWObjects.make(NWPathMonitorObject.objCClass, PathMonitorState(requiredType: InterfaceType.wired))
}

@c(_nw_path_monitor_prohibit_interface_type)
public func nw_path_monitor_prohibit_interface_type(_ object: UnsafeMutableRawPointer?, _ type: Int32) {
    guard let state = monitor(object) else { return }
    state.lock.withLock { state.prohibitedTypes.append(type) }
}

@c(_nw_path_monitor_set_queue)
public func nw_path_monitor_set_queue(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {
    guard let state = monitor(object) else { return }
    let held = ObjCRuntime.retain(queue)
    let old = state.lock.withLock { () -> UnsafeMutableRawPointer? in
        let old = state.queue
        state.queue = held
        return old
    }
    ObjCRuntime.release(old)
}

@c(_nw_path_monitor_set_update_handler)
public func nw_path_monitor_set_update_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = monitor(object) else { return }
    let block = ObjCBlock.from(handler)
    state.lock.withLock { state.handler = block }
}

@c(_nw_path_monitor_set_cancel_handler)
public func nw_path_monitor_set_cancel_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = monitor(object) else { return }
    let block = ObjCBlock.from(handler)
    state.lock.withLock { state.cancelHandler = block }
}

/// Calls the handler if the path changed, then looks again in two seconds,
/// while the monitor is started.
private func checkPath(_ object: UnsafeMutableRawPointer, _ state: PathMonitorState) {
    let (required, prohibited) = state.lock.withLock { (state.requiredType, state.prohibitedTypes) }
    let info = PathInfo.current(required: required, prohibited: prohibited)
    let delivery = state.lock.withLock { () -> (UnsafeMutableRawPointer?, ObjCBlock?)? in
        guard state.started, !state.cancelled else { return nil }
        let changed = state.last != info
        state.last = info
        return (state.queue, changed ? state.handler : nil)
    }
    guard let (queue, handler) = delivery else { return }
    if let handler {
        Dispatch.on(queue) {
            guard !state.lock.withLock({ state.cancelled }) else { return }
            let path = info.object()
            handler.call(path)
            ObjCRuntime.release(path)
        }
    }
    Dispatch.after(2, on: nil) { checkPath(object, state) }
}

@c(_nw_path_monitor_start)
public func nw_path_monitor_start(_ object: UnsafeMutableRawPointer?) {
    guard let object, let state = monitor(object) else { return }
    let start = state.lock.withLock { () -> Bool in
        guard !state.started, !state.cancelled else { return false }
        state.started = true
        return true
    }
    guard start else { return }
    // A started monitor keeps itself until it is cancelled, as on Darwin.
    _ = ObjCRuntime.retain(object)
    checkPath(object, state)
}

@c(_nw_path_monitor_cancel)
public func nw_path_monitor_cancel(_ object: UnsafeMutableRawPointer?) {
    guard let object, let state = monitor(object) else { return }
    let (wasStarted, queue, handler) = state.lock.withLock { () -> (Bool, UnsafeMutableRawPointer?, ObjCBlock?) in
        guard !state.cancelled else { return (false, nil, nil) }
        state.cancelled = true
        let handler = state.cancelHandler
        state.handler = nil
        state.cancelHandler = nil
        return (state.started, state.queue, handler)
    }
    if let handler { Dispatch.on(queue) { handler.call() } }
    if wasStarted { Dispatch.on(queue) { ObjCRuntime.release(object) } }
}

@c(_nw_path_get_status)
public func nw_path_get_status(_ object: UnsafeMutableRawPointer?) -> Int32 { path(object)?.status ?? PathStatus.invalid }

@c(_nw_path_get_unsatisfied_reason)
public func nw_path_get_unsatisfied_reason(_ object: UnsafeMutableRawPointer?) -> Int32 { 0 }

/// Cellular links are expensive; nothing here is constrained.
@c(_nw_path_is_expensive)
public func nw_path_is_expensive(_ object: UnsafeMutableRawPointer?) -> Bool {
    path(object)?.interfaces.first?.type == InterfaceType.cellular
}

@c(_nw_path_is_constrained)
public func nw_path_is_constrained(_ object: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_path_is_ultra_constrained)
public func nw_path_is_ultra_constrained(_ object: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_path_has_ipv4)
public func nw_path_has_ipv4(_ object: UnsafeMutableRawPointer?) -> Bool { path(object)?.hasIPv4 ?? false }

@c(_nw_path_has_ipv6)
public func nw_path_has_ipv6(_ object: UnsafeMutableRawPointer?) -> Bool { path(object)?.hasIPv6 ?? false }

@c(_nw_path_has_dns)
public func nw_path_has_dns(_ object: UnsafeMutableRawPointer?) -> Bool { path(object)?.hasDNS ?? false }

/// nw_link_quality_t: unknown, as Linux doesn't rate links.
@c(_nw_path_get_link_quality)
public func nw_path_get_link_quality(_ object: UnsafeMutableRawPointer?) -> UInt8 { 0 }

@c(_nw_path_uses_interface_type)
public func nw_path_uses_interface_type(_ object: UnsafeMutableRawPointer?, _ type: Int32) -> Bool {
    path(object)?.interfaces.contains { $0.type == type } ?? false
}

@c(_nw_path_enumerate_interfaces)
public func nw_path_enumerate_interfaces(_ object: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let info = path(object), let block = ObjCBlock.from(block) else { return }
    for interface in info.interfaces {
        let made = interface.object()
        let more = block.test(made)
        ObjCRuntime.release(made)
        if !more { break }
    }
}

@c(_nw_path_enumerate_gateways)
public func nw_path_enumerate_gateways(_ object: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard let info = path(object), let block = ObjCBlock.from(block) else { return }
    for gateway in info.gateways {
        let endpoint = Endpoints.make(address: gateway)
        let more = block.test(endpoint)
        ObjCRuntime.release(endpoint)
        if !more { break }
    }
}

@c(_nw_path_copy_effective_local_endpoint)
public func nw_path_copy_effective_local_endpoint(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    path(object)?.local.map { Endpoints.make(address: $0) }
}

@c(_nw_path_copy_effective_remote_endpoint)
public func nw_path_copy_effective_remote_endpoint(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    path(object)?.remote.map { Endpoints.make(address: $0) }
}

@c(_nw_path_is_equal)
public func nw_path_is_equal(_ object: UnsafeMutableRawPointer?, _ other: UnsafeMutableRawPointer?) -> Bool {
    guard let first = path(object), let second = path(other) else { return false }
    return first == second
}
