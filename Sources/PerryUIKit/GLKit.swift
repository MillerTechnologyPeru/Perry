import CPerryGeometry
import Glibc
import PerryObjCInterop

// GLKit's views: GLKView draws with OpenGL ES into a framebuffer of its
// own, the size of its bounds in pixels, through its delegate's
// -glkView:drawInRect: (or a subclass's -drawRect:), and shows the result
// in its layer; GLKViewController redraws it at its frame rate, as does a
// CADisplayLink for its target. Frames are timed on the main queue, with
// or without a display.

/// Callbacks at a frame rate, while there are any.
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
        schedule()
    }

    static func remove(_ owner: AnyObject) { subscribers[ObjectIdentifier(owner)] = nil }

    private static func schedule() {
        guard let after = Display.dispatchAfter, let time = Display.dispatchTime else { return }
        after(time(0, 1_000_000_000 / 120), Updates.mainQueue, nil) { _ in Frames.step() }
    }

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
        schedule()
    }
}

// MARK: - GLKView

final class GLKViewState: ObjectState {
    var context: EAGLContext?
    var delegate: UnsafeMutableRawPointer?
    var colorFormat = 0
    var depthFormat = 0
    var stencilFormat = 0
    var multisample = 0
    var enableSetNeedsDisplay = true
    /// The drawable: a framebuffer with color and depth or stencil
    /// renderbuffers, in the context, and its size in pixels.
    var framebuffer: UInt32 = 0
    var color: UInt32 = 0
    var depth: UInt32 = 0
    var size = (width: 0, height: 0)
}

@ObjCClass("GLKView")
open class GLKView: UIView {
    static let glkStates = StateTable<GLKViewState>()
    var glk: GLKViewState { GLKView.glkStates[objcObject] }

    @ObjCClassMethod("layerClass") static func eaglLayerClass() -> ObjCClass { CAEAGLLayer.objCClass }

    @ObjCMethod("initWithFrame:context:")
    func initialize(frame: CGRect, context: EAGLContext?) -> NSObject {
        let view = initializeView(frame: frame).unsafeCast(to: GLKView.self)
        view.glk.context = context
        return view
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        deleteDrawable()
        GLKView.glkStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("context") func context() -> EAGLContext? { glk.context }

    @ObjCMethod("setContext:")
    func setContext(_ context: EAGLContext?) {
        deleteDrawable()
        glk.context = context
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { glk.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { glk.delegate = delegate?.objcObject }
    @ObjCMethod("drawableColorFormat") func drawableColorFormat() -> Int { glk.colorFormat }
    @ObjCMethod("setDrawableColorFormat:") func setDrawableColorFormat(_ format: Int) { glk.colorFormat = format; deleteDrawable() }
    @ObjCMethod("drawableDepthFormat") func drawableDepthFormat() -> Int { glk.depthFormat }
    @ObjCMethod("setDrawableDepthFormat:") func setDrawableDepthFormat(_ format: Int) { glk.depthFormat = format; deleteDrawable() }
    @ObjCMethod("drawableStencilFormat") func drawableStencilFormat() -> Int { glk.stencilFormat }
    @ObjCMethod("setDrawableStencilFormat:") func setDrawableStencilFormat(_ format: Int) { glk.stencilFormat = format; deleteDrawable() }
    @ObjCMethod("drawableMultisample") func drawableMultisample() -> Int { glk.multisample }
    @ObjCMethod("setDrawableMultisample:") func setDrawableMultisample(_ multisample: Int) { glk.multisample = multisample }
    @ObjCMethod("enableSetNeedsDisplay") func enableSetNeedsDisplay() -> Bool { glk.enableSetNeedsDisplay }
    @ObjCMethod("setEnableSetNeedsDisplay:") func setEnableSetNeedsDisplay(_ enable: Bool) { glk.enableSetNeedsDisplay = enable }

    /// The drawable's size: the bounds in pixels.
    var pixelSize: (width: Int, height: Int) {
        let bounds = state.bounds, scale = state.geometry.contentsScale
        return (Int((bounds.width * scale).rounded()), Int((bounds.height * scale).rounded()))
    }

    @ObjCMethod("drawableWidth") func drawableWidth() -> Int { glk.framebuffer != 0 ? glk.size.width : pixelSize.width }
    @ObjCMethod("drawableHeight") func drawableHeight() -> Int { glk.framebuffer != 0 ? glk.size.height : pixelSize.height }

    /// Makes the drawable if it is missing or the wrong size, in the
    /// current context.
    private func ensureDrawable() {
        let size = pixelSize
        if glk.framebuffer != 0, glk.size == size { return }
        deleteDrawable()
        guard size.width > 0, size.height > 0 else { return }
        var framebuffer: UInt32 = 0, color: UInt32 = 0
        GLES.genFramebuffers(1, &framebuffer)
        GLES.bindFramebuffer(GLES.framebuffer, framebuffer)
        GLES.genRenderbuffers(1, &color)
        GLES.bindRenderbuffer(GLES.renderbuffer, color)
        let colorFormat = glk.colorFormat == 1 ? GLES.rgb565 : glk.colorFormat == 2 ? GLES.srgb8Alpha8 : GLES.rgba8
        GLES.renderbufferStorage(GLES.renderbuffer, colorFormat, Int32(size.width), Int32(size.height))
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, color)
        var depth: UInt32 = 0
        if glk.depthFormat != 0 || glk.stencilFormat != 0 {
            GLES.genRenderbuffers(1, &depth)
            GLES.bindRenderbuffer(GLES.renderbuffer, depth)
            let both = glk.stencilFormat != 0
            let format = both ? GLES.depth24Stencil8 : glk.depthFormat == 1 ? GLES.depth16 : GLES.depth24
            GLES.renderbufferStorage(GLES.renderbuffer, format, Int32(size.width), Int32(size.height))
            if glk.depthFormat != 0 || both {
                GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.depthAttachment, GLES.renderbuffer, depth)
            }
            if both { GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.stencilAttachment, GLES.renderbuffer, depth) }
        }
        (glk.framebuffer, glk.color, glk.depth, glk.size) = (framebuffer, color, depth, size)
    }

