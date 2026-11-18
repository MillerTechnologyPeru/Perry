import CPerryGeometry
import Glibc
import PerryObjCInterop

// SpriteKit's other nodes. A camera node is where its scene is seen from
// (SKScene's sceneToView reads it). The rest are kept, for what an app sets
// to be what it reads back, and so that their children are drawn where they
// are: a crop node shows its children whole, with no mask; an emitter emits
// nothing; a shader's source is not compiled; a tile map has no tiles.
// Nodes are not read from .sks files: one made from a file's name is nil,
// but for an emitter, which is an empty one.

@ObjCClass("SKCameraNode")
open class SKCameraNode: SKNode {
    /// Whether the node is in the scene, as far as its frame is known: within what the camera shows.
    @ObjCMethod("containsNode:")
    func contains(node other: SKNode) -> Bool {
        guard let scene = scene() else { return false }
        let size = scene.node.sceneSize
        let center = toScene().apply(CGPoint(x: 0, y: 0))
        let shown = CGRect(x: center.x - size.width * abs(node.xScale) / 2, y: center.y - size.height * abs(node.yScale) / 2,
                           width: size.width * abs(node.xScale), height: size.height * abs(node.yScale))
        let frame = other.calculateAccumulatedFrame()
        let origin = other.parent().map { $0.toScene().apply(frame.origin) } ?? frame.origin
        let placed = CGRect(origin: origin, size: frame.size)
        return placed.maxX >= shown.minX && placed.minX <= shown.maxX && placed.maxY >= shown.minY && placed.minY <= shown.maxY
    }
}

@ObjCClass("SKCropNode")
open class SKCropNode: SKNode {
    @ObjCMethod("maskNode") func maskNode() -> SKNode? { node.maskNode }
    @ObjCMethod("setMaskNode:") func setMaskNode(_ mask: SKNode?) { node.maskNode = mask }
}

@ObjCClass("SKEffectNode")
open class SKEffectNode: SKNode {
    @ObjCMethod("shouldEnableEffects") func shouldEnableEffects() -> Bool { false }
    @ObjCMethod("setShouldEnableEffects:") func setShouldEnableEffects(_ enabled: Bool) {}
    @ObjCMethod("shouldRasterize") func shouldRasterize() -> Bool { false }
    @ObjCMethod("setShouldRasterize:") func setShouldRasterize(_ rasterize: Bool) {}
    @ObjCMethod("filter") func filter() -> NSObject? { nil }
    @ObjCMethod("setFilter:") func setFilter(_ filter: NSObject?) {}
}

// MARK: - Emitters

final class SKEmitterState: ObjectState {
    var numbers: [String: CGFloat] = [:]
    var texture: SKTexture?
    var color: UnsafeMutableRawPointer?
    var target: SKNode?
    deinit { ObjCRuntime.release(color) }
}

@ObjCClass("SKEmitterNode")
open class SKEmitterNode: SKNode {
    static let emitterStates = StateTable<SKEmitterState>()
    var emitter: SKEmitterState { SKEmitterNode.emitterStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        SKEmitterNode.emitterStates.remove(objcObject)
        super.dealloc()
    }

    private func number(_ key: String, _ fallback: CGFloat = 0) -> CGFloat { emitter.numbers[key] ?? fallback }

