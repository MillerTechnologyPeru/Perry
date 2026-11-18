import CPerryGeometry
import Glibc
import PerryObjCInterop

// SpriteKit's physics, simply. A body is a circle, a box that stays upright
// (a rectangle, a polygon's or a texture's bounds) or a run of edges; each
// frame the dynamic ones fall, move by their velocities, and are pushed out
// of whatever their collision masks say they hit, bouncing by their
// restitution and slowed along the surface by their friction. Two bodies
// that touch, one of them dynamic, with a contact test mask that takes the
// other's category, are a contact: the world's delegate hears it begin and
// end. Speeds are points a second; a body's mass is its area over 150
// points squared, as SpriteKit's metre is 150 points, so an impulse changes
// the speed by itself over the mass.
//
// Not done: turning by collisions (a body spins only as it is told to),
// boxes turned with their nodes, joints (kept, not held), fields, and
// sleeping.

final class SKPhysicsBodyState: ObjectState {
    enum Shape {
        case circle(radius: CGFloat, center: CGPoint)
        case box(size: CGSize, center: CGPoint)
        case edges([(CGPoint, CGPoint)])
    }
    var shape = Shape.circle(radius: 0, center: CGPoint(x: 0, y: 0))
    var dynamic = true, affectedByGravity = true, allowsRotation = true, pinned = false, precise = false
    var velocity = CGPoint(x: 0, y: 0), force = CGPoint(x: 0, y: 0)
    var angularVelocity: CGFloat = 0
    var mass: CGFloat = 1, friction: CGFloat = 0.2, restitution: CGFloat = 0.2, linearDamping: CGFloat = 0.1, angularDamping: CGFloat = 0.1
    var categoryBitMask: UInt32 = 0xFFFF_FFFF, collisionBitMask: UInt32 = 0xFFFF_FFFF, contactTestBitMask: UInt32 = 0, fieldBitMask: UInt32 = 0xFFFF_FFFF
    /// The node the body is on; not retained.
    var node: UnsafeMutableRawPointer?

    var isEdges: Bool {
        if case .edges = shape { return true }
        return false
    }

    var area: CGFloat {
        switch shape {
        case .circle(let radius, _): return CGFloat.pi * radius * radius
        case .box(let size, _): return size.width * size.height
        case .edges: return 0
        }
    }
}

