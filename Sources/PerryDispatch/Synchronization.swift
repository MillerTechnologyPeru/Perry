import CPerryDispatch
import Glibc

// Groups, semaphores and time. dispatch_time_t values pass through as
// Linux's: nanoseconds of uptime, negative for wall-clock times, with
// DISPATCH_TIME_NOW 0 and DISPATCH_TIME_FOREVER ~0 as on Darwin.

// MARK: - Groups

@c(_dispatch_group_create)
public func dispatch_group_create() -> Object? {
    linux_dispatch_group_create().map { Objects.make(Classes.group, linux: $0) }
}

@c(_dispatch_group_enter)
public func dispatch_group_enter(_ group: Object?) {
    linux_dispatch_group_enter(Objects.linux(group))
}

@c(_dispatch_group_leave)
public func dispatch_group_leave(_ group: Object?) {
    linux_dispatch_group_leave(Objects.linux(group))
}

@c(_dispatch_group_wait)
public func dispatch_group_wait(_ group: Object?, _ timeout: UInt64) -> Int {
    linux_dispatch_group_wait(Objects.linux(group), timeout)
}

@c(_dispatch_group_async)
public func dispatch_group_async(_ group: Object?, _ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    linux_dispatch_group_async_f(Objects.linux(group), Objects.linux(queue), Blocks.copy(block), Blocks.runOnce)
}

@c(_dispatch_group_async_f)
public func dispatch_group_async_f(_ group: Object?, _ queue: Object?, _ context: UnsafeMutableRawPointer?,
                                   _ work: Function?) {
    guard let work else { dispatchFatal("dispatch_group_async_f called with a NULL function") }
    let (call, run) = Blocks.pooled(context, work)
    linux_dispatch_group_async_f(Objects.linux(group), Objects.linux(queue), call, run)
}

@c(_dispatch_group_notify)
public func dispatch_group_notify(_ group: Object?, _ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    linux_dispatch_group_notify_f(Objects.linux(group), Objects.linux(queue), Blocks.copy(block), Blocks.runOnce)
}

@c(_dispatch_group_notify_f)
public func dispatch_group_notify_f(_ group: Object?, _ queue: Object?, _ context: UnsafeMutableRawPointer?,
                                    _ work: Function?) {
    guard let work else { dispatchFatal("dispatch_group_notify_f called with a NULL function") }
    let (call, run) = Blocks.pooled(context, work)
    linux_dispatch_group_notify_f(Objects.linux(group), Objects.linux(queue), call, run)
}

// MARK: - Semaphores

@c(_dispatch_semaphore_create)
public func dispatch_semaphore_create(_ value: Int) -> Object? {
    linux_dispatch_semaphore_create(value).map { Objects.make(Classes.semaphore, linux: $0) }
}

@c(_dispatch_semaphore_wait)
public func dispatch_semaphore_wait(_ semaphore: Object?, _ timeout: UInt64) -> Int {
    linux_dispatch_semaphore_wait(Objects.linux(semaphore), timeout)
}

@c(_dispatch_semaphore_signal)
public func dispatch_semaphore_signal(_ semaphore: Object?) -> Int {
    linux_dispatch_semaphore_signal(Objects.linux(semaphore))
}

// MARK: - Time

@c(_dispatch_time)
public func dispatch_time(_ when: UInt64, _ delta: Int64) -> UInt64 {
    linux_dispatch_time(when, delta)
}

@c(_dispatch_walltime)
public func dispatch_walltime(_ when: UnsafePointer<timespec>?, _ delta: Int64) -> UInt64 {
    linux_dispatch_walltime(when, delta)
}
