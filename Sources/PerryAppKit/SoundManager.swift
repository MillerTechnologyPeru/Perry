import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// Carbon's Sound Manager (which the loader maps to AppKit), as programs of
// its time that play through sound channels call it, Bink's movies among
// them: a channel is an SDL audio stream on the default playback device.
// A bufferCmd's samples go to the stream as it's queued, so that buffer
// after buffer plays without a gap, and a callBackCmd calls the channel's
// callback once what was queued before it has played, which is when the
// Sound Manager would have come to it. Without SDL's audio SndNewChannel
// says there is no sound hardware, and programs go on without sound.

private let notEnoughHardwareErr: Int16 = -201
private let badChannel: Int16 = -205
private let badFormat: Int16 = -206

/// Sound Manager commands (Sound.h).
private enum Command: UInt16 {
    case null = 0, quiet = 3, flush = 4, reInit = 5, wait = 10, pause = 11, resume = 12, callBack = 13, sync = 14
    case available = 24, version = 25, volume = 46, getVolume = 47, sound = 80, buffer = 81, rateMultiplier = 86
}

/// SndChannel, as Sound.h lays it out (2-byte packing): its callBack at 8,
/// userInfo (the program's) at 12, qLength at 30; 1060 bytes with its
/// standard 128-command queue.
private enum ChannelLayout {
    static let size = 1060
    static let callBack = 8
    static let queueLength = 30
}

/// SndCommand: cmd, param1 (a short) and param2 (a long), 8 bytes.
private struct SoundCommand {
    var command: UInt16
    var param1: Int16
    var param2: Int32
}

private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

/// SDL3's audio streams.
private enum Audio {
    struct Spec: Equatable {
        var format: UInt32
        var channels: Int32
        var frequency: Int32
    }
    static let u8: UInt32 = 0x0008, s8: UInt32 = 0x8008, s16le: UInt32 = 0x8010, s16be: UInt32 = 0x9010
    static let defaultPlayback: UInt32 = 0xFFFF_FFFF

    nonisolated(unsafe) static var openStream: (@convention(c) (UInt32, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?)?
    nonisolated(unsafe) static var put: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32) -> Bool)?
    nonisolated(unsafe) static var queued: (@convention(c) (UnsafeMutableRawPointer?) -> Int32)?
    nonisolated(unsafe) static var clear: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    nonisolated(unsafe) static var setFormat: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool)?
    nonisolated(unsafe) static var setGain: (@convention(c) (UnsafeMutableRawPointer?, Float) -> Bool)?
    nonisolated(unsafe) static var setRatio: (@convention(c) (UnsafeMutableRawPointer?, Float) -> Bool)?
    nonisolated(unsafe) static var pauseDevice: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    nonisolated(unsafe) static var resumeDevice: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    nonisolated(unsafe) static var destroy: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?

    /// Whether SDL's audio started, once.
    static let available: Bool = {
        guard let library = dlopen("libSDL3.so.0", RTLD_NOW) else { return false }
        func bind<T>(_ name: String) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        typealias InitSubSystem = @convention(c) (UInt32) -> Bool
        guard let initSubSystem: InitSubSystem = bind("SDL_InitSubSystem"), initSubSystem(0x10) else {   // SDL_INIT_AUDIO
            appKitWarning("Sound Manager: no SDL3 audio; sound channels are unavailable")
            return false
        }
        openStream = bind("SDL_OpenAudioDeviceStream")
        put = bind("SDL_PutAudioStreamData")
        queued = bind("SDL_GetAudioStreamQueued")
        clear = bind("SDL_ClearAudioStream")
        setFormat = bind("SDL_SetAudioStreamFormat")
        setGain = bind("SDL_SetAudioStreamGain")
        setRatio = bind("SDL_SetAudioStreamFrequencyRatio")
        pauseDevice = bind("SDL_PauseAudioStreamDevice")
        resumeDevice = bind("SDL_ResumeAudioStreamDevice")
        destroy = bind("SDL_DestroyAudioStream")
        return openStream != nil && put != nil && queued != nil && clear != nil && setFormat != nil && destroy != nil
    }()
}

