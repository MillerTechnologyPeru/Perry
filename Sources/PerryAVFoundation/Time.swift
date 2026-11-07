import CPerryGeometry
import CPerryMedia
import Glibc
import PerryObjCInterop

// CoreMedia, for what AVFoundation's players and assets hand out: times
// and their arithmetic, and the descriptions of a track's format. Sample
// buffers, which asset readers give, are not made here.

extension CMTime: ObjCScalar {
    public static var objCTypeEncoding: String { "{?=qiIq}" }

    static let valid: UInt32 = 1, positiveInfinity: UInt32 = 4, negativeInfinity: UInt32 = 8, indefinite: UInt32 = 16
    static let zero = CMTime(value: 0, timescale: 1, flags: valid, epoch: 0)
    static let invalid = CMTime(value: 0, timescale: 0, flags: 0, epoch: 0)
    /// The timescale times are given in here: every common frame rate
    /// divides it.
    static let scale: Int32 = 90000

    init(seconds: Double, timescale: Int32 = CMTime.scale) {
        guard seconds.isFinite, timescale > 0 else {
            self = seconds == .infinity ? CMTime(value: 0, timescale: 0, flags: CMTime.valid | CMTime.positiveInfinity, epoch: 0)
                : seconds == -.infinity ? CMTime(value: 0, timescale: 0, flags: CMTime.valid | CMTime.negativeInfinity, epoch: 0)
                : .invalid
            return
        }
        self.init(value: Int64((seconds * Double(timescale)).rounded()), timescale: timescale, flags: CMTime.valid, epoch: 0)
    }

    /// A time with a value: valid, and neither infinite nor indefinite.
    var isNumeric: Bool {
        flags & CMTime.valid != 0 && flags & (CMTime.positiveInfinity | CMTime.negativeInfinity | CMTime.indefinite) == 0 && timescale != 0
    }

    var seconds: Double {
        if isNumeric { return Double(value) / Double(timescale) }
        if flags & CMTime.valid != 0, flags & CMTime.positiveInfinity != 0 { return .infinity }
        if flags & CMTime.valid != 0, flags & CMTime.negativeInfinity != 0 { return -.infinity }
        return .nan
    }

    /// The same time counted in another timescale, rounded to the nearest.
    func converted(to scale: Int32) -> CMTime {
        guard isNumeric, scale > 0, scale != timescale else { return self }
        let (product, overflow) = value.multipliedReportingOverflow(by: Int64(scale))
        let converted = overflow ? Int64((Double(value) * Double(scale) / Double(timescale)).rounded())
            : (product + (product < 0 ? -1 : 1) * Int64(timescale) / 2) / Int64(timescale)
        return CMTime(value: converted, timescale: scale, flags: flags, epoch: epoch)
    }
}

extension CMTimeRange: ObjCScalar {
    public static var objCTypeEncoding: String { "{?={?=qiIq}{?=qiIq}}" }
}

extension CGSize: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
}

extension CGAffineTransform: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGAffineTransform=dddddd}" }
}

// MARK: - Times

/// Two numeric times in one timescale, the finer of theirs.
private func common(_ a: CMTime, _ b: CMTime) -> (Int64, Int64, Int32) {
    let scale = max(a.timescale, b.timescale)
    return (a.converted(to: scale).value, b.converted(to: scale).value, scale)
}

@c(_CMTimeMake) public func CMTimeMake(_ value: Int64, _ timescale: Int32) -> CMTime {
    CMTime(value: value, timescale: timescale, flags: CMTime.valid, epoch: 0)
}

@c(_CMTimeMakeWithEpoch) public func CMTimeMakeWithEpoch(_ value: Int64, _ timescale: Int32, _ epoch: Int64) -> CMTime {
    CMTime(value: value, timescale: timescale, flags: CMTime.valid, epoch: epoch)
}

@c(_CMTimeMakeWithSeconds) public func CMTimeMakeWithSeconds(_ seconds: Double, _ preferredTimescale: Int32) -> CMTime {
    CMTime(seconds: seconds, timescale: preferredTimescale)
}

@c(_CMTimeGetSeconds) public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }

