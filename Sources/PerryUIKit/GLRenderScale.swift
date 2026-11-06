import CPerryGeometry
import Glibc
import PerryObjCInterop

/// Draws a program's screen at more pixels than it asks for, so that a game
/// made for a 320 by 480 screen stays sharp on a display of many more.
/// PERRY_UIKIT_GL_SCALE turns it on: "native" for the display's own pixels,
/// or the factor to multiply the program's pixels by.
///
/// The drawable's renderbuffer, and any renderbuffer the program sizes to
/// match it (its depth buffer), get the factor's pixels. A framebuffer
/// drawing into them has its state in pixels scaled to match: the viewport,
/// the scissor box, line widths and point sizes. Every size the program can
/// ask for reads back as it set it, so it never sees the difference.
/// Framebuffers it draws into off screen are left alone.
///
/// Not scaled: glReadPixels and glCopyTexImage2D from the screen, OpenGL
/// ES 3's own multisampling and blits, and shaders that use gl_FragCoord
/// or gl_PointSize.
enum GLRenderScale {
    /// The setting: nil when off, 0 for the display's pixels, else the
    /// factor.
    private static let setting: CGFloat? = {
        guard let value = getenv("PERRY_UIKIT_GL_SCALE").map({ String(cString: $0).lowercased() }) else { return nil }
        if value == "native" { return 0 }
        guard let factor = Double(value), factor > 1 else { return nil }
        return CGFloat(min(factor, 8))
    }()

    static var isOn: Bool { setting != nil }

    /// What the program's pixels are multiplied by, set when its drawable
    /// gets storage.
    nonisolated(unsafe) private static var factor: CGFloat = 1

    private static let lock = Lock()
    nonisolated(unsafe) private static var scaledRenderbuffers: Set<UInt32> = []
    nonisolated(unsafe) private static var scaledFramebuffers: Set<UInt32> = []
    /// Framebuffers whose color target is a texture or a renderbuffer of
    /// the program's own size: its passes off screen.
    nonisolated(unsafe) private static var unscaledFramebuffers: Set<UInt32> = []
    /// The framebuffer each depth or stencil renderbuffer is attached to,
    /// whose color target's size it has to match.
    nonisolated(unsafe) private static var attachedTo: [UInt32: UInt32] = [:]
    /// The drawable's size as the program knows it, and its renderbuffer.
    nonisolated(unsafe) private static var drawableWidth: Int32 = 0
    nonisolated(unsafe) private static var drawableHeight: Int32 = 0
    nonisolated(unsafe) private static var drawableRenderbuffer: UInt32 = 0

    // MARK: The host's functions

