import CPerryGeometry
import PerryObjCInterop
import SDL3Swift

// NSCursor: a cursor made from an image is SDL's cursor of that image once
// it's set (one with nothing to see hides the cursor, as games' blank
// cursors do on a Mac); the system cursors are SDL's default arrow. Hiding
// it hides SDL's cursor, as many times as it was hidden, as AppKit counts.

@ObjCClass("NSCursor")
open class NSCursor: NSObject {
    var image: NSObject?
    var hotSpot = CGPoint.zero
    var name = "arrow"

    nonisolated(unsafe) static var named: [String: NSCursor] = [:]
    nonisolated(unsafe) static var current: NSCursor?
    nonisolated(unsafe) static var stack: [NSCursor] = []
    nonisolated(unsafe) static var hideCount = 0
    /// SDL's cursor of the image, made the first time this is set; nil for
    /// the default arrow.
    private var sdlCursor: SDLCursor?
    private var prepared = false
    /// Whether the image has nothing to see.
    private var blank = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithImage:hotSpot:")
    public required init(image: NSObject?, hotSpot: CGPoint) {
        super.init()
        self.image = image
        self.hotSpot = hotSpot
        name = "image"
    }

    static func system(_ name: String) -> NSCursor {
        if let cursor = named[name] { return cursor }
        let cursor = NSCursor()
        cursor.name = name
        named[name] = cursor
        return cursor
    }

    @ObjCClassMethod("arrowCursor") static func arrowCursor() -> NSCursor { system("arrow") }
    @ObjCClassMethod("IBeamCursor") static func iBeamCursor() -> NSCursor { system("IBeam") }
    @ObjCClassMethod("pointingHandCursor") static func pointingHandCursor() -> NSCursor { system("pointingHand") }
    @ObjCClassMethod("crosshairCursor") static func crosshairCursor() -> NSCursor { system("crosshair") }
    @ObjCClassMethod("closedHandCursor") static func closedHandCursor() -> NSCursor { system("closedHand") }
    @ObjCClassMethod("openHandCursor") static func openHandCursor() -> NSCursor { system("openHand") }
    @ObjCClassMethod("operationNotAllowedCursor") static func operationNotAllowedCursor() -> NSCursor { system("operationNotAllowed") }
    @ObjCClassMethod("resizeUpCursor") static func resizeUpCursor() -> NSCursor { system("resizeUp") }
    @ObjCClassMethod("resizeDownCursor") static func resizeDownCursor() -> NSCursor { system("resizeDown") }
    @ObjCClassMethod("resizeUpDownCursor") static func resizeUpDownCursor() -> NSCursor { system("resizeUpDown") }
    @ObjCClassMethod("resizeLeftCursor") static func resizeLeftCursor() -> NSCursor { system("resizeLeft") }
    @ObjCClassMethod("resizeRightCursor") static func resizeRightCursor() -> NSCursor { system("resizeRight") }
    @ObjCClassMethod("resizeLeftRightCursor") static func resizeLeftRightCursor() -> NSCursor { system("resizeLeftRight") }
    @ObjCClassMethod("disappearingItemCursor") static func disappearingItemCursor() -> NSCursor { system("disappearingItem") }
    @ObjCClassMethod("dragCopyCursor") static func dragCopyCursor() -> NSCursor { system("dragCopy") }
    @ObjCClassMethod("dragLinkCursor") static func dragLinkCursor() -> NSCursor { system("dragLink") }
    @ObjCClassMethod("contextualMenuCursor") static func contextualMenuCursor() -> NSCursor { system("contextualMenu") }
    @ObjCClassMethod("IBeamCursorForVerticalLayout") static func iBeamCursorForVerticalLayout() -> NSCursor { system("IBeamVertical") }
    @ObjCClassMethod("currentCursor") static func currentCursor() -> NSCursor { current ?? arrowCursor() }
    @ObjCClassMethod("currentSystemCursor") static func currentSystemCursor() -> NSCursor? { current ?? arrowCursor() }

    @ObjCClassMethod("hide")
    static func hide() {
        hideCount += 1
        if hideCount == 1, SDLSession.start() { SDL.isCursorVisible = false }
    }

    @ObjCClassMethod("unhide")
    static func unhide() {
        guard hideCount > 0 else { return }
        hideCount -= 1
        if hideCount == 0, current?.blank != true, SDLSession.start() { SDL.isCursorVisible = true }
    }