/// -1, 0 or 1: invalid times first, then by value, the infinities at the
/// ends.
@c(_CMTimeCompare) public func CMTimeCompare(_ a: CMTime, _ b: CMTime) -> Int32 {
    if a.isNumeric, b.isNumeric {
        let (x, y, _) = common(a, b)
        return x < y ? -1 : x > y ? 1 : 0
    }
    let (x, y) = (a.seconds, b.seconds)
    if x.isNaN || y.isNaN { return x.isNaN && y.isNaN ? 0 : x.isNaN ? -1 : 1 }
    return x < y ? -1 : x > y ? 1 : 0
}

@c(_CMTimeAdd) public func CMTimeAdd(_ a: CMTime, _ b: CMTime) -> CMTime {
    guard a.isNumeric, b.isNumeric else { return CMTime(seconds: a.seconds + b.seconds) }
    let (x, y, scale) = common(a, b)
    return CMTime(value: x &+ y, timescale: scale, flags: CMTime.valid, epoch: a.epoch)
}

@c(_CMTimeSubtract) public func CMTimeSubtract(_ a: CMTime, _ b: CMTime) -> CMTime {
    guard a.isNumeric, b.isNumeric else { return CMTime(seconds: a.seconds - b.seconds) }
    let (x, y, scale) = common(a, b)
    return CMTime(value: x &- y, timescale: scale, flags: CMTime.valid, epoch: a.epoch)
}

@c(_CMTimeMultiply) public func CMTimeMultiply(_ time: CMTime, _ multiplier: Int32) -> CMTime {
    guard time.isNumeric else { return time }
    return CMTime(value: time.value &* Int64(multiplier), timescale: time.timescale, flags: time.flags, epoch: time.epoch)
}

@c(_CMTimeMultiplyByFloat64) public func CMTimeMultiplyByFloat64(_ time: CMTime, _ multiplier: Double) -> CMTime {
    guard time.isNumeric else { return time }
    return CMTime(value: Int64((Double(time.value) * multiplier).rounded()), timescale: time.timescale, flags: time.flags, epoch: time.epoch)
}

@c(_CMTimeMultiplyByRatio) public func CMTimeMultiplyByRatio(_ time: CMTime, _ multiplier: Int32, _ divisor: Int32) -> CMTime {
    guard time.isNumeric, divisor != 0 else { return divisor == 0 ? .invalid : time }
    return CMTime(value: time.value &* Int64(multiplier) / Int64(divisor), timescale: time.timescale, flags: time.flags, epoch: time.epoch)
}

/// The rounding method is not looked at: to the nearest.
@c(_CMTimeConvertScale) public func CMTimeConvertScale(_ time: CMTime, _ timescale: Int32, _ method: UInt32) -> CMTime {
    time.converted(to: timescale)
}

@c(_CMTimeAbsoluteValue) public func CMTimeAbsoluteValue(_ time: CMTime) -> CMTime {
    guard time.isNumeric else { return time.seconds == -.infinity ? CMTime(seconds: .infinity) : time }
    return CMTime(value: abs(time.value), timescale: time.timescale, flags: time.flags, epoch: time.epoch)
}

@c(_CMTimeMaximum) public func CMTimeMaximum(_ a: CMTime, _ b: CMTime) -> CMTime { CMTimeCompare(a, b) >= 0 ? a : b }
@c(_CMTimeMinimum) public func CMTimeMinimum(_ a: CMTime, _ b: CMTime) -> CMTime { CMTimeCompare(a, b) <= 0 ? a : b }

@c(_CMTimeRangeMake) public func CMTimeRangeMake(_ start: CMTime, _ duration: CMTime) -> CMTimeRange {
    CMTimeRange(start: start, duration: duration)
}

@c(_CMTimeRangeGetEnd) public func CMTimeRangeGetEnd(_ range: CMTimeRange) -> CMTime { CMTimeAdd(range.start, range.duration) }

@c(_CMTimeRangeFromTimeToTime) public func CMTimeRangeFromTimeToTime(_ start: CMTime, _ end: CMTime) -> CMTimeRange {
    CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
}

