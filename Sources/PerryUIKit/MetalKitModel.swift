import PerryObjCInterop

// MetalKit's bridge to Model I/O: vertex descriptors converted between
// Metal's and Model I/O's, the mesh buffer allocator that keeps Model I/O
// meshes in Metal buffers, and MTKMesh. Model I/O's classes are Model I/O's
// provider's (libPerryModelIO), so they are reached only by messages and
// looked up by name; without that provider, making a Model I/O descriptor
// fails as MetalKit does when it can't, with an error in
// MTKModelErrorDomain.

@ObjCConstants
enum MetalKitModelConstants {
    static let MTKModelErrorDomain = "MTKModelErrorDomain"
    static let MTKModelErrorKey = "MTKModelErrorKey"
}

enum MetalKitModel {
    /// MDLVertexFormat's element types (its bits above the count), in order
    /// from UCharBits (0x10000) to FloatBits (0xC0000).
    private enum Element: UInt {
        case uchar = 1, char, ucharNormalized, charNormalized, ushort, short, ushortNormalized, shortNormalized,
             uint, int, half, float
    }

    /// The MTLVertexFormat of an MDLVertexFormat, or nil for an invalid one.
    static func metalFormat(_ format: UInt) -> UInt? {
        let count = format & 0xFFF, packed = format & 0x1000 != 0
        guard let element = Element(rawValue: (format >> 16) & 0xF), (1...4).contains(count) else { return nil }
        if packed {
            guard count == 4 else { return nil }
            switch element {
            case .int: return 40      // Int1010102Normalized
            case .uint: return 41     // UInt1010102Normalized
            default: return nil
            }
        }
        // The two-to-four-component formats, by element: the first's value.
        let vectors: [Element: UInt] = [.uchar: 1, .char: 4, .ucharNormalized: 7, .charNormalized: 10, .ushort: 13, .short: 16,
                                        .ushortNormalized: 19, .shortNormalized: 22, .half: 25, .float: 29, .int: 33, .uint: 37]
        let scalars: [Element: UInt] = [.uchar: 45, .char: 46, .ucharNormalized: 47, .charNormalized: 48, .ushort: 49, .short: 50,
                                        .ushortNormalized: 51, .shortNormalized: 52, .half: 53, .float: 28, .int: 32, .uint: 36]
        return count == 1 ? scalars[element] : vectors[element].map { $0 + count - 2 }
    }

    /// The MDLVertexFormat of an MTLVertexFormat, or nil for one Model I/O
    /// has no format for (BGRA order, the packed floats).
    static func modelIOFormat(_ format: UInt) -> UInt? {
        for element: UInt in 1...12 {
            for count: UInt in 1...4 {
                let candidate = element << 16 | count
                if metalFormat(candidate) == format { return candidate }
            }
        }
        switch format {
        case 40: return 0xA0000 | 0x1000 | 4
        case 41: return 0x90000 | 0x1000 | 4
        default: return nil
        }
    }

    static func fail(_ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ message: String) {
        guard let error else { return }
        let info = NSDictionary.make(object: NSObject(objCReturnValue: message.objCArgument()), forKey: "NSLocalizedDescription")
        error.pointee = NSErrorObject.make(domain: MetalKitModelConstants.MTKModelErrorDomain, code: 0, userInfo: info)
            .objCReturnValue()
    }

    /// A class by name, when some provider has registered it.
    static func registered(_ name: String) -> NSObject? { ObjCRuntime.registeredClassPair(name).map { NSObject($0.cls) } }
}

