import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// An NSThread's state. Threads run a block or a target and selector, in an
/// autorelease pool, on a detached pthread.
final class ThreadStorage {
    var name: String?
    let isMain: Bool
    private(set) var dictionary: id?
    private var block: id?
    private var target: id?
    private let selector: SEL?
    private var argument: id?
    var isExecuting = false
    var isFinished = false
    var isCancelled = false
    var stackSize: UInt = 512 * 1024
    /// The thread's run loop, once it or a perform onto the thread made one.
    var runLoop: RunLoopState?

    init(isMain: Bool = false, block: id? = nil, target: id? = nil, selector: SEL? = nil, argument: id? = nil) {
        self.isMain = isMain
        self.block = ObjC.retainBlock(block)
        self.target = ObjC.retain(target)
        self.selector = selector
        self.argument = ObjC.retain(argument)
    }

    deinit {
        for object in [dictionary, block, target, argument] { ObjC.release(object) }
    }

    /// The thread dictionary, created when first asked for.
    var threadDictionary: id {
        if let dictionary { return dictionary }
        let created = Dictionaries.make([], cls: UnsafeMutableRawPointer(Dictionaries.mutableClass))
        dictionary = created
        return created
    }

    func main(_ thread: id) {
        if let block {
            Blocks.invoke(block, as: (@convention(c) (id) -> Void).self)(block)
        } else if let target, let selector {
            _ = ObjC.send(target, selector, argument)
        }
    }
}

enum Threads {
    nonisolated(unsafe) static var threadClass: Class!
    nonisolated(unsafe) static var main: id!
    nonisolated(unsafe) static var mainThread: pthread_t?

    /// The NSThread object of each thread that has one.
    static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { object in ObjC.release(object) }
        return key
    }()

    static func storage(_ object: id?) -> ThreadStorage? {
        Storage.get(object, as: ThreadStorage.self)
    }

    static var isMainThread: Bool {
        mainThread.map { pthread_equal($0, pthread_self()) != 0 } ?? true
    }

    /// The calling thread's NSThread, created for threads Foundation did not start.
    static var current: id {
        if isMainThread { return main }
        if let object = pthread_getspecific(key) { return object }
        let object = make(ThreadStorage())
        pthread_setspecific(key, object)
        return object
    }

    /// A new thread object, +1.
    static func make(_ storage: ThreadStorage) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(threadClass))!
        Storage.set(object, storage)
        return object
    }

    /// Starts `thread` on a new detached pthread.
    static func start(_ thread: id) {
        guard let storage = storage(thread), !storage.isExecuting, !storage.isFinished else { return }
        storage.isExecuting = true
        _ = ObjC.retain(thread)     // released when the thread ends, through the key's destructor
        var attributes = pthread_attr_t()
        pthread_attr_init(&attributes)
        pthread_attr_setdetachstate(&attributes, Int32(PTHREAD_CREATE_DETACHED))
        pthread_attr_setstacksize(&attributes, Int(max(storage.stackSize, 64 * 1024)))
        var handle = pthread_t()
        let result = pthread_create(&handle, &attributes, { context in
            guard let thread = context else { return nil }
            pthread_setspecific(Threads.key, thread)
            ObjC.autoreleasepool {
                Threads.storage(thread)?.main(thread)
            }
            if let storage = Threads.storage(thread) {
                storage.isExecuting = false
                storage.isFinished = true
            }
            return nil
        }, thread)
        pthread_attr_destroy(&attributes)
        if result != 0 {
            storage.isExecuting = false
            ObjC.release(thread)
        }
    }


    /// Runs `selector` on the main thread from its run loop, or at once when
    /// already there and waiting; with `wait`, blocks until it has run.
    static func performOnMain(_ target: id, _ selector: SEL, _ argument: id?, wait: Bool) {
        perform(target, selector, argument, on: main, wait: wait)
    }

    /// The run loop of a thread, made for it if it has none yet; the thread
    /// adopts it when it first asks for its own.
    static func runLoop(of thread: id) -> RunLoopState? {
        if thread == main { return RunLoops.mainLoop }
        guard let storage = storage(thread) else { return nil }
        if let runLoop = storage.runLoop { return runLoop }
        let runLoop = RunLoopState()
        storage.runLoop = runLoop
        return runLoop
    }

    /// Runs `selector` on `thread` from its run loop, or at once when that
    /// is the calling thread and waiting; with `wait`, blocks until it has
    /// run.
    static func perform(_ target: id, _ selector: SEL, _ argument: id?, on thread: id, wait: Bool) {
        if wait && thread == current {
            _ = ObjC.send(target, selector, argument)
            return
        }
        guard let runLoop = runLoop(of: thread) else { return }
        var done = false
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(condition, nil)
        defer {
            pthread_mutex_destroy(mutex)
            pthread_cond_destroy(condition)
            mutex.deallocate()
            condition.deallocate()
        }
        let request = TimerStorage(fireDate: 0, interval: 0, repeats: false, target: target, selector: selector,
                                   userInfo: nil, block: nil, argument: argument, isPerformRequest: true)
        if wait {
            request.onFired = {
                pthread_mutex_lock(mutex)
                done = true
                pthread_cond_broadcast(condition)
                pthread_mutex_unlock(mutex)
            }
        }
        let timer = Timers.make(request)
        Timers.add(timer, to: runLoop)
        ObjC.release(timer)
        guard wait else { return }
        pthread_mutex_lock(mutex)
        while !done { pthread_cond_wait(condition, mutex) }
        pthread_mutex_unlock(mutex)
    }
}

