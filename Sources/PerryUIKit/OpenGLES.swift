import CPerryGeometry
import Glibc
import PerryObjCInterop

// OpenGL ES: the host's own. An app's gl* imports bind to the host's
// libGLESv2 (or libGLESv1_CM), whose C API is the same; EAGLContext is an
// EGL context on Mesa's surfaceless platform, which needs no window and
// runs on the GPU when there is one and in software otherwise. A context
// for an API the host lacks is nil, as on a device without it. As on iOS
// there is no default framebuffer: apps draw into renderbuffers, which a
// QuartzCore's CAEAGLLayer gives storage and shows when presented.

enum GLES {
    typealias Pointer = UnsafeMutableRawPointer

    nonisolated(unsafe) private static var loaded = false
    nonisolated(unsafe) private static var libraries: [Pointer] = []
    nonisolated(unsafe) static var display: Pointer?

    nonisolated(unsafe) static var getProcAddress: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?
    nonisolated(unsafe) static var getPlatformDisplay: (@convention(c) (UInt32, Pointer?, UnsafePointer<Int>?) -> Pointer?)?
    nonisolated(unsafe) static var initialize: (@convention(c) (Pointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> UInt32)?
    nonisolated(unsafe) static var bindAPI: (@convention(c) (UInt32) -> UInt32)?
    nonisolated(unsafe) static var createContext: (@convention(c) (Pointer?, Pointer?, Pointer?, UnsafePointer<Int32>?) -> Pointer?)?
    nonisolated(unsafe) static var destroyContext: (@convention(c) (Pointer?, Pointer?) -> UInt32)?
    nonisolated(unsafe) static var makeCurrent: (@convention(c) (Pointer?, Pointer?, Pointer?, Pointer?) -> UInt32)?
    nonisolated(unsafe) static var getCurrentDisplay: (@convention(c) () -> Pointer?)?
    nonisolated(unsafe) static var getCurrentSurface: (@convention(c) (Int32) -> Pointer?)?
    nonisolated(unsafe) static var getCurrentContext: (@convention(c) () -> Pointer?)?

    // The GL functions EAGLContext and GLKit call themselves.
    nonisolated(unsafe) static var getString: (@convention(c) (UInt32) -> UnsafePointer<UInt8>?)?
    nonisolated(unsafe) static var getIntegerv: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void)!
    nonisolated(unsafe) static var genFramebuffers: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void)!
    nonisolated(unsafe) static var deleteFramebuffers: (@convention(c) (Int32, UnsafePointer<UInt32>?) -> Void)!
    nonisolated(unsafe) static var bindFramebuffer: (@convention(c) (UInt32, UInt32) -> Void)!
    nonisolated(unsafe) static var genRenderbuffers: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void)!
    nonisolated(unsafe) static var deleteRenderbuffers: (@convention(c) (Int32, UnsafePointer<UInt32>?) -> Void)!
    nonisolated(unsafe) static var bindRenderbuffer: (@convention(c) (UInt32, UInt32) -> Void)!
    nonisolated(unsafe) static var renderbufferStorage: (@convention(c) (UInt32, UInt32, Int32, Int32) -> Void)!
    nonisolated(unsafe) static var renderbufferStorageMultisample: (@convention(c) (UInt32, Int32, UInt32, Int32, Int32) -> Void)?
    nonisolated(unsafe) static var getRenderbufferParameteriv: (@convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void)!
    nonisolated(unsafe) static var framebufferRenderbuffer: (@convention(c) (UInt32, UInt32, UInt32, UInt32) -> Void)!
    nonisolated(unsafe) static var readPixels: (@convention(c) (Int32, Int32, Int32, Int32, UInt32, UInt32, Pointer?) -> Void)!
    nonisolated(unsafe) static var viewport: (@convention(c) (Int32, Int32, Int32, Int32) -> Void)!
    nonisolated(unsafe) static var finish: (@convention(c) () -> Void)!

    static let framebuffer: UInt32 = 0x8D40, renderbuffer: UInt32 = 0x8D41
    static let framebufferBinding: UInt32 = 0x8CA6, renderbufferBinding: UInt32 = 0x8CA7
    static let colorAttachment0: UInt32 = 0x8CE0, depthAttachment: UInt32 = 0x8D00, stencilAttachment: UInt32 = 0x8D20
    static let rgba8: UInt32 = 0x8058, rgb565: UInt32 = 0x8D62, srgb8Alpha8: UInt32 = 0x8C43
    static let depth16: UInt32 = 0x81A5, depth24: UInt32 = 0x81A6, depth24Stencil8: UInt32 = 0x88F0, stencil8: UInt32 = 0x8D48

    /// Loads the host's EGL and OpenGL ES once; false without them.
    @discardableResult
    static func load() -> Bool {
        if loaded { return display != nil }
        loaded = true
        guard let egl = dlopen("libEGL.so.1", RTLD_NOW) else { return false }
        for name in ["libGLESv2.so.2", "libGLESv1_CM.so.1"] {
            if let library = dlopen(name, RTLD_NOW) { libraries.append(library) }
        }
        func bind<T>(_ library: Pointer, _ name: String) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        getProcAddress = bind(egl, "eglGetProcAddress")
        getPlatformDisplay = bind(egl, "eglGetPlatformDisplay")
        initialize = bind(egl, "eglInitialize")
        bindAPI = bind(egl, "eglBindAPI")
        createContext = bind(egl, "eglCreateContext")
        destroyContext = bind(egl, "eglDestroyContext")
        makeCurrent = bind(egl, "eglMakeCurrent")
        getCurrentDisplay = bind(egl, "eglGetCurrentDisplay")
        getCurrentSurface = bind(egl, "eglGetCurrentSurface")
        getCurrentContext = bind(egl, "eglGetCurrentContext")
        guard let gles = libraries.first, let getPlatformDisplay, let initialize, let bindAPI else { return false }
        getString = bind(gles, "glGetString")
        getIntegerv = bind(gles, "glGetIntegerv")
        genFramebuffers = bind(gles, "glGenFramebuffers")
        deleteFramebuffers = bind(gles, "glDeleteFramebuffers")
        bindFramebuffer = bind(gles, "glBindFramebuffer")
        genRenderbuffers = bind(gles, "glGenRenderbuffers")
        deleteRenderbuffers = bind(gles, "glDeleteRenderbuffers")
        bindRenderbuffer = bind(gles, "glBindRenderbuffer")
        renderbufferStorage = bind(gles, "glRenderbufferStorage")
        renderbufferStorageMultisample = bind(gles, "glRenderbufferStorageMultisample")
        getRenderbufferParameteriv = bind(gles, "glGetRenderbufferParameteriv")
        framebufferRenderbuffer = bind(gles, "glFramebufferRenderbuffer")
        readPixels = bind(gles, "glReadPixels")
        viewport = bind(gles, "glViewport")
        finish = bind(gles, "glFinish")
        // Mesa's surfaceless platform: contexts without a window system.
        guard let display = getPlatformDisplay(0x31DD, nil, nil), initialize(display, nil, nil) != 0,
              bindAPI(0x30A0) != 0 else { return false }
        self.display = display
        return true
    }

    /// The host's function for an import such as "_glDrawArrays", or an
    /// extension's such as "_glBindFramebufferOES", which the libraries
    /// do not export; nil when the host has none. glGetString answers as
    /// iOS's does.
    static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard name.hasPrefix("_gl") else { return nil }
        if name == "_glGetString" { return unsafeBitCast(getStringFunction, to: UnsafeMutableRawPointer.self) }
        load()
        let cName = String(name.dropFirst())
        for library in libraries {
            if let symbol = dlsym(library, cName) { return symbol }
        }
        return getProcAddress?(cName)
    }

    /// The version strings for the current context's API, as iOS gives
    /// them, with the host's renderer after them.
    private static let getStringFunction: @convention(c) (UInt32) -> UnsafePointer<UInt8>? = { name in
        GLES.string(name)
    }

    nonisolated(unsafe) private static var strings: [String: UnsafePointer<UInt8>] = [:]

    static func string(_ name: UInt32) -> UnsafePointer<UInt8>? {
        load()
        let host = getString?(name).map { String(cString: $0) }
        let api = EAGLContexts.current?.context.api ?? 2
        let text: String?
        switch name {
        case 0x1F02: // GL_VERSION
            text = "OpenGL ES \(api == 1 ? "1.1" : api == 3 ? "3.0" : "2.0") Perry (\(host ?? ""))"
        case 0x8B8C: // GL_SHADING_LANGUAGE_VERSION
            text = api == 1 ? nil : "OpenGL ES GLSL ES \(api == 3 ? "3.00" : "1.00")"
        default:
            return getString?(name)
        }
        guard let text else { return nil }
        if let cached = strings[text] { return cached }
        let copy = UnsafeRawPointer(strdup(text)!).assumingMemoryBound(to: UInt8.self)
        strings[text] = copy
        return copy
    }
}

