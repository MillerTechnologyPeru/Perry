import CPerryDispatch
import PerryObjCInterop
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The autorelease pool of the blocks a worker thread runs. Darwin's
/// libdispatch keeps one pool across a drain of a queue, so an autoreleased
/// object one block made lives into the blocks after it, and programs rely on
/// that (a string one block formats and the next uses without a retain). A
/// pool per block frees it between them. This keeps the thread's pool across
/// blocks and pops it when the blocks that follow arrive after a gap or it has
/// held objects for a while, which is where a drain would have ended.
enum DrainPool {
    private final class State {
        var pool: UnsafeMutableRawPointer?
        var touched: UInt64 = 0
        var born: UInt64 = 0
    }

    /// How long a pool may sit unused before the next block starts a new one,
    /// and the longest it is kept at all, in nanoseconds.
    private static let gap: UInt64 = 5_000_000
    private static let limit: UInt64 = 100_000_000

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { raw in
            if let raw { Unmanaged<State>.fromOpaque(UnsafeRawPointer(raw)).release() }
        }
        return key
    }()

    private static func now() -> UInt64 {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
    }

    private static func state() -> State {
        if let raw = pthread_getspecific(key) { return Unmanaged<State>.fromOpaque(raw).takeUnretainedValue() }
        let state = State()
        pthread_setspecific(key, Unmanaged.passRetained(state).toOpaque())
        return state
    }

    static func run<Result>(_ body: () -> Result) -> Result {
        let state = state()
        let start = now()
        if state.pool != nil, start - state.touched > gap || start - state.born > limit {
            ObjCRuntime.poolFunctions.pop(state.pool)
            state.pool = nil
        }
        if state.pool == nil {
            state.pool = ObjCRuntime.poolFunctions.push()
            state.born = start
        }
        defer { state.touched = now() }
        return body()
    }
}

// Queues: each Darwin queue stands for a Linux queue, which does the work.
// Blocks are copied with Darwin's _Block_copy and run by the _f variants
// through a function that invokes and releases them, in an autorelease
// pool as Darwin's worker threads drain one per item. Each function
// libdispatch calls keeps the registers Linux's code expects kept
// (keepingLinuxRegisters) around the Darwin code it runs.

enum Blocks {
    /// The block's invoke function, which takes the block first.
    @inline(__always)
    static func invoke(_ block: UnsafeMutableRawPointer) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: Invoke.self)(block)
    }

    /// A heap copy of a block (+1).
    @inline(__always)
    static func copy(_ block: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        guard let block, let copy = Runtime.blockCopy(block) else { dispatchFatal("the block is NULL") }
        return copy
    }

    /// Runs a copied block once and releases it.
    static let runOnce: Function = { block in
        guard let block else { return }
        keepingLinuxRegisters {
            DrainPool.run { Blocks.invoke(block) }
            Runtime.blockRelease(block)
        }
    }

    /// Runs a block the caller keeps, for the synchronous calls.
    static let run: Function = { block in
        guard let block else { return }
        keepingLinuxRegisters { Blocks.invoke(block) }
    }

    /// Runs a function the caller passed with its context, in a pool.
    static func pooled(_ context: UnsafeMutableRawPointer?, _ work: Function) -> (UnsafeMutableRawPointer, Function) {
        let call = UnsafeMutablePointer<(UnsafeMutableRawPointer?, Function)>.allocate(capacity: 1)
        call.initialize(to: (context, work))
        return (UnsafeMutableRawPointer(call), Blocks.runFunction)
    }

    private static let runFunction: Function = { pointer in
        guard let call = pointer?.assumingMemoryBound(to: (UnsafeMutableRawPointer?, Function).self) else { return }
        let (context, work) = call.pointee
        call.deallocate()
        keepingLinuxRegisters { DrainPool.run { work(context) } }
    }

    /// For the synchronous _f calls, which libdispatch runs before they
    /// return: the context and function to give it for a Darwin function and
    /// its context, valid during `body`. On armv7 they keep r9 around the
    /// call; elsewhere they are the Darwin ones.
    static func synchronous(_ context: UnsafeMutableRawPointer?, _ work: Function?,
                            _ body: (UnsafeMutableRawPointer?, Function?) -> Void) {
#if arch(arm)
        guard let work else { return body(context, nil) }
        var call = (context, work)
        withUnsafeMutablePointer(to: &call) { body(UnsafeMutableRawPointer($0), Blocks.runCall) }
#else
        body(context, work)
#endif
    }

    typealias ApplyFunction = @convention(c) (UnsafeMutableRawPointer?, Int) -> Void

    /// synchronous(_:_:_:) for dispatch_apply_f's function of an index.
    static func synchronous(_ context: UnsafeMutableRawPointer?, _ work: ApplyFunction?,
                            _ body: (UnsafeMutableRawPointer?, ApplyFunction?) -> Void) {
#if arch(arm)
        guard let work else { return body(context, nil) }
        var call = (context, work)
        withUnsafeMutablePointer(to: &call) { body(UnsafeMutableRawPointer($0), Blocks.runApply) }
#else
        body(context, work)
#endif
    }

