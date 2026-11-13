import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's scene files (.scn): an NSKeyedArchiver archive, a binary
// property list whose objects are SceneKit's own classes with their own keys
// (nodes with their transforms as raw floats, geometry sources and elements
// as raw bytes, materials with colours or image paths). Rather than decode
// the archive into the classes through an unarchiver, the loader reads the
// archive's property list and builds the scene from it: nodes, cameras,
// parametric and mesh geometry, materials with their colours and pictures,
// and the files that reference nodes refer to. What the scene has beyond
// that (lights, particles, physics, actions, animations, skinning) is
// counted, and listed when PERRY_SCENEKIT_TRACE is set.

extension NSBundle {
    @ObjCMethod("resourcePath") func resourcePath() -> String?
}

enum SCNFile {
    /// The parsed archives by path: apps load a scene's file again for each
    /// copy of what is in it.
    nonisolated(unsafe) private static var archives: [String: SCNArchive] = [:]
    nonisolated(unsafe) static var images: [String: UIImage] = [:]

    /// The scene in the main bundle at `name`, in `directory` if given.
    static func scene(named name: String, inDirectory directory: String?) -> SCNScene? {
        for path in candidates(named: name, inDirectory: directory) where access(path, R_OK) == 0 {
            if let scene = scene(atPath: path) { return scene }
        }
        return nil
    }

    /// Where a file named `name` in `directory` may be: in the main bundle, or as the path says. A
    /// directory made absolute by the current folder (as URL(fileURLWithPath:) makes it) is taken
    /// back to the bundle's.
    static func candidates(named name: String, inDirectory directory: String?) -> [String] {
        var list: [String] = []
        if name.hasPrefix("/") { list.append(name) }
        var relative = directory
        if let directory, directory.hasPrefix("/") {
            list.append("\(directory)/\(name)")
            var buffer = [CChar](repeating: 0, count: 4096)
            if getcwd(&buffer, buffer.count) != nil {
                let current = String(cString: buffer) + "/"
                relative = directory.hasPrefix(current) ? String(directory.dropFirst(current.count)) : nil
            } else {
                relative = nil
            }
        }
        if let base = NSBundle.main().resourcePath() {
            if let relative { list.append("\(base)/\(relative)/\(name)") }
            list.append("\(base)/\(name)")
        }
        return list
    }

    static func scene(atPath path: String) -> SCNScene? {
        guard let archive = archive(atPath: path) else { return nil }
        return SCNSceneBuilder(archive).scene()
    }

    static func archive(atPath path: String) -> SCNArchive? {
        if let known = archives[path] { return known }
        guard let bytes = read(path), let archive = SCNArchive(bytes: bytes, path: path) else { return nil }
        archives[path] = archive
        return archive
    }

    /// The particle system a .scnp file holds, found in the main bundle.
    static func particleSystem(named name: String, inDirectory directory: String?) -> SCNParticleSystem? {
        for path in candidates(named: name, inDirectory: directory) where access(path, R_OK) == 0 {
            if let archive = archive(atPath: path), let root = archive.top["root"] { return SCNSceneBuilder(archive).particleSystem(root) }
        }
        return nil
    }

    static func read(_ path: String) -> [UInt8]? {
        guard let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        fseek(file, 0, SEEK_END)
        let size = ftell(file)
        guard size > 0 else { return nil }
        fseek(file, 0, SEEK_SET)
        var bytes = [UInt8](repeating: 0, count: size)
        guard fread(&bytes, 1, size, file) == size else { return nil }
        return bytes
    }
}

/// An NSKeyedArchiver archive's property list, read for its values.
final class SCNArchive {
    typealias Plist = KeyedNib.Plist
    let objects: [Plist]
    let top: [String: Plist]
    /// The folder the file is in, which the pictures and other files it
    /// names are relative to.
    let directory: String

    init?(bytes: [UInt8], path: String) {
        guard case .dictionary(let root)? = KeyedNib.parse(bytes), case .array(let objects)? = root["$objects"],
              case .dictionary(let top)? = root["$top"] else { return nil }
        self.objects = objects
        self.top = top
        directory = path.lastIndex(of: "/").map { String(path[..<$0]) } ?? "."
    }

    /// A reference followed to what it refers to.
    func resolve(_ plist: Plist?) -> Plist? {
        if case .uid(let index)? = plist { return objects.indices.contains(index) ? objects[index] : nil }
        return plist
    }

