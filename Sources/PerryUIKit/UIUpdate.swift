import PerryObjCInterop

// UIKit's private update functions, which SwiftUI calls to fit its updates
// into UIKit's. Here UIKit has no update cycle of its own (UIUpdateLink's):
// SwiftUI then updates from run loop observers, as before iOS 18, and asks
// nothing of the update sequence.

@c(__UIUpdateCycleEnabled) public func _UIUpdateCycleEnabled() -> Bool { false }

/// Whether displays vary their refresh rate; none does here.
@c(__UIUpdateAdaptiveRateNeeded) public func _UIUpdateAdaptiveRateNeeded() -> Bool { false }

/// The factor UIKit slows animations by (Debug > Slow Animations): none.
@c(_UIAnimationDragCoefficient) public func UIAnimationDragCoefficient() -> Float { 1 }

/// Whether a view ignores touches during an animation; views here never do.
@c(_UIViewIgnoresTouchEvents) public func UIViewIgnoresTouchEvents(_ view: UnsafeMutableRawPointer?) -> Bool { false }

/// The hit test in progress, which UIKit keeps for gesture recognizers;
/// none here.
@c(__UICurrentHitTestContext) public func _UICurrentHitTestContext() -> UnsafeMutableRawPointer? { nil }

/// Key commands' special inputs.
@ObjCConstants
enum KeyInputs {
    static let UIKeyInputUpArrow = "UIKeyInputUpArrow"
    static let UIKeyInputDownArrow = "UIKeyInputDownArrow"
    static let UIKeyInputLeftArrow = "UIKeyInputLeftArrow"
    static let UIKeyInputRightArrow = "UIKeyInputRightArrow"
    static let UIKeyInputEscape = "UIKeyInputEscape"
    static let UIKeyInputPageUp = "UIKeyInputPageUp"
    static let UIKeyInputPageDown = "UIKeyInputPageDown"
    static let UIKeyInputHome = "UIKeyInputHome"
    static let UIKeyInputEnd = "UIKeyInputEnd"
    static let UIKeyInputDelete = "UIKeyInputDelete"
    static let UIKeyInputF1 = "UIKeyInputF1"
    static let UIKeyInputF2 = "UIKeyInputF2"
    static let UIKeyInputF3 = "UIKeyInputF3"
    static let UIKeyInputF4 = "UIKeyInputF4"
    static let UIKeyInputF5 = "UIKeyInputF5"
    static let UIKeyInputF6 = "UIKeyInputF6"
    static let UIKeyInputF7 = "UIKeyInputF7"
    static let UIKeyInputF8 = "UIKeyInputF8"
    static let UIKeyInputF9 = "UIKeyInputF9"
    static let UIKeyInputF10 = "UIKeyInputF10"
    static let UIKeyInputF11 = "UIKeyInputF11"
    static let UIKeyInputF12 = "UIKeyInputF12"
    static let UILargeContentViewerInteractionEnabledStatusDidChangeNotification =
        "UILargeContentViewerInteractionEnabledStatusDidChangeNotification"
    static let UISceneSystemProtectionDidChangeNotification = "UISceneSystemProtectionDidChangeNotification"
    static let NSAttachmentAttributeName = "NSAttachment"
    static let NSAdaptiveImageGlyphAttributeName = "CTAdaptiveImageProvider"
    static let NSTextEncapsulationAttributeName = "NSTextEncapsulation"
    static let UIFontDescriptorFeatureSettingsAttribute = "NSCTFontFeatureSettingsAttribute"
}

/// UIKit's Swift UIFocusSystem.focusSystem(for:): no environment has a
/// focus system here, which only devices with a pointer or keyboard focus
/// give.
@_silgen_name("_$sSo13UIFocusSystemC5UIKitE05focusB03forABSgSo0A11Environment_p_tFZ")
public func UIFocusSystemFocusSystem(_ environment: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