/// The Metal descriptor of a Model I/O one: each attribute with a format at
/// its own index, each layout's stride per vertex, autoreleased; nil with an
/// error if an attribute's format has no Metal format.
@c(_MTKMetalVertexDescriptorFromModelIOWithError)
public func MTKMetalVertexDescriptorFromModelIOWithError(_ modelIO: UnsafeMutableRawPointer?,
                                                         _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let modelIO, let metalClass = MetalKitModel.registered("MTLVertexDescriptor") else {
        MetalKitModel.fail(error, modelIO == nil ? "No Model I/O vertex descriptor" : "Metal has no vertex descriptors")
        return nil
    }
    let source = NSObject(modelIO)
    guard let descriptor = metalClass.mtkSendVertexDescriptor() else { return nil }
    let attributes = source.mtkAttributes().map { $0.unsafeCast(to: NSArray.self).elements } ?? []
    for (index, attribute) in attributes.enumerated() {
        let format = attribute.mtkFormat()
        guard format != 0 else { continue }
        guard let metal = MetalKitModel.metalFormat(format) else {
            MetalKitModel.fail(error, "Model I/O vertex format \(format) has no Metal vertex format")
            return nil
        }
        let target = descriptor.mtkAttributeArray().mtkObject(atIndexedSubscript: UInt(index))
        target.mtkSetFormat(metal)
        target.mtkSetOffset(attribute.mtkOffset())
        target.mtkSetBufferIndex(attribute.mtkBufferIndex())
    }
    let layouts = source.mtkLayouts().map { $0.unsafeCast(to: NSArray.self).elements } ?? []
    for (index, layout) in layouts.enumerated() {
        let stride = layout.mtkStride()
        guard stride > 0 else { continue }
        let target = descriptor.mtkLayoutArray().mtkObject(atIndexedSubscript: UInt(index))
        target.mtkSetStride(stride)
        target.mtkSetStepFunction(1)    // MTLVertexStepFunctionPerVertex
        target.mtkSetStepRate(1)
    }
    return descriptor.objCReturnValue()
}

@c(_MTKMetalVertexDescriptorFromModelIO)
public func MTKMetalVertexDescriptorFromModelIO(_ modelIO: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    MTKMetalVertexDescriptorFromModelIOWithError(modelIO, nil)
}

/// The Model I/O descriptor of a Metal one: an unnamed attribute for each
/// with a format, a layout for each buffer with a stride, autoreleased. Made
/// from Model I/O's own classes, so nil with an error when Model I/O's
/// provider isn't loaded.
@c(_MTKModelIOVertexDescriptorFromMetalWithError)
public func MTKModelIOVertexDescriptorFromMetalWithError(_ metal: UnsafeMutableRawPointer?,
                                                         _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let metal else {
        MetalKitModel.fail(error, "No Metal vertex descriptor")
        return nil
    }
    guard let descriptorClass = MetalKitModel.registered("MDLVertexDescriptor"),
          let attributeClass = MetalKitModel.registered("MDLVertexAttribute"),
          let layoutClass = MetalKitModel.registered("MDLVertexBufferLayout") else {
        MetalKitModel.fail(error, "Model I/O is not available")
        return nil
    }
    let source = NSObject(metal)
    let descriptor = descriptorClass.mtkNewObject()
    var attributes: [NSObject] = [], layouts: [NSObject] = []
    // Metal's descriptors have 31 attribute and 31 buffer slots.
    for index in 0..<31 {
        let attribute = source.mtkAttributeArray().mtkObject(atIndexedSubscript: UInt(index))
        let format = attribute.mtkFormat()
        let made = attributeClass.mtkNewObject()
        if format != 0 {
            guard let modelIO = MetalKitModel.modelIOFormat(format) else {
                MetalKitModel.fail(error, "Metal vertex format \(format) has no Model I/O vertex format")
                return nil
            }
            made.mtkSetFormat(modelIO)
            made.mtkSetOffset(attribute.mtkOffset())
            made.mtkSetBufferIndex(attribute.mtkBufferIndex())
        }
        attributes.append(made)
        let layout = layoutClass.mtkNewObject()
        layout.mtkSetStride(source.mtkLayoutArray().mtkObject(atIndexedSubscript: UInt(index)).mtkStride())
        layouts.append(layout)
    }
    descriptor.mtkSetAttributes(NSMutableArray.of(attributes))
    descriptor.mtkSetLayouts(NSMutableArray.of(layouts))
    return descriptor.objCReturnValue()
}

@c(_MTKModelIOVertexDescriptorFromMetal)
public func MTKModelIOVertexDescriptorFromMetal(_ metal: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    MTKModelIOVertexDescriptorFromMetalWithError(metal, nil)
}