// MARK: - EAGLContext

/// An EGL context and the API it was made for.
final class GLContext {
    let handle: UnsafeMutableRawPointer
    let api: Int

    init(handle: UnsafeMutableRawPointer, api: Int) {
        self.handle = handle
        self.api = api
    }

    deinit { _ = GLES.destroyContext?(GLES.display, handle) }
}

final class SharegroupState: ObjectState {
    /// The first context made in the group, which later ones share with.
    var root: GLContext?
    var debugLabel: String?
}

@ObjCClass("EAGLSharegroup")
open class EAGLSharegroup: NSObject {
    static let states = StateTable<SharegroupState>()
    var state: SharegroupState { EAGLSharegroup.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        EAGLSharegroup.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: EAGLSharegroup.objCClass.pointer)
    }

    @ObjCMethod("debugLabel") func debugLabel() -> String? { state.debugLabel }
    @ObjCMethod("setDebugLabel:") func setDebugLabel(_ label: String?) { state.debugLabel = label }
}

final class ContextState: ObjectState {
    var context: GLContext?
    var sharegroup: EAGLSharegroup?
    var debugLabel: String?
    var multiThreaded = false
    /// Renderbuffers given storage from a layer, by name, and the layer
    /// (not retained).
    var drawables: [UInt32: UnsafeMutableRawPointer] = [:]
}

