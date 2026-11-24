import CacaoDBus
import PerryDesktopAppearance
import Testing

/// How the settings portal's appearance becomes AppKit's: Aqua or Dark Aqua,
/// the accent colors and tint, and Increase Contrast.
@Suite("Desktop appearance")
struct DesktopAppearanceTests {
    private static let blue = PortalAppearance.AccentColor(red: 0.21, green: 0.52, blue: 0.89)
    private static let gray = PortalAppearance.AccentColor(red: 0.6, green: 0.6, blue: 0.62)

    @Test("The portal's color scheme decides light or dark")
    func colorScheme() {
        #expect(DesktopAppearance(portal: PortalAppearance(colorScheme: .dark)).dark)
        #expect(!DesktopAppearance(portal: PortalAppearance(colorScheme: .light)).dark)
        // GNOME's portal serves its "default" as no preference: light.
        #expect(!DesktopAppearance(portal: PortalAppearance(colorScheme: .noPreference)) { "'prefer-dark'" }.dark)
    }

    @Test("Without the portal's color scheme, GNOME's setting decides, else light")
    func gnomeFallback() {
        #expect(DesktopAppearance(portal: nil) { "'prefer-dark'\n" }.dark)
        #expect(!DesktopAppearance(portal: nil) { "'default'\n" }.dark)
        #expect(!DesktopAppearance(portal: nil) { "'prefer-light'\n" }.dark)
        #expect(!DesktopAppearance(portal: nil) { nil }.dark)
        #expect(!DesktopAppearance(portal: nil).dark)
        // A portal that serves only an accent.
        #expect(DesktopAppearance(portal: PortalAppearance(accentColor: Self.blue)) { "'prefer-dark'" }.dark)
    }

    @Test("GNOME's setting isn't asked when the portal says")
    func gnomeNotAsked() {
        var asked = false
        _ = DesktopAppearance(portal: PortalAppearance(colorScheme: .light)) {
            asked = true
            return "'prefer-dark'"
        }
        #expect(!asked)
    }

    @Test("An app built before the 10.14 SDK stays in Aqua")
    func requiresAqua() {
        let appearance = DesktopAppearance(portal: PortalAppearance(colorScheme: .dark, accentColor: Self.blue), requiresAqua: true)
        #expect(!appearance.dark)
        #expect(appearance.appearanceName == DesktopAppearance.aqua)
        // Its accent still follows the desktop.
        #expect(appearance.accent == DesktopAppearance.Color(red: 0.21, green: 0.52, blue: 0.89))
    }

    @Test("PERRY_APPKIT_APPEARANCE overrides the desktop and the SDK rule")
    func override() {
        #expect(DesktopAppearance(portal: PortalAppearance(colorScheme: .light), override: "dark").dark)
        #expect(DesktopAppearance(portal: nil, override: "Dark", requiresAqua: true).dark)
        #expect(!DesktopAppearance(portal: PortalAppearance(colorScheme: .dark), override: "light").dark)
        // Empty is unset.
        #expect(DesktopAppearance(portal: PortalAppearance(colorScheme: .dark), override: "").dark)
    }

    @Test("Appearance names, with Increase Contrast's variants")
    func names() {
        #expect(DesktopAppearance(dark: false).appearanceName == "NSAppearanceNameAqua")
        #expect(DesktopAppearance(dark: true).appearanceName == "NSAppearanceNameDarkAqua")
        #expect(DesktopAppearance(portal: PortalAppearance(colorScheme: .light, contrast: .high)).appearanceName
                == "NSAppearanceNameAccessibilityHighContrastAqua")
        #expect(DesktopAppearance(portal: PortalAppearance(colorScheme: .dark, contrast: .high)).appearanceName
                == "NSAppearanceNameAccessibilityHighContrastDarkAqua")
        #expect(!DesktopAppearance(portal: PortalAppearance(contrast: .normal)).increasedContrast)
    }

    @Test("The accent tints controlAccentColor and the selection colors")
    func accentColors() throws {
        let appearance = DesktopAppearance(portal: PortalAppearance(colorScheme: .light, accentColor: Self.blue))
        let accent = DesktopAppearance.Color(red: 0.21, green: 0.52, blue: 0.89)
        for name in ["controlAccentColor", "selectedContentBackgroundColor", "alternateSelectedControlColor"] {
            #expect(appearance.accentColor(named: name, dark: false) == accent)
            #expect(appearance.accentColor(named: name, dark: true) == accent)
        }
        #expect(appearance.accentColor(named: "keyboardFocusIndicatorColor", dark: false)?.alpha == 0.5)

        // Selected text: pale in Aqua, deep in Dark Aqua.
        let light = try #require(appearance.accentColor(named: "selectedTextBackgroundColor", dark: false))
        let dark = try #require(appearance.accentColor(named: "selectedTextBackgroundColor", dark: true))
        #expect(light.red > accent.red && light.green > accent.green && light.blue > accent.blue)
        #expect(dark.red < accent.red && dark.green < accent.green && dark.blue < accent.blue)
        #expect(abs(light.blue - (0.89 + 0.11 * 0.7)) < 1e-9)

        // Other colors, systemBlueColor among them, keep AppKit's.
        #expect(appearance.accentColor(named: "systemBlueColor", dark: false) == nil)
        #expect(appearance.accentColor(named: "textColor", dark: false) == nil)
    }

    @Test("Without an accent, AppKit's blue colors stand")
    func noAccent() {
        let appearance = DesktopAppearance(portal: PortalAppearance(colorScheme: .dark))
        #expect(appearance.accent == nil)
        #expect(appearance.accentColor(named: "controlAccentColor", dark: true) == nil)
        #expect(appearance.controlTint == 1)
    }

    @Test("A gray accent is the graphite tint, any other blue")
    func controlTint() {
        #expect(DesktopAppearance(portal: PortalAppearance(accentColor: Self.blue)).controlTint == 1)
        #expect(DesktopAppearance(portal: PortalAppearance(accentColor: Self.gray)).controlTint == 6)
        #expect(DesktopAppearance(portal: PortalAppearance(accentColor: .init(red: 0.9, green: 0.2, blue: 0.3))).controlTint == 1)
    }

    @Test("Changes name what an app is told about")
    func changes() {
        let light = DesktopAppearance(dark: false)
        #expect(DesktopAppearance(dark: true).changes(from: light) == .colorScheme)
        #expect(DesktopAppearance(dark: false, accent: .init(red: 1, green: 0, blue: 0)).changes(from: light) == .accent)
        #expect(DesktopAppearance(dark: false, increasedContrast: true).changes(from: light) == .contrast)
        #expect(light.changes(from: light).isEmpty)
        #expect(DesktopAppearance(dark: true, accent: .init(red: 1, green: 0, blue: 0), increasedContrast: true).changes(from: light)
                == [.colorScheme, .accent, .contrast])
    }
}
