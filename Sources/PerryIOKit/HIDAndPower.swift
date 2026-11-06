import PerryObjCInterop

// HID managers and power. A HID manager opens but finds no devices, so
// its callbacks are never called: games read controllers through
// GameController here. There are no power sources (the machine runs on
// AC power, with no battery) and no sleep or wake notifications.

@ObjCClass("__IOHIDManager")
final class IOHIDManagerObject: NSObject {}

@c(_IOHIDManagerCreate)
public func IOHIDManagerCreate(_ allocator: UnsafeRawPointer?, _ options: UInt32) -> UnsafeMutableRawPointer? {
    NSObject.opaque("__IOHIDManager")
}

@c(_IOHIDManagerOpen) public func IOHIDManagerOpen(_ manager: UnsafeMutableRawPointer?, _ options: UInt32) -> Int32 { IOReturn.success }
@c(_IOHIDManagerClose) public func IOHIDManagerClose(_ manager: UnsafeMutableRawPointer?, _ options: UInt32) -> Int32 { IOReturn.success }
@c(_IOHIDManagerSetDeviceMatching)
public func IOHIDManagerSetDeviceMatching(_ manager: UnsafeMutableRawPointer?, _ matching: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerSetDeviceMatchingMultiple)
public func IOHIDManagerSetDeviceMatchingMultiple(_ manager: UnsafeMutableRawPointer?, _ multiple: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerSetInputValueMatching)
public func IOHIDManagerSetInputValueMatching(_ manager: UnsafeMutableRawPointer?, _ matching: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerSetInputValueMatchingMultiple)
public func IOHIDManagerSetInputValueMatchingMultiple(_ manager: UnsafeMutableRawPointer?, _ multiple: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerRegisterDeviceMatchingCallback)
public func IOHIDManagerRegisterDeviceMatchingCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                       _ context: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerRegisterDeviceRemovalCallback)
public func IOHIDManagerRegisterDeviceRemovalCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                      _ context: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerRegisterInputValueCallback)
public func IOHIDManagerRegisterInputValueCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                   _ context: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerRegisterInputReportCallback)
public func IOHIDManagerRegisterInputReportCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                    _ context: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerScheduleWithRunLoop)
public func IOHIDManagerScheduleWithRunLoop(_ manager: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                            _ mode: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerUnscheduleFromRunLoop)
public func IOHIDManagerUnscheduleFromRunLoop(_ manager: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                              _ mode: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerSetDispatchQueue)
public func IOHIDManagerSetDispatchQueue(_ manager: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerActivate) public func IOHIDManagerActivate(_ manager: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerCancel) public func IOHIDManagerCancel(_ manager: UnsafeMutableRawPointer?) {}

/// No devices: NULL, as IOKit answers for an empty set.
@c(_IOHIDManagerCopyDevices) public func IOHIDManagerCopyDevices(_ manager: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

// MARK: - Power

/// The power sources' snapshot: none.
@c(_IOPSCopyPowerSourcesInfo) public func IOPSCopyPowerSourcesInfo() -> UnsafeMutableRawPointer? { NSObject.opaque("__IOKitOpaque") }

@c(_IOPSCopyPowerSourcesList)
public func IOPSCopyPowerSourcesList(_ info: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(NSMutableArray.empty().objcObject)
}

@c(_IOPSGetPowerSourceDescription)
public func IOPSGetPowerSourceDescription(_ info: UnsafeMutableRawPointer?, _ source: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

@c(_IOPSGetProvidingPowerSourceType)
public func IOPSGetProvidingPowerSourceType(_ info: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { PowerKeys.kIOPMACPowerKeyObject }

/// kIOPSTimeRemainingUnlimited: on AC power.
@c(_IOPSGetTimeRemainingEstimate) public func IOPSGetTimeRemainingEstimate() -> Double { -2 }

@c(_IOPSNotificationCreateRunLoopSource)
public func IOPSNotificationCreateRunLoopSource(_ callback: UnsafeRawPointer?, _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NSObject.opaque("__IOKitOpaque")
}

@ObjCConstants
enum PowerKeys {
    static let kIOPMACPowerKey = "AC Power"
    static let kIOPMBatteryPowerKey = "Battery Power"
}

/// Sleep and wake notifications never come: a connection with a port
/// whose source nothing signals.
@c(_IORegisterForSystemPower)
public func IORegisterForSystemPower(_ refcon: UnsafeMutableRawPointer?, _ port: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                     _ callback: UnsafeRawPointer?, _ notifier: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    port?.pointee = NSObject.opaque("__IOKitOpaque")
    notifier?.pointee = Registry.makeIterator([])
    return 0x3001
}

@c(_IODeregisterForSystemPower) public func IODeregisterForSystemPower(_ notifier: UnsafeMutablePointer<UInt32>?) -> Int32 { IOReturn.success }
@c(_IOAllowPowerChange) public func IOAllowPowerChange(_ connection: UInt32, _ argument: Int) -> Int32 { IOReturn.success }
@c(_IOCancelPowerChange) public func IOCancelPowerChange(_ connection: UInt32, _ argument: Int) -> Int32 { IOReturn.success }
@c(_IOServiceClose) public func IOServiceClose(_ connection: UInt32) -> Int32 { IOReturn.success }

/// Assertions that keep the display awake are granted and change nothing.
@c(_IOPMAssertionCreateWithName)
public func IOPMAssertionCreateWithName(_ type: UnsafeMutableRawPointer?, _ level: UInt32, _ name: UnsafeMutableRawPointer?,
                                        _ id: UnsafeMutablePointer<UInt32>?) -> Int32 {
    id?.pointee = Registry.makeIterator([])
    return IOReturn.success
}

@c(_IOPMAssertionCreateWithDescription)
public func IOPMAssertionCreateWithDescription(_ type: UnsafeMutableRawPointer?, _ name: UnsafeMutableRawPointer?, _ details: UnsafeMutableRawPointer?,
                                               _ reason: UnsafeMutableRawPointer?, _ bundle: UnsafeMutableRawPointer?, _ timeout: Double,
                                               _ action: UnsafeMutableRawPointer?, _ id: UnsafeMutablePointer<UInt32>?) -> Int32 {
    IOPMAssertionCreateWithName(type, 255, name, id)
}

@c(_IOPMAssertionRelease)
public func IOPMAssertionRelease(_ id: UInt32) -> Int32 {
    Registry.release(id)
    return IOReturn.success
}

@c(_IOPMAssertionDeclareUserActivity)
public func IOPMAssertionDeclareUserActivity(_ name: UnsafeMutableRawPointer?, _ type: UInt32, _ id: UnsafeMutablePointer<UInt32>?) -> Int32 {
    IOPMAssertionCreateWithName(nil, 255, name, id)
}
