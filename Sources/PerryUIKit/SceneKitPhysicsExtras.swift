import CPerryGeometry
import Glibc
import PerryObjCInterop

// More of SceneKit's physics and geometry that is kept and not acted on:
// what an app sets is what it reads back. A body's factors, moment of
// inertia, rolling friction and charge; physics fields, which pull at
// nothing; vehicles, whose wheels turn nothing and whose speed is zero; a
// world's behaviors; and a geometry's levels of detail, of which the
// geometry itself is always the one drawn.

/// Numbers, vectors and objects by name.
final class SCNKeptState: ObjectState {
    var numbers: [String: Double] = [:]
    var vectors: [String: SCNVector3] = [:]
    var objects: [String: NSObject] = [:]
    var lists: [String: [NSObject]] = [:]
}

enum SCNKept {
    static let bodies = StateTable<SCNKeptState>()
    static let worlds = StateTable<SCNKeptState>()
    static let geometries = StateTable<SCNKeptState>()
    static let nodes = StateTable<SCNKeptState>()
}

@ObjCCategory("SCNPhysicsBodyExtras")
extension SCNPhysicsBody {
    private var kept: SCNKeptState { SCNKept.bodies[objcObject] }
    private static let one = SCNVector3(x: 1, y: 1, z: 1), zero = SCNVector3(x: 0, y: 0, z: 0)

    @ObjCMethod("velocityFactor") func velocityFactor() -> SCNVector3 { kept.vectors["velocityFactor"] ?? SCNPhysicsBody.one }
    @ObjCMethod("setVelocityFactor:") func setVelocityFactor(_ factor: SCNVector3) { kept.vectors["velocityFactor"] = factor }
    @ObjCMethod("angularVelocityFactor") func angularVelocityFactor() -> SCNVector3 { kept.vectors["angularVelocityFactor"] ?? SCNPhysicsBody.one }
    @ObjCMethod("setAngularVelocityFactor:") func setAngularVelocityFactor(_ factor: SCNVector3) { kept.vectors["angularVelocityFactor"] = factor }
    @ObjCMethod("momentOfInertia") func momentOfInertia() -> SCNVector3 { kept.vectors["momentOfInertia"] ?? SCNPhysicsBody.one }
    @ObjCMethod("setMomentOfInertia:") func setMomentOfInertia(_ moment: SCNVector3) { kept.vectors["momentOfInertia"] = moment }
    @ObjCMethod("centerOfMassOffset") func centerOfMassOffset() -> SCNVector3 { kept.vectors["centerOfMassOffset"] ?? SCNPhysicsBody.zero }
    @ObjCMethod("setCenterOfMassOffset:") func setCenterOfMassOffset(_ offset: SCNVector3) { kept.vectors["centerOfMassOffset"] = offset }
    @ObjCMethod("usesDefaultMomentOfInertia") func usesDefaultMomentOfInertia() -> Bool { (kept.numbers["defaultMoment"] ?? 1) != 0 }
    @ObjCMethod("setUsesDefaultMomentOfInertia:") func setUsesDefaultMomentOfInertia(_ uses: Bool) { kept.numbers["defaultMoment"] = uses ? 1 : 0 }
    @ObjCMethod("rollingFriction") func rollingFriction() -> CGFloat { CGFloat(kept.numbers["rollingFriction"] ?? 0) }
    @ObjCMethod("setRollingFriction:") func setRollingFriction(_ friction: CGFloat) { kept.numbers["rollingFriction"] = Double(friction) }
    @ObjCMethod("charge") func charge() -> CGFloat { CGFloat(kept.numbers["charge"] ?? 0) }
    @ObjCMethod("setCharge:") func setCharge(_ charge: CGFloat) { kept.numbers["charge"] = Double(charge) }
    @ObjCMethod("continuousCollisionDetectionThreshold") func continuousThreshold() -> CGFloat { CGFloat(kept.numbers["continuous"] ?? 0) }
    @ObjCMethod("setContinuousCollisionDetectionThreshold:") func setContinuousThreshold(_ threshold: CGFloat) { kept.numbers["continuous"] = Double(threshold) }
    @ObjCMethod("linearRestingThreshold") func linearRestingThreshold() -> CGFloat { CGFloat(kept.numbers["linearRest"] ?? 0.1) }
    @ObjCMethod("setLinearRestingThreshold:") func setLinearRestingThreshold(_ threshold: CGFloat) { kept.numbers["linearRest"] = Double(threshold) }
    @ObjCMethod("angularRestingThreshold") func angularRestingThreshold() -> CGFloat { CGFloat(kept.numbers["angularRest"] ?? 0.1) }
    @ObjCMethod("setAngularRestingThreshold:") func setAngularRestingThreshold(_ threshold: CGFloat) { kept.numbers["angularRest"] = Double(threshold) }
    @ObjCMethod("isResting") func isResting() -> Bool { false }
    @ObjCMethod("setResting:") func setResting(_ resting: Bool) {}
}

