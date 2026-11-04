import Foundation
import Testing

/// CoreBluetooth over BlueZ: the Pulse fixture, a central for a heart rate
/// monitor, against a fake BlueZ (Tests/Fixtures/bluez/fake-bluez.py) on a
/// bus of the test's own, which libPerryCoreBluetooth finds through
/// DBUS_SYSTEM_BUS_ADDRESS.
@Suite(.enabled(if: Bluetooth.available, "needs the Pulse fixture, dbus-daemon and python3-dbus"))
struct BluetoothTests {

    @Test("A central scans, connects, reads, writes and is notified through BlueZ")
    func pulse() throws {
        let bus = try Bluetooth.Bus()
        defer { bus.stop() }
        let result = try runPerry([DarwinFixtures.app("Pulse").path], environment: ["DBUS_SYSTEM_BUS_ADDRESS": bus.address])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "UUIDs 2A37 2A37 equal YES",
            "initial state 0",
            "state 5",
            "scanning YES",
            "discovered Pulse B1E7D0D0-0000-4000-8000-C0FFEE001122 RSSI -52",
            "  name Pulse",
            "  manufacturer 4c00010203",
            "  service 180D",
            "  connectable 1",
            "scanning NO",
            "retrieved the same peripheral YES",
            "peripheral state 1",
            "connected, peripheral state 2",
            "service 180D primary YES",
            "characteristic 2A37 properties 0x10",
            "characteristic 2A38 properties 0x02",
            "characteristic 2A39 properties 0x08",
            "body sensor location 01",
            "wrote 2A39, error none",
            "descriptor 2902",
            "notifying YES",
            "measurement 003d",
            "measurement 003e",
            "measurement 003f",
            "notifying NO",
            "disconnected, error none, peripheral state 0",
        ])
    }

    @Test("Without BlueZ a central is unsupported")
    func unsupported() throws {
        let socket = TestEnvironment.fixtureBuild.appending(path: "no-such-bus").path
        let result = try runPerry([DarwinFixtures.app("Pulse").path], environment: ["DBUS_SYSTEM_BUS_ADDRESS": "unix:path=\(socket)"])
        #expect(result.status == 1, "\(result.stderr)")
        #expect(result.stdout.lines.suffix(2) == ["initial state 0", "state 2"])
    }
}

enum Bluetooth {
    static let fake = TestEnvironment.packageRoot.appending(path: "Tests/Fixtures/bluez/fake-bluez.py")

    static func tool(_ name: String) -> URL? {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var available: Bool {
        guard TestEnvironment.perry != nil, DarwinFixtures.built("Pulse"),
              tool("dbus-daemon") != nil, let python = tool("python3"),
              let check = try? run(python, ["-c", "import dbus, gi.repository.GLib"]) else { return false }
        return check.status == 0
    }

    /// A private bus with the fake BlueZ on it, until stopped.
    final class Bus {
        let address: String
        private let daemon = Process()
        private let bluez = Process()

        init() throws {
            let directory = TestEnvironment.fixtureBuild.appending(path: "bluetooth-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let socket = directory.appending(path: "bus").path
            address = "unix:path=\(socket)"

            daemon.executableURL = Bluetooth.tool("dbus-daemon")
            daemon.arguments = ["--session", "--nofork", "--address=\(address)"]
            try daemon.run()
            try Self.waitFor { FileManager.default.fileExists(atPath: socket) }

            let log = directory.appending(path: "bluez.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            bluez.executableURL = Bluetooth.tool("python3")
            bluez.arguments = [Bluetooth.fake.path]
            bluez.environment = ProcessInfo.processInfo.environment.merging(["DBUS_SYSTEM_BUS_ADDRESS": address]) { $1 }
            bluez.standardOutput = try FileHandle(forWritingTo: log)
            bluez.standardError = bluez.standardOutput
            try bluez.run()
            try Self.waitFor { (try? String(contentsOf: log, encoding: .utf8))?.contains("ready") == true }
        }

        /// SIGKILL, as the children inherit the test thread's blocked
        /// signals, which hold off SIGTERM.
        func stop() {
            for process in [bluez, daemon] where process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }

        private static func waitFor(_ condition: () -> Bool) throws {
            for _ in 0..<100 {
                if condition() { return }
                usleep(50_000)
            }
            throw TestError.missingTool("a fake BlueZ that starts")
        }
    }
}
