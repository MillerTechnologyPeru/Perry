import Glibc
import PerryObjCInterop

// Network.framework's browser, which looks for Bonjour services: here none
// is ever found. A started browser says it is ready, on its queue, and its
// results never change; the descriptor it was made with can be read back.

final class BrowseDescriptorState: @unchecked Sendable {
    let type: UnsafeMutablePointer<CChar>?
    let domain: UnsafeMutablePointer<CChar>?

    init(type: UnsafePointer<CChar>?, domain: UnsafePointer<CChar>?) {
        self.type = type.flatMap { strdup($0) }
        self.domain = domain.flatMap { strdup($0) }
    }

    deinit {
        free(type)
        free(domain)
    }
}

final class BrowserState: @unchecked Sendable {
    let lock = Lock()
    var descriptor: UnsafeMutableRawPointer?
    var queue: UnsafeMutableRawPointer?
    var stateHandler: ObjCBlock?
    var started = false
    var cancelled = false
}

@ObjCClass("OS_nw_browse_descriptor")
open class NWBrowseDescriptorObject: NSObject {
    static let states = StateTable<BrowseDescriptorState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        NWBrowseDescriptorObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NWBrowseDescriptorObject.objCClass.pointer)
    }
}

@ObjCClass("OS_nw_browser")
open class NWBrowserObject: NSObject {
    static let states = StateTable<BrowserState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        if let descriptor = NWBrowserObject.states[objcObject]?.descriptor { ObjCRuntime.release(descriptor) }
        NWBrowserObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NWBrowserObject.objCClass.pointer)
    }
}

/// An endpoint or a browse result: neither is made, here.
@ObjCClass("OS_nw_endpoint")
open class NWEndpointObject: NSObject {}

@c(_nw_browse_descriptor_create_bonjour_service)
public func nw_browse_descriptor_create_bonjour_service(_ type: UnsafePointer<CChar>?, _ domain: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    let object = NSObject(NWBrowseDescriptorObject.objCClass.pointer).newInstance()
    NWBrowseDescriptorObject.states.set(object.objcObject, BrowseDescriptorState(type: type, domain: domain))
    return object.objCOwnedReturnValue()
}

@c(_nw_browse_descriptor_get_bonjour_service_type)
public func nw_browse_descriptor_get_bonjour_service_type(_ descriptor: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    NWBrowseDescriptorObject.states[descriptor]?.type.map { UnsafePointer($0) }
}

@c(_nw_browse_descriptor_get_bonjour_service_domain)
public func nw_browse_descriptor_get_bonjour_service_domain(_ descriptor: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    NWBrowseDescriptorObject.states[descriptor]?.domain.map { UnsafePointer($0) }
}

@c(_nw_browser_create)
public func nw_browser_create(_ descriptor: UnsafeMutableRawPointer?, _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let object = NSObject(NWBrowserObject.objCClass.pointer).newInstance()
    let state = BrowserState()
    state.descriptor = ObjCRuntime.retain(descriptor)
    NWBrowserObject.states.set(object.objcObject, state)
    return object.objCOwnedReturnValue()
}

@c(_nw_browser_copy_browse_descriptor)
public func nw_browser_copy_browse_descriptor(_ browser: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(NWBrowserObject.states[browser]?.descriptor)
}

@c(_nw_browser_set_queue)
public func nw_browser_set_queue(_ browser: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {
    guard let state = NWBrowserObject.states[browser] else { return }
    let held = ObjCRuntime.retain(queue)
    state.lock.withLock { state.queue = held }
}

@c(_nw_browser_set_state_changed_handler)
public func nw_browser_set_state_changed_handler(_ browser: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = NWBrowserObject.states[browser] else { return }
    let block = handler.map { ObjCBlock(objCArgument: $0) }
    state.lock.withLock { state.stateHandler = block }
}

/// The results never change, so the handler is kept and never called.
@c(_nw_browser_set_browse_results_changed_handler)
public func nw_browser_set_browse_results_changed_handler(_ browser: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {}

/// nw_browser_state_t: ready 1, cancelled 3.
private func report(_ state: BrowserState, _ browserState: Int32) {
    let delivery = state.lock.withLock { (state.queue, state.stateHandler) }
    guard let handler = delivery.1 else { return }
    Dispatch.on(delivery.0) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int32, UnsafeMutableRawPointer?) -> Void
        handler.function(as: Invoke.self)(handler.object, browserState, nil)
    }
}

@c(_nw_browser_start)
public func nw_browser_start(_ browser: UnsafeMutableRawPointer?) {
    guard let browser, let state = NWBrowserObject.states[browser] else { return }
    let start = state.lock.withLock { () -> Bool in
        guard !state.started, !state.cancelled else { return false }
        state.started = true
        return true
    }
    guard start else { return }
    report(state, 1)
}

@c(_nw_browser_cancel)
public func nw_browser_cancel(_ browser: UnsafeMutableRawPointer?) {
    guard let state = NWBrowserObject.states[browser] else { return }
    let cancel = state.lock.withLock { () -> Bool in
        guard !state.cancelled else { return false }
        state.cancelled = true
        return true
    }
    if cancel { report(state, 3) }
}

@c(_nw_browse_result_copy_endpoint)
public func nw_browse_result_copy_endpoint(_ result: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_nw_browse_result_get_changes)
public func nw_browse_result_get_changes(_ old: UnsafeMutableRawPointer?, _ new: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_nw_endpoint_get_type)
public func nw_endpoint_get_type(_ endpoint: UnsafeMutableRawPointer?) -> Int32 { 0 }

@c(_nw_endpoint_get_bonjour_service_name)
public func nw_endpoint_get_bonjour_service_name(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? { nil }

@c(_nw_endpoint_get_bonjour_service_type)
public func nw_endpoint_get_bonjour_service_type(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? { nil }

@c(_nw_endpoint_get_bonjour_service_domain)
public func nw_endpoint_get_bonjour_service_domain(_ endpoint: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? { nil }

/// A host endpoint: an object that stands for it, with nothing to read from it.
@c(_nw_endpoint_create_host)
public func nw_endpoint_create_host(_ host: UnsafePointer<CChar>?, _ port: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    NSObject(NWEndpointObject.objCClass.pointer).newInstance().objCOwnedReturnValue()
}
