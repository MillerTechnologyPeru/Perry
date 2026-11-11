import CPerryImageIO
import Glibc
import PerryObjCInterop

// ImageIO: image sources read PNG, JPEG, GIF, WebP and HEIF through the
// codecs in CPerryImageIO; image destinations write PNG, JPEG and GIF.
// Sources decode when first asked about an image; images with alpha come
// out premultiplied (RGBA), opaque JPEGs as RGBX, as on iOS.

enum ImageTypes {
    static let png = "public.png", jpeg = "public.jpeg", gif = "com.compuserve.gif", webp = "org.webmproject.webp"
    static let heic = "public.heic", heif = "public.heif"
    static let readable = [jpeg, png, gif, heic, heif, webp]
    static let writable = [jpeg, png, gif]

    /// The type the bytes start like.
    static func sniff(_ bytes: [UInt8]) -> String? {
        if bytes.starts(with: [0x89, 0x50, 0x4e, 0x47]) { return png }
        if bytes.starts(with: [0xff, 0xd8, 0xff]) { return jpeg }
        if bytes.starts(with: Array("GIF8".utf8)) { return gif }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) { return webp }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            if ["heic", "heix", "hevc", "heim", "heis"].contains(brand) { return heic }
            if ["mif1", "msf1", "avif"].contains(brand) { return heif }
        }
        return nil
    }
}

