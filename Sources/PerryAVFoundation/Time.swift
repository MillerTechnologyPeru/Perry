import CPerryGeometry
import CPerryMedia
import Glibc
import PerryObjCInterop

// CoreMedia, for what AVFoundation's players and assets hand out: times
// and their arithmetic, and the descriptions of a track's format; and the
// sample buffers and audio format descriptions programs make for an asset
// writer. Asset readers, which would give sample buffers, are not made.

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
    /// An audio description's AudioStreamBasicDescription and channel
    /// layout, as the program gave them, kept for as long as it is.
    var streamDescription: UnsafeMutableRawPointer?
    var channelLayout: UnsafeMutableRawPointer?
    var channelLayoutSize = 0

    deinit {
        streamDescription?.deallocate()
        channelLayout?.deallocate()
    }
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

/// An audio description made with CMAudioFormatDescriptionCreate gives
/// back its stream description; a track's audio is not described.
@c(_CMAudioFormatDescriptionGetStreamBasicDescription)
public func CMAudioFormatDescriptionGetStreamBasicDescription(_ description: UnsafeMutableRawPointer?) -> UnsafeRawPointer? {
    FormatDescription.states[description]?.streamDescription.map { UnsafeRawPointer($0) }
}

@c(_CMAudioFormatDescriptionGetChannelLayout)
public func CMAudioFormatDescriptionGetChannelLayout(_ description: UnsafeMutableRawPointer?,
                                                     _ size: UnsafeMutablePointer<Int>?) -> UnsafeRawPointer? {
    let state = FormatDescription.states[description]
    size?.pointee = state?.channelLayout == nil ? 0 : state?.channelLayoutSize ?? 0
    return state?.channelLayout.map { UnsafeRawPointer($0) }
}

/// (allocator, AudioStreamBasicDescription, layout size, layout, cookie
/// size, cookie, extensions, out): the cookie and extensions are not kept.
@c(_CMAudioFormatDescriptionCreate)
public func CMAudioFormatDescriptionCreate(_ allocator: UnsafeRawPointer?, _ stream: UnsafeRawPointer?, _ layoutSize: Int,
                                           _ layout: UnsafeRawPointer?, _ cookieSize: Int, _ cookie: UnsafeRawPointer?,
                                           _ extensions: UnsafeRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let stream, let out else { return -12710 }   // kCMFormatDescriptionError_InvalidParameter
    let description = NSObject(FormatDescription.objCClass.pointer).newInstance().unsafeCast(to: FormatDescription.self)
    let state = FormatDescriptionState()
    state.mediaType = 0x736F_756E   // 'soun'
    // AudioStreamBasicDescription: a Float64, then the format ID and the
    // rest, 40 bytes.
    state.subType = stream.load(fromByteOffset: 8, as: UInt32.self)
    let copied = UnsafeMutableRawPointer.allocate(byteCount: 40, alignment: 8)
    copied.copyMemory(from: stream, byteCount: 40)
    state.streamDescription = copied
    if let layout, layoutSize > 0 {
        let layoutCopy = UnsafeMutableRawPointer.allocate(byteCount: layoutSize, alignment: 8)
        layoutCopy.copyMemory(from: layout, byteCount: layoutSize)
        (state.channelLayout, state.channelLayoutSize) = (layoutCopy, layoutSize)
    }
    FormatDescription.states.set(description.objcObject, state)
    out.pointee = description.objCOwnedReturnValue()
    return 0
}

/// A time as CoreMedia describes it: "{value/timescale = seconds}", or
/// what it is when it isn't a number.
private func describe(_ time: CMTime) -> String {
    if time.flags & CMTime.valid == 0 { return "{INVALID}" }
    if time.flags & CMTime.indefinite != 0 { return "{INDEFINITE}" }
    if time.flags & CMTime.positiveInfinity != 0 { return "{+INFINITY}" }
    if time.flags & CMTime.negativeInfinity != 0 { return "{-INFINITY}" }
    return "{\(time.value)/\(time.timescale) = \(time.seconds)}"
}

