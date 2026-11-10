import CPerryGeometry
import PerryObjCInterop

// CoreGraphics' C API, which UIKit draws with as Darwin's UIKit does. The
// functions are the CoreGraphics provider's (with ImageIO's), bound
// through the loader when UIKit starts.

/// A CoreGraphics object: a context, color, path, image and so on.
typealias CGRef = UnsafeMutableRawPointer

private let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

enum CG {
    typealias Ref = CGRef?
    typealias Transform = UnsafePointer<CGAffineTransform>?

    nonisolated(unsafe) static var colorSpaceCreateDeviceRGB: (@convention(c) () -> Ref)!
    nonisolated(unsafe) static var colorCreateSRGB: (@convention(c) (CGFloat, CGFloat, CGFloat, CGFloat) -> Ref)!
    nonisolated(unsafe) static var colorCreateGenericGray: (@convention(c) (CGFloat, CGFloat) -> Ref)!
    nonisolated(unsafe) static var colorGetNumberOfComponents: (@convention(c) (Ref) -> Int)!
    nonisolated(unsafe) static var colorGetComponents: (@convention(c) (Ref) -> UnsafePointer<CGFloat>?)!

    nonisolated(unsafe) static var bitmapContextCreate: (@convention(c) (UnsafeMutableRawPointer?, Int, Int, Int, Int, Ref, UInt32) -> Ref)!
    nonisolated(unsafe) static var bitmapContextCreateImage: (@convention(c) (Ref) -> Ref)!
    nonisolated(unsafe) static var bitmapContextGetData: (@convention(c) (Ref) -> UnsafeMutableRawPointer?)!
    nonisolated(unsafe) static var saveGState: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var restoreGState: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var translateCTM: (@convention(c) (Ref, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var scaleCTM: (@convention(c) (Ref, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var concatCTM: (@convention(c) (Ref, CGAffineTransform) -> Void)!
    nonisolated(unsafe) static var setFillColorWithColor: (@convention(c) (Ref, Ref) -> Void)!
    nonisolated(unsafe) static var setStrokeColorWithColor: (@convention(c) (Ref, Ref) -> Void)!
    nonisolated(unsafe) static var setAlpha: (@convention(c) (Ref, CGFloat) -> Void)!
    nonisolated(unsafe) static var setBlendMode: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var setLineWidth: (@convention(c) (Ref, CGFloat) -> Void)!
    nonisolated(unsafe) static var setLineCap: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var setLineJoin: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var setMiterLimit: (@convention(c) (Ref, CGFloat) -> Void)!
    nonisolated(unsafe) static var setLineDash: (@convention(c) (Ref, CGFloat, UnsafePointer<CGFloat>?, Int) -> Void)!
    nonisolated(unsafe) static var addPath: (@convention(c) (Ref, Ref) -> Void)!
    nonisolated(unsafe) static var fillPath: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var eoFillPath: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var strokePath: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var clip: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var eoClip: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var clipToRect: (@convention(c) (Ref, CGRect) -> Void)!
    nonisolated(unsafe) static var fillRect: (@convention(c) (Ref, CGRect) -> Void)!
    nonisolated(unsafe) static var strokeRect: (@convention(c) (Ref, CGRect) -> Void)!
    nonisolated(unsafe) static var drawImage: (@convention(c) (Ref, CGRect, Ref) -> Void)!
    nonisolated(unsafe) static var beginTransparencyLayer: (@convention(c) (Ref, Ref) -> Void)!
    nonisolated(unsafe) static var endTransparencyLayer: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var selectFont: (@convention(c) (Ref, UnsafePointer<CChar>?, CGFloat, Int32) -> Void)!
    nonisolated(unsafe) static var setTextPosition: (@convention(c) (Ref, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var getTextPosition: (@convention(c) (Ref) -> CGPoint)!
    nonisolated(unsafe) static var setTextMatrix: (@convention(c) (Ref, CGAffineTransform) -> Void)!
    nonisolated(unsafe) static var setTextDrawingMode: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var showText: (@convention(c) (Ref, UnsafePointer<CChar>?, Int) -> Void)!

    nonisolated(unsafe) static var pathCreateMutable: (@convention(c) () -> Ref)!
    nonisolated(unsafe) static var pathCreateMutableCopy: (@convention(c) (Ref) -> Ref)!
    nonisolated(unsafe) static var pathCreateCopyByTransformingPath: (@convention(c) (Ref, Transform) -> Ref)!
    nonisolated(unsafe) static var pathMoveToPoint: (@convention(c) (Ref, Transform, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var pathAddLineToPoint: (@convention(c) (Ref, Transform, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var pathAddCurveToPoint: (@convention(c) (Ref, Transform, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var pathAddQuadCurveToPoint: (@convention(c) (Ref, Transform, CGFloat, CGFloat, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var pathCloseSubpath: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var pathAddRect: (@convention(c) (Ref, Transform, CGRect) -> Void)!
    nonisolated(unsafe) static var pathAddEllipseInRect: (@convention(c) (Ref, Transform, CGRect) -> Void)!
    nonisolated(unsafe) static var pathAddRoundedRect: (@convention(c) (Ref, Transform, CGRect, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var pathAddArc: (@convention(c) (Ref, Transform, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool) -> Void)!
    nonisolated(unsafe) static var pathAddPath: (@convention(c) (Ref, Transform, Ref) -> Void)!
    nonisolated(unsafe) static var pathIsEmpty: (@convention(c) (Ref) -> Bool)!
    nonisolated(unsafe) static var pathGetCurrentPoint: (@convention(c) (Ref) -> CGPoint)!
    nonisolated(unsafe) static var pathApply: (@convention(c) (Ref, UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void)?) -> Void)!
    nonisolated(unsafe) static var pathGetBoundingBox: (@convention(c) (Ref) -> CGRect)!
    nonisolated(unsafe) static var pathContainsPoint: (@convention(c) (Ref, Transform, CGPoint, Bool) -> Bool)!

    nonisolated(unsafe) static var imageGetWidth: (@convention(c) (Ref) -> Int)!
    nonisolated(unsafe) static var imageGetHeight: (@convention(c) (Ref) -> Int)!
    nonisolated(unsafe) static var imageSourceCreateWithData: (@convention(c) (Ref, Ref) -> Ref)!
    nonisolated(unsafe) static var imageSourceCreateImageAtIndex: (@convention(c) (Ref, Int, Ref) -> Ref)!
    nonisolated(unsafe) static var imageDestinationCreateWithData: (@convention(c) (Ref, Ref, Int, Ref) -> Ref)!
    nonisolated(unsafe) static var imageDestinationAddImage: (@convention(c) (Ref, Ref, Ref) -> Void)!
    nonisolated(unsafe) static var imageDestinationFinalize: (@convention(c) (Ref) -> Bool)!

    nonisolated(unsafe) static var dataProviderCreateWithURL: (@convention(c) (Ref) -> Ref)!
    nonisolated(unsafe) static var fontCreateWithDataProvider: (@convention(c) (Ref) -> Ref)!
    nonisolated(unsafe) static var fontRelease: (@convention(c) (Ref) -> Void)!
    /// Adds a font made from data to FontConfig's fonts (libPerryCoreGraphics).
    nonisolated(unsafe) static var fontRegister: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    nonisolated(unsafe) static var dataProviderRelease: (@convention(c) (Ref) -> Void)!

    /// Binds the functions through `lookup`; false if one is missing.
    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) -> Bool {
        var complete = true
        func bind<T>(_ name: String) -> T? {
            // Its native export when it has one: @DarwinC's under the Darwin
            // name takes Darwin's calling convention.
            guard let symbol = lookup(coreGraphics, "perry_native_" + name) ?? lookup(coreGraphics, "_" + name) else {
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        colorSpaceCreateDeviceRGB = bind("CGColorSpaceCreateDeviceRGB")
        colorCreateSRGB = bind("CGColorCreateSRGB")
        colorCreateGenericGray = bind("CGColorCreateGenericGray")
        colorGetNumberOfComponents = bind("CGColorGetNumberOfComponents")
        colorGetComponents = bind("CGColorGetComponents")
        bitmapContextCreate = bind("CGBitmapContextCreate")
        bitmapContextCreateImage = bind("CGBitmapContextCreateImage")
        bitmapContextGetData = bind("CGBitmapContextGetData")
        saveGState = bind("CGContextSaveGState")
        restoreGState = bind("CGContextRestoreGState")
        translateCTM = bind("CGContextTranslateCTM")
        scaleCTM = bind("CGContextScaleCTM")
        concatCTM = bind("CGContextConcatCTM")
        setFillColorWithColor = bind("CGContextSetFillColorWithColor")
        setStrokeColorWithColor = bind("CGContextSetStrokeColorWithColor")
        setAlpha = bind("CGContextSetAlpha")
        setBlendMode = bind("CGContextSetBlendMode")
        setLineWidth = bind("CGContextSetLineWidth")
        setLineCap = bind("CGContextSetLineCap")
        setLineJoin = bind("CGContextSetLineJoin")
        setMiterLimit = bind("CGContextSetMiterLimit")
        setLineDash = bind("CGContextSetLineDash")
        addPath = bind("CGContextAddPath")
        fillPath = bind("CGContextFillPath")
        eoFillPath = bind("CGContextEOFillPath")
        strokePath = bind("CGContextStrokePath")
        clip = bind("CGContextClip")
        eoClip = bind("CGContextEOClip")
        clipToRect = bind("CGContextClipToRect")
        fillRect = bind("CGContextFillRect")
        strokeRect = bind("CGContextStrokeRect")
        drawImage = bind("CGContextDrawImage")
        beginTransparencyLayer = bind("CGContextBeginTransparencyLayer")
        endTransparencyLayer = bind("CGContextEndTransparencyLayer")
        selectFont = bind("CGContextSelectFont")
        setTextPosition = bind("CGContextSetTextPosition")
        getTextPosition = bind("CGContextGetTextPosition")
        setTextMatrix = bind("CGContextSetTextMatrix")
        setTextDrawingMode = bind("CGContextSetTextDrawingMode")
        showText = bind("CGContextShowText")
        pathCreateMutable = bind("CGPathCreateMutable")
        pathCreateMutableCopy = bind("CGPathCreateMutableCopy")
        pathCreateCopyByTransformingPath = bind("CGPathCreateCopyByTransformingPath")
        pathMoveToPoint = bind("CGPathMoveToPoint")
        pathAddLineToPoint = bind("CGPathAddLineToPoint")
        pathAddCurveToPoint = bind("CGPathAddCurveToPoint")
        pathAddQuadCurveToPoint = bind("CGPathAddQuadCurveToPoint")
        pathCloseSubpath = bind("CGPathCloseSubpath")
        pathAddRect = bind("CGPathAddRect")
        pathAddEllipseInRect = bind("CGPathAddEllipseInRect")
        pathAddRoundedRect = bind("CGPathAddRoundedRect")
        pathAddArc = bind("CGPathAddArc")
        pathAddPath = bind("CGPathAddPath")
        pathIsEmpty = bind("CGPathIsEmpty")
        pathGetCurrentPoint = bind("CGPathGetCurrentPoint")
        pathApply = bind("CGPathApply")
        pathGetBoundingBox = bind("CGPathGetPathBoundingBox")
        pathContainsPoint = bind("CGPathContainsPoint")
        imageGetWidth = bind("CGImageGetWidth")
        imageGetHeight = bind("CGImageGetHeight")
        imageSourceCreateWithData = bind("CGImageSourceCreateWithData")
        imageSourceCreateImageAtIndex = bind("CGImageSourceCreateImageAtIndex")
        imageDestinationCreateWithData = bind("CGImageDestinationCreateWithData")
        imageDestinationAddImage = bind("CGImageDestinationAddImage")
        imageDestinationFinalize = bind("CGImageDestinationFinalize")
        dataProviderCreateWithURL = bind("CGDataProviderCreateWithURL")
        fontCreateWithDataProvider = bind("CGFontCreateWithDataProvider")
        fontRelease = bind("CGFontRelease")
        fontRegister = lookup(coreGraphics, "_perry_cgfont_register").map { unsafeBitCast($0, to: (@convention(c) (UnsafeMutableRawPointer?) -> Bool).self) }
        CTFonts.load { lookup(coreGraphics, $0) }
        dataProviderRelease = bind("CGDataProviderRelease")
        return complete
    }

    /// Releases a CoreGraphics object, which is an Objective-C object.
    static func release(_ object: Ref) { ObjCRuntime.release(object) }

    /// UIKit's pixel format: premultiplied alpha first in 32-bit
    /// little-endian words (BGRA in memory), or no alpha when opaque.
    static func bitmapInfo(opaque: Bool) -> UInt32 { (opaque ? 6 : 2) | 0x2000 }

    /// A bitmap context for `size` points at `scale` pixels per point, in
    /// UIKit's coordinates: the origin at the top left, y downwards.
    static func makeContext(size: CGSize, scale: CGFloat, opaque: Bool) -> CGRef? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = colorSpaceCreateDeviceRGB() else { return nil }
        defer { release(space) }
        guard let context = bitmapContextCreate(nil, width, height, 8, width * 4, space, bitmapInfo(opaque: opaque)) else {
            return nil
        }
        translateCTM(context, 0, CGFloat(height))
        scaleCTM(context, scale, -scale)
        return context
    }

    /// Draws `image` upright in `rect`, in a context whose y axis points
    /// down.
    static func drawFlipped(_ image: CGRef, in rect: CGRect, context: CGRef) {
        saveGState(context)
        translateCTM(context, rect.origin.x, rect.origin.y + rect.size.height)
        scaleCTM(context, 1, -1)
        drawImage(context, CGRect(x: 0, y: 0, width: rect.size.width, height: rect.size.height), image)
        restoreGState(context)
    }
}
