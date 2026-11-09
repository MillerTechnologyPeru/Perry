import Glibc
import PerryObjCInterop

// MediaPlayer, with no media library and nothing that plays movies: the
// names apps pass to the notification center and read from media items, a
// music player that has no songs, and movie players that skip their movie,
// so an app waiting for its intro goes on.

/// With PERRY_TRACE_MEDIA set, what an app asks of its players is reported.
private let tracing = getenv("PERRY_TRACE_MEDIA") != nil

private func trace(_ message: @autoclosure () -> String) {
    guard tracing else { return }
    let line = "perry: MediaPlayer: \(message())\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> NSNotificationCenter
    @ObjCMethod("postNotificationName:object:userInfo:") func post(name: String, object: NSObject?, userInfo: NSObject?)
}

@ObjCWrapper("UIView")
class UIView: NSObject {
    @ObjCClassMethod("new") static func new() -> UIView
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithInteger:") static func number(_ value: Int) -> NSNumber
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCClassMethod("dictionaryWithObject:forKey:") static func dictionary(object: NSObject, key: String) -> NSDictionary
}

/// MPMoviePlayerController, the player of iOS 2 to 8. Its movie is skipped:
/// it is ready as soon as the player is made, and playing it (by -play, or
/// by preparing it while it plays by itself, which it does unless told not
/// to) reports it finished, once, as if it had played to its end.
@ObjCClass("MPMoviePlayerController")
open class MPMoviePlayerController: NSObject {
    var contentURL: NSObject? = nil
    var playerView: UIView? = nil
    var autoplays = true
    var loaded = false
    var playing = false
    var skipped = false
    var finished = false

    /// Players that have played, kept for the rest of the run: apps release
    /// theirs when it finishes and may still send it -stop afterwards, which
    /// a real player, kept by MediaPlayer, survives.
    nonisolated(unsafe) static var played: [MPMoviePlayerController] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithContentURL:")
    public required init(contentURL: NSObject?) {
        super.init()
        self.contentURL = contentURL
        trace("movie player made")
        // iOS 2 and 3.0 load a movie as soon as its player is made, and say
        // when it is ready.
        later(ObjCSelector("_perryLoaded"))
    }

    /// The movie is "ready": what the oldest apps wait for before they play it.
    @ObjCMethod("_perryLoaded")
    func didLoad() {
        guard !loaded else { return }
        loaded = true
        trace("movie loaded: preload and load state notifications")
        let center = NSNotificationCenter.defaultCenter()
        center.post(name: MediaPlayerConstants.MPMoviePlayerContentPreloadDidFinishNotification, object: self, userInfo: nil)
        center.post(name: MediaPlayerConstants.MPMoviePlayerLoadStateDidChangeNotification, object: self, userInfo: nil)
    }

    @ObjCMethod("contentURL") func getContentURL() -> NSObject? { contentURL }
    @ObjCMethod("setContentURL:") func setContentURL(_ url: NSObject?) { contentURL = url }

    /// The view the movie would show in: an empty one, which apps size and
    /// put in their own.
    @ObjCMethod("view")
    func view() -> UIView {
        if let playerView { return playerView }
        let made = UIView.new()
        playerView = made
        return made
    }

    @ObjCMethod("backgroundView") func backgroundView() -> NSObject? { nil }

    @ObjCMethod("prepareToPlay")
    func prepareToPlay() {
        trace("prepareToPlay")
        if autoplays { play() }
    }

    @ObjCMethod("isPreparedToPlay") func isPreparedToPlay() -> Bool { true }
    @ObjCMethod("shouldAutoplay") func shouldAutoplay() -> Bool { autoplays }

    /// Playing by itself starts once the movie is ready, which is at once.
    @ObjCMethod("setShouldAutoplay:")
    func setShouldAutoplay(_ autoplay: Bool) {
        autoplays = autoplay
        if autoplay { play() }
    }

    @ObjCMethod("pause") func pause() { trace("pause") }

    @ObjCMethod("stop")
    func stop() {
        trace("stop")
        finish()
    }

    /// MPMoviePlaybackStatePlaying while it "plays"; always
    /// MPMovieLoadStatePlayable and MPMovieLoadStatePlaythroughOK.
    @ObjCMethod("playbackState") func playbackState() -> Int { playing ? 1 : 0 }
    @ObjCMethod("loadState") func loadState() -> UInt { 3 }
    @ObjCMethod("duration") func duration() -> Double { 0 }
    @ObjCMethod("playableDuration") func playableDuration() -> Double { 0 }
    @ObjCMethod("currentPlaybackTime") func currentPlaybackTime() -> Double { 0 }
    @ObjCMethod("setCurrentPlaybackTime:") func setCurrentPlaybackTime(_ time: Double) {}
    @ObjCMethod("currentPlaybackRate") func currentPlaybackRate() -> Float { 0 }
    @ObjCMethod("setCurrentPlaybackRate:") func setCurrentPlaybackRate(_ rate: Float) {}