    /// Shows `cursor` as SDL's: its image's, or the default arrow; hidden
    /// for a blank image or while the cursor is hidden.
    static func show(_ cursor: NSCursor?) {
        guard SDLSession.start() else { return }
        cursor?.prepare()
        if cursor?.blank == true {
            SDL.isCursorVisible = false
            return
        }
        SDL.setCursor(cursor?.sdlCursor)
        if hideCount == 0 { SDL.isCursorVisible = true }
    }

    /// The image's pixels as SDL's cursor, once.
    private func prepare() {
        guard !prepared else { return }
        prepared = true
        guard let image, CG.ready else { return }
        // An image with nothing in it (no bitmap, or none of any size), as
        // games make for a cursor that isn't seen, draws nothing.
        guard let cgImage = NSCursor.bitmap(of: image), CG.imageGetWidth(cgImage) > 0, CG.imageGetHeight(cgImage) > 0 else {
            Trace.log("NSCursor: an empty image: hidden while set")
            blank = true
            return
        }
        let width = CG.imageGetWidth(cgImage), height = CG.imageGetHeight(cgImage)
        guard let space = CG.colorSpaceCreateDeviceRGB(),
              let surface = try? SDLSurface(format: .argb8888, size: (width, height)) else { return }
        defer { CG.release(space) }
        // Premultiplied alpha first in 32-bit little-endian words, SDL's
        // ARGB8888, drawn into the surface from the top row down.
        let visible = try? surface.withUnsafeMutableBytes { pixels -> Bool in
            guard let context = CG.bitmapContextCreate(pixels, width, height, 8, surface.pitch, space, 2 | 0x2000) else { return false }
            defer { CG.release(context) }
            CG.drawImage(context, CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), cgImage)
            return (0..<height).contains { row in
                let words = (pixels + row * surface.pitch).assumingMemoryBound(to: UInt32.self)
                return (0..<width).contains { words[$0] >> 24 != 0 }
            }
        }
        guard let visible else { return }
        guard visible else {
            Trace.log("NSCursor: a blank \(width)×\(height) image: hidden while set")
            blank = true
            return
        }
        // The hot spot is in the image's points, from its top left.
        var points = image.as(NSImage.self)?.size ?? .zero
        if points.width <= 0 || points.height <= 0 { points = CGSize(width: CGFloat(width), height: CGFloat(height)) }
        let hotX = Int(min(max(hotSpot.x * CGFloat(width) / points.width, 0), CGFloat(width - 1)))
        let hotY = Int(min(max(hotSpot.y * CGFloat(height) / points.height, 0), CGFloat(height - 1)))
        sdlCursor = try? SDLCursor(surface: surface, hotspot: (hotX, hotY))
        Trace.log("NSCursor: a \(width)×\(height) image, hot spot \(hotSpot)")
    }

    /// An NSImage's bitmap, or its first bitmap representation's.
    private static func bitmap(of image: NSObject) -> UnsafeMutableRawPointer? {
        guard let image = image.as(NSImage.self) else { return image.as(NSBitmapImageRep.self)?.cgImage() }
        if let bitmap = image.bitmap() { return bitmap }
        return image.representations.lazy.compactMap { $0.as(NSBitmapImageRep.self)?.cgImage() }.first
    }

    @ObjCClassMethod("setHiddenUntilMouseMoves:") static func setHiddenUntilMouseMoves(_ hidden: Bool) {}

    @ObjCMethod("set")
    func set() {
        NSCursor.current = self
        NSCursor.show(self)
    }
    @ObjCMethod("push")
    func push() {
        NSCursor.stack.append(NSCursor.currentCursor())
        set()
    }
    @ObjCMethod("pop") func pop() { NSCursor.classPop() }
    @ObjCClassMethod("pop")
    static func classPop() {
        current = stack.popLast()
        show(current)
    }
    @ObjCMethod("image") func cursorImage() -> NSObject? { image }
    @ObjCMethod("hotSpot") func cursorHotSpot() -> CGPoint { hotSpot }
    @ObjCMethod("setOnMouseEntered:") func setOnMouseEntered(_ value: Bool) {}
    @ObjCMethod("setOnMouseExited:") func setOnMouseExited(_ value: Bool) {}
    @ObjCMethod("mouseEntered:") func mouseEntered(_ event: NSObject?) { set() }
    @ObjCMethod("mouseExited:") func mouseExited(_ event: NSObject?) {}
}