/// Property keys and the option keys sources and destinations take.
@ObjCConstants
enum ImagePropertyKeys {
    static let kCGImagePropertyPixelWidth = "PixelWidth"
    static let kCGImagePropertyPixelHeight = "PixelHeight"
    static let kCGImagePropertyDPIWidth = "DPIWidth"
    static let kCGImagePropertyDPIHeight = "DPIHeight"
    static let kCGImagePropertyDepth = "Depth"
    static let kCGImagePropertyOrientation = "Orientation"
    static let kCGImagePropertyIsFloat = "IsFloat"
    static let kCGImagePropertyIsIndexed = "IsIndexed"
    static let kCGImagePropertyHasAlpha = "HasAlpha"
    static let kCGImagePropertyColorModel = "ColorModel"
    static let kCGImagePropertyProfileName = "ProfileName"
    static let kCGImagePropertyFileSize = "FileSize"
    static let kCGImagePropertyFileContentsDictionary = "FileContents"
    static let kCGImagePropertyColorModelRGB = "RGB"
    static let kCGImagePropertyColorModelGray = "Gray"
    static let kCGImagePropertyColorModelCMYK = "CMYK"
    static let kCGImagePropertyColorModelLab = "Lab"
    static let kCGImagePropertyTIFFDictionary = "{TIFF}"
    static let kCGImagePropertyGIFDictionary = "{GIF}"
    static let kCGImagePropertyJFIFDictionary = "{JFIF}"
    static let kCGImagePropertyExifDictionary = "{Exif}"
    static let kCGImagePropertyExifAuxDictionary = "{ExifAux}"
    static let kCGImagePropertyPNGDictionary = "{PNG}"
    static let kCGImagePropertyIPTCDictionary = "{IPTC}"
    static let kCGImagePropertyGPSDictionary = "{GPS}"
    static let kCGImagePropertyRawDictionary = "{Raw}"
    static let kCGImagePropertyCIFFDictionary = "{CIFF}"
    static let kCGImagePropertyMakerAppleDictionary = "{MakerApple}"
    static let kCGImageProperty8BIMDictionary = "{8BIM}"
    static let kCGImagePropertyDNGDictionary = "{DNG}"
    static let kCGImagePropertyWebPDictionary = "{WebP}"
    static let kCGImagePropertyHEICSDictionary = "{HEICS}"
    static let kCGImagePropertyTGADictionary = "{TGA}"
    static let kCGImagePropertyGIFLoopCount = "LoopCount"
    static let kCGImagePropertyGIFDelayTime = "DelayTime"
    static let kCGImagePropertyGIFUnclampedDelayTime = "UnclampedDelayTime"
    static let kCGImagePropertyGIFImageColorMap = "ImageColorMap"
    static let kCGImagePropertyHEICSLoopCount = "LoopCount"
    static let kCGImagePropertyHEICSDelayTime = "DelayTime"
    static let kCGImagePropertyHEICSUnclampedDelayTime = "UnclampedDelayTime"
    static let kCGImagePropertyWebPLoopCount = "LoopCount"
    static let kCGImagePropertyWebPDelayTime = "DelayTime"
    static let kCGImagePropertyWebPUnclampedDelayTime = "UnclampedDelayTime"
    static let kCGImagePropertyGIFHasGlobalColorMap = "HasGlobalColorMap"
    static let kCGImagePropertyGIFCanvasPixelWidth = "CanvasPixelWidth"
    static let kCGImagePropertyGIFCanvasPixelHeight = "CanvasPixelHeight"
    static let kCGImagePropertyGIFFrameInfoArray = "FrameInfo"
    static let kCGImagePropertyPNGGamma = "Gamma"
    static let kCGImagePropertyPNGInterlaceType = "InterlaceType"
    static let kCGImagePropertyPNGXPixelsPerMeter = "XPixelsPerMeter"
    static let kCGImagePropertyPNGYPixelsPerMeter = "YPixelsPerMeter"
    static let kCGImagePropertyPNGsRGBIntent = "sRGBIntent"
    static let kCGImagePropertyPNGAuthor = "Author"
    static let kCGImagePropertyPNGCopyright = "Copyright"
    static let kCGImagePropertyPNGCreationTime = "CreationTime"
    static let kCGImagePropertyPNGDescription = "Description"
    static let kCGImagePropertyPNGSoftware = "Software"
    static let kCGImagePropertyPNGTitle = "Title"
    static let kCGImagePropertyAPNGLoopCount = "LoopCount"
    static let kCGImagePropertyAPNGDelayTime = "DelayTime"
    static let kCGImagePropertyAPNGUnclampedDelayTime = "UnclampedDelayTime"
    static let kCGImagePropertyJFIFVersion = "JFIFVersion"
    static let kCGImagePropertyJFIFXDensity = "XDensity"
    static let kCGImagePropertyJFIFYDensity = "YDensity"
    static let kCGImagePropertyJFIFDensityUnit = "DensityUnit"
    static let kCGImagePropertyJFIFIsProgressive = "IsProgressive"
    static let kCGImagePropertyTIFFOrientation = "Orientation"
    static let kCGImagePropertyTIFFMake = "Make"
    static let kCGImagePropertyTIFFModel = "Model"
    static let kCGImagePropertyTIFFSoftware = "Software"
    static let kCGImagePropertyTIFFDateTime = "DateTime"
    static let kCGImagePropertyTIFFCompression = "Compression"
    static let kCGImagePropertyTIFFCopyright = "Copyright"
    static let kCGImagePropertyTIFFDocumentName = "DocumentName"
    static let kCGImagePropertyTIFFImageDescription = "ImageDescription"
    static let kCGImagePropertyTIFFXResolution = "XResolution"
    static let kCGImagePropertyTIFFYResolution = "YResolution"
    static let kCGImagePropertyTIFFResolutionUnit = "ResolutionUnit"
    static let kCGImagePropertyExifDateTimeOriginal = "DateTimeOriginal"
    static let kCGImagePropertyExifDateTimeDigitized = "DateTimeDigitized"
    static let kCGImagePropertyExifPixelXDimension = "PixelXDimension"
    static let kCGImagePropertyExifPixelYDimension = "PixelYDimension"
    static let kCGImagePropertyExifColorSpace = "ColorSpace"
    static let kCGImagePropertyExifUserComment = "UserComment"
    static let kCGImageSourceTypeIdentifierHint = "kCGImageSourceTypeIdentifierHint"
    static let kCGImageSourceShouldCache = "kCGImageSourceShouldCache"
    static let kCGImageSourceShouldCacheImmediately = "kCGImageSourceShouldCacheImmediately"
    static let kCGImageSourceShouldAllowFloat = "kCGImageSourceShouldAllowFloat"
    static let kCGImageSourceCreateThumbnailFromImageIfAbsent = "kCGImageSourceCreateThumbnailFromImageIfAbsent"
    static let kCGImageSourceCreateThumbnailFromImageAlways = "kCGImageSourceCreateThumbnailFromImageAlways"
    static let kCGImageSourceThumbnailMaxPixelSize = "kCGImageSourceThumbnailMaxPixelSize"
    static let kCGImageSourceCreateThumbnailWithTransform = "kCGImageSourceCreateThumbnailWithTransform"
    static let kCGImageSourceSubsampleFactor = "kCGImageSourceSubsampleFactor"
    /// Decode requests (iOS 17): images here are decoded at standard
    /// dynamic range whatever is asked.
    static let kCGImageSourceDecodeRequest = "kCGImageSourceDecodeRequest"
    static let kCGImageSourceDecodeToHDR = "kCGImageSourceDecodeToHDR"
    static let kCGImageSourceDecodeToSDR = "kCGImageSourceDecodeToSDR"
    static let kCGImageDestinationLossyCompressionQuality = "kCGImageDestinationLossyCompressionQuality"
    static let kCGImageDestinationBackgroundColor = "kCGImageDestinationBackgroundColor"
    static let kCGImageDestinationImageMaxPixelSize = "kCGImageDestinationImageMaxPixelSize"
    static let kCGImageDestinationEmbedThumbnail = "kCGImageDestinationEmbedThumbnail"
    static let kCGImageDestinationOptimizeColorForSharing = "kCGImageDestinationOptimizeColorForSharing"
    static let kCGImageDestinationMergeMetadata = "kCGImageDestinationMergeMetadata"
    static let kCGImageDestinationMetadata = "kCGImageDestinationMetadata"
    /// Encode requests (iOS 17): images here are encoded at standard
    /// dynamic range whatever is asked.
    static let kCGImageDestinationEncodeRequest = "kCGImageDestinationEncodeRequest"
    static let kCGImageDestinationEncodeToSDR = "kCGImageDestinationEncodeToSDR"
    static let kCGImageDestinationEncodeToISOHDR = "kCGImageDestinationEncodeToISOHDR"
    static let kCGImageDestinationEncodeToISOGainmap = "kCGImageDestinationEncodeToISOGainmap"
    static let kCGImageDestinationDateTime = "kCGImageDestinationDateTime"
    static let kCGImageDestinationOrientation = "kCGImageDestinationOrientation"
}

