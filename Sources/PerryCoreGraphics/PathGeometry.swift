import CPerryCoreGraphics
import CPerryGeometry
import Glibc
import PerryObjCInterop

// Paths as geometry: flattening, and the boolean operations of macOS 13 and
// iOS 16 (union, intersection, subtraction, symmetric difference,
// normalizing, separating components, and clipping a path's lines to
// another's fill). Curves are flattened to polygons within a tolerance; every
// edge of both operands is split where it meets another, so the pieces form
// a planar arrangement; each piece is kept when the result's fill differs on
// its two sides, which the operands' winding numbers just beside it tell, by
// the fill rule asked for; and the kept pieces, each turned to have the
// result's inside on its left, are linked into closed loops. Outer
// boundaries then run counterclockwise and holes clockwise (in CoreGraphics'
// y-up space), so the result fills the same under either fill rule. Results
// are polygons: curves come back as the lines they were flattened to.

struct PathPoint: Hashable {
    var x: Double
    var y: Double

    static func + (a: PathPoint, b: PathPoint) -> PathPoint { PathPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: PathPoint, b: PathPoint) -> PathPoint { PathPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: PathPoint, k: Double) -> PathPoint { PathPoint(x: a.x * k, y: a.y * k) }

    var length: Double { (x * x + y * y).squareRoot() }
    var isFinite: Bool { x.isFinite && y.isFinite }

    func dot(_ other: PathPoint) -> Double { x * other.x + y * other.y }
    func cross(_ other: PathPoint) -> Double { x * other.y - y * other.x }
    func midpoint(_ other: PathPoint) -> PathPoint { PathPoint(x: (x + other.x) / 2, y: (y + other.y) / 2) }
}

/// A subpath with its curves flattened: its points in order, and whether it
/// was closed.
struct FlatSubpath {
    var points: [PathPoint]
    var closed: Bool
}

/// A directed line segment.
struct PathEdge {
    var a: PathPoint
    var b: PathPoint
}

enum Flattening {
    /// The subpaths, curves replaced by lines that stay within `tolerance`
    /// of them. A segment after a close starts a new subpath at the closed
    /// one's start, as CGPath's do.
    static func polylines(_ commands: [PathCommand], tolerance: Double) -> [FlatSubpath] {
        let tolerance = max(tolerance, 1e-6)
        var result: [FlatSubpath] = []
        var current: [PathPoint] = []
        var start = PathPoint(x: 0, y: 0)
        var last = start
        func finish(closed: Bool) {
            if !current.isEmpty { result.append(FlatSubpath(points: current, closed: closed)) }
            current = []
        }
        for command in commands {
            switch command {
            case .move(let x, let y):
                finish(closed: false)
                start = PathPoint(x: x, y: y)
                last = start
                current = [start]
            case .line(let x, let y):
                if current.isEmpty { current = [last] }
                last = PathPoint(x: x, y: y)
                current.append(last)
            case .quad(let cx, let cy, let x, let y):
                if current.isEmpty { current = [last] }
                let control = PathPoint(x: cx, y: cy), end = PathPoint(x: x, y: y)
                // The cubic with the same curve.
                cubic(last, last + (control - last) * (2.0 / 3), end + (control - end) * (2.0 / 3), end, tolerance, 0, &current)
                last = end
            case .curve(let ax, let ay, let bx, let by, let x, let y):
                if current.isEmpty { current = [last] }
                let end = PathPoint(x: x, y: y)
                cubic(last, PathPoint(x: ax, y: ay), PathPoint(x: bx, y: by), end, tolerance, 0, &current)
                last = end
            case .close:
                finish(closed: true)
                last = start
            }
        }
        finish(closed: false)
        return result
    }

    /// The distance from `p` to the line through `a` and `b` (to `a` when
    /// they are the same point).
    private static func distance(_ p: PathPoint, _ a: PathPoint, _ b: PathPoint) -> Double {
        let d = b - a, length = d.length
        guard length > 0 else { return (p - a).length }
        return abs(d.cross(p - a)) / length
    }

