import CPerryFoundation
import Glibc
import PerryObjCInterop

/// A thread's run loop. Perry's run loops have timers and, on the main
/// thread, the main dispatch queue, and every mode runs every timer. The
/// main run loop behaves as if it had an input source, as it always does in
/// a Darwin app: it waits for work instead of finishing when it has no
/// timers. A run loop sleeps in poll(), woken through an eventfd and, on
/// the main thread, by the main queue's port.
///
/// Like CFRunLoop, a run returns when it is stopped, when its time limit
/// passes, or when it has nothing left to run ("finished").
final class RunLoopState {
    enum Result: Int32 {
        case finished = 1, stopped = 2, timedOut = 3, handledSource = 4
    }

    /// The NSRunLoop object, which also serves as the CFRunLoopRef.
    private(set) var object: id!
    private var timers: [id] = []
    /// Observers added, retained, and blocks to perform, copied.
    private var observers: [id] = []
    private var blocks: [id] = []
    /// Work from Foundation itself for the next pass, such as a socket's
    /// callback.
    private var work: [() -> Void] = []
    /// Ports added, which keep the loop running as input sources do.
    var ports = 0
    private var stopRequested = false
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private let wakeFile = eventfd(0, Int32(EFD_CLOEXEC | EFD_NONBLOCK))

    let isMain: Bool

    /// Whether this run loop drains the main dispatch queue.
    var servesMainQueue: Bool { isMain && MainDispatchQueue.port >= 0 }

    init(isMain: Bool = false) {
        self.isMain = isMain
        pthread_mutex_init(mutex, nil)
        let object = Storage.allocate(UnsafeMutableRawPointer(RunLoops.runLoopClass))!
        Storage.set(object, self)
        self.object = object
    }

    /// An input source added or removed: one of another library's, such as
    /// an audio queue's on the run loop its app names.
    func addSource() { locked { ports += 1 } }
    func removeSource() { locked { ports = max(0, ports - 1) } }

    private func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    /// Adds a timer, retaining it until it is invalidated. Safe from any thread.
    func add(_ timer: id) {
        let added = locked {
            guard !timers.contains(timer) else { return false }
            timers.append(timer)
            return true
        }
        if added { _ = ObjC.retain(timer) }
        wakeUp()
    }

    func remove(_ timer: id) {
        let removed = locked {
            guard let index = timers.firstIndex(of: timer) else { return false }
            timers.remove(at: index)
            return true
        }
        if removed { ObjC.release(timer) }
    }

    var hasTimers: Bool { locked { !timers.isEmpty } }

    func add(observer: id) {
        let added = locked {
            guard !observers.contains(observer) else { return false }
            observers.append(observer)
            return true
        }
        if added { _ = ObjC.retain(observer) }
    }

    func remove(observer: id) {
        let removed = locked {
            guard let index = observers.firstIndex(of: observer) else { return false }
            observers.remove(at: index)
            return true
        }
        if removed { ObjC.release(observer) }
    }

    func contains(observer: id) -> Bool { locked { observers.contains(observer) } }

    /// Runs a block on the loop's next pass. Safe from any thread.
    func perform(_ block: id) {
        guard let copied = ObjC.retainBlock(block) else { return }
        locked { blocks.append(copied) }
        wakeUp()
    }

    /// Runs Foundation's own work on the loop's next pass. Safe from any thread.
    func perform(work body: @escaping () -> Void) {
        locked { work.append(body) }
        wakeUp()
    }

    /// Calls the observers of `activity`, in their order; an observer that
    /// does not repeat is removed after its first call.
    private func notify(_ activity: UInt) {
        let observing = locked { observers.filter { RunLoopObservers.activities($0) & activity != 0 } }
            .sorted { RunLoopObservers.order($0) < RunLoopObservers.order($1) }
        for observer in observing {
            _ = ObjC.retain(observer)
            ObjC.autoreleasepool { RunLoopObservers.call(observer, activity) }
            if !RunLoopObservers.repeats(observer) { remove(observer: observer) }
            ObjC.release(observer)
        }
    }

    /// Runs the blocks performed so far; whether there were any.
    private func runBlocks() -> Bool {
        let (pending, bodies) = locked { () -> ([id], [() -> Void]) in
            defer {
                blocks.removeAll()
                work.removeAll()
            }
            return (blocks, work)
        }
        for block in pending {
            ObjC.autoreleasepool { Blocks.invoke(block, as: (@convention(c) (id) -> Void).self)(block) }
            ObjC.release(block)
        }
        for body in bodies { ObjC.autoreleasepool { body() } }
        return !pending.isEmpty || !bodies.isEmpty
    }

