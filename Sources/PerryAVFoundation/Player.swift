import Glibc
import PerryObjCInterop

// AVPlayer and AVPlayerItem, playing through GStreamer. A playing player's
// frames are pulled on the main queue sixty times a second, for a view
// (AVPlayerViewController's, in UIKit) to show; when its item ends, or
// can't play, it posts AVPlayerItemDidPlayToEndTimeNotification for the
// item, as AVFoundation does.

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCMethod("absoluteString") func absoluteString() -> String?
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
}

// MARK: - AVPlayerItem

final class PlayerItemState {
    var url: NSObject?
    var pipeline: Pipeline?
    /// Whether making a pipeline was tried (and so whether nil means it
    /// can't play).
    var prepared = false
    var finished = false
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
        AVPlayerItem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVPlayerItem.objCClass.pointer)
    }

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
        guard state.prepared else { return 0 }
        return state.pipeline == nil ? 2 : 1
    }

    @ObjCMethod("URL") func url() -> NSObject? { item.url }
    @ObjCMethod("asset") func asset() -> NSObject? { nil }
    @ObjCMethod("error") func error() -> NSObject? { nil }
    @ObjCMethod("isPlaybackLikelyToKeepUp") func isPlaybackLikelyToKeepUp() -> Bool { true }
    @ObjCMethod("isPlaybackBufferEmpty") func isPlaybackBufferEmpty() -> Bool { false }
    @ObjCMethod("isPlaybackBufferFull") func isPlaybackBufferFull() -> Bool { true }

    /// The ranges buffered and seekable, as NSValues of CMTimeRanges: none
    /// reported, as a local file needs no buffering.
    @ObjCMethod("loadedTimeRanges") func loadedTimeRanges() -> NSArray { NSArray.empty() }
    @ObjCMethod("seekableTimeRanges") func seekableTimeRanges() -> NSArray { NSArray.empty() }
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
        return player
    }

    @ObjCMethod("initWithURL:")
    func initialize(url: NSObject?) -> Self {
        player.item = AVPlayerItem.make(AVPlayerItem.objCClass, url: url)
        return self
    }

    @ObjCMethod("initWithPlayerItem:")
    func initialize(item: AVPlayerItem?) -> Self {
        player.item = item
        return self
    }

    @ObjCMethod("currentItem") func currentItem() -> AVPlayerItem? { player.item }

    @ObjCMethod("replaceCurrentItemWithPlayerItem:")
    func replaceCurrentItem(_ item: AVPlayerItem?) {
        let playing = player.rate != 0
        player.item?.pipeline?.pause()
        player.item = item
        player.frame = VideoFrame()
        if playing { play() }
    }

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
        if pipeline.pullFrame(into: &state.frame), state.frame.number % 30 == 1 {
            Players.trace("frame \(state.frame.number) \(state.frame.width)x\(state.frame.height)")
        }
        if pipeline.finished() {
            finish(item)
            return false
        }
        return true
    }

    private func finish(_ item: AVPlayerItem) {
        Players.trace("item finished after \(player.frame.number) frames")
        player.rate = 0
        item.pipeline?.pause()
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
        mainQueue = lookup(library, "__dispatch_main_q")
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