    @ObjCMethod("particleBirthRate") func particleBirthRate() -> CGFloat { number("birthRate") }
    @ObjCMethod("setParticleBirthRate:") func setParticleBirthRate(_ value: CGFloat) { emitter.numbers["birthRate"] = value }
    @ObjCMethod("particleLifetime") func particleLifetime() -> CGFloat { number("lifetime") }
    @ObjCMethod("setParticleLifetime:") func setParticleLifetime(_ value: CGFloat) { emitter.numbers["lifetime"] = value }
    @ObjCMethod("particleLifetimeRange") func particleLifetimeRange() -> CGFloat { number("lifetimeRange") }
    @ObjCMethod("setParticleLifetimeRange:") func setParticleLifetimeRange(_ value: CGFloat) { emitter.numbers["lifetimeRange"] = value }
    @ObjCMethod("particleScale") func particleScale() -> CGFloat { number("scale", 1) }
    @ObjCMethod("setParticleScale:") func setParticleScale(_ value: CGFloat) { emitter.numbers["scale"] = value }
    @ObjCMethod("particleScaleRange") func particleScaleRange() -> CGFloat { number("scaleRange") }
    @ObjCMethod("setParticleScaleRange:") func setParticleScaleRange(_ value: CGFloat) { emitter.numbers["scaleRange"] = value }
    @ObjCMethod("particleScaleSpeed") func particleScaleSpeed() -> CGFloat { number("scaleSpeed") }
    @ObjCMethod("setParticleScaleSpeed:") func setParticleScaleSpeed(_ value: CGFloat) { emitter.numbers["scaleSpeed"] = value }
    @ObjCMethod("particleSpeed") func particleSpeed() -> CGFloat { number("speed") }
    @ObjCMethod("setParticleSpeed:") func setParticleSpeed(_ value: CGFloat) { emitter.numbers["speed"] = value }
    @ObjCMethod("particleSpeedRange") func particleSpeedRange() -> CGFloat { number("speedRange") }
    @ObjCMethod("setParticleSpeedRange:") func setParticleSpeedRange(_ value: CGFloat) { emitter.numbers["speedRange"] = value }
    @ObjCMethod("particleAlpha") func particleAlpha() -> CGFloat { number("alpha", 1) }
    @ObjCMethod("setParticleAlpha:") func setParticleAlpha(_ value: CGFloat) { emitter.numbers["alpha"] = value }
    @ObjCMethod("particleAlphaSpeed") func particleAlphaSpeed() -> CGFloat { number("alphaSpeed") }
    @ObjCMethod("setParticleAlphaSpeed:") func setParticleAlphaSpeed(_ value: CGFloat) { emitter.numbers["alphaSpeed"] = value }
    @ObjCMethod("particleZPosition") func particleZPosition() -> CGFloat { number("zPosition") }
    @ObjCMethod("setParticleZPosition:") func setParticleZPosition(_ value: CGFloat) { emitter.numbers["zPosition"] = value }
    @ObjCMethod("emissionAngle") func emissionAngle() -> CGFloat { number("emissionAngle") }
    @ObjCMethod("setEmissionAngle:") func setEmissionAngle(_ value: CGFloat) { emitter.numbers["emissionAngle"] = value }
    @ObjCMethod("emissionAngleRange") func emissionAngleRange() -> CGFloat { number("emissionAngleRange") }
    @ObjCMethod("setEmissionAngleRange:") func setEmissionAngleRange(_ value: CGFloat) { emitter.numbers["emissionAngleRange"] = value }
    @ObjCMethod("particleColorBlendFactor") func particleColorBlendFactor() -> CGFloat { number("colorBlendFactor") }
    @ObjCMethod("setParticleColorBlendFactor:") func setParticleColorBlendFactor(_ value: CGFloat) { emitter.numbers["colorBlendFactor"] = value }
    @ObjCMethod("numParticlesToEmit") func numParticlesToEmit() -> Int { Int(number("count")) }
    @ObjCMethod("setNumParticlesToEmit:") func setNumParticlesToEmit(_ count: Int) { emitter.numbers["count"] = CGFloat(count) }
    @ObjCMethod("particleTexture") func particleTexture() -> SKTexture? { emitter.texture }
    @ObjCMethod("setParticleTexture:") func setParticleTexture(_ texture: SKTexture?) { emitter.texture = texture }
    @ObjCMethod("particleColor") func particleColor() -> NSObject? { emitter.color.map { NSObject($0) } }
    @ObjCMethod("setParticleColor:") func setParticleColor(_ color: NSObject?) { SKSupport.replace(&emitter.color, with: color?.objcObject) }
    @ObjCMethod("particleSize") func particleSize() -> CGSize { CGSize(width: number("width"), height: number("height")) }
    @ObjCMethod("setParticleSize:") func setParticleSize(_ size: CGSize) { emitter.numbers["width"] = size.width; emitter.numbers["height"] = size.height }
    @ObjCMethod("particlePositionRange") func particlePositionRange() -> CGPoint { CGPoint(x: number("rangeX"), y: number("rangeY")) }
    @ObjCMethod("setParticlePositionRange:") func setParticlePositionRange(_ range: CGPoint) { emitter.numbers["rangeX"] = range.x; emitter.numbers["rangeY"] = range.y }
    @ObjCMethod("particleBlendMode") func particleBlendMode() -> Int { Int(number("blendMode")) }
    @ObjCMethod("setParticleBlendMode:") func setParticleBlendMode(_ mode: Int) { emitter.numbers["blendMode"] = CGFloat(mode) }
    @ObjCMethod("targetNode") func targetNode() -> SKNode? { emitter.target }
    @ObjCMethod("setTargetNode:") func setTargetNode(_ target: SKNode?) { emitter.target = target }
    @ObjCMethod("resetSimulation") func resetSimulation() {}
    @ObjCMethod("advanceSimulationTime:") func advanceSimulationTime(_ time: Double) {}
}

