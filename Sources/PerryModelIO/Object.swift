import CPerryModelIO
import Glibc
import PerryObjCInterop

// MDLObject, the node of an asset's hierarchy, with its components (a
// transform, a container of children), MDLObjectContainer, MDLTransform,
// and the cameras and lights an asset may hold.

@ObjCClass("MDLObject")
open class MDLObject: NSObject {
    var nameValue = ""
    /// Components, by the name of the protocol they were set for, in order.
    var componentList: [(protocolName: String, component: NSObject)] = []
    weak var parentObject: MDLObject?
    var instanceObject: NSObject?
    var childContainer: NSObject?
    var isHidden = false

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ name: String?) { nameValue = name ?? "" }

    @ObjCMethod("components") func components() -> NSObject { NSArray.of(componentList.map(\.component)) }

    func component(named protocolName: String) -> NSObject? { componentList.first { $0.protocolName == protocolName }?.component }

    func setComponent(_ component: NSObject?, named protocolName: String) {
        componentList.removeAll { $0.protocolName == protocolName }
        if let component { componentList.append((protocolName, component)) }
    }

    @ObjCMethod("setComponent:forProtocol:") func setComponent(_ component: NSObject?, forProtocol proto: UnsafeMutableRawPointer?) {
        guard let name = Runtime.name(ofProtocol: proto) else { return }
        if name == "MDLObjectContainerComponent" { childContainer = component }
        setComponent(component, named: name)
    }

    @ObjCMethod("componentConformingToProtocol:") func component(conformingTo proto: UnsafeMutableRawPointer?) -> NSObject? {
        guard let name = Runtime.name(ofProtocol: proto) else { return nil }
        return name == "MDLObjectContainerComponent" ? children() : component(named: name)
    }

    @ObjCMethod("objectForKeyedSubscript:") func objectForKeyedSubscript(_ proto: UnsafeMutableRawPointer?) -> NSObject? {
        component(conformingTo: proto)
    }

    @ObjCMethod("setObject:forKeyedSubscript:") func setObject(_ component: NSObject?, forKeyedSubscript proto: UnsafeMutableRawPointer?) {
        setComponent(component, forProtocol: proto)
    }

    @ObjCMethod("parent") func parent() -> MDLObject? { parentObject }
    @ObjCMethod("setParent:") func setParent(_ parent: MDLObject?) { parentObject = parent }
    @ObjCMethod("instance") func instance() -> NSObject? { instanceObject }
    @ObjCMethod("setInstance:") func setInstance(_ instance: NSObject?) { instanceObject = instance }
    @ObjCMethod("hidden") func hidden() -> Bool { isHidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { isHidden = hidden }

    @ObjCMethod("path") func path() -> String { (parentObject?.path() ?? "") + "/" + nameValue }

    @ObjCMethod("objectAtPath:") func object(atPath path: String?) -> MDLObject? {
        guard let path else { return nil }
        var current: MDLObject? = self
        for component in path.split(separator: "/") {
            current = current?.childObjects.compactMap { ObjCPeers.peer(of: $0.objcObject) as? MDLObject }
                .first { $0.nameValue == component }
        }
        return current === self ? nil : current
    }

    @ObjCMethod("transform") func transform() -> NSObject? { component(named: "MDLTransformComponent") }
    @ObjCMethod("setTransform:") func setTransform(_ transform: NSObject?) { setComponent(transform, named: "MDLTransformComponent") }

    @ObjCMethod("children") func children() -> NSObject {
        if let childContainer { return childContainer }
        let container = MDLObjectContainer()
        childContainer = container
        return container
    }

    @ObjCMethod("setChildren:") func setChildren(_ children: NSObject?) { childContainer = children }

    /// The children, whatever container holds them.
    var childObjects: [NSObject] {
        guard let childContainer else { return [] }
        if let container = ObjCPeers.peer(of: childContainer.objcObject) as? MDLObjectContainer { return container.list.elements }
        return childContainer.containerObjects().map { $0.unsafeCast(to: NSArray.self).elements } ?? []
    }

    @ObjCMethod("addChild:") func addChild(_ child: NSObject?) {
        guard let child else { return }
        children().containerAdd(child)
        (ObjCPeers.peer(of: child.objcObject) as? MDLObject)?.parentObject = self
    }

    /// The local transform at `time`, identity without one.
    func localMatrix(at time: Double) -> Matrix4 {
        guard let transform = transform() else { return .identity }
        if let own = ObjCPeers.peer(of: transform.objcObject) as? MDLTransform { return own.matrixValue }
        return transform.sendMatrix().matrix
    }

    /// The bounds of this object's own geometry, in its own space.
    func ownBounds(at time: Double) -> PerryMDLBoundingBox { .empty }

    /// The bounds of this object and its children, in its parent's space.
    func bounds(at time: Double) -> PerryMDLBoundingBox {
        var box = ownBounds(at: time)
        for child in childObjects {
            if let object = ObjCPeers.peer(of: child.objcObject) as? MDLObject { box.add(object.bounds(at: time)) }
        }
        return box.transformed(localMatrix(at: time))
    }

    @ObjCMethod("boundingBoxAtTime:") func boundingBox(atTime time: Double) -> PerryMDLBoundingBox { bounds(at: time).reported }

    @ObjCMethod("enumerateChildObjectsOfClass:root:usingBlock:stopPointer:")
    func enumerateChildObjects(of cls: ObjCClass?, root: NSObject?, block: ObjCBlock?, stop: UnsafeMutablePointer<Int8>?) {
        guard let block else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int8>?) -> Void
        let invoke = block.function(as: Invoke.self)
        func visit(_ object: MDLObject) -> Bool {
            for child in object.childObjects {
                if stop?.pointee ?? 0 != 0 { return false }
                if cls.map({ child.sendIsKind(of: $0) }) ?? true { invoke(block.object, child.objcObject, stop) }
                if stop?.pointee ?? 0 != 0 { return false }
                if let peer = ObjCPeers.peer(of: child.objcObject) as? MDLObject, !visit(peer) { return false }
            }
            return true
        }
        _ = visit(self)
    }

    @ObjCMethod("description") func describe() -> String { "<\(String(describing: type(of: self))): \(nameValue)>" }
}

