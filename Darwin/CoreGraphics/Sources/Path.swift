import Foundation

public enum CGPathFillRule: Int {
    case winding
    case evenOdd
}

extension CGPath {
    public func copy(dashingWithPhase phase: CGFloat, lengths: [CGFloat], transform: CGAffineTransform = .identity) -> CGPath {
        var transform = transform
        // Dashing with no lengths leaves the path as it is.
        return CGPath(__byDashing: self, transform: &transform, phase: phase, lengths: lengths, count: lengths.count) ?? self
    }

    public func copy(strokingWithWidth lineWidth: CGFloat, lineCap: CGLineCap, lineJoin: CGLineJoin,
                     miterLimit: CGFloat, transform: CGAffineTransform = .identity) -> CGPath {
        var transform = transform
        return CGPath(__byStroking: self, transform: &transform, lineWidth: lineWidth, lineCap: lineCap,
                      lineJoin: lineJoin, miterLimit: miterLimit) ?? CGMutablePath()
    }

    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool {
        var transform = transform
        return __containsPoint(transform: &transform, point: point, eoFill: rule == .evenOdd)
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension CGPath {
    public func union(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        __union(other: other, eoFill: rule == .evenOdd) ?? CGMutablePath()
    }

    public func intersection(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        __intersection(other: other, eoFill: rule == .evenOdd) ?? CGMutablePath()
    }

    public func subtracting(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        __subtracting(other: other, eoFill: rule == .evenOdd) ?? CGMutablePath()
    }

    public func symmetricDifference(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        __symmetricDifference(other: other, eoFill: rule == .evenOdd) ?? CGMutablePath()
    }

    public func lineSubtracting(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        __lineSubtracting(other: other, eoFill: rule == .evenOdd) ?? CGMutablePath()
    }

    public func lineIntersection(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
        __lineIntersection(other: other, eoFill: rule == .evenOdd) ?? CGMutablePath()
    }

    public func normalized(using rule: CGPathFillRule = .winding) -> CGPath {
        __normalized(eoFill: rule == .evenOdd) ?? self
    }

    public func flattened(threshold: CGFloat) -> CGPath {
        __flattened(threshold: threshold) ?? self
    }

    public func intersects(_ other: CGPath, using rule: CGPathFillRule = .winding) -> Bool {
        __intersects(other: other, eoFill: rule == .evenOdd)
    }

    public func componentsSeparated(using rule: CGPathFillRule = .winding) -> [CGPath] {
        guard let components = __componentsSeparated(eoFill: rule == .evenOdd) else { return [] }
        return (0 ..< CFArrayGetCount(components)).map {
            unsafeBitCast(CFArrayGetValueAtIndex(components, $0), to: CGPath.self)
        }
    }
}

extension CGMutablePath {
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addRoundedRect(transform: &transform, rect: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }

    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) {
        var transform = transform
        __moveTo(transform: &transform, x: point.x, y: point.y)
    }

    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addLineTo(transform: &transform, x: point.x, y: point.y)
    }

    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addQuadCurve(transform: &transform, cpx: control.x, cpy: control.y, endingAtX: end.x, y: end.y)
    }

    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addCurve(transform: &transform, cp1x: control1.x, cp1y: control1.y, cp2x: control2.x, cp2y: control2.y,
                   endingAtX: end.x, y: end.y)
    }

    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addRect(transform: &transform, rect: rect)
    }

    public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        var transform = transform
        __addRects(transform: &transform, rects: rects, count: rects.count)
    }

    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) {
        var transform = transform
        __addLines(transform: &transform, between: points, count: points.count)
    }

    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addEllipse(transform: &transform, rect: rect)
    }

    public func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, delta: CGFloat, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addRelativeArc(transform: &transform, x: center.x, y: center.y, radius: radius, startAngle: startAngle, delta: delta)
    }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool,
                       transform: CGAffineTransform = .identity) {
        var transform = transform
        __addArc(transform: &transform, x: center.x, y: center.y, radius: radius, startAngle: startAngle,
                 endAngle: endAngle, clockwise: clockwise)
    }

    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addArc(transform: &transform, x1: tangent1End.x, y1: tangent1End.y, x2: tangent2End.x, y2: tangent2End.y, radius: radius)
    }

    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) {
        var transform = transform
        __addPath(transform: &transform, path: path)
    }
}

// The C forms of before.

@available(*, unavailable, message: "Use copy(byDashingWithPhase:lengths:transform:)")
public func CGPathCreateCopyByDashingPath(_ path: CGPath?, _ transform: UnsafePointer<CGAffineTransform>, _ phase: CGFloat,
                                          _ lengths: UnsafePointer<CGFloat>, _ count: Int) -> CGPath? {
    guard let path else { return nil }
    return CGPath(__byDashing: path, transform: transform, phase: phase, lengths: lengths, count: count)
}

