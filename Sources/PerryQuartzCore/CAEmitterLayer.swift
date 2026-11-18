import CPerryGeometry
import PerryObjCInterop

// CAEmitterLayer and CAEmitterCell: a particle system. No particles are
// drawn; the layer and its cells keep what they are given, so an app that
// sets one up (confetti, a pulsing dot) runs, and shows the rest.

final class EmitterLayerState {
    var cells: NSObject?
    var birthRate: Float = 1
    var lifetime: Float = 1
    var position = CGPoint(x: 0, y: 0)
    var zPosition: CGFloat = 0
    var size = CGSize(width: 0, height: 0)
    var depth: CGFloat = 0
    var shape = "point"
    var mode = "volume"
    var renderMode = "unordered"
    var preservesDepth = false
    var velocity: Float = 1
    var scale: Float = 1
    var spin: Float = 1
    var seed: UInt32 = 0
}

@ObjCClass("CAEmitterLayer")
open class CAEmitterLayer: CALayer {
    var emitter = EmitterLayerState()

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithLayer:")
    public required init(layer: CALayer) { super.init(layer: layer) }

    @ObjCMethod("emitterCells") func emitterCells() -> NSObject? { emitter.cells }
    @ObjCMethod("setEmitterCells:") func setEmitterCells(_ cells: NSObject?) { emitter.cells = cells }
    @ObjCMethod("birthRate") func birthRate() -> Float { emitter.birthRate }
    @ObjCMethod("setBirthRate:") func setBirthRate(_ rate: Float) { emitter.birthRate = rate }
    @ObjCMethod("lifetime") func lifetime() -> Float { emitter.lifetime }
    @ObjCMethod("setLifetime:") func setLifetime(_ lifetime: Float) { emitter.lifetime = lifetime }
    @ObjCMethod("emitterPosition") func emitterPosition() -> CGPoint { emitter.position }
    @ObjCMethod("setEmitterPosition:") func setEmitterPosition(_ position: CGPoint) { emitter.position = position }
    @ObjCMethod("emitterZPosition") func emitterZPosition() -> CGFloat { emitter.zPosition }
    @ObjCMethod("setEmitterZPosition:") func setEmitterZPosition(_ position: CGFloat) { emitter.zPosition = position }
    @ObjCMethod("emitterSize") func emitterSize() -> CGSize { emitter.size }
    @ObjCMethod("setEmitterSize:") func setEmitterSize(_ size: CGSize) { emitter.size = size }
    @ObjCMethod("emitterDepth") func emitterDepth() -> CGFloat { emitter.depth }
    @ObjCMethod("setEmitterDepth:") func setEmitterDepth(_ depth: CGFloat) { emitter.depth = depth }
    @ObjCMethod("emitterShape") func emitterShape() -> String { emitter.shape }
    @ObjCMethod("setEmitterShape:") func setEmitterShape(_ shape: String) { emitter.shape = shape }
    @ObjCMethod("emitterMode") func emitterMode() -> String { emitter.mode }
    @ObjCMethod("setEmitterMode:") func setEmitterMode(_ mode: String) { emitter.mode = mode }
    @ObjCMethod("renderMode") func renderMode() -> String { emitter.renderMode }
    @ObjCMethod("setRenderMode:") func setRenderMode(_ mode: String) { emitter.renderMode = mode }
    @ObjCMethod("preservesDepth") func preservesDepth() -> Bool { emitter.preservesDepth }
    @ObjCMethod("setPreservesDepth:") func setPreservesDepth(_ preserves: Bool) { emitter.preservesDepth = preserves }
    @ObjCMethod("velocity") func velocity() -> Float { emitter.velocity }
    @ObjCMethod("setVelocity:") func setVelocity(_ velocity: Float) { emitter.velocity = velocity }
    @ObjCMethod("scale") func scale() -> Float { emitter.scale }
    @ObjCMethod("setScale:") func setScale(_ scale: Float) { emitter.scale = scale }
    @ObjCMethod("spin") func spin() -> Float { emitter.spin }
    @ObjCMethod("setSpin:") func setSpin(_ spin: Float) { emitter.spin = spin }
    @ObjCMethod("seed") func seed() -> UInt32 { emitter.seed }
    @ObjCMethod("setSeed:") func setSeed(_ seed: UInt32) { emitter.seed = seed }
}

/// A source of particles: its values are kept by key, as Core Animation's
/// own cell keeps many more than are worth a property each.
@ObjCClass("CAEmitterCell")
open class CAEmitterCell: NSObject {
    var cellName: String?
    var enabled = true
    var contents: NSObject?
    var color: UnsafeMutableRawPointer?
    var cells: NSObject?
    var numbers: [String: Double] = [:]

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { if let color { ObjCRuntime.release(color) } }

    @ObjCClassMethod("emitterCell")
    static func emitterCell(_ cls: ObjCClass) -> NSObject { NSObject(cls.pointer).newInstance() }

    @ObjCMethod("name") func name() -> String? { cellName }
    @ObjCMethod("setName:") func setName(_ name: String?) { cellName = name }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    @ObjCMethod("contents") func cellContents() -> NSObject? { contents }
    @ObjCMethod("setContents:") func setCellContents(_ contents: NSObject?) { self.contents = contents }
    @ObjCMethod("emitterCells") func emitterCells() -> NSObject? { cells }
    @ObjCMethod("setEmitterCells:") func setEmitterCells(_ cells: NSObject?) { self.cells = cells }
    @ObjCMethod("color") func cellColor() -> UnsafeMutableRawPointer? { color }
    @ObjCMethod("setColor:")
    func setCellColor(_ color: UnsafeMutableRawPointer?) {
        let old = self.color
        self.color = color.flatMap { ObjCRuntime.retain($0) }
        if let old { ObjCRuntime.release(old) }
    }

