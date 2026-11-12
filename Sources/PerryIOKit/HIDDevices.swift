import Glibc
import PerryObjCInterop

// HID devices, their elements and their values: the objects a HID manager
// hands out. A device has its properties (vendor, product, usages) and its
// elements, each a button or an axis with a usage, a cookie unique on the
// device, its logical range and the value it last had. Values are made as
// elements change and passed to the input value callbacks; the Get
// functions return objects the device keeps, not retained.

/// IOHIDElementType.
enum HIDElementType {
    static let button: UInt32 = 2       // kIOHIDElementTypeInput_Button
    static let axis: UInt32 = 3         // kIOHIDElementTypeInput_Axis
}

@ObjCClass("__IOHIDDevice")
final class HIDDevice: NSObject {
    @ObjCMethod("init")
    required override init() { super.init() }

    /// Its properties, by IOKit's keys: kept so that Get returns them.
    var properties = NSMutableDictionary.empty()
    var elements: [HIDElement] = []
    /// What it is for matching: its usage pages and usages.
    var usages: [(page: UInt32, usage: UInt32)] = []
    /// Input value callbacks registered on the device itself.
    var inputCallbacks: [(function: UnsafeRawPointer, context: UnsafeMutableRawPointer?)] = []

    func property(_ key: String) -> NSObject? { properties.object(key) }

    /// Calls the device's own input value callbacks with `value`.
    func deliver(_ value: HIDValue) {
        for (function, context) in inputCallbacks {
            HIDCallbacks.value(function)(context, IOReturn.success, objcObject, value.objcObject)
        }
    }
}

@ObjCClass("__IOHIDElement")
final class HIDElement: NSObject {
    @ObjCMethod("init")
    required override init() { super.init() }

    var cookie: UInt32 = 0
    var type: UInt32 = HIDElementType.button
    var usagePage: UInt32 = 0
    var usage: UInt32 = 0
    var logicalMinimum = 0
    var logicalMaximum = 1
    /// The device, which has its elements for as long as it is.
    var device: UnsafeMutableRawPointer?
    /// The value it last had.
    var value: HIDValue?
}

@ObjCClass("__IOHIDValue")
final class HIDValue: NSObject {
    @ObjCMethod("init")
    required override init() { super.init() }

    var element: HIDElement?
    var integer = 0
    /// When it was read, in mach_absolute_time's units.
    var timestamp: UInt64 = 0

    static func make(_ element: HIDElement, _ integer: Int) -> HIDValue {
        let value = HIDValue()
        value.element = element
        value.integer = integer
        value.timestamp = Clock.absolute()
        return value
    }
}

/// The C callbacks HID objects call.
enum HIDCallbacks {
    /// IOHIDValueCallback: (context, result, sender, value).
    typealias Value = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    /// IOHIDDeviceCallback: (context, result, sender, device).
    typealias Device = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

    static func value(_ function: UnsafeRawPointer) -> Value { unsafeBitCast(function, to: Value.self) }
    static func device(_ function: UnsafeRawPointer) -> Device { unsafeBitCast(function, to: Device.self) }
}

/// mach_absolute_time, as the program reads it.
enum Clock {
    nonisolated(unsafe) static var machAbsoluteTime: (@convention(c) () -> UInt64)?

    static func absolute() -> UInt64 {
        if let machAbsoluteTime { return machAbsoluteTime() }
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
    }
}

private func deviceObject(_ pointer: UnsafeRawPointer?) -> HIDDevice? {
    pointer.map { NSObject(objcObject: UnsafeMutableRawPointer(mutating: $0), ownership: .retain).as(HIDDevice.self) } ?? nil
}

private func elementObject(_ pointer: UnsafeRawPointer?) -> HIDElement? {
    pointer.map { NSObject(objcObject: UnsafeMutableRawPointer(mutating: $0), ownership: .retain).as(HIDElement.self) } ?? nil
}

private func valueObject(_ pointer: UnsafeRawPointer?) -> HIDValue? {
    pointer.map { NSObject(objcObject: UnsafeMutableRawPointer(mutating: $0), ownership: .retain).as(HIDValue.self) } ?? nil
}

// MARK: - Devices

/// CFTypeRef IOHIDDeviceGetProperty(IOHIDDeviceRef, CFStringRef key): not
/// retained.
@c(_IOHIDDeviceGetProperty)
public func IOHIDDeviceGetProperty(_ device: UnsafeRawPointer?, _ key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let device = deviceObject(device), let key else { return nil }
    return device.properties.object(forKey: NSObject(objcObject: key, ownership: .retain))?.objcObject
}