    /// Splits the curve in half until its control points lie within the
    /// tolerance of its chord, appending the end points of the pieces.
    private static func cubic(_ p0: PathPoint, _ p1: PathPoint, _ p2: PathPoint, _ p3: PathPoint, _ tolerance: Double, _ depth: Int,
                              _ out: inout [PathPoint]) {
        if depth >= 16 || max(distance(p1, p0, p3), distance(p2, p0, p3)) <= tolerance {
            out.append(p3)
            return
        }
        let p01 = p0.midpoint(p1), p12 = p1.midpoint(p2), p23 = p2.midpoint(p3)
        let p012 = p01.midpoint(p12), p123 = p12.midpoint(p23), middle = p012.midpoint(p123)
        cubic(p0, p01, p012, middle, tolerance, depth + 1, &out)
        cubic(middle, p123, p23, p3, tolerance, depth + 1, &out)
    }

    /// The commands of polylines: each a move, its lines, and a close if it
    /// was closed.
    static func commands(_ polylines: [FlatSubpath]) -> [PathCommand] {
        var commands: [PathCommand] = []
        for line in polylines {
            guard let first = line.points.first else { continue }
            commands.append(.move(first.x, first.y))
            for point in line.points.dropFirst() { commands.append(.line(point.x, point.y)) }
            if line.closed { commands.append(.close) }
        }
        return commands
    }

    /// A tolerance for flattening paths for their fill: a ten-thousandth of
    /// their size, between 0.0001 and 0.1.
    static func fillTolerance(_ commands: [PathCommand]) -> Double {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for point in PathState(commands).points where point.0.isFinite && point.1.isFinite {
            minX = min(minX, point.0); maxX = max(maxX, point.0)
            minY = min(minY, point.1); maxY = max(maxY, point.1)
        }
        guard minX <= maxX else { return 0.01 }
        let size = PathPoint(x: maxX - minX, y: maxY - minY).length
        return min(0.1, max(1e-4, size * 1e-4))
    }
}

/// A filled region: the edges of its subpaths, each closed as filling
/// closes it.
struct FilledRegion {
    let edges: [PathEdge]
    let evenOdd: Bool

    init(_ commands: [PathCommand], tolerance: Double, evenOdd: Bool) {
        var edges: [PathEdge] = []
        for line in Flattening.polylines(commands, tolerance: tolerance) where line.points.count >= 2 {
            let points = line.points.filter(\.isFinite)
            guard points.count >= 2 else { continue }
            for index in points.indices {
                let a = points[index], b = points[(index + 1) % points.count]
                if a != b { edges.append(PathEdge(a: a, b: b)) }
            }
        }
        self.edges = edges
        self.evenOdd = evenOdd
    }

    /// The winding number at `p`: edges crossing the horizontal ray to its
    /// right, upward ones counting one and downward ones minus one.
    func winding(at p: PathPoint) -> Int {
        var winding = 0
        for edge in edges {
            let side = (edge.b - edge.a).cross(p - edge.a)
            if edge.a.y <= p.y {
                if edge.b.y > p.y && side > 0 { winding += 1 }
            } else if edge.b.y <= p.y && side < 0 {
                winding -= 1
            }
        }
        return winding
    }

    func contains(_ p: PathPoint) -> Bool {
        let winding = winding(at: p)
        return evenOdd ? winding & 1 != 0 : winding != 0
    }
}

/// Edges split at every point where they meet one another.
enum Arrangement {
    /// The largest coordinate's magnitude, at least 1, by which tolerances
    /// scale.
    static func scale(_ edges: [PathEdge]) -> Double {
        var scale = 1.0
        for edge in edges { scale = max(scale, abs(edge.a.x), abs(edge.a.y), abs(edge.b.x), abs(edge.b.y)) }
        return scale
    }

    /// The edges' pieces between the points where they cross, touch or
    /// overlap. A point two edges share is the same value in both, so the
    /// pieces meet exactly.
    static func split(_ edges: [PathEdge], scale: Double) -> [PathEdge] {
        let count = edges.count
        let near = scale * 1e-12
        var cuts = [[(t: Double, point: PathPoint)]](repeating: [], count: count)
        // Edges by their left end, so each is tested only against those
        // that overlap it horizontally.
        let order = edges.indices.sorted { min(edges[$0].a.x, edges[$0].b.x) < min(edges[$1].a.x, edges[$1].b.x) }
        for (position, i) in order.enumerated() {
            let e = edges[i]
            let maxX = max(e.a.x, e.b.x) + near, minY = min(e.a.y, e.b.y) - near, maxY = max(e.a.y, e.b.y) + near
            var next = position + 1
            while next < count {
                let j = order[next]
                next += 1
                let f = edges[j]
                if min(f.a.x, f.b.x) > maxX { break }
                if max(f.a.y, f.b.y) < minY || min(f.a.y, f.b.y) > maxY { continue }
                intersect(i, e, j, f, scale: scale, &cuts)
            }
        }
        var pieces: [PathEdge] = []
        pieces.reserveCapacity(count)
        let shortest = scale * 1e-12
        for (index, edge) in edges.enumerated() {
            var points = [edge.a]
            for cut in cuts[index].sorted(by: { $0.t < $1.t }) where (cut.point - points[points.count - 1]).length > shortest {
                points.append(cut.point)
            }
            if (edge.b - points[points.count - 1]).length > shortest || points.count == 1 { points.append(edge.b) }
            else { points[points.count - 1] = edge.b }
            for k in 0..<(points.count - 1) where points[k] != points[k + 1] {
                pieces.append(PathEdge(a: points[k], b: points[k + 1]))
            }
        }
        return pieces
    }

