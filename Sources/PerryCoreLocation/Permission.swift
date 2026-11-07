import DBUS
import Glibc
import Logging

// Whether the user lets the app know its location, as the desktop keeps it:
// the permission store's "location" table (org.freedesktop.impl.portal.
// PermissionStore, on the session bus), which GNOME's Settings lists under
// Privacy › Location, where the user can take it back. GeoClue and the
// location portal ask the user only for sandboxed apps, so for an app Perry
// runs, Perry asks: with the desktop's own permission dialog (GNOME's
// org.freedesktop.impl.portal.Access), naming the app and giving its usage
// description, and keeps the answer in the table. Without a session bus,
// a permission store or a dialog, the desktop has no say: the app is let
// know, as GeoClue lets apps outside a sandbox.

enum DesktopPermission {
    enum Answer: Sendable {
        /// Allowed, at GeoClue's accuracy level (exact 8).
        case allowed(level: UInt32)
        case denied
        /// The desktop has no say.
        case unknown
    }

    private static let table = "location"
    private static let storeName = "org.freedesktop.impl.portal.PermissionStore"
    private static let storePath = "/org/freedesktop/impl/portal/PermissionStore"
    private static let accessInterface = "org.freedesktop.impl.portal.Access"

    private static let logger: Logger = {
        var logger = Logger(label: "perry.corelocation.permission")
        logger.logLevel = .critical
        return logger
    }()

    /// GeoClue's accuracy levels by the names the table keeps.
    private static let levels: [String: UInt32] = ["NONE": 0, "COUNTRY": 1, "CITY": 4, "NEIGHBORHOOD": 5, "STREET": 6, "EXACT": 8]

    /// The app's permission: kept, else the user's answer to the dialog,
    /// which is then kept.
    static func ask(appID: String, name: String, reason: String?) async -> Answer {
        do {
            return try await DBusClient.withSessionBus(auth: .external(userID: String(getuid())), logger: logger) { connection in
                if let kept = try await lookUp(appID, on: connection) { return kept }
                guard let granted = try await dialog(appID: appID, name: name, reason: reason, on: connection) else { return .unknown }
                try? await keep(appID, granted ? "EXACT" : "NONE", on: connection)
                return granted ? .allowed(level: 8) : .denied
            }
        } catch {
            return .unknown
        }
    }

    /// The app's permission as the table keeps it, without asking; nil
    /// when it has none, or there is no table.
    static func kept(appID: String) async -> Answer? {
        try? await DBusClient.withSessionBus(auth: .external(userID: String(getuid())), logger: logger) { connection in
            try await lookUp(appID, on: connection)
        }
    }

    /// The table's entry for the app; nil when there is none.
    private static func lookUp(_ appID: String, on connection: DBusClient.Connection) async throws -> Answer? {
        let reply: [DBusValue]
        do {
            reply = try await call(connection, destination: storeName, path: storePath, interface: storeName, method: "Lookup",
                                   body: [.string(table), .string(table)])
        } catch let error as PermissionError where error.name.hasSuffix("NotFound") {
            return nil
        }
        guard case .dictionary(let entries)? = reply.first else { return nil }
        for (key, value) in entries where key.string == appID {
            guard let level = value.array?.first?.string else { return nil }
            let numeric = levels[level.uppercased()] ?? 0
            return numeric == 0 ? .denied : .allowed(level: numeric)
        }
        return nil
    }

    /// The desktop's dialog: true if the user allows, false if not; nil
    /// without one.
    private static func dialog(appID: String, name: String, reason: String?,
                               on connection: DBusClient.Connection) async throws -> Bool? {
        // The desktop's portal backend: GNOME's, else any that answers.
        for backend in ["org.freedesktop.impl.portal.desktop.gnome", "org.freedesktop.impl.portal.desktop.gtk"] {
            let options: [DBusValue: DBusValue] = [
                .string("deny_label"): .variant(DBusVariant(.string("Deny"))),
                .string("grant_label"): .variant(DBusVariant(.string("Allow"))),
                .string("icon"): .variant(DBusVariant(.string("find-location-symbolic"))),
            ]
            let body: [DBusValue] = [
                .objectPath("/org/freedesktop/portal/desktop/request/perry/location"),
                .string(appID), .string(""),
                .string("Allow \(name) to Use Your Location?"),
                .string(reason ?? "\(name) wants to know where you are."),
                .string("Location access can be changed at any time from the privacy settings."),
                .dictionary(options),
            ]
            let reply: [DBusValue]
            do {
                reply = try await call(connection, destination: backend, path: "/org/freedesktop/portal/desktop",
                                       interface: accessInterface, method: "AccessDialog", body: body, signature: "osssssa{sv}")
            } catch let error as PermissionError where error.name.hasSuffix("ServiceUnknown") || error.name.hasSuffix("UnknownMethod")
                || error.name.hasSuffix("UnknownInterface") || error.name.hasSuffix("UnknownObject") || error.name.hasSuffix("NameHasNoOwner") {
                continue
            }
            // 0 granted, 1 cancelled, 2 closed otherwise.
            guard case .uint32(let response)? = reply.first else { return nil }
            return response == 0
        }
        return nil
    }

    /// Keeps the app's level in the table.
    private static func keep(_ appID: String, _ level: String, on connection: DBusClient.Connection) async throws {
        var now = timespec()
        clock_gettime(CLOCK_REALTIME, &now)
        _ = try await call(connection, destination: storeName, path: storePath, interface: storeName, method: "SetPermission",
                           body: [.string(table), .boolean(true), .string(table), .string(appID),
                                  .array([.string(level), .string(String(now.tv_sec))])],
                           signature: "sbssas")
    }

    private struct PermissionError: Error {
        let name: String
    }

    private static func call(_ connection: DBusClient.Connection, destination: String, path: String, interface: String,
                             method: String, body: [DBusValue], signature: String? = nil) async throws -> [DBusValue] {
        let request = DBusRequest.createMethodCall(destination: destination, path: path, interface: interface,
                                                   method: method, body: body, signature: signature)
        guard let reply = try await connection.send(request) else { return [] }
        if case .error = reply.messageType {
            let name = reply.headerFields.first { $0.code == .errorName }.flatMap { $0.variant.value.string }
            throw PermissionError(name: name ?? "org.freedesktop.DBus.Error.Failed")
        }
        return reply.body
    }
}
