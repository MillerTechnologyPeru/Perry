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
    private static var bindings: [pthread_t: Binding] {
        unsafeAddress { UnsafePointer(Storage.bindings) }
        unsafeMutableAddress { Storage.bindings }
    }
    /// Contexts their threads have let go of that EGL still has bound to
    /// them. Games that make their context current around every batch of
    /// drawing (a Mac's CGLSetCurrentContext is cheap) would otherwise
    /// have Mesa submit what they drew each time it's let go of, many
    /// hundreds of times a frame; making the same context current again
    /// takes it back as it was. Only a thread that has made the same
    /// context current again many times running keeps it so: one that
    /// does it a few times and then waits for another thread would keep
    /// the context from it. A thread lets go of it in EGL before it blocks
    /// (libSystem's and libdispatch's waits run BlockingRelease's hook),
    /// when another thread asks for it, at its next letting go, and when it
    /// ends; the main thread lets go at once.
    private static var parked: [pthread_t: Binding] {
        unsafeAddress { UnsafePointer(Storage.parked) }
        unsafeMutableAddress { Storage.parked }
    }
    private static var releaseRequested: Set<pthread_t> {
        unsafeAddress { UnsafePointer(Storage.releaseRequested) }
        unsafeMutableAddress { Storage.releaseRequested }
    }
    /// Each thread's context last made current, and how many times running
    /// it has been made current again after being let go of.
    private static var streaks: [pthread_t: (context: ObjectIdentifier, count: Int)] {
        unsafeAddress { UnsafePointer(Storage.streaks) }
        unsafeMutableAddress { Storage.streaks }
    }

    /// The variables above, kept behind pointers and guarded by
    /// bindingsLock: Swift checks each access to a static variable at run
    /// time (through a thread-local lookup), which for threads that make a
    /// context current thousands of times a frame costs more than the rest.
    private enum Storage {
        nonisolated(unsafe) static let bindings = make([pthread_t: Binding]())
        nonisolated(unsafe) static let parked = make([pthread_t: Binding]())
        nonisolated(unsafe) static let releaseRequested = make(Set<pthread_t>())
        nonisolated(unsafe) static let streaks = make([pthread_t: (context: ObjectIdentifier, count: Int)]())

        static func make<T>(_ value: T) -> UnsafeMutablePointer<T> {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return storage
        }
    }
    private static let parkingStreak = 64
    nonisolated(unsafe) private static let parkedKey: pthread_key_t = {
        var key = pthread_key_t()
        // The value is only a marker: the thread's own EGL binding is what
        // goes, at its end, so that no context stays bound to a thread
        // that's gone.
        pthread_key_create(&key) { _ in
            let thread = pthread_self()
            let wasParked = NSOpenGLContext.withBindings { _ in
                NSOpenGLContext.releaseRequested.remove(thread)
                NSOpenGLContext.streaks[thread] = nil
                return NSOpenGLContext.parked.removeValue(forKey: thread) != nil
            }
            if wasParked { _ = SDL.glMakeCurrent(nil, nil) }
        }
        return key
    }()
    nonisolated(unsafe) private static let bindingsLock: UnsafeMutablePointer<pthread_mutex_t> = {
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
        return withBindings {
            $0.contains { pthread_equal($0.key, thread) == 0 && $0.value.window == window }
                || parked.contains { pthread_equal($0.key, thread) == 0 && $0.value.window == window }
        }
    }

    /// Asks the threads that keep `context` (or `window`) bound after
    /// letting go of them to let go of them in EGL, at their next letting
    /// go: those threads.
    @discardableResult
    private static func requestRelease(of context: SDL.Pointer, _ window: SDL.Window?) -> [pthread_t] {
        let thread = pthread_self()
        return withBindings { _ in
            var threads: [pthread_t] = []
            for (other, binding) in parked where pthread_equal(other, thread) == 0
                && (binding.context.context == context || window != nil && binding.window == window) {
                releaseRequested.insert(other)
                threads.append(other)
            }
            return threads
        }
    }

    /// For the main thread, which doesn't wait for windows: a context
    /// another thread keeps is asked for, and waited for a little (that
    /// thread lets go of it within a batch of drawing).
    private static func reclaim(_ context: SDL.Pointer) {
        let threads = requestRelease(of: context, nil)
        guard !threads.isEmpty else { return }
        for _ in 0..<100 {
            if withBindings({ _ in !threads.contains { releaseRequested.contains($0) } }) { return }
            usleep(1000)
        }
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
        let thread = pthread_self()
        // The context this thread let go of last, still bound to the same
        // window: taken back as it is.
        let resumed = Self.withBindings {
            guard let binding = Self.parked.removeValue(forKey: thread) else { return false }
            guard binding.context === self, binding.window == window else { return false }
            $0[thread] = binding
            return true
        }
        if resumed { return }
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
        let identifier = ObjectIdentifier(self)
        Self.withBindings {
            $0[thread] = Binding(context: self, window: bound)
            if let streak = Self.streaks[thread], streak.context == identifier {
                Self.streaks[thread] = (identifier, streak.count + 1)
            } else {
                Self.streaks[thread] = (identifier, 0)
            }
        }
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
        if onMain { reclaim(context) }
        for attempt in 0..<2000 {
            if !(onMain && isBoundOnAnotherThread(window)), SDL.glMakeCurrent(window, context) { return .some(window) }
            if onMain { return SDL.glMakeCurrent(nil, context) ? .some(nil) : nil }
            if attempt == 0 {
                Trace.log("OpenGL: waiting for another thread to let go of window \(window)")
                requestRelease(of: context, window)
            }
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
        let thread = pthread_self()
        // The main thread's drawing is now and then, and a game's own
        // thread may be waiting for the window: it lets go at once.
        let onMain = Dispatch.isMainThread
        let release = withBindings { bindings -> Bool? in
            guard let binding = bindings.removeValue(forKey: thread) else { return nil }
            if releaseRequested.remove(thread) != nil {
                streaks[thread] = nil
                return true
            }
            if onMain || BlockingRelease.arm == nil || (streaks[thread]?.count ?? 0) < parkingStreak { return true }
            parked[thread] = binding
            return false
        }
        switch release {
        case true?: _ = SDL.glMakeCurrent(nil, nil)
        case false?:
            if pthread_getspecific(parkedKey) == nil { pthread_setspecific(parkedKey, UnsafeRawPointer(bitPattern: 1)) }
            BlockingRelease.arm?(1)
        case nil: break
        }
    }

    /// Lets go in EGL of the context this thread keeps bound, for libSystem
    /// and libdispatch's waits to run before the thread blocks.
    static func releaseParked() {
        let thread = pthread_self()
        let wasParked = withBindings { _ in
            releaseRequested.remove(thread)
            return parked.removeValue(forKey: thread) != nil
        }
        if wasParked { _ = SDL.glMakeCurrent(nil, nil) }
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

/// libSystem's hook for what a thread lets go of before it blocks, which
/// lets AppKit keep a context bound to a thread that has let go of it: a
/// thread that stops drawing and waits lets go of it in EGL then, so that
/// the thread it hands the drawing to can have it. Without the hook,
/// contexts aren't kept.
enum BlockingRelease {
    typealias Set = @convention(c) ((@convention(c) () -> Void)?) -> Void
    typealias Arm = @convention(c) (Int32) -> Void
    nonisolated(unsafe) static var arm: Arm?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        guard let set = lookup("perry_set_release_before_blocking"), let arm = lookup("perry_arm_release_before_blocking") else {
            return
        }
        unsafeBitCast(set, to: Set.self)({ NSOpenGLContext.releaseParked() })
        self.arm = unsafeBitCast(arm, to: Arm.self)
    }
}
