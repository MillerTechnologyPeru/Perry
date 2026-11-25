// Scans one framework of an SDK: reads its .tbd, runs `clang -extract-api`
// over all its headers and, when it has a Swift module,
// `swift-symbolgraph-extract`, and puts the results in a manifest.

import Foundation

public struct ScanError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// An SDK on disk.
public struct SDK: Sendable {
    public let path: String
    public let info: SDKInfo
    /// The triple to read headers and Swift modules for: arm64, the SDK's
    /// OS and its own version (`arm64-apple-macos27.2`).
    public let defaultTarget: String

    public init(path: String) throws {
        let settingsURL = URL(fileURLWithPath: path).appendingPathComponent("SDKSettings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScanError("\(path): no SDKSettings.json")
        }
        let canonicalName = settings["CanonicalName"] as? String ?? ""
        let version = settings["Version"] as? String ?? ""
        let defaults = settings["DefaultProperties"] as? [String: Any]
        let platform = defaults?["PLATFORM_NAME"] as? String
            ?? String(canonicalName.prefix(while: { !$0.isNumber && $0 != "." }))
        self.path = path
        info = SDKInfo(canonicalName: canonicalName, platform: platform, version: version)
        // The triple's OS from the SDK's own target settings where there are
        // any; macosx and iphoneos are named otherwise in triples.
        let targets = settings["SupportedTargets"] as? [String: Any]
        let target = targets?[platform] as? [String: Any]
        let system = target?["LLVMTargetTripleSys"] as? String ?? Self.tripleSystem(platform)
        let environment = (target?["LLVMTargetTripleEnvironment"] as? String).flatMap { $0.isEmpty ? nil : "-" + $0 } ?? ""
        let deployment = target?["DefaultDeploymentTarget"] as? String ?? version
        defaultTarget = "arm64-apple-\(system)\(deployment)\(environment)"
    }

    static func tripleSystem(_ platform: String) -> String {
        switch platform {
        case "macosx": "macos"
        case "iphoneos", "iphonesimulator": "ios"
        case "appletvos", "appletvsimulator": "tvos"
        case "watchos", "watchsimulator": "watchos"
        case "xros", "xrsimulator": "xros"
        default: platform
        }
    }

    public var frameworksDirectory: String { path + "/System/Library/Frameworks" }

    public func frameworkDirectory(_ name: String) -> String { frameworksDirectory + "/\(name).framework" }

    /// Every public framework the SDK has, by name.
    public func frameworkNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: frameworksDirectory)
            .filter { $0.hasSuffix(".framework") }.map { String($0.dropLast(".framework".count)) }.sorted()
    }
}

/// The programs a scan runs. On a Mac each is found through xcrun; set
/// SDK_SCAN_CLANG or SDK_SCAN_SYMBOLGRAPH_EXTRACT to use others.
public struct Tools: Sendable {
    public var clang: [String]
    public var symbolGraphExtract: [String]

    public static var `default`: Tools {
        let environment = ProcessInfo.processInfo.environment
        #if os(macOS)
        let clang = ["/usr/bin/xcrun", "clang"]
        let extract = ["/usr/bin/xcrun", "swift-symbolgraph-extract"]
        #else
        let clang = ["/usr/bin/env", "clang"]
        let extract = ["/usr/bin/env", "swift-symbolgraph-extract"]
        #endif
        return Tools(clang: environment["SDK_SCAN_CLANG"].map { [$0] } ?? clang,
                     symbolGraphExtract: environment["SDK_SCAN_SYMBOLGRAPH_EXTRACT"].map { [$0] } ?? extract)
    }
}

