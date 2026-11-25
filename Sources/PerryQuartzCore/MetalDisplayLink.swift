import CPerryGeometry
import PerryObjCInterop

// CAMetalDisplayLink: a display link that hands its delegate, once a
// frame, an update with its Metal layer's next drawable and when that
// frame is to be shown. It ticks as CADisplayLink does, on the run loop it
// is added to, through a display link of its own made while it is added;
// a frame whose drawable is not ready is skipped. The frame is due one
// display interval on, and shown the preferred latency's frames after.

@ObjCClass("CAMetalDisplayLinkUpdate")
open class CAMetalDisplayLinkUpdate: NSObject {
    var drawableObject: NSObject?
    var target = 0.0
    var presentation = 0.0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("drawable") func drawable() -> NSObject? { drawableObject }
    @ObjCMethod("targetTimestamp") func targetTimestamp() -> Double { target }
    @ObjCMethod("targetPresentationTimestamp") func targetPresentationTimestamp() -> Double { presentation }
}

@ObjCClass("CAMetalDisplayLink")
open class CAMetalDisplayLink: NSObject {
    var layer: CAMetalLayer?
    /// The delegate, not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var paused = false
    var frameLatency: Float = 2
    var frameRateRange = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
    /// The display link that ticks this one while it is added to a run loop.
    var link: CADisplayLink?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithMetalLayer:") public init(metalLayer: NSObject?) {
        layer = metalLayer?.as(CAMetalLayer.self)
        super.init()
    }

    @ObjCMethod("metalLayer") func metalLayer() -> CAMetalLayer? { layer }
    @ObjCMethod("delegate") func delegate() -> NSObject? { delegateObject.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { delegateObject = delegate?.objcObject }

    @ObjCMethod("isPaused") func isPaused() -> Bool { paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) {
        self.paused = paused
        link?.setPaused(paused)
    }

    @ObjCMethod("preferredFrameLatency") func preferredFrameLatency() -> Float { frameLatency }
    @ObjCMethod("setPreferredFrameLatency:") func setPreferredFrameLatency(_ latency: Float) { frameLatency = max(latency, 1) }

    @ObjCMethod("preferredFrameRateRange", types: "{CAFrameRateRange=fff}16@0:8")
    func preferredFrameRateRange() -> CAFrameRateRange { frameRateRange }

    @ObjCMethod("setPreferredFrameRateRange:", types: "v28@0:8{CAFrameRateRange=fff}16")
    func setPreferredFrameRateRange(_ range: CAFrameRateRange) {
        frameRateRange = range
        link?.setPreferredFrameRateRange(range)
    }

    /// Ticks on `runLoop` from now on; the run loop's link retains this one
    /// until it is invalidated.
    @ObjCMethod("addToRunLoop:forMode:")
    func add(to runLoop: NSObject?, forMode mode: NSObject?) {
        guard link == nil else { return }
        let link = CADisplayLink.make(CADisplayLink.objCClass, target: self, selector: ObjCSelector("_perryMetalTick:"))
        link.setPreferredFrameRateRange(frameRateRange)
        link.setPaused(paused)
        link.add(to: runLoop, forMode: mode)
        self.link = link
    }

    @ObjCMethod("removeFromRunLoop:forMode:")
    func remove(from runLoop: NSObject?, forMode mode: NSObject?) { invalidate() }

    @ObjCMethod("invalidate")
    func invalidate() {
        guard let link else { return }
        self.link = nil
        link.invalidate()
    }

    /// One frame: the layer's next drawable, in an update for the delegate.
    @ObjCMethod("_perryMetalTick:")
    func tick(_ sender: NSObject?) {
        guard !paused, let link, let delegateObject, let layer, let drawable = layer.nextDrawable() else { return }
        let update = CAMetalDisplayLinkUpdate()
        update.drawableObject = drawable
        update.target = link.targetTimestamp()
        update.presentation = update.target + Double(max(frameLatency - 1, 0)) * link.duration()
        NSObject(delegateObject).sendMetalDisplayLink(self, needsUpdate: update)
    }
}

extension NSObject {
    @ObjCMethod("metalDisplayLink:needsUpdate:") func sendMetalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLinkUpdate)
}
