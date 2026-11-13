import CPerryGeometry
import Glibc
import PerryObjCInterop

// The rest of the SceneKit API apps call on nodes, views and materials
// that has an answer without drawing anything new: enumerating and cloning
// nodes, the simd accessors, a node's category mask and the things it keeps
// for others (particle systems, audio players, animation players), the
// view's projection of points, a material's other properties, and boxing
// SceneKit's vectors in NSValue.

// MARK: - simd

#if _pointerBitWidth(_64)
extension PerrySimdFloat3: ObjCStructure {
    public typealias ObjCType = PerrySimdFloat3
    public static var objCTypeEncoding: String { "<3f>" }
    init(_ x: Float, _ y: Float, _ z: Float) { self.init(v: SIMD3(x, y, z)) }
}

extension PerrySimdFloat4: ObjCStructure {
    public typealias ObjCType = PerrySimdFloat4
    public static var objCTypeEncoding: String { "<4f>" }
}

extension PerrySimdFloat4x4: ObjCStructure {
    public typealias ObjCType = PerrySimdFloat4x4
    public static var objCTypeEncoding: String { "{?=[4<4f>]}" }

    init(_ m: Matrix) {
        self.init(c0: SIMD4(m[0], m[1], m[2], m[3]), c1: SIMD4(m[4], m[5], m[6], m[7]), c2: SIMD4(m[8], m[9], m[10], m[11]),
                  c3: SIMD4(m[12], m[13], m[14], m[15]))
    }

    var matrix: Matrix {
        [c0[0], c0[1], c0[2], c0[3], c1[0], c1[1], c1[2], c1[3], c2[0], c2[1], c2[2], c2[3], c3[0], c3[1], c3[2], c3[3]]
    }
}

@ObjCCategory("SCNNodeSimd")
extension SCNNode {
    @ObjCMethod("simdPosition") func simdPosition() -> PerrySimdFloat3 { PerrySimdFloat3(node.position.x, node.position.y, node.position.z) }
    @ObjCMethod("setSimdPosition:") func setSimdPosition(_ position: PerrySimdFloat3) {
        node.position = SCNVector3(x: position.v.x, y: position.v.y, z: position.v.z)
    }
    @ObjCMethod("simdWorldPosition") func simdWorldPosition() -> PerrySimdFloat3 {
        let m = world
        return PerrySimdFloat3(m[12], m[13], m[14])
    }
    @ObjCMethod("setSimdWorldPosition:") func setSimdWorldPosition(_ position: PerrySimdFloat3) {
        var m = world
        m[12] = position.v.x; m[13] = position.v.y; m[14] = position.v.z
        setWorld(m)
    }
    @ObjCMethod("simdTransform") func simdTransform() -> PerrySimdFloat4x4 { PerrySimdFloat4x4(node.local) }
    @ObjCMethod("setSimdTransform:") func setSimdTransform(_ transform: PerrySimdFloat4x4) {
        let parts = SCNMath.decompose(transform.matrix)
        node.position = parts.position
        node.rotation = parts.rotation
        node.scale = parts.scale
        node.pivot = SCNMath.identity
    }
    @ObjCMethod("simdWorldTransform") func simdWorldTransform() -> PerrySimdFloat4x4 { PerrySimdFloat4x4(world) }
    @ObjCMethod("simdWorldFront") func simdWorldFront() -> PerrySimdFloat3 { axis(2, negated: true) }
    @ObjCMethod("simdWorldRight") func simdWorldRight() -> PerrySimdFloat3 { axis(0, negated: false) }
    @ObjCMethod("simdWorldUp") func simdWorldUp() -> PerrySimdFloat3 { axis(1, negated: false) }

    /// A column of the world transform, as a unit vector.
    private func axis(_ column: Int, negated: Bool) -> PerrySimdFloat3 {
        let m = world, sign: Float = negated ? -1 : 1
        let v = SIMD3(m[column * 4], m[column * 4 + 1], m[column * 4 + 2]) * sign
        let length = (v * v).sum().squareRoot()
        return PerrySimdFloat3(v: length > 0 ? v / length : v)
    }

