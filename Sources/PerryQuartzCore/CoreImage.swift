import CPerryGeometry
import Glibc
import PerryObjCInterop

// Core Image: images that are recipes, filters that make new ones, and
// contexts that render them into bitmaps or CoreGraphics contexts. Mac OS X
// 10.4 to 10.10 keep its classes in QuartzCore and iOS in CoreImage; this
// provider answers both, for Mac and iOS apps alike. The rendering is
// CoreImagePixels.swift's, on the CPU; the filters are CIFilter.swift's.

@ObjCConstants
enum CoreImageKeys {
    // Filters' inputs and output.
    static let kCIInputImageKey = "inputImage"
    static let kCIOutputImageKey = "outputImage"
    static let kCIInputBackgroundImageKey = "inputBackgroundImage"
    static let kCIInputTargetImageKey = "inputTargetImage"
    static let kCIInputMaskImageKey = "inputMaskImage"
    static let kCIInputTimeKey = "inputTime"
    static let kCIInputTransformKey = "inputTransform"
    static let kCIInputScaleKey = "inputScale"
    static let kCIInputAspectRatioKey = "inputAspectRatio"
    static let kCIInputCenterKey = "inputCenter"
    static let kCIInputRadiusKey = "inputRadius"
    static let kCIInputAngleKey = "inputAngle"
    static let kCIInputWidthKey = "inputWidth"
    static let kCIInputSharpnessKey = "inputSharpness"
    static let kCIInputIntensityKey = "inputIntensity"
    static let kCIInputEVKey = "inputEV"
    static let kCIInputSaturationKey = "inputSaturation"
    static let kCIInputColorKey = "inputColor"
    static let kCIInputBrightnessKey = "inputBrightness"
    static let kCIInputContrastKey = "inputContrast"
    static let kCIInputExtentKey = "inputExtent"

    // Filters' attributes.
    static let kCIAttributeFilterName = "CIAttributeFilterName"
    static let kCIAttributeFilterDisplayName = "CIAttributeFilterDisplayName"
    static let kCIAttributeDescription = "CIAttributeDescription"
    static let kCIAttributeReferenceDocumentation = "CIAttributeReferenceDocumentation"
    static let kCIAttributeFilterCategories = "CIAttributeFilterCategories"
    static let kCIAttributeClass = "CIAttributeClass"
    static let kCIAttributeType = "CIAttributeType"
    static let kCIAttributeMin = "CIAttributeMin"
    static let kCIAttributeMax = "CIAttributeMax"
    static let kCIAttributeSliderMin = "CIAttributeSliderMin"
    static let kCIAttributeSliderMax = "CIAttributeSliderMax"
    static let kCIAttributeDefault = "CIAttributeDefault"
    static let kCIAttributeIdentity = "CIAttributeIdentity"
    static let kCIAttributeName = "CIAttributeName"
    static let kCIAttributeDisplayName = "CIAttributeDisplayName"
    static let kCIUIParameterSet = "CIUIParameterSet"
    static let kCIUISetBasic = "CIUISetBasic"
    static let kCIUISetIntermediate = "CIUISetIntermediate"
    static let kCIUISetAdvanced = "CIUISetAdvanced"
    static let kCIUISetDevelopment = "CIUISetDevelopment"

    static let kCIAttributeTypeTime = "CIAttributeTypeTime"
    static let kCIAttributeTypeScalar = "CIAttributeTypeScalar"
    static let kCIAttributeTypeDistance = "CIAttributeTypeDistance"
    static let kCIAttributeTypeAngle = "CIAttributeTypeAngle"
    static let kCIAttributeTypeBoolean = "CIAttributeTypeBoolean"
    static let kCIAttributeTypeInteger = "CIAttributeTypeInteger"
    static let kCIAttributeTypeCount = "CIAttributeTypeCount"
    static let kCIAttributeTypePosition = "CIAttributeTypePosition"
    static let kCIAttributeTypeOffset = "CIAttributeTypeOffset"
    static let kCIAttributeTypePosition3 = "CIAttributeTypePosition3"
    static let kCIAttributeTypeRectangle = "CIAttributeTypeRectangle"
    static let kCIAttributeTypeOpaqueColor = "CIAttributeTypeOpaqueColor"
    static let kCIAttributeTypeColor = "CIAttributeTypeColor"
    static let kCIAttributeTypeGradient = "CIAttributeTypeGradient"
    static let kCIAttributeTypeImage = "CIAttributeTypeImage"
    static let kCIAttributeTypeTransform = "CIAttributeTypeTransform"