#if arch(arm)
/// (allocator, time): 32-bit Darwin passes the time after the allocator in
/// r1 to r3 and then the stack, where Linux would start a structure of
/// 64-bit members at r2: its six words are taken one by one.
@c(_CMTimeCopyDescription)
public func CMTimeCopyDescription(_ allocator: UnsafeRawPointer?, _ valueLow: UInt32, _ valueHigh: UInt32, _ timescale: Int32,
                                  _ flags: UInt32, _ epochLow: UInt32, _ epochHigh: UInt32) -> UnsafeMutableRawPointer? {
    let time = CMTime(value: Int64(bitPattern: UInt64(valueHigh) << 32 | UInt64(valueLow)), timescale: timescale, flags: flags,
                      epoch: Int64(bitPattern: UInt64(epochHigh) << 32 | UInt64(epochLow)))
    return ObjCRuntime.retain(describe(time).objCArgument())
}
#else
@c(_CMTimeCopyDescription)
public func CMTimeCopyDescription(_ allocator: UnsafeRawPointer?, _ time: CMTime) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(describe(time).objCArgument())
}
#endif

// MARK: - Sample buffers

final class SampleBufferState {
    /// The format description and image buffer, retained.
    var format: UnsafeMutableRawPointer?
    var image: UnsafeMutableRawPointer?
    var count = 0
    var timings: [CMSampleTimingInfo] = []
    /// The audio set from an AudioBufferList, its buffers one after another.
    var data: [UInt8] = []
    var ready = false

    deinit {
        if let format { ObjCRuntime.release(format) }
        if let image { ObjCRuntime.release(image) }
    }
}

/// A CMSampleBuffer: an object, retained and released as any CoreFoundation
/// one. It keeps its format, timing, image buffer and audio; it has no
/// CMBlockBuffer of its own.
@ObjCClass("__PerryCMSampleBuffer")
open class SampleBuffer: NSObject {
    static let states = StateTable<SampleBufferState>()

    static func make(format: UnsafeMutableRawPointer?, image: UnsafeMutableRawPointer?, count: Int,
                     timings: [CMSampleTimingInfo]) -> UnsafeMutableRawPointer? {
        let buffer = NSObject(objCClass.pointer).newInstance().unsafeCast(to: SampleBuffer.self)
        let state = SampleBufferState()
        state.format = format.flatMap { ObjCRuntime.retain($0) }
        state.image = image.flatMap { ObjCRuntime.retain($0) }
        (state.count, state.timings) = (count, timings)
        states.set(buffer.objcObject, state)
        return buffer.objCOwnedReturnValue()
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        SampleBuffer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SampleBuffer.objCClass.pointer)
    }
}

private func timings(_ count: Int, _ array: UnsafePointer<CMSampleTimingInfo>?) -> [CMSampleTimingInfo] {
    guard let array, count > 0 else { return [] }
    return Array(UnsafeBufferPointer(start: array, count: count))
}

/// (allocator, data buffer, data ready, make-data-ready callback, its
/// refcon, format description, samples, timing entries, timings, size
/// entries, sizes, out). A data buffer given is not read.
@c(_CMSampleBufferCreate)
public func CMSampleBufferCreate(_ allocator: UnsafeRawPointer?, _ dataBuffer: UnsafeRawPointer?, _ dataReady: UInt8,
                                 _ makeDataReady: UnsafeRawPointer?, _ refcon: UnsafeRawPointer?, _ format: UnsafeMutableRawPointer?,
                                 _ samples: Int, _ timingCount: Int, _ timingArray: UnsafePointer<CMSampleTimingInfo>?,
                                 _ sizeCount: Int, _ sizes: UnsafePointer<Int>?,
                                 _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return -12730 }   // kCMSampleBufferError_RequiredParameterMissing
    out.pointee = SampleBuffer.make(format: format, image: nil, count: samples, timings: timings(timingCount, timingArray))
    SampleBuffer.states[out.pointee]?.ready = dataReady != 0
    return 0
}

/// A copy with other timing, sharing the original's format, image and audio.
@c(_CMSampleBufferCreateCopyWithNewTiming)
public func CMSampleBufferCreateCopyWithNewTiming(_ allocator: UnsafeRawPointer?, _ original: UnsafeMutableRawPointer?,
                                                  _ timingCount: Int, _ timingArray: UnsafePointer<CMSampleTimingInfo>?,
                                                  _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out, let state = SampleBuffer.states[original] else { return -12730 }
    out.pointee = SampleBuffer.make(format: state.format, image: state.image, count: state.count,
                                    timings: timings(timingCount, timingArray))
    if let copy = SampleBuffer.states[out.pointee] {
        (copy.data, copy.ready) = (state.data, state.ready)
    }
    return 0
}

