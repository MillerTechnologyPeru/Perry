import PerryObjCInterop

// AVSpeechUtterance, AVSpeechSynthesisVoice and AVSpeechSynthesizer: what a
// navigation app speaks its directions with. There is no speech engine
// here, so a synthesizer takes each utterance, reports its start and end
// to the delegate as if it had been said, and says nothing.

@ObjCClass("AVSpeechSynthesisVoice")
open class AVSpeechSynthesisVoice: NSObject {
    var language = "en-US"
    var identifier = "com.apple.voice.compact.en-US.Samantha"
    var name = "Samantha"

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("language") func voiceLanguage() -> String { language }
    @ObjCMethod("identifier") func voiceIdentifier() -> String { identifier }
    @ObjCMethod("name") func voiceName() -> String { name }
    @ObjCMethod("quality") func quality() -> Int { 1 }

    @ObjCClassMethod("voiceWithLanguage:")
    static func voice(_ cls: ObjCClass, language: String?) -> AVSpeechSynthesisVoice {
        let made = NSObject(cls.pointer).newInstance().unsafeCast(to: AVSpeechSynthesisVoice.self)
        if let language { made.language = language }
        return made
    }

    @ObjCClassMethod("voiceWithIdentifier:")
    static func voice(_ cls: ObjCClass, identifier: String?) -> AVSpeechSynthesisVoice {
        let made = NSObject(cls.pointer).newInstance().unsafeCast(to: AVSpeechSynthesisVoice.self)
        if let identifier { made.identifier = identifier }
        return made
    }

    @ObjCClassMethod("currentLanguageCode") static func currentLanguageCode(_ cls: ObjCClass) -> String { "en-US" }

    @ObjCClassMethod("speechVoices")
    static func speechVoices(_ cls: ObjCClass) -> NSObject {
        Arrays.of([NSObject(cls.pointer).newInstance().unsafeCast(to: AVSpeechSynthesisVoice.self)])
    }
}

@ObjCClass("AVSpeechUtterance")
open class AVSpeechUtterance: NSObject {
    var speechString = ""
    var rate: Float = 0.5
    var pitchMultiplier: Float = 1
    var volume: Float = 1
    var preUtteranceDelay = 0.0
    var postUtteranceDelay = 0.0
    var voice: NSObject?
    var prefersAssistiveTechnologySettings = false

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithString:")
    public required init(string: String?) {
        super.init()
        speechString = string ?? ""
    }

    @ObjCClassMethod("speechUtteranceWithString:")
    static func utterance(_ cls: ObjCClass, string: String?) -> AVSpeechUtterance {
        let made = NSObject(cls.pointer).newInstance().unsafeCast(to: AVSpeechUtterance.self)
        made.speechString = string ?? ""
        return made
    }

    @ObjCMethod("speechString") func utteranceString() -> String { speechString }
    @ObjCMethod("rate") func utteranceRate() -> Float { rate }
    @ObjCMethod("setRate:") func setRate(_ rate: Float) { self.rate = rate }
    @ObjCMethod("pitchMultiplier") func utterancePitch() -> Float { pitchMultiplier }
    @ObjCMethod("setPitchMultiplier:") func setPitchMultiplier(_ pitch: Float) { pitchMultiplier = pitch }
    @ObjCMethod("volume") func utteranceVolume() -> Float { volume }
    @ObjCMethod("setVolume:") func setVolume(_ volume: Float) { self.volume = volume }
    @ObjCMethod("preUtteranceDelay") func utterancePreDelay() -> Double { preUtteranceDelay }
    @ObjCMethod("setPreUtteranceDelay:") func setPreUtteranceDelay(_ delay: Double) { preUtteranceDelay = delay }
    @ObjCMethod("postUtteranceDelay") func utterancePostDelay() -> Double { postUtteranceDelay }
    @ObjCMethod("setPostUtteranceDelay:") func setPostUtteranceDelay(_ delay: Double) { postUtteranceDelay = delay }
    @ObjCMethod("prefersAssistiveTechnologySettings") func utterancePrefersAssistive() -> Bool { prefersAssistiveTechnologySettings }
    @ObjCMethod("setPrefersAssistiveTechnologySettings:") func setPrefersAssistive(_ prefers: Bool) { prefersAssistiveTechnologySettings = prefers }

    @ObjCMethod("voice") func utteranceVoice() -> NSObject? { voice }
    @ObjCMethod("setVoice:")
    func setVoice(_ voice: NSObject?) {
        let retained = ObjCRuntime.retain(voice?.objcObject)
        if let old = self.voice { ObjCRuntime.release(old.objcObject) }
        self.voice = retained.map { NSObject($0) }
    }
}

@ObjCClass("AVSpeechSynthesizer")
open class AVSpeechSynthesizer: NSObject {
    var delegate: NSObject?
    var usesApplicationAudioSession = true

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("delegate") func synthesizerDelegate() -> NSObject? { delegate }
    @ObjCMethod("setDelegate:") func setSynthesizerDelegate(_ delegate: NSObject?) { self.delegate = delegate }
    @ObjCMethod("isSpeaking") func isSpeaking() -> Bool { false }
    @ObjCMethod("isPaused") func isPaused() -> Bool { false }
    @ObjCMethod("usesApplicationAudioSession") func usesApplicationAudio() -> Bool { usesApplicationAudioSession }
    @ObjCMethod("setUsesApplicationAudioSession:") func setUsesApplicationAudio(_ uses: Bool) { usesApplicationAudioSession = uses }
    @ObjCMethod("mixToTelephonyUplink") func mixToTelephonyUplink() -> Bool { false }
    @ObjCMethod("setMixToTelephonyUplink:") func setMixToTelephonyUplink(_ mix: Bool) {}
    @ObjCMethod("pauseSpeakingAtBoundary:") func pauseSpeaking(atBoundary boundary: Int) -> Bool { false }
    @ObjCMethod("continueSpeaking") func continueSpeaking() -> Bool { false }
    @ObjCMethod("stopSpeakingAtBoundary:") func stopSpeaking(atBoundary boundary: Int) -> Bool { false }

    /// An utterance is "spoken" at once: its start and end are reported.
    @ObjCMethod("speakUtterance:")
    func speak(_ utterance: NSObject?) {
        guard let utterance, let delegate else { return }
        if delegate.responds(to: "speechSynthesizer:didStartSpeechUtterance:") {
            delegate.sendSpeechDidStart(self, utterance)
        }
        if delegate.responds(to: "speechSynthesizer:didFinishSpeechUtterance:") {
            delegate.sendSpeechDidFinish(self, utterance)
        }
    }
}

extension NSObject {
    @ObjCMethod("speechSynthesizer:didStartSpeechUtterance:")
    func sendSpeechDidStart(_ synthesizer: NSObject, _ utterance: NSObject)
    @ObjCMethod("speechSynthesizer:didFinishSpeechUtterance:")
    func sendSpeechDidFinish(_ synthesizer: NSObject, _ utterance: NSObject)
}
