import Glibc
import PerryObjCInterop

// AVAudioPlayer and AVAudioSession. A player plays its file through
// GStreamer when it's installed, looping as many times as asked and telling
// its delegate when it's done; without GStreamer, or for data, it keeps the
// state an app sets and reads back but is silent. The session accepts every
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
    /// The file's pipeline, made when it's first wanted.
    var pipeline: Pipeline?
    var prepared = false
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
        // Its pipeline goes with its state.
        let start = AudioTiming.now()
        AVAudioPlayer.states.remove(objcObject)
        Players.trace("audio player freed in \(AudioTiming.since(start)) ms at \(AudioTiming.stamp())")
        ObjCRuntime.superDealloc(objcObject, definedOn: AVAudioPlayer.objCClass.pointer)
    }

    /// The file's pipeline, made the first time it's wanted, paused at
    /// the start; nil without GStreamer, for data, or when it can't play.
    var pipeline: Pipeline? {
        let state = player
        if !state.prepared {
            state.prepared = true
            let start = AudioTiming.now()
            if let gst = GStreamer.shared, let uri = state.url?.unsafeCast(to: NSURL.self).absoluteString(),
               let pipeline = Pipeline(uri: uri, gst: gst, video: false) {
                defer { Players.trace("audio player for \(uri.split(separator: "/").last ?? "") made in \(AudioTiming.since(start)) ms at \(AudioTiming.stamp())") }
                pipeline.set(volume: Double(state.volume), muted: false)
                pipeline.pause()
                if state.currentTime > 0 { pipeline.seek(to: state.currentTime) }
                state.pipeline = pipeline
            }
        }
        return state.pipeline
    }

    @ObjCMethod("prepareToPlay") func prepareToPlay() -> Bool { _ = pipeline; return true }

    @ObjCMethod("play")
    func play() -> Bool {
        player.playing = true
        if let pipeline {
            let start = AudioTiming.now()
            pipeline.play()
            Players.trace("audio play in \(AudioTiming.since(start)) ms at \(AudioTiming.stamp())")
            Players.startAudio(objcObject)
        }
        return true
    }

    @ObjCMethod("playAtTime:") func play(atTime time: Double) -> Bool { play() }

    @ObjCMethod("pause")
    func pause() {
        player.playing = false
        player.pipeline?.pause()
        Players.stopAudio(objcObject)
    }

    /// Stops, keeping the position, as Darwin's does.
    @ObjCMethod("stop") func stop() { pause() }

    /// Ends or loops a finished pass; false once the player has stopped.
    func tick() -> Bool {
        let state = player
        guard state.playing, let pipeline = state.pipeline else { return false }
        guard pipeline.finished() else { return true }
        if state.numberOfLoops != 0 {
            if state.numberOfLoops > 0 { state.numberOfLoops -= 1 }
            pipeline.seek(to: 0)
            pipeline.play()
            return true
        }
        state.playing = false
        pipeline.pause()
        pipeline.seek(to: 0)
        state.currentTime = 0
        if let delegate = state.delegate.map({ NSObject($0) }), delegate.responds(to: "audioPlayerDidFinishPlaying:successfully:") {
            delegate.sendAudioPlayerDidFinishPlaying(self, successfully: true)
        }
        return false
    }
    @ObjCMethod("isPlaying") func isPlaying() -> Bool { player.playing }

    @ObjCMethod("url") func url() -> NSObject? { player.url }
    @ObjCMethod("data") func data() -> NSObject? { player.data }
    @ObjCMethod("delegate") func delegate() -> NSObject? { player.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { player.delegate = delegate?.objcObject }
    @ObjCMethod("volume") func volume() -> Float { player.volume }
    @ObjCMethod("setVolume:")
    func setVolume(_ volume: Float) {
        player.volume = volume
        player.pipeline?.set(volume: Double(max(volume, 0)), muted: false)
    }
    @ObjCMethod("setVolume:fadeDuration:") func setVolume(_ volume: Float, fadeDuration: Double) { setVolume(volume) }
    @ObjCMethod("pan") func pan() -> Float { player.pan }
    @ObjCMethod("setPan:") func setPan(_ pan: Float) { player.pan = pan }
    @ObjCMethod("rate") func rate() -> Float { player.rate }
    @ObjCMethod("setRate:") func setRate(_ rate: Float) { player.rate = rate }
    @ObjCMethod("enableRate") func enableRate() -> Bool { player.enableRate }
    @ObjCMethod("setEnableRate:") func setEnableRate(_ enable: Bool) { player.enableRate = enable }
    @ObjCMethod("numberOfLoops") func numberOfLoops() -> Int { player.numberOfLoops }
    @ObjCMethod("setNumberOfLoops:") func setNumberOfLoops(_ loops: Int) { player.numberOfLoops = loops }
    @ObjCMethod("currentTime") func currentTime() -> Double { player.pipeline?.position ?? player.currentTime }
    @ObjCMethod("setCurrentTime:")
    func setCurrentTime(_ time: Double) {
        player.currentTime = time
        player.pipeline?.seek(to: time)
    }
    @ObjCMethod("deviceCurrentTime") func deviceCurrentTime() -> Double { 0 }
    @ObjCMethod("duration") func duration() -> Double { pipeline?.duration ?? 0 }
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
    /// Seconds from output to sound and from sound to input: a buffer's
    /// worth, about what Linux's audio servers add.
    @ObjCMethod("outputLatency") func outputLatency() -> Double { 0.023 }
    @ObjCMethod("inputLatency") func inputLatency() -> Double { 0.023 }
    @ObjCMethod("preferredIOBufferDuration") func preferredIOBufferDuration() -> Double { session.preferredIOBufferDuration }
    @ObjCMethod("setPreferredIOBufferDuration:error:")
    func setPreferredIOBufferDuration(_ duration: Double, error: ErrorOut) -> Bool { session.preferredIOBufferDuration = duration; return true }
    @ObjCMethod("outputNumberOfChannels") func outputNumberOfChannels() -> Int { 2 }
    @ObjCMethod("inputAvailable") func inputAvailable() -> Bool { false }
    @ObjCMethod("isInputAvailable") func isInputAvailable() -> Bool { false }
    @ObjCMethod("delegate") func delegate() -> NSObject? { session.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { session.delegate = delegate?.objcObject }

    /// Sound would go to the built-in speaker; nothing comes in.
    @ObjCMethod("currentRoute")
    func currentRoute() -> AVAudioSessionRouteDescription {
        let route = AVAudioSessionRouteDescription()
        route.outputs = [AVAudioSessionPortDescription(type: SessionConstants.AVAudioSessionPortBuiltInSpeaker, name: "Speaker")]
        return route
    }

    @ObjCMethod("availableInputs") func availableInputs() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).sendArray() }
}

