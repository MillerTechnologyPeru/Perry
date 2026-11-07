import CPerryGeometry
import CPerryMedia
import Glibc
import PerryObjCInterop

// AVAsset, AVURLAsset, their tracks, and AVMutableComposition, over a
// GStreamer pipeline per asset: made when the asset's values are first
// loaded or asked for, and paused on its first frame, which says how long
// the stream is, its video's size and its frame rate. A player item made
// with the asset plays that pipeline.
//
// An asset whose URL is neither a file's nor the web's is read through its
// resource loader's delegate, as AVFoundation reads it: the delegate is
// asked what the resource is and how long, then for its bytes, which are
// kept in a temporary file for GStreamer to play. An engine keeps a movie
// inside one of its own data files this way.
//
// Only the video is described as a track. A stream's sound is played by
// GStreamer to the system's output, and has no track: a program that mixes
// a movie's audio itself, through a processing tap, finds none to tap.
//
// A composition stands for the first asset put in it: what engines build
// to play one asset at another rate. Its time ranges are not kept.

final class AssetState {
    var url: NSObject?
    /// A composition's asset.
    var source: AVAsset?
    var loader: NSObject?
    /// Not retained, as AVFoundation keeps it weakly.
    var loaderDelegate: UnsafeMutableRawPointer?
    let lock = Lock()
    var loaded = false
    var pipeline: Pipeline?
    var description: MediaDescription?
    /// The resource as its loader's delegate gave it, and its length.
    var temporaryPath: String?
    var byteCount = 0
    var tracks: [NSObject]?

    deinit {
        if let temporaryPath { unlink(temporaryPath) }
    }
}

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?
    @ObjCMethod("length") func length() -> Int
}

extension NSObject {
    @ObjCMethod("resourceLoader:shouldWaitForLoadingOfRequestedResource:")
    func sendResourceLoader(_ loader: NSObject, shouldWaitForLoadingOfRequestedResource request: NSObject) -> Bool
}

// MARK: - AVAsset

@ObjCClass("AVAsset")
open class AVAsset: NSObject {
    static let states = StateTable<AssetState>()
    var asset: AssetState {
        if let state = AVAsset.states[objcObject] { return state }
        let state = AssetState()
        AVAsset.states.set(objcObject, state)
        return state
    }