// MARK: - Fields

@ObjCClass("SCNPhysicsField")
open class SCNPhysicsField: NSObject {
    static let states = StateTable<SCNKeptState>()
    var field: SCNKeptState { SCNPhysicsField.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsField.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsField.objCClass.pointer)
    }

    private static func make(_ cls: ObjCClass) -> SCNPhysicsField { cls.object.allocated().unsafeCast(to: SCNPhysicsField.self) }

    @ObjCClassMethod("dragField") static func dragField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("vortexField") static func vortexField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("radialGravityField") static func radialGravityField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("linearGravityField") static func linearGravityField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("springField") static func springField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("electricField") static func electricField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("magneticField") static func magneticField(_ cls: ObjCClass) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("noiseFieldWithSmoothness:animationSpeed:")
    static func noiseField(_ cls: ObjCClass, smoothness: CGFloat, animationSpeed: CGFloat) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("turbulenceFieldWithSmoothness:animationSpeed:")
    static func turbulenceField(_ cls: ObjCClass, smoothness: CGFloat, animationSpeed: CGFloat) -> SCNPhysicsField { make(cls) }
    @ObjCClassMethod("customFieldWithEvaluationBlock:")
    static func customField(_ cls: ObjCClass, block: ObjCBlock) -> SCNPhysicsField { make(cls) }

    private func number(_ key: String, _ fallback: Double) -> CGFloat { CGFloat(field.numbers[key] ?? fallback) }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("strength") func strength() -> CGFloat { number("strength", 1) }
    @ObjCMethod("setStrength:") func setStrength(_ value: CGFloat) { field.numbers["strength"] = Double(value) }
    @ObjCMethod("falloffExponent") func falloffExponent() -> CGFloat { number("falloff", 0) }
    @ObjCMethod("setFalloffExponent:") func setFalloffExponent(_ value: CGFloat) { field.numbers["falloff"] = Double(value) }
    @ObjCMethod("minimumDistance") func minimumDistance() -> CGFloat { number("minimum", 1e-6) }
    @ObjCMethod("setMinimumDistance:") func setMinimumDistance(_ value: CGFloat) { field.numbers["minimum"] = Double(value) }
    @ObjCMethod("isActive") func isActive() -> Bool { number("active", 1) != 0 }
    @ObjCMethod("setActive:") func setActive(_ active: Bool) { field.numbers["active"] = active ? 1 : 0 }
    @ObjCMethod("isExclusive") func isExclusive() -> Bool { number("exclusive", 0) != 0 }
    @ObjCMethod("setExclusive:") func setExclusive(_ exclusive: Bool) { field.numbers["exclusive"] = exclusive ? 1 : 0 }
    @ObjCMethod("usesEllipsoidalExtent") func usesEllipsoidalExtent() -> Bool { number("ellipsoidal", 0) != 0 }
    @ObjCMethod("setUsesEllipsoidalExtent:") func setUsesEllipsoidalExtent(_ uses: Bool) { field.numbers["ellipsoidal"] = uses ? 1 : 0 }
    @ObjCMethod("scope") func scope() -> Int { Int(number("scope", 0)) }
    @ObjCMethod("setScope:") func setScope(_ scope: Int) { field.numbers["scope"] = Double(scope) }
    @ObjCMethod("categoryBitMask") func categoryBitMask() -> Int { Int(number("category", -1)) }
    @ObjCMethod("setCategoryBitMask:") func setCategoryBitMask(_ mask: Int) { field.numbers["category"] = Double(mask) }
    @ObjCMethod("halfExtent") func halfExtent() -> SCNVector3 {
        field.vectors["halfExtent"] ?? SCNVector3(x: .infinity, y: .infinity, z: .infinity)
    }
    @ObjCMethod("setHalfExtent:") func setHalfExtent(_ extent: SCNVector3) { field.vectors["halfExtent"] = extent }
    @ObjCMethod("offset") func offset() -> SCNVector3 { field.vectors["offset"] ?? SCNVector3(x: 0, y: 0, z: 0) }
    @ObjCMethod("setOffset:") func setOffset(_ offset: SCNVector3) { field.vectors["offset"] = offset }
    @ObjCMethod("direction") func direction() -> SCNVector3 { field.vectors["direction"] ?? SCNVector3(x: 0, y: -1, z: 0) }
    @ObjCMethod("setDirection:") func setDirection(_ direction: SCNVector3) { field.vectors["direction"] = direction }
}