    // Filters' categories.
    static let kCICategoryDistortionEffect = "CICategoryDistortionEffect"
    static let kCICategoryGeometryAdjustment = "CICategoryGeometryAdjustment"
    static let kCICategoryCompositeOperation = "CICategoryCompositeOperation"
    static let kCICategoryHalftoneEffect = "CICategoryHalftoneEffect"
    static let kCICategoryColorAdjustment = "CICategoryColorAdjustment"
    static let kCICategoryColorEffect = "CICategoryColorEffect"
    static let kCICategoryTransition = "CICategoryTransition"
    static let kCICategoryTileEffect = "CICategoryTileEffect"
    static let kCICategoryGenerator = "CICategoryGenerator"
    static let kCICategoryReduction = "CICategoryReduction"
    static let kCICategoryGradient = "CICategoryGradient"
    static let kCICategoryStylize = "CICategoryStylize"
    static let kCICategorySharpen = "CICategorySharpen"
    static let kCICategoryBlur = "CICategoryBlur"
    static let kCICategoryVideo = "CICategoryVideo"
    static let kCICategoryStillImage = "CICategoryStillImage"
    static let kCICategoryInterlaced = "CICategoryInterlaced"
    static let kCICategoryNonSquarePixels = "CICategoryNonSquarePixels"
    static let kCICategoryHighDynamicRange = "CICategoryHighDynamicRange"
    static let kCICategoryBuiltIn = "CICategoryBuiltIn"
    static let kCICategoryFilterGenerator = "CIFilterGenerator"
    static let kCIApplyOptionExtent = "extent"
    static let kCIApplyOptionDefinition = "definition"
    static let kCIApplyOptionUserInfo = "user_info"
    static let kCIApplyOptionColorSpace = "color_space"

    // Contexts' and images' options.
    static let kCIContextOutputColorSpace = "output_color_space"
    static let kCIContextWorkingColorSpace = "working_color_space"
    static let kCIContextWorkingFormat = "working_format"
    static let kCIContextUseSoftwareRenderer = "software_renderer"
    static let kCIContextCacheIntermediates = "kCIContextCacheIntermediates"
    static let kCIContextPriorityRequestLow = "priority_request_low"
    static let kCIImageColorSpace = "CIImageColorSpace"
    static let kCIImageProperties = "CIImageProperties"
    static let kCIImageProviderTileSize = "tile_size"
    static let kCIImageProviderUserInfo = "user_info"
    static let kCISamplerAffineMatrix = "affine_matrix"
    static let kCISamplerWrapMode = "wrap_mode"
    static let kCISamplerFilterMode = "filter_mode"
    static let kCISamplerWrapBlack = "black"
    static let kCISamplerWrapClamp = "clamp"
    static let kCISamplerFilterNearest = "nearest"
    static let kCISamplerFilterLinear = "linear"

    // Pixel formats: CIFormat, an int.
    static let kCIFormatARGB8: Int64 = 23
    static let kCIFormatBGRA8: Int64 = 24
    static let kCIFormatRGBA8: Int64 = 25
    static let kCIFormatRGBA16: Int64 = 27
    static let kCIFormatRGBAh: Int64 = 31
    static let kCIFormatRGBAf: Int64 = 34
}

/// The byte each of red, green, blue and alpha takes in an 8-bit format's
/// pixel; nil for a format Perry doesn't read or write.
func byteOrder(of format: Int32) -> (Int, Int, Int, Int)? {
    switch Int64(format) {
    case CoreImageKeys.kCIFormatARGB8: return (1, 2, 3, 0)
    case CoreImageKeys.kCIFormatBGRA8: return (2, 1, 0, 3)
    case CoreImageKeys.kCIFormatRGBA8: return (0, 1, 2, 3)
    default: return nil
    }
}

// MARK: - Foundation, as Core Image calls it

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: String) -> NSObject?
    @ObjCMethod("allKeys") func allKeys() -> NSArray
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> NSMutableDictionary
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: String)
}

extension String {
    /// The string as an NSString.
    var objectValue: NSObject { NSObject(objCOwned: objCOwnedReturnValue()) }
}

extension NSObject {
    @ObjCMethod("transformStruct") func sendTransformStruct() -> CGAffineTransform
}

/// Objective-C messages Core Image sends to objects it doesn't define.
enum CoreImageMessages {
    typealias Object = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias ObjectWith = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Length = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UInt

    static func object(_ receiver: UnsafeMutableRawPointer?, _ selector: String) -> UnsafeMutableRawPointer? {
        guard let receiver else { return nil }
        return unsafeBitCast(ObjCRuntime.msgSend, to: Object.self)(receiver, ObjCRuntime.selector(selector))
    }

    static func object(_ receiver: UnsafeMutableRawPointer?, _ selector: String, _ argument: UnsafeMutableRawPointer?)
        -> UnsafeMutableRawPointer? {
        guard let receiver else { return nil }
        return unsafeBitCast(ObjCRuntime.msgSend, to: ObjectWith.self)(receiver, ObjCRuntime.selector(selector), argument)
    }

    /// An NSData's bytes while `body` runs.
    static func withBytes<T>(of data: UnsafeMutableRawPointer?, _ body: (UnsafeRawPointer, Int) -> T?) -> T? {
        guard let data, let bytes = object(data, "bytes") else { return nil }
        let length = unsafeBitCast(ObjCRuntime.msgSend, to: Length.self)(data, ObjCRuntime.selector("length"))
        return body(UnsafeRawPointer(bytes), Int(length))
    }

    /// The CGImage an object gives (a UIImage, an NSBitmapImageRep), +0.
    static func cgImage(of object: NSObject?) -> CGRef? {
        guard let object, object.responds(to: "CGImage") else { return nil }
        return self.object(object.objcObject, "CGImage")
    }

    /// The CoreGraphics context AppKit is drawing in.
    static var currentAppKitContext: CGRef? {
        object(object(ObjCRuntime.classObject("NSGraphicsContext"), "currentContext"), "graphicsPort")
    }
}

// MARK: - CIColor

final class CIColorState {
    var components: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
    /// -components' storage, made when asked for.
    var storage: UnsafeMutablePointer<CGFloat>?