    func snapshotTimers() -> [id] { locked { timers } }

    func stop() {
        locked { stopRequested = true }
        wakeUp()
    }

    func wakeUp() {
        _ = eventfd_write(wakeFile, 1)
    }

    /// Runs timers until `limit` (absolute time), a stop, or no timers.
    /// With `waitWhenEmpty`, running out of timers waits for `limit` instead,
    /// as a Darwin run loop with an input source does.
    func run(until limit: Double, returnAfterSourceHandled: Bool = false, waitWhenEmpty: Bool? = nil) -> Result {
        notify(RunLoopActivity.entry)
        let result = runPasses(until: limit, returnAfterSourceHandled: returnAfterSourceHandled, waitWhenEmpty: waitWhenEmpty)
        notify(RunLoopActivity.exit)
        return result
    }

    private func runPasses(until limit: Double, returnAfterSourceHandled: Bool, waitWhenEmpty: Bool?) -> Result {
        let waitWhenEmpty = waitWhenEmpty ?? isMain
        while true {
            if runBlocks(), returnAfterSourceHandled { return .handledSource }
            notify(RunLoopActivity.beforeTimers)
            if servesMainQueue, MainDispatchQueue.isReady() {
                MainDispatchQueue.drain()
                if returnAfterSourceHandled { return .handledSource }
            }
            let next: (timer: id?, fire: Double)? = locked {
                if stopRequested {
                    stopRequested = false
                    return nil
                }
                // A timer invalidated without the run loop hearing of it
                // would otherwise come due forever.
                let invalid = timers.filter { !Timers.isValid($0) }
                if !invalid.isEmpty {
                    timers.removeAll { !Timers.isValid($0) }
                    invalid.forEach { ObjC.release($0) }
                }
                let due = timers.min { Timers.fireDate($0) < Timers.fireDate($1) }
                return (due, due.map(Timers.fireDate) ?? .infinity)
            }
            guard let next else { return .stopped }
            let now = absoluteTimeNow()
            guard let timer = next.timer else {
                guard waitWhenEmpty, now < limit else { return .finished }
                wait(until: limit)
                continue
            }

            if next.fire <= now {
                _ = ObjC.retain(timer)
                ObjC.autoreleasepool { Timers.fire(timer, from: self) }
                ObjC.release(timer)
                if returnAfterSourceHandled { return .handledSource }
                continue
            }
            if now >= limit { return .timedOut }
            wait(until: min(next.fire, limit))
        }
    }

    /// Sleeps until `deadline`, a wake-up or, on the main thread, work for
    /// the main queue.
    private func wait(until deadline: Double) {
        if locked({ stopRequested || !blocks.isEmpty || !work.isEmpty }) { return }
        notify(RunLoopActivity.beforeWaiting)
        defer { notify(RunLoopActivity.afterWaiting) }
        let remaining = deadline - absoluteTimeNow()
        // Milliseconds, rounded up so a timer is never woken for early.
        let timeout = remaining.isFinite ? Int32(min(max(ceil(remaining * 1000), 0), Double(Int32.max))) : -1
        var files = [pollfd(fd: wakeFile, events: Int16(POLLIN), revents: 0)]
        if servesMainQueue { files.append(pollfd(fd: MainDispatchQueue.port, events: Int16(POLLIN), revents: 0)) }
        _ = poll(&files, nfds_t(files.count), timeout)
        var value: eventfd_t = 0
        _ = eventfd_read(wakeFile, &value)
    }
}

/// The main dispatch queue, drained by the main run loop through the
/// hooks libdispatch gives CoreFoundation's run loop. Its port is a file
/// descriptor that becomes readable when the queue has work.
enum MainDispatchQueue {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?) -> Void
    nonisolated(unsafe) static var port: Int32 = -1
    nonisolated(unsafe) static var callback: Callback?

    /// Binds libdispatch's hooks, which libSystem re-exports.
    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        typealias GetPort = @convention(c) () -> Int32
        guard let getPort = lookup("__dispatch_get_main_queue_port_4CF"),
              let callback = lookup("__dispatch_main_queue_callback_4CF") else { return }
        self.callback = unsafeBitCast(callback, to: Callback.self)
        port = unsafeBitCast(getPort, to: GetPort.self)()
    }

    static func isReady() -> Bool {
        var file = pollfd(fd: port, events: Int16(POLLIN), revents: 0)
        return poll(&file, 1, 0) > 0
    }

    static func drain() {
        callback?(nil)
    }
}

enum RunLoops {
    nonisolated(unsafe) static var runLoopClass: Class!
    nonisolated(unsafe) private static var main: RunLoopState?
    nonisolated(unsafe) static var mainThread: pthread_t?

