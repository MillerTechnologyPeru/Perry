import CPerryGeometry
import Glibc
import PerryObjCInterop
import SDL3Swift

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
        try? SDL.glSetAttribute(.doubleBuffer, double)
        try? SDL.glSetAttribute(.depthSize, value(12) ?? 16)
        try? SDL.glSetAttribute(.stencilSize, value(13) ?? 0)
        try? SDL.glSetAttribute(.alphaSize, value(11) ?? 0)
        try? SDL.glSetAttribute(.multisampleBuffers, value(55) ?? 0)
        try? SDL.glSetAttribute(.multisampleSamples, value(56) ?? 0)
        // Whatever the format asks of the version, these programs draw with
        // the fixed-function pipeline.
        try? SDL.glSetAttribute(.contextMajorVersion, 2)
        try? SDL.glSetAttribute(.contextMinorVersion, 1)
        try? SDL.glSetAttribute(.contextProfileMask, GLAttribute.Profile.compatibility.rawValue)
    }
}

@ObjCClass("NSOpenGLContext")
open class NSOpenGLContext: NSObject {
    nonisolated(unsafe) static var current: NSOpenGLContext?
    /// For contexts made current before their view has a window.
    nonisolated(unsafe) private static var holdingWindow: SDLWindow?

    var format: NSOpenGLPixelFormat?
    var shared: NSOpenGLContext?
    /// Not retained.
    var viewObject: UnsafeMutableRawPointer?
    var context: SDLGLContext?
    var swapInterval: Int32 = 0

    public required override init() { super.init() }

    @ObjCMethod("initWithFormat:shareContext:")
    public required init(format: NSObject?, shareContext: NSObject?) {
        super.init()
        self.format = format?.as(NSOpenGLPixelFormat.self)
        shared = shareContext?.as(NSOpenGLContext.self)
    }

    /// The SDL window this context draws to: its view's window's, or one
    /// kept hidden until the view has a window.
    private func drawable() -> SDLWindow? {
        guard SDLSession.start() else { return nil }
        if let viewObject, let window = NSView.wrap(viewObject).window {
            window.prepareForOpenGL(format)
            if let sdlWindow = window.sdlWindow { return sdlWindow }
        }
        if let window = Self.holdingWindow { return window }
        format?.applyToSDL()
        do {
            let window = try SDLWindow(title: "", width: 16, height: 16, options: [.opengl, .hidden])
            Self.holdingWindow = window
            return window
        } catch {
            appKitWarning("SDL could not make a window for OpenGL: \(error)")
            return nil
        }
    }

    @ObjCMethod("makeCurrentContext")
    func makeCurrentContext() {
        guard let window = drawable() else { return }
        if context == nil {
            format?.applyToSDL()
            let sharing = shared?.context != nil
            if sharing, let other = shared?.context { try? other.makeCurrent(in: window) }
            try? SDL.glSetAttribute(.shareWithCurrentContext, sharing ? 1 : 0)
            do {
                context = try SDLGLContext(window: window)
            } catch {
                appKitWarning("SDL could not make an OpenGL context: \(error)")
            }
            try? SDL.glSetSwapInterval(swapInterval)
        }
        guard let context else { return }
        do { try context.makeCurrent(in: window) } catch { appKitWarning("SDL could not make the OpenGL context current: \(error)") }
        Self.current = self
    }

    @ObjCMethod("flushBuffer")
    func flushBuffer() {
        guard let window = drawable() else { return }
        try? window.glSwap()
    }

    @ObjCClassMethod("currentContext") static func currentContext() -> NSOpenGLContext? { current }

    @ObjCClassMethod("clearCurrentContext")
    static func clearCurrentContext() {
        if current != nil { try? SDLGLContext.clearCurrent() }
        current = nil
    }

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
        if context != nil { try? SDL.glSetSwapInterval(swapInterval) }
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
