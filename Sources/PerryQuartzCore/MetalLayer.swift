import CPerryGeometry
import Glibc
import PerryObjCInterop

// CAMetalLayer and its drawables. A drawable is a texture of the layer's
// device, made through Metal's own classes; presenting one, once the command
// buffer that rendered it completes, reads its pixels back (Metal's private
// -_perryReadRGBA:width:height:, RGBA rows bottom first) and shows them on
// the layer as a GL frame is shown. At most maximumDrawableCount drawables
// are out at once; -nextDrawable waits a second for one, as Core
// Animation's does. With displaySyncEnabled, as by default, it also hands
// out at most one a display refresh (60 a second, as UIScreen's
// maximumFramesPerSecond, or PERRY_METAL_FPS), as a drawable comes free
// only at a refresh on iOS: an app drawing in a loop is paced by it. Their textures are reused once presented, as Core
// Animation's are, so a drawable an app keeps holds no new memory.

@ObjCWrapper("MTLTextureDescriptor")
class MTLTextureDescriptor: NSObject {
    @ObjCClassMethod("texture2DDescriptorWithPixelFormat:width:height:mipmapped:")
    static func texture2D(pixelFormat: UInt, width: UInt, height: UInt, mipmapped: Bool) -> MTLTextureDescriptor
    @ObjCMethod("setUsage:") func setUsage(_ usage: UInt)
    @ObjCMethod("setStorageMode:") func setStorageMode(_ mode: UInt)
}

extension NSObject {
    @ObjCMethod("newTextureWithDescriptor:") func newTexture(descriptor: MTLTextureDescriptor) -> NSObject?
    @ObjCMethod("_perryReadPixels:width:height:")
    func readPixels(_ pixels: UnsafeMutableRawPointer?, width: UInt, height: UInt) -> Int
}

/// The drawables a layer has out, and the textures of those it has back.
final class DrawablePool: @unchecked Sendable {
    /// A texture's width, height, pixel format and usage.
    struct Key: Equatable {
        var width: UInt, height: UInt, format: UInt, usage: UInt
    }

    private var mutex = pthread_mutex_t()
    private var condition = pthread_cond_t()
    private(set) var out = 0
    private var textures: [(key: Key, texture: NSObject)] = []

    init() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&condition, nil)
    }

    /// Takes one, waiting up to `timeout` seconds while `limit` are out.
    func take(limit: Int, timeout: Double?) -> Bool {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        var deadline = timespec()
        clock_gettime(CLOCK_REALTIME, &deadline)
        let nanoseconds = Int(deadline.tv_nsec) + Int((timeout ?? 0) * 1e9)
        deadline.tv_sec += nanoseconds / 1_000_000_000
        deadline.tv_nsec = nanoseconds % 1_000_000_000
        while out >= limit {
            if timeout == nil {
                pthread_cond_wait(&condition, &mutex)
            } else if pthread_cond_timedwait(&condition, &mutex, &deadline) != 0 {
                return false
            }
        }
        out += 1
        return true
    }

    /// A texture given back, of the key; others go, as the size or format
    /// changed.
    func reuse(_ key: Key) -> NSObject? {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        textures.removeAll { $0.key != key }
        return textures.popLast()?.texture
    }

    func give(_ texture: NSObject?, key: Key, limit: Int) {
        pthread_mutex_lock(&mutex)
        if let texture, textures.count < limit { textures.append((key, texture)) }
        out = max(0, out - 1)
        pthread_cond_signal(&condition)
        pthread_mutex_unlock(&mutex)
    }
}

/// PERRY_METAL_TRACE: layers made, and drawables asked for and presented.
enum MetalTrace {
    nonisolated(unsafe) static let enabled = getenv("PERRY_METAL_TRACE") != nil
    nonisolated(unsafe) static var drawables = 0
    nonisolated(unsafe) static var presents = 0

    /// PERRY_METAL_DUMP=<path.ppm> writes the PERRY_METAL_DUMP_FRAME'th
    /// presented frame (300th by default) there, for checking what an app
    /// draws without a display.
    nonisolated(unsafe) static let dumpFrame: Int = getenv("PERRY_METAL_DUMP_FRAME").flatMap { Int(String(cString: $0)) } ?? 300

