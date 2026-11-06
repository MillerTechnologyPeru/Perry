import CPerryGeometry
import PerryObjCInterop

// NSCursor: the cursor's shape is kept but not shown (the desktop's own
// arrow stays); hiding it hides SDL's cursor, as many times as it was
// hidden, as AppKit counts.

@ObjCClass("NSCursor")
open class NSCursor: NSObject {
    var image: NSObject?
    var hotSpot = CGPoint.zero
    var name = "arrow"

    nonisolated(unsafe) static var named: [String: NSCursor] = [:]
    nonisolated(unsafe) static var current: NSCursor?
    nonisolated(unsafe) static var stack: [NSCursor] = []
    nonisolated(unsafe) static var hideCount = 0

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
        if hideCount == 1, SDL.start() { _ = SDL.hideCursor() }
    }

    @ObjCClassMethod("unhide")
    static func unhide() {
        guard hideCount > 0 else { return }
        hideCount -= 1
        if hideCount == 0, SDL.start() { _ = SDL.showCursor() }
    }

    @ObjCClassMethod("setHiddenUntilMouseMoves:") static func setHiddenUntilMouseMoves(_ hidden: Bool) {}

    @ObjCMethod("set") func set() { NSCursor.current = self }
    @ObjCMethod("push")
    func push() {
        NSCursor.stack.append(NSCursor.currentCursor())
        set()
    }
    @ObjCMethod("pop") func pop() { NSCursor.current = NSCursor.stack.popLast() }
    @ObjCClassMethod("pop") static func classPop() { current = stack.popLast() }
    @ObjCMethod("image") func cursorImage() -> NSObject? { image }
    @ObjCMethod("hotSpot") func cursorHotSpot() -> CGPoint { hotSpot }
    @ObjCMethod("setOnMouseEntered:") func setOnMouseEntered(_ value: Bool) {}
    @ObjCMethod("setOnMouseExited:") func setOnMouseExited(_ value: Bool) {}
    @ObjCMethod("mouseEntered:") func mouseEntered(_ event: NSObject?) { set() }
    @ObjCMethod("mouseExited:") func mouseExited(_ event: NSObject?) {}
}
