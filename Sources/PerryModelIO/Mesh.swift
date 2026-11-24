import CPerryModelIO
import Glibc
import PerryObjCInterop

// MDLMesh: vertex buffers laid out by a vertex descriptor, a vertex count
// and submeshes; its generators, which build Shapes into an interleaved
// buffer; and its modifiers, which read attributes as floats and write
// them back in the descriptor's formats: a new descriptor lays the buffers
// out anew, and normals and tangents are computed from the triangles.

@ObjCClass("MDLMesh")
open class MDLMesh: MDLObject {
    var buffers: [NSObject] = []
    var count = 0
    var descriptor = MDLVertexDescriptor()
    var submeshArray: NSMutableArray? = NSMutableArray.empty()
    var allocatorObject: NSObject = MDLMeshBufferDataAllocator()

    @ObjCMethod("init") public required init() { super.init() }

    @ObjCMethod("initWithBufferAllocator:") public init(bufferAllocator: NSObject?) {
        if let bufferAllocator { allocatorObject = bufferAllocator }
        super.init()
    }

    @ObjCMethod("initWithVertexBuffer:vertexCount:descriptor:submeshes:")
    public init(vertexBuffer: NSObject?, vertexCount: UInt, descriptor: NSObject?, submeshes: NSObject?) {
        super.init()
        setUp(buffers: vertexBuffer.map { [$0] } ?? [], vertexCount: vertexCount, descriptor: descriptor, submeshes: submeshes)
    }

    @ObjCMethod("initWithVertexBuffers:vertexCount:descriptor:submeshes:")
    public init(vertexBuffers: NSObject?, vertexCount: UInt, descriptor: NSObject?, submeshes: NSObject?) {
        super.init()
        setUp(buffers: vertexBuffers.map { $0.unsafeCast(to: NSArray.self).elements } ?? [], vertexCount: vertexCount,
              descriptor: descriptor, submeshes: submeshes)
    }

    func setUp(buffers: [NSObject], vertexCount: UInt, descriptor: NSObject?, submeshes: NSObject?) {
        self.buffers = buffers
        count = Int(vertexCount)
        if let descriptor { self.descriptor = MDLVertexDescriptor(Layout(descriptor)) }
        submeshArray = NSMutableArray.with(submeshes.map { $0.unsafeCast(to: NSArray.self).elements } ?? [])
        if let allocator = buffers.first?.sendAllocator() { allocatorObject = allocator }
    }

    // MARK: Generators

    @ObjCMethod("initBoxWithExtent:segments:inwardNormals:geometryType:allocator:")
    public init(boxWithExtent extent: PerryMDLFloat3, segments: PerryMDLUInt3, inwardNormals: Bool, geometryType: Int, allocator: NSObject?) {
        super.init()
        load(Shapes.box(extent: extent.v, segments: segments.v, inward: inwardNormals, geometryType: geometryType), allocator: allocator)
    }

    @ObjCMethod("initSphereWithExtent:segments:inwardNormals:geometryType:allocator:")
    public init(sphereWithExtent extent: PerryMDLFloat3, segments: PerryMDLUInt2, inwardNormals: Bool, geometryType: Int, allocator: NSObject?) {
        super.init()
        load(Shapes.ellipsoid(radii: extent.v, segments: segments.v, inward: inwardNormals, hemisphere: false, geometryType: geometryType),
             allocator: allocator)
    }

    @ObjCMethod("initHemisphereWithExtent:segments:inwardNormals:cap:geometryType:allocator:")
    public init(hemisphereWithExtent extent: PerryMDLFloat3, segments: PerryMDLUInt2, inwardNormals: Bool, cap: Bool, geometryType: Int,
                allocator: NSObject?) {
        super.init()
        load(Shapes.ellipsoid(radii: extent.v, segments: segments.v, inward: inwardNormals, hemisphere: true, geometryType: geometryType),
             allocator: allocator)
    }

    @ObjCMethod("initCylinderWithExtent:segments:inwardNormals:topCap:bottomCap:geometryType:allocator:")
    public init(cylinderWithExtent extent: PerryMDLFloat3, segments: PerryMDLUInt2, inwardNormals: Bool, topCap: Bool, bottomCap: Bool,
                geometryType: Int, allocator: NSObject?) {
        super.init()
        load(Shapes.cylinder(extent: extent.v, segments: segments.v, inward: inwardNormals, topCap: topCap, bottomCap: bottomCap,
                             geometryType: geometryType), allocator: allocator)
    }

