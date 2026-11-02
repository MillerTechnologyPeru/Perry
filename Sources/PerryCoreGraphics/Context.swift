import CPerryCoreGraphics
import Glibc
import PerryObjCInterop

// Bitmap contexts: memory the program gives or the context allocates, in
// one of the pixel formats images use. User space has its origin at the
// bottom left, y up; memory rows run from the top. Fills and drawn images
// composite source-over in 8-bit premultiplied color, each source color
// quantized first, as CoreGraphics' bitmap contexts do. Shapes cover whole
// pixels whose centers they contain.

final class GraphicsState {
    var fill = (0.0, 0.0, 0.0, 1.0)
    var stroke = (0.0, 0.0, 0.0, 1.0)
    var alpha = 1.0
    var lineWidth = 1.0
    /// The current transform: x' = a x + c y + tx, y' = b x + d y + ty.
    var ctm = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    var interpolation: Int32 = 0

    func copy() -> GraphicsState {
        let copy = GraphicsState()
        (copy.fill, copy.stroke, copy.alpha, copy.lineWidth, copy.ctm, copy.interpolation) = (fill, stroke, alpha, lineWidth, ctm, interpolation)
        return copy
    }
}

final class ContextState: @unchecked Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let format: PixelFormat
    let space: Ref
    let data: UnsafeMutableRawPointer
    let ownsData: Bool
    var state = GraphicsState()
    var saved: [GraphicsState] = []

    init(width: Int, height: Int, bytesPerRow: Int, format: PixelFormat, space: Ref, data: UnsafeMutableRawPointer, ownsData: Bool) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.format = format
        self.space = ObjCRuntime.retain(space)!
        self.data = data
        self.ownsData = ownsData
    }

    deinit {
        ObjCRuntime.release(space)
        if ownsData { free(data) }
    }

    private func pointer(_ x: Int, _ row: Int) -> UnsafeMutableRawPointer { data + row * bytesPerRow + x * format.bytesPerPixel }

    func read(_ x: Int, _ row: Int) -> (UInt8, UInt8, UInt8, UInt8) { format.read(pointer(x, row)) }
    func write(_ pixel: (UInt8, UInt8, UInt8, UInt8), _ x: Int, _ row: Int) { format.write(pixel, to: pointer(x, row)) }

    /// Source-over: the source is premultiplied.
    func blend(_ source: (UInt8, UInt8, UInt8, UInt8), _ x: Int, _ row: Int) {
        let sa = Int(source.3)
        guard sa > 0 else { return }
        if sa == 255 { return write(source, x, row) }
        let d = read(x, row)
        func over(_ s: UInt8, _ d: UInt8) -> UInt8 { UInt8(min(255, Int(s) + (Int(d) * (255 - sa) + 127) / 255)) }
        write((over(source.0, d.0), over(source.1, d.1), over(source.2, d.2), over(source.3, d.3)), x, row)
    }

    /// A color as a premultiplied 8-bit source.
    func quantize(_ color: (Double, Double, Double, Double)) -> (UInt8, UInt8, UInt8, UInt8) {
        let alpha = max(0, min(1, color.3 * state.alpha))
        let a = (alpha * 255).rounded()
        func c(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (max(0, min(1, v)) * a).rounded()))) }
        return (c(color.0), c(color.1), c(color.2), UInt8(a))
    }

    /// The device-space bounds of a user-space rect.
    func device(_ rect: CGRect) -> CGRect {
        let r = CGRectStandardize(rect)
        let t = state.ctm
        let corners = [(r.origin.x, r.origin.y), (r.origin.x + r.size.width, r.origin.y),
                       (r.origin.x, r.origin.y + r.size.height), (r.origin.x + r.size.width, r.origin.y + r.size.height)]
            .map { (t.a * $0.0 + t.c * $0.1 + t.tx, t.b * $0.0 + t.d * $0.1 + t.ty) }
        let minX = corners.map(\.0).min()!, maxX = corners.map(\.0).max()!
        let minY = corners.map(\.1).min()!, maxY = corners.map(\.1).max()!
        return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
    }

    /// Calls `body` with each pixel (x, memory row) whose center the rect covers.
    func pixels(in rect: CGRect, _ body: (Int, Int) -> Void) {
        let d = device(rect)
        let x0 = max(0, Int((d.origin.x - 0.5).rounded(.up))), x1 = min(width, Int((d.origin.x + d.size.width - 0.5).rounded(.up)))
        let y0 = max(0, Int((d.origin.y - 0.5).rounded(.up))), y1 = min(height, Int((d.origin.y + d.size.height - 0.5).rounded(.up)))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            for x in x0..<x1 { body(x, height - 1 - y) }
        }
    }

    /// The image scaled into the rect, sampled at each covered pixel's center.
    func draw(_ image: Bitmap, in rect: CGRect) {
        let d = device(rect)
        guard d.size.width > 0, d.size.height > 0 else { return }
        let targetWidth = max(1, Int(d.size.width.rounded())), targetHeight = max(1, Int(d.size.height.rounded()))
        let scaled = image.resized(width: targetWidth, height: targetHeight)
        let flippedY = state.ctm.d < 0
        let alpha = max(0, min(1, state.alpha))
        pixels(in: rect) { x, row in
            let deviceY = Double(height - 1 - row) + 0.5
            let u = Int(((Double(x) + 0.5 - d.origin.x) / d.size.width * Double(scaled.width)).rounded(.down))
            var v = Int(((d.origin.y + d.size.height - deviceY) / d.size.height * Double(scaled.height)).rounded(.down))
            if flippedY { v = scaled.height - 1 - v }
            guard u >= 0, u < scaled.width, v >= 0, v < scaled.height else { return }
            var p = scaled.pixel(u, v)
            if alpha < 1 {
                func m(_ c: UInt8) -> UInt8 { UInt8((Double(c) * alpha).rounded()) }
                p = (m(p.0), m(p.1), m(p.2), m(p.3))
            }
            blend(p, x, row)
        }
    }

    /// The contents as premultiplied RGBA.
    var bitmap: Bitmap {
        var bitmap = Bitmap(width: width, height: height)
        for row in 0..<height {
            for x in 0..<width {
                let p = read(x, row), i = (row * width + x) * 4
                (bitmap.pixels[i], bitmap.pixels[i + 1], bitmap.pixels[i + 2], bitmap.pixels[i + 3]) = p
            }
        }
        return bitmap
    }
}

