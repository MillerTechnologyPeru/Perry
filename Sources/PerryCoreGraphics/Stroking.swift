import CPerryCoreGraphics
import Glibc
import PerryObjCInterop

// Paths' outlines and dashes, as CGPathCreateCopyByStrokingPath and
// CGPathCreateCopyByDashingPath make them. Curves are flattened into
// polylines first. A stroke's outline is the union of a quad along each
// segment, a join at each corner and a cap at each open end: all wound the
// same way, so filling the outline by the nonzero rule fills their union,
// as CoreGraphics' outlines are filled.

/// A subpath as points, curves flattened.
struct Polyline {
    var points: [(Double, Double)] = []
    var closed = false
}

enum Stroking {
    /// The path's subpaths as polylines, each curve in segments short
    /// enough to look smooth, and no segment of zero length.
    static func polylines(_ commands: [PathCommand]) -> [Polyline] {
        var lines: [Polyline] = []
        var line = Polyline()
        var start = (0.0, 0.0)
        func add(_ p: (Double, Double)) {
            if let last = line.points.last, abs(last.0 - p.0) < 1e-9, abs(last.1 - p.1) < 1e-9 { return }
            line.points.append(p)
        }
        func finish() {
            if !line.points.isEmpty { lines.append(line) }
            line = Polyline()
        }
        /// Segments for a curve whose control polygon is `length` long.
        func segments(_ length: Double) -> Int { min(64, max(4, Int((length / 2).rounded(.up)))) }
        for command in commands {
            switch command {
            case .move(let x, let y):
                finish()
                start = (x, y)
                line.points = [(x, y)]
            case .line(let x, let y):
                if line.points.isEmpty { line.points = [start] }
                add((x, y))
            case .quad(let cx, let cy, let x, let y):
                if line.points.isEmpty { line.points = [start] }
                let p0 = line.points.last!
                let n = segments(hypot(cx - p0.0, cy - p0.1) + hypot(x - cx, y - cy))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    add((u * u * p0.0 + 2 * u * t * cx + t * t * x, u * u * p0.1 + 2 * u * t * cy + t * t * y))
                }
            case .curve(let ax, let ay, let bx, let by, let x, let y):
                if line.points.isEmpty { line.points = [start] }
                let p0 = line.points.last!
                let n = segments(hypot(ax - p0.0, ay - p0.1) + hypot(bx - ax, by - ay) + hypot(x - bx, y - by))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    add((a * p0.0 + b * ax + c * bx + d * x, a * p0.1 + b * ay + c * by + d * y))
                }
            case .close:
                if !line.points.isEmpty {
                    line.closed = true
                    // The closing segment is implied; drop a point repeating the start.
                    if line.points.count > 1, let first = line.points.first, let last = line.points.last,
                       abs(first.0 - last.0) < 1e-9, abs(first.1 - last.1) < 1e-9 {
                        line.points.removeLast()
                    }
                    start = line.points[0]
                }
                finish()
            }
        }
        finish()
        return lines
    }

    // MARK: Outlines

    /// The outline of the path stroked with the width, cap (butt 0, round 1,
    /// square 2), join (miter 0, round 1, bevel 2) and miter limit.
    static func stroke(_ commands: [PathCommand], width: Double, cap: Int32, join: Int32, miterLimit: Double) -> [PathCommand] {
        let half = width / 2
        guard half > 0 else { return [] }
        var out: [PathCommand] = []

        /// A polygon wound counterclockwise (positive area), so every piece
        /// adds to the winding the same way.
        func polygon(_ points: [(Double, Double)]) {
            guard points.count > 2 else { return }
            var area = 0.0
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                area += a.0 * b.1 - b.0 * a.1
            }
            guard abs(area) > 1e-12 else { return }
            let ordered = area > 0 ? points : points.reversed()
            out.append(.move(ordered[0].0, ordered[0].1))
            for p in ordered.dropFirst() { out.append(.line(p.0, p.1)) }
            out.append(.close)
        }
        func circle(_ p: (Double, Double)) {
            out += Paths.ellipse(CGRect(origin: CGPoint(x: CGFloat(p.0 - half), y: CGFloat(p.1 - half)),
                                        size: CGSize(width: CGFloat(width), height: CGFloat(width))))
        }
        /// The unit direction from a to b, and its left normal scaled to
        /// the half width.
        func direction(_ a: (Double, Double), _ b: (Double, Double)) -> (d: (Double, Double), n: (Double, Double)) {
            let length = hypot(b.0 - a.0, b.1 - a.1)
            let d = ((b.0 - a.0) / length, (b.1 - a.1) / length)
            return (d, (-d.1 * half, d.0 * half))
        }
        func segment(_ a: (Double, Double), _ b: (Double, Double)) {
            let n = direction(a, b).n
            polygon([(a.0 - n.0, a.1 - n.1), (b.0 - n.0, b.1 - n.1), (b.0 + n.0, b.1 + n.1), (a.0 + n.0, a.1 + n.1)])
        }
        /// The join at p between the segment from a and the one to b.
        func joint(_ a: (Double, Double), _ p: (Double, Double), _ b: (Double, Double)) {
            let (d1, n1) = direction(a, p), (d2, n2) = direction(p, b)
            let cross = d1.0 * d2.1 - d1.1 * d2.0
            let dot = d1.0 * d2.0 + d1.1 * d2.1
            if abs(cross) < 1e-9, dot > 0 { return }
            if join == 1 { circle(p); return }
            // The outer side is the one the path turns away from.
            let sign = cross > 0 ? -1.0 : 1.0
            let o1 = (n1.0 * sign, n1.1 * sign), o2 = (n2.0 * sign, n2.1 * sign)
            let e1 = (p.0 + o1.0, p.1 + o1.1), e2 = (p.0 + o2.0, p.1 + o2.1)
            if join == 0 {
                let m = (o1.0 + o2.0, o1.1 + o2.1)
                let mLength = hypot(m.0, m.1)
                if mLength > 1e-12 {
                    let cosHalf = (m.0 * o1.0 + m.1 * o1.1) / (mLength * half)
                    if cosHalf > 1e-9, 1 / cosHalf <= miterLimit {
                        let reach = half / cosHalf
                        let tip = (p.0 + m.0 / mLength * reach, p.1 + m.1 / mLength * reach)
                        polygon([p, e1, tip, e2])
                        return
                    }
                }
            }
            polygon([p, e1, e2])
        }
        /// The cap at end p of the segment coming from a.
        func endCap(_ a: (Double, Double), _ p: (Double, Double)) {
            switch cap {
            case 1: circle(p)
            case 2:
                let (d, n) = direction(a, p)
                let q = (p.0 + d.0 * half, p.1 + d.1 * half)
                polygon([(p.0 - n.0, p.1 - n.1), (q.0 - n.0, q.1 - n.1), (q.0 + n.0, q.1 + n.1), (p.0 + n.0, p.1 + n.1)])
            default: break
            }
        }

        for line in polylines(commands) {
            let points = line.points
            if points.count == 1 {
                // A lone point: drawn only by round and square caps.
                let p = points[0]
                if cap == 1 { circle(p) }
                if cap == 2 { polygon([(p.0 - half, p.1 - half), (p.0 + half, p.1 - half), (p.0 + half, p.1 + half), (p.0 - half, p.1 + half)]) }
                continue
            }
            let closed = line.closed && points.count > 2
            let count = points.count
            for i in 0..<(closed ? count : count - 1) {
                segment(points[i], points[(i + 1) % count])
            }
            for i in (closed ? 0 : 1)..<(closed ? count : count - 1) {
                joint(points[(i + count - 1) % count], points[i], points[(i + 1) % count])
            }
            if !closed {
                endCap(points[1], points[0])
                endCap(points[count - 2], points[count - 1])
            }
        }
        return out
    }

    // MARK: Dashes

    /// The path cut into dashes: lengths alternate on and off, starting
    /// `phase` into the pattern.
    static func dash(_ commands: [PathCommand], phase: Double, lengths: [Double]) -> [PathCommand] {
        let total = lengths.reduce(0, +)
        guard total > 0, lengths.allSatisfy({ $0 >= 0 }) else { return commands }
        var out: [PathCommand] = []
        for line in polylines(commands) {
            var points = line.points
            if line.closed, let first = points.first { points.append(first) }
            guard points.count > 1 else { continue }
            // Where in the pattern the subpath starts.
            var index = 0
            var left = lengths[0]
            var offset = phase.truncatingRemainder(dividingBy: total)
            if offset < 0 { offset += total }
            while offset > 0 {
                if offset >= left {
                    offset -= left
                    index = (index + 1) % lengths.count
                    left = lengths[index]
                } else {
                    left -= offset
                    offset = 0
                }
            }
            var on = index % 2 == 0
            if on { out.append(.move(points[0].0, points[0].1)) }
            for i in 1..<points.count {
                var a = points[i - 1]
                let b = points[i]
                var remaining = hypot(b.0 - a.0, b.1 - a.1)
                while remaining > 0 {
                    if left >= remaining {
                        left -= remaining
                        remaining = 0
                        if on { out.append(.line(b.0, b.1)) }
                    } else {
                        let t = left / remaining
                        let p = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
                        if on { out.append(.line(p.0, p.1)) } else { out.append(.move(p.0, p.1)) }
                        remaining -= left
                        a = p
                        on.toggle()
                        index = (index + 1) % lengths.count
                        left = lengths[index]
                        // A pattern of only zero lengths would never advance.
                        if left == 0, lengths.allSatisfy({ $0 == 0 }) { return commands }
                    }
                }
            }
        }
        return out
    }
}

@DarwinC("_CGPathCreateCopyByStrokingPath")
public func CGPathCreateCopyByStrokingPath(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ lineWidth: CGFloat,
                                           _ lineCap: Int32, _ lineJoin: Int32, _ miterLimit: CGFloat) -> Ref? {
    guard let state = Paths.state(path) else { return nil }
    let outline = Paths.make()
    Paths.append(outline, t, Stroking.stroke(state.commands, width: Double(lineWidth), cap: lineCap, join: lineJoin, miterLimit: Double(miterLimit)))
    return outline
}

@DarwinC("_CGPathCreateCopyByDashingPath")
public func CGPathCreateCopyByDashingPath(_ path: Ref?, _ t: UnsafePointer<CGAffineTransform>?, _ phase: CGFloat,
                                          _ lengths: UnsafePointer<CGFloat>?, _ count: Int) -> Ref? {
    guard let state = Paths.state(path) else { return nil }
    let pattern = lengths.map { UnsafeBufferPointer(start: $0, count: count).map { Double($0) } } ?? []
    let dashed = Paths.make()
    Paths.append(dashed, t, Stroking.dash(state.commands, phase: Double(phase), lengths: pattern))
    return dashed
}
