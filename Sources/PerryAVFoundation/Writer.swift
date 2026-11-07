import CPerryGeometry
import CPerryMedia
import Glibc
import PerryObjCInterop

// AVAssetWriter, its inputs and the pixel buffer adaptor, for programs that
// record what they draw and play (Everyplay, in games of its time). Nothing
// is encoded here: a writer takes its inputs' samples as they are appended,
// in order and as fast as they come, and writes no file. Finishing it fails
// with AVErrorUnknown and no movie, as a device that cannot encode would,
// and the program goes on without its recording.

final class WriterState {
    var url: NSObject?
    var fileType: String?
    var inputs: [NSObject] = []
    /// AVAssetWriterStatus: unknown 0, writing 1, completed 2, failed 3,
    /// cancelled 4.
    var status = 0
    var error: NSObject?
    var sessionStart = CMTime.invalid
    var sessionEnd = CMTime.invalid
    var shouldOptimizeForNetworkUse = false
    var movieFragmentInterval = CMTime.invalid
}

@ObjCClass("AVAssetWriter")
open class AVAssetWriter: NSObject {
    static let states = StateTable<WriterState>()
    var writer: WriterState {
        if let state = AVAssetWriter.states[objcObject] { return state }
        let state = WriterState()
        AVAssetWriter.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetWriter.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetWriter.objCClass.pointer)
    }

    @ObjCClassMethod("assetWriterWithURL:fileType:error:")
    static func make(_ cls: ObjCClass, url: NSObject?, fileType: String?, error: UnsafeMutableRawPointer?) -> NSObject? {
        guard url != nil else { return nil }
        let writer = NSObject(cls.pointer).newInstance().unsafeCast(to: AVAssetWriter.self)
        (writer.writer.url, writer.writer.fileType) = (url, fileType)
        return writer
    }

    @ObjCMethod("initWithURL:fileType:error:")
    func initialize(url: NSObject?, fileType: String?, error: UnsafeMutableRawPointer?) -> Self? {
        guard url != nil else { return nil }
        (writer.url, writer.fileType) = (url, fileType)
        return self
    }

    @ObjCMethod("outputURL") func outputURL() -> NSObject? { writer.url }
    @ObjCMethod("outputFileType") func outputFileType() -> String? { writer.fileType }
    @ObjCMethod("status") func status() -> Int { writer.status }
    @ObjCMethod("error") func error() -> NSObject? { writer.error }
    @ObjCMethod("inputs") func inputs() -> NSObject { Arrays.of(writer.inputs) }

    @ObjCMethod("shouldOptimizeForNetworkUse") func shouldOptimizeForNetworkUse() -> Bool { writer.shouldOptimizeForNetworkUse }
    @ObjCMethod("setShouldOptimizeForNetworkUse:")
    func setShouldOptimizeForNetworkUse(_ optimize: Bool) { writer.shouldOptimizeForNetworkUse = optimize }
    @ObjCMethod("movieFragmentInterval") func movieFragmentInterval() -> CMTime { writer.movieFragmentInterval }
    @ObjCMethod("setMovieFragmentInterval:") func setMovieFragmentInterval(_ interval: CMTime) { writer.movieFragmentInterval = interval }

    /// Video and audio, in settings or not, until writing starts.
    @ObjCMethod("canApplyOutputSettings:forMediaType:")
    func canApplyOutputSettings(_ settings: NSObject?, forMediaType mediaType: String?) -> Bool {
        mediaType == "vide" || mediaType == "soun"
    }

    @ObjCMethod("canAddInput:")
    func canAddInput(_ input: NSObject?) -> Bool {
        guard writer.status == 0, let input = input?.as(AVAssetWriterInput.self) else { return false }
        return !writer.inputs.contains { $0.objcObject == input.objcObject }
    }

    @ObjCMethod("addInput:")
    func addInput(_ input: NSObject?) {
        guard canAddInput(input), let input = input?.as(AVAssetWriterInput.self) else { return }
        writer.inputs.append(input)
        input.input.writer = objcObject
    }

    @ObjCMethod("startWriting")
    func startWriting() -> Bool {
        guard writer.status == 0 else { return false }
        writer.status = 1
        Players.trace("asset writer started, \(writer.inputs.count) inputs, no encoding")
        return true
    }

    @ObjCMethod("startSessionAtSourceTime:") func startSession(atSourceTime time: CMTime) { writer.sessionStart = time }
    @ObjCMethod("endSessionAtSourceTime:") func endSession(atSourceTime time: CMTime) { writer.sessionEnd = time }

    /// Ends writing: no movie is made, so writing fails.
    private func finish() {
        guard writer.status == 1 else { return }
        for input in writer.inputs { input.as(AVAssetWriterInput.self)?.input.finished = true }
        writer.status = 3
        writer.error = Writers.error(code: -11800, description: "This device cannot encode movies")
        Players.trace("asset writer finished, \(writer.inputs.map { $0.as(AVAssetWriterInput.self)?.input.appended ?? 0 }) samples taken")
    }

    @ObjCMethod("finishWriting")
    func finishWriting() -> Bool {
        finish()
        return writer.status == 2
    }

    /// The handler is called on the main queue.
    @ObjCMethod("finishWritingWithCompletionHandler:")
    func finishWriting(completionHandler: ObjCBlock?) {
        finish()
        guard let completionHandler else { return }
        Players.onMain {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object)
        }
    }

    @ObjCMethod("cancelWriting")
    func cancelWriting() {
        guard writer.status == 0 || writer.status == 1 else { return }
        for input in writer.inputs { input.as(AVAssetWriterInput.self)?.input.finished = true }
        writer.status = 4
    }
}

