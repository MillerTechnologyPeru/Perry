import CPerryCoreGraphics
import Glibc
import PerryObjCInterop

// Bitmap contexts, paths and gradients. A context's drawing goes through
// Silica's Cairo renderer (Rendering.swift). Memory already in Cairo's
// layout (premultiplied ARGB in 32-bit little-endian words, which is
// kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, UIKit's
// format) is drawn into directly; any other format is kept in step with a
// Cairo surface: before each painting operation the rows of memory the
// program has changed since the last are copied into the surface, and
// after it the rows the painting changed are copied back. A copy of the
// memory as it was last in step tells which rows those are.

final class ContextState: @unchecked Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let format: PixelFormat
    let space: Ref
    let data: UnsafeMutableRawPointer
    let ownsData: Bool
    let canvas: Canvas
    /// Whether the canvas draws into `data` itself.
    let direct: Bool
    /// The layouts whose rows are converted a word at a time.
    private enum Layout { case rgba, argb, alphaOnly, gray, other }
    private let layout: Layout
    /// The memory as it was when it and the canvas were last in step; made
    /// at the first painting.
    private var mirror: UnsafeMutableRawPointer?
    /// A row of memory, to compare with the mirror's.
    private var scratch: UnsafeMutableRawPointer?

    init?(width: Int, height: Int, bytesPerRow: Int, format: PixelFormat, space: Ref, data: UnsafeMutableRawPointer, ownsData: Bool) {
        let cairoLayout = format.bitsPerComponent == 8 && format.colorComponents == 3 && format.byteOrder == 0x2000
            && (format.alphaInfo == 2 || format.alphaInfo == 6) && bytesPerRow == width * 4
        let canvas = cairoLayout
            ? Canvas(width: width, height: height, memory: data.assumingMemoryBound(to: UInt8.self), bytesPerRow: bytesPerRow,
                     opaque: format.alphaInfo == 6)
            : Canvas(width: width, height: height)
        guard let canvas else { return nil }
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.format = format
        self.space = ObjCRuntime.retain(space)!
        self.data = data
        self.ownsData = ownsData
        self.canvas = canvas
        direct = cairoLayout
        // Bytes in the order named (kCGBitmapByteOrderDefault or 32Big).
        let natural = format.byteOrder == 0 || format.byteOrder == 0x4000
        if format.bitsPerComponent == 8, format.colorComponents == 3, format.bitsPerPixel == 32, natural {
            layout = [1, 5].contains(format.alphaInfo) ? .rgba : [2, 6].contains(format.alphaInfo) ? .argb : .other
        } else if format.bitsPerComponent == 8, format.bitsPerPixel == 8, format.alphaInfo == 7 {
            layout = .alphaOnly
        } else if format.bitsPerComponent == 8, format.bitsPerPixel == 8, format.colorComponents == 1, format.alphaInfo == 0 {
            layout = .gray
        } else {
            layout = .other
        }
    }

    deinit {
        ObjCRuntime.release(space)
        if ownsData { free(data) }
        free(mirror)
        free(scratch)
    }

    /// Runs a painting operation, with the memory and the canvas in step.
    func paint(_ body: (Canvas) -> Void) {
        if direct {
            canvas.context.markDirty()
            body(canvas)
            canvas.context.flush()
            return
        }
        load()
        body(canvas)
        store()
    }

    /// A row of memory as a row of the canvas: B, G, R, A, premultiplied.
    private func convert(row source: UnsafeRawPointer, to pixels: UnsafeMutableRawPointer) {
        let opaque: UInt32 = format.alphaInfo == 5 || format.alphaInfo == 6 ? 0xFF00_0000 : 0
        switch layout {
        case .rgba:
            // R, G, B, A in memory is A, B, G, R in the word: red and blue
            // change places.
            for x in 0..<width {
                let v = source.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self)
                pixels.storeBytes(of: (v & 0xFF00_FF00) | ((v & 0xFF) << 16) | ((v >> 16) & 0xFF) | opaque, toByteOffset: x * 4, as: UInt32.self)
            }
        case .argb:
            for x in 0..<width {
                let v = source.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self)
                pixels.storeBytes(of: v.byteSwapped | opaque, toByteOffset: x * 4, as: UInt32.self)
            }
        case .alphaOnly:
            for x in 0..<width {
                pixels.storeBytes(of: UInt32(source.load(fromByteOffset: x, as: UInt8.self)) << 24, toByteOffset: x * 4, as: UInt32.self)
            }
        case .gray:
            for x in 0..<width {
                let y = UInt32(source.load(fromByteOffset: x, as: UInt8.self))
                pixels.storeBytes(of: 0xFF00_0000 | y << 16 | y << 8 | y, toByteOffset: x * 4, as: UInt32.self)
            }
        case .other:
            let p = pixels.assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let (r, g, b, a) = format.read(source + x * format.bytesPerPixel)
                (p[x * 4], p[x * 4 + 1], p[x * 4 + 2], p[x * 4 + 3]) = (b, g, r, a)
            }
        }
    }

    /// A row of the canvas as a row of memory.
    private func convert(row pixels: UnsafeRawPointer, toMemory target: UnsafeMutableRawPointer) {
        let opaque: UInt32 = format.alphaInfo == 5 || format.alphaInfo == 6 ? 0xFF00_0000 : 0
        switch layout {
        case .rgba:
            for x in 0..<width {
                let v = pixels.load(fromByteOffset: x * 4, as: UInt32.self)
                target.storeBytes(of: (v & 0xFF00_FF00) | ((v & 0xFF) << 16) | ((v >> 16) & 0xFF) | opaque, toByteOffset: x * 4, as: UInt32.self)
            }
        case .argb:
            for x in 0..<width {
                let v = pixels.load(fromByteOffset: x * 4, as: UInt32.self) | opaque
                target.storeBytes(of: v.byteSwapped, toByteOffset: x * 4, as: UInt32.self)
            }
        case .alphaOnly:
            for x in 0..<width {
                target.storeBytes(of: UInt8(pixels.load(fromByteOffset: x * 4, as: UInt32.self) >> 24), toByteOffset: x, as: UInt8.self)
            }
        case .gray:
            for x in 0..<width {
                let v = pixels.load(fromByteOffset: x * 4, as: UInt32.self)
                let (r, g, b) = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                target.storeBytes(of: UInt8((r * 299 + g * 587 + b * 114 + 500) / 1000), toByteOffset: x, as: UInt8.self)
            }
        case .other:
            let p = pixels.assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                format.write((p[x * 4 + 2], p[x * 4 + 1], p[x * 4], p[x * 4 + 3]), to: target + x * format.bytesPerPixel)
            }
        }
    }

    /// Memory to canvas: the rows that are not as the mirror has them, and
    /// every row the first time.
    private func load() {
        let rowBytes = width * format.bytesPerPixel
        let first = mirror == nil
        if first {
            mirror = malloc(max(rowBytes * height, 1))
            scratch = malloc(max(rowBytes, 1))
        }
        guard let mirror else { return }
        _ = canvas.withPixels { pixels, stride in
            for row in 0..<height {
                let source = UnsafeRawPointer(data + row * bytesPerRow), kept = mirror + row * rowBytes
                guard first || memcmp(source, kept, rowBytes) != 0 else { continue }
                convert(row: source, to: UnsafeMutableRawPointer(pixels + row * stride))
                memcpy(kept, source, rowBytes)
            }
        }
    }

    /// Canvas to memory: the rows whose pixels are no longer what memory
    /// has.
    private func store() {
        let rowBytes = width * format.bytesPerPixel
        guard let mirror, let scratch else { return }
        _ = canvas.withPixels { pixels, stride in
            for row in 0..<height {
                convert(row: UnsafeRawPointer(pixels + row * stride), toMemory: scratch)
                let kept = mirror + row * rowBytes
                guard memcmp(scratch, kept, rowBytes) != 0 else { continue }
                memcpy(data + row * bytesPerRow, scratch, rowBytes)
                memcpy(kept, scratch, rowBytes)
            }
        }
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

    /// The canvas, for state changes that need no painting.
    static func canvas(_ context: Ref?) -> Canvas? { state(context)?.canvas }

    static func paint(_ context: Ref?, _ body: (Canvas) -> Void) { state(context)?.paint(body) }
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
    guard let state = ContextState(width: width, height: height, bytesPerRow: rowBytes, format: format, space: space, data: memory,
                                   ownsData: data == nil) else {
        if data == nil { free(memory) }
        return nil
    }
    return makeObject(CGContextObject.objCClass, CGContextObject.states, state)
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
    state.canvas.context.flush()
    let bytes = Array(UnsafeRawBufferPointer(start: state.data, count: state.bytesPerRow * state.height))
    let provider = DataProviders.make(bytes)
    defer { ObjCRuntime.release(provider) }
    return makeObject(CGImageObject.objCClass, CGImageObject.states,
                      ImageState(width: state.width, height: state.height, format: state.format, bytesPerRow: state.bytesPerRow,
                                 space: state.space, provider: provider))
}

