import CPerryGeometry
import PerryObjCInterop

// The appearance objects iOS 13 gave bars: UINavigationBarAppearance,
// UITabBarAppearance, UIToolbarAppearance and the item appearances they
// hold. Apps set them up as they do on an iPhone and hand them to a bar;
// they are kept as set and read back, and copies take the values, with the
// bars drawing as they do without them. UIBarAppearance is open to subclasses
// (a popup bar's), which keep their own state beside it.

final class BarAppearanceState: ObjectState {
    var objects: [String: NSObject] = [:]
    var numbers: [String: Double] = [:]
    var sizes: [String: CGSize] = [:]

    func copy(from other: BarAppearanceState) {
        objects = other.objects
        numbers = other.numbers
        sizes = other.sizes
    }
}

/// UIBarAppearance: what a bar's background and shadow look like.
@ObjCClass("UIBarAppearance")
open class UIBarAppearance: NSObject {
    static let states = StateTable<BarAppearanceState>()
    var barState: BarAppearanceState { UIBarAppearance.states[objcObject] }

    /// An object kept under a key, made of `cls` on first use.
    func lazy(_ key: String, _ cls: ObjCClass) -> NSObject {
        if let object = barState.objects[key] { return object }
        let object = cls.object.newInstance()
        barState.objects[key] = object
        return object
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithIdiom:")
    func initialize(idiom: Int) -> Self {
        barState.numbers["idiom"] = Double(idiom)
        return self
    }

    @ObjCMethod("initWithBarAppearance:")
    func initialize(barAppearance: UIBarAppearance?) -> Self {
        if let barAppearance { barState.copy(from: barAppearance.barState) }
        return self
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UIBarAppearance {
        let copy = ObjCClass(ObjCRuntime.objectClass(objcObject)!).object.newInstance().unsafeCast(to: UIBarAppearance.self)
        copy.barState.copy(from: barState)
        return copy
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIBarAppearance.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIBarAppearance.objCClass.pointer)
    }

    @ObjCMethod("idiom") func idiom() -> Int { Int(barState.numbers["idiom"] ?? 0) }

    @ObjCMethod("configureWithDefaultBackground") func configureWithDefaultBackground() { barState.objects["backgroundColor"] = nil }
    @ObjCMethod("configureWithOpaqueBackground") func configureWithOpaqueBackground() { barState.objects["backgroundEffect"] = nil }
    @ObjCMethod("configureWithTransparentBackground")
    func configureWithTransparentBackground() {
        barState.objects["backgroundEffect"] = nil
        barState.objects["backgroundColor"] = nil
        barState.objects["shadowColor"] = nil
    }

    @ObjCMethod("backgroundEffect") func backgroundEffect() -> NSObject? { barState.objects["backgroundEffect"] }
    @ObjCMethod("setBackgroundEffect:") func setBackgroundEffect(_ value: NSObject?) { barState.objects["backgroundEffect"] = value }
    @ObjCMethod("backgroundColor") func backgroundColor() -> NSObject? { barState.objects["backgroundColor"] }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ value: NSObject?) { barState.objects["backgroundColor"] = value }
    @ObjCMethod("backgroundImage") func backgroundImage() -> NSObject? { barState.objects["backgroundImage"] }
    @ObjCMethod("setBackgroundImage:") func setBackgroundImage(_ value: NSObject?) { barState.objects["backgroundImage"] = value }
    @ObjCMethod("backgroundImageContentMode") func backgroundImageContentMode() -> Int { Int(barState.numbers["backgroundImageContentMode"] ?? 0) }
    @ObjCMethod("setBackgroundImageContentMode:") func setBackgroundImageContentMode(_ mode: Int) { barState.numbers["backgroundImageContentMode"] = Double(mode) }
    @ObjCMethod("shadowColor") func shadowColor() -> NSObject? { barState.objects["shadowColor"] }
    @ObjCMethod("setShadowColor:") func setShadowColor(_ value: NSObject?) { barState.objects["shadowColor"] = value }
    @ObjCMethod("shadowImage") func shadowImage() -> NSObject? { barState.objects["shadowImage"] }
    @ObjCMethod("setShadowImage:") func setShadowImage(_ value: NSObject?) { barState.objects["shadowImage"] = value }
}

