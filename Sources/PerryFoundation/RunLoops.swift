import CPerryFoundation
import Glibc
import PerryObjCInterop

/// A thread's run loop. Perry's run loops have timers and no other input
/// sources yet, and every mode runs every timer.
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
    private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)

    init() {
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(condition, nil)
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
        pthread_mutex_lock(mutex)
        pthread_cond_broadcast(condition)
        pthread_mutex_unlock(mutex)
    }

    /// Runs timers until `limit` (absolute time), a stop, or no timers.
    /// With `waitWhenEmpty`, running out of timers waits for `limit` instead,
    /// as a Darwin run loop with an input source does.
    func run(until limit: Double, returnAfterSourceHandled: Bool = false, waitWhenEmpty: Bool = false) -> Result {
        while true {
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
                guard waitWhenEmpty, limit.isFinite, now < limit else { return .finished }
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

    /// Sleeps until `deadline` or a wake-up.
    private func wait(until deadline: Double) {
        let unix = deadline + referenceDateOffset
        var time = timespec()
        if unix.isFinite && unix < Double(Int32.max) {
            time.tv_sec = Int(unix)
            time.tv_nsec = Int((unix - floor(unix)) * 1e9)
        } else {
            time.tv_sec = Int(Int32.max)
        }
        pthread_mutex_lock(mutex)
        if !stopRequested {
            _ = pthread_cond_timedwait(condition, mutex, &time)
        }
        pthread_mutex_unlock(mutex)
    }
}

enum RunLoops {
    nonisolated(unsafe) static var runLoopClass: Class!
    nonisolated(unsafe) private static var main: RunLoopState?
    nonisolated(unsafe) private static var mainThread: pthread_t?

    static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    /// The run loop of the thread that started the program.
    static var mainLoop: RunLoopState {
        if let main { return main }
        let created = RunLoopState()
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
        let created = RunLoopState()
        pthread_setspecific(key, Unmanaged.passRetained(created).toOpaque())
        return created
    }

    static func state(_ object: id?) -> RunLoopState? {
        Storage.get(object, as: RunLoopState.self)
    }

    /// The mode name constants, which NSRunLoop and CFRunLoop share.
    nonisolated(unsafe) static var defaultMode: id!

    static func install(superclass: Class) {
        mainThread = pthread_self()
        runLoopClass = ClassDefinition(PERRY_CLASS_NSRunLoop, name: "NSRunLoop", superclass: superclass,
                                       NSRunLoop.register).cls
        defaultMode = Strings.make("kCFRunLoopDefaultMode")
        let commonModes = Strings.make("kCFRunLoopCommonModes")
        perry_foundation_constant(PERRY_CONSTANT_NSDefaultRunLoopMode).pointee = defaultMode
        perry_foundation_constant(PERRY_CONSTANT_kCFRunLoopDefaultMode).pointee = defaultMode
        perry_foundation_constant(PERRY_CONSTANT_NSRunLoopCommonModes).pointee = commonModes
        perry_foundation_constant(PERRY_CONSTANT_kCFRunLoopCommonModes).pointee = commonModes
    }
}

/// NSRunLoop.
@ObjCClass("NSRunLoop")
public struct NSRunLoop {}

@ObjCImplementation
extension NSRunLoop {
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
    func currentMode() -> UnsafeMutableRawPointer? { RunLoops.defaultMode }

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
        guard let state, state.hasTimers else { return false }
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
