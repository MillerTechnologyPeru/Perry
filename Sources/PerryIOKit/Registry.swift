import Glibc
import PerryObjCInterop

// The I/O Registry: io_object_t handles, as mach ports are, for its
// entries and for iterators over matches. It has the root and the
// platform expert device (IOPlatformUUID, IOPlatformSerialNumber, model);
// matching dictionaries find the platform device by its class and nothing
// else, so an app looking for a GPU, a battery or USB devices finds none.

public typealias Handle = UInt32

final class RegistryEntry {
    let className: String
    let name: String
    let parent: Handle?
    let properties: () -> [(String, NSObject)]

    init(className: String, name: String, parent: Handle?, properties: @escaping () -> [(String, NSObject)]) {
        (self.className, self.name, self.parent, self.properties) = (className, name, parent, properties)
    }

    func property(_ key: String) -> NSObject? { properties().first { $0.0 == key }?.1 }
}

enum Registry {
    static let rootHandle: Handle = 0x1001
    static let platformHandle: Handle = 0x1002

    private static let lock = Lock()
    nonisolated(unsafe) private static var iterators: [Handle: [Handle]] = [:]
    nonisolated(unsafe) private static var nextIterator: Handle = 0x2000

    /// This machine's identity: /etc/machine-id as a UUID, and a serial
    /// number made from it.
    nonisolated(unsafe) static let machineID: String = {
        guard let file = fopen("/etc/machine-id", "r") else { return "00000000000000000000000000000000" }
        defer { fclose(file) }
        var buffer = [CChar](repeating: 0, count: 64)
        guard fgets(&buffer, Int32(buffer.count), file) != nil else { return "00000000000000000000000000000000" }
        let text = String(cString: buffer).filter(\.isHexDigit).uppercased()
        return text.count >= 32 ? String(text.prefix(32)) : text + String(repeating: "0", count: 32 - text.count)
    }()

    static var platformUUID: String {
        let id = Array(machineID)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(id[$0]) }.joined(separator: "-")
    }

    static var serialNumber: String { "P" + String(machineID.suffix(11)) }

    nonisolated(unsafe) static let entries: [Handle: RegistryEntry] = [
        // The root has the machine's identity too, as apps read it there.
        rootHandle: RegistryEntry(className: "IORegistryEntry", name: "Root", parent: nil) {
            [("IOPlatformUUID", NSObject.string(Registry.platformUUID)),
             ("IOPlatformSerialNumber", NSObject.string(Registry.serialNumber))]
        },
        platformHandle: RegistryEntry(className: "IOPlatformExpertDevice", name: "Perry", parent: rootHandle) {
            [("IOPlatformUUID", NSObject.string(Registry.platformUUID)),
             ("IOPlatformSerialNumber", NSObject.string(Registry.serialNumber)),
             ("model", NSData.of("Perry1,1")),
             ("manufacturer", NSData.of("Perry")),
             ("product-name", NSData.of("Perry")),
             ("IOProviderClass", NSObject.string("IOPlatformExpertDevice"))]
        },
    ]

    static func entry(_ handle: Handle) -> RegistryEntry? { entries[handle] }

    /// The entries a matching dictionary matches: by IOProviderClass (the
    /// class or a superclass), IONameMatch, or a registry entry ID.
    static func matches(_ matching: UnsafeMutableRawPointer?) -> [Handle] {
        guard let matching else { return [] }
        let dictionary = NSDictionary(matching)
        if let cls = dictionary.object("IOProviderClass"), cls.isString {
            let name = cls.stringValue
            return entries.filter { $0.value.className == name || (name == "IOService" && $0.key != rootHandle) }.map(\.key).sorted()
        }
        if let name = dictionary.object("IONameMatch"), name.isString {
            return entries.filter { $0.value.name == name.stringValue }.map(\.key).sorted()
        }
        if let id = dictionary.object("IORegistryEntryID") {
            typealias Get = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int64
            let value = unsafeBitCast(ObjCRuntime.msgSend, to: Get.self)(id.objcObject, ObjCRuntime.selector("longLongValue"))
            return entries.keys.filter { Int64($0) == value }
        }
        return []
    }

    static func makeIterator(_ handles: [Handle]) -> Handle {
        lock.withLock {
            nextIterator += 1
            iterators[nextIterator] = handles
            return nextIterator
        }
    }

    static func next(_ iterator: Handle) -> Handle {
        lock.withLock {
            guard var remaining = iterators[iterator], !remaining.isEmpty else { return 0 }
            let next = remaining.removeFirst()
            iterators[iterator] = remaining
            return next
        }
    }

    static func release(_ handle: Handle) { _ = lock.withLock { iterators.removeValue(forKey: handle) } }
    static func isIterator(_ handle: Handle) -> Bool { lock.withLock { iterators[handle] != nil } }
}