    @ObjCMethod("initCapsuleWithExtent:cylinderSegments:hemisphereSegments:inwardNormals:geometryType:allocator:")
    public init(capsuleWithExtent extent: PerryMDLFloat3, cylinderSegments: PerryMDLUInt2, hemisphereSegments: Int32, inwardNormals: Bool,
                geometryType: Int, allocator: NSObject?) {
        super.init()
        load(Shapes.capsule(extent: extent.v, segments: cylinderSegments.v, hemisphereSegments: Int(hemisphereSegments), inward: inwardNormals,
                            geometryType: geometryType), allocator: allocator)
    }

    @ObjCMethod("initConeWithExtent:segments:inwardNormals:cap:geometryType:allocator:")
    public init(coneWithExtent extent: PerryMDLFloat3, segments: PerryMDLUInt2, inwardNormals: Bool, cap: Bool, geometryType: Int,
                allocator: NSObject?) {
        super.init()
        load(Shapes.cone(extent: extent.v, segments: segments.v, inward: inwardNormals, geometryType: geometryType), allocator: allocator)
    }

    @ObjCMethod("initPlaneWithExtent:segments:geometryType:allocator:")
    public init(planeWithExtent extent: PerryMDLFloat3, segments: PerryMDLUInt2, geometryType: Int, allocator: NSObject?) {
        super.init()
        load(Shapes.plane(extent: extent.v, segments: segments.v, geometryType: geometryType), allocator: allocator)
    }

    @ObjCMethod("initIcosahedronWithExtent:inwardNormals:geometryType:allocator:")
    public init(icosahedronWithExtent extent: PerryMDLFloat3, inwardNormals: Bool, geometryType: Int, allocator: NSObject?) {
        super.init()
        load(Shapes.icosahedron(extent: extent.v, inward: inwardNormals, geometryType: geometryType), allocator: allocator)
    }

    /// Model I/O subdivides with OpenSubdiv; here the mesh is copied as it is.
    @ObjCMethod("initMeshBySubdividingMesh:submeshIndex:subdivisionLevels:allocator:")
    public init(meshBySubdividingMesh mesh: NSObject?, submeshIndex: Int32, subdivisionLevels: UInt32, allocator: NSObject?) {
        super.init()
        if let source = mesh.flatMap({ ObjCPeers.peer(of: $0.objcObject) as? MDLMesh }) { copyContents(of: source, allocator: allocator) }
    }

    func copyContents(of source: MDLMesh, allocator: NSObject?) {
        if let allocator { allocatorObject = allocator }
        nameValue = source.nameValue
        count = source.count
        descriptor = MDLVertexDescriptor(Layout(source.descriptor))
        buffers = source.buffers.map { makeBuffer(bytes(of: $0), type: BufferType.vertex, allocator: allocatorObject) }
        submeshArray = NSMutableArray.with(source.submeshes.map { submesh in
            MDLSubmesh(name: submesh.nameValue, indexBuffer: makeBuffer(bytes(of: submesh.buffer ?? MDLMeshBufferData()), type: BufferType.index,
                                                                         allocator: allocatorObject),
                       indexCount: submesh.count, indexType: submesh.bits, geometryType: submesh.geometry, material: submesh.materialObject)
        })
    }

    @ObjCClassMethod("newBoxWithDimensions:segments:geometryType:inwardNormals:allocator:")
    static func newBox(dimensions: PerryMDLFloat3, segments: PerryMDLUInt3, geometryType: Int, inwardNormals: Bool, allocator: NSObject?) -> MDLMesh {
        MDLMesh(boxWithExtent: dimensions, segments: segments, inwardNormals: inwardNormals, geometryType: geometryType, allocator: allocator)
    }

    @ObjCClassMethod("newEllipsoidWithRadii:radialSegments:verticalSegments:geometryType:inwardNormals:hemisphere:allocator:")
    static func newEllipsoid(radii: PerryMDLFloat3, radialSegments: UInt, verticalSegments: UInt, geometryType: Int, inwardNormals: Bool,
                             hemisphere: Bool, allocator: NSObject?) -> MDLMesh {
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.load(Shapes.ellipsoid(radii: radii.v, segments: SIMD2(UInt32(radialSegments), UInt32(verticalSegments)), inward: inwardNormals,
                                   hemisphere: hemisphere, geometryType: geometryType), allocator: allocator)
        return mesh
    }

    @ObjCClassMethod("newCylinderWithHeight:radii:radialSegments:verticalSegments:geometryType:inwardNormals:allocator:")
    static func newCylinder(height: Float, radii: PerryMDLFloat2, radialSegments: UInt, verticalSegments: UInt, geometryType: Int,
                            inwardNormals: Bool, allocator: NSObject?) -> MDLMesh {
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.load(Shapes.cylinder(extent: SIMD3(radii.v.x, height, radii.v.y), segments: SIMD2(UInt32(radialSegments), UInt32(verticalSegments)),
                                  inward: inwardNormals, topCap: true, bottomCap: true, geometryType: geometryType), allocator: allocator)
        return mesh
    }

