import DBus
import Foundation
import Glibc

/// A dbus-daemon of the tests' own on a Unix socket, so they never touch
/// the user's session bus.
final class PrivateBus: Sendable {
    static let executable: URL? = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin").split(separator: ":")
        .map { URL(fileURLWithPath: String($0)).appending(path: "dbus-daemon") }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }

    static var available: Bool { executable != nil }

    let address: String
    private let directory: URL
    private let processID: Int32

    /// Starts a bus and waits until it takes connections.
    static func start() async throws -> PrivateBus {
        let bus = try PrivateBus()
        for _ in 0..<100 {
            if let connection = try? await DBusConnection.connect(to: bus.address) {
                await connection.close()
                return bus
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        bus.stop()
        throw PortalTestError.busNotReady
    }

    private init() throws {
        guard let executable = Self.executable else { throw PortalTestError.noDaemon }
        // Short: a Unix socket's path is limited to about 100 bytes.
        directory = URL(fileURLWithPath: "/tmp/perry-portal-\(UInt32.random(in: 0 ... .max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        address = "unix:path=\(directory.appending(path: "bus").path)"
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--session", "--nofork", "--nopidfile", "--address=\(address)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        processID = process.processIdentifier
    }

    /// SIGKILL, as the daemon inherits the test runner's blocked signals,
    /// which hold off SIGTERM.
    func stop() {
        kill(processID, SIGKILL)
        var status: Int32 = 0
        waitpid(processID, &status, 0)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A settings portal serving the appearance namespace's keys as
/// xdg-desktop-portal does, with ReadOne, and SettingChanged when told to.
final class FakePortal: Sendable {
    static let path = DBusObjectPath(rawValue: "/org/freedesktop/portal/desktop")!
    static let interface = DBusInterface(rawValue: "org.freedesktop.portal.Settings")!

    let connection: DBusConnection

    init(address: String, values: [String: DBusMessageArgument]) async throws {
        connection = try await DBusConnection.connect(to: address)
        let readOne = DBusInterfaceImplementation.Method(
            name: DBusMember(rawValue: "ReadOne")!,
            inputSignature: DBusSignature(rawValue: "ss")!,
            outputSignature: DBusSignature(rawValue: "v")!
        ) { call in
            guard call.arguments.count == 2, case .string("org.freedesktop.appearance") = call.arguments[0],
                  case let .string(key) = call.arguments[1], let value = values[key] else {
                throw DBusError(name: .init(rawValue: "org.freedesktop.portal.Error.NotFound")!, message: "Not found")
            }
            return [.variant(.init(value))]
        }
        await connection.export(DBusExportedObject([DBusInterfaceImplementation(name: Self.interface, methods: [readOne])]), at: Self.path)
        try await connection.requestName(DBusBusName(rawValue: "org.freedesktop.portal.Desktop")!)
    }

    /// Emits SettingChanged, as the portal does when a setting changes.
    func change(_ key: String, to value: DBusMessageArgument) async throws {
        try await connection.emit(
            DBusMessage.Signal(path: Self.path, interface: Self.interface, name: DBusMember(rawValue: "SettingChanged")!),
            arguments: [.string("org.freedesktop.appearance"), .string(key), .variant(.init(value))]
        )
    }
}

enum PortalTestError: Error {
    case noDaemon
    case busNotReady
}

/// Runs `body`, which blocks, on a thread of its own rather than one of
/// the tasks' threads, whose pool the monitor's own tasks need.
func onThread<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        Thread { continuation.resume(returning: body()) }.start()
    }
}
