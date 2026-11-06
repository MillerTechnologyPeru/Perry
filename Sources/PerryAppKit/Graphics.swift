import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSColor, NSFont, NSImage, NSGraphicsContext and NSBezierPath. Colors keep
// their components and set themselves in the current context; fonts their
// name, size and traits, which text is measured and drawn in through
// CoreGraphics; images the bitmap ImageIO decodes from their file or data.
// The current context is the one a view draws its layer into.

@ObjCClass("NSColor")
open class NSColor: NSObject {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
    /// A system color's name: "System", "controlTextColor".
    var catalogName: String?
    var colorName: String?
    private var cgColor: CGRef?

    @ObjCMethod("init")
    public required override init() { super.init() }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        super.init()
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    convenience init(white: CGFloat, alpha: CGFloat) { self.init(red: white, green: white, blue: white, alpha: alpha) }

    /// A system color, under its catalog name.
    convenience init(named name: String, white: CGFloat, alpha: CGFloat = 1) {
        self.init(named: name, red: white, green: white, blue: white, alpha: alpha)
    }

    convenience init(named name: String, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
        (catalogName, colorName) = ("System", name)
    }

    /// NSColor's keyed archive: NSColorSpace 1 and 2 are RGB ("NSRGB": "r g
    /// b a"), 3 and 4 gray ("NSWhite": "w a"), 5 a CMYK or custom space's
    /// components, 6 a catalog color by name, with its value under
    /// "NSColor"; 10 and 11 a component list ("NSComponents").
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        func numbers(_ key: String) -> [CGFloat] {
            guard let bytes = decoded.bytes(key) else { return [] }
            return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
        }
        switch decoded.integer("NSColorSpace") {
        case 1, 2:
            let v = numbers("NSRGB")
            if v.count >= 3 { (red, green, blue, alpha) = (v[0], v[1], v[2], v.count > 3 ? v[3] : 1) }
        case 3, 4:
            let v = numbers("NSWhite")
            if let white = v.first { (red, green, blue, alpha) = (white, white, white, v.count > 1 ? v[1] : 1) }
        case 6:
            catalogName = decoded.string("NSCatalogName")
            colorName = decoded.string("NSColorName")
            if let name = colorName, let system = NSColor.system(name) {
                (red, green, blue, alpha) = (system.red, system.green, system.blue, system.alpha)
                resolvedDark = Appearances.currentIsDark
            } else if let fallback = decoded.object("NSColor")?.as(NSColor.self) {
                (red, green, blue, alpha) = (fallback.red, fallback.green, fallback.blue, fallback.alpha)
            }
        default:
            let v = numbers("NSComponents")
            if v.count >= 4 { (red, green, blue, alpha) = (v[0], v[1], v[2], v[3]) } else if v.count >= 2 {
                (red, green, blue, alpha) = (v[0], v[0], v[0], v[1])
            } else if let fallback = numbers("NSRGB").first {
                (red, green, blue) = (fallback, fallback, fallback)
            }
        }
    }

    deinit { if let cgColor { CG.release(cgColor) } }

    /// For a system color from a nib, the appearance its components are
    /// for: it takes the current one's when drawn, as AppKit's dynamic
    /// colors do.
    var resolvedDark: Bool?

    /// The color as a CGColor, made once (again when a system color's
    /// appearance changes).
    var cgColorRef: CGRef? {
        if let dark = resolvedDark, dark != Appearances.currentIsDark, let name = colorName, let system = NSColor.system(name) {
            (red, green, blue, alpha) = (system.red, system.green, system.blue, system.alpha)
            resolvedDark = Appearances.currentIsDark
            if let cgColor { CG.release(cgColor) }
            cgColor = nil
        }
        if let cgColor { return cgColor }
        guard CG.ready else { return nil }
        cgColor = CG.colorCreateSRGB(red, green, blue, alpha)
        return cgColor
    }

    @ObjCClassMethod("colorWithRed:green:blue:alpha:")
    static func color(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCClassMethod("colorWithSRGBRed:green:blue:alpha:")
    static func color(sRGBRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCClassMethod("colorWithCalibratedRed:green:blue:alpha:")
    static func color(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCClassMethod("colorWithDeviceRed:green:blue:alpha:")
    static func color(deviceRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCClassMethod("colorWithDisplayP3Red:green:blue:alpha:")
    static func color(displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCClassMethod("colorWithWhite:alpha:")
    static func color(white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(white: white, alpha: alpha) }
    @ObjCClassMethod("colorWithCalibratedWhite:alpha:")
    static func color(calibratedWhite white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(white: white, alpha: alpha) }
    @ObjCClassMethod("colorWithDeviceWhite:alpha:")
    static func color(deviceWhite white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(white: white, alpha: alpha) }
    @ObjCClassMethod("colorWithGenericGamma22White:alpha:")
    static func color(gamma22White white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(white: white, alpha: alpha) }
    @ObjCClassMethod("colorWithHue:saturation:brightness:alpha:")
    static func color(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) -> NSColor {
        let (r, g, b) = HSB.rgb(hue: hue, saturation: saturation, brightness: brightness)
        return NSColor(red: r, green: g, blue: b, alpha: alpha)
    }
    @ObjCClassMethod("colorWithCalibratedHue:saturation:brightness:alpha:")
    static func color(calibratedHue hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) -> NSColor {
        color(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
    @ObjCClassMethod("colorWithCGColor:")
    static func color(cgColor: UnsafeMutableRawPointer?) -> NSColor? {
        guard let cgColor, CG.ready, let components = CG.colorGetComponents(cgColor) else { return nil }
        let count = CG.colorGetNumberOfComponents(cgColor)
        if count >= 4 { return NSColor(red: components[0], green: components[1], blue: components[2], alpha: components[3]) }
        if count == 2 { return NSColor(white: components[0], alpha: components[1]) }
        return nil
    }
    @ObjCClassMethod("colorWithPatternImage:") static func color(patternImage: NSObject?) -> NSColor { NSColor(white: 0.9, alpha: 1) }
    /// A system color by name, else the app's asset catalog's.
    @ObjCClassMethod("colorNamed:")
    static func color(named name: String?) -> NSColor? { name.flatMap { system($0) ?? AppKitAssets.color(named: $0) } }
    @ObjCClassMethod("colorNamed:bundle:")
    static func color(named name: String?, bundle: NSObject?) -> NSColor? { color(named: name) }
    @ObjCClassMethod("colorWithCatalogName:colorName:")
    static func color(catalogName: String?, colorName: String?) -> NSColor? { colorName.flatMap(system) }

    /// The system's named colors in macOS's dark appearance, where they
    /// differ from the light one's.
    static let darkSystemColors: [String: (CGFloat, CGFloat, CGFloat, CGFloat)] = {
        let accent: (CGFloat, CGFloat, CGFloat) = (0.04, 0.52, 1.0)
        return [
            "windowBackgroundColor": (0.196, 0.196, 0.196, 1), "underPageBackgroundColor": (0.157, 0.157, 0.157, 1),
            "controlColor": (1, 1, 1, 0.25), "controlBackgroundColor": (0.118, 0.118, 0.118, 1), "textBackgroundColor": (0.118, 0.118, 0.118, 1),
            "controlTextColor": (1, 1, 1, 0.85), "textColor": (1, 1, 1, 1), "labelColor": (1, 1, 1, 0.85),
            "secondaryLabelColor": (1, 1, 1, 0.55), "tertiaryLabelColor": (1, 1, 1, 0.25), "quaternaryLabelColor": (1, 1, 1, 0.1),
            "disabledControlTextColor": (1, 1, 1, 0.25), "placeholderTextColor": (1, 1, 1, 0.25),
            "headerColor": (0.118, 0.118, 0.118, 1), "headerTextColor": (1, 1, 1, 0.85), "gridColor": (0.1, 0.1, 0.1, 1),
            "separatorColor": (1, 1, 1, 0.1), "windowFrameColor": (0.2, 0.2, 0.2, 1), "windowFrameTextColor": (1, 1, 1, 0.85),
            "selectedTextBackgroundColor": (0.25, 0.39, 0.55, 1), "selectedTextColor": (1, 1, 1, 1),
            "selectedContentBackgroundColor": (accent.0, accent.1, accent.2, 1), "selectedControlColor": (0.25, 0.39, 0.55, 1),
            "selectedControlTextColor": (1, 1, 1, 0.85), "alternateSelectedControlColor": (accent.0, accent.1, accent.2, 1),
            "unemphasizedSelectedContentBackgroundColor": (0.27, 0.27, 0.27, 1),
            "unemphasizedSelectedTextBackgroundColor": (0.27, 0.27, 0.27, 1), "unemphasizedSelectedTextColor": (1, 1, 1, 1),
            "keyboardFocusIndicatorColor": (accent.0, accent.1, accent.2, 0.5), "controlAccentColor": (accent.0, accent.1, accent.2, 1),
            "linkColor": (0.2, 0.6, 1, 1), "scrollBarColor": (0.4, 0.4, 0.4, 1), "knobColor": (1, 1, 1, 0.5),
            "selectedKnobColor": (1, 1, 1, 0.6), "highlightColor": (1, 1, 1, 0.25), "controlShadowColor": (0, 0, 0, 1),
            "controlHighlightColor": (1, 1, 1, 0.25), "controlLightHighlightColor": (1, 1, 1, 0.25),
            "systemBlueColor": (accent.0, accent.1, accent.2, 1), "systemRedColor": (1, 0.27, 0.23, 1),
            "systemGreenColor": (0.19, 0.82, 0.35, 1), "systemOrangeColor": (1, 0.62, 0.04, 1), "systemYellowColor": (1, 0.84, 0.04, 1),
            "systemPinkColor": (1, 0.22, 0.37, 1), "systemPurpleColor": (0.75, 0.35, 0.95, 1), "systemTealColor": (0.39, 0.82, 1, 1),
            "systemIndigoColor": (0.37, 0.36, 0.9, 1), "systemBrownColor": (0.67, 0.56, 0.4, 1), "systemMintColor": (0.4, 0.83, 0.81, 1),
            "systemCyanColor": (0.35, 0.78, 0.98, 1), "systemGrayColor": (0.6, 0.6, 0.62, 1),
            "systemFillColor": (1, 1, 1, 0.1), "secondarySystemFillColor": (1, 1, 1, 0.08), "tertiarySystemFillColor": (1, 1, 1, 0.05),
        ]
    }()

    /// The system's named colors, in the current appearance: macOS's light
    /// one, or its dark one when the desktop prefers dark.
    static func system(_ name: String) -> NSColor? {
        if Appearances.currentIsDark, let value = darkSystemColors[name] {
            return NSColor(named: name, red: value.0, green: value.1, blue: value.2, alpha: value.3)
        }
        let accent = (0.0, 0.48, 1.0)
        let values: [String: (CGFloat, CGFloat, CGFloat, CGFloat)] = [
            "clearColor": (0, 0, 0, 0), "blackColor": (0, 0, 0, 1), "whiteColor": (1, 1, 1, 1),
            "grayColor": (0.5, 0.5, 0.5, 1), "lightGrayColor": (2.0 / 3, 2.0 / 3, 2.0 / 3, 1), "darkGrayColor": (1.0 / 3, 1.0 / 3, 1.0 / 3, 1),
            "redColor": (1, 0, 0, 1), "greenColor": (0, 1, 0, 1), "blueColor": (0, 0, 1, 1), "yellowColor": (1, 1, 0, 1),
            "orangeColor": (1, 0.5, 0, 1), "brownColor": (0.6, 0.4, 0.2, 1), "purpleColor": (0.5, 0, 0.5, 1),
            "cyanColor": (0, 1, 1, 1), "magentaColor": (1, 0, 1, 1),
            "windowBackgroundColor": (0.925, 0.925, 0.925, 1), "underPageBackgroundColor": (0.59, 0.59, 0.59, 1),
            "controlColor": (1, 1, 1, 1), "controlBackgroundColor": (1, 1, 1, 1), "textBackgroundColor": (1, 1, 1, 1),
            "controlTextColor": (0, 0, 0, 0.85), "textColor": (0, 0, 0, 1), "labelColor": (0, 0, 0, 0.85),
            "secondaryLabelColor": (0, 0, 0, 0.5), "tertiaryLabelColor": (0, 0, 0, 0.26), "quaternaryLabelColor": (0, 0, 0, 0.1),
            "disabledControlTextColor": (0, 0, 0, 0.25), "placeholderTextColor": (0, 0, 0, 0.25),
            "headerColor": (1, 1, 1, 1), "headerTextColor": (0, 0, 0, 0.85), "gridColor": (0.9, 0.9, 0.9, 1),
            "separatorColor": (0, 0, 0, 0.1), "windowFrameColor": (0.67, 0.67, 0.67, 1), "windowFrameTextColor": (0, 0, 0, 0.85),
            "selectedTextBackgroundColor": (0.7, 0.84, 1, 1), "selectedTextColor": (0, 0, 0, 1),
            "selectedContentBackgroundColor": (accent.0, accent.1, accent.2, 1), "selectedControlColor": (0.7, 0.84, 1, 1),
            "selectedControlTextColor": (0, 0, 0, 0.85), "alternateSelectedControlColor": (accent.0, accent.1, accent.2, 1),
            "alternateSelectedControlTextColor": (1, 1, 1, 1), "unemphasizedSelectedContentBackgroundColor": (0.86, 0.86, 0.86, 1),
            "unemphasizedSelectedTextBackgroundColor": (0.86, 0.86, 0.86, 1), "unemphasizedSelectedTextColor": (0, 0, 0, 1),
            "selectedMenuItemTextColor": (1, 1, 1, 1), "keyboardFocusIndicatorColor": (accent.0, accent.1, accent.2, 0.5),
            "controlAccentColor": (accent.0, accent.1, accent.2, 1), "linkColor": (0, 0.41, 0.85, 1),
            "scrollBarColor": (0.67, 0.67, 0.67, 1), "knobColor": (0, 0, 0, 0.5), "selectedKnobColor": (0, 0, 0, 0.6),
            "shadowColor": (0, 0, 0, 1), "highlightColor": (1, 1, 1, 1), "controlShadowColor": (0.5, 0.5, 0.5, 1),
            "controlDarkShadowColor": (0, 0, 0, 1), "controlHighlightColor": (1, 1, 1, 1), "controlLightHighlightColor": (1, 1, 1, 1),
            "findHighlightColor": (1, 1, 0, 1),
            "systemBlueColor": (accent.0, accent.1, accent.2, 1), "systemRedColor": (1, 0.23, 0.19, 1),
            "systemGreenColor": (0.16, 0.8, 0.25, 1), "systemOrangeColor": (1, 0.58, 0, 1), "systemYellowColor": (1, 0.8, 0, 1),
            "systemPinkColor": (1, 0.18, 0.33, 1), "systemPurpleColor": (0.69, 0.32, 0.87, 1), "systemTealColor": (0.35, 0.78, 0.98, 1),
            "systemIndigoColor": (0.35, 0.34, 0.84, 1), "systemBrownColor": (0.64, 0.52, 0.37, 1), "systemMintColor": (0, 0.78, 0.75, 1),
            "systemCyanColor": (0.33, 0.75, 0.94, 1), "systemGrayColor": (0.56, 0.56, 0.58, 1),
            "systemFillColor": (0, 0, 0, 0.1), "secondarySystemFillColor": (0, 0, 0, 0.08), "tertiarySystemFillColor": (0, 0, 0, 0.05),
        ]
        guard let value = values[name] else { return nil }
        return NSColor(named: name, red: value.0, green: value.1, blue: value.2, alpha: value.3)
    }

    @ObjCClassMethod("clearColor") static func clearColor() -> NSColor { system("clearColor")! }
    @ObjCClassMethod("blackColor") static func blackColor() -> NSColor { system("blackColor")! }
    @ObjCClassMethod("whiteColor") static func whiteColor() -> NSColor { system("whiteColor")! }
    @ObjCClassMethod("grayColor") static func grayColor() -> NSColor { system("grayColor")! }
    @ObjCClassMethod("lightGrayColor") static func lightGrayColor() -> NSColor { system("lightGrayColor")! }
    @ObjCClassMethod("darkGrayColor") static func darkGrayColor() -> NSColor { system("darkGrayColor")! }
    @ObjCClassMethod("redColor") static func redColor() -> NSColor { system("redColor")! }
    @ObjCClassMethod("greenColor") static func greenColor() -> NSColor { system("greenColor")! }
    @ObjCClassMethod("blueColor") static func blueColor() -> NSColor { system("blueColor")! }
    @ObjCClassMethod("yellowColor") static func yellowColor() -> NSColor { system("yellowColor")! }
    @ObjCClassMethod("orangeColor") static func orangeColor() -> NSColor { system("orangeColor")! }
    @ObjCClassMethod("brownColor") static func brownColor() -> NSColor { system("brownColor")! }
    @ObjCClassMethod("purpleColor") static func purpleColor() -> NSColor { system("purpleColor")! }
    @ObjCClassMethod("cyanColor") static func cyanColor() -> NSColor { system("cyanColor")! }
    @ObjCClassMethod("magentaColor") static func magentaColor() -> NSColor { system("magentaColor")! }
    @ObjCClassMethod("windowBackgroundColor") static func windowBackgroundColor() -> NSColor { system("windowBackgroundColor")! }
    @ObjCClassMethod("underPageBackgroundColor") static func underPageBackgroundColor() -> NSColor { system("underPageBackgroundColor")! }
    @ObjCClassMethod("controlColor") static func controlColor() -> NSColor { system("controlColor")! }
    @ObjCClassMethod("controlBackgroundColor") static func controlBackgroundColor() -> NSColor { system("controlBackgroundColor")! }
    @ObjCClassMethod("textColor") static func textColor() -> NSColor { system("textColor")! }
    @ObjCClassMethod("controlTextColor") static func controlTextColor() -> NSColor { system("controlTextColor")! }
    @ObjCClassMethod("disabledControlTextColor") static func disabledControlTextColor() -> NSColor { system("disabledControlTextColor")! }
    @ObjCClassMethod("labelColor") static func labelColor() -> NSColor { system("labelColor")! }
    @ObjCClassMethod("secondaryLabelColor") static func secondaryLabelColor() -> NSColor { system("secondaryLabelColor")! }
    @ObjCClassMethod("tertiaryLabelColor") static func tertiaryLabelColor() -> NSColor { system("tertiaryLabelColor")! }
    @ObjCClassMethod("quaternaryLabelColor") static func quaternaryLabelColor() -> NSColor { system("quaternaryLabelColor")! }
    @ObjCClassMethod("placeholderTextColor") static func placeholderTextColor() -> NSColor { system("placeholderTextColor")! }
    @ObjCClassMethod("textBackgroundColor") static func textBackgroundColor() -> NSColor { system("textBackgroundColor")! }
    @ObjCClassMethod("selectedTextBackgroundColor") static func selectedTextBackgroundColor() -> NSColor { system("selectedTextBackgroundColor")! }
    @ObjCClassMethod("selectedTextColor") static func selectedTextColor() -> NSColor { system("selectedTextColor")! }
    @ObjCClassMethod("selectedContentBackgroundColor") static func selectedContentBackgroundColor() -> NSColor { system("selectedContentBackgroundColor")! }
    @ObjCClassMethod("unemphasizedSelectedContentBackgroundColor")
    static func unemphasizedSelectedContentBackgroundColor() -> NSColor { system("unemphasizedSelectedContentBackgroundColor")! }
    @ObjCClassMethod("selectedControlColor") static func selectedControlColor() -> NSColor { system("selectedControlColor")! }
    @ObjCClassMethod("selectedControlTextColor") static func selectedControlTextColor() -> NSColor { system("selectedControlTextColor")! }
    @ObjCClassMethod("alternateSelectedControlColor") static func alternateSelectedControlColor() -> NSColor { system("alternateSelectedControlColor")! }
    @ObjCClassMethod("alternateSelectedControlTextColor")
    static func alternateSelectedControlTextColor() -> NSColor { system("alternateSelectedControlTextColor")! }
    @ObjCClassMethod("headerColor") static func headerColor() -> NSColor { system("headerColor")! }
    @ObjCClassMethod("headerTextColor") static func headerTextColor() -> NSColor { system("headerTextColor")! }
    @ObjCClassMethod("gridColor") static func gridColor() -> NSColor { system("gridColor")! }
    @ObjCClassMethod("separatorColor") static func separatorColor() -> NSColor { system("separatorColor")! }
    @ObjCClassMethod("linkColor") static func linkColor() -> NSColor { system("linkColor")! }
    @ObjCClassMethod("shadowColor") static func shadowColor() -> NSColor { system("shadowColor")! }
    @ObjCClassMethod("highlightColor") static func highlightColor() -> NSColor { system("highlightColor")! }
    @ObjCClassMethod("keyboardFocusIndicatorColor") static func keyboardFocusIndicatorColor() -> NSColor { system("keyboardFocusIndicatorColor")! }
    @ObjCClassMethod("controlAccentColor") static func controlAccentColor() -> NSColor { system("controlAccentColor")! }
    @ObjCClassMethod("windowFrameColor") static func windowFrameColor() -> NSColor { system("windowFrameColor")! }
    @ObjCClassMethod("scrollBarColor") static func scrollBarColor() -> NSColor { system("scrollBarColor")! }
    @ObjCClassMethod("systemBlueColor") static func systemBlueColor() -> NSColor { system("systemBlueColor")! }
    @ObjCClassMethod("systemRedColor") static func systemRedColor() -> NSColor { system("systemRedColor")! }
    @ObjCClassMethod("systemGreenColor") static func systemGreenColor() -> NSColor { system("systemGreenColor")! }
    @ObjCClassMethod("systemOrangeColor") static func systemOrangeColor() -> NSColor { system("systemOrangeColor")! }
    @ObjCClassMethod("systemYellowColor") static func systemYellowColor() -> NSColor { system("systemYellowColor")! }
    @ObjCClassMethod("systemPinkColor") static func systemPinkColor() -> NSColor { system("systemPinkColor")! }
    @ObjCClassMethod("systemPurpleColor") static func systemPurpleColor() -> NSColor { system("systemPurpleColor")! }
    @ObjCClassMethod("systemTealColor") static func systemTealColor() -> NSColor { system("systemTealColor")! }
    @ObjCClassMethod("systemIndigoColor") static func systemIndigoColor() -> NSColor { system("systemIndigoColor")! }
    @ObjCClassMethod("systemBrownColor") static func systemBrownColor() -> NSColor { system("systemBrownColor")! }
    @ObjCClassMethod("systemGrayColor") static func systemGrayColor() -> NSColor { system("systemGrayColor")! }
    @ObjCClassMethod("systemMintColor") static func systemMintColor() -> NSColor { system("systemMintColor")! }
    @ObjCClassMethod("systemCyanColor") static func systemCyanColor() -> NSColor { system("systemCyanColor")! }
    @ObjCClassMethod("systemFillColor") static func systemFillColor() -> NSColor { system("systemFillColor")! }
    @ObjCClassMethod("alternatingContentBackgroundColors")
    static func alternatingContentBackgroundColors() -> NSObject { NSMutableArray.of([whiteColor(), NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)]) }
    @ObjCClassMethod("controlAlternatingRowBackgroundColors")
    static func controlAlternatingRowBackgroundColors() -> NSObject { alternatingContentBackgroundColors() }
    @ObjCClassMethod("currentControlTint") static func currentControlTint() -> UInt { 1 }

    @ObjCMethod("redComponent") func redComponent() -> CGFloat { red }
    @ObjCMethod("greenComponent") func greenComponent() -> CGFloat { green }
    @ObjCMethod("blueComponent") func blueComponent() -> CGFloat { blue }
    @ObjCMethod("alphaComponent") func alphaComponent() -> CGFloat { alpha }
    @ObjCMethod("whiteComponent") func whiteComponent() -> CGFloat { (red + green + blue) / 3 }
    @ObjCMethod("hueComponent") func hueComponent() -> CGFloat { HSB.hsb(red, green, blue).0 }
    @ObjCMethod("saturationComponent") func saturationComponent() -> CGFloat { HSB.hsb(red, green, blue).1 }
    @ObjCMethod("brightnessComponent") func brightnessComponent() -> CGFloat { HSB.hsb(red, green, blue).2 }
    @ObjCMethod("numberOfComponents") func numberOfComponents() -> Int { 4 }
    @ObjCMethod("getRed:green:blue:alpha:")
    func get(red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?,
             alpha: UnsafeMutablePointer<CGFloat>?) {
        red?.pointee = self.red
        green?.pointee = self.green
        blue?.pointee = self.blue
        alpha?.pointee = self.alpha
    }
    @ObjCMethod("getWhite:alpha:")
    func get(white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        white?.pointee = whiteComponent()
        alpha?.pointee = self.alpha
    }
    @ObjCMethod("getHue:saturation:brightness:alpha:")
    func get(hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?, brightness: UnsafeMutablePointer<CGFloat>?,
             alpha: UnsafeMutablePointer<CGFloat>?) {
        let value = HSB.hsb(red, green, blue)
        hue?.pointee = value.0
        saturation?.pointee = value.1
        brightness?.pointee = value.2
        alpha?.pointee = self.alpha
    }
    @ObjCMethod("colorWithAlphaComponent:")
    func withAlphaComponent(_ alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCMethod("blendedColorWithFraction:ofColor:")
    func blended(fraction: CGFloat, of other: NSColor?) -> NSColor? {
        guard let other else { return nil }
        let f = max(0, min(1, fraction))
        return NSColor(red: red + (other.red - red) * f, green: green + (other.green - green) * f, blue: blue + (other.blue - blue) * f,
                       alpha: alpha + (other.alpha - alpha) * f)
    }
    @ObjCMethod("highlightWithLevel:") func highlight(level: CGFloat) -> NSColor? { blended(fraction: level, of: NSColor.whiteColor()) }
    @ObjCMethod("shadowWithLevel:") func shadow(level: CGFloat) -> NSColor? { blended(fraction: level, of: NSColor.blackColor()) }
    @ObjCMethod("colorUsingColorSpace:") func usingColorSpace(_ space: NSObject?) -> NSColor? { self }
    @ObjCMethod("colorUsingColorSpaceName:") func usingColorSpaceName(_ name: NSObject?) -> NSColor? { self }
    @ObjCMethod("colorUsingType:") func usingType(_ type: Int) -> NSColor? { self }
    @ObjCMethod("colorSpaceName") func colorSpaceName() -> String { Constants.NSCalibratedRGBColorSpace }
    @ObjCMethod("colorSpace") func colorSpace() -> NSObject? { NSColorSpace.sRGBColorSpace() }
    @ObjCMethod("type") func colorType() -> Int { catalogName == nil ? 0 : 2 }
    @ObjCMethod("catalogNameComponent") func catalogNameComponent() -> String? { catalogName }
    @ObjCMethod("colorNameComponent") func colorNameComponent() -> String? { colorName }
    @ObjCMethod("localizedColorNameComponent") func localizedColorNameComponent() -> String? { colorName }
    @ObjCMethod("CGColor") func cgColorObject() -> UnsafeMutableRawPointer? { cgColorRef }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(NSColor.self) else { return false }
        return other.red == red && other.green == green && other.blue == blue && other.alpha == alpha
    }
    @ObjCMethod("hash") func colorHash() -> UInt { UInt(truncatingIfNeeded: Int(red * 255) << 24 | Int(green * 255) << 16 | Int(blue * 255) << 8 | Int(alpha * 255)) }
    @ObjCMethod("description")
    func colorDescription() -> String {
        if let colorName { return "Catalog color: \(catalogName ?? "System") \(colorName)" }
        return "sRGB IEEE61966-2.1 colorspace \(red) \(green) \(blue) \(alpha)"
    }

    /// The fill and stroke color of the current context.
    @ObjCMethod("set") func set() { setFill(); setStroke() }
    @ObjCMethod("setFill")
    func setFill() {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.setFillColorWithColor(context, cgColorRef)
    }
    @ObjCMethod("setStroke")
    func setStroke() {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.setStrokeColorWithColor(context, cgColorRef)
    }
    @ObjCMethod("drawSwatchInRect:")
    func drawSwatch(in rect: CGRect) {
        guard let context = NSGraphicsContext.currentCG else { return }
        CG.saveGState(context)
        CG.setFillColorWithColor(context, cgColorRef)
        CG.fillRect(context, rect)
        CG.restoreGState(context)
    }
}

/// Hue, saturation and brightness, as NSColor converts them.
enum HSB {
    static func rgb(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let h = (hue - hue.rounded(.down)) * 6, s = max(0, min(1, saturation)), v = max(0, min(1, brightness))
        let i = Int(h) % 6, f = h - CGFloat(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func hsb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard delta > 0 else { return (0, 0, high) }
        var hue: CGFloat
        if high == r { hue = (g - b) / delta } else if high == g { hue = 2 + (b - r) / delta } else { hue = 4 + (r - g) / delta }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, high > 0 ? delta / high : 0, high)
    }
}

/// NSColorSpace: sRGB, as every color here is.
@ObjCClass("NSColorSpace")
open class NSColorSpace: NSObject {
    var name = "sRGB IEC61966-2.1"
    var model = 1

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        if let coder { model = Coder(coder: coder).integer("NSModel") == 0 ? 0 : 1 }
    }

    nonisolated(unsafe) private static var shared: [String: NSColorSpace] = [:]
    static func named(_ name: String, model: Int) -> NSColorSpace {
        if let space = shared[name] { return space }
        let space = NSColorSpace()
        (space.name, space.model) = (name, model)
        shared[name] = space
        return space
    }

    @ObjCClassMethod("sRGBColorSpace") static func sRGBColorSpace() -> NSColorSpace { named("sRGB IEC61966-2.1", model: 1) }
    @ObjCClassMethod("genericRGBColorSpace") static func genericRGBColorSpace() -> NSColorSpace { named("Generic RGB", model: 1) }
    @ObjCClassMethod("deviceRGBColorSpace") static func deviceRGBColorSpace() -> NSColorSpace { named("Device RGB", model: 1) }
    @ObjCClassMethod("displayP3ColorSpace") static func displayP3ColorSpace() -> NSColorSpace { named("Display P3", model: 1) }
    @ObjCClassMethod("extendedSRGBColorSpace") static func extendedSRGBColorSpace() -> NSColorSpace { named("Extended sRGB", model: 1) }
    @ObjCClassMethod("genericGrayColorSpace") static func genericGrayColorSpace() -> NSColorSpace { named("Generic Gray", model: 0) }
    @ObjCClassMethod("deviceGrayColorSpace") static func deviceGrayColorSpace() -> NSColorSpace { named("Device Gray", model: 0) }
    @ObjCClassMethod("genericGamma22GrayColorSpace") static func genericGamma22GrayColorSpace() -> NSColorSpace { named("Generic Gray Gamma 2.2", model: 0) }

    @ObjCMethod("localizedName") func localizedName() -> String { name }
    @ObjCMethod("colorSpaceModel") func colorSpaceModel() -> Int { model }
    @ObjCMethod("numberOfColorComponents") func numberOfColorComponents() -> Int { model == 0 ? 1 : 3 }
    @ObjCMethod("CGColorSpace") func cgColorSpace() -> UnsafeMutableRawPointer? { nil }
}

@ObjCClass("NSFont")
open class NSFont: NSObject {
    var name = ".AppleSystemUIFont"
    var size: CGFloat = 13
    var bold = false
    var italic = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    init(name: String, size: CGFloat) {
        super.init()
        self.name = name
        self.size = size > 0 ? size : 13
        let lower = name.lowercased()
        bold = lower.contains("bold") || lower.contains("heavy") || lower.contains("black") || lower.contains("semibold")
        italic = lower.contains("italic") || lower.contains("oblique")
    }

    /// NSFont's archive: "NSName", "NSSize" and "NSfFlags".
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        let named = NSFont(name: decoded.string("NSName") ?? ".AppleSystemUIFont", size: decoded.double("NSSize"))
        (name, size, bold, italic) = (named.name, named.size, named.bold, named.italic)
    }

    /// A system font of a weight: NSFontWeight's semibold (0.3) and heavier
    /// are bold.
    static func system(size: CGFloat, weight: CGFloat = 0) -> NSFont {
        NSFont(name: weight >= 0.3 ? ".AppleSystemUIFontBold" : ".AppleSystemUIFont", size: size > 0 ? size : 13)
    }

    /// The font CoreGraphics draws for it: DejaVu for the system's fonts,
    /// which Linux doesn't have, and the font's own name otherwise.
    var drawingName: String {
        let monospaced = name.contains("Monospaced") || name.hasPrefix("Menlo") || name.hasPrefix("Monaco") || name.hasPrefix("Courier")
            || name.hasPrefix("SFMono")
        guard name.hasPrefix(".") || name.hasPrefix("SF") || name.hasPrefix("Helvetica") || name.hasPrefix("LucidaGrande") || monospaced else { return name }
        let family = monospaced ? "DejaVu Sans Mono" : "DejaVu Sans"
        let style = (bold ? "Bold" : "") + (italic ? "Oblique" : "")
        return style.isEmpty ? family : family + "-" + style
    }

    func with(bold: Bool? = nil, italic: Bool? = nil, size: CGFloat? = nil) -> NSFont {
        let font = NSFont(name: name, size: size ?? self.size)
        font.bold = bold ?? self.bold
        font.italic = italic ?? self.italic
        return font
    }

    @ObjCClassMethod("systemFontOfSize:") static func systemFont(ofSize size: CGFloat) -> NSFont { system(size: size) }
    @ObjCClassMethod("systemFontOfSize:weight:")
    static func systemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont { system(size: size, weight: weight) }
    @ObjCClassMethod("boldSystemFontOfSize:") static func boldSystemFont(ofSize size: CGFloat) -> NSFont { system(size: size, weight: 0.4) }
    @ObjCClassMethod("monospacedSystemFontOfSize:weight:")
    static func monospacedSystemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont {
        let font = NSFont(name: ".AppleSystemUIFontMonospaced", size: size)
        font.bold = weight >= 0.3
        return font
    }
    @ObjCClassMethod("monospacedDigitSystemFontOfSize:weight:")
    static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont { system(size: size, weight: weight) }
    @ObjCClassMethod("labelFontOfSize:") static func labelFont(ofSize size: CGFloat) -> NSFont { system(size: size > 0 ? size : 10) }
    @ObjCClassMethod("messageFontOfSize:") static func messageFont(ofSize size: CGFloat) -> NSFont { system(size: size) }
    @ObjCClassMethod("menuFontOfSize:") static func menuFont(ofSize size: CGFloat) -> NSFont { system(size: size > 0 ? size : 14) }
    @ObjCClassMethod("menuBarFontOfSize:") static func menuBarFont(ofSize size: CGFloat) -> NSFont { system(size: size > 0 ? size : 14) }
    @ObjCClassMethod("titleBarFontOfSize:") static func titleBarFont(ofSize size: CGFloat) -> NSFont { system(size: size, weight: 0.4) }
    @ObjCClassMethod("paletteFontOfSize:") static func paletteFont(ofSize size: CGFloat) -> NSFont { system(size: size > 0 ? size : 11) }
    @ObjCClassMethod("toolTipsFontOfSize:") static func toolTipsFont(ofSize size: CGFloat) -> NSFont { system(size: size > 0 ? size : 11) }
    @ObjCClassMethod("controlContentFontOfSize:") static func controlContentFont(ofSize size: CGFloat) -> NSFont { system(size: size) }
    @ObjCClassMethod("userFontOfSize:") static func userFont(ofSize size: CGFloat) -> NSFont { NSFont(name: "Helvetica", size: size > 0 ? size : 12) }
    @ObjCClassMethod("userFixedPitchFontOfSize:")
    static func userFixedPitchFont(ofSize size: CGFloat) -> NSFont { NSFont(name: "Menlo-Regular", size: size > 0 ? size : 11) }
    @ObjCClassMethod("fontWithName:size:") static func font(name: String?, size: CGFloat) -> NSFont? { NSFont(name: name ?? "Helvetica", size: size) }
    @ObjCClassMethod("fontWithDescriptor:size:")
    static func font(descriptor: NSObject?, size: CGFloat) -> NSFont? { system(size: size) }
    @ObjCClassMethod("preferredFontForTextStyle:options:")
    static func preferredFont(forTextStyle style: String?, options: NSObject?) -> NSFont {
        let sizes = ["NSCTFontUIFontTextStyleLargeTitle": 26.0, "NSCTFontUIFontTextStyleTitle1": 22, "NSCTFontUIFontTextStyleTitle2": 17,
                     "NSCTFontUIFontTextStyleTitle3": 15, "NSCTFontUIFontTextStyleHeadline": 13, "NSCTFontUIFontTextStyleSubhead": 11,
                     "NSCTFontUIFontTextStyleBody": 13, "NSCTFontUIFontTextStyleCallout": 12, "NSCTFontUIFontTextStyleFootnote": 10,
                     "NSCTFontUIFontTextStyleCaption1": 10, "NSCTFontUIFontTextStyleCaption2": 10]
        return system(size: CGFloat(sizes[style ?? ""] ?? 13), weight: style == "NSCTFontUIFontTextStyleHeadline" ? 0.4 : 0)
    }
    @ObjCClassMethod("systemFontSize") static func systemFontSize() -> CGFloat { 13 }
    @ObjCClassMethod("smallSystemFontSize") static func smallSystemFontSize() -> CGFloat { 11 }
    @ObjCClassMethod("labelFontSize") static func labelFontSize() -> CGFloat { 10 }
    @ObjCClassMethod("systemFontSizeForControlSize:") static func systemFontSize(forControlSize size: UInt) -> CGFloat { [13, 11, 9, 13][Int(min(size, 3))] }

    @ObjCMethod("fontName") func fontName() -> String { name }
    @ObjCMethod("familyName") func familyName() -> String { name.hasPrefix(".") ? "System Font" : name.split(separator: "-").first.map(String.init) ?? name }
    @ObjCMethod("displayName") func displayName() -> String { name.hasPrefix(".") ? "System Font Regular" : name }
    @ObjCMethod("pointSize") func pointSize() -> CGFloat { size }
    @ObjCMethod("ascender") func ascender() -> CGFloat { (size * 0.95).rounded(.up) }
    @ObjCMethod("descender") func descender() -> CGFloat { -(size * 0.24).rounded(.up) }
    @ObjCMethod("leading") func leading() -> CGFloat { 0 }
    @ObjCMethod("capHeight") func capHeight() -> CGFloat { size * 0.7 }
    @ObjCMethod("xHeight") func xHeight() -> CGFloat { size * 0.52 }
    @ObjCMethod("underlinePosition") func underlinePosition() -> CGFloat { -size * 0.1 }
    @ObjCMethod("underlineThickness") func underlineThickness() -> CGFloat { max(1, size / 14) }
    @ObjCMethod("italicAngle") func italicAngle() -> CGFloat { italic ? -12 : 0 }
    @ObjCMethod("isFixedPitch") func isFixedPitch() -> Bool { drawingName.contains("Mono") }
    @ObjCMethod("boundingRectForFont")
    func boundingRectForFont() -> CGRect { CGRect(x: 0, y: descender(), width: size, height: ascender() - descender()) }
    @ObjCMethod("maximumAdvancement") func maximumAdvancement() -> CGSize { CGSize(width: size, height: 0) }
    @ObjCMethod("fontWithSize:") func withSize(_ size: CGFloat) -> NSFont { with(size: size) }
    @ObjCMethod("fontDescriptor") func fontDescriptor() -> NSObject? { nil }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(NSFont.self) else { return false }
        return other.name == name && other.size == size && other.bold == bold && other.italic == italic
    }
    @ObjCMethod("hash") func fontHash() -> UInt { UInt(bitPattern: name.hashValue) ^ UInt(size * 100) }
    @ObjCMethod("description") func fontDescription() -> String { "\"\(name) \(size).00pt.\"" }
}

/// NSFontManager: converts fonts between traits. NSFontTraitMask: italic 1,
/// bold 2, unbold 4, unitalic 0x1000000.
@ObjCClass("NSFontManager")
open class NSFontManager: NSObject {
    nonisolated(unsafe) static var shared: NSFontManager?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("sharedFontManager")
    static func sharedFontManager() -> NSFontManager {
        if let shared { return shared }
        let manager = NSFontManager()
        shared = manager
        return manager
    }

    @ObjCMethod("convertFont:toHaveTrait:")
    func convert(_ font: NSFont?, toHaveTrait trait: UInt) -> NSFont? {
        guard let font else { return nil }
        return font.with(bold: trait & 2 != 0 ? true : trait & 4 != 0 ? false : nil,
                         italic: trait & 1 != 0 ? true : trait & 0x100_0000 != 0 ? false : nil)
    }
    @ObjCMethod("convertFont:toNotHaveTrait:")
    func convert(_ font: NSFont?, toNotHaveTrait trait: UInt) -> NSFont? {
        guard let font else { return nil }
        return font.with(bold: trait & 2 != 0 ? false : nil, italic: trait & 1 != 0 ? false : nil)
    }
    @ObjCMethod("convertFont:toSize:") func convert(_ font: NSFont?, toSize size: CGFloat) -> NSFont? { font?.with(size: size) }
    @ObjCMethod("convertFont:toFamily:") func convert(_ font: NSFont?, toFamily family: String?) -> NSFont? { font }
    @ObjCMethod("convertWeight:ofFont:") func convertWeight(_ heavier: Bool, of font: NSFont?) -> NSFont? { font?.with(bold: heavier) }
    @ObjCMethod("traitsOfFont:") func traits(of font: NSFont?) -> UInt { (font?.bold == true ? 2 : 0) | (font?.italic == true ? 1 : 0) }
    @ObjCMethod("weightOfFont:") func weight(of font: NSFont?) -> Int { font?.bold == true ? 9 : 5 }
    @ObjCMethod("fontWithFamily:traits:weight:size:")
    func font(family: String?, traits: UInt, weight: Int, size: CGFloat) -> NSFont? {
        let font = NSFont(name: family ?? "Helvetica", size: size)
        return font.with(bold: traits & 2 != 0 || weight >= 9, italic: traits & 1 != 0)
    }
    @ObjCMethod("availableFonts") func availableFonts() -> NSObject { NSMutableArray.of(["Helvetica", "Menlo-Regular"].compactMap { $0.objCArgument().map(NSObject.init) }) }
    @ObjCMethod("availableFontFamilies") func availableFontFamilies() -> NSObject { NSMutableArray.of(["Helvetica", "Menlo"].compactMap { $0.objCArgument().map(NSObject.init) }) }
    @ObjCMethod("selectedFont") func selectedFont() -> NSFont? { nil }
    @ObjCMethod("setSelectedFont:isMultiple:") func setSelectedFont(_ font: NSObject?, isMultiple: Bool) {}
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) {}
    @ObjCMethod("setAction:") func setAction(_ action: ObjCSelector?) {}
}

@ObjCClass("NSImage")
open class NSImage: NSObject {
    var size = CGSize.zero
    var name: String?
    var path: String?
    var data: NSObject?
    var template = false
    var representations: [NSObject] = []
    /// The decoded bitmap: retained; nil until it is first drawn.
    var cgImage: CGRef?
    private var decoded = false
    /// An image drawn by code: an app's block, or a system image's drawing.
    var drawingHandler: ObjCBlock?
    var drawing: ((CGRect) -> Void)?
    var handlerFlipped = false

    nonisolated(unsafe) static var named: [String: NSImage] = [:]

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithSize:")
    public required init(size: CGSize) {
        super.init()
        self.size = size
    }

    @ObjCMethod("initWithContentsOfFile:")
    public required init(contentsOfFile path: String?) {
        super.init()
        self.path = path
        decodeSize()
    }

    @ObjCMethod("initByReferencingFile:")
    public required init(referencingFile path: String?) {
        super.init()
        self.path = path
        decodeSize()
    }

    @ObjCMethod("initWithContentsOfURL:")
    public required init(contentsOf url: NSObject?) {
        super.init()
        path = url.flatMap { Send.object($0.objcObject, "path") }.map { String(objCArgument: $0) }
        decodeSize()
    }

    @ObjCMethod("initWithData:")
    public required init(data: NSObject?) {
        super.init()
        self.data = data
        decodeSize()
    }

    @ObjCMethod("initWithCGImage:size:")
    public required init(cgImage: UnsafeMutableRawPointer?, size: CGSize) {
        super.init()
        self.cgImage = ObjCRuntime.retain(cgImage)
        decoded = true
        if size == .zero, let cgImage, CG.ready {
            self.size = CGSize(width: CGFloat(CG.imageGetWidth(cgImage)), height: CGFloat(CG.imageGetHeight(cgImage)))
        } else {
            self.size = size
        }
    }

    /// A nib's image: an NSCustomResource names it.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        if let coder, let name = Coder(coder: coder).string("NSResourceName") ?? Coder(coder: coder).string("NSName") { load(named: name) }
    }

    deinit { if let cgImage { CG.release(cgImage) } }

    /// The image's file in the main bundle's resources, by name.
    private func load(named name: String) {
        self.name = name
        let resources = NSBundle.main().bundlePath() + "/Contents/Resources/"
        for candidate in [name, name + ".png", name + "@2x.png", name + ".jpg", name + ".tiff", name + ".pdf"] {
            for directory in [resources, resources + "en.lproj/", resources + "Base.lproj/"] where access(directory + candidate, R_OK) == 0 {
                path = directory + candidate
                decodeSize()
                return
            }
        }
        // The app's asset catalog's.
        if let (image, imageSize) = AppKitAssets.image(named: name) {
            cgImage = image
            decoded = true
            size = imageSize
            path = ""
            template = AppKitAssets.isTemplate(named: name)
            return
        }
        if let (file, scale) = AppKitAssets.extractedImage(named: name), let pixels = Self.pngSize(file) {
            path = file
            size = CGSize(width: pixels.width / CGFloat(scale), height: pixels.height / CGFloat(scale))
            template = AppKitAssets.isTemplate(named: name)
            return
        }
        size = CGSize(width: 16, height: 16)
    }

    /// A PNG's size in pixels, from its header, without decoding it.
    static func pngSize(_ path: String) -> CGSize? {
        guard let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        var header = [UInt8](repeating: 0, count: 24)
        guard fread(&header, 1, 24, file) == 24, header[0] == 0x89, header[1] == 0x50 else { return nil }
        func be32(_ at: Int) -> Int { header[at...at + 3].reduce(0) { $0 << 8 | Int($1) } }
        return CGSize(width: CGFloat(be32(16)), height: CGFloat(be32(20)))
    }

    /// Decodes the bitmap now, for its size.
    func decodeSize() {
        guard let image = bitmap() else { return }
        if size == .zero { size = CGSize(width: CGFloat(CG.imageGetWidth(image)), height: CGFloat(CG.imageGetHeight(image))) }
    }

    /// The bitmap ImageIO decodes from the file or data, or that a drawing
    /// handler draws, at twice the image's size.
    func bitmap() -> CGRef? {
        if decoded { return cgImage }
        if drawingHandler != nil || drawing != nil { return drawnBitmap() }
        // Decoded once CoreGraphics is there to decode it.
        guard CG.ready else { return nil }
        decoded = true
        var source = data
        if source == nil, let path, let read = Send.object(Classes.named("NSData")?.pointer, "dataWithContentsOfFile:", path.objCArgument()) {
            source = NSObject(read)
        }
        guard let source, let imageSource = CG.imageSourceCreateWithData(source.objcObject, nil) else { return nil }
        defer { CG.release(imageSource) }
        cgImage = CG.imageSourceCreateImageAtIndex(imageSource, 0, nil)
        return cgImage
    }

    private func drawnBitmap() -> CGRef? {
        decoded = true
        guard CG.ready, size.width > 0, size.height > 0, let context = CG.makeContext(size: size, scale: 2) else { return nil }
        defer { CG.release(context) }
        let bounds = CGRect(origin: .zero, size: size)
        NSGraphicsContext.with(context, flipped: handlerFlipped) {
            if handlerFlipped {
                CG.translateCTM(context, 0, size.height)
                CG.scaleCTM(context, 1, -1)
            }
            if let drawing {
                drawing(bounds)
            } else if let drawingHandler {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, CGRect) -> Bool
                _ = drawingHandler.function(as: Invoke.self)(drawingHandler.object, bounds)
            }
        }
        cgImage = CG.bitmapContextCreateImage(context)
        return cgImage
    }

    /// An image its block draws, each time at its size, y upwards unless
    /// flipped.
    @ObjCClassMethod("imageWithSize:flipped:drawingHandler:")
    static func image(size: CGSize, flipped: Bool, drawingHandler: ObjCBlock?) -> NSImage {
        let image = NSImage(size: size)
        image.drawingHandler = drawingHandler
        image.handlerFlipped = flipped
        return image
    }

    /// Named images: the app's resources by name, else a system image (the
    /// templates and symbols Perry draws, or a blank one of the size apps
    /// expect).
    @ObjCClassMethod("imageNamed:")
    static func image(named name: String?) -> NSImage? {
        guard let name else { return nil }
        if let image = named[name] { return image }
        let image = NSImage(size: .zero)
        image.load(named: name)
        if image.path == nil {
            if let drawing = SystemImages.drawing(for: name) {
                image.size = CGSize(width: 16, height: 16)
                image.drawing = drawing
                image.template = true
            } else {
                image.size = CGSize(width: 32, height: 32)
            }
        }
        named[name] = image
        return image
    }

    @ObjCClassMethod("imageWithSystemSymbolName:accessibilityDescription:")
    static func image(systemSymbolName name: String?, accessibilityDescription: String?) -> NSImage? {
        let image = NSImage(size: CGSize(width: 16, height: 16))
        image.name = name
        image.template = true
        // As macOS rendered it into the app's copy (Scripts/extract-symbols,
        // 34 points at 3 pixels a point), at the system font's 13 points.
        if let name, case let file = NSBundle.main().bundlePath() + "/SFSymbols/" + name + ".png", access(file, R_OK) == 0 {
            image.path = file
            let pixels = pngSize(file) ?? CGSize(width: 48, height: 48)
            let factor: CGFloat = 13.0 / 34.0 / 3.0
            image.size = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
            return image
        }
        image.drawing = name.flatMap(SystemImages.drawing)
        if image.drawing == nil, let name, getenv("PERRY_APPKIT_SYMBOL_TRACE") != nil {
            appKitWarning("SF Symbol \(name) isn't rendered: list it in the app's SFSymbols.txt for Scripts/extract-symbols")
        }
        return image
    }

    @ObjCMethod("size") func imageSize() -> CGSize { size }
    @ObjCMethod("setSize:") func setSize(_ size: CGSize) { self.size = size }
    @ObjCMethod("name") func imageName() -> String? { name }
    @ObjCMethod("setName:") func setName(_ name: String?) -> Bool { self.name = name; return true }
    @ObjCMethod("isTemplate") func isTemplate() -> Bool { template }
    @ObjCMethod("setTemplate:") func setTemplate(_ value: Bool) { template = value }
    @ObjCMethod("isValid") func isValid() -> Bool { true }
    @ObjCMethod("representations") func imageRepresentations() -> NSObject { NSMutableArray.of(representations) }
    @ObjCMethod("addRepresentation:") func addRepresentation(_ representation: NSObject?) { representation.map { representations.append($0) } }
    @ObjCMethod("removeRepresentation:") func removeRepresentation(_ representation: NSObject?) { representations.removeAll { $0 === representation } }
    @ObjCMethod("CGImageForProposedRect:context:hints:")
    func cgImage(forProposedRect rect: UnsafeMutablePointer<CGRect>?, context: NSObject?, hints: NSObject?) -> UnsafeMutableRawPointer? { bitmap() }
    @ObjCMethod("TIFFRepresentation") func tiffRepresentation() -> NSObject? { data }
    @ObjCMethod("lockFocus") func lockFocus() {}
    @ObjCMethod("unlockFocus") func unlockFocus() {}
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    /// Draws the bitmap in `rect` of the current context, upright in a
    /// flipped view as AppKit draws images whose -respectFlipped is set.
    /// A template bitmap (one Perry doesn't draw itself) takes the tint
    /// color, the label color by default, through its alpha.
    func draw(in rect: CGRect, fraction: CGFloat = 1, tint: NSColor? = nil) {
        guard let context = NSGraphicsContext.currentCG, let image = bitmap() else { return }
        CG.saveGState(context)
        if fraction < 1 { CG.setAlpha(context, fraction) }
        var target = rect
        if NSGraphicsContext.current?.flipped == true {
            CG.translateCTM(context, rect.minX, rect.maxY)
            CG.scaleCTM(context, 1, -1)
            target = CGRect(origin: .zero, size: rect.size)
        }
        if template, drawing == nil, drawingHandler == nil, let clipToMask = CG.clipToMask {
            clipToMask(context, target, image)
            CG.setFill(context, (tint ?? NSColor.labelColor()))
            CG.fillRect(context, target)
        } else {
            CG.drawImage(context, target, image)
        }
        CG.restoreGState(context)
    }

    @ObjCMethod("drawInRect:") func draw(inRect rect: CGRect) { draw(in: rect) }
    @ObjCMethod("drawInRect:fromRect:operation:fraction:")
    func draw(in rect: CGRect, from source: CGRect, operation: UInt, fraction: CGFloat) { draw(in: rect, fraction: fraction) }
    @ObjCMethod("drawInRect:fromRect:operation:fraction:respectFlipped:hints:")
    func draw(in rect: CGRect, from source: CGRect, operation: UInt, fraction: CGFloat, respectFlipped: Bool, hints: NSObject?) {
        draw(in: rect, fraction: fraction)
    }
    @ObjCMethod("drawAtPoint:fromRect:operation:fraction:")
    func draw(at point: CGPoint, from source: CGRect, operation: UInt, fraction: CGFloat) {
        draw(in: CGRect(origin: point, size: size), fraction: fraction)
    }
    @ObjCMethod("setAccessibilityDescription:") func setAccessibilityDescription(_ text: String?) {}
}

