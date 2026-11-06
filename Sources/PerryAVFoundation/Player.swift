import CPerryGeometry
import CPerryMedia
import Glibc
import PerryObjCInterop

// AVPlayer and AVPlayerItem, playing through GStreamer. A playing player's
// frames are pulled on the main queue sixty times a second, for a view
// (AVPlayerViewController's, in UIKit) to show, unless its item has a video
// output, which then pulls them when the program asks for them; when its
// item ends, or can't play, it posts
// AVPlayerItemDidPlayToEndTimeNotification for the item, as AVFoundation
// does. An item is made with a URL, or with an asset (Assets.swift), whose
// pipeline it plays; one made with an asset becomes ready to play, telling
// those observing its status, once a player has it.

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCMethod("absoluteString") func absoluteString() -> String?
    @ObjCMethod("scheme") func scheme() -> String?
}

extension NSObject {
    @ObjCMethod("willChangeValueForKey:") func sendWillChangeValue(forKey key: String)
    @ObjCMethod("didChangeValueForKey:") func sendDidChangeValue(forKey key: String)
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCClassMethod("array") static func empty() -> NSArray
}

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> NSNotificationCenter
    @ObjCMethod("postNotificationName:object:userInfo:") func post(name: String, object: NSObject?, userInfo: NSObject?)
}

@ObjCConstants
enum PlayerConstants {
    static let AVPlayerItemDidPlayToEndTimeNotification = "AVPlayerItemDidPlayToEndTimeNotification"
    static let AVPlayerItemFailedToPlayToEndTimeNotification = "AVPlayerItemFailedToPlayToEndTimeNotification"
    static let AVPlayerItemTimeJumpedNotification = "AVPlayerItemTimeJumpedNotification"
    static let AVPlayerItemPlaybackStalledNotification = "AVPlayerItemPlaybackStalledNotification"
    static let AVPlayerItemNewAccessLogEntryNotification = "AVPlayerItemNewAccessLogEntryNotification"
    static let AVPlayerItemNewErrorLogEntryNotification = "AVPlayerItemNewErrorLogEntryNotification"
    static let AVPlayerItemFailedToPlayToEndTimeErrorKey = "AVPlayerItemFailedToPlayToEndTimeErrorKey"
    static let AVLayerVideoGravityResizeAspect = "AVLayerVideoGravityResizeAspect"
    static let AVLayerVideoGravityResizeAspectFill = "AVLayerVideoGravityResizeAspectFill"
    static let AVLayerVideoGravityResize = "AVLayerVideoGravityResize"
    // How a player keeps pitch when its rate changes: weak imports that
    // programs read without a check.
    static let AVAudioTimePitchAlgorithmLowQualityZeroLatency = "LowQualityZeroLatency"
    static let AVAudioTimePitchAlgorithmTimeDomain = "TimeDomain"
    static let AVAudioTimePitchAlgorithmSpectral = "Spectral"
    static let AVAudioTimePitchAlgorithmVarispeed = "Varispeed"
    static let AVURLAssetPreferPreciseDurationAndTimingKey = "AVURLAssetPreferPreciseDurationAndTimingKey"
}

// MARK: - AVPlayerItem

final class PlayerItemState {
    var url: NSObject?
    /// The asset the item was made with, whose pipeline it plays.
    var asset: AVAsset?
    var pipeline: Pipeline?
    /// Whether making a pipeline was tried (and so whether nil means it
    /// can't play).
    var prepared = false
    var finished = false
    /// AVPlayerItemStatus for an item made with an asset: unknown until a
    /// player has it.
    var status = 0
    /// Its video outputs, which pull its frames; not retained beyond the
    /// array.
    var outputs: [NSObject] = []
    var tracks: [NSObject]?
    var audioMix: NSObject?
    var audioTimePitchAlgorithm = PlayerConstants.AVAudioTimePitchAlgorithmLowQualityZeroLatency
}

