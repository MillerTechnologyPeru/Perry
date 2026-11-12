import Glibc
import PerryObjCInterop

// MediaPlayer, with no media library: the names apps pass to the notification
// center and read from media items, a music player that has no songs, and
// movie players. A movie with a view to show in plays through AVFoundation's
// player; any other is skipped, so an app waiting for its intro goes on.

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
    @ObjCMethod("addObserver:selector:name:object:") func addObserver(_ observer: NSObject, selector: ObjCSelector, name: String, object: NSObject?)
    @ObjCMethod("removeObserver:") func removeObserver(_ observer: NSObject)
}

/// AVFoundation's player, which decodes a movie.
@ObjCWrapper("AVPlayer")
class AVPlayer: NSObject {
    @ObjCClassMethod("playerWithURL:") static func player(url: NSObject?) -> AVPlayer
    @ObjCMethod("currentItem") func currentItem() -> NSObject?
    @ObjCMethod("replaceCurrentItemWithPlayerItem:") func replaceCurrentItem(_ item: NSObject?)
    @ObjCMethod("play") func play()
    @ObjCMethod("pause") func pause()
}

@ObjCWrapper("UIView")
class UIView: NSObject {
    @ObjCClassMethod("new") static func new() -> UIView
}

/// UIKit's view showing an AVFoundation player's frames.
@ObjCWrapper("_PerryMovieView")
class MovieView: NSObject {
    @ObjCClassMethod("new") static func make() -> MovieView
    @ObjCMethod("setMoviePlayer:") func setMoviePlayer(_ player: NSObject?)
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithInteger:") static func number(_ value: Int) -> NSNumber
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCClassMethod("dictionaryWithObject:forKey:") static func dictionary(object: NSObject, key: String) -> NSDictionary
}

/// MPMoviePlayerController, the player of iOS 2 to 8. It is ready as soon as
/// it is made. Playing it (by -play, or by preparing it while it plays by
/// itself, which it does unless told not to) plays the movie if it has a view
/// to show in and AVFoundation is loaded; otherwise it reports the movie
/// finished, once, as if it had played to its end.
@ObjCClass("MPMoviePlayerController")
open class MPMoviePlayerController: NSObject {
    var contentURL: NSObject? = nil
    var playerView: UIView? = nil
    var autoplays = true
    var loaded = false
    var playing = false
    var skipped = false
    var finished = false
    /// Presented by a view controller, which shows the view when it can.
    var onScreen = false
    /// The player decoding the movie, while it plays.
    var movie: AVPlayer? = nil
    /// When the movie was started, by now().
    var startedAt = 0.0
    var repeatMode = 0

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
        trace("movie player made \(objcObject) \(contentURL.map { "\($0)" } ?? "nil")")
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

    /// Whether movies can be played and shown.
    private var canPlay: Bool {
        ObjCRuntime.registeredClassPair("AVPlayer") != nil && ObjCRuntime.registeredClassPair("_PerryMovieView") != nil
    }

    /// The view the movie shows in, which apps size and put in their own.
    @ObjCMethod("view")
    func view() -> UIView {
        if let playerView { return playerView }
        let made = canPlay ? MovieView.make().unsafeCast(to: UIView.self) : UIView.new()
        playerView = made
        // An app that plays a movie and then asks for the view to put in its
        // window, as iOS 7 apps do, has the movie start in it.
        if playing, movie == nil, !finished { _ = startMovie() }
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

    @ObjCMethod("pause")
    func pause() {
        trace("pause")
        movie?.pause()
    }

    /// Stops the movie. An app that sets a player up with -stop and -play
    /// right after it has started (as an iOS 7 game does for its menu's
    /// background movie) is not told the movie finished, which a real player
    /// does not do for a movie not yet shown: the movie halts, and plays
    /// again with -play.
    @ObjCMethod("stop")
    func stop() {
        trace("stop \(objcObject) playing=\(playing) movie=\(movie != nil) finished=\(finished)")
        if movie != nil, now() - startedAt < 1 {
            halt()
            return
        }
        finish()
    }

    /// Takes the movie off its view and lets it be played again.
    private func halt() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        movie?.pause()
        view().unsafeCast(to: MovieView.self).setMoviePlayer(nil)
        movie?.replaceCurrentItem(nil)
        movie = nil
        playing = false
        skipped = false
        finished = false
    }