    static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    /// The run loop of the thread that started the program.
    static var mainLoop: RunLoopState {
        if let main { return main }
        let created = RunLoopState(isMain: true)
        main = created
        return created
    }

    static var current: RunLoopState {
        if let mainThread, pthread_equal(mainThread, pthread_self()) != 0 {
            return mainLoop
        }
        if let pointer = pthread_getspecific(key) {
            return Unmanaged<RunLoopState>.fromOpaque(pointer).takeUnretainedValue()
        }
        // One a perform onto this thread made, or a new one.
        let storage = Threads.storage(Threads.current)
        let created = storage?.runLoop ?? RunLoopState()
        storage?.runLoop = created
        pthread_setspecific(key, Unmanaged.passRetained(created).toOpaque())
        return created
    }

    static func state(_ object: id?) -> RunLoopState? {
        Storage.get(object, as: RunLoopState.self)
    }

}

/// Run loop mode names. NSRunLoop's and CFRunLoop's are the same objects.
@ObjCConstants
enum RunLoopModes {
    static let NSDefaultRunLoopMode = "kCFRunLoopDefaultMode"
    static let NSRunLoopCommonModes = "kCFRunLoopCommonModes"
    static let kCFRunLoopDefaultMode = NSDefaultRunLoopMode
    static let kCFRunLoopCommonModes = NSRunLoopCommonModes
}

/// NSRunLoop.
@ObjCClass("NSRunLoop")
public final class NSRunLoop: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        RunLoops.runLoopClass = cls.storage
    }

    private var state: RunLoopState? { RunLoops.state(objcObject) }

    @ObjCClassMethod("currentRunLoop")
    static func current() -> UnsafeMutableRawPointer? { RunLoops.current.object }

    @ObjCClassMethod("mainRunLoop")
    static func main() -> UnsafeMutableRawPointer? { RunLoops.mainLoop.object }

    // Run loops live as long as their thread.
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }

    @ObjCMethod("getCFRunLoop")
    func cfRunLoop() -> UnsafeMutableRawPointer { objcObject }

    @ObjCMethod("currentMode")
    func currentMode() -> UnsafeMutableRawPointer? { RunLoopModes.NSDefaultRunLoopModeObject }

    /// The timer records the run loop, so invalidating it takes it out.
    @ObjCMethod("addTimer:forMode:")
    func add(_ timer: ObjCObject, forMode mode: ObjCObject?) {
        if let state, Timers.isValid(timer.id) { Timers.add(timer.id, to: state) }
    }

    /// Runs a block on the loop's next pass; the loop runs one mode here.
    @ObjCMethod("performBlock:")
    func perform(block: ObjCObject?) {
        if let block { state?.perform(block.id) }
    }

    @ObjCMethod("performInModes:block:")
    func perform(inModes modes: ObjCObject?, block: ObjCObject?) {
        if let block { state?.perform(block.id) }
    }

    /// Runs until nothing is left to run. Stopping does not end -run.
    @ObjCMethod("run")
    func run() {
        guard let state else { return }
        while state.run(until: .infinity) != .finished {}
    }

    /// Runs until `date`. Apps' run loops always have input sources on
    /// Darwin, so this lasts until `date` even when no timers remain.
    @ObjCMethod("runUntilDate:")
    func run(until date: NSDate) {
        guard let state else { return }
        let limit = date.date.timeIntervalSinceReferenceDate
        while true {
            let result = state.run(until: limit, waitWhenEmpty: true)
            if result == .finished || result == .timedOut { return }
        }
    }

    /// Timers are not input sources, so a run with only timers lasts until
    /// `date`, as on Darwin. NO when there is nothing to run.
    @ObjCMethod("runMode:beforeDate:")
    func run(mode: ObjCObject?, before date: NSDate) -> Bool {
        guard let state, state.hasTimers || state.servesMainQueue || state.ports > 0 else { return false }
        _ = state.run(until: date.date.timeIntervalSinceReferenceDate, waitWhenEmpty: state.ports > 0)
        return true
    }

    /// No messages arrive on ports, but one keeps the loop running.
    @ObjCMethod("addPort:forMode:") func add(port: ObjCObject?, forMode mode: ObjCObject?) { state?.ports += 1 }
    @ObjCMethod("removePort:forMode:")
    func remove(port: ObjCObject?, forMode mode: ObjCObject?) { if let state, state.ports > 0 { state.ports -= 1 } }
}

// MARK: - CFRunLoop

@c(_CFRunLoopGetCurrent)
public func CFRunLoopGetCurrent() -> UnsafeMutableRawPointer? {
    RunLoops.current.object
}

