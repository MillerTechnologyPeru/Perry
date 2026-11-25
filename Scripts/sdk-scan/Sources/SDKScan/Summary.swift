// Counts of what a manifest holds, for the terminal and for checking a scan
// against what the plan measured.

public struct ManifestSummary: Equatable, Sendable {
    /// Export counts of a set of libraries, unique over targets.
    public struct Exports: Equatable, Sendable {
        public var byKind: [ExportKind: Int] = [:]
        /// Classes without a leading underscore.
        public var publicClasses = 0
        /// C names a program writes without an underscore of its own: the
        /// symbol's C underscore dropped, none left, and not `OBJC_…`.
        public var publicSymbols = 0

        init(_ libraries: some Sequence<Library>) {
            var names: [ExportKind: Set<String>] = [:]
            for library in libraries {
                for kind in ExportKind.allCases { names[kind, default: []].formUnion(library.names(kind)) }
            }
            for kind in ExportKind.allCases { byKind[kind] = names[kind]?.count ?? 0 }
            publicClasses = (names[.objcClass] ?? []).filter { !$0.hasPrefix("_") }.count
            publicSymbols = (names[.symbol] ?? []).filter { name in
                let bare = name.hasPrefix("_") ? name.dropFirst() : Substring(name)
                return !bare.hasPrefix("OBJC_") && !bare.hasPrefix("_") && !bare.hasPrefix(".")
            }.count
        }

        var text: String {
            "classes \(byKind[.objcClass] ?? 0) (\(publicClasses) without _), C names \(byKind[.symbol] ?? 0) "
                + "(\(publicSymbols) without _), Swift \(byKind[.swift] ?? 0), ivars \(byKind[.objcIvar] ?? 0)"
        }
    }

    /// The framework's own library.
    public var exports: Exports
    /// It and the libraries it re-exports that its .tbd inlines: all a
    /// program linking the framework can reach.
    public var exportsWithReexports: Exports
    public var reexportedLibraries: [String]
    /// Header declarations by kind.
    public var declarations: [String: Int] = [:]
    public var swiftDeclarations = 0
    public var skippedHeaders = 0

    public init(_ manifest: FrameworkManifest) {
        exports = Exports(manifest.libraries.prefix(1))
        exportsWithReexports = Exports(manifest.libraries)
        reexportedLibraries = manifest.libraries.dropFirst().map {
            String($0.installName.split(separator: "/").last ?? "")
        }
        for declaration in manifest.declarations { declarations[declaration.kind, default: 0] += 1 }
        swiftDeclarations = manifest.swiftDeclarations.count
        skippedHeaders = manifest.skippedHeaders.count
    }

    public var lines: [String] {
        let kinds = ["class", "protocol", "method", "type.method", "property", "type.property", "func", "var", "ivar"]
        let headerCounts = kinds.map { "\($0) \(declarations[$0] ?? 0)" }.joined(separator: ", ")
        var lines = ["exports: " + exports.text]
        if !reexportedLibraries.isEmpty {
            lines.append("with \(reexportedLibraries.joined(separator: ", ")): " + exportsWithReexports.text)
        }
        lines.append("headers: \(headerCounts); \(declarations.values.reduce(0, +)) in all, \(skippedHeaders) headers skipped")
        lines.append("swift: \(swiftDeclarations) declarations")
        return lines
    }
}
