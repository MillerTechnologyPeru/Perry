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

    /// Each of Prism's scenes must composite, through Cacao's engine, to a
    /// frame of its 480x360 screen, which the window may scale up to fit
    /// the display. The frames are the GPU's (PERRY_UIKIT_FRAME_DUMP), so
    /// this needs a display.
    @Test("Layer scenes composite",
          .enabled(if: DarwinFixtures.built("Prism") && DarwinFixtures.hasDisplay, "needs Prism built and a display"),
          arguments: DarwinFixtures.layerScenes)
    func layerScenesComposite(_ scene: String) throws {
        let scratch = TestEnvironment.fixtureBuild.appending(path: "prism-frames")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let frame = scratch.appending(path: "\(scene).png")
        try? FileManager.default.removeItem(at: frame)
        let environment = [
            "PRISM_SCENE": scene, "PRISM_SECONDS": "3",
            "PERRY_UIKIT_FRAME_DUMP": frame.path, "PERRY_UIKIT_FRAME_DUMP_INTERVAL": "0.5",
            "PERRY_UIKIT_SCREEN": "480x360@1",
        ]
        let result = try runPerry([DarwinFixtures.app("Prism").path], environment: environment)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == ["scene \(scene)"])
        // A PNG's header chunk: its width and height, big-endian, at 16.
        let png = try Data(contentsOf: frame)
        let size = png.count >= 24 ? (png[16..<20].reduce(0) { $0 << 8 | Int($1) }, png[20..<24].reduce(0) { $0 << 8 | Int($1) }) : (0, 0)
        #expect(size.0 >= 480 && size.0 * 3 == size.1 * 4, "\(scene): \(size), \(frame.path)")
    }

    /// Prism's GL frames must composite the same whether they are shared
    /// with the compositor as GPU buffers or read back as pixels
    /// (PERRY_UIKIT_ZERO_COPY=0): the same way up and the same colors.
    /// Where the host can't share them, both are read back.
    @Test("GL frames composite alike shared and read back",
          .enabled(if: DarwinFixtures.built("Prism") && DarwinFixtures.hasDisplay, "needs Prism built and a display"))
    func sharedFramesMatchReadBack() throws {
        let scratch = TestEnvironment.fixtureBuild.appending(path: "prism-frames")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let frames = try ["shared", "read"].map { way -> Data in
            let frame = scratch.appending(path: "frames-\(way).png")
            try? FileManager.default.removeItem(at: frame)
            let environment = [
                "PRISM_SCENE": "frames", "PRISM_SECONDS": "3",
                "PERRY_UIKIT_FRAME_DUMP": frame.path, "PERRY_UIKIT_FRAME_DUMP_INTERVAL": "0.5",
                "PERRY_UIKIT_SCREEN": "480x360@1", "PERRY_UIKIT_ZERO_COPY": way == "shared" ? "1" : "0",
            ]
            let result = try runPerry([DarwinFixtures.app("Prism").path], environment: environment)
            #expect(result.status == 0, "\(way): \(result.stderr)")
            #expect(result.stdout.lines == ["scene frames"], "\(way)")
            return try Data(contentsOf: frame)
        }
        #expect(frames[0] == frames[1], "frames differ, in \(scratch.path)")
    }

    /// Each app's stdout must match what it prints with Apple's Foundation
    /// on macOS, recorded by Scripts/build-darwin-fixtures.sh.
    @Test("Apps print exactly what they print on Darwin", arguments: DarwinFixtures.withReference)
    func matchesDarwin(_ name: String) throws {
        let result = try runPerry([DarwinFixtures.app(name).path], environment: DarwinFixtures.environment(name))
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
            "Abacus", "Almanac", "Anvil", "Archivist", "Atlas", "Babel", "Bedrock", "Chronicle", "Cipher", "Clock", "Cobweb", "Cornerstone", "Courier", "Darkroom", "Easel", "Foreman", "Forge", "Foundry", "Gatekeeper", "Gossamer", "Herald", "Itinerary", "Keyring", "Lantern", "Launchpad", "Ledger", "Lexicon", "Logbook", "Menagerie", "Panorama", "Parsley",
            "Quill", "Relay", "Roster", "Satchel", "Scribe", "Scriptorium", "Sentinel", "Shelf", "Sketchbook", "Telegraph", "Typecast", "Vault", "Viewport",
        ].filter {
            built($0) && FileManager.default.fileExists(atPath: reference($0).path)
        } + swift.filter {
            built($0) && FileManager.default.fileExists(atPath: reference($0).path) && swiftRuntime != nil
        }
    }

    /// Prism's scenes. Its texts scene is left out until there is a
    /// CATextLayer to draw.
    static let layerScenes = ["basics", "masks", "shadows", "gradients", "contents", "transforms", "ordering", "corners",
                              "shapes", "replicated", "frames"]

    /// Whether there is a display to open a window on.
    static var hasDisplay: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["DISPLAY"] != nil || environment["WAYLAND_DISPLAY"] != nil
    }

    /// Fixtures written in Swift, which run on Apple's Swift runtime.
    static let swift = ["Tempo"]

    /// Apple's Swift runtime as Scripts/swift-runtime.sh assembles it, with
    /// Perry's Swift frameworks; nil when it isn't there.
    static var swiftRuntime: URL? {
        let directory = TestEnvironment.packageRoot.appending(path: ".build/perry-swift-runtime")
        return FileManager.default.fileExists(atPath: directory.appending(path: "libswiftCore.dylib").path) ? directory : nil
    }

    static func environment(_ name: String) -> [String: String] {
        guard swift.contains(name), let swiftRuntime else { return [:] }
        return ["PERRY_SWIFT_RUNTIME": swiftRuntime.path]
    }

    static func built(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: app(name).appending(path: name).path)
    }

    static var available: Bool {
        TestEnvironment.perry != nil && built("Menagerie")
    }
}
