import CPerryGeometry
import PerryObjCInterop

// CoreText's fonts, as UIKit's: a CTFont is a UIFont and a CTFontDescriptor
// a UIFontDescriptor, as they are toll-free bridged on Darwin. A descriptor
// keeps the attributes a font is chosen by (name, size, text style, weight,
// symbolic traits, design); creating a font from one gives the UIFont they
// name, which Perry draws with its system font or a font of that name.

enum CoreTextTypeIDs {
    static let font: UInt = 0x50_01
    static let fontDescriptor: UInt = 0x50_02
    static let glyphInfo: UInt = 0x50_03
}

/// CoreText's attribute and trait keys, as its constants give them.
enum CoreTextKeys {
    static let name = "NSFontNameAttribute"
    static let family = "NSFontFamilyAttribute"
    static let size = "NSFontSizeAttribute"
    static let traits = "NSCTFontTraitsAttribute"
    static let textStyle = "NSCTFontUIUsageAttribute"
    static let weight = "NSCTFontWeightTrait"
    static let symbolic = "NSCTFontSymbolicTrait"
    static let design = "NSCTFontUIFontDesignTrait"
}

/// kCTFontTraitItalic, kCTFontTraitBold and kCTFontTraitMonoSpace.
let italicTrait: UInt32 = 1 << 0
let boldTrait: UInt32 = 1 << 1
let monoSpaceTrait: UInt32 = 1 << 10

final class FontDescriptorState: ObjectState {
    var name: String?
    var family: String?
    var size: CGFloat = 0
    var textStyle: String?
    var weight: CGFloat = 0
    var symbolicTraits: UInt32 = 0
    var design: String?

    func copy(from other: FontDescriptorState) {
        (name, family, size, textStyle) = (other.name, other.family, other.size, other.textStyle)
        (weight, symbolicTraits, design) = (other.weight, other.symbolicTraits, other.design)
    }

    /// The attributes a dictionary gives, over those already set.
    func apply(_ attributes: UnsafeMutableRawPointer?) {
        guard let attributes else { return }
        let dictionary = NSDictionary(objCArgument: attributes)
        if let name = dictionary.object(forKey: CoreTextKeys.name) { self.name = name.stringValue }
        if let family = dictionary.object(forKey: CoreTextKeys.family) { self.family = family.stringValue }
        if let size = dictionary.object(forKey: CoreTextKeys.size)?.as(NSNumber.self) { self.size = size.doubleValue() }
        if let style = dictionary.object(forKey: CoreTextKeys.textStyle) { textStyle = style.stringValue }
        if let traits = dictionary.object(forKey: CoreTextKeys.traits)?.as(NSDictionary.self) {
            if let weight = traits.object(forKey: CoreTextKeys.weight)?.as(NSNumber.self) { self.weight = weight.doubleValue() }
            if let symbolic = traits.object(forKey: CoreTextKeys.symbolic)?.as(NSNumber.self) {
                symbolicTraits = symbolic.unsignedIntValue()
            }
            if let design = traits.object(forKey: CoreTextKeys.design) { self.design = design.stringValue }
        }
    }

    var isSystemFont: Bool { textStyle != nil || name.map { $0.hasPrefix(".") } ?? true }

    /// The weight, with the bold trait at least semibold.
    var effectiveWeight: CGFloat { symbolicTraits & boldTrait != 0 ? Swift.max(weight, 0.3) : weight }
}

@ObjCClass("UIFontDescriptor")
open class UIFontDescriptor: NSObject {
    static let states = StateTable<FontDescriptorState>()
    var state: FontDescriptorState { UIFontDescriptor.states[objcObject] }

    /// A new descriptor, +1.
    static func make(_ configure: (FontDescriptorState) -> Void) -> UnsafeMutableRawPointer {
        let descriptor = objCClass.object.allocated().unsafeCast(to: UIFontDescriptor.self)
        configure(descriptor.state)
        return ObjCRuntime.retain(descriptor.objcObject)!
    }