/// Properties can't be set: false.
@c(_IOHIDDeviceSetProperty)
public func IOHIDDeviceSetProperty(_ device: UnsafeRawPointer?, _ key: UnsafeMutableRawPointer?, _ value: UnsafeMutableRawPointer?) -> Bool { false }

/// Boolean IOHIDDeviceConformsTo(IOHIDDeviceRef, uint32_t usagePage, uint32_t usage).
@c(_IOHIDDeviceConformsTo)
public func IOHIDDeviceConformsTo(_ device: UnsafeRawPointer?, _ page: UInt32, _ usage: UInt32) -> Bool {
    deviceObject(device)?.usages.contains { $0.page == page && $0.usage == usage } ?? false
}

@c(_IOHIDDeviceOpen)
public func IOHIDDeviceOpen(_ device: UnsafeRawPointer?, _ options: UInt32) -> Int32 {
    deviceObject(device) != nil ? IOReturn.success : IOReturn.badArgument
}

@c(_IOHIDDeviceClose)
public func IOHIDDeviceClose(_ device: UnsafeRawPointer?, _ options: UInt32) -> Int32 {
    deviceObject(device) != nil ? IOReturn.success : IOReturn.badArgument
}

/// CFArrayRef IOHIDDeviceCopyMatchingElements(IOHIDDeviceRef, CFDictionaryRef
/// matching, IOOptionBits): the elements with each of the matching
/// dictionary's UsagePage, Usage, Type and ElementCookie; all of them with
/// no dictionary.
@c(_IOHIDDeviceCopyMatchingElements)
public func IOHIDDeviceCopyMatchingElements(_ device: UnsafeRawPointer?, _ matching: UnsafeMutableRawPointer?,
                                            _ options: UInt32) -> UnsafeMutableRawPointer? {
    guard let device = deviceObject(device) else { return nil }
    let criteria = matching.map { NSDictionary(objcObject: $0, ownership: .retain) }
    func wanted(_ key: String, _ actual: UInt32) -> Bool {
        guard let number = criteria?.object(key) else { return true }
        return number.longLongValue() == Int64(actual)
    }
    let array = NSMutableArray.empty()
    for element in device.elements
    where wanted("UsagePage", element.usagePage) && wanted("Usage", element.usage)
        && wanted("Type", element.type) && wanted("ElementCookie", element.cookie) {
        array.add(element)
    }
    return array.objCOwnedReturnValue()
}

/// IOReturn IOHIDDeviceGetValue(IOHIDDeviceRef, IOHIDElementRef, IOHIDValueRef *):
/// the element's last value, not retained.
@c(_IOHIDDeviceGetValue)
public func IOHIDDeviceGetValue(_ device: UnsafeRawPointer?, _ element: UnsafeRawPointer?,
                                _ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let element = elementObject(element) else { return IOReturn.badArgument }
    if element.value == nil { element.value = HIDValue.make(element, 0) }
    value?.pointee = element.value?.objcObject
    return IOReturn.success
}

/// Output elements aren't written: a controller's rumble isn't sent.
@c(_IOHIDDeviceSetValue)
public func IOHIDDeviceSetValue(_ device: UnsafeRawPointer?, _ element: UnsafeRawPointer?, _ value: UnsafeRawPointer?) -> Int32 {
    IOReturn.unsupported
}

@c(_IOHIDDeviceRegisterInputValueCallback)
public func IOHIDDeviceRegisterInputValueCallback(_ device: UnsafeRawPointer?, _ callback: UnsafeRawPointer?,
                                                  _ context: UnsafeMutableRawPointer?) {
    guard let device = deviceObject(device) else { return }
    device.inputCallbacks = callback.map { [($0, context)] } ?? []
}

/// A device's own callbacks are called on the main queue, as the
/// manager's are, wherever it is scheduled.
@c(_IOHIDDeviceScheduleWithRunLoop)
public func IOHIDDeviceScheduleWithRunLoop(_ device: UnsafeRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                           _ mode: UnsafeMutableRawPointer?) {
    Gamepads.start()
}

@c(_IOHIDDeviceUnscheduleFromRunLoop)
public func IOHIDDeviceUnscheduleFromRunLoop(_ device: UnsafeRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                             _ mode: UnsafeMutableRawPointer?) {}

// MARK: - Elements