    /// Records where e and f meet, as a cut of each strictly inside it.
    private static func intersect(_ i: Int, _ e: PathEdge, _ j: Int, _ f: PathEdge, scale: Double,
                                  _ cuts: inout [[(t: Double, point: PathPoint)]]) {
        let r = e.b - e.a, s = f.b - f.a
        let lr = r.length, ls = s.length
        guard lr > 0, ls > 0 else { return }
        let qp = f.a - e.a
        let denominator = r.cross(s)
        let inside = 1e-12
        if abs(denominator) > 1e-12 * lr * ls {
            let t = qp.cross(s) / denominator, u = qp.cross(r) / denominator
            guard t >= -inside, t <= 1 + inside, u >= -inside, u <= 1 + inside else { return }
            // An end point that lies on the other edge is the point itself.
            let point: PathPoint
            if u <= inside { point = f.a }
            else if u >= 1 - inside { point = f.b }
            else if t <= inside { point = e.a }
            else if t >= 1 - inside { point = e.b }
            else { point = e.a + r * t }
            if t > inside && t < 1 - inside { cuts[i].append((t, point)) }
            if u > inside && u < 1 - inside { cuts[j].append((u, point)) }
            return
        }
        // Parallel: overlapping when on one line, each cut at the other's
        // end points.
        guard abs(qp.cross(r)) / lr <= scale * 1e-10 else { return }
        for point in [f.a, f.b] {
            let t = (point - e.a).dot(r) / (lr * lr)
            if t > inside && t < 1 - inside { cuts[i].append((t, point)) }
        }
        for point in [e.a, e.b] {
            let u = (point - f.a).dot(s) / (ls * ls)
            if u > inside && u < 1 - inside { cuts[j].append((u, point)) }
        }
    }
}

/// Points within a tolerance of one another made one, so pieces whose ends
/// were computed apart still meet.
final class PointSnapper {
    private struct Cell: Hashable { let x: Int64, y: Int64 }
    private let tolerance: Double
    private var cells: [Cell: [PathPoint]] = [:]

    init(tolerance: Double) { self.tolerance = tolerance }

    func snap(_ point: PathPoint) -> PathPoint {
        let cx = Int64((point.x / tolerance).rounded(.down)), cy = Int64((point.y / tolerance).rounded(.down))
        for dx in -1...1 {
            for dy in -1...1 {
                for known in cells[Cell(x: cx + Int64(dx), y: cy + Int64(dy))] ?? [] where (known - point).length <= tolerance {
                    return known
                }
            }
        }
        cells[Cell(x: cx, y: cy), default: []].append(point)
        return point
    }
}

enum PathBoolean {
    enum Operation {
        case union, intersection, subtraction, symmetricDifference, normalization

        func apply(_ a: Bool, _ b: Bool) -> Bool {
            switch self {
            case .union: return a || b
            case .intersection: return a && b
            case .subtraction: return a && !b
            case .symmetricDifference: return a != b
            case .normalization: return a
            }
        }
    }

