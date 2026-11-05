import CPerryGeometry
import Glibc
import PerryObjCInterop

// GL frames shared with the compositor as GPU buffers, without passing
// through the CPU. UIKit copies each presented frame, on the GPU, into one
// of a few textures it has exported as dma-bufs; the compositor imports
// each once, as an EGL image bound to an SDL texture's GL texture, and
// draws the newest finished one. Each frame comes with a fence the GPU
// signals when the copy is done; until then the compositor shows the frame
// before it. The app never draws into a buffer in use: the one on screen,
// the newest finished, or the one still being copied into.

/// A layer's shared buffers and which holds the newest frame. UIKit
/// publishes from the thread the app presents on; the compositor reads on
/// the main thread.
final class SharedFrames: @unchecked Sendable {
    struct Buffer {
        /// The dma-buf, owned here.
        var fd: Int32
        var width, height, stride, offset: Int32
        /// The DRM format and modifier it was exported with.
        var fourcc: UInt32
        var modifier: UInt64
    }

    /// DRM_FORMAT_MOD_INVALID: exported without a modifier.
    static let noModifier: UInt64 = 0x00ff_ffff_ffff_ffff

    let buffers: [Buffer]
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    /// The newest finished frame's buffer, and the one on screen.
    private var latest = -1
    private var showing = -1
    /// A frame the GPU is still copying, and the fence it signals when
    /// done (owned here).
    private var pending: (slot: Int, fence: Int32)?
    private var published = 0
    private var failed = false
    private(set) var opaque = false

    /// Takes `count` records of seven 64-bit values (fd, width, height,
    /// stride, offset, fourcc, modifier), duplicating each fd.
    init(records: UnsafeRawPointer, count: Int) {
        let values = records.assumingMemoryBound(to: Int64.self)
        buffers = (0..<count).map { index in
            let v = values + index * 7
            return Buffer(fd: dup(Int32(v[0])), width: Int32(v[1]), height: Int32(v[2]), stride: Int32(v[3]), offset: Int32(v[4]),
                          fourcc: UInt32(truncatingIfNeeded: v[5]), modifier: UInt64(bitPattern: v[6]))
        }
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        if let pending { close(pending.fence) }
        for buffer in buffers where buffer.fd >= 0 { close(buffer.fd) }
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    /// The app's: the buffer at `slot` is getting a new frame, finished
    /// when `fence` (a sync file, taken over here) signals, or already if
    /// there is none. A frame still being copied is passed over for it.
    func publish(_ slot: Int, opaque: Bool, fence: Int32) {
        locked {
            if let old = pending { close(old.fence) }
            pending = nil
            if fence >= 0 { pending = (slot, fence) } else { latest = slot }
            published += 1
            self.opaque = opaque
        }
    }

    /// The app's: the buffers it must not draw into, as a mask of their
    /// indexes; -1 once the compositor could not import the buffers.
    var slotsInUse: Int {
        locked {
            guard !failed else { return -1 }
            var mask = 0
            for slot in [latest, showing, pending?.slot ?? -1] where slot >= 0 { mask |= 1 << slot }
            return mask
        }
    }

    /// The compositor's: the newest finished frame's buffer, now the one
    /// on screen; how many frames were published since the last; and
    /// whether a newer frame is still being copied. Waits a few
    /// milliseconds for one that nearly is. Nil before any frame.
    func take() -> (slot: Int, frames: Int, waiting: Bool)? {
        // The fence is polled on a duplicate, as the app may pass the
        // frame over, closing it, meanwhile.
        if let (slot, fence) = locked({ pending.map { ($0.slot, dup($0.fence)) } }), fence >= 0 {
            var file = pollfd(fd: fence, events: Int16(POLLIN), revents: 0)
            let finished = poll(&file, 1, 3) > 0
            close(fence)
            if finished {
                locked {
                    guard let current = pending, current.slot == slot else { return }
                    latest = slot
                    close(current.fence)
                    pending = nil
                }
            }
        }
        return locked {
            guard !failed, latest >= 0 else { return nil }
            showing = latest
            let frames = published
            published = 0
            return (latest, frames, pending != nil)
        }
    }

    /// The compositor's: the buffers can't be imported; the app reads
    /// frames back instead.
    func fail() { locked { failed = true } }

    var hasFailed: Bool { locked { failed } }
}

/// EGL and OpenGL ES, as the compositor imports shared buffers with:
/// bound from the host's libraries, in SDL's context.
enum SharedGL {
    typealias Pointer = UnsafeMutableRawPointer

