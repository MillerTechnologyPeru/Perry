import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's scene graph. A scene's nodes are kept as nodes (a position,
// rotation and scale, and what they show: a geometry with its materials, or
// a camera); a view runs its frames — the delegate's steps — and then draws
// the scene itself with OpenGL ES (SceneKitRenderer.swift), showing the
// frame in its own layer. There are no lights, textures, animations,
// physics, hit tests or scene files yet: a view's default lighting lights
// the geometry, and a material with a constant lighting model is its colour.

// MARK: - Messages

extension NSObject {
    @ObjCMethod("path") func scnPath() -> String?

    // The delegate's, sent when it answers them.
    @ObjCMethod("renderer:updateAtTime:") func scnSendRenderer(_ renderer: NSObject, updateAtTime time: Double)
    @ObjCMethod("renderer:didApplyAnimationsAtTime:") func scnSendRenderer(_ renderer: NSObject, didApplyAnimationsAtTime time: Double)
    @ObjCMethod("renderer:didSimulatePhysicsAtTime:") func scnSendRenderer(_ renderer: NSObject, didSimulatePhysicsAtTime time: Double)
    @ObjCMethod("renderer:willRenderScene:atTime:")
    func scnSendRenderer(_ renderer: NSObject, willRenderScene scene: NSObject, atTime time: Double)
    @ObjCMethod("renderer:didRenderScene:atTime:")
    func scnSendRenderer(_ renderer: NSObject, didRenderScene scene: NSObject, atTime time: Double)
}

// MARK: - Material

final class SCNMaterialPropertyState: ObjectState {
    /// The contents, retained: a colour, a picture or a number.
    var contents: UnsafeMutableRawPointer?
    var intensity: CGFloat = 1
    /// SCNWrapMode: clamp 1, repeat 2, clamp to border 3, mirror 4.
    var wrapS = 1, wrapT = 1
    deinit { ObjCRuntime.release(contents) }
}

@ObjCClass("SCNMaterialProperty")
open class SCNMaterialProperty: NSObject {
    static let states = StateTable<SCNMaterialPropertyState>()
    var property: SCNMaterialPropertyState { SCNMaterialProperty.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNMaterialProperty.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNMaterialProperty.objCClass.pointer)
    }

    static func make(contents: UnsafeMutableRawPointer?) -> SCNMaterialProperty {
        let made = SCNMaterialProperty.objCClass.object.allocated().unsafeCast(to: SCNMaterialProperty.self)
        SKSupport.replace(&made.property.contents, with: contents)
        return made
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("contents") func contents() -> NSObject? { property.contents.map { NSObject($0) } }
    @ObjCMethod("setContents:") func setContents(_ contents: NSObject?) { SKSupport.replace(&property.contents, with: contents?.objcObject) }
    @ObjCMethod("intensity") func intensity() -> CGFloat { property.intensity }
    @ObjCMethod("setIntensity:") func setIntensity(_ intensity: CGFloat) { property.intensity = intensity }
    @ObjCMethod("wrapS") func wrapS() -> Int { property.wrapS }
    @ObjCMethod("setWrapS:") func setWrapS(_ mode: Int) { property.wrapS = mode }
    @ObjCMethod("wrapT") func wrapT() -> Int { property.wrapT }
    @ObjCMethod("setWrapT:") func setWrapT(_ mode: Int) { property.wrapT = mode }
}

// MARK: - Light

final class SCNLightState: ObjectState {
    /// The type as set: "omni", or SceneKit's constant's own text.
    var type = "omni"
    var color: UnsafeMutableRawPointer?
    var intensity: CGFloat = 1000
    var temperature: CGFloat = 6500
    var castsShadow = false
    var name: String?
    var attenuationStart: CGFloat = 0, attenuationEnd: CGFloat = 0, attenuationFalloff: CGFloat = 2
    var spotInner: CGFloat = 0, spotOuter: CGFloat = 45
    deinit { ObjCRuntime.release(color) }

    /// The type without the constants' prefix, in lower case.
    var kind: String {
        let lower = type.lowercased()
        return lower.hasPrefix("scnlighttype") ? String(lower.dropFirst(12)) : lower
    }
}

@ObjCClass("SCNLight")
open class SCNLight: NSObject {
    static let states = StateTable<SCNLightState>()
    var light: SCNLightState { SCNLight.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNLight.states.remove(objcObject)
        SCNExtras.lights.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNLight.objCClass.pointer)
    }

    @ObjCClassMethod("light") static func make(_ cls: ObjCClass) -> SCNLight { cls.object.allocated().unsafeCast(to: SCNLight.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("type") func type() -> String { light.type }
    @ObjCMethod("setType:") func setType(_ type: String) { light.type = type }
    @ObjCMethod("color") func color() -> NSObject? { light.color.map { NSObject($0) } ?? SKSupport.whiteObject.map { NSObject($0) } }
    @ObjCMethod("setColor:") func setColor(_ color: NSObject?) { SKSupport.replace(&light.color, with: color?.objcObject) }
    @ObjCMethod("intensity") func intensity() -> CGFloat { light.intensity }
    @ObjCMethod("setIntensity:") func setIntensity(_ intensity: CGFloat) { light.intensity = intensity }
    @ObjCMethod("temperature") func temperature() -> CGFloat { light.temperature }
    @ObjCMethod("setTemperature:") func setTemperature(_ temperature: CGFloat) { light.temperature = temperature }
    @ObjCMethod("castsShadow") func castsShadow() -> Bool { light.castsShadow }
    @ObjCMethod("setCastsShadow:") func setCastsShadow(_ casts: Bool) { light.castsShadow = casts }
    @ObjCMethod("name") func name() -> String? { light.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { light.name = name }
    @ObjCMethod("attenuationStartDistance") func attenuationStartDistance() -> CGFloat { light.attenuationStart }
    @ObjCMethod("setAttenuationStartDistance:") func setAttenuationStartDistance(_ distance: CGFloat) { light.attenuationStart = distance }
    @ObjCMethod("attenuationEndDistance") func attenuationEndDistance() -> CGFloat { light.attenuationEnd }
    @ObjCMethod("setAttenuationEndDistance:") func setAttenuationEndDistance(_ distance: CGFloat) { light.attenuationEnd = distance }
    @ObjCMethod("attenuationFalloffExponent") func attenuationFalloffExponent() -> CGFloat { light.attenuationFalloff }
    @ObjCMethod("setAttenuationFalloffExponent:") func setAttenuationFalloffExponent(_ exponent: CGFloat) { light.attenuationFalloff = exponent }
    @ObjCMethod("spotInnerAngle") func spotInnerAngle() -> CGFloat { light.spotInner }
    @ObjCMethod("setSpotInnerAngle:") func setSpotInnerAngle(_ angle: CGFloat) { light.spotInner = angle }
    @ObjCMethod("spotOuterAngle") func spotOuterAngle() -> CGFloat { light.spotOuter }
    @ObjCMethod("setSpotOuterAngle:") func setSpotOuterAngle(_ angle: CGFloat) { light.spotOuter = angle }
}

final class SCNMaterialState: ObjectState {
    var diffuse: SCNMaterialProperty?
    var emission: SCNMaterialProperty?
    var specular: SCNMaterialProperty?
    var transparency: CGFloat = 1
    var doubleSided = false
    /// SCNCullMode: back 0, front 1.
    var cullMode = 0
    var lightingModel: String? = "SCNLightingModelBlinn"
    var name: String?
}

@ObjCClass("SCNMaterial")
open class SCNMaterial: NSObject {
    static let states = StateTable<SCNMaterialState>()
    var material: SCNMaterialState { SCNMaterial.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNMaterial.states.remove(objcObject)
        SCNExtras.materials.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNMaterial.objCClass.pointer)
    }

    @ObjCClassMethod("material") static func make(_ cls: ObjCClass) -> SCNMaterial { cls.object.allocated().unsafeCast(to: SCNMaterial.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    /// The default diffuse colour is white; the others are black.
    private func property(_ slot: inout SCNMaterialProperty?, white: Bool) -> SCNMaterialProperty {
        if let slot { return slot }
        let made = SCNMaterialProperty.make(contents: white ? SKSupport.whiteObject : SKSupport.blackObject)
        slot = made
        return made
    }

    @ObjCMethod("diffuse") func diffuse() -> SCNMaterialProperty { property(&material.diffuse, white: true) }
    @ObjCMethod("emission") func emission() -> SCNMaterialProperty { property(&material.emission, white: false) }
    @ObjCMethod("specular") func specular() -> SCNMaterialProperty { property(&material.specular, white: false) }
    @ObjCMethod("transparency") func transparency() -> CGFloat { material.transparency }
    @ObjCMethod("setTransparency:") func setTransparency(_ transparency: CGFloat) { material.transparency = transparency }
    @ObjCMethod("isDoubleSided") func isDoubleSided() -> Bool { material.doubleSided }
    @ObjCMethod("setDoubleSided:") func setDoubleSided(_ doubleSided: Bool) { material.doubleSided = doubleSided }
    @ObjCMethod("cullMode") func cullMode() -> Int { material.cullMode }
    @ObjCMethod("setCullMode:") func setCullMode(_ mode: Int) { material.cullMode = mode }
    @ObjCMethod("lightingModelName") func lightingModelName() -> String? { material.lightingModel }
    @ObjCMethod("setLightingModelName:") func setLightingModelName(_ name: String?) { material.lightingModel = name }
    @ObjCMethod("name") func name() -> String? { material.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { material.name = name }
}

extension SKSupport {
    nonisolated(unsafe) static var whiteColorObject: UnsafeMutableRawPointer?
    nonisolated(unsafe) static var blackColorObject: UnsafeMutableRawPointer?

    /// A UIColor of white or black, kept for default material contents.
    static var whiteObject: UnsafeMutableRawPointer? {
        if whiteColorObject == nil { whiteColorObject = uiColor(white: 1) }
        return whiteColorObject
    }

    static var blackObject: UnsafeMutableRawPointer? {
        if blackColorObject == nil { blackColorObject = uiColor(white: 0) }
        return blackColorObject
    }

    private static func uiColor(white: CGFloat) -> UnsafeMutableRawPointer? {
        // The wrapper owns the colour until it is retained here.
        let color = UIColor.gray(white)
        return withExtendedLifetime(color) { ObjCRuntime.retain(color.objcObject) }
    }
}

// MARK: - Camera

final class SCNCameraState: ObjectState {
    var fieldOfView: CGFloat = 60
    var zNear = 1.0
    var zFar = 100.0
    var orthographic = false
    var orthographicScale = 1.0
    /// SCNCameraProjectionDirection: vertical 0, horizontal 1.
    var horizontal = false
}

@ObjCClass("SCNCamera")
open class SCNCamera: NSObject {
    static let states = StateTable<SCNCameraState>()
    var camera: SCNCameraState { SCNCamera.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNCamera.states.remove(objcObject)
        SCNExtras.cameras.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNCamera.objCClass.pointer)
    }

    @ObjCClassMethod("camera") static func make(_ cls: ObjCClass) -> SCNCamera { cls.object.allocated().unsafeCast(to: SCNCamera.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("fieldOfView") func fieldOfView() -> CGFloat { camera.fieldOfView }
    @ObjCMethod("setFieldOfView:") func setFieldOfView(_ angle: CGFloat) { camera.fieldOfView = angle }
    @ObjCMethod("zNear") func zNear() -> Double { camera.zNear }
    @ObjCMethod("setZNear:") func setZNear(_ distance: Double) { camera.zNear = distance }
    @ObjCMethod("zFar") func zFar() -> Double { camera.zFar }
    @ObjCMethod("setZFar:") func setZFar(_ distance: Double) { camera.zFar = distance }
    @ObjCMethod("usesOrthographicProjection") func usesOrthographicProjection() -> Bool { camera.orthographic }
    @ObjCMethod("setUsesOrthographicProjection:") func setUsesOrthographicProjection(_ uses: Bool) { camera.orthographic = uses }
    @ObjCMethod("projectionDirection") func projectionDirection() -> Int { camera.horizontal ? 1 : 0 }
    @ObjCMethod("setProjectionDirection:") func setProjectionDirection(_ direction: Int) { camera.horizontal = direction == 1 }
    @ObjCMethod("orthographicScale") func orthographicScale() -> Double { camera.orthographicScale }
    @ObjCMethod("setOrthographicScale:") func setOrthographicScale(_ scale: Double) { camera.orthographicScale = scale }
}

// MARK: - Geometry

/// A geometry's triangles: eight floats a vertex (position, normal and
/// texture coordinates), in runs, one for each material the geometry names.
struct SCNMesh {
    var vertices: [Float] = []
    /// For a mesh read from a file, the index in the file's sources of each vertex, which a skinner's weights are by.
    var sources: [Int32] = []
    var elements: [(first: Int, count: Int)] = []
}

final class SCNGeometryState: ObjectState {
    enum Kind { case box, sphere, plane, cylinder, cone, custom }
    var kind = Kind.box
    var width: CGFloat = 1, height: CGFloat = 1, length: CGFloat = 1
    var radius: CGFloat = 0.5, topRadius: CGFloat = 0, bottomRadius: CGFloat = 0.5
    var segments = 48
    /// A geometry read from a scene file: its own triangles.
    var custom = SCNMesh()
    var materials: [NSObject] = []
    var name: String?
    /// Counts changes, for what the renderer keeps of the mesh; the
    /// identifier tells this geometry from any other, as an address can't.
    var revision = 0
    let identifier: Int = {
        SCNGeometryState.counter += 1
        return SCNGeometryState.counter
    }()
    nonisolated(unsafe) private static var counter = 0
    private var cached: (revision: Int, mesh: SCNMesh)?

    var mesh: SCNMesh {
        if kind == .custom { return custom }
        if let cached, cached.revision == revision { return cached.mesh }
        let made = SCNMeshes.make(self)
        cached = (revision, made)
        return made
    }
}

@ObjCClass("SCNGeometry")
open class SCNGeometry: NSObject {
    static let states = StateTable<SCNGeometryState>()
    var geometry: SCNGeometryState { SCNGeometry.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNGeometry.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNGeometry.objCClass.pointer)
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("name") func name() -> String? { geometry.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { geometry.name = name }

    /// The geometry's materials: one default one until set.
    var materialList: [NSObject] {
        if geometry.materials.isEmpty { geometry.materials = [SCNMaterial.make(SCNMaterial.objCClass)] }
        return geometry.materials
    }

    @ObjCMethod("materials") func materials() -> NSObject { NSMutableArray.of(materialList) }
    @ObjCMethod("setMaterials:") func setMaterials(_ materials: NSArray?) { geometry.materials = materials?.elements ?? [] }
    @ObjCMethod("firstMaterial") func firstMaterial() -> SCNMaterial? { materialList.first?.unsafeCast(to: SCNMaterial.self) }
    @ObjCMethod("setFirstMaterial:") func setFirstMaterial(_ material: SCNMaterial?) {
        guard let material else { geometry.materials = []; return }
        var list = materialList
        list[0] = material
        geometry.materials = list
    }
    @ObjCMethod("insertMaterial:atIndex:") func insertMaterial(_ material: SCNMaterial, at index: Int) {
        var list = materialList
        list.insert(material, at: min(max(index, 0), list.count))
        geometry.materials = list
    }
    @ObjCMethod("removeMaterialAtIndex:") func removeMaterial(at index: Int) {
        var list = materialList
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        geometry.materials = list
    }
    @ObjCMethod("materialWithName:") func material(named name: String) -> SCNMaterial? {
        materialList.map { $0.unsafeCast(to: SCNMaterial.self) }.first { $0.material.name == name }
    }
}

@ObjCClass("SCNBox")
open class SCNBox: SCNGeometry {
    @ObjCClassMethod("boxWithWidth:height:length:chamferRadius:")
    static func box(_ cls: ObjCClass, width: CGFloat, height: CGFloat, length: CGFloat, chamferRadius: CGFloat) -> SCNBox {
        let made = cls.object.allocated().unsafeCast(to: SCNBox.self)
        made.geometry.kind = .box
        made.geometry.width = width
        made.geometry.height = height
        made.geometry.length = length
        return made
    }

    @ObjCMethod("init") override func initialize() -> Self { geometry.kind = .box; return self }
    @ObjCMethod("width") func width() -> CGFloat { geometry.width }
    @ObjCMethod("setWidth:") func setWidth(_ width: CGFloat) { geometry.width = width; geometry.revision += 1 }
    @ObjCMethod("height") func height() -> CGFloat { geometry.height }
    @ObjCMethod("setHeight:") func setHeight(_ height: CGFloat) { geometry.height = height; geometry.revision += 1 }
    @ObjCMethod("length") func length() -> CGFloat { geometry.length }
    @ObjCMethod("setLength:") func setLength(_ length: CGFloat) { geometry.length = length; geometry.revision += 1 }
    @ObjCMethod("chamferRadius") func chamferRadius() -> CGFloat { 0 }
    @ObjCMethod("setChamferRadius:") func setChamferRadius(_ radius: CGFloat) {}
}

@ObjCClass("SCNSphere")
open class SCNSphere: SCNGeometry {
    @ObjCClassMethod("sphereWithRadius:")
    static func sphere(_ cls: ObjCClass, radius: CGFloat) -> SCNSphere {
        let made = cls.object.allocated().unsafeCast(to: SCNSphere.self)
        made.geometry.kind = .sphere
        made.geometry.radius = radius
        return made
    }

    @ObjCMethod("init") override func initialize() -> Self { geometry.kind = .sphere; return self }
    @ObjCMethod("radius") func radius() -> CGFloat { geometry.radius }
    @ObjCMethod("setRadius:") func setRadius(_ radius: CGFloat) { geometry.radius = radius; geometry.revision += 1 }
    @ObjCMethod("segmentCount") func segmentCount() -> Int { geometry.segments }
    @ObjCMethod("setSegmentCount:") func setSegmentCount(_ count: Int) { geometry.segments = min(max(count, 3), 96); geometry.revision += 1 }
    @ObjCMethod("isGeodesic") func isGeodesic() -> Bool { false }
    @ObjCMethod("setGeodesic:") func setGeodesic(_ geodesic: Bool) {}
}

@ObjCClass("SCNPlane")
open class SCNPlane: SCNGeometry {
    @ObjCClassMethod("planeWithWidth:height:")
    static func plane(_ cls: ObjCClass, width: CGFloat, height: CGFloat) -> SCNPlane {
        let made = cls.object.allocated().unsafeCast(to: SCNPlane.self)
        made.geometry.kind = .plane
        made.geometry.width = width
        made.geometry.height = height
        return made
    }

    @ObjCMethod("init") override func initialize() -> Self { geometry.kind = .plane; return self }
    @ObjCMethod("width") func width() -> CGFloat { geometry.width }
    @ObjCMethod("setWidth:") func setWidth(_ width: CGFloat) { geometry.width = width; geometry.revision += 1 }
    @ObjCMethod("height") func height() -> CGFloat { geometry.height }
    @ObjCMethod("setHeight:") func setHeight(_ height: CGFloat) { geometry.height = height; geometry.revision += 1 }
    @ObjCMethod("cornerRadius") func cornerRadius() -> CGFloat { 0 }
    @ObjCMethod("setCornerRadius:") func setCornerRadius(_ radius: CGFloat) {}
}

@ObjCClass("SCNCylinder")
open class SCNCylinder: SCNGeometry {
    @ObjCClassMethod("cylinderWithRadius:height:")
    static func cylinder(_ cls: ObjCClass, radius: CGFloat, height: CGFloat) -> SCNCylinder {
        let made = cls.object.allocated().unsafeCast(to: SCNCylinder.self)
        made.geometry.kind = .cylinder
        made.geometry.radius = radius
        made.geometry.height = height
        return made
    }

    @ObjCMethod("init") override func initialize() -> Self { geometry.kind = .cylinder; return self }
    @ObjCMethod("radius") func radius() -> CGFloat { geometry.radius }
    @ObjCMethod("setRadius:") func setRadius(_ radius: CGFloat) { geometry.radius = radius; geometry.revision += 1 }
    @ObjCMethod("height") func height() -> CGFloat { geometry.height }
    @ObjCMethod("setHeight:") func setHeight(_ height: CGFloat) { geometry.height = height; geometry.revision += 1 }
    @ObjCMethod("radialSegmentCount") func radialSegmentCount() -> Int { geometry.segments }
    @ObjCMethod("setRadialSegmentCount:") func setRadialSegmentCount(_ count: Int) {
        geometry.segments = min(max(count, 3), 96)
        geometry.revision += 1
    }
}

@ObjCClass("SCNCone")
open class SCNCone: SCNGeometry {
    @ObjCClassMethod("coneWithTopRadius:bottomRadius:height:")
    static func cone(_ cls: ObjCClass, topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat) -> SCNCone {
        let made = cls.object.allocated().unsafeCast(to: SCNCone.self)
        made.geometry.kind = .cone
        made.geometry.topRadius = topRadius
        made.geometry.bottomRadius = bottomRadius
        made.geometry.height = height
        return made
    }

    @ObjCMethod("init") override func initialize() -> Self { geometry.kind = .cone; return self }
    @ObjCMethod("topRadius") func topRadius() -> CGFloat { geometry.topRadius }
    @ObjCMethod("setTopRadius:") func setTopRadius(_ radius: CGFloat) { geometry.topRadius = radius; geometry.revision += 1 }
    @ObjCMethod("bottomRadius") func bottomRadius() -> CGFloat { geometry.bottomRadius }
    @ObjCMethod("setBottomRadius:") func setBottomRadius(_ radius: CGFloat) { geometry.bottomRadius = radius; geometry.revision += 1 }
    @ObjCMethod("height") func height() -> CGFloat { geometry.height }
    @ObjCMethod("setHeight:") func setHeight(_ height: CGFloat) { geometry.height = height; geometry.revision += 1 }
    @ObjCMethod("radialSegmentCount") func radialSegmentCount() -> Int { geometry.segments }
    @ObjCMethod("setRadialSegmentCount:") func setRadialSegmentCount(_ count: Int) {
        geometry.segments = min(max(count, 3), 96)
        geometry.revision += 1
    }
}

// MARK: - Node

final class SCNNodeState: ObjectState {
    var position = SCNVector3(x: 0, y: 0, z: 0)
    var rotation = SCNMath.noRotation
    var scale = SCNVector3(x: 1, y: 1, z: 1)
    var pivot = SCNMath.identity
    var opacity: CGFloat = 1
    var hidden = false
    var name: String?
    /// The parent, which retains this node; not retained.
    var parent: UnsafeMutableRawPointer?
    var children: [NSObject] = []
    var geometry: SCNGeometry?
    var camera: SCNCamera?
    var light: SCNLight?
    /// The actions running on the node, and the constraints it keeps.
    var running: [SCNRunning] = []
    var constraints: [NSObject] = []
    var categoryBitMask = 1
    var physicsBody: NSObject?
    var skinner: SCNSkinner?
    var particleSystems: [NSObject] = []
    var audioPlayers: [NSObject] = []
    /// Animation players by key, with the keys in the order they were added.
    var animationPlayers: [String: NSObject] = [:]
    var animationKeys: [String] = []

    /// The node's transform within its parent: translation, rotation and
    /// scale, then the pivot undone.
    var local: Matrix {
        let placed = SCNMath.multiply(SCNMath.multiply(SCNMath.translation(position.x, position.y, position.z), SCNMath.rotation(rotation)),
                                      SCNMath.scaling(scale.x, scale.y, scale.z))
        return pivot == SCNMath.identity ? placed : SCNMath.multiply(placed, SCNMath.inverse(pivot))
    }
}

@ObjCClass("SCNNode")
open class SCNNode: NSObject {
    static let nodeStates = StateTable<SCNNodeState>()
    var node: SCNNodeState { SCNNode.nodeStates[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        for child in node.children { SCNNode.nodeStates.existing(child.objcObject)?.parent = nil }
        SCNNode.nodeStates.remove(objcObject)
        SCNExtras.nodes.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNNode.objCClass.pointer)
    }

    @ObjCClassMethod("node") static func make(_ cls: ObjCClass) -> SCNNode { cls.object.allocated().unsafeCast(to: SCNNode.self) }
    @ObjCClassMethod("nodeWithGeometry:")
    static func node(_ cls: ObjCClass, geometry: SCNGeometry?) -> SCNNode {
        let made = cls.object.allocated().unsafeCast(to: SCNNode.self)
        made.node.geometry = geometry
        return made
    }

    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("initWithCoder:") func initialize(coder: NSObject) -> Self { self }

    @ObjCMethod("name") func name() -> String? { node.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { node.name = name }
    @ObjCMethod("geometry") func geometry() -> SCNGeometry? { node.geometry }
    @ObjCMethod("setGeometry:") func setGeometry(_ geometry: SCNGeometry?) { node.geometry = geometry }
    @ObjCMethod("camera") func camera() -> SCNCamera? { node.camera }
    @ObjCMethod("setCamera:") func setCamera(_ camera: SCNCamera?) { node.camera = camera }
    @ObjCMethod("constraints") func constraints() -> NSObject { NSMutableArray.of(node.constraints) }
    @ObjCMethod("setConstraints:") func setConstraints(_ constraints: NSArray?) { node.constraints = constraints?.elements ?? [] }
    @ObjCMethod("light") func light() -> SCNLight? { node.light }
    @ObjCMethod("setLight:") func setLight(_ light: SCNLight?) { node.light = light }
    @ObjCMethod("isHidden") func isHidden() -> Bool { node.hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { node.hidden = hidden }
    @ObjCMethod("opacity") func opacity() -> CGFloat { node.opacity }
    @ObjCMethod("setOpacity:") func setOpacity(_ opacity: CGFloat) { node.opacity = opacity }

    // MARK: Transform

    @ObjCMethod("position") func position() -> SCNVector3 { node.position }
    @ObjCMethod("setPosition:") func setPosition(_ position: SCNVector3) { node.position = position }
    @ObjCMethod("scale") func scale() -> SCNVector3 { node.scale }
    @ObjCMethod("setScale:") func setScale(_ scale: SCNVector3) { node.scale = scale }
    @ObjCMethod("rotation") func rotation() -> SCNVector4 { SCNMath.axisAngle(node.rotation) }
    @ObjCMethod("setRotation:") func setRotation(_ rotation: SCNVector4) {
        node.rotation = SCNMath.quaternion(axis: SCNVector3(x: rotation.x, y: rotation.y, z: rotation.z), angle: rotation.w)
    }
    @ObjCMethod("eulerAngles") func eulerAngles() -> SCNVector3 { SCNMath.euler(node.rotation) }
    @ObjCMethod("setEulerAngles:") func setEulerAngles(_ angles: SCNVector3) { node.rotation = SCNMath.quaternion(euler: angles) }
    @ObjCMethod("orientation") func orientation() -> SCNVector4 {
        SCNVector4(x: node.rotation.x, y: node.rotation.y, z: node.rotation.z, w: node.rotation.w)
    }
    @ObjCMethod("setOrientation:") func setOrientation(_ q: SCNVector4) {
        node.rotation = SCNMath.normalized((q.x, q.y, q.z, q.w))
    }
    @ObjCMethod("pivot") func pivot() -> SCNMatrix4 { SCNMath.matrix4(node.pivot) }
    @ObjCMethod("setPivot:") func setPivot(_ pivot: SCNMatrix4) { node.pivot = SCNMath.matrix(pivot) }

    @ObjCMethod("transform") func transform() -> SCNMatrix4 { SCNMath.matrix4(node.local) }
    @ObjCMethod("setTransform:") func setTransform(_ transform: SCNMatrix4) {
        let parts = SCNMath.decompose(SCNMath.matrix(transform))
        node.position = parts.position
        node.rotation = parts.rotation
        node.scale = parts.scale
        node.pivot = SCNMath.identity
    }

    /// The node's transform in the scene: its parents' times its own.
    var world: Matrix {
        var matrix = node.local
        var current = node.parent
        while let parent = current, let state = SCNNode.nodeStates.existing(parent) {
            matrix = SCNMath.multiply(state.local, matrix)
            current = state.parent
        }
        return matrix
    }

    @ObjCMethod("worldTransform") func worldTransform() -> SCNMatrix4 { SCNMath.matrix4(world) }
    @ObjCMethod("worldPosition") func worldPosition() -> SCNVector3 {
        let m = world
        return SCNVector3(x: m[12], y: m[13], z: m[14])
    }

    /// A point of this node's space in another node's, or the scene's.
    @ObjCMethod("convertPosition:toNode:")
    func convertPosition(_ position: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        let inScene = SCNMath.transform(world, position)
        guard let node else { return inScene }
        return SCNMath.transform(SCNMath.inverse(node.world), inScene)
    }

    @ObjCMethod("convertPosition:fromNode:")
    func convertPosition(_ position: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let inScene = node.map { SCNMath.transform($0.world, position) } ?? position
        return SCNMath.transform(SCNMath.inverse(world), inScene)
    }

    // MARK: Tree

    @ObjCMethod("parentNode") func parentNode() -> SCNNode? { node.parent.map { SCNNode(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("childNodes") func childNodes() -> NSObject { NSMutableArray.of(node.children) }

    @ObjCMethod("addChildNode:")
    func addChildNode(_ child: SCNNode) {
        guard child.objcObject != objcObject, !isDescendant(of: child) else { return }
        // A node has one parent: adding it somewhere else moves it.
        if child.node.parent != nil { child.removeFromParentNode() }
        child.node.parent = objcObject
        node.children.append(child)
    }

    @ObjCMethod("insertChildNode:atIndex:")
    func insertChildNode(_ child: SCNNode, at index: Int) {
        guard child.objcObject != objcObject, !isDescendant(of: child) else { return }
        if child.node.parent != nil { child.removeFromParentNode() }
        child.node.parent = objcObject
        node.children.insert(child, at: min(max(index, 0), node.children.count))
    }

    /// Whether `ancestor` is this node or above it.
    private func isDescendant(of ancestor: SCNNode) -> Bool {
        var current: UnsafeMutableRawPointer? = objcObject
        while let object = current {
            if object == ancestor.objcObject { return true }
            current = SCNNode.nodeStates.existing(object)?.parent
        }
        return false
    }

    @ObjCMethod("removeFromParentNode")
    func removeFromParentNode() {
        guard let parent = node.parent, let state = SCNNode.nodeStates.existing(parent) else { return }
        // The child may be released with the last reference; hold it while it goes.
        let held = SCNNode(objcObject: objcObject, ownership: .retain)
        state.children.removeAll { $0.objcObject == held.objcObject }
        node.parent = nil
    }

    @ObjCMethod("replaceChildNode:with:")
    func replaceChildNode(_ old: SCNNode, with new: SCNNode) {
        guard let index = node.children.firstIndex(where: { $0.objcObject == old.objcObject }) else { return }
        old.removeFromParentNode()
        insertChildNode(new, at: index)
    }

    @ObjCMethod("childNodeWithName:recursively:")
    func childNode(withName name: String, recursively: Bool) -> SCNNode? {
        for child in node.children.map({ $0.unsafeCast(to: SCNNode.self) }) {
            if child.node.name == name { return child }
            if recursively, let found = child.childNode(withName: name, recursively: true) { return found }
        }
        return nil
    }
}

// MARK: - Scene

final class SCNSceneState: ObjectState {
    var root: SCNNode?
    var background: SCNMaterialProperty?
}

@ObjCClass("SCNScene")
open class SCNScene: NSObject {
    static let states = StateTable<SCNSceneState>()
    var scene: SCNSceneState { SCNScene.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNScene.states.remove(objcObject)
        SCNExtras.scenes.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNScene.objCClass.pointer)
    }

    @ObjCClassMethod("scene") static func make(_ cls: ObjCClass) -> SCNScene { cls.object.allocated().unsafeCast(to: SCNScene.self) }
    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCClassMethod("sceneNamed:")
    static func scene(_ cls: ObjCClass, named name: String) -> SCNScene? { SCNFile.scene(named: name, inDirectory: nil) }

    @ObjCClassMethod("sceneNamed:inDirectory:options:")
    static func scene(_ cls: ObjCClass, named name: String, inDirectory directory: String?, options: NSObject?) -> SCNScene? {
        SCNFile.scene(named: name, inDirectory: directory)
    }

    @ObjCClassMethod("sceneWithURL:options:error:")
    static func scene(_ cls: ObjCClass, url: NSObject, options: NSObject?, error: UnsafeMutableRawPointer?) -> SCNScene? {
        url.scnPath().flatMap { SCNFile.scene(atPath: $0) }
    }

    @ObjCMethod("rootNode")
    func rootNode() -> SCNNode {
        if let root = scene.root { return root }
        let made = SCNNode.make(SCNNode.objCClass)
        scene.root = made
        return made
    }

    /// The background: black until given contents.
    @ObjCMethod("background")
    func background() -> SCNMaterialProperty {
        if let background = scene.background { return background }
        let made = SCNMaterialProperty.make(contents: SKSupport.blackObject)
        scene.background = made
        return made
    }
}

// MARK: - SCNView

final class SCNViewState: ObjectState {
    var scene: SCNScene?
    var pointOfView: SCNNode?
    var delegate: UnsafeMutableRawPointer?
    var autoenablesDefaultLighting = false
    var playing = false
    var loops = true
    var showsStatistics = false
    var allowsCameraControl = false
    var antialiasing = 0
    var framesPerSecond = 60
    var running = false
    var start: Double?
    var lastFrame = 0.0
    /// A SpriteKit scene over the view's drawing, shown by a view of its own.
    var overlayScene: SKScene?
    var overlayView: SKView?
    /// The view's drawing, made at its first frame.
    var renderer: SCNRenderer?
}

@ObjCClass("SCNView")
open class SCNView: UIView {
    static let scnStates = StateTable<SCNViewState>()
    var scn: SCNViewState { SCNView.scnStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        configure()
        return self
    }

    @ObjCMethod("initWithFrame:options:")
    func initialize(frame: CGRect, options: NSObject?) -> Self {
        _ = super.initialize(frame: frame)
        configure()
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        configure()
        return self
    }

    private func configure() {
        state.geometry.masksToBounds = true
        state.geometry.backgroundColor = SKSupport.blackColor
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        Frames.remove(scn)
        SCNView.scnStates.remove(objcObject)
        SCNExtras.views.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("scene") func scene() -> SCNScene? { scn.scene }
    @ObjCMethod("setScene:") func setScene(_ scene: SCNScene?) {
        scn.scene = scene
        scn.start = nil
        restartFrames()
    }
    @ObjCMethod("pointOfView") func pointOfView() -> SCNNode? { scn.pointOfView }
    @ObjCMethod("setPointOfView:") func setPointOfView(_ node: SCNNode?) { scn.pointOfView = node }
    @ObjCMethod("delegate") func delegate() -> NSObject? { scn.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { scn.delegate = delegate?.objcObject }
    @ObjCMethod("autoenablesDefaultLighting") func autoenablesDefaultLighting() -> Bool { scn.autoenablesDefaultLighting }
    @ObjCMethod("setAutoenablesDefaultLighting:") func setAutoenablesDefaultLighting(_ enables: Bool) { scn.autoenablesDefaultLighting = enables }
    @ObjCMethod("isPlaying") func isPlaying() -> Bool { scn.playing }
    @ObjCMethod("setPlaying:") func setPlaying(_ playing: Bool) { scn.playing = playing }
    @ObjCMethod("loops") func loops() -> Bool { scn.loops }
    @ObjCMethod("setLoops:") func setLoops(_ loops: Bool) { scn.loops = loops }
    @ObjCMethod("showsStatistics") func showsStatistics() -> Bool { scn.showsStatistics }
    @ObjCMethod("setShowsStatistics:") func setShowsStatistics(_ shows: Bool) { scn.showsStatistics = shows }
    @ObjCMethod("allowsCameraControl") func allowsCameraControl() -> Bool { scn.allowsCameraControl }
    @ObjCMethod("setAllowsCameraControl:") func setAllowsCameraControl(_ allows: Bool) { scn.allowsCameraControl = allows }
    @ObjCMethod("antialiasingMode") func antialiasingMode() -> Int { scn.antialiasing }
    @ObjCMethod("setAntialiasingMode:") func setAntialiasingMode(_ mode: Int) { scn.antialiasing = mode }
    @ObjCMethod("preferredFramesPerSecond") func preferredFramesPerSecond() -> Int { scn.framesPerSecond }
    @ObjCMethod("setPreferredFramesPerSecond:") func setPreferredFramesPerSecond(_ rate: Int) {
        scn.framesPerSecond = min(max(rate, 1), 60)
        restartFrames()
    }
    @ObjCMethod("overlaySKScene") func overlaySKScene() -> SKScene? { scn.overlayScene }
    @ObjCMethod("setOverlaySKScene:")
    func setOverlaySKScene(_ scene: SKScene?) {
        scn.overlayScene = scene
        if getenv("PERRY_SCENEKIT_NO_OVERLAY") != nil { return }
        guard let scene else {
            scn.overlayView?.removeFromSuperview()
            scn.overlayView = nil
            return
        }
        if scn.overlayView == nil {
            let overlay = SKView.objCClass.object.allocated().unsafeCast(to: SKView.self).initialize(frame: state.bounds)
            overlay.sk.allowsTransparency = true
            overlay.sk.isOverlay = true
            overlay.state.geometry.backgroundColor = nil
            scn.overlayView = overlay
            addSubview(overlay)
        }
        scn.overlayView?.presentScene(scene)
    }
    @ObjCMethod("sceneTime") func sceneTime() -> Double { scn.start.map { SKSupport.now() - $0 } ?? 0 }

    // MARK: Frames

    private func restartFrames() {
        stopFrames()
        guard scn.scene != nil else { return }
        scn.running = true
        let object = objcObject
        Frames.add(scn, framesPerSecond: scn.framesPerSecond) { _ in
            UIView.wrap(object).unsafeCast(to: SCNView.self).runFrame()
        }
    }

    private func stopFrames() {
        guard scn.running else { return }
        scn.running = false
        Frames.remove(scn)
    }

    /// One frame: the delegate's steps, when the view is playing, then the
    /// scene's drawing.
    func runFrame() {
        guard let scene = scn.scene else { return }
        let now = SKSupport.now()
        if scn.start == nil { scn.start = now; scn.lastFrame = now }
        let time = now - (scn.start ?? now)
        let delegate = scn.delegate.map { NSObject($0) }
        func send(_ selector: String, _ body: (NSObject) -> Void) {
            if let delegate, delegate.responds(to: selector) { body(delegate) }
        }
        // Actions run with the frame's time, then the delegate hears of them, and constraints settle the nodes.
        let elapsed = min(max(now - scn.lastFrame, 0), 0.1)
        scn.lastFrame = now
        SCNTimers.process(now: now)
        send("renderer:updateAtTime:") { $0.scnSendRenderer(self, updateAtTime: time) }
        SCNActions.advance(scene.rootNode(), elapsed)
        SCNAnimations.advance(scene.rootNode(), elapsed)
        send("renderer:didApplyAnimationsAtTime:") { $0.scnSendRenderer(self, didApplyAnimationsAtTime: time) }
        send("renderer:didSimulatePhysicsAtTime:") { $0.scnSendRenderer(self, didSimulatePhysicsAtTime: time) }
        let camera = scn.pointOfView?.world
        SCNCollision.step(scene)
        SCNConstraints.apply(scene.rootNode(), elapsed: elapsed, cameraPosition: camera.map { SCNVector3(x: $0[12], y: $0[13], z: $0[14]) })
        if let delegate, delegate.responds(to: "renderer:willRenderScene:atTime:") {
            delegate.scnSendRenderer(self, willRenderScene: scene, atTime: time)
        }
        if let overlay = scn.overlayView, overlay.state.bounds.size != state.bounds.size { overlay.setFrame(state.bounds) }
        if scn.renderer == nil { scn.renderer = SCNRenderer() }
        scn.renderer?.draw(scene, pointOfView: scn.pointOfView, in: self, scale: state.geometry.contentsScale, layer: state.layer,
                           defaultLighting: scn.autoenablesDefaultLighting)
        if let delegate, delegate.responds(to: "renderer:didRenderScene:atTime:") {
            delegate.scnSendRenderer(self, didRenderScene: scene, atTime: time)
        }
    }
}
