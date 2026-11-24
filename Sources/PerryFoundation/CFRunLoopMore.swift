import CPerryFoundation
import Glibc
import PerryObjCInterop

// The rest of CFRunLoop's C API: type IDs, common modes, running a given
// run loop, and the getters of sources, observers and timers; and the
// suspension of notification centers. The type IDs are Darwin's.

// MARK: - Type IDs

@c(_CFRunLoopGetTypeID) public func CFRunLoopGetTypeID() -> UInt { CFTypeIDs.runLoop }
@c(_CFRunLoopObserverGetTypeID) public func CFRunLoopObserverGetTypeID() -> UInt { 45 }
@c(_CFRunLoopSourceGetTypeID) public func CFRunLoopSourceGetTypeID() -> UInt { 46 }
@c(_CFRunLoopTimerGetTypeID) public func CFRunLoopTimerGetTypeID() -> UInt { 47 }
@c(_CFNotificationCenterGetTypeID) public func CFNotificationCenterGetTypeID() -> UInt { 52 }

// MARK: - CFRunLoop

/// Makes `mode` one of the run loop's common modes. Every mode is the same
/// run loop here, so this only records the name, which CFRunLoopCopyAllModes
/// then lists; what is added to the common modes runs in it already.
@c(_CFRunLoopAddCommonMode)
public func CFRunLoopAddCommonMode(_ runLoop: UnsafeMutableRawPointer?, _ mode: UnsafeMutableRawPointer?) {
    guard let state = RunLoops.state(runLoop), let name = Strings.value(of: mode) else { return }
    state.addCommonMode(name)
}

/// Whether the source is on the run loop. Every mode is the same run loop
/// here, so the mode is not looked at.
@c(_CFRunLoopContainsSource)
public func CFRunLoopContainsSource(_ runLoop: UnsafeMutableRawPointer?, _ source: UnsafeMutableRawPointer?,
                                    _ mode: UnsafeMutableRawPointer?) -> Bool {
    guard let loop = RunLoops.state(runLoop), let source else { return false }
    if let custom = Storage.get(source, as: CustomSourceStorage.self) { return custom.isScheduled(on: loop) }
    guard let storage = Sockets.storage(Sockets.source(source)?.socket) else { return false }
    return Sockets.locked { storage.loops.contains { $0 === loop } }
}

/// Whether the run loop is asleep, waiting for a source, a timer or a
/// wake-up; false while it runs something, or is not running.
@c(_CFRunLoopIsWaiting)
public func CFRunLoopIsWaiting(_ runLoop: UnsafeMutableRawPointer?) -> Bool {
    RunLoops.state(runLoop)?.isWaiting ?? false
}

/// Runs the given run loop, as CFRunLoopRunInMode runs the current
/// thread's, and gives the same results (kCFRunLoopRunFinished and so on).
/// Every mode is the same run loop here, so the mode is not looked at. As
/// on Darwin, a run loop should only be run on its own thread.
@DarwinC("_CFRunLoopRunSpecific")
public func CFRunLoopRunSpecific(_ runLoop: UnsafeMutableRawPointer?, _ mode: UnsafeMutableRawPointer?, _ seconds: Double,
                                 _ returnAfterSourceHandled: Bool) -> Int32 {
    guard let state = RunLoops.state(runLoop) else { return RunLoopState.Result.finished.rawValue }
    // A loop with an input source waits for it, as on Darwin.
    return state.run(until: absoluteTimeNow() + seconds, returnAfterSourceHandled: returnAfterSourceHandled,
                     waitWhenEmpty: state.ports > 0 ? true : nil).rawValue
}

// MARK: - CFRunLoopSource

/// The order the source was made with. A socket's source doesn't record
/// its order here, so it gives 0.
@c(_CFRunLoopSourceGetOrder)
public func CFRunLoopSourceGetOrder(_ source: UnsafeMutableRawPointer?) -> Int {
    Storage.get(source, as: CustomSourceStorage.self)?.order ?? 0
}

/// void CFRunLoopSourceGetContext(source, CFRunLoopSourceContext *): as on
/// Darwin, as many words of the source's context as the caller's version
/// asks for (10 for version 0, 8 for version 1), with the info the source
/// keeps. A source CFRunLoopSourceCreate made gives back its context; a
/// port's or descriptor's gives its info, release and perform; a socket's
/// gives version 0 with the socket as info and the rest zero.
@c(_CFRunLoopSourceGetContext)
public func CFRunLoopSourceGetContext(_ source: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let count = context.load(as: Int.self) == 1 ? 8 : 10
    var words = [UInt](repeating: 0, count: 10)
    if let custom = Storage.get(source, as: CustomSourceStorage.self) {
        if custom.contextWords.count == 10 {
            words = custom.contextWords
        } else {
            words[3] = custom.release.map { UInt(bitPattern: unsafeBitCast($0, to: UnsafeRawPointer.self)) } ?? 0
            words[7] = custom.schedule.map { UInt(bitPattern: unsafeBitCast($0, to: UnsafeRawPointer.self)) } ?? 0
            words[8] = custom.cancel.map { UInt(bitPattern: unsafeBitCast($0, to: UnsafeRawPointer.self)) } ?? 0
            words[9] = custom.perform.map { UInt(bitPattern: unsafeBitCast($0, to: UnsafeRawPointer.self)) } ?? 0
        }
        words[1] = custom.info.map { UInt(bitPattern: $0) } ?? 0
    } else if let socket = Sockets.source(source)?.socket {
        words[1] = UInt(bitPattern: socket)
    }
    for index in 0..<count {
        context.storeBytes(of: words[index], toByteOffset: index * DarwinLayout.word, as: UInt.self)
    }
}

