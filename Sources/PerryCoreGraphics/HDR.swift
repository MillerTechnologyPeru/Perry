import CPerryCoreGraphics
import CPerryGeometry
import Glibc
import PerryObjCInterop

// High dynamic range: tone mapping, adaptive bitmap contexts and rendering
// buffer providers. Contexts here draw 8-bit standard dynamic range, so tone
// mapping has nothing to map: images draw as CGContextDrawImage draws them,
// and a context's content tone mapping info is kept, saved and restored with
// its graphics state, and given back as set. An adaptive context resolves to
// 8-bit premultiplied BGRA in sRGB (or what its resolve block chooses, among
// the 8-bit layouts bitmap contexts draw), since nothing it can draw is
// deeper; it resolves when it is made rather than at its first image.

/// Option keys and values.
@ObjCConstants
enum ToneMappingConstants {
    static let kCGAdaptiveMaximumBitDepth = "kCGAdaptiveMaximumBitDepth"
    static let kCGPreferredDynamicRange = "kCGPreferredDynamicRange"
    static let kCGDynamicRangeHigh = "kCGDynamicRangeHigh"
    static let kCGDynamicRangeConstrained = "kCGDynamicRangeConstrained"
    static let kCGDynamicRangeStandard = "kCGDynamicRangeStandard"
    static let kCGContentAverageLightLevel = "kCGContentAverageLightLevel"
    static let kCGContentAverageLightLevelNits = "kCGContentAverageLightLevelNits"
    static let kCGEXRToneMappingGammaDefog = "kCGEXRToneMappingGammaDefog"
    static let kCGEXRToneMappingGammaExposure = "kCGEXRToneMappingGammaExposure"
    static let kCGEXRToneMappingGammaKneeLow = "kCGEXRToneMappingGammaKneeLow"
    static let kCGEXRToneMappingGammaKneeHigh = "kCGEXRToneMappingGammaKneeHigh"
    static let kCGUse100nitsHLGOOTF = "kCGUse100nitsHLGOOTF"
    static let kCGUseBT1886ForCoreVideoGamma = "kCGUseBT1886ForCoreVideoGamma"
    static let kCGSkipBoostToHDR = "kCGSkipBoostToHDR"
    static let kCGUseLegacyHDREcosystem = "kCGUseLegacyHDREcosystem"
}

/// Graphics state beside Silica's: the content tone mapping info, saved and
/// restored with CGContextSaveGState and CGContextRestoreGState. Each entry
/// holds a reference to its options.
final class ExtendedGraphicsState: @unchecked Sendable {
    struct ToneMapping {
        var method: UInt32
        var options: Ref?
    }

    private let lock = Lock()
    private var current = ToneMapping(method: 0, options: nil)
    private var saved: [ToneMapping] = []

    var toneMapping: ToneMapping { lock.withLock { current } }

    func setToneMapping(method: UInt32, options: Ref?) {
        lock.withLock {
            let old = current.options
            current = ToneMapping(method: method, options: ObjCRuntime.retain(options))
            ObjCRuntime.release(old)
        }
    }

    func save() {
        lock.withLock {
            saved.append(ToneMapping(method: current.method, options: ObjCRuntime.retain(current.options)))
        }
    }

    func restore() {
        lock.withLock {
            guard let previous = saved.popLast() else { return }
            ObjCRuntime.release(current.options)
            current = previous
        }
    }

    deinit {
        ObjCRuntime.release(current.options)
        saved.forEach { ObjCRuntime.release($0.options) }
    }
}

/// CGToneMapping's largest value, kCGToneMappingHeadroomAdaptiveGainCurve.
private let lastToneMapping: UInt32 = 6

/// Whether an image may hold more than standard dynamic range: deeper than
/// 8 bits, or in an extended-range or ITU-R BT.2100 space.
private func mayBeHighDynamicRange(_ image: ImageState) -> Bool {
    if image.format.bitsPerComponent > 8 { return true }
    guard let name = ColorSpaces.state(image.space)?.name else { return false }
    return name.contains("Extended") || name.contains("2100")
}