    @ObjCClassMethod("newCapsuleWithHeight:radii:radialSegments:verticalSegments:hemisphereSegments:geometryType:inwardNormals:allocator:")
    static func newCapsule(height: Float, radii: PerryMDLFloat2, radialSegments: UInt, verticalSegments: UInt, hemisphereSegments: UInt,
                           geometryType: Int, inwardNormals: Bool, allocator: NSObject?) -> MDLMesh {
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.load(Shapes.capsule(extent: SIMD3(radii.v.x, height, radii.v.y), segments: SIMD2(UInt32(radialSegments), UInt32(verticalSegments)),
                                 hemisphereSegments: Int(hemisphereSegments), inward: inwardNormals, geometryType: geometryType),
                  allocator: allocator)
        return mesh
    }

    @ObjCClassMethod("newEllipticalConeWithHeight:radii:radialSegments:verticalSegments:geometryType:inwardNormals:allocator:")
    static func newEllipticalCone(height: Float, radii: PerryMDLFloat2, radialSegments: UInt, verticalSegments: UInt, geometryType: Int,
                                  inwardNormals: Bool, allocator: NSObject?) -> MDLMesh {
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.load(Shapes.cone(extent: SIMD3(radii.v.x, height, radii.v.y), segments: SIMD2(UInt32(radialSegments), UInt32(verticalSegments)),
                              inward: inwardNormals, geometryType: geometryType), allocator: allocator)
        return mesh
    }

    @ObjCClassMethod("newPlaneWithDimensions:segments:geometryType:allocator:")
    static func newPlane(dimensions: PerryMDLFloat2, segments: PerryMDLUInt2, geometryType: Int, allocator: NSObject?) -> MDLMesh {
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.load(Shapes.plane(extent: SIMD3(dimensions.v.x, 0, dimensions.v.y), segments: segments.v, geometryType: geometryType),
                  allocator: allocator)
        return mesh
    }

    @ObjCClassMethod("newIcosahedronWithRadius:inwardNormals:geometryType:allocator:")
    static func newIcosahedron(radius: Float, inwardNormals: Bool, geometryType: Int, allocator: NSObject?) -> MDLMesh {
        let mesh = MDLMesh(bufferAllocator: allocator)
        mesh.load(Shapes.icosahedron(extent: SIMD3(repeating: radius), inward: inwardNormals, geometryType: geometryType), allocator: allocator)
        return mesh
    }

    @ObjCClassMethod("newIcosahedronWithRadius:inwardNormals:allocator:")
    static func newIcosahedron(radius: Float, inwardNormals: Bool, allocator: NSObject?) -> MDLMesh {
        newIcosahedron(radius: radius, inwardNormals: inwardNormals, geometryType: Geometry.triangles, allocator: allocator)
    }

    @ObjCClassMethod("newSubdividedMesh:submeshIndex:subdivisionLevels:")
    static func newSubdividedMesh(_ mesh: NSObject?, submeshIndex: UInt, subdivisionLevels: UInt) -> MDLMesh? {
        guard let source = mesh.flatMap({ ObjCPeers.peer(of: $0.objcObject) as? MDLMesh }) else { return nil }
        let copy = MDLMesh(bufferAllocator: source.allocatorObject)
        copy.copyContents(of: source, allocator: nil)
        return copy
    }

    /// Builds a generated shape: one buffer of positions, normals and
    /// texture coordinates, one submesh of 16-bit indices, and a material.
    func load(_ shape: Shape, allocator: NSObject?) {
        if let allocator { allocatorObject = allocator }
        nameValue = shape.name
        count = shape.positions.count
        descriptor = MDLVertexDescriptor(Layout.standard)
        var vertices = [Float]()
        vertices.reserveCapacity(count * 8)
        for i in 0..<count {
            let (p, n, t) = (shape.positions[i], shape.normals[i], shape.uvs[i])
            vertices += [p.x, p.y, p.z, n.x, n.y, n.z, t.x, t.y]
        }
        buffers = [vertices.withUnsafeBytes { makeBuffer($0, type: BufferType.vertex, allocator: allocatorObject) }]
        let bits = Indices.bits(forVertexCount: count)
        let indexBuffer = makeBuffer(Indices.bytes(shape.indices, bits: bits), type: BufferType.index, allocator: allocatorObject)
        let material = MDLMaterial(physicallyPlausible: shape.materialName)
        submeshArray = NSMutableArray.with([MDLSubmesh(name: shape.submeshName, indexBuffer: indexBuffer, indexCount: UInt(shape.indices.count),
                                                       indexType: bits, geometryType: shape.geometryType, material: material)])
    }

