import PerryObjCInterop

// HID managers and power. A HID manager finds the HID devices there are,
// SDL3's gamepads (Gamepads.swift), those its matching dictionaries
// match: by DeviceUsagePage and DeviceUsage, against each of a device's
// usages, and by any other property's value. Once scheduled, on a run
// loop or a queue, it calls its matching callback for each device it
// finds and its removal callback for each that goes, and its input value
// callback with each value that changes, all on the main queue. There are
// no power sources (the machine runs on AC power, with no battery) and no
// sleep or wake notifications.

@ObjCClass("__IOHIDManager")
final class IOHIDManagerObject: NSObject {
    @ObjCMethod("init")
    required override init() { super.init() }

    /// The matching dictionaries: nil matches every device, none matches
    /// none.
    var matching: [NSDictionary]? = []
    var deviceMatching: (function: UnsafeRawPointer, context: UnsafeMutableRawPointer?)?
    var deviceRemoval: (function: UnsafeRawPointer, context: UnsafeMutableRawPointer?)?
    var inputValue: (function: UnsafeRawPointer, context: UnsafeMutableRawPointer?)?
    /// Whether it calls its callbacks: scheduled, or activated on a queue.
    var scheduled = false
    /// The devices its matching callback was called with.
    var reported: [HIDDevice] = []

    func matches(_ device: HIDDevice) -> Bool {
        guard let matching else { return true }
        return matching.contains { HIDManagers.matches(device, $0) }
    }

    var matchingDevices: [HIDDevice] { Gamepads.devices.filter(matches) }
}

/// The managers there are, and what they hear.
enum HIDManagers {
    /// Those scheduled, which are called back; kept until unscheduled or
    /// closed.
    nonisolated(unsafe) private static var scheduled: [IOHIDManagerObject] = []

    static func manager(_ pointer: UnsafeMutableRawPointer?) -> IOHIDManagerObject? {
        pointer.map { NSObject(objcObject: $0, ownership: .retain).as(IOHIDManagerObject.self) } ?? nil
    }

    /// Whether `device` has every property `dictionary` asks for.
    static func matches(_ device: HIDDevice, _ dictionary: NSDictionary) -> Bool {
        let page = dictionary.object("DeviceUsagePage")?.longLongValue()
        let usage = dictionary.object("DeviceUsage")?.longLongValue()
        // The page and usage are compared as a pair the device has.
        if page != nil || usage != nil {
            let pair = device.usages.contains { pair in
                (page == nil || page == Int64(pair.page)) && (usage == nil || usage == Int64(pair.usage))
            }
            guard pair else { return false }
        }
        for key in dictionary.keys() where key != "DeviceUsagePage" && key != "DeviceUsage" {
            guard let wanted = dictionary.object(key), let actual = device.property(key), actual.isEqual(wanted) else { return false }
        }
        return true
    }

    static func schedule(_ manager: IOHIDManagerObject) {
        manager.scheduled = true
        if !scheduled.contains(where: { $0 === manager }) { scheduled.append(manager) }
        Gamepads.start()
    }

    static func unschedule(_ manager: IOHIDManagerObject) {
        manager.scheduled = false
        scheduled.removeAll { $0 === manager }
    }

    /// Calls each scheduled manager back with the devices it matches that
    /// came and those it was told of that went.
    static func reportDevices() {
        let present = Gamepads.devices
        for manager in scheduled where manager.scheduled {
            let gone = manager.reported.filter { device in !present.contains { $0 === device } }
            manager.reported.removeAll { device in gone.contains { $0 === device } }
            for device in gone {
                if let (function, context) = manager.deviceRemoval {
                    HIDCallbacks.device(function)(context, IOReturn.success, manager.objcObject, device.objcObject)
                }
            }
            for device in manager.matchingDevices where !manager.reported.contains(where: { $0 === device }) {
                manager.reported.append(device)
                if let (function, context) = manager.deviceMatching {
                    HIDCallbacks.device(function)(context, IOReturn.success, manager.objcObject, device.objcObject)
                }
            }
        }
    }

    /// Calls the input value callbacks of the managers that found `device`.
    static func deliver(_ value: HIDValue, from device: HIDDevice) {
        for manager in scheduled where manager.scheduled && manager.reported.contains(where: { $0 === device }) {
            if let (function, context) = manager.inputValue {
                HIDCallbacks.value(function)(context, IOReturn.success, manager.objcObject, value.objcObject)
            }
        }
    }

    /// The dictionaries of a CFArray of them.
    static func dictionaries(_ array: UnsafeMutableRawPointer?) -> [NSDictionary]? {
        guard let array else { return nil }
        return NSArray(objcObject: array, ownership: .retain).objects().map { NSDictionary(objcObject: $0.objcObject, ownership: .retain) }
    }
}

@c(_IOHIDManagerCreate)
public func IOHIDManagerCreate(_ allocator: UnsafeRawPointer?, _ options: UInt32) -> UnsafeMutableRawPointer? {
    // +1 while the manager is still in use: the new manager's only reference
    // is Swift's until then.
    IOHIDManagerObject().objCOwnedReturnValue()
}

