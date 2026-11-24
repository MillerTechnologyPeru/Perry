import CacaoDBus
import Glibc
import PerryDesktopAppearance
import PerryObjCInterop

// NSAppearance: Aqua or Dark Aqua, as the desktop prefers, followed live.
// The system's is the freedesktop settings portal's org.freedesktop.appearance
// keys, read over D-Bus with Cacao's portal client: color-scheme, the
// accent-color NSColor's controlAccentColor takes, and contrast, which
// Increase Contrast's high-contrast appearances follow. Without a portal it
// is GNOME's org.gnome.desktop.interface color-scheme setting, else light.
// PERRY_APPKIT_APPEARANCE=dark or light fixes light or dark whatever the
// desktop says.
//
// When the desktop's appearance changes, the app hears it as on macOS: KVO
// of NSApp's and the windows' effectiveAppearance, views'
// -viewDidChangeEffectiveAppearance, NSSystemColorsDidChangeNotification,
// and the distributed AppleInterfaceThemeChangedNotification, and every
// window draws again. NSGlobalDomain's AppleInterfaceStyle is "Dark" while
// it is dark.
//
// As on macOS, a program built with an SDK before 10.14's, which predates
// Dark Aqua and draws for light only, or whose Info.plist sets
// NSRequiresAquaSystemAppearance, is always in Aqua.

enum Appearances {
    static let aqua = DesktopAppearance.aqua
    static let darkAqua = DesktopAppearance.darkAqua

    /// How long the first look at the appearance waits for the portal's
    /// answer, which follow() asked for as AppKit started. One later than
    /// that is taken as a change.
    static let firstReadWait = 1.5

    /// The portal's appearance and its changes.
    nonisolated(unsafe) private static var monitor: DesktopAppearanceMonitor?
    /// The desktop's appearance, once something asked for it.
    nonisolated(unsafe) private static var resolved: DesktopAppearance?
    /// Counts the desktop's changes, so colors resolved before one resolve
    /// again.
    nonisolated(unsafe) private(set) static var generation = 0

    /// Starts reading the portal as AppKit starts, so its answer is there
    /// by the time anything is drawn, and hearing its changes.
    static func follow() {
        guard monitor == nil else { return }
        monitor = DesktopAppearanceMonitor.start { portal in
            Dispatch.onMain { Appearances.portalChanged(portal) }
        }
    }

    /// The desktop's appearance: read when first asked for, then kept as
    /// the portal changes it.
    static var desktop: DesktopAppearance {
        if let resolved { return resolved }
        let portal = monitor?.current(waitingAtMost: firstReadWait)
        let desktop = resolve(portal)
        resolved = desktop
        publishInterfaceStyle(desktop)
        Trace.log("appearance: \(desktop.appearanceName), accent \(desktop.accent.map { "\($0.red) \($0.green) \($0.blue)" } ?? "none")"
                  + (portal == nil ? ", no portal" : ""))
        return desktop
    }

    /// Whether the desktop prefers dark.
    static var systemIsDark: Bool { desktop.dark }

    private static func resolve(_ portal: PortalAppearance?) -> DesktopAppearance {
        DesktopAppearance(portal: portal, override: getenv("PERRY_APPKIT_APPEARANCE").map { String(cString: $0) },
                          requiresAqua: requiresAqua,
                          gnomeColorScheme: { run((userHome.map { "HOME='\($0)' " } ?? "") + "gsettings get org.gnome.desktop.interface color-scheme") })
    }

    /// The user's home, from the password database: HOME is the app's
    /// container here, where dconf finds none of the user's settings.
    nonisolated(unsafe) private static let userHome: String? = {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        let home = String(cString: directory)
        return home.isEmpty || home.contains("'") ? nil : home
    }()