    @ObjCMethod("simdConvertPosition:toNode:")
    func simdConvertPosition(_ position: PerrySimdFloat3, to node: SCNNode?) -> PerrySimdFloat3 {
        let v = convertPosition(SCNVector3(x: position.v.x, y: position.v.y, z: position.v.z), to: node)
        return PerrySimdFloat3(v.x, v.y, v.z)
    }

    /// Turns the node about a point in its parent's space.
    @ObjCMethod("simdRotateBy:aroundTarget:")
    func simdRotate(by rotation: PerrySimdFloat4, aroundTarget target: PerrySimdFloat3) {
        let r = rotation.v, t = target.v
        let q = SCNMath.normalized((r[0], r[1], r[2], r[3]))
        let about = SCNMath.multiply(SCNMath.multiply(SCNMath.translation(t.x, t.y, t.z), SCNMath.rotation(q)), SCNMath.translation(-t.x, -t.y, -t.z))
        let parts = SCNMath.decompose(SCNMath.multiply(about, node.local))
        node.position = parts.position
        node.rotation = parts.rotation
    }
}
#endif

// MARK: - Nodes

@ObjCCategory("SCNNodeEnumeration")
extension SCNNode {
    /// Calls the block for each node below this one (and this one, for the hierarchy), until it sets stop.
    private func enumerate(_ block: ObjCBlock, includingSelf: Bool) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutablePointer<Bool>) -> Void
        let invoke = block.function(as: Invoke.self)
        var stop = false
        func visit(_ node: SCNNode) {
            guard !stop else { return }
            invoke(block.object, node.objcObject, &stop)
            guard !stop else { return }
            for child in node.node.children { visit(child.unsafeCast(to: SCNNode.self)) }
        }
        if includingSelf {
            visit(self)
        } else {
            for child in node.children { visit(child.unsafeCast(to: SCNNode.self)) }
        }
    }

    @ObjCMethod("enumerateChildNodesUsingBlock:") func enumerateChildNodes(_ block: ObjCBlock) { enumerate(block, includingSelf: false) }
    @ObjCMethod("enumerateHierarchyUsingBlock:") func enumerateHierarchy(_ block: ObjCBlock) { enumerate(block, includingSelf: true) }

    /// A copy of the node and what it holds, sharing its geometry and materials.
    @ObjCMethod("clone")
    func clone() -> SCNNode {
        let copy = SCNNode.make(SCNNode.objCClass)
        let (from, to) = (node, copy.node)
        to.position = from.position
        to.rotation = from.rotation
        to.scale = from.scale
        to.pivot = from.pivot
        to.opacity = from.opacity
        to.hidden = from.hidden
        to.name = from.name
        to.geometry = from.geometry
        to.camera = from.camera
        to.light = from.light
        to.categoryBitMask = from.categoryBitMask
        to.constraints = from.constraints
        to.particleSystems = from.particleSystems
        for child in from.children { copy.addChildNode(child.unsafeCast(to: SCNNode.self).clone()) }
        return copy
    }

    @ObjCMethod("flattenedClone") func flattenedClone() -> SCNNode { clone() }
    @ObjCMethod("presentationNode") func presentationNode() -> SCNNode { self }
    @ObjCMethod("categoryBitMask") func categoryBitMask() -> Int { node.categoryBitMask }
    @ObjCMethod("setCategoryBitMask:") func setCategoryBitMask(_ mask: Int) { node.categoryBitMask = mask }
    @ObjCMethod("castsShadow") func castsShadow() -> Bool { SCNExtras.nodes[objcObject].values["castsShadow"] ?? 1 != 0 }
    @ObjCMethod("setCastsShadow:") func setCastsShadow(_ casts: Bool) { SCNExtras.nodes[objcObject].values["castsShadow"] = casts ? 1 : 0 }
    @ObjCMethod("renderingOrder") func renderingOrder() -> Int { Int(SCNExtras.nodes[objcObject].values["renderingOrder"] ?? 0) }
    @ObjCMethod("setRenderingOrder:") func setRenderingOrder(_ order: Int) { SCNExtras.nodes[objcObject].values["renderingOrder"] = Double(order) }

    @ObjCMethod("physicsBody") func physicsBody() -> NSObject? { node.physicsBody }
    @ObjCMethod("setPhysicsBody:") func setPhysicsBody(_ body: NSObject?) { node.physicsBody = body }

    @ObjCMethod("particleSystems") func particleSystems() -> NSObject? { node.particleSystems.isEmpty ? nil : NSMutableArray.of(node.particleSystems) }
    @ObjCMethod("addParticleSystem:") func addParticleSystem(_ system: NSObject) { node.particleSystems.append(system) }
    @ObjCMethod("addParticleSystem:withTransform:")
    func addParticleSystem(_ system: NSObject, withTransform transform: SCNMatrix4) { node.particleSystems.append(system) }
    @ObjCMethod("removeParticleSystem:")
    func removeParticleSystem(_ system: NSObject) { node.particleSystems.removeAll { $0.objcObject == system.objcObject } }
    @ObjCMethod("removeAllParticleSystems") func removeAllParticleSystems() { node.particleSystems = [] }

    @ObjCMethod("audioPlayers") func audioPlayers() -> NSObject { NSMutableArray.of(node.audioPlayers) }
    @ObjCMethod("addAudioPlayer:") func addAudioPlayer(_ player: NSObject) { node.audioPlayers.append(player) }
    @ObjCMethod("removeAllAudioPlayers") func removeAllAudioPlayers() { node.audioPlayers = [] }

}

