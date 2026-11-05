import CPerryFoundation
import FoundationEssentials
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
    /// Called after the timer fires, for performSelectorOnMainThread:…waitUntilDone:.
    var onFired: (() -> Void)?
    private(set) var isValid = true
    var runLoops: [RunLoopState] = []
    /// While its callout runs: a run loop run inside it (as apps pump
    /// events from a timer) doesn't fire it again, as CFRunLoop doesn't.
    var firing = false

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

    /// When it fires next; never while it is firing.
    static func fireDate(_ timer: id) -> Double {
        guard let storage = storage(timer), !storage.firing else { return .infinity }
        return storage.fireDate
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
    static func schedule(_ storage: TimerStorage) -> NSTimer {
        let timer = make(storage)
        add(timer, to: RunLoops.current)
        return NSTimer(objCOwned: timer)
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
        guard let storage = storage(timer), storage.isValid, !storage.firing else { return }
        storage.firing = true
        if let block = storage.block {
            Blocks.invoke(block, as: (@convention(c) (id, id?) -> Void).self)(block, timer)
        } else if let selector = storage.selector {
            _ = ObjC.send(storage.target, selector, storage.isPerformRequest ? storage.argument : timer)
        }
        storage.firing = false
        storage.onFired?()
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


    /// Repeating timers fire at least every 0.1 ms, as Foundation clamps them.
    static func clamp(_ interval: Double) -> Double {
        max(interval, 0.0001)
    }
}

/// NSTimer.
@ObjCClass("NSTimer")
public final class NSTimer: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Timers.timerClass = cls.storage
    }

    private var storage: TimerStorage? { Timers.storage(objcObject) }

    private static func make(_ interval: Double, repeats: Bool, target: ObjCObject?, selector: ObjCSelector?,
                             userInfo: ObjCObject?, block: ObjCBlock?) -> TimerStorage {
        TimerStorage(fireDate: absoluteTimeNow() + interval, interval: Timers.clamp(interval), repeats: repeats,
                     target: target?.id, selector: selector?.pointer.assumingMemoryBound(to: CChar.self),
                     userInfo: userInfo?.id, block: block?.object)
    }

    @ObjCClassMethod("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:")
    static func scheduled(interval: Double, target: ObjCObject, selector: ObjCSelector, userInfo: ObjCObject?,
                          repeats: Bool) -> NSTimer {
        Timers.schedule(make(interval, repeats: repeats, target: target, selector: selector, userInfo: userInfo, block: nil))
    }

    @ObjCClassMethod("timerWithTimeInterval:target:selector:userInfo:repeats:")
    static func timer(interval: Double, target: ObjCObject, selector: ObjCSelector, userInfo: ObjCObject?,
                      repeats: Bool) -> NSTimer {
        NSTimer(objCOwned: Timers.make(make(interval, repeats: repeats, target: target, selector: selector,
                                            userInfo: userInfo, block: nil)))
    }

    @ObjCClassMethod("scheduledTimerWithTimeInterval:repeats:block:")
    static func scheduled(interval: Double, repeats: Bool, block: ObjCBlock) -> NSTimer {
        Timers.schedule(make(interval, repeats: repeats, target: nil, selector: nil, userInfo: nil, block: block))
    }

    @ObjCClassMethod("timerWithTimeInterval:repeats:block:")
    static func timer(interval: Double, repeats: Bool, block: ObjCBlock) -> NSTimer {
        NSTimer(objCOwned: Timers.make(make(interval, repeats: repeats, target: nil, selector: nil, userInfo: nil,
                                            block: block)))
    }

    // MARK: Initializers, for timers allocated and then added to a run loop

    @ObjCMethod("initWithFireDate:interval:repeats:block:")
    func initialize(fireDate: NSDate, interval: Double, repeats: Bool, block: ObjCBlock) -> Self {
        let storage = NSTimer.make(interval, repeats: repeats, target: nil, selector: nil, userInfo: nil, block: block)
        storage.fireDate = fireDate.date.timeIntervalSinceReferenceDate
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("initWithFireDate:interval:target:selector:userInfo:repeats:")
    func initialize(fireDate: NSDate, interval: Double, target: ObjCObject, selector: ObjCSelector, userInfo: ObjCObject?,
                    repeats: Bool) -> Self {
        let storage = NSTimer.make(interval, repeats: repeats, target: target, selector: selector, userInfo: userInfo, block: nil)
        storage.fireDate = fireDate.date.timeIntervalSinceReferenceDate
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("initWithTimeInterval:repeats:block:")
    func initialize(interval: Double, repeats: Bool, block: ObjCBlock) -> Self {
        Storage.set(objcObject, NSTimer.make(interval, repeats: repeats, target: nil, selector: nil, userInfo: nil, block: block))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Timers.timerClass)
    }

    @ObjCMethod("invalidate")
    func invalidate() { Timers.invalidate(objcObject) }

    @ObjCMethod("isValid")
    func isValid() -> Bool { Timers.isValid(objcObject) }

    /// Fires now without changing the schedule of a repeating timer.
    @ObjCMethod("fire")
    func fire() {
        guard let storage, storage.isValid else { return }
        if storage.repeats {
            let next = storage.fireDate
            Timers.fire(objcObject, from: nil)
            storage.fireDate = next
        } else {
            Timers.fire(objcObject, from: nil)
        }
    }

    @ObjCMethod("fireDate")
    func fireDate() -> NSDate { Dates.wrapped(Date(timeIntervalSinceReferenceDate: storage?.fireDate ?? 0)) }

    @ObjCMethod("setFireDate:")
    func setFireDate(_ date: NSDate) {
        storage?.fireDate = date.date.timeIntervalSinceReferenceDate
        storage?.runLoops.forEach { $0.wakeUp() }
    }

    @ObjCMethod("timeInterval")
    func timeInterval() -> Double {
        guard let storage, storage.repeats else { return 0 }
        return storage.interval
    }

    @ObjCMethod("userInfo")
    func userInfo() -> ObjCObject? { storage?.userInfo.map(ObjCObject.init) }

    @ObjCMethod("tolerance") func tolerance() -> Double { 0 }
    @ObjCMethod("setTolerance:") func setTolerance(_ tolerance: Double) {}
}