    /// Binds the drawable's framebuffer and sets the viewport to it.
    @ObjCMethod("bindDrawable")
    func bindDrawable() {
        guard glk.context != nil else { return }
        ensureDrawable()
        GLES.bindFramebuffer(GLES.framebuffer, glk.framebuffer)
        GLES.viewport(0, 0, Int32(glk.size.width), Int32(glk.size.height))
    }

    @ObjCMethod("deleteDrawable")
    func deleteDrawable() {
        guard glk.framebuffer != 0 else { return }
        if let context = glk.context {
            let previous = EAGLContexts.current?.object
            _ = EAGLContexts.setCurrent(context)
            var names = [glk.color, glk.depth].filter { $0 != 0 }
            GLES.deleteRenderbuffers(Int32(names.count), &names)
            GLES.deleteFramebuffers(1, &glk.framebuffer)
            _ = EAGLContexts.setCurrent(previous)
        }
        (glk.framebuffer, glk.color, glk.depth, glk.size) = (0, 0, 0, (0, 0))
    }

    /// Draws now: the context current and the drawable bound, through the
    /// delegate or -drawRect:; then shows the drawing in the layer.
    @ObjCMethod("display")
    func display() {
        guard draw() else { return }
        if let image = Renderbuffers.image(glk.color, opaque: state.geometry.isOpaque) {
            state.geometry.contents = NSObject(image.object)
            state.geometry.contentsScale = state.geometry.contentsScale
            Display.markDirty()
        }
    }

    private func draw() -> Bool {
        guard let context = glk.context, EAGLContexts.setCurrent(context) else { return false }
        bindDrawable()
        let bounds = state.bounds
        if let delegate = delegate(), delegate.responds(to: "glkView:drawInRect:") {
            delegate.sendGLKView(self, drawIn: bounds)
        } else {
            sendDraw(bounds)
        }
        return true
    }

    /// Draws and returns the drawing as an image at the view's scale.
    @ObjCMethod("snapshot")
    func snapshot() -> UIImage? {
        guard draw(), let image = Renderbuffers.image(glk.color, opaque: state.geometry.isOpaque) else { return nil }
        return UIImage.make(cgImage: image.object, scale: state.geometry.contentsScale)
    }

    /// The layer's display: drawing again.
    @ObjCMethod("displayLayer:")
    func displayLayer(_ layer: CALayer) { display() }

    @ObjCMethod("setNeedsDisplay")
    override func setNeedsDisplay() {
        guard glk.enableSetNeedsDisplay else { return }
        state.geometry.needsDisplay = true
        Updates.schedule()
    }
}

extension NSObject {
    @ObjCMethod("glkView:drawInRect:") func sendGLKView(_ view: GLKView, drawIn rect: CGRect)
    @ObjCMethod("update") func sendUpdate()
    @ObjCMethod("glkViewControllerUpdate:") func sendGLKViewControllerUpdate(_ controller: GLKViewController)
    @ObjCMethod("glkViewController:willPause:") func sendGLKViewController(_ controller: GLKViewController, willPause pause: Bool)
}

// MARK: - GLKViewController

final class GLKViewControllerState: ObjectState {
    var preferredFramesPerSecond = 30
    var paused = true
    var delegate: UnsafeMutableRawPointer?
    var pauseOnWillResignActive = true
    var resumeOnDidBecomeActive = true
    var framesDisplayed = 0
    var firstResume = 0.0
    var lastResume = 0.0
    var lastUpdate = 0.0
    var lastDraw = 0.0
    var sinceLastUpdate = 0.0
}