@c(_CGContextRetain) public func CGContextRetain(_ context: Ref?) -> Ref? { ObjCRuntime.retain(context) }
@c(_CGContextRelease) public func CGContextRelease(_ context: Ref?) { ObjCRuntime.release(context) }
@c(_CGContextFlush) public func CGContextFlush(_ context: Ref?) { Contexts.canvas(context)?.context.flush() }
@c(_CGContextSynchronize) public func CGContextSynchronize(_ context: Ref?) { Contexts.canvas(context)?.context.flush() }

// MARK: Graphics state

@c(_CGContextSaveGState) public func CGContextSaveGState(_ context: Ref?) { Contexts.canvas(context)?.save() }
@c(_CGContextRestoreGState) public func CGContextRestoreGState(_ context: Ref?) { Contexts.canvas(context)?.restore() }

@c(_CGContextSetRGBFillColor)
public func CGContextSetRGBFillColor(_ context: Ref?, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
    Contexts.canvas(context)?.setFill(r, g, b, a)
}

@c(_CGContextSetRGBStrokeColor)
public func CGContextSetRGBStrokeColor(_ context: Ref?, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
    Contexts.canvas(context)?.setStroke(r, g, b, a)
}

@c(_CGContextSetGrayFillColor)
public func CGContextSetGrayFillColor(_ context: Ref?, _ gray: Double, _ a: Double) { Contexts.canvas(context)?.setFill(gray, gray, gray, a) }

@c(_CGContextSetGrayStrokeColor)
public func CGContextSetGrayStrokeColor(_ context: Ref?, _ gray: Double, _ a: Double) { Contexts.canvas(context)?.setStroke(gray, gray, gray, a) }

@c(_CGContextSetFillColorWithColor)
public func CGContextSetFillColorWithColor(_ context: Ref?, _ color: Ref?) {
    guard let color = Colors.state(color) else { return }
    let c = color.rgba
    Contexts.canvas(context)?.setFill(c.0, c.1, c.2, c.3)
}

@c(_CGContextSetStrokeColorWithColor)
public func CGContextSetStrokeColorWithColor(_ context: Ref?, _ color: Ref?) {
    guard let color = Colors.state(color) else { return }
    let c = color.rgba
    Contexts.canvas(context)?.setStroke(c.0, c.1, c.2, c.3)
}

/// Components in the context's fill color space; with three or four, RGB(A).
@c(_CGContextSetFillColor)
public func CGContextSetFillColor(_ context: Ref?, _ components: UnsafePointer<Double>?) {
    guard let components else { return }
    Contexts.canvas(context)?.setFill(components[0], components[1], components[2], components[3])
}