// MARK: - Sources

final class SourceState: @unchecked Sendable {
    var bytes: [UInt8]
    var complete: Bool
    private var decodedType: String?
    private var decoded: (images: [Bitmap], info: perry_decoded)?
    /// Each frame's delay, kept when the codec's buffers are freed.
    private(set) var delays: [Double] = []
    private var failed = false

    init(bytes: [UInt8], complete: Bool = true) {
        self.bytes = bytes
        self.complete = complete
    }

    var type: String? { ImageTypes.sniff(bytes) }

    /// The decoded file, decoding it once.
    var contents: (images: [Bitmap], info: perry_decoded)? {
        if let decoded, decodedType == type { return decoded }
        guard !failed, let type else { return nil }
        var info = perry_decoded()
        let ok = bytes.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            switch type {
            case ImageTypes.png: return perry_png_decode(base, buffer.count, &info)
            case ImageTypes.jpeg: return perry_jpeg_decode(base, buffer.count, &info)
            case ImageTypes.gif: return perry_gif_decode(base, buffer.count, &info)
            case ImageTypes.webp: return perry_webp_decode(base, buffer.count, &info)
            default: return perry_heif_decode(base, buffer.count, &info)
            }
        }
        guard ok != 0 else {
            if complete { failed = true }
            return nil
        }
        var images: [Bitmap] = []
        delays = []
        for index in 0..<Int(info.count) {
            let frame = info.frames[index]
            images.append(Bitmap(width: Int(frame.width), height: Int(frame.height), straight: frame.rgba))
            delays.append(frame.delay)
        }
        perry_decoded_free(&info)
        decoded = (images, info)
        decodedType = type
        return decoded
    }

    /// CGImageSourceStatus: complete 0, incomplete -1, unknown type -3, invalid data -4.
    var status: Int32 {
        guard let _ = type else { return bytes.isEmpty ? -2 : -4 }
        if contents != nil { return 0 }
        return complete ? -4 : -1
    }

    func properties(at index: Int) -> NSMutableDictionary? {
        guard let (images, info) = contents, images.indices.contains(index) else { return nil }
        let image = images[index]
        var entries: [(String, NSObject)] = [("PixelWidth", .number(image.width)), ("PixelHeight", .number(image.height)),
                                             ("Depth", .number(Int(info.depth))),
                                             ("ColorModel", .string(info.components == 1 ? "Gray" : "RGB")),
                                             ("DPIWidth", .number(info.dpi_x)), ("DPIHeight", .number(info.dpi_y))]
        if info.has_alpha != 0 { entries.append(("HasAlpha", NSNumber.make(bool: true))) }
        if info.orientation > 1 {
            entries.append(("Orientation", .number(Int(info.orientation))))
            entries.append(("{TIFF}", NSMutableDictionary.of([("Orientation", .number(Int(info.orientation)))])))
        }
        switch type {
        case ImageTypes.gif:
            let delay = delays[index]
            entries.append(("{GIF}", NSMutableDictionary.of([("DelayTime", .number(delay < 0.011 ? 0.1 : delay)),
                                                             ("UnclampedDelayTime", .number(delay))])))
        case ImageTypes.png:
            entries.append(("{PNG}", NSMutableDictionary.of([("InterlaceType", .number(0))])))
        case ImageTypes.jpeg:
            entries.append(("{JFIF}", NSMutableDictionary.of([("DensityUnit", .number(1)), ("XDensity", .number(info.dpi_x)),
                                                              ("YDensity", .number(info.dpi_y))])))
        default: break
        }
        return NSMutableDictionary.of(entries)
    }

    var containerProperties: NSMutableDictionary {
        var entries: [(String, NSObject)] = [("FileSize", .number(bytes.count))]
        if type == ImageTypes.gif, let (images, info) = contents {
            var gif: [(String, NSObject)] = [("HasGlobalColorMap", NSNumber.make(bool: true))]
            if info.loop_count >= 0 { gif.append(("LoopCount", .number(Int(info.loop_count)))) }
            if let first = images.first {
                gif.append(("CanvasPixelWidth", .number(first.width)))
                gif.append(("CanvasPixelHeight", .number(first.height)))
            }
            entries.append(("{GIF}", NSMutableDictionary.of(gif)))
        }
        return NSMutableDictionary.of(entries)
    }

    /// The image (+1): with alpha, premultiplied RGBA; without, RGBX.
    func image(at index: Int) -> Ref? {
        guard let (images, info) = contents, images.indices.contains(index) else { return nil }
        let opaque = info.has_alpha == 0
        return Images.make(images[index], format: opaque ? .rgbx : .rgbaPremultiplied, typeIdentifier: type)
    }
}