#if arch(arm)
    private static let runCall: Function = { pointer in
        guard let call = pointer?.assumingMemoryBound(to: (UnsafeMutableRawPointer?, Function).self) else { return }
        keepingLinuxRegisters { call.pointee.1(call.pointee.0) }
    }

    private static let runApply: ApplyFunction = { pointer, index in
        guard let call = pointer?.assumingMemoryBound(to: (UnsafeMutableRawPointer?, ApplyFunction).self) else { return }
        keepingLinuxRegisters { call.pointee.1(call.pointee.0, index) }
    }
#endif
}

/// Queue attributes' flags, kept in their state word.
enum QueueAttributes {
    static let concurrent: UInt = 1

    private static let lock = Lock()
    nonisolated(unsafe) private static var wrappers: [Object: Object] = [:]

    /// The Darwin attribute for a Linux one, made once: attributes are
    /// never freed, on either side.
    static func wrap(_ linux: Object?, concurrent: Bool) -> Object? {
        guard let linux else { return nil }
        return lock.withLock {
            if let wrapper = wrappers[linux] { return wrapper }
            let wrapper = Objects.make(Classes.queueAttribute, linux: linux)
            wrapper.storeBytes(of: UnsafeMutableRawPointer(bitPattern: concurrent ? QueueAttributes.concurrent : 0),
                               toByteOffset: DarwinLayout.objectState, as: UnsafeMutableRawPointer?.self)
            wrappers[linux] = wrapper
            return wrapper
        }
    }

    static func isConcurrent(_ attr: Object?) -> Bool {
        UInt(bitPattern: Objects.word(attr)) & concurrent != 0
    }
}

enum Queues {
    /// The key under which each Linux queue made here holds its Darwin queue.
    nonisolated(unsafe) static let wrapperKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    private static let lock = Lock()
    /// The main and root queues, which cannot hold queue-specific data.
    nonisolated(unsafe) private static var shared: [Object: Object] = [:]

    static func register(main: Object) {
        lock.withLock { shared[perry_linux_main_q()] = main }
    }

    /// A Darwin queue (+1) for a new Linux queue.
    static func wrap(_ linux: Object, concurrent: Bool) -> Object {
        let queue = Objects.make(concurrent ? Classes.concurrentQueue : Classes.serialQueue, linux: linux)
        linux_dispatch_queue_set_specific(linux, wrapperKey, queue, nil)
        return queue
    }

    /// From a queue's -dealloc.
    static func forget(_ queue: Object) {
        if let linux = Objects.linux(queue) { linux_dispatch_queue_set_specific(linux, wrapperKey, nil, nil) }
    }

    /// The Darwin queue standing for a Linux one.
    static func darwin(_ linux: Object?) -> Object? {
        guard let linux else { return nil }
        if let queue = lock.withLock({ shared[linux] }) { return queue }
        return linux_dispatch_queue_get_specific(linux, wrapperKey)
    }

    static func global(_ linux: Object?) -> Object? {
        guard let linux else { return nil }
        return lock.withLock {
            if let queue = shared[linux] { return queue }
            let queue = Objects.make(Classes.globalQueue, linux: linux)
            shared[linux] = queue
            return queue
        }
    }
}

// MARK: - Making queues

@c(_dispatch_queue_create)
public func dispatch_queue_create(_ label: UnsafePointer<CChar>?, _ attr: Object?) -> Object? {
    guard let linux = linux_dispatch_queue_create(label, Objects.linux(attr)) else { return nil }
    return Queues.wrap(linux, concurrent: QueueAttributes.isConcurrent(attr))
}

@_cdecl("_dispatch_queue_create_with_target$V2")
public func dispatch_queue_create_with_target(_ label: UnsafePointer<CChar>?, _ attr: Object?,
                                              _ target: Object?) -> Object? {
    guard let linux = linux_dispatch_queue_create_with_target(label, Objects.linux(attr), Objects.linux(target))
    else { return nil }
    return Queues.wrap(linux, concurrent: QueueAttributes.isConcurrent(attr))
}