/// A sound header's samples: where they are, how many bytes, and their
/// format.
private struct Samples {
    var bytes: UnsafeRawPointer
    var count: Int
    var spec: Audio.Spec

    /// From a bufferCmd's SoundHeader, ExtSoundHeader or CmpSoundHeader
    /// (by its encode byte at 20), uncompressed.
    init?(header: UnsafeRawPointer) {
        func field<T>(_ offset: Int, _ type: T.Type) -> T { header.loadUnaligned(fromByteOffset: offset, as: type) }
        let pointer = field(0, UInt32.self)
        let rate = Int32(field(8, UInt32.self) >> 16)
        switch field(20, UInt8.self) {
        case 0x00:                                                          // stdSH: 8-bit unsigned mono
            count = Int(field(4, UInt32.self))
            spec = Audio.Spec(format: Audio.u8, channels: 1, frequency: rate)
            bytes = pointer != 0 ? UnsafeRawPointer(bitPattern: UInt(pointer))! : header + 22
        case 0xFF, 0xFE:                                                    // extSH, cmpSH
            let channels = Int32(field(4, UInt32.self))
            let frames = Int(field(22, UInt32.self))
            let compressed = field(20, UInt8.self) == 0xFE
            let bits = Int(compressed ? field(62, UInt16.self) : field(48, UInt16.self))
            // An ExtSoundHeader's 16-bit samples are in the machine's byte
            // order, an Intel Mac's little-endian; a CmpSoundHeader says.
            var format = bits == 16 ? Audio.s16le : Audio.u8
            if compressed {
                guard field(56, Int16.self) == 0 || field(56, Int16.self) == -1 else { return nil }   // notCompressed, fixedCompression with no codec
                switch field(40, UInt32.self) {
                case 0x736F_7774: format = Audio.s16le                      // 'sowt'
                case 0x7477_6F73: format = bits == 16 ? Audio.s16be : Audio.s8   // 'twos'
                case 0x7261_7720, 0: break                                  // 'raw ', none: by the size
                default: return nil
                }
            }
            guard channels > 0, bits == 8 || bits == 16 else { return nil }
            count = frames * Int(channels) * bits / 8
            spec = Audio.Spec(format: format, channels: channels, frequency: rate)
            bytes = pointer != 0 ? UnsafeRawPointer(bitPattern: UInt(pointer))! : header + 64
        default:
            return nil
        }
        guard spec.frequency > 0 else { return nil }
    }
}

/// A channel's stream and the callbacks waiting for it to play up to their
/// place.
private final class Channel {
    let memory: UnsafeMutableRawPointer
    let ownsMemory: Bool
    var stream: UnsafeMutableRawPointer?
    var spec: Audio.Spec?
    /// Bytes put into the stream so far.
    var pushed = 0
    var waiting: [(mark: Int, command: SoundCommand)] = []
    var running = true
    var paused = false
    /// The volume and the rate multiplier asked for, which a channel has
    /// from before its first buffer opens its stream.
    var gain: Float = 1
    var ratio: Float = 1
    var lock = pthread_mutex_t()
    nonisolated(unsafe) static var described = false
    /// Held while a callback runs: the Sound Manager calls them at
    /// interrupt time, one at a time, and programs count on it (MacSoft's
    /// Halo's returns at once when another channel's is running, and its
    /// sound never goes on).
    nonisolated(unsafe) static var callbacks: pthread_mutex_t = {
        var mutex = pthread_mutex_t()
        pthread_mutex_init(&mutex, nil)
        return mutex
    }()

    init(memory: UnsafeMutableRawPointer, ownsMemory: Bool) {
        self.memory = memory
        self.ownsMemory = ownsMemory
        pthread_mutex_init(&lock, nil)
    }

