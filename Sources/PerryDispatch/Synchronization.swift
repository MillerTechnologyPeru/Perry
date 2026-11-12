import CPerryDispatch
import Glibc
import PerryObjCInterop

// Groups, semaphores and time. dispatch_time_t values are Darwin's, as
// Apple's code makes them itself: uptime and monotonic (continuous) times
// in mach ticks, which DarwinTime converts to and from Linux's nanoseconds;
// wall-clock times, DISPATCH_TIME_NOW and DISPATCH_TIME_FOREVER are the
// same on both.

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
public func dispatch_group_wait(_ group: Object?, _ timeout: UInt64.ObjCType) -> Int {
    linux_dispatch_group_wait(Objects.linux(group), DarwinTime.linux(UInt64(objCArgument: timeout)))
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
public func dispatch_semaphore_wait(_ semaphore: Object?, _ timeout: UInt64.ObjCType) -> Int {
    linux_dispatch_semaphore_wait(Objects.linux(semaphore), DarwinTime.linux(UInt64(objCArgument: timeout)))
}

@c(_dispatch_semaphore_signal)
public func dispatch_semaphore_signal(_ semaphore: Object?) -> Int {
    linux_dispatch_semaphore_signal(Objects.linux(semaphore))
}

// MARK: - Time

@c(_dispatch_time)
public func dispatch_time(_ when: UInt64.ObjCType, _ delta: Int64.ObjCType) -> UInt64 {
    DarwinTime.darwin(linux_dispatch_time(DarwinTime.linux(UInt64(objCArgument: when)), Int64(objCArgument: delta)))
}

/// Darwin's dispatch_time_t encoding, which Linux's libdispatch shares but
/// for units: bit 63 alone marks the monotonic (continuous) clock, bits 63
/// and 62 a wall-clock time, kept negated in nanoseconds on both; the rest
/// are uptimes. Darwin keeps uptime and monotonic times in mach ticks,
/// Apple silicon's 125/3 nanoseconds (libPerrySystem's mach_timebase_info),
/// and Swift's concurrency runtime makes its deadlines in them itself;
/// Linux keeps them in nanoseconds. On x86 a tick is a nanosecond, as on
/// Intel Macs, and times are the same on both.
enum DarwinTime {
    static let monotonic: UInt64 = 1 << 63
    static let clocks: UInt64 = 3 << 62
    /// The largest value a time can hold before it reaches the flags.
    static let maximum: UInt64 = (1 << 62) - 1

    static func linux(_ time: UInt64) -> UInt64 {
        #if arch(i386) || arch(x86_64)
        return time
        #else
        convert(time) { ticks in
            let (high, low) = ticks.multipliedFullWidth(by: 125)
            let (quotient, _) = (3 as UInt64).dividingFullWidth((high, low))
            return high >= 3 ? maximum : quotient
        }
        #endif
    }

    static func darwin(_ time: UInt64) -> UInt64 {
        #if arch(i386) || arch(x86_64)
        return time
        #else
        convert(time) { nanoseconds in nanoseconds / 125 * 3 + nanoseconds % 125 * 3 / 125 }
        #endif
    }

    /// An uptime or monotonic time's value converted, its clock kept; a time
    /// too far off to hold is forever.
    private static func convert(_ time: UInt64, _ value: (UInt64) -> UInt64) -> UInt64 {
        guard time != 0, time != ~0, time & clocks != clocks else { return time }
        let converted = value(time & ~clocks)
        guard converted <= maximum else { return ~0 }
        return converted | (time & monotonic)
    }
}

@c(_dispatch_walltime)
public func dispatch_walltime(_ when: UnsafePointer<timespec>?, _ delta: Int64.ObjCType) -> UInt64 {
    linux_dispatch_walltime(when, Int64(objCArgument: delta))
}

// MARK: - Once

/// libSystem's: one implementation, whichever library an image binds.
@_cdecl("_dispatch_once")
public func dispatch_once(_ predicate: UnsafeMutablePointer<Int>?, _ block: UnsafeMutableRawPointer?) {
    Runtime.once(predicate, block)
}

@_cdecl("_dispatch_once_f")
public func dispatch_once_f(_ predicate: UnsafeMutablePointer<Int>?, _ context: UnsafeMutableRawPointer?,
                            _ function: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) {
    Runtime.onceFunction(predicate, context, function)
}