/// MTKMeshBufferAllocator: Model I/O meshes it allocates for keep their
/// vertices and indices in Metal buffers, which MTKMesh then uses as they are.
@ObjCClass("MTKMeshBufferAllocator")
open class MTKMeshBufferAllocator: NSObject {
    var deviceObject: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithDevice:") public init(device: NSObject?) {
        deviceObject = device
        super.init()
    }

    @ObjCMethod("device") func device() -> NSObject? { deviceObject }

    @ObjCMethod("newZone:") func newZone(capacity: UInt) -> NSObject { MTKMeshBufferZone(capacity: capacity, allocator: self) }

    @ObjCMethod("newZoneForBuffersWithSize:andType:") func newZone(sizes: NSObject?, types: NSObject?) -> NSObject {
        let sizes = sizes.map { $0.unsafeCast(to: NSArray.self).elements } ?? []
        return MTKMeshBufferZone(capacity: sizes.reduce(UInt(0)) { $0 + $1.mtkUnsignedIntegerValue() }, allocator: self)
    }

    @ObjCMethod("newBuffer:type:") func newBuffer(length: UInt, type: UInt) -> NSObject? {
        MTKMeshBuffer.make(device: deviceObject, bytes: nil, length: length, type: type, allocator: self)
    }

    @ObjCMethod("newBufferWithData:type:") func newBuffer(data: NSObject?, type: UInt) -> NSObject? {
        MTKMeshBuffer.make(device: deviceObject, bytes: data?.mtkBytes(), length: data?.mtkLength() ?? 0, type: type, allocator: self)
    }

    @ObjCMethod("newBufferFromZone:length:type:") func newBuffer(zone: NSObject?, length: UInt, type: UInt) -> NSObject? {
        let buffer = MTKMeshBuffer.make(device: deviceObject, bytes: nil, length: length, type: type, allocator: self)
        buffer?.zoneObject = zone
        return buffer
    }

    @ObjCMethod("newBufferFromZone:data:type:") func newBuffer(zone: NSObject?, data: NSObject?, type: UInt) -> NSObject? {
        let buffer = MTKMeshBuffer.make(device: deviceObject, bytes: data?.mtkBytes(), length: data?.mtkLength() ?? 0, type: type, allocator: self)
        buffer?.zoneObject = zone
        return buffer
    }
}

/// A zone of an MTKMeshBufferAllocator: only its capacity is kept.
@ObjCClass("MTKMeshBufferZone")
open class MTKMeshBufferZone: NSObject {
    var capacityValue: UInt = 0
    weak var allocatorObject: MTKMeshBufferAllocator?

    @ObjCMethod("init") public required override init() { super.init() }

    init(capacity: UInt, allocator: MTKMeshBufferAllocator) {
        capacityValue = capacity
        allocatorObject = allocator
        super.init()
    }

    @ObjCMethod("capacity") func capacity() -> UInt { capacityValue }
    @ObjCMethod("allocator") func allocator() -> NSObject? { allocatorObject }
}

/// A Model I/O mesh buffer in a Metal buffer: the Metal buffer, and where
/// in it the mesh buffer's bytes are.
@ObjCClass("MTKMeshBuffer")
open class MTKMeshBuffer: NSObject {
    var bufferObject: NSObject?
    var offsetValue: UInt = 0
    var lengthValue: UInt = 0
    var typeValue: UInt = 1
    var allocatorObject: NSObject?
    var zoneObject: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    init(buffer: NSObject, length: UInt, type: UInt, allocator: NSObject?) {
        bufferObject = buffer
        lengthValue = length
        typeValue = type
        allocatorObject = allocator
        super.init()
    }

    /// A shared Metal buffer of `length` bytes, a copy of `bytes` when given;
    /// nil without a device.
    static func make(device: NSObject?, bytes: UnsafeRawPointer?, length: UInt, type: UInt, allocator: NSObject?) -> MTKMeshBuffer? {
        guard let device else { return nil }
        // At least a byte: Metal makes no empty buffers.
        let size = max(length, 1)
        let made = bytes.flatMap { length > 0 ? device.mtkNewBuffer(bytes: $0, length: length, options: 0) : nil }
            ?? device.mtkNewBuffer(length: size, options: 0)
        guard let made else { return nil }
        return MTKMeshBuffer(buffer: made, length: length, type: type, allocator: allocator)
    }

