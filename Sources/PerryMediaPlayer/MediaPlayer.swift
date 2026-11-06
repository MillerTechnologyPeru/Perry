import PerryObjCInterop

// MediaPlayer, with no media library and nothing that plays movies: the
// names apps pass to the notification center and read from media items, a
// music player that has no songs, and movie players that finish as soon as
// they are asked to play, so an app waiting for its intro movie goes on.

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> NSNotificationCenter
    @ObjCMethod("postNotificationName:object:userInfo:") func post(name: String, object: NSObject?, userInfo: NSObject?)
}

/// MPMoviePlayerController, the player of iOS 2 to 8.
@ObjCClass("MPMoviePlayerController")
open class MPMoviePlayerController: NSObject {
    var contentURL: NSObject?

    @ObjCMethod("initWithContentURL:")
    func initialize(contentURL: NSObject?) -> Self {
        self.contentURL = contentURL
        return self
    }

    @ObjCMethod("contentURL") func getContentURL() -> NSObject? { contentURL }
    @ObjCMethod("setContentURL:") func setContentURL(_ url: NSObject?) { contentURL = url }
    @ObjCMethod("view") func view() -> NSObject? { nil }
    @ObjCMethod("backgroundView") func backgroundView() -> NSObject? { nil }
    @ObjCMethod("prepareToPlay") func prepareToPlay() {}
    @ObjCMethod("isPreparedToPlay") func isPreparedToPlay() -> Bool { false }
    @ObjCMethod("pause") func pause() {}
    @ObjCMethod("stop") func stop() {}

    /// MPMoviePlaybackStateStopped, MPMovieLoadStateUnknown.
    @ObjCMethod("playbackState") func playbackState() -> Int { 0 }
    @ObjCMethod("loadState") func loadState() -> UInt { 0 }
    @ObjCMethod("duration") func duration() -> Double { 0 }
    @ObjCMethod("playableDuration") func playableDuration() -> Double { 0 }
    @ObjCMethod("currentPlaybackTime") func currentPlaybackTime() -> Double { 0 }
    @ObjCMethod("setCurrentPlaybackTime:") func setCurrentPlaybackTime(_ time: Double) {}
    @ObjCMethod("currentPlaybackRate") func currentPlaybackRate() -> Float { 0 }
    @ObjCMethod("setCurrentPlaybackRate:") func setCurrentPlaybackRate(_ rate: Float) {}

    // What an app sets up before it plays; nothing is shown.
    @ObjCMethod("setControlStyle:") func setControlStyle(_ style: Int) {}
    @ObjCMethod("setMovieControlMode:") func setMovieControlMode(_ mode: Int) {}
    @ObjCMethod("setScalingMode:") func setScalingMode(_ mode: Int) {}
    @ObjCMethod("setRepeatMode:") func setRepeatMode(_ mode: Int) {}
    @ObjCMethod("setShouldAutoplay:") func setShouldAutoplay(_ autoplay: Bool) {}
    @ObjCMethod("setFullscreen:") func setFullscreen(_ fullscreen: Bool) {}
    @ObjCMethod("setFullscreen:animated:") func setFullscreen(_ fullscreen: Bool, animated: Bool) {}
    @ObjCMethod("isFullscreen") func isFullscreen() -> Bool { false }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: NSObject?) {}
    @ObjCMethod("setUseApplicationAudioSession:") func setUseApplicationAudioSession(_ uses: Bool) {}
    @ObjCMethod("setMovieSourceType:") func setMovieSourceType(_ type: Int) {}
    @ObjCMethod("setInitialPlaybackTime:") func setInitialPlaybackTime(_ time: Double) {}

    /// Nothing plays: the movie has finished, which the app hears once it is
    /// back in its run loop.
    @ObjCMethod("play")
    func play() {
        performSelector(ObjCRuntime.selector("_perryFinished"), with: nil, afterDelay: 0)
    }

    @ObjCMethod("performSelector:withObject:afterDelay:")
    func performSelector(_ selector: ObjCSelector, with object: NSObject?, afterDelay delay: Double)

    @ObjCMethod("_perryFinished")
    func finished() {
        NSNotificationCenter.defaultCenter().post(name: MediaPlayerConstants.MPMoviePlayerPlaybackDidFinishNotification,
                                                  object: self, userInfo: nil)
    }
}

/// The view controller that presents a movie full screen (iOS 3.2).
@ObjCClass("MPMoviePlayerViewController")
open class MPMoviePlayerViewController: NSObject {
    var player: MPMoviePlayerController?

    @ObjCMethod("initWithContentURL:")
    func initialize(contentURL: NSObject?) -> Self {
        player = MPMoviePlayerController().initialize(contentURL: contentURL)
        return self
    }

    @ObjCMethod("moviePlayer") func moviePlayer() -> MPMoviePlayerController? { player }
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