final class WriterInputState {
    var mediaType: String?
    var outputSettings: NSObject?
    var sourceFormatHint: NSObject?
    /// The writer it was added to, not retained (the writer keeps its inputs).
    var writer: UnsafeMutableRawPointer?
    var expectsMediaDataInRealTime = false
    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    var finished = false
    /// The samples taken, and the last one's time.
    var appended = 0
    var lastTime = CMTime.invalid
}

@ObjCClass("AVAssetWriterInput")
open class AVAssetWriterInput: NSObject {
    static let states = StateTable<WriterInputState>()
    var input: WriterInputState {
        if let state = AVAssetWriterInput.states[objcObject] { return state }
        let state = WriterInputState()
        AVAssetWriterInput.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetWriterInput.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetWriterInput.objCClass.pointer)
    }

    @ObjCClassMethod("assetWriterInputWithMediaType:outputSettings:")
    static func make(_ cls: ObjCClass, mediaType: String?, outputSettings: NSObject?) -> AVAssetWriterInput {
        let input = NSObject(cls.pointer).newInstance().unsafeCast(to: AVAssetWriterInput.self)
        (input.input.mediaType, input.input.outputSettings) = (mediaType, outputSettings)
        return input
    }

    @ObjCClassMethod("assetWriterInputWithMediaType:outputSettings:sourceFormatHint:")
    static func make(_ cls: ObjCClass, mediaType: String?, outputSettings: NSObject?, sourceFormatHint: NSObject?) -> AVAssetWriterInput {
        let input = make(cls, mediaType: mediaType, outputSettings: outputSettings)
        input.input.sourceFormatHint = sourceFormatHint
        return input
    }

    @ObjCMethod("initWithMediaType:outputSettings:")
    func initialize(mediaType: String?, outputSettings: NSObject?) -> Self {
        (input.mediaType, input.outputSettings) = (mediaType, outputSettings)
        return self
    }

    @ObjCMethod("initWithMediaType:outputSettings:sourceFormatHint:")
    func initialize(mediaType: String?, outputSettings: NSObject?, sourceFormatHint: NSObject?) -> Self {
        input.sourceFormatHint = sourceFormatHint
        return initialize(mediaType: mediaType, outputSettings: outputSettings)
    }

    @ObjCMethod("mediaType") func mediaType() -> String? { input.mediaType }
    @ObjCMethod("outputSettings") func outputSettings() -> NSObject? { input.outputSettings }
    @ObjCMethod("sourceFormatHint") func sourceFormatHint() -> NSObject? { input.sourceFormatHint }
    @ObjCMethod("expectsMediaDataInRealTime") func expectsMediaDataInRealTime() -> Bool { input.expectsMediaDataInRealTime }
    @ObjCMethod("setExpectsMediaDataInRealTime:")
    func setExpectsMediaDataInRealTime(_ realTime: Bool) { input.expectsMediaDataInRealTime = realTime }
    @ObjCMethod("transform") func transform() -> CGAffineTransform { input.transform }
    @ObjCMethod("setTransform:") func setTransform(_ transform: CGAffineTransform) { input.transform = transform }
    @ObjCMethod("languageCode") func languageCode() -> String? { nil }
    @ObjCMethod("setLanguageCode:") func setLanguageCode(_ code: String?) {}

    /// Its writer is writing and it has not been marked finished.
    var accepting: Bool {
        guard !input.finished, let writer = input.writer else { return false }
        return AVAssetWriter.states[writer]?.status == 1
    }

    /// Always, while its writer is writing: samples are taken at once.
    @ObjCMethod("isReadyForMoreMediaData") func isReadyForMoreMediaData() -> Bool { accepting }

    /// Takes a sample: its time is kept, its data is not encoded.
    @ObjCMethod("appendSampleBuffer:")
    func append(sampleBuffer: UnsafeMutableRawPointer?) -> Bool {
        guard accepting, let sampleBuffer else { return false }
        take(at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        return true
    }

    func take(at time: CMTime) {
        input.appended += 1
        input.lastTime = time
    }

    @ObjCMethod("markAsFinished") func markAsFinished() { input.finished = true }

    /// The block is called on the queue once: an input is always ready, so a
    /// block that appends while it is ready appends all it has then.
    @ObjCMethod("requestMediaDataWhenReadyOnQueue:usingBlock:")
    func requestMediaDataWhenReady(onQueue queue: UnsafeMutableRawPointer?, using block: ObjCBlock?) {
        guard let block, let queue else { return }
        _ = ObjCRuntime.retain(objcObject)
        let object = objcObject
        Writers.run(on: queue) {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
            block.function(as: Invoke.self)(block.object)
            ObjCRuntime.release(object)
        }
    }
}

