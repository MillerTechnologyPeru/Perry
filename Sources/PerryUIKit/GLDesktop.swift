import CPerryOpenGL
import Glibc

// OpenGL ES 1 on desktop OpenGL. Some hosts' Mesa makes no OpenGL ES 1
// context (Debian's: EGL answers EGL_BAD_ALLOC) but makes OpenGL
// compatibility contexts, whose fixed-function pipeline is ES 1's. There an
// EAGLContext for ES 1 is a compatibility context, made current through
// EGL's OpenGL API, and the ES 1 names desktop OpenGL lacks are mapped:
// extensions' OES functions to their core names, the single-precision
// glOrthof, glFrustumf, glClipPlanef and the like to desktop OpenGL's
// double-precision ones, and the common fixed-point (x) functions to their
// floating-point ones. Hosts with OpenGL ES 1 are left as they are.

enum GLDesktop {
    typealias Pointer = UnsafeMutableRawPointer
    static let openGLESAPI: UInt32 = 0x30A0, openGLAPI: UInt32 = 0x30A2

    /// Whether ES 1 contexts are compatibility contexts here: the host
    /// makes no ES 1 context but makes an OpenGL one.
    static let isOn: Bool = {
        guard GLES.load(), let create = GLES.createContext, let destroy = GLES.destroyContext,
              let bindAPI = GLES.bindAPI, let display = GLES.display else { return false }
        _ = bindAPI(openGLESAPI)
        let es1: [Int32] = [0x3098, 1, 0x3038]     // EGL_CONTEXT_MAJOR_VERSION 1
        if let context = create(display, nil, nil, es1) {
            _ = destroy(display, context)
            return false
        }
        defer { _ = bindAPI(openGLESAPI) }
        guard bindAPI(openGLAPI) != 0, let context = create(display, nil, nil, [0x3038]) else { return false }
        _ = destroy(display, context)
        let line = "perry: UIKit: the host has no OpenGL ES 1; its contexts are OpenGL compatibility contexts\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        wrapCurrentContext()
        return true
    }()

    nonisolated(unsafe) private static var desktopHandles = Set<UInt>()
    private static let lock = Lock()

    static func isDesktop(_ handle: Pointer?) -> Bool {
        guard let handle else { return false }
        return lock.withLock { desktopHandles.contains(UInt(bitPattern: handle)) }
    }

    /// A compatibility context sharing with `share` when it is one too.
    static func createContext(sharing share: Pointer?) -> Pointer? {
        guard isOn, let create = GLES.createContext, let bindAPI = GLES.bindAPI else { return nil }
        defer { _ = bindAPI(openGLESAPI) }
        guard bindAPI(openGLAPI) != 0,
              let handle = create(GLES.display, nil, isDesktop(share) ? share : nil, [0x3038]) else { return nil }
        lock.withLock { _ = desktopHandles.insert(UInt(bitPattern: handle)) }
        return handle
    }

    static func forget(_ handle: Pointer) { lock.withLock { _ = desktopHandles.remove(UInt(bitPattern: handle)) } }

    // MARK: Current contexts

    // EGL keeps a current context for each API: a context is made current
    // under its own, after the other's is let go, so one is current.
    nonisolated(unsafe) private static var hostMakeCurrent: (@convention(c) (Pointer?, Pointer?, Pointer?, Pointer?) -> UInt32)?
    nonisolated(unsafe) private static var hostGetCurrentContext: (@convention(c) () -> Pointer?)?

    private static func wrapCurrentContext() {
        hostMakeCurrent = GLES.makeCurrent
        hostGetCurrentContext = GLES.getCurrentContext
        GLES.makeCurrent = makeCurrent
        GLES.getCurrentContext = getCurrentContext
    }

