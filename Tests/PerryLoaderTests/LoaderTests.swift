import Foundation
import Testing

/// End-to-end tests: build arm64 iOS Mach-O fixtures and run them with perry.
@Suite(.enabled(if: TestEnvironment.canRunFixtures, "needs perry and an LLVM toolchain with ld64.lld"))
struct LoaderTests {

    @Test("C binary runs with chained fixups", arguments: [
        ("chained", ["-fixup_chains"]),
        ("legacy", ["-no_fixup_chains"]),
    ])
    func hello(variant: String, flags: [String]) throws {
        let exe = try FixtureBuilder.executable("hello.c", variant: "-\(variant)", linkFlags: flags)
        let result = try runPerry([exe.path, "one", "two words"])
        #expect(result.status == 7)
        #expect(result.stdout.lines == ["hello from iOS argc=3", "arg[1]=one", "arg[2]=two words"])

        let report = try runPerry(["--report", exe.path])
        #expect(report.status == 0)
        #expect(report.stdout.contains("platform\tiOS\t15.0\tsdk 17.0"))
        #expect(report.stdout.contains("fixups\t\(variant == "chained" ? "chained" : "dyld-info")"))
        #expect(report.stdout.contains("dependency\t/usr/lib/libSystem.B.dylib\t"))
        #expect(report.stdout.contains("libPerrySystem.so"))
        #expect(report.stdout.contains("\t0 unresolved\t"))
    }

