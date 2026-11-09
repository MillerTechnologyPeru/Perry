import CPerryGeometry
import Glibc
import PerryObjCInterop

// Foundation's NSPoint, NSSize and NSRect functions, which macOS apps call
// as functions (CoreGraphics' CGRect ones are the same structures). The
// rectangles are in a y-up space: NSMinY is the bottom edge. armv7, which
// runs only iOS apps, leaves them out.

#if !arch(arm)

/// What a CGFloat is: 32-bit Mac programs' is a float.
#if arch(i386)
public typealias GeometryValue = Float
#else
public typealias GeometryValue = Double
#endif

private func normalized(_ rect: CGRect) -> CGRect {
    var rect = rect
    if rect.size.width < 0 { rect.origin.x += rect.size.width; rect.size.width = -rect.size.width }
    if rect.size.height < 0 { rect.origin.y += rect.size.height; rect.size.height = -rect.size.height }
    return rect
}

private func make(_ x: GeometryValue, _ y: GeometryValue, _ width: GeometryValue, _ height: GeometryValue) -> CGRect {
    CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
}

private func minX(_ r: CGRect) -> GeometryValue { r.origin.x }
private func minY(_ r: CGRect) -> GeometryValue { r.origin.y }
private func maxX(_ r: CGRect) -> GeometryValue { r.origin.x + r.size.width }
private func maxY(_ r: CGRect) -> GeometryValue { r.origin.y + r.size.height }
private func isEmpty(_ r: CGRect) -> Bool { !(r.size.width > 0 && r.size.height > 0) }

@c(_NSEqualPoints)
public func NSEqualPoints(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }

@c(_NSEqualSizes)
public func NSEqualSizes(_ a: CGSize, _ b: CGSize) -> Bool { a.width == b.width && a.height == b.height }

@c(_NSEqualRects)
public func NSEqualRects(_ a: CGRect, _ b: CGRect) -> Bool { NSEqualPoints(a.origin, b.origin) && NSEqualSizes(a.size, b.size) }

@c(_NSIsEmptyRect)
public func NSIsEmptyRect(_ rect: CGRect) -> Bool { isEmpty(rect) }

@c(_NSInsetRect)
public func NSInsetRect(_ rect: CGRect, _ dx: GeometryValue, _ dy: GeometryValue) -> CGRect {
    make(rect.origin.x + dx, rect.origin.y + dy, rect.size.width - 2 * dx, rect.size.height - 2 * dy)
}

@c(_NSOffsetRect)
public func NSOffsetRect(_ rect: CGRect, _ dx: GeometryValue, _ dy: GeometryValue) -> CGRect {
    make(rect.origin.x + dx, rect.origin.y + dy, rect.size.width, rect.size.height)
}

/// The smallest rectangle on whole numbers that holds this one; empty ones
/// are all zeros.
@c(_NSIntegralRect)
public func NSIntegralRect(_ rect: CGRect) -> CGRect {
    guard !isEmpty(rect) else { return make(0, 0, 0, 0) }
    let x = minX(rect).rounded(.down), y = minY(rect).rounded(.down)
    return make(x, y, maxX(rect).rounded(.up) - x, maxY(rect).rounded(.up) - y)
}

/// NSAlignmentOptions: each edge, width or height rounded inward (bits 0
/// to 5), outward (8 to 13) or to the nearest (16 to 21); this rounds edges
/// as the options' outward and nearest bits ask, inward otherwise.
@c(_NSIntegralRectWithOptions)
public func NSIntegralRectWithOptions(_ rect: CGRect, _ options: UInt64) -> CGRect {
    func round(_ value: GeometryValue, inward: UInt64, outward: UInt64, nearest: UInt64, up: Bool) -> GeometryValue {
        if options & nearest != 0 { return value.rounded() }
        if options & outward != 0 { return up ? value.rounded(.up) : value.rounded(.down) }
        if options & inward != 0 { return up ? value.rounded(.down) : value.rounded(.up) }
        return value
    }
    let x0 = round(minX(rect), inward: 1 << 0, outward: 1 << 8, nearest: 1 << 16, up: false)
    let y0 = round(minY(rect), inward: 1 << 1, outward: 1 << 9, nearest: 1 << 17, up: false)
    let x1 = round(maxX(rect), inward: 1 << 2, outward: 1 << 10, nearest: 1 << 18, up: true)
    let y1 = round(maxY(rect), inward: 1 << 3, outward: 1 << 11, nearest: 1 << 19, up: true)
    return make(x0, y0, max(0, x1 - x0), max(0, y1 - y0))
}

@c(_NSUnionRect)
public func NSUnionRect(_ a: CGRect, _ b: CGRect) -> CGRect {
    if isEmpty(a) { return b }
    if isEmpty(b) { return a }
    let x = min(minX(a), minX(b)), y = min(minY(a), minY(b))
    return make(x, y, max(maxX(a), maxX(b)) - x, max(maxY(a), maxY(b)) - y)
}

