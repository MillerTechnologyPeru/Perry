import CPerryGeometry
import PerryObjCInterop

// Messages AppKit sends by selector, so that an app's subclasses and
// delegates get them as on Darwin: AppKit's own calls to methods apps
// override (-sendEvent:, -mouseDown:, -setFrameSize:, -viewDidMoveToWindow,
// delegate callbacks) go through objc_msgSend, never straight to the Swift
// method.

enum Send {
    typealias Object = UnsafeMutableRawPointer
    typealias Selector = UnsafeRawPointer

    static func responds(_ receiver: Object?, _ selector: String) -> Bool {
        guard let receiver else { return false }
        return NSObject(receiver).responds(to: selector)
    }

    static func void(_ receiver: Object?, _ selector: String) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }

    static func void(_ receiver: Object?, _ selector: String, _ argument: Object?) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, Object?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    static func void(_ receiver: Object?, _ selector: String, _ first: Object?, _ second: Object?) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, Object?, Object?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second)
    }

    static func void(_ receiver: Object?, _ selector: String, size: CGSize) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, CGSize) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), size)
    }

    static func void(_ receiver: Object?, _ selector: String, rect: CGRect) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, CGRect) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), rect)
    }

    static func void(_ receiver: Object?, _ selector: String, point: CGPoint) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, CGPoint) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), point)
    }

    static func void(_ receiver: Object?, _ selector: String, bool: Bool) {
        guard let receiver else { return }
        typealias F = @convention(c) (Object, Selector, Bool) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), bool)
    }

    static func bool(_ receiver: Object?, _ selector: String) -> Bool {
        guard let receiver else { return false }
        typealias F = @convention(c) (Object, Selector) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }

    static func bool(_ receiver: Object?, _ selector: String, _ argument: Object?) -> Bool {
        guard let receiver else { return false }
        typealias F = @convention(c) (Object, Selector, Object?) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    static func uint(_ receiver: Object?, _ selector: String, _ argument: Object?) -> UInt {
        guard let receiver else { return 0 }
        typealias F = @convention(c) (Object, Selector, Object?) -> UInt
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    static func object(_ receiver: Object?, _ selector: String) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }

    static func object(_ receiver: Object?, _ selector: String, _ argument: Object?) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    /// -nextEventMatchingMask:untilDate:inMode:dequeue:
    static func nextEvent(_ receiver: Object, mask: UInt64, until date: Object?, mode: Object?, dequeue: Bool) -> Object? {
        typealias F = @convention(c) (Object, Selector, UInt64, Object?, Object?, Bool) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector("nextEventMatchingMask:untilDate:inMode:dequeue:"),
                                                              mask, date, mode, dequeue)
    }

    /// -hitTest: on a view, with a point in its superview's coordinates.
    static func hitTest(_ receiver: Object, _ point: CGPoint) -> Object? {
        typealias F = @convention(c) (Object, Selector, CGPoint) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector("hitTest:"), point)
    }

    static func rect(_ receiver: Object, _ selector: String) -> CGRect {
        typealias F = @convention(c) (Object, Selector) -> CGRect
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }

    /// The delegate's -applicationShouldTerminate: and the like, which
    /// return an NSUInteger.
    static func reply(_ receiver: Object?, _ selector: String, _ argument: Object?) -> UInt? {
        guard responds(receiver, selector) else { return nil }
        return uint(receiver, selector, argument)
    }
}