@available(*, unavailable, message: "Use copy(byStroking:lineWidth:lineCap:lineJoin:miterLimit:transform:)")
public func CGPathCreateCopyByStrokingPath(_ path: CGPath?, _ transform: UnsafePointer<CGAffineTransform>, _ lineWidth: CGFloat,
                                           _ lineCap: CGLineCap, _ lineJoin: CGLineJoin, _ miterLimit: CGFloat) -> CGPath? {
    guard let path else { return nil }
    return CGPath(__byStroking: path, transform: transform, lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, miterLimit: miterLimit)
}

@available(*, unavailable, message: "Use == instead")
public func CGPathEqualToPath(_ path1: CGPath?, _ path2: CGPath?) -> Bool {
    guard let path1, let path2 else { return path1 == nil && path2 == nil }
    return path1.__equalTo(path2)
}

@available(*, unavailable, message: "Use move(to:transform:)")
public func CGPathMoveToPoint(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ x: CGFloat, _ y: CGFloat) {
    path?.__moveTo(transform: m, x: x, y: y)
}

@available(*, unavailable, message: "Use addLine(to:transform:)")
public func CGPathAddLineToPoint(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ x: CGFloat, _ y: CGFloat) {
    path?.__addLineTo(transform: m, x: x, y: y)
}

@available(*, unavailable, message: "Use addCurve(to:control1:control2:transform:)")
public func CGPathAddCurveToPoint(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ cp1x: CGFloat, _ cp1y: CGFloat,
                                  _ cp2x: CGFloat, _ cp2y: CGFloat, _ x: CGFloat, _ y: CGFloat) {
    path?.__addCurve(transform: m, cp1x: cp1x, cp1y: cp1y, cp2x: cp2x, cp2y: cp2y, endingAtX: x, y: y)
}

@available(*, unavailable, message: "Use addQuadCurve(to:control:transform:)")
public func CGPathAddQuadCurveToPoint(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ cpx: CGFloat, _ cpy: CGFloat,
                                      _ x: CGFloat, _ y: CGFloat) {
    path?.__addQuadCurve(transform: m, cpx: cpx, cpy: cpy, endingAtX: x, y: y)
}

@available(*, unavailable, message: "Use addRect(_:transform:)")
public func CGPathAddRect(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ rect: CGRect) {
    path?.__addRect(transform: m, rect: rect)
}

@available(*, unavailable, message: "Use addRects(_:transform:)")
public func CGPathAddRects(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ rects: UnsafePointer<CGRect>, _ count: Int) {
    path?.__addRects(transform: m, rects: rects, count: count)
}

@available(*, unavailable, message: "Use addLines(between:transform:)")
public func CGPathAddLines(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ points: UnsafePointer<CGPoint>, _ count: Int) {
    path?.__addLines(transform: m, between: points, count: count)
}

@available(*, unavailable, message: "Use addEllipse(rect:transform:)")
public func CGPathAddEllipseInRect(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ rect: CGRect) {
    path?.__addEllipse(transform: m, rect: rect)
}

@available(*, unavailable, message: "Use addRelativeArc(center:radius:startAngle:delta:transform:)")
public func CGPathAddRelativeArc(_ path: CGMutablePath?, _ matrix: UnsafePointer<CGAffineTransform>, _ x: CGFloat, _ y: CGFloat,
                                 _ radius: CGFloat, _ startAngle: CGFloat, _ delta: CGFloat) {
    path?.__addRelativeArc(transform: matrix, x: x, y: y, radius: radius, startAngle: startAngle, delta: delta)
}

@available(*, unavailable, message: "Use addArc(center:radius:startAngle:endAngle:clockwise:transform:)")
public func CGPathAddArc(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat,
                         _ startAngle: CGFloat, _ endAngle: CGFloat, _ clockwise: Bool) {
    path?.__addArc(transform: m, x: x, y: y, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
}

@available(*, unavailable, message: "Use addArc(tangent1End:tangent2End:radius:transform:)")
public func CGPathAddArcToPoint(_ path: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ x1: CGFloat, _ y1: CGFloat,
                                _ x2: CGFloat, _ y2: CGFloat, _ radius: CGFloat) {
    path?.__addArc(transform: m, x1: x1, y1: y1, x2: x2, y2: y2, radius: radius)
}

@available(*, unavailable, message: "Use addPath(_:transform:)")
public func CGPathAddPath(_ path1: CGMutablePath?, _ m: UnsafePointer<CGAffineTransform>, _ path2: CGPath?) {
    guard let path2 else { return }
    path1?.__addPath(transform: m, path: path2)
}
