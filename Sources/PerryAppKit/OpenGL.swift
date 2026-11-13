import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSOpenGLPixelFormat, NSOpenGLContext and NSOpenGLView, over SDL's OpenGL
// contexts. A window showing an NSOpenGLView has no SDL renderer: the
// program's OpenGL drawing is the window's picture, as a full-window view's
// is on a Mac. The context is OpenGL's compatibility profile, which has the
// fixed-function pipeline older Mac programs use.

/// NSOpenGLPixelFormatAttribute's values that are followed by a number.
private let attributesWithValues: Set<UInt32> = [7, 8, 11, 12, 13, 14, 55, 56, 70, 84, 96, 99, 128]

@ObjCClass("NSOpenGLPixelFormat")
open class NSOpenGLPixelFormat: NSObject {
    var attributes: [UInt32: UInt32] = [:]

    public required override init() { super.init() }

    @ObjCMethod("initWithAttributes:")
    public required init(attributes list: UnsafePointer<UInt32>?) {
        super.init()
        guard var next = list else { return }
        while next.pointee != 0 {
            let name = next.pointee
            next += 1
            if attributesWithValues.contains(name) {
                attributes[name] = next.pointee
                next += 1
            } else {
                attributes[name] = 1
            }
        }
    }

    func value(_ attribute: UInt32) -> Int32? { attributes[attribute].map { Int32(bitPattern: $0) } }

    @ObjCMethod("numberOfVirtualScreens") func numberOfVirtualScreens() -> Int { 1 }

    @ObjCMethod("getValues:forAttribute:forVirtualScreen:")
    func getValues(_ values: UnsafeMutablePointer<Int32>?, attribute: UInt32, screen: Int) {
        values?.pointee = value(attribute) ?? 0
    }

    /// SDL's attributes for the next context and window to have this format.
    func applyToSDL() {
        let double: Int32 = attributes[5] != nil ? 1 : 0
        _ = SDL.glSetAttribute(SDL.glDoubleBuffer, double)
        _ = SDL.glSetAttribute(SDL.glDepthSize, value(12) ?? 16)
        _ = SDL.glSetAttribute(SDL.glStencilSize, value(13) ?? 0)
        _ = SDL.glSetAttribute(SDL.glAlphaSize, value(11) ?? 0)
        _ = SDL.glSetAttribute(SDL.glMultisampleBuffers, value(55) ?? 0)
        _ = SDL.glSetAttribute(SDL.glMultisampleSamples, value(56) ?? 0)
        // Whatever the format asks of the version, these programs draw with
        // the fixed-function pipeline.
        _ = SDL.glSetAttribute(SDL.glContextMajorVersion, 2)
        _ = SDL.glSetAttribute(SDL.glContextMinorVersion, 1)
        _ = SDL.glSetAttribute(SDL.glContextProfileMask, SDL.glProfileCompatibility)
        // Letting go of a context doesn't submit what was drawn with it, as
        // a Mac's doesn't: games that make theirs current around every
        // batch of drawing would otherwise have each batch submitted alone.
        _ = SDL.glSetAttribute(SDL.glContextReleaseBehavior, SDL.glReleaseBehaviorNone)
    }
}

@ObjCClass("NSOpenGLContext")
open class NSOpenGLContext: NSObject {
    /// Each thread's current context and the SDL window it draws to: as
    /// with EGL's, a context and a window's surface are current on one
    /// thread at a time.
    private struct Binding {
        let context: NSOpenGLContext
        /// None when the context is current without a surface.
        let window: SDL.Window?
    }
    nonisolated(unsafe) private static var bindings: [pthread_t: Binding] = [:]
    nonisolated(unsafe) private static var bindingsLock: UnsafeMutablePointer<pthread_mutex_t> = {
        let lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(lock, nil)
        return lock
    }()

    private static func withBindings<T>(_ body: (inout [pthread_t: Binding]) -> T) -> T {
        pthread_mutex_lock(bindingsLock)
        defer { pthread_mutex_unlock(bindingsLock) }
        return body(&bindings)
    }

    /// This thread's current context.
    static var current: NSOpenGLContext? { withBindings { $0[pthread_self()]?.context } }