@c(_CFRunLoopGetMain)
public func CFRunLoopGetMain() -> UnsafeMutableRawPointer? {
    RunLoops.mainLoop.object
}

/// Runs the current thread's run loop until it is stopped or finished.
@c(_CFRunLoopRun)
public func CFRunLoopRun() {
    let state = RunLoops.current
    while true {
        let result = state.run(until: .infinity)
        if result == .stopped || result == .finished { return }
    }
}

@c(_CFRunLoopRunInMode)
public func CFRunLoopRunInMode(_ mode: UnsafeMutableRawPointer?, _ seconds: Double.ObjCType,
                               _ returnAfterSourceHandled: Bool) -> Int32 {
    // A loop with an input source waits for it, as on Darwin.
    let state = RunLoops.current
    return state.run(until: absoluteTimeNow() + Double(objCArgument: seconds), returnAfterSourceHandled: returnAfterSourceHandled,
                     waitWhenEmpty: state.ports > 0 ? true : nil).rawValue
}

/// Perry's own: another library's input source on a run loop, which keeps
/// it waiting rather than finished when it has nothing else. Audio queues
/// add one to the run loop their app names for callbacks.
@c(_perry_CFRunLoopAddInputSource)
public func perry_CFRunLoopAddInputSource(_ runLoop: UnsafeMutableRawPointer?) {
    RunLoops.state(runLoop)?.addSource()
}

@c(_perry_CFRunLoopRemoveInputSource)
public func perry_CFRunLoopRemoveInputSource(_ runLoop: UnsafeMutableRawPointer?) {
    RunLoops.state(runLoop)?.removeSource()
}

/// An NSTimer is a CFRunLoopTimer; every mode is the same run loop here.
@c(_CFRunLoopAddTimer)
public func CFRunLoopAddTimer(_ runLoop: UnsafeMutableRawPointer?, _ timer: UnsafeMutableRawPointer?,
                              _ mode: UnsafeMutableRawPointer?) {
    guard let state = RunLoops.state(runLoop), let timer else { return }
    Timers.add(timer, to: state)
}

@c(_CFRunLoopRemoveTimer)
public func CFRunLoopRemoveTimer(_ runLoop: UnsafeMutableRawPointer?, _ timer: UnsafeMutableRawPointer?,
                                 _ mode: UnsafeMutableRawPointer?) {
    guard let state = RunLoops.state(runLoop), let timer else { return }
    Timers.storage(timer)?.runLoops.removeAll { $0 === state }
    state.remove(timer)
}

/// The mode the run loop is running in, +1: the default mode, the only
/// one run loops here run in.
@c(_CFRunLoopCopyCurrentMode)
public func CFRunLoopCopyCurrentMode(_ loop: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjC.retain(RunLoopModes.NSDefaultRunLoopModeObject)
}

@c(_CFRunLoopStop)
public func CFRunLoopStop(_ runLoop: UnsafeMutableRawPointer?) {
    RunLoops.state(runLoop)?.stop()
}

@c(_CFRunLoopWakeUp)
public func CFRunLoopWakeUp(_ runLoop: UnsafeMutableRawPointer?) {
    RunLoops.state(runLoop)?.wakeUp()
}

// MARK: - Observers and blocks

/// CFRunLoopActivity.
enum RunLoopActivity {
    static let entry: UInt = 1 << 0
    static let beforeTimers: UInt = 1 << 1
    static let beforeSources: UInt = 1 << 2
    static let beforeWaiting: UInt = 1 << 5
    static let afterWaiting: UInt = 1 << 6
    static let exit: UInt = 1 << 7
}

/// A CFRunLoopObserver: the activities it watches, and a block or a
/// callout with its context's info.
final class RunLoopObserverStorage {
    typealias Callout = @convention(c) (id?, UInt, UnsafeMutableRawPointer?) -> Void
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void

    let activities: UInt
    let repeats: Bool
    let order: Int
    let block: id?
    let callout: Callout?
    let info: UnsafeMutableRawPointer?
    let release: Release?
    var valid = true

    init(activities: UInt, repeats: Bool, order: Int, block: id?, callout: Callout?, info: UnsafeMutableRawPointer?,
         release: Release?) {
        (self.activities, self.repeats, self.order) = (activities, repeats, order)
        (self.block, self.callout, self.info, self.release) = (block.flatMap(ObjC.retainBlock), callout, info, release)
    }

    deinit {
        if let block { ObjC.release(block) }
        release?(info)
    }
}

enum RunLoopObservers {
    nonisolated(unsafe) static var observerClass: Class!