    static func state(_ descriptor: UnsafeMutableRawPointer?) -> FontDescriptorState? {
        descriptor.map { UIFontDescriptor.states[$0] }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIFontDescriptor.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIFontDescriptor.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:") func initialize(coder: NSObject) -> Self { self }
    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { CoreTextTypeIDs.fontDescriptor }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("pointSize") func pointSize() -> CGFloat { state.size }
    @ObjCMethod("symbolicTraits") func symbolicTraits() -> UInt32 { state.symbolicTraits }

    /// A copy with these symbolic traits instead of its own.
    @ObjCMethod("fontDescriptorWithSymbolicTraits:")
    func withSymbolicTraits(_ traits: UInt32) -> UnsafeMutableRawPointer? {
        let original = state
        return ObjCRuntime.autorelease(UIFontDescriptor.make { copy in
            copy.copy(from: original)
            copy.symbolicTraits = traits
        })
    }
    @ObjCMethod("postscriptName") func postscriptName() -> String { state.name ?? ".SFUI-Regular" }
}

/// Text styles' sizes by content size category, scaled from the Large
/// category's as UIKit's are.
func textStyleSize(_ style: String, category: String?) -> CGFloat {
    let base = UIFont.textStyleSizes[style] ?? 17
    let steps: [String: CGFloat] = [
        "UICTContentSizeCategoryXS": -3, "UICTContentSizeCategoryS": -2, "UICTContentSizeCategoryM": -1,
        "UICTContentSizeCategoryL": 0, "UICTContentSizeCategoryXL": 2, "UICTContentSizeCategoryXXL": 4,
        "UICTContentSizeCategoryXXXL": 6, "UICTContentSizeCategoryAccessibilityM": 11,
        "UICTContentSizeCategoryAccessibilityL": 16, "UICTContentSizeCategoryAccessibilityXL": 23,
        "UICTContentSizeCategoryAccessibilityXXL": 30, "UICTContentSizeCategoryAccessibilityXXXL": 36,
    ]
    return Swift.max(base + (category.flatMap { steps[$0] } ?? 0), 9)
}

private func string(_ object: UnsafeMutableRawPointer?) -> String? {
    object.map { String(objCArgument: $0) }
}

private func font(_ object: UnsafeMutableRawPointer?) -> UIFont? {
    object.flatMap { NSObject(objCArgument: $0).as(UIFont.self) }
}

// MARK: Descriptors

@c(_CTFontDescriptorGetTypeID)
public func CTFontDescriptorGetTypeID() -> UInt { CoreTextTypeIDs.fontDescriptor }

@c(_CTFontGetTypeID)
public func CTFontGetTypeID() -> UInt { CoreTextTypeIDs.font }

@c(_CTGlyphInfoGetTypeID)
public func CTGlyphInfoGetTypeID() -> UInt { CoreTextTypeIDs.glyphInfo }

@c(_CTFontDescriptorCreateWithNameAndSize)
public func CTFontDescriptorCreateWithNameAndSize(_ name: UnsafeMutableRawPointer?, _ size: CGFloat) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { ($0.name, $0.size) = (string(name), size) }
}

@c(_CTFontDescriptorCreateWithAttributes)
public func CTFontDescriptorCreateWithAttributes(_ attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { $0.apply(attributes) }
}

@c(_CTFontDescriptorCreateWithAttributesAndOptions)
public func CTFontDescriptorCreateWithAttributesAndOptions(_ attributes: UnsafeMutableRawPointer?, _ options: UInt) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { $0.apply(attributes) }
}

@c(_CTFontDescriptorCreateWithTextStyleAndAttributes)
public func CTFontDescriptorCreateWithTextStyleAndAttributes(
    _ style: UnsafeMutableRawPointer?, _ category: UnsafeMutableRawPointer?, _ attributes: UnsafeMutableRawPointer?
) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { state in
        let style = string(style) ?? "UICTFontTextStyleBody"
        state.textStyle = style
        state.size = textStyleSize(style, category: string(category))
        state.weight = style == "UICTFontTextStyleHeadline" ? 0.4 : 0
        state.apply(attributes)
    }
}