    // What an app sets up before it plays; nothing is shown.
    @ObjCMethod("setControlStyle:") func setControlStyle(_ style: Int) { trace("setControlStyle: \(style)") }
    @ObjCMethod("setMovieControlMode:") func setMovieControlMode(_ mode: Int) {}
    @ObjCMethod("setScalingMode:") func setScalingMode(_ mode: Int) { trace("setScalingMode: \(mode)") }
    @ObjCMethod("setRepeatMode:") func setRepeatMode(_ mode: Int) {}
    @ObjCMethod("setFullscreen:") func setFullscreen(_ fullscreen: Bool) {}
    @ObjCMethod("setFullscreen:animated:") func setFullscreen(_ fullscreen: Bool, animated: Bool) {}
    @ObjCMethod("isFullscreen") func isFullscreen() -> Bool { false }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) {}
    @ObjCMethod("setUseApplicationAudioSession:") func setUseApplicationAudioSession(_ uses: Bool) {}
    @ObjCMethod("setMovieSourceType:") func setMovieSourceType(_ type: Int) {}
    @ObjCMethod("setInitialPlaybackTime:") func setInitialPlaybackTime(_ time: Double) {}
    @ObjCMethod("setEndPlaybackTime:") func setEndPlaybackTime(_ time: Double) {}
    @ObjCMethod("setOrientation:animated:") func setOrientation(_ orientation: Int, animated: Bool) {}

    /// Nothing plays: the movie has finished, which the app hears from the
    /// main run loop. Each movie is skipped once.
    @ObjCMethod("play")
    func play() {
        trace("play")
        guard !playing, !skipped else { return }
        playing = true
        skipped = true
        finished = false
        MPMoviePlayerController.played.append(self)
        later(ObjCSelector("_perryFinished"))
    }

    /// Sends itself the message from the main run loop, where a real player
    /// posts its notifications, whatever thread the app uses it from: a
    /// game's own thread may run no run loop.
    private func later(_ selector: ObjCSelector) {
        performSelectorOnMainThread(selector, with: nil, waitUntilDone: false)
    }

    @ObjCMethod("performSelectorOnMainThread:withObject:waitUntilDone:")
    func performSelectorOnMainThread(_ selector: ObjCSelector, with object: NSObject?, waitUntilDone wait: Bool)

    @ObjCMethod("_perryFinished")
    func finish() {
        guard !finished else { return }
        finished = true
        playing = false
        trace("movie finished: playback did finish notification")
        // MPMovieFinishReasonPlaybackEnded: an app may play a movie it does
        // not let the user skip again when told the user left it.
        let reason = NSDictionary.dictionary(
            object: NSNumber.number(0), key: MediaPlayerConstants.MPMoviePlayerPlaybackDidFinishReasonUserInfoKey)
        NSNotificationCenter.defaultCenter().post(name: MediaPlayerConstants.MPMoviePlayerPlaybackDidFinishNotification,
                                                  object: self, userInfo: reason)
    }
}

/// The view controller that presents a movie full screen (iOS 3.2).
@ObjCClass("MPMoviePlayerViewController")
open class MPMoviePlayerViewController: NSObject {
    var player: MPMoviePlayerController? = nil

    /// Controllers whose view was shown, kept for the rest of the run: the
    /// screen holds a presented one, and apps release theirs when its
    /// movie finishes and then take its view off the screen.
    nonisolated(unsafe) static var shown: [MPMoviePlayerViewController] = []

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithContentURL:")
    public required init(contentURL: NSObject?) {
        super.init()
        trace("movie player view controller made")
        player = MPMoviePlayerController(contentURL: contentURL)
    }

    @ObjCMethod("moviePlayer")
    func moviePlayer() -> MPMoviePlayerController? {
        trace("moviePlayer: \(player.map { "\($0.objcObject)" } ?? "nil")")
        return player
    }

    /// The controller's view, which a view controller has: the player's.
    /// An app asks for it to put it on the screen, where the movie starts
    /// by itself unless the player is told not to, as it does when the
    /// controller is presented.
    @ObjCMethod("view")
    func view() -> UIView? {
        trace("movie player view controller's view")
        guard let player else { return nil }
        if !MPMoviePlayerViewController.shown.contains(where: { $0 === self }) { MPMoviePlayerViewController.shown.append(self) }
        if player.autoplays { player.prepareToPlay() }
        return player.view()
    }
}

/// The music player, with an empty library: nothing is playing.
@ObjCClass("MPMusicPlayerController")
open class MPMusicPlayerController: NSObject {
    nonisolated(unsafe) static let shared = MPMusicPlayerController()

