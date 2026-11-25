import CPerryGeometry
import PerryObjCInterop

// NSAccessibilityElement: an object that stands for part of a view to
// assistive technology, which apps subclass for things they draw
// themselves (lines of text, hovered ranges). There is no assistive
// technology here to ask it anything, so it keeps what it is told, as every
// object's NSAccessibility properties do (Accessibility.swift), and works
// out its frame as Darwin's does.

@ObjCClass("NSAccessibilityElement")
open class NSAccessibilityElement: NSObject {
    var frame = CGRect.zero
    var frameInParentSpace = CGRect.zero
    /// Whether the frame in its parent's space was set last: the frame is
    /// then worked out from the parent's.
    var framedInParent = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// Its properties go with it, so an object made later at its address
    /// doesn't take them over.
    deinit {
        AccessibilityValues.values[objcObject] = nil
        AccessibilityValues.flags[objcObject] = nil
    }

    /// An element of the receiving class with these properties. It isn't
    /// added to the parent's children, as on Darwin.
    @ObjCClassMethod("accessibilityElementWithRole:frame:label:parent:")
    static func element(_ cls: ObjCClass, role: NSObject?, frame: CGRect, label: NSObject?, parent: NSObject?) -> NSObject? {
        guard let made = Send.object(cls.pointer, "new") else { return nil }
        let element = NSObject(objcObject: made, ownership: .adopt)
        Send.void(made, "setAccessibilityRole:", role?.objcObject)
        Send.void(made, "setAccessibilityFrame:", rect: frame)
        Send.void(made, "setAccessibilityLabel:", label?.objcObject)
        Send.void(made, "setAccessibilityParent:", parent?.objcObject)
        return element
    }

    /// Adds `child` to the children, and makes this its parent.
    @ObjCMethod("accessibilityAddChildElement:")
    func accessibilityAddChildElement(_ child: NSObject?) {
        guard let child else { return }
        let existing = AccessibilityValues.values[objcObject]?["children"]?.as(NSArray.self)?.elements ?? []
        AccessibilityValues.values[objcObject, default: [:]]["children"] = NSMutableArray.of(existing + [child])
        Send.void(child.objcObject, "setAccessibilityParent:", objcObject)
    }

    /// The frame in screen coordinates: the one set, or, when the frame in
    /// the parent's space was set last, that frame moved by the parent's
    /// (a view's, through NSAccessibilityFrameInView).
    @ObjCMethod("accessibilityFrame")
    func elementAccessibilityFrame() -> CGRect {
        guard framedInParent, let parent = Send.object(objcObject, "accessibilityParent") else { return frame }
        if NSObject(parent).as(NSView.self) != nil { return NSAccessibilityFrameInView(parent, frameInParentSpace) }
        let origin = Send.rect(parent, "accessibilityFrame").origin
        return CGRect(origin: CGPoint(x: origin.x + frameInParentSpace.minX, y: origin.y + frameInParentSpace.minY),
                      size: frameInParentSpace.size)
    }

    @ObjCMethod("setAccessibilityFrame:")
    func setElementAccessibilityFrame(_ value: CGRect) {
        frame = value
        framedInParent = false
    }

    @ObjCMethod("accessibilityFrameInParentSpace") func accessibilityFrameInParentSpace() -> CGRect { frameInParentSpace }

    @ObjCMethod("setAccessibilityFrameInParentSpace:")
    func setAccessibilityFrameInParentSpace(_ value: CGRect) {
        frameInParentSpace = value
        framedInParent = true
    }

    /// An element is one unless told otherwise; and, unlike a view, is not
    /// enabled until told so.
    @ObjCMethod("isAccessibilityElement")
    func elementIsAccessibilityElement() -> Bool { AccessibilityValues.flags[objcObject]?["element"] ?? true }
    @ObjCMethod("isAccessibilityEnabled")
    func elementIsAccessibilityEnabled() -> Bool { AccessibilityValues.flags[objcObject]?["enabled"] ?? false }
}
