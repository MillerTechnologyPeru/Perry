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

    @Test("printf's 64-bit and floating-point arguments, and 64-bit file offsets, pass as on arm64")
    func sixtyFourBitArguments() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("abi").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "-5 4000000000 ff A str|",
            "1234567890123 18446744073709551615 -9876543210",
            "3.141590 0.667 1e+10 1.234568e+04",
            "  2.2|42      |0003.142|+7",
            "1 0.500000 5000000000 mix 1.500000",
            "    42|3.14|ab   |",
            "-7 7 9 -3 -4",
            "0x1234 %",
            "77-1.50-9",
            "end 12",
            "far 5000000000",
            "wrote 1",
            "read 1 X",
            "read 5 world",
            "truncate 0",
            "end 5",
            "mmap k z 0",
        ])
    }

    @Test("Files: open's flags, struct stat, struct dirent, symlinks and errno")
    func files() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("files").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "mkdir 0",
            "mkdir again -1 errno 17",
            "write 12",
            "fstat 0 size 12",
            "exclusive -1 errno 17",
            "missing -1 errno 2",
            "stat 0",
            "mode 640 type 100000 nlink 1 size 12 uid-set 1",
            "mtime-set 1 blocks-set 1",
            "rename 0",
            "stat old -1 errno 2",
            "symlink 0",
            "readlink 1 b",
            "lstat link 120000 size 1",
            "stat link 100000 size 12",
            "read 12 hello, files",
            "entry b type 8 namlen 1",
            "entry link type 10",
            "entries 4 found 1 1",
            "rmdir 0",
        ])
    }

    @Test("fseeko and ftello take 64-bit offsets")
    func seeko() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("seeko").path])
        #expect(result.stdout.lines == ["seek 0 2", "seek 0 11", "seek 0 14"])
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
            && fm.fileExists(atPath: fixture("abi").path)
            && fm.fileExists(atPath: fixture("seeko").path)
            && fm.fileExists(atPath: fixture("files").path)
    }
}
