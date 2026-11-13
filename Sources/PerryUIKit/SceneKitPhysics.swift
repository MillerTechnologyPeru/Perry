import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's physics, without a simulation: bodies and shapes keep what
// they are given, the world keeps its gravity and contact delegate, and its
// ray tests (and the nodes' segment hit tests) are real, against the
// geometry's triangles, which is what apps use the world for to find the
// ground. Sweep and contact tests find nothing, and nothing falls or
// collides.

// MARK: - Bodies and shapes

final class SCNPhysicsBodyState: ObjectState {
    /// SCNPhysicsBodyType: static 0, dynamic 1, kinematic 2.
    var type = 1
    var shape: NSObject?
    var mass: CGFloat = 1
    var friction: CGFloat = 0.5, restitution: CGFloat = 0.5, damping: CGFloat = 0.1, angularDamping: CGFloat = 0.1
    var categoryBitMask = 1, collisionBitMask = -1, contactTestBitMask = 0
    var affectedByGravity = true, allowsResting = true
    var velocity = SCNVector3(x: 0, y: 0, z: 0), angularVelocity = SCNVector4(x: 0, y: 0, z: 0, w: 0)
}

@ObjCClass("SCNPhysicsBody")
open class SCNPhysicsBody: NSObject {
    static let states = StateTable<SCNPhysicsBodyState>()
    var body: SCNPhysicsBodyState { SCNPhysicsBody.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsBody.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsBody.objCClass.pointer)
    }

    private static func make(_ cls: ObjCClass, type: Int, shape: NSObject?) -> SCNPhysicsBody {
        let made = cls.object.allocated().unsafeCast(to: SCNPhysicsBody.self)
        made.body.type = type
        made.body.shape = shape
        return made
    }

    @ObjCClassMethod("staticBody") static func staticBody(_ cls: ObjCClass) -> SCNPhysicsBody { make(cls, type: 0, shape: nil) }
    @ObjCClassMethod("dynamicBody") static func dynamicBody(_ cls: ObjCClass) -> SCNPhysicsBody { make(cls, type: 1, shape: nil) }
    @ObjCClassMethod("kinematicBody") static func kinematicBody(_ cls: ObjCClass) -> SCNPhysicsBody { make(cls, type: 2, shape: nil) }
    @ObjCClassMethod("bodyWithType:shape:")
    static func body(_ cls: ObjCClass, type: Int, shape: NSObject?) -> SCNPhysicsBody { make(cls, type: type, shape: shape) }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("type") func type() -> Int { body.type }
    @ObjCMethod("setType:") func setType(_ type: Int) { body.type = type }
    @ObjCMethod("physicsShape") func physicsShape() -> NSObject? { body.shape }
    @ObjCMethod("setPhysicsShape:") func setPhysicsShape(_ shape: NSObject?) { body.shape = shape }
    @ObjCMethod("mass") func mass() -> CGFloat { body.mass }
    @ObjCMethod("setMass:") func setMass(_ mass: CGFloat) { body.mass = mass }
    @ObjCMethod("friction") func friction() -> CGFloat { body.friction }
    @ObjCMethod("setFriction:") func setFriction(_ friction: CGFloat) { body.friction = friction }
    @ObjCMethod("restitution") func restitution() -> CGFloat { body.restitution }
    @ObjCMethod("setRestitution:") func setRestitution(_ restitution: CGFloat) { body.restitution = restitution }
    @ObjCMethod("damping") func damping() -> CGFloat { body.damping }
    @ObjCMethod("setDamping:") func setDamping(_ damping: CGFloat) { body.damping = damping }
    @ObjCMethod("angularDamping") func angularDamping() -> CGFloat { body.angularDamping }
    @ObjCMethod("setAngularDamping:") func setAngularDamping(_ damping: CGFloat) { body.angularDamping = damping }
    @ObjCMethod("categoryBitMask") func categoryBitMask() -> Int { body.categoryBitMask }
    @ObjCMethod("setCategoryBitMask:") func setCategoryBitMask(_ mask: Int) { body.categoryBitMask = mask }
    @ObjCMethod("collisionBitMask") func collisionBitMask() -> Int { body.collisionBitMask }
    @ObjCMethod("setCollisionBitMask:") func setCollisionBitMask(_ mask: Int) { body.collisionBitMask = mask }
    @ObjCMethod("contactTestBitMask") func contactTestBitMask() -> Int { body.contactTestBitMask }
    @ObjCMethod("setContactTestBitMask:") func setContactTestBitMask(_ mask: Int) { body.contactTestBitMask = mask }
    @ObjCMethod("isAffectedByGravity") func isAffectedByGravity() -> Bool { body.affectedByGravity }
    @ObjCMethod("setAffectedByGravity:") func setAffectedByGravity(_ affected: Bool) { body.affectedByGravity = affected }
    @ObjCMethod("allowsResting") func allowsResting() -> Bool { body.allowsResting }
    @ObjCMethod("setAllowsResting:") func setAllowsResting(_ allows: Bool) { body.allowsResting = allows }
    @ObjCMethod("velocity") func velocity() -> SCNVector3 { body.velocity }
    @ObjCMethod("setVelocity:") func setVelocity(_ velocity: SCNVector3) { body.velocity = velocity }
    @ObjCMethod("angularVelocity") func angularVelocity() -> SCNVector4 { body.angularVelocity }
    @ObjCMethod("setAngularVelocity:") func setAngularVelocity(_ velocity: SCNVector4) { body.angularVelocity = velocity }
    @ObjCMethod("applyForce:impulse:") func applyForce(_ direction: SCNVector3, impulse: Bool) {}
    @ObjCMethod("resetTransform") func resetTransform() {}
    @ObjCMethod("clearAllForces") func clearAllForces() {}
}