@ObjCClass("GLKViewController")
open class GLKViewController: UIViewController {
    static let glkStates = StateTable<GLKViewControllerState>()
    var glk: GLKViewControllerState { GLKViewController.glkStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        Frames.remove(GLKViewController.glkStates[objcObject])
        GLKViewController.glkStates.remove(objcObject)
        super.dealloc()
    }

    /// A GLKView the size of the screen, which the controller draws.
    @ObjCMethod("loadView")
    override func loadView() {
        let view = GLKView.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: GLKView.self)
        view.setDelegate(self)
        setView(view)
    }

    @ObjCMethod("preferredFramesPerSecond") func preferredFramesPerSecond() -> Int { glk.preferredFramesPerSecond }
    @ObjCMethod("setPreferredFramesPerSecond:") func setPreferredFramesPerSecond(_ rate: Int) {
        glk.preferredFramesPerSecond = rate
        if !glk.paused { start() }
    }

    /// The rate frames come at: the preferred rate, at most 60.
    @ObjCMethod("framesPerSecond") func framesPerSecond() -> Int { min(max(glk.preferredFramesPerSecond, 1), 60) }
    @ObjCMethod("isPaused") func isPaused() -> Bool { glk.paused }

    @ObjCMethod("setPaused:")
    func setPaused(_ paused: Bool) {
        guard paused != glk.paused else { return }
        if let delegate = delegate(), delegate.responds(to: "glkViewController:willPause:") {
            delegate.sendGLKViewController(self, willPause: paused)
        }
        glk.paused = paused
        if paused { Frames.remove(glk) } else { start() }
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { glk.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { glk.delegate = delegate?.objcObject }
    @ObjCMethod("pauseOnWillResignActive") func pauseOnWillResignActive() -> Bool { glk.pauseOnWillResignActive }
    @ObjCMethod("setPauseOnWillResignActive:") func setPauseOnWillResignActive(_ pause: Bool) { glk.pauseOnWillResignActive = pause }
    @ObjCMethod("resumeOnDidBecomeActive") func resumeOnDidBecomeActive() -> Bool { glk.resumeOnDidBecomeActive }
    @ObjCMethod("setResumeOnDidBecomeActive:") func setResumeOnDidBecomeActive(_ resume: Bool) { glk.resumeOnDidBecomeActive = resume }
    @ObjCMethod("framesDisplayed") func framesDisplayed() -> Int { glk.framesDisplayed }
    @ObjCMethod("timeSinceFirstResume") func timeSinceFirstResume() -> Double { glk.firstResume == 0 ? 0 : Clock.now - glk.firstResume }
    @ObjCMethod("timeSinceLastResume") func timeSinceLastResume() -> Double { glk.lastResume == 0 ? 0 : Clock.now - glk.lastResume }
    @ObjCMethod("timeSinceLastUpdate") func timeSinceLastUpdate() -> Double { glk.sinceLastUpdate }
    @ObjCMethod("timeSinceLastDraw") func timeSinceLastDraw() -> Double { glk.lastDraw == 0 ? 0 : Clock.now - glk.lastDraw }

    /// Frames start as the view appears and stop as it goes.
    @ObjCMethod("viewDidAppear:")
    override func viewDidAppear(_ animated: Bool) { setPaused(false) }

    @ObjCMethod("viewWillDisappear:")
    override func viewWillDisappear(_ animated: Bool) { setPaused(true) }

    private func start() {
        let now = Clock.now
        if glk.firstResume == 0 { glk.firstResume = now }
        glk.lastResume = now
        glk.lastUpdate = now
        let object = objcObject
        Frames.add(glk, framesPerSecond: framesPerSecond()) { time in
            UIViewController.wrap(object).unsafeCast(to: GLKViewController.self).frame(at: time)
        }
    }

    /// One frame: the update, through the delegate or -update, then the
    /// view drawn.
    private func frame(at time: Double) {
        glk.sinceLastUpdate = time - glk.lastUpdate
        glk.lastUpdate = time
        if let delegate = delegate(), delegate.responds(to: "glkViewControllerUpdate:") {
            delegate.sendGLKViewControllerUpdate(self)
        } else if responds(to: "update") {
            sendUpdate()
        }
        guard let view = state.view?.as(GLKView.self) else { return }
        view.display()
        glk.framesDisplayed += 1
        glk.lastDraw = time
    }
}

// MARK: - CADisplayLink

final class DisplayLinkState: ObjectState {
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
    static let states = StateTable<DisplayLinkState>()
    var state: DisplayLinkState { CADisplayLink.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        Frames.remove(CADisplayLink.states[objcObject])
        CADisplayLink.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CADisplayLink.objCClass.pointer)
    }

    @ObjCClassMethod("displayLinkWithTarget:selector:")
    static func make(_ cls: ObjCClass, target: NSObject, selector: ObjCSelector) -> CADisplayLink {
        let link = cls.object.allocated().unsafeCast(to: CADisplayLink.self)
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
            let link = CADisplayLink(objcObject: object, ownership: .retain)
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