@c(_NSIntersectionRect)
public func NSIntersectionRect(_ a: CGRect, _ b: CGRect) -> CGRect {
    let x = max(minX(a), minX(b)), y = max(minY(a), minY(b))
    let width = min(maxX(a), maxX(b)) - x, height = min(maxY(a), maxY(b)) - y
    return width > 0 && height > 0 ? make(x, y, width, height) : make(0, 0, 0, 0)
}

@c(_NSIntersectsRect)
public func NSIntersectsRect(_ a: CGRect, _ b: CGRect) -> Bool { !isEmpty(NSIntersectionRect(a, b)) }

@c(_NSContainsRect)
public func NSContainsRect(_ a: CGRect, _ b: CGRect) -> Bool {
    !isEmpty(b) && minX(a) <= minX(b) && minY(a) <= minY(b) && maxX(a) >= maxX(b) && maxY(a) >= maxY(b)
}

@c(_NSPointInRect)
public func NSPointInRect(_ point: CGPoint, _ rect: CGRect) -> Bool {
    point.x >= minX(rect) && point.x < maxX(rect) && point.y >= minY(rect) && point.y < maxY(rect)
}

/// Whether the point is in the rectangle, in a flipped view (y down) or not.
@c(_NSMouseInRect)
public func NSMouseInRect(_ point: CGPoint, _ rect: CGRect, _ flipped: Bool) -> Bool {
    guard point.x >= minX(rect) && point.x < maxX(rect) else { return false }
    return flipped ? point.y >= minY(rect) && point.y < maxY(rect) : point.y > minY(rect) && point.y <= maxY(rect)
}

/// Cuts `amount` off the rectangle's `edge` (NSRectEdge: min x 0, min y 1,
/// max x 2, max y 3) into `slice`, the rest into `remainder`.
@c(_NSDivideRect)
public func NSDivideRect(_ rect: CGRect, _ slice: UnsafeMutablePointer<CGRect>?, _ remainder: UnsafeMutablePointer<CGRect>?,
                         _ amount: GeometryValue, _ edge: UInt32) {
    let r = normalized(rect)
    let horizontal = edge == 0 || edge == 2
    let cut = max(0, min(amount, horizontal ? r.size.width : r.size.height))
    var cutRect = r, rest = r
    switch edge {
    case 0: cutRect.size.width = cut; rest.origin.x += cut; rest.size.width -= cut
    case 1: cutRect.size.height = cut; rest.origin.y += cut; rest.size.height -= cut
    case 2: cutRect.origin.x = maxX(r) - cut; cutRect.size.width = cut; rest.size.width -= cut
    default: cutRect.origin.y = maxY(r) - cut; cutRect.size.height = cut; rest.size.height -= cut
    }
    slice?.pointee = cutRect
    remainder?.pointee = rest
}

// MARK: - Strings

private func number(_ value: GeometryValue) -> String {
    value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
}

/// The numbers in a string, in order, as "{x, y}" and "{{x, y}, {w, h}}"
/// write them; missing ones are 0.
private func numbers(_ string: id?, count: Int) -> [GeometryValue] {
    let text = Strings.value(of: string) ?? ""
    var values: [GeometryValue] = []
    var current = ""
    for character in text + "," {
        if character.isNumber || "+-.eE".contains(character) {
            current.append(character)
        } else if !current.isEmpty {
            values.append(GeometryValue(strtod(current, nil)))
            current = ""
        }
    }
    return Array((values + Array(repeating: 0, count: count)).prefix(count))
}

/// "{x, y}"
@c(_NSStringFromPoint)
public func NSStringFromPoint(_ point: CGPoint) -> id? { Strings.autoreleased("{\(number(point.x)), \(number(point.y))}") }

/// "{width, height}"
@c(_NSStringFromSize)
public func NSStringFromSize(_ size: CGSize) -> id? { Strings.autoreleased("{\(number(size.width)), \(number(size.height))}") }

/// "{{x, y}, {width, height}}"
@c(_NSStringFromRect)
public func NSStringFromRect(_ rect: CGRect) -> id? {
    Strings.autoreleased("{{\(number(rect.origin.x)), \(number(rect.origin.y))}, {\(number(rect.size.width)), \(number(rect.size.height))}}")
}

@c(_NSPointFromString)
public func NSPointFromString(_ string: id?) -> CGPoint {
    let n = numbers(string, count: 2)
    return CGPoint(x: n[0], y: n[1])
}

@c(_NSSizeFromString)
public func NSSizeFromString(_ string: id?) -> CGSize {
    let n = numbers(string, count: 2)
    return CGSize(width: n[0], height: n[1])
}

@c(_NSRectFromString)
public func NSRectFromString(_ string: id?) -> CGRect {
    let n = numbers(string, count: 4)
    return make(n[0], n[1], n[2], n[3])
}

#endif