    /// Time spent reading drawables back and handing them to the layer, in
    /// nanoseconds, logged every 300 frames.
    nonisolated(unsafe) static var readTime: UInt64 = 0
    nonisolated(unsafe) static let framesPerSecond: Double = getenv("PERRY_METAL_FPS").flatMap { Double(String(cString: $0)) }.map { max($0, 1) } ?? 60
    nonisolated(unsafe) static var showTime: UInt64 = 0

    static func dump(_ pixels: UnsafeRawPointer, layout: Int, width: Int, height: Int, to path: String) {
        guard let file = fopen(path, "wb") else { return }
        defer { fclose(file) }
        let header = "P6\n\(width) \(height)\n255\n"
        _ = header.withCString { fwrite($0, 1, strlen($0), file) }
        var row = [UInt8](repeating: 0, count: width * 3)
        let bytes = pixels.assumingMemoryBound(to: UInt8.self)
        let (red, blue) = layout & 1 != 0 ? (2, 0) : (0, 2)
        // A PPM's rows are RGB, top first.
        for y in 0..<height {
            let line = layout & 2 != 0 ? y : height - 1 - y
            for x in 0..<width {
                let i = (line * width + x) * 4
                (row[x * 3], row[x * 3 + 1], row[x * 3 + 2]) = (bytes[i + red], bytes[i + 1], bytes[i + blue])
            }
            _ = row.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) }
        }
        log("wrote frame \(dumpFrame) to \(path)")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "perry: QuartzCore: \(message())\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}

final class MetalLayerState {
    var device: NSObject?
    /// MTLPixelFormatBGRA8Unorm.
    var pixelFormat: UInt = 80
    /// Set by the app; else the bounds in pixels.
    var drawableSize: CGSize?
    var framebufferOnly = true
    var maximumDrawableCount = 3
    var presentsWithTransaction = false
    var displaySyncEnabled = true
    var allowsNextDrawableTimeout = true
    var colorspace: UnsafeMutableRawPointer?
    var nextID = 0
    let pool = DrawablePool()
    /// When -nextDrawable last handed one out, on the monotonic clock.
    var lastDrawable: UInt64 = 0

    /// The buffer drawables are read back into, reused frame to frame.
    var readback: UnsafeMutableRawPointer?
    var readbackSize = 0

    deinit { readback?.deallocate() }

    func readbackBuffer(_ size: Int) -> UnsafeMutableRawPointer {
        if let readback, readbackSize == size { return readback }
        readback?.deallocate()
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(size, 4), alignment: 64)
        (readback, readbackSize) = (buffer, size)
        return buffer
    }
}

@ObjCClass("CAMetalLayer")
open class CAMetalLayer: CALayer {
    var metal = MetalLayerState()

    @ObjCMethod("init")
    public required init() {
        super.init()
        state.isOpaque = true
        MetalTrace.log("CAMetalLayer \(objcObject) made")
    }

    @ObjCMethod("initWithLayer:")
    public required init(layer: CALayer) { super.init(layer: layer) }

    @ObjCMethod("device") func device() -> NSObject? { metal.device }
    @ObjCMethod("setDevice:") func setDevice(_ device: NSObject?) { metal.device = device }
    @ObjCMethod("preferredDevice") func preferredDevice() -> NSObject? { metal.device }
    @ObjCMethod("pixelFormat") func pixelFormat() -> UInt { metal.pixelFormat }
    @ObjCMethod("setPixelFormat:") func setPixelFormat(_ format: UInt) { metal.pixelFormat = format }
    @ObjCMethod("framebufferOnly") func framebufferOnly() -> Bool { metal.framebufferOnly }
    @ObjCMethod("setFramebufferOnly:") func setFramebufferOnly(_ only: Bool) { metal.framebufferOnly = only }
    @ObjCMethod("maximumDrawableCount") func maximumDrawableCount() -> UInt { UInt(metal.maximumDrawableCount) }
    @ObjCMethod("setMaximumDrawableCount:") func setMaximumDrawableCount(_ count: UInt) {
        metal.maximumDrawableCount = max(2, min(3, Int(count)))
    }
    @ObjCMethod("presentsWithTransaction") func presentsWithTransaction() -> Bool { metal.presentsWithTransaction }
    @ObjCMethod("setPresentsWithTransaction:") func setPresentsWithTransaction(_ presents: Bool) { metal.presentsWithTransaction = presents }
    @ObjCMethod("displaySyncEnabled") func displaySyncEnabled() -> Bool { metal.displaySyncEnabled }
    @ObjCMethod("setDisplaySyncEnabled:") func setDisplaySyncEnabled(_ enabled: Bool) { metal.displaySyncEnabled = enabled }
    @ObjCMethod("allowsNextDrawableTimeout") func allowsNextDrawableTimeout() -> Bool { metal.allowsNextDrawableTimeout }
    @ObjCMethod("setAllowsNextDrawableTimeout:") func setAllowsNextDrawableTimeout(_ allows: Bool) { metal.allowsNextDrawableTimeout = allows }
    @ObjCMethod("colorspace") func colorspace() -> UnsafeMutableRawPointer? { metal.colorspace }
    @ObjCMethod("setColorspace:") func setColorspace(_ space: UnsafeMutableRawPointer?) { metal.colorspace = space }

