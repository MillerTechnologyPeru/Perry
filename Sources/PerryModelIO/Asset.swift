import CPerryModelIO
import Glibc
import PerryObjCInterop

// MDLAsset: top-level objects, loaded from and exported to Wavefront OBJ
// files (with their MTL materials). An OBJ file becomes one mesh, with a
// submesh for each group or material and a vertex for each distinct
// position, texture coordinate and normal a face corner names; its
// attributes are those the file has, interleaved. Other formats fail.

@ObjCClass("MDLAsset")
open class MDLAsset: NSObject {
    var list: NSMutableArray = NSMutableArray.empty()
    var url: NSObject?
    var allocatorObject: NSObject = MDLMeshBufferDataAllocator()
    var descriptorObject: MDLVertexDescriptor?
    var frameIntervalValue: Double = 0
    var startTimeValue: Double = 0
    var endTimeValue: Double = 0
    var originalsObject: NSObject = MDLObjectContainer()
    var animationsObject: NSObject = MDLObjectContainer()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithBufferAllocator:") public init(bufferAllocator: NSObject?) {
        if let bufferAllocator { allocatorObject = bufferAllocator }
        super.init()
    }

    @ObjCMethod("initWithURL:") public init(url: NSObject?) {
        super.init()
        load(url, error: nil)
    }

    @ObjCMethod("initWithURL:vertexDescriptor:bufferAllocator:")
    public init(url: NSObject?, vertexDescriptor: NSObject?, bufferAllocator: NSObject?) {
        if let bufferAllocator { allocatorObject = bufferAllocator }
        super.init()
        descriptorObject = vertexDescriptor.map { MDLVertexDescriptor(Layout($0)) }
        load(url, error: nil)
    }

    @ObjCMethod("initWithURL:vertexDescriptor:bufferAllocator:preserveTopology:error:")
    public init(url: NSObject?, vertexDescriptor: NSObject?, bufferAllocator: NSObject?, preserveTopology: Bool,
                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
        if let bufferAllocator { allocatorObject = bufferAllocator }
        super.init()
        descriptorObject = vertexDescriptor.map { MDLVertexDescriptor(Layout($0)) }
        load(url, error: error)
    }

    /// Loads a file's objects; an NSError in `error` if it can't.
    func load(_ url: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
        error?.pointee = nil
        self.url = url
        guard let url, let path = url.unsafeCast(to: NSURL.self).path() else {
            storeError(error, "No URL")
            return
        }
        let ext = path.split(separator: ".").last.map { $0.lowercased() } ?? ""
        guard ext == "obj" else {
            modelIOWarning("cannot load \(path): Model I/O here reads only OBJ files")
            storeError(error, "Model I/O here reads only OBJ files, not .\(ext)", code: 1)
            return
        }
        guard let bytes = readFile(path) else {
            modelIOWarning("Could not open OBJ file")
            storeError(error, "Could not open OBJ file \(path)")
            return
        }
        let directory = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : "."
        let obj = OBJFile(text: String(decoding: bytes, as: UTF8.self), directory: directory)
        guard let mesh = obj.mesh(allocator: allocatorObject) else { return }
        if let descriptorObject { mesh.relayout(Layout(descriptorObject)) }
        list.add(mesh)
    }

    @ObjCClassMethod("canImportFileExtension:") static func canImport(fileExtension: String?) -> Bool { fileExtension?.lowercased() == "obj" }
    @ObjCClassMethod("canExportFileExtension:") static func canExport(fileExtension: String?) -> Bool { fileExtension?.lowercased() == "obj" }

    @ObjCMethod("exportAssetToURL:") func export(to url: NSObject?) -> Bool { export(to: url, error: nil) }

    @ObjCMethod("exportAssetToURL:error:") func export(to url: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        error?.pointee = nil
        guard let path = url?.unsafeCast(to: NSURL.self).path() else {
            storeError(error, "No URL")
            return false
        }
        guard path.lowercased().hasSuffix(".obj") else {
            storeError(error, "Model I/O here writes only OBJ files", code: 1)
            return false
        }
        var meshes: [(MDLMesh, Matrix4)] = []
        func collect(_ object: NSObject, _ parent: Matrix4) {
            guard let node = ObjCPeers.peer(of: object.objcObject) as? MDLObject else { return }
            let matrix = parent * node.localMatrix(at: 0)
            if let mesh = node as? MDLMesh { meshes.append((mesh, matrix)) }
            for child in node.childObjects { collect(child, matrix) }
        }
        for object in list.elements { collect(object, .identity) }
        let (obj, mtl) = OBJFile.export(meshes, name: String(path.split(separator: "/").last?.dropLast(4) ?? "asset"))
        let mtlPath = String(path.dropLast(4)) + ".mtl"
        guard writeFile(path, obj), writeFile(mtlPath, mtl) else {
            storeError(error, "Could not write \(path)")
            return false
        }
        return true
    }

    var objects: [MDLObject] { list.elements.compactMap { ObjCPeers.peer(of: $0.objcObject) as? MDLObject } }

    @ObjCMethod("childObjectsOfClass:") func childObjects(of cls: ObjCClass?) -> NSObject {
        var found: [NSObject] = []
        func visit(_ object: NSObject) {
            if cls.map({ object.sendIsKind(of: $0) }) ?? true { found.append(object) }
            if let node = ObjCPeers.peer(of: object.objcObject) as? MDLObject { node.childObjects.forEach(visit) }
        }
        list.elements.forEach(visit)
        return NSArray.of(found)
    }

    func bounds(at time: Double) -> PerryMDLBoundingBox {
        var box = PerryMDLBoundingBox.empty
        for object in objects { box.add(object.bounds(at: time)) }
        return box.reported
    }

    @ObjCMethod("boundingBoxAtTime:") func boundingBox(atTime time: Double) -> PerryMDLBoundingBox { bounds(at: time) }
    @ObjCMethod("boundingBox") func boundingBox() -> PerryMDLBoundingBox { bounds(at: 0) }

    @ObjCMethod("frameInterval") func frameInterval() -> Double { frameIntervalValue }
    @ObjCMethod("setFrameInterval:") func setFrameInterval(_ v: Double) { frameIntervalValue = v }
    @ObjCMethod("startTime") func startTime() -> Double { startTimeValue }
    @ObjCMethod("setStartTime:") func setStartTime(_ v: Double) { startTimeValue = v }
    @ObjCMethod("endTime") func endTime() -> Double { endTimeValue }
    @ObjCMethod("setEndTime:") func setEndTime(_ v: Double) { endTimeValue = v }
    @ObjCMethod("URL") func urlObject() -> NSObject? { url }
    @ObjCMethod("bufferAllocator") func bufferAllocator() -> NSObject { allocatorObject }
    @ObjCMethod("vertexDescriptor") func vertexDescriptor() -> MDLVertexDescriptor? { descriptorObject }
    @ObjCMethod("masters") func masters() -> NSObject { originalsObject }
    @ObjCMethod("setMasters:") func setMasters(_ v: NSObject?) { if let v { originalsObject = v } }
    @ObjCMethod("originals") func originals() -> NSObject { originalsObject }
    @ObjCMethod("setOriginals:") func setOriginals(_ v: NSObject?) { if let v { originalsObject = v } }
    @ObjCMethod("animations") func animations() -> NSObject { animationsObject }
    @ObjCMethod("setAnimations:") func setAnimations(_ v: NSObject?) { if let v { animationsObject = v } }
    @ObjCMethod("resolver") func resolver() -> NSObject? { nil }
    @ObjCMethod("setResolver:") func setResolver(_ v: NSObject?) {}
    @ObjCMethod("loadTextures") func loadTextures() {}

    @ObjCMethod("addObject:") func add(_ object: NSObject?) { if let object { list.add(object) } }
    @ObjCMethod("removeObject:") func remove(_ object: NSObject?) { if let object { list.removeIdentical(object) } }
    @ObjCMethod("count") func count() -> UInt { list.count() }

    @ObjCMethod("objectAtIndexedSubscript:") func object(atIndexedSubscript index: UInt) -> NSObject? {
        index < list.count() ? list.object(at: index) : nil
    }

    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject? { object(atIndexedSubscript: index) }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func countByEnumerating(state: UnsafeMutableRawPointer?, objects: UnsafeMutableRawPointer?, count: UInt) -> UInt {
        list.sendCountByEnumerating(state: state, objects: objects, count: count)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLAsset {
        let copy = MDLAsset(bufferAllocator: allocatorObject)
        copy.list = NSMutableArray.with(list.elements)
        copy.url = url
        copy.descriptorObject = descriptorObject
        (copy.frameIntervalValue, copy.startTimeValue, copy.endTimeValue) = (frameIntervalValue, startTimeValue, endTimeValue)
        return copy
    }
}