    @Test("Variadic calls use Darwin's stack-based convention")
    func variadic() throws {
        let exe = try FixtureBuilder.executable("variadic.c")
        let result = try runPerry([exe.path])
        #expect(result.status == 0)
        #expect(result.stdout.lines == [
            "ints 1 2 3 4 5 6 7 8 9 10",
            "mixed str 3.14 1234567890123 x -2.5 42",
            "snprintf-99-0.125 (17)",
            "vsnprintf|-7|1e+10",
        ])
        #expect(result.stderr == "to stderr 5\n")
    }

    @Test("errno is translated to Darwin values")
    func errno() throws {
        let exe = try FixtureBuilder.executable("errno.c")
        let result = try runPerry([exe.path])
        #expect(result.status == 0)
        #expect(result.stdout.lines == [
            "strtol overflow errno=34 (ERANGE=34) value-positive=1",
            "after success errno=0",
            "fopen null=1 errno=2 (ENOENT=2) message=No such file or directory",
            "darwin EAGAIN message=Resource temporarily unavailable",
        ])
    }

    @Test("Initializers run in order and pointer tables are rebased", arguments: [
        ("mod-init-func", [String]()),
        ("init-offsets", ["-init_offsets"]),
    ])
    func initializers(variant: String, flags: [String]) throws {
        let exe = try FixtureBuilder.executable("initializers.c", variant: "-\(variant)", linkFlags: flags)
        let result = try runPerry([exe.path])
        #expect(result.status == 0)
        #expect(result.stdout.lines == [
            "constructor first",
            "constructor second",
            "counter=22 names=alpha,beta,gamma",
        ])
    }

    @Test("Missing weak imports are NULL; missing calls are reported")
    func missingImports() throws {
        let exe = try FixtureBuilder.executable("imports.c")

        let ok = try runPerry([exe.path])
        #expect(ok.status == 0)
        #expect(ok.stdout == "weak import is null: 1\n")

        let call = try runPerry([exe.path, "call"])
        #expect(call.signaled)
        #expect(call.stderr.contains("perry: unimplemented: _perry_fixture_unimplemented (/usr/lib/libSystem.B.dylib)"))

        let report = try runPerry(["--report", exe.path])
        #expect(report.stdout.contains("weak-missing\t/usr/lib/libSystem.B.dylib\t_perry_fixture_absent"))
        #expect(report.stdout.contains("unresolved\t/usr/lib/libSystem.B.dylib\t_perry_fixture_unimplemented"))

        let strict = try runPerry(["--strict", exe.path])
        #expect(strict.status == 127)
        #expect(strict.stderr.contains("unresolved symbol _perry_fixture_unimplemented"))
    }

    @Test("App bundles load their executable and embedded dylibs", arguments: [false, true])
    func appBundle(binaryPlist: Bool) throws {
        let app = try FixtureBuilder.greeterApp(variant: binaryPlist ? "binary" : "xml", binaryPlist: binaryPlist)
        let result = try runPerry([app.path])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.lines == [
            "libGreet initializer",
            "app initializer sees greet_count=101",
            "hello from libGreet, count=101",
            "argv0 ends with Greeter.app/Greeter: 1",
        ])

        let report = try runPerry(["--report", app.path])
        #expect(report.stdout.contains("bundle\t\(app.resolvingSymlinksInPath().path)\torg.perry.fixture.greeter"))
        #expect(report.stdout.contains("dependency\t@rpath/libGreet.dylib\t\(app.path)/Frameworks/libGreet.dylib"))
    }

    @Test("Objective-C metadata is reported by name")
    func objectiveCReport() throws {
        let exe = try FixtureBuilder.executable("zoo.m", libraries: [FixtureBuilder.stub("libobjc")])
        let report = try runPerry(["--report", exe.path])
        #expect(report.status == 0)
        let lines = Set(report.stdout.lines)
        for expected in [
            "objc-class-defined\tAnimal",
            "objc-class-defined\tDog",
            "objc-category\tAnimal(Extras)",
            "objc-protocol-defined\tGreeting",
            "objc-class-conforms\tAnimal\tGreeting",
            "objc-protocol-defined\tWagging",
            "objc-category-conforms\tAnimal(Extras)\tWagging",
            "objc-class-referenced\tNSObject\tunresolved",
            "objc-selector\tsetLegs:",
            "objc-selector\tspeak",
            "unresolved\t/usr/lib/libobjc.A.dylib\t_objc_msgSend",
            "unresolved\t/usr/lib/libSystem.B.dylib\t__NSConcreteStackBlock",
            "dependency\t/usr/lib/libobjc.A.dylib\tmissing",
        ] {
            #expect(lines.contains(expected), "missing report line: \(expected)")
        }
    }

    @Test("Images are mapped in the low 64 GB like dyld")
    func lowAddresses() throws {
        let app = try FixtureBuilder.greeterApp(variant: "addresses", binaryPlist: false)
        let report = try runPerry(["--report", app.path])
        let bases = report.stdout.lines.filter { $0.hasPrefix("base\t0x") }.compactMap {
            UInt64($0.dropFirst("base\t0x".count), radix: 16)
        }
        #expect(bases.count == 2)
        for base in bases {
            #expect(base >= 0x1_0000_0000 && base < 0x10_0000_0000, "image base 0x\(String(base, radix: 16))")
        }
    }

    @Test("Encrypted binaries are rejected with a clear error")
    func encrypted() throws {
        let exe = try FixtureBuilder.executable("hello.c", variant: "-encrypted")
        try setCryptID(1, in: exe)

        let result = try runPerry([exe.path])
        #expect(result.status == 127)
        #expect(result.stderr.contains("binary is encrypted (cryptid 1)"))

        let report = try runPerry(["--report", exe.path])
        #expect(report.status == 0)
        #expect(report.stdout.contains("encrypted\tyes"))
    }

    @Test("Files that are not arm64 Mach-O are rejected", arguments: [
        ("#!/bin/sh\n", "file too small to be a Mach-O binary"),
        ("#!/bin/sh\n# padding so the file is larger than a mach header\necho hi\n", "not a 64-bit Mach-O binary"),
    ])
    func notMachO(contents: String, message: String) throws {
        let dir = try FixtureBuilder.directory("not-macho-\(contents.count)")
        let file = dir.appending(path: "script.sh")
        try Data(contents.utf8).write(to: file)
        let result = try runPerry([file.path])
        #expect(result.status == 127)
        #expect(result.stderr.contains(message))
    }

    /// Rewrites LC_ENCRYPTION_INFO_64.cryptid in a thin 64-bit Mach-O.
    private func setCryptID(_ value: UInt32, in url: URL) throws {
        var data = try Data(contentsOf: url)
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        }
        let ncmds = Int(u32(16))
        var offset = 32
        for _ in 0..<ncmds {
            let cmd = u32(offset), size = Int(u32(offset + 4))
            if cmd == 0x2c { // LC_ENCRYPTION_INFO_64
                withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset + 16..<offset + 20, with: $0) }
                try data.write(to: url)
                return
            }
            offset += size
        }
        Issue.record("fixture has no LC_ENCRYPTION_INFO_64")
    }
}
