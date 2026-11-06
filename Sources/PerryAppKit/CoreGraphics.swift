import CPerryGeometry
import PerryObjCInterop

// CoreGraphics' C API, which AppKit draws views, cells and text with as
// Darwin's AppKit does. The functions are the CoreGraphics provider's,
// bound through the loader the first time AppKit draws: an app that never
// draws doesn't need libPerryCoreGraphics.

typealias CGRef = UnsafeMutableRawPointer

private let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

enum CG {
    typealias Ref = CGRef?
    typealias Transform = UnsafePointer<CGAffineTransform>?

    nonisolated(unsafe) static var colorSpaceCreateDeviceRGB: (@convention(c) () -> Ref)!
    nonisolated(unsafe) static var colorCreateSRGB: (@convention(c) (CGFloat, CGFloat, CGFloat, CGFloat) -> Ref)!
    nonisolated(unsafe) static var colorGetNumberOfComponents: (@convention(c) (Ref) -> Int)!
    nonisolated(unsafe) static var colorGetComponents: (@convention(c) (Ref) -> UnsafePointer<CGFloat>?)!

    nonisolated(unsafe) static var bitmapContextCreate: (@convention(c) (UnsafeMutableRawPointer?, Int, Int, Int, Int, Ref, UInt32) -> Ref)!
    nonisolated(unsafe) static var bitmapContextCreateImage: (@convention(c) (Ref) -> Ref)!
    nonisolated(unsafe) static var saveGState: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var restoreGState: (@convention(c) (Ref) -> Void)!
    nonisolated(unsafe) static var translateCTM: (@convention(c) (Ref, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var scaleCTM: (@convention(c) (Ref, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var concatCTM: (@convention(c) (Ref, CGAffineTransform) -> Void)!
    nonisolated(unsafe) static var setFillColorWithColor: (@convention(c) (Ref, Ref) -> Void)!
    nonisolated(unsafe) static var setStrokeColorWithColor: (@convention(c) (Ref, Ref) -> Void)!
    nonisolated(unsafe) static var setAlpha: (@convention(c) (Ref, CGFloat) -> Void)!
    nonisolated(unsafe) static var setLineWidth: (@convention(c) (Ref, CGFloat) -> Void)!
    nonisolated(unsafe) static var setLineCap: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var setLineJoin: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var setLineDash: (@convention(c) (Ref, CGFloat, UnsafePointer<CGFloat>?, Int) -> Void)!
    nonisolated(unsafe) static var setShouldAntialias: (@convention(c) (Ref, Bool) -> Void)!
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
    nonisolated(unsafe) static var selectFont: (@convention(c) (Ref, UnsafePointer<CChar>?, CGFloat, Int32) -> Void)!
    nonisolated(unsafe) static var setTextPosition: (@convention(c) (Ref, CGFloat, CGFloat) -> Void)!
    nonisolated(unsafe) static var getTextPosition: (@convention(c) (Ref) -> CGPoint)!
    nonisolated(unsafe) static var setTextMatrix: (@convention(c) (Ref, CGAffineTransform) -> Void)!
    nonisolated(unsafe) static var setTextDrawingMode: (@convention(c) (Ref, Int32) -> Void)!
    nonisolated(unsafe) static var showText: (@convention(c) (Ref, UnsafePointer<CChar>?, Int) -> Void)!

    nonisolated(unsafe) static var pathCreateMutable: (@convention(c) () -> Ref)!
    nonisolated(unsafe) static var pathCreateMutableCopy: (@convention(c) (Ref) -> Ref)!
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
    nonisolated(unsafe) static var pathGetBoundingBox: (@convention(c) (Ref) -> CGRect)!
    nonisolated(unsafe) static var pathContainsPoint: (@convention(c) (Ref, Transform, CGPoint, Bool) -> Bool)!

    nonisolated(unsafe) static var imageGetWidth: (@convention(c) (Ref) -> Int)!
    nonisolated(unsafe) static var imageGetHeight: (@convention(c) (Ref) -> Int)!
    nonisolated(unsafe) static var imageSourceCreateWithData: (@convention(c) (Ref, Ref) -> Ref)!
    nonisolated(unsafe) static var imageSourceCreateImageAtIndex: (@convention(c) (Ref, Int, Ref) -> Ref)!

    nonisolated(unsafe) private static var state: Bool?

    /// Whether CoreGraphics' functions are bound: the first time it is
    /// asked, they are looked up.
    static var ready: Bool {
        if let state { return state }
        let loaded = load()
        state = loaded
        if !loaded { appKitWarning("libPerryCoreGraphics is missing or incomplete: views draw nothing") }
        return loaded
    }

    private static func load() -> Bool {
        var complete = true
        func bind<T>(_ name: String) -> T? {
            // Its native export when it has one: @DarwinC's under the Darwin
            // name takes Darwin's calling convention.
            guard let symbol = Symbols.symbol(coreGraphics, "perry_native_" + name) ?? Symbols.symbol(coreGraphics, "_" + name) else {
                complete = false
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        colorSpaceCreateDeviceRGB = bind("CGColorSpaceCreateDeviceRGB")
        colorCreateSRGB = bind("CGColorCreateSRGB")
        colorGetNumberOfComponents = bind("CGColorGetNumberOfComponents")
        colorGetComponents = bind("CGColorGetComponents")
        bitmapContextCreate = bind("CGBitmapContextCreate")
        bitmapContextCreateImage = bind("CGBitmapContextCreateImage")
        saveGState = bind("CGContextSaveGState")
        restoreGState = bind("CGContextRestoreGState")
        translateCTM = bind("CGContextTranslateCTM")
        scaleCTM = bind("CGContextScaleCTM")
        concatCTM = bind("CGContextConcatCTM")
        setFillColorWithColor = bind("CGContextSetFillColorWithColor")
        setStrokeColorWithColor = bind("CGContextSetStrokeColorWithColor")
        setAlpha = bind("CGContextSetAlpha")
        setLineWidth = bind("CGContextSetLineWidth")
        setLineCap = bind("CGContextSetLineCap")
        setLineJoin = bind("CGContextSetLineJoin")
        setLineDash = bind("CGContextSetLineDash")
        setShouldAntialias = bind("CGContextSetShouldAntialias")
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
        selectFont = bind("CGContextSelectFont")
        setTextPosition = bind("CGContextSetTextPosition")
        getTextPosition = bind("CGContextGetTextPosition")
        setTextMatrix = bind("CGContextSetTextMatrix")
        setTextDrawingMode = bind("CGContextSetTextDrawingMode")
        showText = bind("CGContextShowText")
        pathCreateMutable = bind("CGPathCreateMutable")
        pathCreateMutableCopy = bind("CGPathCreateMutableCopy")
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
        pathGetBoundingBox = bind("CGPathGetPathBoundingBox")
        pathContainsPoint = bind("CGPathContainsPoint")
        imageGetWidth = bind("CGImageGetWidth")
        imageGetHeight = bind("CGImageGetHeight")
        imageSourceCreateWithData = bind("CGImageSourceCreateWithData")
        imageSourceCreateImageAtIndex = bind("CGImageSourceCreateImageAtIndex")
        return complete
    }

    /// Releases a CoreGraphics object, which is an Objective-C object.
    static func release(_ object: Ref) { ObjCRuntime.release(object) }

    /// A bitmap context for `size` points at `scale` pixels per point, in
    /// AppKit's coordinates: the origin at the bottom left, y upwards.
    static func makeContext(size: CGSize, scale: CGFloat) -> CGRef? {
        guard ready else { return nil }
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = colorSpaceCreateDeviceRGB() else { return nil }
        defer { release(space) }
        // Premultiplied alpha first in 32-bit little-endian words.
        guard let context = bitmapContextCreate(nil, width, height, 8, width * 4, space, 2 | 0x2000) else { return nil }
        scaleCTM(context, scale, scale)
        return context
    }

    /// A path through `points`, closed.
    static func polygon(_ points: [CGPoint]) -> CGRef? {
        guard ready, let first = points.first, let path = pathCreateMutable() else { return nil }
        pathMoveToPoint(path, nil, first.x, first.y)
        for point in points.dropFirst() { pathAddLineToPoint(path, nil, point.x, point.y) }
        pathCloseSubpath(path)
        return path
    }

    /// A rectangle with rounded corners.
    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGRef? {
        guard ready, let path = pathCreateMutable() else { return nil }
        let radius = max(0, min(radius, rect.width / 2, rect.height / 2))
        pathAddRoundedRect(path, nil, rect, radius, radius)
        return path
    }

    /// Fills `path` in `color`, and releases it.
    static func fill(_ path: CGRef?, _ color: NSColor, in context: CGRef) {
        guard let path else { return }
        saveGState(context)
        setFillColorWithColor(context, color.cgColorRef)
        addPath(context, path)
        fillPath(context)
        restoreGState(context)
        release(path)
    }

    /// Strokes `path` in `color`, and releases it.
    static func stroke(_ path: CGRef?, _ color: NSColor, width: CGFloat = 1, in context: CGRef) {
        guard let path else { return }
        saveGState(context)
        setStrokeColorWithColor(context, color.cgColorRef)
        setLineWidth(context, width)
        addPath(context, path)
        strokePath(context)
        restoreGState(context)
        release(path)
    }
}