    static func storage(_ observer: id?) -> RunLoopObserverStorage? { Storage.get(observer, as: RunLoopObserverStorage.self) }
    static func activities(_ observer: id) -> UInt { storage(observer).map { $0.valid ? $0.activities : 0 } ?? 0 }
    static func order(_ observer: id) -> Int { storage(observer)?.order ?? 0 }
    static func repeats(_ observer: id) -> Bool { storage(observer)?.repeats ?? false }

    static func call(_ observer: id, _ activity: UInt) {
        guard let storage = storage(observer), storage.valid else { return }
        if let block = storage.block {
            Blocks.invoke(block, as: (@convention(c) (id, id?, UInt) -> Void).self)(block, observer, activity)
        } else {
            storage.callout?(observer, activity, storage.info)
        }
    }

    static func make(_ storage: RunLoopObserverStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(observerClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }
}

@ObjCClass("__NSCFRunLoopObserver")
final class NSCFRunLoopObserver: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        RunLoopObservers.observerClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: RunLoopObservers.observerClass)
    }
}

@c(_CFRunLoopObserverCreateWithHandler)
public func CFRunLoopObserverCreateWithHandler(_ allocator: UnsafeMutableRawPointer?, _ activities: UInt, _ repeats: Bool,
                                               _ order: Int, _ block: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    RunLoopObservers.make(RunLoopObserverStorage(activities: activities, repeats: repeats, order: order, block: block,
                                                 callout: nil, info: nil, release: nil))
}

/// The context is { version, info, retain, release, copyDescription }.
@c(_CFRunLoopObserverCreate)
public func CFRunLoopObserverCreate(_ allocator: UnsafeMutableRawPointer?, _ activities: UInt, _ repeats: Bool, _ order: Int,
                                    _ callout: (@convention(c) (UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?) -> Void)?,
                                    _ context: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    var info = context?.load(fromByteOffset: DarwinLayout.contextInfo, as: UnsafeMutableRawPointer?.self)
    if let retain = context?.load(fromByteOffset: DarwinLayout.contextRetain, as: Retain?.self) {
        info = UnsafeMutableRawPointer(mutating: retain(info))
    }
    let release = context?.load(fromByteOffset: DarwinLayout.contextRelease, as: RunLoopObserverStorage.Release?.self)
    return RunLoopObservers.make(RunLoopObserverStorage(activities: activities, repeats: repeats, order: order, block: nil,
                                                        callout: callout, info: info, release: release))
}

/// Every mode is the same run loop here.
@c(_CFRunLoopAddObserver)
public func CFRunLoopAddObserver(_ runLoop: UnsafeMutableRawPointer?, _ observer: UnsafeMutableRawPointer?,
                                 _ mode: UnsafeMutableRawPointer?) {
    guard let observer else { return }
    RunLoops.state(runLoop)?.add(observer: observer)
}

@c(_CFRunLoopRemoveObserver)
public func CFRunLoopRemoveObserver(_ runLoop: UnsafeMutableRawPointer?, _ observer: UnsafeMutableRawPointer?,
                                    _ mode: UnsafeMutableRawPointer?) {
    guard let observer else { return }
    RunLoops.state(runLoop)?.remove(observer: observer)
}

@c(_CFRunLoopContainsObserver)
public func CFRunLoopContainsObserver(_ runLoop: UnsafeMutableRawPointer?, _ observer: UnsafeMutableRawPointer?,
                                      _ mode: UnsafeMutableRawPointer?) -> Bool {
    guard let observer else { return false }
    return RunLoops.state(runLoop)?.contains(observer: observer) ?? false
}

@c(_CFRunLoopObserverInvalidate)
public func CFRunLoopObserverInvalidate(_ observer: UnsafeMutableRawPointer?) {
    RunLoopObservers.storage(observer)?.valid = false
}

@c(_CFRunLoopObserverIsValid)
public func CFRunLoopObserverIsValid(_ observer: UnsafeMutableRawPointer?) -> Bool {
    RunLoopObservers.storage(observer)?.valid ?? false
}

@c(_CFRunLoopObserverGetActivities)
public func CFRunLoopObserverGetActivities(_ observer: UnsafeMutableRawPointer?) -> UInt {
    RunLoopObservers.storage(observer)?.activities ?? 0
}

@c(_CFRunLoopPerformBlock)
public func CFRunLoopPerformBlock(_ runLoop: UnsafeMutableRawPointer?, _ mode: UnsafeMutableRawPointer?,
                                  _ block: UnsafeMutableRawPointer?) {
    guard let block else { return }
    RunLoops.state(runLoop)?.perform(block)
}