// MARK: - Bounds

extension SCNGeometryState {
    /// The corners of the box around the geometry's vertices, kept until it changes.
    var bounds: (min: SCNVector3, max: SCNVector3)? {
        if let cached = SCNBounds.cache[identifier], cached.revision == revision { return cached.box }
        let v = mesh.vertices
        var box: (min: SCNVector3, max: SCNVector3)?
        if v.count >= 8 {
            var lo = SCNVector3(x: v[0], y: v[1], z: v[2]), hi = lo
            for i in stride(from: 0, to: v.count - 7, by: 8) {
                lo = SCNVector3(x: min(lo.x, v[i]), y: min(lo.y, v[i + 1]), z: min(lo.z, v[i + 2]))
                hi = SCNVector3(x: max(hi.x, v[i]), y: max(hi.y, v[i + 1]), z: max(hi.z, v[i + 2]))
            }
            box = (lo, hi)
        }
        SCNBounds.cache[identifier] = (revision, box)
        return box
    }
}

enum SCNBounds {
    nonisolated(unsafe) static var cache: [Int: (revision: Int, box: (min: SCNVector3, max: SCNVector3)?)] = [:]
}

@ObjCCategory("SCNNodeBounds")
extension SCNNode {
    /// The box around the node's geometry and its children's, in the node's own space.
    func boundingBox() -> (min: SCNVector3, max: SCNVector3)? {
        var lo = SCNVector3(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude, z: .greatestFiniteMagnitude)
        var hi = SCNVector3(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude, z: -.greatestFiniteMagnitude)
        var any = false
        func add(_ box: (min: SCNVector3, max: SCNVector3), _ matrix: Matrix) {
            for corner in 0..<8 {
                let p = SCNMath.transform(matrix, SCNVector3(x: corner & 1 == 0 ? box.min.x : box.max.x, y: corner & 2 == 0 ? box.min.y : box.max.y,
                                                              z: corner & 4 == 0 ? box.min.z : box.max.z))
                lo = SCNVector3(x: min(lo.x, p.x), y: min(lo.y, p.y), z: min(lo.z, p.z))
                hi = SCNVector3(x: max(hi.x, p.x), y: max(hi.y, p.y), z: max(hi.z, p.z))
                any = true
            }
        }
        if let box = node.geometry?.geometry.bounds { add(box, SCNMath.identity) }
        for child in node.children.map({ $0.unsafeCast(to: SCNNode.self) }) {
            if let box = child.boundingBox() { add(box, child.node.local) }
        }
        return any ? (lo, hi) : nil
    }

