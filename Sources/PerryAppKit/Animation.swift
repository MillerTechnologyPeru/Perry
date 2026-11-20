import CPerryGeometry
import PerryObjCInterop

// NSAnimation and NSViewAnimation: timed changes, which Interface Builder
// subclasses. An animation runs to its end when started: its progress
// becomes 1 and its delegate hears it end, and a view animation's views
// take their end frames (or are hidden or shown), as they would at the end.

@ObjCClass("NSAnimation")
open class NSAnimation: NSObject {
    var duration: Double = 0
    /// NSAnimationCurve: ease in-out 0, ease in 1, ease out 2, linear 3.
    var curve: UInt = 0
    /// NSAnimationBlockingMode: blocking 0, nonblocking 1, nonblocking threaded 2.
    var blockingMode: UInt = 0
    var frameRate: Float = 0
    var progress: Float = 0
    var animating = false
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var progressMarks: [Float] = []

    public required override init() { super.init() }

    @ObjCMethod("initWithDuration:animationCurve:")
    public required init(duration: Double, animationCurve curve: UInt) {
        super.init()
        self.duration = duration
        self.curve = curve
    }

    @ObjCMethod("duration") func animationDuration() -> Double { duration }
    @ObjCMethod("setDuration:") func setDuration(_ value: Double) { duration = value }
    @ObjCMethod("animationCurve") func animationCurve() -> UInt { curve }
    @ObjCMethod("setAnimationCurve:") func setAnimationCurve(_ value: UInt) { curve = value }
    @ObjCMethod("animationBlockingMode") func animationBlockingMode() -> UInt { blockingMode }
    @ObjCMethod("setAnimationBlockingMode:") func setAnimationBlockingMode(_ value: UInt) { blockingMode = value }
    @ObjCMethod("frameRate") func animationFrameRate() -> Float { frameRate }
    @ObjCMethod("setFrameRate:") func setFrameRate(_ value: Float) { frameRate = value }
    @ObjCMethod("delegate") func animationDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("isAnimating") func isAnimating() -> Bool { animating }
    @ObjCMethod("currentProgress") func currentProgress() -> Float { progress }
    @ObjCMethod("setCurrentProgress:") func setCurrentProgress(_ value: Float) { progress = min(max(value, 0), 1) }
    @ObjCMethod("currentValue") func currentValue() -> Float { progress }
    @ObjCMethod("progressMarks") func animationProgressMarks() -> NSObject { NSMutableArray.of(progressMarks.map { NSNumber.make(double: Double($0)) }) }
    @ObjCMethod("addProgressMark:") func addProgressMark(_ value: Float) { progressMarks.append(value) }
    @ObjCMethod("removeProgressMark:") func removeProgressMark(_ value: Float) { progressMarks.removeAll { $0 == value } }
    @ObjCMethod("runLoopModesForAnimating") func runLoopModesForAnimating() -> NSObject? { nil }

    /// Runs to the end at once, asking the delegate first and telling it after.
    @ObjCMethod("startAnimation")
    func startAnimation() {
        guard !animating else { return }
        if Send.responds(delegateObject, "animationShouldStart:"), !Send.bool(delegateObject, "animationShouldStart:", objcObject) { return }
        animating = true
        // Sent, so a subclass's -setCurrentProgress: sees the end.
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Float) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("setCurrentProgress:"), 1)
        animating = false
        if Send.responds(delegateObject, "animationDidEnd:") { Send.void(delegateObject, "animationDidEnd:", objcObject) }
    }

    @ObjCMethod("stopAnimation")
    func stopAnimation() {
        guard animating else { return }
        animating = false
        if Send.responds(delegateObject, "animationDidStop:") { Send.void(delegateObject, "animationDidStop:", objcObject) }
    }

    @ObjCMethod("startWhenAnimation:reachesProgress:") func start(when animation: NSObject?, reachesProgress progress: Float) {}
    @ObjCMethod("stopWhenAnimation:reachesProgress:") func stop(when animation: NSObject?, reachesProgress progress: Float) {}
    @ObjCMethod("clearStartAnimation") func clearStartAnimation() {}
    @ObjCMethod("clearStopAnimation") func clearStopAnimation() {}
}

@ObjCClass("NSViewAnimation")
open class NSViewAnimation: NSAnimation {
    var viewAnimations: NSObject?

    public required init() { super.init() }
    public required init(duration: Double, animationCurve curve: UInt) { super.init(duration: duration, animationCurve: curve) }

    @ObjCMethod("initWithViewAnimations:")
    public required init(viewAnimations: NSObject?) {
        super.init(duration: 0.5, animationCurve: 0)
        self.viewAnimations = viewAnimations
    }

    @ObjCMethod("viewAnimations") func animationViewAnimations() -> NSObject? { viewAnimations }
    @ObjCMethod("setViewAnimations:") func setViewAnimations(_ value: NSObject?) { viewAnimations = value }

    /// At the end, each view (or window) has its end frame, and is shown
    /// or hidden as its effect says.
    @ObjCMethod("setCurrentProgress:")
    override func setCurrentProgress(_ value: Float) {
        super.setCurrentProgress(value)
        guard progress >= 1 else { return }
        for animation in viewAnimations?.as(NSArray.self)?.elements ?? [] {
            guard let dictionary = animation.as(NSDictionary.self), let target = dictionary.object(forKey: "NSViewAnimationTargetKey") else { continue }
            if let end = dictionary.object(forKey: "NSViewAnimationEndFrameKey") {
                Send.void(target.objcObject, "setFrame:", rect: Send.rect(end.objcObject, "rectValue"))
            }
            if let effect = dictionary.object(forKey: "NSViewAnimationEffectKey")?.stringValue {
                let hide = effect == "NSViewAnimationFadeOutEffect"
                if target.as(NSWindow.self) != nil {
                    Send.void(target.objcObject, hide ? "orderOut:" : "orderFront:", nil)
                } else {
                    Send.void(target.objcObject, "setHidden:", bool: hide)
                }
            }
        }
    }
}
