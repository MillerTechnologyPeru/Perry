import CPerryGeometry
import PerryObjCInterop

// NSScreen: the primary display SDL reports, in AppKit's screen
// coordinates (points, origin at the bottom left of the main screen, y
// up). Its backing scale is the display's pixels per point. Without a
// display it is 1920 by 1080 points at 1x, at 60 frames a second.

/// NSEdgeInsets: top, left, bottom, right, as UIEdgeInsets.
typealias NSEdgeInsets = UIEdgeInsets

extension UIEdgeInsets: ObjCScalar {
    public static var objCTypeEncoding: String { "{NSEdgeInsets=dddd}" }
}

enum Screens {
    nonisolated(unsafe) private static var cached: SDLSession.Display?
    nonisolated(unsafe) private static var fetched = false

    /// The display, asked of SDL once; screen changes aren't followed.
    static var display: SDLSession.Display {
        if !fetched {
            fetched = true
            cached = SDLSession.primary()
        }
        return cached ?? SDLSession.Display(bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     usable: CGRect(x: 0, y: 0, width: 1920, height: 1080), density: 1, refreshRate: 60)
    }

    /// The main screen's height, which flips SDL's y into AppKit's.
    static var height: CGFloat { display.bounds.height }

    /// A rectangle in SDL's display coordinates (top-left origin) in
    /// AppKit's screen coordinates, and back: the same flip both ways.
    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    nonisolated(unsafe) static var main: NSScreen?
}

@ObjCClass("NSScreen")
open class NSScreen: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCClassMethod("mainScreen")
    static func mainScreen() -> NSScreen? {
        if let main = Screens.main { return main }
        let screen = NSScreen()
        Screens.main = screen
        return screen
    }

    @ObjCClassMethod("deepestScreen") static func deepestScreen() -> NSScreen? { mainScreen() }

    @ObjCClassMethod("screens")
    static func screens() -> NSObject { NSMutableArray.of(mainScreen().map { [$0] } ?? []) }

    @ObjCClassMethod("screensHaveSeparateSpaces") static func screensHaveSeparateSpaces() -> Bool { false }

    @ObjCMethod("frame") func frame() -> CGRect { Screens.flip(Screens.display.bounds) }
    @ObjCMethod("visibleFrame") func visibleFrame() -> CGRect { Screens.flip(Screens.display.usable) }
    @ObjCMethod("backingScaleFactor") func backingScaleFactor() -> CGFloat { Screens.display.density }
    @ObjCMethod("userSpaceScaleFactor") func userSpaceScaleFactor() -> CGFloat { 1 }
    @ObjCMethod("localizedName") func localizedName() -> String { "Display" }
    @ObjCMethod("maximumFramesPerSecond") func maximumFramesPerSecond() -> Int { Int(Screens.display.refreshRate.rounded()) }
    @ObjCMethod("minimumRefreshInterval") func minimumRefreshInterval() -> Double { 1 / Screens.display.refreshRate }
    @ObjCMethod("maximumRefreshInterval") func maximumRefreshInterval() -> Double { 1 / Screens.display.refreshRate }
    @ObjCMethod("displayUpdateGranularity") func displayUpdateGranularity() -> Double { 0 }
    @ObjCMethod("lastDisplayUpdateTimestamp") func lastDisplayUpdateTimestamp() -> Double { Clock.now }
    /// NSWindowDepth: 24 bits of RGB.
    @ObjCMethod("depth") func depth() -> Int32 { 0x208 }
    @ObjCMethod("colorSpace") func colorSpace() -> NSObject? { nil }
    @ObjCMethod("safeAreaInsets") func safeAreaInsets() -> NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    @ObjCMethod("auxiliaryTopLeftArea") func auxiliaryTopLeftArea() -> CGRect { .zero }
    @ObjCMethod("auxiliaryTopRightArea") func auxiliaryTopRightArea() -> CGRect { .zero }
    @ObjCMethod("maximumExtendedDynamicRangeColorComponentValue") func maximumEDR() -> CGFloat { 1 }
    @ObjCMethod("maximumPotentialExtendedDynamicRangeColorComponentValue") func maximumPotentialEDR() -> CGFloat { 1 }
    @ObjCMethod("maximumReferenceExtendedDynamicRangeColorComponentValue") func maximumReferenceEDR() -> CGFloat { 0 }

    /// NSScreenNumber (the CGDirectDisplayID, 1), NSDeviceSize,
    /// NSDeviceResolution (72 dpi a point) and NSDeviceIsScreen.
    @ObjCMethod("deviceDescription")
    func deviceDescription() -> NSObject {
        let description = NSMutableDictionary.empty()
        description.set(NSNumber.make(unsignedInt: 1), forKey: "NSScreenNumber")
        description.set(NSValue.boxing(Screens.display.bounds.size), forKey: Constants.NSDeviceSize)
        let dpi = 72 * Screens.display.density
        description.set(NSValue.boxing(CGSize(width: dpi, height: dpi)), forKey: Constants.NSDeviceResolution)
        description.set(NSNumber.make(bool: true), forKey: Constants.NSDeviceIsScreen)
        return description
    }

    @ObjCMethod("convertRectToBacking:")
    func convertRectToBacking(_ rect: CGRect) -> CGRect { Backing.scale(rect, by: Screens.display.density) }
    @ObjCMethod("convertRectFromBacking:")
    func convertRectFromBacking(_ rect: CGRect) -> CGRect { Backing.scale(rect, by: 1 / Screens.display.density) }
    @ObjCMethod("backingAlignedRect:options:")
    func backingAlignedRect(_ rect: CGRect, options: UInt64) -> CGRect { Backing.aligned(rect, scale: Screens.display.density) }
}

/// Conversions between points and a backing store's pixels.
enum Backing {
    static func scale(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    static func scale(_ point: CGPoint, by scale: CGFloat) -> CGPoint { CGPoint(x: point.x * scale, y: point.y * scale) }
    static func scale(_ size: CGSize, by scale: CGFloat) -> CGSize { CGSize(width: size.width * scale, height: size.height * scale) }

    /// The rectangle's edges moved out to whole pixels.
    static func aligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded(.down) / scale, minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale, maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