/// Draws the image as CGContextDrawImage does (an 8-bit context has no
/// headroom to map into), true. As CoreGraphics does, a method other than
/// the default applies only to an image that may hold high dynamic range:
/// for any other image it draws nothing and gives false; so does a method
/// CoreGraphics doesn't define.
@DarwinC("_CGContextDrawImageApplyingToneMapping")
public func CGContextDrawImageApplyingToneMapping(_ context: Ref?, _ rect: CGRect, _ image: Ref?, _ method: UInt32, _ options: Ref?) -> Bool {
    guard Contexts.state(context) != nil, let state = Images.state(image), method <= lastToneMapping else { return false }
    guard method == 0 || mayBeHighDynamicRange(state) else { return false }
    CGContextDrawImage(context, rect, image)
    return true
}

@c(_CGContextGetContentToneMappingInfo)
public func CGContextGetContentToneMappingInfo(_ context: Ref?) -> PerryCGContentToneMappingInfo {
    let toneMapping = Contexts.state(context)?.extended.toneMapping
    return PerryCGContentToneMappingInfo(method: toneMapping?.method ?? 0, options: toneMapping?.options)
}

@c(_CGContextSetContentToneMappingInfo)
public func CGContextSetContentToneMappingInfo(_ context: Ref?, _ info: PerryCGContentToneMappingInfo) {
    Contexts.state(context)?.extended.setToneMapping(method: info.method, options: info.options)
}

/// The EXR gamma tone mapping's defaults, as its header gives them (defog
/// 0, exposure 0, knee low 0, knee high 5), under kCGApplyEXRToneMappingGamma
/// as CoreGraphics nests them. One dictionary, kept for good.
nonisolated(unsafe) private var exrDefaults: Ref?
private let exrDefaultsLock = Lock()

@c(_CGEXRToneMappingGammaGetDefaultOptions)
public func CGEXRToneMappingGammaGetDefaultOptions() -> Ref? {
    exrDefaultsLock.withLock {
        if let exrDefaults { return exrDefaults }
        let entries: [(String, NSObject)] = [("kCGEXRToneMappingGammaDefog", NSObject.number(0.0)),
                                             ("kCGEXRToneMappingGammaExposure", NSObject.number(0.0)),
                                             ("kCGEXRToneMappingGammaKneeLow", NSObject.number(0.0)),
                                             ("kCGEXRToneMappingGammaKneeHigh", NSObject.number(5.0))]
        exrDefaults = NSMutableDictionary.of([("kCGApplyEXRToneMappingGamma", NSMutableDictionary.of(entries))]).objCOwnedReturnValue()
        return exrDefaults
    }
}

// MARK: - Rendering buffer providers

extension NSMutableData {
    @ObjCMethod("mutableBytes") func mutableBytes() -> UnsafeMutableRawPointer?
}

/// Memory a context draws into: the provider's own (malloc'd, freed with
/// it), a CFMutableData's, or what a lock block hands out, given back to the
/// unlock block. Locks nest; the first locks, the last unlocks.
final class RenderingBufferState: @unchecked Sendable {
    let info: UnsafeMutableRawPointer?
    let size: Int
    private let lockBlock: ObjCBlock?
    private let unlockBlock: ObjCBlock?
    private let releaseBlock: ObjCBlock?
    private let data: NSMutableData?
    private let owned: UnsafeMutableRawPointer?
    private let lock = Lock()
    private var locked: UnsafeMutableRawPointer?
    private var lockCount = 0

    typealias LockPointer = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias UnlockPointer = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void
    typealias ReleaseInfo = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void

    init(info: UnsafeMutableRawPointer?, size: Int, lock: ObjCBlock?, unlock: ObjCBlock?, release: ObjCBlock?,
         data: NSMutableData? = nil, owned: UnsafeMutableRawPointer? = nil) {
        self.info = info
        self.size = size
        lockBlock = lock
        unlockBlock = unlock
        releaseBlock = release
        self.data = data
        self.owned = owned
    }

