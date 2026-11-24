public import CacaoDBus

// The desktop's look as a Mac app sees it: light or dark, the accent color
// controls are tinted with, and whether the user asked for more contrast.
// It comes from the freedesktop settings portal's org.freedesktop.appearance
// keys, which Cacao's CacaoDBus reads; without a portal, from GNOME's
// color-scheme setting; else light. Kept apart from AppKit so the mapping
// can be tested without an Objective-C runtime.

/// The desktop's appearance, in AppKit's terms.
public struct DesktopAppearance: Hashable, Sendable {

    /// An sRGB color, its components from 0 to 1.
    public struct Color: Hashable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
        }

        /// This color moved toward `other` by `fraction`.
        func mixed(with other: Color, _ fraction: Double) -> Color {
            Color(red: red + (other.red - red) * fraction, green: green + (other.green - green) * fraction,
                  blue: blue + (other.blue - blue) * fraction, alpha: alpha)
        }

        func with(alpha: Double) -> Color { Color(red: red, green: green, blue: blue, alpha: alpha) }
    }

    /// Whether windows are dark: Dark Aqua rather than Aqua.
    public var dark: Bool

    /// The desktop's accent color, when it has one; AppKit's blue otherwise.
    public var accent: Color?

    /// Whether the user asked for higher contrast.
    public var increasedContrast: Bool

    public init(dark: Bool = false, accent: Color? = nil, increasedContrast: Bool = false) {
        self.dark = dark
        self.accent = accent
        self.increasedContrast = increasedContrast
    }

    /// The appearance from what the desktop says.
    ///
    /// - Parameters:
    ///   - portal: The settings portal's appearance, or `nil` when there's
    ///     no portal.
    ///   - override: `PERRY_APPKIT_APPEARANCE`: a value with "dark" in it
    ///     makes windows dark, any other light, whatever the desktop says.
    ///   - requiresAqua: Whether the app is held to Aqua: built with an SDK
    ///     before 10.14's, which predates Dark Aqua, or asking for it in its
    ///     Info.plist. Its windows stay light, as on macOS.
    ///   - gnomeColorScheme: GNOME's org.gnome.desktop.interface
    ///     color-scheme ("'prefer-dark'"), asked only when the portal
    ///     doesn't say.
    public init(portal: PortalAppearance?, override: String? = nil, requiresAqua: Bool = false,
                gnomeColorScheme: () -> String? = { nil }) {
        if let override, !override.isEmpty {
            dark = override.lowercased().contains("dark")
        } else if requiresAqua {
            dark = false
        } else {
            switch portal?.colorScheme {
            case .dark?: dark = true
            // GNOME's portal serves its "default" as no preference, which
            // is light there, as it is in the portal's own words.
            case .light?, .noPreference?: dark = false
            case nil: dark = gnomeColorScheme()?.contains("prefer-dark") ?? false
            }
        }
        accent = portal?.accentColor.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        increasedContrast = portal?.contrast == .high
    }
}

// MARK: - AppKit's names and values

public extension DesktopAppearance {

    static let aqua = "NSAppearanceNameAqua"
    static let darkAqua = "NSAppearanceNameDarkAqua"
    static let highContrastAqua = "NSAppearanceNameAccessibilityHighContrastAqua"
    static let highContrastDarkAqua = "NSAppearanceNameAccessibilityHighContrastDarkAqua"

    /// The system appearance's name, as NSApp's effectiveAppearance has it:
    /// with Increase Contrast on, macOS's is the high-contrast variant.
    var appearanceName: String {
        switch (dark, increasedContrast) {
        case (false, false): Self.aqua
        case (true, false): Self.darkAqua
        case (false, true): Self.highContrastAqua
        case (true, true): Self.highContrastDarkAqua
        }
    }

    /// NSControlTint: NSBlueControlTint (1), or NSGraphiteControlTint (6)
    /// when the accent is a gray, as macOS's Graphite accent is.
    var controlTint: UInt {
        guard let accent else { return 1 }
        let spread = max(accent.red, accent.green, accent.blue) - min(accent.red, accent.green, accent.blue)
        return spread < 0.1 ? 6 : 1
    }

    /// The named system colors the accent tints, for the desktop's accent,
    /// in a dark appearance or a light one: `nil` for other names, and for
    /// every name when there's no accent, where AppKit's own blue colors
    /// stand.
    func accentColor(named name: String, dark: Bool) -> Color? {
        guard let accent else { return nil }
        switch name {
        case "controlAccentColor", "selectedContentBackgroundColor", "alternateSelectedControlColor":
            return accent
        case "keyboardFocusIndicatorColor":
            return accent.with(alpha: 0.5)
        // Selected text and controls show a pale accent in Aqua, a deep one
        // in Dark Aqua.
        case "selectedTextBackgroundColor", "selectedControlColor":
            return dark ? accent.mixed(with: Color(red: 0, green: 0, blue: 0), 0.45)
                : accent.mixed(with: Color(red: 1, green: 1, blue: 1), 0.7)
        default:
            return nil
        }
    }
}

// MARK: - Changes

public extension DesktopAppearance {

    /// What changed from `old` to this appearance, for the notifications an
    /// app hears.
    struct Changes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Light became dark or dark light: AppleInterfaceThemeChangedNotification.
        public static let colorScheme = Changes(rawValue: 1 << 0)
        /// The accent: NSControlTintDidChangeNotification when the tint did.
        public static let accent = Changes(rawValue: 1 << 1)
        /// Increase Contrast: NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification.
        public static let contrast = Changes(rawValue: 1 << 2)
    }

    func changes(from old: DesktopAppearance) -> Changes {
        var changes: Changes = []
        if dark != old.dark { changes.insert(.colorScheme) }
        if accent != old.accent { changes.insert(.accent) }
        if increasedContrast != old.increasedContrast { changes.insert(.contrast) }
        return changes
    }
}
