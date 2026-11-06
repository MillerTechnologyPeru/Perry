import CPerryGeometry
import PerryObjCInterop

// Core Image, as far as apps resize and touch up images with it: an image
// is a CGImage, a filter works it on the CPU as its output image is asked
// for, and a context hands the result back as a CGImage. Lanczos scaling
// draws the image at its new size; filters Perry has no rendering of give
// their input image back unchanged.

@ObjCConstants
enum CoreImageKeys {
    static let kCIInputImageKey = "inputImage"
    static let kCIOutputImageKey = "outputImage"
    static let kCIInputScaleKey = "inputScale"
    static let kCIInputAspectRatioKey = "inputAspectRatio"
    static let kCIInputSharpnessKey = "inputSharpness"
    static let kCIInputRadiusKey = "inputRadius"
    static let kCIInputIntensityKey = "inputIntensity"
    static let kCIContextUseSoftwareRenderer = "kCIContextUseSoftwareRenderer"
    static let kCIContextWorkingColorSpace = "kCIContextWorkingColorSpace"
    static let kCIContextOutputColorSpace = "kCIContextOutputColorSpace"
}

final class CIImageState: ObjectState {
    /// Retained.
    var cgImage: CGRef?
    deinit { cgImage.map(CG.release) }
}

@ObjCClass("CIImage")
open class CIImage: NSObject {
    static let states = StateTable<CIImageState>()
    var image: CIImageState { CIImage.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIImage.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIImage.objCClass.pointer)
    }

    /// An image of `cgImage`, which it retains.
    static func make(_ cgImage: CGRef?) -> CIImage {
        let made = objCClass.object.allocated().unsafeCast(to: CIImage.self)
        made.image.cgImage = cgImage.flatMap { ObjCRuntime.retain($0) }
        return made
    }

    @ObjCMethod("initWithCGImage:")
    func initialize(cgImage: CGRef?) -> Self {
        image.cgImage = cgImage.flatMap { ObjCRuntime.retain($0) }
        return self
    }

    @ObjCMethod("initWithCGImage:options:")
    func initialize(cgImage: CGRef?, options: NSObject?) -> Self { initialize(cgImage: cgImage) }

    @ObjCMethod("initWithImage:")
    func initialize(uiImage: UIImage?) -> Self { initialize(cgImage: uiImage?.state.cgImage) }

    @ObjCClassMethod("imageWithCGImage:")
    static func image(_ cls: ObjCClass, cgImage: CGRef?) -> NSObject { make(cgImage) }

    @ObjCClassMethod("imageWithCGImage:options:")
    static func image(_ cls: ObjCClass, cgImage: CGRef?, options: NSObject?) -> NSObject { make(cgImage) }

    @ObjCMethod("CGImage") func cgImage() -> CGRef? { image.cgImage }

    /// The image's pixels, from the origin.
    @ObjCMethod("extent")
    func extent() -> CGRect {
        guard let cgImage = image.cgImage else { return .zero }
        return CGRect(x: 0, y: 0, width: CGFloat(CG.imageGetWidth(cgImage)), height: CGFloat(CG.imageGetHeight(cgImage)))
    }
}

final class CIFilterState: ObjectState {
    var name = ""
    var values: [String: NSObject] = [:]
}

@ObjCClass("CIFilter")
open class CIFilter: NSObject {
    static let states = StateTable<CIFilterState>()
    var filter: CIFilterState { CIFilter.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIFilter.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIFilter.objCClass.pointer)
    }

    @ObjCClassMethod("filterWithName:")
    static func filter(_ cls: ObjCClass, name: String) -> NSObject {
        let made = cls.object.allocated().unsafeCast(to: CIFilter.self)
        made.filter.name = name
        return made
    }

    @ObjCClassMethod("filterWithName:withInputParameters:")
    static func filter(_ cls: ObjCClass, name: String, parameters: NSObject?) -> NSObject {
        let made = filter(cls, name: name).unsafeCast(to: CIFilter.self)
        if let parameters = parameters?.as(NSDictionary.self) {
            for key in ["inputImage", "inputScale", "inputAspectRatio", "inputSharpness", "inputRadius", "inputIntensity"] {
                if let value = parameters.object(forKey: key) { made.filter.values[key] = value }
            }
        }
        return made
    }

    @ObjCMethod("name") func name() -> String { filter.name }
    @ObjCMethod("setDefaults") func setDefaults() {}

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String) { filter.values[key] = value }

    @ObjCMethod("valueForKey:")
    func value(forKey key: String) -> NSObject? { key == "outputImage" ? outputImage() : filter.values[key] }

    private func number(_ key: String, _ fallback: Double) -> Double {
        filter.values[key]?.as(NSNumber.self)?.doubleValue() ?? fallback
    }

    /// The input image worked by the filter.
    @ObjCMethod("outputImage")
    func outputImage() -> CIImage? {
        guard let input = filter.values["inputImage"]?.as(CIImage.self) else { return nil }
        switch filter.name {
        case "CILanczosScaleTransform":
            return scaled(input, scale: number("inputScale", 1), aspectRatio: number("inputAspectRatio", 1)) ?? input
        default:
            return input
        }
    }

    /// The image drawn `scale` times its height and `scale` times
    /// `aspectRatio` its width.
    private func scaled(_ input: CIImage, scale: Double, aspectRatio: Double) -> CIImage? {
        guard let cgImage = input.image.cgImage, scale > 0, aspectRatio > 0 else { return nil }
        let extent = input.extent()
        let size = CGSize(width: (extent.width * CGFloat(scale * aspectRatio)).rounded(), height: (extent.height * CGFloat(scale)).rounded())
        guard size.width >= 1, size.height >= 1, let context = CG.makeContext(size: size, scale: 1, opaque: false) else { return nil }
        defer { CG.release(context) }
        CG.drawFlipped(cgImage, in: CGRect(origin: .zero, size: size), context: context)
        guard let result = CG.bitmapContextCreateImage(context) else { return nil }
        defer { CG.release(result) }
        return CIImage.make(result)
    }
}

@ObjCClass("CIContext")
open class CIContext: NSObject {
    @ObjCClassMethod("context") static func context(_ cls: ObjCClass) -> NSObject { cls.object.allocated() }
    @ObjCClassMethod("contextWithOptions:") static func context(_ cls: ObjCClass, options: NSObject?) -> NSObject { cls.object.allocated() }
    @ObjCMethod("initWithOptions:") func initialize(options: NSObject?) -> Self { self }

    /// The image's pixels as a CGImage, which the caller releases. Only
    /// the whole image is given; a smaller rect still gives all of it.
    @ObjCMethod("createCGImage:fromRect:")
    func createCGImage(_ image: CIImage?, from rect: CGRect) -> CGRef? {
        image?.image.cgImage.flatMap { ObjCRuntime.retain($0) }
    }
}
