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
            "objc-class-referenced\tNSObject\tunresolved",
            "objc-protocol-defined\tGreeting",
            // Protocols are emitted in every image that uses them, so the
            // app carries its own copy of the NSObject protocol.
            "objc-protocol-defined\tNSObject",
            "objc-class-conforms\tAnimal\tGreeting",
            "objc-selector\tinitWithName:legs:",
            "objc-selector\tdescribe",
            "objc-selector\tcompareByLegs:",
            "dependency\t/System/Library/Frameworks/Foundation.framework/Foundation\tmissing",
            "dependency\t/usr/lib/libobjc.A.dylib\tmissing",
            "dependency\t/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation\tmissing",
            "fixups\tchained",
            "unresolved\t/usr/lib/libobjc.A.dylib\t_objc_msgSend",
            "unresolved\t/usr/lib/libobjc.A.dylib\t_objc_msgSendSuper2",
            "unresolved\t/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation\t___CFConstantStringClassReference",
            "unresolved\t/System/Library/Frameworks/Foundation.framework/Foundation\t_NSLog",
        ] {
            #expect(lines.contains(expected), "missing report line: \(expected)")
        }
        // Apple's linker merges categories on classes from the same image into
        // the class, so Animal(Sorting) has no __objc_catlist entry; its method
        // still shows up as a selector above.
        #expect(!lines.contains { $0.hasPrefix("objc-category\t") })
    }
}

enum DarwinFixtures {
    static let directory = TestEnvironment.fixtureBuild.appending(path: "darwin")

    static func app(_ name: String) -> URL {
        directory.appending(path: "\(name).app")
    }

    static var available: Bool {
        TestEnvironment.perry != nil
            && FileManager.default.fileExists(atPath: app("Menagerie").appending(path: "Menagerie").path)
    }
}
