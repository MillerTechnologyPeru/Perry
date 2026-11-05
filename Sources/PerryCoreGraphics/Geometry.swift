import CPerryCoreGraphics
import CPerryGeometry
import Glibc
import PerryObjCInterop

// CoreGraphics' geometry functions; the constants are data in
// CPerryCoreGraphics. Rects with negative sizes are standardized first, as
// CoreGraphics does.

/// CoreGraphics' scalar: double on 64-bit Darwin, float on 32-bit.
#if _pointerBitWidth(_32)
public typealias CGFloat = Float
#else
public typealias CGFloat = Double
#endif

// The geometry as Darwin passes it to and from CoreGraphics' C functions
// (@DarwinC): itself on 64-bit, its words on 32-bit.
extension CGPoint: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGPoint=ff}" }
    #else
    public typealias ObjCType = CGPoint
    public static var objCTypeEncoding: String { "{CGPoint=dd}" }
    #endif
}

extension CGSize: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords2
    public static var objCTypeEncoding: String { "{CGSize=ff}" }
    #else
    public typealias ObjCType = CGSize
    public static var objCTypeEncoding: String { "{CGSize=dd}" }
    #endif
}

extension CGRect: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=ff}{CGSize=ff}}" }
    #else
    public typealias ObjCType = CGRect
    public static var objCTypeEncoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }
    #endif
}

extension CGAffineTransform: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords6
    public static var objCTypeEncoding: String { "{CGAffineTransform=ffffff}" }
    #else
    public typealias ObjCType = CGAffineTransform
    public static var objCTypeEncoding: String { "{CGAffineTransform=dddddd}" }
    #endif
}

private let null = CGRect(origin: CGPoint(x: .infinity, y: .infinity), size: CGSize(width: 0, height: 0))

private func isNull(_ rect: CGRect) -> Bool { rect.origin.x.isInfinite || rect.origin.y.isInfinite }

/// The rect with a non-negative size covering the same area.
@DarwinC("_CGRectStandardize")
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

@DarwinC("_CGRectGetMinX") public func CGRectGetMinX(_ rect: CGRect) -> CGFloat { CGRectStandardize(rect).origin.x }
@DarwinC("_CGRectGetMinY") public func CGRectGetMinY(_ rect: CGRect) -> CGFloat { CGRectStandardize(rect).origin.y }
@DarwinC("_CGRectGetWidth") public func CGRectGetWidth(_ rect: CGRect) -> CGFloat { abs(rect.size.width) }
@DarwinC("_CGRectGetHeight") public func CGRectGetHeight(_ rect: CGRect) -> CGFloat { abs(rect.size.height) }
@DarwinC("_CGRectGetMaxX") public func CGRectGetMaxX(_ rect: CGRect) -> CGFloat { CGRectGetMinX(rect) + CGRectGetWidth(rect) }
@DarwinC("_CGRectGetMaxY") public func CGRectGetMaxY(_ rect: CGRect) -> CGFloat { CGRectGetMinY(rect) + CGRectGetHeight(rect) }
@DarwinC("_CGRectGetMidX") public func CGRectGetMidX(_ rect: CGRect) -> CGFloat { CGRectGetMinX(rect) + CGRectGetWidth(rect) / 2 }
@DarwinC("_CGRectGetMidY") public func CGRectGetMidY(_ rect: CGRect) -> CGFloat { CGRectGetMinY(rect) + CGRectGetHeight(rect) / 2 }

@DarwinC("_CGRectIsNull") public func CGRectIsNull(_ rect: CGRect) -> Bool { isNull(rect) }

@DarwinC("_CGRectIsEmpty")
public func CGRectIsEmpty(_ rect: CGRect) -> Bool {
    isNull(rect) || rect.size.width == 0 || rect.size.height == 0
}

@DarwinC("_CGRectIsInfinite")
public func CGRectIsInfinite(_ rect: CGRect) -> Bool {
    rect.size.width == .greatestFiniteMagnitude && rect.size.height == .greatestFiniteMagnitude
}

@DarwinC("_CGPointEqualToPoint")
public func CGPointEqualToPoint(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }

@DarwinC("_CGSizeEqualToSize")
public func CGSizeEqualToSize(_ a: CGSize, _ b: CGSize) -> Bool { a.width == b.width && a.height == b.height }

@DarwinC("_CGRectEqualToRect")
public func CGRectEqualToRect(_ a: CGRect, _ b: CGRect) -> Bool {
    let a = CGRectStandardize(a), b = CGRectStandardize(b)
    return CGPointEqualToPoint(a.origin, b.origin) && CGSizeEqualToSize(a.size, b.size)
}

/// Whether the point is inside: the minimum edges count, the maximum do not.
@DarwinC("_CGRectContainsPoint")
public func CGRectContainsPoint(_ rect: CGRect, _ point: CGPoint) -> Bool {
    guard !isNull(rect) else { return false }
    return point.x >= CGRectGetMinX(rect) && point.x < CGRectGetMaxX(rect)
        && point.y >= CGRectGetMinY(rect) && point.y < CGRectGetMaxY(rect)
}

@DarwinC("_CGRectContainsRect")
public func CGRectContainsRect(_ rect: CGRect, _ other: CGRect) -> Bool {
    CGRectEqualToRect(CGRectUnion(rect, other), rect)
}

/// The overlap, or CGRectNull when there is none.
@DarwinC("_CGRectIntersection")
public func CGRectIntersection(_ a: CGRect, _ b: CGRect) -> CGRect {
    guard !isNull(a), !isNull(b) else { return null }
    let minX = max(CGRectGetMinX(a), CGRectGetMinX(b)), maxX = min(CGRectGetMaxX(a), CGRectGetMaxX(b))
    let minY = max(CGRectGetMinY(a), CGRectGetMinY(b)), maxY = min(CGRectGetMaxY(a), CGRectGetMaxY(b))
    guard minX < maxX, minY < maxY else { return null }
    return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
}

@DarwinC("_CGRectIntersectsRect")
public func CGRectIntersectsRect(_ a: CGRect, _ b: CGRect) -> Bool { !isNull(CGRectIntersection(a, b)) }

/// The smallest rect containing both; a null rect contributes nothing.
@DarwinC("_CGRectUnion")
public func CGRectUnion(_ a: CGRect, _ b: CGRect) -> CGRect {
    if isNull(a) { return CGRectStandardize(b) }
    if isNull(b) { return CGRectStandardize(a) }
    let minX = min(CGRectGetMinX(a), CGRectGetMinX(b)), maxX = max(CGRectGetMaxX(a), CGRectGetMaxX(b))
    let minY = min(CGRectGetMinY(a), CGRectGetMinY(b)), maxY = max(CGRectGetMaxY(a), CGRectGetMaxY(b))
    return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
}

@DarwinC("_CGRectOffset")
public func CGRectOffset(_ rect: CGRect, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
    guard !isNull(rect) else { return null }
    var result = CGRectStandardize(rect)
    result.origin.x += dx
    result.origin.y += dy
    return result
}