    /// The state with the media: a composition's is its asset's.
    var media: AssetState {
        var state = asset
        for _ in 0..<8 {
            guard let source = state.source else { break }
            state = source.asset
        }
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAsset.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAsset.objCClass.pointer)
    }

    @ObjCClassMethod("assetWithURL:")
    static func make(_ cls: ObjCClass, url: NSObject?) -> AVAsset {
        let asset = NSObject(AVURLAsset.objCClass.pointer).newInstance().unsafeCast(to: AVAsset.self)
        asset.asset.url = url
        return asset
    }

    /// The media, read if it hasn't been: other threads wait meanwhile.
    @discardableResult
    func load() -> AssetState {
        let state = media
        state.lock.withLock {
            guard !state.loaded else { return }
            state.loaded = true
            guard let gst = GStreamer.shared, let uri = AssetLoading.uri(for: state) else {
                Players.trace("asset can't be read")
                return
            }
            guard let pipeline = Pipeline(uri: uri, gst: gst, format: "BGRA"), let description = pipeline.describe(timeout: 10) else {
                Players.trace("asset \(uri) can't play")
                return
            }
            Players.trace("asset \(uri): \(description.width)x\(description.height), \(description.frameRate) frames a second, "
                          + "\(description.duration) s, \(description.audioStreams) audio streams")
            (state.pipeline, state.description) = (pipeline, description)
        }
        return state
    }

    /// AVKeyValueStatus: loaded 2, failed 3.
    @ObjCMethod("statusOfValueForKey:error:")
    func statusOfValue(forKey key: String, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int {
        error?.pointee = nil
        let state = media
        guard state.lock.withLock({ state.loaded }) else { return 0 }
        return state.description != nil ? 2 : 3
    }

    /// The values are read on a thread of their own, and the handler is
    /// called from it.
    @ObjCMethod("loadValuesAsynchronouslyForKeys:completionHandler:")
    func loadValuesAsynchronously(forKeys keys: NSObject?, completionHandler: ObjCBlock?) {
        let object = objcObject
        _ = ObjCRuntime.retain(object)
        Players.trace("asset's values asked for")
        Background.run {
            AVAsset(object).load()
            Players.trace("asset's values loaded")
            if let completionHandler {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
                completionHandler.function(as: Invoke.self)(completionHandler.object)
            }
            ObjCRuntime.release(object)
        }
    }

    @ObjCMethod("cancelLoading") func cancelLoading() {}
    @ObjCMethod("isPlayable") func isPlayable() -> Bool { load().description != nil }
    @ObjCMethod("isReadable") func isReadable() -> Bool { load().description != nil }
    @ObjCMethod("isExportable") func isExportable() -> Bool { false }
    @ObjCMethod("isComposable") func isComposable() -> Bool { true }
    @ObjCMethod("hasProtectedContent") func hasProtectedContent() -> Bool { false }
    @ObjCMethod("preferredRate") func preferredRate() -> Float { 1 }
    @ObjCMethod("preferredVolume") func preferredVolume() -> Float { 1 }
    @ObjCMethod("duration") func duration() -> CMTime { CMTime(seconds: load().description?.duration ?? 0) }

    @ObjCMethod("naturalSize")
    func naturalSize() -> CGSize {
        let description = load().description
        return CGSize(width: Double(description?.width ?? 0), height: Double(description?.height ?? 0))
    }

    @ObjCMethod("preferredTransform")
    func preferredTransform() -> CGAffineTransform { CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }

    /// The video's track, if the stream has video.
    var trackObjects: [NSObject] {
        let state = load()
        return state.lock.withLock {
            if let tracks = state.tracks { return tracks }
            var tracks: [NSObject] = []
            if let description = state.description, description.width > 0, description.height > 0 {
                let track = NSObject(AVAssetTrack.objCClass.pointer).newInstance()
                let trackState = TrackState()
                (trackState.media, trackState.asset) = (state, objcObject)
                AVAssetTrack.states.set(track.objcObject, trackState)
                tracks.append(track)
            }
            state.tracks = tracks
            return tracks
        }
    }

    @ObjCMethod("tracks") func tracks() -> NSObject { Arrays.of(trackObjects) }

    @ObjCMethod("tracksWithMediaType:")
    func tracks(withMediaType type: String?) -> NSObject { Arrays.of(type == MediaConstants.AVMediaTypeVideo ? trackObjects : []) }

    @ObjCMethod("tracksWithMediaCharacteristic:")
    func tracks(withMediaCharacteristic characteristic: String?) -> NSObject { Arrays.of([]) }

    @ObjCMethod("trackWithTrackID:") func track(withTrackID id: Int32) -> NSObject? { id == 1 ? trackObjects.first : nil }
    @ObjCMethod("metadata") func metadata() -> NSObject { Arrays.of([]) }
    @ObjCMethod("commonMetadata") func commonMetadata() -> NSObject { Arrays.of([]) }
}

// MARK: - AVURLAsset

@ObjCClass("AVURLAsset")
open class AVURLAsset: AVAsset {
    @ObjCClassMethod("URLAssetWithURL:options:")
    static func make(_ cls: ObjCClass, url: NSObject?, options: NSObject?) -> AVURLAsset {
        let asset = NSObject(cls.pointer).newInstance().unsafeCast(to: AVURLAsset.self)
        asset.asset.url = url
        return asset
    }

    @ObjCMethod("initWithURL:options:")
    func initialize(url: NSObject?, options: NSObject?) -> Self {
        asset.url = url
        Players.trace("asset for \(url?.unsafeCast(to: NSURL.self).absoluteString() ?? "no URL")")
        return self
    }

    @ObjCMethod("URL") func url() -> NSObject? { asset.url }

    @ObjCMethod("resourceLoader")
    func resourceLoader() -> NSObject {
        let state = asset
        if let loader = state.loader { return loader }
        let loader = NSObject(AVAssetResourceLoader.objCClass.pointer).newInstance()
        let owner = AssetOwner()
        owner.state = state
        AVAssetResourceLoader.owners.set(loader.objcObject, owner)
        state.loader = loader
        return loader
    }
}

// MARK: - AVAssetTrack

final class TrackState {
    weak var media: AssetState?
    /// The asset's object, not retained: looked up before it is given.
    var asset: UnsafeMutableRawPointer?
}

