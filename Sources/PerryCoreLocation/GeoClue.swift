import DBus
import Glibc

// GeoClue, the desktop's location service, through its D-Bus API on the
// system bus (DBUS_SYSTEM_BUS_ADDRESS, or /var/run/dbus/system_bus_socket).
// The process has one client, made when the app first asks for its
// location's authorization, once the desktop's permission allows it
// (Permission.swift, which asks the user the first time): its DesktopId is
// the app's desktop entry's (PerryUIKit's DesktopEntry, the bundle
// identifier). GeoClue may still refuse it. Without a system bus, or with no
// GeoClue on it, location services are unavailable, and no one is asked.

/// A location GeoClue reported.
struct GeoClueFix: Sendable {
    var latitude: Double
    var longitude: Double
    /// Meters.
    var accuracy: Double
    /// Meters; nil when unknown.
    var altitude: Double?
    /// Meters a second; nil when unknown.
    var speed: Double?
    /// Degrees clockwise from north; nil when unknown.
    var heading: Double?
    /// Seconds since 1970.
    var timestamp: Double?
}

enum GeoClueAnswer: Sendable {
    case authorized, denied, unavailable
}

private enum GeoClueName {
    static let service = "org.freedesktop.GeoClue2"
    static let manager = "org.freedesktop.GeoClue2.Manager"
    static let client = "org.freedesktop.GeoClue2.Client"
    static let location = "org.freedesktop.GeoClue2.Location"
    static let properties = "org.freedesktop.DBus.Properties"
}

/// A D-Bus error a call was answered with.
private struct GeoClueError: Error {
    let name: String
    let message: String
}

