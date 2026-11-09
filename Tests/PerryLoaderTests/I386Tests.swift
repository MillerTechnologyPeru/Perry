import Foundation
import Testing

/// i386 Mac programs, run by perry32 on x86_64. The tests need the 32-bit
/// loader and providers, which Scripts/build-i386-loader.sh,
/// build-i386-system.sh and build-i386-swiftpm.sh make, the SDK's Swift
/// libraries, and the fixtures of build-i386-fixtures.sh. Without them they
/// are skipped.
@Suite("i386", .enabled(if: I386.available))
struct I386Tests {
    @Test("A C program runs through perry32")
    func hello() throws {
        let result = try run(I386.perry32, [I386.fixture("hello").path, "a", "b"], environment: I386.environment)
        #expect(result.status == 7)
        #expect(result.stdout == "hello from iOS argc=3\narg[1]=a\narg[2]=b\n")
    }

    @Test("Threads, libm, signal handlers and socket options pass as on Darwin")
    func system() throws {
        let result = try run(I386.perry32, [I386.fixture("system").path], environment: I386.environment)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "threads counter 4000 once 1 results 64 timedwait 60",
            "math 0.479426 0.877583 1.414214 -3.000000 2.718282 2.302585",
            "math2 1.414214 2.356194 1.500000 5.000000 12.000000",
            "math3 0.750 6 -3.000 -0.750 0.232088 -3",
            "float 0.24740 3.37500 3.16228 6.50000",
            "convert 6.2500 -1000.0000 0.1250",
            "sorted -1.25 0.00 2.75 3.50 10.00",
            "signal handled 1 context 1",
            "timeout 2 500000 size 1",
        ])
    }

    @Test("The old Objective-C ABI: classes by name, fixed ivars, calling conventions and setjmp exceptions",
          .enabled(if: FileManager.default.fileExists(atPath: I386.fixture("legacy_runtime").path)))
    func legacyRuntime() throws {
        let result = try run(I386.perry32, [I386.fixture("legacy_runtime").path], environment: I386.environment)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "load Base",
            "load Added",
            "ivars 8 m 2.5 16",
            "numbers 108 11",
            "fp 4.00 2.00",
            "wide 800000000",
            "structs 8 2 8 2.5 4",
            "sum 10",
            "added 9",
            "kind 1 0 1",
            "responds 1 0",
            "protocol 1 0",
            "nil 0 0.0 0",
            "caught 110 12 1010",
        ])
    }

    /// What foundation_abi.m prints with Apple's Foundation on macOS.
    @Test("Foundation's variadic methods, KVC, KVO and floating point pass as on Darwin",
          .enabled(if: FileManager.default.fileExists(atPath: I386.fixture("foundation_abi").path)))
    func foundation() throws {
        let result = try run(I386.perry32, [I386.fixture("foundation_abi").path], environment: I386.environment)
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

    @Test("AppKit from the old ABI: a subclass's fixed ivars over NSView, and float geometry",
          .enabled(if: FileManager.default.fileExists(atPath: I386.fixture("legacy_appkit").path)
                   && FileManager.default.fileExists(atPath: I386.perry32.deletingLastPathComponent()
                       .appending(path: "libPerryAppKit.so").path)))
    func legacyAppKit() throws {
        var environment = I386.environment
        environment["SDL_VIDEODRIVER"] = "dummy"
        let result = try run(I386.perry32, [I386.fixture("legacy_appkit").path], environment: environment)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "ivars 77 1.5 200.5",
            "frame 10.0 20.0 1300.0 200.5",
            "bounds 0.0 0.0 300.0 200.5",
            "moved 1.0 2.0 1030.0 40.0",
            "sized 1.0 2.0 1050.0 60.2",
            "tree 1 flipped 1 0",
            "converted 6.0 13.0",
            "inset 12.5 25.0 295.0 190.5",
            "in 1",
            "color 0.250 0.125",
        ])
    }
}

enum I386 {
    static let root = TestEnvironment.packageRoot
    static let perry32 = root.appending(path: ".build/i386/bin/perry32")
    static func fixture(_ name: String) -> URL { TestEnvironment.fixtureBuild.appending(path: "i386/\(name)") }

    /// Where the SDK's Swift runtime is, for the providers.
    static var environment: [String: String] {
        let sysroot = root.appending(path: ".toolchains/i386-sdk/sysroot/usr/lib").path
        return ["LD_LIBRARY_PATH": "\(sysroot)/swift/linux:\(sysroot)/i386-linux-gnu"]
    }

    static var available: Bool {
        #if arch(x86_64)
        FileManager.default.isExecutableFile(atPath: perry32.path)
            && FileManager.default.fileExists(atPath: fixture("hello").path)
        #else
        false
        #endif
    }
}
