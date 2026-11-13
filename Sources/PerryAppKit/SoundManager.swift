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
    case available = 24, version = 25, volume = 46, getVolume = 47, sound = 80, buffer = 81
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
    var lock = pthread_mutex_t()
    var thread = pthread_t()
    nonisolated(unsafe) static var described = false

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
    var played: Int { pushed - Int(stream.map { Audio.queued!($0) } ?? 0) }

    func play(_ samples: Samples) -> Int16 {
        if stream == nil {
            var spec = samples.spec
            guard let opened = withUnsafePointer(to: &spec, { Audio.openStream!(Audio.defaultPlayback, $0, nil, nil) }) else {
                appKitWarning("Sound Manager: SDL could not open an audio stream")
                return notEnoughHardwareErr
            }
            stream = opened
            self.spec = spec
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
        case .quiet:
            if let stream { _ = Audio.clear!(stream) }
            pushed = played
            waiting.removeAll()
        case .flush:
            waiting.removeAll()
        case .pause:
            if let stream { _ = Audio.pauseDevice?(stream) }
        case .resume:
            if let stream { _ = Audio.resumeDevice?(stream) }
        case .volume:
            // Left in the low word, right in the high; 0x100 is full.
            let level = max(command.param2 & 0xFFFF, (command.param2 >> 16) & 0xFFFF)
            if let stream { _ = Audio.setGain?(stream, Float(level) / 256) }
        default:
            break
        }
        return 0
    }

    /// The callbacks whose place has played, taken off the list.
    func due() -> [SoundCommand] {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        let played = self.played
        var due: [SoundCommand] = []
        while let first = waiting.first, first.mark <= played {
            due.append(first.command)
            waiting.removeFirst()
        }
        return due
    }

    /// Calls the callbacks as their places play, every 5 ms, until the
    /// channel goes.
    func run() {
        while true {
            pthread_mutex_lock(&lock)
            let running = self.running
            pthread_mutex_unlock(&lock)
            guard running else { return }
            for command in due() {
                pthread_mutex_lock(&lock)
                let disposed = !self.running
                pthread_mutex_unlock(&lock)
                if disposed { return }
                var argument = command
                callback?(memory, &argument)
            }
            usleep(5000)
        }
    }

    /// Whether everything put in has played.
    var drained: Bool {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return played >= pushed
    }
}

private enum Channels {
    nonisolated(unsafe) static var all: [UnsafeMutableRawPointer: Channel] = [:]
    nonisolated(unsafe) static var lock = pthread_mutex_t()
    nonisolated(unsafe) static let initialized: Bool = {
        pthread_mutex_init(&lock, nil)
        return true
    }()

    static func find(_ memory: UnsafeMutableRawPointer?) -> Channel? {
        guard let memory, initialized else { return nil }
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        return all[memory]
    }
}

/// OSErr SndNewChannel(SndChannelPtr *chan, short synth, long init,
/// SndCallBackUPP userRoutine): a channel in the program's memory, or in
/// memory made for it when *chan is NULL.
@c(_SndNewChannel)
public func SndNewChannel(_ channel: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ synth: Int16, _ initialize: Int,
                          _ callback: UnsafeRawPointer?) -> Int16 {
    guard let channel else { return badChannel }
    guard Audio.available, Channels.initialized else { return notEnoughHardwareErr }
    let owns = channel.pointee == nil
    let memory = channel.pointee ?? calloc(1, ChannelLayout.size)!
    if owns { memory.storeBytes(of: Int16(128), toByteOffset: ChannelLayout.queueLength, as: Int16.self) }
    memory.storeBytes(of: UInt(bitPattern: callback), toByteOffset: ChannelLayout.callBack, as: UInt.self)
    let state = Channel(memory: memory, ownsMemory: owns)
    let unmanaged = Unmanaged.passRetained(state)
    guard pthread_create(&state.thread, nil, { argument in
        Unmanaged<Channel>.fromOpaque(argument!).takeRetainedValue().run()
        return nil
    }, unmanaged.toOpaque()) == 0 else {
        unmanaged.release()
        if owns { free(memory) }
        return notEnoughHardwareErr
    }
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
    // A callback disposing of its own channel can't wait for its thread.
    if pthread_equal(pthread_self(), state.thread) == 0 { pthread_join(state.thread, nil) } else { pthread_detach(state.thread) }
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

@c(_SndChannelStatus)
public func SndChannelStatus(_ channel: UnsafeMutableRawPointer?, _ length: Int16, _ status: UnsafeMutableRawPointer?) -> Int16 {
    guard Channels.find(channel) != nil else { return badChannel }
    if let status, length > 0 { memset(status, 0, Int(length)) }
    return 0
}

/// NumVersion SndSoundManagerVersion(void): 3.6.8, Mac OS X's.
@c(_SndSoundManagerVersion)
public func SndSoundManagerVersion() -> UInt32 { 0x0368_8000 }
#endif
