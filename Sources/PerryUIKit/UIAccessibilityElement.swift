import CPerryGeometry
import PerryObjCInterop

// UIAccessibilityElement: an object that stands for something drawn but not
// a view, which a view lists as an accessibility element. There is no
// assistive technology to read it, so it keeps what is set and answers it
// back. Apps subclass it, overriding the label and the frame.

final class AccessibilityElementState: ObjectState {
    /// The view that contains the element: not retained, as it holds the
    /// element.
    var container: UnsafeMutableRawPointer?
    var frame = CGRect.zero
}

@ObjCClass("UIAccessibilityElement")
open class UIAccessibilityElement: NSObject {
    static let states = StateTable<AccessibilityElementState>()
    var element: AccessibilityElementState { UIAccessibilityElement.states[objcObject] }

    @ObjCMethod("initWithAccessibilityContainer:")
    func initialize(container: NSObject?) -> Self {
        element.container = container?.objcObject
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIAccessibilityElement.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIAccessibilityElement.objCClass.pointer)
    }

    @ObjCMethod("accessibilityContainer") func accessibilityContainer() -> NSObject? {
        element.container.map { NSObject($0) }
    }
    @ObjCMethod("setAccessibilityContainer:")
    func setAccessibilityContainer(_ container: NSObject?) { element.container = container?.objcObject }

    /// An element is one unless it says it is not.
    @ObjCMethod("isAccessibilityElement") func elementIsAccessibilityElement() -> Bool {
        (Accessibility.get(self, .isElement)?.sendIntegerValue() ?? 1) != 0
    }

    @ObjCMethod("accessibilityFrame") func elementAccessibilityFrame() -> CGRect { element.frame }
    @ObjCMethod("setAccessibilityFrame:") func setElementAccessibilityFrame(_ frame: CGRect) { element.frame = frame }

    /// The point a double tap activates: the middle of the frame.
    @ObjCMethod("accessibilityActivationPoint") func accessibilityActivationPoint() -> CGPoint {
        CGPoint(x: element.frame.midX, y: element.frame.midY)
    }
}