    /// The boundary of the region the operation gives, as closed loops with
    /// the region on their left.
    static func loops(_ a: [PathCommand], _ b: [PathCommand], _ operation: Operation, evenOdd: Bool) -> [[PathPoint]] {
        let tolerance = Flattening.fillTolerance(a + b)
        let first = FilledRegion(a, tolerance: tolerance, evenOdd: evenOdd)
        let second = FilledRegion(b, tolerance: tolerance, evenOdd: evenOdd)
        let all = first.edges + second.edges
        guard !all.isEmpty else { return [] }
        let scale = Arrangement.scale(all)
        let snapper = PointSnapper(tolerance: scale * 1e-9)
        // How far beside a piece its two sides are sampled: well beyond the
        // snapping, well within any feature that matters.
        let offset = scale * 1e-7
        struct Key: Hashable { let a: PathPoint, b: PathPoint }
        var seen = Set<Key>()
        var boundary: [PathEdge] = []
        for piece in Arrangement.split(all, scale: scale) {
            let a = snapper.snap(piece.a), b = snapper.snap(piece.b)
            guard a != b else { continue }
            let direction = b - a, length = direction.length
            let normal = PathPoint(x: -direction.y / length, y: direction.x / length)
            let middle = a.midpoint(b)
            let left = middle + normal * offset, right = middle - normal * offset
            let insideLeft = operation.apply(first.contains(left), second.contains(left))
            let insideRight = operation.apply(first.contains(right), second.contains(right))
            guard insideLeft != insideRight else { continue }
            let edge = insideLeft ? PathEdge(a: a, b: b) : PathEdge(a: b, b: a)
            if seen.insert(Key(a: edge.a, b: edge.b)).inserted { boundary.append(edge) }
        }
        return link(boundary)
    }

    /// Joins edges end to start into closed loops. Where several leave a
    /// point, the one turning furthest right is taken, which keeps loops
    /// that touch at a point apart.
    static func link(_ edges: [PathEdge]) -> [[PathPoint]] {
        var outgoing: [PathPoint: [Int]] = [:]
        for (index, edge) in edges.enumerated() { outgoing[edge.a, default: []].append(index) }
        var used = [Bool](repeating: false, count: edges.count)
        var loops: [[PathPoint]] = []
        for first in edges.indices where !used[first] {
            var loop: [PathPoint] = []
            var index = first
            let start = edges[first].a
            while true {
                used[index] = true
                let edge = edges[index]
                loop.append(edge.a)
                if edge.b == start { break }
                let incoming = edge.b - edge.a
                var best: Int?
                var bestTurn = Double.infinity
                for candidate in outgoing[edge.b] ?? [] where !used[candidate] {
                    let out = edges[candidate].b - edges[candidate].a
                    let turn = atan2(incoming.cross(out), incoming.dot(out))
                    if turn < bestTurn { (best, bestTurn) = (candidate, turn) }
                }
                guard let best else { break }
                index = best
            }
            let simplified = simplify(loop)
            if simplified.count >= 3 { loops.append(simplified) }
        }
        return loops
    }

    /// Drops points where a loop goes straight on.
    static func simplify(_ loop: [PathPoint]) -> [PathPoint] {
        var points = loop
        var changed = true
        while changed && points.count >= 3 {
            changed = false
            var kept: [PathPoint] = []
            for index in points.indices {
                let previous = kept.last ?? points[(index + points.count - 1) % points.count]
                let point = points[index], next = points[(index + 1) % points.count]
                let a = point - previous, b = next - point
                let straight = abs(a.cross(b)) <= 1e-12 * max(a.length * b.length, 1e-300) && a.dot(b) > 0
                if point == previous || straight { changed = true; continue }
                kept.append(point)
            }
            points = kept
        }
        return points
    }

    static func commands(_ loops: [[PathPoint]]) -> [PathCommand] {
        Flattening.commands(loops.map { FlatSubpath(points: $0, closed: true) })
    }

    /// Twice the loop's signed area: positive counterclockwise.
    static func signedArea(_ loop: [PathPoint]) -> Double {
        var area = 0.0
        for index in loop.indices { area += loop[index].cross(loop[(index + 1) % loop.count]) }
        return area
    }

    static func winding(_ loop: [PathPoint], at p: PathPoint) -> Int {
        var winding = 0
        for index in loop.indices {
            let a = loop[index], b = loop[(index + 1) % loop.count]
            let side = (b - a).cross(p - a)
            if a.y <= p.y {
                if b.y > p.y && side > 0 { winding += 1 }
            } else if b.y <= p.y && side < 0 {
                winding -= 1
            }
        }
        return winding
    }