@ObjCCategory("SCNNodePhysicsField")
extension SCNNode {
    @ObjCMethod("physicsField") func physicsField() -> NSObject? { SCNKept.nodes[objcObject].objects["field"] }
    @ObjCMethod("setPhysicsField:") func setPhysicsField(_ field: NSObject?) { SCNKept.nodes[objcObject].objects["field"] = field }
}

// MARK: - Vehicles and behaviors

@ObjCClass("SCNPhysicsBehavior")
open class SCNPhysicsBehavior: NSObject {}

@ObjCClass("SCNPhysicsVehicleWheel")
open class SCNPhysicsVehicleWheel: NSObject {
    static let states = StateTable<SCNKeptState>()
    var wheel: SCNKeptState { SCNPhysicsVehicleWheel.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsVehicleWheel.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsVehicleWheel.objCClass.pointer)
    }

    @ObjCClassMethod("wheelWithNode:")
    static func wheel(_ cls: ObjCClass, node: SCNNode) -> SCNPhysicsVehicleWheel {
        let made = cls.object.allocated().unsafeCast(to: SCNPhysicsVehicleWheel.self)
        made.wheel.objects["node"] = node
        return made
    }

    private func number(_ key: String, _ fallback: Double) -> CGFloat { CGFloat(wheel.numbers[key] ?? fallback) }

    @ObjCMethod("node") func node() -> NSObject? { wheel.objects["node"] }
    @ObjCMethod("suspensionStiffness") func suspensionStiffness() -> CGFloat { number("stiffness", 2) }
    @ObjCMethod("setSuspensionStiffness:") func setSuspensionStiffness(_ value: CGFloat) { wheel.numbers["stiffness"] = Double(value) }
    @ObjCMethod("suspensionCompression") func suspensionCompression() -> CGFloat { number("compression", 4.4) }
    @ObjCMethod("setSuspensionCompression:") func setSuspensionCompression(_ value: CGFloat) { wheel.numbers["compression"] = Double(value) }
    @ObjCMethod("suspensionDamping") func suspensionDamping() -> CGFloat { number("damping", 2.3) }
    @ObjCMethod("setSuspensionDamping:") func setSuspensionDamping(_ value: CGFloat) { wheel.numbers["damping"] = Double(value) }
    @ObjCMethod("maximumSuspensionTravel") func maximumSuspensionTravel() -> CGFloat { number("travel", 500) }
    @ObjCMethod("setMaximumSuspensionTravel:") func setMaximumSuspensionTravel(_ value: CGFloat) { wheel.numbers["travel"] = Double(value) }
    @ObjCMethod("frictionSlip") func frictionSlip() -> CGFloat { number("slip", 1) }
    @ObjCMethod("setFrictionSlip:") func setFrictionSlip(_ value: CGFloat) { wheel.numbers["slip"] = Double(value) }
    @ObjCMethod("maximumSuspensionForce") func maximumSuspensionForce() -> CGFloat { number("force", 6000) }
    @ObjCMethod("setMaximumSuspensionForce:") func setMaximumSuspensionForce(_ value: CGFloat) { wheel.numbers["force"] = Double(value) }
    @ObjCMethod("radius") func radius() -> CGFloat { number("radius", 0.5) }
    @ObjCMethod("setRadius:") func setRadius(_ value: CGFloat) { wheel.numbers["radius"] = Double(value) }
    @ObjCMethod("suspensionRestLength") func suspensionRestLength() -> CGFloat { number("rest", 1.6) }
    @ObjCMethod("setSuspensionRestLength:") func setSuspensionRestLength(_ value: CGFloat) { wheel.numbers["rest"] = Double(value) }
    @ObjCMethod("connectionPosition") func connectionPosition() -> SCNVector3 { wheel.vectors["connection"] ?? SCNVector3(x: 0, y: 0, z: 0) }
    @ObjCMethod("setConnectionPosition:") func setConnectionPosition(_ value: SCNVector3) { wheel.vectors["connection"] = value }
    @ObjCMethod("steeringAxis") func steeringAxis() -> SCNVector3 { wheel.vectors["steering"] ?? SCNVector3(x: 0, y: -1, z: 0) }
    @ObjCMethod("setSteeringAxis:") func setSteeringAxis(_ value: SCNVector3) { wheel.vectors["steering"] = value }
    @ObjCMethod("axle") func axle() -> SCNVector3 { wheel.vectors["axle"] ?? SCNVector3(x: -1, y: 0, z: 0) }
    @ObjCMethod("setAxle:") func setAxle(_ value: SCNVector3) { wheel.vectors["axle"] = value }
}