    nonisolated(unsafe) private static var loaded: Bool?
    nonisolated(unsafe) static var getCurrentDisplay: (@convention(c) () -> Pointer?)!
    nonisolated(unsafe) static var createImage: (@convention(c) (Pointer?, Pointer?, UInt32, Pointer?, UnsafePointer<Int32>?) -> Pointer?)!
    nonisolated(unsafe) static var destroyImage: (@convention(c) (Pointer?, Pointer?) -> UInt32)!
    nonisolated(unsafe) static var getIntegerv: (@convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void)!
    nonisolated(unsafe) static var bindTexture: (@convention(c) (UInt32, UInt32) -> Void)!
    nonisolated(unsafe) static var imageTargetTexture: (@convention(c) (UInt32, Pointer?) -> Void)!
    nonisolated(unsafe) static var getError: (@convention(c) () -> UInt32)!
    nonisolated(unsafe) static var textureProperties: (@convention(c) (Pointer?) -> UInt32)!
    nonisolated(unsafe) static var numberProperty: (@convention(c) (UInt32, UnsafePointer<CChar>, Int64) -> Int64)!

    /// Binds the functions once; false where the host lacks any.
    static func load() -> Bool {
        if let loaded { return loaded }
        var complete = true
        func bind<T>(_ library: Pointer?, _ name: String, _ fallback: ((UnsafePointer<CChar>) -> Pointer?)? = nil) -> T? {
            guard let symbol = library.flatMap({ dlsym($0, name) }) ?? fallback?(name) else {
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        let egl = dlopen("libEGL.so.1", RTLD_NOW), gles = dlopen("libGLESv2.so.2", RTLD_NOW), sdl = dlopen("libSDL3.so.0", RTLD_NOW)
        let procAddress: (@convention(c) (UnsafePointer<CChar>) -> Pointer?)? = bind(egl, "eglGetProcAddress")
        let extension_: (UnsafePointer<CChar>) -> Pointer? = { procAddress?($0) }
        getCurrentDisplay = bind(egl, "eglGetCurrentDisplay")
        createImage = bind(egl, "eglCreateImageKHR", extension_)
        destroyImage = bind(egl, "eglDestroyImageKHR", extension_)
        getIntegerv = bind(gles, "glGetIntegerv")
        bindTexture = bind(gles, "glBindTexture")
        imageTargetTexture = bind(gles, "glEGLImageTargetTexture2DOES", extension_)
        getError = bind(gles, "glGetError")
        textureProperties = bind(sdl, "SDL_GetTextureProperties")
        numberProperty = bind(sdl, "SDL_GetNumberProperty")
        loaded = complete
        return complete
    }
}

extension Compositor {
    /// One layer's imported buffers: an SDL texture for each, whose GL
    /// texture is the buffer's EGL image.
    final class SharedTextures {
        let frames: SharedFrames
        var textures: [SDL.Pointer?]
        var images: [UnsafeMutableRawPointer?]
        let display: UnsafeMutableRawPointer?
        var used = true

        init(frames: SharedFrames, display: UnsafeMutableRawPointer?) {
            self.frames = frames
            self.display = display
            textures = Array(repeating: nil, count: frames.buffers.count)
            images = Array(repeating: nil, count: frames.buffers.count)
        }

        func destroy() {
            for texture in textures where texture != nil { SDL.destroyTexture(texture) }
            for image in images where image != nil { _ = SharedGL.destroyImage(display, image) }
            textures = []
            images = []
        }
    }

    /// The buffer imported: an EGL image of the dma-buf, bound to the GL
    /// texture of a new SDL texture, in SDL's context, whose bindings are
    /// left as they were. Nil if the host can't.
    private func importBuffer(_ buffer: SharedFrames.Buffer, display: UnsafeMutableRawPointer?) -> (SDL.Pointer, UnsafeMutableRawPointer)? {
        guard buffer.fd >= 0 else { return nil }
        // EGL_WIDTH, EGL_HEIGHT, EGL_LINUX_DRM_FOURCC_EXT, plane 0's fd,
        // offset and pitch, and its modifier when it has one.
        var attributes: [Int32] = [0x3057, buffer.width, 0x3056, buffer.height, 0x3271, Int32(bitPattern: buffer.fourcc),
                                   0x3272, buffer.fd, 0x3273, buffer.offset, 0x3274, buffer.stride]
        if buffer.modifier != SharedFrames.noModifier {
            attributes += [0x3443, Int32(truncatingIfNeeded: buffer.modifier), 0x3444, Int32(truncatingIfNeeded: buffer.modifier >> 32)]
        }
        attributes.append(0x3038)       // EGL_NONE
        // EGL_LINUX_DMA_BUF_EXT, with no context and no client buffer.
        guard let image = SharedGL.createImage(display, nil, 0x3270, nil, attributes) else { return nil }
        // SDL_TEXTUREACCESS_STATIC: SDL never writes to it.
        guard let texture = SDL.createTexture(renderer, SDL.pixelFormatABGR8888, 0, buffer.width, buffer.height) else {
            _ = SharedGL.destroyImage(display, image)
            return nil
        }
        _ = SDL.setTextureScaleMode(texture, 1)
        let name = SharedGL.numberProperty(SharedGL.textureProperties(texture), "SDL.texture.opengles2.texture", 0)
        guard name != 0 else {
            SDL.destroyTexture(texture)
            _ = SharedGL.destroyImage(display, image)
            return nil
        }
        var previous: Int32 = 0
        SharedGL.getIntegerv(0x8069, &previous)             // GL_TEXTURE_BINDING_2D
        while SharedGL.getError() != 0 {}
        SharedGL.bindTexture(0x0DE1, UInt32(name))
        SharedGL.imageTargetTexture(0x0DE1, image)
        let error = SharedGL.getError()
        SharedGL.bindTexture(0x0DE1, UInt32(previous))
        guard error == 0 else {
            SDL.destroyTexture(texture)
            _ = SharedGL.destroyImage(display, image)
            return nil
        }
        return (texture, image)
    }

    /// The layer's newest shared frame, drawn flipped upright, as GL's
    /// rows are bottom first; false when its buffers can't be imported,
    /// after which the app reads its frames back.
    func drawShared(_ frames: SharedFrames, of layer: CALayer, state: LayerState, toScreen: CGAffineTransform, alpha: CGFloat) -> Bool {
        guard SharedGL.load() else {
            frames.fail()
            return false
        }
        let key = layer.objcObject
        var entry = sharedTextures[key]
        if let current = entry, current.frames !== frames {
            current.destroy()
            entry = nil
        }
        let imported = entry ?? SharedTextures(frames: frames, display: SharedGL.getCurrentDisplay())
        sharedTextures[key] = imported
        imported.used = true
        guard let (slot, count, waiting) = frames.take(), slot < imported.textures.count else {
            // The first frame is still being copied: look again next pass.
            Compositing.changed()
            return true
        }
        FrameRate.glFrames += count
        if waiting { Compositing.changed() }
        if imported.textures[slot] == nil {
            guard let (texture, image) = importBuffer(frames.buffers[slot], display: imported.display) else {
                frames.fail()
                imported.destroy()
                sharedTextures[key] = nil
                let line = "perry: QuartzCore: GL frames can't be shared with the compositor (\(SDL.lastError)); reading them back\n"
                line.withCString { _ = write(2, $0, strlen($0)) }
                return false
            }
            imported.textures[slot] = texture
            imported.images[slot] = image
        }
        guard let texture = imported.textures[slot] else { return true }
        _ = SDL.setTextureBlendMode(texture, frames.opaque && alpha >= 1 ? SDL.blendNone : SDL.blendPremultiplied)
        let level = Float(alpha)
        _ = SDL.setTextureAlphaMod(texture, level)
        _ = SDL.setTextureColorMod(texture, level, level, level)
        var target = pixels(toScreen.apply(state.bounds))
        // SDL_FLIP_VERTICAL.
        _ = SDL.renderTextureRotated(renderer, texture, nil, &target, 0, nil, 2)
        return true
    }
}