/// A user interface font: the system font, at the size given or 12.
@c(_CTFontDescriptorCreateForUIType)
public func CTFontDescriptorCreateForUIType(_ type: UInt32, _ size: CGFloat, _ language: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { ($0.name, $0.size) = (".SFUI-Regular", size > 0 ? size : 12) }
}

@c(_CTFontDescriptorCreateCopyWithAttributes)
public func CTFontDescriptorCreateCopyWithAttributes(_ original: UnsafeMutableRawPointer?, _ attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { state in
        UIFontDescriptor.state(original).map(state.copy(from:))
        state.apply(attributes)
    }
}

/// Font features are not drawn: the copy has the same attributes.
@c(_CTFontDescriptorCreateCopyWithFeature)
public func CTFontDescriptorCreateCopyWithFeature(_ original: UnsafeMutableRawPointer?, _ type: UnsafeMutableRawPointer?, _ selector: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { state in UIFontDescriptor.state(original).map(state.copy(from:)) }
}

@c(_CTFontDescriptorCreateCopyWithSymbolicTraits)
public func CTFontDescriptorCreateCopyWithSymbolicTraits(_ original: UnsafeMutableRawPointer?, _ value: UInt32, _ mask: UInt32) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { state in
        UIFontDescriptor.state(original).map(state.copy(from:))
        state.symbolicTraits = (state.symbolicTraits & ~mask) | (value & mask)
    }
}

/// The weight axis ('wght', 1 to 1000) sets the weight; other variations
/// are not drawn.
@c(_CTFontDescriptorCreateCopyWithVariation)
public func CTFontDescriptorCreateCopyWithVariation(_ original: UnsafeMutableRawPointer?, _ identifier: UnsafeMutableRawPointer?, _ value: CGFloat) -> UnsafeMutableRawPointer? {
    UIFontDescriptor.make { state in
        UIFontDescriptor.state(original).map(state.copy(from:))
        if identifier.flatMap({ NSObject(objCArgument: $0).as(NSNumber.self) })?.unsignedIntValue() == 0x7767_6874 {
            state.weight = (value - 400) / 500
        }
    }
}

/// An attribute, +1: name, family, size, text style, or the traits.
@c(_CTFontDescriptorCopyAttribute)
public func CTFontDescriptorCopyAttribute(_ descriptor: UnsafeMutableRawPointer?, _ key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = UIFontDescriptor.state(descriptor), let key = string(key) else { return nil }
    switch key {
    case CoreTextKeys.name: return (state.name ?? ".SFUI-Regular").objCOwnedReturnValue()
    case CoreTextKeys.family: return (state.family ?? state.name ?? ".AppleSystemUIFont").objCOwnedReturnValue()
    case CoreTextKeys.size: return ObjCRuntime.retain(NSNumber.make(double: state.size).objcObject)
    case CoreTextKeys.textStyle: return state.textStyle?.objCOwnedReturnValue()
    case CoreTextKeys.traits: return ObjCRuntime.retain(traits(state).objcObject)
    default: return nil
    }
}

private func traits(_ state: FontDescriptorState) -> NSMutableDictionary {
    let traits = NSMutableDictionary.empty()
    traits.set(NSNumber.make(double: state.weight), forKey: CoreTextKeys.weight)
    traits.set(NSNumber.make(unsignedInt: state.symbolicTraits), forKey: CoreTextKeys.symbolic)
    if let design = state.design { traits.set(NSObject(objCReturnValue: design.objCArgument()), forKey: CoreTextKeys.design) }
    return traits
}

