import CPerryGeometry
import Glibc
import PerryObjCInterop

// MetalKit's view: MTKView, a view backed by QuartzCore's CAMetalLayer. Each
// frame it hands its delegate (-drawInMTKView:, or a subclass's -drawRect:)
// the layer's next drawable and a render pass descriptor over it, with a
// depth and stencil texture of its own when asked for one; the app renders
// and presents the drawable itself. Frames come at the preferred rate while
// the view is not paused, or, with enableSetNeedsDisplay, when it is marked
// as needing display.

/// MTLClearColor: four doubles, red, green, blue and alpha.
typealias MTKClearColor = PerryClearColor

extension PerryClearColor: ObjCScalar {
    public static var objCTypeEncoding: String { "{MTLClearColor=dddd}" }
}

/// MTLPixelFormat's depth and stencil formats.
enum MetalPixelFormats {
    static let bgra8Unorm: UInt = 80
    static let depth32Float: UInt = 252
    static let stencil8: UInt = 253
    static let depth24UnormStencil8: UInt = 255
    static let depth32FloatStencil8: UInt = 260
    static let x32Stencil8: UInt = 261

    static func hasDepth(_ format: UInt) -> Bool {
        format == 250 || format == depth32Float || format == depth24UnormStencil8 || format == depth32FloatStencil8
    }

    static func hasStencil(_ format: UInt) -> Bool {
        format == stencil8 || format == depth24UnormStencil8 || format == depth32FloatStencil8 || format == x32Stencil8
    }
}

final class MTKViewState: ObjectState {
    var delegate: UnsafeMutableRawPointer?
    var depthStencilPixelFormat: UInt = 0
    var depthStencilStorageMode: UInt = 2           // MTLStorageModePrivate
    var depthStencilAttachmentTextureUsage: UInt = 4 // MTLTextureUsageRenderTarget
    var sampleCount = 1
    var clearColor = MTKClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    var clearDepth = 1.0
    var clearStencil: UInt32 = 0
    var preferredFramesPerSecond = 60
    var paused = false
    var enableSetNeedsDisplay = false
    var autoResizeDrawable = true
    var presentsWithTransaction = false
    /// The size the delegate was last told of.
    var reportedSize = CGSize(width: 0, height: 0)
    /// This frame's drawable and pass descriptor, made when first asked for.
    var drawable: NSObject?
    var passDescriptor: NSObject?
    /// The depth and stencil texture, and the size and format it was made for.
    var depthStencilTexture: NSObject?
    var depthStencilKey: (width: UInt, height: UInt, format: UInt) = (0, 0, 0)
    var running = false
}

@ObjCClass("MTKView")
open class MTKView: UIView {
    static let mtkStates = StateTable<MTKViewState>()
    var mtk: MTKViewState { MTKView.mtkStates[objcObject] }

    @ObjCClassMethod("layerClass") static func metalLayerClass() -> ObjCClass { ObjCClass(named: "CAMetalLayer") }

    var metalLayer: NSObject? { state.layer }

    @ObjCMethod("initWithFrame:device:")
    func initialize(frame: CGRect, device: NSObject?) -> NSObject {
        let view = initializeView(frame: frame).unsafeCast(to: MTKView.self)
        view.setDevice(device)
        return view
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        configure()
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        configure()
        return self
    }

    /// The layer's defaults, as MetalKit's: BGRA8, framebuffer only; then
    /// frames start.
    private func configure() {
        metalLayer?.mtkSetPixelFormat(MetalPixelFormats.bgra8Unorm)
        metalLayer?.mtkSetFramebufferOnly(true)
        updateFrames()
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        Frames.remove(MTKView.mtkStates[objcObject])
        MTKView.mtkStates.remove(objcObject)
        super.dealloc()
    }

    // MARK: Properties