@ObjCClass("SCNPhysicsVehicle")
open class SCNPhysicsVehicle: SCNPhysicsBehavior {
    static let states = StateTable<SCNKeptState>()
    var vehicle: SCNKeptState { SCNPhysicsVehicle.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNPhysicsVehicle.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNPhysicsVehicle.objCClass.pointer)
    }

    @ObjCClassMethod("vehicleWithChassisBody:wheels:")
    static func vehicle(_ cls: ObjCClass, chassisBody: NSObject?, wheels: NSArray?) -> SCNPhysicsVehicle {
        let made = cls.object.allocated().unsafeCast(to: SCNPhysicsVehicle.self)
        made.vehicle.objects["chassis"] = chassisBody
        made.vehicle.lists["wheels"] = wheels?.elements ?? []
        return made
    }

    @ObjCMethod("chassisBody") func chassisBody() -> NSObject? { vehicle.objects["chassis"] }
    @ObjCMethod("wheels") func wheels() -> NSObject { NSMutableArray.of(vehicle.lists["wheels"] ?? []) }
    /// The vehicle does not drive.
    @ObjCMethod("speedInKilometersPerHour") func speedInKilometersPerHour() -> CGFloat { 0 }
    @ObjCMethod("applyEngineForce:forWheelAtIndex:") func applyEngineForce(_ force: CGFloat, forWheelAt index: Int) {}
    @ObjCMethod("setSteeringAngle:forWheelAtIndex:") func setSteeringAngle(_ angle: CGFloat, forWheelAt index: Int) {}
    @ObjCMethod("applyBrakingForce:forWheelAtIndex:") func applyBrakingForce(_ force: CGFloat, forWheelAt index: Int) {}
}