    @ObjCClassMethod("iPodMusicPlayer") static func iPodMusicPlayer() -> MPMusicPlayerController { shared }
    @ObjCClassMethod("applicationMusicPlayer") static func applicationMusicPlayer() -> MPMusicPlayerController { shared }
    @ObjCClassMethod("systemMusicPlayer") static func systemMusicPlayer() -> MPMusicPlayerController { shared }

    /// MPMusicPlaybackStateStopped.
    @ObjCMethod("playbackState") func playbackState() -> Int { 0 }
    @ObjCMethod("nowPlayingItem") func nowPlayingItem() -> NSObject? { nil }
    @ObjCMethod("volume") func volume() -> Float { 1 }
    @ObjCMethod("setVolume:") func setVolume(_ volume: Float) {}
    @ObjCMethod("play") func play() {}
    @ObjCMethod("pause") func pause() {}
    @ObjCMethod("stop") func stop() {}
    @ObjCMethod("skipToNextItem") func skipToNextItem() {}
    @ObjCMethod("skipToPreviousItem") func skipToPreviousItem() {}
    @ObjCMethod("skipToBeginning") func skipToBeginning() {}
    @ObjCMethod("setQueueWithItemCollection:") func setQueue(collection: NSObject?) {}
    @ObjCMethod("setQueueWithQuery:") func setQueue(query: NSObject?) {}
    @ObjCMethod("setRepeatMode:") func setRepeatMode(_ mode: Int) {}
    @ObjCMethod("setShuffleMode:") func setShuffleMode(_ mode: Int) {}
    @ObjCMethod("beginGeneratingPlaybackNotifications") func beginGeneratingPlaybackNotifications() {}
    @ObjCMethod("endGeneratingPlaybackNotifications") func endGeneratingPlaybackNotifications() {}
}

@ObjCConstants
enum MediaPlayerConstants {
    static let MPMoviePlayerPlaybackDidFinishNotification = "MPMoviePlayerPlaybackDidFinishNotification"
    static let MPMoviePlayerPlaybackStateDidChangeNotification = "MPMoviePlayerPlaybackStateDidChangeNotification"
    static let MPMoviePlayerLoadStateDidChangeNotification = "MPMoviePlayerLoadStateDidChangeNotification"
    static let MPMoviePlayerNowPlayingMovieDidChangeNotification = "MPMoviePlayerNowPlayingMovieDidChangeNotification"
    static let MPMoviePlayerContentPreloadDidFinishNotification = "MPMoviePlayerContentPreloadDidFinishNotification"
    static let MPMoviePlayerScalingModeDidChangeNotification = "MPMoviePlayerScalingModeDidChangeNotification"
    static let MPMoviePlayerWillEnterFullscreenNotification = "MPMoviePlayerWillEnterFullscreenNotification"
    static let MPMoviePlayerDidEnterFullscreenNotification = "MPMoviePlayerDidEnterFullscreenNotification"
    static let MPMoviePlayerWillExitFullscreenNotification = "MPMoviePlayerWillExitFullscreenNotification"
    static let MPMoviePlayerDidExitFullscreenNotification = "MPMoviePlayerDidExitFullscreenNotification"
    static let MPMoviePlayerPlaybackDidFinishReasonUserInfoKey = "MPMoviePlayerPlaybackDidFinishReasonUserInfoKey"
    static let MPMusicPlayerControllerPlaybackStateDidChangeNotification = "MPMusicPlayerControllerPlaybackStateDidChangeNotification"
    static let MPMusicPlayerControllerNowPlayingItemDidChangeNotification = "MPMusicPlayerControllerNowPlayingItemDidChangeNotification"
    static let MPMusicPlayerControllerVolumeDidChangeNotification = "MPMusicPlayerControllerVolumeDidChangeNotification"
    static let MPMediaItemPropertyPersistentID = "persistentID"
    static let MPMediaItemPropertyMediaType = "mediaType"
    static let MPMediaItemPropertyTitle = "title"
    static let MPMediaItemPropertyAlbumTitle = "albumTitle"
    static let MPMediaItemPropertyArtist = "artist"
    static let MPMediaItemPropertyAlbumArtist = "albumArtist"
    static let MPMediaItemPropertyGenre = "genre"
    static let MPMediaItemPropertyComposer = "composer"
    static let MPMediaItemPropertyPlaybackDuration = "playbackDuration"
    static let MPMediaItemPropertyAlbumTrackNumber = "albumTrackNumber"
    static let MPMediaItemPropertyAlbumTrackCount = "albumTrackCount"
    static let MPMediaItemPropertyDiscNumber = "discNumber"
    static let MPMediaItemPropertyDiscCount = "discCount"
    static let MPMediaItemPropertyArtwork = "artwork"
    static let MPMediaItemPropertyLyrics = "lyrics"
    static let MPMediaItemPropertyIsCompilation = "isCompilation"
}
