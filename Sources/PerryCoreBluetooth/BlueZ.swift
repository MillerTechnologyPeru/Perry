import DBus
import Glibc

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
        case idle, connecting, connected(DBusConnection), unavailable
    }

    private var phase = Phase.idle
    private var waiting: [CheckedContinuation<DBusConnection?, Never>] = []
    /// path → interface → properties.
    private(set) var objects: [String: Interfaces] = [:]
    private var observers: [Int: @Sendable (BlueZEvent, Interfaces) -> Void] = [:]
    private var nextObserver = 0

    // MARK: Connection

    /// The connection, made on first use; nil when there is no system bus
    /// or BlueZ is not on it.
    func connection() async -> DBusConnection? {
        switch phase {
        case .connected(let connection):
            if await connection.isConnected { return connection }
            phase = .unavailable
            objects = [:]
            return nil
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
        var connection: DBusConnection?
        do {
            connection = try await DBusConnection.connect(to: .system)
            try await BlueZ.shared.connected(connection!)
        } catch {
            await connection?.close()
            await BlueZ.shared.closed()
        }
    }

    private func connected(_ connection: DBusConnection) async throws {
        // Signals from BlueZ only; subscribing first misses none of them.
        // The bus sends only BlueZ's; the connection hands them on unsorted, as it knows a sender by
        // its unique name, not the one the rules give. One stream keeps them in order.
        guard let bluez = DBusBusName(rawValue: "org.bluez"), let objectManager = DBusInterface(rawValue: BlueZInterface.objectManager),
              let properties = DBusInterface(rawValue: BlueZInterface.properties) else { return }
        let (signals, heard) = AsyncStream<DBusMessage>.makeStream()
        await connection.setMessageHandler { message in
            if message.type == .signal { heard.yield(message) }
        }
        try await connection.addMatch(.signal(interface: objectManager, sender: bluez))
        try await connection.addMatch(.propertiesChanged(sender: bluez))
        Task {
            for await message in signals {
                switch (message.interface, message.member?.rawValue) {
                case (objectManager, "InterfacesAdded"): self.interfacesAdded(message)
                case (objectManager, "InterfacesRemoved"): self.interfacesRemoved(message)
                case (properties, "PropertiesChanged"): self.propertiesChanged(message)
                default: break
                }
            }
        }

        let reply = try await Self.call(connection, path: "/", interface: BlueZInterface.objectManager, method: "GetManagedObjects")
        if case .dictionary(let managed)? = reply.first {
            for entry in managed {
                guard let path = entry.key.pathValue else { continue }
                objects[path] = Self.interfaces(entry.value)
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
    func call(_ path: String, _ interface: String, _ method: String, _ body: [DBusValue] = []) async throws -> [DBusValue] {
        guard let connection = await connection() else {
            throw BlueZError(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "BlueZ is not running")
        }
        return try await Self.call(connection, path: path, interface: interface, method: method, body: body)
    }

    private static func call(_ connection: DBusConnection, path: String, interface: String, method: String,
                             body: [DBusValue] = []) async throws -> [DBusValue] {
        guard let destination = DBusBusName(rawValue: "org.bluez"), let path = DBusObjectPath(rawValue: path),
              let interface = DBusInterface(rawValue: interface), let method = DBusMember(rawValue: method) else {
            throw BlueZError(name: "org.freedesktop.DBus.Error.InvalidArgs", message: "\(path) \(interface).\(method)")
        }
        do {
            // No timeout: a call waits for its answer, as a connection to a device far away does.
            return try await connection.callMethod(destination: destination, path: path, interface: interface, method: method,
                                                   arguments: body, timeout: nil)
        } catch let error as DBusError {
            throw BlueZError(name: error.name.rawValue, message: error.message)
        }
    }

    /// Sets a property of an object of BlueZ's.
    func set(_ path: String, _ interface: String, _ property: String, _ value: DBusVariant) async throws {
        _ = try await call(path, BlueZInterface.properties, "Set",
                           [.string(interface), .string(property), .variant(value)])
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
        guard message.arguments.count >= 2, let path = message.arguments[0].pathValue else { return }
        let added = Self.interfaces(message.arguments[1])
        objects[path, default: [:]].merge(added) { $1 }
        notify(.added(path: path, interfaces: added))
    }

    private func interfacesRemoved(_ message: DBusMessage) {
        guard message.arguments.count >= 2, let path = message.arguments[0].pathValue,
              case .array(let names) = message.arguments[1] else { return }
        let removed = names.compactMap(\.stringValue)
        removed.forEach { objects[path]?[$0] = nil }
        if objects[path]?.isEmpty == true { objects[path] = nil }
        notify(.removed(path: path, interfaces: removed))
    }

    private func propertiesChanged(_ message: DBusMessage) {
        guard let path = message.path?.rawValue, message.arguments.count >= 2, let interface = message.arguments[0].stringValue else { return }
        let changed = Self.properties(message.arguments[1])
        objects[path, default: [:]][interface, default: [:]].merge(changed) { $1 }
        if message.arguments.count >= 3, case .array(let invalidated) = message.arguments[2] {
            invalidated.compactMap(\.stringValue).forEach { objects[path]?[interface]?[$0] = nil }
        }
        notify(.changed(path: path, interface: interface, changed: changed))
    }

    // MARK: Decoding

    /// a{sa{sv}}.
    static func interfaces(_ value: DBusValue) -> Interfaces {
        guard case .dictionary(let entries) = value else { return [:] }
        var interfaces: Interfaces = [:]
        for entry in entries {
            guard let name = entry.key.stringValue else { continue }
            interfaces[name] = self.properties(entry.value)
        }
        return interfaces
    }

    /// a{sv}, the variants unwrapped.
    static func properties(_ value: DBusValue) -> [String: DBusValue] {
        guard case .dictionary(let entries) = value else { return [:] }
        var properties: [String: DBusValue] = [:]
        for entry in entries {
            guard let name = entry.key.stringValue else { continue }
            properties[name] = entry.value.unwrapped
        }
        return properties
    }
}

typealias DBusValue = DBusMessageArgument
typealias DBusVariant = DBusMessageArgument.Variant

extension DBusMessageArgument {
    var unwrapped: DBusValue {
        if case .variant(let variant) = self { return variant.element.unwrapped }
        return self
    }

    /// An object path's text, or a string's.
    var pathValue: String? {
        if case .objectPath(let path) = unwrapped { return path.rawValue }
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

    /// ay.
    static func byteArray(_ bytes: [UInt8]) -> DBusValue {
        .array(Array(type: .byte, bytes.map { .byte($0) })!)
    }

    /// as.
    static func strings(_ strings: [String]) -> DBusValue {
        .array(Array(type: .string, strings.map { .string($0) })!)
    }

    /// a{sv}, each value in a variant.
    static func options(_ entries: [String: DBusValue] = [:]) -> DBusValue {
        .dictionary(Dictionary(keyType: .string, valueType: .variant,
                               entries.sorted { $0.key < $1.key }.map { .init(key: .string($0.key), value: .variant(DBusVariant($0.value))) })!)
    }
}
