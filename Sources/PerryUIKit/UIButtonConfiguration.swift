import CPerryGeometry
import PerryObjCInterop

// Button and background configurations. A button with a configuration takes
// its title, image, colors, insets and background from it: the background
// is a view of its own behind the content, with the fill, the corners, the
// stroke and any custom view. The subtitle and the activity indicator are
// kept and not shown, and of a background only the fill, corners, stroke
// and custom view are drawn.

final class BackgroundConfigurationState: ObjectState {
    var customView: UIView?
    var cornerRadius: CGFloat = 0
    /// NSDirectionalEdgeInsets, as UIEdgeInsets (leading is left).
    var backgroundInsets = UIEdgeInsets.zero
    var edgesAddingLayoutMargins: UInt = 0
    /// The fill, or none for the one whatever shows the background gives it.
    var backgroundColor: UIColor?
    var backgroundColorTransformer: ObjCBlock?
    var visualEffect: UIVisualEffect?
    var image: UIImage?
    var imageContentMode = 0
    var strokeColor: UIColor?
    var strokeColorTransformer: ObjCBlock?
    var strokeWidth: CGFloat = 0
    var strokeOutset: CGFloat = 0

    func copy(to other: BackgroundConfigurationState) {
        (other.customView, other.cornerRadius, other.backgroundInsets) = (customView, cornerRadius, backgroundInsets)
        (other.edgesAddingLayoutMargins, other.backgroundColor) = (edgesAddingLayoutMargins, backgroundColor)
        (other.backgroundColorTransformer, other.visualEffect) = (backgroundColorTransformer, visualEffect)
        (other.image, other.imageContentMode) = (image, imageContentMode)
        (other.strokeColor, other.strokeColorTransformer) = (strokeColor, strokeColorTransformer)
        (other.strokeWidth, other.strokeOutset) = (strokeWidth, strokeOutset)
    }
}

