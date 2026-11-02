import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An NSTimer's state. The timer retains its target, user info and block
/// until it is invalidated, as Foundation's does.
final class TimerStorage {
    var fireDate: Double
    let interval: Double
    let repeats: Bool
    private(set) var target: id?
    let selector: SEL?
    private(set) var userInfo: id?
    private(set) var block: id?
    /// For performSelector:withObject:afterDelay:, which sends the argument
    /// rather than the timer.
    private(set) var argument: id?
    let isPerformRequest: Bool
    private(set) var isValid = true
    var runLoops: [RunLoopState] = []

    init(fireDate: Double, interval: Double, repeats: Bool, target: id?, selector: SEL?, userInfo: id?,
         block: id?, argument: id? = nil, isPerformRequest: Bool = false) {
        self.fireDate = fireDate
        self.interval = interval
        self.repeats = repeats
        self.target = ObjC.retain(target)
        self.selector = selector
        self.userInfo = ObjC.retain(userInfo)
        self.block = ObjC.retainBlock(block)
        self.argument = ObjC.retain(argument)
        self.isPerformRequest = isPerformRequest
    }

    deinit {
        releaseReferences()
    }

    func invalidate() {
        isValid = false
        releaseReferences()
    }

    private func releaseReferences() {
        let objects = [target, userInfo, block, argument]
        target = nil
        userInfo = nil
        block = nil
        argument = nil
        for object in objects { ObjC.release(object) }
    }
}

enum Timers {
    nonisolated(unsafe) static var timerClass: Class!

    static func storage(_ timer: id?) -> TimerStorage? {
        Storage.get(timer, as: TimerStorage.self)
    }

    static func fireDate(_ timer: id) -> Double {
        storage(timer)?.fireDate ?? .infinity
    }

    static func isValid(_ timer: id) -> Bool {
        storage(timer)?.isValid ?? false
    }

    /// A new timer, retained (+1).
    static func make(_ storage: TimerStorage) -> id {
        let timer = Storage.allocate(UnsafeMutableRawPointer(timerClass))!
        Storage.set(timer, storage)
        return timer
    }

    /// Schedules `storage` on the current run loop; returns it autoreleased.
    static func schedule(_ storage: TimerStorage) -> id? {
        let timer = make(storage)
        add(timer, to: RunLoops.current)
        return ObjC.autorelease(timer)
    }

    static func add(_ timer: id, to runLoop: RunLoopState) {
        guard let storage = storage(timer), storage.isValid else { return }
        if !storage.runLoops.contains(where: { $0 === runLoop }) {
            storage.runLoops.append(runLoop)
        }
        runLoop.add(timer)
    }

    static func invalidate(_ timer: id) {
        guard let storage = storage(timer), storage.isValid else { return }
        let loops = storage.runLoops
        storage.runLoops.removeAll()
        storage.invalidate()
        for loop in loops { loop.remove(timer) }
    }

    /// Fires a timer: sends its message or calls its block, then reschedules
    /// a repeating timer past now (missed fires are skipped) or invalidates
    /// a one-shot one.
    static func fire(_ timer: id, from runLoop: RunLoopState?) {
        guard let storage = storage(timer), storage.isValid else { return }
        if let block = storage.block {
            Blocks.invoke(block, as: (@convention(c) (id, id?) -> Void).self)(block, timer)
        } else if let selector = storage.selector {
            _ = ObjC.send(storage.target, selector, storage.isPerformRequest ? storage.argument : timer)
        }
        guard storage.isValid else { return }
        if storage.repeats {
            let now = absoluteTimeNow()
            repeat {
                storage.fireDate += storage.interval
            } while storage.fireDate <= now
        } else {
            invalidate(timer)
        }
    }

    static func install(superclass: Class) {
        timerClass = ClassDefinition(PERRY_CLASS_NSTimer, name: "NSTimer", superclass: superclass,
                                     StorageAllocation.self, NSTimerMethods.self).cls
    }

    /// Repeating timers fire at least every 0.1 ms, as Foundation clamps them.
    static func clamp(_ interval: Double) -> Double {
        max(interval, 0.0001)
    }
}

@ObjCImplementation
enum NSTimerMethods {
    @ObjCClassMethod("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:")
    static func scheduled(_ cls: id?, interval: Double, target: id?, selector: SEL?, userInfo: id?,
                          repeats: Bool) -> id? {
        Timers.schedule(TimerStorage(fireDate: absoluteTimeNow() + interval, interval: Timers.clamp(interval),
                                     repeats: repeats, target: target, selector: selector, userInfo: userInfo,
                                     block: nil))
    }

