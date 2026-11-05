import Foundation
import Testing

/// armv7 iOS programs, run by perry32. The tests need the 32-bit loader and
/// providers and the armv7 fixtures, which Scripts/build-armv7-loader.sh,
/// build-armv7-system.sh, build-armv7-swiftpm.sh (or build-armv7-objc.sh) and
/// build-armv7-fixtures.sh make, and a machine that runs 32-bit ARM programs:
/// its kernel, or qemu-arm, as in Scripts/docker-test.sh. Without them they
/// are skipped.
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

    @Test("Objective-C classes, categories, +load and blocks run")
    func objectiveCRuns() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("zoo").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout == "Dog +load\nwoof legs=4\nwag\n")
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

    /// What system.c prints on macOS. qemu-arm returns nothing for a 32-bit
    /// program's SO_RCVTIMEO, so under qemu the timeout line is not compared.
    @Test("Threads, libm, signal handlers and socket options pass as on Darwin",
          .enabled(if: FileManager.default.fileExists(atPath: ARMv7.fixture("system").path)))
    func system() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("system").path])
        #expect(result.status == 0, "\(result.stderr)")
        var expected = [
            "threads counter 4000 once 1 results 64 timedwait 60",
            "math 0.479426 0.877583 1.414214 -3.000000 2.718282 2.302585",
            "math2 1.414214 2.356194 1.500000 5.000000 12.000000",
            "math3 0.750 6 -3.000 -0.750 0.232088 -3",
            "float 0.24740 3.37500 3.16228 6.50000",
            "convert 6.2500 -1000.0000 0.1250",
            "sorted -1.25 0.00 2.75 3.50 10.00",
            "signal handled 1 context 1",
        ]
        var lines = result.stdout.lines
        if ProcessInfo.processInfo.environment["QEMU_LD_PREFIX"] == nil {
            expected.append("timeout 2 500000 size 1")
        } else {
            lines.removeAll { $0.hasPrefix("timeout ") }
        }
        #expect(lines == expected)
    }

    /// What foundation_abi.m prints with Apple's Foundation on macOS.
    @Test("Foundation's variadic methods, KVC, KVO and floating point pass as on Darwin",
          .enabled(if: ARMv7.foundationAvailable))
    func foundation() throws {
        let result = try run(ARMv7.perry32, [ARMv7.fixture("foundation_abi").path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stderr.contains("NSLog 1 2 3.0 four"))
        #expect(result.stdout.lines == [
            "int -7 long -123456 llong -9876543210 unsigned 4000000000",
            "double 3.142 float 2.5 mixed 1 0.500000 1099511627776 object cstring",
            " 1.50|42  |ff|123456789abc|77|Z|    3",
            "mutable 2 3.0 4",
            "prefix 5000000000 6",
            "init 9 0.25",
            "a,b,c",
            "1 2 2",
            "set 2",
            "5,10,5000000000",
            "5,5000000000",
            "cf 1 2 3.00 four",
            "set 3 123456789012 4 7 1.50 -2.25",
            "count 3",
            "big 123456789012",
            "range range 4 7",
            "pair pair 1.50 -2.25",
            "numbers -2.500 -2.500 0.750 0.750 1.250 7",
            "strings 3.250 -0.500",
            "date 1000.250 999.750",
            "cf date 12345.500 now 1",
            "floats 2.500 0.125 1",
            "weight 2.500",
            "ratio 0.125",
            "flag 1",
            "changed count",
            "  old 3",
            "  new 4",
            "changed big",
            "  old 123456789012",
            "  new 34359738368",
            "changed range",
            "  old range 4 7",
            "  new range 1 2",
            "changed pair",
            "  old pair 1.50 -2.25",
            "  new pair 3.50 4.75",
            "changed weight",
            "  old 2.500",
            "  new -1.500",
            "changed ratio",
            "  old 0.125",
            "  new 3.250",
            "after 5 34359738368 2 4.75",
        ])
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
            && fm.fileExists(atPath: fixture("zoo").path)
            && runs
    }

    /// Whether perry32 runs here: the kernel runs 32-bit ARM programs, or
    /// qemu-arm does through binfmt_misc (Docker Desktop on Apple silicon,
    /// which has no AArch32), finding Linux's armhf libraries under
    /// QEMU_LD_PREFIX.
    static let runs: Bool = (try? run(perry32, [fixture("hello").path]))?.status == 7

    /// Foundation's provider and its fixture, which Scripts/build-armv7-swiftpm.sh
    /// and build-armv7-fixtures.sh make.
    static var foundationAvailable: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: perry32.deletingLastPathComponent().appending(path: "libPerryFoundation.so").path)
            && fm.fileExists(atPath: fixture("foundation_abi").path)
    }
}
