import CPerryGeometry
import PerryObjCInterop

// NSColor, NSFont, NSImage and NSGraphicsContext, as values: colors keep
// their components, fonts their name and size, images their size and
// where they came from. Views don't draw with them here.

@ObjCClass("NSColor")
open class NSColor: NSObject {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1

    @ObjCMethod("init")
    public required override init() { super.init() }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        super.init()
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
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
    static func color(white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: white, green: white, blue: white, alpha: alpha) }
    @ObjCClassMethod("colorWithCalibratedWhite:alpha:")
    static func color(calibratedWhite white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: white, green: white, blue: white, alpha: alpha) }
    @ObjCClassMethod("colorWithDeviceWhite:alpha:")
    static func color(deviceWhite white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: white, green: white, blue: white, alpha: alpha) }
    @ObjCClassMethod("colorWithGenericGamma22White:alpha:")
    static func color(gamma22White white: CGFloat, alpha: CGFloat) -> NSColor { NSColor(red: white, green: white, blue: white, alpha: alpha) }

    @ObjCClassMethod("clearColor") static func clearColor() -> NSColor { NSColor(red: 0, green: 0, blue: 0, alpha: 0) }
    @ObjCClassMethod("blackColor") static func blackColor() -> NSColor { NSColor(red: 0, green: 0, blue: 0, alpha: 1) }
    @ObjCClassMethod("whiteColor") static func whiteColor() -> NSColor { NSColor(red: 1, green: 1, blue: 1, alpha: 1) }
    @ObjCClassMethod("grayColor") static func grayColor() -> NSColor { NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1) }
    @ObjCClassMethod("lightGrayColor") static func lightGrayColor() -> NSColor { NSColor(red: 2.0 / 3, green: 2.0 / 3, blue: 2.0 / 3, alpha: 1) }
    @ObjCClassMethod("darkGrayColor") static func darkGrayColor() -> NSColor { NSColor(red: 1.0 / 3, green: 1.0 / 3, blue: 1.0 / 3, alpha: 1) }
    @ObjCClassMethod("redColor") static func redColor() -> NSColor { NSColor(red: 1, green: 0, blue: 0, alpha: 1) }
    @ObjCClassMethod("greenColor") static func greenColor() -> NSColor { NSColor(red: 0, green: 1, blue: 0, alpha: 1) }
    @ObjCClassMethod("blueColor") static func blueColor() -> NSColor { NSColor(red: 0, green: 0, blue: 1, alpha: 1) }
    @ObjCClassMethod("yellowColor") static func yellowColor() -> NSColor { NSColor(red: 1, green: 1, blue: 0, alpha: 1) }
    @ObjCClassMethod("orangeColor") static func orangeColor() -> NSColor { NSColor(red: 1, green: 0.5, blue: 0, alpha: 1) }
    @ObjCClassMethod("windowBackgroundColor") static func windowBackgroundColor() -> NSColor { NSColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1) }
    @ObjCClassMethod("controlColor") static func controlColor() -> NSColor { whiteColor() }
    @ObjCClassMethod("controlBackgroundColor") static func controlBackgroundColor() -> NSColor { whiteColor() }
    @ObjCClassMethod("textColor") static func textColor() -> NSColor { blackColor() }
    @ObjCClassMethod("labelColor") static func labelColor() -> NSColor { NSColor(red: 0, green: 0, blue: 0, alpha: 0.85) }
    @ObjCClassMethod("secondaryLabelColor") static func secondaryLabelColor() -> NSColor { NSColor(red: 0, green: 0, blue: 0, alpha: 0.5) }
    @ObjCClassMethod("textBackgroundColor") static func textBackgroundColor() -> NSColor { whiteColor() }
    @ObjCClassMethod("selectedTextBackgroundColor") static func selectedTextBackgroundColor() -> NSColor { NSColor(red: 0.7, green: 0.84, blue: 1, alpha: 1) }
    @ObjCClassMethod("controlAccentColor") static func controlAccentColor() -> NSColor { NSColor(red: 0, green: 0.48, blue: 1, alpha: 1) }
    @ObjCClassMethod("systemBlueColor") static func systemBlueColor() -> NSColor { controlAccentColor() }
    @ObjCClassMethod("systemRedColor") static func systemRedColor() -> NSColor { NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 1) }

    @ObjCMethod("redComponent") func redComponent() -> CGFloat { red }
    @ObjCMethod("greenComponent") func greenComponent() -> CGFloat { green }
    @ObjCMethod("blueComponent") func blueComponent() -> CGFloat { blue }
    @ObjCMethod("alphaComponent") func alphaComponent() -> CGFloat { alpha }
    @ObjCMethod("whiteComponent") func whiteComponent() -> CGFloat { (red + green + blue) / 3 }
    @ObjCMethod("numberOfComponents") func numberOfComponents() -> Int { 4 }
    @ObjCMethod("getRed:green:blue:alpha:")
    func get(red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?,
             alpha: UnsafeMutablePointer<CGFloat>?) {
        red?.pointee = self.red
        green?.pointee = self.green
        blue?.pointee = self.blue
        alpha?.pointee = self.alpha
    }
    @ObjCMethod("colorWithAlphaComponent:")
    func withAlphaComponent(_ alpha: CGFloat) -> NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
    @ObjCMethod("colorUsingColorSpace:") func usingColorSpace(_ space: NSObject?) -> NSColor? { self }
    @ObjCMethod("colorUsingColorSpaceName:") func usingColorSpaceName(_ name: NSObject?) -> NSColor? { self }
    @ObjCMethod("colorUsingType:") func usingType(_ type: Int) -> NSColor? { self }
    @ObjCMethod("colorSpaceName") func colorSpaceName() -> String { Constants.NSCalibratedRGBColorSpace }
    @ObjCMethod("CGColor") func cgColor() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("set") func set() {}
    @ObjCMethod("setFill") func setFill() {}
    @ObjCMethod("setStroke") func setStroke() {}
}