final class SCNPhysicsShapeState: ObjectState {
    var source: NSObject?
    var options: NSObject?
}

@ObjCClass("SCNPhysicsShape")
open class SCNPhysicsShape: NSObject {
    static let states = StateTable<SCNPhysicsShapeState>()
    var shape: SCNPhysicsShapeState { SCNPhysicsShape.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsShape.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsShape.objCClass.pointer)
    }

    @ObjCClassMethod("shapeWithGeometry:options:")
    static func shape(_ cls: ObjCClass, geometry: NSObject, options: NSObject?) -> SCNPhysicsShape {
        let made = cls.object.allocated().unsafeCast(to: SCNPhysicsShape.self)
        made.shape.source = geometry
        made.shape.options = options
        return made
    }
    @ObjCClassMethod("shapeWithNode:options:")
    static func shape(_ cls: ObjCClass, node: NSObject, options: NSObject?) -> SCNPhysicsShape {
        let made = cls.object.allocated().unsafeCast(to: SCNPhysicsShape.self)
        made.shape.source = node
        made.shape.options = options
        return made
    }
    @ObjCClassMethod("shapeWithShapes:transforms:")
    static func shape(_ cls: ObjCClass, shapes: NSArray, transforms: NSArray?) -> SCNPhysicsShape {
        cls.object.allocated().unsafeCast(to: SCNPhysicsShape.self)
    }

    @ObjCMethod("sourceObject") func sourceObject() -> NSObject? { shape.source }
    @ObjCMethod("options") func options() -> NSObject? { shape.options }
}

// MARK: - Contacts and results

final class SCNPhysicsContactState: ObjectState {
    var nodeA: SCNNode?, nodeB: SCNNode?
    var point = SCNVector3(x: 0, y: 0, z: 0), normal = SCNVector3(x: 0, y: 0, z: 0)
    var impulse: CGFloat = 0, penetration: CGFloat = 0
    /// How far along a sweep the shape was when it touched.
    var fraction: CGFloat = 0
}

@ObjCClass("SCNPhysicsContact")
open class SCNPhysicsContact: NSObject {
    static let states = StateTable<SCNPhysicsContactState>()
    var contact: SCNPhysicsContactState { SCNPhysicsContact.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsContact.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsContact.objCClass.pointer)
    }

    @ObjCMethod("nodeA") func nodeA() -> SCNNode? { contact.nodeA }
    @ObjCMethod("nodeB") func nodeB() -> SCNNode? { contact.nodeB }
    @ObjCMethod("contactPoint") func contactPoint() -> SCNVector3 { contact.point }
    @ObjCMethod("contactNormal") func contactNormal() -> SCNVector3 { contact.normal }
    @ObjCMethod("collisionImpulse") func collisionImpulse() -> CGFloat { contact.impulse }
    @ObjCMethod("penetrationDistance") func penetrationDistance() -> CGFloat { contact.penetration }
    @ObjCMethod("sweepTestFraction") func sweepTestFraction() -> CGFloat { contact.fraction }
}