    func identifier(_ plist: Plist?) -> Int? {
        if case .uid(let index)? = plist { return index }
        return nil
    }

    func dictionary(_ plist: Plist?) -> [String: Plist]? {
        if case .dictionary(let value)? = resolve(plist) { return value }
        return nil
    }

    func className(_ plist: Plist?) -> String? {
        guard let value = dictionary(plist), case .uid(let index)? = value["$class"],
              case .dictionary(let described)? = resolve(.uid(index)), case .string(let name)? = described["$classname"] else { return nil }
        return name
    }

    func double(_ plist: Plist?) -> Double? {
        switch resolve(plist) {
        case .real(let value)?: return value
        case .integer(let value)?: return Double(value)
        case .bool(let value)?: return value ? 1 : 0
        default: return nil
        }
    }

    func int(_ plist: Plist?) -> Int? { double(plist).map { Int($0) } }
    func bool(_ plist: Plist?) -> Bool? { double(plist).map { $0 != 0 } }

    func string(_ plist: Plist?) -> String? {
        if case .string(let value)? = resolve(plist), value != "$null" { return value }
        return nil
    }

    /// Whether the key holds an object, not the archive's null.
    func has(_ plist: Plist?) -> Bool {
        guard let value = resolve(plist) else { return false }
        if case .string("$null") = value { return false }
        return true
    }

    /// Raw bytes: data, or an NSData's.
    func bytes(_ plist: Plist?) -> [UInt8]? {
        switch resolve(plist) {
        case .data(let value)?: return value
        case .dictionary(let value)?:
            // A mutable NSData keeps its bytes under NS.bytes, an immutable one (as Xcode's compiled scenes have) under NS.data.
            for key in ["NS.bytes", "NS.data"] { if case .data(let inner)? = resolve(value[key]) { return inner } }
        default: break
        }
        return nil
    }

    func floats(_ plist: Plist?) -> [Float] {
        guard let bytes = bytes(plist) else { return [] }
        return (0..<bytes.count / 4).map { index in
            bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: index * 4, as: Float.self) }
        }
    }

    /// An NSArray's elements, as references.
    func list(_ plist: Plist?) -> [Plist] {
        guard case .dictionary(let value)? = resolve(plist) else { return [] }
        if case .array(let items)? = value["NS.objects"] { return items }
        // A short collection keeps its elements under NS.object.0, NS.object.1...
        var items: [Plist] = []
        while let item = value["NS.object.\(items.count)"] { items.append(item) }
        return items
    }

    /// An NSDictionary's string keys and values.
    func entries(_ plist: Plist?) -> [(key: String, value: Plist)] {
        guard let value = dictionary(plist) else { return [] }
        if case .array(let keys)? = value["NS.keys"], case .array(let items)? = value["NS.objects"] {
            return zip(keys, items).compactMap { key, item in string(key).map { ($0, item) } }
        }
        var pairs: [(key: String, value: Plist)] = []
        while let key = value["NS.key.\(pairs.count)"], let item = value["NS.object.\(pairs.count)"], let name = string(key) { pairs.append((name, item)) }
        return pairs
    }

    /// An NSColor's red, green, blue and alpha: its components are text.
    func color(_ plist: Plist?) -> (Double, Double, Double, Double)? {
        guard let value = dictionary(plist) else { return nil }
        func numbers(_ key: String) -> [Double] {
            guard let data = bytes(value[key]) else { return [] }
            return String(decoding: data.filter { $0 != 0 }, as: UTF8.self).split(separator: " ").compactMap { Double($0) }
        }
        let components = numbers("NSComponents")
        for source in [components, numbers("NSRGB")] where source.count >= 3 {
            return (source[0], source[1], source[2], source.count > 3 ? source[3] : 1)
        }
        for source in [components, numbers("NSWhite")] where !source.isEmpty {
            return (source[0], source[0], source[0], source.count > 1 ? source[1] : 1)
        }
        return nil
    }
}

/// One scene's building from its archive.
final class SCNSceneBuilder {
    private let archive: SCNArchive
    private let depth: Int
    private var materials: [Int: SCNMaterial] = [:]
    private var geometries: [Int: SCNGeometry] = [:]
    /// Nodes by their place in the archive, which a skinner's bones are named by, and the skinners to give theirs.
    private var nodes: [Int: SCNNode] = [:]
    private var skinners: [(node: SCNNode, described: [String: SCNArchive.Plist])] = []
    /// What the file has that is not built yet, by kind.
    private var skipped: [String: Int] = [:]

