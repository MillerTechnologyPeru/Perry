import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's collisions, as far as a game needs to walk about: a sphere or
// capsule swept through the triangles of the nodes whose bodies it may hit,
// to the first place it touches, and bodies that ask to be told of contacts
// told when their boxes begin to overlap and when they stop. There is no
// simulation: bodies are not moved by it.

enum SCNOptions {
    /// A number in an options dictionary, by the key's text.
    static func number(_ options: NSObject?, _ key: String) -> Double? {
        guard let options, options.responds(to: "objectForKey:") else { return nil }
        guard let value = options.unsafeCast(to: NSDictionary.self).object(forKey: key), value.responds(to: "doubleValue") else { return nil }
        return value.unsafeCast(to: NSNumber.self).doubleValue()
    }
}

enum SCNCollision {
    typealias V = SCNVector3
    private static func sub(_ a: V, _ b: V) -> V { V(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    private static func add(_ a: V, _ b: V) -> V { V(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    private static func scale(_ a: V, _ s: Float) -> V { V(x: a.x * s, y: a.y * s, z: a.z * s) }
    private static func dot(_ a: V, _ b: V) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
    private static func cross(_ a: V, _ b: V) -> V { V(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
    private static func length(_ a: V) -> Float { dot(a, a).squareRoot() }
    private static func normalized(_ a: V) -> V { let l = length(a); return l > 1e-12 ? scale(a, 1 / l) : a }

    typealias Hit = (t: Float, point: SCNVector3, normal: SCNVector3)

    // MARK: A sphere against a triangle

    /// When a sphere of radius `r` from `c` moving by `d` meets the first of a ray's crossings of a sphere at `v`.
    private static func raySphere(_ c: V, _ d: V, _ v: V, _ r: Float) -> Float? {
        let m = sub(c, v), a = dot(d, d), b = dot(m, d), q = dot(m, m) - r * r
        if q <= 0 { return 0 }
        guard a > 1e-12, b < 0 else { return nil }
        let disc = b * b - a * q
        guard disc >= 0 else { return nil }
        let t = (-b - disc.squareRoot()) / a
        return t <= 1 ? max(t, 0) : nil
    }

    /// The same for the cylinder of radius `r` round the segment p to q, whose ends the spheres at them take.
    private static func rayCylinder(_ c: V, _ d: V, _ p: V, _ q: V, _ r: Float) -> (t: Float, point: V)? {
        let axis = sub(q, p), m = sub(c, p)
        let dd = dot(axis, axis), md = dot(m, axis), nd = dot(d, axis)
        let a = dd * dot(d, d) - nd * nd, b = dd * dot(m, d) - nd * md, k = dd * (dot(m, m) - r * r) - md * md
        guard dd > 1e-12, abs(a) > 1e-9 else { return nil }
        let disc = b * b - a * k
        guard disc >= 0 else { return nil }
        let t = max((-b - disc.squareRoot()) / a, 0)
        guard t <= 1 else { return nil }
        let s = md + t * nd
        guard s >= 0, s <= dd else { return nil }
        return (t, add(p, scale(axis, s / dd)))
    }

    private static func inside(_ p: V, _ a: V, _ b: V, _ c: V) -> Bool {
        let v0 = sub(b, a), v1 = sub(c, a), v2 = sub(p, a)
        let d00 = dot(v0, v0), d01 = dot(v0, v1), d11 = dot(v1, v1), d20 = dot(v2, v0), d21 = dot(v2, v1)
        let denominator = d00 * d11 - d01 * d01
        guard abs(denominator) > 1e-12 else { return false }
        let v = (d11 * d20 - d01 * d21) / denominator, w = (d00 * d21 - d01 * d20) / denominator
        return v >= 0 && w >= 0 && v + w <= 1
    }

    /// Where a sphere moving by `d` first touches the triangle, with the surface's normal there.
    static func sweep(sphere c: V, by d: V, radius r: Float, a: V, b: V, c3: V) -> Hit? {
        var n = normalized(cross(sub(b, a), sub(c3, a)))
        guard length(n) > 0.5 else { return nil }
        var distance = dot(n, sub(c, a))
        // Either side of the triangle stops the sphere.
        if distance < 0 { n = scale(n, -1); distance = -distance }
        var best: Hit?
        if distance <= r {
            let foot = sub(c, scale(n, distance))
            if inside(foot, a, b, c3) { return (0, foot, n) }
        } else {
            let approach = dot(n, d)
            if approach < 0 {
                let t = (distance - r) / -approach
                if t <= 1 {
                    let point = sub(add(c, scale(d, t)), scale(n, r))
                    if inside(point, a, b, c3) { best = (t, point, n) }
                }
            }
        }
        for vertex in [a, b, c3] {
            if let t = raySphere(c, d, vertex, r), best == nil || t < best!.t {
                best = (t, vertex, normalized(sub(add(c, scale(d, t)), vertex)))
            }
        }
        for (p, q) in [(a, b), (b, c3), (c3, a)] {
            if let hit = rayCylinder(c, d, p, q, r), best == nil || hit.t < best!.t {
                best = (hit.t, hit.point, normalized(sub(add(c, scale(d, hit.t)), hit.point)))
            }
        }
        return best
    }

    // MARK: Sweeping a shape through the scene

    /// A shape's spheres: the radius, and where each is above the shape's centre. A sphere is one; a
    /// capsule or cylinder is its two ends and its middle.
    static func spheres(of shape: SCNPhysicsShape) -> (radius: Float, offsets: [Float]) {
        guard let source = shape.shape.source, source.is(SCNGeometry.self) else { return (0.1, [0]) }
        let g = source.unsafeCast(to: SCNGeometry.self).geometry
        switch g.kind {
        case .sphere: return (Float(g.radius), [0])
        case .cylinder, .cone:
            let r = Float(max(g.radius, g.bottomRadius)), half = max(Float(g.height) / 2 - r, 0)
            return (r, half > 0 ? [-half, 0, half] : [0])
        case .box: return (Float(min(g.width, g.length)) / 2, [0])
        default: return (0.1, [0])
        }
    }

    /// The first touch of `shape` moving from the point `from` to `to` with any geometry below `root` whose body
    /// takes `collisionMask`: where the shape is when it touches, the point and the surface's normal.
    static func sweep(_ shape: SCNPhysicsShape, from: V, to: V, root: SCNNode, collisionMask: Int) -> (node: SCNNode, fraction: Float, point: V, normal: V)? {
        let (radius, offsets) = spheres(of: shape)
        let delta = sub(to, from)
        var best: (node: SCNNode, fraction: Float, point: V, normal: V)?
        func visit(_ node: SCNNode, parent: Matrix) {
            let state = node.node
            let model = SCNMath.multiply(parent, state.local)
            if let body = state.physicsBody?.unsafeCast(to: SCNPhysicsBody.self).body, body.categoryBitMask & collisionMask != 0,
               let geometry = state.geometry?.geometry, let box = geometry.bounds {
                let inverse = SCNMath.inverse(model)
                let scaleFactor = max((model[0] * model[0] + model[1] * model[1] + model[2] * model[2]).squareRoot(), 1e-6)
                let r = radius / scaleFactor
                // The box round the geometry, grown by the radius, against the box round the sweep, in the node's space.
                let lo = V(x: box.min.x - r, y: box.min.y - r, z: box.min.z - r), hi = V(x: box.max.x + r, y: box.max.y + r, z: box.max.z + r)
                let mesh = geometry.mesh
                let v = mesh.vertices
                for offset in offsets {
                    let start = SCNMath.transform(inverse, V(x: from.x, y: from.y + offset, z: from.z))
                    let end = SCNMath.transform(inverse, V(x: to.x, y: to.y + offset, z: to.z))
                    let d = sub(end, start)
                    let sweptLo = V(x: min(start.x, end.x) - r, y: min(start.y, end.y) - r, z: min(start.z, end.z) - r)
                    let sweptHi = V(x: max(start.x, end.x) + r, y: max(start.y, end.y) + r, z: max(start.z, end.z) + r)
                    guard sweptHi.x >= lo.x, sweptLo.x <= hi.x, sweptHi.y >= lo.y, sweptLo.y <= hi.y, sweptHi.z >= lo.z, sweptLo.z <= hi.z else { continue }
                    var i = 0
                    while i + 2 < mesh.vertices.count / 8 {
                        let p0 = i * 8, p1 = p0 + 8, p2 = p1 + 8
                        i += 3
                        // A cheap reject by the triangle's box.
                        let tminX = min(v[p0], v[p1], v[p2]), tmaxX = max(v[p0], v[p1], v[p2])
                        if tmaxX < sweptLo.x || tminX > sweptHi.x { continue }
                        let tminY = min(v[p0 + 1], v[p1 + 1], v[p2 + 1]), tmaxY = max(v[p0 + 1], v[p1 + 1], v[p2 + 1])
                        if tmaxY < sweptLo.y || tminY > sweptHi.y { continue }
                        let tminZ = min(v[p0 + 2], v[p1 + 2], v[p2 + 2]), tmaxZ = max(v[p0 + 2], v[p1 + 2], v[p2 + 2])
                        if tmaxZ < sweptLo.z || tminZ > sweptHi.z { continue }
                        let a = V(x: v[p0], y: v[p0 + 1], z: v[p0 + 2]), b = V(x: v[p1], y: v[p1 + 1], z: v[p1 + 2]), c = V(x: v[p2], y: v[p2 + 1], z: v[p2 + 2])
                        guard let hit = sweep(sphere: start, by: d, radius: r, a: a, b: b, c3: c), best == nil || hit.t < best!.fraction else { continue }
                        let normal = SCNMath.normalMatrix(model)
                        let n = normalized(V(x: normal[0] * hit.normal.x + normal[3] * hit.normal.y + normal[6] * hit.normal.z,
                                             y: normal[1] * hit.normal.x + normal[4] * hit.normal.y + normal[7] * hit.normal.z,
                                             z: normal[2] * hit.normal.x + normal[5] * hit.normal.y + normal[8] * hit.normal.z))
                        best = (node, hit.t, SCNMath.transform(model, hit.point), n)
                    }
                }
            }
            for child in state.children { visit(child.unsafeCast(to: SCNNode.self), parent: model) }
        }
        visit(root, parent: SCNMath.identity)
        return best
    }

    // MARK: Contacts

    /// A body's box in the scene.
    private static func box(of node: SCNNode, _ world: Matrix) -> (min: V, max: V)? {
        var local = node.boundingBox()
        if local == nil, let source = node.node.physicsBody?.unsafeCast(to: SCNPhysicsBody.self).body.shape?.unsafeCast(to: SCNPhysicsShape.self).shape.source,
           source.is(SCNGeometry.self) {
            local = source.unsafeCast(to: SCNGeometry.self).geometry.bounds
        }
        guard let local else { return nil }
        var lo = V(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude, z: .greatestFiniteMagnitude)
        var hi = V(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude, z: -.greatestFiniteMagnitude)
        for corner in 0..<8 {
            let p = SCNMath.transform(world, V(x: corner & 1 == 0 ? local.min.x : local.max.x, y: corner & 2 == 0 ? local.min.y : local.max.y,
                                               z: corner & 4 == 0 ? local.min.z : local.max.z))
            lo = V(x: min(lo.x, p.x), y: min(lo.y, p.y), z: min(lo.z, p.z))
            hi = V(x: max(hi.x, p.x), y: max(hi.y, p.y), z: max(hi.z, p.z))
        }
        return (lo, hi)
    }

    struct Pair: Hashable {
        var a: UnsafeMutableRawPointer, b: UnsafeMutableRawPointer
    }

    /// Tells the world's contact delegate of the bodies whose boxes began or stopped overlapping since the last step, for
    /// those that asked by their contact test masks.
    static func step(_ scene: SCNScene) {
        let world = scene.physicsWorld()
        guard let delegate = world.world.delegate.map({ NSObject($0) }) else { return }
        var bodies: [(node: SCNNode, state: SCNPhysicsBodyState, box: (min: V, max: V))] = []
        func collect(_ node: SCNNode, parent: Matrix) {
            let model = SCNMath.multiply(parent, node.node.local)
            if let body = node.node.physicsBody?.unsafeCast(to: SCNPhysicsBody.self).body, let box = box(of: node, model) { bodies.append((node, body, box)) }
            for child in node.node.children { collect(child.unsafeCast(to: SCNNode.self), parent: model) }
        }
        collect(scene.rootNode(), parent: SCNMath.identity)
        var now: [Pair: (SCNNode, SCNNode, V)] = [:]
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let (a, b) = (bodies[i], bodies[j])
                guard a.state.contactTestBitMask & b.state.categoryBitMask != 0 || b.state.contactTestBitMask & a.state.categoryBitMask != 0 else { continue }
                guard a.box.max.x >= b.box.min.x, a.box.min.x <= b.box.max.x, a.box.max.y >= b.box.min.y, a.box.min.y <= b.box.max.y,
                      a.box.max.z >= b.box.min.z, a.box.min.z <= b.box.max.z else { continue }
                let centre = V(x: (max(a.box.min.x, b.box.min.x) + min(a.box.max.x, b.box.max.x)) / 2, y: (max(a.box.min.y, b.box.min.y) + min(a.box.max.y, b.box.max.y)) / 2,
                               z: (max(a.box.min.z, b.box.min.z) + min(a.box.max.z, b.box.max.z)) / 2)
                now[Pair(a: a.node.objcObject, b: b.node.objcObject)] = (a.node, b.node, centre)
            }
        }
        let before = world.world.touching
        func contact(_ nodes: (SCNNode, SCNNode, V)) -> SCNPhysicsContact {
            let made = SCNPhysicsContact.objCClass.object.allocated().unsafeCast(to: SCNPhysicsContact.self)
            made.contact.nodeA = nodes.0
            made.contact.nodeB = nodes.1
            made.contact.point = nodes.2
            return made
        }
        for (pair, nodes) in now where before[pair] == nil && delegate.responds(to: "physicsWorld:didBeginContact:") {
            delegate.scnSendPhysicsWorld(world, didBegin: contact(nodes))
        }
        for (pair, nodes) in before where now[pair] == nil && delegate.responds(to: "physicsWorld:didEndContact:") {
            delegate.scnSendPhysicsWorld(world, didEnd: contact(nodes))
        }
        world.world.touching = now
    }
}

extension NSObject {
    @ObjCMethod("physicsWorld:didBeginContact:") func scnSendPhysicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact)
    @ObjCMethod("physicsWorld:didEndContact:") func scnSendPhysicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact)
}
