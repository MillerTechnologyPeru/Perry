public import CacaoDBusMenu
import DBus

/// A Mac app's status item on the desktop, as an `org.kde.StatusNotifierItem`,
/// the items Cacao's menu bar and other desktops' panels show at their right.
///
/// Each item has a connection of its own to the session bus, or the bus at
/// `address`, with the item at `/StatusNotifierItem` and its menu, as
/// `com.canonical.dbusmenu`, at `/MenuBar`. It registers with the
/// `org.kde.StatusNotifierWatcher`, and again whenever a watcher starts, so
/// an item made before the menu bar shows once the bar is there. Removing
/// the item closes its connection, which takes it off the bar.
///
/// An item with a menu shows it when clicked; one without is activated:
/// `onActivate` hears it. The bar's `AboutToShow` hands the menu's
/// identifier to `onMenuAboutToShow`, so the app can bring the menu up to
/// date and publish it, and the bar is answered once what the app published
/// is served; a click on one of its items is handed to `onMenuClick`. The
/// handlers run on tasks of their own. Requests are sent in order from a
/// task of its own; with no bus, nothing is shown.
public final class DesktopStatusItem: Sendable {

    /// What the bar shows of the item.
    public struct Properties: Equatable, Sendable {

        /// Whether the item wants to be seen.
        public enum Status: String, Sendable {
            /// Hidden: the bar doesn't show it.
            case passive = "Passive"
            case active = "Active"
            /// Asking for the user's attention.
            case needsAttention = "NeedsAttention"
        }

        /// The app's name for the item.
        public var id: String
        public var title: String
        public var toolTip: String
        public var status: Status
        /// Whether the item has a menu, which a click shows instead of
        /// activating the item.
        public var hasMenu: Bool

        public init(id: String, title: String = "", toolTip: String = "", status: Status = .active, hasMenu: Bool = false) {
            self.id = id
            self.title = title
            self.toolTip = toolTip
            self.status = status
            self.hasMenu = hasMenu
        }
    }

    private enum Request: Sendable {
        case update(Properties)
        case menu(DBusMenuItem)
        /// Resumes once the requests before it are done.
        case barrier(CheckedContinuation<Void, Never>)
        case remove
    }

    private let requests: AsyncStream<Request>.Continuation

    /// Shows an item on the session bus, or the bus at `address`.
    public init(_ properties: Properties, address: String? = nil,
                onActivate: @escaping @Sendable () -> Void,
                onMenuClick: @escaping @Sendable (_ id: Int32) -> Void = { _ in },
                onMenuAboutToShow: @escaping @Sendable (_ id: Int32) async -> Void = { _ in }) {
        let (stream, continuation) = AsyncStream.makeStream(of: Request.self)
        requests = continuation
        let handlers = Handlers(activate: onActivate, menuClick: onMenuClick, menuAboutToShow: onMenuAboutToShow) {
            await withCheckedContinuation { waiter in
                // Once the item is gone, nothing is left to wait for.
                if case .terminated = continuation.yield(.barrier(waiter)) { waiter.resume() }
            }
        }
        Task.detached {
            await Self.run(stream, properties: properties, address: address, handlers: handlers)
        }
    }

    deinit {
        requests.finish()
    }

    /// Shows the item as it is now.
    public func update(_ properties: Properties) {
        requests.yield(.update(properties))
    }

    /// Serves a newer menu: the bar hears what changed.
    public func publish(_ menu: DBusMenuItem) {
        requests.yield(.menu(menu))
    }

    /// Takes the item off the bar.
    public func remove() {
        requests.yield(.remove)
        requests.finish()
    }

    // MARK: The bus

    static let itemPath = DBusObjectPath(rawValue: "/StatusNotifierItem")!
    static let menuPath = DBusObjectPath(rawValue: "/MenuBar")!
    static let itemInterface = DBusInterface(rawValue: "org.kde.StatusNotifierItem")!
    static let watcherName = DBusBusName(rawValue: "org.kde.StatusNotifierWatcher")!
    static let watcherPath = DBusObjectPath(rawValue: "/StatusNotifierWatcher")!
    static let watcherInterface = DBusInterface(rawValue: "org.kde.StatusNotifierWatcher")!

