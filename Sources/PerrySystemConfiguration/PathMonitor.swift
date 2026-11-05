import Glibc
import PerryObjCInterop

// Network.framework's path monitor, over the same routing table as
// SCNetworkReachability: a path is satisfied while a default route is up,
// over one interface, Wi-Fi (there is no cellular data, and apps treat
// Wi-Fi as unmetered). A started monitor calls its update handler once, on
// its queue, and again when the status changes; it is checked every two
// seconds. Monitors, paths and interfaces are objects, as nw_retain and
// ARC expect.

/// nw_path_status_t: satisfied 1, unsatisfied 2.
private func currentStatus() -> Int32 { Routes.hasDefaultRoute() ? 1 : 2 }

final class PathMonitorState: @unchecked Sendable {
    let lock = Lock()
    var queue: UnsafeMutableRawPointer?
    var handler: ObjCBlock?
    var cancelHandler: ObjCBlock?
    var started = false
    var cancelled = false
    var lastStatus: Int32?
}

final class PathState: @unchecked Sendable {
    let status: Int32
    init(status: Int32) { self.status = status }
}

@ObjCClass("OS_nw_path_monitor")
open class NWPathMonitorObject: NSObject {
    static let states = StateTable<PathMonitorState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        NWPathMonitorObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NWPathMonitorObject.objCClass.pointer)
    }
}

@ObjCClass("OS_nw_path")
open class NWPathObject: NSObject {
    static let states = StateTable<PathState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        NWPathObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NWPathObject.objCClass.pointer)
    }
}

/// The one interface a satisfied path uses.
@ObjCClass("OS_nw_interface")
open class NWInterfaceObject: NSObject {}

private func makePath(status: Int32) -> UnsafeMutableRawPointer? {
    let object = NSObject(NWPathObject.objCClass.pointer).newInstance()
    NWPathObject.states.set(object.objcObject, PathState(status: status))
    return object.objCOwnedReturnValue()
}

/// A new monitor, owned by the caller.
@c(_nw_path_monitor_create)
public func nw_path_monitor_create() -> UnsafeMutableRawPointer? {
    let object = NSObject(NWPathMonitorObject.objCClass.pointer).newInstance()
    NWPathMonitorObject.states.set(object.objcObject, PathMonitorState())
    return object.objCOwnedReturnValue()
}

/// A monitor for one interface type: the same, as there is one interface.
@c(_nw_path_monitor_create_with_type)
public func nw_path_monitor_create_with_type(_ type: Int32) -> UnsafeMutableRawPointer? { nw_path_monitor_create() }

