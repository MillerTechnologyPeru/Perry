import Foundation
import Testing

/// With `PERRY_REQUIRE_FIXTURES=1`, what the other suites skip without is
/// required: a run that would have skipped them and passed fails here.
@Suite(.enabled(if: TestEnvironment.requiresFixtures, "set PERRY_REQUIRE_FIXTURES=1 to require the tools and fixtures"))
struct RequiredFixtureTests {

    /// On arm64, LoaderTests' tools too: the programs they build are arm64
    /// iOS ones, which x86_64 doesn't run. x86_64 has the Darwin fixtures
    /// built for it instead.
    @Test("perry and the tools the fixtures need are there")
    func tools() {
        #expect(TestEnvironment.perry != nil, "perry isn't beside the test runner")
        #if arch(arm64)
        #expect(TestEnvironment.llvmBin != nil, "no clang and ld64.lld in $PERRY_LLVM_BIN, .toolchains or $PATH")
        #expect(TestEnvironment.canRunFixtures)
        #elseif !arch(x86_64)
        Issue.record("the fixtures are arm64 and x86_64 programs, which need an arm64 or x86_64 machine")
        #endif
    }

    /// Every directory in Tests/Fixtures/Darwin that is built for this
    /// architecture.
    static let darwinFixtures: [String] = {
        let directory = TestEnvironment.fixtures.appending(path: "Darwin")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && DarwinFixtures.leftOut[$0] == nil }.sorted()
    }()

    @Test("Each Darwin fixture was built", arguments: darwinFixtures)
    func darwinFixture(name: String) {
        #expect(DarwinFixtures.built(name), """
            run Scripts/build-darwin-fixtures.sh on a Mac (PERRY_FIXTURES_ARCH=x86_64 for x86_64), \
            or download its output, into \(DarwinFixtures.directory.path)
            """)
    }

    @Test("The Darwin fixture suites run")
    func darwinSuites() {
        #expect(!Self.darwinFixtures.isEmpty)
        #expect(DarwinFixtures.available)
        #expect(!DarwinFixtures.withReference.isEmpty, "no fixture has its output from Darwin recorded")
    }

    @Test("The Bluetooth and Bonjour suites run")
    func daemons() {
        #expect(Bluetooth.available, "needs the Pulse fixture, dbus-daemon and python3-dbus")
        #expect(Avahi.available, "needs the Beacon fixture, dbus-daemon and avahi-daemon")
    }
}