// MARK: - Ports

@c(_IOMainPort)
public func IOMainPort(_ bootstrap: UInt32, _ port: UnsafeMutablePointer<UInt32>?) -> Int32 {
    port?.pointee = 0
    return IOReturn.success
}

@c(_IOMasterPort)
public func IOMasterPort(_ bootstrap: UInt32, _ port: UnsafeMutablePointer<UInt32>?) -> Int32 { IOMainPort(bootstrap, port) }

// MARK: - Matching

/// A new matching dictionary, +1, which the matching functions consume.
private func matching(_ entries: [(String, NSObject)]) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(NSMutableDictionary.of(entries).objcObject)
}

@c(_IOServiceMatching)
public func IOServiceMatching(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return matching([("IOProviderClass", NSObject.string(String(cString: name)))])
}

@c(_IOServiceNameMatching)
public func IOServiceNameMatching(_ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return matching([("IONameMatch", NSObject.string(String(cString: name)))])
}

@c(_IOBSDNameMatching)
public func IOBSDNameMatching(_ port: UInt32, _ options: UInt32, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return matching([("BSD Name", NSObject.string(String(cString: name)))])
}

@c(_IORegistryEntryIDMatching)
public func IORegistryEntryIDMatching(_ id: UInt64) -> UnsafeMutableRawPointer? {
    matching([("IORegistryEntryID", NSNumber.make(int64: Int64(bitPattern: id)))])
}

@c(_IOServiceGetMatchingService)
public func IOServiceGetMatchingService(_ port: UInt32, _ matching: UnsafeMutableRawPointer?) -> Handle {
    defer { ObjCRuntime.release(matching) }
    return Registry.matches(matching).first ?? 0
}

@c(_IOServiceGetMatchingServices)
public func IOServiceGetMatchingServices(_ port: UInt32, _ matching: UnsafeMutableRawPointer?,
                                         _ iterator: UnsafeMutablePointer<Handle>?) -> Int32 {
    defer { ObjCRuntime.release(matching) }
    iterator?.pointee = Registry.makeIterator(Registry.matches(matching))
    return IOReturn.success
}

/// Services never appear or go here: the iterator has those there now,
/// and the callback is never called.
@c(_IOServiceAddMatchingNotification)
public func IOServiceAddMatchingNotification(_ port: UnsafeMutableRawPointer?, _ type: UnsafePointer<CChar>?,
                                             _ matching: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                             _ refcon: UnsafeMutableRawPointer?, _ iterator: UnsafeMutablePointer<Handle>?) -> Int32 {
    defer { ObjCRuntime.release(matching) }
    let first = type.map { String(cString: $0) == "IOServiceFirstMatch" || String(cString: $0) == "IOServiceMatched" } ?? false
    iterator?.pointee = Registry.makeIterator(first ? Registry.matches(matching) : [])
    return IOReturn.success
}