public struct Scanner: Sendable {
    public let sdk: SDK
    public let target: String
    public let tools: Tools
    public var includeSwift = true
    /// Progress and the headers left out, for the terminal.
    public var log: @Sendable (String) -> Void = { message in
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    public init(sdk: SDK, target: String? = nil, tools: Tools = .default) {
        self.sdk = sdk
        self.target = target ?? sdk.defaultTarget
        self.tools = tools
    }

    public func scan(_ framework: String) throws -> FrameworkManifest {
        let directory = sdk.frameworkDirectory(framework)
        guard FileManager.default.fileExists(atPath: directory) else { throw ScanError("\(directory): no such framework") }

        let libraries = try readStub(framework)
        let (declarations, skipped) = try readHeaders(framework)
        let swift = includeSwift ? try readSwiftModule(framework) : []
        return FrameworkManifest(framework: framework, sdk: sdk.info, target: target, libraries: libraries,
                                 declarations: declarations, swiftDeclarations: swift, skippedHeaders: skipped)
    }

    // MARK: Exports

    /// The framework's .tbd: its own document and the re-exported ones the
    /// file inlines. A framework with no stub (headers only) exports none.
    func readStub(_ framework: String) throws -> [Library] {
        let directory = sdk.frameworkDirectory(framework)
        let candidates = [directory + "/\(framework).tbd", directory + "/Versions/A/\(framework).tbd",
                          directory + "/Versions/C/\(framework).tbd"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            log("\(framework): no .tbd")
            return []
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return TBD.reexportClosure(try TBD.parse(text))
    }

    // MARK: Headers

    /// Every header in the framework's Headers directory and below.
    func headerPaths(_ framework: String) -> [String] {
        let headers = sdk.frameworkDirectory(framework) + "/Headers"
        guard let enumerator = FileManager.default.enumerator(atPath: headers) else { return [] }
        var paths: [String] = []
        while let relative = enumerator.nextObject() as? String {
            if relative.hasSuffix(".h") { paths.append(headers + "/" + relative) }
        }
        return paths.sorted()
    }

    /// clang's declarations for all the headers at once, with extension
    /// graphs so categories on other frameworks' classes are kept. If clang
    /// fails on the set, each header is tried alone and the ones that fail
    /// are left out and reported.
    func readHeaders(_ framework: String) throws -> ([Declaration], [String]) {
        let headers = headerPaths(framework)
        guard !headers.isEmpty else { return ([], []) }
        let headersDirectory = sdk.frameworkDirectory(framework) + "/Headers"
        if let graphs = try? extractAPI(framework, headers) {
            return (Headers.declarations(graphs, headersDirectory: headersDirectory), [])
        }
        log("\(framework): clang failed on the headers together; trying each alone")
        var graphs: [SymbolGraph] = []
        var skipped: [String] = []
        for header in headers {
            do {
                graphs += try extractAPI(framework, [header])
            } catch {
                skipped.append(String(header.dropFirst(headersDirectory.count + 1)))
                log("\(framework): left out \(header): \(error)")
            }
        }
        return (Headers.declarations(graphs, headersDirectory: headersDirectory), skipped)
    }

    func extractAPI(_ framework: String, _ headers: [String]) throws -> [SymbolGraph] {
        let output = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: output) }
        // xcrun's own SDK argument only picks the clang; -isysroot is what
        // the headers are read from.
        let arguments = ["-extract-api", "--product-name=\(framework)", "-target", target, "-isysroot", sdk.path,
                         "-x", "objective-c-header", "--emit-extension-symbol-graphs", "--symbol-graph-dir=\(output)"]
        try run(tools.clang + arguments + headers)
        return try readGraphs(in: output).map(\.graph)
    }

    // MARK: Swift

    /// The framework's Swift module, in the framework or in usr/lib/swift.
    func swiftModulePath(_ framework: String) -> String? {
        let candidates = [sdk.frameworkDirectory(framework) + "/Modules/\(framework).swiftmodule",
                          sdk.path + "/usr/lib/swift/\(framework).swiftmodule"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    func readSwiftModule(_ framework: String) throws -> [SwiftDeclaration] {
        guard swiftModulePath(framework) != nil else { return [] }
        let output = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: output) }
        try run(tools.symbolGraphExtract + ["-module-name", framework, "-target", target, "-sdk", sdk.path,
                                            "-output-dir", output, "-minimum-access-level", "public"])
        return SwiftAPI.declarations(try readGraphs(in: output), module: framework)
    }

    // MARK: Files and processes

    /// The graphs in a directory: `<Module>.symbols.json` and, for what it
    /// extends of another module, `<Module>@<Other>.symbols.json`.
    func readGraphs(in directory: String) throws -> [(extendedModule: String?, graph: SymbolGraph)] {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".symbols.json") }.sorted()
        return try files.map { file in
            let data = try Data(contentsOf: URL(fileURLWithPath: directory + "/" + file))
            let name = file.dropLast(".symbols.json".count)
            let extended = name.split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init)
            return (extended, try JSONDecoder().decode(SymbolGraph.self, from: data))
        }
    }

    func temporaryDirectory() throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("sdk-scan-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Runs a program, its output discarded but for the end of what it
    /// wrote to stderr when it fails.
    func run(_ command: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Read before waiting, so a full pipe can't stall the program.
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let lines = String(decoding: errorData, as: UTF8.self).split(separator: "\n")
                .filter { $0.contains("error") }.suffix(3)
            throw ScanError("\(command[1...].prefix(2).joined(separator: " ")) failed (\(process.terminationStatus)): "
                + lines.joined(separator: "; "))
        }
    }
}
