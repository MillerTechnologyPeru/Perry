import CPerryGeometry
import Glibc
import PerryObjCInterop

// The other layer classes and the display link: CAEAGLLayer, which OpenGL
// ES contexts give storage from and present into (UIKit's EAGLContext),
// and CADisplayLink, which calls its target once a frame.

// MARK: - CAEAGLLayer

final class EAGLLayerState {
    var drawableProperties: NSObject?
    var presentsWithTransaction = false
}

@ObjCClass("CAEAGLLayer")
open class CAEAGLLayer: CALayer {
    var eagl = EAGLLayerState()

    /// Opaque, as Core Animation's.
    @ObjCMethod("init")
    public required init() {
        super.init()
        state.isOpaque = true
    }

    @ObjCMethod("initWithLayer:")
    public required init(layer: CALayer) { super.init(layer: layer) }

    @ObjCMethod("drawableProperties") func drawableProperties() -> NSObject? { eagl.drawableProperties }
    @ObjCMethod("setDrawableProperties:") func setDrawableProperties(_ properties: NSObject?) { eagl.drawableProperties = properties }
    @ObjCMethod("presentsWithTransaction") func presentsWithTransaction() -> Bool { eagl.presentsWithTransaction }
    @ObjCMethod("setPresentsWithTransaction:") func setPresentsWithTransaction(_ presents: Bool) { eagl.presentsWithTransaction = presents }
}

// MARK: - CADisplayLink

/// The frame clock: subscribers are called at their rates from the main
/// queue, checked 120 times a second.
enum Frames {
    final class Subscriber {
        let interval: Double
        var last = 0.0
        let tick: (Double) -> Void

        init(interval: Double, tick: @escaping (Double) -> Void) {
            self.interval = interval
            self.tick = tick
        }
    }

    nonisolated(unsafe) private static var subscribers: [ObjectIdentifier: Subscriber] = [:]
    nonisolated(unsafe) private static var running = false

    static func add(_ owner: AnyObject, framesPerSecond: Int, _ tick: @escaping (Double) -> Void) {
        subscribers[ObjectIdentifier(owner)] = Subscriber(interval: 1 / Double(max(framesPerSecond, 1)), tick: tick)
        guard !running else { return }
        running = true
        Dispatch.onMain(after: 1.0 / 120) { step() }
    }

    static func remove(_ owner: AnyObject) { subscribers[ObjectIdentifier(owner)] = nil }

    private static func step() {
        guard !subscribers.isEmpty else {
            running = false
            return
        }
        let now = Clock.now
        for subscriber in Array(subscribers.values) where now - subscriber.last >= subscriber.interval * 0.98 {
            subscriber.last = now
            ObjCRuntime.autoreleasepool { subscriber.tick(now) }
        }
        Dispatch.onMain(after: 1.0 / 120) { step() }
    }
}

final class DisplayLinkState {
    var target: NSObject?
    var selector: UnsafeRawPointer?
    var paused = false
    var preferredFramesPerSecond = 0
    var timestamp = 0.0
    var duration = 1.0 / 60
    var added = false
}

/// Calls its target once a frame, at the display's 60 a second or the
/// preferred rate, while added to a run loop and not paused.
@ObjCClass("CADisplayLink")
open class CADisplayLink: NSObject {
    var state = DisplayLinkState()

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { Frames.remove(state) }

    @ObjCClassMethod("displayLinkWithTarget:selector:")
    static func make(_ cls: ObjCClass, target: NSObject, selector: ObjCSelector) -> CADisplayLink {
        let link = cls.object.allocated().initialized().unsafeCast(to: CADisplayLink.self)
        (link.state.target, link.state.selector) = (target, selector.pointer)
        return link
    }

    /// The run loop retains the link, as it does on Darwin, until it is
    /// invalidated.
    @ObjCMethod("addToRunLoop:forMode:")
    func add(to runLoop: NSObject?, forMode mode: NSObject?) {
        guard !state.added else { return }
        state.added = true
        _ = ObjCRuntime.retain(objcObject)
        schedule()
    }

    @ObjCMethod("removeFromRunLoop:forMode:")
    func remove(from runLoop: NSObject?, forMode mode: NSObject?) { invalidate() }

    @ObjCMethod("invalidate")
    func invalidate() {
        guard state.added else { return }
        state.added = false
        Frames.remove(state)
        state.target = nil
        ObjCRuntime.release(objcObject)
    }

