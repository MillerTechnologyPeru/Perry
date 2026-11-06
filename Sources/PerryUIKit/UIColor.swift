import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIColor: a color in sRGB, or a gray, with its CGColor made on first use.
// Setting a color sets the current context's fill and stroke colors. A
// dynamic color is its provider's color for the device's traits, and for
// other traits when resolved with them.

final class ColorState: ObjectState {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 1
    /// A gray's white level; nil for a color made from components.
    var white: CGFloat?
    /// The CGColor, made on first use and released with the color.
    var cgColor: CGRef?
    /// colorWithPatternImage:'s image, which is drawn as its average color.
    var patternImage: UIImage?
    /// colorWithDynamicProvider:'s block, which gives the color for a trait
    /// collection; the color's components are its color for the device's.
    var provider: ObjCBlock?

    deinit { if let cgColor { CG.release(cgColor) } }

    func set(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        (self.red, self.green, self.blue, self.alpha, white) = (red, green, blue, alpha, nil)
    }

    func set(white: CGFloat, alpha: CGFloat) {
        (red, green, blue, self.alpha, self.white) = (white, white, white, alpha, white)
    }

    func makeCGColor() -> CGRef {
        if let cgColor { return cgColor }
        let color = white.map { CG.colorCreateGenericGray($0, alpha) } ?? CG.colorCreateSRGB(red, green, blue, alpha)
        cgColor = color
        return color!
    }
}

/// A component as UIColor prints it: `%g`.
private func format(_ value: CGFloat) -> String {
    var buffer = [CChar](repeating: 0, count: 32)
    _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, "%g", $0) }
    return String(cString: buffer)
}

@ObjCClass("UIColor")
open class UIColor: NSObject {
    static let states = StateTable<ColorState>()
    var state: ColorState { UIColor.states[objcObject] }

