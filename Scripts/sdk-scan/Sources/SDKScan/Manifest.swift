// What a scan writes for one framework of one SDK: the symbols its stub
// library exports, the declarations its headers make, and its Swift API.
// One JSON file per framework, in .build (SDK content stays out of the
// repository).

/// One framework of one SDK.
public struct FrameworkManifest: Codable, Equatable, Sendable {
    /// Bumped when the shape changes, so readers can refuse an old file.
    public static let currentFormat = 1

    public var format = FrameworkManifest.currentFormat
    public var framework: String
    public var sdk: SDKInfo
    /// The triple the headers and Swift module were read for.
    public var target: String
    /// The `.tbd` documents: the framework's own first, then the libraries
    /// it re-exports that the same file describes.
    public var libraries: [Library]
    /// The headers' declarations, in the order clang reports them.
    public var declarations: [Declaration]
    /// The Swift module's own declarations (none for a framework without
    /// one), in the order the symbol graph lists them.
    public var swiftDeclarations: [SwiftDeclaration]
    /// Headers clang couldn't read, which the scan left out.
    public var skippedHeaders: [String]

    public init(framework: String, sdk: SDKInfo, target: String, libraries: [Library],
                declarations: [Declaration], swiftDeclarations: [SwiftDeclaration], skippedHeaders: [String]) {
        self.framework = framework
        self.sdk = sdk
        self.target = target
        self.libraries = libraries
        self.declarations = declarations
        self.swiftDeclarations = swiftDeclarations
        self.skippedHeaders = skippedHeaders
    }
}

/// The SDK a manifest was read from, from its SDKSettings.json.
public struct SDKInfo: Codable, Equatable, Sendable {
    /// `macosx27.2`, `iphoneos27.2`.
    public var canonicalName: String
    /// `macosx`, `iphoneos`.
    public var platform: String
    public var version: String

    public init(canonicalName: String, platform: String, version: String) {
        self.canonicalName = canonicalName
        self.platform = platform
        self.version = version
    }
}

// MARK: - Exports

/// One document of a `.tbd`: a library and what it exports.
public struct Library: Codable, Equatable, Sendable {
    public var installName: String
    public var currentVersion: String?
    /// Libraries whose exports this one passes on as its own.
    public var reexportedLibraries: [String]
    /// The export lists, each for the targets it names, as the `.tbd`
    /// groups them.
    public var exports: [ExportSection]
    /// `$ld$` directives (hide, previous, install_name), which say where a
    /// symbol was before an OS version rather than declare one.
    public var directives: [String]

    public init(installName: String, currentVersion: String? = nil, reexportedLibraries: [String] = [],
                exports: [ExportSection] = [], directives: [String] = []) {
        self.installName = installName
        self.currentVersion = currentVersion
        self.reexportedLibraries = reexportedLibraries
        self.exports = exports
        self.directives = directives
    }

    /// Whether it is public: in the SDK's Frameworks or usr/lib, not
    /// PrivateFrameworks.
    public var isPublic: Bool { !installName.contains("/PrivateFrameworks/") }

    /// Every name it exports of a kind, for any target.
    public func names(_ kind: ExportKind) -> Set<String> {
        exports.reduce(into: []) { $0.formUnion($1[kind]) }
    }
}

/// The kinds of name a `.tbd` exports.
public enum ExportKind: String, Codable, CaseIterable, Sendable {
    /// C functions and data, with their leading underscore.
    case symbol
    /// Swift symbols (`_$s…`), which `.tbd` lists with the C ones.
    case swift
    /// Objective-C classes by name; each exports `_OBJC_CLASS_$_<name>` and
    /// `_OBJC_METACLASS_$_<name>`.
    case objcClass
    /// Objective-C exception types (`_OBJC_EHTYPE_$_<name>`).
    case objcEHType
    /// Instance variable offsets, as `<class>.<ivar>`.
    case objcIvar
    case weakSymbol
    case threadLocalSymbol
}

/// The names exported for a set of targets.
public struct ExportSection: Codable, Equatable, Sendable {
    /// `arm64e-macos`, `x86_64-maccatalyst`, `arm64-ios` (v4 targets).
    public var targets: [String]
    public var symbols: [String]
    public var swiftSymbols: [String]
    public var objcClasses: [String]
    public var objcEHTypes: [String]
    public var objcIvars: [String]
    public var weakSymbols: [String]
    public var threadLocalSymbols: [String]