/// The current context of each thread.
enum EAGLContexts {
    nonisolated(unsafe) private static var currents: [UInt: EAGLContext] = [:]
    private static let lock = Lock()

    static var current: (object: EAGLContext, context: GLContext)? {
        lock.withLock { currents[UInt(pthread_self())] }.flatMap { object in object.state.context.map { (object, $0) } }
    }

    /// Whatever EGL context is current on this thread, with its display and
    /// surfaces, to make current again later.
    struct Saved {
        let display, draw, read, context: UnsafeMutableRawPointer?

        func restore() {
            guard let display else { return }
            _ = GLES.makeCurrent?(display, draw, read, context)
        }
    }

    static func save() -> Saved? {
        GLES.load()
        guard let currentDisplay = GLES.getCurrentDisplay, let surface = GLES.getCurrentSurface, let context = GLES.getCurrentContext else {
            return nil
        }
        // EGL_DRAW and EGL_READ.
        return Saved(display: currentDisplay(), draw: surface(0x3059), read: surface(0x305A), context: context())
    }

    /// Makes the thread's EAGLContext current again, after something else,
    /// such as the compositor, made its own current.
    static func restore() {
        guard let display = GLES.display, let makeCurrent = GLES.makeCurrent else { return }
        _ = makeCurrent(display, nil, nil, current?.context.handle)
    }

    static func setCurrent(_ context: EAGLContext?) -> Bool {
        GLES.load()
        guard let display = GLES.display, let makeCurrent = GLES.makeCurrent else { return context == nil }
        let handle = context?.state.context?.handle
        guard makeCurrent(display, nil, nil, handle) != 0 else { return false }
        lock.withLock { currents[UInt(pthread_self())] = context }
        return true
    }
}