@ObjCClass("CGImageSource")
public final class CGImageSourceObject: NSObject {
    static let states = StateTable<SourceState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGImageSourceObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGImageSourceObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.imageSource }
}

enum Sources {
    static func state(_ source: Ref?) -> SourceState? { CGImageSourceObject.states[source] }
    static func make(_ state: SourceState) -> Ref { makeObject(CGImageSourceObject.objCClass, CGImageSourceObject.states, state) }
}

@c(_CGImageSourceGetTypeID) public func CGImageSourceGetTypeID() -> UInt { TypeIDs.imageSource }

@c(_CGImageSourceCopyTypeIdentifiers)
public func CGImageSourceCopyTypeIdentifiers() -> Ref? { NSMutableArray.of(ImageTypes.readable.map(NSObject.string)).objCOwnedReturnValue() }

@c(_CGImageSourceCreateWithData)
public func CGImageSourceCreateWithData(_ data: Ref?, _ options: Ref?) -> Ref? {
    guard let data else { return nil }
    return Sources.make(SourceState(bytes: NSData(objCArgument: data).array))
}

@c(_CGImageSourceCreateWithURL)
public func CGImageSourceCreateWithURL(_ url: Ref?, _ options: Ref?) -> Ref? {
    guard let url, let path = NSURL(objCArgument: url).path(), let data = NSData.make(contentsOfFile: path) else { return nil }
    return Sources.make(SourceState(bytes: data.array))
}

@c(_CGImageSourceCreateWithDataProvider)
public func CGImageSourceCreateWithDataProvider(_ provider: Ref?, _ options: Ref?) -> Ref? {
    guard let bytes = DataProviders.bytes(provider) else { return nil }
    return Sources.make(SourceState(bytes: bytes))
}

@c(_CGImageSourceCreateIncremental)
public func CGImageSourceCreateIncremental(_ options: Ref?) -> Ref { Sources.make(SourceState(bytes: [], complete: false)) }

@c(_CGImageSourceUpdateData)
public func CGImageSourceUpdateData(_ source: Ref?, _ data: Ref?, _ final: Bool) {
    guard let state = Sources.state(source), let data else { return }
    state.bytes = NSData(objCArgument: data).array
    state.complete = final
}

@c(_CGImageSourceGetType)
public func CGImageSourceGetType(_ source: Ref?) -> Ref? {
    Sources.state(source)?.type.map { ConstantStrings.make($0) }
}

@c(_CGImageSourceGetCount)
public func CGImageSourceGetCount(_ source: Ref?) -> Int { Sources.state(source)?.contents?.images.count ?? 0 }

