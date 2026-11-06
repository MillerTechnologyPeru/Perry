import CPerryGeometry
import CPerryOpenGL
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

    // OpenGL ES 3's pixel buffers and fences, for reading frames back
    // without waiting for the GPU; nil where the host has none.
    nonisolated(unsafe) static var flush: (@convention(c) () -> Void)?
    nonisolated(unsafe) static var genBuffers: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void)?
    nonisolated(unsafe) static var deleteBuffers: (@convention(c) (Int32, UnsafePointer<UInt32>?) -> Void)?
    nonisolated(unsafe) static var bindBuffer: (@convention(c) (UInt32, UInt32) -> Void)?
    nonisolated(unsafe) static var bufferData: (@convention(c) (UInt32, Int, UnsafeRawPointer?, UInt32) -> Void)?
    /// GL_EXT_buffer_storage's: storage the CPU reads from cached memory.
    nonisolated(unsafe) static var bufferStorage: (@convention(c) (UInt32, Int, UnsafeRawPointer?, UInt32) -> Void)?
    nonisolated(unsafe) static var mapBufferRange: (@convention(c) (UInt32, Int, Int, UInt32) -> UnsafeMutableRawPointer?)?
    nonisolated(unsafe) static var unmapBuffer: (@convention(c) (UInt32) -> UInt8)?
    nonisolated(unsafe) static var fenceSync: (@convention(c) (UInt32, UInt32) -> Pointer?)?
    nonisolated(unsafe) static var clientWaitSync: (@convention(c) (Pointer?, UInt32, UInt64) -> UInt32)?
    nonisolated(unsafe) static var deleteSync: (@convention(c) (Pointer?) -> Void)?
    static let pixelPackBuffer: UInt32 = 0x88EB, pixelPackBufferBinding: UInt32 = 0x88ED

    // Textures and EGL images, for sharing frames with the compositor as
    // dma-bufs; nil where the host has none.
    nonisolated(unsafe) static var getError: (@convention(c) () -> UInt32)?
    nonisolated(unsafe) static var genTextures: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void)?
    nonisolated(unsafe) static var deleteTextures: (@convention(c) (Int32, UnsafePointer<UInt32>?) -> Void)?
    nonisolated(unsafe) static var bindTexture: (@convention(c) (UInt32, UInt32) -> Void)?
    nonisolated(unsafe) static var texParameteri: (@convention(c) (UInt32, UInt32, Int32) -> Void)?
    nonisolated(unsafe) static var texImage2D: (@convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void)?
    nonisolated(unsafe) static var copyTexSubImage2D: (@convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Void)?
    nonisolated(unsafe) static var createImage: (@convention(c) (Pointer?, Pointer?, UInt32, Pointer?, UnsafePointer<Int32>?) -> Pointer?)?
    nonisolated(unsafe) static var destroyImage: (@convention(c) (Pointer?, Pointer?) -> UInt32)?
    nonisolated(unsafe) static var exportImageQuery: (@convention(c) (Pointer?, Pointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
                                                                      UnsafeMutablePointer<UInt64>?) -> UInt32)?
    nonisolated(unsafe) static var exportImage: (@convention(c) (Pointer?, Pointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
                                                                 UnsafeMutablePointer<Int32>?) -> UInt32)?
    nonisolated(unsafe) static var createSync: (@convention(c) (Pointer?, UInt32, UnsafePointer<Int32>?) -> Pointer?)?
    nonisolated(unsafe) static var destroySync: (@convention(c) (Pointer?, Pointer?) -> UInt32)?
    nonisolated(unsafe) static var dupNativeFence: (@convention(c) (Pointer?, Pointer?) -> Int32)?
    static let texture2D: UInt32 = 0x0DE1, textureBinding2D: UInt32 = 0x8069

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
        func host<T>(_ name: String) -> T? {
            (dlsym(gles, name) ?? getProcAddress?(name)).map { unsafeBitCast($0, to: T.self) }
        }
        flush = host("glFlush")
        genBuffers = host("glGenBuffers")
        deleteBuffers = host("glDeleteBuffers")
        bindBuffer = host("glBindBuffer")
        bufferData = host("glBufferData")
        bufferStorage = host("glBufferStorageEXT")
        mapBufferRange = host("glMapBufferRange")
        unmapBuffer = host("glUnmapBuffer")
        fenceSync = host("glFenceSync")
        clientWaitSync = host("glClientWaitSync")
        deleteSync = host("glDeleteSync")
        getError = host("glGetError")
        genTextures = host("glGenTextures")
        deleteTextures = host("glDeleteTextures")
        bindTexture = host("glBindTexture")
        texParameteri = host("glTexParameteri")
        texImage2D = host("glTexImage2D")
        copyTexSubImage2D = host("glCopyTexSubImage2D")
        func extension_<T>(_ name: String) -> T? { getProcAddress?(name).map { unsafeBitCast($0, to: T.self) } }
        createImage = extension_("eglCreateImageKHR")
        destroyImage = extension_("eglDestroyImageKHR")
        exportImageQuery = extension_("eglExportDMABUFImageQueryMESA")
        exportImage = extension_("eglExportDMABUFImageMESA")
        createSync = extension_("eglCreateSyncKHR")
        destroySync = extension_("eglDestroySyncKHR")
        dupNativeFence = extension_("eglDupNativeFenceFDANDROID")
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
        // Each is entered through an entry point, which gives the calling
        // thread its context first when another thread has it.
        if name == "_glGetString" { return perry_gl_entry(unsafeBitCast(getStringFunction, to: UnsafeMutableRawPointer.self)) }
        load()
        // PVRTC textures are decoded for the host, which can't sample them.
        if name == "_glCompressedTexImage2D" || name == "_glCompressedTexSubImage2D" {
            PVRTC.bind(host)
            return perry_gl_entry(name == "_glCompressedTexImage2D"
                ? unsafeBitCast(PVRTC.compressedTexImage2D, to: UnsafeMutableRawPointer.self)
                : unsafeBitCast(PVRTC.compressedTexSubImage2D, to: UnsafeMutableRawPointer.self))
        }
        // Apple's multisampling is made of OpenGL ES 3's.
        if name == "_glRenderbufferStorageMultisampleAPPLE" || name == "_glResolveMultisampleFramebufferAPPLE" {
            guard GLMultisample.bind(host) else { return nil }
            return perry_gl_entry(name == "_glRenderbufferStorageMultisampleAPPLE"
                ? unsafeBitCast(GLMultisample.renderbufferStorageMultisample, to: UnsafeMutableRawPointer.self)
                : unsafeBitCast(GLMultisample.resolveMultisampleFramebuffer, to: UnsafeMutableRawPointer.self))
        }
        let cName = String(name.dropFirst())
        return perry_gl_entry(host(cName).map { perry_gles_darwin_function(cName, $0) })
    }

    /// The host's function by its C name.
    static func host(_ cName: String) -> UnsafeMutableRawPointer? {
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
    private static let pvrtcExtension = "GL_IMG_texture_compression_pvrtc"

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
        case 0x1F03: // GL_EXTENSIONS
            // PVRTC textures, which every iOS GPU has, are decoded here
            // (PVRTC): a program that finds them missing may fall back to
            // a decoder of its own, never run on iOS.
            // Apple's multisampling is made here too (GLMultisample).
            guard let host else { return getString?(name) }
            var extensions = host
            for added in [pvrtcExtension] + (GLMultisample.bind(GLES.host) ? [GLMultisample.name] : [])
            where !extensions.contains(added) {
                extensions += (extensions.hasSuffix(" ") || extensions.isEmpty ? "" : " ") + added
            }
            text = extensions
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

    deinit {
        if GLTrace.on { GLTrace.say("context \(handle) destroyed") }
        _ = GLES.destroyContext?(GLES.display, handle)
    }
}