/// Delayed performs, which Foundation adds to NSObject.
@ObjCCategory("DelayedPerforms")
extension NSObject {
    @ObjCMethod("performSelector:withObject:afterDelay:")
    func perform(_ selector: ObjCSelector, with argument: ObjCObject?, afterDelay delay: Double) {
        let request = Timers.make(TimerStorage(fireDate: absoluteTimeNow() + delay, interval: 0, repeats: false,
                                               target: objcObject, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                               userInfo: nil, block: nil, argument: argument?.id, isPerformRequest: true))
        Timers.add(request, to: RunLoops.current)
        ObjC.release(request)
    }

    @ObjCMethod("performSelector:withObject:afterDelay:inModes:")
    func perform(_ selector: ObjCSelector, with argument: ObjCObject?, afterDelay delay: Double, inModes modes: ObjCObject?) {
        perform(selector, with: argument, afterDelay: delay)
    }

    @ObjCClassMethod("cancelPreviousPerformRequestsWithTarget:")
    static func cancel(target: ObjCObject?) {
        RunLoops.current.cancelPerformRequests { $0.target == target?.id }
    }

    @ObjCClassMethod("cancelPreviousPerformRequestsWithTarget:selector:object:")
    static func cancel(target: ObjCObject?, selector: ObjCSelector?, object argument: ObjCObject?) {
        RunLoops.current.cancelPerformRequests {
            $0.target == target?.id && UnsafeRawPointer($0.selector) == selector?.pointer && $0.argument == argument?.id
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