@ObjCClass("NSFont")
open class NSFont: NSObject {
    var name = ".AppleSystemUIFont"
    var size: CGFloat = 13

    @ObjCMethod("init")
    public required override init() { super.init() }

    init(name: String, size: CGFloat) {
        super.init()
        self.name = name
        self.size = size > 0 ? size : 13
    }

    @ObjCClassMethod("systemFontOfSize:") static func systemFont(ofSize size: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFont", size: size) }
    @ObjCClassMethod("systemFontOfSize:weight:")
    static func systemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFont", size: size) }
    @ObjCClassMethod("boldSystemFontOfSize:") static func boldSystemFont(ofSize size: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFontBold", size: size) }
    @ObjCClassMethod("monospacedSystemFontOfSize:weight:")
    static func monospacedSystemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFontMonospaced", size: size) }
    @ObjCClassMethod("monospacedDigitSystemFontOfSize:weight:")
    static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFont", size: size) }
    @ObjCClassMethod("labelFontOfSize:") static func labelFont(ofSize size: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFont", size: size) }
    @ObjCClassMethod("messageFontOfSize:") static func messageFont(ofSize size: CGFloat) -> NSFont { NSFont(name: ".AppleSystemUIFont", size: size) }
    @ObjCClassMethod("userFontOfSize:") static func userFont(ofSize size: CGFloat) -> NSFont { NSFont(name: "Helvetica", size: size) }
    @ObjCClassMethod("userFixedPitchFontOfSize:") static func userFixedPitchFont(ofSize size: CGFloat) -> NSFont { NSFont(name: "Menlo-Regular", size: size) }
    @ObjCClassMethod("fontWithName:size:") static func font(name: String?, size: CGFloat) -> NSFont? { NSFont(name: name ?? "Helvetica", size: size) }
    @ObjCClassMethod("systemFontSize") static func systemFontSize() -> CGFloat { 13 }
    @ObjCClassMethod("smallSystemFontSize") static func smallSystemFontSize() -> CGFloat { 11 }
    @ObjCClassMethod("labelFontSize") static func labelFontSize() -> CGFloat { 10 }
    @ObjCClassMethod("systemFontSizeForControlSize:") static func systemFontSize(forControlSize size: UInt) -> CGFloat { [13, 11, 9, 13][Int(min(size, 3))] }

    @ObjCMethod("fontName") func fontName() -> String { name }
    @ObjCMethod("familyName") func familyName() -> String { name }
    @ObjCMethod("displayName") func displayName() -> String { name }
    @ObjCMethod("pointSize") func pointSize() -> CGFloat { size }
    @ObjCMethod("ascender") func ascender() -> CGFloat { size * 0.95 }
    @ObjCMethod("descender") func descender() -> CGFloat { -size * 0.25 }
    @ObjCMethod("leading") func leading() -> CGFloat { 0 }
    @ObjCMethod("capHeight") func capHeight() -> CGFloat { size * 0.7 }
    @ObjCMethod("xHeight") func xHeight() -> CGFloat { size * 0.52 }
    @ObjCMethod("fontWithSize:") func withSize(_ size: CGFloat) -> NSFont { NSFont(name: name, size: size) }
}

@ObjCClass("NSImage")
open class NSImage: NSObject {
    var size = CGSize.zero
    var name: String?
    var path: String?
    var data: NSObject?
    var template = false
    var representations: [NSObject] = []

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
    }

    @ObjCMethod("initByReferencingFile:")
    public required init(referencingFile path: String?) {
        super.init()
        self.path = path
    }

    @ObjCMethod("initWithContentsOfURL:")
    public required init(contentsOf url: NSObject?) {
        super.init()
        path = url?.as(NSURL.self)?.absoluteString()
    }

    @ObjCMethod("initWithData:")
    public required init(data: NSObject?) {
        super.init()
        self.data = data
    }

    @ObjCMethod("initWithCGImage:size:")
    public required init(cgImage: UnsafeMutableRawPointer?, size: CGSize) {
        super.init()
        self.size = size
    }

    /// Named images: the system's are blank, of the size apps expect.
    @ObjCClassMethod("imageNamed:")
    static func image(named name: String?) -> NSImage? {
        guard let name else { return nil }
        if let image = named[name] { return image }
        let image = NSImage(size: CGSize(width: 32, height: 32))
        image.name = name
        named[name] = image
        return image
    }

    @ObjCClassMethod("imageWithSystemSymbolName:accessibilityDescription:")
    static func image(systemSymbolName name: String?, accessibilityDescription: String?) -> NSImage? { image(named: name) }

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
    func cgImage(forProposedRect rect: UnsafeMutablePointer<CGRect>?, context: NSObject?, hints: NSObject?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("TIFFRepresentation") func tiffRepresentation() -> NSObject? { nil }
    @ObjCMethod("lockFocus") func lockFocus() {}
    @ObjCMethod("unlockFocus") func unlockFocus() {}
    @ObjCMethod("drawInRect:") func draw(in rect: CGRect) {}
    @ObjCMethod("drawInRect:fromRect:operation:fraction:")
    func draw(in rect: CGRect, from source: CGRect, operation: UInt, fraction: CGFloat) {}
    @ObjCMethod("drawAtPoint:fromRect:operation:fraction:")
    func draw(at point: CGPoint, from source: CGRect, operation: UInt, fraction: CGFloat) {}
    @ObjCMethod("setAccessibilityDescription:") func setAccessibilityDescription(_ text: String?) {}
}

@ObjCClass("NSGraphicsContext")
open class NSGraphicsContext: NSObject {
    nonisolated(unsafe) static var current: NSGraphicsContext?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("currentContext") static func currentContext() -> NSGraphicsContext? { current }
    @ObjCClassMethod("setCurrentContext:") static func setCurrentContext(_ context: NSGraphicsContext?) { current = context }
    @ObjCClassMethod("graphicsContextWithWindow:") static func graphicsContext(with window: NSObject?) -> NSGraphicsContext? { NSGraphicsContext() }
    @ObjCClassMethod("graphicsContextWithCGContext:flipped:")
    static func graphicsContext(cgContext: UnsafeMutableRawPointer?, flipped: Bool) -> NSGraphicsContext? { NSGraphicsContext() }
    @ObjCClassMethod("saveGraphicsState") static func classSaveGraphicsState() {}
    @ObjCClassMethod("restoreGraphicsState") static func classRestoreGraphicsState() {}
    @ObjCMethod("saveGraphicsState") func saveGraphicsState() {}
    @ObjCMethod("restoreGraphicsState") func restoreGraphicsState() {}
    @ObjCMethod("flushGraphics") func flushGraphics() {}
    @ObjCMethod("CGContext") func cgContext() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("isFlipped") func isFlipped() -> Bool { false }
    @ObjCMethod("setImageInterpolation:") func setImageInterpolation(_ value: UInt) {}
    @ObjCMethod("setShouldAntialias:") func setShouldAntialias(_ value: Bool) {}
}
