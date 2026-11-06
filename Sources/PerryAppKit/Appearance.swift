import Glibc
import PerryObjCInterop

// NSAppearance: Aqua or Dark Aqua, as the desktop prefers. The system's is
// the desktop's color scheme: the freedesktop portal's
// org.freedesktop.appearance color-scheme (1 dark, 2 light), else GNOME's
// org.gnome.desktop.interface color-scheme setting, else light.
// PERRY_APPKIT_APPEARANCE=dark or light overrides both.

enum Appearances {
    static let aqua = "NSAppearanceNameAqua"
    static let darkAqua = "NSAppearanceNameDarkAqua"

    /// Whether the desktop prefers dark, read once.
    nonisolated(unsafe) static let systemIsDark: Bool = {
        if let setting = getenv("PERRY_APPKIT_APPEARANCE").map({ String(cString: $0).lowercased() }), !setting.isEmpty {
            return setting.contains("dark")
        }
        let portal = run("gdbus call --session --timeout 2 --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop "
                         + "--method org.freedesktop.portal.Settings.ReadOne org.freedesktop.appearance color-scheme")
        if portal.contains("uint32 1") { return true }
        if portal.contains("uint32 2") { return false }
        let gnome = run("gsettings get org.gnome.desktop.interface color-scheme")
        if gnome.contains("prefer-dark") { return true }
        if gnome.contains("prefer-light") || gnome.contains("default") { return false }
        return false
    }()

    /// A command's output, or "" when it can't run.
    private static func run(_ command: String) -> String {
        guard let pipe = popen(command + " 2>/dev/null", "r") else { return "" }
        defer { pclose(pipe) }
        var output = ""
        var buffer = [CChar](repeating: 0, count: 256)
        while fgets(&buffer, Int32(buffer.count), pipe) != nil { output += String(cString: buffer) }
        return output
    }

    /// The appearance drawing happens in: the current one, else the system's.
    static var currentIsDark: Bool {
        if let current = NSAppearance.current { return current.name == darkAqua || current.name.contains("Dark") }
        return systemIsDark
    }
}

@ObjCClass("NSAppearance")
open class NSAppearance: NSObject {
    nonisolated(unsafe) static var current: NSAppearance?
    nonisolated(unsafe) static var named: [String: NSAppearance] = [:]
    var name = Appearances.aqua

    @ObjCMethod("init")
    public required override init() { super.init() }

    static func appearance(named name: String) -> NSAppearance {
        if let appearance = named[name] { return appearance }
        let appearance = NSAppearance()
        appearance.name = name
        named[name] = appearance
        return appearance
    }

    /// The desktop's appearance.
    static var system: NSAppearance { appearance(named: Appearances.systemIsDark ? Appearances.darkAqua : Appearances.aqua) }

    @ObjCClassMethod("appearanceNamed:")
    static func appearanceNamed(_ name: String?) -> NSAppearance? {
        guard let name else { return nil }
        // The vibrant and high-contrast variants are drawn as their base.
        return appearance(named: name)
    }

    @ObjCClassMethod("currentAppearance") static func currentAppearance() -> NSAppearance { current ?? system }
    @ObjCClassMethod("setCurrentAppearance:") static func setCurrentAppearance(_ appearance: NSAppearance?) { current = appearance }
    @ObjCClassMethod("currentDrawingAppearance") static func currentDrawingAppearance() -> NSAppearance { current ?? system }

    @ObjCMethod("name") func appearanceName() -> String { name }
    @ObjCMethod("allowsVibrancy") func allowsVibrancy() -> Bool { name.contains("Vibrant") }

    /// The name among `names` that suits this appearance best: its own, or
    /// the dark or light one it is a variant of.
    @ObjCMethod("bestMatchFromAppearancesWithNames:")
    func bestMatch(fromAppearancesWithNames names: NSObject?) -> String? {
        let candidates = names?.as(NSArray.self)?.elements.compactMap { $0.stringValue } ?? []
        if Trace.enabled { Trace.log("appearance \(name): best of \(candidates)") }
        if candidates.contains(name) { return name }
        let dark = name.contains("Dark")
        return candidates.first { $0.contains("Dark") == dark } ?? candidates.first
    }

    /// Runs the block with this appearance current, as drawing for a view
    /// does.
    @ObjCMethod("performAsCurrentDrawingAppearance:")
    func performAsCurrentDrawingAppearance(_ block: ObjCBlock?) {
        let saved = NSAppearance.current
        NSAppearance.current = self
        if let block { Blocks.call(block) }
        NSAppearance.current = saved
    }
}
