import Cairo
import Foundation
import SilicaCairo

// Drawing through Silica's Cairo renderer. A Canvas is a Cairo image
// surface (ARGB32: premultiplied, native-endian 0xAARRGGBB, so B, G, R, A
// in memory here) with Silica's context on it, origin at the bottom left as
// in a CoreGraphics bitmap context. This file speaks only in numbers, so
// CoreGraphics' C types and Silica's never meet: Context.swift converts.

/// A path, as CGPath objects keep it and contexts take it.
enum PathCommand: Equatable {
    case move(Double, Double)
    case line(Double, Double)
    case quad(Double, Double, Double, Double)
    case curve(Double, Double, Double, Double, Double, Double)
    case close
}

final class Canvas {
    let width: Int
    let height: Int
    let surface: Cairo.Surface.Image
    let context: CairoContext

    /// A canvas drawing into `memory` itself, which must be ARGB32
    /// (`opaque`: RGB24) with the given row length; or into its own memory.
    init?(width: Int, height: Int, memory: UnsafeMutablePointer<UInt8>? = nil, bytesPerRow: Int = 0, opaque: Bool = false) {
        do {
            if let memory {
                surface = try Cairo.Surface.Image(mutableBytes: memory, format: opaque ? .rgb24 : .argb32, width: width,
                                                  height: height, stride: bytesPerRow)
            } else {
                surface = try Cairo.Surface.Image(format: .argb32, width: width, height: height)
            }
            context = try CairoContext(surface: surface, size: CGSize(width: width, height: height), flipped: false)
        } catch {
            return nil
        }
        self.width = width
        self.height = height
        context.shouldAntialias = true
    }

    /// The surface's pixels: B, G, R, A per pixel, premultiplied.
    func withPixels<T>(_ body: (UnsafeMutablePointer<UInt8>, Int) -> T) -> T? {
        context.flush()
        let stride = surface.stride
        let result = surface.withUnsafeMutableBytes { body($0, stride) }
        context.markDirty()
        return result
    }

    // MARK: State

    func save() { try? context.save() }
    func restore() { try? context.restore() }

    func setFill(_ r: Double, _ g: Double, _ b: Double, _ a: Double) { context.fillColor = CGColor(red: r, green: g, blue: b, alpha: a) }
    func setStroke(_ r: Double, _ g: Double, _ b: Double, _ a: Double) { context.strokeColor = CGColor(red: r, green: g, blue: b, alpha: a) }
    var fill: (Double, Double, Double, Double) { let c = context.fillColor; return (c.red, c.green, c.blue, c.alpha) }

    var alpha: Double {
        get { context.alpha }
        set { context.alpha = newValue }
    }

    var lineWidth: Double {
        get { context.lineWidth }
        set { context.lineWidth = newValue }
    }

    /// CGLineCap: butt 0, round 1, square 2.
    func setLineCap(_ cap: Int32) { context.lineCap = cap == 1 ? .round : cap == 2 ? .square : .butt }
    /// CGLineJoin: miter 0, round 1, bevel 2.
    func setLineJoin(_ join: Int32) { context.lineJoin = join == 1 ? .round : join == 2 ? .bevel : .miter }
    func setMiterLimit(_ limit: Double) { context.miterLimit = limit }
    func setLineDash(phase: Double, lengths: [Double]) {
        // Foundation's CGFloat: this module's own is Double.
        let dashes: [Foundation.CGFloat] = lengths.map { Foundation.CGFloat($0) }
        context.lineDash = (phase: Foundation.CGFloat(phase), lengths: dashes)
    }
    func setFlatness(_ flatness: Double) { context.tolerance = max(0.01, flatness) }
    func setAntialias(_ on: Bool) { context.shouldAntialias = on }
    func setBlendMode(_ mode: Int32) { context.blendMode = mode }

    func setShadow(dx: Double, dy: Double, blur: Double, color: (Double, Double, Double, Double)) {
        context.setShadow(offset: CGSize(width: dx, height: dy), radius: blur,
                          color: CGColor(red: color.0, green: color.1, blue: color.2, alpha: color.3))
    }

    // MARK: Transforms