    public init(targets: [String], symbols: [String] = [], swiftSymbols: [String] = [], objcClasses: [String] = [],
                objcEHTypes: [String] = [], objcIvars: [String] = [], weakSymbols: [String] = [],
                threadLocalSymbols: [String] = []) {
        self.targets = targets
        self.symbols = symbols
        self.swiftSymbols = swiftSymbols
        self.objcClasses = objcClasses
        self.objcEHTypes = objcEHTypes
        self.objcIvars = objcIvars
        self.weakSymbols = weakSymbols
        self.threadLocalSymbols = threadLocalSymbols
    }

    public subscript(kind: ExportKind) -> [String] {
        get {
            switch kind {
            case .symbol: symbols
            case .swift: swiftSymbols
            case .objcClass: objcClasses
            case .objcEHType: objcEHTypes
            case .objcIvar: objcIvars
            case .weakSymbol: weakSymbols
            case .threadLocalSymbol: threadLocalSymbols
            }
        }
        set {
            switch kind {
            case .symbol: symbols = newValue
            case .swift: swiftSymbols = newValue
            case .objcClass: objcClasses = newValue
            case .objcEHType: objcEHTypes = newValue
            case .objcIvar: objcIvars = newValue
            case .weakSymbol: weakSymbols = newValue
            case .threadLocalSymbol: threadLocalSymbols = newValue
            }
        }
    }

    var isEmpty: Bool { ExportKind.allCases.allSatisfy { self[$0].isEmpty } }
}

// MARK: - Declarations

/// A declaration in the framework's headers.
public struct Declaration: Codable, Equatable, Sendable {
    /// clang's kind without its language: `class`, `protocol`, `method`
    /// (instance), `type.method` (class), `property`, `type.property`,
    /// `ivar`, `func`, `var`, `enum`, `enum.case`, `struct`, `union`,
    /// `typealias`, `macro`.
    public var kind: String
    /// Its own name: a selector for a method, a property's name.
    public var name: String
    /// The class, protocol, enum or struct it is a member of.
    public var container: String?
    /// `class`, `protocol`, `enum`, `struct` or `union`, from the USR.
    public var containerKind: String?
    /// clang's USR, unique per declaration.
    public var usr: String
    /// The declaration as the header writes it, comments left out.
    public var declaration: String
    /// The header, relative to the framework's Headers directory.
    public var header: String
    public var line: Int?
    /// A class's superclass.
    public var superclass: String?
    /// The protocols a class or protocol adopts.
    public var protocols: [String]?
    public var availability: [Availability]?
    /// A method's or function's result and parameters, as the header types
    /// them.
    public var returns: String?
    public var parameters: [Parameter]?
    /// A property's accessors and attributes.
    public var getter: String?
    public var setter: String?
    public var attributes: [String]?

    public init(kind: String, name: String, usr: String, declaration: String, header: String) {
        self.kind = kind
        self.name = name
        self.usr = usr
        self.declaration = declaration
        self.header = header
    }
}

public struct Parameter: Codable, Equatable, Sendable {
    public var name: String
    public var type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

/// Availability on one platform (`macos`, `ios`, `maccatalyst`…).
public struct Availability: Codable, Equatable, Sendable {
    public var domain: String
    public var introduced: String?
    public var deprecated: String?
    public var obsoleted: String?
    public var unavailable: Bool?

    public init(domain: String, introduced: String? = nil, deprecated: String? = nil, obsoleted: String? = nil,
                unavailable: Bool? = nil) {
        self.domain = domain
        self.introduced = introduced
        self.deprecated = deprecated
        self.obsoleted = obsoleted
        self.unavailable = unavailable
    }
}

/// A declaration of the framework's Swift module.
public struct SwiftDeclaration: Codable, Equatable, Sendable {
    /// The symbol graph's kind without `swift.`: `struct`, `class`,
    /// `method`, `property`, `init`, `func`, `var`, `subscript`…
    public var kind: String
    /// Its path: `NSHorizontalDirection.Set.init(rawValue:)`.
    public var path: String
    /// The Swift USR (`s:` and a mangled name without its `$s`), which the
    /// exports' mangled names start with or derive from.
    public var usr: String
    public var declaration: String
    /// The module of the type it extends, when not this one.
    public var extendedModule: String?
    public var availability: [Availability]?

    public init(kind: String, path: String, usr: String, declaration: String) {
        self.kind = kind
        self.path = path
        self.usr = usr
        self.declaration = declaration
    }
}