@c(_CGImageSourceGetStatus) public func CGImageSourceGetStatus(_ source: Ref?) -> Int32 { Sources.state(source)?.status ?? -4 }

/// Sources here keep their decoded images for good; nothing to drop.
@c(_CGImageSourceRemoveCacheAtIndex) public func CGImageSourceRemoveCacheAtIndex(_ source: Ref?, _ index: Int) {}

@c(_CGImageSourceGetStatusAtIndex)
public func CGImageSourceGetStatusAtIndex(_ source: Ref?, _ index: Int) -> Int32 {
    guard let state = Sources.state(source) else { return -4 }
    return (state.contents?.images.indices.contains(index) ?? false) ? 0 : state.status == 0 ? -4 : state.status
}

@c(_CGImageSourceGetPrimaryImageIndex) public func CGImageSourceGetPrimaryImageIndex(_ source: Ref?) -> Int { 0 }

@c(_CGImageSourceCopyProperties)
public func CGImageSourceCopyProperties(_ source: Ref?, _ options: Ref?) -> Ref? {
    Sources.state(source)?.containerProperties.objCOwnedReturnValue() ?? nil
}

@c(_CGImageSourceCopyPropertiesAtIndex)
public func CGImageSourceCopyPropertiesAtIndex(_ source: Ref?, _ index: Int, _ options: Ref?) -> Ref? {
    Sources.state(source)?.properties(at: index)?.objCOwnedReturnValue() ?? nil
}

@c(_CGImageSourceCreateImageAtIndex)
public func CGImageSourceCreateImageAtIndex(_ source: Ref?, _ index: Int, _ options: Ref?) -> Ref? {
    Sources.state(source)?.image(at: index)
}

/// Files here carry no thumbnails, so the image itself is the thumbnail,
/// scaled to fit the largest size asked for, never enlarged.
@c(_CGImageSourceCreateThumbnailAtIndex)
public func CGImageSourceCreateThumbnailAtIndex(_ source: Ref?, _ index: Int, _ options: Ref?) -> Ref? {
    guard let state = Sources.state(source), let (images, info) = state.contents, images.indices.contains(index) else { return nil }
    let options = Options(options)
    var bitmap = images[index]
    if let maximum = options.number("kCGImageSourceThumbnailMaxPixelSize"), maximum > 0 {
        let scale = min(1, maximum / Double(max(bitmap.width, bitmap.height)))
        if scale < 1 {
            func size(_ value: Int) -> Int { max(1, Int((Double(value) * scale).rounded(.toNearestOrAwayFromZero))) }
            bitmap = bitmap.resized(width: size(bitmap.width), height: size(bitmap.height))
        }
    }
    return Images.make(bitmap, format: info.has_alpha == 0 ? .rgbx : .rgbaPremultiplied)
}

// MARK: - Destinations

final class DestinationState: @unchecked Sendable {
    let type: String
    let capacity: Int
    let data: NSMutableData?
    let path: String?
    var images: [(bitmap: Bitmap, options: Options)] = []
    var properties = Options(nil)

    init(type: String, capacity: Int, data: NSMutableData?, path: String?) {
        self.type = type
        self.capacity = capacity
        self.data = data
        self.path = path
    }

    func encode() -> [UInt8]? {
        guard let first = images.first else { return nil }
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        let ok: Int32
        switch type {
        case ImageTypes.png:
            let pixels = first.bitmap.straight
            ok = perry_png_encode(pixels, Int32(first.bitmap.width), Int32(first.bitmap.height), first.bitmap.isOpaque ? 0 : 1, &out, &size)
        case ImageTypes.jpeg:
            // JPEG has no alpha: composite onto white, as the encoder sees it.
            var pixels = first.bitmap.pixels
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let a = Int(pixels[index + 3])
                for c in 0..<3 { pixels[index + c] = UInt8(min(255, Int(pixels[index + c]) + (255 - a))) }
                pixels[index + 3] = 255
            }
            let quality = Int32(((first.options.number("kCGImageDestinationLossyCompressionQuality")
                ?? properties.number("kCGImageDestinationLossyCompressionQuality") ?? 0.8) * 100).rounded())
            let orientation = Int32(first.options.number("Orientation") ?? properties.number("Orientation") ?? 1)
            ok = perry_jpeg_encode(pixels, Int32(first.bitmap.width), Int32(first.bitmap.height), max(1, min(100, quality)), orientation,
                                   &out, &size)
        default:
            let straight = images.map { $0.bitmap.straight }
            var frames: [perry_frame] = []
            var buffers: [UnsafeMutablePointer<UInt8>] = []
            for (index, image) in images.enumerated() {
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: straight[index].count)
                buffer.initialize(from: straight[index], count: straight[index].count)
                buffers.append(buffer)
                let delay = image.options.nested("{GIF}").number("DelayTime") ?? 0
                frames.append(perry_frame(rgba: buffer, width: Int32(image.bitmap.width), height: Int32(image.bitmap.height), delay: delay))
            }
            let loop = Int32(properties.nested("{GIF}").number("LoopCount") ?? -1)
            ok = perry_gif_encode(frames, Int32(frames.count), loop, &out, &size)
            buffers.forEach { $0.deallocate() }
        }
        guard ok != 0, let out else { return nil }
        defer { free(out) }
        return Array(UnsafeBufferPointer(start: out, count: size))
    }
}

