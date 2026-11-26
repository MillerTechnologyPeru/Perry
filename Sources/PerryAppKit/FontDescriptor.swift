import CPerryGeometry
import PerryObjCInterop

// NSFontDescriptor: a font described by attributes (name, family, face,
// size, symbolic traits). Matching looks at no font list: a descriptor
// matches itself, and the font made from it is NSFont's for its name, size
// and traits. NSFontPanel, the shared font panel, which keeps the font it
// is given and isn't shown. And NSImageSymbolConfiguration, which keeps a
// symbol image's point size, weight, scale and colors.

/// NSFontFaceAttribute's value: the face ("Bold", "Italic") in its family.
private let fontFaceAttribute = "NSFontFaceAttribute"

@ObjCClass("NSFontDescriptor")
open class NSFontDescriptor: NSObject {
    /// The attributes: an NSDictionary, nil for none.
    var attributes: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithFontAttributes:")
    public required init(fontAttributes: NSObject?) {
        super.init()
        attributes = fontAttributes.flatMap { Send.object($0.objcObject, "copy") }.map { NSObject(objcObject: $0, ownership: .adopt) }
    }

    /// A descriptor's archive: its attributes ("NSAttributes"), as AppKit's.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        attributes = Coder(coder: coder).object("NSAttributes")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        Encoder(coder: coder).object(attributes, "NSAttributes")
    }

    @ObjCClassMethod("fontDescriptorWithFontAttributes:")
    static func descriptor(_ cls: ObjCClass, fontAttributes: NSObject?) -> NSObject? { make(cls, fontAttributes) }

    @ObjCClassMethod("fontDescriptorWithName:size:")
    static func descriptor(_ cls: ObjCClass, name: String?, size: CGFloat) -> NSObject? {
        let attributes = NSMutableDictionary.empty()
        if let name { attributes.set(text(name), forKey: Constants.NSFontNameAttribute) }
        attributes.set(NSNumber.make(double: Double(size)), forKey: Constants.NSFontSizeAttribute)
        return make(cls, attributes)
    }

    /// An instance of `cls` with these attributes.
    private static func make(_ cls: ObjCClass, _ attributes: NSObject?) -> NSObject? {
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let made = unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(Send.object(cls.pointer, "alloc"), ObjCRuntime.selector("initWithFontAttributes:"),
                                                                    attributes?.objcObject)
        return made.map { NSObject(objcObject: $0, ownership: .adopt) }
    }

    private static func text(_ string: String) -> NSObject { NSObject(objCReturnValue: string.objCReturnValue()) }

    /// A descriptor of this one's class with `changes` added to the
    /// attributes.
    func adding(_ changes: [String: NSObject]) -> NSObject? {
        let merged = attributes.flatMap { Send.object($0.objcObject, "mutableCopy") }.map { NSObject(objcObject: $0, ownership: .adopt) }
            .flatMap { $0.as(NSMutableDictionary.self) } ?? NSMutableDictionary.empty()
        for (key, value) in changes { merged.set(value, forKey: key) }
        return NSFontDescriptor.make(ObjCClass(ObjCRuntime.objectClass(objcObject)!), merged)
    }

    func value(_ key: String) -> NSObject? { attributes?.as(NSDictionary.self)?.object(forKey: key) }

    @ObjCMethod("fontAttributes") func fontAttributes() -> NSObject { attributes ?? NSMutableDictionary.empty() }
    @ObjCMethod("objectForKey:") func object(forKey key: String?) -> NSObject? { key.flatMap(value) }
    @ObjCMethod("postscriptName") func postscriptName() -> String? { value(Constants.NSFontNameAttribute)?.stringValue }
    @ObjCMethod("pointSize") func pointSize() -> CGFloat { CGFloat(value(Constants.NSFontSizeAttribute)?.as(NSNumber.self)?.doubleValue() ?? 0) }

    /// NSFontDescriptorSymbolicTraits: the traits attribute's, or what the
    /// name says (italic 1 << 0, bold 1 << 1).
    @ObjCMethod("symbolicTraits")
    func symbolicTraits() -> UInt32 {
        if let traits = value(Constants.NSFontTraitsAttribute)?.as(NSDictionary.self)?.object(forKey: Constants.NSFontSymbolicTrait) {
            return UInt32(truncatingIfNeeded: Send.integer(traits.objcObject, "unsignedIntValue"))
        }
        let name = (postscriptName() ?? value(fontFaceAttribute)?.stringValue ?? "").lowercased()
        return (name.contains("italic") || name.contains("oblique") ? 1 : 0) | (name.contains("bold") ? 2 : 0)
    }

    @ObjCMethod("fontDescriptorWithSize:")
    func withSize(_ size: CGFloat) -> NSObject? { adding([Constants.NSFontSizeAttribute: NSNumber.make(double: Double(size))]) }

    @ObjCMethod("fontDescriptorWithSymbolicTraits:")
    func withSymbolicTraits(_ traits: UInt32) -> NSObject? {
        let dictionary = NSMutableDictionary.empty()
        dictionary.set(NSNumber.make(unsignedInt: traits), forKey: Constants.NSFontSymbolicTrait)
        return adding([Constants.NSFontTraitsAttribute: dictionary])
    }

    @ObjCMethod("fontDescriptorWithFamily:")
    func withFamily(_ family: String?) -> NSObject? { adding(family.map { [Constants.NSFontFamilyAttribute: NSFontDescriptor.text($0)] } ?? [:]) }
    @ObjCMethod("fontDescriptorWithFace:")
    func withFace(_ face: String?) -> NSObject? { adding(face.map { [fontFaceAttribute: NSFontDescriptor.text($0)] } ?? [:]) }

    @ObjCMethod("fontDescriptorByAddingAttributes:")
    func addingAttributes(_ added: NSObject?) -> NSObject? {
        guard let added = added?.as(NSDictionary.self), let keys = Send.object(added.objcObject, "allKeys") else { return adding([:]) }
        var changes: [String: NSObject] = [:]
        for key in NSObject(keys).as(NSArray.self)?.elements ?? [] { changes[key.stringValue] = added.object(forKey: key.stringValue) }
        return adding(changes)
    }

    /// The fonts that match: this one, as there is no font list to search.
    @ObjCMethod("matchingFontDescriptorsWithMandatoryKeys:")
    func matchingFontDescriptors(withMandatoryKeys keys: NSObject?) -> NSObject { NSMutableArray.of([self]) }
    @ObjCMethod("matchingFontDescriptorWithMandatoryKeys:")
    func matchingFontDescriptor(withMandatoryKeys keys: NSObject?) -> NSObject? { self }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(NSFontDescriptor.self) else { return false }
        return Send.bool(fontAttributes().objcObject, "isEqualToDictionary:", other.fontAttributes().objcObject)
    }
    @ObjCMethod("hash") func descriptorHash() -> UInt { UInt(bitPattern: (postscriptName() ?? "").hashValue) }

    /// The font: its name (the family's when it has none, the system
    /// font's when neither), `size` or else its own, and its traits.
    func font(size: CGFloat) -> NSFont {
        let size = size > 0 ? size : pointSize() > 0 ? pointSize() : 13
        let traits = symbolicTraits()
        guard let name = postscriptName() ?? value(Constants.NSFontFamilyAttribute)?.stringValue else {
            return NSFont.system(size: size, weight: traits & 2 != 0 ? 0.4 : 0)
        }
        let font = NSFont(name: name, size: size)
        font.bold = font.bold || traits & 2 != 0
        font.italic = font.italic || traits & 1 != 0
        return font
    }

    /// A font's descriptor: its name and size.
    static func describing(_ font: NSFont) -> NSObject? { descriptor(NSFontDescriptor.objCClass, name: font.name, size: font.size) }
}