@ObjCClass("AVPlayerItem")
open class AVPlayerItem: NSObject {
    static let states = StateTable<PlayerItemState>()
    var item: PlayerItemState {
        if let state = AVPlayerItem.states[objcObject] { return state }
        let state = PlayerItemState()
        AVPlayerItem.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        for output in AVPlayerItem.states[objcObject]?.outputs ?? [] { AVPlayerItemOutput.states[output.objcObject]?.item = nil }
        AVPlayerItem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVPlayerItem.objCClass.pointer)
    }

    @ObjCClassMethod("playerItemWithAsset:")
    static func make(_ cls: ObjCClass, asset: AVAsset?) -> AVPlayerItem {
        let item = NSObject(cls.pointer).newInstance().unsafeCast(to: AVPlayerItem.self)
        item.item.asset = asset
        return item
    }

    @ObjCMethod("initWithAsset:")
    func initialize(asset: AVAsset?) -> Self {
        item.asset = asset
        return self
    }

    @ObjCMethod("initWithAsset:automaticallyLoadedAssetKeys:")
    func initialize(asset: AVAsset?, automaticallyLoadedAssetKeys keys: NSObject?) -> Self { initialize(asset: asset) }

    @ObjCClassMethod("playerItemWithURL:")
    static func make(_ cls: ObjCClass, url: NSObject?) -> AVPlayerItem {
        let item = NSObject(cls.pointer).newInstance().unsafeCast(to: AVPlayerItem.self)
        item.item.url = url
        return item
    }

    @ObjCMethod("initWithURL:")
    func initialize(url: NSObject?) -> Self {
        item.url = url
        return self
    }

    /// The URL's pipeline, made the first time it's wanted; nil when the
    /// item can't play.
    var pipeline: Pipeline? {
        let state = item
        if let asset = state.asset { return asset.load().pipeline }
        if !state.prepared {
            state.prepared = true
            if let gst = GStreamer.shared, let uri = state.url?.unsafeCast(to: NSURL.self).absoluteString() {
                state.pipeline = Pipeline(uri: uri, gst: gst)
            }
        }
        return state.pipeline
    }

    /// AVPlayerItemStatus: unknown 0, ready to play 1, failed 2.
    @ObjCMethod("status")
    func status() -> Int {
        let state = item
        if state.asset != nil { return state.status }
        guard state.prepared else { return 0 }
        return state.pipeline == nil ? 2 : 1
    }

    /// An item made with an asset, once a player has it: ready to play, or
    /// failed, as those observing its status are told.
    func becomeReady() {
        let state = item
        guard state.asset != nil, state.status == 0 else { return }
        let ready = pipeline != nil
        sendWillChangeValue(forKey: "status")
        state.status = ready ? 1 : 2
        sendDidChangeValue(forKey: "status")
        Players.trace("item \(ready ? "ready to play" : "failed")")
    }

    @ObjCMethod("URL") func url() -> NSObject? { item.url }
    @ObjCMethod("asset") func asset() -> NSObject? { item.asset }

    /// One AVPlayerItemTrack for each of the asset's tracks.
    @ObjCMethod("tracks")
    func tracks() -> NSObject {
        let state = item
        if state.tracks == nil {
            state.tracks = (state.asset?.trackObjects ?? []).map { assetTrack in
                let track = NSObject(AVPlayerItemTrack.objCClass.pointer).newInstance()
                let trackState = PlayerItemTrackState()
                trackState.assetTrack = assetTrack
                AVPlayerItemTrack.states.set(track.objcObject, trackState)
                return track
            }
        }
        return Arrays.of(state.tracks ?? [])
    }

    // MARK: Outputs

    @ObjCMethod("outputs") func outputs() -> NSObject { Arrays.of(item.outputs) }

    @ObjCMethod("addOutput:")
    func addOutput(_ output: NSObject?) {
        guard let output, !item.outputs.contains(where: { $0.objcObject == output.objcObject }) else { return }
        item.outputs.append(output)
        AVPlayerItemOutput.state(for: output.objcObject).item = objcObject
    }

    @ObjCMethod("removeOutput:")
    func removeOutput(_ output: NSObject?) {
        guard let output else { return }
        item.outputs.removeAll { $0.objcObject == output.objcObject }
        AVPlayerItemOutput.states[output.objcObject]?.item = nil
    }

    // MARK: Time

    @ObjCMethod("currentTime") func currentTime() -> CMTime { CMTime(seconds: item.asset == nil && !item.prepared ? 0 : pipeline?.position ?? 0) }

    @ObjCMethod("duration")
    func duration() -> CMTime {
        if let asset = item.asset { return asset.duration() }
        guard item.prepared, let duration = pipeline?.duration else { return CMTime(value: 0, timescale: 0, flags: CMTime.valid | CMTime.indefinite, epoch: 0) }
        return CMTime(seconds: duration)
    }

    @ObjCMethod("presentationSize") func presentationSize() -> CGSize { item.asset?.naturalSize() ?? CGSize(width: 0, height: 0) }

    /// Seeks land on the frame GStreamer picks; the tolerances are not
    /// looked at. The handler is called on the main queue.
    func seek(to time: CMTime, completionHandler: ObjCBlock?) {
        if time.isNumeric { pipeline?.seek(to: time.seconds) }
        item.finished = false
        guard let completionHandler else { return }
        Players.onMain {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Bool) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, true)
        }
    }

    @ObjCMethod("seekToTime:") func seek(to time: CMTime) { seek(to: time, completionHandler: nil) }

    @ObjCMethod("seekToTime:completionHandler:")
    func seekTo(_ time: CMTime, completionHandler: ObjCBlock?) { seek(to: time, completionHandler: completionHandler) }

    @ObjCMethod("seekToTime:toleranceBefore:toleranceAfter:")
    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) { seek(to: time, completionHandler: nil) }

    @ObjCMethod("seekToTime:toleranceBefore:toleranceAfter:completionHandler:")
    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: ObjCBlock?) {
        seek(to: time, completionHandler: completionHandler)
    }

    @ObjCMethod("cancelPendingSeeks") func cancelPendingSeeks() {}
    /// Frames are not stepped through one at a time.
    @ObjCMethod("canStepForward") func canStepForward() -> Bool { false }
    @ObjCMethod("canStepBackward") func canStepBackward() -> Bool { false }
    @ObjCMethod("stepByCount:") func step(byCount count: Int) {}
    @ObjCMethod("canPlayFastForward") func canPlayFastForward() -> Bool { false }
    @ObjCMethod("canPlayReverse") func canPlayReverse() -> Bool { false }

    // MARK: Sound

    /// An audio mix is kept and given back; the sound plays as it is.
    @ObjCMethod("audioMix") func audioMix() -> NSObject? { item.audioMix }
    @ObjCMethod("setAudioMix:") func setAudioMix(_ mix: NSObject?) { item.audioMix = mix }
    @ObjCMethod("audioTimePitchAlgorithm") func audioTimePitchAlgorithm() -> String { item.audioTimePitchAlgorithm }
    @ObjCMethod("setAudioTimePitchAlgorithm:")
    func setAudioTimePitchAlgorithm(_ algorithm: String?) {
        item.audioTimePitchAlgorithm = algorithm ?? PlayerConstants.AVAudioTimePitchAlgorithmLowQualityZeroLatency
    }
    @ObjCMethod("error") func error() -> NSObject? { nil }
    @ObjCMethod("isPlaybackLikelyToKeepUp") func isPlaybackLikelyToKeepUp() -> Bool { true }
    @ObjCMethod("isPlaybackBufferEmpty") func isPlaybackBufferEmpty() -> Bool { false }
    @ObjCMethod("isPlaybackBufferFull") func isPlaybackBufferFull() -> Bool { true }

    /// The ranges buffered and seekable, as NSValues of CMTimeRanges: none
    /// reported, as a local file needs no buffering.
    @ObjCMethod("loadedTimeRanges") func loadedTimeRanges() -> NSArray { NSArray.empty() }
    @ObjCMethod("seekableTimeRanges") func seekableTimeRanges() -> NSArray { NSArray.empty() }
}