@c(_CGContextSetStrokeColor)
public func CGContextSetStrokeColor(_ context: Ref?, _ components: UnsafePointer<Double>?) {
    guard let components else { return }
    Contexts.canvas(context)?.setStroke(components[0], components[1], components[2], components[3])
}

@c(_CGContextSetFillColorSpace) public func CGContextSetFillColorSpace(_ context: Ref?, _ space: Ref?) {}
@c(_CGContextSetStrokeColorSpace) public func CGContextSetStrokeColorSpace(_ context: Ref?, _ space: Ref?) {}

@c(_CGContextSetAlpha) public func CGContextSetAlpha(_ context: Ref?, _ alpha: Double) { Contexts.canvas(context)?.alpha = alpha }
@c(_CGContextSetLineWidth) public func CGContextSetLineWidth(_ context: Ref?, _ width: Double) { Contexts.canvas(context)?.lineWidth = width }
@c(_CGContextSetLineCap) public func CGContextSetLineCap(_ context: Ref?, _ cap: Int32) { Contexts.canvas(context)?.setLineCap(cap) }
@c(_CGContextSetLineJoin) public func CGContextSetLineJoin(_ context: Ref?, _ join: Int32) { Contexts.canvas(context)?.setLineJoin(join) }
@c(_CGContextSetMiterLimit) public func CGContextSetMiterLimit(_ context: Ref?, _ limit: Double) { Contexts.canvas(context)?.setMiterLimit(limit) }
@c(_CGContextSetFlatness) public func CGContextSetFlatness(_ context: Ref?, _ flatness: Double) { Contexts.canvas(context)?.setFlatness(flatness) }

@c(_CGContextSetLineDash)
public func CGContextSetLineDash(_ context: Ref?, _ phase: Double, _ lengths: UnsafePointer<Double>?, _ count: Int) {
    Contexts.canvas(context)?.setLineDash(phase: phase, lengths: lengths.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? [])
}

@c(_CGContextSetShouldAntialias) public func CGContextSetShouldAntialias(_ context: Ref?, _ value: Bool) { Contexts.canvas(context)?.setAntialias(value) }
@c(_CGContextSetAllowsAntialiasing) public func CGContextSetAllowsAntialiasing(_ context: Ref?, _ value: Bool) {}
@c(_CGContextSetBlendMode) public func CGContextSetBlendMode(_ context: Ref?, _ mode: Int32) { Contexts.canvas(context)?.setBlendMode(mode) }

@c(_CGContextSetInterpolationQuality) public func CGContextSetInterpolationQuality(_ context: Ref?, _ quality: Int32) {}
@c(_CGContextGetInterpolationQuality) public func CGContextGetInterpolationQuality(_ context: Ref?) -> Int32 { 0 }

@c(_CGContextSetShadowWithColor)
public func CGContextSetShadowWithColor(_ context: Ref?, _ offset: CGSize, _ blur: Double, _ color: Ref?) {
    let c = Colors.state(color)?.rgba ?? (0, 0, 0, 0)
    Contexts.canvas(context)?.setShadow(dx: offset.width, dy: offset.height, blur: blur, color: c)
}

@c(_CGContextSetShadow)
public func CGContextSetShadow(_ context: Ref?, _ offset: CGSize, _ blur: Double) {
    Contexts.canvas(context)?.setShadow(dx: offset.width, dy: offset.height, blur: blur, color: (0, 0, 0, 1.0 / 3))
}

// MARK: Transforms

@c(_CGContextConcatCTM)
public func CGContextConcatCTM(_ context: Ref?, _ t: CGAffineTransform) { Contexts.canvas(context)?.concat(t.a, t.b, t.c, t.d, t.tx, t.ty) }

@c(_CGContextTranslateCTM) public func CGContextTranslateCTM(_ context: Ref?, _ tx: Double, _ ty: Double) { Contexts.canvas(context)?.translate(tx, ty) }
@c(_CGContextScaleCTM) public func CGContextScaleCTM(_ context: Ref?, _ sx: Double, _ sy: Double) { Contexts.canvas(context)?.scale(sx, sy) }
@c(_CGContextRotateCTM) public func CGContextRotateCTM(_ context: Ref?, _ angle: Double) { Contexts.canvas(context)?.rotate(angle) }

@c(_CGContextGetCTM)
public func CGContextGetCTM(_ context: Ref?) -> CGAffineTransform {
    guard let m = Contexts.canvas(context)?.ctm else { return CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    return CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty)
}

// MARK: Paths

@c(_CGContextBeginPath) public func CGContextBeginPath(_ context: Ref?) { Contexts.canvas(context)?.beginPath() }
@c(_CGContextClosePath) public func CGContextClosePath(_ context: Ref?) { Contexts.canvas(context)?.closePath() }
@c(_CGContextMoveToPoint) public func CGContextMoveToPoint(_ context: Ref?, _ x: Double, _ y: Double) { Contexts.canvas(context)?.move(x, y) }
@c(_CGContextAddLineToPoint) public func CGContextAddLineToPoint(_ context: Ref?, _ x: Double, _ y: Double) { Contexts.canvas(context)?.line(x, y) }

@c(_CGContextAddCurveToPoint)
public func CGContextAddCurveToPoint(_ context: Ref?, _ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
    Contexts.canvas(context)?.curve(c1x, c1y, c2x, c2y, x, y)
}

@c(_CGContextAddQuadCurveToPoint)
public func CGContextAddQuadCurveToPoint(_ context: Ref?, _ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
    Contexts.canvas(context)?.quad(cx, cy, x, y)
}

@c(_CGContextAddArc)
public func CGContextAddArc(_ context: Ref?, _ x: Double, _ y: Double, _ radius: Double, _ start: Double, _ end: Double, _ clockwise: Int32) {
    Contexts.canvas(context)?.arc(x, y, radius: radius, start: start, end: end, clockwise: clockwise != 0)
}

