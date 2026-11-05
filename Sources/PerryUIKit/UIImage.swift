import CPerryGeometry
import PerryObjCInterop

// UIImage: a CGImage with a scale and an orientation. Images decode and
// encode through ImageIO, and draw upright in UIKit's flipped coordinates.

final class ImageState: ObjectState {
    var cgImage: CGRef?
    var scale: CGFloat = 1
    /// UIImageOrientation: up 0, down 1, left 2, right 3, and mirrored.
    var orientation = 0
    /// UIImageRenderingMode: automatic 0, original 1, template 2.
    var renderingMode = 0
    var capInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    /// The SF Symbol this image draws (Symbols), and its configuration.
    var symbolName: String?
    var configuration: UIImageConfiguration?

    deinit { if let cgImage { CG.release(cgImage) } }

    func set(_ image: CGRef?, scale: CGFloat, orientation: Int) {
        if let cgImage { CG.release(cgImage) }
        cgImage = ObjCRuntime.retain(image)
        self.scale = scale > 0 ? scale : 1
        self.orientation = orientation
    }

    /// The size in points; left and right orientations swap the sides.
    var size: CGSize {
        guard let cgImage else { return .zero }
        let width = CGFloat(CG.imageGetWidth(cgImage)) / scale, height = CGFloat(CG.imageGetHeight(cgImage)) / scale
        return (2...3).contains(orientation) || (6...7).contains(orientation)
            ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

@ObjCClass("UIImage")
open class UIImage: NSObject {
    static let states = StateTable<ImageState>()
    var state: ImageState { UIImage.states[objcObject] }

    /// A new image of `cgImage`.
    static func make(_ cls: ObjCClass = objCClass, cgImage: CGRef?, scale: CGFloat, orientation: Int = 0) -> UIImage {
        let image = cls.object.allocated().unsafeCast(to: UIImage.self)
        image.state.set(cgImage, scale: scale, orientation: orientation)
        return image
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIImage.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIImage.objCClass.pointer)
    }

    // MARK: Making images

    @ObjCClassMethod("imageWithCGImage:")
    static func image(_ cls: ObjCClass, cgImage: UnsafeMutableRawPointer?) -> UIImage { make(cls, cgImage: cgImage, scale: 1) }

    @ObjCClassMethod("imageWithCGImage:scale:orientation:")
    static func image(_ cls: ObjCClass, cgImage: UnsafeMutableRawPointer?, scale: CGFloat, orientation: Int) -> UIImage {
        make(cls, cgImage: cgImage, scale: scale, orientation: orientation)
    }

    @ObjCMethod("initWithCGImage:")
    func initialize(cgImage: UnsafeMutableRawPointer?) -> Self {
        state.set(cgImage, scale: 1, orientation: 0)
        return self
    }

    @ObjCMethod("initWithCGImage:scale:orientation:")
    func initialize(cgImage: UnsafeMutableRawPointer?, scale: CGFloat, orientation: Int) -> Self {
        state.set(cgImage, scale: scale, orientation: orientation)
        return self
    }

    /// From a nib: the named image in the bundle the nib came from, else in
    /// the main bundle.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        guard let name = decoded.string("UIResourceName") ?? decoded.string("UIImageName") else { return self }
        let nibBundle = coder.as(UINibDecoder.self)?.nib?.bundlePath.flatMap { NSBundle.bundle(path: $0) }
        let image = nibBundle.flatMap { UIImage.image(UIImage.objCClass, named: name, in: $0, catalog: false) }
            ?? UIImage.image(UIImage.objCClass, named: name)
        if let image { state.set(image.state.cgImage, scale: image.state.scale, orientation: 0) }
        return self
    }

    @ObjCClassMethod("imageWithData:")
    static func image(_ cls: ObjCClass, data: NSObject?) -> UIImage? { image(cls, data: data, scale: 1) }