@ObjCClass("AVAssetTrack")
open class AVAssetTrack: NSObject {
    static let states = StateTable<TrackState>()
    private var description: MediaDescription? { AVAssetTrack.states[objcObject]?.media?.description }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetTrack.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetTrack.objCClass.pointer)
    }

    @ObjCMethod("asset")
    func asset() -> NSObject? {
        guard let asset = AVAssetTrack.states[objcObject]?.asset, AVAsset.states[asset] != nil else { return nil }
        return NSObject(asset)
    }

    @ObjCMethod("trackID") func trackID() -> Int32 { 1 }
    @ObjCMethod("mediaType") func mediaType() -> String { MediaConstants.AVMediaTypeVideo }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { true }
    @ObjCMethod("isPlayable") func isPlayable() -> Bool { true }
    @ObjCMethod("isSelfContained") func isSelfContained() -> Bool { true }
    @ObjCMethod("languageCode") func languageCode() -> String? { nil }
    @ObjCMethod("extendedLanguageTag") func extendedLanguageTag() -> String? { nil }
    @ObjCMethod("preferredVolume") func preferredVolume() -> Float { 1 }
    @ObjCMethod("naturalTimeScale") func naturalTimeScale() -> Int32 { CMTime.scale }
    @ObjCMethod("nominalFrameRate") func nominalFrameRate() -> Float { Float(description?.frameRate ?? 0) }

    @ObjCMethod("naturalSize")
    func naturalSize() -> CGSize { CGSize(width: Double(description?.width ?? 0), height: Double(description?.height ?? 0)) }

    @ObjCMethod("preferredTransform")
    func preferredTransform() -> CGAffineTransform { CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }

    @ObjCMethod("timeRange")
    func timeRange() -> CMTimeRange { CMTimeRange(start: .zero, duration: CMTime(seconds: description?.duration ?? 0)) }

    @ObjCMethod("minFrameDuration")
    func minFrameDuration() -> CMTime {
        guard let rate = description?.frameRate, rate > 0 else { return .invalid }
        return CMTime(seconds: 1 / rate)
    }

    /// Bits a second, from the resource's length when its loader gave it;
    /// unknown (zero) for a file or a URL.
    @ObjCMethod("estimatedDataRate")
    func estimatedDataRate() -> Float {
        guard let media = AVAssetTrack.states[objcObject]?.media, let duration = media.description?.duration, duration > 0 else { return 0 }
        return Float(Double(media.byteCount) * 8 / duration)
    }

    @ObjCMethod("totalSampleDataLength") func totalSampleDataLength() -> Int64 { Int64(AVAssetTrack.states[objcObject]?.media?.byteCount ?? 0) }

    @ObjCMethod("formatDescriptions")
    func formatDescriptions() -> NSObject {
        guard let description else { return Arrays.of([]) }
        return Arrays.of([FormatDescription.video(width: description.width, height: description.height)])
    }

    @ObjCMethod("metadata") func metadata() -> NSObject { Arrays.of([]) }
    @ObjCMethod("commonMetadata") func commonMetadata() -> NSObject { Arrays.of([]) }
}

// MARK: - AVMutableComposition

@ObjCClass("AVComposition")
open class AVComposition: AVAsset {
}

@ObjCClass("AVMutableComposition")
open class AVMutableComposition: AVComposition {
    @ObjCClassMethod("composition")
    static func make(_ cls: ObjCClass) -> AVMutableComposition {
        NSObject(cls.pointer).newInstance().unsafeCast(to: AVMutableComposition.self)
    }

    /// The first asset put in is what the composition plays, whole.
    @ObjCMethod("insertTimeRange:ofAsset:atTime:error:")
    func insert(timeRange: CMTimeRange, of source: AVAsset?, at time: CMTime, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = nil
        guard let source else { return false }
        let state = asset
        if state.source == nil, source.objcObject != objcObject { state.source = source }
        return true
    }

    /// Time is not stretched: players play at the rate they are set to.
    @ObjCMethod("scaleTimeRange:toDuration:") func scale(timeRange: CMTimeRange, toDuration duration: CMTime) {}
    @ObjCMethod("removeTimeRange:") func remove(timeRange: CMTimeRange) {}
    @ObjCMethod("insertEmptyTimeRange:") func insertEmpty(timeRange: CMTimeRange) {}