    func lockBytes() -> UnsafeMutableRawPointer? {
        lock.withLock {
            if lockCount > 0 {
                lockCount += 1
                return locked
            }
            let pointer: UnsafeMutableRawPointer?
            if let owned { pointer = owned }
            else if let data { pointer = data.mutableBytes() }
            else if let lockBlock { pointer = lockBlock.function(as: LockPointer.self)(lockBlock.object, info) }
            else { pointer = nil }
            guard let pointer else { return nil }
            locked = pointer
            lockCount = 1
            return pointer
        }
    }

    func unlockBytes() {
        lock.withLock {
            guard lockCount > 0 else { return }
            lockCount -= 1
            guard lockCount == 0, let pointer = locked else { return }
            locked = nil
            if let unlockBlock { unlockBlock.function(as: UnlockPointer.self)(unlockBlock.object, info, pointer) }
        }
    }

    deinit {
        if lockCount > 0, let pointer = locked, let unlockBlock {
            unlockBlock.function(as: UnlockPointer.self)(unlockBlock.object, info, pointer)
        }
        if let releaseBlock { releaseBlock.function(as: ReleaseInfo.self)(releaseBlock.object, info) }
        free(owned)
    }
}

@ObjCClass("CGRenderingBufferProvider")
public final class CGRenderingBufferProviderObject: NSObject {
    static let states = StateTable<RenderingBufferState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGRenderingBufferProviderObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGRenderingBufferProviderObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.renderingBufferProvider }
}

enum RenderingBuffers {
    static func state(_ provider: Ref?) -> RenderingBufferState? { CGRenderingBufferProviderObject.states[provider] }

    static func make(_ state: RenderingBufferState) -> Ref {
        makeObject(CGRenderingBufferProviderObject.objCClass, CGRenderingBufferProviderObject.states, state)
    }

    /// A provider of zeroed memory of its own.
    static func make(size: Int) -> Ref? {
        guard size > 0, let memory = calloc(size, 1) else { return nil }
        return make(RenderingBufferState(info: nil, size: size, lock: nil, unlock: nil, release: nil, owned: memory))
    }
}

@c(_CGRenderingBufferProviderGetTypeID) public func CGRenderingBufferProviderGetTypeID() -> UInt { TypeIDs.renderingBufferProvider }

@c(_CGRenderingBufferProviderCreate)
public func CGRenderingBufferProviderCreate(_ info: UnsafeMutableRawPointer?, _ size: Int, _ lockPointer: UnsafeMutableRawPointer?,
                                            _ unlockPointer: UnsafeMutableRawPointer?, _ releaseInfo: UnsafeMutableRawPointer?) -> Ref? {
    guard size > 0, let lockPointer else { return nil }
    return RenderingBuffers.make(RenderingBufferState(info: info, size: size, lock: ObjCBlock(objCArgument: lockPointer),
                                                      unlock: unlockPointer.map { ObjCBlock(objCArgument: $0) },
                                                      release: releaseInfo.map { ObjCBlock(objCArgument: $0) }))
}

/// The data's bytes, as long as the provider lives; its length is the size.
@c(_CGRenderingBufferProviderCreateWithCFData)
public func CGRenderingBufferProviderCreateWithCFData(_ data: Ref?) -> Ref? {
    guard let data else { return nil }
    let mutable = NSMutableData(objCArgument: data)
    let size = Int(mutable.length())
    guard size > 0 else { return nil }
    return RenderingBuffers.make(RenderingBufferState(info: nil, size: size, lock: nil, unlock: nil, release: nil, data: mutable))
}

@c(_CGRenderingBufferProviderGetSize)
public func CGRenderingBufferProviderGetSize(_ provider: Ref?) -> Int { RenderingBuffers.state(provider)?.size ?? 0 }

@c(_CGRenderingBufferLockBytePtr)
public func CGRenderingBufferLockBytePtr(_ provider: Ref?) -> UnsafeMutableRawPointer? { RenderingBuffers.state(provider)?.lockBytes() }