    init(_ archive: SCNArchive, depth: Int = 0) {
        self.archive = archive
        self.depth = depth
    }

    func scene() -> SCNScene? {
        guard let described = archive.dictionary(archive.top["root"]), archive.className(archive.top["root"]) == "SCNScene" else { return nil }
        let scene = SCNScene.make(SCNScene.objCClass)
        if let root = node(described["rootNode"]) { scene.scene.root = root }
        // The bones are in the tree now.
        for (node, skinner) in skinners { attachSkinner(skinner, to: node) }
        if let contents = propertyContents(described["background"]) {
            withExtendedLifetime(contents) { SKSupport.replace(&scene.background().property.contents, with: contents.objcObject) }
        }
        if getenv("PERRY_SCENEKIT_TRACE") != nil, !skipped.isEmpty {
            let list = skipped.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            let line = "perry: SceneKit: \(archive.directory): not built: \(list)\n"
            line.withCString { _ = write(2, $0, strlen($0)) }
        }
        return scene
    }

    private func skip(_ what: String) { skipped[what, default: 0] += 1 }

    // MARK: Nodes

    private func node(_ reference: SCNArchive.Plist?) -> SCNNode? {
        guard let described = archive.dictionary(reference), depth < 16 else { return nil }
        let made = SCNNode.make(SCNNode.objCClass)
        if let key = archive.identifier(reference) { nodes[key] = made }
        let state = made.node
        state.name = archive.string(described["name"])
        state.hidden = archive.bool(described["hidden"]) ?? false
        state.opacity = CGFloat(archive.double(described["opacity"]) ?? 1)

        let position = archive.floats(described["position"]), scale = archive.floats(described["scale"])
        if position.count >= 3 { state.position = SCNVector3(x: position[0], y: position[1], z: position[2]) }
        if scale.count >= 3 { state.scale = SCNVector3(x: scale[0], y: scale[1], z: scale[2]) }
        let orientation = archive.floats(described["orientation"]), euler = archive.floats(described["eulerAngles"])
        let rotation = archive.floats(described["rotation"])
        if orientation.count >= 4, orientation.contains(where: { $0 != 0 }) {
            state.rotation = SCNMath.normalized((orientation[0], orientation[1], orientation[2], orientation[3]))
        } else if euler.count >= 3 {
            state.rotation = SCNMath.quaternion(euler: SCNVector3(x: euler[0], y: euler[1], z: euler[2]))
        } else if rotation.count >= 4 {
            state.rotation = SCNMath.quaternion(axis: SCNVector3(x: rotation[0], y: rotation[1], z: rotation[2]), angle: rotation[3])
        }
        let pivot = archive.floats(described["pivot"])
        if pivot.count == 16 { state.pivot = pivot }

        if archive.has(described["geometry"]) { state.geometry = geometry(described["geometry"]) }
        if archive.has(described["camera"]) { state.camera = camera(described["camera"]) }
        if archive.has(described["light"]) { state.light = light(described["light"]) }
        if archive.has(described["particleSystem"]) {
            for item in archive.list(described["particleSystem"]) { if let system = particleSystem(item) { state.particleSystems.append(system) } }
        }
        if archive.has(described["animation-players"]) {
            // Each player has the animation under the key of the same place, and starts playing.
            let keys = archive.list(described["animation-keys"]).map { archive.string($0) }
            let animations = archive.entries(described["animations"])
            for (index, item) in archive.list(described["animation-players"]).enumerated() where index < keys.count {
                guard let key = keys[index] else { continue }
                let player = SCNAnimationPlayer.objCClass.object.allocated().unsafeCast(to: SCNAnimationPlayer.self)
                if let found = animations.first(where: { $0.key == key }), let animation = animation(found.value) { player.player.animation = animation }
                if let details = archive.dictionary(item) {
                    player.player.speed = CGFloat(archive.double(details["speed"]) ?? 1)
                    player.player.blendFactor = CGFloat(archive.double(details["weight"]) ?? 1)
                    player.player.paused = archive.bool(details["paused"]) ?? false
                }
                player.player.playing = true
                made.addAnimationPlayer(player, forKey: key)
            }
        }
        if archive.has(described["actions"]) {
            // A node's actions start running when it is loaded.
            let keys = archive.list(described["action-keys"]).map { archive.string($0) }
            for (index, item) in archive.list(described["actions"]).enumerated() {
                guard let built = action(item) else { continue }
                state.running.append(SCNRunning(key: index < keys.count ? keys[index] : nil, action: built, completion: nil))
            }
        }
        if let skinner = archive.dictionary(described["skinner"]) { skinners.append((made, skinner)) }
        if archive.has(described["physicsBody"]) { state.physicsBody = physicsBody(described["physicsBody"]) }
        for key in ["physicsField", "morpher", "constraints"]
        where archive.has(described[key]) { skip(key) }

        for child in archive.list(described["childNodes"]) {
            if let built = node(child) { made.addChildNode(built) }
        }
        if archive.className(reference) == "SCNReferenceNode" { addReferenced(to: made, described) }
        return made
    }

