import CPerryGeometry
import Glibc
import PerryObjCInterop

// CAShapeLayer: a path, filled then stroked over the layer's background
// and under its sublayers. Only the part of the stroke between strokeStart
// and strokeEnd is drawn, measured along the path's length, as progress
// rings use it; both animate, as do the line width and the colors.

final class ShapeLayerState: ObjectState {
    var path: CGRef?
    var fillColor: CGRef? = CG.colorCreateGenericGray(0, 1)
    var strokeColor: CGRef?
    var lineWidth: CGFloat = 1
    var miterLimit: CGFloat = 10
    var lineCap = "butt"
    var lineJoin = "miter"
    var fillRule = "non-zero"
    var strokeStart: CGFloat = 0
    var strokeEnd: CGFloat = 1
    var lineDashPhase: CGFloat = 0
    var lineDashPattern: NSObject?

    deinit {
        for object in [path, fillColor, strokeColor] { if let object { CG.release(object) } }
    }

    /// A copy to present, with the path and colors retained again.
    func copy() -> ShapeLayerState {
        let copy = ShapeLayerState()
        LayerState.setColor(&copy.path, path)
        LayerState.setColor(&copy.fillColor, fillColor)
        LayerState.setColor(&copy.strokeColor, strokeColor)
        (copy.lineWidth, copy.miterLimit, copy.lineCap, copy.lineJoin, copy.fillRule) = (lineWidth, miterLimit, lineCap, lineJoin, fillRule)
        (copy.strokeStart, copy.strokeEnd, copy.lineDashPhase, copy.lineDashPattern) = (strokeStart, strokeEnd, lineDashPhase, lineDashPattern)
        return copy
    }
}

@ObjCClass("CAShapeLayer")
open class CAShapeLayer: CALayer {
    static let shapeStates = StateTable<ShapeLayerState>()
    var shape: ShapeLayerState { CAShapeLayer.shapeStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        CAShapeLayer.shapeStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("path") func path() -> UnsafeMutableRawPointer? { shape.path }
    @ObjCMethod("setPath:") func setPath(_ path: UnsafeMutableRawPointer?) { change("path") { LayerState.setColor(&shape.path, path) } }
    @ObjCMethod("fillColor") func fillColor() -> UnsafeMutableRawPointer? { shape.fillColor }
    @ObjCMethod("setFillColor:") func setFillColor(_ color: UnsafeMutableRawPointer?) { change("fillColor") { LayerState.setColor(&shape.fillColor, color) } }
    @ObjCMethod("strokeColor") func strokeColor() -> UnsafeMutableRawPointer? { shape.strokeColor }
    @ObjCMethod("setStrokeColor:")
    func setStrokeColor(_ color: UnsafeMutableRawPointer?) { change("strokeColor") { LayerState.setColor(&shape.strokeColor, color) } }
    @ObjCMethod("lineWidth") func lineWidth() -> CGFloat { shape.lineWidth }
    @ObjCMethod("setLineWidth:") func setLineWidth(_ width: CGFloat) { change("lineWidth") { shape.lineWidth = width } }
    @ObjCMethod("miterLimit") func miterLimit() -> CGFloat { shape.miterLimit }
    @ObjCMethod("setMiterLimit:") func setMiterLimit(_ limit: CGFloat) { change("miterLimit") { shape.miterLimit = limit } }
    @ObjCMethod("lineCap") func lineCap() -> String { shape.lineCap }
    @ObjCMethod("setLineCap:") func setLineCap(_ cap: String) { changed { shape.lineCap = cap } }
    @ObjCMethod("lineJoin") func lineJoin() -> String { shape.lineJoin }
    @ObjCMethod("setLineJoin:") func setLineJoin(_ join: String) { changed { shape.lineJoin = join } }
    @ObjCMethod("fillRule") func fillRule() -> String { shape.fillRule }
    @ObjCMethod("setFillRule:") func setFillRule(_ rule: String) { changed { shape.fillRule = rule } }
    @ObjCMethod("strokeStart") func strokeStart() -> CGFloat { shape.strokeStart }
    @ObjCMethod("setStrokeStart:") func setStrokeStart(_ start: CGFloat) { change("strokeStart") { shape.strokeStart = start } }
    @ObjCMethod("strokeEnd") func strokeEnd() -> CGFloat { shape.strokeEnd }
    @ObjCMethod("setStrokeEnd:") func setStrokeEnd(_ end: CGFloat) { change("strokeEnd") { shape.strokeEnd = end } }
    @ObjCMethod("lineDashPhase") func lineDashPhase() -> CGFloat { shape.lineDashPhase }
    @ObjCMethod("setLineDashPhase:") func setLineDashPhase(_ phase: CGFloat) { change("lineDashPhase") { shape.lineDashPhase = phase } }
    @ObjCMethod("lineDashPattern") func lineDashPattern() -> NSObject? { shape.lineDashPattern }
    @ObjCMethod("setLineDashPattern:") func setLineDashPattern(_ pattern: NSObject?) { changed { shape.lineDashPattern = pattern } }

    /// Fills the path, then strokes the part between strokeStart and
    /// strokeEnd, as `shape` presents them.
    func drawShape(_ shape: ShapeLayerState, in context: CGRef) {
        guard let path = shape.path, !CG.pathIsEmpty(path) else { return }
        if let fill = shape.fillColor {
            CG.setFillColorWithColor(context, fill)
            CG.addPath(context, path)
            if shape.fillRule == "even-odd" { CG.eoFillPath(context) } else { CG.fillPath(context) }
        }
        guard let stroke = shape.strokeColor, shape.lineWidth > 0 else { return }
        let start = min(max(shape.strokeStart, 0), 1), end = min(max(shape.strokeEnd, 0), 1)
        guard end > start else { return }
        let trimmed = start > 0 || end < 1 ? PathTrimming.trim(path, from: start, to: end) : nil
        defer { if let trimmed { CG.release(trimmed) } }
        CG.saveGState(context)
        defer { CG.restoreGState(context) }
        CG.setStrokeColorWithColor(context, stroke)
        CG.setLineWidth(context, shape.lineWidth)
        CG.setMiterLimit(context, shape.miterLimit)
        // CGLineCap: butt 0, round 1, square 2; CGLineJoin: miter 0, round 1, bevel 2.
        CG.setLineCap(context, shape.lineCap == "round" ? 1 : shape.lineCap == "square" ? 2 : 0)
        CG.setLineJoin(context, shape.lineJoin == "round" ? 1 : shape.lineJoin == "bevel" ? 2 : 0)
        let dashes = shape.lineDashPattern?.as(NSArray.self)?.elements.map { $0.sendDoubleValue() } ?? []
        if !dashes.isEmpty { dashes.withUnsafeBufferPointer { CG.setLineDash(context, shape.lineDashPhase, $0.baseAddress, $0.count) } }
        CG.addPath(context, trimmed ?? path)
        CG.strokePath(context)
    }
}

/// The part of a path between two fractions of its length, and the point
/// a fraction along it, with curves followed as short lines.
enum PathTrimming {
    /// The path as polylines, one per subpath.
    nonisolated(unsafe) private static var polylines: [[CGPoint]] = []

