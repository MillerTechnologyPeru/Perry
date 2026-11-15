import CPerryGeometry
import PerryObjCInterop

// UIAccessibility's informal protocol, which every object has. There is no
// assistive technology to read it, so it keeps what apps set, as
// associated objects that go with the object, and reads it back.

enum Accessibility {
    typealias Setter = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?, UInt) -> Void
    typealias Getter = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    nonisolated(unsafe) static var setter: Setter?
    nonisolated(unsafe) static var getter: Getter?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        setter = lookup("_objc_setAssociatedObject").map { unsafeBitCast($0, to: Setter.self) }
        getter = lookup("_objc_getAssociatedObject").map { unsafeBitCast($0, to: Getter.self) }
    }

    /// One key per property: the address of its byte.
    enum Key: Int, CaseIterable {
        case label, hint, value, language, traits, isElement, elementsHidden, viewIsModal, elements, identifier
        case attributedLabel, attributedHint, attributedValue, customActions, headerElements, path, userInputLabels,
             attributedUserInputLabels, groupsChildren, navigationStyle, respondsToUserInteraction
    }
    nonisolated(unsafe) private static let keys = UnsafeMutablePointer<UInt8>.allocate(capacity: Key.allCases.count)

    static func get(_ object: NSObject, _ key: Key) -> NSObject? {
        getter?(object.objcObject, keys + key.rawValue).map { NSObject($0) }
    }

    /// OBJC_ASSOCIATION_RETAIN_NONATOMIC, or COPY_NONATOMIC for strings.
    static func set(_ object: NSObject, _ key: Key, _ value: NSObject?, copy: Bool = false) {
        setter?(object.objcObject, keys + key.rawValue, value?.objcObject, copy ? 3 : 1)
    }
}

@ObjCCategory("UIAccessibility")
extension NSObject {
    @ObjCMethod("accessibilityLabel") func accessibilityLabel() -> NSObject? { Accessibility.get(self, .label) }
    @ObjCMethod("setAccessibilityLabel:")
    func setAccessibilityLabel(_ label: NSObject?) { Accessibility.set(self, .label, label, copy: true) }

    /// UIAccessibilityIdentification's identifier; UIView keeps its own.
    @ObjCMethod("accessibilityIdentifier") func objectAccessibilityIdentifier() -> NSObject? { Accessibility.get(self, .identifier) }
    @ObjCMethod("setAccessibilityIdentifier:")
    func setObjectAccessibilityIdentifier(_ identifier: NSObject?) { Accessibility.set(self, .identifier, identifier, copy: true) }

    @ObjCMethod("accessibilityHint") func accessibilityHint() -> NSObject? { Accessibility.get(self, .hint) }
    @ObjCMethod("setAccessibilityHint:")
    func setAccessibilityHint(_ hint: NSObject?) { Accessibility.set(self, .hint, hint, copy: true) }

    @ObjCMethod("accessibilityValue") func accessibilityValue() -> NSObject? { Accessibility.get(self, .value) }
    @ObjCMethod("setAccessibilityValue:")
    func setAccessibilityValue(_ value: NSObject?) { Accessibility.set(self, .value, value, copy: true) }

    @ObjCMethod("accessibilityLanguage") func accessibilityLanguage() -> NSObject? { Accessibility.get(self, .language) }
    @ObjCMethod("setAccessibilityLanguage:")
    func setAccessibilityLanguage(_ language: NSObject?) { Accessibility.set(self, .language, language, copy: true) }

    /// UIAccessibilityTraits, a bit set.
    @ObjCMethod("accessibilityTraits")
    func accessibilityTraits() -> UInt64 { UInt64(Accessibility.get(self, .traits)?.sendIntegerValue() ?? 0) }
    @ObjCMethod("setAccessibilityTraits:")
    func setAccessibilityTraits(_ traits: UInt64) { Accessibility.set(self, .traits, NSNumber.make(integer: Int(bitPattern: UInt(traits)))) }

    /// Whether Smart Invert leaves the view as it is: colors are never
    /// inverted here.
    @ObjCMethod("accessibilityIgnoresInvertColors") func accessibilityIgnoresInvertColors() -> Bool { false }
    @ObjCMethod("setAccessibilityIgnoresInvertColors:") func setAccessibilityIgnoresInvertColors(_ ignores: Bool) {}

    @ObjCMethod("isAccessibilityElement")
    func isAccessibilityElement() -> Bool { (Accessibility.get(self, .isElement)?.sendIntegerValue() ?? 0) != 0 }
    @ObjCMethod("setIsAccessibilityElement:")
    func setIsAccessibilityElement(_ value: Bool) { Accessibility.set(self, .isElement, NSNumber.make(bool: value)) }

    @ObjCMethod("accessibilityElementsHidden")
    func accessibilityElementsHidden() -> Bool { (Accessibility.get(self, .elementsHidden)?.sendIntegerValue() ?? 0) != 0 }
    @ObjCMethod("setAccessibilityElementsHidden:")
    func setAccessibilityElementsHidden(_ value: Bool) { Accessibility.set(self, .elementsHidden, NSNumber.make(bool: value)) }

    @ObjCMethod("accessibilityViewIsModal")
    func accessibilityViewIsModal() -> Bool { (Accessibility.get(self, .viewIsModal)?.sendIntegerValue() ?? 0) != 0 }
    @ObjCMethod("setAccessibilityViewIsModal:")
    func setAccessibilityViewIsModal(_ value: Bool) { Accessibility.set(self, .viewIsModal, NSNumber.make(bool: value)) }

