import PerryObjCInterop

// MetalKit's bridge to Model I/O: vertex descriptors converted between
// Metal's and Model I/O's, and MTKMesh. Model I/O's classes are Model I/O's
// provider's, which Perry doesn't have, so they are reached only by
// messages and looked up by name: a Model I/O vertex descriptor an app hands
// over converts to a Metal one, while making a Model I/O descriptor, or a
// mesh from a Model I/O mesh or asset, fails as MetalKit does when it can't,
// with an error in MTKModelErrorDomain.

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
/// from Model I/O's own classes, so nil with an error when no provider has
/// registered them, as here.
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

/// MetalKit's mesh of a Model I/O mesh, its buffers in Metal buffers. With
/// no Model I/O there is no mesh to make one from: the initializer and the
/// asset loader fail with an error, and a mesh never exists.
@ObjCClass("MTKMesh")
open class MTKMesh: NSObject {
    @ObjCMethod("initWithMesh:device:error:")
    func initialize(mesh: NSObject?, device: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self? {
        MetalKitModel.fail(error, "Model I/O meshes are not available")
        return nil
    }

    @ObjCClassMethod("newMeshesFromAsset:device:sourceMeshes:error:")
    static func newMeshes(asset: NSObject?, device: NSObject?, sourceMeshes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                          error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSObject? {
        sourceMeshes?.pointee = nil
        MetalKitModel.fail(error, "Model I/O assets are not available")
        return nil
    }

    @ObjCMethod("vertexBuffers") func vertexBuffers() -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("vertexDescriptor") func vertexDescriptor() -> NSObject? { nil }
    @ObjCMethod("submeshes") func submeshes() -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("vertexCount") func vertexCount() -> UInt { 0 }
    @ObjCMethod("name") func name() -> String { "" }
    @ObjCMethod("setName:") func setName(_ name: String?) {}
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
}
