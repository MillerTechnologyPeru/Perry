import Foundation
import Testing

/// Sources/PerryInterface/perry_settings.def lists every PERRY_*
/// environment variable: a name read in Sources and missing from it, or
/// listed and read nowhere, fails here.
@Suite struct SettingsTests {

    static let table = TestEnvironment.packageRoot.appending(path: "Sources/PerryInterface/perry_settings.def")

    static let kinds: Set<String> = ["flag", "bool01", "number", "string", "path", "list", "dynamic"]

    /// The table's lines: name, kind, group and whether --help lists it.
    static func entries() throws -> [(name: String, kind: String, group: String, help: String)] {
        let pattern = try Regex(#"^PERRY_SETTING\(([A-Z0-9_]+), ([a-z0-9]+), "([^"]+)", ([a-z]+), "[^"]+"\)$"#)
        return try String(contentsOf: table, encoding: .utf8).split(separator: "\n").compactMap { line in
            guard line.hasPrefix("PERRY_SETTING(") else { return nil }
            guard let match = try pattern.wholeMatch(in: String(line)) else {
                Issue.record("a line the table's format doesn't match: \(line)")
                return nil
            }
            return ("PERRY_" + String(match.output[1].substring!), String(match.output[2].substring!),
                    String(match.output[3].substring!), String(match.output[4].substring!))
        }
    }

    /// The PERRY_* names written as string literals in Sources, with a
    /// file that has each. Names ending in "_" are prefixes, not variables.
    static func namesInSources() throws -> [String: String] {
        let sources = TestEnvironment.packageRoot.appending(path: "Sources")
        let pattern = try Regex(#""(PERRY_[A-Z0-9_]+)""#)
        var names: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            guard ["swift", "c", "h", "m", "S", "cpp"].contains(file.pathExtension),
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for match in text.matches(of: pattern) {
                let name = String(match.output[1].substring!)
                if !name.hasSuffix("_") {
                    names[name] = names[name] ?? String(file.path.dropFirst(sources.path.count + 1))
                }
            }
        }
        return names
    }

    @Test("Every PERRY_* variable read in Sources is in the table")
    func everyNameIsListed() throws {
        let listed = Set(try Self.entries().map(\.name))
        for (name, file) in try Self.namesInSources().sorted(by: { $0.key < $1.key }) where !listed.contains(name) {
            Issue.record("\(name), read in \(file), isn't in perry_settings.def")
        }
    }

    @Test("Every variable in the table is read somewhere")
    func everyListedNameIsRead() throws {
        let read = try Self.namesInSources()
        for entry in try Self.entries() where read[entry.name] == nil {
            Issue.record("\(entry.name) is in perry_settings.def but nothing in Sources reads it")
        }
    }

    @Test("The table's entries are well formed and each listed once")
    func wellFormed() throws {
        let entries = try Self.entries()
        #expect(!entries.isEmpty)
        var seen: Set<String> = []
        for entry in entries {
            #expect(seen.insert(entry.name).inserted, "\(entry.name) is listed twice")
            #expect(Self.kinds.contains(entry.kind), "\(entry.name) has kind \(entry.kind)")
            #expect(["help", "detail"].contains(entry.help), "\(entry.name) is \(entry.help), not help or detail")
        }
    }

    @Test("perry --settings lists them all", .enabled(if: TestEnvironment.perry != nil, "needs perry"))
    func perryListsThem() throws {
        let result = try runPerry(["--settings"])
        #expect(result.status == 0)
        let printed = Set(result.stdout.lines.compactMap { $0.split(separator: " ").first.map(String.init) })
        for entry in try Self.entries() {
            #expect(printed.contains(entry.name), "perry --settings doesn't list \(entry.name)")
        }
    }
}
