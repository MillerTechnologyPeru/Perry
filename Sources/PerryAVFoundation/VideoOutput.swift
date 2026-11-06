import CPerryMedia
import Glibc
import PerryObjCInterop

// AVPlayerItemVideoOutput and CoreVideo: a player item's frames as pixel
// buffers, for a program that draws the video itself, as an engine does to
// put a movie on a texture. The output takes the newest frame GStreamer
// has decoded when the program asks whether there is one; the frame is
// copied into a pixel buffer, 32-bit BGRA, top row first, whatever
// attributes were asked for.
//
// A pixel buffer is made into an OpenGL ES texture through a texture
// cache, as on iOS, where the texture shares the buffer's memory: here the
// pixels are uploaded to a new texture, in the context current on the
// calling thread, each time one is made. There are no Metal textures.

// MARK: - Pixel buffers

final class PixelBufferState {
    var width = 0
    var height = 0
    var format: UInt32 = PixelBuffer.bgra
    var bytes: UnsafeMutableRawPointer?
    var count = 0

    deinit {
        if let bytes { PixelBuffer.recycle(bytes, count: count) }
    }
}

/// A CVPixelBuffer: an object, as it is retained and released as any
/// CoreFoundation one.
@ObjCClass("__PerryCVPixelBuffer")
open class PixelBuffer: NSObject {
    static let states = StateTable<PixelBufferState>()
    /// kCVPixelFormatType_32BGRA.
    static let bgra: UInt32 = 0x4247_5241

    // A movie's frames are all one size and come and go many times a
    // second: their memory is kept to be used again.
    nonisolated(unsafe) private static var spare: [(bytes: UnsafeMutableRawPointer, count: Int)] = []
    private static let spareLock = Lock()

    static func recycle(_ bytes: UnsafeMutableRawPointer, count: Int) {
        let kept = spareLock.withLock { () -> Bool in
            guard spare.count < 4 else { return false }
            spare.append((bytes, count))
            return true
        }
        if !kept { free(bytes) }
    }

    private static func memory(count: Int) -> UnsafeMutableRawPointer? {
        let reused = spareLock.withLock { () -> UnsafeMutableRawPointer? in
            guard let index = spare.firstIndex(where: { $0.count == count }) else {
                // Another size of frame now: the old ones' memory goes.
                for other in spare { free(other.bytes) }
                spare.removeAll()
                return nil
            }
            return spare.remove(at: index).bytes
        }
        return reused ?? malloc(max(count, 1))
    }

    /// A buffer of four bytes a pixel; nil when there is no memory for it.
    static func make(width: Int, height: Int, format: UInt32) -> PixelBuffer? {
        guard width > 0, height > 0, let bytes = memory(count: width * height * 4) else { return nil }
        let buffer = NSObject(objCClass.pointer).newInstance().unsafeCast(to: PixelBuffer.self)
        let state = PixelBufferState()
        (state.width, state.height, state.format, state.bytes, state.count) = (width, height, format, bytes, width * height * 4)
        states.set(buffer.objcObject, state)
        return buffer
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        PixelBuffer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PixelBuffer.objCClass.pointer)
    }
}

private let cvSuccess: Int32 = 0, cvError: Int32 = -6660, cvInvalidArgument: Int32 = -6661, cvAllocationFailed: Int32 = -6662

@c(_CVPixelBufferCreate)
public func CVPixelBufferCreate(_ allocator: UnsafeRawPointer?, _ width: Int, _ height: Int, _ format: UInt32, _ attributes: UnsafeRawPointer?,
                                _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return cvInvalidArgument }
    out.pointee = nil
    guard let buffer = PixelBuffer.make(width: width, height: height, format: format) else { return cvAllocationFailed }
    _ = ObjCRuntime.retain(buffer.objcObject)
    out.pointee = buffer.objcObject
    return cvSuccess
}

