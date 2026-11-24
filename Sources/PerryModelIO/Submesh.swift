import CPerryModelIO
import Glibc
import PerryObjCInterop

// MDLSubmesh: an index buffer, its index type and geometry type and a
// material; its topology; and MDLVertexAttributeData, a view of one
// attribute's values in a vertex buffer.

/// MDLGeometryType.
enum Geometry {
    static let points = 0, lines = 1, triangles = 2, triangleStrips = 3, quads = 4, variableTopology = 5
}

/// Reads and writes indices of 8, 16 or 32 bits.
enum Indices {
    static func read(_ pointer: UnsafeRawPointer?, count: Int, bits: UInt) -> [UInt32] {
        guard let pointer, count > 0 else { return [] }
        switch bits {
        case 8: return (0..<count).map { UInt32(pointer.load(fromByteOffset: $0, as: UInt8.self)) }
        case 16: return (0..<count).map { UInt32(pointer.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
        default: return (0..<count).map { pointer.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
        }
    }

    static func bytes(_ indices: [UInt32], bits: UInt) -> [UInt8] {
        switch bits {
        case 8: return indices.map { UInt8(truncatingIfNeeded: $0) }
        case 16: return indices.map { UInt16(truncatingIfNeeded: $0) }.withUnsafeBytes { Array($0) }
        default: return indices.withUnsafeBytes { Array($0) }
        }
    }

    /// The smallest of 16 and 32 bits that holds indices below `count`.
    static func bits(forVertexCount count: Int) -> UInt { count <= 65536 ? 16 : 32 }

    /// Triangle lists of other primitives: strips (restarting at the
    /// largest index) and quads, fanned.
    static func triangles(_ indices: [UInt32], geometryType: Int, restart: UInt32 = 0xFFFF_FFFF) -> [UInt32] {
        switch geometryType {
        case Geometry.triangleStrips:
            var result: [UInt32] = []
            var strip: [UInt32] = []
            func flush() {
                guard strip.count >= 3 else { strip = []; return }
                for i in 0..<(strip.count - 2) {
                    let (a, b, c) = (strip[i], strip[i + 1], strip[i + 2])
                    if a == b || b == c || a == c { continue }
                    result += i % 2 == 0 ? [a, b, c] : [b, a, c]
                }
                strip = []
            }
            for index in indices {
                if index == restart { flush() } else { strip.append(index) }
            }
            flush()
            return result
        case Geometry.quads:
            var result: [UInt32] = []
            var i = 0
            while i + 3 < indices.count {
                let (a, b, c, d) = (indices[i], indices[i + 1], indices[i + 2], indices[i + 3])
                result += [a, b, c, a, c, d]
                i += 4
            }
            return result
        default:
            return indices
        }
    }
}

@ObjCClass("MDLSubmeshTopology")
open class MDLSubmeshTopology: NSObject {
    var faceTopologyBuffer: NSObject?
    var faces: UInt = 0
    var vertexCreaseIndicesBuffer: NSObject?
    var vertexCreasesBuffer: NSObject?
    var vertexCreases: UInt = 0
    var edgeCreaseIndicesBuffer: NSObject?
    var edgeCreasesBuffer: NSObject?
    var edgeCreases: UInt = 0
    var holesBuffer: NSObject?
    var holes: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithSubmesh:") public init(submesh: NSObject?) {
        super.init()
        guard let submesh = submesh.flatMap({ ObjCPeers.peer(of: $0.objcObject) as? MDLSubmesh }) else { return }
        // One face per primitive, of its corner count.
        let corners: Int
        switch submesh.geometry {
        case Geometry.lines: corners = 2
        case Geometry.quads: corners = 4
        case Geometry.points: corners = 1
        default: corners = 3
        }
        let count = Int(submesh.count) / corners
        faces = UInt(count)
        faceTopologyBuffer = makeBuffer([UInt8](repeating: UInt8(corners), count: count), type: BufferType.index, allocator: nil)
    }

    @ObjCMethod("faceTopology") func faceTopology() -> NSObject? { faceTopologyBuffer }
    @ObjCMethod("setFaceTopology:") func setFaceTopology(_ v: NSObject?) { faceTopologyBuffer = v }
    @ObjCMethod("faceCount") func faceCount() -> UInt { faces }
    @ObjCMethod("setFaceCount:") func setFaceCount(_ v: UInt) { faces = v }
    @ObjCMethod("vertexCreaseIndices") func vertexCreaseIndices() -> NSObject? { vertexCreaseIndicesBuffer }
    @ObjCMethod("setVertexCreaseIndices:") func setVertexCreaseIndices(_ v: NSObject?) { vertexCreaseIndicesBuffer = v }
    @ObjCMethod("vertexCreases") func vertexCreasesObject() -> NSObject? { vertexCreasesBuffer }
    @ObjCMethod("setVertexCreases:") func setVertexCreases(_ v: NSObject?) { vertexCreasesBuffer = v }
    @ObjCMethod("vertexCreaseCount") func vertexCreaseCount() -> UInt { vertexCreases }
    @ObjCMethod("setVertexCreaseCount:") func setVertexCreaseCount(_ v: UInt) { vertexCreases = v }
    @ObjCMethod("edgeCreaseIndices") func edgeCreaseIndices() -> NSObject? { edgeCreaseIndicesBuffer }
    @ObjCMethod("setEdgeCreaseIndices:") func setEdgeCreaseIndices(_ v: NSObject?) { edgeCreaseIndicesBuffer = v }
    @ObjCMethod("edgeCreases") func edgeCreasesObject() -> NSObject? { edgeCreasesBuffer }
    @ObjCMethod("setEdgeCreases:") func setEdgeCreases(_ v: NSObject?) { edgeCreasesBuffer = v }
    @ObjCMethod("edgeCreaseCount") func edgeCreaseCount() -> UInt { edgeCreases }
    @ObjCMethod("setEdgeCreaseCount:") func setEdgeCreaseCount(_ v: UInt) { edgeCreases = v }
    @ObjCMethod("holes") func holesObject() -> NSObject? { holesBuffer }
    @ObjCMethod("setHoles:") func setHoles(_ v: NSObject?) { holesBuffer = v }
    @ObjCMethod("holeCount") func holeCount() -> UInt { holes }
    @ObjCMethod("setHoleCount:") func setHoleCount(_ v: UInt) { holes = v }
}

@ObjCClass("MDLSubmesh")
open class MDLSubmesh: NSObject {
    var nameValue = ""
    var buffer: NSObject?
    var count: UInt = 0
    var bits: UInt = 16
    var geometry = Geometry.triangles
    var materialObject: NSObject?
    var topologyObject: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithName:indexBuffer:indexCount:indexType:geometryType:material:")
    public init(name: String?, indexBuffer: NSObject?, indexCount: UInt, indexType: UInt, geometryType: Int, material: NSObject?) {
        (nameValue, buffer, count, bits, geometry, materialObject) = (name ?? "", indexBuffer, indexCount, indexType, geometryType, material)
        super.init()
    }

    @ObjCMethod("initWithIndexBuffer:indexCount:indexType:geometryType:material:")
    public init(indexBuffer: NSObject?, indexCount: UInt, indexType: UInt, geometryType: Int, material: NSObject?) {
        (buffer, count, bits, geometry, materialObject) = (indexBuffer, indexCount, indexType, geometryType, material)
        super.init()
    }

    @ObjCMethod("initWithName:indexBuffer:indexCount:indexType:geometryType:material:topology:")
    public init(name: String?, indexBuffer: NSObject?, indexCount: UInt, indexType: UInt, geometryType: Int, material: NSObject?,
                topology: NSObject?) {
        (nameValue, buffer, count, bits, geometry, materialObject, topologyObject) =
            (name ?? "", indexBuffer, indexCount, indexType, geometryType, material, topology)
        super.init()
    }

    /// Another submesh's indices as triangles or lines, in `indexType`.
    @ObjCMethod("initWithMDLSubmesh:indexType:geometryType:")
    public init?(mdlSubmesh: NSObject?, indexType: UInt, geometryType: Int) {
        guard let source = mdlSubmesh.flatMap({ ObjCPeers.peer(of: $0.objcObject) as? MDLSubmesh }) else { return nil }
        var indices = source.indices
        if geometryType != source.geometry {
            guard geometryType == Geometry.triangles,
                  [Geometry.triangleStrips, Geometry.quads].contains(source.geometry) else { return nil }
            indices = Indices.triangles(indices, geometryType: source.geometry)
        }
        let bits = [8, 16, 32].contains(indexType) ? indexType : 32
        (nameValue, count, self.bits, geometry, materialObject) = (source.nameValue, UInt(indices.count), bits, geometryType, source.materialObject)
        buffer = makeBuffer(Indices.bytes(indices, bits: bits), type: BufferType.index, allocator: source.buffer?.sendAllocator())
        super.init()
    }

    /// The indices, as 32-bit values.
    var indices: [UInt32] {
        guard let buffer else { return [] }
        let count = Int(count), bits = bits
        return withBytes(of: buffer) { pointer, length in
            Indices.read(pointer, count: min(count, length / max(Int(bits) / 8, 1)), bits: bits)
        }
    }

    /// Indices as triangles, for normals, tangents and bounds.
    var triangleIndices: [UInt32] { Indices.triangles(indices, geometryType: geometry) }

    @ObjCMethod("indexBuffer") func indexBuffer() -> NSObject? { buffer }

    @ObjCMethod("indexBufferAsIndexType:") func indexBuffer(asIndexType indexType: UInt) -> NSObject? {
        guard indexType != bits, let buffer else { return buffer }
        return makeBuffer(Indices.bytes(indices, bits: indexType), type: BufferType.index, allocator: buffer.sendAllocator())
    }

    @ObjCMethod("indexCount") func indexCount() -> UInt { count }
    @ObjCMethod("indexType") func indexType() -> UInt { bits }
    @ObjCMethod("geometryType") func geometryType() -> Int { geometry }
    @ObjCMethod("material") func material() -> NSObject? { materialObject }
    @ObjCMethod("setMaterial:") func setMaterial(_ v: NSObject?) { materialObject = v }
    @ObjCMethod("topology") func topology() -> NSObject? { topologyObject }
    @ObjCMethod("setTopology:") func setTopology(_ v: NSObject?) { topologyObject = v }
    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ v: String?) { nameValue = v ?? "" }

    /// Replaces the indices, in a new buffer of the same allocator.
    func replaceIndices(_ indices: [UInt32], vertexCount: Int) {
        let allocator = buffer?.sendAllocator()
        if bits == 8 && vertexCount > 256 || bits == 16 && vertexCount > 65536 { bits = 32 }
        buffer = makeBuffer(Indices.bytes(indices, bits: bits), type: BufferType.index, allocator: allocator)
        count = UInt(indices.count)
    }

    @ObjCMethod("description") func describe() -> String {
        "<MDLSubmesh \(nameValue): \(count) indices of \(bits) bits, geometry \(geometry)>"
    }
}

extension NSObject {
    @ObjCMethod("allocator") func sendAllocator() -> NSObject?
}

@ObjCClass("MDLVertexAttributeData")
open class MDLVertexAttributeData: NSObject {
    var mapObject: NSObject?
    var start: UnsafeMutableRawPointer?
    var strideValue: UInt = 0
    var formatValue: UInt = 0
    var size: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }

    init(map: NSObject?, start: UnsafeMutableRawPointer?, stride: Int, format: UInt, bufferSize: Int) {
        (mapObject, self.start, strideValue, formatValue, size) = (map, start, UInt(stride), format, UInt(max(bufferSize, 0)))
        super.init()
    }

    @ObjCMethod("map") func map() -> NSObject? { mapObject }
    @ObjCMethod("setMap:") func setMap(_ v: NSObject?) { mapObject = v }
    @ObjCMethod("dataStart") func dataStart() -> UnsafeMutableRawPointer? { start }
    @ObjCMethod("setDataStart:") func setDataStart(_ v: UnsafeMutableRawPointer?) { start = v }
    @ObjCMethod("stride") func stride() -> UInt { strideValue }
    @ObjCMethod("setStride:") func setStride(_ v: UInt) { strideValue = v }
    @ObjCMethod("format") func format() -> UInt { formatValue }
    @ObjCMethod("setFormat:") func setFormat(_ v: UInt) { formatValue = v }
    @ObjCMethod("bufferSize") func bufferSize() -> UInt { size }
    @ObjCMethod("setBufferSize:") func setBufferSize(_ v: UInt) { size = v }
}

extension NSObject {
    @ObjCMethod("dataStart") func sendDataStart() -> UnsafeMutableRawPointer?
    @ObjCMethod("stride") func sendStride() -> UInt
    @ObjCMethod("format") func sendFormat() -> UInt
}