    private typealias Rect = @convention(c) (Int32, Int32, Int32, Int32) -> Void
    private typealias Width = @convention(c) (Float) -> Void
    private typealias WidthFixed = @convention(c) (Int32) -> Void
    private typealias GetIntegerv = @convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void
    private typealias Storage = @convention(c) (UInt32, UInt32, Int32, Int32) -> Void
    private typealias StorageMultisample = @convention(c) (UInt32, Int32, UInt32, Int32, Int32) -> Void
    private typealias GetParameter = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void
    private typealias AttachRenderbuffer = @convention(c) (UInt32, UInt32, UInt32, UInt32) -> Void
    private typealias AttachTexture = @convention(c) (UInt32, UInt32, UInt32, UInt32, Int32) -> Void
    private typealias GetAttachment = @convention(c) (UInt32, UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void

    /// The host's function by its OpenGL ES 2 name, or by OpenGL ES 1's
    /// extension's.
    private static func host<T>(_ name: String) -> T? {
        (GLES.host(name) ?? GLES.host(name + "OES")).map { unsafeBitCast($0, to: T.self) }
    }

    private static let hostViewport: Rect? = host("glViewport")
    private static let hostScissor: Rect? = host("glScissor")
    private static let hostLineWidth: Width? = host("glLineWidth")
    private static let hostPointSize: Width? = host("glPointSize")
    private static let hostLineWidthx: WidthFixed? = host("glLineWidthx")
    private static let hostPointSizex: WidthFixed? = host("glPointSizex")
    private static let hostGetIntegerv: GetIntegerv? = host("glGetIntegerv")
    private static let hostStorage: Storage? = host("glRenderbufferStorage")
    private static let hostStorageMultisample: StorageMultisample? = host("glRenderbufferStorageMultisample")
    private static let hostGetParameter: GetParameter? = host("glGetRenderbufferParameteriv")
    private static let hostAttachRenderbuffer: AttachRenderbuffer? = host("glFramebufferRenderbuffer")
    private static let hostAttachTexture: AttachTexture? = host("glFramebufferTexture2D")
    private static let hostGetAttachment: GetAttachment? = host("glGetFramebufferAttachmentParameteriv")

    private static let viewportName: UInt32 = 0x0BA2, scissorBox: UInt32 = 0x0C10
    private static let framebufferBinding: UInt32 = 0x8CA6, renderbufferBinding: UInt32 = 0x8CA7
    private static let renderbuffer: UInt32 = 0x8D41, framebuffer: UInt32 = 0x8D40
    private static let renderbufferWidth: UInt32 = 0x8D42, renderbufferHeight: UInt32 = 0x8D43
    private static let colorAttachment: UInt32 = 0x8CE0

    // Asked of GL rather than kept: programs set up the screen on one
    // thread and draw on another.
    private static func bound(_ name: UInt32) -> UInt32 {
        var value: Int32 = 0
        hostGetIntegerv?(name, &value)
        return UInt32(bitPattern: value)
    }

    /// Whether the bound framebuffer draws into the screen's renderbuffers.
    private static var scaling: Bool {
        let name = bound(framebufferBinding)
        return lock.withLock { scaledFramebuffers.contains(name) }
    }

    private static func scaled(_ value: Int32) -> Int32 { Int32((CGFloat(value) * factor).rounded()) }
    private static func unscaled(_ value: Int32) -> Int32 { Int32((CGFloat(value) / factor).rounded()) }

    // MARK: The drawable

    /// The pixels to give the drawable's renderbuffer, which the program
    /// knows as `width` by `height`, of a layer at `layerScale` pixels a
    /// point.
    static func drawable(renderbuffer name: UInt32, width: Int32, height: Int32, layerScale: CGFloat) -> (Int32, Int32) {
        guard let setting else { return (width, height) }
        // The display's pixels: as many a point as it has, over the layer's.
        factor = setting > 0 ? setting : max(Display.scale / max(layerScale, 1), 1)
        lock.withLock {
            drawableWidth = width
            drawableHeight = height
            drawableRenderbuffer = name
            scaledRenderbuffers.insert(name)
        }
        if GLTrace.on || factor > 1 {
            uikitWarning("OpenGL ES: the \(width) by \(height) screen is drawn at \(scaled(width)) by \(scaled(height))")
        }
        return (scaled(width), scaled(height))
    }

    /// The pixels for storage the program asks for at `width` by `height`:
    /// the factor's when that is the drawable's size, for the screen's
    /// depth, stencil or multisample buffer, unless it is attached to a
    /// framebuffer off screen. One not attached yet is settled when it is.
    static func storage(width: Int32, height: Int32) -> (Int32, Int32) {
        guard isOn else { return (width, height) }
        let name = bound(renderbufferBinding)
        let scale = lock.withLock { () -> Bool in
            let offScreen = attachedTo[name].map { unscaledFramebuffers.contains($0) } ?? false
            let scale = width > 0 && width == drawableWidth && height == drawableHeight && !offScreen
            if scale { scaledRenderbuffers.insert(name) } else { scaledRenderbuffers.remove(name) }
            return scale
        }
        return scale ? (scaled(width), scaled(height)) : (width, height)
    }

    /// Gives a drawable-sized depth or stencil renderbuffer of the bound
    /// framebuffer the size its color target has: the factor's for the
    /// screen, the program's own off screen.
    private static func matchDepthAndStencil(scaled wanted: Bool) {
        guard let hostGetAttachment, let hostGetParameter, let hostStorage else { return }
        for attachment: UInt32 in [0x8D00, 0x8D20] {    // GL_DEPTH_ATTACHMENT, GL_STENCIL_ATTACHMENT
            var type: Int32 = 0, name: Int32 = 0
            hostGetAttachment(framebuffer, attachment, 0x8CD0, &type)   // the object's type
            guard type == Int32(renderbuffer) else { continue }
            hostGetAttachment(framebuffer, attachment, 0x8CD1, &name)   // and its name
            let attached = UInt32(bitPattern: name)
            let (width, height, isDrawable) = lock.withLock { (drawableWidth, drawableHeight, attached == drawableRenderbuffer) }
            guard !isDrawable, width > 0 else { continue }
            let previous = bound(renderbufferBinding)
            GLES.bindRenderbuffer(renderbuffer, attached)
            var current: Int32 = 0, format: Int32 = 0, samples: Int32 = 0
            hostGetParameter(renderbuffer, renderbufferWidth, &current)
            hostGetParameter(renderbuffer, 0x8D44, &format)             // GL_RENDERBUFFER_INTERNAL_FORMAT
            hostGetParameter(renderbuffer, 0x8CAB, &samples)            // GL_RENDERBUFFER_SAMPLES
            let isScreenSized = current == width || current == scaled(width)
            let pixels = wanted ? (scaled(width), scaled(height)) : (width, height)
            if isScreenSized, current != pixels.0 {
                if samples > 0, let hostStorageMultisample {
                    hostStorageMultisample(renderbuffer, samples, UInt32(bitPattern: format), pixels.0, pixels.1)
                } else {
                    hostStorage(renderbuffer, UInt32(bitPattern: format), pixels.0, pixels.1)
                }
            }
            GLES.bindRenderbuffer(renderbuffer, previous)
            if isScreenSized {
                lock.withLock {
                    if wanted { scaledRenderbuffers.insert(attached) } else { scaledRenderbuffers.remove(attached) }
                }
            }
        }
    }

    // MARK: The program's functions

    private static let viewport: Rect = { x, y, width, height in rect(hostViewport, x, y, width, height) }
    private static let scissor: Rect = { x, y, width, height in rect(hostScissor, x, y, width, height) }

    /// A rectangle in the bound framebuffer's pixels: its edges scaled, so
    /// that rectangles side by side still meet.
    private static func rect(_ function: Rect?, _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) {
        guard scaling else {
            function?(x, y, width, height)
            return
        }
        let left = scaled(x), bottom = scaled(y)
        function?(left, bottom, scaled(x &+ width) - left, scaled(y &+ height) - bottom)
    }

    private static let lineWidth: Width = { width in hostLineWidth?(scaling ? width * Float(factor) : width) }
    private static let pointSize: Width = { size in hostPointSize?(scaling ? size * Float(factor) : size) }
    private static let lineWidthx: WidthFixed = { width in hostLineWidthx?(scaling ? scaled(width) : width) }
    private static let pointSizex: WidthFixed = { size in hostPointSizex?(scaling ? scaled(size) : size) }

    /// The viewport and the scissor box read back in the program's pixels.
    private static let getIntegerv: GetIntegerv = { name, values in
        hostGetIntegerv?(name, values)
        guard let values, name == viewportName || name == scissorBox, scaling else { return }
        for index in 0..<4 { values[index] = unscaled(values[index]) }
    }

    private static let renderbufferStorage: Storage = { target, format, width, height in
        let pixels = storage(width: width, height: height)
        hostStorage?(target, format, pixels.0, pixels.1)
    }

    /// A scaled renderbuffer's size reads back as the drawable's.
    private static let getRenderbufferParameteriv: GetParameter = { target, name, value in
        hostGetParameter?(target, name, value)
        guard let value, name == renderbufferWidth || name == renderbufferHeight else { return }
        let rb = bound(renderbufferBinding)
        lock.withLock {
            guard scaledRenderbuffers.contains(rb) else { return }
            value.pointee = name == renderbufferWidth ? drawableWidth : drawableHeight
        }
    }

    /// A framebuffer is scaled while its color attachment is a scaled
    /// renderbuffer.
    private static let framebufferRenderbuffer: AttachRenderbuffer = { target, attachment, renderbufferTarget, name in
        let fb = bound(framebufferBinding)
        let color = lock.withLock { () -> Bool? in
            if attachment == colorAttachment {
                if scaledRenderbuffers.contains(name) {
                    scaledFramebuffers.insert(fb)
                    unscaledFramebuffers.remove(fb)
                } else {
                    scaledFramebuffers.remove(fb)
                    unscaledFramebuffers.insert(fb)
                }
            } else if name != 0 {
                attachedTo[name] = fb
            }
            return scaledFramebuffers.contains(fb) ? true : unscaledFramebuffers.contains(fb) ? false : nil
        }
        hostAttachRenderbuffer?(target, attachment, renderbufferTarget, name)
        if fb != 0, let color { matchDepthAndStencil(scaled: color) }
    }

    /// Drawing into a texture: its depth and stencil keep the program's
    /// size.
    private static let framebufferTexture2D: AttachTexture = { target, attachment, textureTarget, texture, level in
        let fb = bound(framebufferBinding)
        if attachment == colorAttachment {
            lock.withLock {
                scaledFramebuffers.remove(fb)
                unscaledFramebuffers.insert(fb)
            }
        }
        hostAttachTexture?(target, attachment, textureTarget, texture, level)
        if fb != 0, attachment == colorAttachment { matchDepthAndStencil(scaled: false) }
    }

    /// The function a program's import binds to while scaling, by its C
    /// name; nil for those left to the host.
    static func function(_ name: String) -> UnsafeMutableRawPointer? {
        guard isOn else { return nil }
        func pointer<T>(_ function: T) -> UnsafeMutableRawPointer { unsafeBitCast(function, to: UnsafeMutableRawPointer.self) }
        switch name {
        case "glViewport": return pointer(viewport)
        case "glScissor": return pointer(scissor)
        // Their widths arrive as Darwin passes floating point.
        case "glLineWidth": return perry_gles_darwin_function(name, pointer(lineWidth))
        case "glPointSize": return perry_gles_darwin_function(name, pointer(pointSize))
        case "glLineWidthx", "glLineWidthxOES": return pointer(lineWidthx)
        case "glPointSizex", "glPointSizexOES": return pointer(pointSizex)
        case "glGetIntegerv": return pointer(getIntegerv)
        case "glRenderbufferStorage", "glRenderbufferStorageOES": return pointer(renderbufferStorage)
        case "glGetRenderbufferParameteriv", "glGetRenderbufferParameterivOES": return pointer(getRenderbufferParameteriv)
        case "glFramebufferRenderbuffer", "glFramebufferRenderbufferOES": return pointer(framebufferRenderbuffer)
        case "glFramebufferTexture2D", "glFramebufferTexture2DOES": return pointer(framebufferTexture2D)
        default: return nil
        }
    }
}