    private static let makeCurrent: @convention(c) (Pointer?, Pointer?, Pointer?, Pointer?) -> UInt32 = { display, draw, read, context in
        guard let real = GLDesktop.hostMakeCurrent, let bindAPI = GLES.bindAPI else { return 0 }
        guard let context else {
            _ = bindAPI(GLDesktop.openGLAPI)
            _ = real(display, nil, nil, nil)
            _ = bindAPI(GLDesktop.openGLESAPI)
            return real(display, nil, nil, nil)
        }
        let desktop = GLDesktop.isDesktop(context)
        _ = bindAPI(desktop ? GLDesktop.openGLESAPI : GLDesktop.openGLAPI)
        _ = real(display, nil, nil, nil)
        _ = bindAPI(desktop ? GLDesktop.openGLAPI : GLDesktop.openGLESAPI)
        return real(display, draw, read, context)
    }

    private static let getCurrentContext: @convention(c) () -> Pointer? = {
        guard let real = GLDesktop.hostGetCurrentContext, let bindAPI = GLES.bindAPI else { return nil }
        if let context = real() { return context }
        // The other API's, which stays bound if it has one.
        _ = bindAPI(GLDesktop.openGLAPI)
        if let context = real() { return context }
        _ = bindAPI(GLDesktop.openGLESAPI)
        return real()
    }

    // MARK: Functions

    /// OES functions desktop OpenGL has under their core names.
    private static let coreNames: Set<String> = [
        "glBindFramebuffer", "glBindRenderbuffer", "glCheckFramebufferStatus", "glDeleteFramebuffers",
        "glDeleteRenderbuffers", "glFramebufferRenderbuffer", "glFramebufferTexture2D", "glGenFramebuffers",
        "glGenRenderbuffers", "glGenerateMipmap", "glGetFramebufferAttachmentParameteriv",
        "glGetRenderbufferParameteriv", "glIsFramebuffer", "glIsRenderbuffer", "glRenderbufferStorage",
        "glBlendEquation", "glBlendEquationSeparate", "glBlendFuncSeparate", "glMapBuffer", "glUnmapBuffer",
        "glGetBufferPointerv", "glBindVertexArray", "glDeleteVertexArrays", "glGenVertexArrays", "glIsVertexArray",
        "glClearDepthf", "glDepthRangef",
    ]

    /// The function a program's import of `name` binds to here, or nil to
    /// look it up as usual.
    static func function(_ name: String) -> Pointer? {
        func pointer<T>(_ function: T) -> Pointer { unsafeBitCast(function, to: Pointer.self) }
        let plain = name.hasSuffix("OES") ? String(name.dropLast(3)) : name
        // Only names it maps decide whether it is on: finding out makes
        // contexts.
        guard shimNames.contains(plain) || (plain != name && coreNames.contains(plain)), isOn else { return nil }
        switch plain {
        case "glOrthof": bind(); return pointer(orthof)
        case "glFrustumf": bind(); return pointer(frustumf)
        case "glClipPlanef": bind(); return pointer(clipPlanef)
        case "glGetClipPlanef": bind(); return pointer(getClipPlanef)
        case "glOrthox": bind(); return pointer(orthox)
        case "glFrustumx": bind(); return pointer(frustumx)
        case "glTranslatex": bind(); return pointer(translatex)
        case "glRotatex": bind(); return pointer(rotatex)
        case "glScalex": bind(); return pointer(scalex)
        case "glColor4x": bind(); return pointer(color4x)
        case "glClearColorx": bind(); return pointer(clearColorx)
        case "glClearDepthx": bind(); return pointer(clearDepthx)
        case "glAlphaFuncx": bind(); return pointer(alphaFuncx)
        case "glTexEnvx": bind(); return pointer(texEnvx)
        case "glTexParameterx": bind(); return pointer(texParameterx)
        case "glLoadMatrixx": bind(); return pointer(loadMatrixx)
        case "glMultMatrixx": bind(); return pointer(multMatrixx)
        case "glNormal3x": bind(); return pointer(normal3x)
        default: break
        }
        if plain != name, coreNames.contains(plain) { return GLES.host(plain) }
        return nil
    }