@ObjCClass("NSFontPanel")
open class NSFontPanel: NSPanel {
    nonisolated(unsafe) private static var shared: NSFontPanel?

    var panelFont: NSFont?
    var multiple = false
    var accessoryView: NSView?
    var worksWhenModal = false
    var enabled = true

    @ObjCClassMethod("sharedFontPanel")
    static func sharedFontPanel() -> NSFontPanel {
        if let shared { return shared }
        let panel = NSFontPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: 0xb, backing: 2, defer: true)
        shared = panel
        return panel
    }
    @ObjCClassMethod("sharedFontPanelExists") static func sharedFontPanelExists() -> Bool { shared != nil }

    @ObjCMethod("setPanelFont:isMultiple:")
    func setPanelFont(_ font: NSFont?, isMultiple: Bool) {
        panelFont = font
        multiple = isMultiple
    }
    /// The font as it is: nothing is chosen in a panel that isn't shown.
    @ObjCMethod("panelConvertFont:") func panelConvertFont(_ font: NSFont?) -> NSFont? { font }
    @ObjCMethod("accessoryView") func panelAccessoryView() -> NSView? { accessoryView }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ value: NSView?) { accessoryView = value }
    @ObjCMethod("worksWhenModal") func panelWorksWhenModal() -> Bool { worksWhenModal }
    @ObjCMethod("setWorksWhenModal:") override func setWorksWhenModal(_ value: Bool) { worksWhenModal = value }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ value: Bool) { enabled = value }
    @ObjCMethod("reloadDefaultFontFamilies") func reloadDefaultFontFamilies() {}

    /// There are no font panel controls to show: it stays hidden, as an
    /// empty window would be no help.
    @ObjCMethod("orderFront:")
    override func orderFront(_ sender: NSObject?) {
        appKitWarning("NSFontPanel: no font panel here; not shown")
    }
}