    @ObjCClassMethod("timerWithTimeInterval:target:selector:userInfo:repeats:")
    static func timer(_ cls: id?, interval: Double, target: id?, selector: SEL?, userInfo: id?, repeats: Bool) -> id? {
        ObjC.autorelease(Timers.make(TimerStorage(fireDate: absoluteTimeNow() + interval,
                                                  interval: Timers.clamp(interval), repeats: repeats, target: target,
                                                  selector: selector, userInfo: userInfo, block: nil)))
    }

    @ObjCClassMethod("scheduledTimerWithTimeInterval:repeats:block:")
    static func scheduled(_ cls: id?, interval: Double, repeats: Bool, block: ObjCBlock?) -> id? {
        Timers.schedule(TimerStorage(fireDate: absoluteTimeNow() + interval, interval: Timers.clamp(interval),
                                     repeats: repeats, target: nil, selector: nil, userInfo: nil, block: block))
    }

    @ObjCClassMethod("timerWithTimeInterval:repeats:block:")
    static func timer(_ cls: id?, interval: Double, repeats: Bool, block: ObjCBlock?) -> id? {
        ObjC.autorelease(Timers.make(TimerStorage(fireDate: absoluteTimeNow() + interval,
                                                  interval: Timers.clamp(interval), repeats: repeats, target: nil,
                                                  selector: nil, userInfo: nil, block: block)))
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ timer: id?) {
        guard let timer else { return }
        Storage.set(timer, nil)
        ObjC.superDealloc(timer, from: Timers.timerClass)
    }

    @ObjCMethod("invalidate")
    static func invalidate(_ timer: id?) {
        if let timer { Timers.invalidate(timer) }
    }

    @ObjCMethod("isValid")
    static func isValid(_ timer: id?) -> Bool { timer.map(Timers.isValid) ?? false }

    /// Fires now without changing the schedule of a repeating timer.
    @ObjCMethod("fire")
    static func fire(_ timer: id?) {
        guard let timer, let storage = Timers.storage(timer), storage.isValid else { return }
        if storage.repeats {
            let next = storage.fireDate
            Timers.fire(timer, from: nil)
            storage.fireDate = next
        } else {
            Timers.fire(timer, from: nil)
        }
    }

    @ObjCMethod("fireDate")
    static func fireDate(_ timer: id?) -> id? { Dates.autoreleased(Timers.storage(timer)?.fireDate ?? 0) }

    @ObjCMethod("setFireDate:")
    static func setFireDate(_ timer: id?, _ date: id?) {
        Timers.storage(timer)?.fireDate = Dates.interval(date)
        Timers.storage(timer)?.runLoops.forEach { $0.wakeUp() }
    }

    @ObjCMethod("timeInterval")
    static func timeInterval(_ timer: id?) -> Double {
        guard let storage = Timers.storage(timer), storage.repeats else { return 0 }
        return storage.interval
    }

    @ObjCMethod("userInfo")
    static func userInfo(_ timer: id?) -> id? { Timers.storage(timer)?.userInfo }

    @ObjCMethod("tolerance")
    static func tolerance(_ timer: id?) -> Double { 0 }

    @ObjCMethod("setTolerance:")
    static func setTolerance(_ timer: id?, _ tolerance: Double) {}
}

/// Delayed performs, which Foundation adds to NSObject.
@ObjCImplementation
enum NSObjectDelayedPerformMethods {
    @ObjCMethod("performSelector:withObject:afterDelay:")
    static func perform(_ object: id?, _ selector: SEL?, with argument: id?, afterDelay delay: Double) {
        let request = Timers.make(TimerStorage(fireDate: absoluteTimeNow() + delay, interval: 0, repeats: false,
                                               target: object, selector: selector, userInfo: nil, block: nil,
                                               argument: argument, isPerformRequest: true))
        Timers.add(request, to: RunLoops.current)
        ObjC.release(request)
    }

    @ObjCMethod("performSelector:withObject:afterDelay:inModes:")
    static func perform(_ object: id?, _ selector: SEL?, with argument: id?, afterDelay delay: Double, inModes modes: id?) {
        perform(object, selector, with: argument, afterDelay: delay)
    }

    @ObjCClassMethod("cancelPreviousPerformRequestsWithTarget:")
    static func cancel(_ cls: id?, target: id?) {
        RunLoops.current.cancelPerformRequests { $0.target == target }
    }

    @ObjCClassMethod("cancelPreviousPerformRequestsWithTarget:selector:object:")
    static func cancel(_ cls: id?, target: id?, selector: SEL?, object argument: id?) {
        RunLoops.current.cancelPerformRequests {
            $0.target == target && $0.selector == selector && $0.argument == argument
        }
    }
}

extension RunLoopState {
    /// Invalidates pending performSelector:afterDelay: requests that match.
    func cancelPerformRequests(where matches: (TimerStorage) -> Bool) {
        for timer in snapshotTimers() {
            if let storage = Timers.storage(timer), storage.isPerformRequest, matches(storage) {
                Timers.invalidate(timer)
            }
        }
    }
}