// MARK: - AVPlayerItemTrack

final class PlayerItemTrackState {
    var assetTrack: NSObject?
    var enabled = true
}

@ObjCClass("AVPlayerItemTrack")
open class AVPlayerItemTrack: NSObject {
    static let states = StateTable<PlayerItemTrackState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        AVPlayerItemTrack.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVPlayerItemTrack.objCClass.pointer)
    }

    @ObjCMethod("assetTrack") func assetTrack() -> NSObject? { AVPlayerItemTrack.states[objcObject]?.assetTrack }
    /// Kept and given back: every track plays.
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { AVPlayerItemTrack.states[objcObject]?.enabled ?? true }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { AVPlayerItemTrack.states[objcObject]?.enabled = enabled }
    @ObjCMethod("currentVideoFrameRate") func currentVideoFrameRate() -> Float { 0 }
}

// MARK: - Audio mixes

// What a program builds to set a track's volume or tap its audio: kept
// and given back. Sound plays as GStreamer plays it, and an asset has no
// audio tracks to make parameters for.

final class AudioMixState {
    var inputParameters: NSObject?
    var track: NSObject?
    var tap: UnsafeMutableRawPointer?
}

@ObjCClass("AVAudioMix")
open class AVAudioMix: NSObject {
    static let states = StateTable<AudioMixState>()
    var mix: AudioMixState {
        if let state = AVAudioMix.states[objcObject] { return state }
        let state = AudioMixState()
        AVAudioMix.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAudioMix.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAudioMix.objCClass.pointer)
    }

    @ObjCMethod("inputParameters") func inputParameters() -> NSObject { mix.inputParameters ?? Arrays.of([]) }
}

