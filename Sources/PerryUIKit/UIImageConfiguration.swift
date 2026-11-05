import CPerryGeometry
import PerryObjCInterop

// Image configurations: the traits an image is for, and for SF Symbols the
// point size, weight and scale they are drawn at, which Symbols draws them
// in. Colors a configuration gives (hierarchical, palette, multicolor) are
// kept but symbols stay templates, tinted by the view that shows them.

final class ImageConfigurationState: ObjectState {
    var traits: UITraitCollection?
    /// The point size the symbol matches, or 0 for unspecified.
    var pointSize: CGFloat = 0
    /// UIImageSymbolWeight: unspecified 0, ultraLight 1 … regular 4,
    /// medium 5, semibold 6, bold 7, heavy 8, black 9.
    var weight = 0
    /// UIImageSymbolScale: default -1, unspecified 0, small 1, medium 2,
    /// large 3.
    var scale = 0
    var textStyle: String?
    var colors: [NSObject] = []
    var prefersMulticolor = false
}

@ObjCClass("UIImageConfiguration")
open class UIImageConfiguration: NSObject {
    static let states = StateTable<ImageConfigurationState>()
    var configuration: ImageConfigurationState { UIImageConfiguration.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIImageConfiguration.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIImageConfiguration.objCClass.pointer)
    }

    /// A new configuration of `cls`.
    static func make(_ cls: ObjCClass, _ body: (ImageConfigurationState) -> Void) -> UIImageConfiguration {
        let made = cls.object.allocated().unsafeCast(to: UIImageConfiguration.self)
        body(made.configuration)
        return made
    }

    /// A copy of this configuration, of its class.
    func copied(_ body: (ImageConfigurationState) -> Void = { _ in }) -> UIImageConfiguration {
        let mine = configuration
        let cls = ObjCClass(ObjCRuntime.objectClass(objcObject)!)
        return UIImageConfiguration.make(cls) { state in
            (state.traits, state.pointSize, state.weight, state.scale) = (mine.traits, mine.pointSize, mine.weight, mine.scale)
            (state.textStyle, state.colors, state.prefersMulticolor) = (mine.textStyle, mine.colors, mine.prefersMulticolor)
            body(state)
        }
    }

    @ObjCClassMethod("configurationWithTraitCollection:")
    static func with(_ cls: ObjCClass, traits: UITraitCollection?) -> UIImageConfiguration { make(cls) { $0.traits = traits } }

    @ObjCMethod("traitCollection") func traitCollection() -> UITraitCollection? { configuration.traits }

    @ObjCMethod("configurationWithTraitCollection:")
    func with(traits: UITraitCollection?) -> UIImageConfiguration { copied { $0.traits = traits } }

    /// This configuration with what `other` specifies instead.
    @ObjCMethod("configurationByApplyingConfiguration:")
    func applying(_ other: UIImageConfiguration?) -> UIImageConfiguration {
        guard let other = other?.configuration else { return self }
        return copied { state in
            if let traits = other.traits { state.traits = traits }
            if other.pointSize > 0 { state.pointSize = other.pointSize }
            if other.weight != 0 { state.weight = other.weight }
            if other.scale > 0 { state.scale = other.scale }
            if let style = other.textStyle { state.textStyle = style }
            if !other.colors.isEmpty { state.colors = other.colors }
            if other.prefersMulticolor { state.prefersMulticolor = true }
        }
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

@ObjCClass("UIImageSymbolConfiguration")
open class UIImageSymbolConfiguration: UIImageConfiguration {
    @ObjCClassMethod("unspecifiedConfiguration")
    static func unspecified(_ cls: ObjCClass) -> UIImageConfiguration { make(cls) { _ in } }
    @ObjCClassMethod("defaultConfiguration")
    static func defaultConfiguration(_ cls: ObjCClass) -> UIImageConfiguration { make(cls) { $0.scale = -1 } }

    @ObjCClassMethod("configurationWithPointSize:")
    static func with(_ cls: ObjCClass, pointSize: CGFloat) -> UIImageConfiguration { make(cls) { $0.pointSize = pointSize } }
    @ObjCClassMethod("configurationWithPointSize:weight:")
    static func with(_ cls: ObjCClass, pointSize: CGFloat, weight: Int) -> UIImageConfiguration {
        make(cls) { ($0.pointSize, $0.weight) = (pointSize, weight) }
    }
    @ObjCClassMethod("configurationWithPointSize:weight:scale:")
    static func with(_ cls: ObjCClass, pointSize: CGFloat, weight: Int, scale: Int) -> UIImageConfiguration {
        make(cls) { ($0.pointSize, $0.weight, $0.scale) = (pointSize, weight, scale) }
    }
    @ObjCClassMethod("configurationWithWeight:")
    static func with(_ cls: ObjCClass, weight: Int) -> UIImageConfiguration { make(cls) { $0.weight = weight } }
    @ObjCClassMethod("configurationWithScale:")
    static func with(_ cls: ObjCClass, scale: Int) -> UIImageConfiguration { make(cls) { $0.scale = scale } }

    /// A text style's symbols: its font's size, and a headline's weight.
    @ObjCClassMethod("configurationWithTextStyle:")
    static func with(_ cls: ObjCClass, textStyle: String) -> UIImageConfiguration { with(cls, textStyle: textStyle, scale: 0) }
    @ObjCClassMethod("configurationWithTextStyle:scale:")
    static func with(_ cls: ObjCClass, textStyle: String, scale: Int) -> UIImageConfiguration {
        make(cls) { state in
            state.textStyle = textStyle
            state.pointSize = UIFont.textStyleSizes[textStyle] ?? 17
            state.weight = textStyle == "UICTFontTextStyleHeadline" ? 6 : 0
            state.scale = scale
        }
    }

    /// A font's symbols: its size and weight.
    @ObjCClassMethod("configurationWithFont:")
    static func with(_ cls: ObjCClass, font: UIFont) -> UIImageConfiguration { with(cls, font: font, scale: 0) }
    @ObjCClassMethod("configurationWithFont:scale:")
    static func with(_ cls: ObjCClass, font: UIFont, scale: Int) -> UIImageConfiguration {
        make(cls) { state in
            state.pointSize = font.state.pointSize
            state.weight = symbolWeight(fontWeight: font.state.weight)
            state.scale = scale
        }
    }

    @ObjCClassMethod("configurationWithHierarchicalColor:")
    static func with(_ cls: ObjCClass, hierarchicalColor: UIColor) -> UIImageConfiguration { make(cls) { $0.colors = [hierarchicalColor] } }
    @ObjCClassMethod("configurationWithPaletteColors:")
    static func with(_ cls: ObjCClass, paletteColors: NSArray) -> UIImageConfiguration { make(cls) { $0.colors = paletteColors.elements } }
    @ObjCClassMethod("configurationPreferringMulticolor")
    static func multicolor(_ cls: ObjCClass) -> UIImageConfiguration { make(cls) { $0.prefersMulticolor = true } }
    @ObjCClassMethod("configurationPreferringMonochrome")
    static func monochrome(_ cls: ObjCClass) -> UIImageConfiguration { make(cls) { _ in } }

    @ObjCMethod("configurationWithoutPointSizeAndWeight")
    func withoutPointSizeAndWeight() -> UIImageConfiguration { copied { ($0.pointSize, $0.weight) = (0, 0) } }
    @ObjCMethod("configurationWithoutScale") func withoutScale() -> UIImageConfiguration { copied { $0.scale = 0 } }
    @ObjCMethod("configurationWithoutWeight") func withoutWeight() -> UIImageConfiguration { copied { $0.weight = 0 } }
    @ObjCMethod("configurationWithoutTextStyle") func withoutTextStyle() -> UIImageConfiguration { copied { $0.textStyle = nil } }

    /// UIFontWeight (-1 to 1) as the nearest symbol weight.
    static func symbolWeight(fontWeight: CGFloat) -> Int {
        let weights: [(CGFloat, Int)] = [(-0.8, 1), (-0.6, 2), (-0.4, 3), (0, 4), (0.23, 5), (0.3, 6), (0.4, 7), (0.56, 8), (0.62, 9)]
        return weights.min { abs($0.0 - fontWeight) < abs($1.0 - fontWeight) }?.1 ?? 4
    }
}

extension Symbols {
    /// The square a symbol is drawn in, and its line width there, for a
    /// configuration: unconfigured, the 24-point square in regular lines.
    static func metrics(_ configuration: UIImageConfiguration?) -> (side: CGFloat, lineWidth: CGFloat) {
        guard let state = configuration?.configuration else { return (24, 2) }
        let scale: CGFloat = state.scale == 1 ? 0.8 : state.scale == 3 ? 1.3 : 1
        let side = state.pointSize > 0 ? (state.pointSize * 1.3 * scale).rounded() : 24 * scale
        let widths: [Int: CGFloat] = [1: 0.8, 2: 1.1, 3: 1.5, 4: 2, 5: 2.25, 6: 2.5, 7: 2.8, 8: 3.1, 9: 3.4]
        return (side, widths[state.weight] ?? 2)
    }
}

/// Scaled fonts and values for Dynamic Type. Perry's content size is the
/// default one, at which fonts and values are themselves.
@ObjCClass("UIFontMetrics")
open class UIFontMetrics: NSObject {
    @ObjCClassMethod("defaultMetrics") static func defaultMetrics(_ cls: ObjCClass) -> NSObject {
        cls.object.allocated().unsafeCast(to: NSObject.self)
    }
    @ObjCClassMethod("metricsForTextStyle:")
    static func metrics(_ cls: ObjCClass, textStyle: String) -> NSObject { cls.object.allocated().unsafeCast(to: NSObject.self) }

    @ObjCMethod("initForTextStyle:") func initialize(textStyle: String) -> Self { self }

    @ObjCMethod("scaledFontForFont:") func scaledFont(for font: UIFont) -> UIFont { font }
    @ObjCMethod("scaledFontForFont:maximumPointSize:")
    func scaledFont(for font: UIFont, maximumPointSize: CGFloat) -> UIFont {
        maximumPointSize > 0 && font.state.pointSize > maximumPointSize ? font.withSize(maximumPointSize) : font
    }
    @ObjCMethod("scaledFontForFont:compatibleWithTraitCollection:")
    func scaledFont(for font: UIFont, compatibleWith traits: NSObject?) -> UIFont { font }
    @ObjCMethod("scaledFontForFont:maximumPointSize:compatibleWithTraitCollection:")
    func scaledFont(for font: UIFont, maximumPointSize: CGFloat, compatibleWith traits: NSObject?) -> UIFont {
        scaledFont(for: font, maximumPointSize: maximumPointSize)
    }
    @ObjCMethod("scaledValueForValue:") func scaledValue(for value: CGFloat) -> CGFloat { value }
    @ObjCMethod("scaledValueForValue:compatibleWithTraitCollection:")
    func scaledValue(for value: CGFloat, compatibleWith traits: NSObject?) -> CGFloat { value }
}