@c(_CTFontDescriptorCopyAttributes)
public func CTFontDescriptorCopyAttributes(_ descriptor: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let attributes = NSMutableDictionary.empty()
    if let state = UIFontDescriptor.state(descriptor) {
        attributes.set(NSObject(objCReturnValue: (state.name ?? ".SFUI-Regular").objCArgument()), forKey: CoreTextKeys.name)
        if state.size > 0 { attributes.set(NSNumber.make(double: state.size), forKey: CoreTextKeys.size) }
        if let style = state.textStyle { attributes.set(NSObject(objCReturnValue: style.objCArgument()), forKey: CoreTextKeys.textStyle) }
        attributes.set(traits(state), forKey: CoreTextKeys.traits)
    }
    return ObjCRuntime.retain(attributes.objcObject)
}

@c(_CTFontDescriptorGetSymbolicTraits)
public func CTFontDescriptorGetSymbolicTraits(_ descriptor: UnsafeMutableRawPointer?) -> UInt32 {
    UIFontDescriptor.state(descriptor)?.symbolicTraits ?? 0
}

@c(_CTFontDescriptorGetWeight)
public func CTFontDescriptorGetWeight(_ descriptor: UnsafeMutableRawPointer?) -> CGFloat {
    UIFontDescriptor.state(descriptor)?.effectiveWeight ?? 0
}

@c(_CTFontDescriptorIsSystemUIFont)
public func CTFontDescriptorIsSystemUIFont(_ descriptor: UnsafeMutableRawPointer?) -> Bool {
    UIFontDescriptor.state(descriptor)?.isSystemFont ?? false
}

@c(_CTFontDescriptorGetTextStyleSize)
public func CTFontDescriptorGetTextStyleSize(
    _ style: UnsafeMutableRawPointer?, _ category: UnsafeMutableRawPointer?, _ options: Int32,
    _ weight: UnsafeMutablePointer<CGFloat>?, _ size: UnsafeMutablePointer<CGFloat>?
) -> CGFloat {
    textStyleSize(string(style) ?? "UICTFontTextStyleBody", category: string(category))
}

// MARK: Fonts

@c(_CTFontCreateWithFontDescriptor)
public func CTFontCreateWithFontDescriptor(_ descriptor: UnsafeMutableRawPointer?, _ size: CGFloat, _ matrix: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    let state = UIFontDescriptor.state(descriptor)
    let pointSize = size > 0 ? size : (state.map { $0.size > 0 ? $0.size : 12 } ?? 12)
    let name = state.flatMap { $0.isSystemFont ? nil : $0.name } ?? ".SFUI-Regular"
    let font = UIFont.make(name: name, size: pointSize, weight: state?.effectiveWeight ?? 0,
                           traits: state?.symbolicTraits ?? 0, design: state?.design)
    return ObjCRuntime.retain(font.objcObject)
}

@c(_CTFontCopyFontDescriptor)
public func CTFontCopyFontDescriptor(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let font = font(object) else { return nil }
    return UIFontDescriptor.make { state in
        (state.name, state.size, state.weight) = (font.state.name, font.state.pointSize, font.state.weight)
        (state.symbolicTraits, state.design) = (font.state.traits, font.state.design)
        if font.state.weight >= 0.3 { state.symbolicTraits |= boldTrait }
    }
}

@c(_CTFontGetSize) public func CTFontGetSize(_ object: UnsafeMutableRawPointer?) -> CGFloat { font(object)?.pointSize() ?? 0 }
@c(_CTFontGetAscent) public func CTFontGetAscent(_ object: UnsafeMutableRawPointer?) -> CGFloat { font(object)?.ascender() ?? 0 }
/// Positive, unlike UIFont's descender.
@c(_CTFontGetDescent) public func CTFontGetDescent(_ object: UnsafeMutableRawPointer?) -> CGFloat { -(font(object)?.descender() ?? 0) }
@c(_CTFontGetLeading) public func CTFontGetLeading(_ object: UnsafeMutableRawPointer?) -> CGFloat { font(object)?.leading() ?? 0 }
@c(_CTFontGetCapHeight) public func CTFontGetCapHeight(_ object: UnsafeMutableRawPointer?) -> CGFloat { font(object)?.capHeight() ?? 0 }
@c(_CTFontGetWeight) public func CTFontGetWeight(_ object: UnsafeMutableRawPointer?) -> CGFloat { font(object)?.state.weight ?? 0 }

