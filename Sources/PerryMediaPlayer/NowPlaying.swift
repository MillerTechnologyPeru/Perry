import CPerryGeometry
import PerryObjCInterop

// MPNowPlayingInfoCenter and MPRemoteCommandCenter, with no lock screen, no
// Control Center and no headphone buttons: what an app puts in the info
// center is kept for it to read back, and the commands it enables take
// targets that nothing ever calls. An audio or video app sets all of them
// up when it starts playing.

/// MPNowPlayingInfoCenter: the media an app says is playing.
@ObjCClass("MPNowPlayingInfoCenter")
open class MPNowPlayingInfoCenter: NSObject {
    var info: NSObject? = nil
    var state = 0
    nonisolated(unsafe) static var shared = MPNowPlayingInfoCenter()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> MPNowPlayingInfoCenter { shared }

    @ObjCMethod("nowPlayingInfo") func nowPlayingInfo() -> NSObject? { info }
    @ObjCMethod("setNowPlayingInfo:") func setNowPlayingInfo(_ info: NSObject?) { self.info = info }
    /// MPNowPlayingPlaybackState: unknown 0, playing 1, paused 2, stopped 3, interrupted 4.
    @ObjCMethod("playbackState") func playbackState() -> Int { state }
    @ObjCMethod("setPlaybackState:") func setPlaybackState(_ state: Int) { self.state = state }
}

/// MPRemoteCommand: a command a remote control may send, which is never sent.
@ObjCClass("MPRemoteCommand")
open class MPRemoteCommand: NSObject {
    var enabled = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { self.enabled = enabled }

    @ObjCMethod("addTarget:action:") func addTarget(_ target: NSObject?, action: ObjCSelector?) {}
    /// The handler is kept by nothing; the command itself stands for it.
    @ObjCMethod("addTargetWithHandler:") func addTarget(handler: ObjCBlock?) -> NSObject { self }
    @ObjCMethod("removeTarget:") func removeTarget(_ target: NSObject?) {}
    @ObjCMethod("removeTarget:action:") func removeTarget(_ target: NSObject?, action: ObjCSelector?) {}
}

@ObjCClass("MPSkipIntervalCommand")
open class MPSkipIntervalCommand: MPRemoteCommand {
    var intervals: NSObject? = nil
    @ObjCMethod("preferredIntervals") func preferredIntervals() -> NSObject? { intervals }
    @ObjCMethod("setPreferredIntervals:") func setPreferredIntervals(_ intervals: NSObject?) { self.intervals = intervals }
}

@ObjCClass("MPChangePlaybackRateCommand")
open class MPChangePlaybackRateCommand: MPRemoteCommand {
    var rates: NSObject? = nil
    @ObjCMethod("supportedPlaybackRates") func supportedPlaybackRates() -> NSObject? { rates }
    @ObjCMethod("setSupportedPlaybackRates:") func setSupportedPlaybackRates(_ rates: NSObject?) { self.rates = rates }
}

@ObjCClass("MPChangePlaybackPositionCommand") open class MPChangePlaybackPositionCommand: MPRemoteCommand {}
@ObjCClass("MPSeekCommand") open class MPSeekCommand: MPRemoteCommand {}
@ObjCClass("MPFeedbackCommand")
open class MPFeedbackCommand: MPRemoteCommand {
    var active = false
    @ObjCMethod("isActive") func isActive() -> Bool { active }
    @ObjCMethod("setActive:") func setActive(_ active: Bool) { self.active = active }
    @ObjCMethod("localizedTitle") func localizedTitle() -> String? { nil }
    @ObjCMethod("setLocalizedTitle:") func setLocalizedTitle(_ title: String?) {}
}
@ObjCClass("MPRatingCommand") open class MPRatingCommand: MPRemoteCommand {}
@ObjCClass("MPChangeRepeatModeCommand") open class MPChangeRepeatModeCommand: MPRemoteCommand {}
@ObjCClass("MPChangeShuffleModeCommand") open class MPChangeShuffleModeCommand: MPRemoteCommand {}

