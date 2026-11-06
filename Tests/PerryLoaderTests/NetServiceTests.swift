import Foundation
import Testing

/// NSNetService and NSNetServiceBrowser over Avahi: the Beacon fixture,
/// which publishes, finds and resolves a service, against an avahi-daemon
/// on a bus of the test's own, which the Bonjour compatibility library
/// finds through DBUS_SYSTEM_BUS_ADDRESS. The fixture's output is exactly
/// Darwin's (Tests/Fixtures/Darwin/Beacon prints nothing that depends on
/// the machine).
@Suite(.enabled(if: Avahi.available, "needs the Beacon fixture, dbus-daemon and avahi-daemon"))
struct NetServiceTests {

    @Test("A service is published, found, resolved and stopped through Avahi")
    func beacon() throws {
        let bus = try Avahi.Bus()
        defer { bus.stop() }
        let result = try runPerry([DarwinFixtures.app("Beacon").path],
                                  environment: ["DBUS_SYSTEM_BUS_ADDRESS": bus.address, "AVAHI_COMPAT_NOWARN": "1"])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "txt data 096b65793d76616c7565016e",
            "txt dict count 2, key 'value', n null 1",
            "txt empty data null 1, dict null 1",
            "txt bare count 1, abc null 1",
            "initial 'Beacon Fixture' '_perry7b3f._tcp.' '' port 7777, hostName null 1, addresses 0",
            "willPublish 'Beacon Fixture' '_perry7b3f._tcp.' '' port 7777",
            "didPublish 'Beacon Fixture' '_perry7b3f._tcp.' 'local.' port 7777",
            "willSearch",
            "didFind 'Beacon Fixture' '_perry7b3f._tcp.' 'local.' port -1, hostName null 1",
            "willResolve 'Beacon Fixture'",
            "didResolve 'Beacon Fixture' port 7777, host in local. 1, txt count 2, key 'value', n null 1, ipv4 1, sockaddr len 16 family 2 port 7777",
            "willResolve 'Ghost 7b3f'",
            "didNotResolve code -72007 domain 10",
            "didNotSearch code -72004 domain 10",
            "didStopSearch",
            "cf txt data 096b65793d76616c7565016e",
            "cf txt dict count 2, key 'value', n null 1",
            "cf resolve 1 code 0 domain 0, port 7777, host in local. 1, txt count 2, ipv4 1",
            "cf searching 1 code 0 domain 0",
            "cf found 'Beacon Fixture' '_perry7b3f._tcp.' 'local.' port -1",
            "cf didStopSearch flags 0 code 0 domain 0",
            "serviceDidStop 'Beacon Fixture'",
            "end",
        ])
    }

    @Test("Without Avahi, publishing and searching fail with the unknown error")
    func unsupported() throws {
        let socket = TestEnvironment.fixtureBuild.appending(path: "no-such-avahi").path
        let result = try runPerry([DarwinFixtures.app("Beacon").path],
                                  environment: ["DBUS_SYSTEM_BUS_ADDRESS": "unix:path=\(socket)",
                                                "AVAHI_COMPAT_NOWARN": "1"])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines.contains("didNotPublish code -72000 domain 10"), "\(result.stdout)")
    }
}

enum Avahi {
    static var available: Bool {
        TestEnvironment.perry != nil && DarwinFixtures.built("Beacon")
            && Bluetooth.tool("dbus-daemon") != nil && Bluetooth.tool("avahi-daemon") != nil
    }

    /// A private bus with an avahi-daemon on it, until stopped. The
    /// daemons are detached through a shell rather than held as children:
    /// a child that lives while later ones are awaited wedges Foundation's
    /// process reaping on Linux.
    final class Bus {
        let address: String
        private let directory: URL
        private var pids: [Int32] = []

        /// Runs a daemon detached, returning its pid once `ready` holds.
        /// posix_spawn and waitpid rather than Process: Foundation's child
        /// reaping never fires under this runner, which would leave the
        /// shell a zombie and this wait stuck.
        private func launch(_ command: String, pidFile: String, ready: () -> Bool) throws -> Int32 {
            let pidPath = directory.appending(path: pidFile).path
            let script = "DBUS_SYSTEM_BUS_ADDRESS='\(address)' \(command) & echo $! > \(pidPath)"
            var shell: pid_t = 0
            var arguments = ["/bin/sh", "-c", script].map { strdup($0) }
            arguments.append(nil)
            defer { arguments.forEach { free($0) } }
            guard posix_spawn(&shell, "/bin/sh", nil, nil, arguments, environ) == 0 else {
                throw TestError.missingTool("a shell that starts (\(command))")
            }
            var status: Int32 = 0
            waitpid(shell, &status, 0)
            try Self.waitFor(ready)
            guard let text = try? String(contentsOfFile: pidPath, encoding: .utf8),
                  let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TestError.missingTool("a daemon that starts (\(command))")
            }
            pids.append(pid)
            return pid
        }

        init() throws {
            directory = TestEnvironment.fixtureBuild.appending(path: "avahi-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let socket = directory.appending(path: "bus").path
            address = "unix:path=\(socket)"
            let log = directory.appending(path: "avahi.log").path

            // The daemon itself: IPv4 only, publishing nothing of its own.
            let configuration = directory.appending(path: "avahi.conf")
            try """
            [server]
            use-ipv4=yes
            use-ipv6=no
            enable-dbus=yes
            [publish]
            publish-hinfo=no
            publish-workstation=no
            publish-domain=no
            [rlimits]
            """.write(to: configuration, atomically: true, encoding: .utf8)

            do {
                _ = try launch("dbus-daemon --session --nofork --address=\(address)", pidFile: "dbus.pid") {
                    FileManager.default.fileExists(atPath: socket)
                }
                _ = try launch("avahi-daemon -f \(configuration.path) --no-chroot --no-drop-root --no-rlimits --debug"
                               + " > \(log) 2>&1", pidFile: "avahi.pid") {
                    (try? String(contentsOfFile: log, encoding: .utf8))?.contains("Server startup complete") == true
                }
            } catch {
                stop()
                let output = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
                throw TestError.missingTool("an avahi-daemon that starts (\(output.isEmpty ? "no output" : output))")
            }
        }

        func stop() {
            for pid in pids.reversed() { kill(pid, SIGKILL) }
            pids = []
        }

        private static func waitFor(_ condition: () -> Bool) throws {
            for _ in 0..<400 {
                if condition() { return }
                usleep(50_000)
            }
            throw TestError.missingTool("an avahi-daemon that starts")
        }
    }
}