@c(_IOServiceAddInterestNotification)
public func IOServiceAddInterestNotification(_ port: UnsafeMutableRawPointer?, _ service: Handle, _ type: UnsafePointer<CChar>?,
                                             _ callback: UnsafeRawPointer?, _ refcon: UnsafeMutableRawPointer?,
                                             _ notification: UnsafeMutablePointer<Handle>?) -> Int32 {
    notification?.pointee = Registry.makeIterator([])
    return IOReturn.success
}

// MARK: - Objects and iterators

@c(_IOIteratorNext) public func IOIteratorNext(_ iterator: Handle) -> Handle { Registry.next(iterator) }
@c(_IOIteratorIsValid) public func IOIteratorIsValid(_ iterator: Handle) -> UInt32 { Registry.isIterator(iterator) ? 1 : 0 }
@c(_IOIteratorReset) public func IOIteratorReset(_ iterator: Handle) {}

@c(_IOObjectRelease)
public func IOObjectRelease(_ object: Handle) -> Int32 {
    Registry.release(object)
    return IOReturn.success
}

@c(_IOObjectRetain) public func IOObjectRetain(_ object: Handle) -> Int32 { IOReturn.success }
@c(_IOObjectIsEqualTo) public func IOObjectIsEqualTo(_ a: Handle, _ b: Handle) -> UInt32 { a == b ? 1 : 0 }

@c(_IOObjectGetClass)
public func IOObjectGetClass(_ object: Handle, _ name: UnsafeMutablePointer<CChar>?) -> Int32 {
    guard let name, let entry = Registry.entry(object) else { return IOReturn.badArgument }
    _ = entry.className.withCString { strncpy(name, $0, 127) }
    name[127] = 0
    return IOReturn.success
}

@c(_IOObjectConformsTo)
public func IOObjectConformsTo(_ object: Handle, _ name: UnsafePointer<CChar>?) -> UInt32 {
    guard let name, let entry = Registry.entry(object) else { return 0 }
    let wanted = String(cString: name)
    return entry.className == wanted || wanted == "IOService" || wanted == "IORegistryEntry" ? 1 : 0
}

// MARK: - Registry entries

/// A plane's root ("IOService:/", "IODeviceTree:/") is the root; a path
/// through the platform device is the platform device; others aren't here.
private func entry(fromPath path: String) -> Handle {
    guard let colon = path.firstIndex(of: ":") else { return 0 }
    let rest = path[path.index(after: colon)...].trimmingPrefix("/")
    if rest.isEmpty { return Registry.rootHandle }
    return rest.hasPrefix("IOPlatformExpertDevice") || rest.hasPrefix("IOResources") || rest.hasPrefix("Perry") ? Registry.platformHandle : 0
}

@c(_IORegistryEntryFromPath)
public func IORegistryEntryFromPath(_ port: UInt32, _ path: UnsafePointer<CChar>?) -> Handle {
    path.map { entry(fromPath: String(cString: $0)) } ?? 0
}

@c(_IORegistryEntryCopyFromPath)
public func IORegistryEntryCopyFromPath(_ port: UInt32, _ path: UnsafeMutableRawPointer?) -> Handle {
    path.map { entry(fromPath: String(objCArgument: $0)) } ?? 0
}

@c(_IORegistryGetRootEntry) public func IORegistryGetRootEntry(_ port: UInt32) -> Handle { Registry.rootHandle }

@c(_IORegistryEntryCreateCFProperty)
public func IORegistryEntryCreateCFProperty(_ entry: Handle, _ key: UnsafeMutableRawPointer?, _ allocator: UnsafeRawPointer?,
                                            _ options: UInt32) -> UnsafeMutableRawPointer? {
    guard let key, let value = Registry.entry(entry)?.property(String(objCArgument: key)) else { return nil }
    return ObjCRuntime.retain(value.objcObject)
}