/// What a remote command was sent with; no command is ever sent.
@ObjCClass("MPRemoteCommandEvent")
open class MPRemoteCommandEvent: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }
    @ObjCMethod("command") func command() -> NSObject? { nil }
    @ObjCMethod("timestamp") func timestamp() -> Double { 0 }
}

@ObjCClass("MPChangePlaybackPositionCommandEvent")
open class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent {
    @ObjCMethod("positionTime") func positionTime() -> Double { 0 }
}

@ObjCClass("MPSkipIntervalCommandEvent")
open class MPSkipIntervalCommandEvent: MPRemoteCommandEvent {
    @ObjCMethod("interval") func interval() -> Double { 0 }
}

@ObjCClass("MPChangePlaybackRateCommandEvent")
open class MPChangePlaybackRateCommandEvent: MPRemoteCommandEvent {
    @ObjCMethod("playbackRate") func playbackRate() -> Float { 1 }
}

/// MPRemoteCommandCenter: every command, disabled until the app enables it.
@ObjCClass("MPRemoteCommandCenter")
open class MPRemoteCommandCenter: NSObject {
    nonisolated(unsafe) static var shared = MPRemoteCommandCenter()

    let play = MPRemoteCommand()
    let pause = MPRemoteCommand()
    let stop = MPRemoteCommand()
    let togglePlayPause = MPRemoteCommand()
    let enableLanguageOption = MPRemoteCommand()
    let disableLanguageOption = MPRemoteCommand()
    let changePlaybackRate = MPChangePlaybackRateCommand()
    let seekBackward = MPSeekCommand()
    let seekForward = MPSeekCommand()
    let skipBackward = MPSkipIntervalCommand()
    let skipForward = MPSkipIntervalCommand()
    let previousTrack = MPRemoteCommand()
    let nextTrack = MPRemoteCommand()
    let changeRepeatMode = MPChangeRepeatModeCommand()
    let changeShuffleMode = MPChangeShuffleModeCommand()
    let changePlaybackPosition = MPChangePlaybackPositionCommand()
    let rating = MPRatingCommand()
    let like = MPFeedbackCommand()
    let dislike = MPFeedbackCommand()
    let bookmark = MPFeedbackCommand()

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedCommandCenter") static func sharedCommandCenter() -> MPRemoteCommandCenter { shared }

    @ObjCMethod("playCommand") func playCommand() -> MPRemoteCommand { play }
    @ObjCMethod("pauseCommand") func pauseCommand() -> MPRemoteCommand { pause }
    @ObjCMethod("stopCommand") func stopCommand() -> MPRemoteCommand { stop }
    @ObjCMethod("togglePlayPauseCommand") func togglePlayPauseCommand() -> MPRemoteCommand { togglePlayPause }
    @ObjCMethod("enableLanguageOptionCommand") func enableLanguageOptionCommand() -> MPRemoteCommand { enableLanguageOption }
    @ObjCMethod("disableLanguageOptionCommand") func disableLanguageOptionCommand() -> MPRemoteCommand { disableLanguageOption }
    @ObjCMethod("changePlaybackRateCommand") func changePlaybackRateCommand() -> MPChangePlaybackRateCommand { changePlaybackRate }
    @ObjCMethod("seekBackwardCommand") func seekBackwardCommand() -> MPSeekCommand { seekBackward }
    @ObjCMethod("seekForwardCommand") func seekForwardCommand() -> MPSeekCommand { seekForward }
    @ObjCMethod("skipBackwardCommand") func skipBackwardCommand() -> MPSkipIntervalCommand { skipBackward }
    @ObjCMethod("skipForwardCommand") func skipForwardCommand() -> MPSkipIntervalCommand { skipForward }
    @ObjCMethod("previousTrackCommand") func previousTrackCommand() -> MPRemoteCommand { previousTrack }
    @ObjCMethod("nextTrackCommand") func nextTrackCommand() -> MPRemoteCommand { nextTrack }
    @ObjCMethod("changeRepeatModeCommand") func changeRepeatModeCommand() -> MPChangeRepeatModeCommand { changeRepeatMode }
    @ObjCMethod("changeShuffleModeCommand") func changeShuffleModeCommand() -> MPChangeShuffleModeCommand { changeShuffleMode }
    @ObjCMethod("changePlaybackPositionCommand") func changePlaybackPositionCommand() -> MPChangePlaybackPositionCommand { changePlaybackPosition }
    @ObjCMethod("ratingCommand") func ratingCommand() -> MPRatingCommand { rating }
    @ObjCMethod("likeCommand") func likeCommand() -> MPFeedbackCommand { like }
    @ObjCMethod("dislikeCommand") func dislikeCommand() -> MPFeedbackCommand { dislike }
    @ObjCMethod("bookmarkCommand") func bookmarkCommand() -> MPFeedbackCommand { bookmark }
}