final class PixelBufferAdaptorState {
    var input: NSObject?
    var attributes: NSObject?
}

@ObjCClass("AVAssetWriterInputPixelBufferAdaptor")
open class AVAssetWriterInputPixelBufferAdaptor: NSObject {
    static let states = StateTable<PixelBufferAdaptorState>()
    var adaptor: PixelBufferAdaptorState {
        if let state = AVAssetWriterInputPixelBufferAdaptor.states[objcObject] { return state }
        let state = PixelBufferAdaptorState()
        AVAssetWriterInputPixelBufferAdaptor.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetWriterInputPixelBufferAdaptor.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetWriterInputPixelBufferAdaptor.objCClass.pointer)
    }

    @ObjCClassMethod("assetWriterInputPixelBufferAdaptorWithAssetWriterInput:sourcePixelBufferAttributes:")
    static func make(_ cls: ObjCClass, input: NSObject?, attributes: NSObject?) -> AVAssetWriterInputPixelBufferAdaptor {
        let adaptor = NSObject(cls.pointer).newInstance().unsafeCast(to: AVAssetWriterInputPixelBufferAdaptor.self)
        (adaptor.adaptor.input, adaptor.adaptor.attributes) = (input, attributes)
        return adaptor
    }

    @ObjCMethod("initWithAssetWriterInput:sourcePixelBufferAttributes:")
    func initialize(input: NSObject?, attributes: NSObject?) -> Self {
        (adaptor.input, adaptor.attributes) = (input, attributes)
        return self
    }

    @ObjCMethod("assetWriterInput") func assetWriterInput() -> NSObject? { adaptor.input }
    @ObjCMethod("sourcePixelBufferAttributes") func sourcePixelBufferAttributes() -> NSObject? { adaptor.attributes }
    /// No pool: the program makes its pixel buffers with CVPixelBufferCreate.
    @ObjCMethod("pixelBufferPool") func pixelBufferPool() -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("appendPixelBuffer:withPresentationTime:")
    func append(pixelBuffer: UnsafeMutableRawPointer?, withPresentationTime time: CMTime) -> Bool {
        guard pixelBuffer != nil, let input = adaptor.input?.as(AVAssetWriterInput.self), input.accepting else { return false }
        input.take(at: time)
        return true
    }
}