    @ObjCMethod("addMutableTrackWithMediaType:preferredTrackID:")
    func addMutableTrack(withMediaType type: String?, preferredTrackID: Int32) -> NSObject? { nil }
}

// MARK: - Resource loaders

/// The asset a resource loader is for, which owns it.
final class AssetOwner {
    weak var state: AssetState?
}

@ObjCClass("AVAssetResourceLoader")
open class AVAssetResourceLoader: NSObject {
    static let owners = StateTable<AssetOwner>()

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAssetResourceLoader.owners.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetResourceLoader.objCClass.pointer)
    }

    /// The delegate is called on the thread that reads the asset, whatever
    /// the queue.
    @ObjCMethod("setDelegate:queue:")
    func setDelegate(_ delegate: NSObject?, queue: UnsafeMutableRawPointer?) {
        Players.trace("resource loader's delegate \(delegate == nil ? "taken away" : "set")")
        AVAssetResourceLoader.owners[objcObject]?.state?.loaderDelegate = delegate?.objcObject
    }

    @ObjCMethod("delegate")
    func delegate() -> NSObject? { AVAssetResourceLoader.owners[objcObject]?.state?.loaderDelegate.map { NSObject($0) } }

    @ObjCMethod("delegateQueue") func delegateQueue() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("preloadsEligibleContentKeys") func preloadsEligibleContentKeys() -> Bool { false }
    @ObjCMethod("setPreloadsEligibleContentKeys:") func setPreloadsEligibleContentKeys(_ preloads: Bool) {}
}

/// One request made of a resource loader's delegate: its loading request,
/// and the URL request, content information request and data request that
/// one gives.
final class LoadingState {
    var url: NSObject?
    var offset: Int64 = 0
    var length = 0
    var received = 0
    var contentType: String?
    var contentLength: Int64 = 0
    var byteRangeAccess = false
    var failed = false
    /// Where the bytes go; nowhere for the first request, which asks what
    /// the resource is.
    var file: UnsafeMutablePointer<FILE>?
    var urlRequest: NSObject?
    var information: NSObject?
    var data: NSObject?

    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)
    private var finished = false

    init() {
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(condition, nil)
    }

    deinit {
        pthread_cond_destroy(condition)
        pthread_mutex_destroy(mutex)
        condition.deallocate()
        mutex.deallocate()
    }

    func finish(failed: Bool) {
        pthread_mutex_lock(mutex)
        if failed { self.failed = true }
        finished = true
        pthread_cond_broadcast(condition)
        pthread_mutex_unlock(mutex)
    }

    var isFinished: Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return finished
    }

    /// Waits for the delegate to finish the request, when it answers from
    /// another thread; false if it hadn't in `seconds`.
    func waitUntilFinished(seconds: Int) -> Bool {
        var deadline = timespec()
        clock_gettime(CLOCK_REALTIME, &deadline)
        deadline.tv_sec += seconds
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        while !finished {
            if pthread_cond_timedwait(condition, mutex, &deadline) != 0 { break }
        }
        return finished
    }
}

enum Loading {
    /// A request's state, by any of its four objects.
    static let states = StateTable<LoadingState>()
}

@ObjCClass("AVAssetResourceLoadingRequest")
open class AVAssetResourceLoadingRequest: NSObject {
    static func make(url: NSObject, offset: Int64, length: Int, information: Bool, file: UnsafeMutablePointer<FILE>?) -> AVAssetResourceLoadingRequest {
        let state = LoadingState()
        (state.url, state.offset, state.length, state.file) = (url, offset, length, file)
        let request = NSObject(objCClass.pointer).newInstance().unsafeCast(to: AVAssetResourceLoadingRequest.self)
        let urlRequest = NSObject(ResourceURLRequest.objCClass.pointer).newInstance()
        let data = NSObject(AVAssetResourceLoadingDataRequest.objCClass.pointer).newInstance()
        (state.urlRequest, state.data) = (urlRequest, data)
        if information { state.information = NSObject(AVAssetResourceLoadingContentInformationRequest.objCClass.pointer).newInstance() }
        for object in [request, urlRequest, data, state.information].compactMap({ $0 }) { Loading.states.set(object.objcObject, state) }
        return request
    }

    var loading: LoadingState? { Loading.states[objcObject] }

