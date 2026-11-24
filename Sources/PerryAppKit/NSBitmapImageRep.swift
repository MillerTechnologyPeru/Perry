import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSImageRep and NSBitmapImageRep: a picture's pixels, kept in memory for the
// program to fill and read. Games make them to hand an image to the window or
// the cursor; apps draw views into them (-cacheDisplayInRect:toBitmapImageRep:)
// and write them out as PNG, JPEG or GIF through ImageIO.

@ObjCClass("NSImageRep")
open class NSImageRep: NSObject {
    var size = CGSize.zero
    var pixelsWide = 0
    var pixelsHigh = 0
    var hasAlpha = false
    var bitsPerSample = 8
    var colorSpace = Constants.NSCalibratedRGBColorSpace

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("size") func repSize() -> CGSize { size }
    @ObjCMethod("setSize:") func setRepSize(_ size: CGSize) { self.size = size }
    @ObjCMethod("pixelsWide") func repPixelsWide() -> Int { pixelsWide }
    @ObjCMethod("pixelsHigh") func repPixelsHigh() -> Int { pixelsHigh }
    @ObjCMethod("setPixelsWide:") func setRepPixelsWide(_ value: Int) { pixelsWide = value }
    @ObjCMethod("setPixelsHigh:") func setRepPixelsHigh(_ value: Int) { pixelsHigh = value }
    @ObjCMethod("hasAlpha") func repHasAlpha() -> Bool { hasAlpha }
    @ObjCMethod("setAlpha:") func setRepAlpha(_ value: Bool) { hasAlpha = value }
    @ObjCMethod("bitsPerSample") func repBitsPerSample() -> Int { bitsPerSample }
    @ObjCMethod("setBitsPerSample:") func setRepBitsPerSample(_ value: Int) { bitsPerSample = value }
    @ObjCMethod("isOpaque") func repIsOpaque() -> Bool { !hasAlpha }
    @ObjCMethod("colorSpaceName") func repColorSpaceName() -> String { colorSpace }
    @ObjCMethod("setColorSpaceName:") func setRepColorSpaceName(_ name: String?) { if let name { colorSpace = name } }
}

/// NSCachedImageRep: an image drawn into an offscreen window, from before
/// image reps drew themselves (Interface Builder subclasses it). It keeps
/// its size; the window and rectangle it was given are kept to give back.
@ObjCClass("NSCachedImageRep")
open class NSCachedImageRep: NSImageRep {
    var cacheWindow: NSWindow?
    var cacheRect = CGRect.zero

    public required init() { super.init() }

    @ObjCMethod("initWithSize:depth:separate:alpha:")
    public required init(size: CGSize, depth: Int32, separate: Bool, alpha: Bool) {
        super.init()
        self.size = size
        (pixelsWide, pixelsHigh) = (Int(size.width), Int(size.height))
        hasAlpha = alpha
        cacheRect = CGRect(origin: .zero, size: size)
    }

    @ObjCMethod("initWithWindow:rect:")
    public required init(window: NSWindow?, rect: CGRect) {
        super.init()
        cacheWindow = window
        cacheRect = rect
        size = rect.size
        (pixelsWide, pixelsHigh) = (Int(rect.width), Int(rect.height))
    }

    @ObjCMethod("window") func repWindow() -> NSWindow? { cacheWindow }
    @ObjCMethod("rect") func repRect() -> CGRect { cacheRect }
    @ObjCMethod("draw") func draw() -> Bool { true }
}

@ObjCClass("NSBitmapImageRep")
open class NSBitmapImageRep: NSImageRep {
    var samplesPerPixel = 4
    var bitsPerPixel = 32
    var bytesPerRow = 0
    var planar = false
    var format: UInt = 0
    /// The pixels: the program's own, or a block this owns.
    private var pixels: UnsafeMutablePointer<UInt8>?
    private var ownsPixels = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bitmapFormat:bytesPerRow:bitsPerPixel:")
    public required init(planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide: Int, pixelsHigh: Int,
                         bitsPerSample: Int, samplesPerPixel: Int, hasAlpha: Bool, isPlanar: Bool,
                         colorSpaceName: String?, bitmapFormat: UInt, bytesPerRow: Int, bitsPerPixel: Int) {
        super.init()
        setUp(planes: planes, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: bitsPerSample,
              samplesPerPixel: samplesPerPixel, hasAlpha: hasAlpha, isPlanar: isPlanar,
              colorSpaceName: colorSpaceName, bitmapFormat: bitmapFormat, bytesPerRow: bytesPerRow, bitsPerPixel: bitsPerPixel)
    }

    @ObjCMethod("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:")
    public required init(planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide: Int, pixelsHigh: Int,
                         bitsPerSample: Int, samplesPerPixel: Int, hasAlpha: Bool, isPlanar: Bool,
                         colorSpaceName: String?, bytesPerRow: Int, bitsPerPixel: Int) {
        super.init()
        setUp(planes: planes, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: bitsPerSample,
              samplesPerPixel: samplesPerPixel, hasAlpha: hasAlpha, isPlanar: isPlanar,
              colorSpaceName: colorSpaceName, bitmapFormat: 0, bytesPerRow: bytesPerRow, bitsPerPixel: bitsPerPixel)
    }

