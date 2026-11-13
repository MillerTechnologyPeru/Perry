import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// Carbon's Sound Manager (which the loader maps to AppKit), as programs of
// its time that played through sound channels call it: there are no
// channels here, so SndNewChannel says there is no sound hardware and
// they go on without sound, as they would on a Mac with none. Video
// libraries such as Bink's play their movies silently then.

/// notEnoughHardwareErr: no channel can be had.
private let notEnoughHardwareErr: Int16 = -201
/// badChannel: the channel isn't one.
private let badChannel: Int16 = -205

/// OSErr SndNewChannel(SndChannelPtr *, short synth, long init,
/// SndCallBackUPP): none, notEnoughHardwareErr.
@c(_SndNewChannel)
public func SndNewChannel(_ channel: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ synth: Int16, _ initialize: Int,
                          _ callback: UnsafeRawPointer?) -> Int16 {
    notEnoughHardwareErr
}

@c(_SndDisposeChannel)
public func SndDisposeChannel(_ channel: UnsafeMutableRawPointer?, _ quietNow: UInt8) -> Int16 { badChannel }

@c(_SndDoCommand)
public func SndDoCommand(_ channel: UnsafeMutableRawPointer?, _ command: UnsafeRawPointer?, _ noWait: UInt8) -> Int16 { badChannel }

@c(_SndDoImmediate)
public func SndDoImmediate(_ channel: UnsafeMutableRawPointer?, _ command: UnsafeRawPointer?) -> Int16 { badChannel }

@c(_SndChannelStatus)
public func SndChannelStatus(_ channel: UnsafeMutableRawPointer?, _ length: Int16, _ status: UnsafeMutableRawPointer?) -> Int16 {
    badChannel
}
#endif