    private static let collect: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { _, element in
        guard let element else { return }
        let type = element.load(as: Int32.self)
        let points = element.load(fromByteOffset: 8, as: UnsafePointer<CGPoint>.self)
        let current = PathTrimming.polylines.last?.last ?? .zero
        func sample(_ count: Int, _ point: (CGFloat) -> CGPoint) {
            for step in 1...count { PathTrimming.polylines[PathTrimming.polylines.count - 1].append(point(CGFloat(step) / CGFloat(count))) }
        }
        switch type {
        case 0: PathTrimming.polylines.append([points[0]])
        case 1:
            if PathTrimming.polylines.isEmpty { PathTrimming.polylines.append([.zero]) }
            PathTrimming.polylines[PathTrimming.polylines.count - 1].append(points[0])
        case 2:
            if PathTrimming.polylines.isEmpty { PathTrimming.polylines.append([.zero]) }
            let (c, e) = (points[0], points[1])
            sample(16) { t in
                let u = 1 - t
                return CGPoint(x: u * u * current.x + 2 * u * t * c.x + t * t * e.x, y: u * u * current.y + 2 * u * t * c.y + t * t * e.y)
            }
        case 3:
            if PathTrimming.polylines.isEmpty { PathTrimming.polylines.append([.zero]) }
            let (c1, c2, e) = (points[0], points[1], points[2])
            sample(24) { t in
                let u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                return CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * e.x, y: a * current.y + b * c1.y + c * c2.y + d * e.y)
            }
        case 4:
            if let first = PathTrimming.polylines.last?.first { PathTrimming.polylines[PathTrimming.polylines.count - 1].append(first) }
        default: break
        }
    }

    /// The path's subpaths as polylines.
    static func lines(of path: CGRef) -> [[CGPoint]] {
        polylines = []
        CG.pathApply(path, nil, collect)
        defer { polylines = [] }
        return polylines
    }

    /// The point `fraction` of the way along the path, by length.
    static func point(at fraction: CGFloat, along path: UnsafeMutableRawPointer) -> CGPoint? {
        let segments = lines(of: path).flatMap { line in zip(line, line.dropFirst()).map { ($0, $1) } }
        let total = segments.reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard total > 0 else { return lines(of: path).first?.first }
        var remaining = min(max(fraction, 0), 1) * total
        for (a, b) in segments {
            let length = hypot(b.x - a.x, b.y - a.y)
            if remaining <= length, length > 0 {
                return CGPoint(x: a.x + (b.x - a.x) * remaining / length, y: a.y + (b.y - a.y) * remaining / length)
            }
            remaining -= length
        }
        return segments.last?.1
    }

    /// A new path, +1, of the stretch from `start` to `end` of the length.
    static func trim(_ path: CGRef, from start: CGFloat, to end: CGFloat) -> CGRef? {
        let lines = lines(of: path)
        let total = lines.reduce(0) { sum, line in sum + zip(line, line.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } }
        guard total > 0, let trimmed = CG.pathCreateMutable() else { return nil }
        let from = start * total, to = end * total
        var travelled: CGFloat = 0
        for line in lines {
            var drawing = false
            for (a, b) in zip(line, line.dropFirst()) {
                let length = hypot(b.x - a.x, b.y - a.y)
                defer { travelled += length }
                guard length > 0, travelled + length > from, travelled < to else { continue }
                func point(_ distance: CGFloat) -> CGPoint {
                    let t = min(max((distance - travelled) / length, 0), 1)
                    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                if !drawing {
                    let first = point(max(from, travelled))
                    CG.pathMoveToPoint(trimmed, nil, first.x, first.y)
                    drawing = true
                }
                let last = point(min(to, travelled + length))
                CG.pathAddLineToPoint(trimmed, nil, last.x, last.y)
            }
        }
        return trimmed
    }
}