/// The ports sound goes in and out through.
@ObjCClass("AVAudioSessionRouteDescription")
open class AVAudioSessionRouteDescription: NSObject {
    var inputs: [AVAudioSessionPortDescription] = []
    var outputs: [AVAudioSessionPortDescription] = []

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("inputs") func inputsArray() -> NSObject { Arrays.of(inputs) }
    @ObjCMethod("outputs") func outputsArray() -> NSObject { Arrays.of(outputs) }
}

@ObjCClass("AVAudioSessionPortDescription")
open class AVAudioSessionPortDescription: NSObject {
    var type = ""
    var name = ""

    @ObjCMethod("init") public required override init() { super.init() }

    convenience init(type: String, name: String) {
        self.init()
        (self.type, self.name) = (type, name)
    }

    @ObjCMethod("portType") func portType() -> String { type }
    @ObjCMethod("portName") func portName() -> String { name }
    @ObjCMethod("UID") func uid() -> String { type }
    @ObjCMethod("channels") func channels() -> NSObject? { nil }
    @ObjCMethod("dataSources") func dataSources() -> NSObject? { nil }
}

/// NSArrays, made by Foundation.
enum Arrays {
    static func of(_ objects: [NSObject]) -> NSObject {
        let array = NSObject(ObjCClass(named: "NSMutableArray").pointer).sendArray()
        for object in objects { array.sendAddObject(object) }
        return array
    }
}

extension NSObject {
    @ObjCMethod("addObject:") func sendAddObject(_ object: NSObject)
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
    static let AVAudioSessionPortAirPlay = "AirPlay"
    static let AVAudioSessionPortBluetoothA2DP = "BluetoothA2DPOutput"
    static let AVAudioSessionPortBluetoothHFP = "BluetoothHFP"
    static let AVAudioSessionPortBuiltInMic = "MicrophoneBuiltIn"
    static let AVAudioSessionPortBuiltInReceiver = "Receiver"
    static let AVAudioSessionPortBuiltInSpeaker = "Speaker"
    static let AVAudioSessionPortHDMI = "HDMIOutput"
    static let AVAudioSessionPortHeadphones = "Headphones"
    static let AVAudioSessionPortLineOut = "LineOut"
}

/// AVAudioPlayerDelegate's message.
extension NSObject {
    @ObjCMethod("audioPlayerDidFinishPlaying:successfully:")
    func sendAudioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool)
}

/// Timing for PERRY_AVFOUNDATION_TRACE.
enum AudioTiming {
    static func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
    static func since(_ start: Double) -> Int { Int((now() - start) * 1000) }
    /// Milliseconds on the same clock as the frame hitch log.
    static func stamp() -> Int { Int(now() * 1000) % 1_000_000 }
}
