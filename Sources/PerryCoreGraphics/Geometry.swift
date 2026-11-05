import CPerryCoreGraphics
import CPerryGeometry
import Glibc

// CoreGraphics' geometry functions; the constants are data in
// CPerryCoreGraphics. Rects with negative sizes are standardized first, as
// CoreGraphics does.

/// CoreGraphics' scalar: double on 64-bit Darwin.
public typealias CGFloat = Double

private let null = CGRect(origin: CGPoint(x: .infinity, y: .infinity), size: CGSize(width: 0, height: 0))

private func isNull(_ rect: CGRect) -> Bool { rect.origin.x.isInfinite || rect.origin.y.isInfinite }

/// The rect with a non-negative size covering the same area.
@c(_CGRectStandardize)
public func CGRectStandardize(_ rect: CGRect) -> CGRect {
    guard !isNull(rect) else { return null }
    var result = rect
    if result.size.width < 0 {
        result.origin.x += result.size.width
        result.size.width = -result.size.width
    }
    if result.size.height < 0 {
        result.origin.y += result.size.height
        result.size.height = -result.size.height
    }
    return result
}

@c(_CGRectGetMinX) public func CGRectGetMinX(_ rect: CGRect) -> CGFloat { CGRectStandardize(rect).origin.x }
@c(_CGRectGetMinY) public func CGRectGetMinY(_ rect: CGRect) -> CGFloat { CGRectStandardize(rect).origin.y }
@c(_CGRectGetWidth) public func CGRectGetWidth(_ rect: CGRect) -> CGFloat { abs(rect.size.width) }
@c(_CGRectGetHeight) public func CGRectGetHeight(_ rect: CGRect) -> CGFloat { abs(rect.size.height) }
@c(_CGRectGetMaxX) public func CGRectGetMaxX(_ rect: CGRect) -> CGFloat { CGRectGetMinX(rect) + CGRectGetWidth(rect) }
@c(_CGRectGetMaxY) public func CGRectGetMaxY(_ rect: CGRect) -> CGFloat { CGRectGetMinY(rect) + CGRectGetHeight(rect) }
@c(_CGRectGetMidX) public func CGRectGetMidX(_ rect: CGRect) -> CGFloat { CGRectGetMinX(rect) + CGRectGetWidth(rect) / 2 }
@c(_CGRectGetMidY) public func CGRectGetMidY(_ rect: CGRect) -> CGFloat { CGRectGetMinY(rect) + CGRectGetHeight(rect) / 2 }

@c(_CGRectIsNull) public func CGRectIsNull(_ rect: CGRect) -> Bool { isNull(rect) }

@c(_CGRectIsEmpty)
public func CGRectIsEmpty(_ rect: CGRect) -> Bool {
    isNull(rect) || rect.size.width == 0 || rect.size.height == 0
}

@c(_CGRectIsInfinite)
public func CGRectIsInfinite(_ rect: CGRect) -> Bool {
    rect.size.width == .greatestFiniteMagnitude && rect.size.height == .greatestFiniteMagnitude
}

@c(_CGPointEqualToPoint)
public func CGPointEqualToPoint(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }

@c(_CGSizeEqualToSize)
public func CGSizeEqualToSize(_ a: CGSize, _ b: CGSize) -> Bool { a.width == b.width && a.height == b.height }

@c(_CGRectEqualToRect)
public func CGRectEqualToRect(_ a: CGRect, _ b: CGRect) -> Bool {
    let a = CGRectStandardize(a), b = CGRectStandardize(b)
    return CGPointEqualToPoint(a.origin, b.origin) && CGSizeEqualToSize(a.size, b.size)
}

/// Whether the point is inside: the minimum edges count, the maximum do not.
@c(_CGRectContainsPoint)
public func CGRectContainsPoint(_ rect: CGRect, _ point: CGPoint) -> Bool {
    guard !isNull(rect) else { return false }
    return point.x >= CGRectGetMinX(rect) && point.x < CGRectGetMaxX(rect)
        && point.y >= CGRectGetMinY(rect) && point.y < CGRectGetMaxY(rect)
}

@c(_CGRectContainsRect)
public func CGRectContainsRect(_ rect: CGRect, _ other: CGRect) -> Bool {
    CGRectEqualToRect(CGRectUnion(rect, other), rect)
}