@ObjCClass("UIBackgroundConfiguration")
open class UIBackgroundConfiguration: NSObject {
    static let states = StateTable<BackgroundConfigurationState>()
    var background: BackgroundConfigurationState { UIBackgroundConfiguration.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIBackgroundConfiguration.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIBackgroundConfiguration.objCClass.pointer)
    }

    static func make(_ cls: ObjCClass = objCClass, _ body: (BackgroundConfigurationState) -> Void = { _ in }) -> UIBackgroundConfiguration {
        let made = cls.object.allocated().initialized().unsafeCast(to: UIBackgroundConfiguration.self)
        body(made.background)
        return made
    }

    @ObjCClassMethod("clearConfiguration")
    static func clear(_ cls: ObjCClass) -> UIBackgroundConfiguration { make(cls) { $0.backgroundColor = UIColor.clear() } }

    // The list backgrounds: a plain cell's is the system background, a
    // grouped one's the secondary, and the headers' and footers' clear.
    @ObjCClassMethod("listPlainCellConfiguration")
    static func listPlainCell(_ cls: ObjCClass) -> UIBackgroundConfiguration { make(cls) { $0.backgroundColor = UIColor.systemBackground() } }
    @ObjCClassMethod("listCellConfiguration")
    static func listCell(_ cls: ObjCClass) -> UIBackgroundConfiguration { listPlainCell(cls) }
    @ObjCClassMethod("listGroupedCellConfiguration")
    static func listGroupedCell(_ cls: ObjCClass) -> UIBackgroundConfiguration {
        make(cls) { $0.backgroundColor = UIColor.secondarySystemGroupedBackground() }
    }
    @ObjCClassMethod("listSidebarCellConfiguration")
    static func listSidebarCell(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }
    @ObjCClassMethod("listAccompaniedSidebarCellConfiguration")
    static func listAccompaniedSidebarCell(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }
    @ObjCClassMethod("listPlainHeaderFooterConfiguration")
    static func listPlainHeaderFooter(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }
    @ObjCClassMethod("listGroupedHeaderFooterConfiguration")
    static func listGroupedHeaderFooter(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }
    @ObjCClassMethod("listSidebarHeaderConfiguration")
    static func listSidebarHeader(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }
    @ObjCClassMethod("listHeaderConfiguration")
    static func listHeader(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }
    @ObjCClassMethod("listFooterConfiguration")
    static func listFooter(_ cls: ObjCClass) -> UIBackgroundConfiguration { clear(cls) }

    func duplicate() -> UIBackgroundConfiguration {
        let source = background
        return UIBackgroundConfiguration.make { source.copy(to: $0) }
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        // The copy is retained while its wrapper still holds it.
        let made = duplicate()
        return withExtendedLifetime(made) { ObjCRuntime.retain(made.objcObject)! }
    }

    /// A background is the same in every state here.
    @ObjCMethod("updatedConfigurationForState:")
    func updated(for state: NSObject?) -> UIBackgroundConfiguration { duplicate() }

    @ObjCMethod("customView") func customView() -> UIView? { background.customView }
    @ObjCMethod("setCustomView:") func setCustomView(_ view: UIView?) { background.customView = view }
    @ObjCMethod("cornerRadius") func cornerRadius() -> CGFloat { background.cornerRadius }
    @ObjCMethod("setCornerRadius:") func setCornerRadius(_ radius: CGFloat) { background.cornerRadius = radius }
    @ObjCMethod("backgroundInsets") func backgroundInsets() -> UIEdgeInsets { background.backgroundInsets }
    @ObjCMethod("setBackgroundInsets:") func setBackgroundInsets(_ insets: UIEdgeInsets) { background.backgroundInsets = insets }
    @ObjCMethod("edgesAddingLayoutMarginsToBackgroundInsets") func edgesAddingLayoutMargins() -> UInt { background.edgesAddingLayoutMargins }
    @ObjCMethod("setEdgesAddingLayoutMarginsToBackgroundInsets:")
    func setEdgesAddingLayoutMargins(_ edges: UInt) { background.edgesAddingLayoutMargins = edges }
    @ObjCMethod("backgroundColor") func backgroundColor() -> UIColor? { background.backgroundColor }
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UIColor?) { background.backgroundColor = color }
    @ObjCMethod("backgroundColorTransformer") func backgroundColorTransformer() -> ObjCBlock? { background.backgroundColorTransformer }
    @ObjCMethod("setBackgroundColorTransformer:")
    func setBackgroundColorTransformer(_ transformer: ObjCBlock?) { background.backgroundColorTransformer = transformer }
    @ObjCMethod("visualEffect") func visualEffect() -> UIVisualEffect? { background.visualEffect }
    @ObjCMethod("setVisualEffect:") func setVisualEffect(_ effect: UIVisualEffect?) { background.visualEffect = effect }
    @ObjCMethod("image") func image() -> UIImage? { background.image }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { background.image = image }
    @ObjCMethod("imageContentMode") func imageContentMode() -> Int { background.imageContentMode }
    @ObjCMethod("setImageContentMode:") func setImageContentMode(_ mode: Int) { background.imageContentMode = mode }
    @ObjCMethod("strokeColor") func strokeColor() -> UIColor? { background.strokeColor }
    @ObjCMethod("setStrokeColor:") func setStrokeColor(_ color: UIColor?) { background.strokeColor = color }
    @ObjCMethod("strokeColorTransformer") func strokeColorTransformer() -> ObjCBlock? { background.strokeColorTransformer }
    @ObjCMethod("setStrokeColorTransformer:")
    func setStrokeColorTransformer(_ transformer: ObjCBlock?) { background.strokeColorTransformer = transformer }
    @ObjCMethod("strokeWidth") func strokeWidth() -> CGFloat { background.strokeWidth }
    @ObjCMethod("setStrokeWidth:") func setStrokeWidth(_ width: CGFloat) { background.strokeWidth = width }
    @ObjCMethod("strokeOutset") func strokeOutset() -> CGFloat { background.strokeOutset }
    @ObjCMethod("setStrokeOutset:") func setStrokeOutset(_ outset: CGFloat) { background.strokeOutset = outset }

    /// The fill: the background's own color, else the tint, through the
    /// transformer if there is one.
    @ObjCMethod("resolvedBackgroundColorForTintColor:")
    func resolvedBackgroundColor(tint: UIColor?) -> UIColor? {
        let color = background.backgroundColor ?? tint
        guard let transformer = background.backgroundColorTransformer, let color else { return color }
        return Blocks.object(transformer, color)?.as(UIColor.self) ?? color
    }

    @ObjCMethod("resolvedStrokeColorForTintColor:")
    func resolvedStrokeColor(tint: UIColor?) -> UIColor? {
        let color = background.strokeColor ?? tint
        guard let transformer = background.strokeColorTransformer, let color else { return color }
        return Blocks.object(transformer, color)?.as(UIColor.self) ?? color
    }
}