    private struct Handlers: Sendable {
        let activate: @Sendable () -> Void
        let menuClick: @Sendable (Int32) -> Void
        let menuAboutToShow: @Sendable (Int32) async -> Void
        /// Waits until the requests made so far are done.
        let served: @Sendable () async -> Void
    }

    /// The item's properties, read by the bar while they change.
    private actor State {
        var properties: Properties

        init(_ properties: Properties) {
            self.properties = properties
        }

        /// Stores newer properties, and returns the ones they replace.
        func replace(with properties: Properties) -> Properties {
            defer { self.properties = properties }
            return self.properties
        }
    }

    /// The signals that tell the bar to read the item again, for what
    /// changed from one set of properties to the next.
    static func signals(from old: Properties, to new: Properties) -> [(name: String, arguments: [DBusMessageArgument])] {
        var signals: [(name: String, arguments: [DBusMessageArgument])] = []
        if old.title != new.title || old.id != new.id { signals.append(("NewTitle", [])) }
        if old.toolTip != new.toolTip { signals.append(("NewToolTip", [])) }
        if old.status != new.status { signals.append(("NewStatus", [.string(new.status.rawValue)])) }
        if old.hasMenu != new.hasMenu { signals.append(("NewMenu", [])) }
        return signals
    }

    private static func run(_ requests: AsyncStream<Request>, properties: Properties, address: String?, handlers: Handlers) async {
        let connection: DBusConnection
        do {
            if let address {
                connection = try await DBusConnection.connect(to: address)
            } else {
                connection = try await DBusConnection.connect(to: .session)
            }
        } catch {
            // Nothing is shown; barriers still pass.
            for await request in requests {
                if case let .barrier(continuation) = request { continuation.resume() }
            }
            return
        }
        let state = State(properties)
        let exporter = DBusMenuExporter(connection: connection, path: menuPath, menu: .root([])) { event in
            guard event.kind == .clicked else { return }
            handlers.menuClick(event.id)
        } onAboutToShow: { id in
            await handlers.menuAboutToShow(id)
            await handlers.served()
        }
        await exporter.export()
        await connection.export(DBusExportedObject([implementation(state, handlers)]), at: itemPath)

        // Registered now, and again whenever a watcher starts.
        let owners = try? await connection.signals(
            interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
            member: DBusMember(rawValue: "NameOwnerChanged")!,
            sender: DBusBusName(rawValue: "org.freedesktop.DBus")!
        )
        let following = owners.map { owners in
            Task {
                for await message in owners {
                    guard message.arguments.count == 3,
                          case let .string(name) = message.arguments[0], name == watcherName.rawValue,
                          case let .string(owner) = message.arguments[2], !owner.isEmpty
                    else { continue }
                    await register(on: connection)
                }
            }
        }
        await register(on: connection)

        serving: for await request in requests {
            switch request {
            case let .update(properties):
                let old = await state.replace(with: properties)
                for signal in signals(from: old, to: properties) {
                    let message = DBusMessage.Signal(path: itemPath, interface: itemInterface, name: DBusMember(rawValue: signal.name)!)
                    try? await connection.emit(message, arguments: signal.arguments)
                }
            case let .menu(menu):
                await exporter.update(menu)
            case let .barrier(continuation):
                continuation.resume()
            case .remove:
                break serving
            }
        }
        following?.cancel()
        await exporter.unexport()
        await connection.unexport(at: itemPath)
        // Answered after the messages sent before it are written.
        _ = try? await connection.getBusID()
        await connection.close()
        // Barriers left after the item went: nothing waits for the bus.
        for await request in requests {
            if case let .barrier(continuation) = request { continuation.resume() }
        }
    }