@ObjCClass("AVMutableAudioMix")
open class AVMutableAudioMix: AVAudioMix {
    @ObjCClassMethod("audioMix")
    static func make(_ cls: ObjCClass) -> AVMutableAudioMix { NSObject(cls.pointer).newInstance().unsafeCast(to: AVMutableAudioMix.self) }

    @ObjCMethod("setInputParameters:") func setInputParameters(_ parameters: NSObject?) { mix.inputParameters = parameters }
}

@ObjCClass("AVAudioMixInputParameters")
open class AVAudioMixInputParameters: NSObject {
    static let states = StateTable<AudioMixState>()
    var parameters: AudioMixState {
        if let state = AVAudioMixInputParameters.states[objcObject] { return state }
        let state = AudioMixState()
        AVAudioMixInputParameters.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAudioMixInputParameters.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAudioMixInputParameters.objCClass.pointer)
    }

    @ObjCMethod("trackID") func trackID() -> Int32 { 1 }
    @ObjCMethod("audioTapProcessor") func audioTapProcessor() -> UnsafeMutableRawPointer? { parameters.tap }
    @ObjCMethod("audioTimePitchAlgorithm") func audioTimePitchAlgorithm() -> String? { nil }
}

@ObjCClass("AVMutableAudioMixInputParameters")
open class AVMutableAudioMixInputParameters: AVAudioMixInputParameters {
    @ObjCClassMethod("audioMixInputParameters")
    static func make(_ cls: ObjCClass) -> AVMutableAudioMixInputParameters {
        NSObject(cls.pointer).newInstance().unsafeCast(to: AVMutableAudioMixInputParameters.self)
    }

    @ObjCClassMethod("audioMixInputParametersWithTrack:")
    static func make(_ cls: ObjCClass, track: NSObject?) -> AVMutableAudioMixInputParameters {
        let parameters = make(cls)
        parameters.parameters.track = track
        return parameters
    }

    @ObjCMethod("setTrackID:") func setTrackID(_ id: Int32) {}
    @ObjCMethod("setAudioTapProcessor:") func setAudioTapProcessor(_ tap: UnsafeMutableRawPointer?) { parameters.tap = tap }
    @ObjCMethod("setAudioTimePitchAlgorithm:") func setAudioTimePitchAlgorithm(_ algorithm: String?) {}
    @ObjCMethod("setVolume:atTime:") func setVolume(_ volume: Float, at time: CMTime) {}
    @ObjCMethod("setVolumeRampFromStartVolume:toEndVolume:timeRange:")
    func setVolumeRamp(fromStartVolume start: Float, toEndVolume end: Float, timeRange: CMTimeRange) {}
}

// MARK: - AVPlayer

