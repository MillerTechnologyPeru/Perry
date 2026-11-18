import CPerryMedia
import Glibc
import PerryObjCInterop

// AVAssetReader: an asset's video frames one after another, as a program
// takes them to show a movie itself (an engine's video player does, to put
// the movie on a texture). The reader has a GStreamer pipeline of its own
// for the asset, not paced by a clock: each frame asked for is waited for,
// copied into a pixel buffer of 32-bit BGRA whatever format the output's
// settings name, and given in a sample buffer with its time. A reader's
// time range starts the pipeline there.
//
// There is no sound: an asset has no audio tracks here, and an output for
// audio gives no samples.

final class ReaderState {
    var asset: AVAsset?
    var outputs: [NSObject] = []
    /// AVAssetReaderStatus: unknown 0, reading 1, completed 2, failed 3, cancelled 4.
    var status = 0
    var pipeline: Pipeline?
    var range = CMTimeRange(start: .zero, duration: CMTime(seconds: .infinity))
    var frameRate = 30.0
    var frames = 0
    let lock = Lock()
}

@ObjCClass("AVAssetReader")
open class AVAssetReader: NSObject {
    static let states = StateTable<ReaderState>()
    var reader: ReaderState {
        if let state = AVAssetReader.states[objcObject] { return state }
        let state = ReaderState()
        AVAssetReader.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetReader.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetReader.objCClass.pointer)
    }

    @ObjCClassMethod("assetReaderWithAsset:error:")
    static func make(_ cls: ObjCClass, asset: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> AVAssetReader? {
        let made = NSObject(cls.pointer).newInstance().unsafeCast(to: AVAssetReader.self)
        error?.pointee = nil
        guard let asset, asset.is(AVAsset.self) else { return nil }
        made.reader.asset = asset.unsafeCast(to: AVAsset.self)
        return made
    }

    @ObjCMethod("initWithAsset:error:")
    func initialize(asset: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self {
        error?.pointee = nil
        if let asset, asset.is(AVAsset.self) { reader.asset = asset.unsafeCast(to: AVAsset.self) }
        return self
    }

    @ObjCMethod("asset") func asset() -> NSObject? { reader.asset }
    @ObjCMethod("status") func status() -> Int { reader.status }
    @ObjCMethod("error") func error() -> NSObject? { nil }
    @ObjCMethod("timeRange") func timeRange() -> CMTimeRange { reader.range }
    @ObjCMethod("setTimeRange:") func setTimeRange(_ range: CMTimeRange) { reader.range = range }
    @ObjCMethod("outputs") func outputs() -> NSObject { Arrays.of(reader.outputs) }
    @ObjCMethod("canAddOutput:") func canAdd(output: NSObject?) -> Bool { output != nil && reader.status == 0 }

    @ObjCMethod("addOutput:")
    func add(output: NSObject?) {
        guard let output else { return }
        reader.outputs.append(output)
        AVAssetReaderOutput.state(for: output.objcObject).reader = objcObject
    }

    /// Starts the asset's frames coming, from the time range's start.
    @ObjCMethod("startReading")
    func startReading() -> Bool {
        let state = reader
        return state.lock.withLock {
            guard state.status == 0, let asset = state.asset, let gst = GStreamer.shared else { return false }
            let media = asset.load()
            guard let uri = AssetLoading.uri(for: media),
                  let pipeline = Pipeline(uri: uri, gst: gst, format: "BGRA", reading: true), pipeline.prepare(timeout: 10) else {
                Players.trace("asset reader: the asset can't be read")
                state.status = 3
                return false
            }
            state.frameRate = media.description.map { $0.frameRate > 0 ? $0.frameRate : 30 } ?? 30
            let start = state.range.start.seconds
            if start.isFinite, start > 0 {
                pipeline.seek(to: start)
                state.frames = Int((start * state.frameRate).rounded())
            }
            pipeline.play()
            state.pipeline = pipeline
            state.status = 1
            Players.trace("asset reader: reading \(uri) from \(start.isFinite ? start : 0) s")
            return true
        }
    }

    @ObjCMethod("cancelReading")
    func cancelReading() {
        let state = reader
        state.lock.withLock {
            if state.status == 1 { state.status = 4 }
            state.pipeline = nil
        }
    }

    /// The next frame as a sample buffer the caller owns, or nil at the end, when the reader has completed.
    func nextSample() -> UnsafeMutableRawPointer? {
        let state = reader
        return state.lock.withLock {
            guard state.status == 1, let pipeline = state.pipeline else { return nil }
            var made: PixelBuffer?
            var seconds: Double?
            let got = pipeline.nextFrame { width, height, bytes, count, time in
                guard let buffer = PixelBuffer.make(width: width, height: height, format: PixelBuffer.bgra),
                      let memory = PixelBuffer.states[buffer.objcObject]?.bytes else { return }
                memcpy(memory, bytes, count)
                (made, seconds) = (buffer, time)
            }
            guard got, let made else {
                state.status = 2
                state.pipeline = nil
                Players.trace("asset reader: completed after \(state.frames) frames")
                return nil
            }
            let time = seconds ?? Double(state.frames) / state.frameRate
            state.frames += 1
            let width = PixelBuffer.states[made.objcObject]?.width ?? 0, height = PixelBuffer.states[made.objcObject]?.height ?? 0
            let timing = CMSampleTimingInfo(duration: CMTime(seconds: 1 / state.frameRate), presentationTimeStamp: CMTime(seconds: time),
                                            decodeTimeStamp: .invalid)
            // The sample buffer retains both: they are kept until it has.
            let format = FormatDescription.video(width: width, height: height)
            let sample = withExtendedLifetime((format, made)) {
                SampleBuffer.make(format: format.objcObject, image: made.objcObject, count: 1, timings: [timing])
            }
            SampleBuffer.states[sample]?.ready = true
            return sample
        }
    }
}

// MARK: - Outputs

final class ReaderOutputState {
    /// The reader the output was added to; not retained.
    var reader: UnsafeMutableRawPointer?
    var track: NSObject?
    var settings: NSObject?
    var mediaType = MediaConstants.AVMediaTypeVideo
    var alwaysCopies = true
    var randomAccess = false
}

@ObjCClass("AVAssetReaderOutput")
open class AVAssetReaderOutput: NSObject {
    static let states = StateTable<ReaderOutputState>()

    static func state(for object: UnsafeMutableRawPointer) -> ReaderOutputState {
        if let state = states[object] { return state }
        let state = ReaderOutputState()
        states.set(object, state)
        return state
    }

    var output: ReaderOutputState { AVAssetReaderOutput.state(for: objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetReaderOutput.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetReaderOutput.objCClass.pointer)
    }

    @ObjCMethod("mediaType") func mediaType() -> String { output.mediaType }
    @ObjCMethod("alwaysCopiesSampleData") func alwaysCopiesSampleData() -> Bool { output.alwaysCopies }
    @ObjCMethod("setAlwaysCopiesSampleData:") func setAlwaysCopiesSampleData(_ copies: Bool) { output.alwaysCopies = copies }
    @ObjCMethod("supportsRandomAccess") func supportsRandomAccess() -> Bool { output.randomAccess }
    @ObjCMethod("setSupportsRandomAccess:") func setSupportsRandomAccess(_ supports: Bool) { output.randomAccess = supports }
    @ObjCMethod("resetForReadingTimeRanges:") func resetForReading(timeRanges: NSObject?) {}
    @ObjCMethod("markConfigurationAsFinal") func markConfigurationAsFinal() {}

    /// The next sample, which the caller owns: a video output's is its reader's next frame.
    @ObjCMethod("copyNextSampleBuffer")
    func copyNextSampleBuffer() -> UnsafeMutableRawPointer? {
        let state = output
        guard state.mediaType == MediaConstants.AVMediaTypeVideo, let reader = state.reader, AVAssetReader.states[reader] != nil else { return nil }
        return AVAssetReader(reader).nextSample()
    }
}

@ObjCClass("AVAssetReaderTrackOutput")
open class AVAssetReaderTrackOutput: AVAssetReaderOutput {
    @ObjCClassMethod("assetReaderTrackOutputWithTrack:outputSettings:")
    static func make(_ cls: ObjCClass, track: NSObject?, outputSettings settings: NSObject?) -> AVAssetReaderTrackOutput {
        NSObject(cls.pointer).newInstance().unsafeCast(to: AVAssetReaderTrackOutput.self).initialize(track: track, outputSettings: settings)
    }

    @ObjCMethod("initWithTrack:outputSettings:")
    func initialize(track: NSObject?, outputSettings settings: NSObject?) -> Self {
        let state = output
        (state.track, state.settings) = (track, settings)
        Players.trace("asset reader: a track output with settings \(settings.map { "\($0)" } ?? "none")")
        return self
    }

    @ObjCMethod("track") func track() -> NSObject? { output.track }
    @ObjCMethod("outputSettings") func outputSettings() -> NSObject? { output.settings }
}

/// The sound of an asset's audio tracks mixed: there are none, so it gives no samples.
@ObjCClass("AVAssetReaderAudioMixOutput")
open class AVAssetReaderAudioMixOutput: AVAssetReaderOutput {
    @ObjCClassMethod("assetReaderAudioMixOutputWithAudioTracks:audioSettings:")
    static func make(_ cls: ObjCClass, audioTracks: NSObject?, audioSettings settings: NSObject?) -> AVAssetReaderAudioMixOutput {
        NSObject(cls.pointer).newInstance().unsafeCast(to: AVAssetReaderAudioMixOutput.self).initialize(audioTracks: audioTracks, audioSettings: settings)
    }

    @ObjCMethod("initWithAudioTracks:audioSettings:")
    func initialize(audioTracks: NSObject?, audioSettings settings: NSObject?) -> Self {
        let state = output
        (state.settings, state.mediaType) = (settings, MediaConstants.AVMediaTypeAudio)
        return self
    }

    @ObjCMethod("audioTracks") func audioTracks() -> NSObject { Arrays.of([]) }
    @ObjCMethod("audioSettings") func audioSettings() -> NSObject? { output.settings }
    @ObjCMethod("audioMix") func audioMix() -> NSObject? { nil }
    @ObjCMethod("setAudioMix:") func setAudioMix(_ mix: NSObject?) {}
}

// MARK: - What a reader's samples are asked

/// A sample's time as it is shown, which is its presentation time: nothing here retimes samples.
@c(_CMSampleBufferGetOutputPresentationTimeStamp)
public func CMSampleBufferGetOutputPresentationTimeStamp(_ buffer: UnsafeMutableRawPointer?) -> CMTime {
    CMSampleBufferGetPresentationTimeStamp(buffer)
}

/// A sample buffer has no block buffer: a frame's pixels are its image buffer's.
@c(_CMSampleBufferGetDataBuffer) public func CMSampleBufferGetDataBuffer(_ buffer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

/// No audio is read: kCMSampleBufferError_RequiredParameterMissing.
@c(_CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer)
public func CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(_ buffer: UnsafeMutableRawPointer?, _ sizeNeeded: UnsafeMutablePointer<Int>?,
                                                                    _ list: UnsafeMutableRawPointer?, _ listSize: Int, _ structureAllocator: UnsafeRawPointer?,
                                                                    _ blockAllocator: UnsafeRawPointer?, _ flags: UInt32,
                                                                    _ blockBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    sizeNeeded?.pointee = 0
    blockBuffer?.pointee = nil
    return -12731
}

/// No extensions are kept.
@c(_CMFormatDescriptionGetExtensions)
public func CMFormatDescriptionGetExtensions(_ description: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

/// The type identifiers of pixel buffers, which CFGetTypeID gives for one, and of block buffers, of which there are none.
enum MediaTypeIDs {
    static let pixelBuffer: UInt = 0x4356_0001, blockBuffer: UInt = 0x434D_0001
}

@c(_CVPixelBufferGetTypeID) public func CVPixelBufferGetTypeID() -> UInt { MediaTypeIDs.pixelBuffer }
@c(_CMBlockBufferGetTypeID) public func CMBlockBufferGetTypeID() -> UInt { MediaTypeIDs.blockBuffer }
