import PerryObjCInterop

// AVAudioEngine, its nodes, AVAudioFormat and AVAudioPCMBuffer: the graph
// an app wires to play sound it makes itself. There is nothing to play to
// here yet, so an engine keeps its nodes and connections, starts and stops
// as asked, and a player node takes the buffers it is given and plays
// nothing.

@ObjCClass("AVAudioFormat")
open class AVAudioFormat: NSObject {
    var rate = 44100.0
    var channels: UInt32 = 2
    var interleaved = false
    /// AVAudioCommonFormat: other 0, float32 1, float64 2, int16 3, int32 4.
    var common = 1

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithCommonFormat:sampleRate:channels:interleaved:")
    public required init(commonFormat: Int, sampleRate: Double, channels: UInt32, interleaved: Bool) {
        super.init()
        (common, rate, self.channels, self.interleaved) = (commonFormat, sampleRate, channels, interleaved)
    }

    @ObjCMethod("initStandardFormatWithSampleRate:channels:")
    public required init(standardFormatWithSampleRate sampleRate: Double, channels: UInt32) {
        super.init()
        (rate, self.channels) = (sampleRate, channels)
    }

    /// An AudioStreamBasicDescription: its rate, and its channels at offset 28.
    @ObjCMethod("initWithStreamDescription:")
    public required init(streamDescription: UnsafeRawPointer?) {
        super.init()
        if let streamDescription {
            rate = streamDescription.load(as: Double.self)
            channels = streamDescription.load(fromByteOffset: 28, as: UInt32.self)
        }
    }

    @ObjCMethod("sampleRate") func formatSampleRate() -> Double { rate }
    @ObjCMethod("channelCount") func formatChannelCount() -> UInt32 { channels }
    @ObjCMethod("isInterleaved") func isFormatInterleaved() -> Bool { interleaved }
    @ObjCMethod("commonFormat") func formatCommonFormat() -> Int { common }
    @ObjCMethod("isStandard") func isStandard() -> Bool { common == 1 && !interleaved }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

@ObjCClass("AVAudioPCMBuffer")
open class AVAudioPCMBuffer: NSObject {
    var bufferFormat: NSObject?
    var capacity: UInt32 = 0
    var length: UInt32 = 0

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { if let bufferFormat { ObjCRuntime.release(bufferFormat.objcObject) } }

    @ObjCMethod("initWithPCMFormat:frameCapacity:")
    public required init(pcmFormat: NSObject?, frameCapacity: UInt32) {
        super.init()
        bufferFormat = ObjCRuntime.retain(pcmFormat?.objcObject).map { NSObject($0) }
        capacity = frameCapacity
    }

    @ObjCMethod("format") func pcmFormat() -> NSObject? { bufferFormat }
    @ObjCMethod("frameCapacity") func frameCapacity() -> UInt32 { capacity }
    @ObjCMethod("frameLength") func frameLength() -> UInt32 { length }
    @ObjCMethod("setFrameLength:") func setFrameLength(_ length: UInt32) { self.length = min(length, capacity) }
}

@ObjCClass("AVAudioNode")
open class AVAudioNode: NSObject {
    var volume: Float = 1
    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("reset") func reset() {}
    @ObjCMethod("numberOfInputs") func numberOfInputs() -> UInt { 1 }
    @ObjCMethod("numberOfOutputs") func numberOfOutputs() -> UInt { 1 }
    @ObjCMethod("engine") func engine() -> NSObject? { nil }
    @ObjCMethod("outputFormatForBus:") func outputFormat(forBus bus: UInt) -> NSObject? { nil }
    @ObjCMethod("inputFormatForBus:") func inputFormat(forBus bus: UInt) -> NSObject? { nil }
    @ObjCMethod("installTapOnBus:bufferSize:format:block:")
    func installTap(onBus bus: UInt, bufferSize: UInt32, format: NSObject?, block: NSObject?) {}
    @ObjCMethod("removeTapOnBus:") func removeTap(onBus bus: UInt) {}
}

@ObjCClass("AVAudioMixerNode")
open class AVAudioMixerNode: AVAudioNode {
    @ObjCMethod("outputVolume") func outputVolume() -> Float { volume }
    @ObjCMethod("setOutputVolume:") func setOutputVolume(_ volume: Float) { self.volume = volume }
}

@ObjCClass("AVAudioOutputNode")
open class AVAudioOutputNode: AVAudioNode {}

@ObjCClass("AVAudioInputNode")
open class AVAudioInputNode: AVAudioNode {}

@ObjCClass("AVAudioPlayerNode")
open class AVAudioPlayerNode: AVAudioNode {
    var playing = false