    @ObjCMethod("accessibilityElements") func accessibilityElements() -> NSObject? { Accessibility.get(self, .elements) }
    @ObjCMethod("setAccessibilityElements:")
    func setAccessibilityElements(_ elements: NSObject?) { Accessibility.set(self, .elements, elements) }

    // The attributed forms are kept beside the plain ones, as set.
    @ObjCMethod("accessibilityAttributedLabel") func accessibilityAttributedLabel() -> NSObject? { Accessibility.get(self, .attributedLabel) }
    @ObjCMethod("setAccessibilityAttributedLabel:")
    func setAccessibilityAttributedLabel(_ label: NSObject?) { Accessibility.set(self, .attributedLabel, label, copy: true) }

    @ObjCMethod("accessibilityAttributedHint") func accessibilityAttributedHint() -> NSObject? { Accessibility.get(self, .attributedHint) }
    @ObjCMethod("setAccessibilityAttributedHint:")
    func setAccessibilityAttributedHint(_ hint: NSObject?) { Accessibility.set(self, .attributedHint, hint, copy: true) }

    @ObjCMethod("accessibilityAttributedValue") func accessibilityAttributedValue() -> NSObject? { Accessibility.get(self, .attributedValue) }
    @ObjCMethod("setAccessibilityAttributedValue:")
    func setAccessibilityAttributedValue(_ value: NSObject?) { Accessibility.set(self, .attributedValue, value, copy: true) }

    @ObjCMethod("accessibilityCustomActions") func accessibilityCustomActions() -> NSObject? { Accessibility.get(self, .customActions) }
    @ObjCMethod("setAccessibilityCustomActions:")
    func setAccessibilityCustomActions(_ actions: NSObject?) { Accessibility.set(self, .customActions, actions, copy: true) }

    @ObjCMethod("accessibilityHeaderElements") func accessibilityHeaderElements() -> NSObject? { Accessibility.get(self, .headerElements) }
    @ObjCMethod("setAccessibilityHeaderElements:")
    func setAccessibilityHeaderElements(_ elements: NSObject?) { Accessibility.set(self, .headerElements, elements, copy: true) }

    @ObjCMethod("accessibilityPath") func accessibilityPath() -> NSObject? { Accessibility.get(self, .path) }
    @ObjCMethod("setAccessibilityPath:") func setAccessibilityPath(_ path: NSObject?) { Accessibility.set(self, .path, path, copy: true) }

    @ObjCMethod("accessibilityUserInputLabels") func accessibilityUserInputLabels() -> NSObject? { Accessibility.get(self, .userInputLabels) }
    @ObjCMethod("setAccessibilityUserInputLabels:")
    func setAccessibilityUserInputLabels(_ labels: NSObject?) { Accessibility.set(self, .userInputLabels, labels, copy: true) }

    @ObjCMethod("accessibilityAttributedUserInputLabels")
    func accessibilityAttributedUserInputLabels() -> NSObject? { Accessibility.get(self, .attributedUserInputLabels) }
    @ObjCMethod("setAccessibilityAttributedUserInputLabels:")
    func setAccessibilityAttributedUserInputLabels(_ labels: NSObject?) { Accessibility.set(self, .attributedUserInputLabels, labels, copy: true) }

    @ObjCMethod("shouldGroupAccessibilityChildren")
    func shouldGroupAccessibilityChildren() -> Bool { (Accessibility.get(self, .groupsChildren)?.sendIntegerValue() ?? 0) != 0 }
    @ObjCMethod("setShouldGroupAccessibilityChildren:")
    func setShouldGroupAccessibilityChildren(_ value: Bool) { Accessibility.set(self, .groupsChildren, NSNumber.make(bool: value)) }

    /// UIAccessibilityNavigationStyle; automatic is 0.
    @ObjCMethod("accessibilityNavigationStyle")
    func accessibilityNavigationStyle() -> Int { Accessibility.get(self, .navigationStyle)?.sendIntegerValue() ?? 0 }
    @ObjCMethod("setAccessibilityNavigationStyle:")
    func setAccessibilityNavigationStyle(_ style: Int) { Accessibility.set(self, .navigationStyle, NSNumber.make(integer: style)) }

    @ObjCMethod("accessibilityRespondsToUserInteraction")
    func accessibilityRespondsToUserInteraction() -> Bool {
        (Accessibility.get(self, .respondsToUserInteraction)?.sendIntegerValue() ?? 0) != 0
    }
    @ObjCMethod("setAccessibilityRespondsToUserInteraction:")
    func setAccessibilityRespondsToUserInteraction(_ value: Bool) {
        Accessibility.set(self, .respondsToUserInteraction, NSNumber.make(bool: value))
    }

    @ObjCMethod("accessibilityActivationPoint") func objectAccessibilityActivationPoint() -> CGPoint { .zero }
    @ObjCMethod("setAccessibilityActivationPoint:") func setObjectAccessibilityActivationPoint(_ point: CGPoint) {}

    @ObjCMethod("accessibilityFrame") func accessibilityFrame() -> CGRect { .zero }
    @ObjCMethod("setAccessibilityFrame:") func setAccessibilityFrame(_ frame: CGRect) {}
}