// MARK: - Files

/// A file's bytes.
func readFile(_ path: String) -> [UInt8]? {
    guard let file = fopen(path, "rb") else { return nil }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&chunk, 1, chunk.count, file)
        if count == 0 { break }
        bytes += chunk.prefix(count)
    }
    return ferror(file) == 0 ? bytes : nil
}

func writeFile(_ path: String, _ text: String) -> Bool {
    guard let file = fopen(path, "wb") else { return false }
    defer { fclose(file) }
    let bytes = Array(text.utf8)
    return fwrite(bytes, 1, bytes.count, file) == bytes.count
}

// MARK: - OBJ

/// A Wavefront OBJ file's geometry and materials.
struct OBJFile {
    var positions: [SIMD3<Float>] = []
    var colors: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var normals: [SIMD3<Float>] = []
    /// Face corners, as indices of position, texture coordinate and normal
    /// (-1 for none), in groups.
    struct Group {
        var name: String
        var material: String?
        var corners: [SIMD3<Int32>] = []
    }
    var groups: [Group] = []
    var materials: [String: MDLMaterial] = [:]
    let directory: String

    init(text: String, directory: String) {
        self.directory = directory
        var object = "MDL_OBJ"
        var material: String?
        var current = Group(name: object, material: nil)
        func flush() {
            if !current.corners.isEmpty { groups.append(current) }
        }
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = fields.first, !keyword.hasPrefix("#") else { continue }
            let values = fields.dropFirst()
            func floats() -> [Float] { values.compactMap { Float(String($0)) } }
            switch keyword {
            case "v":
                let f = floats()
                positions.append(SIMD3(f.count > 0 ? f[0] : 0, f.count > 1 ? f[1] : 0, f.count > 2 ? f[2] : 0))
                if f.count >= 6 { colors.append(SIMD3(f[3], f[4], f[5])) }
            case "vt":
                let f = floats()
                uvs.append(SIMD2(f.count > 0 ? f[0] : 0, f.count > 1 ? f[1] : 0))
            case "vn":
                let f = floats()
                normals.append(SIMD3(f.count > 0 ? f[0] : 0, f.count > 1 ? f[1] : 0, f.count > 2 ? f[2] : 0))
            case "f":
                let corners = values.map { corner(String($0)) }
                guard corners.count >= 3 else { continue }
                for i in 1..<(corners.count - 1) { current.corners += [corners[0], corners[i], corners[i + 1]] }
            case "o", "g":
                flush()
                object = values.joined(separator: " ")
                if object.isEmpty { object = "MDL_OBJ" }
                current = Group(name: object, material: material)
            case "usemtl":
                flush()
                material = values.joined(separator: " ")
                current = Group(name: "\(object)_\(material ?? "")", material: material)
            case "mtllib":
                for name in values { loadMaterials(directory + "/" + name) }
            default:
                break
            }
        }
        flush()
    }

    /// A face corner, "v", "v/vt", "v//vn" or "v/vt/vn", its indices
    /// counted from 0 (negative ones from the end).
    func corner(_ text: String) -> SIMD3<Int32> {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
        func index(_ i: Int, _ count: Int) -> Int32 {
            guard i < parts.count, let value = parts[i] else { return -1 }
            return Int32(value < 0 ? count + value : value - 1)
        }
        return SIMD3(index(0, positions.count), index(1, uvs.count), index(2, normals.count))
    }

    mutating func loadMaterials(_ path: String) {
        guard let bytes = readFile(path) else { return }
        var material: MDLMaterial?
        func color(_ values: [Float]) -> SIMD3<Float> {
            SIMD3(values.count > 0 ? values[0] : 0, values.count > 1 ? values[1] : values.first ?? 0, values.count > 2 ? values[2] : values.first ?? 0)
        }
        for line in String(decoding: bytes, as: UTF8.self).split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = fields.first, !keyword.hasPrefix("#") else { continue }
            let rest = fields.dropFirst().map(String.init)
            let numbers = rest.compactMap { Float($0) }
            if keyword == "newmtl" {
                let made = MDLMaterial(physicallyPlausible: rest.joined(separator: " "))
                // OBJ materials call the refraction index plainly so.
                made.property(named: "materialIndexOfRefraction")?.nameValue = "indexOfRefraction"
                materials[made.nameValue] = made
                material = made
                continue
            }
            guard let material else { continue }
            func set(_ name: String, _ semantic: UInt, float3: SIMD3<Float>) {
                material.setProperty(MDLMaterialProperty(name: name, semantic: semantic, float3: PerryMDLFloat3(float3)))
            }
            func set(_ name: String, _ semantic: UInt, float: Float) {
                material.setProperty(MDLMaterialProperty(name: name, semantic: semantic, float: float))
            }
            func set(_ name: String, _ semantic: UInt, file: String) {
                // A map names the file for the property its color set.
                if let existing = material.property(named: name) {
                    existing.stringValue = file
                    existing.typeValue = PropertyType.string
                    existing.baseURL = directory
                    return
                }
                let property = MDLMaterialProperty(name: name, semantic: semantic, string: file)
                property.baseURL = directory
                material.setProperty(property)
            }
            // A map's file is its last field, after any options.
            let file = rest.last ?? ""
            switch keyword {
            case "Kd": set("baseColor", Semantic.baseColor, float3: color(numbers))
            case "Ks": set("specular", Semantic.specular, float3: color(numbers))
            case "Ka", "Ke": set("emission", Semantic.emission, float3: color(numbers))
            case "Ns": set("specularExponent", Semantic.specularExponent, float: numbers.first ?? 0)
            case "Ni": set("indexOfRefraction", Semantic.materialIndexOfRefraction, float: numbers.first ?? 1)
            case "d": set("opacity", Semantic.opacity, float: numbers.first ?? 1)
            case "Tr": set("opacity", Semantic.opacity, float: 1 - (numbers.first ?? 0))
            case "map_Kd": set("baseColor", Semantic.baseColor, file: file)
            case "map_Ks": set("specular", Semantic.specular, file: file)
            case "map_Ka", "map_Ke": set("emission", Semantic.emission, file: file)
            case "map_Ns": set("specularExponent", Semantic.specularExponent, file: file)
            case "map_d": set("opacity", Semantic.opacity, file: file)
            case "map_bump", "map_Bump", "bump", "norm": set("bump", Semantic.tangentSpaceNormal, file: file)
            default: break
            }
        }
    }

    /// The file's mesh: nil when it has no faces.
    func mesh(allocator: NSObject) -> MDLMesh? {
        guard !groups.isEmpty else { return nil }
        let hasUVs = groups.contains { $0.corners.contains { $0.y >= 0 } }
        let hasNormals = groups.contains { $0.corners.contains { $0.z >= 0 } }
        let hasColors = !colors.isEmpty && colors.count == positions.count
        var attributes = [Attribute(name: AttributeName.position, format: VertexFormat.float3, offset: 0, bufferIndex: 0)]
        var stride = 12
        if hasNormals {
            attributes.append(Attribute(name: AttributeName.normal, format: VertexFormat.float3, offset: stride, bufferIndex: 0))
            stride += 12
        }
        if hasUVs {
            attributes.append(Attribute(name: AttributeName.textureCoordinate, format: VertexFormat.float2, offset: stride, bufferIndex: 0))
            stride += 8
        }
        if hasColors {
            attributes.append(Attribute(name: AttributeName.color, format: VertexFormat.float3, offset: stride, bufferIndex: 0))
            stride += 12
        }
        var vertices: [SIMD3<Int32>: UInt32] = [:]
        var order: [SIMD3<Int32>] = []
        var lists: [[UInt32]] = []
        for group in groups {
            lists.append(group.corners.map { corner in
                if let index = vertices[corner] { return index }
                let index = UInt32(order.count)
                vertices[corner] = index
                order.append(corner)
                return index
            })
        }
        var floats: [Float] = []
        floats.reserveCapacity(order.count * stride / 4)
        for corner in order {
            let p = Int(corner.x) < positions.count && corner.x >= 0 ? positions[Int(corner.x)] : .zero
            floats += [p.x, p.y, p.z]
            if hasNormals {
                let n = corner.z >= 0 && Int(corner.z) < normals.count ? normals[Int(corner.z)] : .zero
                floats += [n.x, n.y, n.z]
            }
            if hasUVs {
                let t = corner.y >= 0 && Int(corner.y) < uvs.count ? uvs[Int(corner.y)] : .zero
                floats += [t.x, t.y]
            }
            if hasColors {
                let c = corner.x >= 0 && Int(corner.x) < colors.count ? colors[Int(corner.x)] : .zero
                floats += [c.x, c.y, c.z]
            }
        }
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.nameValue = groups[0].name
        mesh.count = order.count
        mesh.descriptor = MDLVertexDescriptor(Layout(attributes: attributes, strides: [stride]))
        mesh.buffers = [floats.withUnsafeBytes { makeBuffer($0, type: BufferType.vertex, allocator: allocator) }]
        var submeshes: [NSObject] = []
        for (group, list) in zip(groups, lists) {
            let material = group.material.flatMap { materials[$0] } ?? MDLMaterial(physicallyPlausible: "")
            let buffer = makeBuffer(Indices.bytes(list, bits: 32), type: BufferType.index, allocator: allocator)
            submeshes.append(MDLSubmesh(name: group.name, indexBuffer: buffer, indexCount: UInt(list.count), indexType: 32,
                                        geometryType: Geometry.triangles, material: material))
        }
        mesh.submeshArray = NSMutableArray.with(submeshes)
        return mesh
    }

    static func number(_ value: Float) -> String {
        if value == value.rounded() && abs(value) < 1e7 { return String(Int(value)) }
        return String(value)
    }

    /// OBJ and MTL text for meshes, each placed by its matrix: a group for
    /// each submesh, with the vertices it uses.
    static func export(_ meshes: [(MDLMesh, Matrix4)], name: String) -> (obj: String, mtl: String) {
        var obj = "# Perry Model I/O OBJ file: \(name)\nmtllib \(name).mtl\n"
        var mtl = "# Perry Model I/O MTL file: \(name)\n"
        var (vBase, vtBase, vnBase, materialCount) = (1, 1, 1, 0)
        var written: [ObjectIdentifier: String] = [:]
        func f(_ v: Float) -> String { number(v) }
        for (mesh, matrix) in meshes {
            let positions = mesh.read(named: AttributeName.position)?.map { matrix.transform(SIMD3($0.x, $0.y, $0.z)) } ?? []
            let normals = mesh.read(named: AttributeName.normal)?.map { n -> SIMD3<Float> in
                let m = matrix
                return normalize(SIMD3(m[0, 0] * n.x + m[0, 1] * n.y + m[0, 2] * n.z, m[1, 0] * n.x + m[1, 1] * n.y + m[1, 2] * n.z,
                                       m[2, 0] * n.x + m[2, 1] * n.y + m[2, 2] * n.z))
            }
            let uvs = mesh.read(named: AttributeName.textureCoordinate)
            for submesh in mesh.submeshes {
                let indices = submesh.triangleIndices.filter { Int($0) < positions.count }
                guard !indices.isEmpty else { continue }
                var used: [UInt32: Int] = [:]
                var order: [UInt32] = []
                for index in indices where used[index] == nil {
                    used[index] = order.count
                    order.append(index)
                }
                obj += "g \(submesh.nameValue.isEmpty ? mesh.nameValue : submesh.nameValue)\n"
                for index in order {
                    let p = positions[Int(index)]
                    obj += "v \(f(p.x)) \(f(p.y)) \(f(p.z))\n"
                }
                if let normals { for index in order { let n = normals[Int(index)]; obj += "vn \(f(n.x)) \(f(n.y)) \(f(n.z))\n" } }
                if let uvs { for index in order { let t = uvs[Int(index)]; obj += "vt \(f(t.x)) \(f(t.y))\n" } }
                let material = submesh.materialObject.flatMap { ObjCPeers.peer(of: $0.objcObject) as? MDLMaterial }
                var materialName = material.map { written[ObjectIdentifier($0)] } ?? nil
                if materialName == nil {
                    materialCount += 1
                    let made = material.map { $0.nameValue.isEmpty ? "material_\(materialCount)" : $0.nameValue } ?? "material_\(materialCount)"
                    materialName = made
                    mtl += "newmtl \(made)\n"
                    if let material {
                        written[ObjectIdentifier(material)] = made
                        mtl += materialText(material)
                    }
                }
                obj += "usemtl \(materialName ?? "")\n"
                var i = 0
                while i + 2 < indices.count {
                    let corners = [indices[i], indices[i + 1], indices[i + 2]].map { index -> String in
                        let k = used[index]!
                        let (v, t, n) = (vBase + k, vtBase + k, vnBase + k)
                        switch (uvs != nil, normals != nil) {
                        case (true, true): return "\(v)/\(t)/\(n)"
                        case (true, false): return "\(v)/\(t)"
                        case (false, true): return "\(v)//\(n)"
                        default: return "\(v)"
                        }
                    }
                    obj += "f \(corners.joined(separator: " "))\n"
                    i += 3
                }
                obj += "s off\n"
                vBase += order.count
                if normals != nil { vnBase += order.count }
                if uvs != nil { vtBase += order.count }
            }
        }
        return (obj, mtl)
    }

    /// A material's MTL statements.
    static func materialText(_ material: MDLMaterial) -> String {
        var text = ""
        func f(_ v: Float) -> String { number(v) }
        for property in material.properties {
            let key: String, map: String
            switch property.semanticValue {
            case Semantic.baseColor: (key, map) = ("Kd", "map_Kd")
            case Semantic.specular: (key, map) = ("Ks", "map_Ks")
            case Semantic.emission: (key, map) = ("Ka", "map_Ka")
            case Semantic.specularExponent: (key, map) = ("Ns", "map_Ns")
            case Semantic.opacity: (key, map) = ("d", "map_d")
            case Semantic.materialIndexOfRefraction: (key, map) = ("Ni", "")
            case Semantic.tangentSpaceNormal, Semantic.bump: (key, map) = ("", "map_bump")
            default: continue
            }
            let type = property.typeValue
            let scalar = ["Ns", "d", "Ni"].contains(key)
            if type == PropertyType.string, !map.isEmpty {
                text += "\(map) \(property.stringValue ?? "")\n"
            } else if type == PropertyType.url, !map.isEmpty {
                if let path = property.urlValue?.unsafeCast(to: NSURL.self).path() { text += "\(map) \(path)\n" }
            } else if [PropertyType.float3, PropertyType.float4, PropertyType.color].contains(type), !key.isEmpty, !scalar {
                let c = property.rgb
                text += "\(key) \(f(c.x)) \(f(c.y)) \(f(c.z))\n"
            } else if type == PropertyType.float, !key.isEmpty {
                let v = f(property.vector.x)
                text += scalar ? "\(key) \(v)\n" : "\(key) \(v) \(v) \(v)\n"
            }
        }
        return text
    }
}