/// NSGraphicsContext: a CGContext views draw in, and whether its y axis
/// points down. The current one is a stack, per thread as on Darwin (the
/// main thread's here).
@ObjCClass("NSGraphicsContext")
open class NSGraphicsContext: NSObject {
    nonisolated(unsafe) static var current: NSGraphicsContext?
    nonisolated(unsafe) static var saved: [NSGraphicsContext?] = []
    var cgContext: CGRef?
    var flipped = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    init(cgContext: CGRef?, flipped: Bool) {
        super.init()
        self.cgContext = ObjCRuntime.retain(cgContext)
        self.flipped = flipped
    }

    deinit { if let cgContext { CG.release(cgContext) } }

    static var currentCG: CGRef? { current?.cgContext }

    /// Runs `body` with a context current, then the previous one again.
    static func with(_ context: CGRef, flipped: Bool, _ body: () -> Void) {
        let previous = current
        current = NSGraphicsContext(cgContext: context, flipped: flipped)
        defer { current = previous }
        CG.saveGState(context)
        body()
        CG.restoreGState(context)
    }

    @ObjCClassMethod("currentContext") static func currentContext() -> NSGraphicsContext? { current }
    @ObjCClassMethod("setCurrentContext:") static func setCurrentContext(_ context: NSGraphicsContext?) { current = context }
    @ObjCClassMethod("currentContextDrawingToScreen") static func currentContextDrawingToScreen() -> Bool { true }
    @ObjCClassMethod("graphicsContextWithWindow:") static func graphicsContext(with window: NSObject?) -> NSGraphicsContext? { NSGraphicsContext() }
    @ObjCClassMethod("graphicsContextWithCGContext:flipped:")
    static func graphicsContext(cgContext: UnsafeMutableRawPointer?, flipped: Bool) -> NSGraphicsContext? {
        NSGraphicsContext(cgContext: cgContext, flipped: flipped)
    }
    @ObjCClassMethod("graphicsContextWithBitmapImageRep:") static func graphicsContext(bitmapImageRep: NSObject?) -> NSGraphicsContext? { nil }
    @ObjCClassMethod("saveGraphicsState")
    static func classSaveGraphicsState() {
        saved.append(current)
        current?.saveGraphicsState()
    }
    @ObjCClassMethod("restoreGraphicsState")
    static func classRestoreGraphicsState() {
        guard let previous = saved.popLast() else { return }
        current = previous
        current?.restoreGraphicsState()
    }
    @ObjCMethod("saveGraphicsState") func saveGraphicsState() { if let cgContext { CG.saveGState(cgContext) } }
    @ObjCMethod("restoreGraphicsState") func restoreGraphicsState() { if let cgContext { CG.restoreGState(cgContext) } }
    @ObjCMethod("flushGraphics") func flushGraphics() {}
    @ObjCMethod("CGContext") func cgContextObject() -> UnsafeMutableRawPointer? { cgContext }
    @ObjCMethod("graphicsPort") func graphicsPort() -> UnsafeMutableRawPointer? { cgContext }
    @ObjCMethod("isFlipped") func isFlipped() -> Bool { flipped }
    @ObjCMethod("isDrawingToScreen") func isDrawingToScreen() -> Bool { true }
    @ObjCMethod("imageInterpolation") func imageInterpolation() -> UInt { 3 }
    @ObjCMethod("setImageInterpolation:") func setImageInterpolation(_ value: UInt) {}
    @ObjCMethod("shouldAntialias") func shouldAntialias() -> Bool { true }
    @ObjCMethod("setShouldAntialias:") func setShouldAntialias(_ value: Bool) { if let cgContext { CG.setShouldAntialias(cgContext, value) } }
    @ObjCMethod("setCompositingOperation:") func setCompositingOperation(_ operation: UInt) {}
    @ObjCMethod("compositingOperation") func compositingOperation() -> UInt { 2 }
    @ObjCMethod("setPatternPhase:") func setPatternPhase(_ phase: CGPoint) {}
}