@c(_CVPixelBufferGetWidth) public func CVPixelBufferGetWidth(_ buffer: UnsafeMutableRawPointer?) -> Int { PixelBuffer.states[buffer]?.width ?? 0 }
@c(_CVPixelBufferGetHeight) public func CVPixelBufferGetHeight(_ buffer: UnsafeMutableRawPointer?) -> Int { PixelBuffer.states[buffer]?.height ?? 0 }
@c(_CVPixelBufferGetBytesPerRow) public func CVPixelBufferGetBytesPerRow(_ buffer: UnsafeMutableRawPointer?) -> Int {
    (PixelBuffer.states[buffer]?.width ?? 0) * 4
}
@c(_CVPixelBufferGetDataSize) public func CVPixelBufferGetDataSize(_ buffer: UnsafeMutableRawPointer?) -> Int { PixelBuffer.states[buffer]?.count ?? 0 }
@c(_CVPixelBufferGetPixelFormatType) public func CVPixelBufferGetPixelFormatType(_ buffer: UnsafeMutableRawPointer?) -> UInt32 {
    PixelBuffer.states[buffer]?.format ?? 0
}
@c(_CVPixelBufferGetBaseAddress) public func CVPixelBufferGetBaseAddress(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    PixelBuffer.states[buffer]?.bytes
}
@c(_CVPixelBufferIsPlanar) public func CVPixelBufferIsPlanar(_ buffer: UnsafeMutableRawPointer?) -> UInt8 { 0 }
@c(_CVPixelBufferGetPlaneCount) public func CVPixelBufferGetPlaneCount(_ buffer: UnsafeMutableRawPointer?) -> Int { 0 }
/// The memory is the buffer's own, there whether locked or not.
@c(_CVPixelBufferLockBaseAddress) public func CVPixelBufferLockBaseAddress(_ buffer: UnsafeMutableRawPointer?, _ flags: UInt64) -> Int32 {
    PixelBuffer.states[buffer] == nil ? cvInvalidArgument : cvSuccess
}
@c(_CVPixelBufferUnlockBaseAddress) public func CVPixelBufferUnlockBaseAddress(_ buffer: UnsafeMutableRawPointer?, _ flags: UInt64) -> Int32 {
    PixelBuffer.states[buffer] == nil ? cvInvalidArgument : cvSuccess
}
@c(_CVPixelBufferGetIOSurface) public func CVPixelBufferGetIOSurface(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_CVPixelBufferRetain) public func CVPixelBufferRetain(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    if let buffer { _ = ObjCRuntime.retain(buffer) }
    return buffer
}
@c(_CVPixelBufferRelease) public func CVPixelBufferRelease(_ buffer: UnsafeMutableRawPointer?) {
    if let buffer { ObjCRuntime.release(buffer) }
}
@c(_CVBufferRetain) public func CVBufferRetain(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { CVPixelBufferRetain(buffer) }
@c(_CVBufferRelease) public func CVBufferRelease(_ buffer: UnsafeMutableRawPointer?) { CVPixelBufferRelease(buffer) }

@ObjCConstants
enum CoreVideoConstants {
    static let kCVPixelBufferPixelFormatTypeKey = "PixelFormatType"
    static let kCVPixelBufferWidthKey = "Width"
    static let kCVPixelBufferHeightKey = "Height"
    static let kCVPixelBufferBytesPerRowAlignmentKey = "BytesPerRowAlignment"
    static let kCVPixelBufferIOSurfacePropertiesKey = "IOSurfaceProperties"
    static let kCVPixelBufferOpenGLESCompatibilityKey = "OpenGLESCompatibility"
    static let kCVPixelBufferOpenGLCompatibilityKey = "OpenGLCompatibility"
    static let kCVPixelBufferMetalCompatibilityKey = "MetalCompatibility"
    static let kCVPixelBufferCGImageCompatibilityKey = "CGImageCompatibility"
    static let kCVPixelBufferCGBitmapContextCompatibilityKey = "CGBitmapContextCompatibility"
}

// MARK: - OpenGL ES textures

/// The program's own OpenGL ES functions, found when a texture is first
/// made: UIKit's provider has them, entered as the program enters them, so
/// the calling thread has its context.
enum VideoGL {
    typealias Lookup = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    typealias Names = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    typealias Bind = @convention(c) (UInt32, UInt32) -> Void
    typealias Parameter = @convention(c) (UInt32, UInt32, Int32) -> Void
    typealias Image = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
    typealias GetInteger = @convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void

    nonisolated(unsafe) static var lookup: Lookup?
    nonisolated(unsafe) static var genTextures: Names?
    nonisolated(unsafe) static var deleteTextures: Names?
    nonisolated(unsafe) static var bindTexture: Bind?
    nonisolated(unsafe) static var texParameteri: Parameter?
    nonisolated(unsafe) static var texImage2D: Image?
    nonisolated(unsafe) static var getIntegerv: GetInteger?
    nonisolated(unsafe) private static var loaded = false
    private static let lock = Lock()

    static func load() -> Bool {
        lock.withLock {
            if !loaded, let lookup {
                loaded = true
                func find<T>(_ name: String, _: T.Type) -> T? {
                    "/System/Library/Frameworks/OpenGLES.framework/OpenGLES".withCString { library in
                        name.withCString { lookup(library, $0) }
                    }.map { unsafeBitCast($0, to: T.self) }
                }
                genTextures = find("_glGenTextures", Names.self)
                deleteTextures = find("_glDeleteTextures", Names.self)
                bindTexture = find("_glBindTexture", Bind.self)
                texParameteri = find("_glTexParameteri", Parameter.self)
                texImage2D = find("_glTexImage2D", Image.self)
                getIntegerv = find("_glGetIntegerv", GetInteger.self)
            }
            return genTextures != nil && deleteTextures != nil && bindTexture != nil && texParameteri != nil && texImage2D != nil
                && getIntegerv != nil
        }
    }
}

final class TextureState {
    var name: UInt32 = 0
    var target: UInt32 = 0x0DE1

    /// The texture goes with the last reference to it, which a program
    /// drops on the thread it draws from.
    deinit {
        guard name != 0, let delete = VideoGL.deleteTextures else { return }
        var name = name
        delete(1, &name)
    }
}

@ObjCClass("__PerryCVOpenGLESTexture")
open class VideoTexture: NSObject {
    static let states = StateTable<TextureState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        VideoTexture.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: VideoTexture.objCClass.pointer)
    }
}