    /// The nodes of the file a reference node refers to, as its children.
    private func addReferenced(to node: SCNNode, _ described: [String: SCNArchive.Plist]) {
        guard let url = archive.dictionary(described["referenceURL"]), let relative = archive.string(url["NS.relative"]) else { return }
        let path = relative.hasPrefix("/") ? relative : "\(archive.directory)/\(relative)"
        guard let other = SCNFile.archive(atPath: path), let scene = SCNSceneBuilder(other, depth: depth + 1).scene() else { return }
        for child in scene.rootNode().node.children.map({ $0.unsafeCast(to: SCNNode.self) }) {
            child.removeFromParentNode()
            node.addChildNode(child)
        }
    }

    private func camera(_ reference: SCNArchive.Plist?) -> SCNCamera? {
        guard let described = archive.dictionary(reference) else { return nil }
        let made = SCNCamera.make(SCNCamera.objCClass)
        let state = made.camera
        state.fieldOfView = CGFloat(archive.double(described["fov"]) ?? 60)
        state.zNear = archive.double(described["zNear"]) ?? 1
        state.zFar = archive.double(described["zFar"]) ?? 100
        state.orthographic = archive.bool(described["usesOrthographicProjection"]) ?? false
        state.orthographicScale = archive.double(described["orthographicScale"]) ?? 1
        state.horizontal = archive.int(described["projectionDirection"]) == 1
        return made
    }

