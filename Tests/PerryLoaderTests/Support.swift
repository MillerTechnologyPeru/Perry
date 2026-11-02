import Foundation

/// Locations and tools shared by the loader tests.
enum TestEnvironment {

    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let fixtures = packageRoot.appending(path: "Tests/Fixtures")

    /// Build output for fixtures, kept under .build so it stays out of git.
    static let fixtureBuild = packageRoot.appending(path: ".build/perry-fixtures")

    /// Directory holding `perry` and `libPerrySystem.so`: the same directory as
    /// the test runner.
    static let products: URL? = {
        let exe = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        // xctest bundles may nest the runner one level down.
        for _ in 0..<3 {
            if FileManager.default.isExecutableFile(atPath: dir.appending(path: "perry").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    static var perry: URL? { products?.appending(path: "perry") }

    /// LLVM tools that can produce arm64 Mach-O: clang and ld64.lld.
    /// Searched in $PERRY_LLVM_BIN, .toolchains/LLVM-*/bin, then $PATH.
    static let llvmBin: URL? = {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["PERRY_LLVM_BIN"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        let toolchains = packageRoot.appending(path: ".toolchains")
        if let entries = try? fm.contentsOfDirectory(atPath: toolchains.path) {
            for entry in entries.sorted().reversed() where entry.hasPrefix("LLVM-") {
                candidates.append(toolchains.appending(path: entry).appending(path: "bin"))
            }
        }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(URL(fileURLWithPath: String(dir)))
        }
        return candidates.first {
            fm.isExecutableFile(atPath: $0.appending(path: "clang").path)
                && fm.isExecutableFile(atPath: $0.appending(path: "ld64.lld").path)
        }
    }()

    static var canRunFixtures: Bool { llvmBin != nil && perry != nil }
}

struct ProcessResult {
    var status: Int32
    var signaled: Bool
    var stdout: String
    var stderr: String
}

enum TestError: Error, CustomStringConvertible {
    case commandFailed(String, ProcessResult)
    case missingTool(String)

    var description: String {
        switch self {
        case .commandFailed(let command, let result):
            return "\(command) failed (\(result.status)):\n\(result.stdout)\(result.stderr)"
        case .missingTool(let tool):
            return "missing tool: \(tool)"
        }
    }
}

@discardableResult
func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    var env = ProcessInfo.processInfo.environment
    env.merge(environment) { $1 }
    process.environment = env
    // Output goes to files rather than pipes so a chatty child cannot block.
    let scratch = TestEnvironment.fixtureBuild.appending(path: "process-output")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let id = UUID().uuidString
    let outURL = scratch.appending(path: "\(id).out"), errURL = scratch.appending(path: "\(id).err")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    defer {
        try? FileManager.default.removeItem(at: outURL)
        try? FileManager.default.removeItem(at: errURL)
    }
    let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    try out.close()
    try err.close()
    let outData = try Data(contentsOf: outURL), errData = try Data(contentsOf: errURL)
    return ProcessResult(
        status: process.terminationStatus,
        signaled: process.terminationReason == .uncaughtSignal,
        stdout: String(decoding: outData, as: UTF8.self),
        stderr: String(decoding: errData, as: UTF8.self)
    )
}

func runPerry(_ arguments: [String], environment: [String: String] = [:]) throws -> ProcessResult {
    guard let perry = TestEnvironment.perry else { throw TestError.missingTool("perry") }
    return try run(perry, arguments, environment: environment)
}

/// Builds arm64 iOS Mach-O fixtures from C with clang and ld64.lld.
enum FixtureBuilder {

    static let minimumOS = "15.0"
    static let sdkVersion = "17.0"

    /// A new, empty directory for one build of fixture `name`. Each build
    /// gets a path of its own, and earlier builds are removed: deleting a
    /// directory and recreating it under the same name races on the Docker
    /// bind mount, where the recreated directory can vanish mid-build.
    static func directory(_ name: String) throws -> URL {
        let fm = FileManager.default
        let root = TestEnvironment.fixtureBuild
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for earlier in (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        where earlier == name || earlier.hasPrefix(name + ".") {
            try? fm.removeItem(at: root.appending(path: earlier))
        }
        let dir = root.appending(path: "\(name).\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Compiles and links `sources` (relative to Tests/Fixtures) into `output`.
    static func build(
        _ sources: [String],
        output: URL,
        dylibInstallName: String? = nil,
        linkFlags: [String] = [],
        libraries: [URL] = []
    ) throws {
        guard let bin = TestEnvironment.llvmBin else { throw TestError.missingTool("clang/ld64.lld") }
        let fm = FileManager.default
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        var objects: [String] = []
        for source in sources {
            let object = output.deletingLastPathComponent()
                .appending(path: "\(output.lastPathComponent)-\(URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent).o")
            var flags = ["-target", "arm64-apple-ios\(minimumOS)", "-O1", "-fno-stack-protector"]
            if source.hasSuffix(".m") {
                flags += ["-fobjc-arc", "-fblocks"]
            }
            let result = try run(bin.appending(path: "clang"), flags + [
                "-I", TestEnvironment.fixtures.appending(path: "include").path,
                "-c", TestEnvironment.fixtures.appending(path: source).path,
                "-o", object.path,
            ])
            guard result.status == 0 else { throw TestError.commandFailed("clang \(source)", result) }
            objects.append(object.path)
        }

        var arguments = ["-arch", "arm64", "-platform_version", "ios", minimumOS, sdkVersion, "-o", output.path]
        if let installName = dylibInstallName {
            arguments += ["-dylib", "-install_name", installName]
        }
        arguments += linkFlags + objects + libraries.map(\.path)
        arguments.append(TestEnvironment.fixtures.appending(path: "sdk/libSystem.tbd").path)
        let result = try run(bin.appending(path: "ld64.lld"), arguments)
        guard result.status == 0 else { throw TestError.commandFailed("ld64.lld \(output.lastPathComponent)", result) }
    }

    /// A link stub for a system library in Tests/Fixtures/sdk, e.g. "libobjc".
    static func stub(_ name: String) -> URL {
        TestEnvironment.fixtures.appending(path: "sdk/\(name).tbd")
    }

    /// Builds a single-file executable fixture and returns its path.
    static func executable(_ source: String, variant: String = "", linkFlags: [String] = [],
                           libraries: [URL] = []) throws -> URL {
        let name = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent + variant
        let output = try directory(name).appending(path: name)
        try build([source], output: output, linkFlags: linkFlags, libraries: libraries)
        return output
    }

    /// Builds Greeter.app: an executable plus an embedded @rpath dylib.
    /// `binaryPlist` writes Info.plist in the binary format App Store builds use.
    static func greeterApp(variant: String, binaryPlist: Bool) throws -> URL {
        let app = try directory("Greeter-\(variant)").appending(path: "Greeter.app")
        let frameworks = app.appending(path: "Frameworks")
        let dylib = frameworks.appending(path: "libGreet.dylib")
        try build(["Greeter/greet.c"], output: dylib, dylibInstallName: "@rpath/libGreet.dylib")
        try build(["Greeter/main.c"], output: app.appending(path: "Greeter"),
                  linkFlags: ["-rpath", "@executable_path/Frameworks"], libraries: [dylib])
        // Object files are build intermediates, not bundle contents.
        for dir in [app, frameworks] {
            for file in try FileManager.default.contentsOfDirectory(atPath: dir.path) where file.hasSuffix(".o") {
                try FileManager.default.removeItem(at: dir.appending(path: file))
            }
        }

        let source = TestEnvironment.fixtures.appending(path: "Greeter/Info.plist")
        let plist = app.appending(path: "Info.plist")
        if binaryPlist {
            let data = try Data(contentsOf: source)
            let object = try PropertyListSerialization.propertyList(from: data, format: nil)
            let binary = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
            try binary.write(to: plist)
        } else {
            try FileManager.default.copyItem(at: source, to: plist)
        }
        return app
    }
}

extension String {
    var lines: [String] { split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty } }
}