final class AVPlayerState {
    var item: AVPlayerItem?
    var rate: Float = 0
    var volume: Float = 1
    var muted = false
    /// AVPlayerActionAtItemEnd: advance 0, pause 1, none 2.
    var actionAtItemEnd = 1
    var frame = VideoFrame()
}

@ObjCClass("AVPlayer")
open class AVPlayer: NSObject {
    static let states = StateTable<AVPlayerState>()
    var player: AVPlayerState {
        if let state = AVPlayer.states[objcObject] { return state }
        let state = AVPlayerState()
        AVPlayer.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Players.stop(objcObject)
        AVPlayer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVPlayer.objCClass.pointer)
    }

    @ObjCClassMethod("playerWithURL:")
    static func make(_ cls: ObjCClass, url: NSObject?) -> AVPlayer {
        let player = NSObject(cls.pointer).newInstance().unsafeCast(to: AVPlayer.self)
        player.player.item = AVPlayerItem.make(AVPlayerItem.objCClass, url: url)
        return player
    }

    @ObjCClassMethod("playerWithPlayerItem:")
    static func make(_ cls: ObjCClass, item: AVPlayerItem?) -> AVPlayer {
        let player = NSObject(cls.pointer).newInstance().unsafeCast(to: AVPlayer.self)
        player.player.item = item
        AVPlayer.ready(item)
        return player
    }

    /// Has an item made with an asset become ready, from the main queue,
    /// as an item becomes ready some time after a player takes it.
    static func ready(_ item: AVPlayerItem?) {
        guard let item, item.item.asset != nil, item.item.status == 0 else { return }
        Players.onMain { item.becomeReady() }
    }

    @ObjCMethod("initWithURL:")
    func initialize(url: NSObject?) -> Self {
        player.item = AVPlayerItem.make(AVPlayerItem.objCClass, url: url)
        return self
    }

    @ObjCMethod("initWithPlayerItem:")
    func initialize(item: AVPlayerItem?) -> Self {
        player.item = item
        AVPlayer.ready(item)
        return self
    }

    @ObjCMethod("currentItem") func currentItem() -> AVPlayerItem? { player.item }

    @ObjCMethod("replaceCurrentItemWithPlayerItem:")
    func replaceCurrentItem(_ item: AVPlayerItem?) {
        let playing = player.rate != 0
        if player.item?.objcObject != item?.objcObject { player.item?.pipeline?.pause() }
        player.item = item
        player.frame = VideoFrame()
        AVPlayer.ready(item)
        if playing { play() }
    }

    // MARK: Time

    @ObjCMethod("currentTime") func currentTime() -> CMTime { player.item?.currentTime() ?? .zero }
    @ObjCMethod("seekToTime:") func seek(to time: CMTime) { player.item?.seek(to: time, completionHandler: nil) }

    @ObjCMethod("seekToTime:completionHandler:")
    func seekTo(_ time: CMTime, completionHandler: ObjCBlock?) { player.item?.seek(to: time, completionHandler: completionHandler) }

    @ObjCMethod("seekToTime:toleranceBefore:toleranceAfter:")
    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) { player.item?.seek(to: time, completionHandler: nil) }

    @ObjCMethod("seekToTime:toleranceBefore:toleranceAfter:completionHandler:")
    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: ObjCBlock?) {
        if let item = player.item {
            item.seek(to: time, completionHandler: completionHandler)
        } else if let completionHandler {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Bool) -> Void
            completionHandler.function(as: Invoke.self)(completionHandler.object, false)
        }
    }

    @ObjCMethod("playImmediatelyAtRate:") func playImmediately(atRate rate: Float) { setRate(rate) }
    /// AVPlayerTimeControlStatus: paused 0, playing 2.
    @ObjCMethod("timeControlStatus") func timeControlStatus() -> Int { player.rate == 0 ? 0 : 2 }
    @ObjCMethod("automaticallyWaitsToMinimizeStalling") func automaticallyWaitsToMinimizeStalling() -> Bool { false }
    @ObjCMethod("setAutomaticallyWaitsToMinimizeStalling:") func setAutomaticallyWaitsToMinimizeStalling(_ waits: Bool) {}

    @ObjCMethod("play") func play() { setRate(1) }
    @ObjCMethod("pause") func pause() { setRate(0) }
    @ObjCMethod("rate") func rate() -> Float { player.rate }

    /// Plays at any nonzero rate (at normal speed), or pauses.
    @ObjCMethod("setRate:")
    func setRate(_ rate: Float) {
        let state = player
        state.rate = rate
        Players.trace("rate \(rate) for \(state.item?.item.url.flatMap { $0.unsafeCast(to: NSURL.self).absoluteString() } ?? "no item")")
        guard let item = state.item else { return }
        if rate == 0 {
            item.pipeline?.pause()
            return
        }
        if let pipeline = item.pipeline {
            pipeline.set(volume: Double(state.volume), muted: state.muted)
            pipeline.play()
        }
        Players.start(objcObject)
    }

    @ObjCMethod("volume") func volume() -> Float { player.volume }
    @ObjCMethod("setVolume:")
    func setVolume(_ volume: Float) {
        player.volume = volume
        player.item?.item.pipeline?.set(volume: Double(volume), muted: player.muted)
    }

    @ObjCMethod("isMuted") func isMuted() -> Bool { player.muted }
    @ObjCMethod("setMuted:")
    func setMuted(_ muted: Bool) {
        player.muted = muted
        player.item?.item.pipeline?.set(volume: Double(player.volume), muted: muted)
    }

    @ObjCMethod("actionAtItemEnd") func actionAtItemEnd() -> Int { player.actionAtItemEnd }
    @ObjCMethod("setActionAtItemEnd:") func setActionAtItemEnd(_ action: Int) { player.actionAtItemEnd = action }
    /// AVPlayerStatus: ready to play 1, failed 2.
    @ObjCMethod("status") func status() -> Int { GStreamer.shared == nil ? 2 : 1 }
    @ObjCMethod("error") func error() -> NSObject? { nil }
    @ObjCMethod("allowsExternalPlayback") func allowsExternalPlayback() -> Bool { false }
    @ObjCMethod("setAllowsExternalPlayback:") func setAllowsExternalPlayback(_ allows: Bool) {}

    // MARK: Frames, for the view showing them

    @ObjCMethod("_perryVideoFrameNumber") func videoFrameNumber() -> UInt { player.frame.number }
    @ObjCMethod("_perryVideoFrameWidth") func videoFrameWidth() -> Int { player.frame.width }
    @ObjCMethod("_perryVideoFrameHeight") func videoFrameHeight() -> Int { player.frame.height }

    /// The frame's RGBA pixels, valid until the main queue next runs a pass.
    @ObjCMethod("_perryVideoFrameBytes")
    func videoFrameBytes() -> UnsafeRawPointer? {
        player.frame.pixels.withUnsafeBytes { $0.baseAddress }
    }

    /// Pulls a frame and checks for the end; false once it's stopped.
    func tick() -> Bool {
        let state = player
        guard state.rate != 0, let item = state.item else { return false }
        guard let pipeline = item.pipeline else {
            finish(item)
            return false
        }
        Players.ticks &+= 1
        if Players.tracing, Players.ticks % 60 == 1 {
            Players.trace("tick \(Players.ticks): position \(pipeline.position.map { "\($0)" } ?? "?") of \(pipeline.duration.map { "\($0)" } ?? "?"), sink \(pipeline.sink != nil)")
        }
        // An item's video output pulls its frames itself.
        if item.item.outputs.isEmpty, pipeline.pullFrame(into: &state.frame), state.frame.number % 30 == 1 {
            Players.trace("frame \(state.frame.number) \(state.frame.width)x\(state.frame.height)")
        }
        if pipeline.finished() {
            finish(item)
            return player.rate != 0
        }
        return true
    }

    /// The item played to its end: the player pauses, unless it was told
    /// to do nothing then (as a program that loops the item itself, by
    /// seeking when it hears of the end, tells it).
    private func finish(_ item: AVPlayerItem) {
        Players.trace("item finished after \(player.frame.number) frames")
        if player.actionAtItemEnd != 2 {
            player.rate = 0
            item.pipeline?.pause()
        }
        item.item.finished = true
        NSNotificationCenter.defaultCenter().post(name: PlayerConstants.AVPlayerItemDidPlayToEndTimeNotification, object: item, userInfo: nil)
    }
}