    @ObjCMethod("getBoundingBoxMin:max:")
    func getBoundingBox(min: UnsafeMutableRawPointer?, max: UnsafeMutableRawPointer?) -> Bool {
        guard let box = boundingBox() else { return false }
        min?.storeBytes(of: box.min, as: SCNVector3.self)
        max?.storeBytes(of: box.max, as: SCNVector3.self)
        return true
    }

    @ObjCMethod("getBoundingSphereCenter:radius:")
    func getBoundingSphere(center: UnsafeMutableRawPointer?, radius: UnsafeMutableRawPointer?) -> Bool {
        guard let box = boundingBox() else { return false }
        let c = SCNVector3(x: (box.min.x + box.max.x) / 2, y: (box.min.y + box.max.y) / 2, z: (box.min.z + box.max.z) / 2)
        let r = ((box.max.x - c.x) * (box.max.x - c.x) + (box.max.y - c.y) * (box.max.y - c.y) + (box.max.z - c.z) * (box.max.z - c.z)).squareRoot()
        center?.storeBytes(of: c, as: SCNVector3.self)
        radius?.storeBytes(of: CGFloat(r), as: CGFloat.self)
        return true
    }
}

// MARK: - Materials

@ObjCCategory("SCNMaterialProperties")
extension SCNMaterial {
    /// A property the material has besides its diffuse, emission and specular, made when first asked for.
    private func slot(_ name: String) -> SCNMaterialProperty {
        let table = SCNExtras.materials[objcObject]
        if let made = table.objects[name] { return made.unsafeCast(to: SCNMaterialProperty.self) }
        let made = SCNMaterialProperty.make(contents: nil)
        table.objects[name] = made
        return made
    }

    @ObjCMethod("normal") func normal() -> SCNMaterialProperty { slot("normal") }
    @ObjCMethod("metalness") func metalness() -> SCNMaterialProperty { slot("metalness") }
    @ObjCMethod("roughness") func roughness() -> SCNMaterialProperty { slot("roughness") }
    @ObjCMethod("ambientOcclusion") func ambientOcclusion() -> SCNMaterialProperty { slot("ambientOcclusion") }
    @ObjCMethod("selfIllumination") func selfIllumination() -> SCNMaterialProperty { slot("selfIllumination") }
    @ObjCMethod("transparent") func transparent() -> SCNMaterialProperty { slot("transparent") }
    @ObjCMethod("reflective") func reflective() -> SCNMaterialProperty { slot("reflective") }
    @ObjCMethod("multiply") func multiply() -> SCNMaterialProperty { slot("multiply") }
    @ObjCMethod("displacement") func displacement() -> SCNMaterialProperty { slot("displacement") }
    @ObjCMethod("ambient") func ambient() -> SCNMaterialProperty { slot("ambient") }
    @ObjCMethod("clearCoat") func clearCoat() -> SCNMaterialProperty { slot("clearCoat") }
    @ObjCMethod("shaderModifiers") func shaderModifiers() -> NSObject? { SCNExtras.materials[objcObject].objects["shaderModifiers"] }
    @ObjCMethod("setShaderModifiers:") func setShaderModifiers(_ modifiers: NSObject?) {
        SCNExtras.materials[objcObject].objects["shaderModifiers"] = modifiers
    }
}

// MARK: - The view

@ObjCCategory("SCNViewProjection")
extension SCNView {
    /// The view and projection matrices of the camera the view draws from.
    private func cameraMatrices() -> (view: Matrix, projection: Matrix)? {
        guard let scene = scn.scene else { return nil }
        let camera = scn.pointOfView ?? SCNRenderer.findCamera(in: scene.rootNode())
        let size = state.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let projection = SCNRenderer.projection(camera?.node.camera?.camera, aspect: Float(size.width / size.height))
        return (SCNMath.inverse(camera?.world ?? SCNMath.identity), projection)
    }