@ObjCClass("SKPhysicsBody")
open class SKPhysicsBody: NSObject {
    static let states = StateTable<SKPhysicsBodyState>()
    var body: SKPhysicsBodyState { SKPhysicsBody.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKPhysicsBody.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKPhysicsBody.objCClass.pointer)
    }

    private static func make(_ cls: ObjCClass, _ shape: SKPhysicsBodyState.Shape) -> SKPhysicsBody {
        let made = cls.object.allocated().unsafeCast(to: SKPhysicsBody.self)
        let state = made.body
        state.shape = shape
        if state.isEdges { state.dynamic = false }
        state.mass = max(state.area / 22500, 0.0001)
        return made
    }

    private static func edges(of path: UnsafeMutableRawPointer?, closing: Bool) -> SKPhysicsBodyState.Shape {
        var segments: [(CGPoint, CGPoint)] = []
        for polygon in path.map({ SKRenderer.polygons(of: $0) }) ?? [] where polygon.points.count > 1 {
            for index in 1..<polygon.points.count { segments.append((polygon.points[index - 1], polygon.points[index])) }
            if closing || polygon.closed, let first = polygon.points.first, let last = polygon.points.last, first != last { segments.append((last, first)) }
        }
        return .edges(segments)
    }

    @ObjCClassMethod("bodyWithCircleOfRadius:")
    static func body(_ cls: ObjCClass, circleOfRadius radius: CGFloat) -> SKPhysicsBody { make(cls, .circle(radius: radius, center: CGPoint(x: 0, y: 0))) }
    @ObjCClassMethod("bodyWithCircleOfRadius:center:")
    static func body(_ cls: ObjCClass, circleOfRadius radius: CGFloat, center: CGPoint) -> SKPhysicsBody { make(cls, .circle(radius: radius, center: center)) }
    @ObjCClassMethod("bodyWithRectangleOfSize:")
    static func body(_ cls: ObjCClass, rectangleOfSize size: CGSize) -> SKPhysicsBody { make(cls, .box(size: size, center: CGPoint(x: 0, y: 0))) }
    @ObjCClassMethod("bodyWithRectangleOfSize:center:")
    static func body(_ cls: ObjCClass, rectangleOfSize size: CGSize, center: CGPoint) -> SKPhysicsBody { make(cls, .box(size: size, center: center)) }
    /// A texture's body is its bounds.
    @ObjCClassMethod("bodyWithTexture:size:")
    static func body(_ cls: ObjCClass, texture: SKTexture?, size: CGSize) -> SKPhysicsBody { make(cls, .box(size: size, center: CGPoint(x: 0, y: 0))) }
    @ObjCClassMethod("bodyWithTexture:alphaThreshold:size:")
    static func body(_ cls: ObjCClass, texture: SKTexture?, alphaThreshold: Float, size: CGSize) -> SKPhysicsBody {
        make(cls, .box(size: size, center: CGPoint(x: 0, y: 0)))
    }
    /// A polygon's body is its bounds.
    @ObjCClassMethod("bodyWithPolygonFromPath:")
    static func body(_ cls: ObjCClass, polygonFromPath path: UnsafeMutableRawPointer?) -> SKPhysicsBody {
        let box = path.map { CG.pathGetBoundingBox($0) } ?? .zero
        return make(cls, .box(size: box.size, center: CGPoint(x: box.midX, y: box.midY)))
    }
    @ObjCClassMethod("bodyWithEdgeLoopFromRect:")
    static func body(_ cls: ObjCClass, edgeLoopFromRect rect: CGRect) -> SKPhysicsBody {
        let a = CGPoint(x: rect.minX, y: rect.minY), b = CGPoint(x: rect.maxX, y: rect.minY)
        let c = CGPoint(x: rect.maxX, y: rect.maxY), d = CGPoint(x: rect.minX, y: rect.maxY)
        return make(cls, .edges([(a, b), (b, c), (c, d), (d, a)]))
    }
    @ObjCClassMethod("bodyWithEdgeFromPoint:toPoint:")
    static func body(_ cls: ObjCClass, edgeFrom a: CGPoint, to b: CGPoint) -> SKPhysicsBody { make(cls, .edges([(a, b)])) }
    @ObjCClassMethod("bodyWithEdgeChainFromPath:")
    static func body(_ cls: ObjCClass, edgeChainFromPath path: UnsafeMutableRawPointer?) -> SKPhysicsBody { make(cls, edges(of: path, closing: false)) }
    @ObjCClassMethod("bodyWithEdgeLoopFromPath:")
    static func body(_ cls: ObjCClass, edgeLoopFromPath path: UnsafeMutableRawPointer?) -> SKPhysicsBody { make(cls, edges(of: path, closing: true)) }
    /// Several bodies as one: the first of them.
    @ObjCClassMethod("bodyWithBodies:")
    static func body(_ cls: ObjCClass, bodies: NSArray?) -> SKPhysicsBody {
        guard let first = bodies?.elements.first, first.is(SKPhysicsBody.self) else { return make(cls, .circle(radius: 0, center: CGPoint(x: 0, y: 0))) }
        return make(cls, first.unsafeCast(to: SKPhysicsBody.self).body.shape)
    }

    @ObjCMethod("isDynamic") func isDynamic() -> Bool { body.dynamic }
    @ObjCMethod("setDynamic:") func setDynamic(_ dynamic: Bool) { body.dynamic = dynamic && !body.isEdges }
    @ObjCMethod("affectedByGravity") func affectedByGravity() -> Bool { body.affectedByGravity }
    @ObjCMethod("setAffectedByGravity:") func setAffectedByGravity(_ affected: Bool) { body.affectedByGravity = affected }
    @ObjCMethod("allowsRotation") func allowsRotation() -> Bool { body.allowsRotation }
    @ObjCMethod("setAllowsRotation:") func setAllowsRotation(_ allows: Bool) { body.allowsRotation = allows }
    @ObjCMethod("pinned") func pinned() -> Bool { body.pinned }
    @ObjCMethod("setPinned:") func setPinned(_ pinned: Bool) { body.pinned = pinned }
    @ObjCMethod("usesPreciseCollisionDetection") func usesPreciseCollisionDetection() -> Bool { body.precise }
    @ObjCMethod("setUsesPreciseCollisionDetection:") func setUsesPreciseCollisionDetection(_ precise: Bool) { body.precise = precise }
    @ObjCMethod("isResting") func isResting() -> Bool { abs(body.velocity.x) < 1 && abs(body.velocity.y) < 1 }
    @ObjCMethod("setResting:") func setResting(_ resting: Bool) { if resting { body.velocity = CGPoint(x: 0, y: 0); body.angularVelocity = 0 } }
    @ObjCMethod("velocity") func velocity() -> CGPoint { body.velocity }
    @ObjCMethod("setVelocity:") func setVelocity(_ velocity: CGPoint) { body.velocity = velocity }
    @ObjCMethod("angularVelocity") func angularVelocity() -> CGFloat { body.angularVelocity }
    @ObjCMethod("setAngularVelocity:") func setAngularVelocity(_ velocity: CGFloat) { body.angularVelocity = velocity }
    @ObjCMethod("mass") func mass() -> CGFloat { body.mass }
    @ObjCMethod("setMass:") func setMass(_ mass: CGFloat) { body.mass = max(mass, 0.0001) }
    @ObjCMethod("density") func density() -> CGFloat { body.area > 0 ? body.mass / (body.area / 22500) : 1 }
    @ObjCMethod("setDensity:") func setDensity(_ density: CGFloat) { body.mass = max(density * body.area / 22500, 0.0001) }
    @ObjCMethod("area") func area() -> CGFloat { body.area / 22500 }
    @ObjCMethod("friction") func friction() -> CGFloat { body.friction }
    @ObjCMethod("setFriction:") func setFriction(_ friction: CGFloat) { body.friction = friction }
    @ObjCMethod("restitution") func restitution() -> CGFloat { body.restitution }
    @ObjCMethod("setRestitution:") func setRestitution(_ restitution: CGFloat) { body.restitution = restitution }
    @ObjCMethod("linearDamping") func linearDamping() -> CGFloat { body.linearDamping }
    @ObjCMethod("setLinearDamping:") func setLinearDamping(_ damping: CGFloat) { body.linearDamping = damping }
    @ObjCMethod("angularDamping") func angularDamping() -> CGFloat { body.angularDamping }
    @ObjCMethod("setAngularDamping:") func setAngularDamping(_ damping: CGFloat) { body.angularDamping = damping }
    @ObjCMethod("categoryBitMask") func categoryBitMask() -> UInt32 { body.categoryBitMask }
    @ObjCMethod("setCategoryBitMask:") func setCategoryBitMask(_ mask: UInt32) { body.categoryBitMask = mask }
    @ObjCMethod("collisionBitMask") func collisionBitMask() -> UInt32 { body.collisionBitMask }
    @ObjCMethod("setCollisionBitMask:") func setCollisionBitMask(_ mask: UInt32) { body.collisionBitMask = mask }
    @ObjCMethod("contactTestBitMask") func contactTestBitMask() -> UInt32 { body.contactTestBitMask }
    @ObjCMethod("setContactTestBitMask:") func setContactTestBitMask(_ mask: UInt32) { body.contactTestBitMask = mask }
    @ObjCMethod("fieldBitMask") func fieldBitMask() -> UInt32 { body.fieldBitMask }
    @ObjCMethod("setFieldBitMask:") func setFieldBitMask(_ mask: UInt32) { body.fieldBitMask = mask }
    @ObjCMethod("node") func node() -> SKNode? { body.node.map { SKNode(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("joints") func joints() -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("allContactedBodies") func allContactedBodies() -> NSObject {
        guard let world = node()?.scene()?.node.physicsWorld else { return NSMutableArray.of([]) }
        return NSMutableArray.of(world.world.touching.values.compactMap { pair in
            pair.a.objcObject == objcObject ? pair.b : pair.b.objcObject == objcObject ? pair.a : nil
        })
    }

    @ObjCMethod("applyImpulse:")
    func applyImpulse(_ impulse: CGPoint) {
        body.velocity = CGPoint(x: body.velocity.x + impulse.x / body.mass, y: body.velocity.y + impulse.y / body.mass)
    }
    @ObjCMethod("applyImpulse:atPoint:") func applyImpulse(_ impulse: CGPoint, at point: CGPoint) { applyImpulse(impulse) }
    @ObjCMethod("applyForce:") func applyForce(_ force: CGPoint) { body.force = CGPoint(x: body.force.x + force.x, y: body.force.y + force.y) }
    @ObjCMethod("applyForce:atPoint:") func applyForce(_ force: CGPoint, at point: CGPoint) { applyForce(force) }
    /// A turn's impulse, over the body's mass and what its area spreads it by.
    @ObjCMethod("applyAngularImpulse:")
    func applyAngularImpulse(_ impulse: CGFloat) {
        let moment = max(body.mass * body.area / 22500 / 2, 0.000001)
        body.angularVelocity += impulse / moment
    }
    @ObjCMethod("applyTorque:") func applyTorque(_ torque: CGFloat) { applyAngularImpulse(torque / 60) }
}

// MARK: - Contacts and joints

final class SKPhysicsContactState: ObjectState {
    var a: SKPhysicsBody?, b: SKPhysicsBody?
    var point = CGPoint(x: 0, y: 0), normal = CGPoint(x: 0, y: 0)
    var impulse: CGFloat = 0
}

@ObjCClass("SKPhysicsContact")
open class SKPhysicsContact: NSObject {
    static let states = StateTable<SKPhysicsContactState>()
    var contact: SKPhysicsContactState { SKPhysicsContact.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKPhysicsContact.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKPhysicsContact.objCClass.pointer)
    }

    @ObjCMethod("bodyA") func bodyA() -> SKPhysicsBody? { contact.a }
    @ObjCMethod("bodyB") func bodyB() -> SKPhysicsBody? { contact.b }
    @ObjCMethod("contactPoint") func contactPoint() -> CGPoint { contact.point }
    @ObjCMethod("contactNormal") func contactNormal() -> CGPoint { contact.normal }
    @ObjCMethod("collisionImpulse") func collisionImpulse() -> CGFloat { contact.impulse }
}

final class SKPhysicsJointState: ObjectState {
    var a: SKPhysicsBody?, b: SKPhysicsBody?
    var anchor = CGPoint(x: 0, y: 0)
}

/// Joints are kept, and hold nothing.
@ObjCClass("SKPhysicsJoint")
open class SKPhysicsJoint: NSObject {
    static let states = StateTable<SKPhysicsJointState>()
    var joint: SKPhysicsJointState { SKPhysicsJoint.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKPhysicsJoint.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKPhysicsJoint.objCClass.pointer)
    }

    @ObjCMethod("bodyA") func bodyA() -> SKPhysicsBody? { joint.a }
    @ObjCMethod("setBodyA:") func setBodyA(_ body: SKPhysicsBody?) { joint.a = body }
    @ObjCMethod("bodyB") func bodyB() -> SKPhysicsBody? { joint.b }
    @ObjCMethod("setBodyB:") func setBodyB(_ body: SKPhysicsBody?) { joint.b = body }
}