@ObjCClass("EAGLContext")
open class EAGLContext: NSObject {
    static let states = StateTable<ContextState>()
    var state: ContextState { EAGLContext.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        EAGLContext.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: EAGLContext.objCClass.pointer)
    }

    @ObjCMethod("initWithAPI:")
    func initialize(api: UInt) -> Self? { initialize(api: api, sharegroup: nil) }

    /// nil when the host has no OpenGL ES of that version.
    @ObjCMethod("initWithAPI:sharegroup:")
    func initialize(api: UInt, sharegroup: EAGLSharegroup?) -> Self? {
        guard (1...3).contains(api), GLES.load(), let create = GLES.createContext else { return nil }
        let group = sharegroup ?? EAGLSharegroup.objCClass.object.allocated().unsafeCast(to: EAGLSharegroup.self)
        // EGL_CONTEXT_MAJOR_VERSION, then the end of the list.
        let attributes: [Int32] = [0x3098, Int32(api), 0x3038]
        guard let handle = create(GLES.display, nil, group.state.root?.handle, attributes) else { return nil }
        let context = GLContext(handle: handle, api: Int(api))
        if group.state.root == nil { group.state.root = context }
        state.context = context
        state.sharegroup = group
        return self
    }

    @ObjCClassMethod("setCurrentContext:")
    static func setCurrentContext(_ context: EAGLContext?) -> Bool { EAGLContexts.setCurrent(context) }

    @ObjCClassMethod("currentContext")
    static func currentContext() -> EAGLContext? { EAGLContexts.current?.object }

    @ObjCMethod("API") func api() -> UInt { UInt(state.context?.api ?? 0) }
    @ObjCMethod("sharegroup") func sharegroup() -> EAGLSharegroup? { state.sharegroup }
    @ObjCMethod("debugLabel") func debugLabel() -> String? { state.debugLabel }
    @ObjCMethod("setDebugLabel:") func setDebugLabel(_ label: String?) { state.debugLabel = label }
    @ObjCMethod("isMultiThreaded") func isMultiThreaded() -> Bool { state.multiThreaded }
    @ObjCMethod("setMultiThreaded:") func setMultiThreaded(_ multiThreaded: Bool) { state.multiThreaded = multiThreaded }

    /// Storage for the bound renderbuffer the size of the layer in pixels,
    /// in its drawable's color format.
    @ObjCMethod("renderbufferStorage:fromDrawable:")
    func renderbufferStorage(_ target: UInt, fromDrawable drawable: NSObject?) -> Bool {
        guard let layer = drawable?.as(CAEAGLLayer.self) else { return false }
        let bounds = layer.bounds(), scale = layer.contentsScale()
        let width = Int32((bounds.width * scale).rounded())
        let height = Int32((bounds.height * scale).rounded())
        var name: Int32 = 0
        GLES.getIntegerv(GLES.renderbufferBinding, &name)
        guard name != 0, width > 0, height > 0 else { return false }
        GLES.renderbufferStorage(UInt32(target), layer.colorFormat, width, height)
        state.drawables[UInt32(name)] = layer.objcObject
        return true
    }

    /// Shows the bound renderbuffer in the layer it has storage from.
    @ObjCMethod("presentRenderbuffer:")
    func presentRenderbuffer(_ target: UInt) -> Bool {
        var name: Int32 = 0
        GLES.getIntegerv(GLES.renderbufferBinding, &name)
        guard let layerObject = state.drawables[UInt32(name)] else { return false }
        let layer = CALayer(objcObject: layerObject, ownership: .retain)
        guard let image = Renderbuffers.image(UInt32(name), opaque: layer.isOpaque()) else { return false }
        layer.setContents(NSObject(image.object))
        Display.markDirty()
        Updates.schedule()
        return true
    }

    @ObjCMethod("presentRenderbuffer:atTime:")
    func presentRenderbuffer(_ target: UInt, atTime time: Double) -> Bool { presentRenderbuffer(target) }

    @ObjCMethod("presentRenderbuffer:afterMinimumDuration:")
    func presentRenderbuffer(_ target: UInt, afterMinimumDuration duration: Double) -> Bool { presentRenderbuffer(target) }
}