@c(_CGContextAddArcToPoint)
public func CGContextAddArcToPoint(_ context: Ref?, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ radius: Double) {
    Contexts.canvas(context)?.arc(tangent1: x1, y1, tangent2: x2, y2, radius: radius)
}

@c(_CGContextAddRect)
public func CGContextAddRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.canvas(context)?.rect(r.origin.x, r.origin.y, r.size.width, r.size.height)
}

@c(_CGContextAddRects)
public func CGContextAddRects(_ context: Ref?, _ rects: UnsafePointer<CGRect>?, _ count: Int) {
    for index in 0..<count { CGContextAddRect(context, rects![index]) }
}

@c(_CGContextAddEllipseInRect)
public func CGContextAddEllipseInRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.canvas(context)?.ellipse(r.origin.x, r.origin.y, r.size.width, r.size.height)
}

@c(_CGContextAddLines)
public func CGContextAddLines(_ context: Ref?, _ points: UnsafePointer<CGPoint>?, _ count: Int) {
    guard let points, count > 0, let canvas = Contexts.canvas(context) else { return }
    canvas.move(points[0].x, points[0].y)
    for index in 1..<count { canvas.line(points[index].x, points[index].y) }
}

@c(_CGContextAddPath)
public func CGContextAddPath(_ context: Ref?, _ path: Ref?) {
    guard let commands = Paths.state(path)?.commands else { return }
    Contexts.canvas(context)?.add(commands)
}

@c(_CGContextIsPathEmpty) public func CGContextIsPathEmpty(_ context: Ref?) -> Bool { Contexts.canvas(context)?.isPathEmpty ?? true }

@c(_CGContextGetPathCurrentPoint)
public func CGContextGetPathCurrentPoint(_ context: Ref?) -> CGPoint {
    let point = Contexts.canvas(context)?.currentPoint ?? (0, 0)
    return CGPoint(x: point.0, y: point.1)
}

@c(_CGContextGetPathBoundingBox)
public func CGContextGetPathBoundingBox(_ context: Ref?) -> CGRect {
    guard let canvas = Contexts.canvas(context), !canvas.isPathEmpty else {
        return CGRect(origin: CGPoint(x: .infinity, y: .infinity), size: CGSize(width: 0, height: 0))
    }
    let b = canvas.pathBounds
    return CGRect(origin: CGPoint(x: b.0, y: b.1), size: CGSize(width: b.2, height: b.3))
}

@c(_CGContextPathContainsPoint)
public func CGContextPathContainsPoint(_ context: Ref?, _ point: CGPoint, _ mode: Int32) -> Bool {
    Contexts.canvas(context)?.pathContains(point.x, point.y, evenOdd: mode == 1 || mode == 4) ?? false
}

// MARK: Painting

@c(_CGContextFillPath) public func CGContextFillPath(_ context: Ref?) { Contexts.paint(context) { $0.fillPath(evenOdd: false) } }
@c(_CGContextEOFillPath) public func CGContextEOFillPath(_ context: Ref?) { Contexts.paint(context) { $0.fillPath(evenOdd: true) } }
@c(_CGContextStrokePath) public func CGContextStrokePath(_ context: Ref?) { Contexts.paint(context) { $0.strokePath() } }
@c(_CGContextDrawPath) public func CGContextDrawPath(_ context: Ref?, _ mode: Int32) { Contexts.paint(context) { $0.drawPath(mode) } }

@c(_CGContextFillRect)
public func CGContextFillRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.paint(context) { canvas in
        canvas.beginPath()
        canvas.rect(r.origin.x, r.origin.y, r.size.width, r.size.height)
        canvas.fillPath(evenOdd: false)
    }
}

@c(_CGContextFillRects)
public func CGContextFillRects(_ context: Ref?, _ rects: UnsafePointer<CGRect>?, _ count: Int) {
    for index in 0..<count { CGContextFillRect(context, rects![index]) }
}

@c(_CGContextStrokeRect)
public func CGContextStrokeRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.paint(context) { canvas in
        canvas.beginPath()
        canvas.rect(r.origin.x, r.origin.y, r.size.width, r.size.height)
        canvas.strokePath()
    }
}

@c(_CGContextStrokeRectWithWidth)
public func CGContextStrokeRectWithWidth(_ context: Ref?, _ rect: CGRect, _ width: Double) {
    guard let canvas = Contexts.canvas(context) else { return }
    canvas.save()
    canvas.lineWidth = width
    CGContextStrokeRect(context, rect)
    canvas.restore()
}

@c(_CGContextFillEllipseInRect)
public func CGContextFillEllipseInRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.paint(context) { canvas in
        canvas.beginPath()
        canvas.ellipse(r.origin.x, r.origin.y, r.size.width, r.size.height)
        canvas.fillPath(evenOdd: false)
    }
}

@c(_CGContextStrokeEllipseInRect)
public func CGContextStrokeEllipseInRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.paint(context) { canvas in
        canvas.beginPath()
        canvas.ellipse(r.origin.x, r.origin.y, r.size.width, r.size.height)
        canvas.strokePath()
    }
}

@c(_CGContextStrokeLineSegments)
public func CGContextStrokeLineSegments(_ context: Ref?, _ points: UnsafePointer<CGPoint>?, _ count: Int) {
    guard let points else { return }
    Contexts.paint(context) { canvas in
        canvas.beginPath()
        for index in stride(from: 0, to: count - 1, by: 2) {
            canvas.move(points[index].x, points[index].y)
            canvas.line(points[index + 1].x, points[index + 1].y)
        }
        canvas.strokePath()
    }
}

@c(_CGContextClearRect)
public func CGContextClearRect(_ context: Ref?, _ rect: CGRect) {
    let r = CGRectStandardize(rect)
    Contexts.paint(context) { $0.clear(r.origin.x, r.origin.y, r.size.width, r.size.height) }
}