// MARK: - Players

/// The players playing, ticked on the main queue.
enum Players {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias DispatchAfter = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias DispatchTime = @convention(c) (UInt64, Int64) -> UInt64
    typealias DispatchAsync = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    nonisolated(unsafe) static var dispatchAsync: DispatchAsync?
    /// Work waiting for the main queue.
    nonisolated(unsafe) private static var waiting: [() -> Void] = []
    private static let waitingLock = Lock()
    nonisolated(unsafe) static var dispatchAfter: DispatchAfter?
    nonisolated(unsafe) static var dispatchTime: DispatchTime?
    nonisolated(unsafe) static var mainQueue: UnsafeMutableRawPointer?
    nonisolated(unsafe) private static var playing: [UnsafeMutableRawPointer] = []
    /// AVAudioPlayers playing, retained while they are.
    nonisolated(unsafe) private static var audioPlaying: [UnsafeMutableRawPointer] = []
    nonisolated(unsafe) private static var scheduled = false
    nonisolated(unsafe) static var ticks = 0

    nonisolated(unsafe) static let tracing = getenv("PERRY_AVFOUNDATION_TRACE") != nil

    /// With PERRY_AVFOUNDATION_TRACE set, what players do.
    static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        GStreamer.log(message())
    }

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) {
        let library = "/usr/lib/system/libdispatch.dylib"
        dispatchAfter = lookup(library, "_dispatch_after_f").map { unsafeBitCast($0, to: DispatchAfter.self) }
        dispatchTime = lookup(library, "_dispatch_time").map { unsafeBitCast($0, to: DispatchTime.self) }
        dispatchAsync = lookup(library, "_dispatch_async_f").map { unsafeBitCast($0, to: DispatchAsync.self) }
        mainQueue = lookup(library, "__dispatch_main_q")
    }

    /// Runs `work` on the main queue, after what it already has to do.
    static func onMain(_ work: @escaping () -> Void) {
        guard let dispatchAsync, let mainQueue else {
            work()
            return
        }
        waitingLock.withLock { waiting.append(work) }
        dispatchAsync(mainQueue, nil) { _ in
            let work = Players.waitingLock.withLock { () -> [() -> Void] in
                defer { Players.waiting.removeAll() }
                return Players.waiting
            }
            for item in work { item() }
        }
    }

    static func start(_ player: UnsafeMutableRawPointer) {
        if !playing.contains(player) {
            playing.append(player)
            _ = ObjCRuntime.retain(player)
        }
        schedule()
    }

    static func stop(_ player: UnsafeMutableRawPointer) {
        playing.removeAll { $0 == player }
    }

    static func startAudio(_ player: UnsafeMutableRawPointer) {
        if !audioPlaying.contains(player) {
            audioPlaying.append(player)
            _ = ObjCRuntime.retain(player)
        }
        schedule()
    }

    static func stopAudio(_ player: UnsafeMutableRawPointer) {
        guard audioPlaying.contains(player) else { return }
        audioPlaying.removeAll { $0 == player }
        ObjCRuntime.release(player)
    }

    private static func schedule() {
        guard !scheduled, let dispatchAfter, let dispatchTime, let mainQueue else {
            if dispatchAfter == nil || dispatchTime == nil || mainQueue == nil { trace("no main queue to tick players on") }
            return
        }
        scheduled = true
        dispatchAfter(dispatchTime(0, 16_666_667), mainQueue, nil) { _ in
            Players.scheduled = false
            for object in Players.playing {
                let player = AVPlayer(objcObject: object, ownership: .retain)
                if !player.tick() {
                    Players.playing.removeAll { $0 == object }
                    ObjCRuntime.release(object)
                }
            }
            for object in Players.audioPlaying {
                let player = AVAudioPlayer(objcObject: object, ownership: .retain)
                if !player.tick() { Players.stopAudio(object) }
            }
            if !Players.playing.isEmpty || !Players.audioPlaying.isEmpty { Players.schedule() }
        }
    }
}