/// UINavigationBarAppearance.
@ObjCClass("UINavigationBarAppearance")
open class UINavigationBarAppearance: UIBarAppearance {
    @ObjCMethod("titleTextAttributes") func titleTextAttributes() -> NSObject? { barState.objects["titleTextAttributes"] }
    @ObjCMethod("setTitleTextAttributes:") func setTitleTextAttributes(_ value: NSObject?) { barState.objects["titleTextAttributes"] = value }
    @ObjCMethod("largeTitleTextAttributes") func largeTitleTextAttributes() -> NSObject? { barState.objects["largeTitleTextAttributes"] }
    @ObjCMethod("setLargeTitleTextAttributes:") func setLargeTitleTextAttributes(_ value: NSObject?) { barState.objects["largeTitleTextAttributes"] = value }
    @ObjCMethod("titlePositionAdjustment") func titlePositionAdjustment() -> UIOffset { barState.sizes["titlePositionAdjustment"] ?? .zero }
    @ObjCMethod("setTitlePositionAdjustment:") func setTitlePositionAdjustment(_ offset: UIOffset) { barState.sizes["titlePositionAdjustment"] = offset }
    @ObjCMethod("backIndicatorImage") func backIndicatorImage() -> NSObject? { barState.objects["backIndicatorImage"] }
    @ObjCMethod("backIndicatorTransitionMaskImage") func backIndicatorTransitionMaskImage() -> NSObject? { barState.objects["backIndicatorTransitionMaskImage"] }
    @ObjCMethod("setBackIndicatorImage:transitionMaskImage:")
    func setBackIndicatorImage(_ image: NSObject?, transitionMaskImage mask: NSObject?) {
        barState.objects["backIndicatorImage"] = image
        barState.objects["backIndicatorTransitionMaskImage"] = mask
    }
    @ObjCMethod("buttonAppearance") func buttonAppearance() -> NSObject { lazy("buttonAppearance", UIBarButtonItemAppearance.objCClass) }
    @ObjCMethod("setButtonAppearance:") func setButtonAppearance(_ value: NSObject?) { barState.objects["buttonAppearance"] = value }
    @ObjCMethod("doneButtonAppearance") func doneButtonAppearance() -> NSObject { lazy("doneButtonAppearance", UIBarButtonItemAppearance.objCClass) }
    @ObjCMethod("setDoneButtonAppearance:") func setDoneButtonAppearance(_ value: NSObject?) { barState.objects["doneButtonAppearance"] = value }
    @ObjCMethod("backButtonAppearance") func backButtonAppearance() -> NSObject { lazy("backButtonAppearance", UIBarButtonItemAppearance.objCClass) }
    @ObjCMethod("setBackButtonAppearance:") func setBackButtonAppearance(_ value: NSObject?) { barState.objects["backButtonAppearance"] = value }
}

/// UIToolbarAppearance.
@ObjCClass("UIToolbarAppearance")
open class UIToolbarAppearance: UIBarAppearance {
    @ObjCMethod("buttonAppearance") func buttonAppearance() -> NSObject { lazy("buttonAppearance", UIBarButtonItemAppearance.objCClass) }
    @ObjCMethod("setButtonAppearance:") func setButtonAppearance(_ value: NSObject?) { barState.objects["buttonAppearance"] = value }
    @ObjCMethod("doneButtonAppearance") func doneButtonAppearance() -> NSObject { lazy("doneButtonAppearance", UIBarButtonItemAppearance.objCClass) }
    @ObjCMethod("setDoneButtonAppearance:") func setDoneButtonAppearance(_ value: NSObject?) { barState.objects["doneButtonAppearance"] = value }
}

