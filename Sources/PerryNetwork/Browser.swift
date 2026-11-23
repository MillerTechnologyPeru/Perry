import Glibc
import PerryObjCInterop

// Network.framework's browser, which looks for Bonjour services: here none
// is ever found. A started browser says it is ready, on its queue, and its
// results never change; the descriptor it was made with can be read back.

final class BrowseDescriptorState: NWState {
    let type: HeldCString
    let domain: HeldCString
    let applicationService: HeldCString
    var includeTXTRecord = false

    init(type: String?, domain: String?, applicationService: String? = nil) {
        self.type = HeldCString(type)
        self.domain = HeldCString(domain)
        self.applicationService = HeldCString(applicationService)
    }
}

@ObjCClass("OS_nw_browse_descriptor")
open class NWBrowseDescriptorObject: NWObject {}

final class BrowserState: NWState {
    let lock = Lock()
    let descriptor: UnsafeMutableRawPointer?
    let parameters: UnsafeMutableRawPointer?
    var queue: UnsafeMutableRawPointer?
    var stateHandler: ObjCBlock?
    var resultsHandler: ObjCBlock?
    var started = false
    var cancelled = false

    init(descriptor: UnsafeMutableRawPointer?, parameters: UnsafeMutableRawPointer?) {
        self.descriptor = ObjCRuntime.retain(descriptor)
        self.parameters = ObjCRuntime.retain(parameters)
    }

    deinit {
        ObjCRuntime.release(descriptor)
        ObjCRuntime.release(parameters)
        ObjCRuntime.release(queue)
    }
}

@ObjCClass("OS_nw_browser")
open class NWBrowserObject: NWObject {}

/// A result: never made, as nothing is found.
@ObjCClass("OS_nw_browse_result")
open class NWBrowseResultObject: NWObject {}

private func descriptor(_ object: UnsafeMutableRawPointer?) -> BrowseDescriptorState? { NWObjects.state(object, BrowseDescriptorState.self) }
private func browser(_ object: UnsafeMutableRawPointer?) -> BrowserState? { NWObjects.state(object, BrowserState.self) }

@c(_nw_browse_descriptor_create_bonjour_service)
public func nw_browse_descriptor_create_bonjour_service(_ type: UnsafePointer<CChar>?, _ domain: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWBrowseDescriptorObject.objCClass,
                   BrowseDescriptorState(type: type.map { String(cString: $0) }, domain: domain.map { String(cString: $0) }))
}

@c(_nw_browse_descriptor_create_application_service)
public func nw_browse_descriptor_create_application_service(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWBrowseDescriptorObject.objCClass,
                   BrowseDescriptorState(type: nil, domain: nil, applicationService: name.map { String(cString: $0) }))
}

@c(_nw_browse_descriptor_get_bonjour_service_type)
public func nw_browse_descriptor_get_bonjour_service_type(_ object: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    descriptor(object)?.type.value
}

@c(_nw_browse_descriptor_get_bonjour_service_domain)
public func nw_browse_descriptor_get_bonjour_service_domain(_ object: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    descriptor(object)?.domain.value
}

@c(_nw_browse_descriptor_get_application_service_name)
public func nw_browse_descriptor_get_application_service_name(_ object: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    descriptor(object)?.applicationService.value
}

@c(_nw_browse_descriptor_set_include_txt_record)
public func nw_browse_descriptor_set_include_txt_record(_ object: UnsafeMutableRawPointer?, _ include: Bool) {
    descriptor(object)?.includeTXTRecord = include
}

@c(_nw_browse_descriptor_get_include_txt_record)
public func nw_browse_descriptor_get_include_txt_record(_ object: UnsafeMutableRawPointer?) -> Bool {
    descriptor(object)?.includeTXTRecord ?? false
}

@c(_nw_browser_create)
public func nw_browser_create(_ descriptor: UnsafeMutableRawPointer?, _ parameters: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NWObjects.make(NWBrowserObject.objCClass, BrowserState(descriptor: descriptor, parameters: parameters))
}

@c(_nw_browser_copy_browse_descriptor)
public func nw_browser_copy_browse_descriptor(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(browser(object)?.descriptor)
}

@c(_nw_browser_copy_parameters)
public func nw_browser_copy_parameters(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(browser(object)?.parameters)
}

@c(_nw_browser_set_queue)
public func nw_browser_set_queue(_ object: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {
    guard let state = browser(object) else { return }
    let held = ObjCRuntime.retain(queue)
    let old = state.lock.withLock { () -> UnsafeMutableRawPointer? in
        let old = state.queue
        state.queue = held
        return old
    }
    ObjCRuntime.release(old)
}

@c(_nw_browser_set_state_changed_handler)
public func nw_browser_set_state_changed_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = browser(object) else { return }
    let block = ObjCBlock.from(handler)
    state.lock.withLock { state.stateHandler = block }
}

/// The results never change, so the handler is kept and never called.
@c(_nw_browser_set_browse_results_changed_handler)
public func nw_browser_set_browse_results_changed_handler(_ object: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?) {
    guard let state = browser(object) else { return }
    let block = ObjCBlock.from(handler)
    state.lock.withLock { state.resultsHandler = block }
}

/// nw_browser_state_t: ready 1, cancelled 3.
private func report(_ state: BrowserState, _ browserState: Int32) {
    let (queue, handler) = state.lock.withLock { (state.queue, state.stateHandler) }
    guard let handler else { return }
    Dispatch.on(queue) { handler.call(state: browserState, nil) }
}

@c(_nw_browser_start)
public func nw_browser_start(_ object: UnsafeMutableRawPointer?) {
    guard let state = browser(object) else { return }
    let start = state.lock.withLock { () -> Bool in
        guard !state.started, !state.cancelled else { return false }
        state.started = true
        return true
    }
    if start { report(state, 1) }
}

@c(_nw_browser_cancel)
public func nw_browser_cancel(_ object: UnsafeMutableRawPointer?) {
    guard let state = browser(object) else { return }
    let cancel = state.lock.withLock { () -> Bool in
        guard !state.cancelled else { return false }
        state.cancelled = true
        return true
    }
    if cancel { report(state, 3) }
}

@c(_nw_browse_result_copy_endpoint)
public func nw_browse_result_copy_endpoint(_ result: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_nw_browse_result_copy_txt_record_object)
public func nw_browse_result_copy_txt_record_object(_ result: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_nw_browse_result_enumerate_interfaces)
public func nw_browse_result_enumerate_interfaces(_ result: UnsafeMutableRawPointer?, _ block: UnsafeMutableRawPointer?) {}

@c(_nw_browse_result_get_interfaces_count)
public func nw_browse_result_get_interfaces_count(_ result: UnsafeMutableRawPointer?) -> Int { 0 }

@c(_nw_browse_result_get_changes)
public func nw_browse_result_get_changes(_ old: UnsafeMutableRawPointer?, _ new: UnsafeMutableRawPointer?) -> UInt64 { 0 }
