import CPerryGeometry
import Glibc
import PerryObjCInterop

// NSImageRep and NSBitmapImageRep: a picture's pixels, kept in memory for the
// program to fill and read. Games make them to hand an image to the window or
// the cursor; nothing here decodes or encodes a file.

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
        self.bitsPerPixel = bitsPerPixel != 0 ? bitsPerPixel : bitsPerSample * samplesPerPixel
        self.bytesPerRow = bytesPerRow != 0 ? bytesPerRow : (pixelsWide * self.bitsPerPixel + 7) / 8
        size = CGSize(width: CGFloat(pixelsWide), height: CGFloat(pixelsHigh))
        if let first = planes?.pointee {
            pixels = first
        } else {
            pixels = calloc(max(1, self.bytesPerRow * pixelsHigh), 1)?.assumingMemoryBound(to: UInt8.self)
            ownsPixels = true
        }
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
}