    /// A point in the scene as the view's coordinates (z 0 near, 1 far).
    @ObjCMethod("projectPoint:")
    func projectPoint(_ point: SCNVector3) -> SCNVector3 {
        guard let (view, projection) = cameraMatrices() else { return point }
        let m = SCNMath.multiply(projection, view)
        let x = m[0] * point.x + m[4] * point.y + m[8] * point.z + m[12]
        let y = m[1] * point.x + m[5] * point.y + m[9] * point.z + m[13]
        let z = m[2] * point.x + m[6] * point.y + m[10] * point.z + m[14]
        let w = m[3] * point.x + m[7] * point.y + m[11] * point.z + m[15]
        guard abs(w) > 1e-9 else { return point }
        let size = state.bounds.size
        return SCNVector3(x: Float(size.width) * (x / w + 1) / 2, y: Float(size.height) * (1 - y / w) / 2, z: (z / w + 1) / 2)
    }

    /// A point of the view's (z 0 near, 1 far) in the scene.
    @ObjCMethod("unprojectPoint:")
    func unprojectPoint(_ point: SCNVector3) -> SCNVector3 {
        guard let (view, projection) = cameraMatrices() else { return point }
        let size = state.bounds.size
        let inverse = SCNMath.inverse(SCNMath.multiply(projection, view))
        let x = 2 * point.x / Float(size.width) - 1, y = 1 - 2 * point.y / Float(size.height), z = 2 * point.z - 1
        let wx = inverse[0] * x + inverse[4] * y + inverse[8] * z + inverse[12]
        let wy = inverse[1] * x + inverse[5] * y + inverse[9] * z + inverse[13]
        let wz = inverse[2] * x + inverse[6] * y + inverse[10] * z + inverse[14]
        let ww = inverse[3] * x + inverse[7] * y + inverse[11] * z + inverse[15]
        guard abs(ww) > 1e-9 else { return point }
        return SCNVector3(x: wx / ww, y: wy / ww, z: wz / ww)
    }

    @ObjCMethod("nodesInsideFrustumWithPointOfView:") func nodesInsideFrustum(pointOfView: SCNNode) -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("isNodeInsideFrustum:withPointOfView:") func isNodeInsideFrustum(_ node: SCNNode, pointOfView: SCNNode) -> Bool { true }
    @ObjCMethod("prepareObject:shouldAbortBlock:") func prepareObject(_ object: NSObject, shouldAbortBlock: ObjCBlock?) -> Bool { true }
    @ObjCMethod("prepareObjects:withCompletionHandler:")
    func prepareObjects(_ objects: NSArray, withCompletionHandler handler: ObjCBlock?) {
        guard let handler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Bool) -> Void
        handler.function(as: Invoke.self)(handler.object, true)
    }

    /// SCNRenderingAPI: OpenGL ES 2.
    @ObjCMethod("renderingAPI") func renderingAPI() -> Int { 2 }
    @ObjCMethod("currentViewport") func currentViewport() -> CGRect { state.bounds }
    @ObjCMethod("currentRenderCommandEncoder") func currentRenderCommandEncoder() -> NSObject? { nil }
    @ObjCMethod("audioEngine") func audioEngine() -> NSObject? { nil }
    @ObjCMethod("audioListener") func audioListener() -> SCNNode? { SCNExtras.views[objcObject].objects["audioListener"]?.unsafeCast(to: SCNNode.self) }
    @ObjCMethod("setAudioListener:") func setAudioListener(_ node: SCNNode?) { SCNExtras.views[objcObject].objects["audioListener"] = node }
    @ObjCMethod("setSceneTime:") func setSceneTime(_ time: Double) { scn.start = SKSupport.now() - time }

    /// Shows another scene; the transition is not drawn.
    @ObjCMethod("presentScene:withTransition:incomingPointOfView:completionHandler:")
    func presentScene(_ scene: SCNScene, withTransition transition: NSObject?, incomingPointOfView pointOfView: SCNNode?, completionHandler: ObjCBlock?) {
        setScene(scene)
        scn.pointOfView = pointOfView
        guard let completionHandler else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        completionHandler.function(as: Invoke.self)(completionHandler.object)
    }
}

