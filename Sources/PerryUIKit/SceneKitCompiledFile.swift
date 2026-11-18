import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's compiled models. A model an app's .scnassets folder holds (a
// .dae, most often) is not the file the app was made from: Xcode compiles
// it to a property list with a zip of one file, `contents`, which is another
// property list: the scene's tree of nodes by number, and a library of what
// the numbers are — nodes with their transforms, meshes with their geometry
// and materials, geometry sources and elements, skins, images, and
// keyframed animations. The numbers in its data are big-endian where they
// are floats (positions, matrices, weights, keyframes) and little-endian
// where they are indices.
//
// The loader builds the scene from it: the nodes, each mesh as a geometry of
// triangles with its materials' colours and pictures, a skinned mesh's
// skinner, and each animation as a player, playing, on the node its
// channels start from. Cameras, lights and what else a model may hold are
// counted, and listed when PERRY_SCENEKIT_TRACE is set.

enum SCNCompiledModel {
    typealias Plist = KeyedNib.Plist

    /// The scene of a compiled model's bytes, or nil if they are not one.
    static func scene(bytes: [UInt8], path: String) -> SCNScene? {
        guard case .dictionary(let wrapper)? = KeyedNib.parse(bytes), case .data(let zipped)? = wrapper["zippedData"],
              let contents = Zip.first(in: zipped), case .dictionary(let root)? = KeyedNib.parse(contents),
              case .dictionary(let scene)? = root["scene"], case .dictionary(let library)? = root["library"],
              case .dictionary(let storage)? = library["libraryStorage"] else { return nil }
        let directory = path.lastIndex(of: "/").map { String(path[..<$0]) } ?? "."
        return SCNCompiledBuilder(scene: scene, library: storage, directory: directory).build()
    }
}

/// One compiled model's building.
private final class SCNCompiledBuilder {
    typealias Plist = KeyedNib.Plist
    private let scene: [String: Plist]
    private let library: [String: Plist]
    private let directory: String
    private var nodes: [Int: SCNNode] = [:]
    private var meshes: [Int: SCNMesh] = [:]
    private var materials: [Int: SCNMaterial] = [:]
    private var skinned: [(node: SCNNode, described: [String: Plist])] = []
    private var skipped: [String: Int] = [:]

    init(scene: [String: Plist], library: [String: Plist], directory: String) {
        self.scene = scene
        self.library = library
        self.directory = directory
    }

    // MARK: Reading the property list

    private func dictionary(_ value: Plist?) -> [String: Plist]? {
        if case .dictionary(let entries)? = value { return entries }
        return nil
    }

    private func list(_ value: Plist?) -> [Plist] {
        if case .array(let items)? = value { return items }
        return []
    }

    private func number(_ value: Plist?) -> Double? {
        switch value {
        case .integer(let whole)?: return Double(whole)
        case .real(let real)?: return real
        case .bool(let flag)?: return flag ? 1 : 0
        default: return nil
        }
    }

    /// A whole number; the lists of a library's numbers have them as text.
    private func int(_ value: Plist?) -> Int? {
        if case .string(let text)? = value { return Int(text) }
        return number(value).map { Int($0) }
    }

    private func string(_ value: Plist?) -> String? {
        if case .string(let text)? = value { return text }
        return nil
    }

    private func bytes(_ value: Plist?) -> [UInt8]? {
        if case .data(let data)? = value { return data }
        return nil
    }

    /// The library's record of a kind under a number.
    private func record(_ kind: String, _ identifier: Int?) -> [String: Plist]? {
        guard let identifier else { return nil }
        return dictionary(dictionary(library[kind])?[String(identifier)])
    }

    /// Big-endian floats.
    private func floats(_ data: [UInt8]) -> [Float] {
        data.withUnsafeBytes { raw in
            (0..<raw.count / 4).map { Float(bitPattern: UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    /// Little-endian whole numbers of `size` bytes.
    private func indices(_ data: [UInt8], size: Int) -> [Int] {
        guard [1, 2, 4].contains(size) else { return [] }
        return data.withUnsafeBytes { raw in
            (0..<raw.count / size).map { index in
                switch size {
                case 1: return Int(raw[index])
                case 2: return Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self)))
                default: return Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
                }
            }
        }
    }

    private func skip(_ what: String) { skipped[what, default: 0] += 1 }

    // MARK: The scene

    func build() -> SCNScene? {
        guard let tree = dictionary(scene["nodeTree"]) else { return nil }
        let made = SCNScene.make(SCNScene.objCClass)
        // The tree's first node is the scene's root.
        let root = made.rootNode()
        if let identifier = int(tree["nodeID"]) {
            nodes[identifier] = root
            if let described = record("node", identifier) { describe(root, described) }
        }
        for child in list(tree["childs"]) { if let built = node(dictionary(child), depth: 1) { root.addChildNode(built) } }
        // The bones are in the tree now.
        for (node, skinner) in skinned { attachSkinner(skinner, to: node) }
        for (identifier, value) in dictionary(library["animation"]) ?? [:] {
            guard let described = dictionary(value) else { continue }
            attachAnimation(described, key: string(described["name"]) ?? "animation-\(identifier)", root: root)
        }
        for kind in ["morpher", "controller"] where !(dictionary(library[kind])?.isEmpty ?? true) { skip(kind) }
        if getenv("PERRY_SCENEKIT_TRACE") != nil {
            let left = skipped.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            let pictures = materials.values.filter { $0.diffuse().property.contents.map { NSObject($0).responds(to: "CGImage") } ?? false }.count
            let line = "perry: SceneKit: \(directory): compiled model, \(nodes.count) nodes, \(meshes.count) meshes, \(skinned.count) skinned, "
                + "\(materials.count) materials (\(pictures) with a picture)"
                + (left.isEmpty ? "\n" : ", not built: \(left)\n")
            line.withCString { _ = write(2, $0, strlen($0)) }
        }
        return made
    }

    private func node(_ tree: [String: Plist]?, depth: Int) -> SCNNode? {
        guard let tree, let identifier = int(tree["nodeID"]), depth < 64 else { return nil }
        let made = SCNNode.make(SCNNode.objCClass)
        nodes[identifier] = made
        if let described = record("node", identifier) { describe(made, described) }
        for child in list(tree["childs"]) { if let built = node(dictionary(child), depth: depth + 1) { made.addChildNode(built) } }
        return made
    }

    /// A node's name, transform and what it shows.
    private func describe(_ node: SCNNode, _ described: [String: Plist]) {
        let state = node.node
        state.name = string(described["name"]) ?? string(described["id"])
        state.hidden = (number(described["hidden"]) ?? 0) != 0
        state.opacity = CGFloat(number(described["alpha"]) ?? 1)
        let matrix = list(dictionary(described["transforms"])?["matrix4x4"]).compactMap { number($0).map { Float($0) } }
        if matrix.count == 16 {
            let parts = SCNMath.decompose(matrix)
            (state.position, state.rotation, state.scale) = (parts.position, parts.rotation, parts.scale)
        }
        guard let attributes = dictionary(described["attributes"]) else { return }
        if let mesh = record("mesh", int(attributes["kMeshKey"])) { state.geometry = geometry(mesh) }
        if let skinner = dictionary(attributes["kSkinnerKey"]) { skinned.append((node, skinner)) }
        if let light = record("light", int(attributes["kLightKey"])) { state.light = self.light(light) }
        if let camera = record("camera", int(attributes["kCameraKey"])) { state.camera = self.camera(camera) }
        if attributes["kMorpherKey"] != nil { skip("kMorpherKey") }
    }

    // MARK: Lights and cameras

    /// A light: its type (ambient 0, directional 1, omni 2, spot 3), colour and how far it reaches.
    private func light(_ described: [String: Plist]) -> SCNLight {
        let made = SCNLight.objCClass.object.allocated().unsafeCast(to: SCNLight.self)
        let state = made.light
        state.type = ["ambient", "directional", "omni", "spot"][min(max(int(described["type"]) ?? 2, 0), 3)]
        state.name = string(described["name"]) ?? string(described["id"])
        state.intensity = CGFloat(number(described["intensity"]) ?? 1000)
        if let contents = color(described["color"]) { withExtendedLifetime(contents) { SKSupport.replace(&state.color, with: contents.objcObject) } }
        state.attenuationStart = CGFloat(number(described["attenuationStart"]) ?? 0)
        state.attenuationEnd = CGFloat(number(described["attenuationEnd"]) ?? 0)
        state.attenuationFalloff = CGFloat(number(described["attenuationFalloffExponent"]) ?? 2)
        if let outer = number(described["spotOuterAngle"]), outer > 0 { state.spotOuter = CGFloat(outer) }
        if let inner = number(described["spotInnerAngle"]) { state.spotInner = CGFloat(inner) }
        return made
    }

    private func camera(_ described: [String: Plist]) -> SCNCamera {
        let made = SCNCamera.objCClass.object.allocated().unsafeCast(to: SCNCamera.self)
        let state = made.camera
        if let field = number(described["fov"]), field > 0 { state.fieldOfView = CGFloat(field) }
        state.horizontal = (number(described["fovHorizontal"]) ?? 0) != 0
        if let near = number(described["znear"]), near > 0 { state.zNear = near }
        if let far = number(described["zfar"]), far > 0 { state.zFar = far }
        state.orthographic = (number(described["ortho"]) ?? 0) != 0
        if let scale = number(described["xMag"]), scale > 0 { state.orthographicScale = scale }
        return made
    }

    // MARK: Geometry

    /// A mesh's geometry: its triangles, and its materials.
    private func geometry(_ mesh: [String: Plist]) -> SCNGeometry? {
        guard let identifier = int(mesh["geometryID"]), let described = record("geometry", identifier) else { return nil }
        let made = SCNGeometry.objCClass.object.allocated().unsafeCast(to: SCNGeometry.self)
        made.geometry.kind = .custom
        if meshes[identifier] == nil { meshes[identifier] = triangles(described) }
        made.geometry.custom = meshes[identifier] ?? SCNMesh()
        made.geometry.name = string(mesh["name"])
        made.geometry.materials = list(mesh["materialsID"]).compactMap { int($0) }.compactMap { material($0) }
        return made
    }

    /// A source's numbers, `components` to a value.
    private struct Source {
        var values: [Float]
        var components: Int
        func value(_ index: Int, _ component: Int) -> Float {
            let at = index * components + component
            return component < components && at < values.count ? values[at] : 0
        }
    }

    /// The geometry's source of a semantic: floats, read by its accessor.
    private func source(_ described: [String: Plist], semantic: String) -> Source? {
        let data = dictionary(described["primarySourcesInfo"]) ?? [:]
        for identifier in list(described["sources"]).compactMap({ int($0) }) {
            guard let source = record("geometrySource", identifier), string(source["semantic"]) == semantic,
                  let accessor = dictionary(source["accessor"]), let raw = bytes(dictionary(data[String(identifier)])?["data"]) else { continue }
            // Floats are the type the files have; another is left out.
            guard int(accessor["componentsType"]) == 1 else { skip("source of another type"); continue }
            let components = int(accessor["componentsPerValue"]) ?? 3, stride = max(int(accessor["stride"]) ?? components * 4, 4)
            let offset = int(accessor["offset"]) ?? 0, count = int(accessor["valuesCount"]) ?? 0
            let all = floats(raw)
            var values: [Float] = []
            values.reserveCapacity(count * components)
            for index in 0..<count {
                let first = (offset + index * stride) / 4
                for component in 0..<components { values.append(first + component < all.count ? all[first + component] : 0) }
            }
            return Source(values: values, components: components)
        }
        return nil
    }

    /// The triangles of a geometry's elements, a run each; an element of
    /// another kind is an empty run, so the materials still line up.
    private func triangles(_ described: [String: Plist]) -> SCNMesh {
        var mesh = SCNMesh()
        guard let positions = source(described, semantic: "vertex") else { return mesh }
        let normals = source(described, semantic: "normal"), coordinates = source(described, semantic: "texcoord")
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
        for item in list(described["geometryElements"]) {
            let first = mesh.vertices.count / 8
            if let element = dictionary(item), let data = bytes(element["indexes"]) {
                let all = indices(data, size: int(element["bytesPerIndex"]) ?? 2), faces = int(element["facesCount"]) ?? 0
                switch string(element["geometryElement"]) {
                case "trianglesArray":
                    for i in stride(from: 0, to: min(all.count, faces * 3) - 2, by: 3) { triangle(all[i], all[i + 1], all[i + 2]) }
                case "polygonsArray":
                    // Each face's number of corners, then the faces' corners: a face is a fan of triangles.
                    var at = faces
                    for face in 0..<min(faces, all.count) {
                        let corners = all[face]
                        guard corners >= 3, at + corners <= all.count else { break }
                        for corner in 1..<corners - 1 { triangle(all[at], all[at + corner], all[at + corner + 1]) }
                        at += corners
                    }
                case "triangleStrip":
                    if all.count >= 3 {
                        for i in 0..<all.count - 2 {
                            if i % 2 == 0 { triangle(all[i], all[i + 1], all[i + 2]) } else { triangle(all[i + 1], all[i], all[i + 2]) }
                        }
                    }
                default: skip("element of \(string(element["geometryElement"]) ?? "an unknown kind")")
                }
            }
            mesh.elements.append((first, mesh.vertices.count / 8 - first))
        }
        return mesh
    }

    // MARK: Materials

    /// A material: its effect's diffuse picture, or colour.
    private func material(_ identifier: Int) -> SCNMaterial? {
        if let known = materials[identifier] { return known }
        guard let described = record("material", identifier) else { return nil }
        let made = SCNMaterial.make(SCNMaterial.objCClass)
        made.material.name = string(described["name"])
        made.material.doubleSided = (number(described["doubleSided"]) ?? 0) != 0
        made.material.cullMode = int(described["cullMode"]) ?? 0
        if let profile = dictionary(record("effect", int(described["effectID"]))?["commonProfile"]) {
            if let contents = picture(int(profile["diffuseImageID"])) ?? color(profile["diffuseColor"]) {
                let property = made.diffuse()
                withExtendedLifetime(contents) { SKSupport.replace(&property.property.contents, with: contents.objcObject) }
                if let sampler = dictionary(profile["diffuseTextureSampler"]) {
                    property.property.wrapS = int(sampler["wrapS"]) ?? 1
                    property.property.wrapT = int(sampler["wrapT"]) ?? 1
                }
            }
            if let contents = color(profile["emissionColor"], unlessBlack: true) {
                withExtendedLifetime(contents) { SKSupport.replace(&made.emission().property.contents, with: contents.objcObject) }
            }
            if let transparency = number(profile["transparency"]), transparency > 0 { made.material.transparency = CGFloat(transparency) }
        }
        materials[identifier] = made
        return made
    }

    /// An image of the library, read from beside the model.
    private func picture(_ identifier: Int?) -> NSObject? {
        guard let relative = string(record("image", identifier)?["imageRelativePath"]) else { return nil }
        var path = relative.hasPrefix("/") ? relative : "\(directory)/\(relative)"
        // A picture named with no folder may be in one beside the model (its images, its textures).
        if access(path, R_OK) != 0, let name = relative.split(separator: "/").last.map(String.init), let found = find(name, under: directory, depth: 2) {
            path = found
        }
        if let known = SCNFile.images[path] { return known }
        guard let image = UIImage.image(UIImage.objCClass, contentsOfFile: path) else { skip("picture \(relative)"); return nil }
        SCNFile.images[path] = image
        return image
    }

    /// A file of a name in a folder or the folders in it, to a depth.
    private func find(_ name: String, under folder: String, depth: Int) -> String? {
        let direct = "\(folder)/\(name)"
        if access(direct, R_OK) == 0 { return direct }
        guard depth > 0, let list = opendir(folder) else { return nil }
        defer { closedir(list) }
        var folders: [String] = []
        while let entry = readdir(list) {
            let item = withUnsafePointer(to: &entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            if item != ".", item != "..", entry.pointee.d_type == UInt8(DT_DIR) { folders.append(item) }
        }
        for inner in folders.sorted() { if let found = find(name, under: "\(folder)/\(inner)", depth: depth - 1) { return found } }
        return nil
    }

    private func color(_ value: Plist?, unlessBlack: Bool = false) -> NSObject? {
        let parts = list(value).compactMap { number($0) }
        guard parts.count >= 3 else { return nil }
        if unlessBlack, parts[0] == 0, parts[1] == 0, parts[2] == 0 { return nil }
        return UIColor.rgb(CGFloat(parts[0]), CGFloat(parts[1]), CGFloat(parts[2]), CGFloat(parts.count > 3 ? parts[3] : 1))
    }

    // MARK: Skins

    /// Gives `node` the skinner the model describes: its joints, found among the nodes, with the skin's weights.
    private func attachSkinner(_ described: [String: Plist], to node: SCNNode) {
        guard let skin = record("skin", int(described["skinID"])) else { return }
        let joints = list(described["joints"]).compactMap { int($0) }
        let bones = joints.compactMap { nodes[$0] }
        guard !bones.isEmpty, bones.count == joints.count else { skip("skin with joints elsewhere"); return }
        let made = SCNSkinner.objCClass.object.allocated().unsafeCast(to: SCNSkinner.self)
        let state = made.skinner
        state.bones = bones
        state.exactInverseBind = true
        // A joint's inverse bind transform, after the transform the mesh was bound in.
        let matrices = bytes(skin["inverseBindMatrices"]).map(floats) ?? []
        let shape = bytes(skin["defaultShapeMatrix"]).map(floats) ?? []
        state.inverseBind = (0..<bones.count).map { index in
            guard matrices.count >= (index + 1) * 16 else { return SCNMath.identity }
            let inverse = Array(matrices[index * 16..<index * 16 + 16])
            return shape.count == 16 ? SCNMath.multiply(inverse, shape) : inverse
        }
        if let skeleton = int(described["skeletonID"]) { state.skeleton = nodes[skeleton] }
        // A vertex's weights are a run of the skin's, from its place in the list of places to the next vertex's.
        let weights = bytes(skin["vertexWeights"]).map(floats) ?? []
        let weightJoints = bytes(skin["jointsForVertexWeights"]).map { indices($0, size: 2) } ?? []
        let places = bytes(skin["vertexWeightIndices"]).map { indices($0, size: 4) } ?? []
        let count = int(skin["vertexCount"]) ?? max(places.count - 1, 0)
        let influences = max(int(skin["maxInfluences"]) ?? 4, 1)
        state.influences = influences
        state.weights = [Float](repeating: 0, count: count * influences)
        state.indices = [UInt16](repeating: 0, count: count * influences)
        for vertex in 0..<count where vertex + 1 < places.count {
            let first = places[vertex], last = min(places[vertex + 1], weights.count, weightJoints.count)
            guard first < last else { continue }
            for (slot, at) in (first..<min(last, first + influences)).enumerated() {
                state.weights[vertex * influences + slot] = weights[at]
                state.indices[vertex * influences + slot] = UInt16(truncatingIfNeeded: weightJoints[at])
            }
        }
        node.node.skinner = made
    }

    // MARK: Animations

    /// An animation of the library as a player, playing, on the node its channels start from: the one the first
    /// channel's path names first, so the paths are found from it, or from whatever node the player is moved to above it.
    private func attachAnimation(_ described: [String: Plist], key: String, root: SCNNode) {
        let made = SCNAnimation.objCClass.object.allocated().unsafeCast(to: SCNAnimation.self)
        let state = made.animation
        state.duration = number(described["duration"]) ?? 0
        state.repeatCount = CGFloat(number(described["repeatCount"]) ?? 0)
        state.removedOnCompletion = (number(described["removeOnCompletion"]) ?? 1) != 0
        state.fadeIn = number(described["fadeInDuration"]) ?? 0
        state.fadeOut = number(described["fadeOutDuration"]) ?? 0
        state.autoreverses = (number(described["autoreverses"]) ?? 0) != 0
        // A channel is a node's whole transform, or one part of it (as a model made from a COLLADA file has them):
        // its translation, its turn as a quaternion, or its scale. A node's parts are put together, at the times of
        // all of them; a part with no channel stays as the node has it.
        struct Track { var times: [Double], values: [Float], width: Int }
        var order: [String] = []
        var tracks: [String: [String: Track]] = [:]
        for item in list(described["channels"]) {
            guard let channel = dictionary(item) else { continue }
            let target = list(channel["targetPath"])
            guard target.count == 2, let path = string(target[0]), let property = string(target[1]) else { skip("animated property"); continue }
            let part: String
            switch property {
            case "transform": part = "transform"
            case "translation", "position": part = "translation"
            case "quaternion", "orientation": part = "rotation"
            case "scale": part = "scale"
            default: skip("animated \(property)"); continue
            }
            guard let controller = dictionary(dictionary(channel["animation"])?["keyframeController"]),
                  let timeBytes = bytes(controller["keytimes-data"]), let valueBytes = bytes(controller["values-data"]) else { continue }
            // Times are big-endian doubles, values big-endian floats: a matrix, a vector or a quaternion to a time.
            let count = timeBytes.count / 8
            let width = ["transform": 16, "rotation": 4][part] ?? 3
            guard count > 0, valueBytes.count >= count * width * 4 else { continue }
            let times = timeBytes.withUnsafeBytes { raw in
                (0..<count).map { Double(bitPattern: UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
            }
            if tracks[path] == nil { order.append(path) }
            tracks[path, default: [:]][part] = Track(times: times, values: floats(valueBytes), width: width)
        }
        for path in order {
            guard let parts = tracks[path] else { continue }
            let names = path.split(separator: "/").map(String.init)
            if let matrix = parts["transform"] {
                let keys = matrix.times.indices.map { SCNMath.decompose(Array(matrix.values[$0 * 16..<$0 * 16 + 16])) }
                state.channels.append(SCNChannel(path: names, times: matrix.times, keys: keys))
                if state.duration <= 0 { state.duration = matrix.times.last ?? 0 }
                continue
            }
            let times = Array(Set(parts.values.flatMap(\.times))).sorted()
            let rest = names.last.flatMap { root.childNode(withName: $0, recursively: true) }?.node
            /// A track's value at a time, between the keys about it.
            func sample(_ track: Track, _ time: Double) -> [Float] {
                var high = track.times.firstIndex { $0 >= time } ?? track.times.count - 1
                if high == 0 || track.times[high] == time || time > track.times[high] {
                    if time > track.times[high] { high = track.times.count - 1 }
                    return Array(track.values[high * track.width..<(high + 1) * track.width])
                }
                let low = high - 1, span = track.times[high] - track.times[low]
                let t = span > 0 ? Float((time - track.times[low]) / span) : 0
                var a = Array(track.values[low * track.width..<(low + 1) * track.width])
                var b = Array(track.values[high * track.width..<(high + 1) * track.width])
                // A quaternion and its negative are one turn: the near one, so the way between is the short one.
                if track.width == 4, zip(a, b).reduce(Float(0), { $0 + $1.0 * $1.1 }) < 0 { b = b.map { -$0 } }
                for index in a.indices { a[index] += (b[index] - a[index]) * t }
                return a
            }
            let keys: [(position: SCNVector3, rotation: SCNMath.Quaternion, scale: SCNVector3)] = times.map { time in
                var position = rest?.position ?? SCNVector3(x: 0, y: 0, z: 0)
                var rotation = rest?.rotation ?? SCNMath.noRotation
                var scale = rest?.scale ?? SCNVector3(x: 1, y: 1, z: 1)
                if let track = parts["translation"] { let v = sample(track, time); position = SCNVector3(x: v[0], y: v[1], z: v[2]) }
                if let track = parts["rotation"] { let v = sample(track, time); rotation = SCNMath.normalized((v[0], v[1], v[2], v[3])) }
                if let track = parts["scale"] { let v = sample(track, time); scale = SCNVector3(x: v[0], y: v[1], z: v[2]) }
                return (position, rotation, scale)
            }
            state.channels.append(SCNChannel(path: names, times: times, keys: keys))
            if state.duration <= 0 { state.duration = times.last ?? 0 }
        }
        guard let first = state.channels.first?.path.first else { return }
        let target = root.childNode(withName: first, recursively: true) ?? root
        let player = SCNAnimationPlayer.objCClass.object.allocated().unsafeCast(to: SCNAnimationPlayer.self)
        player.player.animation = made
        player.player.playing = true
        target.addAnimationPlayer(player, forKey: key)
    }
}

// MARK: - Zip

/// The first file of a zip, stored or deflated.
private enum Zip {
    static func first(in bytes: [UInt8]) -> [UInt8]? {
        func little(_ at: Int, _ size: Int) -> Int? {
            guard at >= 0, at + size <= bytes.count else { return nil }
            return (0..<size).reduce(0) { $0 | Int(bytes[at + $1]) << ($1 * 8) }
        }
        // A local file header: its signature, the method, and the lengths of the name and the extra field.
        guard little(0, 4) == 0x0403_4b50, let method = little(8, 2), let stored = little(18, 4), let name = little(26, 2),
              let extra = little(28, 2) else { return nil }
        let start = 30 + name + extra
        guard start <= bytes.count else { return nil }
        switch method {
        case 0: return stored > 0 && start + stored <= bytes.count ? Array(bytes[start..<start + stored]) : nil
        case 8: return Inflate.inflate(bytes, from: start)
        default: return nil
        }
    }
}

/// DEFLATE (RFC 1951), read from `bytes` at a place: the blocks to the last one.
private struct Inflate {
    private let bytes: [UInt8]
    private var at: Int
    private var bit = 0
    private var out: [UInt8] = []
    private var failed = false

    static func inflate(_ bytes: [UInt8], from start: Int) -> [UInt8]? {
        var state = Inflate(bytes: bytes, at: start)
        return state.run() ? state.out : nil
    }

    private init(bytes: [UInt8], at: Int) {
        self.bytes = bytes
        self.at = at
    }

    private mutating func bits(_ count: Int) -> Int {
        var value = 0
        for index in 0..<count {
            guard at < bytes.count else { failed = true; return 0 }
            value |= Int(bytes[at] >> UInt8(bit) & 1) << index
            bit += 1
            if bit == 8 { bit = 0; at += 1 }
        }
        return value
    }

    /// A Huffman code's table: the symbols in order of code, and how many codes have each length.
    private struct Table {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            for length in lengths { counts[length] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<16 { offsets[length] = offsets[length - 1] + counts[length - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private mutating func symbol(_ table: Table) -> Int {
        var code = 0, first = 0, index = 0
        for length in 1..<16 {
            code |= bits(1)
            if failed { return -1 }
            let count = table.counts[length]
            if code - count < first { return table.symbols[index + (code - first)] }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        failed = true
        return -1
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
                                       6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private mutating func block(_ literals: Table, _ distances: Table) {
        while !failed {
            let value = symbol(literals)
            if value < 0 { return }
            if value < 256 { out.append(UInt8(value)); continue }
            if value == 256 { return }
            let index = value - 257
            guard index < Self.lengthBase.count else { failed = true; return }
            let length = Self.lengthBase[index] + bits(Self.lengthExtra[index])
            let code = symbol(distances)
            guard code >= 0, code < Self.distanceBase.count else { failed = true; return }
            let distance = Self.distanceBase[code] + bits(Self.distanceExtra[code])
            guard distance <= out.count else { failed = true; return }
            for _ in 0..<length { out.append(out[out.count - distance]) }
        }
    }

    private mutating func run() -> Bool {
        var last = false
        while !last, !failed {
            last = bits(1) == 1
            switch bits(2) {
            case 0:
                // Stored: to the next byte, a length and its complement, then the bytes.
                if bit != 0 { bit = 0; at += 1 }
                guard at + 4 <= bytes.count else { return false }
                let length = Int(bytes[at]) | Int(bytes[at + 1]) << 8
                at += 4
                guard at + length <= bytes.count else { return false }
                out.append(contentsOf: bytes[at..<at + length])
                at += length
            case 1:
                var lengths = [Int](repeating: 8, count: 288)
                for index in 144..<256 { lengths[index] = 9 }
                for index in 256..<280 { lengths[index] = 7 }
                block(Table(lengths: lengths), Table(lengths: [Int](repeating: 5, count: 30)))
            case 2:
                let literalCount = bits(5) + 257, distanceCount = bits(5) + 1, codeCount = bits(4) + 4
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var codeLengths = [Int](repeating: 0, count: 19)
                for index in 0..<codeCount { codeLengths[order[index]] = bits(3) }
                let codes = Table(lengths: codeLengths)
                var lengths: [Int] = []
                while lengths.count < literalCount + distanceCount, !failed {
                    let value = symbol(codes)
                    switch value {
                    case 0..<16: lengths.append(value)
                    case 16:
                        guard let previous = lengths.last else { return false }
                        lengths.append(contentsOf: [Int](repeating: previous, count: 3 + bits(2)))
                    case 17: lengths.append(contentsOf: [Int](repeating: 0, count: 3 + bits(3)))
                    case 18: lengths.append(contentsOf: [Int](repeating: 0, count: 11 + bits(7)))
                    default: return false
                    }
                }
                guard lengths.count == literalCount + distanceCount else { return false }
                block(Table(lengths: Array(lengths[..<literalCount])), Table(lengths: Array(lengths[literalCount...])))
            default: return false
            }
        }
        return !failed
    }
}