    /// The base transform: user space has y up, the surface y down.
    private var base: Silica.CGAffineTransform { Silica.CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Double(height)) }

    /// The user-space transform, as CGContextGetCTM gives it (without the
    /// flip the bitmap's memory needs).
    var ctm: (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        let m = context.matrix, b = base
        // m = user × base, and base is its own inverse.
        let a = m.a * b.a + m.b * b.c, bb = m.a * b.b + m.b * b.d
        let c = m.c * b.a + m.d * b.c, d = m.c * b.b + m.d * b.d
        let tx = m.tx * b.a + m.ty * b.c + b.tx, ty = m.tx * b.b + m.ty * b.d + b.ty
        return (a, bb, c, d, tx, ty)
    }

    func concat(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ tx: Double, _ ty: Double) {
        context.concatenate(Silica.CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty))
    }

    func translate(_ x: Double, _ y: Double) { context.translateBy(x: x, y: y) }
    func scale(_ x: Double, _ y: Double) { context.scaleBy(x: x, y: y) }
    func rotate(_ angle: Double) { context.rotateBy(angle) }

    // MARK: Paths

    func beginPath() { context.beginPath() }
    func closePath() { context.closePath() }
    func move(_ x: Double, _ y: Double) { context.move(to: CGPoint(x: x, y: y)) }
    func line(_ x: Double, _ y: Double) { context.addLine(to: CGPoint(x: x, y: y)) }

    func curve(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
        context.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
    }

    func quad(_ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
        context.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }

    func arc(_ x: Double, _ y: Double, radius: Double, start: Double, end: Double, clockwise: Bool) {
        context.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
    }

    func arc(tangent1 x1: Double, _ y1: Double, tangent2 x2: Double, _ y2: Double, radius: Double) {
        context.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x2, y: y2), radius: radius)
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { context.addRect(CGRect(x: x, y: y, width: w, height: h)) }
    func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { context.addEllipse(in: CGRect(x: x, y: y, width: w, height: h)) }

    func add(_ commands: [PathCommand]) {
        for command in commands {
            switch command {
            case .move(let x, let y): move(x, y)
            case .line(let x, let y): line(x, y)
            case .quad(let cx, let cy, let x, let y): quad(cx, cy, x, y)
            case .curve(let a, let b, let c, let d, let x, let y): curve(a, b, c, d, x, y)
            case .close: closePath()
            }
        }
    }

    var isPathEmpty: Bool { context.isPathEmpty }

    var currentPoint: (Double, Double)? { context.currentPoint.map { ($0.x, $0.y) } }

    var pathBounds: (Double, Double, Double, Double) {
        let r = context.pathBoundingBox
        return (r.origin.x, r.origin.y, r.size.width, r.size.height)
    }

    func pathContains(_ x: Double, _ y: Double, evenOdd: Bool) -> Bool { context.pathContains(CGPoint(x: x, y: y), evenOdd: evenOdd) }

    // MARK: Painting

    func fillPath(evenOdd: Bool) { context.fillPath(evenOdd: evenOdd, preserve: false) }

    func strokePath() {
        context.strokePath()
        context.beginPath()
    }

    /// CGPathDrawingMode: fill 0, even-odd fill 1, stroke 2, fill and stroke 3, even-odd fill and stroke 4.
    func drawPath(_ mode: Int32) {
        switch mode {
        case 0, 1: fillPath(evenOdd: mode == 1)
        case 2: strokePath()
        default:
            context.fillPath(evenOdd: mode == 4, preserve: true)
            strokePath()
        }
    }

    func clip(evenOdd: Bool) {
        context.clip(evenOdd: evenOdd)
        context.beginPath()
    }

    func clear(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { context.clear(rect: CGRect(x: x, y: y, width: w, height: h)) }

    /// Premultiplied RGBA, rows from the top, upright in the rect.
    func draw(_ bitmap: Bitmap, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let image = Silica.CGImage(width: bitmap.width, height: bitmap.height, data: Data(bitmap.pixels))
        context.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
    }

    func linearGradient(_ stops: [(Double, (Double, Double, Double, Double))], from: (Double, Double), to: (Double, Double), extend: Bool) {
        context.drawLinearGradient(stops: stops.map { ($0.0, CGColor(red: $0.1.0, green: $0.1.1, blue: $0.1.2, alpha: $0.1.3)) },
                                   start: CGPoint(x: from.0, y: from.1), end: CGPoint(x: to.0, y: to.1), extend: extend)
    }

    func radialGradient(_ stops: [(Double, (Double, Double, Double, Double))], from: (Double, Double), radius r1: Double,
                        to: (Double, Double), radius r2: Double, extend: Bool) {
        context.drawRadialGradient(stops: stops.map { ($0.0, CGColor(red: $0.1.0, green: $0.1.1, blue: $0.1.2, alpha: $0.1.3)) },
                                   startCenter: CGPoint(x: from.0, y: from.1), startRadius: r1,
                                   endCenter: CGPoint(x: to.0, y: to.1), endRadius: r2, extend: extend)
    }

    func beginLayer() { context.beginTransparencyLayer(in: nil, auxiliaryInfo: nil) }
    func endLayer() { context.endTransparencyLayer() }

    // MARK: Text

    /// A font by its PostScript or family name, through FontConfig.
    func selectFont(_ name: String, size: Double) -> Bool {
        guard let font = Silica.CGFont(name: name) ?? Silica.CGFont(name: "Helvetica") else { return false }
        context.setFont(font)
        context.fontSize = size
        return true
    }

    func setFontSize(_ size: Double) { context.fontSize = size }
    func setCharacterSpacing(_ spacing: Double) { context.characterSpacing = spacing }

    var textPosition: (Double, Double) {
        get { (context.textPosition.x, context.textPosition.y) }
        set { context.textPosition = CGPoint(x: newValue.0, y: newValue.1) }
    }

    func setTextMatrix(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ tx: Double, _ ty: Double) {
        context.textMatrix = Silica.CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    func showText(_ text: String) { context.show(text: text) }
}