/// A texture cache keeps nothing: each texture is made new.
@ObjCClass("__PerryCVOpenGLESTextureCache")
open class VideoTextureCache: NSObject {
}

@c(_CVOpenGLESTextureCacheCreate)
public func CVOpenGLESTextureCacheCreate(_ allocator: UnsafeRawPointer?, _ cacheAttributes: UnsafeRawPointer?, _ context: UnsafeRawPointer?,
                                         _ textureAttributes: UnsafeRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return cvInvalidArgument }
    out.pointee = nil
    guard VideoGL.load() else { return cvError }
    let cache = NSObject(VideoTextureCache.objCClass.pointer).newInstance()
    _ = ObjCRuntime.retain(cache.objcObject)
    out.pointee = cache.objcObject
    return cvSuccess
}

@c(_CVOpenGLESTextureCacheFlush) public func CVOpenGLESTextureCacheFlush(_ cache: UnsafeMutableRawPointer?, _ options: UInt64) {}

/// The buffer's pixels on a new texture, in the format and type asked for
/// (BGRA bytes, for a BGRA buffer). The texture bound before stays bound.
@c(_CVOpenGLESTextureCacheCreateTextureFromImage)
public func CVOpenGLESTextureCacheCreateTextureFromImage(_ allocator: UnsafeRawPointer?, _ cache: UnsafeMutableRawPointer?,
                                                         _ image: UnsafeMutableRawPointer?, _ attributes: UnsafeRawPointer?, _ target: UInt32,
                                                         _ internalFormat: Int32, _ width: Int32, _ height: Int32,
                                                         _ formatAndType: CVTextureFormatAndType, _ planeIndex: Int,
                                                         _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return cvInvalidArgument }
    out.pointee = nil
    guard let buffer = PixelBuffer.states[image], let bytes = buffer.bytes, Int(width) <= buffer.width, Int(height) <= buffer.height,
          width > 0, height > 0 else { return cvInvalidArgument }
    guard VideoGL.load(), let genTextures = VideoGL.genTextures, let bindTexture = VideoGL.bindTexture,
          let texParameteri = VideoGL.texParameteri, let texImage2D = VideoGL.texImage2D, let getIntegerv = VideoGL.getIntegerv else {
        return cvError
    }
    var name: UInt32 = 0
    genTextures(1, &name)
    guard name != 0 else { return cvError }
    // GL_TEXTURE_BINDING_2D; GL_TEXTURE_MIN_FILTER and MAG to GL_LINEAR,
    // GL_TEXTURE_WRAP_S and T to GL_CLAMP_TO_EDGE, as a texture with one
    // level of any size needs.
    var bound: Int32 = 0
    getIntegerv(0x8069, &bound)
    bindTexture(target, name)
    texParameteri(target, 0x2801, 0x2601)
    texParameteri(target, 0x2800, 0x2601)
    texParameteri(target, 0x2802, 0x812F)
    texParameteri(target, 0x2803, 0x812F)
    // Apple's OpenGL ES takes GL_RGBA as the internal format of GL_BGRA
    // pixels; others want GL_BGRA for both.
    let internalFormat = formatAndType.format == 0x80E1 && internalFormat == 0x1908 ? Int32(0x80E1) : internalFormat
    texImage2D(target, 0, internalFormat, width, height, 0, formatAndType.format, formatAndType.type, UnsafeRawPointer(bytes))
    bindTexture(target, UInt32(bitPattern: bound))
    let texture = NSObject(VideoTexture.objCClass.pointer).newInstance()
    let state = TextureState()
    (state.name, state.target) = (name, target)
    VideoTexture.states.set(texture.objcObject, state)
    _ = ObjCRuntime.retain(texture.objcObject)
    out.pointee = texture.objcObject
    return cvSuccess
}