/// What a ray test or hit test found: SCNHitTestResult and SCNPhysicsContact's
/// cousin for sweeps share it.
final class SCNHitState: ObjectState {
    var node: SCNNode?
    var world = SCNVector3(x: 0, y: 0, z: 0), worldNormal = SCNVector3(x: 0, y: 0, z: 0)
    var local = SCNVector3(x: 0, y: 0, z: 0), localNormal = SCNVector3(x: 0, y: 0, z: 0)
    var fraction: CGFloat = 0
    var geometryIndex = 0
}

@ObjCClass("SCNHitTestResult")
open class SCNHitTestResult: NSObject {
    static let states = StateTable<SCNHitState>()
    var hit: SCNHitState { SCNHitTestResult.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNHitTestResult.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNHitTestResult.objCClass.pointer)
    }

    @ObjCMethod("node") func node() -> SCNNode? { hit.node }
    @ObjCMethod("worldCoordinates") func worldCoordinates() -> SCNVector3 { hit.world }
    @ObjCMethod("worldNormal") func worldNormal() -> SCNVector3 { hit.worldNormal }
    @ObjCMethod("localCoordinates") func localCoordinates() -> SCNVector3 { hit.local }
    @ObjCMethod("localNormal") func localNormal() -> SCNVector3 { hit.localNormal }
    @ObjCMethod("geometryIndex") func geometryIndex() -> Int { hit.geometryIndex }
}

// MARK: - The world

final class SCNPhysicsWorldState: ObjectState {
    var gravity = SCNVector3(x: 0, y: -9.8, z: 0)
    var speed: CGFloat = 1
    var timeStep: CGFloat = 1.0 / 60
    var delegate: UnsafeMutableRawPointer?
    var scene: UnsafeMutableRawPointer?
    /// The pairs of nodes whose boxes overlapped at the last step.
    var touching: [SCNCollision.Pair: (SCNNode, SCNNode, SCNVector3)] = [:]
}

@ObjCClass("SCNPhysicsWorld")
open class SCNPhysicsWorld: NSObject {
    static let states = StateTable<SCNPhysicsWorldState>()
    var world: SCNPhysicsWorldState { SCNPhysicsWorld.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsWorld.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsWorld.objCClass.pointer)
    }

    @ObjCMethod("gravity") func gravity() -> SCNVector3 { world.gravity }
    @ObjCMethod("setGravity:") func setGravity(_ gravity: SCNVector3) { world.gravity = gravity }
    @ObjCMethod("speed") func speed() -> CGFloat { world.speed }
    @ObjCMethod("setSpeed:") func setSpeed(_ speed: CGFloat) { world.speed = speed }
    @ObjCMethod("timeStep") func timeStep() -> CGFloat { world.timeStep }
    @ObjCMethod("setTimeStep:") func setTimeStep(_ step: CGFloat) { world.timeStep = step }
    @ObjCMethod("contactDelegate") func contactDelegate() -> NSObject? { world.delegate.map { NSObject($0) } }
    @ObjCMethod("setContactDelegate:") func setContactDelegate(_ delegate: NSObject?) { world.delegate = delegate?.objcObject }
    @ObjCMethod("updateCollisionPairs") func updateCollisionPairs() {}

    private var root: SCNNode? { world.scene.map { SCNNode(objcObject: $0, ownership: .retain) } }

    @ObjCMethod("rayTestWithSegmentFromPoint:toPoint:options:")
    func rayTest(from start: SCNVector3, to end: SCNVector3, options: NSObject?) -> NSObject {
        guard let root else { return NSMutableArray.empty() }
        let mask = SCNOptions.number(options, "SCNPhysicsTestCollisionBitMaskKey").map { Int($0) }
        return SCNRays.results(SCNRays.cast(root, from: start, to: end, all: true, categoryMask: mask, ignoreHidden: false), as: SCNHitTestResult.self)
    }

    /// The first thing the shape touches moving from one transform to the other, as one contact; only the
    /// shapes' places count, not their turns.
    @ObjCMethod("convexSweepTestWithShape:fromTransform:toTransform:options:")
    func convexSweepTest(with shape: SCNPhysicsShape, from: SCNMatrix4, to: SCNMatrix4, options: NSObject?) -> NSObject {
        guard let root else { return NSMutableArray.empty() }
        let mask = Int(SCNOptions.number(options, "SCNPhysicsTestCollisionBitMaskKey") ?? -1)
        guard let hit = SCNCollision.sweep(shape, from: SCNVector3(x: from.m41, y: from.m42, z: from.m43), to: SCNVector3(x: to.m41, y: to.m42, z: to.m43),
                                           root: root, collisionMask: mask) else { return NSMutableArray.empty() }
        let contact = SCNPhysicsContact.objCClass.object.allocated().unsafeCast(to: SCNPhysicsContact.self)
        contact.contact.nodeA = hit.node
        contact.contact.point = hit.point
        contact.contact.normal = hit.normal
        contact.contact.fraction = CGFloat(hit.fraction)
        return NSMutableArray.of([contact])
    }
    @ObjCMethod("contactTestBetweenBody:andBody:options:")
    func contactTest(between a: NSObject, and b: NSObject, options: NSObject?) -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("contactTestWithBody:options:") func contactTest(with body: NSObject, options: NSObject?) -> NSObject { NSMutableArray.empty() }
}

