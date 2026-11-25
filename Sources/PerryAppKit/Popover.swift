import CPerryGeometry
import PerryObjCInterop

// NSPopover: a view controller's view shown beside a rectangle of another
// view. Here it shows in a borderless window placed against the edge it
// prefers, with no arrow and no animation; it closes when told to (or
// when its delegate agrees to -performClose:), as an application-defined
// popover does: a transient one doesn't close on a click outside it.

@ObjCConstants
enum PopoverNames {
    static let NSPopoverWillShowNotification = "NSPopoverWillShowNotification"
    static let NSPopoverDidShowNotification = "NSPopoverDidShowNotification"
    static let NSPopoverWillCloseNotification = "NSPopoverWillCloseNotification"
    static let NSPopoverDidCloseNotification = "NSPopoverDidCloseNotification"
    static let NSPopoverCloseReasonKey = "NSPopoverCloseReasonKey"
    static let NSPopoverCloseReasonStandard = "NSPopoverCloseReasonStandard"
    static let NSPopoverCloseReasonDetachToWindow = "NSPopoverCloseReasonDetachToWindow"
}

@ObjCClass("NSPopover")
open class NSPopover: NSResponder {
    var contentViewController: NSViewController?
    var contentSize = CGSize.zero
    /// NSPopoverBehavior: application-defined 0, transient 1, semitransient 2.
    var behavior = 0
    var animates = true
    var appearance: NSObject?
    /// Not retained.
    var delegateObject: UnsafeMutableRawPointer?
    var positioningRect = CGRect.zero
    var popoverWindow: NSWindow?

    @ObjCMethod("contentViewController") func popoverContentViewController() -> NSViewController? { contentViewController }
    @ObjCMethod("setContentViewController:") func setContentViewController(_ value: NSViewController?) { contentViewController = value }

    /// The size set, or the content view's.
    @ObjCMethod("contentSize")
    func popoverContentSize() -> CGSize {
        if contentSize != .zero { return contentSize }
        return contentViewController?.view()?.frame.size ?? .zero
    }

    @ObjCMethod("setContentSize:")
    func setContentSize(_ value: CGSize) {
        contentSize = value
        guard let popoverWindow else { return }
        let frame = popoverWindow.frame
        popoverWindow.setFrame(CGRect(x: frame.minX, y: frame.maxY - value.height, width: value.width, height: value.height), display: true)
    }

    @ObjCMethod("behavior") func popoverBehavior() -> Int { behavior }
    @ObjCMethod("setBehavior:") func setBehavior(_ value: Int) { behavior = value }
    @ObjCMethod("animates") func popoverAnimates() -> Bool { animates }
    @ObjCMethod("setAnimates:") func setAnimates(_ value: Bool) { animates = value }
    @ObjCMethod("appearance") func popoverAppearance() -> NSObject? { appearance }
    @ObjCMethod("setAppearance:") func setAppearance(_ value: NSObject?) { appearance = value }
    @ObjCMethod("effectiveAppearance") func effectiveAppearance() -> NSObject { appearance ?? NSAppearance.currentAppearance() }
    @ObjCMethod("delegate") func popoverDelegate() -> NSObject? { delegateObject.map(NSObject.init) }
    @ObjCMethod("setDelegate:") func setDelegate(_ value: NSObject?) { delegateObject = value?.objcObject }
    @ObjCMethod("isShown") func isShown() -> Bool { popoverWindow != nil }
    @ObjCMethod("isDetached") func isDetached() -> Bool { false }
    @ObjCMethod("positioningRect") func popoverPositioningRect() -> CGRect { positioningRect }
    @ObjCMethod("setPositioningRect:") func setPositioningRect(_ value: CGRect) { positioningRect = value }

    /// Shows the content against `rect` of `view` (its bounds when empty),
    /// on the preferred NSRectEdge (min x 0, min y 1, max x 2, max y 3, in
    /// the view's coordinates), centered along it.
    @ObjCMethod("showRelativeToRect:ofView:preferredEdge:")
    func show(relativeTo rect: CGRect, of view: NSView?, preferredEdge: UInt) {
        guard let controller = contentViewController, let view, let window = view.window, controller.view() != nil else { return }
        if popoverWindow != nil { close() }
        positioningRect = rect == .zero ? view.bounds : rect
        let anchor = window.convertRect(toScreen: view.convert(positioningRect, to: nil))
        let size = popoverContentSize()
        var edge = preferredEdge
        // A flipped view's min y is its top, which is max y on the screen.
        if view.flipped, edge == 1 || edge == 3 { edge = 4 - edge }
        let origin: CGPoint
        switch edge {
        case 0: origin = CGPoint(x: anchor.minX - size.width, y: anchor.minY + (anchor.height - size.height) / 2)
        case 2: origin = CGPoint(x: anchor.maxX, y: anchor.minY + (anchor.height - size.height) / 2)
        case 3: origin = CGPoint(x: anchor.minX + (anchor.width - size.width) / 2, y: anchor.maxY)
        default: origin = CGPoint(x: anchor.minX + (anchor.width - size.width) / 2, y: anchor.minY - size.height)
        }
        notify("popoverWillShow:", PopoverNames.NSPopoverWillShowNotification)
        let shown = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: 0, backing: 2, defer: false)
        shown.releasedWhenClosed = false
        shown.setContentViewController(controller)
        popoverWindow = shown
        shown.makeKeyAndOrderFront(nil)
        notify("popoverDidShow:", PopoverNames.NSPopoverDidShowNotification)
    }

    /// Closes it, if its delegate (-popoverShouldClose:) agrees.
    @ObjCMethod("performClose:")
    func performClose(_ sender: NSObject?) {
        if Send.responds(delegateObject, "popoverShouldClose:"), !Send.bool(delegateObject, "popoverShouldClose:", objcObject) { return }
        close()
    }

    @ObjCMethod("close")
    func close() {
        guard let shown = popoverWindow else { return }
        notify("popoverWillClose:", PopoverNames.NSPopoverWillCloseNotification)
        popoverWindow = nil
        shown.close()
        notify("popoverDidClose:", PopoverNames.NSPopoverDidCloseNotification)
    }

    /// The notification, to the delegate and then the default center; its
    /// close reason is the standard one.
    private func notify(_ selector: String, _ name: String) {
        var userInfo: NSObject?
        if name == PopoverNames.NSPopoverWillCloseNotification || name == PopoverNames.NSPopoverDidCloseNotification {
            let info = NSMutableDictionary.empty()
            info.set(NSObject(PopoverNames.NSPopoverCloseReasonStandardObject), forKey: PopoverNames.NSPopoverCloseReasonKey)
            userInfo = info
        }
        let notification = NSNotification.make(name: name, object: self, userInfo: userInfo)
        if Send.responds(delegateObject, selector) { Send.void(delegateObject, selector, notification.objcObject) }
        NSNotificationCenter.defaultCenter().post(notification)
    }
}