@ObjCClass("CGContext")
public final class CGContextObject: NSObject {
    static let states = StateTable<ContextState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGContextObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGContextObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.context }
}

enum Contexts {
    static func state(_ context: Ref?) -> ContextState? { CGContextObject.states[context] }
}

@c(_CGContextGetTypeID) public func CGContextGetTypeID() -> UInt { TypeIDs.context }

/// With no data, the context allocates zeroed memory; with no row length,
/// rows are padded to 32 bytes.
@c(_CGBitmapContextCreate)
public func CGBitmapContextCreate(_ data: UnsafeMutableRawPointer?, _ width: Int, _ height: Int, _ bitsPerComponent: Int,
                                  _ bytesPerRow: Int, _ space: Ref?, _ bitmapInfo: UInt32) -> Ref? {
    guard width > 0, height > 0, let space, let spaceState = ColorSpaces.state(space) else { return nil }
    let alpha = bitmapInfo & 0x1f
    let channels = spaceState.components + (alpha == 0 ? 0 : 1)
    let format = PixelFormat(bitsPerComponent: bitsPerComponent, bitsPerPixel: channels * bitsPerComponent,
                             colorComponents: spaceState.components, bitmapInfo: bitmapInfo)
    guard bitsPerComponent == 8, format.isSupported, alpha != 3, alpha != 4 else { return nil }
    let minimum = width * format.bytesPerPixel
    let rowBytes = bytesPerRow > 0 ? bytesPerRow : (minimum + 31) / 32 * 32
    guard rowBytes >= minimum else { return nil }
    let memory = data ?? calloc(rowBytes * height, 1)!
    return makeObject(CGContextObject.objCClass, CGContextObject.states,
                      ContextState(width: width, height: height, bytesPerRow: rowBytes, format: format, space: space, data: memory,
                                   ownsData: data == nil))
}

@c(_CGBitmapContextCreateWithData)
public func CGBitmapContextCreateWithData(_ data: UnsafeMutableRawPointer?, _ width: Int, _ height: Int, _ bitsPerComponent: Int,
                                          _ bytesPerRow: Int, _ space: Ref?, _ bitmapInfo: UInt32, _ release: UnsafeRawPointer?,
                                          _ info: UnsafeMutableRawPointer?) -> Ref? {
    CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, space, bitmapInfo)
}

