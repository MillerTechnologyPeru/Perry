import CPerryGeometry
import PerryObjCInterop

// UIPopoverBackgroundView: the chrome a popover draws around its content,
// which an app subclasses to restyle it. Popovers here are shown as
// sheets, so nothing draws it, and the class gives the geometry an
// app's subclass overrides.

@ObjCClass("UIPopoverBackgroundView")
open class UIPopoverBackgroundView: UIView {
    nonisolated(unsafe) static var arrowOffsets: [UnsafeMutableRawPointer: CGFloat] = [:]
    nonisolated(unsafe) static var arrowDirections: [UnsafeMutableRawPointer: UInt] = [:]

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIPopoverBackgroundView.arrowOffsets[objcObject] = nil
        UIPopoverBackgroundView.arrowDirections[objcObject] = nil
        super.dealloc()
    }

    @ObjCMethod("arrowOffset") func arrowOffset() -> CGFloat { UIPopoverBackgroundView.arrowOffsets[objcObject] ?? 0 }
    @ObjCMethod("setArrowOffset:") func setArrowOffset(_ offset: CGFloat) { UIPopoverBackgroundView.arrowOffsets[objcObject] = offset }
    @ObjCMethod("arrowDirection") func arrowDirection() -> UInt { UIPopoverBackgroundView.arrowDirections[objcObject] ?? 0 }
    @ObjCMethod("setArrowDirection:") func setArrowDirection(_ direction: UInt) { UIPopoverBackgroundView.arrowDirections[objcObject] = direction }

    @ObjCClassMethod("arrowBase") static func arrowBase(_ cls: ObjCClass) -> CGFloat { 0 }
    @ObjCClassMethod("arrowHeight") static func arrowHeight(_ cls: ObjCClass) -> CGFloat { 0 }
    @ObjCClassMethod("contentViewInsets") static func contentViewInsets(_ cls: ObjCClass) -> UIEdgeInsets { .zero }
    @ObjCClassMethod("wantsDefaultContentAppearance") static func wantsDefaultContentAppearance(_ cls: ObjCClass) -> Bool { true }
}