    // MARK: Properties

    var layout: Layout { Layout(descriptor) }

    var submeshes: [MDLSubmesh] {
        submeshArray?.elements.compactMap { ObjCPeers.peer(of: $0.objcObject) as? MDLSubmesh } ?? []
    }

    @ObjCMethod("vertexDescriptor") func vertexDescriptor() -> MDLVertexDescriptor { descriptor }

    /// A new layout: the attributes it shares with the old one by name are
    /// converted to their new formats and places, the rest initialized.
    @ObjCMethod("setVertexDescriptor:") func setVertexDescriptor(_ newDescriptor: NSObject?) {
        guard let newDescriptor else { return }
        relayout(Layout(newDescriptor))
    }

    @ObjCMethod("vertexCount") func vertexCount() -> UInt { UInt(count) }

    /// A new count: the buffers grow or shrink to it.
    @ObjCMethod("setVertexCount:") func setVertexCount(_ newCount: UInt) {
        guard Int(newCount) != count else { return }
        let values = Dictionary(layout.valid.map { ($0.name, read($0)) }, uniquingKeysWith: { first, _ in first })
        let target = Int(newCount)
        count = target
        write(layout, values.mapValues { Array($0.prefix(target)) })
    }

    @ObjCMethod("vertexBuffers") func vertexBuffers() -> NSObject { NSArray.of(buffers) }
    @ObjCMethod("setVertexBuffers:") func setVertexBuffers(_ array: NSObject?) {
        buffers = array.map { $0.unsafeCast(to: NSArray.self).elements } ?? []
    }

    @ObjCMethod("submeshes") func submeshesObject() -> NSObject? { submeshArray }
    @ObjCMethod("setSubmeshes:") func setSubmeshes(_ array: NSObject?) {
        submeshArray = array.map { NSMutableArray.with($0.unsafeCast(to: NSArray.self).elements) }
    }

    @ObjCMethod("allocator") func allocator() -> NSObject { allocatorObject }

    override func ownBounds(at time: Double) -> PerryMDLBoundingBox {
        guard let position = layout.attribute(named: AttributeName.position) else { return .empty }
        let points = read(position)
        var box = PerryMDLBoundingBox.empty
        let lists = submeshes.map(\.indices)
        if lists.isEmpty {
            for p in points { box.add(SIMD3(p.x, p.y, p.z)) }
        } else {
            for list in lists {
                for index in list where Int(index) < points.count {
                    let p = points[Int(index)]
                    box.add(SIMD3(p.x, p.y, p.z))
                }
            }
        }
        return box
    }

    @ObjCMethod("boundingBox") func boundingBox() -> PerryMDLBoundingBox { ownBounds(at: 0).reported }

    // MARK: Attribute data

    /// The bytes of the buffer an attribute is in, while `body` runs.
    func withAttributeBytes<Result>(_ attribute: Attribute, _ body: (UnsafeMutableRawPointer?, Int, NSObject) -> Result) -> Result? {
        guard attribute.bufferIndex < buffers.count else { return nil }
        let buffer = buffers[attribute.bufferIndex]
        return withBytes(of: buffer) { body($0, $1, buffer) }
    }

    /// An attribute's values for every vertex, as floats.
    func read(_ attribute: Attribute) -> [SIMD4<Float>] {
        let stride = layout.stride(attribute.bufferIndex), size = VertexFormat.size(attribute.format), count = count
        return withAttributeBytes(attribute) { pointer, length, _ in
            guard let pointer else { return [] }
            return (0..<count).map { i in
                let at = i * stride + attribute.offset
                guard at + size <= length else { return attribute.initialValue }
                return VertexFormat.read(attribute.format, pointer + at)
            }
        } ?? []
    }

    func read(named name: String) -> [SIMD4<Float>]? { layout.attribute(named: name).map(read) }

    /// Writes an attribute's values in place.
    func overwrite(_ attribute: Attribute, _ values: [SIMD4<Float>]) {
        let stride = layout.stride(attribute.bufferIndex), size = VertexFormat.size(attribute.format)
        _ = withAttributeBytes(attribute) { pointer, length, _ in
            guard let pointer else { return }
            for (i, value) in values.prefix(count).enumerated() {
                let at = i * stride + attribute.offset
                if at + size <= length { VertexFormat.write(attribute.format, pointer + at, value) }
            }
        }
    }