    /// Whether another thread draws to `window`, as games that render on
    /// their own threads do.
    static func isBoundOnAnotherThread(_ window: SDL.Window) -> Bool {
        let thread = pthread_self()
        return withBindings { $0.contains { pthread_equal($0.key, thread) == 0 && $0.value.window == window } }
    }
    /// For contexts made current before their view has a window.
    nonisolated(unsafe) private static var holdingWindow: SDL.Window?

    var format: NSOpenGLPixelFormat?
    var shared: NSOpenGLContext?
    /// Not retained.
    var viewObject: UnsafeMutableRawPointer?
    var context: SDL.Pointer?
    var swapInterval: Int32 = 0

    public required override init() { super.init() }

    @ObjCMethod("initWithFormat:shareContext:")
    public required init(format: NSObject?, shareContext: NSObject?) {
        super.init()
        self.format = format?.as(NSOpenGLPixelFormat.self)
        shared = shareContext?.as(NSOpenGLContext.self)
    }

    deinit {
        if let context { _ = SDL.glDestroyContext(context) }
    }

    /// The SDL window this context draws to: its view's window's, or one
    /// kept hidden until the view has a window.
    private func drawable() -> SDL.Window? {
        guard SDL.start() else { return nil }
        if let viewObject, let window = NSView.wrap(viewObject).window {
            window.prepareForOpenGL(format)
            if let sdlWindow = window.sdlWindow { return sdlWindow }
        }
        if let window = Self.holdingWindow { return window }
        format?.applyToSDL()
        let window = "".withCString { SDL.createWindow($0, 16, 16, SDL.windowOpenGL | SDL.windowHidden) }
        if window == nil { appKitWarning("SDL could not make a window for OpenGL: \(SDL.lastError)") }
        Self.holdingWindow = window
        return window
    }

    @ObjCMethod("makeCurrentContext")
    func makeCurrentContext() {
        guard let window = drawable() else { return }
        if context == nil {
            format?.applyToSDL()
            let sharing = shared?.context != nil
            if sharing, let other = shared?.context { _ = Self.bind(other, to: window) }
            _ = SDL.glSetAttribute(SDL.glShareWithCurrentContext, sharing ? 1 : 0)
            context = SDL.glCreateContext(window)
            if context == nil { appKitWarning("SDL could not make an OpenGL context: \(SDL.lastError)") }
            _ = SDL.glSetSwapInterval(swapInterval)
        }
        guard let context else { return }
        guard let bound = Self.bind(context, to: window) else {
            appKitWarning("SDL could not make the OpenGL context current: \(SDL.lastError)")
            return
        }
        Self.withBindings { $0[pthread_self()] = Binding(context: self, window: bound) }
    }

    /// Makes `context` current on this thread, drawing to `window`; the
    /// window it draws to, nil for none, or nil nil when it can't be made
    /// current.
    ///
    /// A Mac's contexts on several threads can draw to one view at once;
    /// EGL binds a window's surface on one thread at a time. A game
    /// drawing on its own thread keeps the window: the main thread's
    /// contexts are made current without a surface while it does, and
    /// another thread waits for the main thread's brief binding to end.
    private static func bind(_ context: SDL.Pointer, to window: SDL.Window) -> SDL.Window?? {
        let onMain = Dispatch.isMainThread
        for attempt in 0..<2000 {
            if !(onMain && isBoundOnAnotherThread(window)), SDL.glMakeCurrent(window, context) { return .some(window) }
            if onMain { return SDL.glMakeCurrent(nil, context) ? .some(nil) : nil }
            if attempt == 0 { Trace.log("OpenGL: waiting for the main thread to let go of window \(window)") }
            usleep(1000)
        }
        return nil
    }

    @ObjCMethod("flushBuffer")
    func flushBuffer() {
        guard let window = drawable() else { return }
        _ = SDL.glSwapWindow(window)
    }

    @ObjCClassMethod("currentContext") static func currentContext() -> NSOpenGLContext? { current }

    @ObjCClassMethod("clearCurrentContext")
    static func clearCurrentContext() {
        guard current != nil else { return }
        _ = SDL.glMakeCurrent(nil, nil)
        _ = withBindings { $0.removeValue(forKey: pthread_self()) }
    }

    /// The CGL context: this context itself, which OpenGL's provider's CGL
    /// functions send their messages to.
    @ObjCMethod("CGLContextObj") func cglContextObj() -> UnsafeMutableRawPointer? { objcObject }

