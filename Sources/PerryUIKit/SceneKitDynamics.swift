import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's dynamic bodies, simply. Each flies and falls as a sphere the
// size of its shape, and bounces off or rolls over the triangles of the
// static and kinematic bodies it collides with. Dynamic bodies pass through
// each other; nothing stacks, tips over or is pushed by a body that moves
// into it, as a real engine has them.

enum SCNDynamics {
    typealias V = SCNVector3
    private static func add(_ a: V, _ b: V) -> V { V(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    private static func sub(_ a: V, _ b: V) -> V { V(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    private static func scale(_ a: V, _ s: Float) -> V { V(x: a.x * s, y: a.y * s, z: a.z * s) }
    private static func dot(_ a: V, _ b: V) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
    private static func cross(_ a: V, _ b: V) -> V { V(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
    private static func length(_ a: V) -> Float { dot(a, a).squareRoot() }

    /// What the simulated bodies hit in the step just taken, for the world's contact delegate: the body's node,
    /// the other's, and where.
    nonisolated(unsafe) static var hits: [(SCNNode, SCNNode, V)] = []

    /// The geometry a body's shape was made from, when it names one of its own.
    static func shapeGeometry(of body: SCNPhysicsBodyState) -> SCNGeometryState? {
        guard let source = body.shape?.unsafeCast(to: SCNPhysicsShape.self).shape.source, source.is(SCNGeometry.self) else { return nil }
        return source.unsafeCast(to: SCNGeometry.self).geometry
    }

    /// Moves the scene's dynamic bodies by `elapsed` seconds.
    static func step(_ scene: SCNScene, _ elapsed: Double) {
        let world = scene.physicsWorld().world
        let dt = Float(elapsed * Double(world.speed))
        guard dt > 0 else { return }
        var moving: [(node: SCNNode, body: SCNPhysicsBodyState)] = []
        func collect(_ node: SCNNode) {
            guard !node.node.hidden else { return }
            if let body = node.node.physicsBody?.unsafeCast(to: SCNPhysicsBody.self).body, body.type == 1 { moving.append((node, body)) }
            for child in node.node.children { collect(child.unsafeCast(to: SCNNode.self)) }
        }
        let root = scene.rootNode()
        collect(root)
        for (node, body) in moving { move(node, body, by: dt, gravity: world.gravity, root: root) }
    }

    /// The radius of the sphere a body moves as, in the scene: a sphere's own, or the mean of half its box's sides.
    private static func radius(of node: SCNNode, _ body: SCNPhysicsBodyState, _ world: Matrix) -> Float {
        let factor = (world[0] * world[0] + world[1] * world[1] + world[2] * world[2]).squareRoot()
        guard let geometry = shapeGeometry(of: body) ?? node.node.geometry?.geometry else {
            guard let box = node.boundingBox() else { return 0.1 * factor }
            return max((box.max.x - box.min.x + box.max.y - box.min.y + box.max.z - box.min.z) / 6, 0.01) * factor
        }
        if geometry.kind == .sphere { return Float(geometry.radius) * factor }
        guard let box = geometry.bounds else { return 0.1 * factor }
        return max((box.max.x - box.min.x + box.max.y - box.min.y + box.max.z - box.min.z) / 6, 0.01) * factor
    }

    private static func move(_ node: SCNNode, _ body: SCNPhysicsBodyState, by dt: Float, gravity: V, root: SCNNode) {
        let mass = max(Float(body.mass), 1e-6)
        var v = body.velocity
        if body.affectedByGravity { v = add(v, scale(gravity, dt)) }
        v = add(v, scale(body.force, dt / mass))
        body.force = V(x: 0, y: 0, z: 0)
        v = scale(v, powf(max(1 - Float(body.damping), 0), dt))

        let world = node.world
        let parent = node.node.parent.map { NSObject($0).unsafeCast(to: SCNNode.self).world } ?? SCNMath.identity
        var p = V(x: world[12], y: world[13], z: world[14])
        let r = radius(of: node, body, world)
        let rolls = (shapeGeometry(of: body) ?? node.node.geometry?.geometry)?.kind == .sphere
        var spin = body.angularVelocity
        var remaining = dt
        // A hair, which a body is kept from what it touched by.
        let skin: Float = 0.002
        for _ in 0..<4 where remaining > 1e-6 {
            let d = scale(v, remaining)
            guard length(d) > 1e-7,
                  let hit = SCNCollision.sweep(radius: r, offsets: [0], from: p, to: add(p, d), root: root, collisionMask: body.collisionBitMask, moving: node)
            else {
                p = add(p, d)
                break
            }
            p = add(add(p, scale(d, hit.fraction)), scale(hit.normal, skin))
            remaining *= 1 - hit.fraction
            let into = dot(v, hit.normal)
            // Touching, but on its way out: only kept clear of the surface.
            guard into < 0 else { continue }
            let other = hit.node.node.physicsBody?.unsafeCast(to: SCNPhysicsBody.self).body
            if let other, body.contactTestBitMask & other.categoryBitMask != 0 || other.contactTestBitMask & body.categoryBitMask != 0 {
                hits.append((node, hit.node, hit.point))
            }
            let bounce = Float(body.restitution) * Float(other?.restitution ?? 0.5)
            var along = sub(v, scale(hit.normal, into))
            // A slow touch comes to rest on the surface; a faster one bounces off it.
            let out = -into * bounce
            let rests = out < length(gravity) * dt * 2 + 0.02
            if rolls {
                // A ball rolls over what it touches, turning as fast as it goes.
                let speed = length(along)
                if speed > 1e-4, r > 1e-4 {
                    let axis = cross(hit.normal, along)
                    let size = length(axis)
                    if size > 1e-6 { spin = SCNVector4(x: axis.x / size, y: axis.y / size, z: axis.z / size, w: speed / r) }
                }
                along = scale(along, max(1 - Float(node.node.physicsBody.map { SCNKept.bodies[$0.objcObject].numbers["rollingFriction"] ?? 0 } ?? 0) * dt, 0))
            } else {
                // Anything else slides, slowed by the surfaces' friction and how hard it is pressed to them.
                let friction = Float(body.friction) * Float(other?.friction ?? 0.5)
                let speed = length(along)
                let lost = friction * (-into + out)
                along = speed > lost ? scale(along, (speed - lost) / speed) : V(x: 0, y: 0, z: 0)
            }
            v = rests ? along : add(along, scale(hit.normal, out))
        }
        // Only along the axes the body is free to move on.
        if let factor = node.node.physicsBody.flatMap({ SCNKept.bodies[$0.objcObject].vectors["velocityFactor"] }) {
            v = V(x: v.x * factor.x, y: v.y * factor.y, z: v.z * factor.z)
        }
        body.velocity = v

        node.node.position = SCNMath.transform(SCNMath.inverse(parent), p)
        if spin.w != 0 {
            let turn = SCNMath.quaternion(axis: V(x: spin.x, y: spin.y, z: spin.z), angle: spin.w * dt)
            node.node.rotation = SCNMath.multiply(turn, node.node.rotation)
            spin.w *= powf(max(1 - Float(body.angularDamping), 0), dt)
            if abs(spin.w) < 1e-3 { spin.w = 0 }
        }
        body.angularVelocity = spin
    }

    /// A push on a body: at once when it is an impulse, else over the next step. One away from the body's middle turns
    /// it too.
    static func push(_ body: SCNPhysicsBodyState, _ force: V, at position: V?, impulse: Bool) {
        let mass = max(Float(body.mass), 1e-6)
        if impulse {
            body.velocity = add(body.velocity, scale(force, 1 / mass))
        } else {
            body.force = add(body.force, force)
        }
        guard let position, impulse else { return }
        twist(body, cross(position, force))
    }

    /// A turning push, as an impulse: about its direction, by its size over the body's reluctance to turn (a ball's of half
    /// a unit across).
    static func twist(_ body: SCNPhysicsBodyState, _ torque: V) {
        let inertia = max(Float(body.mass), 1e-6) * 0.1
        let now = body.angularVelocity
        let total = add(scale(V(x: now.x, y: now.y, z: now.z), now.w), scale(torque, 1 / inertia))
        let size = length(total)
        body.angularVelocity = size > 1e-6 ? SCNVector4(x: total.x / size, y: total.y / size, z: total.z / size, w: size) : SCNVector4(x: 0, y: 0, z: 0, w: 0)
    }
}