    private static let shimNames: Set<String> = [
        "glOrthof", "glFrustumf", "glClipPlanef", "glGetClipPlanef", "glOrthox", "glFrustumx", "glTranslatex", "glRotatex",
        "glScalex", "glColor4x", "glClearColorx", "glClearDepthx", "glAlphaFuncx", "glTexEnvx", "glTexParameterx",
        "glLoadMatrixx", "glMultMatrixx", "glNormal3x",
    ]

    typealias Double6 = @convention(c) (Double, Double, Double, Double, Double, Double) -> Void
    nonisolated(unsafe) private static var ortho: Double6?
    nonisolated(unsafe) private static var frustum: Double6?
    nonisolated(unsafe) private static var clipPlane: (@convention(c) (UInt32, UnsafePointer<Double>?) -> Void)?
    nonisolated(unsafe) private static var getClipPlane: (@convention(c) (UInt32, UnsafeMutablePointer<Double>?) -> Void)?
    nonisolated(unsafe) private static var translatef: (@convention(c) (Float, Float, Float) -> Void)?
    nonisolated(unsafe) private static var rotatef: (@convention(c) (Float, Float, Float, Float) -> Void)?
    nonisolated(unsafe) private static var scalef: (@convention(c) (Float, Float, Float) -> Void)?
    nonisolated(unsafe) private static var color4f: (@convention(c) (Float, Float, Float, Float) -> Void)?
    nonisolated(unsafe) private static var clearColor: (@convention(c) (Float, Float, Float, Float) -> Void)?
    nonisolated(unsafe) private static var clearDepth: (@convention(c) (Double) -> Void)?
    nonisolated(unsafe) private static var alphaFunc: (@convention(c) (UInt32, Float) -> Void)?
    nonisolated(unsafe) private static var texEnvf: (@convention(c) (UInt32, UInt32, Float) -> Void)?
    nonisolated(unsafe) private static var texParameterf: (@convention(c) (UInt32, UInt32, Float) -> Void)?
    nonisolated(unsafe) private static var loadMatrixf: (@convention(c) (UnsafePointer<Float>?) -> Void)?
    nonisolated(unsafe) private static var multMatrixf: (@convention(c) (UnsafePointer<Float>?) -> Void)?
    nonisolated(unsafe) private static var normal3f: (@convention(c) (Float, Float, Float) -> Void)?
    nonisolated(unsafe) private static var bound = false

    private static func bind() {
        guard !bound else { return }
        bound = true
        func host<T>(_ name: String) -> T? { GLES.host(name).map { unsafeBitCast($0, to: T.self) } }
        ortho = host("glOrtho")
        frustum = host("glFrustum")
        clipPlane = host("glClipPlane")
        getClipPlane = host("glGetClipPlane")
        translatef = host("glTranslatef")
        rotatef = host("glRotatef")
        scalef = host("glScalef")
        color4f = host("glColor4f")
        clearColor = host("glClearColor")
        clearDepth = host("glClearDepth")
        alphaFunc = host("glAlphaFunc")
        texEnvf = host("glTexEnvf")
        texParameterf = host("glTexParameterf")
        loadMatrixf = host("glLoadMatrixf")
        multMatrixf = host("glMultMatrixf")
        normal3f = host("glNormal3f")
    }

    /// 16.16 fixed point as floating point.
    private static func f(_ x: Int32) -> Float { Float(x) / 65536 }