    /// The filled region's connected parts: each outer boundary with the
    /// holes directly inside it.
    static func components(_ path: [PathCommand], evenOdd: Bool) -> [[PathCommand]] {
        let boundary = loops(path, [], .normalization, evenOdd: evenOdd)
        let areas = boundary.map(signedArea)
        let outers = boundary.indices.filter { areas[$0] > 0 }
        var holes: [Int: [Int]] = [:]
        var scale = 1.0
        for loop in boundary { for point in loop { scale = max(scale, abs(point.x), abs(point.y)) } }
        for hole in boundary.indices where areas[hole] < 0 {
            // A point of the region just beside the hole's first edge: the
            // region is on the left of every boundary edge.
            let loop = boundary[hole], a = loop[0], b = loop[1 % loop.count]
            let direction = b - a, length = max(direction.length, 1e-300)
            let p = a.midpoint(b) + PathPoint(x: -direction.y / length, y: direction.x / length) * (scale * 1e-7)
            var owner: Int?
            for outer in outers where winding(boundary[outer], at: p) != 0 {
                if let current = owner, areas[outer] >= areas[current] { continue }
                owner = outer
            }
            if let owner { holes[owner, default: []].append(hole) }
        }
        return outers.map { outer in commands([boundary[outer]] + (holes[outer] ?? []).map { boundary[$0] }) }
    }

    /// A path's lines, unfilled, cut where they cross the mask's boundary;
    /// the pieces inside the mask's fill (or outside it) are kept, and
    /// pieces that continue one another stay one subpath.
    static func clipLines(_ path: [PathCommand], mask: [PathCommand], evenOdd: Bool, inside keepInside: Bool) -> [PathCommand] {
        let tolerance = Flattening.fillTolerance(path + mask)
        let region = FilledRegion(mask, tolerance: tolerance, evenOdd: evenOdd)
        let scale = Arrangement.scale(region.edges)
        var commands: [PathCommand] = []
        for line in Flattening.polylines(path, tolerance: tolerance) {
            var points = line.points.filter(\.isFinite)
            guard points.count >= 2 || (points.count == 1 && line.closed) else { continue }
            if line.closed { points.append(points[0]) }
            var last: PathPoint?
            var everyPieceKept = true
            let firstCommand = commands.count
            for index in 0..<max(points.count - 1, 0) {
                let a = points[index], b = points[index + 1]
                guard a != b else { continue }
                for (p0, p1) in pieces(a, b, region.edges, scale: scale) {
                    if region.contains(p0.midpoint(p1)) == keepInside {
                        if last != p0 { commands.append(.move(p0.x, p0.y)) }
                        commands.append(.line(p1.x, p1.y))
                        last = p1
                    } else {
                        everyPieceKept = false
                        last = nil
                    }
                }
            }
            // A closed subpath kept whole stays closed.
            if line.closed && everyPieceKept && commands.count > firstCommand, case .line = commands[commands.count - 1] {
                commands[commands.count - 1] = .close
            }
        }
        return commands
    }

    /// The segment from a to b in pieces between the points where it meets
    /// the edges.
    private static func pieces(_ a: PathPoint, _ b: PathPoint, _ edges: [PathEdge], scale: Double) -> [(PathPoint, PathPoint)] {
        let r = b - a, lr = r.length
        var ts: [Double] = []
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        for edge in edges {
            if max(edge.a.x, edge.b.x) < minX || min(edge.a.x, edge.b.x) > maxX
                || max(edge.a.y, edge.b.y) < minY || min(edge.a.y, edge.b.y) > maxY { continue }
            let s = edge.b - edge.a, ls = s.length
            guard ls > 0 else { continue }
            let qp = edge.a - a
            let denominator = r.cross(s)
            if abs(denominator) > 1e-12 * lr * ls {
                let t = qp.cross(s) / denominator, u = qp.cross(r) / denominator
                if t > 0 && t < 1 && u >= 0 && u <= 1 { ts.append(t) }
            } else if abs(qp.cross(r)) / lr <= scale * 1e-10 {
                for point in [edge.a, edge.b] {
                    let t = (point - a).dot(r) / (lr * lr)
                    if t > 0 && t < 1 { ts.append(t) }
                }
            }
        }
        ts.sort()
        var points = [a]
        for t in ts {
            let point = a + r * t
            if (point - points[points.count - 1]).length > scale * 1e-12 { points.append(point) }
        }
        if (b - points[points.count - 1]).length > scale * 1e-12 || points.count == 1 { points.append(b) }
        else { points[points.count - 1] = b }
        return (0..<(points.count - 1)).map { (points[$0], points[$0 + 1]) }
    }
}

