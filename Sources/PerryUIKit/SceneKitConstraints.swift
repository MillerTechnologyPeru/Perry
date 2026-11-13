import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's constraints: rules a node's transform is made to follow after
// each frame's actions, in the order the node lists them: looking at a
// target, keeping a distance from it, facing the camera, limiting how fast
// the node moves, or whatever a block makes of the transform. The nodes are
// taken parents first.

final class SCNConstraintState: ObjectState {
    enum Kind { case base, lookAt, distance, transform, acceleration, billboard }
    enum BlockKind { case position, orientation, transform }
    var kind = Kind.base
    var influence: CGFloat = 1
    var incremental = true

    // Looking at and keeping a distance from a target, which is retained.
    var target: SCNNode?
    var targetOffset = SCNVector3(x: 0, y: 0, z: 0)
    var localFront = SCNVector3(x: 0, y: 0, z: -1)
    var worldUp = SCNVector3(x: 0, y: 1, z: 0)
    var gimbalLock = false
    var minimumDistance: CGFloat = 0, maximumDistance: CGFloat = 0

    // Facing the camera: SCNBillboardAxis, x 1, y 2, z 4.
    var freeAxes = 7

    // A block's.
    var block: ObjCBlock?
    var blockKind = BlockKind.transform
    var inWorldSpace = false

    // Limiting acceleration, with where the node was and how fast it went.
    var maximumLinearAcceleration: CGFloat = 1000
    var maximumLinearVelocity: CGFloat = 1000
    var decelerationDistance: CGFloat = 0.1
    var damping: CGFloat = 0.1
    var previous: SCNVector3?
    var velocity = SCNVector3(x: 0, y: 0, z: 0)
}

@ObjCClass("SCNConstraint")
open class SCNConstraint: NSObject {
    static let states = StateTable<SCNConstraintState>()
    var constraint: SCNConstraintState { SCNConstraint.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNConstraint.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNConstraint.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("influenceFactor") func influenceFactor() -> CGFloat { constraint.influence }
    @ObjCMethod("setInfluenceFactor:") func setInfluenceFactor(_ factor: CGFloat) { constraint.influence = factor }
    @ObjCMethod("isIncremental") func isIncremental() -> Bool { constraint.incremental }
    @ObjCMethod("setIncremental:") func setIncremental(_ incremental: Bool) { constraint.incremental = incremental }
}

@ObjCClass("SCNLookAtConstraint")
open class SCNLookAtConstraint: SCNConstraint {
    @ObjCClassMethod("lookAtConstraintWithTarget:")
    static func lookAt(_ cls: ObjCClass, target: SCNNode?) -> SCNLookAtConstraint {
        let made = cls.object.allocated().unsafeCast(to: SCNLookAtConstraint.self)
        made.constraint.kind = .lookAt
        made.constraint.target = target
        return made
    }

    @ObjCMethod("target") func target() -> SCNNode? { constraint.target }
    @ObjCMethod("setTarget:") func setTarget(_ target: SCNNode?) { constraint.target = target }
    @ObjCMethod("targetOffset") func targetOffset() -> SCNVector3 { constraint.targetOffset }
    @ObjCMethod("setTargetOffset:") func setTargetOffset(_ offset: SCNVector3) { constraint.targetOffset = offset }
    @ObjCMethod("localFront") func localFront() -> SCNVector3 { constraint.localFront }
    @ObjCMethod("setLocalFront:") func setLocalFront(_ front: SCNVector3) { constraint.localFront = front }
    @ObjCMethod("worldUp") func worldUp() -> SCNVector3 { constraint.worldUp }
    @ObjCMethod("setWorldUp:") func setWorldUp(_ up: SCNVector3) { constraint.worldUp = up }
    @ObjCMethod("gimbalLockEnabled") func gimbalLockEnabled() -> Bool { constraint.gimbalLock }
    @ObjCMethod("setGimbalLockEnabled:") func setGimbalLockEnabled(_ enabled: Bool) { constraint.gimbalLock = enabled }
}

@ObjCClass("SCNDistanceConstraint")
open class SCNDistanceConstraint: SCNConstraint {
    @ObjCClassMethod("distanceConstraintWithTarget:")
    static func distance(_ cls: ObjCClass, target: SCNNode?) -> SCNDistanceConstraint {
        let made = cls.object.allocated().unsafeCast(to: SCNDistanceConstraint.self)
        made.constraint.kind = .distance
        made.constraint.target = target
        return made
    }