    @ObjCMethod("drawableSize") func drawableSize() -> CGSize {
        if let size = metal.drawableSize { return size }
        let bounds = state.bounds
        return CGSize(width: (bounds.size.width * state.contentsScale).rounded(),
                      height: (bounds.size.height * state.contentsScale).rounded())
    }

    @ObjCMethod("setDrawableSize:") func setDrawableSize(_ size: CGSize) { metal.drawableSize = size }

    /// A drawable over a new texture of the drawable size, or nil when the
    /// layer has no device or size, or none comes free within a second.
    @ObjCMethod("nextDrawable") func nextDrawable() -> CAMetalDrawable? {
        let size = drawableSize()
        MetalTrace.drawables += 1
        if MetalTrace.drawables <= 3 || MetalTrace.drawables % 300 == 0 {
            MetalTrace.log("nextDrawable #\(MetalTrace.drawables) of \(objcObject): \(size.width)×\(size.height), format \(metal.pixelFormat), device \(metal.device == nil ? "none" : "set"), \(metal.pool.out) out")
        }
        guard let device = metal.device, size.width >= 1, size.height >= 1 else { return nil }
        if metal.displaySyncEnabled { waitForRefresh() }
        guard metal.pool.take(limit: metal.maximumDrawableCount, timeout: metal.allowsNextDrawableTimeout ? 1 : nil) else {
            return nil
        }
        // MTLTextureUsageShaderRead | RenderTarget, in shared storage so its
        // pixels can be read back.
        let key = DrawablePool.Key(width: UInt(size.width), height: UInt(size.height), format: metal.pixelFormat,
                                   usage: metal.framebufferOnly ? 0x4 : 0x5)
        var texture = metal.pool.reuse(key)
        if texture == nil {
            let descriptor = MTLTextureDescriptor.texture2D(pixelFormat: key.format, width: key.width,
                                                            height: key.height, mipmapped: false)
            descriptor.setUsage(key.usage)
            descriptor.setStorageMode(0)
            texture = device.newTexture(descriptor: descriptor)
        }
        guard let texture else {
            metal.pool.give(nil, key: key, limit: 0)
            return nil
        }
        metal.nextID += 1
        return CAMetalDrawable(texture: texture, key: key, layer: self, id: metal.nextID)
    }

    /// Waits, if need be, until a refresh after the last drawable handed out.
    private func waitForRefresh() {
        let interval = UInt64(1e9 / MetalTrace.framesPerSecond)
        let now = clock_gettime_nsec_np()
        let next = metal.lastDrawable + interval
        if metal.lastDrawable != 0, now < next {
            var until = timespec(tv_sec: Int(next / 1_000_000_000), tv_nsec: Int(next % 1_000_000_000))
            while clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &until, nil) == EINTR {}
            // A late frame does not make the next one early.
            metal.lastDrawable = next
        } else {
            metal.lastDrawable = now
        }
    }

    /// Shows pixels read from a presented drawable, as they are, as a GL
    /// frame is shown from the thread that presents it: not through the
    /// main queue, which an app may be waiting in.
    func show(_ pixels: UnsafeRawPointer, layout: Int, width: Int, height: Int) {
        setPixels(pixels, width: width, height: height, opaque: state.isOpaque, layout: layout)
    }
}