@ObjCClass("SKPhysicsJointPin")
open class SKPhysicsJointPin: SKPhysicsJoint {
    @ObjCClassMethod("jointWithBodyA:bodyB:anchor:")
    static func joint(_ cls: ObjCClass, bodyA: SKPhysicsBody?, bodyB: SKPhysicsBody?, anchor: CGPoint) -> SKPhysicsJointPin {
        let made = cls.object.allocated().unsafeCast(to: SKPhysicsJointPin.self)
        (made.joint.a, made.joint.b, made.joint.anchor) = (bodyA, bodyB, anchor)
        return made
    }
}

// MARK: - The world

final class SKPhysicsWorldState: ObjectState {
    var gravity = CGPoint(x: 0, y: -9.8)
    var speed: CGFloat = 1
    /// Not retained.
    var contactDelegate: UnsafeMutableRawPointer?
    var joints: [NSObject] = []
    /// The pairs of bodies touching, by the two bodies' addresses.
    var touching: [String: (a: SKPhysicsBody, b: SKPhysicsBody)] = [:]
}

@ObjCClass("SKPhysicsWorld")
open class SKPhysicsWorld: NSObject {
    static let states = StateTable<SKPhysicsWorldState>()
    var world: SKPhysicsWorldState { SKPhysicsWorld.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKPhysicsWorld.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKPhysicsWorld.objCClass.pointer)
    }

    @ObjCMethod("gravity") func gravity() -> CGPoint { world.gravity }
    @ObjCMethod("setGravity:") func setGravity(_ gravity: CGPoint) { world.gravity = gravity }
    @ObjCMethod("speed") func speed() -> CGFloat { world.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: CGFloat) { world.speed = speed }
    @ObjCMethod("contactDelegate") func contactDelegate() -> NSObject? { world.contactDelegate.map { NSObject($0) } }
    @ObjCMethod("setContactDelegate:") func setContactDelegate(_ delegate: NSObject?) { world.contactDelegate = delegate?.objcObject }
    @ObjCMethod("addJoint:") func addJoint(_ joint: NSObject) { world.joints.append(joint) }
    @ObjCMethod("removeJoint:") func removeJoint(_ joint: NSObject) { world.joints.removeAll { $0.objcObject == joint.objcObject } }
    @ObjCMethod("removeAllJoints") func removeAllJoints() { world.joints = [] }
}

