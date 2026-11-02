import CPerryCoreGraphics
import CPerryGeometry

// libPerryCoreGraphics: the provider for CoreGraphics.framework. So far,
// the geometry functions; the constants are data in CPerryCoreGraphics.
// Rects with negative sizes are standardized first, as CoreGraphics does.

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