// MARK: - CFRunLoopObserver

@c(_CFRunLoopObserverDoesRepeat)
public func CFRunLoopObserverDoesRepeat(_ observer: UnsafeMutableRawPointer?) -> Bool {
    RunLoopObservers.storage(observer)?.repeats ?? false
}

@c(_CFRunLoopObserverGetOrder)
public func CFRunLoopObserverGetOrder(_ observer: UnsafeMutableRawPointer?) -> Int {
    RunLoopObservers.storage(observer)?.order ?? 0
}

/// void CFRunLoopObserverGetContext(observer, CFRunLoopObserverContext *):
/// the context the observer was made with, version 0, with the info it
/// keeps; all zero for one made with a block.
@c(_CFRunLoopObserverGetContext)
public func CFRunLoopObserverGetContext(_ observer: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let word = DarwinLayout.word
    context.initializeMemory(as: UInt8.self, repeating: 0, count: word * 5)
    guard let storage = RunLoopObservers.storage(observer) else { return }
    context.storeBytes(of: storage.info, toByteOffset: DarwinLayout.contextInfo, as: UnsafeMutableRawPointer?.self)
    context.storeBytes(of: storage.retainInfo, toByteOffset: DarwinLayout.contextRetain, as: UnsafeRawPointer?.self)
    context.storeBytes(of: storage.release.map { unsafeBitCast($0, to: UnsafeRawPointer.self) },
                       toByteOffset: DarwinLayout.contextRelease, as: UnsafeRawPointer?.self)
    context.storeBytes(of: storage.copyDescription, toByteOffset: DarwinLayout.contextRelease + word, as: UnsafeRawPointer?.self)
}

// MARK: - CFRunLoopTimer

/// What a CFRunLoopTimer has beyond an NSTimer's storage: the order it was
/// made with and its tolerance. Kept beside the timers, weakly, so an entry
/// goes with its timer.
enum RunLoopTimerExtras {
    final class Entry {
        weak var timer: TimerStorage?
        var order = 0
        var tolerance = 0.0
        init(_ timer: TimerStorage) { self.timer = timer }
    }

    nonisolated(unsafe) private static var entries: [ObjectIdentifier: Entry] = [:]
    nonisolated(unsafe) private static let lock = NSLockStorage()

    /// The timer's entry, made if `creating`; under the lock.
    private static func entry(_ timer: TimerStorage, creating: Bool) -> Entry? {
        let key = ObjectIdentifier(timer)
        if let entry = entries[key], entry.timer === timer { return entry }
        guard creating else { return nil }
        // Entries of timers gone are dropped as new ones come.
        entries = entries.filter { $0.value.timer != nil }
        let entry = Entry(timer)
        entries[key] = entry
        return entry
    }

    static func set(order: Int, of timer: TimerStorage) {
        guard order != 0 else { return }
        _ = lock.locked { entry(timer, creating: true)?.order = order }
    }

    static func order(of timer: TimerStorage) -> Int { lock.locked { entry(timer, creating: false)?.order ?? 0 } }

    static func set(tolerance: Double, of timer: TimerStorage) {
        _ = lock.locked { entry(timer, creating: true)?.tolerance = tolerance }
    }

    static func tolerance(of timer: TimerStorage) -> Double {
        lock.locked { entry(timer, creating: false)?.tolerance ?? 0 }
    }
}

/// The order the timer was made with; 0 for an NSTimer.
@c(_CFRunLoopTimerGetOrder)
public func CFRunLoopTimerGetOrder(_ timer: UnsafeMutableRawPointer?) -> Int {
    guard let storage = Timers.storage(timer) else { return 0 }
    return RunLoopTimerExtras.order(of: storage)
}

/// The tolerance last set, 0 until one is.
@DarwinC("_CFRunLoopTimerGetTolerance")
public func CFRunLoopTimerGetTolerance(_ timer: UnsafeMutableRawPointer?) -> Double {
    guard let storage = Timers.storage(timer) else { return 0 }
    return RunLoopTimerExtras.tolerance(of: storage)
}

/// Records the tolerance, a negative one as 0, for CFRunLoopTimerGetTolerance.
/// Timers here fire when they come due, without coalescing, which a
/// tolerance only allows and never requires.
@DarwinC("_CFRunLoopTimerSetTolerance")
public func CFRunLoopTimerSetTolerance(_ timer: UnsafeMutableRawPointer?, _ tolerance: Double) {
    guard let storage = Timers.storage(timer), storage.isValid else { return }
    RunLoopTimerExtras.set(tolerance: tolerance > 0 ? tolerance : 0, of: storage)
}

// MARK: - CFNotificationCenter

/// The suspension of the distributed center, which is all that is ever
/// suspended on Darwin; other centers never are.
nonisolated(unsafe) private var distributedCenterSuspended = false

/// Whether the center is suspended: only the distributed center can be,
/// when CFNotificationCenterSetSuspended said so.
@c(_CFNotificationCenterIsSuspended)
public func CFNotificationCenterIsSuspended(_ center: id?) -> Bool {
    guard let center, center == CFNotificationCenterGetDistributedCenter() else { return false }
    return distributedCenterSuspended
}

/// Suspends or resumes the distributed center; others are left alone, as
/// on Darwin. This is only recorded: notifications are delivered at once
/// here, as no other process sends them to be held.
@c(_CFNotificationCenterSetSuspended)
public func CFNotificationCenterSetSuspended(_ center: id?, _ suspended: UInt8) {
    guard let center, center == CFNotificationCenterGetDistributedCenter() else { return }
    distributedCenterSuspended = suspended != 0
}
