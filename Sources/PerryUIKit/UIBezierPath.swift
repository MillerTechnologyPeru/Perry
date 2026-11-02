import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIBezierPath: a CGPath with the attributes it fills and strokes with,
// drawing into the current context.

final class BezierPathState: ObjectState {
    var path: CGRef = CG.pathCreateMutable()!
    var lineWidth: CGFloat = 1
    var lineCap: Int32 = 0
    var lineJoin: Int32 = 0
    var miterLimit: CGFloat = 10
    var flatness: CGFloat = 0.6
    var usesEvenOddFillRule = false
    var dash: [CGFloat] = []
    var dashPhase: CGFloat = 0

    deinit { CG.release(path) }

    func replacePath(_ path: CGRef) {
        CG.release(self.path)
        self.path = path
    }

    func copyAttributes(from other: BezierPathState) {
        (lineWidth, lineCap, lineJoin, miterLimit, flatness) = (other.lineWidth, other.lineCap, other.lineJoin, other.miterLimit, other.flatness)
        (usesEvenOddFillRule, dash, dashPhase) = (other.usesEvenOddFillRule, other.dash, other.dashPhase)
    }
}

@ObjCClass("UIBezierPath")
open class UIBezierPath: NSObject {
    static let states = StateTable<BezierPathState>()
    var state: BezierPathState { UIBezierPath.states[objcObject] }