@c(_CVOpenGLESTextureGetName) public func CVOpenGLESTextureGetName(_ texture: UnsafeMutableRawPointer?) -> UInt32 {
    VideoTexture.states[texture]?.name ?? 0
}
@c(_CVOpenGLESTextureGetTarget) public func CVOpenGLESTextureGetTarget(_ texture: UnsafeMutableRawPointer?) -> UInt32 {
    VideoTexture.states[texture]?.target ?? 0x0DE1
}
/// A frame's first row is its top one.
@c(_CVOpenGLESTextureIsFlipped) public func CVOpenGLESTextureIsFlipped(_ texture: UnsafeMutableRawPointer?) -> UInt8 { 1 }

// Metal textures: none, as there is no Metal device.

@c(_CVMetalTextureCacheCreate)
public func CVMetalTextureCacheCreate(_ allocator: UnsafeRawPointer?, _ cacheAttributes: UnsafeRawPointer?, _ device: UnsafeRawPointer?,
                                      _ textureAttributes: UnsafeRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    out?.pointee = nil
    return cvError
}

@c(_CVMetalTextureCacheCreateTextureFromImage)
public func CVMetalTextureCacheCreateTextureFromImage(_ allocator: UnsafeRawPointer?, _ cache: UnsafeRawPointer?, _ image: UnsafeRawPointer?,
                                                      _ attributes: UnsafeRawPointer?, _ format: UInt, _ width: Int, _ height: Int,
                                                      _ planeIndex: Int, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    out?.pointee = nil
    return cvError
}