@c(_CGBitmapContextGetData) public func CGBitmapContextGetData(_ context: Ref?) -> UnsafeMutableRawPointer? { Contexts.state(context)?.data }
@c(_CGBitmapContextGetWidth) public func CGBitmapContextGetWidth(_ context: Ref?) -> Int { Contexts.state(context)?.width ?? 0 }
@c(_CGBitmapContextGetHeight) public func CGBitmapContextGetHeight(_ context: Ref?) -> Int { Contexts.state(context)?.height ?? 0 }
@c(_CGBitmapContextGetBytesPerRow) public func CGBitmapContextGetBytesPerRow(_ context: Ref?) -> Int { Contexts.state(context)?.bytesPerRow ?? 0 }
@c(_CGBitmapContextGetBitsPerComponent) public func CGBitmapContextGetBitsPerComponent(_ context: Ref?) -> Int { Contexts.state(context)?.format.bitsPerComponent ?? 0 }
@c(_CGBitmapContextGetBitsPerPixel) public func CGBitmapContextGetBitsPerPixel(_ context: Ref?) -> Int { Contexts.state(context)?.format.bitsPerPixel ?? 0 }
@c(_CGBitmapContextGetColorSpace) public func CGBitmapContextGetColorSpace(_ context: Ref?) -> Ref? { Contexts.state(context)?.space }
@c(_CGBitmapContextGetAlphaInfo) public func CGBitmapContextGetAlphaInfo(_ context: Ref?) -> UInt32 { Contexts.state(context)?.format.alphaInfo ?? 0 }
@c(_CGBitmapContextGetBitmapInfo) public func CGBitmapContextGetBitmapInfo(_ context: Ref?) -> UInt32 { Contexts.state(context)?.format.bitmapInfo ?? 0 }

/// A copy of the contents, in the context's format.
@c(_CGBitmapContextCreateImage)
public func CGBitmapContextCreateImage(_ context: Ref?) -> Ref? {
    guard let state = Contexts.state(context) else { return nil }
    let bytes = Array(UnsafeRawBufferPointer(start: state.data, count: state.bytesPerRow * state.height))
    let provider = DataProviders.make(bytes)
    defer { ObjCRuntime.release(provider) }
    return makeObject(CGImageObject.objCClass, CGImageObject.states,
                      ImageState(width: state.width, height: state.height, format: state.format, bytesPerRow: state.bytesPerRow,
                                 space: state.space, provider: provider))
}

@c(_CGContextRetain) public func CGContextRetain(_ context: Ref?) -> Ref? { ObjCRuntime.retain(context) }
@c(_CGContextRelease) public func CGContextRelease(_ context: Ref?) { ObjCRuntime.release(context) }
@c(_CGContextFlush) public func CGContextFlush(_ context: Ref?) {}
@c(_CGContextSynchronize) public func CGContextSynchronize(_ context: Ref?) {}

// MARK: Graphics state

@c(_CGContextSaveGState)
public func CGContextSaveGState(_ context: Ref?) {
    guard let state = Contexts.state(context) else { return }
    state.saved.append(state.state.copy())
}

@c(_CGContextRestoreGState)
public func CGContextRestoreGState(_ context: Ref?) {
    guard let state = Contexts.state(context), let previous = state.saved.popLast() else { return }
    state.state = previous
}

@c(_CGContextSetRGBFillColor)
public func CGContextSetRGBFillColor(_ context: Ref?, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
    Contexts.state(context)?.state.fill = (r, g, b, a)
}

@c(_CGContextSetRGBStrokeColor)
public func CGContextSetRGBStrokeColor(_ context: Ref?, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
    Contexts.state(context)?.state.stroke = (r, g, b, a)
}

@c(_CGContextSetGrayFillColor)
public func CGContextSetGrayFillColor(_ context: Ref?, _ gray: Double, _ a: Double) { Contexts.state(context)?.state.fill = (gray, gray, gray, a) }

@c(_CGContextSetGrayStrokeColor)
public func CGContextSetGrayStrokeColor(_ context: Ref?, _ gray: Double, _ a: Double) { Contexts.state(context)?.state.stroke = (gray, gray, gray, a) }

@c(_CGContextSetFillColorWithColor)
public func CGContextSetFillColorWithColor(_ context: Ref?, _ color: Ref?) {
    guard let color = Colors.state(color) else { return }
    Contexts.state(context)?.state.fill = color.rgba
}

@c(_CGContextSetStrokeColorWithColor)
public func CGContextSetStrokeColorWithColor(_ context: Ref?, _ color: Ref?) {
    guard let color = Colors.state(color) else { return }
    Contexts.state(context)?.state.stroke = color.rgba
}