    /// A new color of class `cls`.
    static func make(_ cls: ObjCClass, _ configure: (ColorState) -> Void) -> UIColor {
        let color = cls.object.allocated().unsafeCast(to: UIColor.self)
        configure(color.state)
        return color
    }

    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
        make(objCClass) { $0.set(red: red, green: green, blue: blue, alpha: alpha) }
    }

    static func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
        make(objCClass) { $0.set(white: white, alpha: alpha) }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIColor.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIColor.objCClass.pointer)
    }

    // MARK: Making colors

    /// Patterns aren't tiled here: the color is the image's average.
    @ObjCClassMethod("colorWithPatternImage:")
    static func color(_ cls: ObjCClass, patternImage image: UIImage?) -> UIColor {
        let (r, g, b, a) = image.map(UIColor.averageColor) ?? (0, 0, 0, 0)
        return make(cls) {
            $0.set(red: r, green: g, blue: b, alpha: a)
            $0.patternImage = image
        }
    }

    @ObjCMethod("initWithPatternImage:")
    func initialize(patternImage image: UIImage?) -> Self {
        let (r, g, b, a) = image.map(UIColor.averageColor) ?? (0, 0, 0, 0)
        state.set(red: r, green: g, blue: b, alpha: a)
        state.patternImage = image
        return self
    }

    /// An image's average color, from it drawn at 8 by 8 pixels.
    static func averageColor(_ image: UIImage) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard let cgImage = image.cgImage(), let context = CG.makeContext(size: CGSize(width: 8, height: 8), scale: 1, opaque: false) else {
            return (0, 0, 0, 0)
        }
        defer { CG.release(context) }
        CG.drawFlipped(cgImage, in: CGRect(x: 0, y: 0, width: 8, height: 8), context: context)
        guard let data = CG.bitmapContextGetData(context) else { return (0, 0, 0, 0) }
        // Premultiplied B, G, R, A per pixel.
        var sums = (0.0, 0.0, 0.0, 0.0)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for pixel in 0..<64 {
            sums.0 += Double(bytes[pixel * 4 + 2]); sums.1 += Double(bytes[pixel * 4 + 1])
            sums.2 += Double(bytes[pixel * 4]); sums.3 += Double(bytes[pixel * 4 + 3])
        }
        guard sums.3 > 0 else { return (0, 0, 0, 0) }
        return (CGFloat(sums.0 / sums.3), CGFloat(sums.1 / sums.3), CGFloat(sums.2 / sums.3), CGFloat(sums.3 / 64 / 255))
    }

    @ObjCClassMethod("colorWithRed:green:blue:alpha:")
    static func color(_ cls: ObjCClass, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> UIColor {
        make(cls) { $0.set(red: red, green: green, blue: blue, alpha: alpha) }
    }

    @ObjCMethod("initWithRed:green:blue:alpha:")
    func initialize(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> Self {
        state.set(red: red, green: green, blue: blue, alpha: alpha)
        return self
    }

    @ObjCClassMethod("colorWithWhite:alpha:")
    static func color(_ cls: ObjCClass, white: CGFloat, alpha: CGFloat) -> UIColor {
        make(cls) { $0.set(white: white, alpha: alpha) }
    }

    @ObjCMethod("initWithWhite:alpha:")
    func initialize(white: CGFloat, alpha: CGFloat) -> Self {
        state.set(white: white, alpha: alpha)
        return self
    }

    @ObjCClassMethod("colorWithHue:saturation:brightness:alpha:")
    static func color(_ cls: ObjCClass, hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) -> UIColor {
        let (r, g, b) = UIColor.rgb(hue: hue, saturation: saturation, brightness: brightness)
        return make(cls) { $0.set(red: r, green: g, blue: b, alpha: alpha) }
    }

    @ObjCMethod("initWithHue:saturation:brightness:alpha:")
    func initialize(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) -> Self {
        let (r, g, b) = UIColor.rgb(hue: hue, saturation: saturation, brightness: brightness)
        state.set(red: r, green: g, blue: b, alpha: alpha)
        return self
    }

    @ObjCClassMethod("colorWithCGColor:")
    static func color(_ cls: ObjCClass, cgColor: UnsafeMutableRawPointer?) -> UIColor {
        make(cls) { UIColor.set($0, from: cgColor) }
    }

    @ObjCMethod("initWithCGColor:")
    func initialize(cgColor: UnsafeMutableRawPointer?) -> Self {
        UIColor.set(state, from: cgColor)
        return self
    }

    /// The main bundle's asset catalog's color of that name, in the light
    /// appearance.
    @ObjCClassMethod("colorNamed:")
    static func color(_ cls: ObjCClass, named name: String) -> UIColor? {
        catalogColor(cls, AssetCatalog.color(named: name))
    }

    /// A bundle's asset catalog's color of that name, in the traits'
    /// appearance.
    @ObjCClassMethod("colorNamed:inBundle:compatibleWithTraitCollection:")
    static func color(_ cls: ObjCClass, named name: String, in bundle: NSObject?, compatibleWith traits: NSObject?) -> UIColor? {
        let dark = traits?.as(UITraitCollection.self)?.traits.style == 2
        guard let bundle = bundle?.as(NSBundle.self), bundle.objcObject != NSBundle.main().objcObject else {
            return catalogColor(cls, AssetCatalog.color(named: name, dark: dark))
        }
        return catalogColor(cls, AssetCatalog.catalog(in: bundle)?.color(named: name, dark: dark))
    }

    /// A color of a catalog's components: white and alpha, or red, green,
    /// blue and alpha.
    private static func catalogColor(_ cls: ObjCClass, _ components: [CGFloat]?) -> UIColor? {
        guard let components else { return nil }
        switch components.count {
        case 1, 2: return make(cls) { $0.set(white: components[0], alpha: components.count > 1 ? components[1] : 1) }
        case 3, 4, 5:
            return make(cls) { $0.set(red: components[0], green: components[1], blue: components[2], alpha: components.count > 3 ? components[3] : 1) }
        default: return nil
        }
    }

    /// Display P3 is taken as sRGB.
    @ObjCClassMethod("colorWithDisplayP3Red:green:blue:alpha:")
    static func color(_ cls: ObjCClass, displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> UIColor {
        make(cls) { $0.set(red: red, green: green, blue: blue, alpha: alpha) }
    }

    /// A dynamic color is its light appearance.
    /// From a nib: a named system color, or components.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        if let name = decoded.string("UISystemColorName"), UIColor.objCClass.object.responds(to: name) {
            typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
            if let named = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(UIColor.objCClass.pointer, ObjCRuntime.selector(name)) {
                let source = UIColor.states[named]
                (state.red, state.green, state.blue, state.alpha, state.white) = (source.red, source.green, source.blue, source.alpha, source.white)
                return self
            }
        }
        let alpha = decoded.has("UIAlpha") ? decoded.double("UIAlpha") : 1
        if decoded.integer("UIColorComponentCount") == 2 || (decoded.has("UIWhite") && !decoded.has("UIRed")) {
            state.set(white: decoded.double("UIWhite"), alpha: alpha)
        } else {
            state.set(red: decoded.double("UIRed"), green: decoded.double("UIGreen"), blue: decoded.double("UIBlue"), alpha: alpha)
        }
        return self
    }

    @ObjCClassMethod("colorWithDynamicProvider:")
    static func color(_ cls: ObjCClass, dynamicProvider provider: ObjCBlock) -> NSObject? {
        let resolved = resolve(provider, UITraitCollection.current())
        return make(cls) { state in
            if let resolved {
                let other = resolved.state
                (state.red, state.green, state.blue, state.alpha) = (other.red, other.green, other.blue, other.alpha)
                state.white = other.white
                state.patternImage = other.patternImage
            }
            state.provider = provider
        }
    }

    /// A dynamic color's provider's color for `traits`: the block is given
    /// a trait collection, which apps read without checking for nil, in the
    /// light appearance when `traits` leaves the appearance unspecified.
    private static func resolve(_ provider: ObjCBlock, _ traits: UITraitCollection) -> UIColor? {
        typealias Provider = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let traits = traits.traits.style == 0 ? traits.with(style: 1) : traits
        return provider.function(as: Provider.self)(provider.object, traits.objcObject)
            .map { UIColor(objcObject: $0, ownership: .retain) }
    }

    private static func set(_ state: ColorState, from cgColor: UnsafeMutableRawPointer?) {
        guard let cgColor, let components = CG.colorGetComponents(cgColor) else { return }
        if CG.colorGetNumberOfComponents(cgColor) == 2 {
            state.set(white: components[0], alpha: components[1])
        } else {
            state.set(red: components[0], green: components[1], blue: components[2], alpha: components[3])
        }
    }

    static func rgb(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let h = (hue - hue.rounded(.down)) * 6, sector = Int(h) % 6, f = h - h.rounded(.down)
        let p = brightness * (1 - saturation), q = brightness * (1 - saturation * f), t = brightness * (1 - saturation * (1 - f))
        switch sector {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    // MARK: Named colors

    @ObjCClassMethod("blackColor") static func black() -> UIColor { gray(0) }
    @ObjCClassMethod("darkGrayColor") static func darkGray() -> UIColor { gray(1.0 / 3) }
    @ObjCClassMethod("lightGrayColor") static func lightGray() -> UIColor { gray(2.0 / 3) }
    @ObjCClassMethod("whiteColor") static func white() -> UIColor { gray(1) }
    @ObjCClassMethod("grayColor") static func grayColor() -> UIColor { gray(0.5) }
    @ObjCClassMethod("clearColor") static func clear() -> UIColor { gray(0, 0) }
    @ObjCClassMethod("redColor") static func red() -> UIColor { rgb(1, 0, 0) }
    @ObjCClassMethod("greenColor") static func green() -> UIColor { rgb(0, 1, 0) }
    @ObjCClassMethod("blueColor") static func blue() -> UIColor { rgb(0, 0, 1) }
    @ObjCClassMethod("cyanColor") static func cyan() -> UIColor { rgb(0, 1, 1) }
    @ObjCClassMethod("yellowColor") static func yellow() -> UIColor { rgb(1, 1, 0) }
    @ObjCClassMethod("magentaColor") static func magenta() -> UIColor { rgb(1, 0, 1) }
    @ObjCClassMethod("orangeColor") static func orange() -> UIColor { rgb(1, 0.5, 0) }
    @ObjCClassMethod("purpleColor") static func purple() -> UIColor { rgb(0.5, 0, 0.5) }
    @ObjCClassMethod("brownColor") static func brown() -> UIColor { rgb(0.6, 0.4, 0.2) }

    // System colors, in their light appearance.
    @ObjCClassMethod("systemRedColor") static func systemRed() -> UIColor { rgb(1, 59.0 / 255, 48.0 / 255) }
    @ObjCClassMethod("systemOrangeColor") static func systemOrange() -> UIColor { rgb(1, 149.0 / 255, 0) }
    @ObjCClassMethod("systemYellowColor") static func systemYellow() -> UIColor { rgb(1, 204.0 / 255, 0) }
    @ObjCClassMethod("systemGreenColor") static func systemGreen() -> UIColor { rgb(52.0 / 255, 199.0 / 255, 89.0 / 255) }
    @ObjCClassMethod("systemTealColor") static func systemTeal() -> UIColor { rgb(48.0 / 255, 176.0 / 255, 199.0 / 255) }
    @ObjCClassMethod("systemBlueColor") static func systemBlue() -> UIColor { rgb(0, 122.0 / 255, 1) }
    @ObjCClassMethod("systemIndigoColor") static func systemIndigo() -> UIColor { rgb(88.0 / 255, 86.0 / 255, 214.0 / 255) }
    @ObjCClassMethod("systemPurpleColor") static func systemPurple() -> UIColor { rgb(175.0 / 255, 82.0 / 255, 222.0 / 255) }
    @ObjCClassMethod("systemPinkColor") static func systemPink() -> UIColor { rgb(1, 45.0 / 255, 85.0 / 255) }
    @ObjCClassMethod("systemGrayColor") static func systemGray() -> UIColor { rgb(142.0 / 255, 142.0 / 255, 147.0 / 255) }
    @ObjCClassMethod("systemGray2Color") static func systemGray2() -> UIColor { rgb(174.0 / 255, 174.0 / 255, 178.0 / 255) }
    @ObjCClassMethod("systemGray3Color") static func systemGray3() -> UIColor { rgb(199.0 / 255, 199.0 / 255, 204.0 / 255) }
    @ObjCClassMethod("systemGray4Color") static func systemGray4() -> UIColor { rgb(209.0 / 255, 209.0 / 255, 214.0 / 255) }
    @ObjCClassMethod("systemGray5Color") static func systemGray5() -> UIColor { rgb(229.0 / 255, 229.0 / 255, 234.0 / 255) }
    @ObjCClassMethod("systemGray6Color") static func systemGray6() -> UIColor { rgb(242.0 / 255, 242.0 / 255, 247.0 / 255) }
    @ObjCClassMethod("tintColor") static func tint() -> UIColor { systemBlue() }
    @ObjCClassMethod("linkColor") static func link() -> UIColor { systemBlue() }
    @ObjCClassMethod("labelColor") static func label() -> UIColor { gray(0) }
    @ObjCClassMethod("secondaryLabelColor") static func secondaryLabel() -> UIColor { rgb(60.0 / 255, 60.0 / 255, 67.0 / 255, 0.6) }
    @ObjCClassMethod("tertiaryLabelColor") static func tertiaryLabel() -> UIColor { rgb(60.0 / 255, 60.0 / 255, 67.0 / 255, 0.3) }
    @ObjCClassMethod("placeholderTextColor") static func placeholderText() -> UIColor { rgb(60.0 / 255, 60.0 / 255, 67.0 / 255, 0.3) }
    @ObjCClassMethod("separatorColor") static func separator() -> UIColor { rgb(60.0 / 255, 60.0 / 255, 67.0 / 255, 0.29) }
    @ObjCClassMethod("opaqueSeparatorColor") static func opaqueSeparator() -> UIColor { rgb(198.0 / 255, 198.0 / 255, 200.0 / 255) }
    @ObjCClassMethod("systemBackgroundColor") static func systemBackground() -> UIColor { gray(1) }
    @ObjCClassMethod("secondarySystemBackgroundColor") static func secondarySystemBackground() -> UIColor { systemGray6() }
    @ObjCClassMethod("tertiarySystemBackgroundColor") static func tertiarySystemBackground() -> UIColor { gray(1) }
    @ObjCClassMethod("systemGroupedBackgroundColor") static func systemGroupedBackground() -> UIColor { systemGray6() }
    @ObjCClassMethod("secondarySystemGroupedBackgroundColor") static func secondarySystemGroupedBackground() -> UIColor { gray(1) }
    @ObjCClassMethod("systemFillColor") static func systemFill() -> UIColor { rgb(120.0 / 255, 120.0 / 255, 128.0 / 255, 0.2) }

    // MARK: Components

    @ObjCMethod("getRed:green:blue:alpha:")
    func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?,
                alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        let state = state
        red?.pointee = state.red
        green?.pointee = state.green
        blue?.pointee = state.blue
        alpha?.pointee = state.alpha
        return true
    }

    /// Only a gray has a white level.
    @ObjCMethod("getWhite:alpha:")
    func getWhite(_ white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        guard let level = state.white else { return false }
        white?.pointee = level
        alpha?.pointee = state.alpha
        return true
    }

    @ObjCMethod("getHue:saturation:brightness:alpha:")
    func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?,
                brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        let (r, g, b) = (state.red, state.green, state.blue)
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        var h: CGFloat = 0
        if delta > 0 {
            if maximum == r { h = (g - b) / delta } else if maximum == g { h = 2 + (b - r) / delta } else { h = 4 + (r - g) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        hue?.pointee = h
        saturation?.pointee = maximum > 0 ? delta / maximum : 0
        brightness?.pointee = maximum
        alpha?.pointee = state.alpha
        return true
    }

    @ObjCMethod("colorWithAlphaComponent:")
    func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
        let source = state
        return UIColor.make(objCClass) { state in
            if let white = source.white { state.set(white: white, alpha: alpha) } else {
                state.set(red: source.red, green: source.green, blue: source.blue, alpha: alpha)
            }
        }
    }

    @ObjCMethod("alphaComponent") func alphaComponent() -> CGFloat { state.alpha }

    /// The color's CGColor, which the color owns.
    @ObjCMethod("CGColor") func cgColor() -> UnsafeMutableRawPointer? { state.makeCGColor() }

    /// A dynamic color's provider's color for `traits`; any other color is
    /// itself.
    @ObjCMethod("resolvedColorWithTraitCollection:")
    func resolvedColor(with traits: NSObject?) -> UIColor {
        guard let provider = state.provider else { return self }
        let collection = traits?.as(UITraitCollection.self) ?? UITraitCollection.current()
        return UIColor.resolve(provider, collection) ?? self
    }

    // MARK: Setting

    @ObjCMethod("set")
    func set() {
        setFill()
        setStroke()
    }

    @ObjCMethod("setFill")
    func setFill() {
        guard let context = Graphics.current else { return }
        CG.setFillColorWithColor(context, state.makeCGColor())
    }

    @ObjCMethod("setStroke")
    func setStroke() {
        guard let context = Graphics.current else { return }
        CG.setStrokeColorWithColor(context, state.makeCGColor())
    }

    // MARK: Comparing

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(UIColor.self) else { return false }
        let a = state, b = other.state
        return (a.white == nil) == (b.white == nil) && a.red == b.red && a.green == b.green && a.blue == b.blue && a.alpha == b.alpha
    }

    @ObjCMethod("hash")
    func hash() -> UInt {
        let s = state
        return UInt(s.red * 255) << 24 | UInt(s.green * 255) << 16 | UInt(s.blue * 255) << 8 | UInt(s.alpha * 255)
    }

    /// Colors are immutable.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String {
        let s = state
        if let white = s.white { return "UIExtendedGrayColorSpace \(format(white)) \(format(s.alpha))" }
        return "UIExtendedSRGBColorSpace \(format(s.red)) \(format(s.green)) \(format(s.blue)) \(format(s.alpha))"
    }
}

extension NSObject {
    /// A UIColor's CGColor.
    @ObjCMethod("CGColor") func sendCGColor() -> UnsafeMutableRawPointer?
}