    var callback: Callback? {
        let address = memory.load(fromByteOffset: ChannelLayout.callBack, as: UInt.self)
        return address == 0 ? nil : unsafeBitCast(address, to: Callback.self)
    }

    /// Bytes of the stream played so far: put in, less what's still queued.
    /// SDL keeps a stream's last few frames back for its resampler until
    /// more come (7 of them from 44.1 kHz to a 48 kHz device), so what is
    /// queued never comes down to nothing: up to 64 frames left count as
    /// played, or a sound's end, and the callback after it, never come.
    var played: Int {
        let queued = Int(stream.map { Audio.queued!($0) } ?? 0)
        let frame = spec.map { Int($0.channels) * (($0.format & 0xFF) == 16 ? 2 : 1) } ?? 4
        return pushed - (queued <= 64 * frame ? 0 : queued)
    }

    func play(_ samples: Samples) -> Int16 {
        if stream == nil {
            var spec = samples.spec
            guard let opened = withUnsafePointer(to: &spec, { Audio.openStream!(Audio.defaultPlayback, $0, nil, nil) }) else {
                appKitWarning("Sound Manager: SDL could not open an audio stream")
                return notEnoughHardwareErr
            }
            stream = opened
            self.spec = spec
            if gain != 1 { _ = Audio.setGain?(opened, gain) }
            if ratio != 1 { _ = Audio.setRatio?(opened, ratio) }
            _ = Audio.resumeDevice?(opened)
        } else if spec != samples.spec {
            var spec = samples.spec
            _ = withUnsafePointer(to: &spec) { Audio.setFormat!(stream, $0, nil) }
            self.spec = spec
        }
        guard samples.count > 0 else { return 0 }
        _ = Audio.put!(stream, samples.bytes, Int32(samples.count))
        pushed += samples.count
        return 0
    }

    /// A command, from SndDoCommand or SndDoImmediate alike: buffers are
    /// put in the stream at once, and a callBackCmd waits for what came
    /// before it to play.
    func perform(_ command: SoundCommand) -> Int16 {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        switch Command(rawValue: command.command) {
        case .buffer, .sound:
            guard let header = UnsafeRawPointer(bitPattern: UInt(UInt32(bitPattern: command.param2))) else { return badFormat }
            guard let samples = Samples(header: header) else {
                Trace.log("Sound Manager: a sound header (encode \(header.load(fromByteOffset: 20, as: UInt8.self))) it can't play")
                return badFormat
            }
            if !Channel.described {
                Channel.described = true
                Trace.log("Sound Manager: first buffer, encode \(header.load(fromByteOffset: 20, as: UInt8.self)), \(samples.spec)")
            }
            return play(samples)
        case .callBack:
            waiting.append((pushed, command))
            Channels.wake()
        case .quiet:
            if let stream { _ = Audio.clear!(stream) }
            pushed = played
            waiting.removeAll()
        case .flush:
            waiting.removeAll()
        case .pause:
            paused = true
            if let stream { _ = Audio.pauseDevice?(stream) }
        case .resume:
            paused = false
            if let stream { _ = Audio.resumeDevice?(stream) }
        case .volume:
            // Left in the low word, right in the high; 0x100 is full.
            let level = max(command.param2 & 0xFFFF, (command.param2 >> 16) & 0xFFFF)
            gain = Float(level) / 256
            if let stream { _ = Audio.setGain?(stream, gain) }
        case .rateMultiplier:
            // A Fixed: 1.0 plays at the sound's own rate.
            let multiplier = Float(UInt32(bitPattern: command.param2)) / 65536
            guard multiplier >= 0.01, multiplier <= 100 else { break }
            ratio = multiplier
            if let stream { _ = Audio.setRatio?(stream, ratio) }
        default:
            break
        }
        return 0
    }

