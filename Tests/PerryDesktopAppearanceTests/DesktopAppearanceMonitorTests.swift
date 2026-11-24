import CacaoDBus
import DBus
import PerryDesktopAppearance
import Testing

/// The monitor AppKit asks from its main thread, against a fake settings
/// portal on a bus of the tests' own.
@Suite("Desktop appearance monitor")
struct DesktopAppearanceMonitorTests {
    private static let accent = DBusMessageArgument.struct(.init([.double(0.2), .double(0.4), .double(0.6)])!)

    @Test("With no bus to connect to, the first read finishes with nothing")
    func noBus() async {
        let monitor = DesktopAppearanceMonitor.start(address: "unix:path=/nonexistent/perry-test-bus") { _ in }
        let clock = ContinuousClock()
        let start = clock.now
        let appearance = await onThread { monitor.current(waitingAtMost: 10) }
        #expect(appearance == nil)
        #expect(monitor.isReady)
        #expect(clock.now - start < .seconds(5))
    }

    @Test("The first read, then each change", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func readsAndHearsChanges() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let portal = try await FakePortal(address: bus.address, values: ["color-scheme": .uint32(1), "accent-color": Self.accent])
        let (changes, continuation) = AsyncStream<PortalAppearance>.makeStream()
        let monitor = DesktopAppearanceMonitor.start(address: bus.address) { continuation.yield($0) }

        let first = await onThread { monitor.current(waitingAtMost: 10) }
        let accent = PortalAppearance.AccentColor(red: 0.2, green: 0.4, blue: 0.6)
        #expect(first == PortalAppearance(colorScheme: .dark, accentColor: accent))
        #expect(DesktopAppearance(portal: first).dark)

        try await portal.change("color-scheme", to: .uint32(2))
        var iterator = changes.makeAsyncIterator()
        let changed = await iterator.next()
        #expect(changed == PortalAppearance(colorScheme: .light, accentColor: accent))
        // From then on the latest, at once.
        #expect(monitor.current(waitingAtMost: 0) == changed)
        #expect(!DesktopAppearance(portal: monitor.current(waitingAtMost: 0)).dark)

        await monitor.stop()
        await portal.connection.close()
    }

    @Test("A first read that comes after the wait is handed on as a change", .enabled(if: PrivateBus.available, "needs dbus-daemon"))
    func lateFirstRead() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let portal = try await FakePortal(address: bus.address, values: ["color-scheme": .uint32(1)])
        let (changes, continuation) = AsyncStream<PortalAppearance>.makeStream()
        let monitor = DesktopAppearanceMonitor.start(address: bus.address) { continuation.yield($0) }

        // Not waiting: the read can't have come yet, unless it was quick.
        let first = monitor.current(waitingAtMost: 0)
        if first == nil {
            var iterator = changes.makeAsyncIterator()
            #expect(await iterator.next() == PortalAppearance(colorScheme: .dark))
        } else {
            #expect(first == PortalAppearance(colorScheme: .dark))
        }
        #expect(monitor.current(waitingAtMost: 10) == PortalAppearance(colorScheme: .dark))

        await monitor.stop()
        await portal.connection.close()
    }
}