/// Opening finds the devices there are now, for IOHIDManagerCopyDevices.
@c(_IOHIDManagerOpen)
public func IOHIDManagerOpen(_ manager: UnsafeMutableRawPointer?, _ options: UInt32) -> Int32 {
    guard HIDManagers.manager(manager) != nil else { return IOReturn.badArgument }
    Gamepads.start()
    return IOReturn.success
}

@c(_IOHIDManagerClose)
public func IOHIDManagerClose(_ manager: UnsafeMutableRawPointer?, _ options: UInt32) -> Int32 {
    guard let manager = HIDManagers.manager(manager) else { return IOReturn.badArgument }
    HIDManagers.unschedule(manager)
    return IOReturn.success
}

/// A dictionary, or NULL for every device.
@c(_IOHIDManagerSetDeviceMatching)
public func IOHIDManagerSetDeviceMatching(_ manager: UnsafeMutableRawPointer?, _ matching: UnsafeMutableRawPointer?) {
    guard let manager = HIDManagers.manager(manager) else { return }
    manager.matching = matching.map { [NSDictionary(objcObject: $0, ownership: .retain)] }
}

/// An array of dictionaries, a device matching any of them; NULL for
/// every device.
@c(_IOHIDManagerSetDeviceMatchingMultiple)
public func IOHIDManagerSetDeviceMatchingMultiple(_ manager: UnsafeMutableRawPointer?, _ multiple: UnsafeMutableRawPointer?) {
    guard let manager = HIDManagers.manager(manager) else { return }
    manager.matching = HIDManagers.dictionaries(multiple)
}

/// Every value goes to the callback: input value matching isn't applied.
@c(_IOHIDManagerSetInputValueMatching)
public func IOHIDManagerSetInputValueMatching(_ manager: UnsafeMutableRawPointer?, _ matching: UnsafeMutableRawPointer?) {}
@c(_IOHIDManagerSetInputValueMatchingMultiple)
public func IOHIDManagerSetInputValueMatchingMultiple(_ manager: UnsafeMutableRawPointer?, _ multiple: UnsafeMutableRawPointer?) {}

@c(_IOHIDManagerRegisterDeviceMatchingCallback)
public func IOHIDManagerRegisterDeviceMatchingCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                       _ context: UnsafeMutableRawPointer?) {
    HIDManagers.manager(manager)?.deviceMatching = callback.map { ($0, context) }
}

@c(_IOHIDManagerRegisterDeviceRemovalCallback)
public func IOHIDManagerRegisterDeviceRemovalCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                      _ context: UnsafeMutableRawPointer?) {
    HIDManagers.manager(manager)?.deviceRemoval = callback.map { ($0, context) }
}

@c(_IOHIDManagerRegisterInputValueCallback)
public func IOHIDManagerRegisterInputValueCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                   _ context: UnsafeMutableRawPointer?) {
    HIDManagers.manager(manager)?.inputValue = callback.map { ($0, context) }
}

/// Input reports aren't made: values come to the input value callback.
@c(_IOHIDManagerRegisterInputReportCallback)
public func IOHIDManagerRegisterInputReportCallback(_ manager: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                                    _ context: UnsafeMutableRawPointer?) {}

/// Callbacks come on the main queue, whichever run loop it is scheduled
/// on: the main one, as games schedule theirs.
@c(_IOHIDManagerScheduleWithRunLoop)
public func IOHIDManagerScheduleWithRunLoop(_ manager: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                            _ mode: UnsafeMutableRawPointer?) {
    guard let manager = HIDManagers.manager(manager) else { return }
    HIDManagers.schedule(manager)
}

@c(_IOHIDManagerUnscheduleFromRunLoop)
public func IOHIDManagerUnscheduleFromRunLoop(_ manager: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                              _ mode: UnsafeMutableRawPointer?) {
    guard let manager = HIDManagers.manager(manager) else { return }
    HIDManagers.unschedule(manager)
}

/// A queue is taken as the main one, and the manager is called back once
/// activated.
@c(_IOHIDManagerSetDispatchQueue)
public func IOHIDManagerSetDispatchQueue(_ manager: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {}

@c(_IOHIDManagerActivate)
public func IOHIDManagerActivate(_ manager: UnsafeMutableRawPointer?) {
    guard let manager = HIDManagers.manager(manager) else { return }
    HIDManagers.schedule(manager)
}

@c(_IOHIDManagerCancel)
public func IOHIDManagerCancel(_ manager: UnsafeMutableRawPointer?) {
    guard let manager = HIDManagers.manager(manager) else { return }
    HIDManagers.unschedule(manager)
}

/// CFSetRef IOHIDManagerCopyDevices(IOHIDManagerRef): the devices it
/// matches, +1; NULL when there are none, as IOKit answers.
@c(_IOHIDManagerCopyDevices)
public func IOHIDManagerCopyDevices(_ manager: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let manager = HIDManagers.manager(manager) else { return nil }
    let devices = manager.matchingDevices
    guard !devices.isEmpty else { return nil }
    return NSSet.make(NSMutableArray.of(devices)).objCOwnedReturnValue()
}

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