    /// The callbacks whose place has played, taken off the list.
    func due() -> [SoundCommand] {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        // A callback is called a little before its place has played, 40 ms
        // of sound ahead: the Sound Manager goes from one buffer to the next
        // at interrupt time, with no gap, and a program that streams a sound
        // in short buffers, each queued by the callback after the one before
        // (MacSoft's Halo, 12 ms at a time), has gaps between them if each
        // callback waits for the stream to run dry.
        guard running, !waiting.isEmpty else { return [] }
        let lead = spec.map { Int($0.frequency) * Int($0.channels) * (($0.format & 0xFF) == 16 ? 2 : 1) * 40 / 1000 } ?? 0
        let played = self.played + lead
        var due: [SoundCommand] = []
        while let first = waiting.first, first.mark <= played {
            due.append(first.command)
            waiting.removeFirst()
        }
        return due
    }

    /// Calls the callbacks whose places have played; whether more wait.
    func callDue() -> Bool {
        for command in due() {
            var argument = command
            // One at a time, and none once the channel is disposed of:
            // SndDisposeChannel takes this lock after it stops the channel.
            pthread_mutex_lock(&Channel.callbacks)
            pthread_mutex_lock(&lock)
            let running = self.running
            pthread_mutex_unlock(&lock)
            if running { callback?(memory, &argument) }
            pthread_mutex_unlock(&Channel.callbacks)
        }
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return running && !waiting.isEmpty
    }

    /// Whether everything put in has played.
    var drained: Bool {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return played >= pushed
    }

    /// Whether the channel is making sound or has commands still to come
    /// to, and whether it is paused: an SCStatus's scChannelBusy and
    /// scChannelPaused.
    var status: (busy: Bool, paused: Bool) {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return (played < pushed || !waiting.isEmpty, paused)
    }
}

private enum Channels {
    nonisolated(unsafe) static var all: [UnsafeMutableRawPointer: Channel] = [:]
    nonisolated(unsafe) static var lock = pthread_mutex_t()
    nonisolated(unsafe) static let initialized: Bool = {
        pthread_mutex_init(&lock, nil)
        pthread_mutex_init(&waking, nil)
        pthread_cond_init(&woken, nil)
        return true
    }()

    static func find(_ memory: UnsafeMutableRawPointer?) -> Channel? {
        guard let memory, initialized else { return nil }
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return all[memory]
    }

    // One thread calls every channel's callbacks, as the Sound Manager's
    // interrupt did: it looks every 2 ms while a callback waits for its
    // place to play, and sleeps while none does. A thread for each channel
    // woke 500 times a second whether its channel played or not, and a
    // program with a pool of channels has dozens (MacSoft's Halo, 48).
    nonisolated(unsafe) static var thread = pthread_t()
    nonisolated(unsafe) static var waking = pthread_mutex_t()
    nonisolated(unsafe) static var woken = pthread_cond_t()
    nonisolated(unsafe) static var requested = false
    nonisolated(unsafe) static let started: Bool = {
        guard initialized else { return false }
        return pthread_create(&thread, nil, { _ in
            Channels.serve()
            return nil
        }, nil) == 0
    }()

    /// A callback now waits: the thread looks for it.
    static func wake() {
        pthread_mutex_lock(&waking)
        requested = true
        pthread_cond_signal(&woken)
        pthread_mutex_unlock(&waking)
    }

    private static func serve() {
        while true {
            pthread_mutex_lock(&lock)
            let channels = Array(all.values)
            pthread_mutex_unlock(&lock)
            var waiting = false
            for channel in channels where channel.callDue() { waiting = true }
            if waiting {
                usleep(2000)
            } else {
                pthread_mutex_lock(&waking)
                while !requested { pthread_cond_wait(&woken, &waking) }
                requested = false
                pthread_mutex_unlock(&waking)
            }
        }
    }
}