    private static let orthof: @convention(c) (Float, Float, Float, Float, Float, Float) -> Void = { l, r, b, t, n, fa in
        GLDesktop.ortho?(Double(l), Double(r), Double(b), Double(t), Double(n), Double(fa))
    }
    private static let frustumf: @convention(c) (Float, Float, Float, Float, Float, Float) -> Void = { l, r, b, t, n, fa in
        GLDesktop.frustum?(Double(l), Double(r), Double(b), Double(t), Double(n), Double(fa))
    }
    private static let clipPlanef: @convention(c) (UInt32, UnsafePointer<Float>?) -> Void = { plane, equation in
        guard let equation else { return }
        let values = (0..<4).map { Double(equation[$0]) }
        values.withUnsafeBufferPointer { GLDesktop.clipPlane?(plane, $0.baseAddress) }
    }
    private static let getClipPlanef: @convention(c) (UInt32, UnsafeMutablePointer<Float>?) -> Void = { plane, equation in
        guard let equation else { return }
        var values = [Double](repeating: 0, count: 4)
        values.withUnsafeMutableBufferPointer { GLDesktop.getClipPlane?(plane, $0.baseAddress) }
        for index in 0..<4 { equation[index] = Float(values[index]) }
    }
    private static let orthox: @convention(c) (Int32, Int32, Int32, Int32, Int32, Int32) -> Void = { l, r, b, t, n, fa in
        GLDesktop.ortho?(Double(f(l)), Double(f(r)), Double(f(b)), Double(f(t)), Double(f(n)), Double(f(fa)))
    }
    private static let frustumx: @convention(c) (Int32, Int32, Int32, Int32, Int32, Int32) -> Void = { l, r, b, t, n, fa in
        GLDesktop.frustum?(Double(f(l)), Double(f(r)), Double(f(b)), Double(f(t)), Double(f(n)), Double(f(fa)))
    }
    private static let translatex: @convention(c) (Int32, Int32, Int32) -> Void = { x, y, z in GLDesktop.translatef?(f(x), f(y), f(z)) }
    private static let rotatex: @convention(c) (Int32, Int32, Int32, Int32) -> Void = { a, x, y, z in GLDesktop.rotatef?(f(a), f(x), f(y), f(z)) }
    private static let scalex: @convention(c) (Int32, Int32, Int32) -> Void = { x, y, z in GLDesktop.scalef?(f(x), f(y), f(z)) }
    private static let color4x: @convention(c) (Int32, Int32, Int32, Int32) -> Void = { r, g, b, a in GLDesktop.color4f?(f(r), f(g), f(b), f(a)) }
    private static let clearColorx: @convention(c) (Int32, Int32, Int32, Int32) -> Void = { r, g, b, a in
        GLDesktop.clearColor?(f(r), f(g), f(b), f(a))
    }
    private static let clearDepthx: @convention(c) (Int32) -> Void = { depth in GLDesktop.clearDepth?(Double(f(depth))) }
    private static let alphaFuncx: @convention(c) (UInt32, Int32) -> Void = { function, reference in GLDesktop.alphaFunc?(function, f(reference)) }
    /// Enumerated values pass through as they are, as ES 1 reads them.
    private static let texEnvx: @convention(c) (UInt32, UInt32, Int32) -> Void = { target, name, value in
        GLDesktop.texEnvf?(target, name, Float(value))
    }
    private static let texParameterx: @convention(c) (UInt32, UInt32, Int32) -> Void = { target, name, value in
        GLDesktop.texParameterf?(target, name, Float(value))
    }
    private static let loadMatrixx: @convention(c) (UnsafePointer<Int32>?) -> Void = { matrix in
        guard let matrix else { return }
        let values = (0..<16).map { f(matrix[$0]) }
        values.withUnsafeBufferPointer { GLDesktop.loadMatrixf?($0.baseAddress) }
    }
    private static let multMatrixx: @convention(c) (UnsafePointer<Int32>?) -> Void = { matrix in
        guard let matrix else { return }
        let values = (0..<16).map { f(matrix[$0]) }
        values.withUnsafeBufferPointer { GLDesktop.multMatrixf?($0.baseAddress) }
    }
    private static let normal3x: @convention(c) (Int32, Int32, Int32) -> Void = { x, y, z in GLDesktop.normal3f?(f(x), f(y), f(z)) }
}