enum Writers {
    private final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    /// Runs `body` on a dispatch queue of the program's.
    static func run(on queue: UnsafeMutableRawPointer, _ body: @escaping () -> Void) {
        guard let dispatchAsync = Players.dispatchAsync else { return body() }
        dispatchAsync(queue, Unmanaged.passRetained(Work(body)).toOpaque()) { context in
            guard let context else { return }
            Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body()
        }
    }

    /// An NSError in AVFoundationErrorDomain, +0.
    static func error(code: Int, description: String) -> NSObject? {
        let info = NSObject(ObjCClass(named: "NSDictionary").pointer).sendDictionary(object: description, key: "NSLocalizedDescription")
        return NSObject(ObjCClass(named: "NSError").pointer).sendError(domain: "AVFoundationErrorDomain", code: code, userInfo: info)
    }
}

extension NSObject {
    @ObjCMethod("dictionaryWithObject:forKey:") func sendDictionary(object: String, key: String) -> NSObject
    @ObjCMethod("errorWithDomain:code:userInfo:") func sendError(domain: String, code: Int, userInfo: NSObject?) -> NSObject?
}

/// The keys of a writer input's output settings, and their values.
@ObjCConstants
enum WriterConstants {
    static let AVVideoCodecKey = "AVVideoCodecKey"
    static let AVVideoCodecH264 = "avc1"
    static let AVVideoCodecJPEG = "jpeg"
    static let AVVideoWidthKey = "AVVideoWidthKey"
    static let AVVideoHeightKey = "AVVideoHeightKey"
    static let AVVideoScalingModeKey = "AVVideoScalingModeKey"
    static let AVVideoCompressionPropertiesKey = "AVVideoCompressionPropertiesKey"
    static let AVVideoAverageBitRateKey = "AverageBitRate"
    static let AVVideoMaxKeyFrameIntervalKey = "MaxKeyFrameInterval"
    static let AVVideoMaxKeyFrameIntervalDurationKey = "MaxKeyFrameIntervalDuration"
    static let AVVideoProfileLevelKey = "ProfileLevel"
    static let AVVideoProfileLevelH264Baseline30 = "H264_Baseline_3_0"
    static let AVVideoProfileLevelH264Baseline31 = "H264_Baseline_3_1"
    static let AVVideoProfileLevelH264Baseline41 = "H264_Baseline_4_1"
    static let AVVideoProfileLevelH264Main30 = "H264_Main_3_0"
    static let AVVideoProfileLevelH264Main31 = "H264_Main_3_1"
    static let AVVideoProfileLevelH264Main32 = "H264_Main_3_2"
    static let AVVideoProfileLevelH264Main41 = "H264_Main_4_1"
    static let AVVideoProfileLevelH264High40 = "H264_High_4_0"
    static let AVVideoProfileLevelH264High41 = "H264_High_4_1"
    static let AVFormatIDKey = "AVFormatIDKey"
    static let AVSampleRateKey = "AVSampleRateKey"
    static let AVNumberOfChannelsKey = "AVNumberOfChannelsKey"
    static let AVChannelLayoutKey = "AVChannelLayoutKey"
    static let AVEncoderBitRateKey = "AVEncoderBitRateKey"
    static let AVEncoderAudioQualityKey = "AVEncoderAudioQualityKey"
    static let AVLinearPCMBitDepthKey = "AVLinearPCMBitDepthKey"
    static let AVLinearPCMIsFloatKey = "AVLinearPCMIsFloatKey"
    static let AVLinearPCMIsBigEndianKey = "AVLinearPCMIsBigEndianKey"
    static let AVLinearPCMIsNonInterleaved = "AVLinearPCMIsNonInterleaved"
}