/// The overlap, or CGRectNull when there is none.
@c(_CGRectIntersection)
public func CGRectIntersection(_ a: CGRect, _ b: CGRect) -> CGRect {
    guard !isNull(a), !isNull(b) else { return null }
    let minX = max(CGRectGetMinX(a), CGRectGetMinX(b)), maxX = min(CGRectGetMaxX(a), CGRectGetMaxX(b))
    let minY = max(CGRectGetMinY(a), CGRectGetMinY(b)), maxY = min(CGRectGetMaxY(a), CGRectGetMaxY(b))
    guard minX < maxX, minY < maxY else { return null }
    return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
}

@c(_CGRectIntersectsRect)
public func CGRectIntersectsRect(_ a: CGRect, _ b: CGRect) -> Bool { !isNull(CGRectIntersection(a, b)) }

/// The smallest rect containing both; a null rect contributes nothing.
@c(_CGRectUnion)
public func CGRectUnion(_ a: CGRect, _ b: CGRect) -> CGRect {
    if isNull(a) { return CGRectStandardize(b) }
    if isNull(b) { return CGRectStandardize(a) }
    let minX = min(CGRectGetMinX(a), CGRectGetMinX(b)), maxX = max(CGRectGetMaxX(a), CGRectGetMaxX(b))
    let minY = min(CGRectGetMinY(a), CGRectGetMinY(b)), maxY = max(CGRectGetMaxY(a), CGRectGetMaxY(b))
    return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
}

@c(_CGRectOffset)
public func CGRectOffset(_ rect: CGRect, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
    guard !isNull(rect) else { return null }
    var result = CGRectStandardize(rect)
    result.origin.x += dx
    result.origin.y += dy
    return result
}

/// Shrinks (or with negative insets grows) each side; CGRectNull when
/// nothing is left.
@c(_CGRectInset)
public func CGRectInset(_ rect: CGRect, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
    guard !isNull(rect) else { return null }
    var result = CGRectStandardize(rect)
    result.origin.x += dx
    result.origin.y += dy
    result.size.width -= 2 * dx
    result.size.height -= 2 * dy
    guard result.size.width >= 0, result.size.height >= 0 else { return null }
    return result
}

/// The smallest rect with integral edges that contains the rect.
@c(_CGRectIntegral)
public func CGRectIntegral(_ rect: CGRect) -> CGRect {
    guard !isNull(rect) else { return null }
    let minX = CGRectGetMinX(rect).rounded(.down), minY = CGRectGetMinY(rect).rounded(.down)
    let maxX = CGRectGetMaxX(rect).rounded(.up), maxY = CGRectGetMaxY(rect).rounded(.up)
    return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
}

// MARK: - Affine transforms

private func transform(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ tx: Double, _ ty: Double) -> CGAffineTransform {
    CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
}

