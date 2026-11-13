import CPerryGeometry
import Glibc
import PerryObjCInterop

// GameplayKit's entities, components and agents, enough to run a game's
// characters: an entity keeps components and passes them each frame's
// time; an agent steers by its behavior's goals (seeking, fleeing,
// wandering, staying on a path), each a force that the agent's weight for
// it scales, within the agent's acceleration and speed. Agents move in the
// x and z plane of the transforms they are given. Rule systems, state
// machines, path finding, the random sources and the scene files'
// components are not here.

#if _pointerBitWidth(_64)

extension PerrySimdFloat2: ObjCStructure {
    public typealias ObjCType = PerrySimdFloat2
    public static var objCTypeEncoding: String { "<2f>" }
    init(_ x: Float, _ y: Float) { self.init(v: SIMD2(x, y)) }
}

// MARK: - Entities and components

final class GKComponentState: ObjectState {
    /// The entity the component is in, which holds it; not retained.
    var entity: UnsafeMutableRawPointer?
}

@ObjCClass("GKComponent")
open class GKComponent: NSObject {
    static let componentStates = StateTable<GKComponentState>()
    var component: GKComponentState { GKComponent.componentStates[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        GKComponent.componentStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKComponent.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("entity") func entity() -> GKEntity? { component.entity.map { GKEntity(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("updateWithDeltaTime:") func update(deltaTime seconds: Double) {}
    @ObjCMethod("didAddToEntity") func didAddToEntity() {}
    @ObjCMethod("willRemoveFromEntity") func willRemoveFromEntity() {}
}

extension NSObject {
    @ObjCMethod("didAddToEntity") func gkSendDidAddToEntity()
    @ObjCMethod("willRemoveFromEntity") func gkSendWillRemoveFromEntity()
    @ObjCMethod("updateWithDeltaTime:") func gkSendUpdate(deltaTime seconds: Double)
}

final class GKEntityState: ObjectState {
    var components: [NSObject] = []
}

@ObjCClass("GKEntity")
open class GKEntity: NSObject {
    static let states = StateTable<GKEntityState>()
    var entity: GKEntityState { GKEntity.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        for component in entity.components { GKComponent.componentStates.existing(component.objcObject)?.entity = nil }
        GKEntity.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKEntity.objCClass.pointer)
    }

    @ObjCClassMethod("entity") static func make(_ cls: ObjCClass) -> GKEntity { cls.object.allocated().unsafeCast(to: GKEntity.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("components") func components() -> NSObject { NSMutableArray.of(entity.components) }

    @ObjCMethod("addComponent:")
    func addComponent(_ component: GKComponent) {
        guard !entity.components.contains(where: { $0.objcObject == component.objcObject }) else { return }
        entity.components.append(component)
        component.component.entity = objcObject
        component.gkSendDidAddToEntity()
    }

    private func removeComponent(_ component: NSObject) {
        component.gkSendWillRemoveFromEntity()
        GKComponent.componentStates.existing(component.objcObject)?.entity = nil
        entity.components.removeAll { $0.objcObject == component.objcObject }
    }

    @ObjCMethod("removeComponentForClass:")
    func removeComponent(forClass cls: ObjCClass) {
        if let found = entity.components.first(where: { ObjCRuntime.isKind($0.objcObject, of: cls.pointer) }) { removeComponent(found) }
    }

    @ObjCMethod("componentForClass:")
    func component(forClass cls: ObjCClass) -> NSObject? {
        entity.components.first { ObjCRuntime.isKind($0.objcObject, of: cls.pointer) }
    }

    @ObjCMethod("updateWithDeltaTime:")
    func update(deltaTime seconds: Double) {
        for component in entity.components { component.gkSendUpdate(deltaTime: seconds) }
    }
}

@ObjCClass("GKSCNNodeComponent")
open class GKSCNNodeComponent: GKComponent {
    @ObjCClassMethod("componentWithNode:")
    static func component(_ cls: ObjCClass, node: SCNNode) -> GKSCNNodeComponent {
        let made = cls.object.allocated().unsafeCast(to: GKSCNNodeComponent.self)
        GKSCNNodeComponent.nodes[made.objcObject] = node
        return made
    }

    nonisolated(unsafe) static var nodes: [UnsafeMutableRawPointer: SCNNode] = [:]

    @ObjCMethod("initWithNode:") func initialize(node: SCNNode) -> Self { GKSCNNodeComponent.nodes[objcObject] = node; return self }
    @ObjCMethod("node") func node() -> SCNNode? { GKSCNNodeComponent.nodes[objcObject] }
    @ObjCMethod("dealloc") override func dealloc() {
        GKSCNNodeComponent.nodes[objcObject] = nil
        super.dealloc()
    }
}

// MARK: - Scenes

final class GKSceneState: ObjectState {
    var entities: [NSObject] = []
}

@ObjCClass("GKScene")
open class GKScene: NSObject {
    static let states = StateTable<GKSceneState>()
    var scene: GKSceneState { GKScene.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        GKScene.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKScene.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("entities") func entities() -> NSObject { NSMutableArray.of(scene.entities) }
    @ObjCMethod("addEntity:") func addEntity(_ entity: GKEntity) { scene.entities.append(entity) }
    @ObjCMethod("removeEntity:") func removeEntity(_ entity: GKEntity) { scene.entities.removeAll { $0.objcObject == entity.objcObject } }
}

// MARK: - Goals and behaviors

final class GKGoalState: ObjectState {
    enum Kind { case seek, flee, wander, path }
    var kind = Kind.seek
    /// The agent to seek or flee, retained.
    var target: NSObject?
    var speed: Float = 0
    var path: GKPath?
    var predictionTime: Float = 0
    var wanderAngle: Float = 0
}

@ObjCClass("GKGoal")
open class GKGoal: NSObject {
    static let states = StateTable<GKGoalState>()
    var goal: GKGoalState { GKGoal.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        GKGoal.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKGoal.objCClass.pointer)
    }

    private static func make(_ cls: ObjCClass, _ kind: GKGoalState.Kind) -> GKGoal {
        let made = cls.object.allocated().unsafeCast(to: GKGoal.self)
        made.goal.kind = kind
        return made
    }

    @ObjCClassMethod("goalToSeekAgent:") static func seek(_ cls: ObjCClass, agent: NSObject) -> GKGoal {
        let made = make(cls, .seek)
        made.goal.target = agent
        return made
    }
    @ObjCClassMethod("goalToFleeAgent:") static func flee(_ cls: ObjCClass, agent: NSObject) -> GKGoal {
        let made = make(cls, .flee)
        made.goal.target = agent
        return made
    }
    @ObjCClassMethod("goalToWander:") static func wander(_ cls: ObjCClass, speed: Float) -> GKGoal {
        let made = make(cls, .wander)
        made.goal.speed = speed
        return made
    }
    @ObjCClassMethod("goalToStayOnPath:maxPredictionTime:") static func stay(_ cls: ObjCClass, path: GKPath, maxPredictionTime: Double) -> GKGoal {
        let made = make(cls, .path)
        made.goal.path = path
        made.goal.predictionTime = Float(maxPredictionTime)
        return made
    }
}

final class GKPathState: ObjectState {
    var points: [SIMD2<Float>] = []
    var radius: Float = 1
    var cyclical = false
}

@ObjCClass("GKPath")
open class GKPath: NSObject {
    static let states = StateTable<GKPathState>()
    var path: GKPathState { GKPath.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        GKPath.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKPath.objCClass.pointer)
    }

    @ObjCMethod("initWithPoints:count:radius:cyclical:")
    func initialize(points: UnsafeMutableRawPointer?, count: Int, radius: Float, cyclical: Bool) -> Self {
        if let points {
            path.points = (0..<count).map { i in
                SIMD2(points.load(fromByteOffset: i * 8, as: Float.self), points.load(fromByteOffset: i * 8 + 4, as: Float.self))
            }
        }
        path.radius = radius
        path.cyclical = cyclical
        return self
    }

    @ObjCMethod("radius") func radius() -> Float { path.radius }
    @ObjCMethod("setRadius:") func setRadius(_ radius: Float) { path.radius = radius }
    @ObjCMethod("isCyclical") func isCyclical() -> Bool { path.cyclical }
    @ObjCMethod("setCyclical:") func setCyclical(_ cyclical: Bool) { path.cyclical = cyclical }
    @ObjCMethod("numPoints") func numPoints() -> Int { path.points.count }
}

final class GKBehaviorState: ObjectState {
    var goals: [(goal: GKGoal, weight: Float)] = []
}

@ObjCClass("GKBehavior")
open class GKBehavior: NSObject {
    static let states = StateTable<GKBehaviorState>()
    var behavior: GKBehaviorState { GKBehavior.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        GKBehavior.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: GKBehavior.objCClass.pointer)
    }

    @ObjCClassMethod("behaviorWithGoals:")
    static func make(_ cls: ObjCClass, goals: NSArray) -> GKBehavior {
        let made = cls.object.allocated().unsafeCast(to: GKBehavior.self)
        made.behavior.goals = goals.elements.map { ($0.unsafeCast(to: GKGoal.self), 1) }
        return made
    }
    @ObjCClassMethod("behavior") static func empty(_ cls: ObjCClass) -> GKBehavior { cls.object.allocated().unsafeCast(to: GKBehavior.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("setWeight:forGoal:")
    func setWeight(_ weight: Float, forGoal goal: GKGoal) {
        if let index = behavior.goals.firstIndex(where: { $0.goal.objcObject == goal.objcObject }) {
            behavior.goals[index].weight = weight
        } else {
            behavior.goals.append((goal, weight))
        }
    }
    @ObjCMethod("weightForGoal:")
    func weight(forGoal goal: GKGoal) -> Float { behavior.goals.first { $0.goal.objcObject == goal.objcObject }?.weight ?? 0 }
    @ObjCMethod("removeGoal:") func removeGoal(_ goal: GKGoal) { behavior.goals.removeAll { $0.goal.objcObject == goal.objcObject } }
    @ObjCMethod("goalCount") func goalCount() -> Int { behavior.goals.count }
}

// MARK: - Agents

final class GKAgentState: ObjectState {
    var position = SIMD2<Float>(0, 0)
    var velocity = SIMD2<Float>(0, 0)
    var rotation: Float = 0
    /// The height of the transform last set, which a transform given back keeps.
    var height: Float = 0
    var mass: Float = 1
    var radius: Float = 0.5
    var maxSpeed: Float = 100
    var maxAcceleration: Float = 100
    var behavior: GKBehavior?
    var delegate: UnsafeMutableRawPointer?
}

extension NSObject {
    @ObjCMethod("agentWillUpdate:") func gkSendAgentWillUpdate(_ agent: NSObject)
    @ObjCMethod("agentDidUpdate:") func gkSendAgentDidUpdate(_ agent: NSObject)
}

@ObjCClass("GKAgent")
open class GKAgent: GKComponent {
    static let agentStates = StateTable<GKAgentState>()
    var agent: GKAgentState { GKAgent.agentStates[objcObject] }

    @ObjCMethod("dealloc") override func dealloc() {
        GKAgent.agentStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("behavior") func behavior() -> GKBehavior? { agent.behavior }
    @ObjCMethod("setBehavior:") func setBehavior(_ behavior: GKBehavior?) { agent.behavior = behavior }
    @ObjCMethod("delegate") func delegate() -> NSObject? { agent.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { agent.delegate = delegate?.objcObject }
    @ObjCMethod("mass") func mass() -> Float { agent.mass }
    @ObjCMethod("setMass:") func setMass(_ mass: Float) { agent.mass = mass }
    @ObjCMethod("radius") func radius() -> Float { agent.radius }
    @ObjCMethod("setRadius:") func setRadius(_ radius: Float) { agent.radius = radius }
    @ObjCMethod("maxSpeed") func maxSpeed() -> Float { agent.maxSpeed }
    @ObjCMethod("setMaxSpeed:") func setMaxSpeed(_ speed: Float) { agent.maxSpeed = speed }
    @ObjCMethod("maxAcceleration") func maxAcceleration() -> Float { agent.maxAcceleration }
    @ObjCMethod("setMaxAcceleration:") func setMaxAcceleration(_ acceleration: Float) { agent.maxAcceleration = acceleration }
    @ObjCMethod("speed") func speed() -> Float { (agent.velocity * agent.velocity).sum().squareRoot() }
}

@ObjCClass("GKAgent2D")
open class GKAgent2D: GKAgent {
    @ObjCMethod("position") func position() -> PerrySimdFloat2 { PerrySimdFloat2(v: agent.position) }
    @ObjCMethod("setPosition:") func setPosition(_ position: PerrySimdFloat2) { agent.position = position.v }
    @ObjCMethod("velocity") func velocity() -> PerrySimdFloat2 { PerrySimdFloat2(v: agent.velocity) }
    @ObjCMethod("setVelocity:") func setVelocity(_ velocity: PerrySimdFloat2) { agent.velocity = velocity.v }
    @ObjCMethod("rotation") func rotation() -> Float { agent.rotation }
    @ObjCMethod("setRotation:") func setRotation(_ rotation: Float) { agent.rotation = rotation }

    /// The agent's place and facing as a transform: x and z, turned about y.
    @ObjCMethod("transform") func transform() -> PerrySimdFloat4x4 {
        let s = sinf(agent.rotation), c = cosf(agent.rotation)
        return PerrySimdFloat4x4([c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, agent.position.x, agent.height, agent.position.y, 1])
    }
    @ObjCMethod("setTransform:") func setTransform(_ transform: PerrySimdFloat4x4) {
        let m = transform.matrix
        agent.position = SIMD2(m[12], m[14])
        agent.height = m[13]
        agent.rotation = atan2f(m[8], m[0])
    }

    /// Steers by the behavior's goals for `seconds`: their forces, weighted,
    /// make an acceleration within the agent's limit, which changes the
    /// velocity within the top speed, which moves the agent.
    @ObjCMethod("updateWithDeltaTime:")
    override func update(deltaTime seconds: Double) {
        let state = agent
        let dt = Float(seconds)
        if let delegate = state.delegate.map({ NSObject($0) }), delegate.responds(to: "agentWillUpdate:") { delegate.gkSendAgentWillUpdate(self) }
        if let behavior = state.behavior, dt > 0 {
            var force = SIMD2<Float>(0, 0)
            for (goal, weight) in behavior.behavior.goals { force += steering(goal.goal, state) * weight }
            var acceleration = force / max(state.mass, 1e-3)
            let strength = (acceleration * acceleration).sum().squareRoot()
            if strength > state.maxAcceleration { acceleration *= state.maxAcceleration / strength }
            state.velocity += acceleration * dt
            let speed = (state.velocity * state.velocity).sum().squareRoot()
            if speed > state.maxSpeed { state.velocity *= state.maxSpeed / speed }
            state.position += state.velocity * dt
            if speed > 1e-3 { state.rotation = atan2f(state.velocity.x, state.velocity.y) }
        }
        if let delegate = state.delegate.map({ NSObject($0) }), delegate.responds(to: "agentDidUpdate:") { delegate.gkSendAgentDidUpdate(self) }
    }

    /// The force one goal asks of the agent: what takes its velocity to the one it wants.
    private func steering(_ goal: GKGoalState, _ me: GKAgentState) -> SIMD2<Float> {
        func toward(_ target: SIMD2<Float>, speed: Float) -> SIMD2<Float> {
            let offset = target - me.position, length = (offset * offset).sum().squareRoot()
            return length > 1e-6 ? offset / length * speed : SIMD2(0, 0)
        }
        switch goal.kind {
        case .seek, .flee:
            guard let other = goal.target.map({ GKAgent2D(objcObject: $0.objcObject, ownership: .retain) }) else { return SIMD2(0, 0) }
            let desired = toward(other.agent.position, speed: me.maxSpeed) * (goal.kind == .flee ? -1 : 1)
            return desired - me.velocity
        case .wander:
            // A heading that drifts, at the goal's speed.
            goal.wanderAngle += Float.random(in: -0.5...0.5)
            let base = (me.velocity * me.velocity).sum() > 1e-6 ? atan2f(me.velocity.x, me.velocity.y) : me.rotation
            let heading = base + goal.wanderAngle
            return SIMD2(sinf(heading), cosf(heading)) * goal.speed - me.velocity
        case .path:
            guard let path = goal.path?.path, path.points.count >= 2 else { return SIMD2(0, 0) }
            // The nearest point of the path to where the agent will be.
            let ahead = me.position + me.velocity * goal.predictionTime
            var best = path.points[0], bestDistance = Float.greatestFiniteMagnitude
            let count = path.cyclical ? path.points.count : path.points.count - 1
            for i in 0..<count {
                let a = path.points[i], b = path.points[(i + 1) % path.points.count]
                let ab = b - a, length2 = max((ab * ab).sum(), 1e-9)
                let t = min(max(((ahead - a) * ab).sum() / length2, 0), 1)
                let point = a + ab * t
                let d = ((ahead - point) * (ahead - point)).sum()
                if d < bestDistance { (best, bestDistance) = (point, d) }
            }
            // On the path there is nothing to correct.
            guard bestDistance.squareRoot() > path.radius else { return SIMD2(0, 0) }
            return toward(best, speed: me.maxSpeed) - me.velocity
        }
    }
}

#endif