@c(_IORegistryEntrySearchCFProperty)
public func IORegistryEntrySearchCFProperty(_ entry: Handle, _ plane: UnsafePointer<CChar>?, _ key: UnsafeMutableRawPointer?,
                                            _ allocator: UnsafeRawPointer?, _ options: UInt32) -> UnsafeMutableRawPointer? {
    IORegistryEntryCreateCFProperty(entry, key, allocator, options)
        ?? IORegistryEntryCreateCFProperty(Registry.platformHandle, key, allocator, options)
}

@c(_IORegistryEntryCreateCFProperties)
public func IORegistryEntryCreateCFProperties(_ entry: Handle, _ properties: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                              _ allocator: UnsafeRawPointer?, _ options: UInt32) -> Int32 {
    guard let found = Registry.entry(entry) else { return IOReturn.badArgument }
    properties?.pointee = ObjCRuntime.retain(NSMutableDictionary.of(found.properties()).objcObject)
    return IOReturn.success
}

@c(_IORegistryEntryGetParentEntry)
public func IORegistryEntryGetParentEntry(_ entry: Handle, _ plane: UnsafePointer<CChar>?, _ parent: UnsafeMutablePointer<Handle>?) -> Int32 {
    guard let found = Registry.entry(entry)?.parent else { return IOReturn.noDevice }
    parent?.pointee = found
    return IOReturn.success
}

@c(_IORegistryEntryGetChildIterator)
public func IORegistryEntryGetChildIterator(_ entry: Handle, _ plane: UnsafePointer<CChar>?, _ iterator: UnsafeMutablePointer<Handle>?) -> Int32 {
    iterator?.pointee = Registry.makeIterator(Registry.entries.filter { $0.value.parent == entry }.map(\.key).sorted())
    return IOReturn.success
}

@c(_IORegistryEntryGetName)
public func IORegistryEntryGetName(_ entry: Handle, _ name: UnsafeMutablePointer<CChar>?) -> Int32 {
    guard let name, let found = Registry.entry(entry) else { return IOReturn.badArgument }
    _ = found.name.withCString { strncpy(name, $0, 127) }
    name[127] = 0
    return IOReturn.success
}

@c(_IORegistryEntryGetRegistryEntryID)
public func IORegistryEntryGetRegistryEntryID(_ entry: Handle, _ id: UnsafeMutablePointer<UInt64>?) -> Int32 {
    guard Registry.entry(entry) != nil else { return IOReturn.badArgument }
    id?.pointee = UInt64(entry)
    return IOReturn.success
}

// MARK: - Notification ports and plug-ins

/// A notification port, and its run loop source, which nothing signals.
@c(_IONotificationPortCreate)
public func IONotificationPortCreate(_ port: UInt32) -> UnsafeMutableRawPointer? { NSObject.opaque("__IOKitOpaque") }

@c(_IONotificationPortDestroy)
public func IONotificationPortDestroy(_ port: UnsafeMutableRawPointer?) { ObjCRuntime.release(port) }

/// The port's source: the port itself, as a run loop ignores a source it
/// doesn't know.
@c(_IONotificationPortGetRunLoopSource)
public func IONotificationPortGetRunLoopSource(_ port: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { port }

@c(_IONotificationPortSetDispatchQueue)
public func IONotificationPortSetDispatchQueue(_ port: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {}

@c(_IONotificationPortGetMachPort) public func IONotificationPortGetMachPort(_ port: UnsafeMutableRawPointer?) -> UInt32 { 0 }

/// There are no drivers to load plug-ins from.
@c(_IOCreatePlugInInterfaceForService)
public func IOCreatePlugInInterfaceForService(_ service: Handle, _ pluginType: UnsafeRawPointer?, _ interfaceType: UnsafeRawPointer?,
                                              _ interface: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                              _ score: UnsafeMutablePointer<Int32>?) -> Int32 {
    interface?.pointee = nil
    return IOReturn.unsupported
}

@c(_IODestroyPlugInInterface) public func IODestroyPlugInInterface(_ interface: UnsafeMutableRawPointer?) -> Int32 { IOReturn.success }