@c(_CTFontGetSymbolicTraits)
public func CTFontGetSymbolicTraits(_ object: UnsafeMutableRawPointer?) -> UInt32 {
    guard let font = font(object) else { return 0 }
    return font.state.traits | (font.state.weight >= 0.3 ? boldTrait : 0) | (font.isMonospaced ? monoSpaceTrait : 0)
}

@c(_CTFontIsSystemUIFont)
public func CTFontIsSystemUIFont(_ object: UnsafeMutableRawPointer?) -> Bool {
    font(object)?.state.name.hasPrefix(".") ?? false
}

/// Bold Text's weight for a weight: a step heavier, as UIKit's.
@c(_CTFontGetAccessibilityBoldWeightOfWeight)
public func CTFontGetAccessibilityBoldWeightOfWeight(_ weight: CGFloat) -> CGFloat { Swift.min(weight + 0.2, 0.62) }

@c(_CTFontGetClippingMetrics)
public func CTFontGetClippingMetrics(_ object: UnsafeMutableRawPointer?, _ ascent: UnsafeMutablePointer<CGFloat>?, _ descent: UnsafeMutablePointer<CGFloat>?) {
    ascent?.pointee = CTFontGetAscent(object)
    descent?.pointee = CTFontGetDescent(object)
}

/// No script needs room beyond the line: there are no outsets.
@c(_CTFontGetLanguageAwareOutsets)
public func CTFontGetLanguageAwareOutsets(
    _ object: UnsafeMutableRawPointer?, _ left: UnsafeMutablePointer<CGFloat>?, _ top: UnsafeMutablePointer<CGFloat>?,
    _ right: UnsafeMutablePointer<CGFloat>?, _ bottom: UnsafeMutablePointer<CGFloat>?
) -> Bool {
    for side in [left, top, right, bottom] { side?.pointee = 0 }
    return false
}

@c(_CTFontCopySystemUIFontExcessiveLineHeightCharacterSet)
public func CTFontCopySystemUIFontExcessiveLineHeightCharacterSet() -> UnsafeMutableRawPointer? { nil }

@c(_CTFontCopyTallestTextStyleLanguageForString)
public func CTFontCopyTallestTextStyleLanguageForString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }

/// The default composition language for every language.
@c(_CTParagraphStyleGetCompositionLanguageForLanguage)
public func CTParagraphStyleGetCompositionLanguageForLanguage(_ language: UnsafeMutableRawPointer?) -> UInt8 { 0 }

// MARK: - Registering fonts

/// A graphics font is available from when CoreGraphics makes it, which
/// adds its file to the fonts text is drawn with: registering it succeeds.
@c(_CTFontManagerRegisterGraphicsFont)
public func CTFontManagerRegisterGraphicsFont(_ font: UnsafeMutableRawPointer?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    error?.pointee = nil
    guard let font else { return false }
    return CG.fontRegister?(font) ?? true
}

@c(_CTFontManagerUnregisterGraphicsFont)
public func CTFontManagerUnregisterGraphicsFont(_ font: UnsafeMutableRawPointer?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    error?.pointee = nil
    return font != nil
}

/// Registers the font in the file at the URL, by making a graphics font of
/// it.
@c(_CTFontManagerRegisterFontsForURL)
public func CTFontManagerRegisterFontsForURL(_ url: UnsafeMutableRawPointer?, _ scope: UInt32, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    error?.pointee = nil
    guard let url, let provider = CG.dataProviderCreateWithURL(url) else { return false }
    defer { CG.dataProviderRelease(provider) }
    guard let font = CG.fontCreateWithDataProvider(provider) else { return false }
    CG.fontRelease(font)
    return true
}

@c(_CTFontManagerUnregisterFontsForURL)
public func CTFontManagerUnregisterFontsForURL(_ url: UnsafeMutableRawPointer?, _ scope: UInt32, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    error?.pointee = nil
    return url != nil
}