actor GeoClue {
    static let shared = GeoClue()

    private enum Phase {
        case idle, connecting, connected(DBusConnection), unavailable
    }

    private var phase = Phase.idle
    private var waiting: [CheckedContinuation<DBusConnection?, Never>] = []
    /// The client, once started; nil before and when refused.
    private var client: String?
    private var answer: GeoClueAnswer?
    private var answering: [CheckedContinuation<GeoClueAnswer, Never>] = []
    private var latest: GeoClueFix?
    private var observers: [@Sendable (GeoClueFix) -> Void] = []

    // MARK: Connection

    /// The system bus, with GeoClue on it or able to start; nil when there
    /// is no bus or no GeoClue.
    private func connection() async -> DBusConnection? {
        switch phase {
        case .connected(let connection):
            if await connection.isConnected { return connection }
            phase = .unavailable
            return nil
        case .unavailable: return nil
        case .idle:
            phase = .connecting
            Task.detached { await GeoClue.run() }
        case .connecting: break
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    /// Whether location services are there: GeoClue is on the system bus,
    /// or the bus can start it.
    func isAvailable() async -> Bool { await connection() != nil }

    private static func run() async {
        var connection: DBusConnection?
        do {
            connection = try await DBusConnection.connect(to: .system)
            try await GeoClue.shared.connected(connection!)
        } catch {
            await connection?.close()
            await GeoClue.shared.closed()
        }
    }

    private func connected(_ connection: DBusConnection) async throws {
        guard let service = DBusBusName(rawValue: GeoClueName.service), let client = DBusInterface(rawValue: GeoClueName.client),
              let updated = DBusMember(rawValue: "LocationUpdated") else { return }
        var present = try await connection.nameHasOwner(service)
        if !present { present = try await connection.listActivatableNames().contains(GeoClueName.service) }
        guard present else { throw GeoClueError(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "GeoClue is not there") }
        // The bus sends only GeoClue's; the connection hands them on unsorted, as it knows a sender
        // by its unique name, not the one the rule gives.
        let (updates, heard) = AsyncStream<DBusMessage>.makeStream()
        await connection.setMessageHandler { message in
            if message.type == .signal, message.interface == client, message.member == updated { heard.yield(message) }
        }
        try await connection.addMatch(.signal(interface: client, member: updated, sender: service))
        Task { for await message in updates { await self.locationUpdated(message) } }
        phase = .connected(connection)
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: connection) }
    }

    private func closed() {
        phase = .unavailable
        let waiters = waiting
        waiting = []
        waiters.forEach { $0.resume(returning: nil) }
        if client == nil { finish(.unavailable) }
    }

    private static func call(_ connection: DBusConnection, destination: String = GeoClueName.service, path: String,
                             interface: String, method: String, body: [DBusValue] = []) async throws -> [DBusValue] {
        guard let destination = DBusBusName(rawValue: destination), let path = DBusObjectPath(rawValue: path),
              let interface = DBusInterface(rawValue: interface), let method = DBusMember(rawValue: method) else {
            throw GeoClueError(name: "org.freedesktop.DBus.Error.InvalidArgs", message: "\(path) \(interface).\(method)")
        }
        do {
            // No timeout: a call waits for its answer, which may be the user's.
            return try await connection.callMethod(destination: destination, path: path, interface: interface, method: method,
                                                   arguments: body, timeout: nil)
        } catch let error as DBusError {
            throw GeoClueError(name: error.name.rawValue, message: error.message)
        }
    }

    // MARK: Authorization

    /// Asks for the location for the app `desktopID`, named `name`, at
    /// GeoClue's accuracy `level` (exact 8): the desktop asks the user the
    /// first time, with `reason`. Answered once; later calls get the same
    /// answer.
    func authorize(desktopID: String, name: String, reason: String?, level: UInt32) async -> GeoClueAnswer {
        if let answer { return answer }
        if !answering.isEmpty { return await withCheckedContinuation { answering.append($0) } }
        let result = await withCheckedContinuation { continuation in
            answering.append(continuation)
            Task { await self.start(desktopID: desktopID, name: name, reason: reason, level: level) }
        }
        return result
    }

    private func start(desktopID: String, name: String, reason: String?, level requested: UInt32) async {
        guard let connection = await connection() else { return finish(.unavailable) }
        var level = requested
        switch await DesktopPermission.ask(appID: desktopID, name: name, reason: reason) {
        case .denied: return finish(.denied)
        case .allowed(let allowed): level = min(level, allowed)
        case .unknown: break
        }
        do {
            let reply = try await Self.call(connection, path: "/org/freedesktop/GeoClue2/Manager",
                                            interface: GeoClueName.manager, method: "GetClient")
            guard let path = reply.first?.pathValue else { return finish(.unavailable) }
            for (property, value) in [("DesktopId", DBusValue.string(desktopID)), ("RequestedAccuracyLevel", .uint32(level))] {
                _ = try await Self.call(connection, path: path, interface: GeoClueName.properties, method: "Set",
                                        body: [.string(GeoClueName.client), .string(property), .variant(DBusVariant(value))])
            }
            client = path
            // GeoClue asks the agent before it answers.
            _ = try await Self.call(connection, path: path, interface: GeoClueName.client, method: "Start")
            finish(.authorized)
        } catch let error as GeoClueError {
            client = nil
            finish(error.name.hasSuffix("AccessDenied") ? .denied : .unavailable)
        } catch {
            client = nil
            finish(.unavailable)
        }
    }

    private func finish(_ result: GeoClueAnswer) {
        answer = result
        let waiters = answering
        answering = []
        waiters.forEach { $0.resume(returning: result) }
    }

    // MARK: Locations

    /// The newest location; nil before the first.
    func newest() -> GeoClueFix? { latest }

    /// Hears each new location, and the newest at once if there is one.
    func observe(_ observer: @escaping @Sendable (GeoClueFix) -> Void) {
        observers.append(observer)
        if let latest { observer(latest) }
    }

    private func locationUpdated(_ message: DBusMessage) async {
        let sender = message.path?.rawValue
        guard let client, sender == nil || sender == client, message.arguments.count >= 2, let path = message.arguments[1].pathValue,
              case .connected(let connection) = phase else { return }
        guard let reply = try? await Self.call(connection, path: path, interface: GeoClueName.properties, method: "GetAll",
                                               body: [.string(GeoClueName.location)]),
              case .dictionary(let entries)? = reply.first else { return }
        var properties: [String: DBusValue] = [:]
        for entry in entries {
            guard let key = entry.key.stringValue else { continue }
            properties[key] = entry.value.variantValue ?? entry.value
        }
        guard let latitude = properties["Latitude"]?.doubleValue, let longitude = properties["Longitude"]?.doubleValue else { return }
        func known(_ name: String, below: Double = -1e300) -> Double? {
            guard let value = properties[name]?.doubleValue, value > below else { return nil }
            return value
        }
        var timestamp: Double?
        if case .struct(let parts)? = properties["Timestamp"], parts.count == 2,
           case .uint64(let seconds) = parts[0], case .uint64(let microseconds) = parts[1] {
            timestamp = Double(seconds) + Double(microseconds) / 1_000_000
        }
        let fix = GeoClueFix(latitude: latitude, longitude: longitude, accuracy: properties["Accuracy"]?.doubleValue ?? 0,
                             altitude: known("Altitude"), speed: known("Speed", below: -0.5),
                             heading: known("Heading", below: -0.5), timestamp: timestamp)
        latest = fix
        observers.forEach { $0(fix) }
    }
}

// MARK: - D-Bus value helpers

typealias DBusValue = DBusMessageArgument
typealias DBusVariant = DBusMessageArgument.Variant

extension DBusMessageArgument {
    /// An object path's text.
    var pathValue: String? {
        if case .objectPath(let path) = self { return path.rawValue }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        return nil
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
