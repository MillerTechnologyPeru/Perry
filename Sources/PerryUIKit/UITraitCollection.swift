import CPerryGeometry
import Glibc
import PerryObjCInterop

// UITraitCollection: the environment views are drawn for. Perry's is a
// phone in the light appearance at the screen's scale, with the size
// classes its screen has: regular width from 700 points, as an iPad's, and
// compact height below 500, as a phone's in landscape. Collections an app
// makes hold just the traits it gives, the rest unspecified.

final class TraitState: ObjectState {
    /// UIUserInterfaceIdiom: unspecified -1, phone 0, pad 1.
    var idiom = -1
    /// UIUserInterfaceStyle: unspecified 0, light 1, dark 2.
    var style = 0
    /// UIUserInterfaceSizeClass: unspecified 0, compact 1, regular 2.
    var horizontalSizeClass = 0
    var verticalSizeClass = 0
    var displayScale: CGFloat = 0
    /// UITraitEnvironmentLayoutDirection: unspecified -1, left to right 0.
    var layoutDirection = -1
    var contentSizeCategory = "_UICTContentSizeCategoryUnspecified"
}

/// The appearance views are drawn in unless they or something above them
/// override it: light, or dark with PERRY_UIKIT_APPEARANCE=dark, which
/// whoever starts the app sets from the desktop's preference.
enum SystemAppearance {
    /// UIUserInterfaceStyle: light 1, dark 2.
    static let style: Int = {
        guard let value = getenv("PERRY_UIKIT_APPEARANCE") else { return 1 }
        return String(cString: value).lowercased() == "dark" ? 2 : 1
    }()
}