extension CGSize: ObjCScalar {
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
}

/// MPMediaItemArtwork: an image an app gives for what is playing, made
/// for a size on request; nothing here asks for it.
@ObjCClass("MPMediaItemArtwork")
open class MPMediaItemArtwork: NSObject {
    var provider: ObjCBlock? = nil

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithBoundsSize:requestHandler:")
    public required init(boundsSize: CGSize, requestHandler: ObjCBlock?) {
        super.init()
        provider = requestHandler
    }

    @ObjCMethod("imageWithSize:") func image(with size: CGSize) -> NSObject? { nil }
}

/// The keys of the info center's dictionary; their values are their names.
@ObjCConstants
enum NowPlayingConstants {
    static let MPNowPlayingInfoPropertyElapsedPlaybackTime = "MPNowPlayingInfoPropertyElapsedPlaybackTime"
    static let MPNowPlayingInfoPropertyPlaybackRate = "MPNowPlayingInfoPropertyPlaybackRate"
    static let MPNowPlayingInfoPropertyDefaultPlaybackRate = "MPNowPlayingInfoPropertyDefaultPlaybackRate"
    static let MPNowPlayingInfoPropertyPlaybackQueueIndex = "MPNowPlayingInfoPropertyPlaybackQueueIndex"
    static let MPNowPlayingInfoPropertyPlaybackQueueCount = "MPNowPlayingInfoPropertyPlaybackQueueCount"
    static let MPNowPlayingInfoPropertyChapterNumber = "MPNowPlayingInfoPropertyChapterNumber"
    static let MPNowPlayingInfoPropertyChapterCount = "MPNowPlayingInfoPropertyChapterCount"
    static let MPNowPlayingInfoPropertyIsLiveStream = "MPNowPlayingInfoPropertyIsLiveStream"
    static let MPNowPlayingInfoPropertyAssetURL = "MPNowPlayingInfoPropertyAssetURL"
    static let MPNowPlayingInfoPropertyMediaType = "MPNowPlayingInfoPropertyMediaType"
    static let MPNowPlayingInfoPropertyServiceIdentifier = "MPNowPlayingInfoPropertyServiceIdentifier"
    static let MPNowPlayingInfoPropertyExternalContentIdentifier = "MPNowPlayingInfoPropertyExternalContentIdentifier"
    static let MPNowPlayingInfoPropertyExternalUserProfileIdentifier = "MPNowPlayingInfoPropertyExternalUserProfileIdentifier"
    static let MPNowPlayingInfoPropertyCurrentPlaybackDate = "MPNowPlayingInfoPropertyCurrentPlaybackDate"
    static let MPNowPlayingInfoPropertyCurrentLanguageOptions = "MPNowPlayingInfoPropertyCurrentLanguageOptions"
    static let MPNowPlayingInfoPropertyAvailableLanguageOptions = "MPNowPlayingInfoPropertyAvailableLanguageOptions"
    static let MPNowPlayingInfoCollectionIdentifier = "MPNowPlayingInfoCollectionIdentifier"
}