    @ObjCMethod("birthRate") func birthRate() -> Float { Float(numbers["birthRate"] ?? 0) }
    @ObjCMethod("setBirthRate:") func setBirthRate(_ value: Float) { numbers["birthRate"] = Double(value) }
    @ObjCMethod("lifetime") func lifetime() -> Float { Float(numbers["lifetime"] ?? 0) }
    @ObjCMethod("setLifetime:") func setLifetime(_ value: Float) { numbers["lifetime"] = Double(value) }
    @ObjCMethod("lifetimeRange") func lifetimeRange() -> Float { Float(numbers["lifetimeRange"] ?? 0) }
    @ObjCMethod("setLifetimeRange:") func setLifetimeRange(_ value: Float) { numbers["lifetimeRange"] = Double(value) }
    @ObjCMethod("velocity") func velocity() -> CGFloat { CGFloat(numbers["velocity"] ?? 0) }
    @ObjCMethod("setVelocity:") func setVelocity(_ value: CGFloat) { numbers["velocity"] = Double(value) }
    @ObjCMethod("velocityRange") func velocityRange() -> CGFloat { CGFloat(numbers["velocityRange"] ?? 0) }
    @ObjCMethod("setVelocityRange:") func setVelocityRange(_ value: CGFloat) { numbers["velocityRange"] = Double(value) }
    @ObjCMethod("emissionLongitude") func emissionLongitude() -> CGFloat { CGFloat(numbers["emissionLongitude"] ?? 0) }
    @ObjCMethod("setEmissionLongitude:") func setEmissionLongitude(_ value: CGFloat) { numbers["emissionLongitude"] = Double(value) }
    @ObjCMethod("emissionLatitude") func emissionLatitude() -> CGFloat { CGFloat(numbers["emissionLatitude"] ?? 0) }
    @ObjCMethod("setEmissionLatitude:") func setEmissionLatitude(_ value: CGFloat) { numbers["emissionLatitude"] = Double(value) }
    @ObjCMethod("emissionRange") func emissionRange() -> CGFloat { CGFloat(numbers["emissionRange"] ?? 0) }
    @ObjCMethod("setEmissionRange:") func setEmissionRange(_ value: CGFloat) { numbers["emissionRange"] = Double(value) }
    @ObjCMethod("xAcceleration") func xAcceleration() -> CGFloat { CGFloat(numbers["xAcceleration"] ?? 0) }
    @ObjCMethod("setXAcceleration:") func setXAcceleration(_ value: CGFloat) { numbers["xAcceleration"] = Double(value) }
    @ObjCMethod("yAcceleration") func yAcceleration() -> CGFloat { CGFloat(numbers["yAcceleration"] ?? 0) }
    @ObjCMethod("setYAcceleration:") func setYAcceleration(_ value: CGFloat) { numbers["yAcceleration"] = Double(value) }
    @ObjCMethod("zAcceleration") func zAcceleration() -> CGFloat { CGFloat(numbers["zAcceleration"] ?? 0) }
    @ObjCMethod("setZAcceleration:") func setZAcceleration(_ value: CGFloat) { numbers["zAcceleration"] = Double(value) }
    @ObjCMethod("scale") func scale() -> CGFloat { CGFloat(numbers["scale"] ?? 1) }
    @ObjCMethod("setScale:") func setScale(_ value: CGFloat) { numbers["scale"] = Double(value) }
    @ObjCMethod("scaleRange") func scaleRange() -> CGFloat { CGFloat(numbers["scaleRange"] ?? 0) }
    @ObjCMethod("setScaleRange:") func setScaleRange(_ value: CGFloat) { numbers["scaleRange"] = Double(value) }
    @ObjCMethod("scaleSpeed") func scaleSpeed() -> CGFloat { CGFloat(numbers["scaleSpeed"] ?? 0) }
    @ObjCMethod("setScaleSpeed:") func setScaleSpeed(_ value: CGFloat) { numbers["scaleSpeed"] = Double(value) }
    @ObjCMethod("spin") func spin() -> CGFloat { CGFloat(numbers["spin"] ?? 0) }
    @ObjCMethod("setSpin:") func setSpin(_ value: CGFloat) { numbers["spin"] = Double(value) }
    @ObjCMethod("spinRange") func spinRange() -> CGFloat { CGFloat(numbers["spinRange"] ?? 0) }
    @ObjCMethod("setSpinRange:") func setSpinRange(_ value: CGFloat) { numbers["spinRange"] = Double(value) }
    @ObjCMethod("alphaRange") func alphaRange() -> Float { Float(numbers["alphaRange"] ?? 0) }
    @ObjCMethod("setAlphaRange:") func setAlphaRange(_ value: Float) { numbers["alphaRange"] = Double(value) }
    @ObjCMethod("alphaSpeed") func alphaSpeed() -> Float { Float(numbers["alphaSpeed"] ?? 0) }
    @ObjCMethod("setAlphaSpeed:") func setAlphaSpeed(_ value: Float) { numbers["alphaSpeed"] = Double(value) }
    @ObjCMethod("contentsScale") func contentsScale() -> CGFloat { CGFloat(numbers["contentsScale"] ?? 1) }
    @ObjCMethod("setContentsScale:") func setContentsScale(_ value: CGFloat) { numbers["contentsScale"] = Double(value) }
}
