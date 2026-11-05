import CPerryDispatch
import PerryObjCInterop

// Sources. A source's handlers are set through the _f variants, which pass
// the Linux source's context: that context is the source's Swift state,
// which holds the handlers, Darwin blocks or functions, and the context and
// finalizer the program set. The state lives until Linux finalizes the
// source, as the source may fire after the program's last release.

final class SourceState {
    enum Handler {
        case block(UnsafeMutableRawPointer)
        case function(Function)
    }

    enum Kind: Int {
        case event, cancel, registration
    }

    private let lock = Lock()
    private var handlers: [Kind: Handler] = [:]
    var context: UnsafeMutableRawPointer?
    var finalizer: Function?
    /// A signal source's Darwin signal number, which Linux's differs from.
    var signal: UInt?

    deinit {
        for case .block(let block) in handlers.values { Runtime.blockRelease(block) }
    }

    func set(_ kind: Kind, _ handler: Handler?) {
        let old = lock.withLock {
            let old = handlers[kind]
            handlers[kind] = handler
            return old
        }
        if case .block(let block) = old { Runtime.blockRelease(block) }
    }

    /// Runs a handler, holding its block while it runs.
    func fire(_ kind: Kind) {
        let handler: Handler? = lock.withLock {
            guard let handler = handlers[kind] else { return nil }
            if case .block(let block) = handler { return .block(Blocks.copy(block)) }
            return handler
        }
        switch handler {
        case .block(let block):
            ObjCRuntime.autoreleasepool { Blocks.invoke(block) }
            Runtime.blockRelease(block)
        case .function(let function):
            ObjCRuntime.autoreleasepool { function(context) }
        case nil:
            break
        }
    }

    static func from(_ context: UnsafeMutableRawPointer?) -> SourceState? {
        context.map { Unmanaged<SourceState>.fromOpaque($0).takeUnretainedValue() }
    }

    static let event: Function = { SourceState.from($0)?.fire(.event) }
    static let cancel: Function = { SourceState.from($0)?.fire(.cancel) }
    static let registration: Function = { SourceState.from($0)?.fire(.registration) }

    /// The Linux source's finalizer: the program's, then the state's
    /// reference goes.
    static let finalize: Function = { context in
        guard let context else { return }
        let state = Unmanaged<SourceState>.fromOpaque(context)
        let source = state.takeUnretainedValue()
        if let finalizer = source.finalizer { finalizer(source.context) }
        state.release()
    }
}

/// Darwin's signal numbers on Linux, for DISPATCH_SOURCE_TYPE_SIGNAL.
/// SIGEMT and SIGINFO have no Linux counterpart.
private func linuxSignal(_ darwin: UInt) -> UInt? {
    switch darwin {
    case 1...6, 8, 9, 11, 13, 14, 15, 21, 22, 24...28: return darwin
    case 10: return 7      // SIGBUS
    case 12: return 31     // SIGSYS
    case 16: return 23     // SIGURG
    case 17: return 19     // SIGSTOP
    case 18: return 20     // SIGTSTP
    case 19: return 18     // SIGCONT
    case 20: return 17     // SIGCHLD
    case 23: return 29     // SIGIO
    case 30: return 10     // SIGUSR1
    case 31: return 12     // SIGUSR2
    default: return nil
    }
}

/// NULL for the types Linux lacks: Mach ports, memory pressure, processes
/// and vnodes.
@c(_dispatch_source_create)
public func dispatch_source_create(_ type: UnsafeRawPointer?, _ handle: UInt, _ mask: UInt, _ queue: Object?) -> Object? {
    let kind = perry_dispatch_source_kind(type)
    guard kind >= 0, let linuxType = perry_linux_source_type(kind) else { return nil }
    let darwinHandle = handle
    var handle = handle
    if kind == Int32(PERRY_SOURCE_SIGNAL.rawValue) {
        guard let signal = linuxSignal(handle) else { return nil }
        handle = signal
    }
    guard let linux = linux_dispatch_source_create(linuxType, handle, mask, Objects.linux(queue)) else { return nil }
    let state = SourceState()
    if kind == Int32(PERRY_SOURCE_SIGNAL.rawValue) { state.signal = darwinHandle }
    linux_dispatch_set_context(linux, Unmanaged.passRetained(state).toOpaque())
    linux_dispatch_set_finalizer_f(linux, SourceState.finalize)
    return Objects.make(Classes.source, linux: linux, state: state)
}