    /// Whether the program is held to Aqua: built with an SDK before macOS
    /// 10.14 (or before SDKs were recorded, 0), or asking for it in its
    /// Info.plist.
    nonisolated(unsafe) static let requiresAqua: Bool = {
        if let value = NSBundle.main().infoObject(forKey: "NSRequiresAquaSystemAppearance") {
            let asked = Send.bool(value.objcObject, "boolValue")
            if asked { return true }
        }
        guard let system = dlopen("libPerrySystem.so", RTLD_NOW | RTLD_NOLOAD),
              let symbol = dlsym(system, "_dyld_get_program_sdk_version") else { return false }
        let sdk = unsafeBitCast(symbol, to: (@convention(c) () -> UInt32).self)()
        return sdk < 0x000A_0E00   // 10.14
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

    // MARK: Changes

    /// The portal said something new: on the main thread.
    private static func portalChanged(_ portal: PortalAppearance) {
        // Not asked for yet: the first look takes the portal's latest.
        guard let old = resolved else { return }
        let new = resolve(portal)
        guard new != old else { return }
        changed(from: old, to: new)
    }

    /// Shows the desktop's new appearance and tells the app, as macOS does.
    static func changed(from old: DesktopAppearance, to new: DesktopAppearance) {
        let changes = new.changes(from: old)
        Trace.log("appearance changed to \(new.appearanceName), accent \(new.accent.map { "\($0.red) \($0.green) \($0.blue)" } ?? "none")")
        // The application's and the windows' effective appearance, where
        // they take the system's.
        let appTakesSystem = App.shared?.appearance == nil
        var observed: [NSObject] = appTakesSystem ? Windows.all.filter { $0.appearance == nil } : []
        if appTakesSystem, let app = App.shared { observed.insert(app, at: 0) }
        let key = "effectiveAppearance"
        for object in observed { Send.void(object.objcObject, "willChangeValueForKey:", key.objCArgument()) }
        resolved = new
        generation += 1
        if changes.contains(.colorScheme) { publishInterfaceStyle(new) }
        for object in observed { Send.void(object.objcObject, "didChangeValueForKey:", key.objCArgument()) }
        for window in Windows.all { window.systemAppearanceChanged() }
        Windows.layersChanged()

        post(Constants.NSSystemColorsDidChangeNotification, object: nil)
        if new.controlTint != old.controlTint { post("NSControlTintDidChangeNotification", object: nil) }
        if changes.contains(.colorScheme) { postDistributed("AppleInterfaceThemeChangedNotification") }
        if changes.contains(.accent) { postDistributed("AppleColorPreferencesChangedNotification") }
        if changes.contains(.contrast), let workspace = NSWorkspace.shared, let center = workspace.notificationCenter {
            Send.void(center.objcObject, "postNotificationName:object:",
                      "NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification".objCArgument(), workspace.objcObject)
        }
    }

    /// NSGlobalDomain's AppleInterfaceStyle, which apps read to tell dark
    /// from light: "Dark" while windows are dark, absent when they are
    /// light, as macOS keeps it. An app held to Aqua never sees "Dark", as
    /// it draws light whatever the desktop is. Set through Foundation's
    /// perry_foundation_set_global_default, where Foundation has it.
    private static func publishInterfaceStyle(_ desktop: DesktopAppearance) {
        typealias SetDefault = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
        let foundation = "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
        guard let symbol = Symbols.symbol(foundation, "perry_foundation_set_global_default") else { return }
        unsafeBitCast(symbol, to: SetDefault.self)("AppleInterfaceStyle", desktop.dark ? "Dark" : nil)
    }

    /// Posts to CoreFoundation's distributed center, whose observers are
    /// this process's: there are no other Mac apps to hear it.
    private static func postDistributed(_ name: String) {
        typealias Center = @convention(c) () -> UnsafeMutableRawPointer?
        typealias Post = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                         UnsafeMutableRawPointer?, UInt8) -> Void
        let coreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
        guard let center = Symbols.symbol(coreFoundation, "_CFNotificationCenterGetDistributedCenter"),
              let post = Symbols.symbol(coreFoundation, "_CFNotificationCenterPostNotification") else { return }
        unsafeBitCast(post, to: Post.self)(unsafeBitCast(center, to: Center.self)(), name.objCArgument(), nil, nil, 1)
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
    static var system: NSAppearance { appearance(named: Appearances.desktop.appearanceName) }

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