    deinit { storage?.deallocate() }

    /// Premultiplied, for pixels.
    var premultiplied: RGBA {
        let (r, g, b, a) = components
        return RGBA(Float(r * a), Float(g * a), Float(b * a), Float(a))
    }

    var straight: RGBA { RGBA(Float(components.0), Float(components.1), Float(components.2), Float(components.3)) }
}

@ObjCClass("CIColor")
open class CIColor: NSObject {
    static let states = ObjectStates { CIColorState() }
    var color: CIColorState { CIColor.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIColor.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIColor.objCClass.pointer)
    }

    static func make(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat, cls: ObjCClass = CIColor.objCClass) -> CIColor {
        let made = cls.object.allocated().initialized().unsafeCast(to: CIColor.self)
        made.color.components = (r, g, b, a)
        return made
    }

    /// A CGColor's components: gray and alpha, or red, green, blue and alpha.
    static func components(of cgColor: CGRef?) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard let cgColor, let values = CG.colorGetComponents(cgColor) else { return (0, 0, 0, 1) }
        switch CG.colorGetNumberOfComponents(cgColor) {
        case 2: return (values[0], values[0], values[0], values[1])
        case 4...: return (values[0], values[1], values[2], values[3])
        case 3: return (values[0], values[1], values[2], 1)
        default: return (0, 0, 0, 1)
        }
    }

    /// "r g b a", as -stringRepresentation gives it.
    static func parse(_ text: String) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let values = CIVector.numbers(in: text)
        switch values.count {
        case 0: return (0, 0, 0, 1)
        case 1, 2: return (values[0], values[0], values[0], values.count == 2 ? values[1] : 1)
        case 3: return (values[0], values[1], values[2], 1)
        default: return (values[0], values[1], values[2], values[3])
        }
    }

    @ObjCClassMethod("colorWithRed:green:blue:alpha:")
    static func color(_ cls: ObjCClass, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> CIColor {
        make(red, green, blue, alpha, cls: cls)
    }

    @ObjCClassMethod("colorWithRed:green:blue:")
    static func color(_ cls: ObjCClass, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIColor { make(red, green, blue, 1, cls: cls) }

    @ObjCClassMethod("colorWithCGColor:")
    static func color(_ cls: ObjCClass, cgColor: CGRef?) -> CIColor {
        let (r, g, b, a) = components(of: cgColor)
        return make(r, g, b, a, cls: cls)
    }

    @ObjCClassMethod("colorWithString:")
    static func color(_ cls: ObjCClass, string: String?) -> CIColor {
        let (r, g, b, a) = parse(string ?? "")
        return make(r, g, b, a, cls: cls)
    }

    @ObjCClassMethod("blackColor") static func black(_ cls: ObjCClass) -> CIColor { make(0, 0, 0, 1, cls: cls) }
    @ObjCClassMethod("whiteColor") static func white(_ cls: ObjCClass) -> CIColor { make(1, 1, 1, 1, cls: cls) }
    @ObjCClassMethod("grayColor") static func gray(_ cls: ObjCClass) -> CIColor { make(0.5, 0.5, 0.5, 1, cls: cls) }
    @ObjCClassMethod("redColor") static func red(_ cls: ObjCClass) -> CIColor { make(1, 0, 0, 1, cls: cls) }
    @ObjCClassMethod("greenColor") static func green(_ cls: ObjCClass) -> CIColor { make(0, 1, 0, 1, cls: cls) }
    @ObjCClassMethod("blueColor") static func blue(_ cls: ObjCClass) -> CIColor { make(0, 0, 1, 1, cls: cls) }
    @ObjCClassMethod("cyanColor") static func cyan(_ cls: ObjCClass) -> CIColor { make(0, 1, 1, 1, cls: cls) }
    @ObjCClassMethod("magentaColor") static func magenta(_ cls: ObjCClass) -> CIColor { make(1, 0, 1, 1, cls: cls) }
    @ObjCClassMethod("yellowColor") static func yellow(_ cls: ObjCClass) -> CIColor { make(1, 1, 0, 1, cls: cls) }
    @ObjCClassMethod("clearColor") static func clear(_ cls: ObjCClass) -> CIColor { make(0, 0, 0, 0, cls: cls) }

    @ObjCMethod("initWithRed:green:blue:alpha:")
    func initialize(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> Self {
        color.components = (red, green, blue, alpha)
        return self
    }

    @ObjCMethod("initWithRed:green:blue:")
    func initialize(red: CGFloat, green: CGFloat, blue: CGFloat) -> Self { initialize(red: red, green: green, blue: blue, alpha: 1) }

    @ObjCMethod("initWithCGColor:")
    func initialize(cgColor: CGRef?) -> Self {
        color.components = CIColor.components(of: cgColor)
        return self
    }

    /// An NSColor's or a UIColor's components, through its CGColor.
    @ObjCMethod("initWithColor:")
    func initialize(color other: NSObject?) -> Self {
        let cgColor = other.flatMap { $0.responds(to: "CGColor") ? CoreImageMessages.object($0.objcObject, "CGColor") : nil }
        color.components = CIColor.components(of: cgColor)
        return self
    }

    @ObjCMethod("red") func red() -> CGFloat { color.components.0 }
    @ObjCMethod("green") func green() -> CGFloat { color.components.1 }
    @ObjCMethod("blue") func blue() -> CGFloat { color.components.2 }
    @ObjCMethod("alpha") func alpha() -> CGFloat { color.components.3 }
    @ObjCMethod("numberOfComponents") func numberOfComponents() -> Int { 4 }
    @ObjCMethod("colorSpace") func colorSpace() -> CGRef? { nil }

    @ObjCMethod("components")
    func components() -> UnsafePointer<CGFloat>? {
        let state = color
        let storage = state.storage ?? UnsafeMutablePointer<CGFloat>.allocate(capacity: 4)
        state.storage = storage
        (storage[0], storage[1], storage[2], storage[3]) = state.components
        return UnsafePointer(storage)
    }

    @ObjCMethod("stringRepresentation")
    func stringRepresentation() -> String {
        let (r, g, b, a) = color.components
        return [r, g, b, a].map { CIVector.format($0) }.joined(separator: " ")
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

// MARK: - CIVector

final class CIVectorState {
    var values: [CGFloat] = []
}

@ObjCClass("CIVector")
open class CIVector: NSObject {
    static let states = ObjectStates { CIVectorState() }
    var vector: CIVectorState { CIVector.states[objcObject] }
    var values: [CGFloat] { vector.values }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIVector.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIVector.objCClass.pointer)
    }

    static func make(_ values: [CGFloat], cls: ObjCClass = CIVector.objCClass) -> CIVector {
        let made = cls.object.allocated().initialized().unsafeCast(to: CIVector.self)
        made.vector.values = values
        return made
    }

    /// The numbers in "[1 2 3]" or "1, 2, 3".
    static func numbers(in text: String) -> [CGFloat] {
        text.split(whereSeparator: { " ,[]\t\n".contains($0) }).compactMap { Double($0) }.map { CGFloat($0) }
    }

    static func format(_ value: CGFloat) -> String {
        let double = Double(value)
        return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : String(double)
    }

    static func rect(_ rect: CGRect) -> [CGFloat] { [rect.minX, rect.minY, rect.width, rect.height] }
    static func transform(_ t: CGAffineTransform) -> [CGFloat] { [t.a, t.b, t.c, t.d, t.tx, t.ty] }

    @ObjCClassMethod("vectorWithValues:count:")
    static func vector(_ cls: ObjCClass, values: UnsafePointer<CGFloat>?, count: UInt) -> CIVector {
        make(values.map { Array(UnsafeBufferPointer(start: $0, count: Int(count))) } ?? [], cls: cls)
    }

    @ObjCClassMethod("vectorWithX:") static func vector(_ cls: ObjCClass, x: CGFloat) -> CIVector { make([x], cls: cls) }
    @ObjCClassMethod("vectorWithX:Y:") static func vector(_ cls: ObjCClass, x: CGFloat, y: CGFloat) -> CIVector { make([x, y], cls: cls) }
    @ObjCClassMethod("vectorWithX:Y:Z:")
    static func vector(_ cls: ObjCClass, x: CGFloat, y: CGFloat, z: CGFloat) -> CIVector { make([x, y, z], cls: cls) }
    @ObjCClassMethod("vectorWithX:Y:Z:W:")
    static func vector(_ cls: ObjCClass, x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) -> CIVector { make([x, y, z, w], cls: cls) }
    @ObjCClassMethod("vectorWithString:")
    static func vector(_ cls: ObjCClass, string: String?) -> CIVector { make(numbers(in: string ?? ""), cls: cls) }
    @ObjCClassMethod("vectorWithCGPoint:") static func vector(_ cls: ObjCClass, point: CGPoint) -> CIVector { make([point.x, point.y], cls: cls) }
    @ObjCClassMethod("vectorWithCGRect:") static func vector(_ cls: ObjCClass, rect value: CGRect) -> CIVector { make(rect(value), cls: cls) }
    @ObjCClassMethod("vectorWithCGAffineTransform:")
    static func vector(_ cls: ObjCClass, transform value: CGAffineTransform) -> CIVector { make(transform(value), cls: cls) }

    private func set(_ values: [CGFloat]) -> Self {
        vector.values = values
        return self
    }

    @ObjCMethod("initWithValues:count:")
    func initialize(values: UnsafePointer<CGFloat>?, count: UInt) -> Self {
        set(values.map { Array(UnsafeBufferPointer(start: $0, count: Int(count))) } ?? [])
    }
    @ObjCMethod("initWithX:") func initialize(x: CGFloat) -> Self { set([x]) }
    @ObjCMethod("initWithX:Y:") func initialize(x: CGFloat, y: CGFloat) -> Self { set([x, y]) }
    @ObjCMethod("initWithX:Y:Z:") func initialize(x: CGFloat, y: CGFloat, z: CGFloat) -> Self { set([x, y, z]) }
    @ObjCMethod("initWithX:Y:Z:W:") func initialize(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) -> Self { set([x, y, z, w]) }
    @ObjCMethod("initWithString:") func initialize(string: String?) -> Self { set(CIVector.numbers(in: string ?? "")) }
    @ObjCMethod("initWithCGPoint:") func initialize(point: CGPoint) -> Self { set([point.x, point.y]) }
    @ObjCMethod("initWithCGRect:") func initialize(rect: CGRect) -> Self { set(CIVector.rect(rect)) }
    @ObjCMethod("initWithCGAffineTransform:") func initialize(transform: CGAffineTransform) -> Self { set(CIVector.transform(transform)) }

    /// A missing value is 0, as Core Image gives it.
    func value(_ index: Int) -> CGFloat { index < values.count ? values[index] : 0 }

    @ObjCMethod("valueAtIndex:") func value(at index: UInt) -> CGFloat { value(Int(index)) }
    @ObjCMethod("count") func count() -> UInt { UInt(values.count) }
    @ObjCMethod("X") func x() -> CGFloat { value(0) }
    @ObjCMethod("Y") func y() -> CGFloat { value(1) }
    @ObjCMethod("Z") func z() -> CGFloat { value(2) }
    @ObjCMethod("W") func w() -> CGFloat { value(3) }
    @ObjCMethod("CGPointValue") func pointValue() -> CGPoint { CGPoint(x: value(0), y: value(1)) }
    @ObjCMethod("CGRectValue") func rectValue() -> CGRect { CGRect(x: value(0), y: value(1), width: value(2), height: value(3)) }
    @ObjCMethod("CGAffineTransformValue")
    func transformValue() -> CGAffineTransform {
        CGAffineTransform(a: value(0), b: value(1), c: value(2), d: value(3), tx: value(4), ty: value(5))
    }

    @ObjCMethod("stringRepresentation")
    func stringRepresentation() -> String { "[" + values.map(CIVector.format).joined(separator: " ") + "]" }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

// MARK: - CIImage

final class CIImageState {
    var node = ImageNode.empty
    /// The CGImage it was made from, which -CGImage gives.
    var cgImage: RetainedCG?
}

@ObjCClass("CIImage")
open class CIImage: NSObject {
    static let states = ObjectStates { CIImageState() }
    var image: CIImageState { CIImage.states[objcObject] }
    var node: ImageNode { image.node }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIImage.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIImage.objCClass.pointer)
    }

    static func make(_ node: ImageNode, cls: ObjCClass = CIImage.objCClass) -> CIImage {
        let made = cls.object.allocated().initialized().unsafeCast(to: CIImage.self)
        made.image.node = node
        return made
    }

    static func make(cgImage: CGRef?, cls: ObjCClass = CIImage.objCClass) -> CIImage {
        let made = make(.empty, cls: cls)
        made.adopt(cgImage: cgImage)
        return made
    }

    private func adopt(cgImage: CGRef?) {
        guard let cgImage else { return }
        image.cgImage = RetainedCG(cgImage)
        image.node = .bitmap(cgImage)
    }

    /// An image ImageIO decodes from an NSData, +1; nil when it can't.
    static func decode(_ data: UnsafeMutableRawPointer?) -> CGRef? {
        guard let data, let create = CG.imageSourceCreateWithData, let imageAt = CG.imageSourceCreateImageAtIndex,
              let source = create(data, nil) else { return nil }
        defer { CG.release(source) }
        return imageAt(source, 0, nil)
    }

    static func data(at url: NSObject?) -> UnsafeMutableRawPointer? {
        guard let url else { return nil }
        return CoreImageMessages.object(ObjCRuntime.classObject("NSData"), "dataWithContentsOfURL:", url.objcObject)
    }

    /// Pixels read from 8-bit bitmap data; nil for another format.
    static func node(bitmap data: NSObject?, bytesPerRow: Int, size: CGSize, format: Int32) -> ImageNode? {
        let width = Int(size.width), height = Int(size.height)
        guard let order = byteOrder(of: format), width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }
        let pixels: Pixels? = CoreImageMessages.withBytes(of: data?.objcObject) { bytes, length in
            guard length >= bytesPerRow * (height - 1) + width * 4 else { return nil }
            return Bitmaps.read(bytes.assumingMemoryBound(to: UInt8.self), rowBytes: bytesPerRow, width: width, height: height, order: order)
        }
        return pixels.map(ImageNode.pixels)
    }

    // MARK: Creating

    @ObjCClassMethod("emptyImage") static func emptyImage(_ cls: ObjCClass) -> CIImage { make(.empty, cls: cls) }

    @ObjCClassMethod("imageWithCGImage:")
    static func image(_ cls: ObjCClass, cgImage: CGRef?) -> CIImage { make(cgImage: cgImage, cls: cls) }

    @ObjCClassMethod("imageWithCGImage:options:")
    static func image(_ cls: ObjCClass, cgImage: CGRef?, options: NSObject?) -> CIImage { make(cgImage: cgImage, cls: cls) }

    @ObjCClassMethod("imageWithCGLayer:")
    static func image(_ cls: ObjCClass, cgLayer: CGRef?) -> CIImage { make(.empty, cls: cls) }

    @ObjCClassMethod("imageWithColor:")
    static func image(_ cls: ObjCClass, color: CIColor?) -> CIImage { make(.color(color?.color.premultiplied ?? .zero), cls: cls) }

    @ObjCClassMethod("imageWithData:")
    static func image(_ cls: ObjCClass, data: NSObject?) -> CIImage? {
        guard let decoded = decode(data?.objcObject) else { return nil }
        defer { CG.release(decoded) }
        return make(cgImage: decoded, cls: cls)
    }

    @ObjCClassMethod("imageWithData:options:")
    static func image(_ cls: ObjCClass, data: NSObject?, options: NSObject?) -> CIImage? { image(cls, data: data) }

    @ObjCClassMethod("imageWithContentsOfURL:")
    static func image(_ cls: ObjCClass, url: NSObject?) -> CIImage? {
        guard let decoded = decode(data(at: url)) else { return nil }
        defer { CG.release(decoded) }
        return make(cgImage: decoded, cls: cls)
    }

    @ObjCClassMethod("imageWithContentsOfURL:options:")
    static func image(_ cls: ObjCClass, url: NSObject?, options: NSObject?) -> CIImage? { image(cls, url: url) }

    @ObjCClassMethod("imageWithBitmapData:bytesPerRow:size:format:colorSpace:")
    static func image(_ cls: ObjCClass, bitmap data: NSObject?, bytesPerRow: Int, size: CGSize, format: Int32, colorSpace: CGRef?) -> CIImage {
        make(node(bitmap: data, bytesPerRow: bytesPerRow, size: size, format: format) ?? .empty, cls: cls)
    }

    // Failures give an empty image rather than nil: apps of Core Image's
    // first years seldom check.

    @ObjCMethod("initWithCGImage:")
    func initialize(cgImage: CGRef?) -> Self {
        adopt(cgImage: cgImage)
        return self
    }

    @ObjCMethod("initWithCGImage:options:")
    func initialize(cgImage: CGRef?, options: NSObject?) -> Self { initialize(cgImage: cgImage) }

    @ObjCMethod("initWithCGLayer:") func initialize(cgLayer: CGRef?) -> Self { self }
    @ObjCMethod("initWithCGLayer:options:") func initialize(cgLayer: CGRef?, options: NSObject?) -> Self { self }

    @ObjCMethod("initWithColor:")
    func initialize(color: CIColor?) -> Self {
        image.node = .color(color?.color.premultiplied ?? .zero)
        return self
    }

    @ObjCMethod("initWithData:")
    func initialize(data: NSObject?) -> Self {
        if let decoded = CIImage.decode(data?.objcObject) {
            adopt(cgImage: decoded)
            CG.release(decoded)
        }
        return self
    }

    @ObjCMethod("initWithData:options:") func initialize(data: NSObject?, options: NSObject?) -> Self { initialize(data: data) }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(url: NSObject?) -> Self {
        if let decoded = CIImage.decode(CIImage.data(at: url)) {
            adopt(cgImage: decoded)
            CG.release(decoded)
        }
        return self
    }

    @ObjCMethod("initWithContentsOfURL:options:") func initialize(url: NSObject?, options: NSObject?) -> Self { initialize(url: url) }

    @ObjCMethod("initWithBitmapData:bytesPerRow:size:format:colorSpace:")
    func initialize(bitmap data: NSObject?, bytesPerRow: Int, size: CGSize, format: Int32, colorSpace: CGRef?) -> Self {
        if let node = CIImage.node(bitmap: data, bytesPerRow: bytesPerRow, size: size, format: format) { image.node = node }
        return self
    }

    /// UIKit's -initWithImage: (a UIImage) and AppKit's
    /// -initWithBitmapImageRep:, through the CGImage each gives.
    @ObjCMethod("initWithImage:")
    func initialize(image other: NSObject?) -> Self {
        adopt(cgImage: CoreImageMessages.cgImage(of: other))
        return self
    }

    @ObjCMethod("initWithImage:options:") func initialize(image other: NSObject?, options: NSObject?) -> Self { initialize(image: other) }
    @ObjCMethod("initWithBitmapImageRep:") func initialize(bitmapImageRep: NSObject?) -> Self { initialize(image: bitmapImageRep) }

    // MARK: Properties

    @ObjCMethod("extent") func extent() -> CGRect { node.extent }
    /// The CGImage it was made from; nil for one a filter made.
    @ObjCMethod("CGImage") func cgImage() -> CGRef? { image.cgImage?.ref }
    @ObjCMethod("properties") func properties() -> NSObject? { nil }
    @ObjCMethod("colorSpace") func colorSpace() -> CGRef? { nil }
    @ObjCMethod("definition") func definition() -> NSObject? { self }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }

    /// The whole image rendered, +0, for AppKit's and UIKit's images of
    /// Core Image's.
    @ObjCMethod("_perryCGImage")
    func perryCGImage() -> CGRef? {
        if let made = image.cgImage { return made.ref }
        return node.makeCGImage().flatMap { ObjCRuntime.autorelease($0) }
    }

    // MARK: Making others

    @ObjCMethod("imageByApplyingTransform:")
    func applying(_ transform: CGAffineTransform) -> CIImage { CIImage.make(node.transformed(transform)) }

    @ObjCMethod("imageByCroppingToRect:")
    func cropping(to rect: CGRect) -> CIImage { CIImage.make(node.cropped(to: rect)) }

    @ObjCMethod("imageByClampingToExtent")
    func clampingToExtent() -> CIImage { CIImage.make(node.clamped()) }

    @ObjCMethod("imageByClampingToRect:")
    func clamping(to rect: CGRect) -> CIImage { CIImage.make(node.cropped(to: rect).clamped()) }

    @ObjCMethod("imageByCompositingOverImage:")
    func compositing(over background: CIImage?) -> CIImage {
        CIImage.make(ImageCompositing.node(named: "CISourceOverCompositing", node, background?.node ?? .empty))
    }

    @ObjCMethod("imageByApplyingFilter:withInputParameters:")
    func applying(filterNamed name: String, parameters: NSObject?) -> CIImage {
        let filter = CIFilter.make(named: name, cls: CIFilter.objCClass)
        filter.setValues(from: parameters?.as(NSDictionary.self))
        filter.filter.values["inputImage"] = self
        return filter.outputImage() ?? CIImage.make(.empty)
    }

    @ObjCMethod("imageByApplyingFilter:")
    func applying(filterNamed name: String) -> CIImage { applying(filterNamed: name, parameters: nil) }

    // MARK: Drawing, AppKit's category

    /// Draws the source rectangle in AppKit's current context.
    func draw(in rect: CGRect, from source: CGRect, fraction: CGFloat) {
        guard let context = CoreImageMessages.currentAppKitContext else { return }
        CG.saveGState(context)
        if fraction < 1 { CG.setAlpha(context, fraction) }
        CIContext.draw(node, in: rect, from: source, context: context)
        CG.restoreGState(context)
    }

    @ObjCMethod("drawInRect:fromRect:operation:fraction:")
    func draw(inRect rect: CGRect, fromRect source: CGRect, operation: UInt, fraction: CGFloat) {
        draw(in: rect, from: source, fraction: fraction)
    }

    @ObjCMethod("drawAtPoint:fromRect:operation:fraction:")
    func draw(atPoint point: CGPoint, fromRect source: CGRect, operation: UInt, fraction: CGFloat) {
        let from = CoreImageGeometry.isEmpty(source) ? node.extent : source
        draw(in: CGRect(origin: point, size: from.size), from: from, fraction: fraction)
    }
}