    var contents: UnsafeMutableRawPointer? { bufferObject?.mtkContents().map { $0 + Int(offsetValue) } }

    @ObjCMethod("length") func length() -> UInt { lengthValue }
    @ObjCMethod("offset") func offset() -> UInt { offsetValue }
    @ObjCMethod("buffer") func buffer() -> NSObject? { bufferObject }
    @ObjCMethod("type") func type() -> UInt { typeValue }
    @ObjCMethod("allocator") func allocator() -> NSObject? { allocatorObject }
    @ObjCMethod("zone") func zone() -> NSObject? { zoneObject }

    /// Model I/O's map of the bytes, valid while this buffer is.
    @ObjCMethod("map") func map() -> NSObject? {
        guard let mapClass = MetalKitModel.registered("MDLMeshBufferMap") else { return nil }
        return mapClass.mtkAlloc().mtkInitMap(bytes: contents, deallocator: nil)
    }

    @ObjCMethod("fillData:offset:") func fill(data: NSObject?, offset: UInt) {
        guard let data, let bytes = data.mtkBytes(), let target = contents, offset < lengthValue else { return }
        let count = min(Int(data.mtkLength()), Int(lengthValue - offset))
        (target + Int(offset)).copyMemory(from: bytes, byteCount: count)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTKMeshBuffer? {
        let device = (allocatorObject.flatMap { ObjCPeers.peer(of: $0.objcObject) as? MTKMeshBufferAllocator })?.deviceObject
            ?? bufferObject?.mtkDevice()
        return MTKMeshBuffer.make(device: device, bytes: contents, length: lengthValue, type: typeValue, allocator: allocatorObject)
    }
}

/// A submesh's indices in a Metal buffer, and how to draw them.
@ObjCClass("MTKSubmesh")
open class MTKSubmesh: NSObject {
    var primitive: UInt = 3
    var indexTypeValue: UInt = 0
    var indexBufferObject: MTKMeshBuffer?
    var count: UInt = 0
    weak var meshObject: MTKMesh?
    var nameValue = ""

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("primitiveType") func primitiveType() -> UInt { primitive }
    @ObjCMethod("indexType") func indexType() -> UInt { indexTypeValue }
    @ObjCMethod("indexBuffer") func indexBuffer() -> NSObject? { indexBufferObject }
    @ObjCMethod("indexCount") func indexCount() -> UInt { count }
    @ObjCMethod("mesh") func mesh() -> NSObject? { meshObject }
    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ name: String?) { nameValue = name ?? "" }
}

/// MetalKit's mesh of a Model I/O mesh: its vertex buffers and submeshes'
/// index buffers in Metal buffers (those an MTKMeshBufferAllocator made
/// already are, the rest are copied), its vertex descriptor and count.
@ObjCClass("MTKMesh")
open class MTKMesh: NSObject {
    var buffers: [MTKMeshBuffer] = []
    var descriptor: NSObject?
    var submeshList: [MTKSubmesh] = []
    var count: UInt = 0
    var nameValue = ""

