import CPerryGeometry
import PerryObjCInterop

// Accessibility, which has no assistive technology to talk to here: its
// functions do nothing and its properties keep what is set, so apps that
// describe their views to VoiceOver run as they do with it off.

/// Accessibility properties set on objects, by object and property name.
enum AccessibilityValues {
    nonisolated(unsafe) static var values: [UnsafeMutableRawPointer: [String: NSObject]] = [:]
    nonisolated(unsafe) static var flags: [UnsafeMutableRawPointer: [String: Bool]] = [:]
}

@c(_NSAccessibilityPostNotification)
public func NSAccessibilityPostNotification(_ element: UnsafeMutableRawPointer?, _ notification: UnsafeMutableRawPointer?) {}

@c(_NSAccessibilityPostNotificationWithUserInfo)
public func NSAccessibilityPostNotificationWithUserInfo(_ element: UnsafeMutableRawPointer?, _ notification: UnsafeMutableRawPointer?,
                                                        _ userInfo: UnsafeMutableRawPointer?) {}

/// The element itself: no element is ignored.
@c(_NSAccessibilityUnignoredAncestor)
public func NSAccessibilityUnignoredAncestor(_ element: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { element }

@c(_NSAccessibilityUnignoredDescendant)
public func NSAccessibilityUnignoredDescendant(_ element: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { element }

@c(_NSAccessibilityUnignoredChildren)
public func NSAccessibilityUnignoredChildren(_ children: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { children }

@c(_NSAccessibilityUnignoredChildrenForOnlyChild)
public func NSAccessibilityUnignoredChildrenForOnlyChild(_ child: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let child else { return nil }
    return NSMutableArray.of([NSObject(child)]).objcObject
}

/// A role's description: the role's name without its "AX" prefix.
@c(_NSAccessibilityRoleDescription)
public func NSAccessibilityRoleDescription(_ role: UnsafeMutableRawPointer?, _ subrole: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let name = role.map { String(objCArgument: $0) } ?? ""
    return NSObject(objCReturnValue: (name.hasPrefix("AX") ? String(name.dropFirst(2)) : name).lowercased().objCReturnValue()).objcObject
}

@c(_NSAccessibilityRoleDescriptionForUIElement)
public func NSAccessibilityRoleDescriptionForUIElement(_ element: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    NSObject(objCReturnValue: "".objCReturnValue()).objcObject
}

@c(_NSAccessibilityActionDescription)
public func NSAccessibilityActionDescription(_ action: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let name = action.map { String(objCArgument: $0) } ?? ""
    return NSObject(objCReturnValue: (name.hasPrefix("AX") ? String(name.dropFirst(2)) : name).lowercased().objCReturnValue()).objcObject
}

/// A rectangle in a view, in screen coordinates.
@c(_NSAccessibilityFrameInView)
public func NSAccessibilityFrameInView(_ view: UnsafeMutableRawPointer?, _ rect: CGRect) -> CGRect {
    guard let view, let object = NSObject(view).as(NSView.self), let window = object.window else { return rect }
    return window.convertRect(toScreen: object.convert(rect, to: nil))
}

@c(_NSAccessibilityPointInView)
public func NSAccessibilityPointInView(_ view: UnsafeMutableRawPointer?, _ point: CGPoint) -> CGPoint {
    let frame = NSAccessibilityFrameInView(view, CGRect(origin: point, size: .zero))
    return frame.origin
}

@c(_NSAccessibilitySetMayContainProtectedContent)
public func NSAccessibilitySetMayContainProtectedContent(_ flag: Bool) -> Bool { true }

/// NSAccessibility's properties on every object: kept, and read back.
@ObjCCategory("NSAccessibility")
extension NSObject {
    private func stored(_ name: String) -> NSObject? { AccessibilityValues.values[objcObject]?[name] }
    private func store(_ name: String, _ value: NSObject?) { AccessibilityValues.values[objcObject, default: [:]][name] = value }

    @ObjCMethod("accessibilityRole") func accessibilityRole() -> NSObject? { stored("role") }
    @ObjCMethod("setAccessibilityRole:") func setAccessibilityRole(_ value: NSObject?) { store("role", value) }
    @ObjCMethod("accessibilitySubrole") func accessibilitySubrole() -> NSObject? { stored("subrole") }
    @ObjCMethod("setAccessibilitySubrole:") func setAccessibilitySubrole(_ value: NSObject?) { store("subrole", value) }
    @ObjCMethod("accessibilityRoleDescription") func accessibilityRoleDescription() -> NSObject? { stored("roleDescription") }
    @ObjCMethod("setAccessibilityRoleDescription:") func setAccessibilityRoleDescription(_ value: NSObject?) { store("roleDescription", value) }
    @ObjCMethod("accessibilityLabel") func accessibilityLabel() -> NSObject? { stored("label") }
    @ObjCMethod("setAccessibilityLabel:") func setAccessibilityLabel(_ value: NSObject?) { store("label", value) }
    @ObjCMethod("accessibilityTitle") func accessibilityTitle() -> NSObject? { stored("title") }
    @ObjCMethod("setAccessibilityTitle:") func setAccessibilityTitle(_ value: NSObject?) { store("title", value) }
    @ObjCMethod("accessibilityHelp") func accessibilityHelp() -> NSObject? { stored("help") }
    @ObjCMethod("setAccessibilityHelp:") func setAccessibilityHelp(_ value: NSObject?) { store("help", value) }
    @ObjCMethod("accessibilityValue") func accessibilityValue() -> NSObject? { stored("value") }
    @ObjCMethod("setAccessibilityValue:") func setAccessibilityValue(_ value: NSObject?) { store("value", value) }
    @ObjCMethod("accessibilityIdentifier") func accessibilityIdentifier() -> NSObject? { stored("identifier") }
    @ObjCMethod("setAccessibilityIdentifier:") func setAccessibilityIdentifier(_ value: NSObject?) { store("identifier", value) }
    @ObjCMethod("accessibilityValueDescription") func accessibilityValueDescription() -> NSObject? { stored("valueDescription") }
    @ObjCMethod("setAccessibilityValueDescription:") func setAccessibilityValueDescription(_ value: NSObject?) { store("valueDescription", value) }
    @ObjCMethod("accessibilityChildren") func accessibilityChildren() -> NSObject? { stored("children") }
    @ObjCMethod("setAccessibilityChildren:") func setAccessibilityChildren(_ value: NSObject?) { store("children", value) }
    @ObjCMethod("accessibilityParent") func accessibilityParent() -> NSObject? { stored("parent") }
    @ObjCMethod("setAccessibilityParent:") func setAccessibilityParent(_ value: NSObject?) { store("parent", value) }
    @ObjCMethod("accessibilityTitleUIElement") func accessibilityTitleUIElement() -> NSObject? { stored("titleUIElement") }
    @ObjCMethod("setAccessibilityTitleUIElement:") func setAccessibilityTitleUIElement(_ value: NSObject?) { store("titleUIElement", value) }

    private func flag(_ name: String, _ fallback: Bool) -> Bool { AccessibilityValues.flags[objcObject]?[name] ?? fallback }
    private func setFlag(_ name: String, _ value: Bool) { AccessibilityValues.flags[objcObject, default: [:]][name] = value }

    @ObjCMethod("isAccessibilityElement") func isAccessibilityElement() -> Bool { flag("element", false) }
    @ObjCMethod("setAccessibilityElement:") func setAccessibilityElement(_ value: Bool) { setFlag("element", value) }
    @ObjCMethod("isAccessibilityEnabled") func isAccessibilityEnabled() -> Bool { flag("enabled", true) }
    @ObjCMethod("setAccessibilityEnabled:") func setAccessibilityEnabled(_ value: Bool) { setFlag("enabled", value) }
    @ObjCMethod("isAccessibilityFocused") func isAccessibilityFocused() -> Bool { flag("focused", false) }
    @ObjCMethod("setAccessibilityFocused:") func setAccessibilityFocused(_ value: Bool) { setFlag("focused", value) }
    @ObjCMethod("isAccessibilitySelected") func isAccessibilitySelected() -> Bool { flag("selected", false) }
    @ObjCMethod("setAccessibilitySelected:") func setAccessibilitySelected(_ value: Bool) { setFlag("selected", value) }
    @ObjCMethod("accessibilityIsIgnored") func accessibilityIsIgnored() -> Bool { true }
    @ObjCMethod("accessibilityAttributeNames") func accessibilityAttributeNames() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("accessibilityActionNames") func accessibilityActionNames() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("accessibilityAttributeValue:") func accessibilityAttributeValue(_ name: NSObject?) -> NSObject? { nil }
    @ObjCMethod("accessibilityPerformAction:") func accessibilityPerformAction(_ name: NSObject?) {}
    @ObjCMethod("accessibilityHitTest:") func accessibilityHitTest(_ point: CGPoint) -> NSObject? { self }
    @ObjCMethod("accessibilityFocusedUIElement") func accessibilityFocusedUIElement() -> NSObject? { self }
    @ObjCMethod("accessibilityFrame") func accessibilityFrame() -> CGRect { .zero }
    @ObjCMethod("setAccessibilityFrame:") func setAccessibilityFrame(_ value: CGRect) {}
}