// MARK: - NSValue

private func box<T>(_ cls: ObjCClass, _ value: T, _ encoding: String) -> NSObject {
    var copy = value
    return encoding.withCString { type in
        withUnsafeBytes(of: &copy) { bytes in
            cls.object.allocated().unsafeCast(to: NSValueObject.self).initialize(bytes: bytes.baseAddress, objCType: type)
        }
    }
}

private func unbox<T>(_ object: NSObject, _ empty: T) -> T {
    var value = empty
    withUnsafeMutableBytes(of: &value) { object.unsafeCast(to: NSValueObject.self).getValue($0.baseAddress) }
    return value
}

@ObjCCategory("SceneKitKeyedCoding")
extension NSValueObject {
    @ObjCClassMethod("valueWithSCNVector3:")
    static func value(_ cls: ObjCClass, vector3 vector: SCNVector3) -> NSObject { box(cls, vector, "{SCNVector3=fff}") }
    @ObjCClassMethod("valueWithSCNVector4:")
    static func value(_ cls: ObjCClass, vector4 vector: SCNVector4) -> NSObject { box(cls, vector, "{SCNVector4=ffff}") }
    @ObjCClassMethod("valueWithSCNMatrix4:")
    static func value(_ cls: ObjCClass, matrix4 matrix: SCNMatrix4) -> NSObject { box(cls, matrix, "{SCNMatrix4=ffffffffffffffff}") }

    @ObjCMethod("SCNVector3Value") func vector3Value() -> SCNVector3 { unbox(self, SCNVector3(x: 0, y: 0, z: 0)) }
    @ObjCMethod("SCNVector4Value") func vector4Value() -> SCNVector4 { unbox(self, SCNVector4(x: 0, y: 0, z: 0, w: 0)) }
    @ObjCMethod("SCNMatrix4Value") func matrix4Value() -> SCNMatrix4 { unbox(self, SCNMath.matrix4(SCNMath.identity)) }
}

// MARK: - Copying

@ObjCCategory("SCNGeometryCopying")
extension SCNGeometry {
    /// A geometry of the same shape, sharing the materials.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> SCNGeometry {
        let made = type(of: self).objCClass.object.allocated().unsafeCast(to: SCNGeometry.self)
        let (from, to) = (geometry, made.geometry)
        to.kind = from.kind
        to.width = from.width; to.height = from.height; to.length = from.length
        to.radius = from.radius; to.topRadius = from.topRadius; to.bottomRadius = from.bottomRadius
        to.segments = from.segments
        to.custom = from.custom
        to.materials = from.materials
        to.name = from.name
        return made
    }
}

@ObjCCategory("SCNMaterialCopying")
extension SCNMaterial {
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> SCNMaterial {
        let made = SCNMaterial.make(SCNMaterial.objCClass)
        let (from, to) = (material, made.material)
        to.transparency = from.transparency
        to.doubleSided = from.doubleSided
        to.cullMode = from.cullMode
        to.lightingModel = from.lightingModel
        to.name = from.name
        for (source, target) in [(from.diffuse, made.diffuse()), (from.emission, made.emission()), (from.specular, made.specular())] {
            guard let source else { continue }
            SKSupport.replace(&target.property.contents, with: source.property.contents)
            target.property.wrapS = source.property.wrapS
            target.property.wrapT = source.property.wrapT
        }
        return made
    }
}

@ObjCCategory("SCNNodeCopying")
extension SCNNode {
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> SCNNode { clone() }
}