    @ObjCClassMethod("imageWithData:scale:")
    static func image(_ cls: ObjCClass, data: NSObject?, scale: CGFloat) -> UIImage? {
        decode(data).map { make(cls, cgImage: $0.object, scale: scale) }
    }

    @ObjCMethod("initWithData:")
    func initialize(data: NSObject?) -> Self? { initialize(data: data, scale: 1) }

    @ObjCMethod("initWithData:scale:")
    func initialize(data: NSObject?, scale: CGFloat) -> Self? {
        guard let image = UIImage.decode(data) else { return nil }
        state.set(image.object, scale: scale, orientation: 0)
        return self
    }

    @ObjCClassMethod("imageWithContentsOfFile:")
    static func image(_ cls: ObjCClass, contentsOfFile path: String) -> UIImage? {
        load(path).map { make(cls, cgImage: $0.image.object, scale: $0.scale) }
    }

    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String) -> Self? {
        guard let loaded = UIImage.load(path) else { return nil }
        state.set(loaded.image.object, scale: loaded.scale, orientation: 0)
        return self
    }

    /// An image in the main bundle: the PNG for the screen's scale if
    /// there is one, else the next larger, else the smaller; else the
    /// asset catalog's.
    @ObjCClassMethod("imageNamed:")
    static func image(_ cls: ObjCClass, named name: String) -> UIImage? { image(cls, named: name, in: NSBundle.main(), catalog: true) }

    /// The named image's file in `bundle`, else the bundle's asset
    /// catalog's.
    static func image(_ cls: ObjCClass, named name: String, in bundle: NSBundle, catalog: Bool, dark: Bool = false) -> UIImage? {
        let base = name.hasSuffix(".png") || name.hasSuffix(".jpg") ? String(name.dropLast(4)) : name
        let type = name.hasSuffix(".jpg") ? "jpg" : "png"
        let suffixes = Screen.scale >= 3 ? ["@3x", "@2x", ""] : Screen.scale >= 2 ? ["@2x", "@3x", ""] : ["", "@2x", "@3x"]
        for suffix in suffixes {
            if let path = bundle.path(forResource: base + suffix, ofType: type), let image = image(cls, contentsOfFile: path) {
                return image
            }
        }
        guard catalog else { return nil }
        let found = bundle.objcObject == NSBundle.main().objcObject
            ? AssetCatalog.image(named: name, dark: dark) : AssetCatalog.catalog(in: bundle)?.image(named: name, dark: dark)
        return found.map { make(cls, cgImage: $0.image.object, scale: $0.scale) }
    }

    /// In the bundle given, the main bundle when none is; the catalog's
    /// image for the dark appearance when the traits are dark.
    @ObjCClassMethod("imageNamed:inBundle:compatibleWithTraitCollection:")
    static func image(_ cls: ObjCClass, named name: String, in bundle: NSObject?, compatibleWith traits: NSObject?) -> UIImage? {
        let dark = traits?.as(UITraitCollection.self)?.traits.style == 2
        return image(cls, named: name, in: bundle?.as(NSBundle.self) ?? NSBundle.main(), catalog: true, dark: dark)
    }

    @ObjCClassMethod("imageNamed:inBundle:withConfiguration:")
    static func image(_ cls: ObjCClass, named name: String, in bundle: NSObject?, configuration: NSObject?) -> UIImage? {
        image(cls, named: name, in: bundle, compatibleWith: nil)
    }

    /// The common SF Symbols, drawn as templates (Symbols).
    @ObjCClassMethod("systemImageNamed:") static func systemImage(named name: String) -> UIImage? { Symbols.image(named: name) }

    @ObjCClassMethod("systemImageNamed:withConfiguration:")
    static func systemImage(named name: String, configuration: NSObject?) -> UIImage? {
        Symbols.image(named: name, configuration: configuration?.as(UIImageConfiguration.self))
    }

    @ObjCClassMethod("systemImageNamed:compatibleWithTraitCollection:")
    static func systemImage(named name: String, compatibleWith traits: NSObject?) -> UIImage? { Symbols.image(named: name) }

    /// A file's image; a name ending in @2x or @3x gives the scale.
    private static func load(_ path: String) -> (image: Owned, scale: CGFloat)? {
        guard let data = NSData.contents(ofFile: path), let image = decode(data) else { return nil }
        let stem = path.split(separator: "/").last.map { $0.split(separator: ".").first.map(String.init) ?? "" } ?? ""
        let scale: CGFloat = stem.hasSuffix("@3x") ? 3 : stem.hasSuffix("@2x") ? 2 : 1
        return (image, scale)
    }

    /// Decodes the first image in `data`.
    static func decode(_ data: NSObject?) -> Owned? {
        guard let data, let source = CG.imageSourceCreateWithData(data.objcObject, nil) else { return nil }
        defer { CG.release(source) }
        return CG.imageSourceCreateImageAtIndex(source, 0, nil).map(Owned.init)
    }

    /// Encodes `image` as `type` ("public.png"), with `properties`.
    static func encode(_ image: CGRef, type: String, properties: NSObject? = nil) -> NSObject? {
        let data = NSMutableData.empty()
        guard let destination = CG.imageDestinationCreateWithData(data.objcObject, type.objCReturnValue(), 1, nil) else { return nil }
        defer { CG.release(destination) }
        CG.imageDestinationAddImage(destination, image, properties?.objcObject)
        return CG.imageDestinationFinalize(destination) ? data : nil
    }

    /// Images are immutable, so a copy property holds the image itself.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    // MARK: Properties

    @ObjCMethod("size") func size() -> CGSize { state.size }
    @ObjCMethod("scale") func scale() -> CGFloat { state.scale }
    @ObjCMethod("CGImage") func cgImage() -> UnsafeMutableRawPointer? { state.cgImage }
    @ObjCMethod("CIImage") func ciImage() -> NSObject? { nil }
    @ObjCMethod("imageOrientation") func imageOrientation() -> Int { state.orientation }
    @ObjCMethod("renderingMode") func renderingMode() -> Int { state.renderingMode }
    @ObjCMethod("capInsets") func capInsets() -> UIEdgeInsets { state.capInsets }
    @ObjCMethod("isSymbolImage") func isSymbolImage() -> Bool { state.symbolName != nil }
    /// A symbol's drawing fills its square, with no margins or baseline.
    @ObjCMethod("contentInsets") func contentInsets() -> UIEdgeInsets { UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    @ObjCMethod("hasBaseline") func hasBaseline() -> Bool { false }
    @ObjCMethod("baselineOffsetFromBottom") func baselineOffsetFromBottom() -> CGFloat { 0 }
    @ObjCMethod("configuration") func configuration() -> UIImageConfiguration? { state.configuration }
    @ObjCMethod("symbolConfiguration") func symbolConfiguration() -> UIImageConfiguration? {
        state.configuration?.as(UIImageSymbolConfiguration.self).map { $0 }
    }

    /// A symbol drawn again for the configuration; other images are
    /// themselves.
    @ObjCMethod("imageWithConfiguration:")
    func withConfiguration(_ configuration: UIImageConfiguration?) -> UIImage {
        guard let name = state.symbolName else { return self }
        let combined = state.configuration.map { $0.applying(configuration) } ?? configuration
        return Symbols.image(named: name, configuration: combined) ?? self
    }

    @ObjCMethod("imageByApplyingSymbolConfiguration:")
    func applyingSymbolConfiguration(_ configuration: UIImageConfiguration?) -> UIImage? { withConfiguration(configuration) }

    /// A copy of the image with another rendering mode.
    @ObjCMethod("imageWithRenderingMode:")
    func withRenderingMode(_ mode: Int) -> UIImage {
        let image = UIImage.make(objCClass, cgImage: state.cgImage, scale: state.scale, orientation: state.orientation)
        image.state.renderingMode = mode
        image.state.capInsets = state.capInsets
        (image.state.symbolName, image.state.configuration) = (state.symbolName, state.configuration)
        return image
    }

    @ObjCMethod("resizableImageWithCapInsets:")
    func resizable(capInsets: UIEdgeInsets) -> UIImage {
        let image = withRenderingMode(state.renderingMode)
        image.state.capInsets = capInsets
        return image
    }

    @ObjCMethod("resizableImageWithCapInsets:resizingMode:")
    func resizable(capInsets: UIEdgeInsets, resizingMode: Int) -> UIImage { resizable(capInsets: capInsets) }

    @ObjCMethod("stretchableImageWithLeftCapWidth:topCapHeight:")
    func stretchable(leftCapWidth: Int, topCapHeight: Int) -> UIImage {
        resizable(capInsets: UIEdgeInsets(top: CGFloat(topCapHeight), left: CGFloat(leftCapWidth), bottom: 0, right: 0))
    }

    /// The image drawn in `color`, through its alpha.
    @ObjCMethod("imageWithTintColor:")
    func withTintColor(_ color: UIColor) -> UIImage {
        let size = state.size
        guard let cgImage = state.cgImage, let context = CG.makeContext(size: size, scale: state.scale, opaque: false) else { return self }
        defer { CG.release(context) }
        let rect = CGRect(origin: .zero, size: size)
        CG.drawFlipped(cgImage, in: rect, context: context)
        CG.setBlendMode(context, 18) // kCGBlendModeSourceIn
        CG.setFillColorWithColor(context, color.state.makeCGColor())
        CG.fillRect(context, rect)
        guard let tinted = CG.bitmapContextCreateImage(context) else { return self }
        defer { CG.release(tinted) }
        return UIImage.make(objCClass, cgImage: tinted, scale: state.scale)
    }

    // MARK: Drawing

    @ObjCMethod("drawAtPoint:")
    func draw(at point: CGPoint) { draw(in: CGRect(origin: point, size: state.size)) }

    @ObjCMethod("drawAtPoint:blendMode:alpha:")
    func draw(at point: CGPoint, blendMode: Int32, alpha: CGFloat) {
        draw(in: CGRect(origin: point, size: state.size), blendMode: blendMode, alpha: alpha)
    }

    @ObjCMethod("drawInRect:")
    func draw(in rect: CGRect) {
        guard let context = Graphics.current, let cgImage = state.cgImage else { return }
        CG.drawFlipped(cgImage, in: rect, context: context)
    }

    @ObjCMethod("drawInRect:blendMode:alpha:")
    func draw(in rect: CGRect, blendMode: Int32, alpha: CGFloat) {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.setAlpha(context, alpha)
        draw(in: rect)
        CG.restoreGState(context)
    }
}

/// A CoreGraphics object this holds one reference to.
final class Owned {
    let object: CGRef

    init(_ object: CGRef) { self.object = object }
    deinit { CG.release(object) }
}

/// The image as PNG data.
@c(_UIImagePNGRepresentation)
public func UIImagePNGRepresentation(_ image: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let image, let cgImage = UIImage.states[image].cgImage else { return nil }
    return UIImage.encode(cgImage, type: "public.png")?.objCReturnValue()
}

/// The image as JPEG data, at a quality from 0 to 1.
@c(_UIImageJPEGRepresentation)
public func UIImageJPEGRepresentation(_ image: UnsafeMutableRawPointer?, _ quality: CGFloat) -> UnsafeMutableRawPointer? {
    guard let image, let cgImage = UIImage.states[image].cgImage else { return nil }
    let properties = NSMutableDictionary.empty()
    properties.set(NSNumber.make(double: quality), forKey: "kCGImageDestinationLossyCompressionQuality")
    return UIImage.encode(cgImage, type: "public.jpeg", properties: properties)?.objCReturnValue()
}

extension NSObject {
    @ObjCMethod("CGImage") func sendCGImage() -> UnsafeMutableRawPointer?
}