    @ObjCMethod("target") func target() -> SCNNode? { constraint.target }
    @ObjCMethod("setTarget:") func setTarget(_ target: SCNNode?) { constraint.target = target }
    @ObjCMethod("minimumDistance") func minimumDistance() -> CGFloat { constraint.minimumDistance }
    @ObjCMethod("setMinimumDistance:") func setMinimumDistance(_ distance: CGFloat) { constraint.minimumDistance = distance }
    @ObjCMethod("maximumDistance") func maximumDistance() -> CGFloat { constraint.maximumDistance }
    @ObjCMethod("setMaximumDistance:") func setMaximumDistance(_ distance: CGFloat) { constraint.maximumDistance = distance }
}

@ObjCClass("SCNBillboardConstraint")
open class SCNBillboardConstraint: SCNConstraint {
    @ObjCClassMethod("billboardConstraint")
    static func billboard(_ cls: ObjCClass) -> SCNBillboardConstraint {
        let made = cls.object.allocated().unsafeCast(to: SCNBillboardConstraint.self)
        made.constraint.kind = .billboard
        return made
    }

    @ObjCMethod("freeAxes") func freeAxes() -> Int { constraint.freeAxes }
    @ObjCMethod("setFreeAxes:") func setFreeAxes(_ axes: Int) { constraint.freeAxes = axes }
}

@ObjCClass("SCNAccelerationConstraint")
open class SCNAccelerationConstraint: SCNConstraint {
    @ObjCClassMethod("accelerationConstraint")
    static func acceleration(_ cls: ObjCClass) -> SCNAccelerationConstraint {
        let made = cls.object.allocated().unsafeCast(to: SCNAccelerationConstraint.self)
        made.constraint.kind = .acceleration
        return made
    }

    @ObjCMethod("init") override func initialize() -> Self { constraint.kind = .acceleration; return self }
    @ObjCMethod("maximumLinearAcceleration") func maximumLinearAcceleration() -> CGFloat { constraint.maximumLinearAcceleration }
    @ObjCMethod("setMaximumLinearAcceleration:") func setMaximumLinearAcceleration(_ value: CGFloat) { constraint.maximumLinearAcceleration = value }
    @ObjCMethod("maximumLinearVelocity") func maximumLinearVelocity() -> CGFloat { constraint.maximumLinearVelocity }
    @ObjCMethod("setMaximumLinearVelocity:") func setMaximumLinearVelocity(_ value: CGFloat) { constraint.maximumLinearVelocity = value }
    @ObjCMethod("decelerationDistance") func decelerationDistance() -> CGFloat { constraint.decelerationDistance }
    @ObjCMethod("setDecelerationDistance:") func setDecelerationDistance(_ value: CGFloat) { constraint.decelerationDistance = value }
    @ObjCMethod("damping") func damping() -> CGFloat { constraint.damping }
    @ObjCMethod("setDamping:") func setDamping(_ value: CGFloat) { constraint.damping = value }
}

@ObjCClass("SCNTransformConstraint")
open class SCNTransformConstraint: SCNConstraint {
    private static func make(_ cls: ObjCClass, _ kind: SCNConstraintState.BlockKind, worldSpace: Bool, block: ObjCBlock) -> SCNTransformConstraint {
        let made = cls.object.allocated().unsafeCast(to: SCNTransformConstraint.self)
        made.constraint.kind = .transform
        made.constraint.blockKind = kind
        made.constraint.inWorldSpace = worldSpace
        made.constraint.block = block
        return made
    }

    @ObjCClassMethod("positionConstraintInWorldSpace:withBlock:")
    static func position(_ cls: ObjCClass, inWorldSpace: Bool, block: ObjCBlock) -> SCNTransformConstraint {
        make(cls, .position, worldSpace: inWorldSpace, block: block)
    }
    @ObjCClassMethod("orientationConstraintInWorldSpace:withBlock:")
    static func orientation(_ cls: ObjCClass, inWorldSpace: Bool, block: ObjCBlock) -> SCNTransformConstraint {
        make(cls, .orientation, worldSpace: inWorldSpace, block: block)
    }
    @ObjCClassMethod("transformConstraintInWorldSpace:withBlock:")
    static func transform(_ cls: ObjCClass, inWorldSpace: Bool, block: ObjCBlock) -> SCNTransformConstraint {
        make(cls, .transform, worldSpace: inWorldSpace, block: block)
    }
}

// MARK: - Applying

extension SCNNode {
    /// The transform of the node's parent in the scene.
    var parentWorld: Matrix {
        guard let parent = node.parent, SCNNode.nodeStates.existing(parent) != nil else { return SCNMath.identity }
        return SCNNode(objcObject: parent, ownership: .retain).world
    }