@c(_CGAffineTransformMake)
public func CGAffineTransformMake(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform {
    transform(a, b, c, d, tx, ty)
}

@c(_CGAffineTransformMakeTranslation)
public func CGAffineTransformMakeTranslation(_ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform { transform(1, 0, 0, 1, tx, ty) }

@c(_CGAffineTransformMakeScale)
public func CGAffineTransformMakeScale(_ sx: CGFloat, _ sy: CGFloat) -> CGAffineTransform { transform(sx, 0, 0, sy, 0, 0) }

@c(_CGAffineTransformMakeRotation)
public func CGAffineTransformMakeRotation(_ angle: CGFloat) -> CGAffineTransform {
    transform(cos(angle), sin(angle), -sin(angle), cos(angle), 0, 0)
}

/// t1 then t2.
@c(_CGAffineTransformConcat)
public func CGAffineTransformConcat(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> CGAffineTransform {
    transform(t1.a * t2.a + t1.b * t2.c, t1.a * t2.b + t1.b * t2.d, t1.c * t2.a + t1.d * t2.c, t1.c * t2.b + t1.d * t2.d,
              t1.tx * t2.a + t1.ty * t2.c + t2.tx, t1.tx * t2.b + t1.ty * t2.d + t2.ty)
}

@c(_CGAffineTransformTranslate)
public func CGAffineTransformTranslate(_ t: CGAffineTransform, _ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform {
    CGAffineTransformConcat(CGAffineTransformMakeTranslation(tx, ty), t)
}

@c(_CGAffineTransformScale)
public func CGAffineTransformScale(_ t: CGAffineTransform, _ sx: CGFloat, _ sy: CGFloat) -> CGAffineTransform {
    CGAffineTransformConcat(CGAffineTransformMakeScale(sx, sy), t)
}

@c(_CGAffineTransformRotate)
public func CGAffineTransformRotate(_ t: CGAffineTransform, _ angle: CGFloat) -> CGAffineTransform {
    CGAffineTransformConcat(CGAffineTransformMakeRotation(angle), t)
}

/// The inverse; a transform that cannot be inverted comes back unchanged.
@c(_CGAffineTransformInvert)
public func CGAffineTransformInvert(_ t: CGAffineTransform) -> CGAffineTransform {
    let determinant = t.a * t.d - t.b * t.c
    guard determinant != 0 else { return t }
    let a = t.d / determinant, b = -t.b / determinant, c = -t.c / determinant, d = t.a / determinant
    return transform(a, b, c, d, -(t.tx * a + t.ty * c), -(t.tx * b + t.ty * d))
}

@c(_CGAffineTransformIsIdentity)
public func CGAffineTransformIsIdentity(_ t: CGAffineTransform) -> Bool {
    t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == 0 && t.ty == 0
}

@c(_CGAffineTransformEqualToTransform)
public func CGAffineTransformEqualToTransform(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> Bool {
    t1.a == t2.a && t1.b == t2.b && t1.c == t2.c && t1.d == t2.d && t1.tx == t2.tx && t1.ty == t2.ty
}

@c(_CGPointApplyAffineTransform)
public func CGPointApplyAffineTransform(_ p: CGPoint, _ t: CGAffineTransform) -> CGPoint {
    CGPoint(x: t.a * p.x + t.c * p.y + t.tx, y: t.b * p.x + t.d * p.y + t.ty)
}

@c(_CGSizeApplyAffineTransform)
public func CGSizeApplyAffineTransform(_ s: CGSize, _ t: CGAffineTransform) -> CGSize {
    CGSize(width: t.a * s.width + t.c * s.height, height: t.b * s.width + t.d * s.height)
}

/// The bounds of the transformed rect's corners.
@c(_CGRectApplyAffineTransform)
public func CGRectApplyAffineTransform(_ rect: CGRect, _ t: CGAffineTransform) -> CGRect {
    guard !CGRectIsNull(rect) else { return rect }
    let r = CGRectStandardize(rect)
    let corners = [CGPoint(x: r.origin.x, y: r.origin.y), CGPoint(x: r.origin.x + r.size.width, y: r.origin.y),
                   CGPoint(x: r.origin.x, y: r.origin.y + r.size.height),
                   CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height)].map { CGPointApplyAffineTransform($0, t) }
    let xs = corners.map(\.x), ys = corners.map(\.y)
    return CGRect(origin: CGPoint(x: xs.min()!, y: ys.min()!), size: CGSize(width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
}

/// Splits off `amount` from the edge (CGRectEdge: min x 0, min y 1, max x 2,
/// max y 3) into `slice`, the rest into `remainder`.
@c(_CGRectDivide)
public func CGRectDivide(_ rect: CGRect, _ slice: UnsafeMutablePointer<CGRect>?, _ remainder: UnsafeMutablePointer<CGRect>?,
                         _ amount: Double, _ edge: UInt32) {
    let r = CGRectStandardize(rect)
    let horizontal = edge == 0 || edge == 2
    let extent = horizontal ? r.size.width : r.size.height
    let cut = min(max(amount, 0), extent)
    var a = r, b = r
    switch edge {
    case 0: a.size.width = cut; b.origin.x += cut; b.size.width -= cut
    case 1: a.size.height = cut; b.origin.y += cut; b.size.height -= cut
    case 2: a.origin.x = r.origin.x + r.size.width - cut; a.size.width = cut; b.size.width -= cut
    default: a.origin.y = r.origin.y + r.size.height - cut; a.size.height = cut; b.size.height -= cut
    }
    slice?.pointee = a
    remainder?.pointee = b
}