@c(_CGContextSetAlpha) public func CGContextSetAlpha(_ context: Ref?, _ alpha: Double) { Contexts.state(context)?.state.alpha = alpha }
@c(_CGContextSetLineWidth) public func CGContextSetLineWidth(_ context: Ref?, _ width: Double) { Contexts.state(context)?.state.lineWidth = width }

@c(_CGContextSetInterpolationQuality)
public func CGContextSetInterpolationQuality(_ context: Ref?, _ quality: Int32) { Contexts.state(context)?.state.interpolation = quality }

@c(_CGContextGetInterpolationQuality)
public func CGContextGetInterpolationQuality(_ context: Ref?) -> Int32 { Contexts.state(context)?.state.interpolation ?? 0 }

@c(_CGContextSetShouldAntialias) public func CGContextSetShouldAntialias(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetAllowsAntialiasing) public func CGContextSetAllowsAntialiasing(_ context: Ref?, _ value: Bool) {}

// MARK: Transforms

private func concat(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> CGAffineTransform {
    CGAffineTransform(a: t1.a * t2.a + t1.b * t2.c, b: t1.a * t2.b + t1.b * t2.d, c: t1.c * t2.a + t1.d * t2.c,
                      d: t1.c * t2.b + t1.d * t2.d, tx: t1.tx * t2.a + t1.ty * t2.c + t2.tx, ty: t1.tx * t2.b + t1.ty * t2.d + t2.ty)
}

@c(_CGContextConcatCTM)
public func CGContextConcatCTM(_ context: Ref?, _ transform: CGAffineTransform) {
    guard let state = Contexts.state(context) else { return }
    state.state.ctm = concat(transform, state.state.ctm)
}

@c(_CGContextTranslateCTM)
public func CGContextTranslateCTM(_ context: Ref?, _ tx: Double, _ ty: Double) {
    CGContextConcatCTM(context, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty))
}

@c(_CGContextScaleCTM)
public func CGContextScaleCTM(_ context: Ref?, _ sx: Double, _ sy: Double) {
    CGContextConcatCTM(context, CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0))
}

@c(_CGContextRotateCTM)
public func CGContextRotateCTM(_ context: Ref?, _ angle: Double) {
    CGContextConcatCTM(context, CGAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0))
}

@c(_CGContextGetCTM)
public func CGContextGetCTM(_ context: Ref?) -> CGAffineTransform {
    Contexts.state(context)?.state.ctm ?? CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

// MARK: Drawing

@c(_CGContextFillRect)
public func CGContextFillRect(_ context: Ref?, _ rect: CGRect) {
    guard let state = Contexts.state(context) else { return }
    let source = state.quantize(state.state.fill)
    state.pixels(in: rect) { x, row in state.blend(source, x, row) }
}

@c(_CGContextFillRects)
public func CGContextFillRects(_ context: Ref?, _ rects: UnsafePointer<CGRect>?, _ count: Int) {
    for index in 0..<count { CGContextFillRect(context, rects![index]) }
}

@c(_CGContextClearRect)
public func CGContextClearRect(_ context: Ref?, _ rect: CGRect) {
    guard let state = Contexts.state(context) else { return }
    state.pixels(in: rect) { x, row in state.write((0, 0, 0, 0), x, row) }
}

/// A rect's outline, as four filled bands of the line width.
@c(_CGContextStrokeRect)
public func CGContextStrokeRect(_ context: Ref?, _ rect: CGRect) {
    guard let state = Contexts.state(context) else { return }
    let r = CGRectStandardize(rect), w = state.state.lineWidth, h = w / 2
    let fill = state.state.fill
    state.state.fill = state.state.stroke
    for band in [CGRect(origin: CGPoint(x: r.origin.x - h, y: r.origin.y - h), size: CGSize(width: r.size.width + w, height: w)),
                 CGRect(origin: CGPoint(x: r.origin.x - h, y: r.origin.y + r.size.height - h), size: CGSize(width: r.size.width + w, height: w)),
                 CGRect(origin: CGPoint(x: r.origin.x - h, y: r.origin.y + h), size: CGSize(width: w, height: r.size.height - w)),
                 CGRect(origin: CGPoint(x: r.origin.x + r.size.width - h, y: r.origin.y + h), size: CGSize(width: w, height: r.size.height - w))] {
        CGContextFillRect(context, band)
    }
    state.state.fill = fill
}

@c(_CGContextDrawImage)
public func CGContextDrawImage(_ context: Ref?, _ rect: CGRect, _ image: Ref?) {
    guard let state = Contexts.state(context), let image = Images.state(image) else { return }
    state.draw(image.bitmap, in: rect)
}