extension NSObject {
    @ObjCMethod("objects") func containerObjects() -> NSObject?
    @ObjCMethod("addObject:") func containerAdd(_ object: NSObject)
}

@ObjCClass("MDLObjectContainer")
open class MDLObjectContainer: NSObject {
    var list: NSMutableArray = NSMutableArray.empty()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("addObject:") func add(_ object: NSObject?) { if let object { list.add(object) } }
    @ObjCMethod("removeObject:") func remove(_ object: NSObject?) { if let object { list.removeIdentical(object) } }
    @ObjCMethod("objects") func objects() -> NSObject { NSArray.of(list.elements) }
    @ObjCMethod("count") func count() -> UInt { list.count() }

    @ObjCMethod("objectAtIndexedSubscript:") func object(atIndexedSubscript index: UInt) -> NSObject? {
        index < list.count() ? list.object(at: index) : nil
    }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func countByEnumerating(state: UnsafeMutableRawPointer?, objects: UnsafeMutableRawPointer?, count: UInt) -> UInt {
        list.sendCountByEnumerating(state: state, objects: objects, count: count)
    }
}

// MARK: - Transforms

@ObjCClass("MDLTransform")
open class MDLTransform: NSObject {
    var translationValue = SIMD3<Float>(repeating: 0)
    var rotationValue = SIMD3<Float>(repeating: 0)
    var shearValue = SIMD3<Float>(repeating: 0)
    var scaleValue = SIMD3<Float>(repeating: 1)
    var resets = false
    var times: Set<Double> = [0]

    @ObjCMethod("init") public required override init() { super.init() }


    @ObjCMethod("initWithMatrix:") public init(matrix: PerryMDLFloat4x4) {
        super.init()
        decompose(matrix.matrix)
    }

    @ObjCMethod("initWithMatrix:resetsTransform:") public init(matrix: PerryMDLFloat4x4, resetsTransform: Bool) {
        super.init()
        decompose(matrix.matrix)
        resets = resetsTransform
    }

    @ObjCMethod("initWithTransformComponent:") public init(transformComponent: NSObject?) {
        super.init()
        if let transformComponent { decompose(transformComponent.sendMatrix().matrix) }
    }

    @ObjCMethod("initWithTransformComponent:resetsTransform:") public init(transformComponent: NSObject?, resetsTransform: Bool) {
        super.init()
        if let transformComponent { decompose(transformComponent.sendMatrix().matrix) }
        resets = resetsTransform
    }

    /// Translation, then rotation about Z, Y and X, shear and scale.
    var matrixValue: Matrix4 {
        var shear = Matrix4.identity
        (shear[0, 1], shear[0, 2], shear[1, 2]) = (shearValue.x, shearValue.y, shearValue.z)
        return Matrix4.translation(translationValue) * rotationMatrix * shear * Matrix4.scale(scaleValue)
    }

