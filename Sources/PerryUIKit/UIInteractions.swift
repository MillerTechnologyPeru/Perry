import CPerryGeometry
import PerryObjCInterop

// UILargeContentViewerInteraction and UIContextMenuInteraction: interactions
// an app adds to its views. The large content viewer is an accessibility
// feature there is none of here, and no context menu is shown, so both keep
// their delegate and the view they were added to and do nothing.

@ObjCClass("UILargeContentViewerInteraction")
open class UILargeContentViewerInteraction: NSObject {
    /// Neither is retained.
    var interactionDelegate: NSObject?
    var interactionView: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithDelegate:")
    public required init(delegate: NSObject?) {
        super.init()
        interactionDelegate = delegate
    }

    @ObjCClassMethod("isEnabled") static func isEnabled(_ cls: ObjCClass) -> Bool { false }

    @ObjCMethod("delegate") func delegate() -> NSObject? { interactionDelegate }
    @ObjCMethod("view") func view() -> NSObject? { interactionView }
    @ObjCMethod("gestureRecognizerForExclusionRelationship") func gestureRecognizerForExclusionRelationship() -> NSObject? { nil }
    @ObjCMethod("willMoveToView:") func willMove(toView view: NSObject?) {}
    @ObjCMethod("didMoveToView:") func didMove(toView view: NSObject?) { interactionView = view }
}

@ObjCClass("UIContextMenuInteraction")
open class UIContextMenuInteraction: NSObject {
    /// Neither is retained.
    var interactionDelegate: NSObject?
    var interactionView: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithDelegate:")
    public required init(delegate: NSObject?) {
        super.init()
        interactionDelegate = delegate
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { interactionDelegate }
    @ObjCMethod("view") func view() -> NSObject? { interactionView }
    /// UIContextMenuInteractionAppearanceUnknown.
    @ObjCMethod("menuAppearance") func menuAppearance() -> Int { 0 }
    @ObjCMethod("locationInView:") func location(in view: NSObject?) -> CGPoint { .zero }
    @ObjCMethod("dismissMenu") func dismissMenu() {}
    @ObjCMethod("updateVisibleMenuWithBlock:") func updateVisibleMenu(block: NSObject?) {}
    @ObjCMethod("willMoveToView:") func willMove(toView view: NSObject?) {}
    @ObjCMethod("didMoveToView:") func didMove(toView view: NSObject?) { interactionView = view }
}