@c(_CGContextClip) public func CGContextClip(_ context: Ref?) { Contexts.canvas(context)?.clip(evenOdd: false) }
@c(_CGContextEOClip) public func CGContextEOClip(_ context: Ref?) { Contexts.canvas(context)?.clip(evenOdd: true) }

@c(_CGContextClipToRect)
public func CGContextClipToRect(_ context: Ref?, _ rect: CGRect) {
    guard let canvas = Contexts.canvas(context) else { return }
    let r = CGRectStandardize(rect)
    canvas.beginPath()
    canvas.rect(r.origin.x, r.origin.y, r.size.width, r.size.height)
    canvas.clip(evenOdd: false)
}

/// The mask's alpha, or gray level, limits what is drawn until the
/// graphics state is restored.
@c(_CGContextClipToMask)
public func CGContextClipToMask(_ context: Ref?, _ rect: CGRect, _ mask: Ref?) {
    guard let canvas = Contexts.canvas(context), let image = Images.state(mask) else { return }
    let r = CGRectStandardize(rect)
    canvas.clipToMask(image, r.origin.x, r.origin.y, r.size.width, r.size.height)
}

@c(_CGContextClipToRects)
public func CGContextClipToRects(_ context: Ref?, _ rects: UnsafePointer<CGRect>?, _ count: Int) {
    guard let canvas = Contexts.canvas(context), let rects else { return }
    canvas.beginPath()
    for index in 0..<count {
        let r = CGRectStandardize(rects[index])
        canvas.rect(r.origin.x, r.origin.y, r.size.width, r.size.height)
    }
    canvas.clip(evenOdd: false)
}

@c(_CGContextDrawImage)
public func CGContextDrawImage(_ context: Ref?, _ rect: CGRect, _ image: Ref?) {
    guard let image = Images.state(image) else { return }
    let r = CGRectStandardize(rect)
    Contexts.paint(context) { $0.draw(image, r.origin.x, r.origin.y, r.size.width, r.size.height) }
}

@c(_CGContextBeginTransparencyLayer)
public func CGContextBeginTransparencyLayer(_ context: Ref?, _ info: Ref?) { Contexts.canvas(context)?.beginLayer() }

@c(_CGContextBeginTransparencyLayerWithRect)
public func CGContextBeginTransparencyLayerWithRect(_ context: Ref?, _ rect: CGRect, _ info: Ref?) { Contexts.canvas(context)?.beginLayer() }

@c(_CGContextEndTransparencyLayer)
public func CGContextEndTransparencyLayer(_ context: Ref?) { Contexts.paint(context) { $0.endLayer() } }

// MARK: Text

/// The deprecated toy text calls, which UIKit-era code still makes.
@c(_CGContextSelectFont)
public func CGContextSelectFont(_ context: Ref?, _ name: UnsafePointer<CChar>?, _ size: Double, _ encoding: Int32) {
    _ = Contexts.canvas(context)?.selectFont(name.map { String(cString: $0) } ?? "Helvetica", size: size)
}

@c(_CGContextSetFontSize) public func CGContextSetFontSize(_ context: Ref?, _ size: Double) { Contexts.canvas(context)?.setFontSize(size) }
@c(_CGContextSetCharacterSpacing) public func CGContextSetCharacterSpacing(_ context: Ref?, _ spacing: Double) { Contexts.canvas(context)?.setCharacterSpacing(spacing) }
@c(_CGContextSetTextDrawingMode)
public func CGContextSetTextDrawingMode(_ context: Ref?, _ mode: Int32) { Contexts.canvas(context)?.setTextDrawingMode(mode) }

@c(_CGContextSetTextPosition)
public func CGContextSetTextPosition(_ context: Ref?, _ x: Double, _ y: Double) { Contexts.canvas(context)?.textPosition = (x, y) }

@c(_CGContextGetTextPosition)
public func CGContextGetTextPosition(_ context: Ref?) -> CGPoint {
    let p = Contexts.canvas(context)?.textPosition ?? (0, 0)
    return CGPoint(x: p.0, y: p.1)
}

@c(_CGContextSetTextMatrix)
public func CGContextSetTextMatrix(_ context: Ref?, _ t: CGAffineTransform) { Contexts.canvas(context)?.setTextMatrix(t.a, t.b, t.c, t.d, t.tx, t.ty) }

@c(_CGContextShowText)
public func CGContextShowText(_ context: Ref?, _ text: UnsafePointer<CChar>?, _ length: Int) {
    guard let text else { return }
    let string = String(decoding: UnsafeRawBufferPointer(start: text, count: length), as: UTF8.self)
    Contexts.paint(context) { $0.showText(string) }
}

@c(_CGContextShowTextAtPoint)
public func CGContextShowTextAtPoint(_ context: Ref?, _ x: Double, _ y: Double, _ text: UnsafePointer<CChar>?, _ length: Int) {
    CGContextSetTextPosition(context, x, y)
    CGContextShowText(context, text, length)
}

// MARK: - Paths

final class PathState: @unchecked Sendable {
    var commands: [PathCommand]

    init(_ commands: [PathCommand] = []) {
        self.commands = commands
    }

    var current: (Double, Double)? {
        var start: (Double, Double)?
        var point: (Double, Double)?
        for command in commands {
            switch command {
            case .move(let x, let y):
                start = (x, y)
                point = (x, y)
            case .line(let x, let y), .quad(_, _, let x, let y), .curve(_, _, _, _, let x, let y): point = (x, y)
            case .close: point = start
            }
        }
        return point
    }

    /// Every point, control points included, as CGPathGetBoundingBox counts them.
    var points: [(Double, Double)] {
        commands.flatMap { command -> [(Double, Double)] in
            switch command {
            case .move(let x, let y), .line(let x, let y): return [(x, y)]
            case .quad(let a, let b, let x, let y): return [(a, b), (x, y)]
            case .curve(let a, let b, let c, let d, let x, let y): return [(a, b), (c, d), (x, y)]
            case .close: return []
            }
        }
    }
}

