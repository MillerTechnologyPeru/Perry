import Foundation
import Testing

/// armv7 iOS programs, run by perry32. The tests need the 32-bit loader and
/// providers and the armv7 fixtures, which Scripts/build-armv7-loader.sh,
/// build-armv7-system.sh, build-armv7-objc.sh and build-armv7-fixtures.sh make
/// on a machine whose kernel runs 32-bit ARM programs; without them they are
/// skipped.
@Suite("armv7", .enabled(if: ARMv7.available))
struct ARMv7Tests {
    @Test("A C program runs through perry32")
    func hello() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("hello").path, "a", "b"])
        #expect(result.status == 7)
        #expect(result.stdout == "hello from iOS argc=3\narg[1]=a\narg[2]=b\n")
    }

    @Test("perry hands an armv7 program to perry32")
    func handoff() throws {
        let result = try runPerry([ARMv7.fixture("hello").path], environment: ["PERRY32": ARMv7.perry32.path])
        #expect(result.status == 7)
        #expect(result.stdout == "hello from iOS argc=1\n")
    }

    @Test("The Objective-C runtime initializes, deallocates and zeroes weak references")
    func objectiveCRuntime() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("runtime").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "+initialize Base",
            "+initialize Derived",
            "derived base",
            "responds 1 0",
            "kind 1 0",
            "weak set",
            "dealloc base",
            "weak nil",
            "dealloc base",
            "dealloc derived",
            "dealloc base",
            "dealloc derived",
            "in pool",
            "dealloc base",
            "after pool",
            "dealloc derived",
        ])
    }

    @Test("Unrecognized selectors abort with Apple's message")
    func unrecognizedSelector() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("runtime").path, "crash"])
        #expect(result.stderr.contains("-[Derived missingMethod]: unrecognized selector sent to instance 0x"))
    }
}

enum ARMv7 {
    static let perry32 = TestEnvironment.packageRoot.appending(path: ".build/armv7/bin/perry32")

    static func fixture(_ name: String) -> URL {
        TestEnvironment.fixtureBuild.appending(path: "armv7/\(name)")
    }

    static var available: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: perry32.path)
            && fm.fileExists(atPath: fixture("hello").path)
            && fm.fileExists(atPath: fixture("runtime").path)
    }
}
