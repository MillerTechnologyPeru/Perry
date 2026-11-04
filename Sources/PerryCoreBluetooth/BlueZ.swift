import DBUS
import Glibc
import Logging

// BlueZ, Linux's Bluetooth stack, through its D-Bus API on the system bus
// (DBUS_SYSTEM_BUS_ADDRESS, or /var/run/dbus/system_bus_socket). One
// connection serves every manager: it keeps a copy of the objects BlueZ
// manages (adapters, devices, and their GATT services, characteristics and
// descriptors) from GetManagedObjects, kept current by the ObjectManager's
// and Properties' signals, which observers also hear.

/// A D-Bus error BlueZ answered with: its name and message.
struct BlueZError: Error, Sendable {
    let name: String
    let message: String
}

/// An object's interfaces, each with its properties.
typealias Interfaces = [String: [String: DBusValue]]

enum BlueZEvent: Sendable {
    case added(path: String, interfaces: Interfaces)
    case removed(path: String, interfaces: [String])
    case changed(path: String, interface: String, changed: [String: DBusValue])
}

enum BlueZInterface {
    static let adapter = "org.bluez.Adapter1"
    static let device = "org.bluez.Device1"
    static let service = "org.bluez.GattService1"
    static let characteristic = "org.bluez.GattCharacteristic1"
    static let descriptor = "org.bluez.GattDescriptor1"
    static let objectManager = "org.freedesktop.DBus.ObjectManager"
    static let properties = "org.freedesktop.DBus.Properties"
}