    /// The image's pixels, drawn into a buffer of 8-bit RGBA, premultiplied.
    @ObjCMethod("initWithCGImage:")
    public required init(cgImage: UnsafeMutableRawPointer?) {
        super.init()
        let width = cgImage.map { CG.ready ? CG.imageGetWidth($0) : 0 } ?? 0
        let height = cgImage.map { CG.ready ? CG.imageGetHeight($0) : 0 } ?? 0
        setUp(planes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: "NSDeviceRGBColorSpace", bitmapFormat: 0, bytesPerRow: width * 4, bitsPerPixel: 32)
        guard let cgImage, width > 0, height > 0, let space = CG.colorSpaceCreateDeviceRGB() else { return }
        defer { CG.release(space) }
        // kCGImageAlphaPremultipliedLast.
        guard let context = CG.bitmapContextCreate(pixels, width, height, 8, width * 4, space, 1) else { return }
        defer { CG.release(context) }
        CG.drawImage(context, CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), cgImage)
    }

    /// An image of the pixels as they are now, +0.
    @ObjCMethod("CGImage")
    func cgImage() -> UnsafeMutableRawPointer? {
        guard CG.ready, let pixels, pixelsWide > 0, pixelsHigh > 0, !planar, bitsPerPixel == 32,
              let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        guard let context = CG.bitmapContextCreate(pixels, pixelsWide, pixelsHigh, 8, bytesPerRow, space, hasAlpha ? 1 : 5) else { return nil }
        defer { CG.release(context) }
        return CG.bitmapContextCreateImage(context).map { ObjCRuntime.autorelease($0)! }
    }

    private func setUp(planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide: Int, pixelsHigh: Int,
                       bitsPerSample: Int, samplesPerPixel: Int, hasAlpha: Bool, isPlanar: Bool,
                       colorSpaceName: String?, bitmapFormat: UInt, bytesPerRow: Int, bitsPerPixel: Int) {
        self.pixelsWide = pixelsWide
        self.pixelsHigh = pixelsHigh
        self.bitsPerSample = bitsPerSample
        self.samplesPerPixel = samplesPerPixel
        self.hasAlpha = hasAlpha
        planar = isPlanar
        format = bitmapFormat
        if let colorSpaceName { colorSpace = colorSpaceName }
        // A planar bitmap has a plane for each sample, whose rows hold that
        // sample alone.
        let pixelBits = isPlanar ? bitsPerSample : bitsPerSample * samplesPerPixel
        self.bitsPerPixel = bitsPerPixel != 0 ? bitsPerPixel : pixelBits
        self.bytesPerRow = bytesPerRow != 0 ? bytesPerRow : (pixelsWide * self.bitsPerPixel + 7) / 8
        size = CGSize(width: CGFloat(pixelsWide), height: CGFloat(pixelsHigh))
        let planeCount = isPlanar ? max(1, min(samplesPerPixel, 5)) : 1
        if let first = planes?.pointee {
            pixels = first
            for index in 0..<planeCount { planePointers[index] = planes?[index] }
        } else {
            // Its own storage: the planes one after another.
            let planeBytes = max(1, self.bytesPerRow * pixelsHigh)
            pixels = calloc(planeBytes * planeCount, 1)?.assumingMemoryBound(to: UInt8.self)
            ownsPixels = true
            for index in 0..<planeCount { planePointers[index] = pixels.map { $0 + index * planeBytes } }
        }
    }

    /// The planes' data: a pointer for each plane, the rest of the five NULL.
    private var planePointers = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: 5)

    @ObjCMethod("getBitmapDataPlanes:")
    func getBitmapDataPlanes(_ data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?) {
        for index in 0..<5 { data?[index] = planePointers[index] }
    }

    deinit { if ownsPixels { free(pixels) } }

    @ObjCMethod("bitmapData") func bitmapData() -> UnsafeMutableRawPointer? { pixels.map(UnsafeMutableRawPointer.init) }
    @ObjCMethod("samplesPerPixel") func repSamplesPerPixel() -> Int { samplesPerPixel }
    @ObjCMethod("bitsPerPixel") func repBitsPerPixel() -> Int { bitsPerPixel }
    @ObjCMethod("bytesPerRow") func repBytesPerRow() -> Int { bytesPerRow }
    @ObjCMethod("bytesPerPlane") func repBytesPerPlane() -> Int { bytesPerRow * pixelsHigh }
    @ObjCMethod("numberOfPlanes") func repNumberOfPlanes() -> Int { planar ? samplesPerPixel : 1 }
    @ObjCMethod("isPlanar") func repIsPlanar() -> Bool { planar }
    @ObjCMethod("bitmapFormat") func repBitmapFormat() -> UInt { format }

    /// A context drawing into the pixels, +1, for the layout CGImage reads:
    /// 8-bit RGBA, premultiplied, in one plane; nil for others.
    func makeContext() -> CGRef? {
        guard CG.ready, let pixels, pixelsWide > 0, pixelsHigh > 0, !planar, bitsPerSample == 8, samplesPerPixel == 4,
              bitsPerPixel == 32, let space = CG.colorSpaceCreateDeviceRGB() else { return nil }
        defer { CG.release(space) }
        return CG.bitmapContextCreate(pixels, pixelsWide, pixelsHigh, 8, bytesPerRow, space, hasAlpha ? 1 : 5)
    }

    /// The pixels as a file of an NSBitmapImageFileType that ImageIO writes:
    /// GIF 2, JPEG 3 or PNG 4 (not TIFF 0 or BMP 1), with JPEG's quality from
    /// NSImageCompressionFactor; nil for the others.
    @ObjCMethod("representationUsingType:properties:")
    func representation(using type: UInt, properties: NSObject?) -> NSObject? {
        let types: [UInt: String] = [2: "com.compuserve.gif", 3: "public.jpeg", 4: "public.png"]
        guard let uti = types[type], let image = cgImage(),
              let data = Classes.named("NSMutableData").flatMap({ Send.object($0.pointer, "data") }) else { return nil }
        var options: UnsafeMutableRawPointer?
        if let properties, let factor = Send.object(properties.objcObject, "objectForKey:", "NSImageCompressionFactor".objCArgument()) {
            options = Send.object(ObjCRuntime.classObject("NSDictionary"), "dictionaryWithObject:forKey:", factor,
                                  "kCGImageDestinationLossyCompressionQuality".objCArgument())
        }
        guard ImageIO.write(image, type: uti, to: data, options: options) else { return nil }
        return NSObject(data)
    }
}