@ObjCClass("UITraitCollection")
open class UITraitCollection: NSObject {
    static let states = StateTable<TraitState>()
    var traits: TraitState { UITraitCollection.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UITraitCollection.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UITraitCollection.objCClass.pointer)
    }

    private static func make(_ cls: ObjCClass = objCClass, _ body: (TraitState) -> Void) -> UITraitCollection {
        let collection = cls.object.allocated().unsafeCast(to: UITraitCollection.self)
        body(collection.traits)
        return collection
    }

    /// The device's traits, every one specified.
    static func device(style: Int = SystemAppearance.style) -> UITraitCollection {
        make { traits in
            let size = Screen.bounds.size
            traits.idiom = 0
            traits.style = style
            traits.horizontalSizeClass = size.width >= 700 ? 2 : 1
            traits.verticalSizeClass = size.height < 500 ? 1 : 2
            traits.displayScale = Screen.scale
            traits.layoutDirection = 0
            traits.contentSizeCategory = "UICTContentSizeCategoryL"
        }
    }

    @ObjCClassMethod("currentTraitCollection") static func current() -> UITraitCollection { device() }
    @ObjCClassMethod("setCurrentTraitCollection:") static func setCurrent(_ collection: UITraitCollection?) {}

    @ObjCClassMethod("traitCollectionWithUserInterfaceIdiom:")
    static func with(_ cls: ObjCClass, idiom: Int) -> UITraitCollection { make(cls) { $0.idiom = idiom } }
    @ObjCClassMethod("traitCollectionWithUserInterfaceStyle:")
    static func with(_ cls: ObjCClass, style: Int) -> UITraitCollection { make(cls) { $0.style = style } }
    @ObjCClassMethod("traitCollectionWithHorizontalSizeClass:")
    static func with(_ cls: ObjCClass, horizontalSizeClass: Int) -> UITraitCollection { make(cls) { $0.horizontalSizeClass = horizontalSizeClass } }
    @ObjCClassMethod("traitCollectionWithVerticalSizeClass:")
    static func with(_ cls: ObjCClass, verticalSizeClass: Int) -> UITraitCollection { make(cls) { $0.verticalSizeClass = verticalSizeClass } }
    @ObjCClassMethod("traitCollectionWithDisplayScale:")
    static func with(_ cls: ObjCClass, displayScale: CGFloat) -> UITraitCollection { make(cls) { $0.displayScale = displayScale } }
    @ObjCClassMethod("traitCollectionWithLayoutDirection:")
    static func with(_ cls: ObjCClass, layoutDirection: Int) -> UITraitCollection { make(cls) { $0.layoutDirection = layoutDirection } }
    @ObjCClassMethod("traitCollectionWithPreferredContentSizeCategory:")
    static func with(_ cls: ObjCClass, contentSizeCategory: String) -> UITraitCollection {
        make(cls) { $0.contentSizeCategory = contentSizeCategory }
    }

    // Traits that are the same on every device here: a collection that
    // specifies none of the traits kept.
    @ObjCClassMethod("traitCollectionWithForceTouchCapability:")
    static func with(_ cls: ObjCClass, forceTouchCapability: Int) -> UITraitCollection { make(cls) { _ in } }
    @ObjCClassMethod("traitCollectionWithDisplayGamut:")
    static func with(_ cls: ObjCClass, displayGamut: Int) -> UITraitCollection { make(cls) { _ in } }
    @ObjCClassMethod("traitCollectionWithAccessibilityContrast:")
    static func with(_ cls: ObjCClass, accessibilityContrast: Int) -> UITraitCollection { make(cls) { _ in } }
    @ObjCClassMethod("traitCollectionWithLegibilityWeight:")
    static func with(_ cls: ObjCClass, legibilityWeight: Int) -> UITraitCollection { make(cls) { _ in } }
    @ObjCClassMethod("traitCollectionWithUserInterfaceLevel:")
    static func with(_ cls: ObjCClass, userInterfaceLevel: Int) -> UITraitCollection { make(cls) { _ in } }
    @ObjCClassMethod("traitCollectionWithActiveAppearance:")
    static func with(_ cls: ObjCClass, activeAppearance: Int) -> UITraitCollection { make(cls) { _ in } }

    /// Each trait from the last collection that specifies it.
    @ObjCClassMethod("traitCollectionWithTraitsFromCollections:")
    static func combining(_ cls: ObjCClass, collections: NSArray) -> UITraitCollection {
        make(cls) { traits in
            for collection in collections.elements.compactMap({ $0.as(UITraitCollection.self) }) {
                let other = collection.traits
                if other.idiom != -1 { traits.idiom = other.idiom }
                if other.style != 0 { traits.style = other.style }
                if other.horizontalSizeClass != 0 { traits.horizontalSizeClass = other.horizontalSizeClass }
                if other.verticalSizeClass != 0 { traits.verticalSizeClass = other.verticalSizeClass }
                if other.displayScale != 0 { traits.displayScale = other.displayScale }
                if other.layoutDirection != -1 { traits.layoutDirection = other.layoutDirection }
                if other.contentSizeCategory != "_UICTContentSizeCategoryUnspecified" {
                    traits.contentSizeCategory = other.contentSizeCategory
                }
            }
        }
    }

    /// These traits in the appearance `style`.
    func with(style: Int) -> UITraitCollection {
        let mine = traits
        return UITraitCollection.make { traits in
            traits.idiom = mine.idiom
            traits.style = style
            traits.horizontalSizeClass = mine.horizontalSizeClass
            traits.verticalSizeClass = mine.verticalSizeClass
            traits.displayScale = mine.displayScale
            traits.layoutDirection = mine.layoutDirection
            traits.contentSizeCategory = mine.contentSizeCategory
        }
    }

    @ObjCMethod("userInterfaceIdiom") func userInterfaceIdiom() -> Int { traits.idiom }
    @ObjCMethod("userInterfaceStyle") func userInterfaceStyle() -> Int { traits.style }
    @ObjCMethod("horizontalSizeClass") func horizontalSizeClass() -> Int { traits.horizontalSizeClass }
    @ObjCMethod("verticalSizeClass") func verticalSizeClass() -> Int { traits.verticalSizeClass }
    @ObjCMethod("displayScale") func displayScale() -> CGFloat { traits.displayScale }
    /// The configuration images are chosen by under the traits: one that
    /// asks for nothing.
    @ObjCMethod("imageConfiguration")
    func imageConfiguration() -> UIImageConfiguration { UIImageConfiguration.make(UIImageConfiguration.objCClass) { _ in } }
    /// No custom traits are kept.
    @ObjCMethod("objectForTrait:") func object(forTrait trait: NSObject?) -> NSObject? { nil }
    @ObjCMethod("layoutDirection") func layoutDirection() -> Int { traits.layoutDirection }
    @ObjCMethod("preferredContentSizeCategory") func preferredContentSizeCategory() -> String { traits.contentSizeCategory }
    /// UIForceTouchCapability: unavailable 1.
    @ObjCMethod("forceTouchCapability") func forceTouchCapability() -> Int { 1 }
    /// UIDisplayGamut: sRGB 0.
    @ObjCMethod("displayGamut") func displayGamut() -> Int { 0 }
    @ObjCMethod("accessibilityContrast") func accessibilityContrast() -> Int { 0 }
    @ObjCMethod("legibilityWeight") func legibilityWeight() -> Int { 0 }
    @ObjCMethod("userInterfaceLevel") func userInterfaceLevel() -> Int { 0 }
    @ObjCMethod("activeAppearance") func activeAppearance() -> Int { 1 }

    /// Whether every trait `other` specifies is the same here.
    @ObjCMethod("containsTraitsInCollection:")
    func contains(_ other: UITraitCollection?) -> Bool {
        guard let other = other?.traits else { return true }
        let mine = traits
        return (other.idiom == -1 || other.idiom == mine.idiom) && (other.style == 0 || other.style == mine.style)
            && (other.horizontalSizeClass == 0 || other.horizontalSizeClass == mine.horizontalSizeClass)
            && (other.verticalSizeClass == 0 || other.verticalSizeClass == mine.verticalSizeClass)
            && (other.displayScale == 0 || other.displayScale == mine.displayScale)
            && (other.layoutDirection == -1 || other.layoutDirection == mine.layoutDirection)
    }

    /// The appearance never changes here.
    @ObjCMethod("hasDifferentColorAppearanceComparedToTraitCollection:")
    func hasDifferentColorAppearance(comparedTo other: UITraitCollection?) -> Bool { other.map { $0.traits.style != traits.style } ?? true }

    /// Runs `actions` with this collection current.
    @ObjCMethod("performAsCurrentTraitCollection:")
    func performAsCurrent(_ actions: ObjCBlock?) { actions.map { Blocks.call($0) } }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(UITraitCollection.self) else { return false }
        return contains(other) && other.contains(self)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