@ObjCClass("NSImageSymbolConfiguration")
open class NSImageSymbolConfiguration: NSObject {
    /// 0 for each that isn't set.
    var pointSize: CGFloat = 0
    var weight: CGFloat = 0
    var weightSet = false
    /// NSImageSymbolScale: small 1, medium 2, large 3.
    var scale = 0
    var textStyle: String?
    var hierarchicalColor: NSObject?
    var paletteColors: NSObject?
    /// Which rendering it prefers: monochrome, hierarchical, multicolor.
    var preference: String?
    var variableValueMode = 0
    var colorRenderingMode = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    /// A configuration of `cls`, set up by `configure`.
    private static func make(_ cls: ObjCClass, _ configure: (NSImageSymbolConfiguration) -> Void) -> NSObject? {
        guard let made = Send.object(cls.pointer, "new") else { return nil }
        let object = NSObject(objcObject: made, ownership: .adopt)
        if let configuration = object.as(NSImageSymbolConfiguration.self) { configure(configuration) }
        return object
    }

    @ObjCClassMethod("configurationWithPointSize:weight:scale:")
    static func configuration(_ cls: ObjCClass, pointSize: CGFloat, weight: CGFloat, scale: Int) -> NSObject? {
        make(cls) { ($0.pointSize, $0.weight, $0.weightSet, $0.scale) = (pointSize, weight, true, scale) }
    }
    @ObjCClassMethod("configurationWithPointSize:weight:")
    static func configuration(_ cls: ObjCClass, pointSize: CGFloat, weight: CGFloat) -> NSObject? {
        make(cls) { ($0.pointSize, $0.weight, $0.weightSet) = (pointSize, weight, true) }
    }
    @ObjCClassMethod("configurationWithTextStyle:scale:")
    static func configuration(_ cls: ObjCClass, textStyle: String?, scale: Int) -> NSObject? {
        make(cls) { ($0.textStyle, $0.scale) = (textStyle, scale) }
    }
    @ObjCClassMethod("configurationWithTextStyle:")
    static func configuration(_ cls: ObjCClass, textStyle: String?) -> NSObject? { make(cls) { $0.textStyle = textStyle } }
    @ObjCClassMethod("configurationWithScale:")
    static func configuration(_ cls: ObjCClass, scale: Int) -> NSObject? { make(cls) { $0.scale = scale } }
    @ObjCClassMethod("configurationPreferringMonochrome")
    static func preferringMonochrome(_ cls: ObjCClass) -> NSObject? { make(cls) { $0.preference = "monochrome" } }
    @ObjCClassMethod("configurationPreferringHierarchical")
    static func preferringHierarchical(_ cls: ObjCClass) -> NSObject? { make(cls) { $0.preference = "hierarchical" } }
    @ObjCClassMethod("configurationPreferringMulticolor")
    static func preferringMulticolor(_ cls: ObjCClass) -> NSObject? { make(cls) { $0.preference = "multicolor" } }
    @ObjCClassMethod("configurationWithHierarchicalColor:")
    static func configuration(_ cls: ObjCClass, hierarchicalColor: NSObject?) -> NSObject? {
        make(cls) { $0.hierarchicalColor = hierarchicalColor }
    }
    @ObjCClassMethod("configurationWithPaletteColors:")
    static func configuration(_ cls: ObjCClass, paletteColors: NSObject?) -> NSObject? { make(cls) { $0.paletteColors = paletteColors } }
    @ObjCClassMethod("configurationWithVariableValueMode:")
    static func configuration(_ cls: ObjCClass, variableValueMode: Int) -> NSObject? { make(cls) { $0.variableValueMode = variableValueMode } }
    @ObjCClassMethod("configurationWithColorRenderingMode:")
    static func configuration(_ cls: ObjCClass, colorRenderingMode: Int) -> NSObject? { make(cls) { $0.colorRenderingMode = colorRenderingMode } }

    /// This one with what `other` sets laid over it.
    @ObjCMethod("configurationByApplyingConfiguration:")
    func applying(_ other: NSObject?) -> NSObject? {
        guard let other = other?.as(NSImageSymbolConfiguration.self) else { return self }
        return NSImageSymbolConfiguration.make(ObjCClass(ObjCRuntime.objectClass(objcObject)!)) { made in
            made.pointSize = other.pointSize != 0 ? other.pointSize : pointSize
            (made.weight, made.weightSet) = other.weightSet ? (other.weight, true) : (weight, weightSet)
            made.scale = other.scale != 0 ? other.scale : scale
            made.textStyle = other.textStyle ?? textStyle
            made.hierarchicalColor = other.hierarchicalColor ?? hierarchicalColor
            made.paletteColors = other.paletteColors ?? paletteColors
            made.preference = other.preference ?? preference
            made.variableValueMode = other.variableValueMode != 0 ? other.variableValueMode : variableValueMode
            made.colorRenderingMode = other.colorRenderingMode != 0 ? other.colorRenderingMode : colorRenderingMode
        }
    }

    /// Configurations don't change once made.
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}
