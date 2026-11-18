import CPerryGeometry
import Glibc
import PerryObjCInterop

// SCNSceneSource: a scene's file, for its scene or for one thing in it by
// its identifier. The file is read as SCNScene reads it; an entry is found in
// the scene it makes: an animation by its key (as a model's animations are
// named), else a node by its name. SCNTechnique is kept and draws nothing:
// the passes of a technique (a desaturation, a blur) are not run.

final class SCNSceneSourceState: ObjectState {
    var url: NSObject?
    var path: String?
    var scene: SCNScene?
}

@ObjCClass("SCNSceneSource")
open class SCNSceneSource: NSObject {
    static let states = StateTable<SCNSceneSourceState>()
    var source: SCNSceneSourceState { SCNSceneSource.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNSceneSource.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNSceneSource.objCClass.pointer)
    }

    @ObjCClassMethod("sceneSourceWithURL:options:")
    static func source(_ cls: ObjCClass, url: NSObject?, options: NSObject?) -> SCNSceneSource? {
        guard let url, let path = url.scnPath() else { return nil }
        let made = cls.object.allocated().unsafeCast(to: SCNSceneSource.self)
        (made.source.url, made.source.path) = (url, path)
        return made
    }

    @ObjCMethod("initWithURL:options:")
    func initialize(url: NSObject?, options: NSObject?) -> Self? {
        guard let url, let path = url.scnPath() else { return nil }
        (source.url, source.path) = (url, path)
        return self
    }

    @ObjCMethod("url") func url() -> NSObject? { source.url }

    /// The file's scene, read once for the entries asked of it.
    private var loaded: SCNScene? {
        if let scene = source.scene { return scene }
        source.scene = source.path.flatMap { SCNFile.scene(atPath: $0) }
        return source.scene
    }

    /// A scene of the file's own, as each asking is given.
    @ObjCMethod("sceneWithOptions:error:")
    func scene(options: NSObject?, error: UnsafeMutableRawPointer?) -> SCNScene? { source.path.flatMap { SCNFile.scene(atPath: $0) } }
    @ObjCMethod("sceneWithOptions:statusHandler:")
    func scene(options: NSObject?, statusHandler: ObjCBlock?) -> SCNScene? { source.path.flatMap { SCNFile.scene(atPath: $0) } }

    private func each(_ node: SCNNode, _ body: (SCNNode) -> Void) {
        body(node)
        for child in node.node.children { each(child.unsafeCast(to: SCNNode.self), body) }
    }

    @ObjCMethod("entryWithIdentifier:withClass:")
    func entry(identifier: String, ofClass cls: UnsafeMutableRawPointer?) -> NSObject? {
        guard let root = loaded?.rootNode() else { return nil }
        var found: NSObject?
        each(root) { node in
            guard found == nil, let kept = node.node.animationPlayers[identifier] else { return }
            found = kept.is(SCNAnimationPlayer.self) ? kept.unsafeCast(to: SCNAnimationPlayer.self).player.animation : kept
        }
        return found ?? root.childNode(withName: identifier, recursively: true)
    }

    /// The identifiers of the file's animations, whatever the class asked for.
    @ObjCMethod("identifiersOfEntriesWithClass:")
    func identifiers(ofClass cls: UnsafeMutableRawPointer?) -> NSObject {
        var keys: [String] = []
        if let root = loaded?.rootNode() { each(root) { keys += $0.node.animationKeys } }
        return NSMutableArray.of(keys.compactMap { key in key.objCArgument().map { NSObject(objcObject: $0, ownership: .retain) } })
    }
}

final class SCNTechniqueState: ObjectState {
    var dictionary: NSObject?
    var values: [String: NSObject] = [:]
}

@ObjCClass("SCNTechnique")
open class SCNTechnique: NSObject {
    static let states = StateTable<SCNTechniqueState>()
    var technique: SCNTechniqueState { SCNTechnique.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        SCNTechnique.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SCNTechnique.objCClass.pointer)
    }

    @ObjCClassMethod("techniqueWithDictionary:")
    static func technique(_ cls: ObjCClass, dictionary: NSObject?) -> SCNTechnique? {
        guard let dictionary else { return nil }
        let made = cls.object.allocated().unsafeCast(to: SCNTechnique.self)
        made.technique.dictionary = dictionary
        return made
    }

    @ObjCClassMethod("techniqueBySequencingTechniques:")
    static func technique(_ cls: ObjCClass, sequencing techniques: NSObject?) -> SCNTechnique { cls.object.allocated().unsafeCast(to: SCNTechnique.self) }

    @ObjCMethod("dictionaryRepresentation") func dictionaryRepresentation() -> NSObject? { technique.dictionary }
    @ObjCMethod("setValue:forKey:") func setValue(_ value: NSObject?, forKey key: String) { technique.values[key] = value }
    @ObjCMethod("valueForKey:") func value(forKey key: String) -> NSObject? { technique.values[key] }
    @ObjCMethod("setObject:forKeyedSubscript:") func setObject(_ value: NSObject?, forKeyedSubscript key: String) { technique.values[key] = value }
    @ObjCMethod("objectForKeyedSubscript:") func object(forKeyedSubscript key: String) -> NSObject? { technique.values[key] }
    @ObjCMethod("handleBindingOfSymbol:usingBlock:") func handleBinding(ofSymbol symbol: String, using block: ObjCBlock?) {}
}

@ObjCCategory("SCNViewTechnique")
extension SCNView {
    @ObjCMethod("technique") func technique() -> NSObject? { SCNExtras.views[objcObject].objects["technique"] }
    @ObjCMethod("setTechnique:") func setTechnique(_ technique: NSObject?) { SCNExtras.views[objcObject].objects["technique"] = technique }
}

@ObjCCategory("SCNGeometryAnimations")
extension SCNGeometry {
    // A geometry's shader modifiers are kept; its sources and elements are not given back.
    @ObjCMethod("shaderModifiers") func shaderModifiers() -> NSObject? { SCNKept.geometries[objcObject].objects["shaderModifiers"] }
    @ObjCMethod("setShaderModifiers:") func setShaderModifiers(_ modifiers: NSObject?) { SCNKept.geometries[objcObject].objects["shaderModifiers"] = modifiers }
    // The semantic is not looked at: it may be a constant this SceneKit does not have.
    @ObjCMethod("geometrySourcesForSemantic:") func geometrySources(forSemantic semantic: UnsafeMutableRawPointer?) -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("geometrySources") func geometrySources() -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("geometryElements") func geometryElements() -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("geometryElementCount") func geometryElementCount() -> Int { geometry.mesh.elements.count }
    // A geometry's Core Animation animations (of a shader's values) are not played.
    @ObjCMethod("addAnimation:forKey:") func addAnimation(_ animation: NSObject?, forKey key: String?) {}
    @ObjCMethod("removeAnimationForKey:") func removeAnimation(forKey key: String) {}
    @ObjCMethod("removeAllAnimations") func removeAllAnimations() {}
}
