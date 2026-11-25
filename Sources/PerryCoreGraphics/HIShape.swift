import CPerryGeometry
import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// HIServices' HIShape, which ApplicationServices re-exports and the loader
// maps here on Intel; Carbon's provider re-exports ApplicationServices, so a
// program that binds it to Carbon finds it too. A shape is a region, as
// QuickDraw's were: bands of rows from the top down (y grows downwards, as
// in an HIView), each band a run of rows with the same spans across. Rows
// and spans are half-open, [top, bottom) and [left, right), so rects that
// touch don't overlap. Union, intersection, difference and exclusive or cut
// both shapes at every band edge either has and combine each slice's spans.
// Mutable and immutable shapes are one kind here; a copy is a new shape.

private let noErr: Int32 = 0
private let paramErr: Int32 = -50

/// HIShape's CFTypeID.
let shapeTypeID: UInt = 0x110

/// A region: its bands from the top down, none empty, and where two touch
/// their spans differ; each band's spans from the left, none empty, apart.
struct Region: Equatable {
    struct Span: Equatable {
        var left: Double
        var right: Double
    }

    struct Band: Equatable {
        var top: Double
        var bottom: Double
        var spans: [Span]
    }

    private(set) var bands: [Band] = []

    init() {}

    /// The rect's area: none for an empty, null or not finite rect.
    init(_ rect: CGRect) {
        let x = Double(rect.origin.x), y = Double(rect.origin.y), width = Double(rect.size.width), height = Double(rect.size.height)
        let left = min(x, x + width), right = max(x, x + width), top = min(y, y + height), bottom = max(y, y + height)
        guard left.isFinite, right.isFinite, top.isFinite, bottom.isFinite, left < right, top < bottom else { return }
        bands = [Band(top: top, bottom: bottom, spans: [Span(left: left, right: right)])]
    }

    var isEmpty: Bool { bands.isEmpty }

    /// One rect or none.
    var isRectangular: Bool { bands.count <= 1 && (bands.first?.spans.count ?? 0) <= 1 }

    /// The smallest rect around it; an empty region's is all zeros, as an
    /// empty QuickDraw region's box is.
    var bounds: CGRect {
        guard let first = bands.first, let last = bands.last else { return rect(0, 0, 0, 0) }
        var left = Double.infinity, right = -Double.infinity
        for band in bands {
            left = min(left, band.spans[0].left)
            right = max(right, band.spans[band.spans.count - 1].right)
        }
        return rect(left, first.top, right, last.bottom)
    }

    /// Each band's spans, a rect apiece: from the top or the bottom, and
    /// along each band from the left or the right.
    func rects(fromBottom: Bool = false, fromRight: Bool = false) -> [CGRect] {
        (fromBottom ? bands.reversed() : bands).flatMap { band in
            (fromRight ? band.spans.reversed() : band.spans).map { rect($0.left, band.top, $0.right, band.bottom) }
        }
    }

    func contains(_ x: Double, _ y: Double) -> Bool {
        guard let band = bands.first(where: { $0.top <= y && y < $0.bottom }) else { return false }
        return band.spans.contains { $0.left <= x && x < $0.right }
    }

    func offset(_ dx: Double, _ dy: Double) -> Region {
        var moved = Region()
        for band in bands {
            moved.append(Band(top: band.top + dy, bottom: band.bottom + dy,
                              spans: band.spans.map { Span(left: $0.left + dx, right: $0.right + dx) }))
        }
        return moved
    }

    func union(_ other: Region) -> Region { combined(with: other) { $0 || $1 } }
    func intersection(_ other: Region) -> Region { combined(with: other) { $0 && $1 } }
    func subtracting(_ other: Region) -> Region { combined(with: other) { $0 && !$1 } }
    func symmetricDifference(_ other: Region) -> Region { combined(with: other) { $0 != $1 } }

    /// Shrunk by `dx` at the left and right and `dy` at the top and bottom,
    /// or grown by negative amounts, as QuickDraw's InsetRgn does: across,
    /// each band's spans move in or out; up and down, growing takes every
    /// band further up and down, and shrinking takes away what everything
    /// outside the region covers when it grows.
    func inset(_ dx: Double, _ dy: Double) -> Region { insetAcross(dx).insetUpAndDown(dy) }