@c(_IOHIDElementGetCookie) public func IOHIDElementGetCookie(_ element: UnsafeRawPointer?) -> UInt32 { elementObject(element)?.cookie ?? 0 }
@c(_IOHIDElementGetType) public func IOHIDElementGetType(_ element: UnsafeRawPointer?) -> UInt32 { elementObject(element)?.type ?? 0 }
@c(_IOHIDElementGetUsagePage) public func IOHIDElementGetUsagePage(_ element: UnsafeRawPointer?) -> UInt32 { elementObject(element)?.usagePage ?? 0 }
@c(_IOHIDElementGetUsage) public func IOHIDElementGetUsage(_ element: UnsafeRawPointer?) -> UInt32 { elementObject(element)?.usage ?? 0 }
@c(_IOHIDElementGetLogicalMin) public func IOHIDElementGetLogicalMin(_ element: UnsafeRawPointer?) -> Int { elementObject(element)?.logicalMinimum ?? 0 }
@c(_IOHIDElementGetLogicalMax) public func IOHIDElementGetLogicalMax(_ element: UnsafeRawPointer?) -> Int { elementObject(element)?.logicalMaximum ?? 0 }
/// The physical range is the logical one.
@c(_IOHIDElementGetPhysicalMin) public func IOHIDElementGetPhysicalMin(_ element: UnsafeRawPointer?) -> Int { elementObject(element)?.logicalMinimum ?? 0 }
@c(_IOHIDElementGetPhysicalMax) public func IOHIDElementGetPhysicalMax(_ element: UnsafeRawPointer?) -> Int { elementObject(element)?.logicalMaximum ?? 0 }
@c(_IOHIDElementIsArray) public func IOHIDElementIsArray(_ element: UnsafeRawPointer?) -> Bool { false }
@c(_IOHIDElementIsRelative) public func IOHIDElementIsRelative(_ element: UnsafeRawPointer?) -> Bool { false }
@c(_IOHIDElementIsVirtual) public func IOHIDElementIsVirtual(_ element: UnsafeRawPointer?) -> Bool { false }
@c(_IOHIDElementHasNullState) public func IOHIDElementHasNullState(_ element: UnsafeRawPointer?) -> Bool { false }
@c(_IOHIDElementGetReportCount) public func IOHIDElementGetReportCount(_ element: UnsafeRawPointer?) -> UInt32 { 1 }

/// A button is a bit; an axis has the bits its range needs.
@c(_IOHIDElementGetReportSize)
public func IOHIDElementGetReportSize(_ element: UnsafeRawPointer?) -> UInt32 {
    guard let element = elementObject(element) else { return 0 }
    return element.type == HIDElementType.button ? 1 : element.logicalMinimum < 0 ? 16 : 8
}

/// The device, not retained.
@c(_IOHIDElementGetDevice)
public func IOHIDElementGetDevice(_ element: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { elementObject(element)?.device }

/// Elements are the device's own, under no collection.
@c(_IOHIDElementGetParent) public func IOHIDElementGetParent(_ element: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { nil }
@c(_IOHIDElementGetChildren) public func IOHIDElementGetChildren(_ element: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { nil }
@c(_IOHIDElementGetName) public func IOHIDElementGetName(_ element: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { nil }

// MARK: - Values

/// The element, not retained.
@c(_IOHIDValueGetElement)
public func IOHIDValueGetElement(_ value: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { valueObject(value)?.element?.objcObject }

@c(_IOHIDValueGetIntegerValue) public func IOHIDValueGetIntegerValue(_ value: UnsafeRawPointer?) -> Int { valueObject(value)?.integer ?? 0 }
@c(_IOHIDValueGetTimeStamp) public func IOHIDValueGetTimeStamp(_ value: UnsafeRawPointer?) -> UInt64 { valueObject(value)?.timestamp ?? 0 }

/// A value's bytes: as many as its element's report size takes.
@c(_IOHIDValueGetLength)
public func IOHIDValueGetLength(_ value: UnsafeRawPointer?) -> Int {
    guard let element = valueObject(value)?.element else { return 0 }
    return Int(IOHIDElementGetReportSize(element.objcObject) + 7) / 8
}

/// The value as a double: physical and calibrated values are the logical
/// ones.
@c(_IOHIDValueGetScaledValue)
public func IOHIDValueGetScaledValue(_ value: UnsafeRawPointer?, _ type: UInt32) -> Double { Double(valueObject(value)?.integer ?? 0) }

/// IOHIDValueRef IOHIDValueCreateWithIntegerValue(CFAllocatorRef, IOHIDElementRef,
/// uint64_t timeStamp, CFIndex value): +1.
@c(_IOHIDValueCreateWithIntegerValue)
public func IOHIDValueCreateWithIntegerValue(_ allocator: UnsafeRawPointer?, _ element: UnsafeRawPointer?,
                                             _ timestamp: UInt64, _ integer: Int) -> UnsafeMutableRawPointer? {
    guard let element = elementObject(element) else { return nil }
    let value = HIDValue.make(element, integer)
    value.timestamp = timestamp
    return value.objCOwnedReturnValue()
}