/// NSBezierPath: a CGPath, and its line style.
@ObjCClass("NSBezierPath")
open class NSBezierPath: NSObject {
    var path: CGRef?
    var lineWidth: CGFloat = 1
    /// NSWindingRule: nonzero 0, even-odd 1.
    var windingRule = 0
    var lineCap: Int32 = 0
    var lineJoin: Int32 = 0
    var dash: [CGFloat] = []
    var dashPhase: CGFloat = 0
    nonisolated(unsafe) static var defaultLineWidth: CGFloat = 1

    @ObjCMethod("init")
    public required override init() {
        super.init()
        lineWidth = NSBezierPath.defaultLineWidth
        if CG.ready { path = CG.pathCreateMutable() }
    }

    deinit { if let path { CG.release(path) } }

    static func with(_ build: (CGRef) -> Void) -> NSBezierPath {
        let made = NSBezierPath()
        if let path = made.path { build(path) }
        return made
    }

    @ObjCClassMethod("bezierPath") static func bezierPath() -> NSBezierPath { NSBezierPath() }
    @ObjCClassMethod("bezierPathWithRect:")
    static func bezierPath(rect: CGRect) -> NSBezierPath { with { CG.pathAddRect($0, nil, rect) } }
    @ObjCClassMethod("bezierPathWithOvalInRect:")
    static func bezierPath(ovalIn rect: CGRect) -> NSBezierPath { with { CG.pathAddEllipseInRect($0, nil, rect) } }
    @ObjCClassMethod("bezierPathWithRoundedRect:xRadius:yRadius:")
    static func bezierPath(roundedRect rect: CGRect, xRadius: CGFloat, yRadius: CGFloat) -> NSBezierPath {
        with { path in
            let x = max(0, min(xRadius, rect.width / 2)), y = max(0, min(yRadius, rect.height / 2))
            if x > 0 && y > 0 { CG.pathAddRoundedRect(path, nil, rect, x, y) } else { CG.pathAddRect(path, nil, rect) }
        }
    }
    @ObjCClassMethod("fillRect:") static func fill(rect: CGRect) { NSRectFill(rect) }
    @ObjCClassMethod("strokeRect:") static func stroke(rect: CGRect) { NSFrameRectWithWidth(rect, defaultLineWidth) }
    @ObjCClassMethod("strokeLineFromPoint:toPoint:")
    static func strokeLine(from a: CGPoint, to b: CGPoint) {
        let line = NSBezierPath()
        line.move(to: a)
        line.line(to: b)
        line.stroke()
    }
    @ObjCClassMethod("clipRect:")
    static func clip(rect: CGRect) {
        if let context = NSGraphicsContext.currentCG { CG.clipToRect(context, rect) }
    }
    @ObjCClassMethod("setDefaultLineWidth:") static func setDefaultLineWidth(_ width: CGFloat) { defaultLineWidth = width }
    @ObjCClassMethod("defaultLineWidth") static func classDefaultLineWidth() -> CGFloat { defaultLineWidth }