extension NSObject {
    @ObjCMethod("didBeginContact:") func skSendDidBeginContact(_ contact: SKPhysicsContact)
    @ObjCMethod("didEndContact:") func skSendDidEndContact(_ contact: SKPhysicsContact)
}

enum SKPhysics {
    typealias V = CGPoint

    /// A body where it is in its scene.
    private struct Placed {
        enum Form {
            case circle(center: V, radius: CGFloat)
            case box(center: V, half: V)
            case edges([(V, V)])
        }
        var object: SKPhysicsBody
        var state: SKPhysicsBodyState
        var node: SKNode
        var form: Form
        var bounds: CGRect

        /// How far the body reaches from its centre along a direction, for a circle or a box.
        func reach(_ n: V) -> CGFloat {
            switch form {
            case .circle(_, let radius): return radius
            case .box(_, let half): return half.x * abs(n.x) + half.y * abs(n.y)
            case .edges: return 0
            }
        }

        var center: V {
            switch form {
            case .circle(let center, _), .box(let center, _): return center
            case .edges: return V(x: bounds.midX, y: bounds.midY)
            }
        }
    }

    private static func place(_ object: SKPhysicsBody, on node: SKNode) -> Placed {
        let state = object.body
        let matrix = node.toScene()
        let form: Placed.Form
        var bounds: CGRect
        switch state.shape {
        case .circle(let radius, let center):
            let c = matrix.apply(center), r = radius * (matrix.a * matrix.a + matrix.b * matrix.b).squareRoot()
            form = .circle(center: c, radius: r)
            bounds = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .box(let size, let center):
            let corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].map { matrix.apply(V(x: center.x + CGFloat($0.0) * size.width, y: center.y + CGFloat($0.1) * size.height)) }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            form = .box(center: V(x: bounds.midX, y: bounds.midY), half: V(x: bounds.width / 2, y: bounds.height / 2))
        case .edges(let segments):
            let placed = segments.map { (matrix.apply($0.0), matrix.apply($0.1)) }
            let xs = placed.flatMap { [$0.0.x, $0.1.x] }, ys = placed.flatMap { [$0.0.y, $0.1.y] }
            bounds = xs.isEmpty ? .zero : CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            form = .edges(placed)
        }
        return Placed(object: object, state: state, node: node, form: form, bounds: bounds)
    }

    private static func collect(_ node: SKNode, into list: inout [Placed]) {
        if let body = node.node.physicsBody { list.append(place(body, on: node)) }
        for child in node.node.children { collect(child.unsafeCast(to: SKNode.self), into: &list) }
    }

    /// Where `a` (a circle or a box) is into `b`: the way out of it for `a`, how deep, and where they touch.
    private static func hit(_ a: Placed, _ b: Placed) -> (normal: V, depth: CGFloat, point: V)? {
        let slack: CGFloat = 0.5
        guard a.bounds.maxX + slack >= b.bounds.minX, a.bounds.minX - slack <= b.bounds.maxX,
              a.bounds.maxY + slack >= b.bounds.minY, a.bounds.minY - slack <= b.bounds.maxY else { return nil }
        let ca = a.center
        switch (a.form, b.form) {
        case (.edges, _): return nil
        case (_, .edges(let segments)):
            var best: (normal: V, depth: CGFloat, point: V)?
            for (p, q) in segments {
                let d = V(x: q.x - p.x, y: q.y - p.y), length2 = d.x * d.x + d.y * d.y
                let t = length2 > 0 ? min(max(((ca.x - p.x) * d.x + (ca.y - p.y) * d.y) / length2, 0), 1) : 0
                let closest = V(x: p.x + d.x * t, y: p.y + d.y * t)
                var n = V(x: ca.x - closest.x, y: ca.y - closest.y)
                let distance = (n.x * n.x + n.y * n.y).squareRoot()
                n = distance > 0.0001 ? V(x: n.x / distance, y: n.y / distance) : V(x: 0, y: 1)
                let depth = a.reach(n) - distance
                if depth > -slack, depth > (best?.depth ?? -.infinity) { best = (n, depth, closest) }
            }
            return best
        case (.circle(_, let ra), .circle(let cb, let rb)):
            var n = V(x: ca.x - cb.x, y: ca.y - cb.y)
            let distance = (n.x * n.x + n.y * n.y).squareRoot()
            n = distance > 0.0001 ? V(x: n.x / distance, y: n.y / distance) : V(x: 0, y: 1)
            let depth = ra + rb - distance
            return depth > -slack ? (n, depth, V(x: cb.x + n.x * rb, y: cb.y + n.y * rb)) : nil
        case (.circle(_, let radius), .box(let cb, let half)):
            let closest = V(x: min(max(ca.x, cb.x - half.x), cb.x + half.x), y: min(max(ca.y, cb.y - half.y), cb.y + half.y))
            var n = V(x: ca.x - closest.x, y: ca.y - closest.y)
            let distance = (n.x * n.x + n.y * n.y).squareRoot()
            if distance > 0.0001 {
                n = V(x: n.x / distance, y: n.y / distance)
                let depth = radius - distance
                return depth > -slack ? (n, depth, closest) : nil
            }
            // The centre is inside the box: out by the nearest side.
            let dx = half.x - abs(ca.x - cb.x), dy = half.y - abs(ca.y - cb.y)
            return dx < dy ? (V(x: ca.x < cb.x ? -1 : 1, y: 0), dx + radius, ca) : (V(x: 0, y: ca.y < cb.y ? -1 : 1), dy + radius, ca)
        case (.box, .circle):
            guard let other = hit(b, a) else { return nil }
            return (V(x: -other.normal.x, y: -other.normal.y), other.depth, other.point)
        case (.box(_, let ha), .box(let cb, let hb)):
            let dx = ha.x + hb.x - abs(ca.x - cb.x), dy = ha.y + hb.y - abs(ca.y - cb.y)
            guard dx > -slack, dy > -slack else { return nil }
            let point = V(x: (max(ca.x - ha.x, cb.x - hb.x) + min(ca.x + ha.x, cb.x + hb.x)) / 2, y: (max(ca.y - ha.y, cb.y - hb.y) + min(ca.y + ha.y, cb.y + hb.y)) / 2)
            return dx < dy ? (V(x: ca.x < cb.x ? -1 : 1, y: 0), dx, point) : (V(x: 0, y: ca.y < cb.y ? -1 : 1), dy, point)
        }
    }

    /// Moves a body's node by a distance in the scene.
    private static func move(_ node: SKNode, by delta: V) {
        var local = delta
        if let parent = node.parent(), !parent.is(SKScene.self) {
            let m = parent.toScene().inverted
            local = V(x: m.a * delta.x + m.c * delta.y, y: m.b * delta.x + m.d * delta.y)
        }
        node.node.position = V(x: node.node.position.x + local.x, y: node.node.position.y + local.y)
    }

    static func step(_ scene: SKScene, _ elapsed: Double) {
        guard elapsed > 0 else { return }
        var bodies: [Placed] = []
        collect(scene, into: &bodies)
        guard !bodies.isEmpty else {
            scene.node.physicsWorld?.world.touching = [:]
            return
        }
        let world = scene.physicsWorld().world
        let steps = 2
        let h = CGFloat(elapsed) * world.speed / CGFloat(steps)
        guard h > 0 else { return }
        let gravity = V(x: world.gravity.x * 150, y: world.gravity.y * 150)
        var touching: [String: (a: SKPhysicsBody, b: SKPhysicsBody, point: V, normal: V, impulse: CGFloat)] = [:]

        for _ in 0..<steps {
            for index in bodies.indices where bodies[index].state.dynamic && !bodies[index].state.pinned {
                let state = bodies[index].state
                var v = state.velocity
                if state.affectedByGravity { v = V(x: v.x + gravity.x * h, y: v.y + gravity.y * h) }
                v = V(x: v.x + state.force.x / state.mass * h, y: v.y + state.force.y / state.mass * h)
                let damping = max(1 - state.linearDamping * h, 0)
                v = V(x: v.x * damping, y: v.y * damping)
                state.velocity = v
                move(bodies[index].node, by: V(x: v.x * h, y: v.y * h))
                if state.allowsRotation, state.angularVelocity != 0 {
                    bodies[index].node.node.zRotation += state.angularVelocity * h
                    state.angularVelocity *= max(1 - state.angularDamping * h, 0)
                }
                bodies[index] = place(bodies[index].object, on: bodies[index].node)
            }
            for i in bodies.indices {
                for j in bodies.indices where j > i {
                    let (sa, sb) = (bodies[i].state, bodies[j].state)
                    guard sa.dynamic || sb.dynamic else { continue }
                    let collides = (sa.collisionBitMask & sb.categoryBitMask) != 0 || (sb.collisionBitMask & sa.categoryBitMask) != 0
                    let tests = (sa.contactTestBitMask & sb.categoryBitMask) != 0 || (sb.contactTestBitMask & sa.categoryBitMask) != 0
                    guard collides || tests else { continue }
                    // The first of the two is a circle or a box; `normal` is its way out of the other.
                    let swapped = sa.isEdges
                    let (first, second) = swapped ? (j, i) : (i, j)
                    guard let found = hit(bodies[first], bodies[second]) else { continue }
                    var impulse: CGFloat = 0
                    if found.depth > 0 {
                        let (fs, ss) = (bodies[first].state, bodies[second].state)
                        // Who gives way: a dynamic body whose mask takes the other's category.
                        let firstMoves = fs.dynamic && !fs.pinned && (fs.collisionBitMask & ss.categoryBitMask) != 0
                        let secondMoves = ss.dynamic && !ss.pinned && (ss.collisionBitMask & fs.categoryBitMask) != 0
                        if firstMoves || secondMoves {
                            let n = found.normal
                            let wa: CGFloat = firstMoves ? 1 / fs.mass : 0, wb: CGFloat = secondMoves ? 1 / ss.mass : 0
                            let share = wa / (wa + wb)
                            if firstMoves { move(bodies[first].node, by: V(x: n.x * found.depth * share, y: n.y * found.depth * share)) }
                            if secondMoves { move(bodies[second].node, by: V(x: -n.x * found.depth * (1 - share), y: -n.y * found.depth * (1 - share))) }
                            let relative = V(x: fs.velocity.x - ss.velocity.x, y: fs.velocity.y - ss.velocity.y)
                            let along = relative.x * n.x + relative.y * n.y
                            if along < 0 {
                                // A slow touch does not bounce.
                                let bounce = -along > 60 ? max(fs.restitution, ss.restitution) : 0
                                let j = -(1 + bounce) * along / (wa + wb)
                                impulse = j
                                let t = V(x: -n.y, y: n.x)
                                let slide = relative.x * t.x + relative.y * t.y
                                let grip = min(abs(slide), (fs.friction * ss.friction).squareRoot() * abs(along)) * (slide < 0 ? 1 : -1) / (wa + wb)
                                if firstMoves { fs.velocity = V(x: fs.velocity.x + (n.x * j + t.x * grip) * wa, y: fs.velocity.y + (n.y * j + t.y * grip) * wa) }
                                if secondMoves { ss.velocity = V(x: ss.velocity.x - (n.x * j + t.x * grip) * wb, y: ss.velocity.y - (n.y * j + t.y * grip) * wb) }
                            }
                            if firstMoves { bodies[first] = place(bodies[first].object, on: bodies[first].node) }
                            if secondMoves { bodies[second] = place(bodies[second].object, on: bodies[second].node) }
                        }
                    }
                    if tests {
                        let key = "\(UInt(bitPattern: bodies[i].object.objcObject)):\(UInt(bitPattern: bodies[j].object.objcObject))"
                        touching[key] = (bodies[i].object, bodies[j].object, found.point, found.normal, max(impulse, touching[key]?.impulse ?? 0))
                    }
                }
            }
        }
        for body in bodies { body.state.force = V(x: 0, y: 0) }

        // What began and what ended, told once the bodies are where they are: the delegate may take nodes away.
        let before = world.touching
        world.touching = touching.mapValues { ($0.a, $0.b) }
        guard let delegate = world.contactDelegate.map({ NSObject($0) }) else { return }
        func contact(_ a: SKPhysicsBody, _ b: SKPhysicsBody, _ point: V, _ normal: V, _ impulse: CGFloat) -> SKPhysicsContact {
            let made = SKPhysicsContact.objCClass.object.allocated().unsafeCast(to: SKPhysicsContact.self)
            let state = made.contact
            (state.a, state.b, state.point, state.normal, state.impulse) = (a, b, point, normal, impulse)
            return made
        }
        if delegate.responds(to: "didBeginContact:") {
            for (key, pair) in touching where before[key] == nil {
                delegate.skSendDidBeginContact(contact(pair.a, pair.b, pair.point, pair.normal, pair.impulse))
            }
        }
        if delegate.responds(to: "didEndContact:") {
            for (key, pair) in before where touching[key] == nil {
                delegate.skSendDidEndContact(contact(pair.a, pair.b, V(x: 0, y: 0), V(x: 0, y: 0), 0))
            }
        }
    }
}