    private func insetAcross(_ dx: Double) -> Region {
        guard dx != 0 else { return self }
        var result = Region()
        for band in bands {
            var spans: [Span] = []
            for span in band.spans {
                let left = span.left + dx, right = span.right - dx
                guard left < right else { continue }
                // Grown spans that reach the one before join it.
                if let last = spans.last, last.right >= left {
                    spans[spans.count - 1].right = max(last.right, right)
                } else {
                    spans.append(Span(left: left, right: right))
                }
            }
            result.append(Band(top: band.top, bottom: band.bottom, spans: spans))
        }
        return result
    }

    private func insetUpAndDown(_ dy: Double) -> Region {
        guard dy != 0, let first = bands.first, let last = bands.last else { return self }
        if dy < 0 {
            return bands.reduce(Region()) { grown, band in
                var reach = Region()
                reach.append(Band(top: band.top + dy, bottom: band.bottom - dy, spans: band.spans))
                return grown.union(reach)
            }
        }
        // Outside, within a frame reaching dy above and below the region.
        let box = bounds
        let frame = Region(rect(Double(box.origin.x), first.top - dy, Double(box.origin.x + box.size.width), last.bottom + dy))
        return Region(box).subtracting(frame.subtracting(self).insetUpAndDown(-dy))
    }

    /// The parts that `keep` says of, from whether they're in this region
    /// and whether they're in the other: both cut into slices at every band
    /// edge, and each slice's spans cut at every span edge.
    private func combined(with other: Region, _ keep: (Bool, Bool) -> Bool) -> Region {
        var edges = Set<Double>()
        for band in bands + other.bands {
            edges.insert(band.top)
            edges.insert(band.bottom)
        }
        let ys = edges.sorted()
        var result = Region()
        var a = 0, b = 0
        for (top, bottom) in zip(ys, ys.dropFirst()) {
            while a < bands.count, bands[a].bottom <= top { a += 1 }
            while b < other.bands.count, other.bands[b].bottom <= top { b += 1 }
            let these = a < bands.count && bands[a].top <= top ? bands[a].spans : []
            let those = b < other.bands.count && other.bands[b].top <= top ? other.bands[b].spans : []
            result.append(Band(top: top, bottom: bottom, spans: Region.combine(these, those, keep)))
        }
        return result
    }

    private static func combine(_ these: [Span], _ those: [Span], _ keep: (Bool, Bool) -> Bool) -> [Span] {
        var edges = Set<Double>()
        for span in these + those {
            edges.insert(span.left)
            edges.insert(span.right)
        }
        let xs = edges.sorted()
        var spans: [Span] = []
        var i = 0, j = 0
        for (left, right) in zip(xs, xs.dropFirst()) {
            while i < these.count, these[i].right <= left { i += 1 }
            while j < those.count, those[j].right <= left { j += 1 }
            let inThese = i < these.count && these[i].left <= left
            let inThose = j < those.count && those[j].left <= left
            guard keep(inThese, inThose) else { continue }
            if let last = spans.last, last.right == left {
                spans[spans.count - 1].right = right
            } else {
                spans.append(Span(left: left, right: right))
            }
        }
        return spans
    }

    /// Adds a band below the others: nothing if it's empty, and joined to
    /// the last if it touches it with the same spans.
    private mutating func append(_ band: Band) {
        guard !band.spans.isEmpty, band.top < band.bottom else { return }
        if let last = bands.last, last.bottom == band.top, last.spans == band.spans {
            bands[bands.count - 1].bottom = band.bottom
        } else {
            bands.append(band)
        }
    }
}

private func rect(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> CGRect {
    CGRect(origin: CGPoint(x: CGFloat(left), y: CGFloat(top)), size: CGSize(width: CGFloat(right - left), height: CGFloat(bottom - top)))
}

final class ShapeState: @unchecked Sendable {
    var region: Region

    init(_ region: Region) { self.region = region }
}

@ObjCClass("HIShape")
public final class HIShapeObject: NSObject {
    static let states = StateTable<ShapeState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        HIShapeObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: HIShapeObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { shapeTypeID }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let these = HIShapeObject.states[objcObject], let those = HIShapeObject.states[other?.objcObject] else { return false }
        return these.region == those.region
    }

    @ObjCMethod("description")
    func description() -> String {
        let rects = HIShapeObject.states[objcObject]?.region.rects() ?? []
        let text = rects.map { "{\($0.origin.x), \($0.origin.y), \($0.size.width), \($0.size.height)}" }.joined(separator: ", ")
        return "<HIShape \(objcObject)> [\(text)]"
    }
}