    /// Has the delegate answer the request; false if it won't, or fails.
    func send(to delegate: NSObject, loader: NSObject) -> Bool {
        guard let state = loading, delegate.sendResourceLoader(loader, shouldWaitForLoadingOfRequestedResource: self) else { return false }
        return state.waitUntilFinished(seconds: 30) && !state.failed
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        // The others go with this one.
        if let state = loading { (state.urlRequest, state.information, state.data) = (nil, nil, nil) }
        Loading.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetResourceLoadingRequest.objCClass.pointer)
    }

    @ObjCMethod("request") func request() -> NSObject? { loading?.urlRequest }
    @ObjCMethod("contentInformationRequest") func contentInformationRequest() -> NSObject? { loading?.information }
    @ObjCMethod("dataRequest") func dataRequest() -> NSObject? { loading?.data }
    @ObjCMethod("isFinished") func isFinished() -> Bool { loading?.isFinished ?? true }
    @ObjCMethod("isCancelled") func isCancelled() -> Bool { false }
    @ObjCMethod("response") func response() -> NSObject? { nil }
    @ObjCMethod("redirect") func redirect() -> NSObject? { nil }
    @ObjCMethod("finishLoading") func finishLoading() { loading?.finish(failed: false) }
    @ObjCMethod("finishLoadingWithError:") func finishLoading(error: NSObject?) { loading?.finish(failed: true) }
}

/// The NSURLRequest of a loading request: its URL, which is what a
/// delegate reads of it.
@ObjCClass("__PerryAVResourceURLRequest")
open class ResourceURLRequest: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        Loading.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: ResourceURLRequest.objCClass.pointer)
    }

    @ObjCMethod("URL") func url() -> NSObject? { Loading.states[objcObject]?.url }
    @ObjCMethod("HTTPMethod") func httpMethod() -> String { "GET" }
    @ObjCMethod("allHTTPHeaderFields") func allHTTPHeaderFields() -> NSObject? { nil }
    @ObjCMethod("valueForHTTPHeaderField:") func value(forHTTPHeaderField field: String?) -> String? { nil }
}

@ObjCClass("AVAssetResourceLoadingContentInformationRequest")
open class AVAssetResourceLoadingContentInformationRequest: NSObject {
    var loading: LoadingState? { Loading.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        Loading.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetResourceLoadingContentInformationRequest.objCClass.pointer)
    }

    @ObjCMethod("contentType") func contentType() -> String? { loading?.contentType }
    @ObjCMethod("setContentType:") func setContentType(_ type: String?) { loading?.contentType = type }
    @ObjCMethod("contentLength") func contentLength() -> Int64 { loading?.contentLength ?? 0 }
    @ObjCMethod("setContentLength:") func setContentLength(_ length: Int64) { loading?.contentLength = length }
    @ObjCMethod("isByteRangeAccessSupported") func isByteRangeAccessSupported() -> Bool { loading?.byteRangeAccess ?? false }
    @ObjCMethod("setByteRangeAccessSupported:") func setByteRangeAccessSupported(_ supported: Bool) { loading?.byteRangeAccess = supported }
}

@ObjCClass("AVAssetResourceLoadingDataRequest")
open class AVAssetResourceLoadingDataRequest: NSObject {
    var loading: LoadingState? { Loading.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        Loading.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAssetResourceLoadingDataRequest.objCClass.pointer)
    }

    @ObjCMethod("requestedOffset") func requestedOffset() -> Int64 { loading?.offset ?? 0 }
    @ObjCMethod("requestedLength") func requestedLength() -> Int { loading?.length ?? 0 }
    @ObjCMethod("requestsAllDataToEndOfResource") func requestsAllDataToEndOfResource() -> Bool { false }
    @ObjCMethod("currentOffset") func currentOffset() -> Int64 { (loading?.offset ?? 0) + Int64(loading?.received ?? 0) }

    @ObjCMethod("respondWithData:")
    func respond(with data: NSData?) {
        guard let state = loading, let data else { return }
        let length = data.length()
        if let file = state.file, let bytes = data.bytes(), length > 0, fwrite(bytes, 1, length, file) != length { state.failed = true }
        state.received += length
    }
}

/// Reading a resource through its loader's delegate.
enum AssetLoading {
    nonisolated(unsafe) private static var count = 0
    private static let lock = Lock()

