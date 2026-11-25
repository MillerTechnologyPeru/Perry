import DBus

/// What a Mac app shows on its icon in the desktop's dock: a count, a
/// progress bar, and a request for attention. Sent as
/// `com.canonical.Unity.LauncherEntry` updates, which docks such as Cacao's
/// and KDE's read, for the app's desktop entry, named by its `app_id` (its
/// bundle identifier).
///
/// Updates are sent in order from a task of their own on a session bus
/// connection kept for as long as the app runs: a dock forgets an app's
/// entry when its connection goes. With no session bus, nothing is sent.
public final class DesktopLauncherEntry: Sendable {

    /// What the icon shows.
    public struct State: Equatable, Sendable {
        /// The count on the badge, or nil for none.
        public var count: Int64?
        /// From 0 to 1, or nil for no progress bar.
        public var progress: Double?
        /// Whether the app wants attention.
        public var urgent = false

        public init(count: Int64? = nil, progress: Double? = nil, urgent: Bool = false) {
            self.count = count
            self.progress = progress
            self.urgent = urgent
        }
    }

    /// The desktop entry's URI, as the interface names apps.
    public let appURI: String

    private let updates: AsyncStream<State>.Continuation

    /// Starts sending updates for the app with an `app_id`, on the session
    /// bus, or the bus at `address`.
    public init(appID: String, address: String? = nil) {
        let appURI = "application://\(appID).desktop"
        self.appURI = appURI
        let (stream, continuation) = AsyncStream.makeStream(of: State.self)
        updates = continuation
        Task.detached {
            await Self.send(stream, appURI: appURI, address: address)
        }
    }

    deinit {
        updates.finish()
    }

    /// Shows a state on the app's icon.
    public func update(_ state: State) {
        updates.yield(state)
    }

    /// The signal, from an object path of the entry's own.
    static let updateSignal = DBusMessage.Signal(
        path: DBusObjectPath(rawValue: "/com/canonical/unity/launcherentry/perry")!,
        interface: DBusInterface(rawValue: "com.canonical.Unity.LauncherEntry")!,
        name: DBusMember(rawValue: "Update")!
    )

    /// `Update`'s arguments: the URI, and every property, so a dock that
    /// missed an update still has all of them.
    static func arguments(appURI: String, state: State) -> [DBusMessageArgument] {
        let properties: [(String, DBusMessageArgument)] = [
            ("count", .int64(state.count ?? 0)),
            ("count-visible", .boolean(state.count != nil)),
            ("progress", .double(min(max(state.progress ?? 0, 0), 1))),
            ("progress-visible", .boolean(state.progress != nil)),
            ("urgent", .boolean(state.urgent)),
        ]
        let entries = properties.map {
            DBusMessageArgument.Dictionary.Entry(key: .string($0.0), value: .variant(.init($0.1)))
        }
        return [
            .string(appURI),
            .dictionary(DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, entries)!),
        ]
    }

    private static func send(_ updates: AsyncStream<State>, appURI: String, address: String?) async {
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
        for await state in updates {
            try? await connection.emit(updateSignal, arguments: arguments(appURI: appURI, state: state))
        }
        await connection.close()
    }
}