private func shapeRegion(_ shape: Ref?) -> Region? { HIShapeObject.states[shape]?.region }

private func make(_ region: Region) -> Ref { makeObject(HIShapeObject.objCClass, HIShapeObject.states, ShapeState(region)) }

/// Sets a shape to `body`'s region, from the shapes given: paramErr if any
/// isn't a shape.
private func change(_ shape: Ref?, _ body: (Region) -> Region) -> Int32 {
    guard let state = HIShapeObject.states[shape] else { return paramErr }
    state.region = body(state.region)
    return noErr
}

private func change(_ result: Ref?, _ first: Ref?, _ second: Ref?, _ body: (Region, Region) -> Region) -> Int32 {
    guard let a = shapeRegion(first), let b = shapeRegion(second), let state = HIShapeObject.states[result] else { return paramErr }
    state.region = body(a, b)
    return noErr
}

@c(_HIShapeGetTypeID) public func HIShapeGetTypeID() -> UInt { shapeTypeID }

// MARK: Making shapes

@c(_HIShapeCreateEmpty) public func HIShapeCreateEmpty() -> Ref { make(Region()) }
@c(_HIShapeCreateMutable) public func HIShapeCreateMutable() -> Ref { make(Region()) }

@c(_HIShapeCreateWithRect)
public func HIShapeCreateWithRect(_ rect: UnsafePointer<CGRect>?) -> Ref? { rect.map { make(Region($0.pointee)) } }

@c(_HIShapeCreateMutableWithRect)
public func HIShapeCreateMutableWithRect(_ rect: UnsafePointer<CGRect>?) -> Ref? { rect.map { make(Region($0.pointee)) } }

@c(_HIShapeCreateCopy) public func HIShapeCreateCopy(_ shape: Ref?) -> Ref? { shapeRegion(shape).map(make) }
@c(_HIShapeCreateMutableCopy) public func HIShapeCreateMutableCopy(_ shape: Ref?) -> Ref? { shapeRegion(shape).map(make) }

@c(_HIShapeCreateIntersection)
public func HIShapeCreateIntersection(_ first: Ref?, _ second: Ref?) -> Ref? {
    guard let a = shapeRegion(first), let b = shapeRegion(second) else { return nil }
    return make(a.intersection(b))
}

/// The second shape taken from the first.
@c(_HIShapeCreateDifference)
public func HIShapeCreateDifference(_ first: Ref?, _ second: Ref?) -> Ref? {
    guard let a = shapeRegion(first), let b = shapeRegion(second) else { return nil }
    return make(a.subtracting(b))
}

@c(_HIShapeCreateUnion)
public func HIShapeCreateUnion(_ first: Ref?, _ second: Ref?) -> Ref? {
    guard let a = shapeRegion(first), let b = shapeRegion(second) else { return nil }
    return make(a.union(b))
}

@c(_HIShapeCreateXor)
public func HIShapeCreateXor(_ first: Ref?, _ second: Ref?) -> Ref? {
    guard let a = shapeRegion(first), let b = shapeRegion(second) else { return nil }
    return make(a.symmetricDifference(b))
}

// MARK: Asking about shapes

@c(_HIShapeIsEmpty) public func HIShapeIsEmpty(_ shape: Ref?) -> Bool { shapeRegion(shape)?.isEmpty ?? true }
@c(_HIShapeIsRectangular) public func HIShapeIsRectangular(_ shape: Ref?) -> Bool { shapeRegion(shape)?.isRectangular ?? false }

@c(_HIShapeContainsPoint)
public func HIShapeContainsPoint(_ shape: Ref?, _ point: UnsafePointer<CGPoint>?) -> Bool {
    guard let point, let region = shapeRegion(shape) else { return false }
    return region.contains(Double(point.pointee.x), Double(point.pointee.y))
}

@c(_HIShapeIntersectsRect)
public func HIShapeIntersectsRect(_ shape: Ref?, _ rect: UnsafePointer<CGRect>?) -> Bool {
    guard let rect, let region = shapeRegion(shape) else { return false }
    return !region.intersection(Region(rect.pointee)).isEmpty
}