actor BlueZ {
    static let shared = BlueZ()

    private enum Phase {
        case idle, connecting, connected(DBusClient.Connection), unavailable
    }

    private var phase = Phase.idle
    private var waiting: [CheckedContinuation<DBusClient.Connection?, Never>] = []
    /// path → interface → properties.
    private(set) var objects: [String: Interfaces] = [:]
    private var observers: [Int: @Sendable (BlueZEvent, Interfaces) -> Void] = [:]
    private var nextObserver = 0

    private static let logger: Logger = {
        var logger = Logger(label: "perry.corebluetooth.dbus")
        logger.logLevel = .critical
        return logger
    }()

    // MARK: Connection

    /// The connection, made on first use; nil when there is no system bus
    /// or BlueZ is not on it.
    func connection() async -> DBusClient.Connection? {
        switch phase {
        case .connected(let connection): return connection
        case .unavailable: return nil
        case .idle:
            phase = .connecting
            Task.detached { await BlueZ.run() }
        case .connecting: break
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    var isAvailable: Bool {
        if case .connected = phase { return true }
        return false
    }

    /// Holds the connection open for the life of the process.
    private static func run() async {
        do {
            try await DBusClient.withSystemBus(auth: .external(userID: String(getuid())), logger: logger) { connection in
                try await BlueZ.shared.connected(connection)
                while true { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
            }
        } catch {}
        await BlueZ.shared.closed()
    }

    private func connected(_ connection: DBusClient.Connection) async throws {
        // Signals from BlueZ only; subscribing first misses none of them.
        for rule in ["type='signal',sender='org.bluez',interface='\(BlueZInterface.objectManager)'",
                     "type='signal',sender='org.bluez',interface='\(BlueZInterface.properties)',member='PropertiesChanged'"] {
            _ = try await connection.send(.createMethodCall(
                destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                interface: "org.freedesktop.DBus", method: "AddMatch", body: [.string(rule)]))
        }
        let added = await connection.subscribeToSignal(interface: BlueZInterface.objectManager, member: "InterfacesAdded")
        let removed = await connection.subscribeToSignal(interface: BlueZInterface.objectManager, member: "InterfacesRemoved")
        let changed = await connection.subscribeToSignal(interface: BlueZInterface.properties, member: "PropertiesChanged")
        Task { for await message in added { await self.interfacesAdded(message) } }
        Task { for await message in removed { await self.interfacesRemoved(message) } }
        Task { for await message in changed { await self.propertiesChanged(message) } }

        let reply = try await Self.call(connection, path: "/", interface: BlueZInterface.objectManager, method: "GetManagedObjects")
        if case .dictionary(let managed)? = reply.first {
            for (path, interfaces) in managed {
                guard let path = path.pathValue else { continue }
                objects[path] = Self.interfaces(interfaces)
            }
        }
        phase = .connected(connection)
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: connection) }
    }

    private func closed() {
        phase = .unavailable
        objects = [:]
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: nil) }
    }

    // MARK: Calls

    /// Calls a method of an object of BlueZ's, giving the reply's values.
    func call(_ path: String, _ interface: String, _ method: String, _ body: [DBusValue] = [],
              signature: String? = nil) async throws -> [DBusValue] {
        guard let connection = await connection() else {
            throw BlueZError(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "BlueZ is not running")
        }
        return try await Self.call(connection, path: path, interface: interface, method: method, body: body, signature: signature)
    }

    private static func call(_ connection: DBusClient.Connection, path: String, interface: String, method: String,
                             body: [DBusValue] = [], signature: String? = nil) async throws -> [DBusValue] {
        let request = DBusRequest.createMethodCall(destination: "org.bluez", path: path, interface: interface,
                                                   method: method, body: body, signature: signature)
        guard let reply = try await connection.send(request) else { return [] }
        if case .error = reply.messageType {
            let name = reply.headerFields.first { $0.code == .errorName }.flatMap { $0.variant.value.stringValue }
            throw BlueZError(name: name ?? "org.bluez.Error.Failed", message: reply.body.first?.stringValue ?? "")
        }
        return reply.body
    }

    /// Sets a property of an object of BlueZ's.
    func set(_ path: String, _ interface: String, _ property: String, _ value: DBusVariant) async throws {
        _ = try await call(path, BlueZInterface.properties, "Set",
                           [.string(interface), .string(property), .variant(value)], signature: "ssv")
    }

    // MARK: Objects

    func properties(_ path: String, _ interface: String) -> [String: DBusValue]? { objects[path]?[interface] }

    /// The objects below `path`, a device's services, characteristics and
    /// descriptors.
    func objects(under path: String) -> [String: Interfaces] {
        objects.filter { $0.key.hasPrefix(path + "/") }
    }

    /// The objects with `interface`, and its properties.
    func objects(with interface: String) -> [(path: String, properties: [String: DBusValue])] {
        objects.compactMap { path, interfaces in interfaces[interface].map { (path, $0) } }.sorted { $0.path < $1.path }
    }

    /// The first adapter, as BlueZ numbers them (hci0).
    func adapter() async -> (path: String, properties: [String: DBusValue])? {
        guard await connection() != nil else { return nil }
        return objects(with: BlueZInterface.adapter).first
    }

    // MARK: Observers

    /// Hears every change BlueZ reports, after the copy has it, with the
    /// object's interfaces as they now are.
    func observe(_ observer: @escaping @Sendable (BlueZEvent, Interfaces) -> Void) -> Int {
        nextObserver += 1
        observers[nextObserver] = observer
        return nextObserver
    }

    func removeObserver(_ token: Int) { observers[token] = nil }

    private func notify(_ event: BlueZEvent) {
        let path = switch event {
        case .added(let path, _), .removed(let path, _), .changed(let path, _, _): path
        }
        let current = objects[path] ?? [:]
        observers.values.forEach { $0(event, current) }
    }

    private func interfacesAdded(_ message: DBusMessage) {
        guard message.body.count >= 2, let path = message.body[0].pathValue else { return }
        let added = Self.interfaces(message.body[1])
        objects[path, default: [:]].merge(added) { $1 }
        notify(.added(path: path, interfaces: added))
    }

    private func interfacesRemoved(_ message: DBusMessage) {
        guard message.body.count >= 2, let path = message.body[0].pathValue,
              case .array(let names) = message.body[1] else { return }
        let removed = names.compactMap(\.stringValue)
        removed.forEach { objects[path]?[$0] = nil }
        if objects[path]?.isEmpty == true { objects[path] = nil }
        notify(.removed(path: path, interfaces: removed))
    }

    private func propertiesChanged(_ message: DBusMessage) {
        guard let path = message.path, message.body.count >= 2, let interface = message.body[0].stringValue else { return }
        let changed = Self.properties(message.body[1])
        objects[path, default: [:]][interface, default: [:]].merge(changed) { $1 }
        if message.body.count >= 3, case .array(let invalidated) = message.body[2] {
            invalidated.compactMap(\.stringValue).forEach { objects[path]?[interface]?[$0] = nil }
        }
        notify(.changed(path: path, interface: interface, changed: changed))
    }

    // MARK: Decoding

    /// a{sa{sv}}.
    static func interfaces(_ value: DBusValue) -> Interfaces {
        guard case .dictionary(let entries) = value else { return [:] }
        var interfaces: Interfaces = [:]
        for (name, properties) in entries {
            guard let name = name.stringValue else { continue }
            interfaces[name] = self.properties(properties)
        }
        return interfaces
    }

    /// a{sv}, the variants unwrapped.
    static func properties(_ value: DBusValue) -> [String: DBusValue] {
        guard case .dictionary(let entries) = value else { return [:] }
        var properties: [String: DBusValue] = [:]
        for (name, value) in entries {
            guard let name = name.stringValue else { continue }
            properties[name] = value.unwrapped
        }
        return properties
    }
}

extension DBusValue {
    var unwrapped: DBusValue {
        if case .variant(let variant) = self { return variant.value.unwrapped }
        return self
    }

    var stringValue: String? {
        switch unwrapped {
        case .string(let string), .objectPath(let string): string
        default: nil
        }
    }

    var pathValue: String? {
        if case .objectPath(let path) = unwrapped { return path }
        return stringValue
    }

    var boolValue: Bool? {
        if case .boolean(let value) = unwrapped { return value }
        return nil
    }

    var intValue: Int? {
        switch unwrapped {
        case .byte(let value): Int(value)
        case .int16(let value): Int(value)
        case .uint16(let value): Int(value)
        case .int32(let value): Int(value)
        case .uint32(let value): Int(value)
        case .int64(let value): Int(value)
        case .uint64(let value): Int(value)
        default: nil
        }
    }

    /// ay.
    var bytes: [UInt8]? {
        guard case .array(let elements) = unwrapped else { return nil }
        return elements.compactMap { if case .byte(let byte) = $0 { byte } else { nil } }
    }

    var stringArray: [String] {
        guard case .array(let elements) = unwrapped else { return [] }
        return elements.compactMap(\.stringValue)
    }

    static func byteArray(_ bytes: [UInt8]) -> DBusValue { .array(bytes.map { .byte($0) }) }
}
