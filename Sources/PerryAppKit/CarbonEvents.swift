import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// What Cocoa apps call of Carbon's Event Manager (which the loader maps to
// AppKit): its clock, which is NSEvent's, and the event targets and
// handlers they install for things AppKit tells them of otherwise. The
// handlers are kept but not called: events come to the app as NSEvents.

/// EventTime GetCurrentEventTime(void): seconds since boot, as an NSEvent's
/// timestamp is.
@c(_GetCurrentEventTime) public func GetCurrentEventTime() -> Double { Clock.now }

/// The main event loop and the application's and dispatcher's event
/// targets: tokens that stand for them.
private enum CarbonTargets {
    nonisolated(unsafe) static var loop = UInt8(0), application = UInt8(0), dispatcher = UInt8(0)
}

@c(_GetMainEventLoop) public func GetMainEventLoop() -> UnsafeMutableRawPointer? { pointer(&CarbonTargets.loop) }
@c(_GetCurrentEventLoop) public func GetCurrentEventLoop() -> UnsafeMutableRawPointer? { pointer(&CarbonTargets.loop) }
@c(_GetApplicationEventTarget) public func GetApplicationEventTarget() -> UnsafeMutableRawPointer? { pointer(&CarbonTargets.application) }
@c(_GetEventDispatcherTarget) public func GetEventDispatcherTarget() -> UnsafeMutableRawPointer? { pointer(&CarbonTargets.dispatcher) }

private func pointer(_ token: UnsafeMutablePointer<UInt8>) -> UnsafeMutableRawPointer { UnsafeMutableRawPointer(token) }

/// An installed handler's reference: its record, until it is removed.
private final class CarbonHandler {
    let target: UnsafeMutableRawPointer?
    let handler: UnsafeMutableRawPointer?
    let types: [(UInt32, UInt32)]
    let userData: UnsafeMutableRawPointer?
    init(target: UnsafeMutableRawPointer?, handler: UnsafeMutableRawPointer?, types: [(UInt32, UInt32)], userData: UnsafeMutableRawPointer?) {
        self.target = target
        self.handler = handler
        self.types = types
        self.userData = userData
    }
}

nonisolated(unsafe) private var carbonHandlers: [UnsafeMutableRawPointer: CarbonHandler] = [:]

/// OSStatus InstallEventHandler(EventTargetRef, EventHandlerUPP, ItemCount,
/// const EventTypeSpec *, void *userData, EventHandlerRef *).
@c(_InstallEventHandler)
public func InstallEventHandler(_ target: UnsafeMutableRawPointer?, _ handler: UnsafeMutableRawPointer?, _ count: Int,
                                _ types: UnsafePointer<UInt32>?, _ userData: UnsafeMutableRawPointer?,
                                _ reference: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard target != nil, handler != nil else { return -50 }
    let specs = (0..<max(count, 0)).map { index in (types?[index * 2] ?? 0, types?[index * 2 + 1] ?? 0) }
    let record = CarbonHandler(target: target, handler: handler, types: specs, userData: userData)
    let key = Unmanaged.passRetained(record).toOpaque()
    carbonHandlers[key] = record
    reference?.pointee = key
    return 0
}

@c(_RemoveEventHandler)
public func RemoveEventHandler(_ reference: UnsafeMutableRawPointer?) -> Int32 {
    guard let reference, carbonHandlers.removeValue(forKey: reference) != nil else { return -9876 }  // eventHandlerNotFoundErr
    Unmanaged<CarbonHandler>.fromOpaque(reference).release()
    return 0
}

// MARK: - Receiving events

// An EventRef here is the NSEvent it stands for: Cocoa's events are
// Carbon's underneath on a Mac, and a Cocoa app that pumps them with
// ReceiveNextEvent and SendEventToEventTarget has them go to NSApp.

/// OSStatus ReceiveNextEvent(ItemCount, const EventTypeSpec *, EventTimeout,
/// Boolean pull, EventRef *): the next event, waiting for one up to the
/// timeout (kEventDurationForever, -1, for ever) while timers and the main
/// queue run, as the run loop does on a Mac; eventLoopTimedOutErr if none
/// came. A pulled event is the caller's to release.
@c(_ReceiveNextEvent)
public func ReceiveNextEvent(_ count: Int, _ types: UnsafeRawPointer?, _ timeout: Double, _ pull: UInt8,
                             _ event: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    event?.pointee = nil
    guard let app = App.shared else {
        RunLoop.run(for: max(timeout, 0))
        return -9875                                    // eventLoopTimedOutErr
    }
    let deadline = timeout < 0 ? NSDate.distantFuture() : NSDate.make(timeIntervalSinceReferenceDate: Clock.absolute + timeout)
    guard let next = app.nextEvent(matching: UInt.max, until: deadline, inMode: nil, dequeue: pull != 0) else { return -9875 }
    event?.pointee = pull != 0 ? ObjCRuntime.retain(next.objcObject) : next.objcObject
    return 0
}

/// OSStatus SendEventToEventTarget(EventRef, EventTargetRef): to NSApp,
/// which sends it on to the window it is for.
@c(_SendEventToEventTarget)
public func SendEventToEventTarget(_ event: UnsafeMutableRawPointer?, _ target: UnsafeMutableRawPointer?) -> Int32 {
    guard let event, let app = App.shared else { return -9874 }   // eventNotHandledErr
    app.sendEvent(NSObject(event))
    return 0
}

/// OSStatus RunCurrentEventLoop(EventTimeout): events and the run loop's
/// sources handled for that long; eventLoopTimedOutErr when it passes.
@c(_RunCurrentEventLoop)
public func RunCurrentEventLoop(_ timeout: Double) -> Int32 {
    let end = Clock.now + max(timeout, 0)
    repeat {
        var event: UnsafeMutableRawPointer?
        let wait = timeout < 0 ? 1.0 : max(end - Clock.now, 0)
        if ReceiveNextEvent(0, nil, wait, 1, &event) == 0, let event {
            _ = SendEventToEventTarget(event, nil)
            ObjCRuntime.release(event)
        }
    } while timeout < 0 || Clock.now < end
    return -9875
}

@c(_RetainEvent) public func RetainEvent(_ event: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(event) }
@c(_ReleaseEvent) public func ReleaseEvent(_ event: UnsafeMutableRawPointer?) { ObjCRuntime.release(event) }

/// OSStatus SetSystemUIMode(SystemUIMode, SystemUIOptions): the menu bar
/// and Dock are hidden by a window's being full screen here.
@c(_SetSystemUIMode) public func SetSystemUIMode(_ mode: UInt32, _ options: UInt32) -> Int32 { 0 }
#endif