    @ObjCMethod("moveToPoint:") func move(to point: CGPoint) { if let path { CG.pathMoveToPoint(path, nil, point.x, point.y) } }
    @ObjCMethod("lineToPoint:") func line(to point: CGPoint) { if let path { CG.pathAddLineToPoint(path, nil, point.x, point.y) } }
    @ObjCMethod("curveToPoint:controlPoint1:controlPoint2:")
    func curve(to point: CGPoint, controlPoint1 a: CGPoint, controlPoint2 b: CGPoint) {
        if let path { CG.pathAddCurveToPoint(path, nil, a.x, a.y, b.x, b.y, point.x, point.y) }
    }
    @ObjCMethod("relativeMoveToPoint:") func relativeMove(to point: CGPoint) { let c = currentPoint(); move(to: CGPoint(x: c.x + point.x, y: c.y + point.y)) }
    @ObjCMethod("relativeLineToPoint:") func relativeLine(to point: CGPoint) { let c = currentPoint(); line(to: CGPoint(x: c.x + point.x, y: c.y + point.y)) }
    @ObjCMethod("closePath") func closePath() { if let path { CG.pathCloseSubpath(path) } }
    @ObjCMethod("removeAllPoints")
    func removeAllPoints() {
        if let path { CG.release(path) }
        path = CG.pathCreateMutable()
    }
    @ObjCMethod("appendBezierPath:") func append(_ other: NSBezierPath?) { if let path, let other = other?.path { CG.pathAddPath(path, nil, other) } }
    @ObjCMethod("appendBezierPathWithRect:") func appendRect(_ rect: CGRect) { if let path { CG.pathAddRect(path, nil, rect) } }
    @ObjCMethod("appendBezierPathWithOvalInRect:") func appendOval(in rect: CGRect) { if let path { CG.pathAddEllipseInRect(path, nil, rect) } }
    @ObjCMethod("appendBezierPathWithRoundedRect:xRadius:yRadius:")
    func appendRoundedRect(_ rect: CGRect, xRadius: CGFloat, yRadius: CGFloat) {
        if let path { CG.pathAddRoundedRect(path, nil, rect, max(0, min(xRadius, rect.width / 2)), max(0, min(yRadius, rect.height / 2))) }
    }
    @ObjCMethod("appendBezierPathWithArcWithCenter:radius:startAngle:endAngle:clockwise:")
    func appendArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        if let path { CG.pathAddArc(path, nil, center.x, center.y, radius, startAngle * .pi / 180, endAngle * .pi / 180, clockwise) }
    }
    @ObjCMethod("appendBezierPathWithArcWithCenter:radius:startAngle:endAngle:")
    func appendArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {
        appendArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    }
    @ObjCMethod("transformUsingAffineTransform:") func transform(using transform: NSObject?) {}
    @ObjCMethod("isEmpty") func isEmpty() -> Bool { path.map { CG.pathIsEmpty($0) } ?? true }
    @ObjCMethod("currentPoint") func currentPoint() -> CGPoint { path.map { CG.pathGetCurrentPoint($0) } ?? .zero }
    @ObjCMethod("bounds") func bounds() -> CGRect { path.map { CG.pathGetBoundingBox($0) } ?? .zero }
    @ObjCMethod("controlPointBounds") func controlPointBounds() -> CGRect { bounds() }
    @ObjCMethod("containsPoint:") func contains(_ point: CGPoint) -> Bool { path.map { CG.pathContainsPoint($0, nil, point, windingRule == 1) } ?? false }
    @ObjCMethod("lineWidth") func pathLineWidth() -> CGFloat { lineWidth }
    @ObjCMethod("setLineWidth:") func setLineWidth(_ width: CGFloat) { lineWidth = width }
    @ObjCMethod("windingRule") func pathWindingRule() -> Int { windingRule }
    @ObjCMethod("setWindingRule:") func setWindingRule(_ rule: Int) { windingRule = rule }
    @ObjCMethod("setLineCapStyle:") func setLineCapStyle(_ style: Int) { lineCap = Int32(style) }
    @ObjCMethod("setLineJoinStyle:") func setLineJoinStyle(_ style: Int) { lineJoin = Int32(style) }
    @ObjCMethod("setMiterLimit:") func setMiterLimit(_ limit: CGFloat) {}
    @ObjCMethod("setFlatness:") func setFlatness(_ flatness: CGFloat) {}
    @ObjCMethod("setLineDash:count:phase:")
    func setLineDash(_ pattern: UnsafePointer<CGFloat>?, count: Int, phase: CGFloat) {
        dash = pattern.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
        dashPhase = phase
    }
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = NSBezierPath()
        copy.append(self)
        (copy.lineWidth, copy.windingRule, copy.lineCap, copy.lineJoin, copy.dash) = (lineWidth, windingRule, lineCap, lineJoin, dash)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("fill")
    func fill() {
        guard let context = NSGraphicsContext.currentCG, let path else { return }
        CG.addPath(context, path)
        windingRule == 1 ? CG.eoFillPath(context) : CG.fillPath(context)
    }

    @ObjCMethod("stroke")
    func stroke() {
        guard let context = NSGraphicsContext.currentCG, let path else { return }
        CG.saveGState(context)
        CG.setLineWidth(context, lineWidth)
        CG.setLineCap(context, lineCap)
        CG.setLineJoin(context, lineJoin)
        if !dash.isEmpty { dash.withUnsafeBufferPointer { CG.setLineDash(context, dashPhase, $0.baseAddress, $0.count) } }
        CG.addPath(context, path)
        CG.strokePath(context)
        CG.restoreGState(context)
    }

    @ObjCMethod("addClip")
    func addClip() {
        guard let context = NSGraphicsContext.currentCG, let path else { return }
        CG.addPath(context, path)
        windingRule == 1 ? CG.eoClip(context) : CG.clip(context)
    }

    @ObjCMethod("setClip") func setClip() { addClip() }
}