@c(_nw_path_monitor_set_queue)
public func nw_path_monitor_set_queue(_ monitor: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {
    guard let state = NWPathMonitorObject.states[monitor] else { return }
    let held = ObjCRuntime.retain(queue)
    state.lock.withLock { state.queue = held }
}

@c(_nw_path_monitor_set_update_handler)
public func nw_path_monitor_set_update_handler(_ monitor: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = NWPathMonitorObject.states[monitor] else { return }
    let block = handler.map { ObjCBlock(objCArgument: $0) }
    state.lock.withLock { state.handler = block }
}

@c(_nw_path_monitor_set_cancel_handler)
public func nw_path_monitor_set_cancel_handler(_ monitor: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = NWPathMonitorObject.states[monitor] else { return }
    let block = handler.map { ObjCBlock(objCArgument: $0) }
    state.lock.withLock { state.cancelHandler = block }
}

/// Calls the handler if the status changed, then checks again in two
/// seconds, while the monitor is started and alive.
private func checkPath(_ monitor: UnsafeMutableRawPointer, _ state: PathMonitorState) {
    let status = currentStatus()
    let delivery = state.lock.withLock { () -> (UnsafeMutableRawPointer?, ObjCBlock?)? in
        guard state.started, !state.cancelled else { return nil }
        let changed = state.lastStatus != status
        state.lastStatus = status
        return (state.queue, changed ? state.handler : nil)
    }
    guard let (queue, handler) = delivery else { return }
    if let handler {
        Dispatch.on(queue) {
            guard !state.lock.withLock({ state.cancelled }), let path = makePath(status: status) else { return }
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
            handler.function(as: Invoke.self)(handler.object, path)
            ObjCRuntime.release(path)
        }
    }
    // The monitor is kept while it is checked, as a started one is on Darwin.
    Dispatch.after(2) { checkPath(monitor, state) }
}

@c(_nw_path_monitor_start)
public func nw_path_monitor_start(_ monitor: UnsafeMutableRawPointer?) {
    guard let monitor, let state = NWPathMonitorObject.states[monitor] else { return }
    let start = state.lock.withLock { () -> Bool in
        guard !state.started, !state.cancelled else { return false }
        state.started = true
        return true
    }
    guard start else { return }
    _ = ObjCRuntime.retain(monitor)
    checkPath(monitor, state)
}

@c(_nw_path_monitor_cancel)
public func nw_path_monitor_cancel(_ monitor: UnsafeMutableRawPointer?) {
    guard let monitor, let state = NWPathMonitorObject.states[monitor] else { return }
    let (wasStarted, queue, handler) = state.lock.withLock { () -> (Bool, UnsafeMutableRawPointer?, ObjCBlock?) in
        guard !state.cancelled else { return (false, nil, nil) }
        state.cancelled = true
        let handler = state.cancelHandler
        state.handler = nil
        state.cancelHandler = nil
        return (state.started, state.queue, handler)
    }
    if let handler {
        Dispatch.on(queue) {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            handler.function(as: Invoke.self)(handler.object)
        }
    }
    if wasStarted { ObjCRuntime.release(monitor) }
}

/// nw_path_status_t: invalid 0 for what is not a path.
@c(_nw_path_get_status)
public func nw_path_get_status(_ path: UnsafeMutableRawPointer?) -> Int32 { NWPathObject.states[path]?.status ?? 0 }

/// Wi-Fi is neither expensive nor constrained.
@c(_nw_path_is_expensive)
public func nw_path_is_expensive(_ path: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_path_is_constrained)
public func nw_path_is_constrained(_ path: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_path_has_ipv4)
public func nw_path_has_ipv4(_ path: UnsafeMutableRawPointer?) -> Bool { NWPathObject.states[path]?.status == 1 }

@c(_nw_path_has_ipv6)
public func nw_path_has_ipv6(_ path: UnsafeMutableRawPointer?) -> Bool { false }

@c(_nw_path_has_dns)
public func nw_path_has_dns(_ path: UnsafeMutableRawPointer?) -> Bool { NWPathObject.states[path]?.status == 1 }

/// nw_interface_type_t: Wi-Fi 1.
@c(_nw_path_uses_interface_type)
public func nw_path_uses_interface_type(_ path: UnsafeMutableRawPointer?, _ type: Int32) -> Bool {
    NWPathObject.states[path]?.status == 1 && type == 1
}

/// The block is called with a satisfied path's interface, until it
/// returns false.
@c(_nw_path_enumerate_interfaces)
public func nw_path_enumerate_interfaces(_ path: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {
    guard NWPathObject.states[path]?.status == 1, let block else { return }
    let interface = NSObject(NWInterfaceObject.objCClass.pointer).newInstance()
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Bool
    let invoke = unsafeBitCast(block.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Invoke.self)
    _ = invoke(block, interface.objcObject)
}

@c(_nw_interface_get_type)
public func nw_interface_get_type(_ interface: UnsafeMutableRawPointer?) -> Int32 { interface == nil ? 0 : 1 }

nonisolated(unsafe) private let interfaceName = strdup("wlan0")

@c(_nw_interface_get_name)
public func nw_interface_get_name(_ interface: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? { UnsafePointer(interfaceName) }

@c(_nw_interface_get_index)
public func nw_interface_get_index(_ interface: UnsafeMutableRawPointer?) -> UInt32 { 1 }

@c(_nw_retain)
public func nw_retain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(object) }

@c(_nw_release)
public func nw_release(_ object: UnsafeMutableRawPointer?) {
    if let object { ObjCRuntime.release(object) }
}

/// Paths have no endpoints: they lead to no particular host.
@c(_nw_path_copy_effective_local_endpoint)
public func nw_path_copy_effective_local_endpoint(_ path: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_nw_path_copy_effective_remote_endpoint)
public func nw_path_copy_effective_remote_endpoint(_ path: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

/// Paths with the same status are the same: they use the same interface.
@c(_nw_path_is_equal)
public func nw_path_is_equal(_ path: UnsafeMutableRawPointer?, _ other: UnsafeMutableRawPointer?) -> Bool {
    NWPathObject.states[path]?.status == NWPathObject.states[other]?.status
}

/// nw_path_unsatisfied_reason_t: not available 0.
@c(_nw_path_get_unsatisfied_reason)
public func nw_path_get_unsatisfied_reason(_ path: UnsafeMutableRawPointer?) -> Int32 { 0 }

/// No gateways are listed.
@c(_nw_path_enumerate_gateways)
public func nw_path_enumerate_gateways(_ path: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {}

/// The one interface, by its index or name.
@c(_nw_interface_create_with_index)
public func nw_interface_create_with_index(_ index: UInt32) -> UnsafeMutableRawPointer? {
    index == 1 ? NSObject(NWInterfaceObject.objCClass.pointer).newInstance().objCOwnedReturnValue() : nil
}

@c(_nw_interface_create_with_name)
public func nw_interface_create_with_name(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name, let interfaceName, strcmp(name, interfaceName) == 0 else { return nil }
    return NSObject(NWInterfaceObject.objCClass.pointer).newInstance().objCOwnedReturnValue()
}