    @ObjCMethod("play") func play() { playing = true }
    @ObjCMethod("pause") func pause() { playing = false }
    @ObjCMethod("stop") func stop() { playing = false }
    @ObjCMethod("isPlaying") func isPlaying() -> Bool { playing }
    @ObjCMethod("volume") func playerVolume() -> Float { volume }
    @ObjCMethod("setVolume:") func setPlayerVolume(_ volume: Float) { self.volume = volume }
    @ObjCMethod("scheduleBuffer:completionHandler:") func scheduleBuffer(_ buffer: NSObject?, completionHandler: NSObject?) {}
    @ObjCMethod("scheduleBuffer:atTime:options:completionHandler:")
    func scheduleBuffer(_ buffer: NSObject?, at time: NSObject?, options: UInt, completionHandler: NSObject?) {}
    @ObjCMethod("scheduleFile:atTime:completionHandler:")
    func scheduleFile(_ file: NSObject?, at time: NSObject?, completionHandler: NSObject?) {}
}

@ObjCClass("AVAudioEngine")
open class AVAudioEngine: NSObject {
    var running = false
    var attached: [NSObject] = []
    var mixer: NSObject?
    var output: NSObject?
    var input: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    deinit {
        for node in attached { ObjCRuntime.release(node.objcObject) }
        for node in [mixer, output, input] { if let node { ObjCRuntime.release(node.objcObject) } }
    }

    private func node(_ cls: ObjCClass) -> NSObject {
        let made = NSObject(cls.pointer).newInstance()
        return made
    }

    @ObjCMethod("mainMixerNode")
    func mainMixerNode() -> NSObject {
        if mixer == nil { mixer = ObjCRuntime.retain(node(AVAudioMixerNode.objCClass).objcObject).map { NSObject($0) } }
        return mixer!
    }

    @ObjCMethod("outputNode")
    func outputNode() -> NSObject {
        if output == nil { output = ObjCRuntime.retain(node(AVAudioOutputNode.objCClass).objcObject).map { NSObject($0) } }
        return output!
    }

    @ObjCMethod("inputNode")
    func inputNode() -> NSObject {
        if input == nil { input = ObjCRuntime.retain(node(AVAudioInputNode.objCClass).objcObject).map { NSObject($0) } }
        return input!
    }

    @ObjCMethod("attachNode:")
    func attach(_ node: NSObject?) {
        guard let node, !attached.contains(where: { $0.objcObject == node.objcObject }),
              let retained = ObjCRuntime.retain(node.objcObject) else { return }
        attached.append(NSObject(retained))
    }

    @ObjCMethod("detachNode:")
    func detach(_ node: NSObject?) {
        guard let node, let index = attached.firstIndex(where: { $0.objcObject == node.objcObject }) else { return }
        ObjCRuntime.release(attached.remove(at: index).objcObject)
    }

    @ObjCMethod("connect:to:format:") func connect(_ source: NSObject?, to destination: NSObject?, format: NSObject?) {}
    @ObjCMethod("connect:to:fromBus:toBus:format:")
    func connect(_ source: NSObject?, to destination: NSObject?, fromBus: UInt, toBus: UInt, format: NSObject?) {}
    @ObjCMethod("disconnectNodeOutput:") func disconnectNodeOutput(_ node: NSObject?) {}
    @ObjCMethod("disconnectNodeInput:") func disconnectNodeInput(_ node: NSObject?) {}
    @ObjCMethod("prepare") func prepare() {}
    @ObjCMethod("pause") func pause() { running = false }
    @ObjCMethod("stop") func stop() { running = false }
    @ObjCMethod("reset") func reset() {}
    @ObjCMethod("isRunning") func isRunning() -> Bool { running }

    @ObjCMethod("startAndReturnError:")
    func start(error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        running = true
        return true
    }
}
