import PerryObjCInterop

// UIKit's deferred work, done once the current event or timer callback
// returns, as Darwin does when Core Animation commits its transaction:
// navigation and presentation transitions, then the ends of appearance
// transitions begun since, then layout of the visible windows. Work is
// queued on the main dispatch queue, which the main run loop drains.

enum Updates {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias DispatchAsync = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    nonisolated(unsafe) static var dispatchAsync: DispatchAsync!
    nonisolated(unsafe) static var mainQueue: UnsafeMutableRawPointer?

    nonisolated(unsafe) private static var scheduled = false
    /// Transitions to run, in the order they were asked for.
    nonisolated(unsafe) private static var transitions: [() -> Void] = []
    /// View controllers whose appearance transitions end in the pass.
    nonisolated(unsafe) private static var appearanceEnds: [UIViewController] = []
    /// Work for once the pass is over.
    nonisolated(unsafe) private static var afterwards: [() -> Void] = []

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) -> Bool {
        let library = "/usr/lib/system/libdispatch.dylib"
        guard let async = lookup(library, "_dispatch_async_f"), let main = lookup(library, "__dispatch_main_q") else { return false }
        dispatchAsync = unsafeBitCast(async, to: DispatchAsync.self)
        mainQueue = main
        return true
    }

    /// Runs the pass soon, once.
    static func schedule() {
        guard !scheduled else { return }
        scheduled = true
        dispatchAsync(mainQueue, nil) { _ in Updates.run() }
    }

    /// Adds a transition to the next pass.
    static func transition(_ body: @escaping () -> Void) {
        transitions.append(body)
        schedule()
    }

    /// Ends `controller`'s appearance transition in the next pass.
    static func endAppearance(of controller: UIViewController) {
        appearanceEnds.append(controller)
        schedule()
    }

    /// Runs `body` once the next pass is over.
    static func afterPass(_ body: @escaping () -> Void) {
        afterwards.append(body)
        schedule()
    }

    /// Whether `controller` waits for its appearance transition to end.
    static func isPendingEnd(_ controller: UIViewController) -> Bool {
        appearanceEnds.contains { $0.objcObject == controller.objcObject }
    }

    static func run() {
        scheduled = false
        ObjCRuntime.autoreleasepool {
            while !transitions.isEmpty || !appearanceEnds.isEmpty {
                if !transitions.isEmpty {
                    let transition = transitions.removeFirst()
                    transition()
                    continue
                }
                let controller = appearanceEnds.removeFirst()
                controller.finishAppearance()
            }
            for window in Windows.visible { window.layoutIfNeeded() }
        }
        let after = afterwards
        afterwards = []
        for body in after { ObjCRuntime.autoreleasepool { body() } }
    }
}