    /// Gives the node the transform in the scene, keeping its pivot out of it.
    func setWorld(_ matrix: Matrix) {
        let parts = SCNMath.decompose(SCNMath.multiply(SCNMath.inverse(parentWorld), matrix))
        node.position = parts.position
        node.rotation = parts.rotation
        node.scale = parts.scale
        node.pivot = SCNMath.identity
    }
}

enum SCNConstraints {
    private typealias V = SCNVector3
    private static func sub(_ a: V, _ b: V) -> V { V(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    private static func add(_ a: V, _ b: V) -> V { V(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    private static func scale(_ a: V, _ s: Float) -> V { V(x: a.x * s, y: a.y * s, z: a.z * s) }
    private static func dot(_ a: V, _ b: V) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
    private static func cross(_ a: V, _ b: V) -> V { V(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
    private static func length(_ a: V) -> Float { dot(a, a).squareRoot() }
    private static func normalized(_ a: V) -> V { let l = length(a); return l > 1e-9 ? scale(a, 1 / l) : a }
    private static func position(of world: Matrix) -> V { V(x: world[12], y: world[13], z: world[14]) }

    /// Applies every node's constraints, parents first.
    static func apply(_ node: SCNNode, elapsed: Double, cameraPosition: SCNVector3?) {
        for constraint in node.node.constraints.map({ $0.unsafeCast(to: SCNConstraint.self) }) {
            apply(constraint.constraint, to: node, elapsed: elapsed, cameraPosition: cameraPosition)
        }
        for child in node.node.children { apply(child.unsafeCast(to: SCNNode.self), elapsed: elapsed, cameraPosition: cameraPosition) }
    }

    private static func apply(_ c: SCNConstraintState, to node: SCNNode, elapsed: Double, cameraPosition: SCNVector3?) {
        let influence = Float(min(max(c.influence, 0), 1))
        guard influence > 0 else { return }
        let before = node.world
        var after = before
        switch c.kind {
        case .base: return
        case .lookAt:
            guard let target = c.target else { return }
            let at = SCNMath.transform(target.world, c.targetOffset)
            after = looking(before, at: at, up: c.worldUp, front: c.localFront) ?? before
        case .billboard:
            guard let camera = cameraPosition else { return }
            var face = camera
            // Only turning about y: look at the camera at the node's own height.
            if c.freeAxes == 2 { face.y = position(of: before).y }
            after = looking(before, at: face, up: V(x: 0, y: 1, z: 0), front: V(x: 0, y: 0, z: 1)) ?? before
        case .distance:
            guard let target = c.target else { return }
            let from = position(of: target.world), here = position(of: before)
            let offset = sub(here, from)
            let distance = length(offset)
            let wanted = min(max(distance, Float(c.minimumDistance)), c.maximumDistance > 0 ? Float(c.maximumDistance) : .greatestFiniteMagnitude)
            guard distance > 1e-9, wanted != distance else { return }
            let moved = add(from, scale(offset, wanted / distance))
            after = before
            after[12] = moved.x; after[13] = moved.y; after[14] = moved.z
        case .acceleration:
            let here = position(of: before), dt = Float(max(elapsed, 1e-4))
            guard let previous = c.previous else { c.previous = here; return }
            // The velocity the frame's own move asks for, limited in how fast it changes and in size.
            var wanted = scale(sub(here, previous), 1 / dt)
            var change = sub(wanted, c.velocity)
            let most = Float(c.maximumLinearAcceleration) * dt
            if length(change) > most { change = scale(normalized(change), most) }
            wanted = add(c.velocity, change)
            let fastest = Float(c.maximumLinearVelocity)
            if length(wanted) > fastest { wanted = scale(normalized(wanted), fastest) }
            wanted = scale(wanted, max(1 - Float(c.damping) * dt, 0))
            c.velocity = wanted
            let moved = add(previous, scale(wanted, dt))
            c.previous = moved
            after = before
            after[12] = moved.x; after[13] = moved.y; after[14] = moved.z
        case .transform:
            guard let block = c.block else { return }
            after = transformed(before, node: node, c, block)
        }
        if influence < 1 { after = blend(before, after, influence) }
        node.setWorld(after)
    }

    /// The world matrix turned to face `at`, keeping its place and scale.
    private static func looking(_ world: Matrix, at target: V, up: V, front: V) -> Matrix? {
        let parts = SCNMath.decompose(world)
        let from = parts.position
        let direction = normalized(sub(target, from))
        guard length(direction) > 0.5 else { return nil }
        // The axes of a node facing along -z: z away from the target, x to the right of it.
        let back = scale(direction, -1)
        var right = cross(up, back)
        if length(right) < 1e-6 { right = cross(V(x: 1, y: 0, z: 0), back) }
        right = normalized(right)
        let top = cross(back, right)
        var rotation = SCNMath.identity
        rotation[0] = right.x; rotation[1] = right.y; rotation[2] = right.z
        rotation[4] = top.x; rotation[5] = top.y; rotation[6] = top.z
        rotation[8] = back.x; rotation[9] = back.y; rotation[10] = back.z
        // A front other than -z is turned to it first.
        let own = normalized(front)
        if abs(own.x) + abs(own.y) + abs(own.z - -1) > 1e-6 {
            let axis = cross(own, V(x: 0, y: 0, z: -1))
            let w = 1 + dot(own, V(x: 0, y: 0, z: -1))
            let q = SCNMath.normalized(w < 1e-6 ? (0, 1, 0, 0) : (axis.x, axis.y, axis.z, w))
            rotation = SCNMath.multiply(rotation, SCNMath.rotation(q))
        }
        return SCNMath.multiply(SCNMath.multiply(SCNMath.translation(from.x, from.y, from.z), rotation),
                                SCNMath.scaling(parts.scale.x, parts.scale.y, parts.scale.z))
    }

    /// The matrix the constraint's block makes of the node's transform.
    private static func transformed(_ world: Matrix, node: SCNNode, _ c: SCNConstraintState, _ block: ObjCBlock) -> Matrix {
        let local = !c.inWorldSpace
        let current = local ? node.node.local : world
        let parts = SCNMath.decompose(current)
        var result = current
        switch c.blockKind {
        case .position:
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, SCNVector3) -> SCNVector3
            let moved = block.function(as: Invoke.self)(block.object, node.objcObject, parts.position)
            result[12] = moved.x; result[13] = moved.y; result[14] = moved.z
        case .orientation:
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, SCNVector4) -> SCNVector4
            let q = parts.rotation
            let turned = block.function(as: Invoke.self)(block.object, node.objcObject, SCNVector4(x: q.x, y: q.y, z: q.z, w: q.w))
            let rotation = SCNMath.rotation((turned.x, turned.y, turned.z, turned.w))
            result = SCNMath.multiply(SCNMath.multiply(SCNMath.translation(parts.position.x, parts.position.y, parts.position.z), rotation),
                                      SCNMath.scaling(parts.scale.x, parts.scale.y, parts.scale.z))
        case .transform:
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, SCNMatrix4) -> SCNMatrix4
            result = SCNMath.matrix(block.function(as: Invoke.self)(block.object, node.objcObject, SCNMath.matrix4(current)))
        }
        // A local result is made a world one through the parent.
        return local ? SCNMath.multiply(node.parentWorld, result) : result
    }

    /// `a` moved `amount` of the way to `b`: positions and scales linearly, rotations by the shorter arc.
    private static func blend(_ a: Matrix, _ b: Matrix, _ amount: Float) -> Matrix {
        let p = SCNMath.decompose(a), q = SCNMath.decompose(b)
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * amount }
        var to = q.rotation
        if p.rotation.x * to.x + p.rotation.y * to.y + p.rotation.z * to.z + p.rotation.w * to.w < 0 { to = (-to.x, -to.y, -to.z, -to.w) }
        let turned = SCNMath.normalized((mix(p.rotation.x, to.x), mix(p.rotation.y, to.y), mix(p.rotation.z, to.z), mix(p.rotation.w, to.w)))
        return SCNMath.multiply(SCNMath.multiply(SCNMath.translation(mix(p.position.x, q.position.x), mix(p.position.y, q.position.y),
                                                                       mix(p.position.z, q.position.z)), SCNMath.rotation(turned)),
                                SCNMath.scaling(mix(p.scale.x, q.scale.x), mix(p.scale.y, q.scale.y), mix(p.scale.z, q.scale.z)))
    }
}