@c(_dispatch_get_global_queue)
public func dispatch_get_global_queue(_ identifier: Int, _ flags: UInt) -> Object? {
    Queues.global(linux_dispatch_get_global_queue(identifier, flags))
}

@c(_dispatch_get_current_queue)
public func dispatch_get_current_queue() -> Object? {
    let linux = linux_dispatch_get_current_queue()
    return Queues.darwin(linux) ?? Queues.global(linux)
}

@c(_dispatch_queue_attr_make_with_qos_class)
public func dispatch_queue_attr_make_with_qos_class(_ attr: Object?, _ qos: UInt32, _ priority: Int32) -> Object? {
    QueueAttributes.wrap(linux_dispatch_queue_attr_make_with_qos_class(Objects.linux(attr), qos, priority),
                         concurrent: QueueAttributes.isConcurrent(attr))
}

@c(_dispatch_queue_attr_make_initially_inactive)
public func dispatch_queue_attr_make_initially_inactive(_ attr: Object?) -> Object? {
    QueueAttributes.wrap(linux_dispatch_queue_attr_make_initially_inactive(Objects.linux(attr)),
                         concurrent: QueueAttributes.isConcurrent(attr))
}

@c(_dispatch_queue_attr_make_with_autorelease_frequency)
public func dispatch_queue_attr_make_with_autorelease_frequency(_ attr: Object?, _ frequency: UInt) -> Object? {
    QueueAttributes.wrap(linux_dispatch_queue_attr_make_with_autorelease_frequency(Objects.linux(attr), frequency),
                         concurrent: QueueAttributes.isConcurrent(attr))
}

// MARK: - Queue properties

/// DISPATCH_CURRENT_QUEUE_LABEL (NULL) names the current queue.
@c(_dispatch_queue_get_label)
public func dispatch_queue_get_label(_ queue: Object?) -> UnsafePointer<CChar>? {
    linux_dispatch_queue_get_label(Objects.linux(queue))
}

@c(_dispatch_queue_get_qos_class)
public func dispatch_queue_get_qos_class(_ queue: Object?, _ priority: UnsafeMutablePointer<Int32>?) -> UInt32 {
    linux_dispatch_queue_get_qos_class(Objects.linux(queue), priority)
}

@c(_dispatch_queue_set_specific)
public func dispatch_queue_set_specific(_ queue: Object?, _ key: UnsafeRawPointer?, _ context: UnsafeMutableRawPointer?,
                                        _ destructor: Function?) {
    linux_dispatch_queue_set_specific(Objects.linux(queue), key, context, destructor)
}

@c(_dispatch_queue_get_specific)
public func dispatch_queue_get_specific(_ queue: Object?, _ key: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    linux_dispatch_queue_get_specific(Objects.linux(queue), key)
}

@c(_dispatch_get_specific)
public func dispatch_get_specific(_ key: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    linux_dispatch_get_specific(key)
}

@_cdecl("_dispatch_assert_queue$V2")
public func dispatch_assert_queue(_ queue: Object?) {
    linux_dispatch_assert_queue(Objects.linux(queue))
}

@_cdecl("_dispatch_assert_queue_not$V2")
public func dispatch_assert_queue_not(_ queue: Object?) {
    linux_dispatch_assert_queue_not(Objects.linux(queue))
}

@c(_dispatch_assert_queue_barrier)
public func dispatch_assert_queue_barrier(_ queue: Object?) {
    linux_dispatch_assert_queue_barrier(Objects.linux(queue))
}

// MARK: - Submitting work

@c(_dispatch_async)
public func dispatch_async(_ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    let copy = Blocks.copy(block)
    if DispatchBlocks.isBarrier(copy) {
        linux_dispatch_barrier_async_f(Objects.linux(queue), copy, Blocks.runOnce)
    } else {
        linux_dispatch_async_f(Objects.linux(queue), copy, Blocks.runOnce)
    }
}

@c(_dispatch_async_f)
public func dispatch_async_f(_ queue: Object?, _ context: UnsafeMutableRawPointer?, _ work: Function?) {
    guard let work else { dispatchFatal("dispatch_async_f called with a NULL function") }
    let (call, run) = Blocks.pooled(context, work)
    linux_dispatch_async_f(Objects.linux(queue), call, run)
}

