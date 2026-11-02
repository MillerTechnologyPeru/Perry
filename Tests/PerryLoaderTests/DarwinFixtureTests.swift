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

    @Test("Foundation formats, collects and describes like Darwin",
          .enabled(if: DarwinFixtures.built("Ledger")))
    func ledgerRuns() throws {
        let result = try runPerry([DarwinFixtures.app("Ledger").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "-7|   42|ab |3.14|ff|Z|%|obj",
            "12 2.5 1",
            "Hello, world (12) upper=HELLO, WORLD prefix=1",
            "equal=1 compare=-1",
            "unicode=café ☕ 6",
            "count=5 total=199 first=40 last=10",
            "10,20,30,40,99",
            "contains=1 index=1",
            "(",
            "    x,",
            "    y",
            ")",
        ])
    }
}

enum DarwinFixtures {
    static let directory = TestEnvironment.fixtureBuild.appending(path: "darwin")

    static func app(_ name: String) -> URL {
        directory.appending(path: "\(name).app")
    }

    static func built(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: app(name).appending(path: name).path)
    }

    static var available: Bool {
        TestEnvironment.perry != nil && built("Menagerie")
    }
}
