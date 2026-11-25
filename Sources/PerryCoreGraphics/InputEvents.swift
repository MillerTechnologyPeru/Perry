import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// When input last came, for CGEventSourceSecondsSinceLastEventType. There
// is no window server to ask; AppKit's application is, when there is one:
// its current event, the one it is handling, is noted each time the
// question is asked on the main thread. An NSEvent's timestamp is seconds
// since boot, CLOCK_MONOTONIC's, as the clock here is, and its type's
// number is CGEventType's for the input events. Before any input is seen,
// the time is since the question was first asked.

private let appKit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

@ObjCWrapper("NSThread")
class NSThread: NSObject {
    @ObjCClassMethod("isMainThread") static func isMainThread() -> Bool
}

extension NSObject {
    @ObjCMethod("currentEvent") func applicationCurrentEvent() -> NSObject?
    @ObjCMethod("type") func eventType() -> UInt
    @ObjCMethod("timestamp") func eventTimestamp() -> Double
}

enum InputEvents {
    /// CGEventType's input events: the mouse's buttons, moves and drags,
    /// keys, modifier keys, the scroll wheel and tablets.
    private static let inputTypes: Set<UInt32> = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 22, 23, 24, 25, 26, 27]
    /// kCGAnyInputEventType.
    private static let anyInput = UInt32.max

    private static let lock = Lock()
    nonisolated(unsafe) private static var last: [UInt32: Double] = [:]
    nonisolated(unsafe) private static var firstAsked: Double?

    static var now: Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    static func secondsSince(_ type: UInt32) -> Double {
        let event = currentInput()
        return lock.withLock {
            let time = now
            if firstAsked == nil { firstAsked = time }
            if let event {
                last[event.type] = max(last[event.type] ?? 0, event.timestamp)
                last[anyInput] = max(last[anyInput] ?? 0, event.timestamp)
            }
            return max(0, time - (last[type] ?? firstAsked ?? time))
        }
    }

    /// NSApp's current event's type and timestamp, if it is an input event
    /// and this is the main thread.
    private static func currentInput() -> (type: UInt32, timestamp: Double)? {
        guard "NSApplication".withCString({ ObjCRuntime.functions.getClass($0) }) != nil, NSThread.isMainThread(),
              let lookup = providerSymbolLookup,
              let slot = appKit.withCString({ library in "_NSApp".withCString { lookup(library, $0) } }),
              let app = slot.load(as: UnsafeMutableRawPointer?.self),
              let event = NSObject(objCArgument: app).applicationCurrentEvent() else { return nil }
        let type = UInt32(truncatingIfNeeded: event.eventType())
        guard inputTypes.contains(type) else { return nil }
        return (type, event.eventTimestamp())
    }
}
#endif
