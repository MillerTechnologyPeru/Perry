import class HardwareKit.HardwareRegistry
import class HardwareKit.RegistryEntry
import enum HardwareKit.PowerManagement
import enum HardwareKit.PropertyValue
import struct HardwareKit.ServiceQuery
import struct HardwareKit.SleepAssertion
import HardwareKitDBus
import PerryObjCInterop

/// Adapts Phase 1 hardware services to Perry's existing IOKit ABI and Objective-C objects.
enum HardwareBridge {
    private static let registry = HardwareRegistry.shared
    private static let lock = Lock()
    nonisolated(unsafe) private static var handles: [UInt64: Handle] = [:]
    nonisolated(unsafe) private static var entries: [Handle: HardwareKit.RegistryEntry] = [:]
    nonisolated(unsafe) private static var assertions: [Handle: Assertion] = [:]
    nonisolated(unsafe) private static var started = false

    static func start() {
        registry.bootstrapIfNeeded()
        let shouldStart = lock.withLock {
            guard !started else { return false }
            started = true
            return true
        }
        if shouldStart {
            DBusPowerProvider.shared.installSystemSleepAssertions()
            Task { await DBusPowerProvider.shared.register(with: registry) }
        }
    }

    private static func isPhaseOne(_ entry: HardwareKit.RegistryEntry) -> Bool {
        ["IOPlatformExpertDevice", "IOPMrootDomain", "IOPMPowerSource", "AppleSMC",
         "IONetworkController", "IONetworkInterface"].contains { entry.conforms(to: $0) }
    }

    private static func handle(for entry: HardwareKit.RegistryEntry) -> Handle {
        if entry.pathKey == "/" { return Registry.rootHandle }
        if entry.pathKey == "/platform" { return Registry.platformHandle }
        return lock.withLock {
            if let handle = handles[entry.id] { return handle }
            let handle = Registry.allocateHandle()
            handles[entry.id] = handle
            entries[handle] = entry
            return handle
        }
    }

    private static func hardwareEntry(_ handle: Handle) -> HardwareKit.RegistryEntry? {
        registry.bootstrapIfNeeded()
        if handle == Registry.platformHandle { return registry.entry(forPathKey: "/platform") }
        if handle == Registry.rootHandle { return registry.rootEntry() }
        return lock.withLock { entries[handle] }
    }

    static func entry(_ handle: Handle) -> RegistryEntry? {
        // Keep the legacy root's identity aliases, and bridge all actual hardware entries.
        guard handle != Registry.rootHandle, let entry = hardwareEntry(handle) else { return nil }
        let parent = entry.parent() ?? entry.parent(in: .power) ?? entry.parent(in: .deviceTree)
        return RegistryEntry(className: entry.className, name: entry.name,
                             parent: parent.map { self.handle(for: $0) }) {
            entry.properties().sorted { $0.key < $1.key }.map { ($0.key, object($0.value)) }
        }
    }

    static func children(of handle: Handle) -> [Handle] {
        guard let entry = hardwareEntry(handle) else { return [] }
        let children = entry.children() + entry.children(in: .power) + entry.children(in: .deviceTree)
        return Array(Set(children.filter(isPhaseOne).map { self.handle(for: $0) })).sorted()
    }

    static func conforms(_ handle: Handle, to name: String) -> Bool? {
        hardwareEntry(handle)?.conforms(to: name)
    }

    static func matches(_ matching: UnsafeMutableRawPointer?) -> [Handle] {
        guard let matching else { return [] }
        let dictionary = NSDictionary(matching)
        func string(_ key: String) -> String? {
            guard let value = dictionary.object(key), value.isString else { return nil }
            return value.stringValue
        }
        if let id = dictionary.object("IORegistryEntryID") {
            guard let handle = UInt32(exactly: id.longLongValue()), hardwareEntry(handle) != nil else { return [] }
            return [handle]
        }
        let query = ServiceQuery(className: string("IOProviderClass"), name: string("IONameMatch"),
                                 bsdName: string("BSD Name"))
        guard query.className != nil || query.name != nil || query.bsdName != nil else { return [] }
        return registry.matchingServices(query).filter { entry in
            guard isPhaseOne(entry) else { return false }
            if let requested = dictionary.object("IOPropertyMatch") {
                let properties = NSDictionary(requested.objcObject)
                return properties.keys().allSatisfy { key in
                    guard let actual = entry.property(forKey: key), let expected = properties.object(key) else { return false }
                    return object(actual).isEqual(expected)
                }
            }
            return true
        }.map { handle(for: $0) }
    }

    private static func object(_ value: PropertyValue) -> NSObject {
        switch value {
        case .string(let value): NSObject.string(value)
        case .int(let value): NSNumber.make(int64: value)
        case .uint(let value): NSNumber.make(uint64: value)
        case .bool(let value): NSNumber.make(bool: value)
        case .data(let value): value.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }
        case .array(let value): NSMutableArray.of(value.map(object))
        case .dictionary(let value): NSMutableDictionary.of(value.map { ($0.key, object($0.value)) })
        }
    }

    static func powerSnapshot() -> NSArray {
        let sources = PowerManagement.currentPowerSources(in: registry).map { source -> NSObject in
            NSMutableDictionary.of([
                ("Name", NSObject.string(source.name)),
                ("Type", NSObject.string("InternalBattery")),
                ("Is Present", NSNumber.make(bool: true)),
                ("Current Capacity", NSNumber.make(int64: Int64(source.currentCapacity))),
                ("Max Capacity", NSNumber.make(int64: Int64(source.maxCapacity))),
                ("Is Charging", NSNumber.make(bool: source.isCharging)),
                ("Power Source State", NSObject.string(source.externalConnected ? "AC Power" : "Battery Power"))
            ])
        }
        return NSMutableArray.of(sources)
    }

    static func isOnBattery() -> Bool {
        PowerManagement.currentPowerSources(in: registry).contains { !$0.externalConnected }
    }

    private final class Assertion {
        let value: SleepAssertion
        init(reason: String) { value = PowerManagement.createSleepAssertion(reason: reason) }
    }

    static func makeAssertion(reason: String, enabled: Bool) -> Handle {
        let handle = Registry.allocateHandle()
        if enabled {
            let assertion = Assertion(reason: reason)
            lock.withLock { assertions[handle] = assertion }
        }
        return handle
    }

    static func releaseAssertion(_ handle: Handle) {
        // Release outside the table lock: dropping the value calls the backend.
        let assertion = lock.withLock { assertions.removeValue(forKey: handle) }
        withExtendedLifetime(assertion) {}
    }
}