/// Shrinks (or with negative insets grows) each side; CGRectNull when
/// nothing is left.
@DarwinC("_CGRectInset")
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
@DarwinC("_CGRectIntegral")
public func CGRectIntegral(_ rect: CGRect) -> CGRect {
    guard !isNull(rect) else { return null }
    let minX = CGRectGetMinX(rect).rounded(.down), minY = CGRectGetMinY(rect).rounded(.down)
    let maxX = CGRectGetMaxX(rect).rounded(.up), maxY = CGRectGetMaxY(rect).rounded(.up)
    return CGRect(origin: CGPoint(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
}

// MARK: - Affine transforms

private func transform(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform {
    CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
}

@DarwinC("_CGAffineTransformMake")
public func CGAffineTransformMake(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform {
    transform(a, b, c, d, tx, ty)
}

@DarwinC("_CGAffineTransformMakeTranslation")
public func CGAffineTransformMakeTranslation(_ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform { transform(1, 0, 0, 1, tx, ty) }

@DarwinC("_CGAffineTransformMakeScale")
public func CGAffineTransformMakeScale(_ sx: CGFloat, _ sy: CGFloat) -> CGAffineTransform { transform(sx, 0, 0, sy, 0, 0) }

@DarwinC("_CGAffineTransformMakeRotation")
public func CGAffineTransformMakeRotation(_ angle: CGFloat) -> CGAffineTransform {
    let cosine = CGFloat(cos(Double(angle))), sine = CGFloat(sin(Double(angle)))
    return transform(cosine, sine, -sine, cosine, 0, 0)
}

/// t1 then t2.
@DarwinC("_CGAffineTransformConcat")
public func CGAffineTransformConcat(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> CGAffineTransform {
    transform(t1.a * t2.a + t1.b * t2.c, t1.a * t2.b + t1.b * t2.d, t1.c * t2.a + t1.d * t2.c, t1.c * t2.b + t1.d * t2.d,
              t1.tx * t2.a + t1.ty * t2.c + t2.tx, t1.tx * t2.b + t1.ty * t2.d + t2.ty)
}

@DarwinC("_CGAffineTransformTranslate")
public func CGAffineTransformTranslate(_ t: CGAffineTransform, _ tx: CGFloat, _ ty: CGFloat) -> CGAffineTransform {
    CGAffineTransformConcat(CGAffineTransformMakeTranslation(tx, ty), t)
}

@DarwinC("_CGAffineTransformScale")
public func CGAffineTransformScale(_ t: CGAffineTransform, _ sx: CGFloat, _ sy: CGFloat) -> CGAffineTransform {
    CGAffineTransformConcat(CGAffineTransformMakeScale(sx, sy), t)
}

@DarwinC("_CGAffineTransformRotate")
public func CGAffineTransformRotate(_ t: CGAffineTransform, _ angle: CGFloat) -> CGAffineTransform {
    CGAffineTransformConcat(CGAffineTransformMakeRotation(angle), t)
}

/// The inverse; a transform that cannot be inverted comes back unchanged.
@DarwinC("_CGAffineTransformInvert")
public func CGAffineTransformInvert(_ t: CGAffineTransform) -> CGAffineTransform {
    let determinant = t.a * t.d - t.b * t.c
    guard determinant != 0 else { return t }
    let a = t.d / determinant, b = -t.b / determinant, c = -t.c / determinant, d = t.a / determinant
    return transform(a, b, c, d, -(t.tx * a + t.ty * c), -(t.tx * b + t.ty * d))
}

@DarwinC("_CGAffineTransformIsIdentity")
public func CGAffineTransformIsIdentity(_ t: CGAffineTransform) -> Bool {
    t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == 0 && t.ty == 0
}

@DarwinC("_CGAffineTransformEqualToTransform")
public func CGAffineTransformEqualToTransform(_ t1: CGAffineTransform, _ t2: CGAffineTransform) -> Bool {
    t1.a == t2.a && t1.b == t2.b && t1.c == t2.c && t1.d == t2.d && t1.tx == t2.tx && t1.ty == t2.ty
}

@DarwinC("_CGPointApplyAffineTransform")
public func CGPointApplyAffineTransform(_ p: CGPoint, _ t: CGAffineTransform) -> CGPoint {
    CGPoint(x: t.a * p.x + t.c * p.y + t.tx, y: t.b * p.x + t.d * p.y + t.ty)
}

@DarwinC("_CGSizeApplyAffineTransform")
public func CGSizeApplyAffineTransform(_ s: CGSize, _ t: CGAffineTransform) -> CGSize {
    CGSize(width: t.a * s.width + t.c * s.height, height: t.b * s.width + t.d * s.height)
}

/// The bounds of the transformed rect's corners.
@DarwinC("_CGRectApplyAffineTransform")
public func CGRectApplyAffineTransform(_ rect: CGRect, _ t: CGAffineTransform) -> CGRect {
    guard !CGRectIsNull(rect) else { return rect }
    let r = CGRectStandardize(rect)
    let corners = [CGPoint(x: r.origin.x, y: r.origin.y), CGPoint(x: r.origin.x + r.size.width, y: r.origin.y),
                   CGPoint(x: r.origin.x, y: r.origin.y + r.size.height),
                   CGPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height)].map { CGPointApplyAffineTransform($0, t) }
    let xs = corners.map(\.x), ys = corners.map(\.y)
    return CGRect(origin: CGPoint(x: xs.min()!, y: ys.min()!), size: CGSize(width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
}
