import CPerryGeometry
import Glibc
import PerryObjCInterop

// The properties of SceneKit's particle systems that nothing emits with:
// kept as given, so a system an app sets up reads back what it was set to.
// (Generated from SceneKit's particle system header.)

extension SCNParticleSystemState {
    func number(_ key: String, _ fallback: Double = 0) -> Double { values[key] ?? fallback }
}

@ObjCCategory("SCNParticleSystemSettings")
extension SCNParticleSystem {
    @ObjCMethod("emissionDurationVariation") func emissionDurationVariationValue() -> CGFloat { CGFloat(system.number("emissionDurationVariation")) }
    @ObjCMethod("setEmissionDurationVariation:") func setEmissionDurationVariation(_ value: CGFloat) { system.values["emissionDurationVariation"] = Double(value) }
    @ObjCMethod("idleDuration") func idleDurationValue() -> CGFloat { CGFloat(system.number("idleDuration")) }
    @ObjCMethod("setIdleDuration:") func setIdleDuration(_ value: CGFloat) { system.values["idleDuration"] = Double(value) }
    @ObjCMethod("idleDurationVariation") func idleDurationVariationValue() -> CGFloat { CGFloat(system.number("idleDurationVariation")) }
    @ObjCMethod("setIdleDurationVariation:") func setIdleDurationVariation(_ value: CGFloat) { system.values["idleDurationVariation"] = Double(value) }
    @ObjCMethod("warmupDuration") func warmupDurationValue() -> CGFloat { CGFloat(system.number("warmupDuration")) }
    @ObjCMethod("setWarmupDuration:") func setWarmupDuration(_ value: CGFloat) { system.values["warmupDuration"] = Double(value) }
    @ObjCMethod("particleLifeSpan") func particleLifeSpanValue() -> CGFloat { CGFloat(system.number("particleLifeSpan")) }
    @ObjCMethod("setParticleLifeSpan:") func setParticleLifeSpan(_ value: CGFloat) { system.values["particleLifeSpan"] = Double(value) }
    @ObjCMethod("particleLifeSpanVariation") func particleLifeSpanVariationValue() -> CGFloat { CGFloat(system.number("particleLifeSpanVariation")) }
    @ObjCMethod("setParticleLifeSpanVariation:") func setParticleLifeSpanVariation(_ value: CGFloat) { system.values["particleLifeSpanVariation"] = Double(value) }
    @ObjCMethod("particleVelocity") func particleVelocityValue() -> CGFloat { CGFloat(system.number("particleVelocity")) }
    @ObjCMethod("setParticleVelocity:") func setParticleVelocity(_ value: CGFloat) { system.values["particleVelocity"] = Double(value) }
    @ObjCMethod("particleVelocityVariation") func particleVelocityVariationValue() -> CGFloat { CGFloat(system.number("particleVelocityVariation")) }
    @ObjCMethod("setParticleVelocityVariation:") func setParticleVelocityVariation(_ value: CGFloat) { system.values["particleVelocityVariation"] = Double(value) }
    @ObjCMethod("particleAngle") func particleAngleValue() -> CGFloat { CGFloat(system.number("particleAngle")) }
    @ObjCMethod("setParticleAngle:") func setParticleAngle(_ value: CGFloat) { system.values["particleAngle"] = Double(value) }
    @ObjCMethod("particleAngleVariation") func particleAngleVariationValue() -> CGFloat { CGFloat(system.number("particleAngleVariation")) }
    @ObjCMethod("setParticleAngleVariation:") func setParticleAngleVariation(_ value: CGFloat) { system.values["particleAngleVariation"] = Double(value) }
    @ObjCMethod("particleSize") func particleSizeValue() -> CGFloat { CGFloat(system.number("particleSize")) }
    @ObjCMethod("setParticleSize:") func setParticleSize(_ value: CGFloat) { system.values["particleSize"] = Double(value) }
    @ObjCMethod("particleSizeVariation") func particleSizeVariationValue() -> CGFloat { CGFloat(system.number("particleSizeVariation")) }
    @ObjCMethod("setParticleSizeVariation:") func setParticleSizeVariation(_ value: CGFloat) { system.values["particleSizeVariation"] = Double(value) }
    @ObjCMethod("particleMass") func particleMassValue() -> CGFloat { CGFloat(system.number("particleMass")) }
    @ObjCMethod("setParticleMass:") func setParticleMass(_ value: CGFloat) { system.values["particleMass"] = Double(value) }
    @ObjCMethod("particleMassVariation") func particleMassVariationValue() -> CGFloat { CGFloat(system.number("particleMassVariation")) }
    @ObjCMethod("setParticleMassVariation:") func setParticleMassVariation(_ value: CGFloat) { system.values["particleMassVariation"] = Double(value) }
    @ObjCMethod("particleIntensity") func particleIntensityValue() -> CGFloat { CGFloat(system.number("particleIntensity")) }
    @ObjCMethod("setParticleIntensity:") func setParticleIntensity(_ value: CGFloat) { system.values["particleIntensity"] = Double(value) }
    @ObjCMethod("particleIntensityVariation") func particleIntensityVariationValue() -> CGFloat { CGFloat(system.number("particleIntensityVariation")) }
    @ObjCMethod("setParticleIntensityVariation:") func setParticleIntensityVariation(_ value: CGFloat) { system.values["particleIntensityVariation"] = Double(value) }
    @ObjCMethod("dragFactor") func dragFactorValue() -> CGFloat { CGFloat(system.number("dragFactor")) }
    @ObjCMethod("setDragFactor:") func setDragFactor(_ value: CGFloat) { system.values["dragFactor"] = Double(value) }
    @ObjCMethod("spreadingAngle") func spreadingAngleValue() -> CGFloat { CGFloat(system.number("spreadingAngle")) }
    @ObjCMethod("setSpreadingAngle:") func setSpreadingAngle(_ value: CGFloat) { system.values["spreadingAngle"] = Double(value) }
    @ObjCMethod("speedFactor") func speedFactorValue() -> CGFloat { CGFloat(system.number("speedFactor")) }
    @ObjCMethod("setSpeedFactor:") func setSpeedFactor(_ value: CGFloat) { system.values["speedFactor"] = Double(value) }
    @ObjCMethod("stretchFactor") func stretchFactorValue() -> CGFloat { CGFloat(system.number("stretchFactor")) }
    @ObjCMethod("setStretchFactor:") func setStretchFactor(_ value: CGFloat) { system.values["stretchFactor"] = Double(value) }
    @ObjCMethod("fresnelExponent") func fresnelExponentValue() -> CGFloat { CGFloat(system.number("fresnelExponent")) }
    @ObjCMethod("setFresnelExponent:") func setFresnelExponent(_ value: CGFloat) { system.values["fresnelExponent"] = Double(value) }
    @ObjCMethod("emittingDirectionVariation") func emittingDirectionVariationValue() -> CGFloat { CGFloat(system.number("emittingDirectionVariation")) }
    @ObjCMethod("setEmittingDirectionVariation:") func setEmittingDirectionVariation(_ value: CGFloat) { system.values["emittingDirectionVariation"] = Double(value) }
    @ObjCMethod("particleBounce") func particleBounceValue() -> CGFloat { CGFloat(system.number("particleBounce")) }
    @ObjCMethod("setParticleBounce:") func setParticleBounce(_ value: CGFloat) { system.values["particleBounce"] = Double(value) }
    @ObjCMethod("particleBounceVariation") func particleBounceVariationValue() -> CGFloat { CGFloat(system.number("particleBounceVariation")) }
    @ObjCMethod("setParticleBounceVariation:") func setParticleBounceVariation(_ value: CGFloat) { system.values["particleBounceVariation"] = Double(value) }
    @ObjCMethod("particleFriction") func particleFrictionValue() -> CGFloat { CGFloat(system.number("particleFriction")) }
    @ObjCMethod("setParticleFriction:") func setParticleFriction(_ value: CGFloat) { system.values["particleFriction"] = Double(value) }
    @ObjCMethod("particleFrictionVariation") func particleFrictionVariationValue() -> CGFloat { CGFloat(system.number("particleFrictionVariation")) }
    @ObjCMethod("setParticleFrictionVariation:") func setParticleFrictionVariation(_ value: CGFloat) { system.values["particleFrictionVariation"] = Double(value) }
    @ObjCMethod("particleCharge") func particleChargeValue() -> CGFloat { CGFloat(system.number("particleCharge")) }
    @ObjCMethod("setParticleCharge:") func setParticleCharge(_ value: CGFloat) { system.values["particleCharge"] = Double(value) }
    @ObjCMethod("particleChargeVariation") func particleChargeVariationValue() -> CGFloat { CGFloat(system.number("particleChargeVariation")) }
    @ObjCMethod("setParticleChargeVariation:") func setParticleChargeVariation(_ value: CGFloat) { system.values["particleChargeVariation"] = Double(value) }
    @ObjCMethod("imageSequenceFrameRate") func imageSequenceFrameRateValue() -> CGFloat { CGFloat(system.number("imageSequenceFrameRate")) }
    @ObjCMethod("setImageSequenceFrameRate:") func setImageSequenceFrameRate(_ value: CGFloat) { system.values["imageSequenceFrameRate"] = Double(value) }
    @ObjCMethod("imageSequenceFrameRateVariation") func imageSequenceFrameRateVariationValue() -> CGFloat { CGFloat(system.number("imageSequenceFrameRateVariation")) }
    @ObjCMethod("setImageSequenceFrameRateVariation:") func setImageSequenceFrameRateVariation(_ value: CGFloat) { system.values["imageSequenceFrameRateVariation"] = Double(value) }
    @ObjCMethod("imageSequenceInitialFrame") func imageSequenceInitialFrameValue() -> CGFloat { CGFloat(system.number("imageSequenceInitialFrame")) }
    @ObjCMethod("setImageSequenceInitialFrame:") func setImageSequenceInitialFrame(_ value: CGFloat) { system.values["imageSequenceInitialFrame"] = Double(value) }
    @ObjCMethod("imageSequenceInitialFrameVariation") func imageSequenceInitialFrameVariationValue() -> CGFloat { CGFloat(system.number("imageSequenceInitialFrameVariation")) }
    @ObjCMethod("setImageSequenceInitialFrameVariation:") func setImageSequenceInitialFrameVariation(_ value: CGFloat) { system.values["imageSequenceInitialFrameVariation"] = Double(value) }
    @ObjCMethod("birthRateVariation") func birthRateVariationValue() -> CGFloat { CGFloat(system.number("birthRateVariation")) }
    @ObjCMethod("setBirthRateVariation:") func setBirthRateVariation(_ value: CGFloat) { system.values["birthRateVariation"] = Double(value) }
    @ObjCMethod("blendMode") func blendModeMode() -> Int { Int(system.number("blendMode")) }
    @ObjCMethod("setBlendMode:") func setBlendMode(_ value: Int) { system.values["blendMode"] = Double(value) }
    @ObjCMethod("sortingMode") func sortingModeMode() -> Int { Int(system.number("sortingMode")) }
    @ObjCMethod("setSortingMode:") func setSortingMode(_ value: Int) { system.values["sortingMode"] = Double(value) }
    @ObjCMethod("orientationMode") func orientationModeMode() -> Int { Int(system.number("orientationMode")) }
    @ObjCMethod("setOrientationMode:") func setOrientationMode(_ value: Int) { system.values["orientationMode"] = Double(value) }
    @ObjCMethod("birthLocation") func birthLocationMode() -> Int { Int(system.number("birthLocation")) }
    @ObjCMethod("setBirthLocation:") func setBirthLocation(_ value: Int) { system.values["birthLocation"] = Double(value) }
    @ObjCMethod("birthDirection") func birthDirectionMode() -> Int { Int(system.number("birthDirection")) }
    @ObjCMethod("setBirthDirection:") func setBirthDirection(_ value: Int) { system.values["birthDirection"] = Double(value) }
    @ObjCMethod("particleDiesOnCollision") func particleDiesOnCollisionMode() -> Int { Int(system.number("particleDiesOnCollision")) }
    @ObjCMethod("setParticleDiesOnCollision:") func setParticleDiesOnCollision(_ value: Int) { system.values["particleDiesOnCollision"] = Double(value) }
    @ObjCMethod("imageSequenceRowCount") func imageSequenceRowCountMode() -> Int { Int(system.number("imageSequenceRowCount")) }
    @ObjCMethod("setImageSequenceRowCount:") func setImageSequenceRowCount(_ value: Int) { system.values["imageSequenceRowCount"] = Double(value) }
    @ObjCMethod("imageSequenceColumnCount") func imageSequenceColumnCountMode() -> Int { Int(system.number("imageSequenceColumnCount")) }
    @ObjCMethod("setImageSequenceColumnCount:") func setImageSequenceColumnCount(_ value: Int) { system.values["imageSequenceColumnCount"] = Double(value) }
    @ObjCMethod("emitterShapeSurface") func emitterShapeSurfaceMode() -> Int { Int(system.number("emitterShapeSurface")) }
    @ObjCMethod("setEmitterShapeSurface:") func setEmitterShapeSurface(_ value: Int) { system.values["emitterShapeSurface"] = Double(value) }
    @ObjCMethod("isLocal") func isLocalFlag() -> Bool { system.number("local") != 0 }
    @ObjCMethod("setLocal:") func setLocalFlag(_ value: Bool) { system.values["local"] = value ? 1 : 0 }
    @ObjCMethod("isLightingEnabled") func isLightingEnabledFlag() -> Bool { system.number("lightingEnabled") != 0 }
    @ObjCMethod("setLightingEnabled:") func setLightingEnabledFlag(_ value: Bool) { system.values["lightingEnabled"] = value ? 1 : 0 }
    @ObjCMethod("isAffectedByGravity") func isAffectedByGravityFlag() -> Bool { system.number("affectedByGravity") != 0 }
    @ObjCMethod("setAffectedByGravity:") func setAffectedByGravityFlag(_ value: Bool) { system.values["affectedByGravity"] = value ? 1 : 0 }
    @ObjCMethod("isAffectedByPhysicsFields") func isAffectedByPhysicsFieldsFlag() -> Bool { system.number("affectedByPhysicsFields") != 0 }
    @ObjCMethod("setAffectedByPhysicsFields:") func setAffectedByPhysicsFieldsFlag(_ value: Bool) { system.values["affectedByPhysicsFields"] = value ? 1 : 0 }
    @ObjCMethod("isBlackPassEnabled") func isBlackPassEnabledFlag() -> Bool { system.number("blackPassEnabled") != 0 }
    @ObjCMethod("setBlackPassEnabled:") func setBlackPassEnabledFlag(_ value: Bool) { system.values["blackPassEnabled"] = value ? 1 : 0 }
    @ObjCMethod("isLooping") func isLoopingFlag() -> Bool { system.number("looping") != 0 }
    @ObjCMethod("setLooping:") func setLoopingFlag(_ value: Bool) { system.values["looping"] = value ? 1 : 0 }
    @ObjCMethod("isSoftParticleEnabled") func isSoftParticleEnabledFlag() -> Bool { system.number("softParticleEnabled") != 0 }
    @ObjCMethod("setSoftParticleEnabled:") func setSoftParticleEnabledFlag(_ value: Bool) { system.values["softParticleEnabled"] = value ? 1 : 0 }
    @ObjCMethod("acceleration") func accelerationVector() -> SCNVector3 { let v = system.vectors["acceleration"] ?? [0, 0, 0]; return SCNVector3(x: v[0], y: v[1], z: v[2]) }
    @ObjCMethod("setAcceleration:") func setAcceleration(_ value: SCNVector3) { system.vectors["acceleration"] = [value.x, value.y, value.z] }
    @ObjCMethod("emittingDirection") func emittingDirectionVector() -> SCNVector3 { let v = system.vectors["emittingDirection"] ?? [0, 0, 0]; return SCNVector3(x: v[0], y: v[1], z: v[2]) }
    @ObjCMethod("setEmittingDirection:") func setEmittingDirection(_ value: SCNVector3) { system.vectors["emittingDirection"] = [value.x, value.y, value.z] }
    @ObjCMethod("orientationDirection") func orientationDirectionVector() -> SCNVector3 { let v = system.vectors["orientationDirection"] ?? [0, 0, 0]; return SCNVector3(x: v[0], y: v[1], z: v[2]) }
    @ObjCMethod("setOrientationDirection:") func setOrientationDirection(_ value: SCNVector3) { system.vectors["orientationDirection"] = [value.x, value.y, value.z] }
    @ObjCMethod("particleColor") func particleColorVector() -> SCNVector4 { let v = system.vectors["particleColor"] ?? [1, 1, 1, 1]; return SCNVector4(x: v[0], y: v[1], z: v[2], w: v[3]) }
    @ObjCMethod("setParticleColor:") func setParticleColor(_ value: SCNVector4) { system.vectors["particleColor"] = [value.x, value.y, value.z, value.w] }
    @ObjCMethod("particleColorVariation") func particleColorVariationVector() -> SCNVector4 { let v = system.vectors["particleColorVariation"] ?? [1, 1, 1, 1]; return SCNVector4(x: v[0], y: v[1], z: v[2], w: v[3]) }
    @ObjCMethod("setParticleColorVariation:") func setParticleColorVariation(_ value: SCNVector4) { system.vectors["particleColorVariation"] = [value.x, value.y, value.z, value.w] }
    @ObjCMethod("particleImage") func particleImageObject() -> NSObject? { system.objects["particleImage"] }
    @ObjCMethod("setParticleImage:") func setParticleImage(_ value: NSObject?) { system.objects["particleImage"] = value }
    @ObjCMethod("emitterShape") func emitterShapeObject() -> NSObject? { system.objects["emitterShape"] }
    @ObjCMethod("setEmitterShape:") func setEmitterShape(_ value: NSObject?) { system.objects["emitterShape"] = value }
    @ObjCMethod("colliderNodes") func colliderNodesObject() -> NSObject? { system.objects["colliderNodes"] }
    @ObjCMethod("setColliderNodes:") func setColliderNodes(_ value: NSObject?) { system.objects["colliderNodes"] = value }
    @ObjCMethod("propertyControllers") func propertyControllersObject() -> NSObject? { system.objects["propertyControllers"] }
    @ObjCMethod("setPropertyControllers:") func setPropertyControllers(_ value: NSObject?) { system.objects["propertyControllers"] = value }
    @ObjCMethod("systemSpawnedOnCollision") func systemSpawnedOnCollisionObject() -> NSObject? { system.objects["systemSpawnedOnCollision"] }
    @ObjCMethod("setSystemSpawnedOnCollision:") func setSystemSpawnedOnCollision(_ value: NSObject?) { system.objects["systemSpawnedOnCollision"] = value }
    @ObjCMethod("systemSpawnedOnDying") func systemSpawnedOnDyingObject() -> NSObject? { system.objects["systemSpawnedOnDying"] }
    @ObjCMethod("setSystemSpawnedOnDying:") func setSystemSpawnedOnDying(_ value: NSObject?) { system.objects["systemSpawnedOnDying"] = value }
    @ObjCMethod("systemSpawnedOnLiving") func systemSpawnedOnLivingObject() -> NSObject? { system.objects["systemSpawnedOnLiving"] }
    @ObjCMethod("setSystemSpawnedOnLiving:") func setSystemSpawnedOnLiving(_ value: NSObject?) { system.objects["systemSpawnedOnLiving"] = value }
    @ObjCMethod("name") func nameObject() -> NSObject? { system.objects["name"] }
    @ObjCMethod("setName:") func setName(_ value: NSObject?) { system.objects["name"] = value }
}
