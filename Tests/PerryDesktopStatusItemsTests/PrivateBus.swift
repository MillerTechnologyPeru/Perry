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
        throw PrivateBusError.notReady
    }

    private init() throws {
        guard let executable = Self.executable else { throw PrivateBusError.noDaemon }
        // Short: a Unix socket's path is limited to about 100 bytes.
        directory = URL(fileURLWithPath: "/tmp/perry-status-\(UInt32.random(in: 0 ... .max))")
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

enum PrivateBusError: Error {
    case noDaemon
    case notReady
}

/// Runs `body`, which blocks, on a thread of its own rather than one of
/// the tasks' threads, whose pool the service's own tasks need.
func onThread<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        Thread { continuation.resume(returning: body()) }.start()
    }
}

/// Waits for a condition another connection brings about.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0 ..< 50 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return await condition()
}
