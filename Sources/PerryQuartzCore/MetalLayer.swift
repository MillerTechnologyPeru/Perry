import CPerryGeometry
import Glibc
import PerryObjCInterop

// CAMetalLayer and its drawables. A drawable is a texture of the layer's
// device, made through Metal's own classes; presenting one, once the command
// buffer that rendered it completes, reads its pixels back (Metal's private
// -_perryReadRGBA:width:height:, RGBA rows bottom first) and shows them on
// the layer as a GL frame is shown. At most maximumDrawableCount drawables
// are out at once; -nextDrawable waits a second for one, as Core
// Animation's does. With displaySyncEnabled, as by default, a presented
// drawable comes free one display refresh after the one presented before
// it (60 a second, as UIScreen's maximumFramesPerSecond, or
// PERRY_METAL_FPS), as the display shows one a refresh on iOS: an app
// drawing in a loop is paced by it, and one drawing slower than the display
// never waits. Their textures are reused once free, as Core Animation's
// are, so a drawable an app keeps holds no new memory.
//
// Where metal2vulkan makes textures over dma-bufs (its ABI 11) and the
// compositor imports them, a layer's drawables are those textures instead,
// a slot each, and presenting one publishes its slot as a GL frame's shared
// buffer is published: no pixel passes through the CPU. A drawable never
// takes a slot the compositor holds (the one on screen, the newest), so a
// layer has two more than it gives out at once. Where either side can't,
// or with PERRY_METAL_SHARED=0, frames are read back as above.

@ObjCWrapper("MTLTextureDescriptor")
class MTLTextureDescriptor: NSObject {
    @ObjCClassMethod("texture2DDescriptorWithPixelFormat:width:height:mipmapped:")
    static func texture2D(pixelFormat: UInt, width: UInt, height: UInt, mipmapped: Bool) -> MTLTextureDescriptor
    @ObjCMethod("setUsage:") func setUsage(_ usage: UInt)
    @ObjCMethod("setStorageMode:") func setStorageMode(_ mode: UInt)
}

extension NSObject {
    @ObjCMethod("newTextureWithDescriptor:") func newTexture(descriptor: MTLTextureDescriptor) -> NSObject?
    @ObjCMethod("_perryNewDMABufTextureWithDescriptor:record:")
    func newDMABufTexture(descriptor: MTLTextureDescriptor, record: UnsafeMutablePointer<Int64>) -> NSObject?
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

    /// Presented drawables' textures, each with the time, on the monotonic
    /// clock, it comes free at: they count as out until then.
    private var shown: [(key: Key, texture: NSObject?, limit: Int, free: UInt64)] = []
    /// When the last presented drawable comes, or came, free.
    private var lastFree: UInt64 = 0

