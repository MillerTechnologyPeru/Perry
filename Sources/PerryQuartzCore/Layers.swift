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
    /// The run loop and mode it was added to, when not the main run loop's:
    /// a timer there ticks it, on that run loop's thread.
    var runLoop: UnsafeMutableRawPointer?
    var mode: UnsafeMutableRawPointer?
    var timer: UnsafeMutableRawPointer?
}

/// Calls its target once a frame, at the display's 60 a second or the
/// preferred rate, while added to a run loop and not paused.
@ObjCClass("CADisplayLink")
open class CADisplayLink: NSObject {
    var state = DisplayLinkState()

    @ObjCMethod("init") public required override init() { super.init() }

    deinit {
        CADisplayLink.trace("deinit \(ObjectIdentifier(state)) added \(state.added)")
        Frames.remove(state)
    }

    /// Core Animation's private form, for a display: there is one display,
    /// so it is as displayLinkWithTarget:selector:.
    @ObjCClassMethod("displayLinkWithDisplay:target:selector:")
    static func make(_ cls: ObjCClass, display: NSObject?, target: NSObject, selector: ObjCSelector) -> CADisplayLink {
        make(cls, target: target, selector: selector)
    }

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
        typealias Get = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
        let main = unsafeBitCast(ObjCRuntime.msgSend, to: Get.self)(ObjCRuntime.classObject("NSRunLoop"), ObjCRuntime.selector("mainRunLoop"))
        if let runLoop, runLoop.objcObject != main {
            state.runLoop = ObjCRuntime.retain(runLoop.objcObject)
            state.mode = mode.flatMap { ObjCRuntime.retain($0.objcObject) }
        }
        schedule()
    }

    @ObjCMethod("removeFromRunLoop:forMode:")
    func remove(from runLoop: NSObject?, forMode mode: NSObject?) { invalidate() }

    @ObjCMethod("invalidate")
    func invalidate() {
        guard state.added else { return }
        state.added = false
        Frames.remove(state)
        stopTimer()
        state.target = nil
        ObjCRuntime.release(state.runLoop)
        ObjCRuntime.release(state.mode)
        (state.runLoop, state.mode) = (nil, nil)
        ObjCRuntime.release(objcObject)
    }

    private func stopTimer() {
        guard let timer = state.timer else { return }
        typealias Invalidate = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Invalidate.self)(timer, ObjCRuntime.selector("invalidate"))
        ObjCRuntime.release(timer)
        state.timer = nil
    }

    private func schedule() {
        Frames.remove(state)
        // On another run loop, the link's timer stays while it is added, as
        // the link is that run loop's source, paused or not: the timer skips
        // ticks while paused.
        if state.runLoop != nil, state.timer != nil, state.added { return }
        stopTimer()
        CADisplayLink.trace("\(objcObject) thread \(pthread_self()) schedule added \(state.added) paused \(state.paused) run loop \(String(describing: state.runLoop))")
        guard state.added, !state.paused || state.runLoop != nil else { return }
        let rate = state.preferredFramesPerSecond > 0 ? min(state.preferredFramesPerSecond, 60) : 60
        state.duration = 1 / 60
        if let runLoop = state.runLoop {
            // A repeating timer on the link's run loop, which calls -_perryTick:.
            typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Double, UnsafeMutableRawPointer?,
                                             UnsafeRawPointer?, UnsafeMutableRawPointer?, Bool) -> UnsafeMutableRawPointer?
            typealias Add = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            let timer = unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(
                ObjCRuntime.classObject("NSTimer"), ObjCRuntime.selector("timerWithTimeInterval:target:selector:userInfo:repeats:"),
                1 / Double(rate), objcObject, ObjCRuntime.selector("_perryTick:"), nil, true)
            state.timer = ObjCRuntime.retain(timer)
            let mode = state.mode ?? "kCFRunLoopDefaultMode".objCArgument()
            unsafeBitCast(ObjCRuntime.msgSend, to: Add.self)(runLoop, ObjCRuntime.selector("addTimer:forMode:"), timer, mode)
            return
        }
        let object = objcObject
        Frames.add(state, framesPerSecond: rate) { time in
            CADisplayLink.objCInstance(object, ownership: .retain).tick(at: time)
        }
    }

    /// With PERRY_UIKIT_TOUCH_TRACE set, display links' scheduling and
    /// ticks are written to standard error.
    nonisolated(unsafe) static let tracing = getenv("PERRY_UIKIT_TOUCH_TRACE") != nil

    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let line = "perry: QuartzCore: display link: \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }

    /// One frame: the time, then the target's message.
    func tick(at time: Double) {
        CADisplayLink.trace("\(objcObject) tick, thread \(pthread_self())")
        state.timestamp = time
        guard let target = state.target, let selector = state.selector else { return }
        typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(target.objcObject, selector, objcObject)
        CADisplayLink.trace("\(objcObject) tick done, paused \(state.paused)")
    }

    /// The run loop timer's action, on the link's run loop.
    @ObjCMethod("_perryTick:")
    func runLoopTick(_ timer: NSObject?) {
        CADisplayLink.trace("\(objcObject) timer fired, paused \(state.paused), thread \(pthread_self())")
        guard !state.paused else { return }
        tick(at: Clock.now)
    }

    @ObjCMethod("isPaused") func isPaused() -> Bool { state.paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) {
        CADisplayLink.trace("\(objcObject) setPaused \(paused)")
        guard paused != state.paused else { return }
        state.paused = paused
        schedule()
    }

    @ObjCMethod("preferredFramesPerSecond") func preferredFramesPerSecond() -> Int { state.preferredFramesPerSecond }
    @ObjCMethod("setPreferredFramesPerSecond:") func setPreferredFramesPerSecond(_ rate: Int) {
        guard rate != state.preferredFramesPerSecond else { return }
        state.preferredFramesPerSecond = rate
        schedule()
    }

    /// The display the link follows: there is no display object here.
    @ObjCMethod("display") func display() -> NSObject? { nil }

    /// Why a high rate is wanted, which only tunes Darwin's power use.
    @ObjCMethod("setHighFrameRateReasons:count:")
    func setHighFrameRateReasons(_ reasons: UnsafeRawPointer?, count: Int) {}

    /// CAFrameRateRange (minimum, maximum, preferred): the preferred rate,
    /// else the maximum, sets the frames per second.
    @ObjCMethod("preferredFrameRateRange", types: "{CAFrameRateRange=fff}16@0:8")
    func preferredFrameRateRange() -> CAFrameRateRange {
        let rate = Float(state.preferredFramesPerSecond)
        return CAFrameRateRange(minimum: 0, maximum: rate, preferred: rate)
    }

    @ObjCMethod("setPreferredFrameRateRange:", types: "v28@0:8{CAFrameRateRange=fff}16")
    func setPreferredFrameRateRange(_ range: CAFrameRateRange) {
        let rate = range.preferred > 0 ? range.preferred : range.maximum
        setPreferredFramesPerSecond(Int(rate.rounded()))
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

/// Core Animation's filter names and input keys (its private filters'
/// among them), and contents formats and scaling, with Darwin's values.
@ObjCConstants
enum FilterNames {
    static let kCAFilterAlphaThreshold = "alphaThreshold"
    static let kCAFilterAverageColor = "averageColor"
    static let kCAFilterBox = "box"
    static let kCAFilterClear = "clear"
    static let kCAFilterColorBlendMode = "colorBlendMode"
    static let kCAFilterColorBrightness = "colorBrightness"
    static let kCAFilterColorBurnBlendMode = "colorBurnBlendMode"
    static let kCAFilterColorContrast = "colorContrast"
    static let kCAFilterColorDodgeBlendMode = "colorDodgeBlendMode"
    static let kCAFilterColorHueRotate = "colorHueRotate"
    static let kCAFilterColorInvert = "colorInvert"
    static let kCAFilterColorMatrix = "colorMatrix"
    static let kCAFilterColorMonochrome = "colorMonochrome"
    static let kCAFilterColorSaturate = "colorSaturate"
    static let kCAFilterCopy = "copy"
    static let kCAFilterCurves = "curves"
    static let kCAFilterDarkenBlendMode = "darkenBlendMode"
    static let kCAFilterDarkenSourceOver = "darkenSourceOver"
    static let kCAFilterDestAtop = "destAtop"
    static let kCAFilterDestIn = "destIn"
    static let kCAFilterDestOut = "destOut"
    static let kCAFilterDestOver = "destOver"
    static let kCAFilterDifferenceBlendMode = "differenceBlendMode"
    static let kCAFilterDivideBlendMode = "divideBlendMode"
    static let kCAFilterExclusionBlendMode = "exclusionBlendMode"
    static let kCAFilterGaussianBlur = "gaussianBlur"
    static let kCAFilterHardLightBlendMode = "hardLightBlendMode"
    static let kCAFilterHueBlendMode = "hueBlendMode"
    static let kCAFilterLightenBlendMode = "lightenBlendMode"
    static let kCAFilterLightenSourceOver = "lightenSourceOver"
    static let kCAFilterLinearBurnBlendMode = "linearBurnBlendMode"
    static let kCAFilterLinearDodgeBlendMode = "linearDodgeBlendMode"
    static let kCAFilterLinearLightBlendMode = "linearLightBlendMode"
    static let kCAFilterLuminanceCurveMap = "luminanceCurveMap"
    static let kCAFilterLuminanceToAlpha = "luminanceToAlpha"
    static let kCAFilterLuminosityBlendMode = "luminosityBlendMode"
    static let kCAFilterMaximum = "maximum"
    static let kCAFilterMultiplyBlendMode = "multiplyBlendMode"
    static let kCAFilterMultiplyColor = "multiplyColor"
    static let kCAFilterOverlayBlendMode = "overlayBlendMode"
    static let kCAFilterPinLightBlendMode = "pinLightBlendMode"
    static let kCAFilterPlusD = "plusD"
    static let kCAFilterPlusL = "plusL"
    static let kCAFilterSaturationBlendMode = "saturationBlendMode"
    static let kCAFilterScreenBlendMode = "screenBlendMode"
    static let kCAFilterSoftLightBlendMode = "softLightBlendMode"
    static let kCAFilterSourceAtop = "sourceAtop"
    static let kCAFilterSourceIn = "sourceIn"
    static let kCAFilterSourceOut = "sourceOut"
    static let kCAFilterSubtractBlendMode = "subtractBlendMode"
    static let kCAFilterVariableBlur = "variableBlur"
    static let kCAFilterVibrantColorMatrix = "vibrantColorMatrix"
    static let kCAFilterXor = "xor"
    static let kCAFilterInputAlphaValues = "inputAlphaValues"
    static let kCAFilterInputAmount = "inputAmount"
    static let kCAFilterInputAngle = "inputAngle"
    static let kCAFilterInputBias = "inputBias"
    static let kCAFilterInputBlueValues = "inputBlueValues"
    static let kCAFilterInputColor = "inputColor"
    static let kCAFilterInputColorMatrix = "inputColorMatrix"
    static let kCAFilterInputDither = "inputDither"
    static let kCAFilterInputGreenValues = "inputGreenValues"
    static let kCAFilterInputHardEdges = "inputHardEdges"
    static let kCAFilterInputNormalizeEdges = "inputNormalizeEdges"
    static let kCAFilterInputPremultipliedValues = "inputPremultipliedValues"
    static let kCAFilterInputRadius = "inputRadius"
    static let kCAFilterInputRedValues = "inputRedValues"
    static let kCAFilterInputValues = "inputValues"
    static let kCAContentsFormatA8 = "A8"
    static let kCAContentsFormatAutomatic = "automatic"
    static let kCAContentsScalingRepeat = "repeat"
    static let kCAContentsScalingStretch = "stretch"
    static let kCALayerContentsSwizzleRGBA = "RGBA"
    static let kCALayerContentsSwizzleAAAA = "AAAA"
}