/// PERRY_UIKIT_GL_TRACE=1 reports contexts made, destroyed and made
/// current, renderbuffers given storage, and frame shares.
enum GLTrace {
    /// The presents so far, of which the first few and every 300th are said.
    nonisolated(unsafe) static var presents = 0
    static let on = getenv("PERRY_UIKIT_GL_TRACE") != nil

    static func say(_ text: String) {
        let line = "perry: UIKit: GL: \(text) (thread \(String(UInt(pthread_self()), radix: 16)))\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
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
    /// When the last frame was presented, for pacing.
    var lastPresent = 0.0
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

    // MARK: A context on two threads

    // An EAGLContext can be current on several threads at once, the app
    // keeping them from drawing with it together: it sets a context up on
    // the main thread and draws from its own; an engine makes its context
    // current on the main thread around each frame while its render
    // thread, which has it too, does the drawing, and has the main thread
    // make a renderbuffer's storage while the render thread waits. An EGL
    // context is current on one thread. So a context is a thread's current
    // one in EGL only when no other thread has it; otherwise in name, and
    // the thread is given the EGL context when it draws: each gl function
    // a program calls is entered through CPerryOpenGL's entry points,
    // which call beforeDrawing() while any thread's context is not its own
    // in EGL. The thread that has the EGL context is signalled then, and
    // lets it go from the signal's handler, if it is waiting. One that is
    // drawing keeps it, and the thread that asked goes without for a
    // while, as an engine's main thread does beside its render thread; one
    // that is busy with something else, as a main thread still launching
    // is when the program's own thread starts to draw, is waited for.

    /// The thread each EGL context is current on.
    nonisolated(unsafe) private static var holders: [UnsafeMutableRawPointer: UInt] = [:]
    /// When a thread last could not be given its context, to not ask for
    /// it at every call.
    nonisolated(unsafe) private static var refused: [UInt: Double] = [:]
    /// The gl calls each thread has made while contexts were contended:
    /// a thread whose count stands still is not drawing.
    nonisolated(unsafe) private static var calls: [UInt: UInt] = [:]
    /// One request at a time: the thread asked, and what it is to let go.
    private static let askLock = Lock()
    nonisolated(unsafe) private static var askedThread: pthread_t = 0
    nonisolated(unsafe) private static var askedToRelease: UnsafeMutableRawPointer?
    nonisolated(unsafe) private static var answered: UnsafeMutablePointer<sem_t>?
    nonisolated(unsafe) private static var askSignal: Int32 = 0
    /// 1 when the asked thread did as asked, 2 when it was busy.
    nonisolated(unsafe) private static var askedAnswer: Int32 = 0

    /// Counts the threads whose current context is not theirs in EGL, for
    /// the entry points. With the lock held.
    private static func updateContended() {
        let thread = { (key: UInt, context: EAGLContext) -> Bool in
            guard let handle = context.state.context?.handle else { return false }
            return holders[handle] != key
        }
        perry_gl_set_contended(Int32(currents.reduce(0) { $0 + (thread($1.key, $1.value) ? 1 : 0) }))
    }

    /// In the asked thread, which the signal interrupted anywhere: in the
    /// middle of an allocation, say, which changing the EGL context from
    /// here would then deadlock or corrupt. So it lets the context go only
    /// when it was waiting in a system call (for a semaphore, a condition,
    /// a descriptor, a time), where nothing of its own is half done, as a
    /// render thread waiting for the main thread is; otherwise it says it
    /// is busy and is asked again. It touches only what was set up before
    /// the signal was sent.
    private static let answer: @convention(c) (Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void = { _, _, raw in
        guard pthread_equal(pthread_self(), EAGLContexts.askedThread) != 0, let raw,
              let display = GLES.display, let makeCurrent = GLES.makeCurrent, let answered = EAGLContexts.answered else { return }
        let saved = errno
        let machine = raw.assumingMemoryBound(to: ucontext_t.self).pointee.uc_mcontext
        // It resumes at "svc 0", to make the call again, or just after it,
        // when the call is not restarted; x8 has the call's number: futex,
        // ppoll, epoll_pwait(2), the sleeps, pselect6, read, recvfrom,
        // recvmsg, accept.
        var waiting = false
        let pc = UInt(machine.pc)
        if pc >= 4, UnsafePointer<UInt32>(bitPattern: pc)?.pointee == 0xd400_0001
            || UnsafePointer<UInt32>(bitPattern: pc - 4)?.pointee == 0xd400_0001 {
            switch machine.regs.8 {
            case 98, 73, 22, 441, 101, 115, 72, 63, 207, 212, 202: waiting = true
            default: break
            }
        }
        if waiting, let held = EAGLContexts.askedToRelease, GLES.getCurrentContext?() == held {
            _ = makeCurrent(display, nil, nil, nil)
        }
        EAGLContexts.askedAnswer = waiting ? 1 : 2
        sem_post(answered)
        errno = saved
    }

    /// Has `thread` let `context` go, asking again while it is busy, for
    /// as long as `patience` seconds; false if it had not by then.
    private static func ask(_ thread: UInt, toRelease context: UnsafeMutableRawPointer, patience: Double) -> Bool {
        askLock.withLock {
            if answered == nil {
                let semaphore = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
                sem_init(semaphore, 0, 0)
                answered = semaphore
                // Past the signal libPerrySystem suspends threads with.
                askSignal = __libc_current_sigrtmin() + 6
                var action = sigaction()
                action.__sigaction_handler.sa_sigaction = answer
                action.sa_flags = SA_RESTART | SA_SIGINFO
                sigemptyset(&action.sa_mask)
                sigaction(askSignal, &action, nil)
            }
            guard let answered else { return false }
            (askedThread, askedToRelease) = (pthread_t(thread), context)
            let start = Clock.now
            repeat {
                askedAnswer = 0
                guard pthread_kill(pthread_t(thread), askSignal) == 0 else { return false }
                var deadline = timespec()
                clock_gettime(CLOCK_REALTIME, &deadline)
                deadline.tv_sec += 1
                while sem_timedwait(answered, &deadline) != 0 {
                    if errno != EINTR { return false }
                }
                if askedAnswer == 1 { return true }
                usleep(200)
            } while Clock.now - start < patience
            return false
        }
    }

    /// Before the calling thread draws with its current context: by a
    /// program's gl call, through the entry points, or by Perry's own, as
    /// for a renderbuffer's storage or its presentation. A context that is
    /// the thread's in name only is made its own in EGL: taken from the
    /// thread that has it, once that one waits.
    static func beforeDrawing() {
        guard let display = GLES.display, let makeCurrent = GLES.makeCurrent else { return }
        let thread = UInt(pthread_self())
        let wanted = lock.withLock { () -> (handle: UnsafeMutableRawPointer, holder: UInt?)? in
            calls[thread, default: 0] &+= 1
            guard let handle = currents[thread]?.state.context?.handle, holders[handle] != thread else { return nil }
            if let last = refused[thread], Clock.now - last < 0.1 { return nil }
            return (handle, holders[handle])
        }
        guard let wanted else { return }
        var made = makeCurrent(display, nil, nil, wanted.handle) != 0
        if !made, let holder = wanted.holder {
            // Asked for a moment at a time: a holder that drew meanwhile
            // keeps the context; one that did not is busy elsewhere, and
            // lets it go once it waits, which this thread, about to draw
            // with nothing, waits for.
            let start = Clock.now
            repeat {
                let before = lock.withLock { calls[holder] }
                // Tried again whatever it answered: a thread that ended
                // has let its context go without being asked.
                _ = ask(holder, toRelease: wanted.handle, patience: 0.05)
                made = makeCurrent(display, nil, nil, wanted.handle) != 0
                if made { break }
                if lock.withLock({ calls[holder] }) != before { break }
            } while Clock.now - start < 5
        }
        lock.withLock {
            if made {
                holders[wanted.handle] = thread
                refused[thread] = nil
            } else {
                refused[thread] = Clock.now
            }
            updateContended()
        }
        if GLTrace.on {
            GLTrace.say(made ? "context \(wanted.handle) taken for drawing\(wanted.holder.map { " from thread " + String($0, radix: 16) } ?? "")"
                             : "context \(wanted.handle) could not be taken for drawing")
        }
    }

    private static let beforeCall: @convention(c) () -> Void = { EAGLContexts.beforeDrawing() }

    static func setCurrent(_ context: EAGLContext?) -> Bool {
        GLES.load()
        guard let display = GLES.display, let makeCurrent = GLES.makeCurrent else { return context == nil }
        perry_gl_set_before_call(beforeCall)
        let thread = UInt(pthread_self())
        let handle = context?.state.context?.handle
        var made = makeCurrent(display, nil, nil, handle) != 0
        var inNameOnly = false
        if !made, let handle, lock.withLock({ currents.contains { $0.key != thread && $0.value.state.context?.handle == handle } }) {
            // Another thread has it: this thread's in name, until it draws.
            _ = makeCurrent(display, nil, nil, nil)
            (made, inNameOnly) = (true, true)
        }
        guard made else {
            if GLTrace.on { GLTrace.say("making context \(String(describing: handle)) current failed") }
            return false
        }
        let previous = lock.withLock { () -> EAGLContext? in
            let previous = currents[thread]
            // The EGL context this thread had is let go by the change.
            if let old = previous?.state.context?.handle, holders[old] == thread { holders[old] = nil }
            currents[thread] = context
            if let handle, !inNameOnly { holders[handle] = thread }
            refused[thread] = nil
            updateContended()
            return previous
        }
        if GLTrace.on, previous?.objcObject != context?.objcObject || inNameOnly {
            GLTrace.say("context \(String(describing: handle)) current\(inNameOnly ? " in name" : "")")
        }
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
        if GLTrace.on { GLTrace.say("context \(handle) made, ES \(api), sharing with \(String(describing: group.state.root?.handle))") }
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
        EAGLContexts.beforeDrawing()
        guard let layer = drawable?.as(CAEAGLLayer.self) else { return false }
        let bounds = layer.bounds(), scale = layer.contentsScale()
        let width = Int32((bounds.width * scale).rounded())
        let height = Int32((bounds.height * scale).rounded())
        var name: Int32 = 0
        GLES.getIntegerv(GLES.renderbufferBinding, &name)
        guard name != 0, width > 0, height > 0 else { return false }
        GLES.renderbufferStorage(UInt32(target), layer.colorFormat, width, height)
        if GLTrace.on {
            GLTrace.say("renderbuffer \(name) of context \(String(describing: state.context?.handle)): \(width) by \(height) from layer \(layer.objcObject)")
        }
        state.drawables[UInt32(name)] = layer.objcObject
        return true
    }

    /// Shows the bound renderbuffer in the layer it has storage from.
    @ObjCMethod("presentRenderbuffer:")
    func presentRenderbuffer(_ target: UInt) -> Bool {
        EAGLContexts.beforeDrawing()
        if GLTrace.on {
            GLTrace.presents += 1
            if GLTrace.presents <= 3 || GLTrace.presents % 300 == 0 { GLTrace.say("present \(GLTrace.presents)") }
        }
        var name: Int32 = 0
        GLES.getIntegerv(GLES.renderbufferBinding, &name)
        guard let layerObject = state.drawables[UInt32(name)] else {
            if GLTrace.on { GLTrace.say("presenting renderbuffer \(name), which has no layer's storage") }
            return false
        }
        let layer = CALayer(objcObject: layerObject, ownership: .retain)
        guard Renderbuffers.show(UInt32(name), context: state.context, layer: layer, opaque: layer.isOpaque()) else {
            if GLTrace.on { GLTrace.say("presenting renderbuffer \(name) failed") }
            return false
        }
        Display.markDirty()
        Updates.schedule()
        pace()
        return true
    }

    /// Waits out what is left of the display's frame since the last
    /// present, as presenting does on iOS, where a frame waits for the
    /// display to take it. A program may count on it for its pace: one that
    /// updates, presents and starts over at once (Monopoly) runs at the
    /// display's rate there, and as fast as it can without this. The wait
    /// is a little short of a frame, so that a program already paced by a
    /// display link, whose presents come a frame apart give or take, is
    /// not held back.
    private func pace() {
        let frame = 1.0 / 60 - 0.0005
        let now = Clock.now
        let due = state.lastPresent + frame
        if due > now, due - now < frame {
            usleep(UInt32((due - now) * 1_000_000))
            state.lastPresent = due
        } else {
            state.lastPresent = now
        }
    }

    @ObjCMethod("presentRenderbuffer:atTime:")
    func presentRenderbuffer(_ target: UInt, atTime time: Double) -> Bool { presentRenderbuffer(target) }

    @ObjCMethod("presentRenderbuffer:afterMinimumDuration:")
    func presentRenderbuffer(_ target: UInt, afterMinimumDuration duration: Double) -> Bool { presentRenderbuffer(target) }
}

enum Renderbuffers {
    /// Where frames are read back, kept from one to the next.
    nonisolated(unsafe) private static var buffer: (pointer: UnsafeMutableRawPointer, bytes: Int)?

    // MARK: Showing a frame

    /// Shows the renderbuffer's frame in the layer, its context current:
    /// shared with the compositor as a GPU buffer where the host can;
    /// else read back, through a pixel buffer when that is asked for, or
    /// at once. The pixels read back go to the layer as they are read, for
    /// the compositor to stream to its texture: no image, and no flip on
    /// the CPU.
    static func show(_ renderbuffer: UInt32, context: GLContext?, layer: CALayer, opaque: Bool) -> Bool {
        if let context {
            if share(renderbuffer, context: context, layer: layer, opaque: opaque) { return true }
            if present(renderbuffer, context: context, layer: layer) { return true }
        }
        return read(renderbuffer, into: { pixels, width, height in
            layer.setPerryPixels(pixels, width: width, height: height, opaque: opaque)
        })
    }

    // MARK: Sharing frames with the compositor

    /// A renderbuffer's frames, shared with the compositor without passing
    /// through the CPU: at each present the GPU copies the frame into one
    /// of four textures, each exported once as a dma-buf, which
    /// QuartzCore's compositor imports into SDL's context and draws. The
    /// copy goes into a texture the layer isn't using (on screen, holding
    /// the newest finished frame, or still being copied into), and comes
    /// with a fence the GPU signals when it is done, before which the
    /// compositor doesn't show it.
    final class Share {
        let context: UnsafeMutableRawPointer
        let layer: CALayer
        var framebuffer: UInt32 = 0
        var textures: [UInt32] = []
        var images: [UnsafeMutableRawPointer] = []
        var width = 0, height = 0
        /// Whether the first copy has been checked for an error.
        var checked = false

        /// One more than can be in use at once.
        static let count = 4

        init(context: UnsafeMutableRawPointer, layer: CALayer) { (self.context, self.layer) = (context, layer) }
    }

    nonisolated(unsafe) private static var shares: [Key: Share] = [:]
    private static let sharesLock = Lock()

    /// Whether frames can be shared: SDL composites with OpenGL ES, the
    /// host has EGL's dma-buf export, and nothing has failed. Snapshots
    /// need the pixels, and PERRY_UIKIT_ZERO_COPY=0 turns it off.
    nonisolated(unsafe) private static var sharing: Bool?

    private static func canShare() -> Bool {
        if let sharing { return sharing }
        let wanted = getenv("PERRY_UIKIT_ZERO_COPY").map { String(cString: $0) != "0" } ?? true
        let functions = GLES.genTextures != nil && GLES.deleteTextures != nil && GLES.bindTexture != nil && GLES.texParameteri != nil
            && GLES.texImage2D != nil && GLES.copyTexSubImage2D != nil && GLES.getError != nil && GLES.flush != nil
            && GLES.createImage != nil && GLES.destroyImage != nil && GLES.exportImageQuery != nil && GLES.exportImage != nil
        let result = wanted && functions && Snapshot.path == nil && Display.gpuRenderer == "opengles2"
        sharing = result
        return result
    }

    /// Stops sharing for good, after a failure: frames are read back.
    private static func stopSharing(_ reason: String) {
        if sharing != false { uikitWarning("GL frames can't be shared with the compositor (\(reason)); reading them back") }
        sharing = false
    }

    /// Deletes a share's textures and images, its context current, and
    /// takes its buffers from the layer.
    private static func tearDown(_ share: Share) {
        for image in share.images { _ = GLES.destroyImage?(GLES.display, image) }
        if !share.textures.isEmpty { GLES.deleteTextures?(Int32(share.textures.count), share.textures) }
        share.textures = []
        share.images = []
        share.checked = false
        share.layer.setSharedBuffers(nil, count: 0)
    }

    /// Makes the share's textures for a size and gives the layer their
    /// dma-bufs; false if the host can't export them.
    private static func build(_ share: Share, width: Int32, height: Int32, alpha: Bool) -> Bool {
        guard let genTextures = GLES.genTextures, let bindTexture = GLES.bindTexture, let texParameteri = GLES.texParameteri,
              let texImage2D = GLES.texImage2D, let createImage = GLES.createImage, let query = GLES.exportImageQuery,
              let export = GLES.exportImage else { return false }
        // GL_RGBA or GL_RGB, as the renderbuffer has alpha or not: a copy
        // can't make up a component.
        let format: UInt32 = alpha ? 0x1908 : 0x1907
        var records: [Int64] = []
        var fds: [Int32] = []
        defer { for fd in fds { close(fd) } }
        for _ in 0..<Share.count {
            var texture: UInt32 = 0
            genTextures(1, &texture)
            share.textures.append(texture)
            bindTexture(GLES.texture2D, texture)
            // Complete without mipmaps, as an EGL image's source must be.
            texParameteri(GLES.texture2D, 0x2801, 0x2601)       // GL_TEXTURE_MIN_FILTER, GL_LINEAR
            texParameteri(GLES.texture2D, 0x2800, 0x2601)       // GL_TEXTURE_MAG_FILTER
            texParameteri(GLES.texture2D, 0x2802, 0x812F)       // GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE
            texParameteri(GLES.texture2D, 0x2803, 0x812F)       // GL_TEXTURE_WRAP_T
            texImage2D(GLES.texture2D, 0, Int32(format), width, height, 0, format, 0x1401, nil)
            // EGL_GL_TEXTURE_2D_KHR, of the texture, with no attributes.
            let attributes: [Int32] = [0x3038]
            guard let image = createImage(GLES.display, share.context, 0x30B1, UnsafeMutableRawPointer(bitPattern: UInt(texture)), attributes) else {
                return false
            }
            share.images.append(image)
            var fourcc: Int32 = 0, planes: Int32 = 0, modifier: UInt64 = 0
            guard query(GLES.display, image, &fourcc, &planes, &modifier) != 0, planes == 1 else { return false }
            var fd: Int32 = -1, stride: Int32 = 0, offset: Int32 = 0
            guard export(GLES.display, image, &fd, &stride, &offset) != 0, fd >= 0 else { return false }
            fds.append(fd)
            records += [Int64(fd), Int64(width), Int64(height), Int64(stride), Int64(offset), Int64(UInt32(bitPattern: fourcc)),
                        Int64(bitPattern: modifier)]
        }
        (share.width, share.height) = (Int(width), Int(height))
        // The layer duplicates the fds; these are closed on the way out.
        records.withUnsafeBytes { share.layer.setSharedBuffers($0.baseAddress, count: Share.count) }
        return true
    }

    /// Submits the commands so far, and returns a fence the GPU signals
    /// when they are done: a sync file, the caller's to close. Without
    /// native fences, waits for the GPU instead and returns -1.
    private static func submit() -> Int32 {
        if let createSync = GLES.createSync, let destroySync = GLES.destroySync, let dupFence = GLES.dupNativeFence,
           let sync = createSync(GLES.display, 0x3144, nil) {         // EGL_SYNC_NATIVE_FENCE_ANDROID
            GLES.flush?()
            let fd = dupFence(GLES.display, sync)
            _ = destroySync(GLES.display, sync)
            if fd >= 0 { return fd }
        }
        GLES.finish()
        return -1
    }

    /// Shares the renderbuffer's frame with the compositor, its context
    /// current; false when it can't be, to read it back instead.
    private static func share(_ renderbuffer: UInt32, context: GLContext, layer: CALayer, opaque: Bool) -> Bool {
        guard canShare(), let bindTexture = GLES.bindTexture, let copy = GLES.copyTexSubImage2D, let getError = GLES.getError else {
            return false
        }
        let key = Key(context: context.handle, renderbuffer: renderbuffer)
        let share = sharesLock.withLock { () -> Share in
            if let existing = shares[key], existing.layer.objcObject == layer.objcObject { return existing }
            if GLTrace.on {
                GLTrace.say("share for renderbuffer \(renderbuffer) of context \(context.handle), layer \(layer.objcObject)"
                    + (shares[key] == nil ? "" : ", replacing one"))
            }
            let made = Share(context: context.handle, layer: layer)
            shares[key] = made
            return made
        }
        var previousFramebuffer: Int32 = 0, previousRenderbuffer: Int32 = 0, previousTexture: Int32 = 0
        GLES.getIntegerv(GLES.framebufferBinding, &previousFramebuffer)
        GLES.getIntegerv(GLES.renderbufferBinding, &previousRenderbuffer)
        GLES.getIntegerv(GLES.textureBinding2D, &previousTexture)
        defer {
            bindTexture(GLES.texture2D, UInt32(previousTexture))
            GLES.bindFramebuffer(GLES.framebuffer, UInt32(previousFramebuffer))
            GLES.bindRenderbuffer(GLES.renderbuffer, UInt32(previousRenderbuffer))
        }
        var width: Int32 = 0, height: Int32 = 0, alphaBits: Int32 = 0
        GLES.bindRenderbuffer(GLES.renderbuffer, renderbuffer)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D42, &width)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D43, &height)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D53, &alphaBits)      // GL_RENDERBUFFER_ALPHA_SIZE
        guard width > 0, height > 0 else { return false }
        if share.textures.isEmpty || share.width != Int(width) || share.height != Int(height) {
            if GLTrace.on { GLTrace.say("share for renderbuffer \(renderbuffer) of context \(context.handle) built at \(width) by \(height)") }
            tearDown(share)
            guard build(share, width: width, height: height, alpha: alphaBits > 0) else {
                tearDown(share)
                stopSharing("the host can't export textures as dma-bufs")
                return false
            }
        }
        // The buffers in use, which this frame must not go into.
        let inUse = layer.sharedSlotsInUse()
        guard inUse >= 0 else {
            tearDown(share)
            stopSharing("the compositor can't import them")
            return false
        }
        guard let slot = (0..<share.textures.count).first(where: { inUse & (1 << $0) == 0 }) else { return true }
        if share.framebuffer == 0 { GLES.genFramebuffers(1, &share.framebuffer) }
        GLES.bindFramebuffer(GLES.framebuffer, share.framebuffer)
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, renderbuffer)
        bindTexture(GLES.texture2D, share.textures[slot])
        // The first copy is checked: the formats may not allow one. The
        // app's own errors, read here, are lost only that once.
        if !share.checked { while getError() != 0 {} }
        copy(GLES.texture2D, 0, 0, 0, 0, 0, width, height)
        if !share.checked {
            share.checked = true
            let error = getError()
            guard error == 0 else {
                tearDown(share)
                stopSharing("copying a frame failed with GL error 0x\(String(error, radix: 16))")
                return false
            }
        }
        let fence = submit()
        layer.publishSharedSlot(slot, opaque: opaque || alphaBits == 0, fence: Int(fence))
        return true
    }

    // MARK: Reading back without waiting

    /// A renderbuffer's frames, read back through a pixel buffer: the GPU
    /// copies a frame into it when it is presented, behind the app's
    /// drawing, and the layer takes it once a fence says the copy is done,
    /// at a later present or when the compositor is about to draw. One copy
    /// is under way at a time: frames presented meanwhile are skipped, and
    /// the newest frame taken replaces one the screen has not shown.
    final class Readback {
        let context: UnsafeMutableRawPointer
        let layer: CALayer
        var framebuffer: UInt32 = 0
        var buffer: UInt32 = 0
        var bytes = 0, width = 0, height = 0
        var fence: UnsafeMutableRawPointer?

        init(context: UnsafeMutableRawPointer, layer: CALayer) { (self.context, self.layer) = (context, layer) }
    }

    private struct Key: Hashable {
        let context: UnsafeMutableRawPointer
        let renderbuffer: UInt32
    }

    nonisolated(unsafe) private static var readbacks: [Key: Readback] = [:]

    /// Whether frames are read back through pixel buffers: with
    /// PERRY_UIKIT_ASYNC_READBACK=1, on a host with OpenGL ES 3's, asked
    /// once a context is current. Off by default: Mesa's freedreno copies
    /// into a pixel buffer on the CPU, so it is slower there than reading
    /// at once.
    nonisolated(unsafe) private static var asynchronous: Bool?

    private static func available() -> Bool {
        if let asynchronous { return asynchronous }
        let version = GLES.getString?(0x1F02).map { String(cString: $0) } ?? ""
        let functions = GLES.genBuffers != nil && GLES.bindBuffer != nil && GLES.bufferData != nil && GLES.mapBufferRange != nil
            && GLES.unmapBuffer != nil && GLES.fenceSync != nil && GLES.clientWaitSync != nil && GLES.deleteSync != nil && GLES.flush != nil
        let wanted = getenv("PERRY_UIKIT_ASYNC_READBACK").map { String(cString: $0) == "1" } ?? false
        let result = wanted && functions && (version.contains("OpenGL ES 3") || version.contains("OpenGL ES 4"))
        asynchronous = result
        return result
    }

    /// Presents the renderbuffer, its context current, without waiting for
    /// the GPU; false when the host can't, to read it at once instead.
    static func present(_ renderbuffer: UInt32, context: GLContext, layer: CALayer) -> Bool {
        guard available() else { return false }
        let key = Key(context: context.handle, renderbuffer: renderbuffer)
        let readback = readbacks[key] ?? {
            let made = Readback(context: context.handle, layer: layer)
            readbacks[key] = made
            return made
        }()
        take(readback)
        // The GPU is still copying an earlier frame: this one is skipped,
        // and a newer one is read when the copy is done.
        guard readback.fence == nil else { return true }
        return start(readback, renderbuffer: renderbuffer)
    }

    /// Has the GPU copy the renderbuffer into the readback's pixel buffer,
    /// leaving the app's bindings as they were.
    private static func start(_ readback: Readback, renderbuffer: UInt32) -> Bool {
        guard let bindBuffer = GLES.bindBuffer, let fenceSync = GLES.fenceSync else { return false }
        var previousFramebuffer: Int32 = 0, previousRenderbuffer: Int32 = 0, previousPack: Int32 = 0
        GLES.getIntegerv(GLES.framebufferBinding, &previousFramebuffer)
        GLES.getIntegerv(GLES.renderbufferBinding, &previousRenderbuffer)
        GLES.getIntegerv(GLES.pixelPackBufferBinding, &previousPack)
        defer {
            bindBuffer(GLES.pixelPackBuffer, UInt32(previousPack))
            GLES.bindFramebuffer(GLES.framebuffer, UInt32(previousFramebuffer))
            GLES.bindRenderbuffer(GLES.renderbuffer, UInt32(previousRenderbuffer))
        }
        var width: Int32 = 0, height: Int32 = 0
        GLES.bindRenderbuffer(GLES.renderbuffer, renderbuffer)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D42, &width)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D43, &height)
        guard width > 0, height > 0 else { return false }
        if readback.framebuffer == 0 { GLES.genFramebuffers(1, &readback.framebuffer) }
        GLES.bindFramebuffer(GLES.framebuffer, readback.framebuffer)
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, renderbuffer)
        let bytes = Int(width) * Int(height) * 4
        // Storage made for the CPU to read, in cached memory, where the host
        // has it (and made again for a new size, as it can't change);
        // otherwise a buffer for reading.
        if bytes != readback.bytes, readback.buffer != 0, GLES.bufferStorage != nil {
            GLES.deleteBuffers?(1, &readback.buffer)
            readback.buffer = 0
        }
        if readback.buffer == 0 { GLES.genBuffers?(1, &readback.buffer) }
        bindBuffer(GLES.pixelPackBuffer, readback.buffer)
        if bytes != readback.bytes {
            if let storage = GLES.bufferStorage {
                storage(GLES.pixelPackBuffer, bytes, nil, 0x0001 | 0x0200)     // GL_MAP_READ_BIT, GL_CLIENT_STORAGE_BIT
            } else {
                GLES.bufferData?(GLES.pixelPackBuffer, bytes, nil, 0x88E1)    // GL_STREAM_READ
            }
            readback.bytes = bytes
        }
        // Into the bound pixel buffer, from its start.
        GLES.readPixels(0, 0, width, height, 0x1908, 0x1401, nil)
        (readback.width, readback.height) = (Int(width), Int(height))
        readback.fence = fenceSync(0x9117, 0)      // GL_SYNC_GPU_COMMANDS_COMPLETE
        GLES.flush?()
        return readback.fence != nil
    }

    /// Gives the layer the readback's frame if the GPU has copied it, with
    /// the readback's context current.
    private static func take(_ readback: Readback) {
        guard let fence = readback.fence, let wait = GLES.clientWaitSync, let bindBuffer = GLES.bindBuffer else { return }
        let status = wait(fence, 0, 0)
        // GL_TIMEOUT_EXPIRED: not yet.
        guard status != 0x911B else { return }
        GLES.deleteSync?(fence)
        readback.fence = nil
        // GL_ALREADY_SIGNALED, GL_CONDITION_SATISFIED; otherwise it failed.
        guard status == 0x911A || status == 0x911C else { return }
        var previousPack: Int32 = 0
        GLES.getIntegerv(GLES.pixelPackBufferBinding, &previousPack)
        bindBuffer(GLES.pixelPackBuffer, readback.buffer)
        if let pixels = GLES.mapBufferRange?(GLES.pixelPackBuffer, 0, readback.bytes, 0x0001) {     // GL_MAP_READ_BIT
            readback.layer.setPerryPixels(UnsafeRawPointer(pixels), width: readback.width, height: readback.height,
                                          opaque: readback.layer.isOpaque())
            _ = GLES.unmapBuffer?(GLES.pixelPackBuffer)
            Display.markDirty()
        }
        bindBuffer(GLES.pixelPackBuffer, UInt32(previousPack))
    }

    /// Before the compositor draws: the frames the GPU has finished copying
    /// go to their layers, each with its context current for the moment.
    static func collect() {
        let pending = readbacks.values.filter { $0.fence != nil }
        guard !pending.isEmpty, let display = GLES.display, let makeCurrent = GLES.makeCurrent else { return }
        let saved = EAGLContexts.save()
        for readback in pending where makeCurrent(display, nil, nil, readback.context) != 0 { take(readback) }
        saved?.restore()
    }

    /// A renderbuffer's pixels, RGBA rows bottom first as OpenGL reads
    /// them, passed to `body`; read through a framebuffer of its own so the
    /// app's bindings are untouched.
    static func read(_ renderbuffer: UInt32, into body: (UnsafeRawPointer, Int, Int) -> Void) -> Bool {
        var width: Int32 = 0, height: Int32 = 0, previousFramebuffer: Int32 = 0, previousRenderbuffer: Int32 = 0
        GLES.getIntegerv(GLES.framebufferBinding, &previousFramebuffer)
        GLES.getIntegerv(GLES.renderbufferBinding, &previousRenderbuffer)
        GLES.bindRenderbuffer(GLES.renderbuffer, renderbuffer)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D42, &width)
        GLES.getRenderbufferParameteriv(GLES.renderbuffer, 0x8D43, &height)
        guard width > 0, height > 0 else { return false }
        var framebuffer: UInt32 = 0
        GLES.genFramebuffers(1, &framebuffer)
        GLES.bindFramebuffer(GLES.framebuffer, framebuffer)
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, renderbuffer)
        let bytes = Int(width) * Int(height) * 4
        if buffer.map({ $0.bytes < bytes }) ?? true {
            buffer?.pointer.deallocate()
            buffer = (.allocate(byteCount: bytes, alignment: 16), bytes)
        }
        let pointer = buffer!.pointer
        GLES.readPixels(0, 0, width, height, 0x1908, 0x1401, pointer)
        GLES.bindFramebuffer(GLES.framebuffer, UInt32(previousFramebuffer))
        GLES.bindRenderbuffer(GLES.renderbuffer, UInt32(previousRenderbuffer))
        GLES.deleteFramebuffers(1, &framebuffer)
        body(pointer, Int(width), Int(height))
        return true
    }

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