    @ObjCMethod("delegate") func delegate() -> NSObject? { mtk.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { mtk.delegate = delegate?.objcObject }
    @ObjCMethod("device") func device() -> NSObject? { metalLayer?.mtkDevice() }
    @ObjCMethod("setDevice:") func setDevice(_ device: NSObject?) { metalLayer?.mtkSetDevice(device) }
    @ObjCMethod("preferredDevice") func preferredDevice() -> NSObject? { metalLayer?.mtkDevice() }
    @ObjCMethod("colorPixelFormat") func colorPixelFormat() -> UInt { metalLayer?.mtkPixelFormat() ?? 0 }
    @ObjCMethod("setColorPixelFormat:") func setColorPixelFormat(_ format: UInt) { metalLayer?.mtkSetPixelFormat(format) }
    @ObjCMethod("framebufferOnly") func framebufferOnly() -> Bool { metalLayer?.mtkFramebufferOnly() ?? true }
    @ObjCMethod("setFramebufferOnly:") func setFramebufferOnly(_ only: Bool) { metalLayer?.mtkSetFramebufferOnly(only) }
    @ObjCMethod("colorspace") func colorspace() -> UnsafeMutableRawPointer? { metalLayer?.mtkColorspace() }
    @ObjCMethod("setColorspace:") func setColorspace(_ space: UnsafeMutableRawPointer?) { metalLayer?.mtkSetColorspace(space) }
    @ObjCMethod("depthStencilPixelFormat") func depthStencilPixelFormat() -> UInt { mtk.depthStencilPixelFormat }
    @ObjCMethod("setDepthStencilPixelFormat:") func setDepthStencilPixelFormat(_ format: UInt) { mtk.depthStencilPixelFormat = format }
    @ObjCMethod("depthStencilStorageMode") func depthStencilStorageMode() -> UInt { mtk.depthStencilStorageMode }
    @ObjCMethod("setDepthStencilStorageMode:") func setDepthStencilStorageMode(_ mode: UInt) { mtk.depthStencilStorageMode = mode }
    @ObjCMethod("depthStencilAttachmentTextureUsage") func depthStencilAttachmentTextureUsage() -> UInt {
        mtk.depthStencilAttachmentTextureUsage
    }
    @ObjCMethod("setDepthStencilAttachmentTextureUsage:") func setDepthStencilAttachmentTextureUsage(_ usage: UInt) {
        mtk.depthStencilAttachmentTextureUsage = usage
    }
    @ObjCMethod("sampleCount") func sampleCount() -> Int { mtk.sampleCount }
    @ObjCMethod("setSampleCount:") func setSampleCount(_ count: Int) { mtk.sampleCount = max(count, 1) }
    @ObjCMethod("clearColor") func clearColor() -> MTKClearColor { mtk.clearColor }
    @ObjCMethod("setClearColor:") func setClearColor(_ color: MTKClearColor) { mtk.clearColor = color }
    @ObjCMethod("clearDepth") func clearDepth() -> Double { mtk.clearDepth }
    @ObjCMethod("setClearDepth:") func setClearDepth(_ depth: Double) { mtk.clearDepth = depth }
    @ObjCMethod("clearStencil") func clearStencil() -> UInt32 { mtk.clearStencil }
    @ObjCMethod("setClearStencil:") func setClearStencil(_ stencil: UInt32) { mtk.clearStencil = stencil }
    @ObjCMethod("presentsWithTransaction") func presentsWithTransaction() -> Bool { mtk.presentsWithTransaction }
    @ObjCMethod("setPresentsWithTransaction:") func setPresentsWithTransaction(_ presents: Bool) { mtk.presentsWithTransaction = presents }
    @ObjCMethod("autoResizeDrawable") func autoResizeDrawable() -> Bool { mtk.autoResizeDrawable }
    @ObjCMethod("setAutoResizeDrawable:") func setAutoResizeDrawable(_ resize: Bool) { mtk.autoResizeDrawable = resize }
    @ObjCMethod("preferredDrawableSize") func preferredDrawableSize() -> CGSize { boundsInPixels }
    @ObjCMethod("depthStencilTexture") func depthStencilTexture() -> NSObject? { mtk.depthStencilTexture }
    @ObjCMethod("multisampleColorTexture") func multisampleColorTexture() -> NSObject? { nil }

    @ObjCMethod("drawableSize") func drawableSize() -> CGSize { metalLayer?.mtkDrawableSize() ?? .zero }

    @ObjCMethod("setDrawableSize:")
    func setDrawableSize(_ size: CGSize) {
        metalLayer?.mtkSetDrawableSize(size)
        reportSize(size)
    }

    @ObjCMethod("preferredFramesPerSecond") func preferredFramesPerSecond() -> Int { mtk.preferredFramesPerSecond }
    @ObjCMethod("setPreferredFramesPerSecond:") func setPreferredFramesPerSecond(_ rate: Int) {
        mtk.preferredFramesPerSecond = rate
        if mtk.running {
            Frames.remove(mtk)
            mtk.running = false
        }
        updateFrames()
    }

    @ObjCMethod("isPaused") func isPaused() -> Bool { mtk.paused }
    @ObjCMethod("setPaused:") func setPaused(_ paused: Bool) { mtk.paused = paused; updateFrames() }
    @ObjCMethod("enableSetNeedsDisplay") func enableSetNeedsDisplay() -> Bool { mtk.enableSetNeedsDisplay }
    @ObjCMethod("setEnableSetNeedsDisplay:") func setEnableSetNeedsDisplay(_ enable: Bool) {
        mtk.enableSetNeedsDisplay = enable
        updateFrames()
    }

    // MARK: Frames

    /// Frames at the preferred rate (at most 60) while neither paused nor
    /// drawn on demand.
    private func updateFrames() {
        let timed = !mtk.paused && !mtk.enableSetNeedsDisplay
        guard timed != mtk.running else { return }
        mtk.running = timed
        guard timed else {
            Frames.remove(mtk)
            return
        }
        let object = objcObject
        Frames.add(mtk, framesPerSecond: min(max(mtk.preferredFramesPerSecond, 1), 60)) { _ in
            UIView.wrap(object).unsafeCast(to: MTKView.self).draw()
        }
    }

    var boundsInPixels: CGSize {
        let bounds = state.bounds, scale = state.geometry.contentsScale
        return CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
    }

    /// Tells the delegate of a new drawable size.
    private func reportSize(_ size: CGSize) {
        guard size != mtk.reportedSize else { return }
        mtk.reportedSize = size
        if let delegate = delegate(), delegate.responds(to: "mtkView:drawableSizeWillChange:") {
            delegate.sendMTKView(self, drawableSizeWillChange: size)
        }
    }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        super.layoutSubviews()
        resizeDrawable()
    }