// MARK: - Drawing functions

/// Fills `rect` with the current fill color.
@c(_NSRectFill)
public func NSRectFill(_ rect: CGRect) {
    guard let context = NSGraphicsContext.currentCG else { return }
    CG.fillRect(context, rect)
}

@c(_NSRectFillUsingOperation)
public func NSRectFillUsingOperation(_ rect: CGRect, _ operation: UInt) { NSRectFill(rect) }

@c(_NSRectFillList)
public func NSRectFillList(_ rects: UnsafePointer<CGRect>?, _ count: Int) {
    guard let rects else { return }
    for index in 0..<count { NSRectFill(rects[index]) }
}

@c(_NSRectClip)
public func NSRectClip(_ rect: CGRect) {
    guard let context = NSGraphicsContext.currentCG else { return }
    CG.clipToRect(context, rect)
}

/// Draws the inside edge of `rect`, `width` wide, in the fill color.
@c(_NSFrameRectWithWidth)
public func NSFrameRectWithWidth(_ rect: CGRect, _ width: CGFloat) {
    guard let context = NSGraphicsContext.currentCG else { return }
    CG.fillRect(context, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: width))
    CG.fillRect(context, CGRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width))
    CG.fillRect(context, CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
    CG.fillRect(context, CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height))
}

@c(_NSFrameRect)
public func NSFrameRect(_ rect: CGRect) { NSFrameRectWithWidth(rect, 1) }