    private func schedule() {
        Frames.remove(state)
        guard state.added, !state.paused else { return }
        let rate = state.preferredFramesPerSecond > 0 ? min(state.preferredFramesPerSecond, 60) : 60
        state.duration = 1 / 60
        let object = objcObject
        Frames.add(state, framesPerSecond: rate) { time in
            let link = CADisplayLink.objCInstance(object, ownership: .retain)
            link.state.timestamp = time
            guard let target = link.state.target, let selector = link.state.selector else { return }
            typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(target.objcObject, selector, object)
        }
    }

    @ObjCMethod("isPaused") func isPaused() -> Bool { state.paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) {
        state.paused = paused
        schedule()
    }

    @ObjCMethod("preferredFramesPerSecond") func preferredFramesPerSecond() -> Int { state.preferredFramesPerSecond }
    @ObjCMethod("setPreferredFramesPerSecond:") func setPreferredFramesPerSecond(_ rate: Int) {
        state.preferredFramesPerSecond = rate
        schedule()
    }

    @ObjCMethod("frameInterval") func frameInterval() -> Int { state.preferredFramesPerSecond > 0 ? max(60 / state.preferredFramesPerSecond, 1) : 1 }
    @ObjCMethod("setFrameInterval:") func setFrameInterval(_ interval: Int) { setPreferredFramesPerSecond(60 / max(interval, 1)) }
    @ObjCMethod("timestamp") func timestamp() -> Double { state.timestamp }
    @ObjCMethod("targetTimestamp") func targetTimestamp() -> Double { state.timestamp + state.duration }
    @ObjCMethod("duration") func duration() -> Double { state.duration }
}

/// Core Animation's string constants.
@ObjCConstants
enum LayerConstants {
    static let kCAGravityCenter = "center"
    static let kCAGravityTop = "top"
    static let kCAGravityBottom = "bottom"
    static let kCAGravityLeft = "left"
    static let kCAGravityRight = "right"
    static let kCAGravityTopLeft = "topLeft"
    static let kCAGravityTopRight = "topRight"
    static let kCAGravityBottomLeft = "bottomLeft"
    static let kCAGravityBottomRight = "bottomRight"
    static let kCAGravityResize = "resize"
    static let kCAGravityResizeAspect = "resizeAspect"
    static let kCAGravityResizeAspectFill = "resizeAspectFill"
    static let kCALineCapButt = "butt"
    static let kCALineCapRound = "round"
    static let kCALineCapSquare = "square"
    static let kCALineJoinMiter = "miter"
    static let kCALineJoinRound = "round"
    static let kCALineJoinBevel = "bevel"
    static let kCAFillRuleNonZero = "non-zero"
    static let kCAFillRuleEvenOdd = "even-odd"
    static let kCACornerCurveCircular = "circular"
    static let kCACornerCurveContinuous = "continuous"
    static let kCAFillModeForwards = "forwards"
    static let kCAFillModeBackwards = "backwards"
    static let kCAFillModeBoth = "both"
    static let kCAFillModeRemoved = "removed"
    static let kCAMediaTimingFunctionLinear = "linear"
    static let kCAMediaTimingFunctionEaseIn = "easeIn"
    static let kCAMediaTimingFunctionEaseOut = "easeOut"
    static let kCAMediaTimingFunctionEaseInEaseOut = "easeInEaseOut"
    static let kCAMediaTimingFunctionDefault = "default"
    static let kCAFilterLinear = "linear"
    static let kCAFilterNearest = "nearest"
    static let kCAFilterTrilinear = "trilinear"
    static let kCAGradientLayerAxial = "axial"
    static let kCAGradientLayerRadial = "radial"
    static let kCAGradientLayerConic = "conic"
    static let kCAContentsFormatRGBA8Uint = "RGBA8"
    static let kCAContentsFormatRGBA16Float = "RGBAh"
    static let kCAContentsFormatGray8Uint = "Gray8"
    static let kCAEmitterLayerPoint = "point"
}

/// CATextLayer's alignment modes.
@ObjCConstants
enum TextAlignmentModes {
    static let kCAAlignmentNatural = "natural"
    static let kCAAlignmentLeft = "left"
    static let kCAAlignmentRight = "right"
    static let kCAAlignmentCenter = "center"
    static let kCAAlignmentJustified = "justified"
}