/// OSErr SndNewChannel(SndChannelPtr *chan, short synth, long init,
/// SndCallBackUPP userRoutine): a channel in the program's memory, or in
/// memory made for it when *chan is NULL.
@c(_SndNewChannel)
public func SndNewChannel(_ channel: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ synth: Int16, _ initialize: Int,
                          _ callback: UnsafeRawPointer?) -> Int16 {
    guard let channel else { return badChannel }
    guard Audio.available, Channels.initialized, Channels.started else { return notEnoughHardwareErr }
    let owns = channel.pointee == nil
    let memory = channel.pointee ?? calloc(1, ChannelLayout.size)!
    if owns { memory.storeBytes(of: Int16(128), toByteOffset: ChannelLayout.queueLength, as: Int16.self) }
    memory.storeBytes(of: UInt(bitPattern: callback), toByteOffset: ChannelLayout.callBack, as: UInt.self)
    let state = Channel(memory: memory, ownsMemory: owns)
    pthread_mutex_lock(&Channels.lock)
    Channels.all[memory] = state
    pthread_mutex_unlock(&Channels.lock)
    channel.pointee = memory
    return 0
}

/// OSErr SndDisposeChannel(SndChannelPtr, Boolean quietNow): what's queued
/// plays out first unless quietNow.
@c(_SndDisposeChannel)
public func SndDisposeChannel(_ channel: UnsafeMutableRawPointer?, _ quietNow: UInt8) -> Int16 {
    guard let state = Channels.find(channel) else { return badChannel }
    if quietNow == 0 {
        for _ in 0..<2000 where !state.drained { usleep(5000) }        // at most 10 s
    }
    pthread_mutex_lock(&Channels.lock)
    Channels.all[state.memory] = nil
    pthread_mutex_unlock(&Channels.lock)
    pthread_mutex_lock(&state.lock)
    state.running = false
    state.waiting.removeAll()
    pthread_mutex_unlock(&state.lock)
    // A callback of this channel's that is running ends before its memory
    // goes; one disposing of a channel is that callback, and can't wait.
    if pthread_equal(pthread_self(), Channels.thread) == 0 {
        pthread_mutex_lock(&Channel.callbacks)
        pthread_mutex_unlock(&Channel.callbacks)
    }
    if let stream = state.stream { Audio.destroy!(stream) }
    if state.ownsMemory { free(state.memory) }
    return 0
}

/// OSErr SndDoCommand(SndChannelPtr, const SndCommand *, Boolean noWait).
@c(_SndDoCommand)
public func SndDoCommand(_ channel: UnsafeMutableRawPointer?, _ command: UnsafeRawPointer?, _ noWait: UInt8) -> Int16 {
    guard let state = Channels.find(channel), let command else { return badChannel }
    return state.perform(command.loadUnaligned(as: SoundCommand.self))
}

/// OSErr SndDoImmediate(SndChannelPtr, const SndCommand *).
@c(_SndDoImmediate)
public func SndDoImmediate(_ channel: UnsafeMutableRawPointer?, _ command: UnsafeRawPointer?) -> Int16 {
    guard let state = Channels.find(channel), let command else { return badChannel }
    return state.perform(command.loadUnaligned(as: SoundCommand.self))
}

/// OSErr SndChannelStatus(SndChannelPtr, short length, SCStatusPtr): an
/// SCStatus, 24 bytes, whose scChannelBusy is at 12 and scChannelPaused at
/// 14. A program with a pool of channels takes one that isn't busy for its
/// next sound, and quiets it first.
@c(_SndChannelStatus)
public func SndChannelStatus(_ channel: UnsafeMutableRawPointer?, _ length: Int16, _ status: UnsafeMutableRawPointer?) -> Int16 {
    guard let state = Channels.find(channel) else { return badChannel }
    guard let status, length > 0 else { return 0 }
    memset(status, 0, Int(length))
    let (busy, paused) = state.status
    if length > 12 { status.storeBytes(of: busy ? 1 : 0, toByteOffset: 12, as: UInt8.self) }
    if length > 14 { status.storeBytes(of: paused ? 1 : 0, toByteOffset: 14, as: UInt8.self) }
    return 0
}

/// NumVersion SndSoundManagerVersion(void): 3.6.8, Mac OS X's.
@c(_SndSoundManagerVersion)
public func SndSoundManagerVersion() -> UInt32 { 0x0368_8000 }
#endif