@c(_CMSampleBufferGetFormatDescription)
public func CMSampleBufferGetFormatDescription(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    SampleBuffer.states[buffer]?.format
}

@c(_CMSampleBufferGetImageBuffer) public func CMSampleBufferGetImageBuffer(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    SampleBuffer.states[buffer]?.image
}

@c(_CMSampleBufferGetNumSamples) public func CMSampleBufferGetNumSamples(_ buffer: UnsafeMutableRawPointer?) -> Int {
    SampleBuffer.states[buffer]?.count ?? 0
}

@c(_CMSampleBufferGetPresentationTimeStamp) public func CMSampleBufferGetPresentationTimeStamp(_ buffer: UnsafeMutableRawPointer?) -> CMTime {
    SampleBuffer.states[buffer]?.timings.first?.presentationTimeStamp ?? .invalid
}

@c(_CMSampleBufferGetDuration) public func CMSampleBufferGetDuration(_ buffer: UnsafeMutableRawPointer?) -> CMTime {
    SampleBuffer.states[buffer]?.timings.first?.duration ?? .invalid
}

/// One timing entry stands for every sample.
@c(_CMSampleBufferGetSampleTimingInfo)
public func CMSampleBufferGetSampleTimingInfo(_ buffer: UnsafeMutableRawPointer?, _ index: Int,
                                              _ out: UnsafeMutablePointer<CMSampleTimingInfo>?) -> Int32 {
    guard let state = SampleBuffer.states[buffer], let out else { return -12730 }
    guard !state.timings.isEmpty, index >= 0, index < max(state.count, state.timings.count) else { return -12736 }   // kCMSampleBufferError_BufferHasNoSampleTimingInfo
    out.pointee = state.timings[state.timings.count == 1 ? 0 : index]
    return 0
}

/// (buffer, structure allocator, memory allocator, flags, AudioBufferList):
/// the buffers' bytes are copied, and the buffer is ready.
@c(_CMSampleBufferSetDataBufferFromAudioBufferList)
public func CMSampleBufferSetDataBufferFromAudioBufferList(_ buffer: UnsafeMutableRawPointer?, _ structureAllocator: UnsafeRawPointer?,
                                                           _ memoryAllocator: UnsafeRawPointer?, _ flags: UInt32,
                                                           _ list: UnsafeRawPointer?) -> Int32 {
    guard let state = SampleBuffer.states[buffer], let list else { return -12730 }
    // AudioBufferList: a UInt32 count, then AudioBuffers of two UInt32s
    // (channels, size) and a pointer, aligned to the pointer's size.
    let word = MemoryLayout<UnsafeRawPointer>.size
    let count = Int(list.load(as: UInt32.self))
    let stride = 8 + word
    var data: [UInt8] = []
    for index in 0..<count {
        let entry = list + word + index * stride
        let size = Int(entry.load(fromByteOffset: 4, as: UInt32.self))
        if let bytes = entry.load(fromByteOffset: 8, as: UnsafeRawPointer?.self), size > 0 {
            data.append(contentsOf: UnsafeRawBufferPointer(start: bytes, count: size))
        }
    }
    (state.data, state.ready) = (data, true)
    return 0
}

@c(_CMSampleBufferSetDataReady) public func CMSampleBufferSetDataReady(_ buffer: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = SampleBuffer.states[buffer] else { return -12730 }
    state.ready = true
    return 0
}

@c(_CMSampleBufferDataIsReady) public func CMSampleBufferDataIsReady(_ buffer: UnsafeMutableRawPointer?) -> UInt8 {
    SampleBuffer.states[buffer]?.ready == true ? 1 : 0
}

@c(_CMSampleBufferIsValid) public func CMSampleBufferIsValid(_ buffer: UnsafeMutableRawPointer?) -> UInt8 {
    SampleBuffer.states[buffer] == nil ? 0 : 1
}

@ObjCConstants
enum CoreMediaConstants {
    static let kCMFormatDescriptionExtension_Depth = "Depth"
}