    /// Seconds on a clock that only goes forward.
    private func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
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
    /// MPMovieRepeatModeOne plays the movie again when it ends.
    @ObjCMethod("setRepeatMode:") func setRepeatMode(_ mode: Int) { repeatMode = mode }
    @ObjCMethod("repeatMode") func getRepeatMode() -> Int { repeatMode }
    @ObjCMethod("setFullscreen:") func setFullscreen(_ fullscreen: Bool) {}
    @ObjCMethod("setFullscreen:animated:") func setFullscreen(_ fullscreen: Bool, animated: Bool) {}
    @ObjCMethod("isFullscreen") func isFullscreen() -> Bool { false }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) {}
    @ObjCMethod("setUseApplicationAudioSession:") func setUseApplicationAudioSession(_ uses: Bool) {}
    @ObjCMethod("setMovieSourceType:") func setMovieSourceType(_ type: Int) {}
    @ObjCMethod("setInitialPlaybackTime:") func setInitialPlaybackTime(_ time: Double) {}
    @ObjCMethod("setEndPlaybackTime:") func setEndPlaybackTime(_ time: Double) {}
    @ObjCMethod("setOrientation:animated:") func setOrientation(_ orientation: Int, animated: Bool) {}

    /// Plays the movie, or, with nowhere to show it, has it finish, which
    /// the app hears from the main run loop. Each movie is played or skipped
    /// once; a paused one goes on.
    @ObjCMethod("play")
    func play() {
        trace("play \(objcObject) playing=\(playing) skipped=\(skipped) view=\(playerView != nil)")
        if let movie {
            movie.play()
            return
        }
        guard !playing, !skipped else { return }
        playing = true
        skipped = true
        finished = false
        MPMoviePlayerController.played.append(self)
        if !startMovie() { later(ObjCSelector("_perryNoView")) }
    }

    /// The movie had no view to show in when played, and the app has had
    /// until now to ask for one.
    @ObjCMethod("_perryNoView")
    func finishWithoutView() {
        if movie == nil { finish() }
    }

    /// Starts decoding the movie into the view, if there is a view for it.
    /// The player says when the movie ends, or that it can't be played.
    private func startMovie() -> Bool {
        guard onScreen || playerView != nil, canPlay, let contentURL else { return false }
        trace("playing the movie")
        let player = AVPlayer.player(url: contentURL)
        view().unsafeCast(to: MovieView.self).setMoviePlayer(player)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: ObjCSelector("_perryEnded"),
                                                         name: "AVPlayerItemDidPlayToEndTimeNotification", object: player.currentItem())
        movie = player
        startedAt = now()
        player.play()
        return true
    }

    /// Sends itself the message from the main run loop, where a real player
    /// posts its notifications, whatever thread the app uses it from: a
    /// game's own thread may run no run loop.
    private func later(_ selector: ObjCSelector) {
        performSelectorOnMainThread(selector, with: nil, waitUntilDone: false)
    }

    @ObjCMethod("performSelectorOnMainThread:withObject:waitUntilDone:")
    func performSelectorOnMainThread(_ selector: ObjCSelector, with object: NSObject?, waitUntilDone wait: Bool)

    /// The movie played to its end: again, if the app asked for that.
    @ObjCMethod("_perryEnded")
    func movieEnded() {
        guard repeatMode != 0, movie != nil else { finish(); return }
        halt()
        playing = true
        skipped = true
        if !startMovie() { finish() }
    }

    @ObjCMethod("_perryFinished")
    func finish() {
        guard !finished else { return }
        finished = true
        playing = false
        if let movie {
            NSNotificationCenter.defaultCenter().removeObserver(self)
            movie.pause()
            view().unsafeCast(to: MovieView.self).setMoviePlayer(nil)
            movie.replaceCurrentItem(nil)
            self.movie = nil
        }
        trace("movie finished: playback did finish notification \(objcObject)")
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
        player?.onScreen = true
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