@ObjCCategory("SKNodeFiles")
extension SKNode {
    /// A node from an .sks file. The files are not read: an emitter is an empty one, anything else is none.
    @ObjCClassMethod("nodeWithFileNamed:")
    static func node(_ cls: ObjCClass, fileNamed name: String) -> SKNode? {
        guard cls.pointer == SKEmitterNode.objCClass.pointer else { return nil }
        return cls.object.allocated().unsafeCast(to: SKNode.self)
    }

    @ObjCMethod("initWithFileNamed:")
    func initialize(fileNamed name: String) -> Self? { self.is(SKEmitterNode.self) ? self : nil }
}

// MARK: - Shaders

final class SKShaderState: ObjectState {
    var source: String?
    var uniforms: [NSObject] = []
}

@ObjCClass("SKShader")
open class SKShader: NSObject {
    static let states = StateTable<SKShaderState>()
    var shader: SKShaderState { SKShader.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKShader.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKShader.objCClass.pointer)
    }

    @ObjCClassMethod("shader") static func make(_ cls: ObjCClass) -> SKShader { cls.object.allocated().unsafeCast(to: SKShader.self) }

    @ObjCClassMethod("shaderWithSource:")
    static func shader(_ cls: ObjCClass, source: String?) -> SKShader {
        let made = make(cls)
        made.shader.source = source
        return made
    }

    @ObjCClassMethod("shaderWithSource:uniforms:")
    static func shader(_ cls: ObjCClass, source: String?, uniforms: NSArray?) -> SKShader {
        let made = shader(cls, source: source)
        made.shader.uniforms = uniforms?.elements ?? []
        return made
    }

    /// A shader named by its file in the main bundle, whose text is kept.
    @ObjCClassMethod("shaderWithFileNamed:")
    static func shader(_ cls: ObjCClass, fileNamed name: String) -> SKShader {
        let made = make(cls)
        if let base = NSBundle.main().resourcePath() {
            for path in ["\(base)/\(name)", "\(base)/\(name).fsh"] {
                if let bytes = SCNFile.read(path) { made.shader.source = String(decoding: bytes, as: UTF8.self); break }
            }
        }
        return made
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("initWithSource:") func initialize(source: String?) -> Self { shader.source = source; return self }
    @ObjCMethod("initWithSource:uniforms:") func initialize(source: String?, uniforms: NSArray?) -> Self {
        shader.source = source
        shader.uniforms = uniforms?.elements ?? []
        return self
    }
    @ObjCMethod("source") func source() -> String? { shader.source }
    @ObjCMethod("setSource:") func setSource(_ source: String?) { shader.source = source }
    @ObjCMethod("uniforms") func uniforms() -> NSObject { NSMutableArray.of(shader.uniforms) }
    @ObjCMethod("setUniforms:") func setUniforms(_ uniforms: NSArray?) { shader.uniforms = uniforms?.elements ?? [] }
    @ObjCMethod("addUniform:") func addUniform(_ uniform: NSObject) { shader.uniforms.append(uniform) }
    @ObjCMethod("uniformNamed:") func uniform(named name: String) -> NSObject? {
        shader.uniforms.first { SKUniform.states.existing($0.objcObject)?.name == name }
    }
    @ObjCMethod("removeUniformNamed:") func removeUniform(named name: String) {
        shader.uniforms.removeAll { SKUniform.states.existing($0.objcObject)?.name == name }
    }
}

final class SKUniformState: ObjectState {
    var name = ""
    var value: Float = 0
    var texture: SKTexture?
}