    /// An animation a file keeps: a group of keyframed channels, each a transform over time for a node below the player's.
    private func animation(_ reference: SCNArchive.Plist?) -> SCNAnimation? {
        let wrapper = Dictionary(archive.entries(reference).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard archive.string(wrapper["class"]) == "group" else { skip("animation of another kind"); return nil }
        let group = Dictionary(archive.entries(wrapper["animation"]).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let made = SCNAnimation.objCClass.object.allocated().unsafeCast(to: SCNAnimation.self)
        let state = made.animation
        state.duration = archive.double(group["duration"]) ?? 0
        state.repeatCount = CGFloat(archive.double(group["repeatCount"]) ?? 0)
        state.removedOnCompletion = archive.bool(group["removeOnCompletion"]) ?? true
        state.fadeIn = archive.double(group["fadeInDuration"]) ?? 0
        state.fadeOut = archive.double(group["fadeOutDuration"]) ?? 0
        state.autoreverses = archive.bool(group["autoreverses"]) ?? false
        for item in archive.list(group["channels"]) {
            let channel = Dictionary(archive.entries(item).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            let target = archive.list(channel["targetPath"])
            guard target.count == 2, let path = archive.string(target[0]), archive.string(target[1]) == "transform" else { skip("animated property"); continue }
            let animated = Dictionary(archive.entries(channel["animation"]).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            let controller = Dictionary(archive.entries(animated["keyframeController"]).map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            guard let timeBytes = archive.bytes(controller["keytimes-data"]), let valueBytes = archive.bytes(controller["values-data"]) else { continue }
            // Times are big-endian doubles, values big-endian floats: a matrix to a time.
            let count = timeBytes.count / 8
            guard count > 0, valueBytes.count >= count * 64 else { continue }
            func double(_ at: Int) -> Double { Double(bitPattern: timeBytes.withUnsafeBytes { UInt64(bigEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt64.self)) }) }
            func float(_ at: Int) -> Float { Float(bitPattern: valueBytes.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt32.self)) }) }
            let times = (0..<count).map { double($0 * 8) }
            let keys = (0..<count).map { key in SCNMath.decompose((0..<16).map { float(key * 64 + $0 * 4) }) }
            let names = path.split(separator: "/").map(String.init)
            state.channels.append(SCNChannel(path: names, times: times, keys: keys))
            if state.duration <= 0 { state.duration = times.last ?? 0 }
        }
        return made
    }

    func particleSystem(_ reference: SCNArchive.Plist?) -> SCNParticleSystem? {
        guard let described = archive.dictionary(reference), archive.className(reference) == "SCNParticleSystem" else { return nil }
        let made = SCNParticleSystem.make(SCNParticleSystem.objCClass)
        made.system.values["birthRate"] = archive.double(described["birthRate"]) ?? 1
        made.system.values["emissionDuration"] = archive.double(described["emissionDuration"]) ?? 1
        made.system.values["loops"] = (archive.bool(described["loops"]) ?? true) ? 1 : 0
        return made
    }

    /// Gives `node` the skinner a file describes: its bones, found among the nodes, with their weights.
    private func attachSkinner(_ described: [String: SCNArchive.Plist], to node: SCNNode) {
        let made = SCNSkinner.objCClass.object.allocated().unsafeCast(to: SCNSkinner.self)
        let state = made.skinner
        let boneReferences = archive.list(described["bones"])
        state.bones = boneReferences.compactMap { archive.identifier($0).flatMap { nodes[$0] } }
        guard state.bones.count == boneReferences.count else { skip("skinner with bones elsewhere"); return }
        // A bone's inverse bind transform is named by its place, the first with none.
        state.inverseBind = (0..<state.bones.count).map { index in
            let floats = archive.floats(described[index == 0 ? "baseGeometryBindTransform" : "baseGeometryBindTransform-\(index)"])
            return floats.count == 16 ? floats : SCNMath.identity
        }
        if let key = archive.identifier(described["skeleton"]) { state.skeleton = nodes[key] }
        if let weights = source(described["boneWeights"]), let indices = source(described["boneIndices"]) {
            let n = weights.components
            state.influences = n
            state.weights = (0..<weights.count * n).map { weights.value($0 / n, $0 % n) }
            // Indices are whole numbers, not the fractions a normalised source reads as.
            state.indices = (0..<indices.count * n).map { i in
                let at = indices.offset + (i / n) * indices.stride + (i % n) * indices.bytesPerComponent
                guard at + indices.bytesPerComponent <= indices.data.count else { return 0 }
                return indices.data.withUnsafeBytes { bytes in
                    indices.bytesPerComponent == 1 ? UInt16(bytes[at]) : bytes.loadUnaligned(fromByteOffset: at, as: UInt16.self)
                }
            }
        }
        node.node.skinner = made
    }

    private func action(_ reference: SCNArchive.Plist?) -> SCNAction? {
        guard let described = archive.dictionary(reference), let kind = archive.className(reference) else { return nil }
        let duration = archive.double(described["_duration"]) ?? 0
        let made: SCNAction
        switch kind {
        case "SCNActionGroup": made = SCNAction.make(.group(archive.list(described["_actions"]).compactMap { action($0) }))
        case "SCNActionSequence": made = SCNAction.make(.sequence(archive.list(described["_actions"]).compactMap { action($0) }))
        case "SCNActionWait": made = SCNAction.make(.wait, duration: duration)
        case "SCNActionRepeat":
            guard let inner = action(described["_repeatedAction"]) else { return nil }
            made = SCNAction.make(archive.bool(described["_forever"]) == true ? .forever(inner) : .repeatCount(inner, archive.int(described["_timesToRepeat"]) ?? 1))
        case "SCNActionRotate":
            let relative = archive.bool(described["_isRelative"]) ?? true
            if archive.bool(described["_isAxisAngle"]) == true {
                let axis = archive.floats(described["_axisRot"])
                guard axis.count >= 4 else { return nil }
                made = SCNAction.make(.rotateAxis(axis: SCNVector3(x: axis[0], y: axis[1], z: axis[2]), angle: axis[3], by: relative), duration: duration)
            } else {
                let angles = SCNVector3(x: Float(archive.double(described["_rotX"]) ?? 0), y: Float(archive.double(described["_rotY"]) ?? 0),
                                        z: Float(archive.double(described["_rotZ"]) ?? 0))
                made = SCNAction.make(.rotateEuler(angles, by: relative, shortest: archive.bool(described["_isUnitArc"]) ?? false), duration: duration)
            }
        default:
            skip(kind)
            return nil
        }
        made.action.timing = archive.int(described["_timingMode"]) ?? 0
        return made
    }

    /// A body a file gives a node: its masks and surface, and the shape it names if it is not the node's own.
    private func physicsBody(_ reference: SCNArchive.Plist?) -> SCNPhysicsBody? {
        guard let described = archive.dictionary(reference) else { return nil }
        let made = SCNPhysicsBody.objCClass.object.allocated().unsafeCast(to: SCNPhysicsBody.self)
        let state = made.body
        state.type = archive.int(described["type"]) ?? 1
        state.categoryBitMask = archive.int(described["categoryBitMask"]) ?? 1
        state.collisionBitMask = archive.int(described["collisionBitMask"]) ?? -1
        state.contactTestBitMask = archive.int(described["contactTestBitMask"]) ?? 0
        state.mass = CGFloat(archive.double(described["mass"]) ?? 1)
        state.friction = CGFloat(archive.double(described["friction"]) ?? 0.5)
        state.restitution = CGFloat(archive.double(described["restitution"]) ?? 0.5)
        state.damping = CGFloat(archive.double(described["damping"]) ?? 0.1)
        state.angularDamping = CGFloat(archive.double(described["angularDamping"]) ?? 0.1)
        state.affectedByGravity = !(archive.bool(described["ignoreGravity"]) ?? false)
        if archive.bool(described["isDefaultShape"]) != true, let shape = archive.dictionary(described["physicsShape"]),
           archive.has(shape["referenceObject"]), let geometry = geometry(shape["referenceObject"]) {
            let made = SCNPhysicsShape.objCClass.object.allocated().unsafeCast(to: SCNPhysicsShape.self)
            made.shape.source = geometry
            state.shape = made
        }
        return made
    }

    private func light(_ reference: SCNArchive.Plist?) -> SCNLight? {
        guard let described = archive.dictionary(reference) else { return nil }
        let made = SCNLight.make(SCNLight.objCClass)
        let state = made.light
        state.type = archive.string(described["type"]) ?? "omni"
        state.intensity = CGFloat(archive.double(described["intensity"]) ?? 1000)
        state.temperature = CGFloat(archive.double(described["temperature"]) ?? 6500)
        state.castsShadow = archive.bool(described["castsShadow"]) ?? false
        state.name = archive.string(described["name"])
        state.attenuationStart = CGFloat(archive.double(described["attenuationStartDistance"]) ?? 0)
        state.attenuationEnd = CGFloat(archive.double(described["attenuationEndDistance"]) ?? 0)
        state.attenuationFalloff = CGFloat(archive.double(described["attenuationFalloffExponent"]) ?? 2)
        state.spotInner = CGFloat(archive.double(described["spotInnerAngle"]) ?? 0)
        state.spotOuter = CGFloat(archive.double(described["spotOuterAngle"]) ?? 45)
        // The colour is four floats; a pre-iOS 10 file's is an NSColor.
        let components = archive.floats(described["scncolor"])
        let color = components.count >= 3 ? UIColor.rgb(CGFloat(components[0]), CGFloat(components[1]), CGFloat(components[2]), 1)
            : UIColor.gray(1)
        withExtendedLifetime(color) { SKSupport.replace(&state.color, with: color.objcObject) }
        return made
    }

    // MARK: Materials

    private func material(_ reference: SCNArchive.Plist) -> SCNMaterial? {
        let key = archive.identifier(reference)
        if let key, let known = materials[key] { return known }
        guard let described = archive.dictionary(reference) else { return nil }
        let made = SCNMaterial.make(SCNMaterial.objCClass)
        for (name, property) in [("diffuse", made.diffuse()), ("emission", made.emission()), ("specular", made.specular())] {
            if let contents = propertyContents(described[name]) {
                withExtendedLifetime(contents) { SKSupport.replace(&property.property.contents, with: contents.objcObject) }
            }
            if let wrapped = archive.dictionary(described[name]) {
                property.property.wrapS = archive.int(wrapped["wrapS"]) ?? 1
                property.property.wrapT = archive.int(wrapped["wrapT"]) ?? 1
            }
        }
        made.material.name = archive.string(described["name"])
        made.material.transparency = CGFloat(archive.double(described["transparency"]) ?? 1)
        made.material.doubleSided = archive.bool(described["doubleSided"]) ?? false
        made.material.cullMode = archive.int(described["cullMode"]) ?? 0
        made.material.lightingModel = archive.string(described["lightingModelName"])
        if let key { materials[key] = made }
        return made
    }

    /// A material property's picture, or its colour: a UIImage or a UIColor.
    private func propertyContents(_ reference: SCNArchive.Plist?) -> NSObject? {
        guard let described = archive.dictionary(reference) else { return nil }
        if archive.has(described["image"]) {
            for (key, value) in archive.entries(described["image"]) where key == "path" {
                guard let relative = archive.string(value) else { continue }
                // A source scene's pictures are beside it; a compiled scene's are named from the bundle.
                var path = relative.hasPrefix("/") ? relative : "\(archive.directory)/\(relative)"
                if access(path, R_OK) != 0, let base = NSBundle.main().resourcePath(), access("\(base)/\(relative)", R_OK) == 0 {
                    path = "\(base)/\(relative)"
                }
                if let known = SCNFile.images[path] { return known }
                if let image = UIImage.image(UIImage.objCClass, contentsOfFile: path) {
                    SCNFile.images[path] = image
                    return image
                }
            }
        }
        guard let rgba = archive.color(described["color"]) else { return nil }
        return UIColor.rgb(CGFloat(rgba.0), CGFloat(rgba.1), CGFloat(rgba.2), CGFloat(rgba.3))
    }

    // MARK: Geometry

    private func geometry(_ reference: SCNArchive.Plist?) -> SCNGeometry? {
        let key = archive.identifier(reference)
        if let key, let known = geometries[key] { return known }
        guard let described = archive.dictionary(reference), let kind = archive.className(reference) else { return nil }
        func number(_ name: String, _ fallback: Double = 1) -> CGFloat { CGFloat(archive.double(described[name]) ?? fallback) }
        let made: SCNGeometry
        switch kind {
        case "SCNBox":
            made = SCNBox.box(SCNBox.objCClass, width: number("boxwidth"), height: number("boxheight"), length: number("boxlength"), chamferRadius: 0)
        case "SCNSphere":
            let sphere = SCNSphere.sphere(SCNSphere.objCClass, radius: number("sphereradius", 0.5))
            sphere.geometry.segments = archive.int(described["spheresegmentCount"]) ?? 48
            made = sphere
        case "SCNPlane":
            made = SCNPlane.plane(SCNPlane.objCClass, width: number("width"), height: number("height"))
        case "SCNCylinder":
            let cylinder = SCNCylinder.cylinder(SCNCylinder.objCClass, radius: number("cylinderradius", 0.5), height: number("cylinderheight"))
            cylinder.geometry.segments = archive.int(described["cylinderradialSegmentCount"]) ?? 48
            made = cylinder
        case "SCNGeometry":
            let custom = SCNGeometry.objCClass.object.allocated().unsafeCast(to: SCNGeometry.self)
            custom.geometry.kind = .custom
            custom.geometry.custom = mesh(described)
            made = custom
        default:
            skip(kind)
            return nil
        }
        made.geometry.name = archive.string(described["name"])
        made.geometry.materials = archive.list(described["materials"]).compactMap { material($0) }
        if let key { geometries[key] = made }
        return made
    }

    /// A geometry source: its bytes and how to read a number from them.
    private struct Source {
        var data: [UInt8]
        var stride: Int, offset: Int, components: Int, bytesPerComponent: Int, count: Int
        var float: Bool

        func value(_ vector: Int, _ component: Int) -> Float {
            let at = offset + vector * stride + component * bytesPerComponent
            guard component < components, at >= 0, at + bytesPerComponent <= data.count else { return 0 }
            return data.withUnsafeBytes { bytes in
                switch (float, bytesPerComponent) {
                case (true, 4): return bytes.loadUnaligned(fromByteOffset: at, as: Float.self)
                case (false, 2): return Float(bytes.loadUnaligned(fromByteOffset: at, as: Int16.self)) / 32767
                case (false, 1): return Float(bytes.loadUnaligned(fromByteOffset: at, as: Int8.self)) / 127
                default: return 0
                }
            }
        }
    }

    private func source(_ reference: SCNArchive.Plist?) -> Source? {
        guard let first = archive.list(reference).first, let described = archive.dictionary(first), let data = archive.bytes(described["data"]) else { return nil }
        let components = archive.int(described["componentsPerVector"]) ?? 3, bytes = archive.int(described["bytesPerComponent"]) ?? 4
        return Source(data: data, stride: archive.int(described["dataStride"]) ?? components * bytes, offset: archive.int(described["dataOffset"]) ?? 0,
                      components: components, bytesPerComponent: bytes, count: archive.int(described["vectorCount"]) ?? 0,
                      float: archive.bool(described["floatComponents"]) ?? true)
    }

    /// The triangles of a geometry's elements, a run each; elements that are
    /// not triangles are empty runs, so the materials still line up.
    private func mesh(_ described: [String: SCNArchive.Plist]) -> SCNMesh {
        var mesh = SCNMesh()
        guard let positions = source(described["kGeometrySourceSemanticVertex"]) else {
            if getenv("PERRY_SCENEKIT_TRACE") != nil {
                let line = "perry: SceneKit: a geometry has no vertex source: keys \(described.keys.sorted())\n"
                line.withCString { _ = write(2, $0, strlen($0)) }
            }
            return mesh
        }
        let normals = source(described["kGeometrySourceSemanticNormal"]), coordinates = source(described["kGeometrySourceSemanticTexcoord"])
        for reference in archive.list(described["elements"]) {
            let first = mesh.vertices.count / 8
            if let element = archive.dictionary(reference) {
                let indices = elementIndices(element)
                func point(_ index: Int) -> (Float, Float, Float) { (positions.value(index, 0), positions.value(index, 1), positions.value(index, 2)) }
                func triangle(_ a: Int, _ b: Int, _ c: Int) {
                    let p = [point(a), point(b), point(c)]
                    // Without normals, the triangle's own.
                    let u = (p[1].0 - p[0].0, p[1].1 - p[0].1, p[1].2 - p[0].2), v = (p[2].0 - p[0].0, p[2].1 - p[0].1, p[2].2 - p[0].2)
                    var face = (u.1 * v.2 - u.2 * v.1, u.2 * v.0 - u.0 * v.2, u.0 * v.1 - u.1 * v.0)
                    let length = (face.0 * face.0 + face.1 * face.1 + face.2 * face.2).squareRoot()
                    if length > 0 { face = (face.0 / length, face.1 / length, face.2 / length) }
                    for (corner, index) in [a, b, c].enumerated() {
                        let n = normals.map { ($0.value(index, 0), $0.value(index, 1), $0.value(index, 2)) } ?? face
                        let t = coordinates.map { ($0.value(index, 0), $0.value(index, 1)) } ?? (0, 0)
                        mesh.vertices.append(contentsOf: [p[corner].0, p[corner].1, p[corner].2, n.0, n.1, n.2, t.0, t.1])
                        mesh.sources.append(Int32(index))
                    }
                }
                switch archive.int(element["primitiveType"]) ?? 0 {
                case 0:
                    for i in stride(from: 0, to: indices.count - 2, by: 3) { triangle(indices[i], indices[i + 1], indices[i + 2]) }
                case 1:
                    if indices.count >= 3 {
                        for i in 0..<indices.count - 2 {
                            if i % 2 == 0 { triangle(indices[i], indices[i + 1], indices[i + 2]) } else { triangle(indices[i + 1], indices[i], indices[i + 2]) }
                        }
                    }
                default: skip("element of other primitives")
                }
            }
            mesh.elements.append((first, mesh.vertices.count / 8 - first))
        }
        return mesh
    }

    private func elementIndices(_ element: [String: SCNArchive.Plist]) -> [Int] {
        guard let data = archive.bytes(element["elementData"]) else { return [] }
        let size = archive.int(element["bytesPerIndex"]) ?? 2
        guard [1, 2, 4].contains(size) else { return [] }
        return data.withUnsafeBytes { bytes in
            (0..<bytes.count / size).map { index in
                switch size {
                case 1: return Int(bytes[index])
                case 2: return Int(bytes.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self))
                default: return Int(bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
                }
            }
        }
    }
}