    /// New buffers of `layout` for `count` vertices, from `values` by name,
    /// each missing attribute filled with its initialization value.
    func write(_ newLayout: Layout, _ values: [String: [SIMD4<Float>]]) {
        let valid = newLayout.valid
        var strides = newLayout.strides
        var made: [NSObject] = []
        for buffer in 0..<newLayout.bufferCount {
            let attributes = valid.filter { $0.bufferIndex == buffer }
            var stride = newLayout.stride(buffer)
            if stride == 0 {
                stride = attributes.map { $0.offset + VertexFormat.size($0.format) }.max() ?? 0
                while strides.count <= buffer { strides.append(0) }
                strides[buffer] = stride
            }
            var bytes = [UInt8](repeating: 0, count: stride * count)
            bytes.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                for attribute in attributes {
                    let source = values[attribute.name]
                    let size = VertexFormat.size(attribute.format)
                    for i in 0..<count where attribute.offset + size <= stride {
                        let value = source.flatMap { i < $0.count ? $0[i] : nil } ?? attribute.initialValue
                        VertexFormat.write(attribute.format, base + i * stride + attribute.offset, value)
                    }
                }
            }
            made.append(makeBuffer(bytes, type: BufferType.vertex, allocator: allocatorObject))
        }
        buffers = made
        var stored = newLayout
        stored.strides = strides
        descriptor = MDLVertexDescriptor(stored)
    }

    func relayout(_ newLayout: Layout) {
        let values = Dictionary(layout.valid.map { ($0.name, read($0)) }, uniquingKeysWith: { first, _ in first })
        write(newLayout, values)
    }

    /// Adds an attribute in a buffer of its own after the others.
    func append(_ name: String, format: UInt, values: [SIMD4<Float>], time: Double = 0) {
        var newLayout = layout
        let buffer = max(newLayout.bufferCount, buffers.count)
        var attribute = Attribute(name: name, format: format, offset: 0, bufferIndex: buffer)
        attribute.time = time
        if let slot = newLayout.attributes.firstIndex(where: { !VertexFormat.isValid($0.format) }) {
            newLayout.attributes[slot] = attribute
        } else {
            newLayout.attributes.append(attribute)
        }
        while newLayout.strides.count <= buffer { newLayout.strides.append(0) }
        newLayout.strides[buffer] = VertexFormat.size(format)
        var bytes = [UInt8](repeating: 0, count: VertexFormat.size(format) * count)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                VertexFormat.write(format, base + i * VertexFormat.size(format), i < values.count ? values[i] : attribute.initialValue)
            }
        }
        while buffers.count < buffer { buffers.append(makeBuffer([], type: BufferType.vertex, allocator: allocatorObject)) }
        buffers.append(makeBuffer(bytes, type: BufferType.vertex, allocator: allocatorObject))
        descriptor = MDLVertexDescriptor(newLayout)
    }

    /// Writes `values` into the named attribute, or adds it.
    func store(_ name: String, format: UInt, values: [SIMD4<Float>]) {
        if let attribute = layout.attribute(named: name) {
            overwrite(attribute, values)
        } else {
            append(name, format: format, values: values)
        }
    }

    @ObjCMethod("vertexAttributeDataForAttributeNamed:") func vertexAttributeData(named name: String?) -> MDLVertexAttributeData? {
        guard let name, let attribute = layout.attribute(named: name), attribute.bufferIndex < buffers.count else { return nil }
        let buffer = buffers[attribute.bufferIndex]
        let map: NSObject? = (ObjCPeers.peer(of: buffer.objcObject) as? MDLMeshBufferData)?.map() ?? buffer.sendMap()
        let start = map.flatMap { ObjCPeers.peer(of: $0.objcObject) as? MDLMeshBufferMap }?.pointer ?? map?.sendBytes()
        let length = Int(buffer.sendLength())
        return MDLVertexAttributeData(map: map, start: start.map { $0 + attribute.offset }, stride: layout.stride(attribute.bufferIndex),
                                      format: attribute.format, bufferSize: length - attribute.offset)
    }

    /// The attribute converted to `format`, in bytes of its own.
    @ObjCMethod("vertexAttributeDataForAttributeNamed:asFormat:")
    func vertexAttributeData(named name: String?, asFormat format: UInt) -> MDLVertexAttributeData? {
        guard let name, let attribute = layout.attribute(named: name) else { return nil }
        if attribute.format == format { return vertexAttributeData(named: name) }
        guard VertexFormat.isValid(format) else { return nil }
        let values = read(attribute)
        let size = VertexFormat.size(format)
        let data = NSMutableData.make(count: size * count)
        guard let base = data.mutableBytes() else { return nil }
        for (i, value) in values.enumerated() { VertexFormat.write(format, base + i * size, value) }
        let map = MDLMeshBufferMap(bytes: base, owner: data)
        return MDLVertexAttributeData(map: map, start: base, stride: size, format: format, bufferSize: size * count)
    }

    // MARK: Modifiers

    @ObjCMethod("addAttributeWithName:format:") func addAttribute(name: String?, format: UInt) {
        guard let name, layout.attribute(named: name) == nil, VertexFormat.isValid(format) else { return }
        append(name, format: format, values: [])
    }

    @ObjCMethod("addAttributeWithName:format:type:data:stride:")
    func addAttribute(name: String?, format: UInt, type: String?, data: NSObject?, stride: Int) {
        addAttribute(name: name, format: format, type: type, data: data, stride: stride, time: 0)
    }

    @ObjCMethod("addAttributeWithName:format:type:data:stride:time:")
    func addAttribute(name: String?, format: UInt, type: String?, data: NSObject?, stride: Int, time: Double) {
        guard let name, VertexFormat.isValid(format) else { return }
        let bytes = data.map { $0.unsafeCast(to: NSData.self).array } ?? []
        let size = VertexFormat.size(format), step = stride > 0 ? stride : size
        let values: [SIMD4<Float>] = bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return [] }
            return (0..<count).compactMap { i in i * step + size <= raw.count ? VertexFormat.read(format, base + i * step) : nil }
        }
        if layout.attribute(named: name) != nil { removeAttribute(named: name) }
        append(name, format: format, values: values, time: time)
    }

    @ObjCMethod("removeAttributeNamed:") func removeAttribute(named name: String?) {
        guard let name else { return }
        var newLayout = layout
        for index in newLayout.attributes.indices where newLayout.attributes[index].name == name {
            newLayout.attributes[index] = Attribute(name: "", format: 0, offset: 0, bufferIndex: 0)
        }
        descriptor = MDLVertexDescriptor(newLayout)
    }

    /// Copies another attribute data's values into the attribute.
    @ObjCMethod("replaceAttributeNamed:withData:") func replaceAttribute(named name: String?, data: NSObject?) {
        updateAttribute(named: name, data: data)
    }

    @ObjCMethod("updateAttributeNamed:withData:") func updateAttribute(named name: String?, data: NSObject?) {
        guard let name, let data, let attribute = layout.attribute(named: name), let start = data.sendDataStart() else { return }
        let format = data.sendFormat(), stride = Int(data.sendStride())
        let step = stride > 0 ? stride : VertexFormat.size(format)
        overwrite(attribute, (0..<count).map { VertexFormat.read(format, start + $0 * step) })
    }

    /// One vertex for every index: each triangle's corners its own.
    @ObjCMethod("makeVerticesUnique") func makeVerticesUnique() { _ = unweld() }

    @ObjCMethod("makeVerticesUniqueAndReturnError:")
    func makeVerticesUnique(error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        _ = unweld()
        return true
    }

    /// Makes every index its own vertex; returns each new vertex's old one.
    func unweld() -> [Int] {
        var order: [Int] = []
        var lists: [[UInt32]] = []
        for submesh in submeshes {
            let indices = submesh.indices
            lists.append((0..<indices.count).map { UInt32(order.count + $0) })
            order += indices.map { Int($0) }
        }
        let current = layout
        let values = Dictionary(current.valid.map { attribute -> (String, [SIMD4<Float>]) in
            let old = read(attribute)
            return (attribute.name, order.map { $0 < old.count ? old[$0] : attribute.initialValue })
        }, uniquingKeysWith: { first, _ in first })
        count = order.count
        write(current, values)
        for (submesh, list) in zip(submeshes, lists) { submesh.replaceIndices(list, vertexCount: count) }
        return order
    }

    /// The triangles of every submesh, as vertex indices.
    var triangles: [(UInt32, UInt32, UInt32)] {
        var result: [(UInt32, UInt32, UInt32)] = []
        let lists = submeshes.isEmpty ? [(0..<UInt32(count)).map { $0 }] : submeshes.filter { $0.geometry != Geometry.lines && $0.geometry != Geometry.points }.map(\.triangleIndices)
        for list in lists {
            var i = 0
            while i + 2 < list.count {
                if Int(max(list[i], list[i + 1], list[i + 2])) < count { result.append((list[i], list[i + 1], list[i + 2])) }
                i += 3
            }
        }
        return result
    }

    /// Normals from the triangles: each corner's the average of the faces
    /// at its position that meet its own at less than the crease (whose
    /// normals' dot product is at least the threshold).
    @ObjCMethod("addNormalsWithAttributeNamed:creaseThreshold:")
    func addNormals(attributeName: String?, creaseThreshold: Float) {
        guard let positionAttribute = layout.attribute(named: AttributeName.position) else { return }
        let name = attributeName ?? AttributeName.normal
        _ = unweld()
        let positions = read(positionAttribute).map { SIMD3($0.x, $0.y, $0.z) }
        let faces = triangles
        var byPosition: [SIMD3<Float>: [Int]] = [:]
        var weighted: [SIMD3<Float>] = []
        for (f, triangle) in faces.enumerated() {
            let (a, b, c) = (Int(triangle.0), Int(triangle.1), Int(triangle.2))
            let n = cross(positions[b] - positions[a], positions[c] - positions[a])
            weighted.append(n)
            for corner in [a, b, c] { byPosition[positions[corner], default: []].append(f) }
        }
        var normals = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 0), count: count)
        for (f, triangle) in faces.enumerated() {
            let own = normalize(weighted[f])
            for corner in [Int(triangle.0), Int(triangle.1), Int(triangle.2)] {
                var sum = SIMD3<Float>.zero
                for other in byPosition[positions[corner]] ?? [] where dot(normalize(weighted[other]), own) >= creaseThreshold || other == f {
                    sum += weighted[other]
                }
                let n = normalize(sum == .zero ? own : sum)
                normals[corner] = SIMD4(n.x, n.y, n.z, 0)
            }
        }
        store(name, format: VertexFormat.float3, values: normals)
    }

    /// Tangents (and bitangents) from positions, texture coordinates and,
    /// when given, normals.
    func tangentBasis(textureCoordinates: String, normals normalName: String?) -> (tangents: [SIMD3<Float>], bitangents: [SIMD3<Float>],
                                                                                     normals: [SIMD3<Float>])? {
        guard let positions = read(named: AttributeName.position)?.map({ SIMD3($0.x, $0.y, $0.z) }),
              let uvs = read(named: textureCoordinates)?.map({ SIMD2($0.x, $0.y) }) else { return nil }
        var tangents = [SIMD3<Float>](repeating: .zero, count: count)
        var bitangents = [SIMD3<Float>](repeating: .zero, count: count)
        var faceNormals = [SIMD3<Float>](repeating: .zero, count: count)
        for (a, b, c) in triangles {
            let (i, j, k) = (Int(a), Int(b), Int(c))
            let e1 = positions[j] - positions[i], e2 = positions[k] - positions[i]
            let d1 = uvs[j] - uvs[i], d2 = uvs[k] - uvs[i]
            let det = d1.x * d2.y - d2.x * d1.y
            let r: Float = det == 0 ? 0 : 1 / det
            let t = (e1 * d2.y - e2 * d1.y) * r
            let bt = (e2 * d1.x - e1 * d2.x) * r
            let n = cross(e1, e2)
            for v in [i, j, k] {
                tangents[v] += t
                bitangents[v] += bt
                faceNormals[v] += n
            }
        }
        let normals = normalName.flatMap { read(named: $0) }?.map { normalize(SIMD3($0.x, $0.y, $0.z)) } ?? faceNormals.map(normalize)
        return (tangents, bitangents, normals)
    }

    @ObjCMethod("addTangentBasisForTextureCoordinateAttributeNamed:tangentAttributeNamed:bitangentAttributeNamed:")
    func addTangentBasis(textureCoordinateAttributeName uv: String?, tangentAttributeName: String?, bitangentAttributeName: String?) {
        guard let uv, let basis = tangentBasis(textureCoordinates: uv, normals: nil) else { return }
        if let tangentAttributeName {
            store(tangentAttributeName, format: VertexFormat.float3, values: basis.tangents.map { let t = normalize($0); return SIMD4(t.x, t.y, t.z, 0) })
        }
        if let bitangentAttributeName {
            store(bitangentAttributeName, format: VertexFormat.float3,
                  values: basis.bitangents.map { let b = normalize($0); return SIMD4(b.x, b.y, b.z, 0) })
        }
    }

    @ObjCMethod("addTangentBasisForTextureCoordinateAttributeNamed:normalAttributeNamed:tangentAttributeNamed:")
    func addTangentBasis(textureCoordinateAttributeName uv: String?, normalAttributeName: String?, tangentAttributeName: String?) {
        guard let uv, let tangentAttributeName, let basis = tangentBasis(textureCoordinates: uv, normals: normalAttributeName) else { return }
        let values = zip(basis.tangents, basis.normals).map { t, n -> SIMD4<Float> in
            let o = normalize(t - n * dot(n, t))
            return SIMD4(o.x, o.y, o.z, 0)
        }
        store(tangentAttributeName, format: VertexFormat.float3, values: values)
    }

    /// Tangents made orthogonal to the normals, with the bitangent's
    /// handedness in w; bitangents, when named, likewise.
    @ObjCMethod("addOrthTanBasisForTextureCoordinateAttributeNamed:normalAttributeNamed:tangentAttributeNamed:")
    func addOrthTanBasis(textureCoordinateAttributeName uv: String?, normalAttributeName: String?, tangentAttributeName: String?) {
        guard let uv, let tangentAttributeName, let basis = tangentBasis(textureCoordinates: uv, normals: normalAttributeName) else { return }
        var values: [SIMD4<Float>] = []
        for i in 0..<count {
            let (t, b, n) = (basis.tangents[i], basis.bitangents[i], basis.normals[i])
            let o = normalize(t - n * dot(n, t))
            values.append(SIMD4(o.x, o.y, o.z, dot(cross(n, t), b) < 0 ? -1 : 1))
        }
        store(tangentAttributeName, format: VertexFormat.float4, values: values)
    }

    /// Texture coordinates where there are none; existing ones are kept.
    @ObjCMethod("addUnwrappedTextureCoordinatesForAttributeNamed:") func addUnwrappedTextureCoordinates(named name: String?) {
        let name = name ?? AttributeName.textureCoordinate
        guard layout.attribute(named: name) == nil, let positions = read(named: AttributeName.position) else { return }
        let box = ownBounds(at: 0)
        let size = box.isEmpty ? SIMD3<Float>(repeating: 1) : box.maxBounds - box.minBounds
        let values = positions.map { p -> SIMD4<Float> in
            let u = size.x > 0 ? (p.x - box.minBounds.x) / size.x : 0, v = size.z > 0 ? (p.z - box.minBounds.z) / size.z : 0
            return SIMD4(u, v, 0, 1)
        }
        append(name, format: VertexFormat.float2, values: values)
    }

    @ObjCMethod("flipTextureCoordinatesInAttributeNamed:") func flipTextureCoordinates(named name: String?) {
        guard let name, let attribute = layout.attribute(named: name) else { return }
        overwrite(attribute, read(attribute).map { SIMD4($0.x, 1 - $0.y, $0.z, $0.w) })
    }

    // Light baking, which needs Model I/O's ray tracer: none is done.
    @ObjCMethod("generateAmbientOcclusionTextureWithSize:raysPerSample:attenuationFactor:objectsToConsider:vertexAttributeNamed:materialPropertyNamed:")
    func generateAmbientOcclusionTexture(size: PerryMDLInt2, rays: Int, attenuation: Float, objects: NSObject?, attribute: String?,
                                         property: String?) -> Bool { false }
    @ObjCMethod("generateAmbientOcclusionTextureWithQuality:attenuationFactor:objectsToConsider:vertexAttributeNamed:materialPropertyNamed:")
    func generateAmbientOcclusionTexture(quality: Float, attenuation: Float, objects: NSObject?, attribute: String?, property: String?) -> Bool {
        false
    }
    @ObjCMethod("generateAmbientOcclusionVertexColorsWithRaysPerSample:attenuationFactor:objectsToConsider:vertexAttributeNamed:")
    func generateAmbientOcclusionVertexColors(rays: Int, attenuation: Float, objects: NSObject?, attribute: String?) -> Bool { false }
    @ObjCMethod("generateAmbientOcclusionVertexColorsWithQuality:attenuationFactor:objectsToConsider:vertexAttributeNamed:")
    func generateAmbientOcclusionVertexColors(quality: Float, attenuation: Float, objects: NSObject?, attribute: String?) -> Bool { false }
    @ObjCMethod("generateLightMapTextureWithTextureSize:lightsToConsider:objectsToConsider:vertexAttributeNamed:materialPropertyNamed:")
    func generateLightMapTexture(size: PerryMDLInt2, lights: NSObject?, objects: NSObject?, attribute: String?, property: String?) -> Bool { false }
    @ObjCMethod("generateLightMapTextureWithQuality:lightsToConsider:objectsToConsider:vertexAttributeNamed:materialPropertyNamed:")
    func generateLightMapTexture(quality: Float, lights: NSObject?, objects: NSObject?, attribute: String?, property: String?) -> Bool { false }
    @ObjCMethod("generateLightMapVertexColorsWithLightsToConsider:objectsToConsider:vertexAttributeNamed:")
    func generateLightMapVertexColors(lights: NSObject?, objects: NSObject?, attribute: String?) -> Bool { false }
}