extension Blocks {
    /// A block taking one object and giving one.
    static func object(_ block: ObjCBlock, _ object: NSObject?) -> NSObject? {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        return block.function(as: Invoke.self)(block.object, object?.objcObject).map { NSObject($0) }
    }
}

final class ButtonConfigurationState: ObjectState {
    /// Plain 0, gray 1, tinted 2, filled 3.
    var style = 0
    var title: String?
    var attributedTitle: NSObject?
    var subtitle: String?
    var attributedSubtitle: NSObject?
    var image: UIImage?
    var baseForegroundColor: UIColor?
    var baseBackgroundColor: UIColor?
    /// NSDirectionalEdgeInsets, as UIEdgeInsets (leading is left).
    var contentInsets = ButtonConfigurationState.defaultInsets
    var imagePadding: CGFloat = 0
    var titlePadding: CGFloat = 1
    /// NSDirectionalRectEdge: top 1, leading 2, bottom 4, trailing 8.
    var imagePlacement: UInt = 2
    /// UIButtonConfigurationCornerStyle: fixed -1, dynamic 0, small 1,
    /// medium 2, large 3, capsule 4.
    var cornerStyle = 0
    var buttonSize = 0
    var titleAlignment = 0
    var titleLineBreakMode = 0
    var macIdiomStyle = 0
    var indicator = 0
    var showsActivityIndicator = false
    var automaticallyUpdateForSelection = true
    var background: UIBackgroundConfiguration?
    var titleTextAttributesTransformer: ObjCBlock?
    var subtitleTextAttributesTransformer: ObjCBlock?
    var imageColorTransformer: ObjCBlock?
    var activityIndicatorColorTransformer: ObjCBlock?
    var indicatorColorTransformer: ObjCBlock?
    var preferredSymbolConfigurationForImage: NSObject?

    static let defaultInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)

    func copy(to other: ButtonConfigurationState) {
        (other.style, other.title, other.attributedTitle) = (style, title, attributedTitle)
        (other.subtitle, other.attributedSubtitle, other.image) = (subtitle, attributedSubtitle, image)
        (other.baseForegroundColor, other.baseBackgroundColor) = (baseForegroundColor, baseBackgroundColor)
        (other.contentInsets, other.imagePadding, other.titlePadding) = (contentInsets, imagePadding, titlePadding)
        (other.imagePlacement, other.cornerStyle, other.buttonSize) = (imagePlacement, cornerStyle, buttonSize)
        (other.titleAlignment, other.titleLineBreakMode) = (titleAlignment, titleLineBreakMode)
        (other.macIdiomStyle, other.indicator) = (macIdiomStyle, indicator)
        (other.showsActivityIndicator, other.automaticallyUpdateForSelection) = (showsActivityIndicator, automaticallyUpdateForSelection)
        other.background = background?.duplicate()
        (other.titleTextAttributesTransformer, other.subtitleTextAttributesTransformer) =
            (titleTextAttributesTransformer, subtitleTextAttributesTransformer)
        (other.imageColorTransformer, other.activityIndicatorColorTransformer) = (imageColorTransformer, activityIndicatorColorTransformer)
        (other.indicatorColorTransformer, other.preferredSymbolConfigurationForImage) =
            (indicatorColorTransformer, preferredSymbolConfigurationForImage)
    }
}