@c(_CVMetalTextureCacheFlush) public func CVMetalTextureCacheFlush(_ cache: UnsafeRawPointer?, _ options: UInt64) {}
@c(_CVMetalTextureGetTexture) public func CVMetalTextureGetTexture(_ texture: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { nil }

// MARK: - AVPlayerItemVideoOutput

final class ItemOutputState {
    /// The item the output was added to; not retained.
    var item: UnsafeMutableRawPointer?
    /// The newest frame, until the program copies it.
    var pending: PixelBuffer?
    let lock = Lock()
    var delegate: UnsafeMutableRawPointer?
    var suppressesPlayerRendering = false
}

@ObjCClass("AVPlayerItemOutput")
open class AVPlayerItemOutput: NSObject {
    static let states = StateTable<ItemOutputState>()

    static func state(for object: UnsafeMutableRawPointer) -> ItemOutputState {
        if let state = states[object] { return state }
        let state = ItemOutputState()
        states.set(object, state)
        return state
    }

    var output: ItemOutputState { AVPlayerItemOutput.state(for: objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVPlayerItemOutput.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVPlayerItemOutput.objCClass.pointer)
    }

    /// The item's time now, whatever the host's time asked about.
    var itemTime: CMTime {
        guard let item = output.item, AVPlayerItem.states[item] != nil else { return .invalid }
        return AVPlayerItem(item).currentTime()
    }

    @ObjCMethod("itemTimeForHostTime:") func itemTime(forHostTime time: Double) -> CMTime { itemTime }
    @ObjCMethod("itemTimeForMachAbsoluteTime:") func itemTime(forMachAbsoluteTime time: Int64) -> CMTime { itemTime }
    @ObjCMethod("suppressesPlayerRendering") func suppressesPlayerRendering() -> Bool { output.suppressesPlayerRendering }
    @ObjCMethod("setSuppressesPlayerRendering:") func setSuppressesPlayerRendering(_ suppresses: Bool) { output.suppressesPlayerRendering = suppresses }
}

@ObjCClass("AVPlayerItemVideoOutput")
open class AVPlayerItemVideoOutput: AVPlayerItemOutput {
    @ObjCMethod("initWithPixelBufferAttributes:")
    func initialize(pixelBufferAttributes attributes: NSObject?) -> Self {
        _ = output
        return self
    }

    @ObjCMethod("initWithOutputSettings:")
    func initialize(outputSettings settings: NSObject?) -> Self {
        _ = output
        return self
    }

    /// The delegate is kept; it is not told of media data changing, as
    /// frames are there to be asked for while the item plays.
    @ObjCMethod("setDelegate:queue:") func setDelegate(_ delegate: NSObject?, queue: UnsafeMutableRawPointer?) { output.delegate = delegate?.objcObject }
    @ObjCMethod("delegate") func delegate() -> NSObject? { output.delegate.map { NSObject($0) } }
    @ObjCMethod("delegateQueue") func delegateQueue() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("requestNotificationOfMediaDataChangeWithAdvanceInterval:") func requestNotificationOfMediaDataChange(withAdvanceInterval interval: Double) {}

    /// Takes the newest frame the item's pipeline has decoded, if there is
    /// one, as the frame waiting to be copied. With the lock held.
    private func pull(_ state: ItemOutputState) {
        guard let item = state.item, AVPlayerItem.states[item] != nil, let pipeline = AVPlayerItem(item).pipeline else { return }
        let swapped = pipeline.format != "BGRA"
        var made: PixelBuffer?
        _ = pipeline.pullFrame { width, height, bytes, count in
            guard let buffer = PixelBuffer.make(width: width, height: height, format: PixelBuffer.bgra),
                  let memory = PixelBuffer.states[buffer.objcObject]?.bytes else { return }
            memcpy(memory, bytes, count)
            if swapped {
                // An item made with a URL has RGBA frames.
                let pixels = memory.assumingMemoryBound(to: UInt8.self)
                var index = 0
                while index + 3 < count {
                    (pixels[index], pixels[index + 2]) = (pixels[index + 2], pixels[index])
                    index += 4
                }
            }
            made = buffer
        }
        if let made { state.pending = made }
    }

    @ObjCMethod("hasNewPixelBufferForItemTime:")
    func hasNewPixelBuffer(forItemTime time: CMTime) -> Bool {
        let state = output
        return state.lock.withLock {
            pull(state)
            return state.pending != nil
        }
    }

    /// The newest frame, which becomes the caller's; nil when there has
    /// been none since the last one copied.
    @ObjCMethod("copyPixelBufferForItemTime:itemTimeForDisplay:")
    func copyPixelBuffer(forItemTime time: CMTime, itemTimeForDisplay display: UnsafeMutablePointer<CMTime>?) -> PixelBuffer? {
        let state = output
        return state.lock.withLock {
            if state.pending == nil { pull(state) }
            display?.pointee = time
            defer { state.pending = nil }
            return state.pending
        }
    }
}

// MARK: - MediaToolbox

// Audio processing taps, which a program puts on a track to take its
// samples: none can be made, as assets have no audio tracks (their sound
// plays as GStreamer plays it).

@c(_MTAudioProcessingTapCreate)
public func MTAudioProcessingTapCreate(_ allocator: UnsafeRawPointer?, _ callbacks: UnsafeRawPointer?, _ flags: UInt32,
                                       _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    out?.pointee = nil
    return -12780    // kMTAudioProcessingTapError_InvalidArgument
}

@c(_MTAudioProcessingTapGetStorage) public func MTAudioProcessingTapGetStorage(_ tap: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_MTAudioProcessingTapGetSourceAudio)
public func MTAudioProcessingTapGetSourceAudio(_ tap: UnsafeRawPointer?, _ frames: Int, _ bufferList: UnsafeMutableRawPointer?,
                                               _ flags: UnsafeMutablePointer<UInt32>?, _ timeRange: UnsafeMutablePointer<CMTimeRange>?,
                                               _ framesOut: UnsafeMutablePointer<Int>?) -> Int32 {
    framesOut?.pointee = 0
    return -12780
}