/// UITabBarAppearance.
@ObjCClass("UITabBarAppearance")
open class UITabBarAppearance: UIBarAppearance {
    @ObjCMethod("stackedLayoutAppearance") func stackedLayoutAppearance() -> NSObject { lazy("stackedLayoutAppearance", UITabBarItemAppearance.objCClass) }
    @ObjCMethod("setStackedLayoutAppearance:") func setStackedLayoutAppearance(_ value: NSObject?) { barState.objects["stackedLayoutAppearance"] = value }
    @ObjCMethod("inlineLayoutAppearance") func inlineLayoutAppearance() -> NSObject { lazy("inlineLayoutAppearance", UITabBarItemAppearance.objCClass) }
    @ObjCMethod("setInlineLayoutAppearance:") func setInlineLayoutAppearance(_ value: NSObject?) { barState.objects["inlineLayoutAppearance"] = value }
    @ObjCMethod("compactInlineLayoutAppearance") func compactInlineLayoutAppearance() -> NSObject { lazy("compactInlineLayoutAppearance", UITabBarItemAppearance.objCClass) }
    @ObjCMethod("setCompactInlineLayoutAppearance:") func setCompactInlineLayoutAppearance(_ value: NSObject?) { barState.objects["compactInlineLayoutAppearance"] = value }
    @ObjCMethod("selectionIndicatorTintColor") func selectionIndicatorTintColor() -> NSObject? { barState.objects["selectionIndicatorTintColor"] }
    @ObjCMethod("setSelectionIndicatorTintColor:") func setSelectionIndicatorTintColor(_ value: NSObject?) { barState.objects["selectionIndicatorTintColor"] = value }
    @ObjCMethod("selectionIndicatorImage") func selectionIndicatorImage() -> NSObject? { barState.objects["selectionIndicatorImage"] }
    @ObjCMethod("setSelectionIndicatorImage:") func setSelectionIndicatorImage(_ value: NSObject?) { barState.objects["selectionIndicatorImage"] = value }
    @ObjCMethod("stackedItemPositioning") func stackedItemPositioning() -> Int { Int(barState.numbers["stackedItemPositioning"] ?? 0) }
    @ObjCMethod("setStackedItemPositioning:") func setStackedItemPositioning(_ value: Int) { barState.numbers["stackedItemPositioning"] = Double(value) }
    @ObjCMethod("stackedItemWidth") func stackedItemWidth() -> Double { barState.numbers["stackedItemWidth"] ?? 0 }
    @ObjCMethod("setStackedItemWidth:") func setStackedItemWidth(_ value: Double) { barState.numbers["stackedItemWidth"] = value }
    @ObjCMethod("stackedItemSpacing") func stackedItemSpacing() -> Double { barState.numbers["stackedItemSpacing"] ?? 0 }
    @ObjCMethod("setStackedItemSpacing:") func setStackedItemSpacing(_ value: Double) { barState.numbers["stackedItemSpacing"] = value }
}

/// The appearance of one state of a bar button item or a tab bar item: a
/// bag of the values set on it.
@ObjCClass("UIBarButtonItemStateAppearance")
open class UIBarButtonItemStateAppearance: UIBarAppearance {
    @ObjCMethod("titleTextAttributes") func titleTextAttributes() -> NSObject? { barState.objects["titleTextAttributes"] }
    @ObjCMethod("setTitleTextAttributes:") func setTitleTextAttributes(_ value: NSObject?) { barState.objects["titleTextAttributes"] = value }
    @ObjCMethod("titlePositionAdjustment") func titlePositionAdjustment() -> UIOffset { barState.sizes["titlePositionAdjustment"] ?? .zero }
    @ObjCMethod("setTitlePositionAdjustment:") func setTitlePositionAdjustment(_ offset: UIOffset) { barState.sizes["titlePositionAdjustment"] = offset }
    @ObjCMethod("backgroundImage") override func backgroundImage() -> NSObject? { barState.objects["backgroundImage"] }
    @ObjCMethod("backgroundImagePositionAdjustment") func backgroundImagePositionAdjustment() -> UIOffset { barState.sizes["backgroundImagePositionAdjustment"] ?? .zero }
    @ObjCMethod("setBackgroundImagePositionAdjustment:") func setBackgroundImagePositionAdjustment(_ offset: UIOffset) { barState.sizes["backgroundImagePositionAdjustment"] = offset }
    @ObjCMethod("backgroundImageTintColor") func backgroundImageTintColor() -> NSObject? { barState.objects["backgroundImageTintColor"] }
    @ObjCMethod("setBackgroundImageTintColor:") func setBackgroundImageTintColor(_ value: NSObject?) { barState.objects["backgroundImageTintColor"] = value }
}