@c(_NSFrameRectWithWidthUsingOperation)
public func NSFrameRectWithWidthUsingOperation(_ rect: CGRect, _ width: CGFloat, _ operation: UInt) { NSFrameRectWithWidth(rect, width) }

@c(_NSEraseRect)
public func NSEraseRect(_ rect: CGRect) {
    guard let context = NSGraphicsContext.currentCG else { return }
    CG.saveGState(context)
    CG.setFill(context, NSColor.whiteColor())
    CG.fillRect(context, rect)
    CG.restoreGState(context)
}

@c(_NSDrawWindowBackground)
public func NSDrawWindowBackground(_ rect: CGRect) {
    guard let context = NSGraphicsContext.currentCG else { return }
    CG.saveGState(context)
    CG.setFill(context, NSColor.windowBackgroundColor())
    CG.fillRect(context, rect)
    CG.restoreGState(context)
}

/// Fills `rect` in the gray of NSDrawGrayBezel's face.
@c(_NSDrawGroove)
public func NSDrawGroove(_ rect: CGRect, _ clip: CGRect) {
    NSColor.gridColor().setFill()
    NSFrameRect(rect)
}

@c(_NSDrawLightBezel)
public func NSDrawLightBezel(_ rect: CGRect, _ clip: CGRect) { NSDrawGroove(rect, clip) }