    private func resizeDrawable() {
        guard mtk.autoResizeDrawable else { return }
        let size = boundsInPixels
        guard size.width >= 1, size.height >= 1 else { return }
        if metalLayer?.mtkDrawableSize() != size { metalLayer?.mtkSetDrawableSize(size) }
        reportSize(size)
    }

    /// Draws a frame now, through the delegate or -drawRect:, then lets go
    /// of the frame's drawable and pass descriptor.
    @ObjCMethod("draw")
    func draw() {
        resizeDrawable()
        if let delegate = delegate(), delegate.responds(to: "drawInMTKView:") {
            delegate.sendDrawInMTKView(self)
        } else {
            sendDraw(state.bounds)
        }
        mtk.drawable = nil
        mtk.passDescriptor = nil
    }

    @ObjCMethod("setNeedsDisplay")
    override func setNeedsDisplay() {
        guard mtk.enableSetNeedsDisplay else { return }
        let object = objcObject
        Updates.afterPass { UIView.wrap(object).unsafeCast(to: MTKView.self).draw() }
    }

    @ObjCMethod("releaseDrawables")
    func releaseDrawables() {
        mtk.drawable = nil
        mtk.passDescriptor = nil
        mtk.depthStencilTexture = nil
        mtk.depthStencilKey = (0, 0, 0)
    }

    // MARK: Drawables

    /// The layer's next drawable, the same one for the rest of the frame.
    @ObjCMethod("currentDrawable")
    func currentDrawable() -> NSObject? {
        if let drawable = mtk.drawable { return drawable }
        let drawable = metalLayer?.mtkNextDrawable()
        mtk.drawable = drawable
        return drawable
    }

    /// A pass that clears the current drawable's texture to the clear color
    /// and keeps it, with the depth and stencil texture cleared and not
    /// kept.
    @ObjCMethod("currentRenderPassDescriptor")
    func currentRenderPassDescriptor() -> NSObject? {
        if let descriptor = mtk.passDescriptor { return descriptor }
        guard let texture = currentDrawable()?.mtkTexture() else { return nil }
        let descriptor = NSObject(objCReturnValue: ObjCClass(named: "MTLRenderPassDescriptor").object.mtkRenderPassDescriptor())
        let color = descriptor.mtkColorAttachments().mtkObject(atIndexedSubscript: 0)
        color.mtkSetTexture(texture)
        color.mtkSetLoadAction(2)       // MTLLoadActionClear
        color.mtkSetStoreAction(1)      // MTLStoreActionStore
        color.mtkSetClearColor(mtk.clearColor)
        let format = mtk.depthStencilPixelFormat
        if format != 0, let depthStencil = depthStencilTexture(width: texture.mtkWidth(), height: texture.mtkHeight(), format: format) {
            if MetalPixelFormats.hasDepth(format) {
                let depth = descriptor.mtkDepthAttachment()
                depth.mtkSetTexture(depthStencil)
                depth.mtkSetLoadAction(2)
                depth.mtkSetStoreAction(0)  // MTLStoreActionDontCare
                depth.mtkSetClearDepth(mtk.clearDepth)
            }
            if MetalPixelFormats.hasStencil(format) {
                let stencil = descriptor.mtkStencilAttachment()
                stencil.mtkSetTexture(depthStencil)
                stencil.mtkSetLoadAction(2)
                stencil.mtkSetStoreAction(0)
                stencil.mtkSetClearStencil(mtk.clearStencil)
            }
        }
        mtk.passDescriptor = descriptor
        return descriptor
    }