// MARK: - CIContext

final class CIContextState {
    /// The CoreGraphics context drawn into; retained.
    var cgContext: RetainedCG?
}

@ObjCClass("CIContext")
open class CIContext: NSObject {
    static let states = ObjectStates { CIContextState() }
    var context: CIContextState { CIContext.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIContext.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIContext.objCClass.pointer)
    }

    static func make(_ cls: ObjCClass, cgContext: CGRef? = nil) -> CIContext {
        let made = cls.object.allocated().initialized().unsafeCast(to: CIContext.self)
        made.context.cgContext = cgContext.map { RetainedCG($0) }
        return made
    }

    /// The rectangle of an image that a source rectangle names: the
    /// image's extent for an empty or infinite one.
    static func pixels(of node: ImageNode, in source: CGRect) -> ImageRect {
        if CoreImageGeometry.isInfinite(source) || CoreImageGeometry.isEmpty(source) { return node.pixelExtent ?? ImageRect() }
        return ImageRect(covering: source)
    }

    /// Draws the source rectangle of an image into a rectangle of a
    /// CoreGraphics context.
    static func draw(_ node: ImageNode, in rect: CGRect, from source: CGRect, context: CGRef) {
        let region = pixels(of: node, in: source)
        guard !region.isEmpty, let image = Bitmaps.image(node.render(region)) else { return }
        defer { CG.release(image) }
        CG.drawImage(context, rect, image)
    }

    @ObjCClassMethod("context") static func context(_ cls: ObjCClass) -> CIContext { make(cls) }
    @ObjCClassMethod("contextWithOptions:") static func context(_ cls: ObjCClass, options: NSObject?) -> CIContext { make(cls) }

    @ObjCClassMethod("contextWithCGContext:options:")
    static func context(_ cls: ObjCClass, cgContext: CGRef?, options: NSObject?) -> CIContext { make(cls, cgContext: cgContext) }

    // Contexts of OpenGL, OpenGL ES and Metal render into bitmaps only.
    @ObjCClassMethod("contextWithCGLContext:pixelFormat:options:")
    static func context(_ cls: ObjCClass, cglContext: UnsafeMutableRawPointer?, pixelFormat: UnsafeMutableRawPointer?, options: NSObject?)
        -> CIContext { make(cls) }

    @ObjCClassMethod("contextWithCGLContext:pixelFormat:colorSpace:options:")
    static func context(_ cls: ObjCClass, cglContext: UnsafeMutableRawPointer?, pixelFormat: UnsafeMutableRawPointer?,
                        colorSpace: CGRef?, options: NSObject?) -> CIContext { make(cls) }

    @ObjCClassMethod("contextWithEAGLContext:") static func context(_ cls: ObjCClass, eaglContext: NSObject?) -> CIContext { make(cls) }
    @ObjCClassMethod("contextWithEAGLContext:options:")
    static func context(_ cls: ObjCClass, eaglContext: NSObject?, options: NSObject?) -> CIContext { make(cls) }
    @ObjCClassMethod("contextWithMTLDevice:") static func context(_ cls: ObjCClass, device: NSObject?) -> CIContext { make(cls) }
    @ObjCClassMethod("contextWithMTLDevice:options:")
    static func context(_ cls: ObjCClass, device: NSObject?, options: NSObject?) -> CIContext { make(cls) }

    @ObjCMethod("initWithOptions:") func initialize(options: NSObject?) -> Self { self }

    // MARK: Drawing

    @ObjCMethod("drawImage:inRect:fromRect:")
    func draw(_ image: CIImage?, inRect rect: CGRect, fromRect source: CGRect) {
        guard let image, let cgContext = context.cgContext else { return }
        CIContext.draw(image.node, in: rect, from: source, context: cgContext.ref)
    }

    @ObjCMethod("drawImage:atPoint:fromRect:")
    func draw(_ image: CIImage?, atPoint point: CGPoint, fromRect source: CGRect) {
        guard let image else { return }
        let from = CIContext.pixels(of: image.node, in: source).cgRect
        draw(image, inRect: CGRect(origin: point, size: from.size), fromRect: from)
    }

    /// The rectangle's pixels as a CGImage, +1.
    @ObjCMethod("createCGImage:fromRect:")
    func createCGImage(_ image: CIImage?, from rect: CGRect) -> CGRef? {
        guard let image else { return nil }
        let region = CIContext.pixels(of: image.node, in: rect)
        return region.isEmpty ? nil : Bitmaps.image(image.node.render(region))
    }

    @ObjCMethod("createCGImage:fromRect:format:colorSpace:")
    func createCGImage(_ image: CIImage?, from rect: CGRect, format: Int32, colorSpace: CGRef?) -> CGRef? {
        createCGImage(image, from: rect)
    }

    @ObjCMethod("createCGImage:fromRect:format:colorSpace:deferred:")
    func createCGImage(_ image: CIImage?, from rect: CGRect, format: Int32, colorSpace: CGRef?, deferred: Bool) -> CGRef? {
        createCGImage(image, from: rect)
    }

    @ObjCMethod("createCGLayerWithSize:info:") func createCGLayer(size: CGSize, info: NSObject?) -> CGRef? { nil }

    /// The rectangle's pixels into the caller's memory, rows from the top.
    @ObjCMethod("render:toBitmap:rowBytes:bounds:format:colorSpace:")
    func render(_ image: CIImage?, toBitmap data: UnsafeMutableRawPointer?, rowBytes: Int, bounds: CGRect, format: Int32, colorSpace: CGRef?) {
        guard let image, let data, let order = byteOrder(of: format) else { return }
        let region = ImageRect(covering: bounds)
        guard !region.isEmpty, rowBytes >= region.width * 4 else { return }
        Bitmaps.write(image.node.render(region), to: data.assumingMemoryBound(to: UInt8.self), rowBytes: rowBytes, order: order)
    }

    @ObjCMethod("reclaimResources") func reclaimResources() {}
    @ObjCMethod("clearCaches") func clearCaches() {}
    @ObjCMethod("workingColorSpace") func workingColorSpace() -> CGRef? { nil }
    @ObjCMethod("inputImageMaximumSize") func inputImageMaximumSize() -> CGSize { CGSize(width: 8192, height: 8192) }
    @ObjCMethod("outputImageMaximumSize") func outputImageMaximumSize() -> CGSize { CGSize(width: 8192, height: 8192) }
}

