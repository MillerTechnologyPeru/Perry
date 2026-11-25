import DBus

/// A Mac app's notifications on the desktop, through its notification
/// server, `org.freedesktop.Notifications`, as Cacao's menu bar and other
/// desktops run one.
///
/// Notifications are named by the app's own identifiers: posting one with
/// an identifier already shown replaces it in place. When the user clicks a
/// notification or one of its buttons, `onResponse` hears the identifier
/// and the action's key, `default` for the notification itself. Requests
/// are sent in order from a task of their own. With no session bus or no
/// server, nothing is shown.
public final class DesktopNotifications: Sendable {

    /// A notification to show.
    public struct Notification: Sendable {
        public var identifier: String
        public var appName: String
        public var summary: String
        public var body: String
        /// The buttons, in order: each action's key and its label.
        public var actions: [Action]
        /// Whether clicking the notification itself does something.
        public var hasDefaultAction: Bool

        public struct Action: Sendable, Equatable {
            public var key: String
            public var label: String

            public init(key: String, label: String) {
                self.key = key
                self.label = label
            }
        }

        public init(identifier: String, appName: String, summary: String, body: String = "",
                    actions: [Action] = [], hasDefaultAction: Bool = true) {
            self.identifier = identifier
            self.appName = appName
            self.summary = summary
            self.body = body
            self.actions = actions
            self.hasDefaultAction = hasDefaultAction
        }
    }

    /// The key of the action the notification itself stands for.
    public static let defaultAction = "default"

    private enum Request: Sendable {
        case post(Notification)
        case close(String)
    }

    private let requests: AsyncStream<Request>.Continuation

    /// Starts a client on the session bus, or the bus at `address`.
    public init(address: String? = nil, onResponse: @escaping @Sendable (_ identifier: String, _ action: String) -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Request.self)
        requests = continuation
        Task.detached {
            await Self.run(stream, address: address, onResponse: onResponse)
        }
    }

    deinit {
        requests.finish()
    }

    /// Shows a notification, or shows it again in place of the one with
    /// the same identifier.
    public func post(_ notification: Notification) {
        requests.yield(.post(notification))
    }

    /// Takes a notification away.
    public func close(identifier: String) {
        requests.yield(.close(identifier))
    }

    // MARK: The bus

    static let name = DBusBusName(rawValue: "org.freedesktop.Notifications")!
    static let path = DBusObjectPath(rawValue: "/org/freedesktop/Notifications")!
    static let interface = DBusInterface(rawValue: "org.freedesktop.Notifications")!

    /// `Notify`'s arguments: the actions run together as keys and labels.
    static func notifyArguments(_ notification: Notification, replacing id: UInt32) -> [DBusMessageArgument] {
        var actions: [DBusMessageArgument] = []
        if notification.hasDefaultAction {
            actions += [.string(defaultAction), .string("")]
        }
        for action in notification.actions {
            actions += [.string(action.key), .string(action.label)]
        }
        return [
            .string(notification.appName),
            .uint32(id),
            .string(""),
            .string(notification.summary),
            .string(notification.body),
            .array(DBusMessageArgument.Array(type: .string, actions)!),
            .dictionary(DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant)!),
            .int32(-1),
        ]
    }

    /// The server's IDs for the app's identifiers, while they're shown.
    private actor Shown {
        var ids: [String: UInt32] = [:]

        func id(for identifier: String) -> UInt32? { ids[identifier] }
        func set(_ id: UInt32, for identifier: String) { ids[identifier] = id }
        func identifier(for id: UInt32) -> String? { ids.first { $0.value == id }?.key }
        func remove(_ id: UInt32) { ids = ids.filter { $0.value != id } }
    }

    private static func run(_ requests: AsyncStream<Request>, address: String?,
                            onResponse: @escaping @Sendable (String, String) -> Void) async {
        let connection: DBusConnection
        do {
            if let address {
                connection = try await DBusConnection.connect(to: address)
            } else {
                connection = try await DBusConnection.connect(to: .session)
            }
        } catch {
            return
        }
        let shown = Shown()
        // The server's signals for every app: only the app's own IDs count.
        // They're read in the order sent, as a click's ActionInvoked comes
        // just before the NotificationClosed that forgets its ID.
        if let signals = try? await connection.signals(interface: interface, path: path) {
            Task {
                for await message in signals {
                    switch message.member?.rawValue {
                    case "ActionInvoked":
                        guard message.arguments.count == 2,
                              case let .uint32(id) = message.arguments[0],
                              case let .string(key) = message.arguments[1],
                              let identifier = await shown.identifier(for: id)
                        else { continue }
                        onResponse(identifier, key)
                    case "NotificationClosed":
                        guard case let .uint32(id)? = message.arguments.first else { continue }
                        await shown.remove(id)
                    default:
                        continue
                    }
                }
            }
        }
        for await request in requests {
            switch request {
            case let .post(notification):
                let replacing = await shown.id(for: notification.identifier) ?? 0
                guard let reply = try? await connection.callMethod(
                    destination: name, path: path, interface: interface,
                    method: DBusMember(rawValue: "Notify")!,
                    arguments: notifyArguments(notification, replacing: replacing)
                ), case let .uint32(id)? = reply.first else { continue }
                await shown.set(id, for: notification.identifier)
            case let .close(identifier):
                guard let id = await shown.id(for: identifier) else { continue }
                _ = try? await connection.callMethod(
                    destination: name, path: path, interface: interface,
                    method: DBusMember(rawValue: "CloseNotification")!,
                    arguments: [.uint32(id)]
                )
                await shown.remove(id)
            }
        }
        await connection.close()
    }
}