/// CGRect *HIShapeGetBounds(HIShapeRef, CGRect *outRect): outRect, given
/// the bounds.
@c(_HIShapeGetBounds)
public func HIShapeGetBounds(_ shape: Ref?, _ bounds: UnsafeMutablePointer<CGRect>?) -> UnsafeMutablePointer<CGRect>? {
    bounds?.pointee = (shapeRegion(shape) ?? Region()).bounds
    return bounds
}

/// Makes the context's path the shape's rects.
@c(_HIShapeReplacePathInCGContext)
public func HIShapeReplacePathInCGContext(_ shape: Ref?, _ context: Ref?) -> Int32 {
    guard let region = shapeRegion(shape), Contexts.state(context) != nil else { return paramErr }
    CGContextBeginPath(context)
    for rect in region.rects() { CGContextAddRect(context, rect) }
    return noErr
}

/// OSStatus HIShapeEnumerate(HIShapeRef, OptionBits, HIShapeEnumerateProcPtr,
/// void *refcon): the callback is told kHIShapeEnumerateInit (1), then each
/// rect with kHIShapeEnumerateRect (2), then kHIShapeEnumerateTerminate (3),
/// with the shape's bounds for the first and last. kHIShapeParseFromBottom
/// (1) and kHIShapeParseFromRight (2) turn the order round. The first
/// status that isn't noErr stops it (after Terminate, unless Init's), and
/// is the result.
@c(_HIShapeEnumerate)
public func HIShapeEnumerate(_ shape: Ref?, _ options: UInt32, _ proc: UnsafeRawPointer?, _ refcon: UnsafeMutableRawPointer?) -> Int32 {
    typealias Callback = @convention(c) (Int32, Ref?, UnsafePointer<CGRect>?, UnsafeMutableRawPointer?) -> Int32
    guard let region = shapeRegion(shape), let proc else { return paramErr }
    let callback = unsafeBitCast(proc, to: Callback.self)
    let bounds = region.bounds
    var status = withUnsafePointer(to: bounds) { callback(1, shape, $0, refcon) }
    guard status == noErr else { return status }
    for rect in region.rects(fromBottom: options & 1 != 0, fromRight: options & 2 != 0) {
        status = withUnsafePointer(to: rect) { callback(2, shape, $0, refcon) }
        if status != noErr { break }
    }
    let terminated = withUnsafePointer(to: bounds) { callback(3, shape, $0, refcon) }
    return status != noErr ? status : terminated
}

// MARK: Changing mutable shapes

@c(_HIShapeSetEmpty) public func HIShapeSetEmpty(_ shape: Ref?) -> Int32 { change(shape) { _ in Region() } }

@c(_HIShapeSetWithShape)
public func HIShapeSetWithShape(_ shape: Ref?, _ source: Ref?) -> Int32 {
    guard let copied = shapeRegion(source) else { return paramErr }
    return change(shape) { _ in copied }
}

/// The result may be either source shape.
@c(_HIShapeIntersect)
public func HIShapeIntersect(_ first: Ref?, _ second: Ref?, _ result: Ref?) -> Int32 { change(result, first, second) { $0.intersection($1) } }

@c(_HIShapeDifference)
public func HIShapeDifference(_ first: Ref?, _ second: Ref?, _ result: Ref?) -> Int32 { change(result, first, second) { $0.subtracting($1) } }

@c(_HIShapeUnion)
public func HIShapeUnion(_ first: Ref?, _ second: Ref?, _ result: Ref?) -> Int32 { change(result, first, second) { $0.union($1) } }

@c(_HIShapeXor)
public func HIShapeXor(_ first: Ref?, _ second: Ref?, _ result: Ref?) -> Int32 { change(result, first, second) { $0.symmetricDifference($1) } }

@DarwinC("_HIShapeOffset")
public func HIShapeOffset(_ shape: Ref?, _ dx: CGFloat, _ dy: CGFloat) -> Int32 { change(shape) { $0.offset(Double(dx), Double(dy)) } }

/// Positive deltas shrink the shape, negative ones grow it.
@DarwinC("_HIShapeInset")
public func HIShapeInset(_ shape: Ref?, _ dx: CGFloat, _ dy: CGFloat) -> Int32 { change(shape) { $0.inset(Double(dx), Double(dy)) } }

@c(_HIShapeUnionWithRect)
public func HIShapeUnionWithRect(_ shape: Ref?, _ rect: UnsafePointer<CGRect>?) -> Int32 {
    guard let rect else { return paramErr }
    let added = Region(rect.pointee)
    return change(shape) { $0.union(added) }
}
#endif