/// UITraitEnvironment's message, sent so apps' overrides run.
extension NSObject {
    @ObjCMethod("traitCollectionDidChange:") func sendTraitCollectionDidChange(_ previous: UITraitCollection?)
}

// MARK: - Trait definitions

// The system's traits, as the classes a program names to say which traits'
// changes it registers for. A registration here is called for any change,
// so the classes only need to be there.

/// What the system's trait classes are of.
@ObjCClass("_PerryTraitDefinition")
open class PerryTraitDefinition: NSObject {
    /// The trait's values do not take part in color appearance or in
    /// animations here.
    @ObjCClassMethod("affectsColorAppearance") static func affectsColorAppearance(_ cls: ObjCClass) -> Bool { false }
}

@ObjCClass("UITraitUserInterfaceIdiom") open class UITraitUserInterfaceIdiom: PerryTraitDefinition {}
@ObjCClass("UITraitUserInterfaceStyle") open class UITraitUserInterfaceStyle: PerryTraitDefinition {}
@ObjCClass("UITraitUserInterfaceLevel") open class UITraitUserInterfaceLevel: PerryTraitDefinition {}
@ObjCClass("UITraitLayoutDirection") open class UITraitLayoutDirection: PerryTraitDefinition {}
@ObjCClass("UITraitDisplayScale") open class UITraitDisplayScale: PerryTraitDefinition {}
@ObjCClass("UITraitHorizontalSizeClass") open class UITraitHorizontalSizeClass: PerryTraitDefinition {}
@ObjCClass("UITraitVerticalSizeClass") open class UITraitVerticalSizeClass: PerryTraitDefinition {}
@ObjCClass("UITraitForceTouchCapability") open class UITraitForceTouchCapability: PerryTraitDefinition {}
@ObjCClass("UITraitPreferredContentSizeCategory") open class UITraitPreferredContentSizeCategory: PerryTraitDefinition {}
@ObjCClass("UITraitDisplayGamut") open class UITraitDisplayGamut: PerryTraitDefinition {}
@ObjCClass("UITraitAccessibilityContrast") open class UITraitAccessibilityContrast: PerryTraitDefinition {}
@ObjCClass("UITraitActiveAppearance") open class UITraitActiveAppearance: PerryTraitDefinition {}
@ObjCClass("UITraitLegibilityWeight") open class UITraitLegibilityWeight: PerryTraitDefinition {}
@ObjCClass("UITraitToolbarItemPresentationSize") open class UITraitToolbarItemPresentationSize: PerryTraitDefinition {}
@ObjCClass("UITraitImageDynamicRange") open class UITraitImageDynamicRange: PerryTraitDefinition {}
@ObjCClass("UITraitTypesettingLanguage") open class UITraitTypesettingLanguage: PerryTraitDefinition {}
@ObjCClass("UITraitSceneCaptureState") open class UITraitSceneCaptureState: PerryTraitDefinition {}
@ObjCClass("UITraitListEnvironment") open class UITraitListEnvironment: PerryTraitDefinition {}
