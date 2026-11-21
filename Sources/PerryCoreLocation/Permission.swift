import DBus
import Glibc

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

    /// GeoClue's accuracy levels by the names the table keeps.
    private static let levels: [String: UInt32] = ["NONE": 0, "COUNTRY": 1, "CITY": 4, "NEIGHBORHOOD": 5, "STREET": 6, "EXACT": 8]

    /// The app's permission: kept, else the user's answer to the dialog,
    /// which is then kept.
    static func ask(appID: String, name: String, reason: String?) async -> Answer {
        let asked: Answer? = try? await withSessionBus { connection in
            if let kept = try await lookUp(appID, on: connection) { return kept }
            guard let granted = try await dialog(appID: appID, name: name, reason: reason, on: connection) else { return .unknown }
            try? await keep(appID, granted ? "EXACT" : "NONE", on: connection)
            return granted ? .allowed(level: 8) : .denied
        }
        return asked ?? .unknown
    }

    /// The app's permission as the table keeps it, without asking; nil
    /// when it has none, or there is no table.
    static func kept(appID: String) async -> Answer? {
        (try? await withSessionBus { connection in try await lookUp(appID, on: connection) }) ?? nil
    }

    /// A connection to the session bus for the length of `body`.
    private static func withSessionBus<T: Sendable>(_ body: (DBusConnection) async throws -> T) async throws -> T {
        let connection = try await DBusConnection.connect(to: .session)
        do {
            let result = try await body(connection)
            await connection.close()
            return result
        } catch {
            await connection.close()
            throw error
        }
    }

    /// The table's entry for the app; nil when there is none.
    private static func lookUp(_ appID: String, on connection: DBusConnection) async throws -> Answer? {
        let reply: [DBusValue]
        do {
            reply = try await call(connection, destination: storeName, path: storePath, interface: storeName, method: "Lookup",
                                   body: [.string(table), .string(table)])
        } catch let error as PermissionError where error.name.hasSuffix("NotFound") {
            return nil
        }
        guard case .dictionary(let entries)? = reply.first else { return nil }
        for entry in entries where entry.key.stringValue == appID {
            guard case .array(let values) = entry.value, let level = values.first?.stringValue else { return nil }
            let numeric = levels[level.uppercased()] ?? 0
            return numeric == 0 ? .denied : .allowed(level: numeric)
        }
        return nil
    }

    /// The desktop's dialog: true if the user allows, false if not; nil
    /// without one.
    private static func dialog(appID: String, name: String, reason: String?,
                               on connection: DBusConnection) async throws -> Bool? {
        // The desktop's portal backend: GNOME's, else any that answers.
        for backend in ["org.freedesktop.impl.portal.desktop.gnome", "org.freedesktop.impl.portal.desktop.gtk"] {
            let options: [String: DBusValue] = [
                "deny_label": .string("Deny"),
                "grant_label": .string("Allow"),
                "icon": .string("find-location-symbolic"),
            ]
            let body: [DBusValue] = [
                .objectPath(DBusObjectPath(rawValue: "/org/freedesktop/portal/desktop/request/perry/location")!),
                .string(appID), .string(""),
                .string("Allow \(name) to Use Your Location?"),
                .string(reason ?? "\(name) wants to know where you are."),
                .string("Location access can be changed at any time from the privacy settings."),
                .options(options),
            ]
            let reply: [DBusValue]
            do {
                reply = try await call(connection, destination: backend, path: "/org/freedesktop/portal/desktop",
                                       interface: accessInterface, method: "AccessDialog", body: body)
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
    private static func keep(_ appID: String, _ level: String, on connection: DBusConnection) async throws {
        var now = timespec()
        clock_gettime(CLOCK_REALTIME, &now)
        _ = try await call(connection, destination: storeName, path: storePath, interface: storeName, method: "SetPermission",
                           body: [.string(table), .boolean(true), .string(table), .string(appID),
                                  .strings([level, String(now.tv_sec)])])
    }

    private struct PermissionError: Error {
        let name: String
    }

    private static func call(_ connection: DBusConnection, destination: String, path: String, interface: String,
                             method: String, body: [DBusValue]) async throws -> [DBusValue] {
        guard let destination = DBusBusName(rawValue: destination), let path = DBusObjectPath(rawValue: path),
              let interface = DBusInterface(rawValue: interface), let method = DBusMember(rawValue: method) else {
            throw PermissionError(name: "org.freedesktop.DBus.Error.InvalidArgs")
        }
        do {
            // No timeout: a call waits for its answer, which may be the user's.
            return try await connection.callMethod(destination: destination, path: path, interface: interface, method: method,
                                                   arguments: body, timeout: nil)
        } catch let error as DBusError {
            throw PermissionError(name: error.name.rawValue)
        }
    }
}