/// NSThread.
@ObjCClass("NSThread")
public final class NSThread: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Threads.threadClass = cls.storage
        Threads.main = Threads.make(ThreadStorage(isMain: true))
        Threads.storage(Threads.main)?.name = "main"
        Threads.storage(Threads.main)?.isExecuting = true
    }

    private var storage: ThreadStorage? { Threads.storage(objcObject) }

    // MARK: Class methods

    @ObjCClassMethod("currentThread") static func current() -> UnsafeMutableRawPointer? { Threads.current }
    @ObjCClassMethod("mainThread") static func main() -> UnsafeMutableRawPointer? { Threads.main }
    @ObjCClassMethod("isMainThread") static func isMainThread() -> Bool { Threads.isMainThread }
    @ObjCClassMethod("isMultiThreaded") static func isMultiThreaded() -> Bool { true }

    @ObjCClassMethod("sleepForTimeInterval:")
    static func sleep(forTimeInterval seconds: Double) {
        guard seconds > 0 else { return }
        var time = timespec(tv_sec: Int(seconds), tv_nsec: Int((seconds - seconds.rounded(.down)) * 1e9))
        var remaining = timespec()
        while nanosleep(&time, &remaining) != 0 && errno == EINTR {
            time = remaining
        }
    }

    @ObjCClassMethod("sleepUntilDate:")
    static func sleep(until date: NSDate) { sleep(forTimeInterval: date.date.timeIntervalSinceNow) }

    @ObjCClassMethod("detachNewThreadWithBlock:")
    static func detach(block: ObjCBlock) {
        let thread = Threads.make(ThreadStorage(block: block.object))
        Threads.start(thread)
        ObjC.release(thread)
    }

    @ObjCClassMethod("detachNewThreadSelector:toTarget:withObject:")
    static func detach(selector: ObjCSelector, toTarget target: ObjCObject, withObject argument: ObjCObject?) {
        let thread = Threads.make(ThreadStorage(target: target.id, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                                argument: argument?.id))
        Threads.start(thread)
        ObjC.release(thread)
    }

    // MARK: Creating

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, ThreadStorage())
        return self
    }

    @ObjCMethod("initWithBlock:")
    func initialize(block: ObjCBlock) -> Self {
        Storage.set(objcObject, ThreadStorage(block: block.object))
        return self
    }

    @ObjCMethod("initWithTarget:selector:object:")
    func initialize(target: ObjCObject, selector: ObjCSelector, object argument: ObjCObject?) -> Self {
        Storage.set(objcObject, ThreadStorage(target: target.id, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                              argument: argument?.id))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Threads.threadClass)
    }

    // MARK: Running

    @ObjCMethod("start") func start() { Threads.start(objcObject) }
    @ObjCMethod("main") func main() { storage?.main(objcObject) }
    @ObjCMethod("cancel") func cancel() { storage?.isCancelled = true }
    @ObjCMethod("isExecuting") func isExecuting() -> Bool { storage?.isExecuting ?? false }
    @ObjCMethod("isFinished") func isFinished() -> Bool { storage?.isFinished ?? false }
    @ObjCMethod("isCancelled") func isCancelled() -> Bool { storage?.isCancelled ?? false }
    @ObjCMethod("isMainThread") func isMainThread() -> Bool { storage?.isMain ?? false }

    @ObjCMethod("name") func name() -> String? { storage?.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { storage?.name = name }
    @ObjCMethod("stackSize") func stackSize() -> UInt { storage?.stackSize ?? 0 }
    @ObjCMethod("setStackSize:") func setStackSize(_ size: UInt) { storage?.stackSize = size }
    @ObjCMethod("threadPriority") func threadPriority() -> Double { 0.5 }
    @ObjCMethod("setThreadPriority:") func setThreadPriority(_ priority: Double) {}

    @ObjCMethod("threadDictionary")
    func threadDictionary() -> UnsafeMutableRawPointer? { storage?.threadDictionary }
}

/// NSObject's thread performs, which Foundation adds.
@ObjCCategory("ThreadPerforms")
extension NSObject {
    @ObjCMethod("performSelectorOnMainThread:withObject:waitUntilDone:")
    func performOnMain(_ selector: ObjCSelector, with argument: ObjCObject?, waitUntilDone wait: Bool) {
        Threads.performOnMain(objcObject, selector.pointer.assumingMemoryBound(to: CChar.self), argument?.id, wait: wait)
    }

    @ObjCMethod("performSelectorOnMainThread:withObject:waitUntilDone:modes:")
    func performOnMain(_ selector: ObjCSelector, with argument: ObjCObject?, waitUntilDone wait: Bool, modes: ObjCObject?) {
        performOnMain(selector, with: argument, waitUntilDone: wait)
    }

    @ObjCMethod("performSelector:onThread:withObject:waitUntilDone:")
    func perform(_ selector: ObjCSelector, on thread: ObjCObject, with argument: ObjCObject?, waitUntilDone wait: Bool) {
        Threads.perform(objcObject, selector.pointer.assumingMemoryBound(to: CChar.self), argument?.id, on: thread.id,
                        wait: wait)
    }

    @ObjCMethod("performSelector:onThread:withObject:waitUntilDone:modes:")
    func perform(_ selector: ObjCSelector, on thread: ObjCObject, with argument: ObjCObject?, waitUntilDone wait: Bool,
                 modes: ObjCObject?) {
        perform(selector, on: thread, with: argument, waitUntilDone: wait)
    }

    @ObjCMethod("performSelectorInBackground:withObject:")
    func performInBackground(_ selector: ObjCSelector, with argument: ObjCObject?) {
        let thread = Threads.make(ThreadStorage(target: objcObject, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                                argument: argument?.id))
        Threads.start(thread)
        ObjC.release(thread)
    }
}
