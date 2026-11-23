// IOKit's error codes. The header builds them with iokit_common_err(), a
// macro Swift doesn't import, so the overlay gives each one as a variable.

/// `iokit_common_err(code)`: the IOKit system (0x38) and its common
/// subsystem (0) over the code.
private func iokitCommonError(_ code: UInt32) -> IOReturn {
    IOReturn(bitPattern: (0x38 << 26) | (0 << 14) | code)
}

public var kIOReturnError: IOReturn { iokitCommonError(0x2bc) }
public var kIOReturnNoMemory: IOReturn { iokitCommonError(0x2bd) }
public var kIOReturnNoResources: IOReturn { iokitCommonError(0x2be) }
public var kIOReturnIPCError: IOReturn { iokitCommonError(0x2bf) }
public var kIOReturnNoDevice: IOReturn { iokitCommonError(0x2c0) }
public var kIOReturnNotPrivileged: IOReturn { iokitCommonError(0x2c1) }
public var kIOReturnBadArgument: IOReturn { iokitCommonError(0x2c2) }
public var kIOReturnLockedRead: IOReturn { iokitCommonError(0x2c3) }
public var kIOReturnLockedWrite: IOReturn { iokitCommonError(0x2c4) }
public var kIOReturnExclusiveAccess: IOReturn { iokitCommonError(0x2c5) }
public var kIOReturnBadMessageID: IOReturn { iokitCommonError(0x2c6) }
public var kIOReturnUnsupported: IOReturn { iokitCommonError(0x2c7) }
public var kIOReturnVMError: IOReturn { iokitCommonError(0x2c8) }
public var kIOReturnInternalError: IOReturn { iokitCommonError(0x2c9) }
public var kIOReturnIOError: IOReturn { iokitCommonError(0x2ca) }
public var kIOReturnCannotLock: IOReturn { iokitCommonError(0x2cc) }
public var kIOReturnNotOpen: IOReturn { iokitCommonError(0x2cd) }
public var kIOReturnNotReadable: IOReturn { iokitCommonError(0x2ce) }
public var kIOReturnNotWritable: IOReturn { iokitCommonError(0x2cf) }
public var kIOReturnNotAligned: IOReturn { iokitCommonError(0x2d0) }
public var kIOReturnBadMedia: IOReturn { iokitCommonError(0x2d1) }
public var kIOReturnStillOpen: IOReturn { iokitCommonError(0x2d2) }
public var kIOReturnRLDError: IOReturn { iokitCommonError(0x2d3) }
public var kIOReturnDMAError: IOReturn { iokitCommonError(0x2d4) }
public var kIOReturnBusy: IOReturn { iokitCommonError(0x2d5) }
public var kIOReturnTimeout: IOReturn { iokitCommonError(0x2d6) }
public var kIOReturnOffline: IOReturn { iokitCommonError(0x2d7) }
public var kIOReturnNotReady: IOReturn { iokitCommonError(0x2d8) }
public var kIOReturnNotAttached: IOReturn { iokitCommonError(0x2d9) }
public var kIOReturnNoChannels: IOReturn { iokitCommonError(0x2da) }
public var kIOReturnNoSpace: IOReturn { iokitCommonError(0x2db) }
public var kIOReturnPortExists: IOReturn { iokitCommonError(0x2dd) }
public var kIOReturnCannotWire: IOReturn { iokitCommonError(0x2de) }
public var kIOReturnNoInterrupt: IOReturn { iokitCommonError(0x2df) }
public var kIOReturnNoFrames: IOReturn { iokitCommonError(0x2e0) }
public var kIOReturnMessageTooLarge: IOReturn { iokitCommonError(0x2e1) }
public var kIOReturnNotPermitted: IOReturn { iokitCommonError(0x2e2) }
public var kIOReturnNoPower: IOReturn { iokitCommonError(0x2e3) }
public var kIOReturnNoMedia: IOReturn { iokitCommonError(0x2e4) }
public var kIOReturnUnformattedMedia: IOReturn { iokitCommonError(0x2e5) }
public var kIOReturnUnsupportedMode: IOReturn { iokitCommonError(0x2e6) }
public var kIOReturnUnderrun: IOReturn { iokitCommonError(0x2e7) }
public var kIOReturnOverrun: IOReturn { iokitCommonError(0x2e8) }
public var kIOReturnDeviceError: IOReturn { iokitCommonError(0x2e9) }
public var kIOReturnNoCompletion: IOReturn { iokitCommonError(0x2ea) }
public var kIOReturnAborted: IOReturn { iokitCommonError(0x2eb) }
public var kIOReturnNoBandwidth: IOReturn { iokitCommonError(0x2ec) }
public var kIOReturnNotResponding: IOReturn { iokitCommonError(0x2ed) }
public var kIOReturnIsoTooOld: IOReturn { iokitCommonError(0x2ee) }
public var kIOReturnIsoTooNew: IOReturn { iokitCommonError(0x2ef) }
public var kIOReturnNotFound: IOReturn { iokitCommonError(0x2f0) }
public var kIOReturnInvalid: IOReturn { iokitCommonError(0x1) }
