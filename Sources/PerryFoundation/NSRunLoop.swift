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
        let waitWhenEmpty = waitWhenEmpty ?? isMain
        while true {
            if servesMainQueue, MainDispatchQueue.isReady() {
                MainDispatchQueue.drain()
                if returnAfterSourceHandled { return .handledSource }
            }
            let next: (timer: id?, fire: Double)? = locked {
                if stopRequested {
                    stopRequested = false
                    return nil
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
        if locked({ stopRequested }) { return }
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

    @ObjCMethod("addTimer:forMode:")
    func add(_ timer: ObjCObject, forMode mode: ObjCObject?) {
        if Timers.isValid(timer.id) { state?.add(timer.id) }
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
        guard let state, state.hasTimers || state.servesMainQueue else { return false }
        _ = state.run(until: date.date.timeIntervalSinceReferenceDate)
        return true
    }
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
public func CFRunLoopRunInMode(_ mode: UnsafeMutableRawPointer?, _ seconds: Double,
                               _ returnAfterSourceHandled: Bool) -> Int32 {
    RunLoops.current.run(until: absoluteTimeNow() + seconds,
                         returnAfterSourceHandled: returnAfterSourceHandled).rawValue
}

@c(_CFRunLoopStop)
public func CFRunLoopStop(_ runLoop: UnsafeMutableRawPointer?) {
    RunLoops.state(runLoop)?.stop()
}

@c(_CFRunLoopWakeUp)
public func CFRunLoopWakeUp(_ runLoop: UnsafeMutableRawPointer?) {
    RunLoops.state(runLoop)?.wakeUp()
}