@c(_dispatch_sync)
public func dispatch_sync(_ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    Blocking.willBlock()
    if let block, DispatchBlocks.isBarrier(block) {
        linux_dispatch_barrier_sync_f(Objects.linux(queue), block, Blocks.run)
    } else {
        linux_dispatch_sync_f(Objects.linux(queue), block, Blocks.run)
    }
}

@c(_dispatch_sync_f)
public func dispatch_sync_f(_ queue: Object?, _ context: UnsafeMutableRawPointer?, _ work: Function?) {
    Blocking.willBlock()
    Blocks.synchronous(context, work) { linux_dispatch_sync_f(Objects.linux(queue), $0, $1) }
}

@c(_dispatch_async_and_wait)
public func dispatch_async_and_wait(_ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    Blocking.willBlock()
    linux_dispatch_async_and_wait_f(Objects.linux(queue), block, Blocks.run)
}

@c(_dispatch_async_and_wait_f)
public func dispatch_async_and_wait_f(_ queue: Object?, _ context: UnsafeMutableRawPointer?, _ work: Function?) {
    Blocking.willBlock()
    Blocks.synchronous(context, work) { linux_dispatch_async_and_wait_f(Objects.linux(queue), $0, $1) }
}

@c(_dispatch_barrier_async)
public func dispatch_barrier_async(_ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    linux_dispatch_barrier_async_f(Objects.linux(queue), Blocks.copy(block), Blocks.runOnce)
}

@c(_dispatch_barrier_async_f)
public func dispatch_barrier_async_f(_ queue: Object?, _ context: UnsafeMutableRawPointer?, _ work: Function?) {
    guard let work else { dispatchFatal("dispatch_barrier_async_f called with a NULL function") }
    let (call, run) = Blocks.pooled(context, work)
    linux_dispatch_barrier_async_f(Objects.linux(queue), call, run)
}

@c(_dispatch_barrier_sync)
public func dispatch_barrier_sync(_ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    Blocking.willBlock()
    linux_dispatch_barrier_sync_f(Objects.linux(queue), block, Blocks.run)
}

@c(_dispatch_barrier_sync_f)
public func dispatch_barrier_sync_f(_ queue: Object?, _ context: UnsafeMutableRawPointer?, _ work: Function?) {
    Blocking.willBlock()
    Blocks.synchronous(context, work) { linux_dispatch_barrier_sync_f(Objects.linux(queue), $0, $1) }
}

@c(_dispatch_barrier_async_and_wait)
public func dispatch_barrier_async_and_wait(_ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    linux_dispatch_barrier_async_and_wait_f(Objects.linux(queue), block, Blocks.run)
}

@c(_dispatch_barrier_async_and_wait_f)
public func dispatch_barrier_async_and_wait_f(_ queue: Object?, _ context: UnsafeMutableRawPointer?,
                                              _ work: Function?) {
    Blocks.synchronous(context, work) { linux_dispatch_barrier_async_and_wait_f(Objects.linux(queue), $0, $1) }
}

@c(_dispatch_after)
public func dispatch_after(_ when: UInt64.ObjCType, _ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    linux_dispatch_after_f(DarwinTime.linux(UInt64(objCArgument: when)), Objects.linux(queue), Blocks.copy(block), Blocks.runOnce)
}

@c(_dispatch_after_f)
public func dispatch_after_f(_ when: UInt64.ObjCType, _ queue: Object?, _ context: UnsafeMutableRawPointer?,
                             _ work: Function?) {
    guard let work else { dispatchFatal("dispatch_after_f called with a NULL function") }
    let (call, run) = Blocks.pooled(context, work)
    linux_dispatch_after_f(DarwinTime.linux(UInt64(objCArgument: when)), Objects.linux(queue), call, run)
}

private let applyBlock: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void = { block, index in
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int) -> Void
    guard let block else { return }
    keepingLinuxRegisters {
        unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: Invoke.self)(block, index)
    }
}

/// DISPATCH_APPLY_AUTO is NULL, as on Linux.
@c(_dispatch_apply)
public func dispatch_apply(_ iterations: Int, _ queue: Object?, _ block: UnsafeMutableRawPointer?) {
    linux_dispatch_apply_f(iterations, Objects.linux(queue), block, applyBlock)
}

@c(_dispatch_apply_f)
public func dispatch_apply_f(_ iterations: Int, _ queue: Object?, _ context: UnsafeMutableRawPointer?,
                             _ work: (@convention(c) (UnsafeMutableRawPointer?, Int) -> Void)?) {
    Blocks.synchronous(context, work) { linux_dispatch_apply_f(iterations, Objects.linux(queue), $0, $1) }
}
