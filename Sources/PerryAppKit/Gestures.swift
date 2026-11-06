import CPerryGeometry
import PerryObjCInterop

// Gesture recognizers: kept with their target, action and settings, as
// nibs and apps attach them to views. A click recognizer fires its action
// on its view's clicks; the others (pans, magnification, rotation, presses)
// don't recognize anything, as the mouse's own events reach the views.

@ObjCClass("NSGestureRecognizer")
open class NSGestureRecognizer: NSObject {
    /// Not retained.
    var target: UnsafeMutableRawPointer?
    var action: ObjCSelector?
    /// Not retained.
    var delegate: UnsafeMutableRawPointer?
    /// Not retained.
    var viewObject: UnsafeMutableRawPointer?
    var enabled = true
    /// NSGestureRecognizerState: possible 0, began 1, changed 2, ended 3,
    /// cancelled 4, failed 5.
    var state = 0
    var allowedTouchTypes: UInt = 1
    var delaysPrimaryMouseButtonEvents = false
    var location = CGPoint.zero

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithTarget:action:")
    public required init(target: NSObject?, action: ObjCSelector?) {
        super.init()
        self.target = target?.objcObject
        self.action = action
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        target = decoded.object("NSGestureRecognizer.target")?.objcObject
        action = decoded.selector("NSGestureRecognizer.action")
        delegate = decoded.object("NSGestureRecognizer.delegate")?.objcObject
        if decoded.has("NSGestureRecognizer.enabled") { enabled = decoded.bool("NSGestureRecognizer.enabled") }
        if decoded.has("NSGestureRecognizer.allowedTouchTypes") { allowedTouchTypes = UInt(decoded.integer("NSGestureRecognizer.allowedTouchTypes")) }
    }

    @ObjCMethod("target") func recognizerTarget() -> NSObject? { target.map(NSObject.init) }
    @ObjCMethod("setTarget:") func setTarget(_ value: NSObject?) { target = value?.objcObject }
    @ObjCMethod("action") func recognizerAction() -> ObjCSelector? { action }
    @ObjCMethod("setAction:") func setAction(_ value: ObjCSelector?) { action = value }
    @ObjCMethod("delegate") func recognizerDelegate() -> NSObject? { delegate.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegate = value?.objcObject }
    @ObjCMethod("view") func view() -> NSObject? { viewObject.map(NSObject.init) }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ value: Bool) { enabled = value }
    @ObjCMethod("state") func recognizerState() -> Int { state }
    @ObjCMethod("setState:") func setState(_ value: Int) { state = value }
    @ObjCMethod("allowedTouchTypes") func recognizerAllowedTouchTypes() -> UInt { allowedTouchTypes }
    @ObjCMethod("setAllowedTouchTypes:") func setAllowedTouchTypes(_ value: UInt) { allowedTouchTypes = value }
    @ObjCMethod("delaysPrimaryMouseButtonEvents") func recognizerDelaysPrimaryMouseButtonEvents() -> Bool { delaysPrimaryMouseButtonEvents }
    @ObjCMethod("setDelaysPrimaryMouseButtonEvents:") func setDelaysPrimaryMouseButtonEvents(_ value: Bool) { delaysPrimaryMouseButtonEvents = value }
    @ObjCMethod("setDelaysSecondaryMouseButtonEvents:") func setDelaysSecondaryMouseButtonEvents(_ value: Bool) {}
    @ObjCMethod("setDelaysOtherMouseButtonEvents:") func setDelaysOtherMouseButtonEvents(_ value: Bool) {}
    @ObjCMethod("setDelaysKeyEvents:") func setDelaysKeyEvents(_ value: Bool) {}
    @ObjCMethod("setDelaysMagnificationEvents:") func setDelaysMagnificationEvents(_ value: Bool) {}
    @ObjCMethod("setDelaysRotationEvents:") func setDelaysRotationEvents(_ value: Bool) {}
    @ObjCMethod("locationInView:") func location(in view: NSView?) -> CGPoint { location }
    @ObjCMethod("requireGestureRecognizerToFail:") func requireToFail(_ other: NSObject?) {}
    @ObjCMethod("reset") func reset() { state = 0 }

    func fire() {
        guard enabled, let target, let action else { return }
        Send.void(target, action.name, objcObject)
    }
}

@ObjCClass("NSClickGestureRecognizer")
open class NSClickGestureRecognizer: NSGestureRecognizer {
    var buttonMask: UInt = 1
    var numberOfClicksRequired = 1
    var numberOfTouchesRequired = 1

    @ObjCMethod("buttonMask") func recognizerButtonMask() -> UInt { buttonMask }
    @ObjCMethod("setButtonMask:") func setButtonMask(_ value: UInt) { buttonMask = value }
    @ObjCMethod("numberOfClicksRequired") func recognizerNumberOfClicksRequired() -> Int { numberOfClicksRequired }
    @ObjCMethod("setNumberOfClicksRequired:") func setNumberOfClicksRequired(_ value: Int) { numberOfClicksRequired = value }
    @ObjCMethod("numberOfTouchesRequired") func recognizerNumberOfTouchesRequired() -> Int { numberOfTouchesRequired }
    @ObjCMethod("setNumberOfTouchesRequired:") func setNumberOfTouchesRequired(_ value: Int) { numberOfTouchesRequired = value }
}

@ObjCClass("NSPanGestureRecognizer")
open class NSPanGestureRecognizer: NSGestureRecognizer {
    var buttonMask: UInt = 1

    @ObjCMethod("buttonMask") func recognizerButtonMask() -> UInt { buttonMask }
    @ObjCMethod("setButtonMask:") func setButtonMask(_ value: UInt) { buttonMask = value }
    @ObjCMethod("translationInView:") func translation(in view: NSView?) -> CGPoint { .zero }
    @ObjCMethod("setTranslation:inView:") func setTranslation(_ translation: CGPoint, in view: NSView?) {}
    @ObjCMethod("velocityInView:") func velocity(in view: NSView?) -> CGPoint { .zero }
    @ObjCMethod("setNumberOfTouchesRequired:") func setNumberOfTouchesRequired(_ value: Int) {}
}

@ObjCClass("NSPressGestureRecognizer")
open class NSPressGestureRecognizer: NSGestureRecognizer {
    var minimumPressDuration: Double = 0.5
    @ObjCMethod("minimumPressDuration") func recognizerMinimumPressDuration() -> Double { minimumPressDuration }
    @ObjCMethod("setMinimumPressDuration:") func setMinimumPressDuration(_ value: Double) { minimumPressDuration = value }
    @ObjCMethod("setAllowableMovement:") func setAllowableMovement(_ value: CGFloat) {}
    @ObjCMethod("setButtonMask:") func setButtonMask(_ value: UInt) {}
}

@ObjCClass("NSMagnificationGestureRecognizer")
open class NSMagnificationGestureRecognizer: NSGestureRecognizer {
    @ObjCMethod("magnification") func magnification() -> CGFloat { 0 }
    @ObjCMethod("setMagnification:") func setMagnification(_ value: CGFloat) {}
}

@ObjCClass("NSRotationGestureRecognizer")
open class NSRotationGestureRecognizer: NSGestureRecognizer {
    @ObjCMethod("rotation") func rotation() -> CGFloat { 0 }
    @ObjCMethod("setRotation:") func setRotation(_ value: CGFloat) {}
}