    @ObjCMethod("view") func view() -> NSView? { viewObject.map(NSView.wrap) }
    @ObjCMethod("setView:") func setView(_ view: NSView?) { viewObject = view?.objcObject }
    @ObjCMethod("clearDrawable") func clearDrawable() { viewObject = nil }
    @ObjCMethod("update") func update() {}
    @ObjCMethod("pixelFormat") func pixelFormat() -> NSOpenGLPixelFormat? { format }

    /// NSOpenGLContextParameter's swap interval, 222; the others have no
    /// meaning here.
    @ObjCMethod("setValues:forParameter:")
    func setValues(_ values: UnsafePointer<Int32>?, parameter: Int) {
        guard parameter == 222, let values else { return }
        swapInterval = values.pointee
        if context != nil { _ = SDL.glSetSwapInterval(swapInterval) }
    }

    @ObjCMethod("getValues:forParameter:")
    func getValues(_ values: UnsafeMutablePointer<Int32>?, parameter: Int) {
        values?.pointee = parameter == 222 ? swapInterval : 0
    }
}

@ObjCClass("NSOpenGLView")
open class NSOpenGLView: NSView {
    var format: NSOpenGLPixelFormat?
    var glContext: NSOpenGLContext?
    private var prepared = false
    private var lastSize = CGSize.zero

    public required init() { super.init() }

    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) { super.init(coder: coder) }

    @ObjCMethod("initWithFrame:pixelFormat:")
    public required init(frame: CGRect, pixelFormat: NSObject?) {
        super.init(frame: frame)
        format = pixelFormat?.as(NSOpenGLPixelFormat.self)
    }

    @ObjCClassMethod("defaultPixelFormat")
    static func defaultPixelFormat() -> NSOpenGLPixelFormat? {
        var attributes: [UInt32] = [5, 12, 16, 0]
        return attributes.withUnsafeMutableBufferPointer { NSOpenGLPixelFormat(attributes: UnsafePointer($0.baseAddress)) }
    }

    @ObjCMethod("pixelFormat") func pixelFormat() -> NSOpenGLPixelFormat? { format }
    @ObjCMethod("setPixelFormat:") func setPixelFormat(_ format: NSOpenGLPixelFormat?) { self.format = format }

    @ObjCMethod("openGLContext")
    func openGLContext() -> NSOpenGLContext? {
        if let glContext { return glContext }
        let context = NSOpenGLContext(format: format, shareContext: nil)
        context.setView(self)
        glContext = context
        return context
    }

    @ObjCMethod("setOpenGLContext:")
    func setOpenGLContext(_ context: NSOpenGLContext?) {
        glContext = context
        context?.setView(self)
    }

    @ObjCMethod("clearGLContext") func clearGLContext() { glContext = nil }
    @ObjCMethod("prepareOpenGL") func prepareOpenGL() {}
    @ObjCMethod("reshape") func reshape() {}
    @ObjCMethod("update") func update() { glContext?.update() }
    @ObjCMethod("isOpaque") func isOpaqueView() -> Bool { true }

    /// What the window's drawing is for this view: -prepareOpenGL once,
    /// -reshape when the size changes, and -drawRect: when asked for.
    func displayOpenGL() {
        let size = bounds.size
        let current = Send.object(objcObject, "openGLContext").map(NSObject.init)?.as(NSOpenGLContext.self)
        guard let current else { return }
        // The app's own thread draws to the window: it leaves it be.
        if let sdlWindow = window?.sdlWindow, NSOpenGLContext.isBoundOnAnotherThread(sdlWindow) { return }
        // What this drawing makes current, it lets go of after, so that
        // the app's threads can draw to the window.
        let previous = NSOpenGLContext.current
        defer {
            if let previous { previous.makeCurrentContext() } else { NSOpenGLContext.clearCurrentContext() }
        }
        current.makeCurrentContext()
        var draw = needsDisplay
        if !prepared {
            prepared = true
            draw = true
            Send.void(objcObject, "prepareOpenGL")
        }
        if size != lastSize {
            lastSize = size
            draw = true
            Send.void(objcObject, "reshape")
        }
        guard draw else { return }
        needsDisplay = false
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(objcObject, ObjCRuntime.selector("drawRect:"), bounds)
    }
}