@ObjCClass("CGPath")
public final class CGPathObject: NSObject {
    static let states = StateTable<PathState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGPathObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGPathObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 80 }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool { Paths.state(other?.objcObject)?.commands == Paths.state(objcObject)?.commands }
}

enum Paths {
    static func state(_ path: Ref?) -> PathState? { CGPathObject.states[path] }
    static func make(_ commands: [PathCommand] = []) -> Ref { makeObject(CGPathObject.objCClass, CGPathObject.states, PathState(commands)) }

    /// A point through an optional transform.
    static func apply(_ t: UnsafePointer<CGAffineTransform>?, _ x: Double, _ y: Double) -> (Double, Double) {
        guard let t = t?.pointee else { return (x, y) }
        return (t.a * x + t.c * y + t.tx, t.b * x + t.d * y + t.ty)
    }

    static func append(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ commands: [PathCommand]) {
        guard let state = state(path) else { return }
        for command in commands {
            switch command {
            case .move(let x, let y): let p = apply(t, x, y); state.commands.append(.move(p.0, p.1))
            case .line(let x, let y): let p = apply(t, x, y); state.commands.append(.line(p.0, p.1))
            case .quad(let a, let b, let x, let y):
                let c = apply(t, a, b), p = apply(t, x, y)
                state.commands.append(.quad(c.0, c.1, p.0, p.1))
            case .curve(let a, let b, let c, let d, let x, let y):
                let c1 = apply(t, a, b), c2 = apply(t, c, d), p = apply(t, x, y)
                state.commands.append(.curve(c1.0, c1.1, c2.0, c2.1, p.0, p.1))
            case .close: state.commands.append(.close)
            }
        }
    }

    /// An ellipse as four cubic curves, from the rect's right middle going
    /// counterclockwise, as CoreGraphics draws it.
    static func ellipse(_ r: CGRect) -> [PathCommand] {
        let k = 0.5522847498307936
        let cx = r.origin.x + r.size.width / 2, cy = r.origin.y + r.size.height / 2
        let rx = r.size.width / 2, ry = r.size.height / 2
        return [.move(cx + rx, cy),
                .curve(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry),
                .curve(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy),
                .curve(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry),
                .curve(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy),
                .close]
    }

    static func rect(_ r: CGRect) -> [PathCommand] {
        let x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height
        return [.move(x, y), .line(x + w, y), .line(x + w, y + h), .line(x, y + h), .close]
    }

    /// An arc as cubic curves of at most a quarter turn each.
    static func arc(_ cx: Double, _ cy: Double, _ radius: Double, _ start: Double, _ end: Double, clockwise: Bool,
                    hasCurrentPoint: Bool) -> [PathCommand] {
        var sweep = end - start
        if clockwise { if sweep > 0 { sweep -= 2 * .pi * (sweep / (2 * .pi)).rounded(.up) } }
        else if sweep < 0 { sweep += 2 * .pi * (-sweep / (2 * .pi)).rounded(.up) }
        let first = (cx + radius * cos(start), cy + radius * sin(start))
        var commands: [PathCommand] = [hasCurrentPoint ? .line(first.0, first.1) : .move(first.0, first.1)]
        let segments = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let step = sweep / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var angle = start
        for _ in 0..<segments {
            let a1 = angle, a2 = angle + step
            let p1 = (cx + radius * cos(a1), cy + radius * sin(a1)), p2 = (cx + radius * cos(a2), cy + radius * sin(a2))
            commands.append(.curve(p1.0 - k * radius * sin(a1), p1.1 + k * radius * cos(a1),
                                   p2.0 + k * radius * sin(a2), p2.1 - k * radius * cos(a2), p2.0, p2.1))
            angle = a2
        }
        return commands
    }

    static func roundedRect(_ r: CGRect, _ rx: Double, _ ry: Double) -> [PathCommand] {
        let x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height
        guard rx > 0, ry > 0 else { return rect(r) }
        let k = 0.5522847498307936
        return [.move(x + rx, y), .line(x + w - rx, y),
                .curve(x + w - rx + k * rx, y, x + w, y + ry - k * ry, x + w, y + ry), .line(x + w, y + h - ry),
                .curve(x + w, y + h - ry + k * ry, x + w - rx + k * rx, y + h, x + w - rx, y + h), .line(x + rx, y + h),
                .curve(x + rx - k * rx, y + h, x, y + h - ry + k * ry, x, y + h - ry), .line(x, y + ry),
                .curve(x, y + ry - k * ry, x + rx - k * rx, y, x + rx, y), .close]
    }
}

@c(_CGPathGetTypeID) public func CGPathGetTypeID() -> UInt { 80 }
@c(_CGPathCreateMutable) public func CGPathCreateMutable() -> Ref { Paths.make() }
@c(_CGPathCreateCopy) public func CGPathCreateCopy(_ path: Ref?) -> Ref? { Paths.state(path).map { Paths.make($0.commands) } }
@c(_CGPathCreateMutableCopy) public func CGPathCreateMutableCopy(_ path: Ref?) -> Ref? { CGPathCreateCopy(path) }

@c(_CGPathCreateCopyByTransformingPath)
public func CGPathCreateCopyByTransformingPath(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?) -> Ref? {
    guard let source = Paths.state(path) else { return nil }
    let copy = Paths.make()
    Paths.append(copy, t, source.commands)
    return copy
}

@c(_CGPathCreateWithRect)
public func CGPathCreateWithRect(_ rect: CGRect, _ t: UnsafePointer<CGAffineTransform>?) -> Ref {
    let path = Paths.make()
    Paths.append(path, t, Paths.rect(CGRectStandardize(rect)))
    return path
}

@c(_CGPathCreateWithEllipseInRect)
public func CGPathCreateWithEllipseInRect(_ rect: CGRect, _ t: UnsafePointer<CGAffineTransform>?) -> Ref {
    let path = Paths.make()
    Paths.append(path, t, Paths.ellipse(CGRectStandardize(rect)))
    return path
}

