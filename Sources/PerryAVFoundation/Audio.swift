import PerryObjCInterop

// AVAudioPlayer and AVAudioSession, without sound: a player keeps the state
// an app sets and reads back (playing, volume, loops, position), but
// nothing is heard and it never finishes; the session accepts every
// category, mode and activation.

final class PlayerState {
    var url: NSObject?
    var data: NSObject?
    var delegate: UnsafeMutableRawPointer?
    var playing = false
    var volume: Float = 1
    var pan: Float = 0
    var rate: Float = 1
    var numberOfLoops = 0
    var currentTime: Double = 0
    var meteringEnabled = false
    var enableRate = false
}

@ObjCClass("AVAudioPlayer")
open class AVAudioPlayer: NSObject {
    static let states = StateTable<PlayerState>()
    var player: PlayerState {
        if let state = AVAudioPlayer.states[objcObject] { return state }
        let state = PlayerState()
        AVAudioPlayer.states.set(objcObject, state)
        return state
    }

    @ObjCMethod("initWithContentsOfURL:error:")
    func initialize(contentsOf url: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self {
        error?.pointee = nil
        player.url = url
        return self
    }

    @ObjCMethod("initWithContentsOfURL:fileTypeHint:error:")
    func initialize(contentsOf url: NSObject?, fileTypeHint: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self {
        initialize(contentsOf: url, error: error)
    }

    @ObjCMethod("initWithData:error:")
    func initialize(data: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self {
        error?.pointee = nil
        player.data = data
        return self
    }

    @ObjCMethod("initWithData:fileTypeHint:error:")
    func initialize(data: NSObject?, fileTypeHint: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self {
        initialize(data: data, error: error)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        AVAudioPlayer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAudioPlayer.objCClass.pointer)
    }

    @ObjCMethod("prepareToPlay") func prepareToPlay() -> Bool { true }
    @ObjCMethod("play") func play() -> Bool { player.playing = true; return true }
    @ObjCMethod("playAtTime:") func play(atTime time: Double) -> Bool { play() }
    @ObjCMethod("pause") func pause() { player.playing = false }
    @ObjCMethod("stop") func stop() { player.playing = false }
    @ObjCMethod("isPlaying") func isPlaying() -> Bool { player.playing }

    @ObjCMethod("url") func url() -> NSObject? { player.url }
    @ObjCMethod("data") func data() -> NSObject? { player.data }
    @ObjCMethod("delegate") func delegate() -> NSObject? { player.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { player.delegate = delegate?.objcObject }
    @ObjCMethod("volume") func volume() -> Float { player.volume }
    @ObjCMethod("setVolume:") func setVolume(_ volume: Float) { player.volume = volume }
    @ObjCMethod("setVolume:fadeDuration:") func setVolume(_ volume: Float, fadeDuration: Double) { player.volume = volume }
    @ObjCMethod("pan") func pan() -> Float { player.pan }
    @ObjCMethod("setPan:") func setPan(_ pan: Float) { player.pan = pan }
    @ObjCMethod("rate") func rate() -> Float { player.rate }
    @ObjCMethod("setRate:") func setRate(_ rate: Float) { player.rate = rate }
    @ObjCMethod("enableRate") func enableRate() -> Bool { player.enableRate }
    @ObjCMethod("setEnableRate:") func setEnableRate(_ enable: Bool) { player.enableRate = enable }
    @ObjCMethod("numberOfLoops") func numberOfLoops() -> Int { player.numberOfLoops }
    @ObjCMethod("setNumberOfLoops:") func setNumberOfLoops(_ loops: Int) { player.numberOfLoops = loops }
    @ObjCMethod("currentTime") func currentTime() -> Double { player.currentTime }
    @ObjCMethod("setCurrentTime:") func setCurrentTime(_ time: Double) { player.currentTime = time }
    @ObjCMethod("deviceCurrentTime") func deviceCurrentTime() -> Double { 0 }
    @ObjCMethod("duration") func duration() -> Double { 0 }
    @ObjCMethod("numberOfChannels") func numberOfChannels() -> UInt { 2 }
    @ObjCMethod("isMeteringEnabled") func isMeteringEnabled() -> Bool { player.meteringEnabled }
    @ObjCMethod("setMeteringEnabled:") func setMeteringEnabled(_ enabled: Bool) { player.meteringEnabled = enabled }
    @ObjCMethod("updateMeters") func updateMeters() {}
    @ObjCMethod("averagePowerForChannel:") func averagePower(forChannel channel: UInt) -> Float { -160 }
    @ObjCMethod("peakPowerForChannel:") func peakPower(forChannel channel: UInt) -> Float { -160 }
}

final class SessionState: @unchecked Sendable {
    var category: NSObject?
    var mode: NSObject?
    var options: UInt = 0
    var active = false
    var preferredSampleRate: Double = 0
    var preferredIOBufferDuration: Double = 0
    var delegate: UnsafeMutableRawPointer?
}

@ObjCClass("AVAudioSession")
open class AVAudioSession: NSObject {
    nonisolated(unsafe) static var shared: AVAudioSession?
    static let session = SessionState()

    @ObjCClassMethod("sharedInstance")
    static func sharedInstance() -> AVAudioSession {
        if let shared { return shared }
        let session = NSObject(objCClass.pointer).newInstance().unsafeCast(to: AVAudioSession.self)
        shared = session
        return session
    }

    private var session: SessionState { AVAudioSession.session }
    typealias ErrorOut = UnsafeMutablePointer<UnsafeMutableRawPointer?>?

    @ObjCMethod("category") func category() -> NSObject? { session.category }
    @ObjCMethod("categoryOptions") func categoryOptions() -> UInt { session.options }
    @ObjCMethod("setCategory:error:")
    func setCategory(_ category: NSObject?, error: ErrorOut) -> Bool { session.category = category; return true }
    @ObjCMethod("setCategory:withOptions:error:")
    func setCategory(_ category: NSObject?, options: UInt, error: ErrorOut) -> Bool {
        (session.category, session.options) = (category, options)
        return true
    }
    @ObjCMethod("setCategory:mode:options:error:")
    func setCategory(_ category: NSObject?, mode: NSObject?, options: UInt, error: ErrorOut) -> Bool {
        (session.category, session.mode, session.options) = (category, mode, options)
        return true
    }
    @ObjCMethod("mode") func mode() -> NSObject? { session.mode }
    @ObjCMethod("setMode:error:") func setMode(_ mode: NSObject?, error: ErrorOut) -> Bool { session.mode = mode; return true }
    @ObjCMethod("setActive:error:") func setActive(_ active: Bool, error: ErrorOut) -> Bool { session.active = active; return true }
    @ObjCMethod("setActive:withOptions:error:")
    func setActive(_ active: Bool, options: UInt, error: ErrorOut) -> Bool { session.active = active; return true }
    @ObjCMethod("setActive:withFlags:error:")
    func setActive(_ active: Bool, flags: Int, error: ErrorOut) -> Bool { session.active = active; return true }
    @ObjCMethod("isOtherAudioPlaying") func isOtherAudioPlaying() -> Bool { false }
    @ObjCMethod("otherAudioPlaying") func otherAudioPlaying() -> Bool { false }
    @ObjCMethod("secondaryAudioShouldBeSilencedHint") func secondaryAudioShouldBeSilencedHint() -> Bool { false }
    @ObjCMethod("outputVolume") func outputVolume() -> Float { 1 }
    @ObjCMethod("sampleRate") func sampleRate() -> Double { 44_100 }
    @ObjCMethod("preferredSampleRate") func preferredSampleRate() -> Double { session.preferredSampleRate }
    @ObjCMethod("setPreferredSampleRate:error:")
    func setPreferredSampleRate(_ rate: Double, error: ErrorOut) -> Bool { session.preferredSampleRate = rate; return true }
    @ObjCMethod("IOBufferDuration") func ioBufferDuration() -> Double { 0.023 }
    @ObjCMethod("preferredIOBufferDuration") func preferredIOBufferDuration() -> Double { session.preferredIOBufferDuration }
    @ObjCMethod("setPreferredIOBufferDuration:error:")
    func setPreferredIOBufferDuration(_ duration: Double, error: ErrorOut) -> Bool { session.preferredIOBufferDuration = duration; return true }
    @ObjCMethod("outputNumberOfChannels") func outputNumberOfChannels() -> Int { 2 }
    @ObjCMethod("inputAvailable") func inputAvailable() -> Bool { false }
    @ObjCMethod("isInputAvailable") func isInputAvailable() -> Bool { false }
    @ObjCMethod("delegate") func delegate() -> NSObject? { session.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { session.delegate = delegate?.objcObject }
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// The session's categories, modes, notifications and their keys.
@ObjCConstants
enum SessionConstants {
    static let AVAudioSessionCategoryAmbient = "AVAudioSessionCategoryAmbient"
    static let AVAudioSessionCategorySoloAmbient = "AVAudioSessionCategorySoloAmbient"
    static let AVAudioSessionCategoryPlayback = "AVAudioSessionCategoryPlayback"
    static let AVAudioSessionCategoryRecord = "AVAudioSessionCategoryRecord"
    static let AVAudioSessionCategoryPlayAndRecord = "AVAudioSessionCategoryPlayAndRecord"
    static let AVAudioSessionCategoryAudioProcessing = "AVAudioSessionCategoryAudioProcessing"
    static let AVAudioSessionCategoryMultiRoute = "AVAudioSessionCategoryMultiRoute"
    static let AVAudioSessionModeDefault = "AVAudioSessionModeDefault"
    static let AVAudioSessionModeGameChat = "AVAudioSessionModeGameChat"
    static let AVAudioSessionModeMeasurement = "AVAudioSessionModeMeasurement"
    static let AVAudioSessionModeMoviePlayback = "AVAudioSessionModeMoviePlayback"
    static let AVAudioSessionModeSpokenAudio = "AVAudioSessionModeSpokenAudio"
    static let AVAudioSessionModeVideoChat = "AVAudioSessionModeVideoChat"
    static let AVAudioSessionModeVideoRecording = "AVAudioSessionModeVideoRecording"
    static let AVAudioSessionModeVoiceChat = "AVAudioSessionModeVoiceChat"
    static let AVAudioSessionInterruptionNotification = "AVAudioSessionInterruptionNotification"
    static let AVAudioSessionRouteChangeNotification = "AVAudioSessionRouteChangeNotification"
    static let AVAudioSessionMediaServicesWereLostNotification = "AVAudioSessionMediaServicesWereLostNotification"
    static let AVAudioSessionMediaServicesWereResetNotification = "AVAudioSessionMediaServicesWereResetNotification"
    static let AVAudioSessionSilenceSecondaryAudioHintNotification = "AVAudioSessionSilenceSecondaryAudioHintNotification"
    static let AVAudioSessionInterruptionTypeKey = "AVAudioSessionInterruptionTypeKey"
    static let AVAudioSessionInterruptionOptionKey = "AVAudioSessionInterruptionOptionKey"
    static let AVAudioSessionRouteChangeReasonKey = "AVAudioSessionRouteChangeReasonKey"
    static let AVAudioSessionRouteChangePreviousRouteKey = "AVAudioSessionRouteChangePreviousRouteKey"
    static let AVAudioSessionSilenceSecondaryAudioHintTypeKey = "AVAudioSessionSilenceSecondaryAudioHintTypeKey"
}