    var rotationMatrix: Matrix4 {
        Matrix4.rotation(z: rotationValue.z) * Matrix4.rotation(y: rotationValue.y) * Matrix4.rotation(x: rotationValue.x)
    }

    /// Splits a matrix into its translation, rotation, shear and scale.
    func decompose(_ m: Matrix4) {
        translationValue = SIMD3(m[0, 3], m[1, 3], m[2, 3])
        let c0 = SIMD3(m[0, 0], m[1, 0], m[2, 0]), c1 = SIMD3(m[0, 1], m[1, 1], m[2, 1]), c2 = SIMD3(m[0, 2], m[1, 2], m[2, 2])
        let sx = length(c0)
        let q0 = sx > 0 ? c0 / sx : SIMD3(1, 0, 0)
        let a = dot(q0, c1)
        let c1p = c1 - a * q0
        let sy = length(c1p)
        let q1 = sy > 0 ? c1p / sy : SIMD3(0, 1, 0)
        let b = dot(q0, c2), c = dot(q1, c2)
        let c2p = c2 - b * q0 - c * q1
        var sz = length(c2p)
        var q2 = sz > 0 ? c2p / sz : cross(q0, q1)
        if dot(cross(q0, q1), q2) < 0 {
            sz = -sz
            q2 = -q2
        }
        scaleValue = SIMD3(sx, sy, sz)
        shearValue = SIMD3(sy != 0 ? a / sy : 0, sz != 0 ? b / sz : 0, sz != 0 ? c / sz : 0)
        // R = Rz Ry Rx: its third row is (-sin y, cos y sin x, cos y cos x).
        let ry = asinf(max(-1, min(1, -q0.z)))
        let rx = atan2f(q1.z, q2.z)
        let rz = atan2f(q0.y, q0.x)
        rotationValue = SIMD3(rx, ry, rz)
    }

    @ObjCMethod("setIdentity") func setIdentity() {
        translationValue = .zero
        rotationValue = .zero
        shearValue = .zero
        scaleValue = SIMD3(repeating: 1)
    }

    @ObjCMethod("matrix") func matrix() -> PerryMDLFloat4x4 { PerryMDLFloat4x4(matrixValue) }
    @ObjCMethod("setMatrix:") func setMatrix(_ matrix: PerryMDLFloat4x4) { decompose(matrix.matrix) }
    @ObjCMethod("resetsTransform") func resetsTransform() -> Bool { resets }
    @ObjCMethod("setResetsTransform:") func setResetsTransform(_ value: Bool) { resets = value }
    @ObjCMethod("minimumTime") func minimumTime() -> Double { times.min() ?? 0 }
    @ObjCMethod("maximumTime") func maximumTime() -> Double { times.max() ?? 0 }
    @ObjCMethod("keyTimes") func keyTimes() -> NSObject { NSArray.of(times.sorted().map { NSNumber.make(double: $0) }) }

    @ObjCMethod("setLocalTransform:forTime:") func setLocalTransform(_ matrix: PerryMDLFloat4x4, forTime time: Double) {
        times.insert(time)
        decompose(matrix.matrix)
    }

    @ObjCMethod("setLocalTransform:") func setLocalTransform(_ matrix: PerryMDLFloat4x4) { decompose(matrix.matrix) }
    @ObjCMethod("localTransformAtTime:") func localTransform(atTime time: Double) -> PerryMDLFloat4x4 { matrix() }

    @ObjCClassMethod("globalTransformWithObject:atTime:")
    static func globalTransform(object: NSObject?, atTime time: Double) -> PerryMDLFloat4x4 {
        var result = Matrix4.identity
        var current = object.flatMap { ObjCPeers.peer(of: $0.objcObject) as? MDLObject }
        while let node = current {
            result = node.localMatrix(at: time) * result
            if let transform = node.transform(), (ObjCPeers.peer(of: transform.objcObject) as? MDLTransform)?.resets ?? false { break }
            current = node.parentObject
        }
        return PerryMDLFloat4x4(result)
    }

    @ObjCMethod("translationAtTime:") func translation(atTime time: Double) -> PerryMDLFloat3 { PerryMDLFloat3(translationValue) }
    @ObjCMethod("rotationAtTime:") func rotation(atTime time: Double) -> PerryMDLFloat3 { PerryMDLFloat3(rotationValue) }
    @ObjCMethod("shearAtTime:") func shear(atTime time: Double) -> PerryMDLFloat3 { PerryMDLFloat3(shearValue) }
    @ObjCMethod("scaleAtTime:") func scale(atTime time: Double) -> PerryMDLFloat3 { PerryMDLFloat3(scaleValue) }
    @ObjCMethod("rotationMatrixAtTime:") func rotationMatrix(atTime time: Double) -> PerryMDLFloat4x4 { PerryMDLFloat4x4(rotationMatrix) }