enum Renderbuffers {
    /// A renderbuffer's pixels as an image, top row first, read through a
    /// framebuffer of its own so the app's bindings are untouched.
    static func image(_ renderbuffer: UInt32, opaque: Bool) -> Owned? {
        var width: Int32 = 0, height: Int32 = 0, previousFramebuffer: Int32 = 0, previousRenderbuffer: Int32 = 0
        GLES.getIntegerv(GLES.framebufferBinding, &previousFramebuffer)
        GLES.getIntegerv(GLES.renderbufferBinding, &previousRenderbuffer)
        GLES.bindRenderbuffer(GLES.renderbuffer, renderbuffer)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D42, &width)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D43, &height)
        guard width > 0, height > 0 else { return nil }
        var framebuffer: UInt32 = 0
        GLES.genFramebuffers(1, &framebuffer)
        GLES.bindFramebuffer(GLES.framebuffer, framebuffer)
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, renderbuffer)
        let image = read(width: Int(width), height: Int(height), opaque: opaque)
        GLES.bindFramebuffer(GLES.framebuffer, UInt32(previousFramebuffer))
        GLES.bindRenderbuffer(GLES.renderbuffer, UInt32(previousRenderbuffer))
        GLES.deleteFramebuffers(1, &framebuffer)
        return image
    }

    /// The bound framebuffer's pixels as an image, flipped to top first.
    static func read(width: Int, height: Int, opaque: Bool) -> Owned? {
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        pixels.withUnsafeMutableBytes { GLES.readPixels(0, 0, Int32(width), Int32(height), 0x1908, 0x1401, $0.baseAddress) }
        var flipped = [UInt8](repeating: 0, count: pixels.count)
        for row in 0..<height {
            let from = (height - 1 - row) * rowBytes
            flipped.replaceSubrange(row * rowBytes..<(row + 1) * rowBytes, with: pixels[from..<from + rowBytes])
        }
        if opaque { for index in stride(from: 3, to: flipped.count, by: 4) { flipped[index] = 255 } }
        guard let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        // Premultiplied RGBA, first byte red.
        return flipped.withUnsafeMutableBytes { bytes -> Owned? in
            guard let context = CG.bitmapContextCreate(bytes.baseAddress, width, height, 8, rowBytes, space, 1 | 0x4000) else {
                return nil
            }
            defer { CG.release(context) }
            return CG.bitmapContextCreateImage(context).map(Owned.init)
        }
    }
}

// MARK: - CAEAGLLayer

/// QuartzCore's CAEAGLLayer keeps the drawable's properties.
extension CAEAGLLayer {
    /// The renderbuffer format for the drawable's color format.
    var colorFormat: UInt32 {
        let format = drawableProperties()?.as(NSDictionary.self)?.object(forKey: GLConstants.kEAGLDrawablePropertyColorFormat)?.stringValue
        switch format {
        case GLConstants.kEAGLColorFormatRGB565: return GLES.rgb565
        case GLConstants.kEAGLColorFormatSRGBA8: return GLES.srgb8Alpha8
        default: return GLES.rgba8
        }
    }
}

@ObjCConstants
enum GLConstants {
    static let kEAGLDrawablePropertyRetainedBacking = "EAGLDrawablePropertyRetainedBacking"
    static let kEAGLDrawablePropertyColorFormat = "EAGLDrawablePropertyColorFormat"
    static let kEAGLColorFormatRGBA8 = "EAGLColorFormat8888"
    static let kEAGLColorFormatRGB565 = "EAGLColorFormat565"
    static let kEAGLColorFormatSRGBA8 = "EAGLColorFormatSRGBA8"
}