@ObjCCategory("SCNScenePhysics")
extension SCNScene {
    @ObjCMethod("physicsWorld")
    func physicsWorld() -> SCNPhysicsWorld {
        let table = SCNExtras.scenes[objcObject]
        if let made = table.objects["physicsWorld"] { return made.unsafeCast(to: SCNPhysicsWorld.self) }
        let made = SCNPhysicsWorld.objCClass.object.allocated().unsafeCast(to: SCNPhysicsWorld.self)
        made.world.scene = rootNode().objcObject
        table.objects["physicsWorld"] = made
        return made
    }

    @ObjCMethod("lightingEnvironment")
    func lightingEnvironment() -> SCNMaterialProperty {
        let table = SCNExtras.scenes[objcObject]
        if let made = table.objects["lightingEnvironment"] { return made.unsafeCast(to: SCNMaterialProperty.self) }
        let made = SCNMaterialProperty.make(contents: nil)
        table.objects["lightingEnvironment"] = made
        return made
    }
}

// MARK: - Rays

enum SCNRays {
    /// What a segment from `start` to `end` (in the scene) meets in the geometry below `root`, nearest first.
    static func cast(_ root: SCNNode, from start: SCNVector3, to end: SCNVector3, all: Bool, categoryMask: Int? = nil, ignoreHidden: Bool = true) -> [SCNHitState] {
        var found: [SCNHitState] = []
        func visit(_ node: SCNNode, parent: Matrix) {
            let state = node.node
            guard !state.hidden || !ignoreHidden else { return }
            let model = SCNMath.multiply(parent, state.local)
            if let geometry = state.geometry, categoryMask.map({ state.categoryBitMask & $0 != 0 }) ?? true {
                let inverse = SCNMath.inverse(model)
                let a = SCNMath.transform(inverse, start), b = SCNMath.transform(inverse, end)
                if let hit = intersect(geometry.geometry, from: a, to: b) {
                    let result = SCNHitState()
                    result.node = node
                    result.local = hit.point
                    result.localNormal = hit.normal
                    result.world = SCNMath.transform(model, hit.point)
                    let normal = SCNMath.normalMatrix(model)
                    let wn = SCNVector3(x: normal[0] * hit.normal.x + normal[3] * hit.normal.y + normal[6] * hit.normal.z,
                                        y: normal[1] * hit.normal.x + normal[4] * hit.normal.y + normal[7] * hit.normal.z,
                                        z: normal[2] * hit.normal.x + normal[5] * hit.normal.y + normal[8] * hit.normal.z)
                    let length = max((wn.x * wn.x + wn.y * wn.y + wn.z * wn.z).squareRoot(), 1e-9)
                    result.worldNormal = SCNVector3(x: wn.x / length, y: wn.y / length, z: wn.z / length)
                    result.fraction = CGFloat(hit.fraction)
                    result.geometryIndex = hit.element
                    found.append(result)
                }
            }
            for child in state.children { visit(child.unsafeCast(to: SCNNode.self), parent: model) }
        }
        visit(root, parent: SCNMath.identity)
        found.sort { $0.fraction < $1.fraction }
        return all ? found : Array(found.prefix(1))
    }