/// ImageIO's destinations, CoreGraphics' provider's.
enum ImageIO {
    private typealias CreateWithData = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias AddImage = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias Finalize = @convention(c) (UnsafeMutableRawPointer?) -> Bool

    private static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let symbol = Symbols.symbol(coreGraphics, "perry_native_" + name) ?? Symbols.symbol(coreGraphics, "_" + name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    /// Writes `image` as a file of the type `type` names into `data`, an
    /// NSMutableData.
    static func write(_ image: CGRef, type: String, to data: UnsafeMutableRawPointer, options: UnsafeMutableRawPointer?) -> Bool {
        guard let create = function("CGImageDestinationCreateWithData", as: CreateWithData.self),
              let add = function("CGImageDestinationAddImage", as: AddImage.self),
              let finalize = function("CGImageDestinationFinalize", as: Finalize.self) else { return false }
        let name = NSObject(objCReturnValue: type.objCReturnValue())
        guard let destination = create(data, name.objcObject, 1, nil) else { return false }
        defer { CG.release(destination) }
        add(destination, image, options)
        return finalize(destination)
    }
}

/// NSCIImageRep: a Core Image image as an image rep. Core Image's classes
/// are QuartzCore's provider's, which renders the image for it.
@ObjCClass("NSCIImageRep")
open class NSCIImageRep: NSImageRep {
    var ciImage: NSObject?

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithCIImage:")
    public required init(ciImage: NSObject?) {
        super.init()
        self.ciImage = ciImage
        hasAlpha = true
        if CG.ready, let image = NSCIImageRep.rendered(ciImage) {
            (pixelsWide, pixelsHigh) = (CG.imageGetWidth(image), CG.imageGetHeight(image))
            size = CGSize(width: CGFloat(pixelsWide), height: CGFloat(pixelsHigh))
        }
    }

    @ObjCClassMethod("imageRepWithCIImage:")
    static func imageRep(ciImage: NSObject?) -> NSCIImageRep { NSCIImageRep(ciImage: ciImage) }

    /// The image rendered whole, +0.
    static func rendered(_ image: NSObject?) -> CGRef? {
        guard let image, Send.responds(image.objcObject, "_perryCGImage") else { return nil }
        return Send.object(image.objcObject, "_perryCGImage")
    }

    @ObjCMethod("CIImage") func image() -> NSObject? { ciImage }
    /// What NSImage draws of it.
    @ObjCMethod("CGImage") func cgImage() -> UnsafeMutableRawPointer? { NSCIImageRep.rendered(ciImage) }

    @ObjCMethod("draw") func draw() -> Bool { draw(in: CGRect(origin: .zero, size: size)) }
    @ObjCMethod("drawAtPoint:") func draw(at point: CGPoint) -> Bool { draw(in: CGRect(origin: point, size: size)) }

    @ObjCMethod("drawInRect:")
    func draw(in rect: CGRect) -> Bool {
        guard let context = NSGraphicsContext.currentCG, let image = NSCIImageRep.rendered(ciImage) else { return false }
        CG.drawImage(context, rect, image)
        return true
    }
}