// MARK: - CGPath's geometry functions

private func boolean(_ path: Ref?, _ mask: Ref?, _ operation: PathBoolean.Operation, _ evenOdd: Bool) -> Ref? {
    guard let a = Paths.state(path)?.commands, let b = Paths.state(mask)?.commands else { return nil }
    return Paths.make(PathBoolean.commands(PathBoolean.loops(a, b, operation, evenOdd: evenOdd)))
}

/// Curves as lines no further than the threshold from them.
@DarwinC("_CGPathCreateCopyByFlattening")
public func CGPathCreateCopyByFlattening(_ path: Ref?, _ threshold: CGFloat) -> Ref? {
    guard let commands = Paths.state(path)?.commands else { return nil }
    let tolerance = Double(threshold) > 0 ? Double(threshold) : 0.5
    return Paths.make(Flattening.commands(Flattening.polylines(commands, tolerance: tolerance)))
}

/// The fill as a path without self-intersections or overlaps.
@c(_CGPathCreateCopyByNormalizing)
public func CGPathCreateCopyByNormalizing(_ path: Ref?, _ evenOdd: Bool) -> Ref? {
    guard let commands = Paths.state(path)?.commands else { return nil }
    return Paths.make(PathBoolean.commands(PathBoolean.loops(commands, [], .normalization, evenOdd: evenOdd)))
}

@c(_CGPathCreateCopyByUnioningPath)
public func CGPathCreateCopyByUnioningPath(_ path: Ref?, _ mask: Ref?, _ evenOdd: Bool) -> Ref? { boolean(path, mask, .union, evenOdd) }

@c(_CGPathCreateCopyByIntersectingPath)
public func CGPathCreateCopyByIntersectingPath(_ path: Ref?, _ mask: Ref?, _ evenOdd: Bool) -> Ref? {
    boolean(path, mask, .intersection, evenOdd)
}

@c(_CGPathCreateCopyBySubtractingPath)
public func CGPathCreateCopyBySubtractingPath(_ path: Ref?, _ mask: Ref?, _ evenOdd: Bool) -> Ref? {
    boolean(path, mask, .subtraction, evenOdd)
}

@c(_CGPathCreateCopyBySymmetricDifferenceOfPath)
public func CGPathCreateCopyBySymmetricDifferenceOfPath(_ path: Ref?, _ mask: Ref?, _ evenOdd: Bool) -> Ref? {
    boolean(path, mask, .symmetricDifference, evenOdd)
}

/// The path's lines where they lie inside the mask's fill.
@c(_CGPathCreateCopyOfLineByIntersectingPath)
public func CGPathCreateCopyOfLineByIntersectingPath(_ path: Ref?, _ mask: Ref?, _ evenOdd: Bool) -> Ref? {
    guard let a = Paths.state(path)?.commands, let b = Paths.state(mask)?.commands else { return nil }
    return Paths.make(PathBoolean.clipLines(a, mask: b, evenOdd: evenOdd, inside: true))
}

/// The path's lines where they lie outside the mask's fill.
@c(_CGPathCreateCopyOfLineBySubtractingPath)
public func CGPathCreateCopyOfLineBySubtractingPath(_ path: Ref?, _ mask: Ref?, _ evenOdd: Bool) -> Ref? {
    guard let a = Paths.state(path)?.commands, let b = Paths.state(mask)?.commands else { return nil }
    return Paths.make(PathBoolean.clipLines(a, mask: b, evenOdd: evenOdd, inside: false))
}

/// A CFArray of paths, one per connected part of the fill.
@c(_CGPathCreateSeparateComponents)
public func CGPathCreateSeparateComponents(_ path: Ref?, _ evenOdd: Bool) -> Ref? {
    guard let commands = Paths.state(path)?.commands else { return nil }
    let parts = PathBoolean.components(commands, evenOdd: evenOdd).map { NSObject(objCOwned: Paths.make($0)) }
    return NSMutableArray.of(parts).objCOwnedReturnValue()
}

/// Whether the two fills overlap.
@c(_CGPathIntersectsPath)
public func CGPathIntersectsPath(_ path1: Ref?, _ path2: Ref?, _ evenOdd: Bool) -> Bool {
    guard let a = Paths.state(path1)?.commands, let b = Paths.state(path2)?.commands else { return false }
    return !PathBoolean.loops(a, b, .intersection, evenOdd: evenOdd).isEmpty
}