@ObjCClass("UIButtonConfiguration")
open class UIButtonConfiguration: NSObject {
    static let states = StateTable<ButtonConfigurationState>()
    var configuration: ButtonConfigurationState { UIButtonConfiguration.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIButtonConfiguration.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIButtonConfiguration.objCClass.pointer)
    }

    private static func make(_ cls: ObjCClass, style: Int) -> UIButtonConfiguration {
        let made = cls.object.allocated().initialized().unsafeCast(to: UIButtonConfiguration.self)
        made.configuration.style = style
        made.configuration.background = UIBackgroundConfiguration.make { $0.cornerRadius = 6 }
        return made
    }

    @ObjCClassMethod("plainButtonConfiguration") static func plain(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 0) }
    @ObjCClassMethod("borderlessButtonConfiguration") static func borderless(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 0) }
    @ObjCClassMethod("grayButtonConfiguration") static func gray(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 1) }
    @ObjCClassMethod("borderedButtonConfiguration") static func bordered(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 1) }
    @ObjCClassMethod("tintedButtonConfiguration") static func tinted(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 2) }
    @ObjCClassMethod("borderedTintedButtonConfiguration")
    static func borderedTinted(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 2) }
    @ObjCClassMethod("filledButtonConfiguration") static func filled(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 3) }
    @ObjCClassMethod("borderedProminentButtonConfiguration")
    static func borderedProminent(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 3) }
    // The glass styles show as the gray and the filled ones do.
    @ObjCClassMethod("glassButtonConfiguration") static func glass(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 1) }
    @ObjCClassMethod("clearGlassButtonConfiguration") static func clearGlass(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 1) }
    @ObjCClassMethod("prominentGlassButtonConfiguration")
    static func prominentGlass(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 3) }
    @ObjCClassMethod("prominentClearGlassButtonConfiguration")
    static func prominentClearGlass(_ cls: ObjCClass) -> UIButtonConfiguration { make(cls, style: 3) }

    func duplicate() -> UIButtonConfiguration {
        let made = UIButtonConfiguration.objCClass.object.allocated().initialized().unsafeCast(to: UIButtonConfiguration.self)
        configuration.copy(to: made.configuration)
        return made
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        // The copy is retained while its wrapper still holds it.
        let made = duplicate()
        return withExtendedLifetime(made) { ObjCRuntime.retain(made.objcObject)! }
    }

    /// A configuration is the same in every state of a button here.
    @ObjCMethod("updatedConfigurationForButton:")
    func updated(for button: UIButton?) -> UIButtonConfiguration { duplicate() }

    @ObjCMethod("setDefaultContentInsets") func setDefaultContentInsets() { configuration.contentInsets = ButtonConfigurationState.defaultInsets }

    @ObjCMethod("background")
    func background() -> UIBackgroundConfiguration {
        if let background = configuration.background { return background }
        let background = UIBackgroundConfiguration.make { $0.cornerRadius = 6 }
        configuration.background = background
        return background
    }
    @ObjCMethod("setBackground:") func setBackground(_ background: UIBackgroundConfiguration?) { configuration.background = background?.duplicate() }

    @ObjCMethod("title") func title() -> String? { configuration.title ?? configuration.attributedTitle?.sendString() }
    @ObjCMethod("setTitle:") func setTitle(_ title: String?) { (configuration.title, configuration.attributedTitle) = (title, nil) }
    @ObjCMethod("attributedTitle") func attributedTitle() -> NSObject? { configuration.attributedTitle }
    @ObjCMethod("setAttributedTitle:")
    func setAttributedTitle(_ title: NSObject?) { (configuration.title, configuration.attributedTitle) = (nil, title) }
    @ObjCMethod("subtitle") func subtitle() -> String? { configuration.subtitle ?? configuration.attributedSubtitle?.sendString() }
    @ObjCMethod("setSubtitle:") func setSubtitle(_ subtitle: String?) { (configuration.subtitle, configuration.attributedSubtitle) = (subtitle, nil) }
    @ObjCMethod("attributedSubtitle") func attributedSubtitle() -> NSObject? { configuration.attributedSubtitle }
    @ObjCMethod("setAttributedSubtitle:")
    func setAttributedSubtitle(_ subtitle: NSObject?) { (configuration.subtitle, configuration.attributedSubtitle) = (nil, subtitle) }
    @ObjCMethod("image") func image() -> UIImage? { configuration.image }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { configuration.image = image }
    @ObjCMethod("baseForegroundColor") func baseForegroundColor() -> UIColor? { configuration.baseForegroundColor }
    @ObjCMethod("setBaseForegroundColor:") func setBaseForegroundColor(_ color: UIColor?) { configuration.baseForegroundColor = color }
    @ObjCMethod("baseBackgroundColor") func baseBackgroundColor() -> UIColor? { configuration.baseBackgroundColor }
    @ObjCMethod("setBaseBackgroundColor:") func setBaseBackgroundColor(_ color: UIColor?) { configuration.baseBackgroundColor = color }
    @ObjCMethod("contentInsets") func contentInsets() -> UIEdgeInsets { configuration.contentInsets }
    @ObjCMethod("setContentInsets:") func setContentInsets(_ insets: UIEdgeInsets) { configuration.contentInsets = insets }
    @ObjCMethod("imagePadding") func imagePadding() -> CGFloat { configuration.imagePadding }
    @ObjCMethod("setImagePadding:") func setImagePadding(_ padding: CGFloat) { configuration.imagePadding = padding }
    @ObjCMethod("titlePadding") func titlePadding() -> CGFloat { configuration.titlePadding }
    @ObjCMethod("setTitlePadding:") func setTitlePadding(_ padding: CGFloat) { configuration.titlePadding = padding }
    @ObjCMethod("imagePlacement") func imagePlacement() -> UInt { configuration.imagePlacement }
    @ObjCMethod("setImagePlacement:") func setImagePlacement(_ placement: UInt) { configuration.imagePlacement = placement }
    @ObjCMethod("cornerStyle") func cornerStyle() -> Int { configuration.cornerStyle }
    @ObjCMethod("setCornerStyle:") func setCornerStyle(_ style: Int) { configuration.cornerStyle = style }
    @ObjCMethod("buttonSize") func buttonSize() -> Int { configuration.buttonSize }
    @ObjCMethod("setButtonSize:") func setButtonSize(_ size: Int) { configuration.buttonSize = size }
    @ObjCMethod("titleAlignment") func titleAlignment() -> Int { configuration.titleAlignment }
    @ObjCMethod("setTitleAlignment:") func setTitleAlignment(_ alignment: Int) { configuration.titleAlignment = alignment }
    @ObjCMethod("titleLineBreakMode") func titleLineBreakMode() -> Int { configuration.titleLineBreakMode }
    @ObjCMethod("setTitleLineBreakMode:") func setTitleLineBreakMode(_ mode: Int) { configuration.titleLineBreakMode = mode }
    @ObjCMethod("subtitleLineBreakMode") func subtitleLineBreakMode() -> Int { configuration.titleLineBreakMode }
    @ObjCMethod("setSubtitleLineBreakMode:") func setSubtitleLineBreakMode(_ mode: Int) {}
    @ObjCMethod("macIdiomStyle") func macIdiomStyle() -> Int { configuration.macIdiomStyle }
    @ObjCMethod("setMacIdiomStyle:") func setMacIdiomStyle(_ style: Int) { configuration.macIdiomStyle = style }
    @ObjCMethod("indicator") func indicator() -> Int { configuration.indicator }
    @ObjCMethod("setIndicator:") func setIndicator(_ indicator: Int) { configuration.indicator = indicator }
    @ObjCMethod("showsActivityIndicator") func showsActivityIndicator() -> Bool { configuration.showsActivityIndicator }
    @ObjCMethod("setShowsActivityIndicator:") func setShowsActivityIndicator(_ shows: Bool) { configuration.showsActivityIndicator = shows }
    @ObjCMethod("automaticallyUpdateForSelection") func automaticallyUpdateForSelection() -> Bool { configuration.automaticallyUpdateForSelection }
    @ObjCMethod("setAutomaticallyUpdateForSelection:")
    func setAutomaticallyUpdateForSelection(_ updates: Bool) { configuration.automaticallyUpdateForSelection = updates }
    @ObjCMethod("titleTextAttributesTransformer") func titleTextAttributesTransformer() -> ObjCBlock? { configuration.titleTextAttributesTransformer }
    @ObjCMethod("setTitleTextAttributesTransformer:")
    func setTitleTextAttributesTransformer(_ transformer: ObjCBlock?) { configuration.titleTextAttributesTransformer = transformer }
    @ObjCMethod("subtitleTextAttributesTransformer")
    func subtitleTextAttributesTransformer() -> ObjCBlock? { configuration.subtitleTextAttributesTransformer }
    @ObjCMethod("setSubtitleTextAttributesTransformer:")
    func setSubtitleTextAttributesTransformer(_ transformer: ObjCBlock?) { configuration.subtitleTextAttributesTransformer = transformer }
    @ObjCMethod("imageColorTransformer") func imageColorTransformer() -> ObjCBlock? { configuration.imageColorTransformer }
    @ObjCMethod("setImageColorTransformer:")
    func setImageColorTransformer(_ transformer: ObjCBlock?) { configuration.imageColorTransformer = transformer }
    @ObjCMethod("activityIndicatorColorTransformer")
    func activityIndicatorColorTransformer() -> ObjCBlock? { configuration.activityIndicatorColorTransformer }
    @ObjCMethod("setActivityIndicatorColorTransformer:")
    func setActivityIndicatorColorTransformer(_ transformer: ObjCBlock?) { configuration.activityIndicatorColorTransformer = transformer }
    @ObjCMethod("indicatorColorTransformer") func indicatorColorTransformer() -> ObjCBlock? { configuration.indicatorColorTransformer }
    @ObjCMethod("setIndicatorColorTransformer:")
    func setIndicatorColorTransformer(_ transformer: ObjCBlock?) { configuration.indicatorColorTransformer = transformer }
    @ObjCMethod("preferredSymbolConfigurationForImage")
    func preferredSymbolConfigurationForImage() -> NSObject? { configuration.preferredSymbolConfigurationForImage }
    @ObjCMethod("setPreferredSymbolConfigurationForImage:")
    func setPreferredSymbolConfigurationForImage(_ symbol: NSObject?) { configuration.preferredSymbolConfigurationForImage = symbol }

    // MARK: What a button shows of it

    /// The title's and the image's color, and the fill, under a tint.
    func colors(tint: UIColor) -> (foreground: UIColor, fill: UIColor?) {
        let state = configuration
        var foreground = state.baseForegroundColor ?? tint
        var fill: UIColor?
        switch state.style {
        case 3:
            foreground = state.baseForegroundColor ?? UIColor.white()
            fill = state.baseBackgroundColor ?? tint
        case 2: fill = (state.baseBackgroundColor ?? tint).withAlphaComponent(0.18)
        case 1: fill = state.baseBackgroundColor ?? UIColor.systemGray5()
        default: break
        }
        if let background = state.background?.background {
            if let color = background.backgroundColor { fill = color }
            if let transformer = background.backgroundColorTransformer, let color = fill {
                fill = Blocks.object(transformer, color)?.as(UIColor.self) ?? color
            }
        }
        return (foreground, fill)
    }

    /// The title's font and color as the attributed title has them, then
    /// as the transformer changes them.
    func titleAttributes(foreground: UIColor) -> (font: UIFont?, color: UIColor) {
        let state = configuration
        var attributes: NSDictionary?
        if let attributed = state.attributedTitle?.as(NSAttributedString.self), attributed.length() > 0 {
            attributes = attributed.attributes(at: 0, effectiveRange: nil)
        }
        if let transformer = state.titleTextAttributesTransformer {
            let given: NSObject = attributes ?? NSDictionaryFactory.empty()
            attributes = Blocks.object(transformer, given)?.as(NSDictionary.self) ?? attributes
        }
        return (attributes?.object(forKey: "NSFont")?.as(UIFont.self), attributes?.object(forKey: "NSColor")?.as(UIColor.self) ?? foreground)
    }

    /// The background's corner radius in a button so high.
    func cornerRadius(height: CGFloat) -> CGFloat {
        switch configuration.cornerStyle {
        case 1: return 4
        case 3: return 8
        case 4: return height / 2
        default: return configuration.background?.background.cornerRadius ?? 6
        }
    }
}