    /// Gives back the presented drawables whose time has come. With the
    /// mutex held.
    private func collect(_ now: UInt64) {
        guard !shown.isEmpty else { return }
        for entry in shown where entry.free <= now {
            if let texture = entry.texture, textures.count < entry.limit { textures.append((entry.key, texture)) }
            out = max(0, out - 1)
        }
        shown.removeAll { $0.free <= now }
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
        while true {
            let now = clock_gettime_nsec_np()
            collect(now)
            if out < limit { break }
            // Until a presented drawable comes free, one is given back, or
            // the time is up.
            var until = deadline
            if let soonest = shown.map(\.free).min() {
                var wake = timespec()
                clock_gettime(CLOCK_REALTIME, &wake)
                let total = Int(wake.tv_nsec) + Int(soonest - now)
                wake.tv_sec += total / 1_000_000_000
                wake.tv_nsec = total % 1_000_000_000
                if timeout == nil || wake.tv_sec < until.tv_sec || (wake.tv_sec == until.tv_sec && wake.tv_nsec < until.tv_nsec) {
                    until = wake
                }
            } else if timeout == nil {
                pthread_cond_wait(&condition, &mutex)
                continue
            }
            if pthread_cond_timedwait(&condition, &mutex, &until) != 0, timeout != nil {
                var current = timespec()
                clock_gettime(CLOCK_REALTIME, &current)
                if current.tv_sec > deadline.tv_sec || (current.tv_sec == deadline.tv_sec && current.tv_nsec >= deadline.tv_nsec) {
                    collect(clock_gettime_nsec_np())
                    if out < limit { break }
                    return false
                }
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

    /// A presented drawable's texture, which comes free as the display
    /// would let go of it: now, or `interval` nanoseconds after the one
    /// before it does, one a refresh. An app that draws without waiting is
    /// paced by that, a few frames ahead; one that draws slower than the
    /// display never waits.
    func givePresented(_ texture: NSObject?, key: Key, limit: Int, interval: UInt64) {
        pthread_mutex_lock(&mutex)
        let free = max(clock_gettime_nsec_np(), lastFree + interval)
        lastFree = free
        shown.append((key, texture, limit, free))
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

    /// Drawables over dma-bufs the compositor imports, when there are.
    let shared = SharedDrawables()

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
        guard metal.pool.take(limit: metal.maximumDrawableCount, timeout: metal.allowsNextDrawableTimeout ? 1 : nil) else {
            return nil
        }
        // MTLTextureUsageShaderRead | RenderTarget, in shared storage so its
        // pixels can be read back.
        let key = DrawablePool.Key(width: UInt(size.width), height: UInt(size.height), format: metal.pixelFormat,
                                   usage: metal.framebufferOnly ? 0x4 : 0x5)
        if let (texture, slot) = metal.shared.take(key, layer: self, device: device) {
            metal.nextID += 1
            return CAMetalDrawable(texture: texture, key: key, layer: self, id: metal.nextID, slot: slot)
        }
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
    /// The shared buffer the texture is, or nil for a texture read back.
    var slot: Int?
}

@ObjCClass("CAMetalDrawable")
open class CAMetalDrawable: NSObject, CAMetalDrawableProtocol {
    var drawable = DrawableState()

    init(texture: NSObject, key: DrawablePool.Key, layer: CAMetalLayer, id: Int, slot: Int? = nil) {
        super.init()
        drawable.texture = texture
        drawable.key = key
        drawable.layer = layer
        drawable.id = id
        drawable.slot = slot
    }

    deinit { giveBack() }

    /// Back to the layer's pool: at once when it was never shown, and as
    /// the display lets go of it when it was presented.
    private func giveBack(presented: Bool = false) {
        guard !drawable.returned else { return }
        drawable.returned = true
        guard let layer = drawable.layer else { return }
        // A shared drawable's texture is its slot's, not the pool's.
        let texture = drawable.slot == nil ? drawable.texture : nil
        if let slot = drawable.slot { layer.metal.shared.giveBack(slot) }
        if presented, layer.metal.displaySyncEnabled {
            layer.metal.pool.givePresented(texture, key: drawable.key, limit: layer.metal.maximumDrawableCount,
                                           interval: UInt64(1e9 / MetalTrace.framesPerSecond))
        } else {
            layer.metal.pool.give(texture, key: drawable.key, limit: layer.metal.maximumDrawableCount)
        }
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
        if let slot = drawable.slot {
            // The command buffer that rendered it has completed: no fence.
            layer.metal.shared.publish(slot, key: drawable.key, layer: layer)
            MetalTrace.presents += 1
            if MetalTrace.presents <= 3 || MetalTrace.presents % 300 == 0 {
                MetalTrace.log("present #\(MetalTrace.presents): \(drawable.key.width)×\(drawable.key.height), shared slot \(slot)")
            }
            finishPresent()
            return
        }
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
        finishPresent()
    }

    /// The presented time, the drawable back to its layer, and the
    /// presented handlers called.
    private func finishPresent() {
        drawable.presentedTime = Double(clock_gettime_nsec_np()) / 1e9
        giveBack(presented: true)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        for handler in drawable.presentedHandlers {
            handler.function(as: Invoke.self)(handler.object, objcObject)
        }
        drawable.presentedHandlers = []
    }

    @ObjCMethod("presentAtTime:") func present(atTime time: Double) { present() }
    @ObjCMethod("presentAfterMinimumDuration:") func present(afterMinimumDuration duration: Double) { present() }
}

/// A layer's drawables over dma-bufs, a slot each, for one size and
/// format at a time. Taken on the threads apps ask for drawables on, and
/// published on metal2vulkan's, which presents them.
final class SharedDrawables: @unchecked Sendable {
    /// PERRY_METAL_SHARED=0 reads every drawable back.
    nonisolated(unsafe) static let wanted = getenv("PERRY_METAL_SHARED").map { String(cString: $0) != "0" } ?? true

    private var mutex = pthread_mutex_t()
    /// The key the slots' textures are of, and the textures.
    private var key: DrawablePool.Key?
    private var textures: [NSObject] = []
    /// Slots of drawables out, not yet presented or given back.
    private var out: Set<Int> = []
    /// Sharing failed for good: no dma-buf textures, or the compositor
    /// couldn't import them.
    private var failed = !SharedDrawables.wanted

    init() { pthread_mutex_init(&mutex, nil) }

    /// A drawable's texture and slot, or nil to read this one back.
    func take(_ key: DrawablePool.Key, layer: CAMetalLayer, device: NSObject) -> (NSObject, Int)? {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        guard !failed else { return nil }
        if self.key != key, !make(key, count: layer.metal.maximumDrawableCount + 2, layer: layer, device: device) {
            return nil
        }
        // Up to a second for a slot the compositor lets go of, as it shows
        // the next frame; there is one at once unless it's behind.
        for _ in 0..<500 {
            let held = layer.sharedSlotsInUse()
            if held < 0 {
                MetalTrace.log("the compositor can't import Metal's dma-bufs: reading drawables back")
                stop(layer)
                return nil
            }
            if let slot = textures.indices.first(where: { held & (1 << $0) == 0 && !out.contains($0) }) {
                out.insert(slot)
                return (textures[slot], slot)
            }
            pthread_mutex_unlock(&mutex)
            usleep(2000)
            pthread_mutex_lock(&mutex)
            if failed || self.key != key { return nil }
        }
        return nil
    }

    /// Makes `count` textures of `key` over dma-bufs and gives them to the
    /// layer's compositor; false, with sharing stopped, where it can't.
    /// With the mutex held.
    private func make(_ key: DrawablePool.Key, count: Int, layer: CAMetalLayer, device: NSObject) -> Bool {
        let descriptor = MTLTextureDescriptor.texture2D(pixelFormat: key.format, width: key.width, height: key.height,
                                                        mipmapped: false)
        descriptor.setUsage(key.usage)
        // MTLStorageModePrivate: only the GPU and the compositor touch them.
        descriptor.setStorageMode(2)
        var made: [NSObject] = []
        var records = [Int64](repeating: 0, count: 7 * count)
        for slot in 0..<count {
            let texture = records.withUnsafeMutableBufferPointer {
                device.newDMABufTexture(descriptor: descriptor, record: $0.baseAddress! + 7 * slot)
            }
            guard let texture else { break }
            made.append(texture)
        }
        defer { for slot in 0..<made.count { close(Int32(records[7 * slot])) } }
        guard made.count == count else {
            MetalTrace.log("no dma-buf textures of \(key.width)×\(key.height) format \(key.format): reading drawables back")
            stop(layer)
            return false
        }
        // The layer's surface duplicates the fds, which are closed above.
        records.withUnsafeBytes { layer.setSharedBuffers($0.baseAddress, count: count, topFirst: true) }
        (self.key, textures, out) = (key, made, [])
        MetalTrace.log("\(count) drawables of \(key.width)×\(key.height) shared with the compositor")
        return true
    }

    /// Back to reading drawables back, for good. With the mutex held.
    private func stop(_ layer: CAMetalLayer) {
        failed = true
        if key != nil { layer.setSharedBuffers(nil, count: 0, topFirst: true) }
        (key, textures, out) = (nil, [], [])
    }

    /// Shows the slot's frame, presented once its command buffer completed.
    func publish(_ slot: Int, key: DrawablePool.Key, layer: CAMetalLayer) {
        pthread_mutex_lock(&mutex)
        let current = !failed && self.key == key
        pthread_mutex_unlock(&mutex)
        if current { layer.publishSharedSlot(slot, opaque: layer.state.isOpaque, fence: -1) }
    }

    /// A drawable presented or given back: its slot is the compositor's to
    /// hold, or free.
    func giveBack(_ slot: Int) {
        pthread_mutex_lock(&mutex)
        out.remove(slot)
        pthread_mutex_unlock(&mutex)
    }
}

/// The monotonic clock, in nanoseconds.
private func clock_gettime_nsec_np() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return UInt64(now.tv_sec) * 1_000_000_000 + UInt64(now.tv_nsec)
}