    /// A new path of class `cls`, built by `build`.
    static func make(_ cls: ObjCClass, _ build: (CGRef) -> Void = { _ in }) -> UIBezierPath {
        let path = cls.object.allocated().unsafeCast(to: UIBezierPath.self)
        build(path.state.path)
        return path
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIBezierPath.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIBezierPath.objCClass.pointer)
    }

    // MARK: Making paths

    @ObjCClassMethod("bezierPath") static func bezierPath(_ cls: ObjCClass) -> UIBezierPath { make(cls) }

    @ObjCClassMethod("bezierPathWithRect:")
    static func bezierPath(_ cls: ObjCClass, rect: CGRect) -> UIBezierPath {
        make(cls) { path in
            CG.pathMoveToPoint(path, nil, rect.minX, rect.minY)
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.minY)
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.maxY)
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.maxY)
            CG.pathCloseSubpath(path)
        }
    }

    @ObjCClassMethod("bezierPathWithOvalInRect:")
    static func bezierPath(_ cls: ObjCClass, ovalIn rect: CGRect) -> UIBezierPath {
        make(cls) { CG.pathAddEllipseInRect($0, nil, rect) }
    }

    @ObjCClassMethod("bezierPathWithRoundedRect:cornerRadius:")
    static func bezierPath(_ cls: ObjCClass, roundedRect rect: CGRect, cornerRadius radius: CGFloat) -> UIBezierPath {
        make(cls) { UIBezierPath.addRoundedRect($0, rect, corners: 0xf, radii: CGSize(width: radius, height: radius)) }
    }

    @ObjCClassMethod("bezierPathWithRoundedRect:byRoundingCorners:cornerRadii:")
    static func bezierPath(_ cls: ObjCClass, roundedRect rect: CGRect, byRoundingCorners corners: UInt, cornerRadii: CGSize) -> UIBezierPath {
        make(cls) { UIBezierPath.addRoundedRect($0, rect, corners: corners, radii: cornerRadii) }
    }

    /// UIKit's clockwise is in its flipped coordinates: CoreGraphics'
    /// counterclockwise.
    @ObjCClassMethod("bezierPathWithArcCenter:radius:startAngle:endAngle:clockwise:")
    static func bezierPath(_ cls: ObjCClass, arcCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat,
                           clockwise: Bool) -> UIBezierPath {
        make(cls) { CG.pathAddArc($0, nil, center.x, center.y, radius, startAngle, endAngle, !clockwise) }
    }

    @ObjCClassMethod("bezierPathWithCGPath:")
    static func bezierPath(_ cls: ObjCClass, cgPath: UnsafeMutableRawPointer?) -> UIBezierPath {
        make(cls) { CG.pathAddPath($0, nil, cgPath) }
    }

    /// A rounded rectangle, with the radii limited to half the sides.
    static func addRoundedRect(_ path: CGRef, _ rect: CGRect, corners: UInt, radii: CGSize) {
        let r = min(max(radii.width, 0), rect.width / 2, rect.height / 2)
        guard r > 0 else {
            CG.pathAddRect(path, nil, rect)
            return
        }
        let (topLeft, topRight, bottomLeft, bottomRight) = (corners & 1 != 0, corners & 2 != 0, corners & 4 != 0, corners & 8 != 0)
        CG.pathMoveToPoint(path, nil, rect.minX + (topLeft ? r : 0), rect.minY)
        if topRight {
            CG.pathAddLineToPoint(path, nil, rect.maxX - r, rect.minY)
            CG.pathAddArc(path, nil, rect.maxX - r, rect.minY + r, r, -.pi / 2, 0, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.minY)
        }
        if bottomRight {
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.maxY - r)
            CG.pathAddArc(path, nil, rect.maxX - r, rect.maxY - r, r, 0, .pi / 2, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.maxX, rect.maxY)
        }
        if bottomLeft {
            CG.pathAddLineToPoint(path, nil, rect.minX + r, rect.maxY)
            CG.pathAddArc(path, nil, rect.minX + r, rect.maxY - r, r, .pi / 2, .pi, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.maxY)
        }
        if topLeft {
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.minY + r)
            CG.pathAddArc(path, nil, rect.minX + r, rect.minY + r, r, .pi, 3 * .pi / 2, false)
        } else {
            CG.pathAddLineToPoint(path, nil, rect.minX, rect.minY)
        }
        CG.pathCloseSubpath(path)
    }

    // MARK: Building

    @ObjCMethod("moveToPoint:")
    func move(to point: CGPoint) { CG.pathMoveToPoint(state.path, nil, point.x, point.y) }

    @ObjCMethod("addLineToPoint:")
    func addLine(to point: CGPoint) { CG.pathAddLineToPoint(state.path, nil, point.x, point.y) }

    @ObjCMethod("addCurveToPoint:controlPoint1:controlPoint2:")
    func addCurve(to point: CGPoint, controlPoint1 c1: CGPoint, controlPoint2 c2: CGPoint) {
        CG.pathAddCurveToPoint(state.path, nil, c1.x, c1.y, c2.x, c2.y, point.x, point.y)
    }

    @ObjCMethod("addQuadCurveToPoint:controlPoint:")
    func addQuadCurve(to point: CGPoint, controlPoint c: CGPoint) {
        CG.pathAddQuadCurveToPoint(state.path, nil, c.x, c.y, point.x, point.y)
    }

    @ObjCMethod("addArcWithCenter:radius:startAngle:endAngle:clockwise:")
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        CG.pathAddArc(state.path, nil, center.x, center.y, radius, startAngle, endAngle, !clockwise)
    }

    @ObjCMethod("closePath") func closePath() { CG.pathCloseSubpath(state.path) }

    @ObjCMethod("removeAllPoints") func removeAllPoints() { state.replacePath(CG.pathCreateMutable()!) }

    @ObjCMethod("appendPath:")
    func append(_ other: UIBezierPath) { CG.pathAddPath(state.path, nil, other.state.path) }

    @ObjCMethod("applyTransform:")
    func apply(_ transform: CGAffineTransform) {
        var transform = transform
        guard let transformed = CG.pathCreateCopyByTransformingPath(state.path, &transform) else { return }
        defer { CG.release(transformed) }
        state.replacePath(CG.pathCreateMutableCopy(transformed)!)
    }

    @ObjCMethod("CGPath") func cgPath() -> UnsafeMutableRawPointer? { state.path }

    @ObjCMethod("setCGPath:")
    func setCGPath(_ path: UnsafeMutableRawPointer?) {
        guard let path, let copy = CG.pathCreateMutableCopy(path) else { return }
        state.replacePath(copy)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = UIBezierPath.make(objCClass) { CG.pathAddPath($0, nil, state.path) }
        copy.state.copyAttributes(from: state)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    // MARK: Inspecting

    @ObjCMethod("bounds") func bounds() -> CGRect { CG.pathGetBoundingBox(state.path) }
    @ObjCMethod("currentPoint") func currentPoint() -> CGPoint { CG.pathGetCurrentPoint(state.path) }
    @ObjCMethod("isEmpty") func isEmpty() -> Bool { CG.pathIsEmpty(state.path) }

    @ObjCMethod("containsPoint:")
    func contains(_ point: CGPoint) -> Bool { CG.pathContainsPoint(state.path, nil, point, state.usesEvenOddFillRule) }

    // MARK: Attributes

    @ObjCMethod("lineWidth") func lineWidth() -> CGFloat { state.lineWidth }
    @ObjCMethod("setLineWidth:") func setLineWidth(_ width: CGFloat) { state.lineWidth = width }
    @ObjCMethod("lineCapStyle") func lineCapStyle() -> Int32 { state.lineCap }
    @ObjCMethod("setLineCapStyle:") func setLineCapStyle(_ cap: Int32) { state.lineCap = cap }
    @ObjCMethod("lineJoinStyle") func lineJoinStyle() -> Int32 { state.lineJoin }
    @ObjCMethod("setLineJoinStyle:") func setLineJoinStyle(_ join: Int32) { state.lineJoin = join }
    @ObjCMethod("miterLimit") func miterLimit() -> CGFloat { state.miterLimit }
    @ObjCMethod("setMiterLimit:") func setMiterLimit(_ limit: CGFloat) { state.miterLimit = limit }
    @ObjCMethod("flatness") func flatness() -> CGFloat { state.flatness }
    @ObjCMethod("setFlatness:") func setFlatness(_ flatness: CGFloat) { state.flatness = flatness }
    @ObjCMethod("usesEvenOddFillRule") func usesEvenOddFillRule() -> Bool { state.usesEvenOddFillRule }
    @ObjCMethod("setUsesEvenOddFillRule:") func setUsesEvenOddFillRule(_ evenOdd: Bool) { state.usesEvenOddFillRule = evenOdd }

    @ObjCMethod("setLineDash:count:phase:")
    func setLineDash(_ pattern: UnsafePointer<CGFloat>?, count: Int, phase: CGFloat) {
        state.dash = pattern.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
        state.dashPhase = phase
    }

    // MARK: Drawing

    @ObjCMethod("fill")
    func fill() {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        fill(in: context)
        CG.restoreGState(context)
    }

    @ObjCMethod("fillWithBlendMode:alpha:")
    func fill(blendMode: Int32, alpha: CGFloat) {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.setAlpha(context, alpha)
        fill(in: context)
        CG.restoreGState(context)
    }

    @ObjCMethod("stroke")
    func stroke() {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        stroke(in: context)
        CG.restoreGState(context)
    }

    @ObjCMethod("strokeWithBlendMode:alpha:")
    func stroke(blendMode: Int32, alpha: CGFloat) {
        guard let context = Graphics.current else { return }
        CG.saveGState(context)
        CG.setBlendMode(context, blendMode)
        CG.setAlpha(context, alpha)
        stroke(in: context)
        CG.restoreGState(context)
    }

    /// Intersects the current context's clip with the path.
    @ObjCMethod("addClip")
    func addClip() {
        guard let context = Graphics.current else { return }
        CG.addPath(context, state.path)
        if state.usesEvenOddFillRule { CG.eoClip(context) } else { CG.clip(context) }
    }

    private func fill(in context: CGRef) {
        CG.addPath(context, state.path)
        if state.usesEvenOddFillRule { CG.eoFillPath(context) } else { CG.fillPath(context) }
    }

    private func stroke(in context: CGRef) {
        let state = state
        CG.setLineWidth(context, state.lineWidth)
        CG.setLineCap(context, state.lineCap)
        CG.setLineJoin(context, state.lineJoin)
        CG.setMiterLimit(context, state.miterLimit)
        if !state.dash.isEmpty { CG.setLineDash(context, state.dashPhase, state.dash, state.dash.count) }
        CG.addPath(context, state.path)
        CG.strokePath(context)
    }
}