@ObjCClass("CGImageDestination")
public final class CGImageDestinationObject: NSObject {
    static let states = StateTable<DestinationState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGImageDestinationObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGImageDestinationObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.imageDestination }
}

enum Destinations {
    static func state(_ destination: Ref?) -> DestinationState? { CGImageDestinationObject.states[destination] }

    static func make(type: Ref?, capacity: Int, data: NSMutableData?, path: String?) -> Ref? {
        guard let type, ImageTypes.writable.contains(String(objCArgument: type)), capacity > 0 else { return nil }
        return makeObject(CGImageDestinationObject.objCClass, CGImageDestinationObject.states,
                          DestinationState(type: String(objCArgument: type), capacity: capacity, data: data, path: path))
    }
}

@c(_CGImageDestinationGetTypeID) public func CGImageDestinationGetTypeID() -> UInt { TypeIDs.imageDestination }

@c(_CGImageDestinationCopyTypeIdentifiers)
public func CGImageDestinationCopyTypeIdentifiers() -> Ref? {
    NSMutableArray.of(ImageTypes.writable.map(NSObject.string)).objCOwnedReturnValue()
}

@c(_CGImageDestinationCreateWithData)
public func CGImageDestinationCreateWithData(_ data: Ref?, _ type: Ref?, _ count: Int, _ options: Ref?) -> Ref? {
    guard let data else { return nil }
    return Destinations.make(type: type, capacity: count, data: NSMutableData(objCArgument: data), path: nil)
}

@c(_CGImageDestinationCreateWithURL)
public func CGImageDestinationCreateWithURL(_ url: Ref?, _ type: Ref?, _ count: Int, _ options: Ref?) -> Ref? {
    guard let url, let path = NSURL(objCArgument: url).path() else { return nil }
    return Destinations.make(type: type, capacity: count, data: nil, path: path)
}

@c(_CGImageDestinationSetProperties)
public func CGImageDestinationSetProperties(_ destination: Ref?, _ properties: Ref?) {
    Destinations.state(destination)?.properties = Options(properties)
}

@c(_CGImageDestinationAddImage)
public func CGImageDestinationAddImage(_ destination: Ref?, _ image: Ref?, _ properties: Ref?) {
    guard let state = Destinations.state(destination), let image = Images.state(image), state.images.count < state.capacity else { return }
    var bitmap = image.bitmap
    if let maximum = Options(properties).number("kCGImageDestinationImageMaxPixelSize"), maximum > 0 {
        let scale = min(1, maximum / Double(max(bitmap.width, bitmap.height)))
        if scale < 1 {
            bitmap = bitmap.resized(width: max(1, Int((Double(bitmap.width) * scale).rounded())),
                                    height: max(1, Int((Double(bitmap.height) * scale).rounded())))
        }
    }
    state.images.append((bitmap, Options(properties)))
}

@c(_CGImageDestinationAddImageFromSource)
public func CGImageDestinationAddImageFromSource(_ destination: Ref?, _ source: Ref?, _ index: Int, _ properties: Ref?) {
    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return }
    defer { ObjCRuntime.release(image) }
    CGImageDestinationAddImage(destination, image, properties)
}

/// Encodes and writes the images; false when there are none or the
/// encoder fails.
@c(_CGImageDestinationFinalize)
public func CGImageDestinationFinalize(_ destination: Ref?) -> Bool {
    guard let state = Destinations.state(destination), let bytes = state.encode() else { return false }
    if let data = state.data {
        data.replace(with: bytes)
        return true
    }
    if let path = state.path { return NSData.of(bytes).write(toFile: path, atomically: true) }
    return false
}