@ObjCProtocol("MTLDrawable")
protocol MTLDrawableProtocol {}

@ObjCProtocol("CAMetalDrawable")
protocol CAMetalDrawableProtocol: MTLDrawableProtocol {}

final class DrawableState {
    var texture: NSObject?
    var key = DrawablePool.Key(width: 0, height: 0, format: 0, usage: 0)
    var layer: CAMetalLayer?
    var id = 0
    var presented = false
    var returned = false
    var presentedTime: Double = 0
    var presentedHandlers: [ObjCBlock] = []
}

@ObjCClass("CAMetalDrawable")
open class CAMetalDrawable: NSObject, CAMetalDrawableProtocol {
    var drawable = DrawableState()

    init(texture: NSObject, key: DrawablePool.Key, layer: CAMetalLayer, id: Int) {
        super.init()
        drawable.texture = texture
        drawable.key = key
        drawable.layer = layer
        drawable.id = id
    }

    deinit { giveBack() }

    private func giveBack() {
        guard !drawable.returned else { return }
        drawable.returned = true
        guard let layer = drawable.layer else { return }
        layer.metal.pool.give(drawable.texture, key: drawable.key, limit: layer.metal.maximumDrawableCount)
    }

    @ObjCMethod("texture") func texture() -> NSObject? { drawable.texture }
    @ObjCMethod("layer") func layer() -> CAMetalLayer? { drawable.layer }
    @ObjCMethod("drawableID") func drawableID() -> UInt { UInt(drawable.id) }
    @ObjCMethod("presentedTime") func presentedTime() -> Double { drawable.presentedTime }

    @ObjCMethod("addPresentedHandler:") func addPresentedHandler(_ handler: ObjCBlock?) {
        if let handler { drawable.presentedHandlers.append(handler) }
    }

    /// Reads the texture and shows it, once; Metal sends this when the
    /// command buffer that presents it has completed.
    @ObjCMethod("present") func present() {
        guard !drawable.presented, let texture = drawable.texture, let layer = drawable.layer else { return }
        drawable.presented = true
        let size = layer.drawableSize()
        let width = Int(size.width), height = Int(size.height)
        // Presents come from one thread, metal2vulkan's, in order.
        let pixels = layer.metal.readbackBuffer(width * height * 4)
        let start = clock_gettime_nsec_np()
        let layout = texture.readPixels(pixels, width: UInt(width), height: UInt(height))
        let read = layout >= 0
        let readEnd = clock_gettime_nsec_np()
        if read { layer.show(pixels, layout: layout, width: width, height: height) }
        MetalTrace.readTime += readEnd - start
        MetalTrace.showTime += clock_gettime_nsec_np() - readEnd
        MetalTrace.presents += 1
        if read, MetalTrace.presents == MetalTrace.dumpFrame, let path = getenv("PERRY_METAL_DUMP") {
            MetalTrace.dump(pixels, layout: layout, width: width, height: height, to: String(cString: path))
        }
        if MetalTrace.presents <= 3 || MetalTrace.presents % 300 == 0 {
            let frames = Double(min(MetalTrace.presents, 300))
            MetalTrace.log("present #\(MetalTrace.presents): \(width)×\(height), read \(read); per frame, read back \(Double(MetalTrace.readTime) / frames / 1e6) ms, shown \(Double(MetalTrace.showTime) / frames / 1e6) ms")
            (MetalTrace.readTime, MetalTrace.showTime) = (0, 0)
        }
        drawable.presentedTime = Double(clock_gettime_nsec_np()) / 1e9
        giveBack()
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        for handler in drawable.presentedHandlers {
            handler.function(as: Invoke.self)(handler.object, objcObject)
        }
        drawable.presentedHandlers = []
    }

    @ObjCMethod("presentAtTime:") func present(atTime time: Double) { present() }
    @ObjCMethod("presentAfterMinimumDuration:") func present(afterMinimumDuration duration: Double) { present() }
}

/// The monotonic clock, in nanoseconds.
private func clock_gettime_nsec_np() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return UInt64(now.tv_sec) * 1_000_000_000 + UInt64(now.tv_nsec)
}