@c(_CMTimeRangeContainsTime) public func CMTimeRangeContainsTime(_ range: CMTimeRange, _ time: CMTime) -> UInt8 {
    CMTimeCompare(time, range.start) >= 0 && CMTimeCompare(time, CMTimeRangeGetEnd(range)) < 0 ? 1 : 0
}

@c(_CMTimeRangeEqual) public func CMTimeRangeEqual(_ a: CMTimeRange, _ b: CMTimeRange) -> UInt8 {
    CMTimeCompare(a.start, b.start) == 0 && CMTimeCompare(a.duration, b.duration) == 0 ? 1 : 0
}

// MARK: - Format descriptions

final class FormatDescriptionState {
    /// 'vide' or 'soun', and the codec ('avc1' for any video: the stream
    /// is decoded by GStreamer, which doesn't say).
    var mediaType: UInt32 = 0x7669_6465
    var subType: UInt32 = 0x6176_6331
    var width = 0
    var height = 0
}

/// A CMFormatDescription: an object, as it is retained and released as
/// any CoreFoundation one.
@ObjCClass("__PerryCMFormatDescription")
open class FormatDescription: NSObject {
    static let states = StateTable<FormatDescriptionState>()

    static func video(width: Int, height: Int) -> FormatDescription {
        let description = NSObject(objCClass.pointer).newInstance().unsafeCast(to: FormatDescription.self)
        let state = FormatDescriptionState()
        (state.width, state.height) = (width, height)
        states.set(description.objcObject, state)
        return description
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        FormatDescription.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: FormatDescription.objCClass.pointer)
    }
}

@c(_CMFormatDescriptionGetMediaType) public func CMFormatDescriptionGetMediaType(_ description: UnsafeMutableRawPointer?) -> UInt32 {
    FormatDescription.states[description]?.mediaType ?? 0
}

@c(_CMFormatDescriptionGetMediaSubType) public func CMFormatDescriptionGetMediaSubType(_ description: UnsafeMutableRawPointer?) -> UInt32 {
    FormatDescription.states[description]?.subType ?? 0
}

@c(_CMVideoFormatDescriptionGetDimensions)
public func CMVideoFormatDescriptionGetDimensions(_ description: UnsafeMutableRawPointer?) -> CMVideoDimensions {
    let state = FormatDescription.states[description]
    return CMVideoDimensions(width: Int32(state?.width ?? 0), height: Int32(state?.height ?? 0))
}

/// Pixels are square and nothing is cropped: the size as it is.
@c(_CMVideoFormatDescriptionGetPresentationDimensions)
public func CMVideoFormatDescriptionGetPresentationDimensions(_ description: UnsafeMutableRawPointer?, _ usePixelAspectRatio: UInt8,
                                                              _ useCleanAperture: UInt8) -> CGSize {
    let state = FormatDescription.states[description]
    return CGSize(width: .init(state?.width ?? 0), height: .init(state?.height ?? 0))
}

/// No extensions are kept (the pixel depth, the color tags…).
@c(_CMFormatDescriptionGetExtension)
public func CMFormatDescriptionGetExtension(_ description: UnsafeMutableRawPointer?, _ key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    nil
}

/// Audio tracks are not described: a player's sound goes to the system's
/// output as GStreamer plays it.
@c(_CMAudioFormatDescriptionGetRichestDecodableFormat)
public func CMAudioFormatDescriptionGetRichestDecodableFormat(_ description: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { nil }

@c(_CMAudioFormatDescriptionGetStreamBasicDescription)
public func CMAudioFormatDescriptionGetStreamBasicDescription(_ description: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { nil }

// MARK: - Sample buffers

@c(_CMSampleBufferGetImageBuffer) public func CMSampleBufferGetImageBuffer(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_CMSampleBufferGetPresentationTimeStamp) public func CMSampleBufferGetPresentationTimeStamp(_ buffer: UnsafeMutableRawPointer?) -> CMTime {
    .invalid
}

@ObjCConstants
enum CoreMediaConstants {
    static let kCMFormatDescriptionExtension_Depth = "Depth"
}