@c(_NSDrawGrayBezel)
public func NSDrawGrayBezel(_ rect: CGRect, _ clip: CGRect) { NSDrawGroove(rect, clip) }

/// System template images and symbols Perry draws itself, in the label
/// color of the appearance they are first drawn in.
enum SystemImages {
    static func drawing(for name: String) -> ((CGRect) -> Void)? {
        func stroke(_ path: NSBezierPath, width: CGFloat = 1.3) {
            NSColor.labelColor().setStroke()
            path.setLineWidth(width)
            path.setLineCapStyle(1)
            path.stroke()
        }
        func line(_ points: [CGPoint]) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            return path
        }
        switch name {
        case "NSActionTemplate", "ellipsis.circle":
            // Three dots in a circle.
            return { rect in
                let circle = rect.insetBy(dx: 1.5, dy: 1.5)
                stroke(NSBezierPath.bezierPath(ovalIn: circle))
                NSColor.labelColor().setFill()
                for offset in [-3.5, 0, 3.5] as [CGFloat] {
                    NSBezierPath.bezierPath(ovalIn: CGRect(x: rect.midX + offset - 1.1, y: rect.midY - 1.1, width: 2.2, height: 2.2)).fill()
                }
            }
        case "sidebar.left", "sidebar.leading":
            // A window outline with its left third set off.
            return { rect in
                let frame = rect.insetBy(dx: 1.5, dy: 3)
                stroke(NSBezierPath.bezierPath(roundedRect: frame, xRadius: 2.5, yRadius: 2.5))
                let x = (frame.minX + frame.width * 0.36).rounded() + 0.5
                stroke(line([CGPoint(x: x, y: frame.minY), CGPoint(x: x, y: frame.maxY)]))
            }
        case "NSAddTemplate", "plus":
            return { rect in stroke(line([CGPoint(x: rect.midX, y: rect.minY + 3), CGPoint(x: rect.midX, y: rect.maxY - 3)]));
                stroke(line([CGPoint(x: rect.minX + 3, y: rect.midY), CGPoint(x: rect.maxX - 3, y: rect.midY)])) }
        case "NSRemoveTemplate", "minus":
            return { rect in stroke(line([CGPoint(x: rect.minX + 3, y: rect.midY), CGPoint(x: rect.maxX - 3, y: rect.midY)])) }
        case "NSGoLeftTemplate", "chevron.left":
            return { rect in stroke(line([CGPoint(x: rect.midX + 2.5, y: rect.minY + 3), CGPoint(x: rect.midX - 2.5, y: rect.midY),
                                         CGPoint(x: rect.midX + 2.5, y: rect.maxY - 3)]), width: 1.6) }
        case "NSGoRightTemplate", "chevron.right":
            return { rect in stroke(line([CGPoint(x: rect.midX - 2.5, y: rect.minY + 3), CGPoint(x: rect.midX + 2.5, y: rect.midY),
                                         CGPoint(x: rect.midX - 2.5, y: rect.maxY - 3)]), width: 1.6) }
        case "NSStopProgressTemplate", "xmark":
            return { rect in
                let box = rect.insetBy(dx: 4, dy: 4)
                stroke(line([CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY)]))
                stroke(line([CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.minY)]))
            }
        case "NSStopProgressFreestandingTemplate", "xmark.circle.fill":
            return { rect in
                NSColor.labelColor().setFill()
                NSBezierPath.bezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                let box = rect.insetBy(dx: 5, dy: 5)
                NSColor.textBackgroundColor().setStroke()
                for points in [[CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY)],
                               [CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.minY)]] {
                    let path = line(points)
                    path.setLineWidth(1.5)
                    path.stroke()
                }
            }
        default:
            return nil
        }
    }
}
