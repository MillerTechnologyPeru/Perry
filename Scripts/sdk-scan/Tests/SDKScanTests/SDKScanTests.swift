// sdk-scan's tests, over a made-up SDK in Fixtures: Widget (two headers, a
// .tbd re-exporting a private library) and Gadget (a category on Widget's
// class, no .tbd). The end-to-end scan needs a clang with -extract-api and
// is skipped without one; everything else runs on any host.

import Foundation
import Testing
@testable import SDKScan

let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
let fakeSDK = fixtures.appendingPathComponent("Fake.sdk").path
let widgetHeaders = "/Fake.sdk/System/Library/Frameworks/Widget.framework/Headers"

func fixture(_ path: String) throws -> String {
    try String(contentsOf: fixtures.appendingPathComponent(path), encoding: .utf8)
}

func graph(_ name: String) throws -> SymbolGraph {
    try JSONDecoder().decode(SymbolGraph.self, from: Data(contentsOf: fixtures.appendingPathComponent(name)))
}

@Suite struct TBDTests {
    @Test func version4() throws {
        let all = try TBD.parse(fixture("Fake.sdk/System/Library/Frameworks/Widget.framework/Widget.tbd"))
        #expect(all.map(\.installName) == [
            "/System/Library/Frameworks/Widget.framework/Versions/A/Widget",
            "/System/Library/PrivateFrameworks/WidgetCore.framework/Versions/A/WidgetCore",
            "/usr/lib/libunrelated.dylib",
        ])
        let widget = all[0]
        #expect(widget.currentVersion == "12.3")
        #expect(widget.reexportedLibraries == ["/System/Library/PrivateFrameworks/WidgetCore.framework/Versions/A/WidgetCore"])
        #expect(widget.directives == ["$ld$hide$os10.9$_OBJC_CLASS_$_Widget"])
        #expect(widget.exports.count == 2)
        let shared = widget.exports[0]
        #expect(shared.targets == ["x86_64-macos", "arm64e-macos"])
        // The flow sequence runs over two lines; directives and Swift
        // symbols are taken out of the C ones.
        #expect(shared.symbols == ["_WidgetCount", "_WidgetDidChangeNotification"])
        #expect(shared.swiftSymbols == ["_$s6Widget5ScaleV8rawValueSivg"])
        #expect(shared.objcClasses == ["Widget", "_WidgetPrivate"])
        #expect(shared.objcIvars == ["Widget._count"])
        #expect(widget.exports[1].targets == ["arm64e-macos"])
        #expect(widget.exports[1].weakSymbols == ["_WidgetWeak"])
        #expect(widget.names(.symbol) == ["_WidgetCount", "_WidgetDidChangeNotification", "_WidgetArm64Only"])
        #expect(widget.isPublic)
        #expect(!all[1].isPublic)
    }

    @Test func reexportClosureFollowsOnlyReexports() throws {
        let all = try TBD.parse(fixture("Fake.sdk/System/Library/Frameworks/Widget.framework/Widget.tbd"))
        let closure = TBD.reexportClosure(all)
        #expect(closure.map(\.installName).map { $0.split(separator: "/").last! } == ["Widget", "WidgetCore"])
        #expect(closure[1].exports.first?.objcClasses == ["WidgetBase"])
    }

    @Test func version3() throws {
        let library = try #require(try TBD.parse(fixture("Sample-v3.tbd")).first)
        #expect(library.installName == "/System/Library/Frameworks/Sample.framework/Sample")
        #expect(library.reexportedLibraries == ["/usr/lib/libobjc.A.dylib"])
        #expect(library.exports[0].targets == ["armv7-ios", "armv7s-ios", "arm64-ios"])
        #expect(library.exports[0].symbols == ["_SampleFunction", "It's quoted"])
        #expect(library.exports[0].objcClasses == ["SampleObject"])
        #expect(library.exports[1].symbols == ["_Sample64"])
    }

    @Test func refusesOtherVersions() {
        #expect(throws: TBDError.self) { try TBD.parse("--- !tapi-tbd\ntbd-version: 5\ninstall-name: x\n...\n") }
        #expect(throws: TBDError.self) { try TBD.parse("not a stub\n") }
    }

    @Test func yamlScalars() {
        #expect(YAML.unquote("'a''b'") == "a'b")
        #expect(YAML.unquote("\"a\\\"b\"") == "a\"b")
        #expect(YAML.scalarOrFlow("[ a, 'b, c', d ]") == .sequence([.scalar("a"), .scalar("b, c"), .scalar("d")]))
        #expect(YAML.scalarOrFlow("[ ]") == .sequence([]))
        #expect(YAML.keyColon("'a:b': c").map { "'a:b': c"[..<$0] } == "'a:b'")
    }
}