@ObjCClass("SKUniform")
open class SKUniform: NSObject {
    static let states = StateTable<SKUniformState>()
    var uniform: SKUniformState { SKUniform.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SKUniform.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SKUniform.objCClass.pointer)
    }

    @ObjCClassMethod("uniformWithName:")
    static func uniform(_ cls: ObjCClass, name: String) -> SKUniform {
        let made = cls.object.allocated().unsafeCast(to: SKUniform.self)
        made.uniform.name = name
        return made
    }

    @ObjCClassMethod("uniformWithName:float:")
    static func uniform(_ cls: ObjCClass, name: String, float value: Float) -> SKUniform {
        let made = uniform(cls, name: name)
        made.uniform.value = value
        return made
    }

    @ObjCClassMethod("uniformWithName:texture:")
    static func uniform(_ cls: ObjCClass, name: String, texture: SKTexture?) -> SKUniform {
        let made = uniform(cls, name: name)
        made.uniform.texture = texture
        return made
    }

    @ObjCMethod("initWithName:") func initialize(name: String) -> Self { uniform.name = name; return self }
    @ObjCMethod("initWithName:float:") func initialize(name: String, float value: Float) -> Self {
        uniform.name = name
        uniform.value = value
        return self
    }
    @ObjCMethod("initWithName:texture:") func initialize(name: String, texture: SKTexture?) -> Self {
        uniform.name = name
        uniform.texture = texture
        return self
    }
    @ObjCMethod("name") func name() -> String { uniform.name }
    @ObjCMethod("floatValue") func floatValue() -> Float { uniform.value }
    @ObjCMethod("setFloatValue:") func setFloatValue(_ value: Float) { uniform.value = value }
    @ObjCMethod("textureValue") func textureValue() -> SKTexture? { uniform.texture }
    @ObjCMethod("setTextureValue:") func setTextureValue(_ texture: SKTexture?) { uniform.texture = texture }
}

// MARK: - Tile maps

final class SKTileMapState: ObjectState {
    var columns = 0, rows = 0
    var tileSize = CGSize.zero
}

@ObjCClass("SKTileMapNode")
open class SKTileMapNode: SKNode {
    static let mapStates = StateTable<SKTileMapState>()
    var map: SKTileMapState { SKTileMapNode.mapStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        SKTileMapNode.mapStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("numberOfColumns") func numberOfColumns() -> Int { map.columns }
    @ObjCMethod("setNumberOfColumns:") func setNumberOfColumns(_ count: Int) { map.columns = count }
    @ObjCMethod("numberOfRows") func numberOfRows() -> Int { map.rows }
    @ObjCMethod("setNumberOfRows:") func setNumberOfRows(_ count: Int) { map.rows = count }
    @ObjCMethod("tileSize") func tileSize() -> CGSize { map.tileSize }
    @ObjCMethod("setTileSize:") func setTileSize(_ size: CGSize) { map.tileSize = size }
    @ObjCMethod("mapSize") func mapSize() -> CGSize {
        CGSize(width: CGFloat(map.columns) * map.tileSize.width, height: CGFloat(map.rows) * map.tileSize.height)
    }
    @ObjCMethod("tileDefinitionAtColumn:row:") func tileDefinition(atColumn column: Int, row: Int) -> NSObject? { nil }
    @ObjCMethod("tileGroupAtColumn:row:") func tileGroup(atColumn column: Int, row: Int) -> NSObject? { nil }
    @ObjCMethod("centerOfTileAtColumn:row:") func centerOfTile(atColumn column: Int, row: Int) -> CGPoint {
        let size = mapSize()
        return CGPoint(x: (CGFloat(column) + 0.5) * map.tileSize.width - size.width / 2, y: (CGFloat(row) + 0.5) * map.tileSize.height - size.height / 2)
    }
    @ObjCMethod("tileColumnIndexFromPosition:") func tileColumnIndex(fromPosition position: CGPoint) -> Int {
        map.tileSize.width > 0 ? Int(((position.x + mapSize().width / 2) / map.tileSize.width).rounded(.down)) : 0
    }
    @ObjCMethod("tileRowIndexFromPosition:") func tileRowIndex(fromPosition position: CGPoint) -> Int {
        map.tileSize.height > 0 ? Int(((position.y + mapSize().height / 2) / map.tileSize.height).rounded(.down)) : 0
    }
}