    @ObjCMethod("setTranslation:forTime:") func setTranslation(_ v: PerryMDLFloat3, forTime time: Double) { times.insert(time); translationValue = v.v }
    @ObjCMethod("setRotation:forTime:") func setRotation(_ v: PerryMDLFloat3, forTime time: Double) { times.insert(time); rotationValue = v.v }
    @ObjCMethod("setShear:forTime:") func setShear(_ v: PerryMDLFloat3, forTime time: Double) { times.insert(time); shearValue = v.v }
    @ObjCMethod("setScale:forTime:") func setScale(_ v: PerryMDLFloat3, forTime time: Double) { times.insert(time); scaleValue = v.v }

    @ObjCMethod("translation") func translation() -> PerryMDLFloat3 { PerryMDLFloat3(translationValue) }
    @ObjCMethod("setTranslation:") func setTranslation(_ v: PerryMDLFloat3) { translationValue = v.v }
    @ObjCMethod("rotation") func rotation() -> PerryMDLFloat3 { PerryMDLFloat3(rotationValue) }
    @ObjCMethod("setRotation:") func setRotation(_ v: PerryMDLFloat3) { rotationValue = v.v }
    @ObjCMethod("shear") func shear() -> PerryMDLFloat3 { PerryMDLFloat3(shearValue) }
    @ObjCMethod("setShear:") func setShear(_ v: PerryMDLFloat3) { shearValue = v.v }
    @ObjCMethod("scale") func scale() -> PerryMDLFloat3 { PerryMDLFloat3(scaleValue) }
    @ObjCMethod("setScale:") func setScale(_ v: PerryMDLFloat3) { scaleValue = v.v }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLTransform {
        let copy = MDLTransform()
        (copy.translationValue, copy.rotationValue, copy.shearValue, copy.scaleValue) = (translationValue, rotationValue, shearValue, scaleValue)
        copy.resets = resets
        copy.times = times
        return copy
    }
}

// MARK: - Cameras and lights

/// A camera an asset holds: its projection's values, kept as set.
@ObjCClass("MDLCamera")
open class MDLCamera: MDLObject {
    var near: Float = 0.1
    var far: Float = 1000
    var fieldOfView: Float = 53.999996
    var aspect: Float = 1

    @ObjCMethod("nearVisibilityDistance") func nearVisibilityDistance() -> Float { near }
    @ObjCMethod("setNearVisibilityDistance:") func setNearVisibilityDistance(_ v: Float) { near = v }
    @ObjCMethod("farVisibilityDistance") func farVisibilityDistance() -> Float { far }
    @ObjCMethod("setFarVisibilityDistance:") func setFarVisibilityDistance(_ v: Float) { far = v }
    @ObjCMethod("fieldOfView") func fieldOfViewValue() -> Float { fieldOfView }
    @ObjCMethod("setFieldOfView:") func setFieldOfView(_ v: Float) { fieldOfView = v }
    @ObjCMethod("sensorAspect") func sensorAspect() -> Float { aspect }
    @ObjCMethod("setSensorAspect:") func setSensorAspect(_ v: Float) { aspect = v }

    /// A right-handed perspective projection.
    @ObjCMethod("projectionMatrix") func projectionMatrix() -> PerryMDLFloat4x4 {
        let y = 1 / tanf(fieldOfView * .pi / 360), x = y / aspect, z = far / (near - far)
        var m = Matrix4([Float](repeating: 0, count: 16))
        (m[0, 0], m[1, 1], m[2, 2], m[2, 3], m[3, 2]) = (x, y, z, z * near, -1)
        return PerryMDLFloat4x4(m)
    }
}

/// A light an asset holds.
@ObjCClass("MDLLight")
open class MDLLight: MDLObject {
    var lightTypeValue: UInt = 0

    @ObjCMethod("lightType") func lightType() -> UInt { lightTypeValue }
    @ObjCMethod("setLightType:") func setLightType(_ v: UInt) { lightTypeValue = v }
}

@ObjCClass("MDLPhysicallyPlausibleLight") open class MDLPhysicallyPlausibleLight: MDLLight {}
@ObjCClass("MDLAreaLight") open class MDLAreaLight: MDLPhysicallyPlausibleLight {}