@Suite struct SDKTests {
    @Test func settings() throws {
        let sdk = try SDK(path: fakeSDK)
        #expect(sdk.info == SDKInfo(canonicalName: "fakeos1.2", platform: "macosx", version: "1.2"))
        #expect(sdk.defaultTarget == "arm64-apple-macos14.0")
        #expect(try sdk.frameworkNames() == ["Gadget", "Widget"])
    }

    @Test func tripleSystems() {
        #expect(SDK.tripleSystem("iphoneos") == "ios")
        #expect(SDK.tripleSystem("macosx") == "macos")
    }
}

@Suite struct HeaderTests {
    /// The fixture's declarations by "<container or kind> <name>".
    func declarations() throws -> [String: Declaration] {
        let list = Headers.declarations([try graph("Widget.symbols.json")], headersDirectory: widgetHeaders)
        return Dictionary(list.map { (($0.container ?? $0.kind) + " " + $0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Test func classes() throws {
        let all = try declarations()
        let widget = try #require(all["class Widget"])
        #expect(widget.superclass == "WidgetBase")
        #expect(widget.protocols == ["WidgetDrawing"])
        #expect(widget.header == "Widget.h")
        #expect(widget.line == 10)
        #expect(widget.availability == [Availability(domain: "macos", introduced: "10.10")])
        #expect(all["class WidgetBase"]?.superclass == nil)
        #expect(all["protocol WidgetDrawing"] != nil)
    }

    @Test func methods() throws {
        let all = try declarations()
        let initializer = try #require(all["Widget initWithName:count:"])
        #expect(initializer.kind == "method")
        #expect(initializer.containerKind == "class")
        #expect(initializer.returns == "instancetype")
        #expect(initializer.parameters == [Parameter(name: "name", type: "const char *"), Parameter(name: "count", type: "int")])
        #expect(all["Widget widgetNamed:"]?.kind == "type.method")
        #expect(all["Widget oldMethod"]?.availability?.first?.deprecated == "10.12")
        #expect(all["WidgetDrawing drawInContext:"]?.containerKind == "protocol")
        // A category's members are its class's.
        #expect(all["WidgetBase setName:animated:"]?.header == "WidgetBase.h")
    }

    @Test func properties() throws {
        let all = try declarations()
        let enabled = try #require(all["Widget enabled"])
        #expect(enabled.getter == "isEnabled")
        #expect(enabled.setter == "setEnabled:")
        #expect(all["Widget count"]?.setter == nil)
        #expect(all["Widget sharedWidget"]?.kind == "type.property")
        #expect(all["WidgetBase name"]?.setter == "setName:")
    }

    @Test func functionsAndVariables() throws {
        let all = try declarations()
        let count = try #require(all["func WidgetCount"])
        #expect(count.returns == "int")
        #expect(count.parameters?.map(\.type) == ["Widget *", "BOOL"])
        #expect(all["var WidgetDidChangeNotification"]?.declaration == "extern const char * const WidgetDidChangeNotification;")
    }

    @Test func propertyAttributes() {
        var declaration = Declaration(kind: "property", name: "on", usr: "", declaration: "", header: "")
        Headers.applyPropertyAttributes(&declaration, [
            .init(kind: "keyword", spelling: "@property"), .init(kind: "text", spelling: " ("),
            .init(kind: "keyword", spelling: "getter"), .init(kind: "text", spelling: "="),
            .init(kind: "identifier", spelling: "isOn"), .init(kind: "text", spelling: ", "),
            .init(kind: "keyword", spelling: "setter"), .init(kind: "text", spelling: "="),
            .init(kind: "identifier", spelling: "turnOn:"), .init(kind: "text", spelling: ") BOOL on;"),
        ])
        #expect(declaration.getter == "isOn")
        #expect(declaration.setter == "turnOn:")
        #expect(declaration.attributes == ["getter=isOn", "setter=turnOn:"])
    }

    @Test func containerKinds() {
        #expect(Headers.containerKind("c:objc(cs)NSView(im)frame") == "class")
        #expect(Headers.containerKind("c:objc(pl)NSCoding(im)encodeWithCoder:") == "protocol")
        #expect(Headers.containerKind("c:@E@NSWindowStyleMask@NSWindowStyleMaskTitled") == "enum")
        #expect(Headers.containerKind("c:@NSBeep") == nil)
        #expect(Headers.name(fromUSR: "c:objc(cs)NSObject") == "NSObject")
    }
}

@Suite struct SwiftTests {
    @Test func ownDeclarationsOnly() throws {
        let scanner = Scanner(sdk: try SDK(path: fakeSDK))
        // Widget.symbols.json, clang's, is read too: it has no Swift USRs.
        let declarations = SwiftAPI.declarations(try scanner.readGraphs(in: fixtures.path), module: "Gizmo")
        // Not the Objective-C class, the protocol's default implementation
        // nor the SPI.
        #expect(declarations.map(\.path) == ["Scale", "Scale.rawValue", "Data.gizmo()"])
        #expect(declarations[0].kind == "struct")
        #expect(declarations[0].declaration == "struct Scale")
        #expect(declarations[0].availability == [Availability(domain: "macOS", introduced: "14.0")])
        #expect(declarations[0].extendedModule == nil)
        #expect(declarations[2].extendedModule == "Foundation")
    }
}

/// A clang that can extract APIs: SDK_SCAN_CLANG, or Xcode's on a Mac.
let canExtractAPI: Bool = {
    let tools = Tools.default
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tools.clang[0])
    process.arguments = Array(tools.clang.dropFirst()) + ["-extract-api", "--help"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}()

@Suite struct ScanTests {
    @Test(.enabled(if: canExtractAPI)) func widget() throws {
        var scanner = Scanner(sdk: try SDK(path: fakeSDK))
        scanner.log = { _ in }
        let manifest = try scanner.scan("Widget")
        #expect(manifest.framework == "Widget")
        #expect(manifest.target == "arm64-apple-macos14.0")
        #expect(manifest.libraries.count == 2)
        #expect(manifest.skippedHeaders.isEmpty)
        #expect(manifest.swiftDeclarations.isEmpty)
        let names = Set(manifest.declarations.map { ($0.container ?? "") + " " + $0.name })
        #expect(names.isSuperset(of: ["Widget initWithName:count:", "WidgetBase setName:animated:", " WidgetCount", " Widget"]))
        let summary = ManifestSummary(manifest)
        #expect(summary.exports.publicClasses == 1)
        #expect(summary.exportsWithReexports.byKind[.objcClass] == 3)
        #expect(summary.declarations["class"] == 2)

        // Round trip through the file format.
        let data = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(FrameworkManifest.self, from: data) == manifest)
    }

    @Test(.enabled(if: canExtractAPI)) func categoryFromAnotherFramework() throws {
        var scanner = Scanner(sdk: try SDK(path: fakeSDK))
        scanner.log = { _ in }
        let manifest = try scanner.scan("Gadget")
        #expect(manifest.libraries.isEmpty)
        let attach = try #require(manifest.declarations.first { $0.name == "attachGadget:" })
        #expect(attach.container == "Widget")
        #expect(attach.header == "Gadget.h")
    }

    @Test(.enabled(if: canExtractAPI)) func leavesOutHeadersClangCantRead() throws {
        // A copy of the fake SDK with a header that doesn't compile.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("sdk-scan-test-\(UUID().uuidString).sdk")
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(atPath: fakeSDK, toPath: copy.path)
        try "@interface Broken : Missing @end\n".write(
            to: copy.appendingPathComponent("System/Library/Frameworks/Widget.framework/Headers/Broken.h"),
            atomically: true, encoding: .utf8)
        var scanner = Scanner(sdk: try SDK(path: copy.path))
        scanner.log = { _ in }
        let manifest = try scanner.scan("Widget")
        #expect(manifest.skippedHeaders == ["Broken.h"])
        #expect(manifest.declarations.contains { $0.name == "initWithName:count:" })
    }
}