    /// The allocator, its buffers and zones adopt Model I/O's protocols,
    /// declared here when Model I/O hasn't yet; MTKMesh is defined after them.
    open override class func didDefineObjCClass(_ cls: ObjCClass) {
        for (proto, className) in [("MDLMeshBufferAllocator", "MTKMeshBufferAllocator"), ("MDLMeshBuffer", "MTKMeshBuffer"),
                                   ("MDLMeshBufferZone", "MTKMeshBufferZone")] {
            if ObjCRuntime.protocolObject(proto) == nil { ObjCRuntime.defineProtocol(named: proto, adopting: [], methods: []) }
            ObjCRuntime.registeredClassPair(className).map { ObjCRuntime.addProtocol(named: proto, to: ObjCClass($0.cls)) }
        }
    }

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithMesh:device:error:")
    public init?(mesh: NSObject?, device: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
        guard let mesh else {
            MetalKitModel.fail(error, "No Model I/O mesh")
            return nil
        }
        guard let device else {
            MetalKitModel.fail(error, "No Metal device")
            return nil
        }
        func metalBuffer(_ buffer: NSObject, type: UInt) -> MTKMeshBuffer? {
            if let own = ObjCPeers.peer(of: buffer.objcObject) as? MTKMeshBuffer { return own }
            let map = buffer.mtkMap()
            return withExtendedLifetime(map) {
                MTKMeshBuffer.make(device: device, bytes: map?.mtkBytes(), length: buffer.mtkLength(), type: type, allocator: nil)
            }
        }
        var buffers: [MTKMeshBuffer] = []
        for buffer in mesh.mtkVertexBuffers().map({ $0.unsafeCast(to: NSArray.self).elements }) ?? [] {
            guard let made = metalBuffer(buffer, type: 1) else {
                MetalKitModel.fail(error, "Could not make a Metal buffer for a vertex buffer")
                return nil
            }
            buffers.append(made)
        }
        var submeshes: [MTKSubmesh] = []
        for source in mesh.mtkSubmeshes().map({ $0.unsafeCast(to: NSArray.self).elements }) ?? [] {
            let primitive: UInt
            switch source.mtkGeometryType() {
            case 0: primitive = 0      // points
            case 1: primitive = 1      // lines
            case 2: primitive = 3      // triangles
            case 3: primitive = 4      // triangle strips
            default:
                MetalKitModel.fail(error, "Metal cannot draw a submesh of geometry type \(source.mtkGeometryType())")
                return nil
            }
            // Metal has no 8-bit indices.
            var bits = source.mtkIndexType()
            var indexBuffer = source.mtkIndexBuffer()
            if bits == 8 {
                indexBuffer = source.mtkIndexBuffer(asIndexType: 16)
                bits = 16
            }
            guard let indexBuffer, let made = metalBuffer(indexBuffer, type: 2) else {
                MetalKitModel.fail(error, "Could not make a Metal buffer for an index buffer")
                return nil
            }
            let submesh = MTKSubmesh()
            submesh.primitive = primitive
            submesh.indexTypeValue = bits == 32 ? 1 : 0
            submesh.indexBufferObject = made
            submesh.count = source.mtkIndexCount()
            submesh.nameValue = source.mtkName() ?? ""
            submeshes.append(submesh)
        }
        self.buffers = buffers
        submeshList = submeshes
        descriptor = mesh.mtkSendVertexDescriptor()?.mtkCopy()
        count = mesh.mtkVertexCount()
        nameValue = mesh.mtkName() ?? ""
        super.init()
        for submesh in submeshes { submesh.meshObject = self }
    }

    /// MetalKit meshes of every Model I/O mesh in an asset, and those meshes.
    @ObjCClassMethod("newMeshesFromAsset:device:sourceMeshes:error:")
    static func newMeshes(asset: NSObject?, device: NSObject?, sourceMeshes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                          error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        sourceMeshes?.pointee = nil
        guard let asset, let meshClass = MetalKitModel.registered("MDLMesh") else {
            MetalKitModel.fail(error, "No Model I/O asset")
            return nil
        }
        let sources = asset.mtkChildObjects(ofClass: meshClass.objcObject).map { $0.unsafeCast(to: NSArray.self).elements } ?? []
        var meshes: [NSObject] = []
        for source in sources {
            guard let mesh = MTKMesh(mesh: source, device: device, error: error) else { return nil }
            meshes.append(mesh)
        }
        sourceMeshes?.pointee = NSMutableArray.of(sources).objCReturnValue()
        // new… returns its array retained.
        return NSMutableArray.of(meshes)
    }

    @ObjCMethod("vertexBuffers") func vertexBuffers() -> NSObject { NSMutableArray.of(buffers) }
    @ObjCMethod("vertexDescriptor") func vertexDescriptor() -> NSObject? { descriptor }
    @ObjCMethod("submeshes") func submeshes() -> NSObject { NSMutableArray.of(submeshList) }
    @ObjCMethod("vertexCount") func vertexCount() -> UInt { count }
    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ name: String?) { nameValue = name ?? "" }
}