    /// What GStreamer plays for the asset: its URL, or the file its
    /// loader's delegate filled.
    static func uri(for state: AssetState) -> String? {
        guard let url = state.url?.unsafeCast(to: NSURL.self) else { return nil }
        let scheme = url.scheme()?.lowercased() ?? ""
        if ["file", "http", "https"].contains(scheme) { return url.absoluteString() }
        return fetch(state, url: url).map { "file://" + $0 }
    }

    private static func fetch(_ state: AssetState, url: NSObject) -> String? {
        guard let loader = state.loader, let delegate = state.loaderDelegate.map({ NSObject($0) }),
              delegate.responds(to: "resourceLoader:shouldWaitForLoadingOfRequestedResource:") else { return nil }
        // What it is and how long, asked along with its first two bytes,
        // as AVFoundation asks.
        Players.trace("asking the asset's resource loader what it is")
        let first = AVAssetResourceLoadingRequest.make(url: url, offset: 0, length: 2, information: true, file: nil)
        guard first.send(to: delegate, loader: loader), let length = first.loading?.contentLength, length > 0 else {
            Players.trace("the asset's resource loader gave nothing")
            return nil
        }
        Players.trace("the resource is \(first.loading?.contentType ?? "of no type"), \(length) bytes")
        let directory = getenv("PERRY_TMP").map { String(cString: $0) } ?? "/tmp"
        mkdir(directory, 0o755)
        let number = lock.withLock { () -> Int in
            count += 1
            return count
        }
        let path = "\(directory)/perry-asset-\(getpid())-\(number)"
        guard let file = fopen(path, "wb") else { return nil }
        // No more is asked for than there is: a delegate may wait for
        // bytes past the end.
        var offset: Int64 = 0
        while offset < length {
            let request = AVAssetResourceLoadingRequest.make(url: url, offset: offset, length: Int(min(length - offset, 4 << 20)),
                                                             information: false, file: file)
            guard request.send(to: delegate, loader: loader), let received = request.loading?.received, received > 0 else { break }
            offset += Int64(received)
        }
        fclose(file)
        guard offset >= length else {
            unlink(path)
            return nil
        }
        Players.trace("asset's \(length) bytes read through its resource loader")
        (state.temporaryPath, state.byteCount) = (path, Int(length))
        return path
    }
}

/// Work on a thread of its own.
enum Background {
    private final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    static func run(_ body: @escaping () -> Void) {
        let work = Unmanaged.passRetained(Work(body)).toOpaque()
        var thread = pthread_t()
        let started = pthread_create(&thread, nil, { raw in
            if let raw { Unmanaged<Work>.fromOpaque(raw).takeRetainedValue().body() }
            return nil
        }, work)
        if started == 0 {
            pthread_detach(thread)
        } else {
            Unmanaged<Work>.fromOpaque(work).takeRetainedValue().body()
        }
    }
}

// MARK: - Constants

/// File types (their uniform type identifiers), codecs, export presets
/// and the error domain. Programs read them as they load: Unity's video
/// code keeps AVVideoCodecHEVC, a weak import it does not check, from a
/// static initializer, and Leo's Fortune gives AVFileTypeAppleM4A as a
/// player's file type hint.
@ObjCConstants
enum AssetConstants {
    static let AVVideoCodecHEVC = "hvc1"
    static let AVFileTypeMPEG4 = "public.mpeg-4"
    static let AVFileTypeAppleM4A = "com.apple.m4a-audio"
    static let AVFileTypeAppleM4V = "com.apple.m4v-video"
    static let AVFileTypeQuickTimeMovie = "com.apple.quicktime-movie"
    static let AVFileTypeMPEGLayer3 = "public.mp3"
    static let AVFileTypeWAVE = "com.microsoft.waveform-audio"
    static let AVFileTypeAIFF = "public.aiff-audio"
    static let AVFileTypeAIFC = "public.aifc-audio"
    static let AVFileTypeCoreAudioFormat = "com.apple.coreaudio-format"
    static let AVFileTypeAC3 = "public.ac3-audio"
    static let AVFileTypeAMR = "org.3gpp.adaptive-multi-rate-audio"
    static let AVFileType3GPP = "public.3gpp"
    static let AVAssetExportPresetHighestQuality = "AVAssetExportPresetHighestQuality"
    static let AVAssetExportPresetPassthrough = "AVAssetExportPresetPassthrough"
    static let AVFoundationErrorDomain = "AVFoundationErrorDomain"
}