    /// The depth and stencil texture, made again when the size or format
    /// changes.
    private func depthStencilTexture(width: UInt, height: UInt, format: UInt) -> NSObject? {
        if let texture = mtk.depthStencilTexture, mtk.depthStencilKey == (width, height, format) { return texture }
        guard let device = device() else { return nil }
        let descriptor = NSObject(objCReturnValue: ObjCClass(named: "MTLTextureDescriptor").object
            .mtkTexture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false))
        descriptor.mtkSetUsage(mtk.depthStencilAttachmentTextureUsage)
        descriptor.mtkSetStorageMode(mtk.depthStencilStorageMode)
        let texture = device.mtkNewTexture(descriptor: descriptor)
        mtk.depthStencilTexture = texture
        mtk.depthStencilKey = (width, height, format)
        return texture
    }
}

// MARK: - Messages

extension NSObject {
    @ObjCMethod("drawInMTKView:") func sendDrawInMTKView(_ view: MTKView)
    @ObjCMethod("mtkView:drawableSizeWillChange:") func sendMTKView(_ view: MTKView, drawableSizeWillChange size: CGSize)

    // CAMetalLayer.
    @ObjCMethod("device") func mtkDevice() -> NSObject?
    @ObjCMethod("setDevice:") func mtkSetDevice(_ device: NSObject?)
    @ObjCMethod("pixelFormat") func mtkPixelFormat() -> UInt
    @ObjCMethod("setPixelFormat:") func mtkSetPixelFormat(_ format: UInt)
    @ObjCMethod("framebufferOnly") func mtkFramebufferOnly() -> Bool
    @ObjCMethod("setFramebufferOnly:") func mtkSetFramebufferOnly(_ only: Bool)
    @ObjCMethod("colorspace") func mtkColorspace() -> UnsafeMutableRawPointer?
    @ObjCMethod("setColorspace:") func mtkSetColorspace(_ space: UnsafeMutableRawPointer?)
    @ObjCMethod("drawableSize") func mtkDrawableSize() -> CGSize
    @ObjCMethod("setDrawableSize:") func mtkSetDrawableSize(_ size: CGSize)
    @ObjCMethod("nextDrawable") func mtkNextDrawable() -> NSObject?

    // CAMetalDrawable and MTLTexture.
    @ObjCMethod("texture") func mtkTexture() -> NSObject?
    @ObjCMethod("width") func mtkWidth() -> UInt
    @ObjCMethod("height") func mtkHeight() -> UInt

    // Descriptors.
    @ObjCMethod("renderPassDescriptor") func mtkRenderPassDescriptor() -> UnsafeMutableRawPointer?
    @ObjCMethod("texture2DDescriptorWithPixelFormat:width:height:mipmapped:")
    func mtkTexture2DDescriptor(pixelFormat: UInt, width: UInt, height: UInt, mipmapped: Bool) -> UnsafeMutableRawPointer?
    @ObjCMethod("colorAttachments") func mtkColorAttachments() -> NSObject
    @ObjCMethod("objectAtIndexedSubscript:") func mtkObject(atIndexedSubscript index: UInt) -> NSObject
    @ObjCMethod("depthAttachment") func mtkDepthAttachment() -> NSObject
    @ObjCMethod("stencilAttachment") func mtkStencilAttachment() -> NSObject
    @ObjCMethod("setTexture:") func mtkSetTexture(_ texture: NSObject?)
    @ObjCMethod("setLoadAction:") func mtkSetLoadAction(_ action: UInt)
    @ObjCMethod("setStoreAction:") func mtkSetStoreAction(_ action: UInt)
    @ObjCMethod("setClearColor:") func mtkSetClearColor(_ color: MTKClearColor)
    @ObjCMethod("setClearDepth:") func mtkSetClearDepth(_ depth: Double)
    @ObjCMethod("setClearStencil:") func mtkSetClearStencil(_ stencil: UInt32)
    @ObjCMethod("setUsage:") func mtkSetUsage(_ usage: UInt)
    @ObjCMethod("setStorageMode:") func mtkSetStorageMode(_ mode: UInt)
    @ObjCMethod("newTextureWithDescriptor:") func mtkNewTexture(descriptor: NSObject) -> NSObject?
}