// MARK: - Messages

extension NSObject {
    @ObjCMethod("vertexDescriptor") func mtkSendVertexDescriptor() -> NSObject?
    @ObjCMethod("new") func mtkNewObject() -> NSObject
    // MDLVertexDescriptor.
    @ObjCMethod("attributes") func mtkAttributes() -> NSObject?
    @ObjCMethod("layouts") func mtkLayouts() -> NSObject?
    @ObjCMethod("setAttributes:") func mtkSetAttributes(_ attributes: NSObject)
    @ObjCMethod("setLayouts:") func mtkSetLayouts(_ layouts: NSObject)
    // MTLVertexDescriptor: the same selectors, giving its arrays.
    @ObjCMethod("attributes") func mtkAttributeArray() -> NSObject
    @ObjCMethod("layouts") func mtkLayoutArray() -> NSObject
    // Attributes and layouts of either.
    @ObjCMethod("format") func mtkFormat() -> UInt
    @ObjCMethod("setFormat:") func mtkSetFormat(_ format: UInt)
    @ObjCMethod("offset") func mtkOffset() -> UInt
    @ObjCMethod("setOffset:") func mtkSetOffset(_ offset: UInt)
    @ObjCMethod("bufferIndex") func mtkBufferIndex() -> UInt
    @ObjCMethod("setBufferIndex:") func mtkSetBufferIndex(_ index: UInt)
    @ObjCMethod("stride") func mtkStride() -> UInt
    @ObjCMethod("setStride:") func mtkSetStride(_ stride: UInt)
    @ObjCMethod("setStepFunction:") func mtkSetStepFunction(_ function: UInt)
    @ObjCMethod("setStepRate:") func mtkSetStepRate(_ rate: UInt)
    // Model I/O's meshes, submeshes, buffers and assets.
    @ObjCMethod("vertexBuffers") func mtkVertexBuffers() -> NSObject?
    @ObjCMethod("submeshes") func mtkSubmeshes() -> NSObject?
    @ObjCMethod("vertexCount") func mtkVertexCount() -> UInt
    @ObjCMethod("name") func mtkName() -> String?
    @ObjCMethod("copy") func mtkCopy() -> NSObject?
    @ObjCMethod("geometryType") func mtkGeometryType() -> Int
    @ObjCMethod("indexType") func mtkIndexType() -> UInt
    @ObjCMethod("indexCount") func mtkIndexCount() -> UInt
    @ObjCMethod("indexBuffer") func mtkIndexBuffer() -> NSObject?
    @ObjCMethod("indexBufferAsIndexType:") func mtkIndexBuffer(asIndexType type: UInt) -> NSObject?
    @ObjCMethod("map") func mtkMap() -> NSObject?
    @ObjCMethod("bytes") func mtkBytes() -> UnsafeMutableRawPointer?
    @ObjCMethod("length") func mtkLength() -> UInt
    @ObjCMethod("unsignedIntegerValue") func mtkUnsignedIntegerValue() -> UInt
    @ObjCMethod("childObjectsOfClass:") func mtkChildObjects(ofClass cls: UnsafeMutableRawPointer?) -> NSObject?
    @ObjCMethod("alloc") func mtkAlloc() -> NSObject
    @ObjCMethod("initWithBytes:deallocator:") func mtkInitMap(bytes: UnsafeMutableRawPointer?, deallocator: UnsafeMutableRawPointer?) -> NSObject?
    // Metal's devices and buffers.
    @ObjCMethod("newBufferWithBytes:length:options:")
    func mtkNewBuffer(bytes: UnsafeRawPointer, length: UInt, options: UInt) -> NSObject?
    @ObjCMethod("newBufferWithLength:options:") func mtkNewBuffer(length: UInt, options: UInt) -> NSObject?
    @ObjCMethod("contents") func mtkContents() -> UnsafeMutableRawPointer?
}