// MARK: - Kernels, samplers and plug-ins

/// CISampler: how a kernel reads an image. Kernels don't run here, so a
/// sampler only keeps its image.
final class CISamplerState {
    var image: CIImage?
}

@ObjCClass("CISampler")
open class CISampler: NSObject {
    static let states = ObjectStates { CISamplerState() }
    var sampler: CISamplerState { CISampler.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CISampler.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CISampler.objCClass.pointer)
    }

    static func make(_ cls: ObjCClass, image: CIImage?) -> CISampler {
        let made = cls.object.allocated().initialized().unsafeCast(to: CISampler.self)
        made.sampler.image = image
        return made
    }

    @ObjCClassMethod("samplerWithImage:") static func sampler(_ cls: ObjCClass, image: CIImage?) -> CISampler { make(cls, image: image) }
    @ObjCClassMethod("samplerWithImage:options:")
    static func sampler(_ cls: ObjCClass, image: CIImage?, options: NSObject?) -> CISampler { make(cls, image: image) }

    @ObjCMethod("initWithImage:")
    func initialize(image: CIImage?) -> Self {
        sampler.image = image
        return self
    }

    @ObjCMethod("initWithImage:options:") func initialize(image: CIImage?, options: NSObject?) -> Self { initialize(image: image) }
    @ObjCMethod("extent") func extent() -> CGRect { sampler.image?.node.extent ?? .zero }
    @ObjCMethod("definition") func definition() -> NSObject? { sampler.image }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(objcObject) }
}