/// UIBarButtonItemAppearance: a state appearance for each state.
@ObjCClass("UIBarButtonItemAppearance")
open class UIBarButtonItemAppearance: UIBarAppearance {
    @ObjCMethod("initWithStyle:")
    func initialize(style: Int) -> Self {
        barState.numbers["style"] = Double(style)
        return self
    }
    @ObjCMethod("configureWithStyle:") func configure(style: Int) { barState.numbers["style"] = Double(style) }

    @ObjCMethod("normal") func normal() -> NSObject { lazy("normal", UIBarButtonItemStateAppearance.objCClass) }
    @ObjCMethod("highlighted") func highlighted() -> NSObject { lazy("highlighted", UIBarButtonItemStateAppearance.objCClass) }
    @ObjCMethod("disabled") func disabled() -> NSObject { lazy("disabled", UIBarButtonItemStateAppearance.objCClass) }
    @ObjCMethod("focused") func focused() -> NSObject { lazy("focused", UIBarButtonItemStateAppearance.objCClass) }
}

/// The appearance of a tab bar item in one state.
@ObjCClass("UITabBarItemStateAppearance")
open class UITabBarItemStateAppearance: UIBarAppearance {
    @ObjCMethod("iconColor") func iconColor() -> NSObject? { barState.objects["iconColor"] }
    @ObjCMethod("setIconColor:") func setIconColor(_ value: NSObject?) { barState.objects["iconColor"] = value }
    @ObjCMethod("titleTextAttributes") func titleTextAttributes() -> NSObject? { barState.objects["titleTextAttributes"] }
    @ObjCMethod("setTitleTextAttributes:") func setTitleTextAttributes(_ value: NSObject?) { barState.objects["titleTextAttributes"] = value }
    @ObjCMethod("titlePositionAdjustment") func titlePositionAdjustment() -> UIOffset { barState.sizes["titlePositionAdjustment"] ?? .zero }
    @ObjCMethod("setTitlePositionAdjustment:") func setTitlePositionAdjustment(_ offset: UIOffset) { barState.sizes["titlePositionAdjustment"] = offset }
    @ObjCMethod("badgeBackgroundColor") func badgeBackgroundColor() -> NSObject? { barState.objects["badgeBackgroundColor"] }
    @ObjCMethod("setBadgeBackgroundColor:") func setBadgeBackgroundColor(_ value: NSObject?) { barState.objects["badgeBackgroundColor"] = value }
    @ObjCMethod("badgeTextAttributes") func badgeTextAttributes() -> NSObject? { barState.objects["badgeTextAttributes"] }
    @ObjCMethod("setBadgeTextAttributes:") func setBadgeTextAttributes(_ value: NSObject?) { barState.objects["badgeTextAttributes"] = value }
    @ObjCMethod("badgeTitlePositionAdjustment") func badgeTitlePositionAdjustment() -> UIOffset { barState.sizes["badgeTitlePositionAdjustment"] ?? .zero }
    @ObjCMethod("setBadgeTitlePositionAdjustment:") func setBadgeTitlePositionAdjustment(_ offset: UIOffset) { barState.sizes["badgeTitlePositionAdjustment"] = offset }
}

/// UITabBarItemAppearance: a state appearance for each state.
@ObjCClass("UITabBarItemAppearance")
open class UITabBarItemAppearance: UIBarAppearance {
    @ObjCMethod("initWithStyle:")
    func initialize(style: Int) -> Self {
        barState.numbers["style"] = Double(style)
        return self
    }
    @ObjCMethod("configureWithStyle:") func configure(style: Int) { barState.numbers["style"] = Double(style) }

    @ObjCMethod("normal") func normal() -> NSObject { lazy("normal", UITabBarItemStateAppearance.objCClass) }
    @ObjCMethod("selected") func selected() -> NSObject { lazy("selected", UITabBarItemStateAppearance.objCClass) }
    @ObjCMethod("disabled") func disabled() -> NSObject { lazy("disabled", UITabBarItemStateAppearance.objCClass) }
    @ObjCMethod("focused") func focused() -> NSObject { lazy("focused", UITabBarItemStateAppearance.objCClass) }
}
