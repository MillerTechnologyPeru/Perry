import CacaoDBusMenu
import DBus
import Foundation
@testable import PerryDesktopStatusItems
import Testing

/// A status item on a private bus, with a watcher and a bar of the tests'
/// own, as the desktop's menu bar is.
@Suite("Serving a status item", .serialized)
struct DesktopStatusItemTests {
    /// What the app's side and the watcher heard.
    private actor Log {
        var activations = 0
        var clicks: [Int32] = []
        var shown: [Int32] = []
        var registered: [String] = []
        func activate() { activations += 1 }
        func click(_ id: Int32) { clicks.append(id) }
        func show(_ id: Int32) { shown.append(id) }
        func register(_ item: String) { registered.append(item) }
    }

    private static let item = DBusObjectPath(rawValue: "/StatusNotifierItem")!
    private static let interface = DBusInterface(rawValue: "org.kde.StatusNotifierItem")!

    /// A watcher that records the items registering with it, by their
    /// sender and path, as the desktop's does.
    private func watcher(on address: String, log: Log) async throws -> DBusConnection {
        let connection = try await DBusConnection.connect(to: address)
        let watcher = DBusInterfaceImplementation(
            name: DBusInterface(rawValue: "org.kde.StatusNotifierWatcher")!,
            methods: [
                .init(name: DBusMember(rawValue: "RegisterStatusNotifierItem")!, inputSignature: DBusSignature(rawValue: "s")!) { call in
                    if case let .string(service)? = call.arguments.first {
                        await log.register((call.sender?.rawValue ?? "") + service)
                    }
                    return []
                },
            ]
        )
        await connection.export(DBusExportedObject([watcher]), at: DBusObjectPath(rawValue: "/StatusNotifierWatcher")!)
        _ = try await connection.requestName(DBusBusName(rawValue: "org.kde.StatusNotifierWatcher")!, flags: [])
        return connection
    }

    private func properties(of service: DBusBusName, on bar: DBusConnection) async throws -> [String: DBusMessageArgument] {
        try await bar.getAllProperties(destination: service, path: Self.item, interface: Self.interface)
    }

    @Test("Registered once a watcher starts, read, activated, changed, and taken away", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func serves() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let log = Log()
        let item = DesktopStatusItem(.init(id: "Probe", title: "Probe", toolTip: "Probing"), address: bus.address) {
            Task { await log.activate() }
        }

        // Made before the menu bar: registered once its watcher is there.
        await item.waitUntilServed()
        let watcher = try await watcher(on: bus.address, log: log)
        #expect(await eventually { await log.registered.count == 1 })
        let registered = try #require(await log.registered.first)
        #expect(registered.hasSuffix("/StatusNotifierItem"))
        let service = try #require(DBusBusName(rawValue: String(registered.dropLast("/StatusNotifierItem".count))))

        let bar = try await DBusConnection.connect(to: bus.address)
        var read = try await properties(of: service, on: bar)
        #expect(read["Id"] == .string("Probe"))
        #expect(read["Title"] == .string("Probe"))
        #expect(read["Status"] == .string("Active"))
        #expect(read["Category"] == .string("ApplicationStatus"))
        #expect(read["ItemIsMenu"] == .boolean(false))
        #expect(read["Menu"] == .objectPath(DBusObjectPath(rawValue: "/")!))
        #expect(read["ToolTip"] == DesktopStatusItem.toolTip("Probing"))

        _ = try await bar.callMethod(destination: service, path: Self.item, interface: Self.interface,
                                     method: DBusMember(rawValue: "Activate")!, arguments: [.int32(0), .int32(0)])
        #expect(await eventually { await log.activations == 1 })

        // A new title: the bar hears it and reads it.
        let signals = try await bar.signals(interface: Self.interface, path: Self.item)
        item.update(.init(id: "Probe", title: "Busy", toolTip: "Probing", status: .needsAttention))
        var heard: [String] = []
        for await message in signals {
            heard.append(message.member?.rawValue ?? "")
            if heard.count == 2 { break }
        }
        #expect(heard == ["NewTitle", "NewStatus"])
        read = try await properties(of: service, on: bar)
        #expect(read["Title"] == .string("Busy"))
        #expect(read["Status"] == .string("NeedsAttention"))

        // Removed: its connection closes, and its name goes.
        item.remove()
        #expect(await eventually { (try? await bar.getNameOwner(service)) == nil })
        await bar.close()
        await watcher.close()
    }

    @Test("A menu: served, clicked, and brought up to date before it opens", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func menu() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let log = Log()
        let watcher = try await watcher(on: bus.address, log: log)
        let menu = DBusMenuItem.root([DBusMenuItem(id: 1, title: "New Note"), DBusMenuItem(id: 2, title: "Quit Probe")])
        var updated = menu
        updated.modifyItem(withID: 1) { $0.isEnabled = false }
        let box = ItemBox()
        let item = DesktopStatusItem(.init(id: "Probe", hasMenu: true), address: bus.address) {
            Task { await log.activate() }
        } onMenuClick: { id in
            Task { await log.click(id) }
        } onMenuAboutToShow: { [updated] id in
            await log.show(id)
            box.item?.publish(updated)
        }
        box.item = item
        item.publish(menu)
        #expect(await eventually { await log.registered.count == 1 })
        let registered = try #require(await log.registered.first)
        let service = try #require(DBusBusName(rawValue: String(registered.dropLast("/StatusNotifierItem".count))))

        let bar = try await DBusConnection.connect(to: bus.address)
        let read = try await properties(of: service, on: bar)
        #expect(read["ItemIsMenu"] == .boolean(true))
        #expect(read["Menu"] == .objectPath(DBusObjectPath(rawValue: "/MenuBar")!))

        let reader = DBusMenuReader(connection: bar, service: service, path: DBusObjectPath(rawValue: "/MenuBar")!)
        try await reader.start()
        #expect(await eventually { await reader.menu == menu })
        try await reader.click(2)
        #expect(await eventually { await log.clicks == [2] })
        // The app brings the menu up to date, and the bar is answered once
        // that's served.
        _ = try await reader.aboutToShow(DBusMenuItem.rootID)
        #expect(await log.shown == [DBusMenuItem.rootID])
        try await reader.refresh()
        #expect(await reader.menu == updated)

        await reader.stop()
        item.remove()
        await bar.close()
        await watcher.close()
    }

    @Test("Only what changed is signaled")
    func changeSignals() {
        let old = DesktopStatusItem.Properties(id: "Probe", title: "Probe")
        #expect(DesktopStatusItem.signals(from: old, to: old).isEmpty)
        var new = old
        new.toolTip = "Tip"
        new.hasMenu = true
        #expect(DesktopStatusItem.signals(from: old, to: new).map(\.name) == ["NewToolTip", "NewMenu"])
        new = old
        new.status = .passive
        let signals = DesktopStatusItem.signals(from: old, to: new)
        #expect(signals.map(\.name) == ["NewStatus"])
        #expect(signals.first?.arguments == [.string("Passive")])
    }

    @Test("With no bus, nothing is shown")
    func noBus() async {
        let item = DesktopStatusItem(.init(id: "Probe"), address: "unix:path=/nonexistent/perry-status-bus") {}
        item.update(.init(id: "Probe", title: "Busy"))
        item.publish(.root([]))
        item.remove()
    }
}

/// The item, for its own handlers to publish with.
private final class ItemBox: @unchecked Sendable {
    var item: DesktopStatusItem?
}