@c(_CGPathCreateWithRoundedRect)
public func CGPathCreateWithRoundedRect(_ rect: CGRect, _ rx: Double, _ ry: Double, _ t: UnsafePointer<CGAffineTransform>?) -> Ref {
    let path = Paths.make()
    Paths.append(path, t, Paths.roundedRect(CGRectStandardize(rect), rx, ry))
    return path
}

@c(_CGPathMoveToPoint)
public func CGPathMoveToPoint(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ x: Double, _ y: Double) { Paths.append(path, t, [.move(x, y)]) }

@c(_CGPathAddLineToPoint)
public func CGPathAddLineToPoint(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ x: Double, _ y: Double) { Paths.append(path, t, [.line(x, y)]) }

@c(_CGPathAddQuadCurveToPoint)
public func CGPathAddQuadCurveToPoint(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
    Paths.append(path, t, [.quad(cx, cy, x, y)])
}

@c(_CGPathAddCurveToPoint)
public func CGPathAddCurveToPoint(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ c1x: Double, _ c1y: Double, _ c2x: Double,
                                  _ c2y: Double, _ x: Double, _ y: Double) {
    Paths.append(path, t, [.curve(c1x, c1y, c2x, c2y, x, y)])
}

@c(_CGPathCloseSubpath) public func CGPathCloseSubpath(_ path: Ref?) { Paths.append(path, nil, [.close]) }

@c(_CGPathAddRect)
public func CGPathAddRect(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ rect: CGRect) {
    Paths.append(path, t, Paths.rect(CGRectStandardize(rect)))
}

@c(_CGPathAddRects)
public func CGPathAddRects(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ rects: UnsafePointer<CGRect>?, _ count: Int) {
    for index in 0..<count { CGPathAddRect(path, t, rects![index]) }
}

@c(_CGPathAddLines)
public func CGPathAddLines(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ points: UnsafePointer<CGPoint>?, _ count: Int) {
    guard let points, count > 0 else { return }
    Paths.append(path, t, [.move(points[0].x, points[0].y)] + (1..<count).map { .line(points[$0].x, points[$0].y) })
}

@c(_CGPathAddEllipseInRect)
public func CGPathAddEllipseInRect(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ rect: CGRect) {
    Paths.append(path, t, Paths.ellipse(CGRectStandardize(rect)))
}

@c(_CGPathAddRoundedRect)
public func CGPathAddRoundedRect(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ rect: CGRect, _ rx: Double, _ ry: Double) {
    Paths.append(path, t, Paths.roundedRect(CGRectStandardize(rect), rx, ry))
}

@c(_CGPathAddArc)
public func CGPathAddArc(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ x: Double, _ y: Double, _ radius: Double,
                         _ start: Double, _ end: Double, _ clockwise: Bool) {
    let hasCurrent = Paths.state(path)?.current != nil
    Paths.append(path, t, Paths.arc(x, y, radius, start, end, clockwise: clockwise, hasCurrentPoint: hasCurrent))
}

@c(_CGPathAddRelativeArc)
public func CGPathAddRelativeArc(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ x: Double, _ y: Double, _ radius: Double,
                                 _ start: Double, _ delta: Double) {
    CGPathAddArc(path, t, x, y, radius, start, start + delta, delta < 0)
}

@c(_CGPathAddPath)
public func CGPathAddPath(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ other: Ref?) {
    guard let other = Paths.state(other) else { return }
    Paths.append(path, t, other.commands)
}

@c(_CGPathIsEmpty) public func CGPathIsEmpty(_ path: Ref?) -> Bool { Paths.state(path)?.commands.isEmpty ?? true }

@c(_CGPathIsRect)
public func CGPathIsRect(_ path: Ref?, _ rect: UnsafeMutablePointer<CGRect>?) -> Bool {
    guard let commands = Paths.state(path)?.commands, commands.count == 5,
          case .move(let x, let y) = commands[0], case .line(let x2, let y2) = commands[2] else { return false }
    rect?.pointee = CGRectStandardize(CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: x2 - x, height: y2 - y)))
    return true
}

@c(_CGPathEqualToPath)
public func CGPathEqualToPath(_ a: Ref?, _ b: Ref?) -> Bool { Paths.state(a)?.commands == Paths.state(b)?.commands }

@c(_CGPathGetCurrentPoint)
public func CGPathGetCurrentPoint(_ path: Ref?) -> CGPoint {
    let point = Paths.state(path)?.current ?? (0, 0)
    return CGPoint(x: point.0, y: point.1)
}