/// CIKernel: a program in Core Image's kernel language, which Perry doesn't
/// compile: there are none to give, and filters that apply one give their
/// first image back.
@ObjCClass("CIKernel")
open class CIKernel: NSObject {
    @ObjCClassMethod("kernelsWithString:") static func kernels(_ cls: ObjCClass, string: String?) -> NSObject { NSMutableArray.empty() }
    @ObjCClassMethod("kernelWithString:") static func kernel(_ cls: ObjCClass, string: String?) -> NSObject? { nil }
    @ObjCMethod("name") func name() -> String { "" }
    @ObjCMethod("setROISelector:") func setROISelector(_ selector: UnsafeRawPointer?) {}
}

/// CIPlugIn: image units, bundles of filters, which load nothing here.
@ObjCClass("CIPlugIn")
open class CIPlugIn: NSObject {
    @ObjCClassMethod("loadAllPlugIns") static func loadAllPlugIns() {}
    @ObjCClassMethod("loadNonExecutablePlugIns") static func loadNonExecutablePlugIns() {}
    @ObjCClassMethod("loadPlugIn:allowNonExecutable:") static func loadPlugIn(_ url: NSObject?, allowNonExecutable: Bool) {}
    @ObjCClassMethod("loadPlugIn:allowExecutableCode:") static func loadPlugIn(_ url: NSObject?, allowExecutableCode: Bool) {}
}