@ObjCCategory("SCNPhysicsWorldBehaviors")
extension SCNPhysicsWorld {
    @ObjCMethod("addBehavior:") func addBehavior(_ behavior: NSObject?) {
        if let behavior { SCNKept.worlds[objcObject].lists["behaviors", default: []].append(behavior) }
    }
    @ObjCMethod("removeBehavior:") func removeBehavior(_ behavior: NSObject?) {
        SCNKept.worlds[objcObject].lists["behaviors"]?.removeAll { $0.objcObject == behavior?.objcObject }
    }
    @ObjCMethod("removeAllBehaviors") func removeAllBehaviors() { SCNKept.worlds[objcObject].lists["behaviors"] = [] }
    @ObjCMethod("allBehaviors") func allBehaviors() -> NSObject { NSMutableArray.of(SCNKept.worlds[objcObject].lists["behaviors"] ?? []) }
}

// MARK: - Levels of detail

@ObjCClass("SCNLevelOfDetail")
open class SCNLevelOfDetail: NSObject {
    static let states = StateTable<SCNKeptState>()
    var level: SCNKeptState { SCNLevelOfDetail.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNLevelOfDetail.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNLevelOfDetail.objCClass.pointer)
    }

    @ObjCClassMethod("levelOfDetailWithGeometry:screenSpaceRadius:")
    static func level(_ cls: ObjCClass, geometry: NSObject?, screenSpaceRadius: CGFloat) -> SCNLevelOfDetail {
        let made = cls.object.allocated().unsafeCast(to: SCNLevelOfDetail.self)
        made.level.objects["geometry"] = geometry
        made.level.numbers["radius"] = Double(screenSpaceRadius)
        return made
    }

    @ObjCClassMethod("levelOfDetailWithGeometry:worldSpaceDistance:")
    static func level(_ cls: ObjCClass, geometry: NSObject?, worldSpaceDistance: CGFloat) -> SCNLevelOfDetail {
        let made = cls.object.allocated().unsafeCast(to: SCNLevelOfDetail.self)
        made.level.objects["geometry"] = geometry
        made.level.numbers["distance"] = Double(worldSpaceDistance)
        return made
    }

    @ObjCMethod("geometry") func geometry() -> NSObject? { level.objects["geometry"] }
    @ObjCMethod("screenSpaceRadius") func screenSpaceRadius() -> CGFloat { CGFloat(level.numbers["radius"] ?? 0) }
    @ObjCMethod("worldSpaceDistance") func worldSpaceDistance() -> CGFloat { CGFloat(level.numbers["distance"] ?? 0) }
}

@ObjCCategory("SCNGeometryLevelsOfDetail")
extension SCNGeometry {
    @ObjCMethod("levelsOfDetail") func levelsOfDetail() -> NSObject? { SCNKept.geometries[objcObject].lists["levels"].map { NSMutableArray.of($0) } }
    @ObjCMethod("setLevelsOfDetail:") func setLevelsOfDetail(_ levels: NSArray?) { SCNKept.geometries[objcObject].lists["levels"] = levels?.elements }
}

// MARK: - A rotation gesture

/// Two fingers turning: there is one pointer here, so it never begins.
@ObjCClass("UIRotationGestureRecognizer")
open class UIRotationGestureRecognizer: UIGestureRecognizer {
    @ObjCMethod("rotation") func rotation() -> CGFloat { 0 }
    @ObjCMethod("setRotation:") func setRotation(_ rotation: CGFloat) {}
    @ObjCMethod("velocity") func velocity() -> CGFloat { 0 }
}

@ObjCCategory("UIPanGestureRecognizerScrollTypes")
extension UIPanGestureRecognizer {
    @ObjCMethod("allowedScrollTypesMask") func allowedScrollTypesMask() -> Int { 0 }
    @ObjCMethod("setAllowedScrollTypesMask:") func setAllowedScrollTypesMask(_ mask: Int) {}
}
