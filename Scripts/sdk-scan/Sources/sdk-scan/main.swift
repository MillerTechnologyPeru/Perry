// sdk-scan: what the public macOS and iOS SDKs declare and export.
// Documentation/Plans/sdk-symbol-coverage.md, Phase 0.
//
//     sdk-scan scan --sdk <SDK> (--framework <name>... | --all) [--out <dir>]
//                   [--target <triple>] [--no-swift]
//         Writes <dir>/<Framework>.json for each framework (default dir
//         .build/sdk-scan/<SDK's canonical name>, e.g. macosx27.2). Needs
//         Xcode's clang and swift-symbolgraph-extract (through xcrun on a
//         Mac; SDK_SCAN_CLANG and SDK_SCAN_SYMBOLGRAPH_EXTRACT elsewhere).
//
//     sdk-scan summary <manifest.json>...
//         Counts what each manifest holds. Runs on any host.
//
// Example:
//     swift run -c release --package-path Scripts/sdk-scan sdk-scan scan \
//         --sdk "$(xcrun --sdk macosx --show-sdk-path)" --framework Foundation --framework AppKit

import Foundation
import SDKScan

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sdk-scan: \(message)\n".utf8))
    exit(1)
}

let usage = """
    usage: sdk-scan scan --sdk <SDK> (--framework <name>... | --all) [--out <dir>] [--target <triple>] [--no-swift]
           sdk-scan summary <manifest.json>...
    """

func scan(_ arguments: [String]) throws {
    var sdkPath: String?
    var frameworks: [String] = []
    var all = false
    var output: String?
    var target: String?
    var includeSwift = true
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        func value() -> String {
            guard let value = iterator.next() else { fail("\(argument) needs a value\n\(usage)") }
            return value
        }
        switch argument {
        case "--sdk": sdkPath = value()
        case "--framework": frameworks.append(value())
        case "--all": all = true
        case "--out": output = value()
        case "--target": target = value()
        case "--no-swift": includeSwift = false
        default: fail("unknown argument \(argument)\n\(usage)")
        }
    }
    guard let sdkPath else { fail(usage) }
    let sdk = try SDK(path: sdkPath)
    if all { frameworks = try sdk.frameworkNames() }
    guard !frameworks.isEmpty else { fail(usage) }
    let directory = output ?? ".build/sdk-scan/\(sdk.info.canonicalName)"
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    var scanner = Scanner(sdk: sdk, target: target)
    scanner.includeSwift = includeSwift
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var failed: [String] = []
    for framework in frameworks {
        let start = Date()
        do {
            let manifest = try scanner.scan(framework)
            let path = directory + "/\(framework).json"
            try encoder.encode(manifest).write(to: URL(fileURLWithPath: path))
            let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
            print("\(framework) (\(scanner.target), \(seconds) s) → \(path)")
            for line in ManifestSummary(manifest).lines { print("  " + line) }
        } catch {
            failed.append(framework)
            FileHandle.standardError.write(Data("sdk-scan: \(framework): \(error)\n".utf8))
        }
    }
    if !failed.isEmpty { fail("\(failed.count) failed: \(failed.joined(separator: ", "))") }
}

func summary(_ paths: [String]) throws {
    guard !paths.isEmpty else { fail(usage) }
    for path in paths {
        let manifest = try JSONDecoder().decode(FrameworkManifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard manifest.format == FrameworkManifest.currentFormat else {
            fail("\(path): format \(manifest.format), this sdk-scan reads \(FrameworkManifest.currentFormat)")
        }
        print("\(manifest.framework) (\(manifest.sdk.canonicalName), \(manifest.target))")
        for line in ManifestSummary(manifest).lines { print("  " + line) }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "scan": try scan(Array(arguments.dropFirst()))
    case "summary": try summary(Array(arguments.dropFirst()))
    default: fail(usage)
    }
} catch {
    fail("\(error)")
}
