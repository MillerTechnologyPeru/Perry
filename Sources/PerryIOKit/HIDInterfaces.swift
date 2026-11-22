import Glibc
import PerryObjCInterop

// The HID device user client's plug-in, as IOCreatePlugInInterfaceForService
// gives it out for a HID device's service: an IOCFPlugInInterface whose
// QueryInterface hands out the device's IOHIDDeviceInterface (the IDs of
// 1.0, 1.2.1 and 1.2.2). Each is a COM object, a pointer to its function
// table followed here by the service it is for. The device interface opens,
// closes and reads its elements' values (getElementValue,
// queryElementValue), as IOHIDEventStructs; it has no queues, async ports
// or reports. Only the keyboard is a HID service in the registry.
//
// A REFIID, the CFUUIDBytes QueryInterface takes by value, is four words on
// i386's stack and two registers on x86_64 and arm64.

enum HIDInterfaces {
    static let pluginInterfaceID: [UInt8] = uuid(0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
    static let unknownID: [UInt8] = uuid(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)
    static let deviceInterfaceIDs: [[UInt8]] = [
        uuid(0x78, 0xBD, 0x42, 0x0C, 0x6F, 0x14, 0x11, 0xD4, 0x94, 0x74, 0x00, 0x05, 0x02, 0x8F, 0x18, 0xD5),
        uuid(0x7D, 0x0B, 0x51, 0x0E, 0x16, 0xD5, 0x11, 0xD7, 0x9E, 0x9B, 0x00, 0x03, 0x93, 0x99, 0x2E, 0x38),
        uuid(0xB7, 0x0A, 0xBF, 0x31, 0x16, 0xD5, 0x11, 0xD7, 0xAB, 0x35, 0x00, 0x03, 0x93, 0x99, 0x2E, 0x38),
    ]

    private static func uuid(_ bytes: UInt8...) -> [UInt8] { bytes }

    static let noInterface = Int32(bitPattern: 0x8000_0004)     // E_NOINTERFACE

    /// A new plug-in for a service, and its device interface, each a COM object.
    static func makePlugin(for service: Handle) -> UnsafeMutableRawPointer {
        let device = object(table: deviceTable, service: service)
        let plugin = object(table: pluginTable, service: service)
        devices[UInt(bitPattern: plugin)] = device
        return plugin
    }

    /// The plug-ins' device interfaces, by plug-in.
    nonisolated(unsafe) private static var devices: [UInt: UnsafeMutableRawPointer] = [:]

    private static func object(table: UnsafeMutableRawPointer, service: Handle) -> UnsafeMutableRawPointer {
        let words = UnsafeMutablePointer<UInt>.allocate(capacity: 2)
        words[0] = UInt(bitPattern: table)
        words[1] = UInt(service)
        return UnsafeMutableRawPointer(words)
    }

    static func service(_ object: UnsafeRawPointer?) -> Handle {
        object.map { Handle($0.load(fromByteOffset: MemoryLayout<UInt>.size, as: UInt.self)) } ?? 0
    }

    /// The interface an ID asks for, of a plug-in or a device interface.
    static func query(_ object: UnsafeMutableRawPointer?, _ id: [UInt8], _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        guard let object else { return noInterface }
        let isPlugin = object.load(as: UInt.self) == UInt(bitPattern: pluginTable)
        let found: UnsafeMutableRawPointer?
        if deviceInterfaceIDs.contains(id) {
            found = isPlugin ? devices[UInt(bitPattern: object)] : object
        } else if id == unknownID || (isPlugin && id == pluginInterfaceID) {
            found = object
        } else {
            found = nil
        }
        out?.pointee = found
        return found == nil ? noInterface : 0
    }

    // MARK: Function tables

    #if arch(i386)
    typealias QueryInterface = @convention(c) (UnsafeMutableRawPointer?, UInt32, UInt32, UInt32, UInt32,
                                               UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    private static let queryInterface: QueryInterface = { object, a, b, c, d, out in
        var bytes: [UInt8] = []
        for word in [a, b, c, d] { withUnsafeBytes(of: word) { bytes += $0 } }
        return HIDInterfaces.query(object, bytes, out)
    }
    #else
    typealias QueryInterface = @convention(c) (UnsafeMutableRawPointer?, UInt64, UInt64,
                                               UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    private static let queryInterface: QueryInterface = { object, a, b, out in
        var bytes: [UInt8] = []
        for word in [a, b] { withUnsafeBytes(of: word) { bytes += $0 } }
        return HIDInterfaces.query(object, bytes, out)
    }
    #endif

    typealias Count = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    typealias Status = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias Pointer = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Open = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32
    typealias ElementValue = @convention(c) (UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?) -> Int32

    /// Objects live as long as the program: their counts are always one.
    private static let addRef: Count = { _ in 1 }
    private static let release: Count = { _ in 1 }
    private static let unsupported: Status = { _ in IOReturn.unsupported }
    private static let none: Pointer = { _ in nil }
    private static let success: Status = { _ in IOReturn.success }
    private static let open: Open = { object, _ in
        Registry.entry(HIDInterfaces.service(object)) != nil ? IOReturn.success : IOReturn.noDevice
    }

    /// The element's value now, as an IOHIDEventStruct: type, cookie and
    /// value at 0, 4 and 8, the time at 12, no long value at 20 and 24.
    private static let elementValue: ElementValue = { object, cookie, event in
        guard HIDInterfaces.service(object) == Registry.keyboardHandle, let event,
              let element = Keyboard.element(cookie: UInt32(truncatingIfNeeded: cookie)) else { return IOReturn.badArgument }
        event.storeBytes(of: element.type, toByteOffset: 0, as: UInt32.self)
        event.storeBytes(of: UInt32(truncatingIfNeeded: cookie), toByteOffset: 4, as: UInt32.self)
        event.storeBytes(of: Int32(Keyboard.isDown(element.usage) ? 1 : 0), toByteOffset: 8, as: Int32.self)
        let time = Clock.absolute()
        event.storeBytes(of: UInt32(truncatingIfNeeded: time), toByteOffset: 12, as: UInt32.self)
        event.storeBytes(of: UInt32(truncatingIfNeeded: time >> 32), toByteOffset: 16, as: UInt32.self)
        event.storeBytes(of: UInt32(0), toByteOffset: 20, as: UInt32.self)
        event.storeBytes(of: UInt(0), toByteOffset: 24, as: UInt.self)
        return IOReturn.success
    }

    private static func table(_ functions: [UnsafeRawPointer?]) -> UnsafeMutableRawPointer {
        let slots = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: functions.count)
        slots.initialize(from: functions, count: functions.count)
        return UnsafeMutableRawPointer(slots)
    }

    private static func function<F>(_ f: F) -> UnsafeRawPointer { unsafeBitCast(f, to: UnsafeRawPointer.self) }

    /// IOCFPlugInInterface: IUnknown's, version 1 revision 0 in one word,
    /// then Probe, Start and Stop.
    nonisolated(unsafe) static let pluginTable: UnsafeMutableRawPointer = table([
        nil, function(queryInterface), function(addRef), function(release),
        UnsafeRawPointer(bitPattern: 1),
        function(unsupported), function(success), function(success),
    ])

    /// IOHIDDeviceInterface122: IUnknown's, then 1.0's, 1.2.1's and 1.2.2's.
    nonisolated(unsafe) static let deviceTable: UnsafeMutableRawPointer = table([
        nil, function(queryInterface), function(addRef), function(release),
        function(unsupported),                      // createAsyncEventSource
        function(none),                             // getAsyncEventSource
        function(unsupported),                      // createAsyncPort
        function(none),                             // getAsyncPort
        function(open),                             // open
        function(success),                          // close
        function(success),                          // setRemovalCallback
        function(elementValue),                     // getElementValue
        function(unsupported),                      // setElementValue
        function(elementValue),                     // queryElementValue
        function(unsupported),                      // startAllQueues
        function(unsupported),                      // stopAllQueues
        function(none),                             // allocQueue
        function(none),                             // allocOutputTransaction
        function(unsupported),                      // setReport
        function(unsupported),                      // getReport
        function(unsupported),                      // copyMatchingElements
        function(unsupported),                      // setInterruptReportHandlerCallback
    ])
}