    /// The nearest crossing of the segment with a geometry's triangles, in the geometry's space.
    private static func intersect(_ geometry: SCNGeometryState, from a: SCNVector3, to b: SCNVector3)
        -> (point: SCNVector3, normal: SCNVector3, fraction: Float, element: Int)? {
        let mesh = geometry.mesh
        let v = mesh.vertices
        guard v.count >= 24 else { return nil }
        let d = (b.x - a.x, b.y - a.y, b.z - a.z)
        var best: (t: Float, index: Int, element: Int)?
        for (element, run) in mesh.elements.enumerated() {
            var i = run.first
            while i + 2 < run.first + run.count {
                let p0 = i * 8, p1 = (i + 1) * 8, p2 = (i + 2) * 8
                let e1 = (v[p1] - v[p0], v[p1 + 1] - v[p0 + 1], v[p1 + 2] - v[p0 + 2])
                let e2 = (v[p2] - v[p0], v[p2 + 1] - v[p0 + 1], v[p2 + 2] - v[p0 + 2])
                // Möller–Trumbore: the segment's parameter t in 0...1.
                let h = (d.1 * e2.2 - d.2 * e2.1, d.2 * e2.0 - d.0 * e2.2, d.0 * e2.1 - d.1 * e2.0)
                let det = e1.0 * h.0 + e1.1 * h.1 + e1.2 * h.2
                if abs(det) > 1e-12 {
                    let inv = 1 / det
                    let s = (a.x - v[p0], a.y - v[p0 + 1], a.z - v[p0 + 2])
                    let u = (s.0 * h.0 + s.1 * h.1 + s.2 * h.2) * inv
                    if u >= 0, u <= 1 {
                        let q = (s.1 * e1.2 - s.2 * e1.1, s.2 * e1.0 - s.0 * e1.2, s.0 * e1.1 - s.1 * e1.0)
                        let w = (d.0 * q.0 + d.1 * q.1 + d.2 * q.2) * inv
                        if w >= 0, u + w <= 1 {
                            let t = (e2.0 * q.0 + e2.1 * q.1 + e2.2 * q.2) * inv
                            if t >= 0, t <= 1, best == nil || t < best!.t { best = (t, p0, element) }
                        }
                    }
                }
                i += 3
            }
        }
        guard let hit = best else { return nil }
        let point = SCNVector3(x: a.x + d.0 * hit.t, y: a.y + d.1 * hit.t, z: a.z + d.2 * hit.t)
        let normal = SCNVector3(x: v[hit.index + 3], y: v[hit.index + 4], z: v[hit.index + 5])
        return (point, normal, hit.t, hit.element)
    }

    static func results<T: SCNHitTestResult>(_ hits: [SCNHitState], as type: T.Type) -> NSObject {
        let array = NSMutableArray.empty()
        for hit in hits {
            let made = T.objCClass.object.allocated().unsafeCast(to: T.self)
            SCNHitTestResult.states[made.objcObject].node = hit.node
            SCNHitTestResult.states[made.objcObject].world = hit.world
            SCNHitTestResult.states[made.objcObject].worldNormal = hit.worldNormal
            SCNHitTestResult.states[made.objcObject].local = hit.local
            SCNHitTestResult.states[made.objcObject].localNormal = hit.localNormal
            SCNHitTestResult.states[made.objcObject].fraction = hit.fraction
            SCNHitTestResult.states[made.objcObject].geometryIndex = hit.geometryIndex
            array.add(made)
        }
        return array
    }
}

@ObjCCategory("SCNNodeHitTest")
extension SCNNode {
    @ObjCMethod("hitTestWithSegmentFromPoint:toPoint:options:")
    func hitTest(from start: SCNVector3, to end: SCNVector3, options: NSObject?) -> NSObject {
        // In this node's space, and below it.
        let toScene = world
        let a = SCNMath.transform(toScene, start), b = SCNMath.transform(toScene, end)
        let mask = SCNOptions.number(options, "SCNHitTestCategoryBitMaskKey").map { Int($0) }
        let hidden = SCNOptions.number(options, "SCNHitTestIgnoreHiddenNodesKey") ?? 1
        return SCNRays.results(SCNRays.cast(self, from: a, to: b, all: true, categoryMask: mask, ignoreHidden: hidden != 0), as: SCNHitTestResult.self)
    }
}

@ObjCCategory("SCNViewHitTest")
extension SCNView {
    /// What a point of the view shows, nearest first: a ray from the camera through it.
    @ObjCMethod("hitTest:options:")
    func hitTest(_ point: CGPoint, options: NSObject?) -> NSObject {
        guard let scene = scn.scene else { return NSMutableArray.empty() }
        let near = unprojectPoint(SCNVector3(x: Float(point.x), y: Float(point.y), z: 0))
        let far = unprojectPoint(SCNVector3(x: Float(point.x), y: Float(point.y), z: 1))
        return SCNRays.results(SCNRays.cast(scene.rootNode(), from: near, to: far, all: true), as: SCNHitTestResult.self)
    }
}