/// The smallest rect holding every point, control points included.
@c(_CGPathGetBoundingBox)
public func CGPathGetBoundingBox(_ path: Ref?) -> CGRect {
    guard let points = Paths.state(path)?.points, !points.isEmpty else {
        return CGRect(origin: CGPoint(x: .infinity, y: .infinity), size: CGSize(width: 0, height: 0))
    }
    let xs = points.map(\.0), ys = points.map(\.1)
    return CGRect(origin: CGPoint(x: xs.min()!, y: ys.min()!), size: CGSize(width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
}

@c(_CGPathGetPathBoundingBox) public func CGPathGetPathBoundingBox(_ path: Ref?) -> CGRect { CGPathGetBoundingBox(path) }

/// Fill containment, through a scratch canvas.
@c(_CGPathContainsPoint)
public func CGPathContainsPoint(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ point: CGPoint, _ evenOdd: Bool) -> Bool {
    guard let commands = Paths.state(path)?.commands, let canvas = Canvas(width: 1, height: 1) else { return false }
    canvas.add(commands)
    let p = t.map { _ in Paths.apply(t, point.x, point.y) } ?? (point.x, point.y)
    return canvas.pathContains(p.0, p.1, evenOdd: evenOdd)
}

/// CGPathElement { type; points }, one call per element.
@c(_CGPathApply)
public func CGPathApply(_ path: Ref?, _ info: UnsafeMutableRawPointer?,
                        _ function: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void)?) {
    guard let commands = Paths.state(path)?.commands, let function else { return }
    let points = UnsafeMutablePointer<CGPoint>.allocate(capacity: 3)
    defer { points.deallocate() }
    for command in commands {
        var type: Int32 = 0
        switch command {
        case .move(let x, let y): (type, points[0]) = (0, CGPoint(x: x, y: y))
        case .line(let x, let y): (type, points[0]) = (1, CGPoint(x: x, y: y))
        case .quad(let a, let b, let x, let y): (type, points[0], points[1]) = (2, CGPoint(x: a, y: b), CGPoint(x: x, y: y))
        case .curve(let a, let b, let c, let d, let x, let y):
            (type, points[0], points[1], points[2]) = (3, CGPoint(x: a, y: b), CGPoint(x: c, y: d), CGPoint(x: x, y: y))
        case .close: type = 4
        }
        var element = (type: type, padding: Int32(0), points: UnsafeMutableRawPointer(points))
        withUnsafePointer(to: &element) { function(info, UnsafeRawPointer($0)) }
    }
}

/// The block takes a pointer to each CGPathElement.
@c(_CGPathApplyWithBlock)
public func CGPathApplyWithBlock(_ path: Ref?, _ block: UnsafeMutableRawPointer?) {
    guard let block else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
    let invoke = unsafeBitCast(block.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Invoke.self)
    nonisolated(unsafe) let context = block
    withoutActuallyEscaping({ (element: UnsafeRawPointer?) in invoke(context, element) }) { body in
        PathBlock.body = body
        CGPathApply(path, nil, { _, element in PathBlock.body?(element) })
        PathBlock.body = nil
    }
}

/// The block CGPathApplyWithBlock calls, for its C function; paths are
/// applied on one thread at a time.
enum PathBlock {
    nonisolated(unsafe) static var body: ((UnsafeRawPointer?) -> Void)?
}

@c(_CGPathRetain) public func CGPathRetain(_ path: Ref?) -> Ref? { ObjCRuntime.retain(path) }
@c(_CGPathRelease) public func CGPathRelease(_ path: Ref?) { ObjCRuntime.release(path) }

// MARK: - Gradients

final class GradientState: @unchecked Sendable {
    let stops: [(Double, (Double, Double, Double, Double))]
    init(_ stops: [(Double, (Double, Double, Double, Double))]) { self.stops = stops }
}

@ObjCClass("CGGradient")
public final class CGGradientObject: NSObject {
    static let states = StateTable<GradientState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGGradientObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGGradientObject.objCClass.pointer)
    }
}

@c(_CGGradientGetTypeID) public func CGGradientGetTypeID() -> UInt { 83 }

/// Components per stop as the space has them, plus alpha; no locations
/// spreads the stops evenly.
@c(_CGGradientCreateWithColorComponents)
public func CGGradientCreateWithColorComponents(_ space: Ref?, _ components: UnsafePointer<Double>?, _ locations: UnsafePointer<Double>?,
                                                _ count: Int) -> Ref? {
    guard let components, count > 0 else { return nil }
    let perColor = (ColorSpaces.state(space)?.components ?? 3) + 1
    let stops = (0..<count).map { index -> (Double, (Double, Double, Double, Double)) in
        let c = components + index * perColor
        let location = locations?[index] ?? (count == 1 ? 0 : Double(index) / Double(count - 1))
        return perColor == 2 ? (location, (c[0], c[0], c[0], c[1])) : (location, (c[0], c[1], c[2], c[3]))
    }
    return makeObject(CGGradientObject.objCClass, CGGradientObject.states, GradientState(stops))
}

@c(_CGGradientCreateWithColors)
public func CGGradientCreateWithColors(_ space: Ref?, _ colors: Ref?, _ locations: UnsafePointer<Double>?) -> Ref? {
    guard let colors else { return nil }
    let list = NSArray(objCArgument: colors)
    let count = Int(list.count())
    let stops = (0..<count).compactMap { index -> (Double, (Double, Double, Double, Double))? in
        guard let color = Colors.state(list.object(at: UInt(index)).objcObject) else { return nil }
        return (locations?[index] ?? (count == 1 ? 0 : Double(index) / Double(count - 1)), color.rgba)
    }
    return makeObject(CGGradientObject.objCClass, CGGradientObject.states, GradientState(stops))
}

@c(_CGGradientRetain) public func CGGradientRetain(_ gradient: Ref?) -> Ref? { ObjCRuntime.retain(gradient) }
@c(_CGGradientRelease) public func CGGradientRelease(_ gradient: Ref?) { ObjCRuntime.release(gradient) }

/// CGGradientDrawingOptions: draws before start 1, after end 2.
@c(_CGContextDrawLinearGradient)
public func CGContextDrawLinearGradient(_ context: Ref?, _ gradient: Ref?, _ start: CGPoint, _ end: CGPoint, _ options: UInt32) {
    guard let stops = CGGradientObject.states[gradient]?.stops else { return }
    Contexts.paint(context) { $0.linearGradient(stops, from: (start.x, start.y), to: (end.x, end.y), extend: options != 0) }
}

@c(_CGContextDrawRadialGradient)
public func CGContextDrawRadialGradient(_ context: Ref?, _ gradient: Ref?, _ startCenter: CGPoint, _ startRadius: Double, _ endCenter: CGPoint,
                                        _ endRadius: Double, _ options: UInt32) {
    guard let stops = CGGradientObject.states[gradient]?.stops else { return }
    Contexts.paint(context) {
        $0.radialGradient(stops, from: (startCenter.x, startCenter.y), radius: startRadius, to: (endCenter.x, endCenter.y),
                          radius: endRadius, extend: options != 0)
    }
}