@c(_CGRenderingBufferUnlockBytePtr)
public func CGRenderingBufferUnlockBytePtr(_ provider: Ref?) { RenderingBuffers.state(provider)?.unlockBytes() }

// MARK: - Adaptive bitmap contexts

@ObjCWrapper("NSError")
class FoundationError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func make(domain: String, code: Int, userInfo: NSObject?) -> FoundationError
}

/// CGComponent's 8-bit integer, CGColorModel's RGB, CGBitmapLayout's values.
private let component8Bit: UInt32 = 1
private let colorModelRGB: UInt32 = 1 << 1
private enum BitmapLayout {
    static let alphaOnly: UInt32 = 0, gray: UInt32 = 1, rgba: UInt32 = 3, argb: UInt32 = 4, rgbx: UInt32 = 5, xrgb: UInt32 = 6
    static let bgra: UInt32 = 7, bgrx: UInt32 = 8, abgr: UInt32 = 9, xbgr: UInt32 = 10
}

/// The CGBitmapInfo a bitmap context draws the parameters' layout with, if
/// it is one it can draw: 8-bit, with premultiplied alpha where there is
/// alpha.
private func bitmapInfo(for parameters: PerryCGBitmapParameters) -> UInt32? {
    guard parameters.component == component8Bit else { return nil }
    let little: UInt32 = 0x2000
    let premultiplied = parameters.hasPremultipliedAlpha
    switch parameters.layout {
    case BitmapLayout.alphaOnly: return 7
    case BitmapLayout.gray: return 0
    case BitmapLayout.rgba: return premultiplied ? 1 : nil
    case BitmapLayout.argb: return premultiplied ? 2 : nil
    case BitmapLayout.rgbx: return 5
    case BitmapLayout.xrgb: return 6
    case BitmapLayout.bgra: return premultiplied ? 2 | little : nil
    case BitmapLayout.bgrx: return 6 | little
    case BitmapLayout.abgr: return premultiplied ? 1 | little : nil
    case BitmapLayout.xbgr: return 5 | little
    default: return nil
    }
}

private func bytesPerPixel(_ layout: UInt32) -> Int { layout == BitmapLayout.alphaOnly || layout == BitmapLayout.gray ? 1 : 4 }