private func setHandler(_ source: Object?, _ kind: SourceState.Kind, _ handler: SourceState.Handler?,
                        _ install: (UnsafeMutableRawPointer?, Function?) -> Void, _ function: Function) {
    guard let state = Objects.state(source, as: SourceState.self) else { return }
    state.set(kind, handler)
    install(Objects.linux(source), handler == nil ? nil : function)
}

@c(_dispatch_source_set_event_handler)
public func dispatch_source_set_event_handler(_ source: Object?, _ block: UnsafeMutableRawPointer?) {
    setHandler(source, .event, block.map { .block(Blocks.copy($0)) }, linux_dispatch_source_set_event_handler_f,
               SourceState.event)
}

@c(_dispatch_source_set_event_handler_f)
public func dispatch_source_set_event_handler_f(_ source: Object?, _ handler: Function?) {
    setHandler(source, .event, handler.map { .function($0) }, linux_dispatch_source_set_event_handler_f,
               SourceState.event)
}

@c(_dispatch_source_set_cancel_handler)
public func dispatch_source_set_cancel_handler(_ source: Object?, _ block: UnsafeMutableRawPointer?) {
    setHandler(source, .cancel, block.map { .block(Blocks.copy($0)) }, linux_dispatch_source_set_cancel_handler_f,
               SourceState.cancel)
}

@c(_dispatch_source_set_cancel_handler_f)
public func dispatch_source_set_cancel_handler_f(_ source: Object?, _ handler: Function?) {
    setHandler(source, .cancel, handler.map { .function($0) }, linux_dispatch_source_set_cancel_handler_f,
               SourceState.cancel)
}

@c(_dispatch_source_set_registration_handler)
public func dispatch_source_set_registration_handler(_ source: Object?, _ block: UnsafeMutableRawPointer?) {
    setHandler(source, .registration, block.map { .block(Blocks.copy($0)) },
               linux_dispatch_source_set_registration_handler_f, SourceState.registration)
}

@c(_dispatch_source_set_registration_handler_f)
public func dispatch_source_set_registration_handler_f(_ source: Object?, _ handler: Function?) {
    setHandler(source, .registration, handler.map { .function($0) },
               linux_dispatch_source_set_registration_handler_f, SourceState.registration)
}

@c(_dispatch_source_cancel)
public func dispatch_source_cancel(_ source: Object?) {
    linux_dispatch_source_cancel(Objects.linux(source))
}

@c(_dispatch_source_testcancel)
public func dispatch_source_testcancel(_ source: Object?) -> Int {
    linux_dispatch_source_testcancel(Objects.linux(source))
}

@c(_dispatch_source_get_data)
public func dispatch_source_get_data(_ source: Object?) -> UInt {
    linux_dispatch_source_get_data(Objects.linux(source))
}

@c(_dispatch_source_get_handle)
public func dispatch_source_get_handle(_ source: Object?) -> UInt {
    Objects.state(source, as: SourceState.self)?.signal ?? linux_dispatch_source_get_handle(Objects.linux(source))
}

@c(_dispatch_source_get_mask)
public func dispatch_source_get_mask(_ source: Object?) -> UInt {
    linux_dispatch_source_get_mask(Objects.linux(source))
}

@c(_dispatch_source_merge_data)
public func dispatch_source_merge_data(_ source: Object?, _ value: UInt) {
    linux_dispatch_source_merge_data(Objects.linux(source), value)
}

@c(_dispatch_source_set_timer)
public func dispatch_source_set_timer(_ source: Object?, _ start: UInt64.ObjCType, _ interval: UInt64.ObjCType,
                                      _ leeway: UInt64.ObjCType) {
    linux_dispatch_source_set_timer(Objects.linux(source), UInt64(objCArgument: start), UInt64(objCArgument: interval),
                                    UInt64(objCArgument: leeway))
}