    private static func register(on connection: DBusConnection) async {
        _ = try? await connection.callMethod(
            destination: watcherName,
            path: watcherPath,
            interface: watcherInterface,
            method: DBusMember(rawValue: "RegisterStatusNotifierItem")!,
            arguments: [.string(itemPath.rawValue)]
        )
    }

    // MARK: The interface

    /// The type a signature of one complete type names.
    private static func type(_ signature: String) -> DBusSignature.ValueType {
        DBusSignature(rawValue: signature)![0]
    }

    /// No icons of its own: icon pixmaps, `a(iiay)`, are empty.
    private static let noPixmaps = DBusMessageArgument.array(DBusMessageArgument.Array(type: type("(iiay)"), [])!)

    /// The `(sa(iiay)ss)` tool tip: an icon name, its pixmaps, a title and
    /// a description.
    static func toolTip(_ text: String) -> DBusMessageArgument {
        .struct(DBusMessageArgument.Structure([.string(""), noPixmaps, .string(text), .string("")])!)
    }

    private static func implementation(_ state: State, _ handlers: Handlers) -> DBusInterfaceImplementation {
        func string(_ name: String, _ value: @escaping @Sendable (Properties) -> String) -> DBusInterfaceImplementation.Property {
            .init(name: name, type: .string) { .string(value(await state.properties)) }
        }
        func pixmaps(_ name: String) -> DBusInterfaceImplementation.Property {
            .init(name: name, type: type("a(iiay)")) { noPixmaps }
        }
        // Points: a click, a menu or a scroll here comes from the bar, which
        // shows the menu itself.
        let point = DBusSignature(rawValue: "ii")!
        return DBusInterfaceImplementation(
            name: itemInterface,
            methods: [
                .init(name: DBusMember(rawValue: "Activate")!, inputSignature: point, inputNames: ["x", "y"]) { _ in
                    handlers.activate()
                    return []
                },
                .init(name: DBusMember(rawValue: "SecondaryActivate")!, inputSignature: point, inputNames: ["x", "y"]) { _ in [] },
                .init(name: DBusMember(rawValue: "ContextMenu")!, inputSignature: point, inputNames: ["x", "y"]) { _ in [] },
                .init(name: DBusMember(rawValue: "Scroll")!, inputSignature: DBusSignature(rawValue: "is")!,
                      inputNames: ["delta", "orientation"]) { _ in [] },
            ],
            properties: [
                .init(name: "Category", type: .string) { .string("ApplicationStatus") },
                string("Id") { $0.id },
                string("Title") { $0.title },
                string("Status") { $0.status.rawValue },
                .init(name: "WindowId", type: .int32) { .int32(0) },
                .init(name: "IconName", type: .string) { .string("") },
                pixmaps("IconPixmap"),
                .init(name: "OverlayIconName", type: .string) { .string("") },
                pixmaps("OverlayIconPixmap"),
                .init(name: "AttentionIconName", type: .string) { .string("") },
                pixmaps("AttentionIconPixmap"),
                .init(name: "AttentionMovieName", type: .string) { .string("") },
                .init(name: "ToolTip", type: type("(sa(iiay)ss)")) {
                    toolTip(await state.properties.toolTip)
                },
                .init(name: "ItemIsMenu", type: .boolean) { .boolean(await state.properties.hasMenu) },
                .init(name: "Menu", type: .objectPath) {
                    .objectPath(await state.properties.hasMenu ? menuPath : DBusObjectPath(rawValue: "/")!)
                },
            ],
            signals: [
                .init(name: DBusMember(rawValue: "NewTitle")!),
                .init(name: DBusMember(rawValue: "NewIcon")!),
                .init(name: DBusMember(rawValue: "NewAttentionIcon")!),
                .init(name: DBusMember(rawValue: "NewOverlayIcon")!),
                .init(name: DBusMember(rawValue: "NewToolTip")!),
                .init(name: DBusMember(rawValue: "NewStatus")!, signature: DBusSignature(rawValue: "s")!, argumentNames: ["status"]),
                .init(name: DBusMember(rawValue: "NewMenu")!),
            ]
        )
    }
}