/// A bitmap context whose format is resolved by the content, which here is
/// always 8-bit standard dynamic range: the resolve block may change the
/// parameters to another layout bitmap contexts draw, the allocate block
/// may supply the memory (else the context allocates it), the free block is
/// handed the memory's provider when the context goes, and the error block
/// hears why a context couldn't be made.
@c(_CGBitmapContextCreateAdaptive)
public func CGBitmapContextCreateAdaptive(_ width: Int, _ height: Int, _ auxiliaryInfo: Ref?, _ onResolve: UnsafeMutableRawPointer?,
                                          _ onAllocate: UnsafeMutableRawPointer?, _ onFree: UnsafeMutableRawPointer?,
                                          _ onError: UnsafeMutableRawPointer?) -> Ref? {
    let resolve = onResolve.map { ObjCBlock(objCArgument: $0) }
    let allocate = onAllocate.map { ObjCBlock(objCArgument: $0) }
    let release = onFree.map { ObjCBlock(objCArgument: $0) }
    let report = onError.map { ObjCBlock(objCArgument: $0) }
    typealias Resolve = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<PerryCGContentInfo>,
                                        UnsafeMutablePointer<PerryCGBitmapParameters>) -> Bool
    typealias Allocate = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<PerryCGContentInfo>,
                                         UnsafePointer<PerryCGBitmapParameters>) -> UnsafeMutableRawPointer?
    typealias Free = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafePointer<PerryCGContentInfo>,
                                     UnsafePointer<PerryCGBitmapParameters>) -> Void
    typealias Report = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafePointer<PerryCGContentInfo>,
                                       UnsafePointer<PerryCGBitmapParameters>) -> Void

    let srgb = CGColorSpaceCreateWithName(NSObject.string("kCGColorSpaceSRGB").objcObject)!
    defer { ObjCRuntime.release(srgb) }
    let info = PerryCGContentInfo(deepestImageComponent: component8Bit, contentColorModels: colorModelRGB, hasWideGamut: false,
                                  hasTransparency: true, largestContentHeadroom: 1)
    var parameters = PerryCGBitmapParameters(width: max(width, 0), height: max(height, 0), bytesPerPixel: 4,
                                             alignedBytesPerRow: (max(width, 0) * 4 + 15) / 16 * 16, component: component8Bit,
                                             layout: BitmapLayout.bgra, format: 0, colorSpace: srgb, hasPremultipliedAlpha: true,
                                             byteOrder: 1, edrTargetHeadroom: 1)

    func fail(_ message: String) -> Ref? {
        guard let report else { return nil }
        let error = FoundationError.make(domain: "CGBitmapContextErrorDomain", code: 1001,
                                 userInfo: NSMutableDictionary.of([("NSLocalizedDescription", NSObject.string(message))]))
        withUnsafePointer(to: info) { info in
            withUnsafePointer(to: parameters) { report.function(as: Report.self)(report.object, error.objcObject, info, $0) }
        }
        return nil
    }

    guard width > 0, height > 0 else { return fail("The width and height must be greater than zero.") }
    if let resolve {
        _ = withUnsafePointer(to: info) { info in
            withUnsafeMutablePointer(to: &parameters) { resolve.function(as: Resolve.self)(resolve.object, info, $0) }
        }
    }
    guard let format = bitmapInfo(for: parameters) else { return fail("The bitmap parameters aren't a format CoreGraphics can draw.") }
    // The space: the parameters' own when its components fit the layout.
    let wantsGray = parameters.layout == BitmapLayout.gray || parameters.layout == BitmapLayout.alphaOnly
    let chosen = ColorSpaces.state(parameters.colorSpace).flatMap { $0.components == (wantsGray ? 1 : 3) ? parameters.colorSpace : nil }
    let space = ObjCRuntime.retain(chosen) ?? (wantsGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB())
    let rowBytes = max(Int(parameters.alignedBytesPerRow), width * bytesPerPixel(parameters.layout))
    parameters.alignedBytesPerRow = rowBytes
    parameters.bytesPerPixel = bytesPerPixel(parameters.layout)
    parameters.colorSpace = space

    // The memory, as a provider this function holds a reference to.
    let provider: Ref
    if let allocate {
        let made = withUnsafePointer(to: info) { info in
            withUnsafePointer(to: parameters) { allocate.function(as: Allocate.self)(allocate.object, info, $0) }
        }
        guard let made, RenderingBuffers.state(made) != nil else {
            ObjCRuntime.release(space)
            return fail("The allocation block gave no rendering buffer provider.")
        }
        provider = ObjCRuntime.retain(made)!
    } else {
        guard let made = RenderingBuffers.make(size: rowBytes * height) else {
            ObjCRuntime.release(space)
            return fail("The bitmap's memory couldn't be allocated.")
        }
        provider = made
    }
    let buffer = RenderingBuffers.state(provider)!
    guard buffer.size >= rowBytes * height, let memory = buffer.lockBytes() else {
        ObjCRuntime.release(provider)
        ObjCRuntime.release(space)
        return fail("The rendering buffer is smaller than the bitmap.")
    }
    guard let context = CGBitmapContextCreate(memory, width, height, 8, rowBytes, space, format),
          let state = Contexts.state(context) else {
        buffer.unlockBytes()
        ObjCRuntime.release(provider)
        ObjCRuntime.release(space)
        return fail("The bitmap context couldn't be made.")
    }
    let resolved = parameters
    state.onRelease = {
        buffer.unlockBytes()
        if let release {
            withUnsafePointer(to: info) { info in
                withUnsafePointer(to: resolved) { release.function(as: Free.self)(release.object, provider, info, $0) }
            }
        }
        ObjCRuntime.release(provider)
        ObjCRuntime.release(space)
    }
    return context
}
