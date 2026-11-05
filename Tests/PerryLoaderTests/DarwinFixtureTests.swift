import Foundation
import Testing

/// Apps built on a Mac by Scripts/build-darwin-fixtures.sh with Xcode and the
/// real iPhoneOS SDK. Linux has no Apple SDK, so these are prebuilt and the
/// suite is skipped when they are missing.
@Suite(.enabled(if: DarwinFixtures.available, "run Scripts/build-darwin-fixtures.sh on a Mac first"))
struct DarwinFixtureTests {

    @Test("Xcode-built Objective-C app is reported by name")
    func menagerieReport() throws {
        let app = DarwinFixtures.app("Menagerie")
        let report = try runPerry(["--report", app.path])
        #expect(report.status == 0, "\(report.stderr)")
        let lines = Set(report.stdout.lines)
        for expected in [
            "bundle\t\(app.resolvingSymlinksInPath().path)\torg.perry.fixture.menagerie",
            "objc-class-defined\tAnimal",
            "objc-class-defined\tDog",
            "objc-class-referenced\tNSObject\tresolved",
            "objc-protocol-defined\tGreeting",
            // Protocols are emitted in every image that uses them, so the
            // app carries its own copy of the NSObject protocol.
            "objc-protocol-defined\tNSObject",
            "objc-class-conforms\tAnimal\tGreeting",
            "objc-selector\tinitWithName:legs:",
            "objc-selector\tdescribe",
            "objc-selector\tcompareByLegs:",
            "fixups\tchained",
        ] {
            #expect(lines.contains(expected), "missing report line: \(expected)")
        }
        // Every import resolves: libobjc to libPerryobjc, and Foundation and
        // CoreFoundation both to libPerryFoundation.
        for (library, provider) in [
            ("/usr/lib/libobjc.A.dylib", "libPerryobjc.so"),
            ("/System/Library/Frameworks/Foundation.framework/Foundation", "libPerryFoundation.so"),
            ("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "libPerryFoundation.so"),
        ] {
            #expect(lines.contains { $0.hasPrefix("dependency\t\(library)\t") && $0.hasSuffix("/\(provider)") },
                    "\(library) should resolve to \(provider)")
        }
        #expect(!lines.contains { $0.hasPrefix("unresolved\t") })
        // Apple's linker merges categories on classes from the same image into
        // the class, so Animal(Sorting) has no __objc_catlist entry; its method
        // still shows up as a selector above.
        #expect(!lines.contains { $0.hasPrefix("objc-category\t") })
    }

    @Test("Xcode-built Objective-C app runs with Foundation")
    func menagerieRuns() throws {
        let result = try runPerry([DarwinFixtures.app("Menagerie").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout == "Dog +load\n")
        // NSLog: "<date> <time> Menagerie[pid:tid] message", sorted by legs.
        let messages = result.stderr.lines.compactMap { line -> String? in
            guard let range = line.range(of: "] ") else { return nil }
            #expect(line.contains(" Menagerie["))
            return String(line[range.upperBound...])
        }
        #expect(messages == ["0: Kiwi says ... on 2 legs", "1: Rex says woof on 4 legs"])
    }

    /// Each app's stdout must match what it prints with Apple's Foundation
    /// on macOS, recorded by Scripts/build-darwin-fixtures.sh.
    @Test("Apps print exactly what they print on Darwin", arguments: DarwinFixtures.withReference)
    func matchesDarwin(_ name: String) throws {
        let result = try runPerry([DarwinFixtures.app(name).path])
        #expect(result.status == 0, "\(result.stderr)")
        let expected = try String(contentsOf: DarwinFixtures.reference(name), encoding: .utf8)
        #expect(result.stdout == expected)
    }
}

enum DarwinFixtures {
    static let directory = TestEnvironment.fixtureBuild.appending(path: "darwin")

    static func app(_ name: String) -> URL {
        directory.appending(path: "\(name).app")
    }

    static func reference(_ name: String) -> URL {
        directory.appending(path: "\(name).expected")
    }

    /// Fixtures with a recorded Darwin output.
    static var withReference: [String] {
        [
            "Abacus", "Almanac", "Archivist", "Atlas", "Babel", "Bedrock", "Chronicle", "Cipher", "Clock", "Cornerstone", "Courier", "Darkroom", "Easel", "Foreman", "Gatekeeper", "Herald", "Itinerary", "Keyring", "Lantern", "Launchpad", "Ledger", "Lexicon", "Logbook", "Menagerie", "Panorama", "Parsley",
            "Quill", "Relay", "Roster", "Satchel", "Scribe", "Scriptorium", "Sentinel", "Shelf", "Sketchbook", "Telegraph", "Typecast", "Vault", "Viewport",
        ].filter {
            built($0) && FileManager.default.fileExists(atPath: reference($0).path)
        }
    }

    static func built(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: app(name).appending(path: name).path)
    }

    static var available: Bool {
        TestEnvironment.perry != nil && built("Menagerie")
    }
}
