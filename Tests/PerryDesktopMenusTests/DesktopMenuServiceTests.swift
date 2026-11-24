import CacaoDBusMenu
import DBus
import Foundation
import PerryDesktopMenus
import Testing

/// The service on a private bus, read and clicked from another connection,
/// as the desktop's menu bar does.
@Suite("Serving the menu", .serialized)
struct DesktopMenuServiceTests {
    /// What the app's side heard.
    private actor Log {
        var clicks: [Int32] = []
        var validated: [Int32] = []
        var presence: [Bool] = []
        func click(_ id: Int32) { clicks.append(id) }
        func validate(_ id: Int32) { validated.append(id) }
        func present(_ value: Bool) { presence.append(value) }
    }

    private static let menu = DBusMenuItem.root([
        DBusMenuItem(id: 1, title: "Probe", children: [
            DBusMenuItem(id: 2, title: "Quit Probe", shortcut: DBusMenuShortcut("q", modifiers: .super)),
        ]),
        DBusMenuItem(id: 3, title: "Edit", children: [
            DBusMenuItem(id: 4, title: "Copy", isEnabled: true),
        ]),
    ])

    /// The menu after the app validated Edit: Copy can't be chosen.
    private static let validated: DBusMenuItem = {
        var menu = DesktopMenuServiceTests.menu
        menu.modifyItem(withID: 4) { $0.isEnabled = false }
        return menu
    }()

    @Test("Served, found by its app_id, clicked, and validated before a menu opens", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func serves() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let log = Log()
        let box = ServiceBox()
        let service = DesktopMenuService.start(appID: "org.example.Probe-App", address: bus.address) { id in
            await log.validate(id)
            box.service?.publish(Self.validated)
        } onClick: { id in
            Task { await log.click(id) }
        } onPresence: { present in
            Task { await log.present(present) }
        }
        box.service = service
        // Published before it's on the bus: served once it is.
        service.publish(Self.menu)
        #expect(await eventually { service.address != nil })
        #expect(service.address?.path == "/MenuBar")

        let bar = try await DBusConnection.connect(to: bus.address)
        // The name is claimed once the menu is served.
        var found: DBusMenuReader?
        for _ in 0 ..< 50 where found == nil {
            found = await AppMenuDiscovery.reader(forAppID: "org.example.Probe-App", on: bar)
            if found == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        let reader = try #require(found)
        #expect(reader.service.rawValue == service.address?.service)
        try await reader.start()
        #expect(await eventually { await reader.menu == Self.menu })

        try await reader.click(2, timestamp: 7)
        #expect(await eventually { await log.clicks == [2] })

        // The app validates Edit, and the bar is answered once that's served.
        #expect(try await reader.aboutToShow(3))
        #expect(await log.validated == [3])
        #expect(await reader.menu == Self.validated)

        await reader.stop()
        await bar.close()
        await onThread { service.stop() }
        #expect(service.address == nil)
    }

    @Test("A menu bar is there while it owns the Registrar", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func presence() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let log = Log()
        let service = DesktopMenuService.start(appID: nil, address: bus.address) { _ in } onClick: { _ in } onPresence: { present in
            Task { await log.present(present) }
        }
        #expect(await onThread { service.menuBarIsPresent(waitingAtMost: 5) } == false)
        #expect(await eventually { await log.presence == [false] })

        let bar = try await DBusConnection.connect(to: bus.address)
        _ = try await bar.requestName(AppMenuDiscovery.registrarName, flags: [])
        #expect(await eventually { await log.presence == [false, true] })
        #expect(service.menuBarIsPresent(waitingAtMost: 0))

        // The menu bar quits.
        await bar.close()
        #expect(await eventually { await log.presence == [false, true, false] })
        #expect(!service.menuBarIsPresent(waitingAtMost: 0))
        await onThread { service.stop() }
    }

    @Test("With no bus, nothing is served and no menu bar is there")
    func noBus() async {
        let service = DesktopMenuService.start(appID: "org.example.Probe", address: "unix:path=/nonexistent/perry-menus-bus") { _ in } onClick: { _ in }
        #expect(await onThread { service.menuBarIsPresent(waitingAtMost: 5) } == false)
        #expect(service.address == nil)
        service.publish(Self.menu)
        await onThread { service.stop() }
    }

    @Test("Menus are served in the order they're published", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func order() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let box = ServiceBox()
        let menus = (1 ... 20).map { count in
            DBusMenuItem.root([DBusMenuItem(id: 1, title: "Probe", children: (1 ... count).map { DBusMenuItem(id: Int32(1 + $0), title: "Item \($0)") })])
        }
        let service = DesktopMenuService.start(appID: nil, address: bus.address) { _ in
            // The app publishes the last menu as the bar opens a menu.
            box.service?.publish(menus[19])
        } onClick: { _ in }
        box.service = service
        #expect(await eventually { service.address != nil })
        for menu in menus.prefix(19) { service.publish(menu) }

        let bar = try await DBusConnection.connect(to: bus.address)
        let reader = DBusMenuReader(connection: bar, service: try #require(DBusBusName(rawValue: service.address?.service ?? "")))
        try await reader.start()
        #expect(await eventually { await reader.menu == menus[18] })
        // Answered once the last is served.
        _ = try await reader.aboutToShow(1)
        try await reader.refresh()
        #expect(await reader.menu == menus[19])
        await reader.stop()
        await bar.close()
        await onThread { service.stop() }
    }

    @Test("A result from another thread, or nil when it doesn't come in time")
    func results() async {
        let quick = await DesktopMenuService.result(within: 5, scheduling: { work in Thread { work() }.start() }) { 42 }
        #expect(quick == 42)
        let late = await DesktopMenuService.result(within: 0.2, scheduling: { _ in }) { 42 }
        #expect(late == nil)
    }
}

/// The service, for its own handlers to publish with.
private final class ServiceBox: @unchecked Sendable {
    var service: DesktopMenuService?
}
