import CPerryGeometry
import CPerryMetal
import PerryObjCInterop

// Metal's descriptors: plain objects apps fill in and pass to the device or
// a command buffer, which reads them then. Each keeps the C structure
// metal2vulkan's ABI takes, with Metal's default values; copies are new
// objects with the same values.

extension MTLOrigin: ObjCScalar { public static var objCTypeEncoding: String { "{MTLOrigin=QQQ}" } }
extension MTLRegion: ObjCScalar { public static var objCTypeEncoding: String { "{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}" } }
extension MTLClearColor: ObjCScalar { public static var objCTypeEncoding: String { "{MTLClearColor=dddd}" } }
extension MTLViewport: ObjCScalar { public static var objCTypeEncoding: String { "{MTLViewport=dddddd}" } }
extension MTLScissorRect: ObjCScalar { public static var objCTypeEncoding: String { "{MTLScissorRect=QQQQ}" } }

// MARK: - Textures

@ObjCClass("MTLTextureDescriptor")
open class MTLTextureDescriptor: NSObject {
    var value = perry_m2v_texture_descriptor(texture_type: 2, pixel_format: 70, width: 1, height: 1, depth: 1,
                                             mipmap_level_count: 1, sample_count: 1, array_length: 1, usage: 1,
                                             resource_options: 0)
    var allowGPUOptimizedContents = true

    @ObjCMethod("init") public required override init() { super.init() }

    /// A 2D texture, with every mipmap level down to 1×1 when mipmapped.
    @ObjCClassMethod("texture2DDescriptorWithPixelFormat:width:height:mipmapped:")
    static func texture2D(pixelFormat: UInt, width: UInt, height: UInt, mipmapped: Bool) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.value.pixel_format = UInt32(pixelFormat)
        descriptor.value.width = UInt64(width)
        descriptor.value.height = UInt64(height)
        if mipmapped { descriptor.value.mipmap_level_count = UInt64(levels(max(width, height))) }
        return descriptor
    }

    @ObjCClassMethod("textureCubeDescriptorWithPixelFormat:size:mipmapped:")
    static func textureCube(pixelFormat: UInt, size: UInt, mipmapped: Bool) -> MTLTextureDescriptor {
        let descriptor = texture2D(pixelFormat: pixelFormat, width: size, height: size, mipmapped: mipmapped)
        descriptor.value.texture_type = 5
        return descriptor
    }

    @ObjCClassMethod("textureBufferDescriptorWithPixelFormat:width:resourceOptions:usage:")
    static func textureBuffer(pixelFormat: UInt, width: UInt, resourceOptions: UInt, usage: UInt) -> MTLTextureDescriptor {
        let descriptor = texture2D(pixelFormat: pixelFormat, width: width, height: 1, mipmapped: false)
        descriptor.value.texture_type = 9
        descriptor.value.resource_options = UInt64(resourceOptions)
        descriptor.value.usage = UInt64(usage)
        return descriptor
    }

    static func levels(_ size: UInt) -> Int {
        var levels = 1, size = size
        while size > 1 { size /= 2; levels += 1 }
        return levels
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLTextureDescriptor {
        let copy = MTLTextureDescriptor()
        copy.value = value
        copy.allowGPUOptimizedContents = allowGPUOptimizedContents
        return copy
    }

    @ObjCMethod("textureType") func textureType() -> UInt { UInt(value.texture_type) }
    @ObjCMethod("setTextureType:") func setTextureType(_ type: UInt) { value.texture_type = UInt32(type) }
    @ObjCMethod("pixelFormat") func pixelFormat() -> UInt { UInt(value.pixel_format) }
    @ObjCMethod("setPixelFormat:") func setPixelFormat(_ format: UInt) { value.pixel_format = UInt32(format) }
    @ObjCMethod("width") func width() -> UInt { UInt(value.width) }
    @ObjCMethod("setWidth:") func setWidth(_ width: UInt) { value.width = UInt64(width) }
    @ObjCMethod("height") func height() -> UInt { UInt(value.height) }
    @ObjCMethod("setHeight:") func setHeight(_ height: UInt) { value.height = UInt64(height) }
    @ObjCMethod("depth") func depth() -> UInt { UInt(value.depth) }
    @ObjCMethod("setDepth:") func setDepth(_ depth: UInt) { value.depth = UInt64(depth) }
    @ObjCMethod("mipmapLevelCount") func mipmapLevelCount() -> UInt { UInt(value.mipmap_level_count) }
    @ObjCMethod("setMipmapLevelCount:") func setMipmapLevelCount(_ count: UInt) { value.mipmap_level_count = UInt64(count) }
    @ObjCMethod("sampleCount") func sampleCount() -> UInt { UInt(value.sample_count) }
    @ObjCMethod("setSampleCount:") func setSampleCount(_ count: UInt) { value.sample_count = UInt64(count) }
    @ObjCMethod("arrayLength") func arrayLength() -> UInt { UInt(value.array_length) }
    @ObjCMethod("setArrayLength:") func setArrayLength(_ length: UInt) { value.array_length = UInt64(length) }
    @ObjCMethod("usage") func usage() -> UInt { UInt(value.usage) }
    @ObjCMethod("setUsage:") func setUsage(_ usage: UInt) { value.usage = UInt64(usage) }
    @ObjCMethod("resourceOptions") func resourceOptions() -> UInt { UInt(value.resource_options) }
    @ObjCMethod("setResourceOptions:") func setResourceOptions(_ options: UInt) { value.resource_options = UInt64(options) }
    @ObjCMethod("cpuCacheMode") func cpuCacheMode() -> UInt { UInt(value.resource_options & 0xf) }
    @ObjCMethod("setCpuCacheMode:") func setCpuCacheMode(_ mode: UInt) { setBits(UInt64(mode), shift: 0, mask: 0xf) }
    @ObjCMethod("storageMode") func storageMode() -> UInt { UInt((value.resource_options >> 4) & 0xf) }
    @ObjCMethod("setStorageMode:") func setStorageMode(_ mode: UInt) { setBits(UInt64(mode), shift: 4, mask: 0xf) }
    @ObjCMethod("hazardTrackingMode") func hazardTrackingMode() -> UInt { UInt((value.resource_options >> 8) & 0x3) }
    @ObjCMethod("setHazardTrackingMode:") func setHazardTrackingMode(_ mode: UInt) { setBits(UInt64(mode), shift: 8, mask: 0x3) }
    @ObjCMethod("allowGPUOptimizedContents") func getAllowGPUOptimizedContents() -> Bool { allowGPUOptimizedContents }
    @ObjCMethod("setAllowGPUOptimizedContents:") func setAllowGPUOptimizedContents(_ allow: Bool) { allowGPUOptimizedContents = allow }

    private func setBits(_ bits: UInt64, shift: UInt64, mask: UInt64) {
        value.resource_options = value.resource_options & ~(mask << shift) | (bits & mask) << shift
    }
}

// MARK: - Samplers

@ObjCClass("MTLSamplerDescriptor")
open class MTLSamplerDescriptor: NSObject {
    var value = perry_m2v_sampler_descriptor(min_filter: 0, mag_filter: 0, mip_filter: 0, s_address_mode: 0,
                                             t_address_mode: 0, r_address_mode: 0, border_color: 0,
                                             normalized_coordinates: true, lod_min_clamp: 0,
                                             lod_max_clamp: .greatestFiniteMagnitude, max_anisotropy: 1,
                                             compare_function: 0)
    var label: String?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLSamplerDescriptor {
        let copy = MTLSamplerDescriptor()
        copy.value = value
        copy.label = label
        return copy
    }

    @ObjCMethod("minFilter") func minFilter() -> UInt { UInt(value.min_filter) }
    @ObjCMethod("setMinFilter:") func setMinFilter(_ filter: UInt) { value.min_filter = UInt32(filter) }
    @ObjCMethod("magFilter") func magFilter() -> UInt { UInt(value.mag_filter) }
    @ObjCMethod("setMagFilter:") func setMagFilter(_ filter: UInt) { value.mag_filter = UInt32(filter) }
    @ObjCMethod("mipFilter") func mipFilter() -> UInt { UInt(value.mip_filter) }
    @ObjCMethod("setMipFilter:") func setMipFilter(_ filter: UInt) { value.mip_filter = UInt32(filter) }
    @ObjCMethod("sAddressMode") func sAddressMode() -> UInt { UInt(value.s_address_mode) }
    @ObjCMethod("setSAddressMode:") func setSAddressMode(_ mode: UInt) { value.s_address_mode = UInt32(mode) }
    @ObjCMethod("tAddressMode") func tAddressMode() -> UInt { UInt(value.t_address_mode) }
    @ObjCMethod("setTAddressMode:") func setTAddressMode(_ mode: UInt) { value.t_address_mode = UInt32(mode) }
    @ObjCMethod("rAddressMode") func rAddressMode() -> UInt { UInt(value.r_address_mode) }
    @ObjCMethod("setRAddressMode:") func setRAddressMode(_ mode: UInt) { value.r_address_mode = UInt32(mode) }
    @ObjCMethod("borderColor") func borderColor() -> UInt { UInt(value.border_color) }
    @ObjCMethod("setBorderColor:") func setBorderColor(_ color: UInt) { value.border_color = UInt32(color) }
    @ObjCMethod("normalizedCoordinates") func normalizedCoordinates() -> Bool { value.normalized_coordinates }
    @ObjCMethod("setNormalizedCoordinates:") func setNormalizedCoordinates(_ normalized: Bool) { value.normalized_coordinates = normalized }
    @ObjCMethod("lodMinClamp") func lodMinClamp() -> Float { value.lod_min_clamp }
    @ObjCMethod("setLodMinClamp:") func setLodMinClamp(_ clamp: Float) { value.lod_min_clamp = clamp }
    @ObjCMethod("lodMaxClamp") func lodMaxClamp() -> Float { value.lod_max_clamp }
    @ObjCMethod("setLodMaxClamp:") func setLodMaxClamp(_ clamp: Float) { value.lod_max_clamp = clamp }
    @ObjCMethod("maxAnisotropy") func maxAnisotropy() -> UInt { UInt(value.max_anisotropy) }
    @ObjCMethod("setMaxAnisotropy:") func setMaxAnisotropy(_ anisotropy: UInt) { value.max_anisotropy = UInt32(anisotropy) }
    @ObjCMethod("compareFunction") func compareFunction() -> UInt { UInt(value.compare_function) }
    @ObjCMethod("setCompareFunction:") func setCompareFunction(_ function: UInt) { value.compare_function = UInt32(function) }
    @ObjCMethod("supportArgumentBuffers") func supportArgumentBuffers() -> Bool { false }
    @ObjCMethod("setSupportArgumentBuffers:") func setSupportArgumentBuffers(_ support: Bool) {}
    @ObjCMethod("lodAverage") func lodAverage() -> Bool { false }
    @ObjCMethod("setLodAverage:") func setLodAverage(_ average: Bool) {}
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
}

// MARK: - Depth and stencil

@ObjCClass("MTLStencilDescriptor")
open class MTLStencilDescriptor: NSObject {
    /// Always, keep everywhere, every bit.
    var value = perry_m2v_stencil_descriptor(compare_function: 7, stencil_failure_operation: 0,
                                             depth_failure_operation: 0, depth_stencil_pass_operation: 0,
                                             read_mask: .max, write_mask: .max)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLStencilDescriptor {
        let copy = MTLStencilDescriptor()
        copy.value = value
        return copy
    }

    @ObjCMethod("stencilCompareFunction") func stencilCompareFunction() -> UInt { UInt(value.compare_function) }
    @ObjCMethod("setStencilCompareFunction:") func setStencilCompareFunction(_ function: UInt) { value.compare_function = UInt32(function) }
    @ObjCMethod("stencilFailureOperation") func stencilFailureOperation() -> UInt { UInt(value.stencil_failure_operation) }
    @ObjCMethod("setStencilFailureOperation:") func setStencilFailureOperation(_ operation: UInt) { value.stencil_failure_operation = UInt32(operation) }
    @ObjCMethod("depthFailureOperation") func depthFailureOperation() -> UInt { UInt(value.depth_failure_operation) }
    @ObjCMethod("setDepthFailureOperation:") func setDepthFailureOperation(_ operation: UInt) { value.depth_failure_operation = UInt32(operation) }
    @ObjCMethod("depthStencilPassOperation") func depthStencilPassOperation() -> UInt { UInt(value.depth_stencil_pass_operation) }
    @ObjCMethod("setDepthStencilPassOperation:") func setDepthStencilPassOperation(_ operation: UInt) { value.depth_stencil_pass_operation = UInt32(operation) }
    @ObjCMethod("readMask") func readMask() -> UInt32 { value.read_mask }
    @ObjCMethod("setReadMask:") func setReadMask(_ mask: UInt32) { value.read_mask = mask }
    @ObjCMethod("writeMask") func writeMask() -> UInt32 { value.write_mask }
    @ObjCMethod("setWriteMask:") func setWriteMask(_ mask: UInt32) { value.write_mask = mask }
}

@ObjCClass("MTLDepthStencilDescriptor")
open class MTLDepthStencilDescriptor: NSObject {
    /// Always, without writes.
    var depthCompareFunction: UInt32 = 7
    var depthWriteEnabled = false
    var front = MTLStencilDescriptor()
    var back = MTLStencilDescriptor()
    var label: String?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLDepthStencilDescriptor {
        let copy = MTLDepthStencilDescriptor()
        copy.depthCompareFunction = depthCompareFunction
        copy.depthWriteEnabled = depthWriteEnabled
        copy.front.value = front.value
        copy.back.value = back.value
        copy.label = label
        return copy
    }

    var value: perry_m2v_depth_stencil_descriptor {
        perry_m2v_depth_stencil_descriptor(depth_compare_function: depthCompareFunction,
                                           depth_write_enabled: depthWriteEnabled,
                                           front_face_stencil: front.value, back_face_stencil: back.value)
    }

    @ObjCMethod("depthCompareFunction") func getDepthCompareFunction() -> UInt { UInt(depthCompareFunction) }
    @ObjCMethod("setDepthCompareFunction:") func setDepthCompareFunction(_ function: UInt) { depthCompareFunction = UInt32(function) }
    @ObjCMethod("isDepthWriteEnabled") func isDepthWriteEnabled() -> Bool { depthWriteEnabled }
    @ObjCMethod("depthWriteEnabled") func getDepthWriteEnabled() -> Bool { depthWriteEnabled }
    @ObjCMethod("setDepthWriteEnabled:") func setDepthWriteEnabled(_ enabled: Bool) { depthWriteEnabled = enabled }
    @ObjCMethod("frontFaceStencil") func frontFaceStencil() -> MTLStencilDescriptor { front }
    /// Nil resets it to the defaults.
    @ObjCMethod("setFrontFaceStencil:") func setFrontFaceStencil(_ stencil: MTLStencilDescriptor?) {
        front.value = (stencil ?? MTLStencilDescriptor()).value
    }
    @ObjCMethod("backFaceStencil") func backFaceStencil() -> MTLStencilDescriptor { back }
    @ObjCMethod("setBackFaceStencil:") func setBackFaceStencil(_ stencil: MTLStencilDescriptor?) {
        back.value = (stencil ?? MTLStencilDescriptor()).value
    }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
}

// MARK: - Render pipelines

@ObjCClass("MTLRenderPipelineColorAttachmentDescriptor")
open class MTLRenderPipelineColorAttachmentDescriptor: NSObject {
    /// None; blending off, one and zero, add; every channel.
    var value = perry_m2v_color_attachment(pixel_format: 0, blending_enabled: false, source_rgb_blend_factor: 1,
                                           destination_rgb_blend_factor: 0, rgb_blend_operation: 0,
                                           source_alpha_blend_factor: 1, destination_alpha_blend_factor: 0,
                                           alpha_blend_operation: 0, write_mask: 0xf)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLRenderPipelineColorAttachmentDescriptor {
        let copy = MTLRenderPipelineColorAttachmentDescriptor()
        copy.value = value
        return copy
    }

    @ObjCMethod("pixelFormat") func pixelFormat() -> UInt { UInt(value.pixel_format) }
    @ObjCMethod("setPixelFormat:") func setPixelFormat(_ format: UInt) { value.pixel_format = UInt32(format) }
    @ObjCMethod("isBlendingEnabled") func isBlendingEnabled() -> Bool { value.blending_enabled }
    @ObjCMethod("blendingEnabled") func blendingEnabled() -> Bool { value.blending_enabled }
    @ObjCMethod("setBlendingEnabled:") func setBlendingEnabled(_ enabled: Bool) { value.blending_enabled = enabled }
    @ObjCMethod("sourceRGBBlendFactor") func sourceRGBBlendFactor() -> UInt { UInt(value.source_rgb_blend_factor) }
    @ObjCMethod("setSourceRGBBlendFactor:") func setSourceRGBBlendFactor(_ factor: UInt) { value.source_rgb_blend_factor = UInt32(factor) }
    @ObjCMethod("destinationRGBBlendFactor") func destinationRGBBlendFactor() -> UInt { UInt(value.destination_rgb_blend_factor) }
    @ObjCMethod("setDestinationRGBBlendFactor:") func setDestinationRGBBlendFactor(_ factor: UInt) { value.destination_rgb_blend_factor = UInt32(factor) }
    @ObjCMethod("rgbBlendOperation") func rgbBlendOperation() -> UInt { UInt(value.rgb_blend_operation) }
    @ObjCMethod("setRgbBlendOperation:") func setRgbBlendOperation(_ operation: UInt) { value.rgb_blend_operation = UInt32(operation) }
    @ObjCMethod("sourceAlphaBlendFactor") func sourceAlphaBlendFactor() -> UInt { UInt(value.source_alpha_blend_factor) }
    @ObjCMethod("setSourceAlphaBlendFactor:") func setSourceAlphaBlendFactor(_ factor: UInt) { value.source_alpha_blend_factor = UInt32(factor) }
    @ObjCMethod("destinationAlphaBlendFactor") func destinationAlphaBlendFactor() -> UInt { UInt(value.destination_alpha_blend_factor) }
    @ObjCMethod("setDestinationAlphaBlendFactor:") func setDestinationAlphaBlendFactor(_ factor: UInt) { value.destination_alpha_blend_factor = UInt32(factor) }
    @ObjCMethod("alphaBlendOperation") func alphaBlendOperation() -> UInt { UInt(value.alpha_blend_operation) }
    @ObjCMethod("setAlphaBlendOperation:") func setAlphaBlendOperation(_ operation: UInt) { value.alpha_blend_operation = UInt32(operation) }
    @ObjCMethod("writeMask") func writeMask() -> UInt { UInt(value.write_mask) }
    @ObjCMethod("setWriteMask:") func setWriteMask(_ mask: UInt) { value.write_mask = UInt32(mask) }
}

/// The objects of an indexed descriptor array: made on first use, copied
/// in when set.
final class Slots<Element: NSObject> {
    var elements: [Int: Element] = [:]
    let make: () -> Element
    let copy: (Element, Element) -> Void

    init(make: @escaping () -> Element, copy: @escaping (Element, Element) -> Void) {
        self.make = make
        self.copy = copy
    }

    func at(_ index: Int) -> Element {
        if let element = elements[index] { return element }
        let element = make()
        elements[index] = element
        return element
    }

    func set(_ element: Element?, at index: Int) {
        let slot = make()
        if let element { copy(slot, element) }
        elements[index] = slot
    }
}

@ObjCClass("MTLRenderPipelineColorAttachmentDescriptorArray")
open class MTLRenderPipelineColorAttachmentDescriptorArray: NSObject {
    var slots = Slots<MTLRenderPipelineColorAttachmentDescriptor>(make: { MTLRenderPipelineColorAttachmentDescriptor() },
                                                                  copy: { $0.value = $1.value })

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("objectAtIndexedSubscript:")
    func object(at index: UInt) -> MTLRenderPipelineColorAttachmentDescriptor { slots.at(Int(index)) }
    @ObjCMethod("setObject:atIndexedSubscript:")
    func setObject(_ object: MTLRenderPipelineColorAttachmentDescriptor?, at index: UInt) { slots.set(object, at: Int(index)) }
}

@ObjCClass("MTLVertexAttributeDescriptor")
open class MTLVertexAttributeDescriptor: NSObject {
    var value = perry_m2v_vertex_attribute(format: 0, offset: 0, buffer_index: 0)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLVertexAttributeDescriptor {
        let copy = MTLVertexAttributeDescriptor()
        copy.value = value
        return copy
    }

    @ObjCMethod("format") func format() -> UInt { UInt(value.format) }
    @ObjCMethod("setFormat:") func setFormat(_ format: UInt) { value.format = UInt32(format) }
    @ObjCMethod("offset") func offset() -> UInt { UInt(value.offset) }
    @ObjCMethod("setOffset:") func setOffset(_ offset: UInt) { value.offset = UInt32(offset) }
    @ObjCMethod("bufferIndex") func bufferIndex() -> UInt { UInt(value.buffer_index) }
    @ObjCMethod("setBufferIndex:") func setBufferIndex(_ index: UInt) { value.buffer_index = UInt32(index) }
}

@ObjCClass("MTLVertexBufferLayoutDescriptor")
open class MTLVertexBufferLayoutDescriptor: NSObject {
    /// Per vertex, every vertex.
    var value = perry_m2v_vertex_layout(stride: 0, step_function: 1, step_rate: 1)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLVertexBufferLayoutDescriptor {
        let copy = MTLVertexBufferLayoutDescriptor()
        copy.value = value
        return copy
    }

    /// MTLBufferLayoutStrideDynamic is UINT_MAX, as in metal2vulkan's ABI.
    @ObjCMethod("stride") func stride() -> UInt { value.stride == .max ? .max : UInt(value.stride) }
    @ObjCMethod("setStride:") func setStride(_ stride: UInt) { value.stride = stride >= UInt(UInt32.max) ? .max : UInt32(stride) }
    @ObjCMethod("stepFunction") func stepFunction() -> UInt { UInt(value.step_function) }
    @ObjCMethod("setStepFunction:") func setStepFunction(_ function: UInt) { value.step_function = UInt32(function) }
    @ObjCMethod("stepRate") func stepRate() -> UInt { UInt(value.step_rate) }
    @ObjCMethod("setStepRate:") func setStepRate(_ rate: UInt) { value.step_rate = UInt32(rate) }
}

@ObjCClass("MTLVertexAttributeDescriptorArray")
open class MTLVertexAttributeDescriptorArray: NSObject {
    var slots = Slots<MTLVertexAttributeDescriptor>(make: { MTLVertexAttributeDescriptor() }, copy: { $0.value = $1.value })

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("objectAtIndexedSubscript:") func object(at index: UInt) -> MTLVertexAttributeDescriptor { slots.at(Int(index)) }
    @ObjCMethod("setObject:atIndexedSubscript:")
    func setObject(_ object: MTLVertexAttributeDescriptor?, at index: UInt) { slots.set(object, at: Int(index)) }
}

@ObjCClass("MTLVertexBufferLayoutDescriptorArray")
open class MTLVertexBufferLayoutDescriptorArray: NSObject {
    var slots = Slots<MTLVertexBufferLayoutDescriptor>(make: { MTLVertexBufferLayoutDescriptor() }, copy: { $0.value = $1.value })

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("objectAtIndexedSubscript:") func object(at index: UInt) -> MTLVertexBufferLayoutDescriptor { slots.at(Int(index)) }
    @ObjCMethod("setObject:atIndexedSubscript:")
    func setObject(_ object: MTLVertexBufferLayoutDescriptor?, at index: UInt) { slots.set(object, at: Int(index)) }
}

@ObjCClass("MTLVertexDescriptor")
open class MTLVertexDescriptor: NSObject {
    var attributeArray = MTLVertexAttributeDescriptorArray()
    var layoutArray = MTLVertexBufferLayoutDescriptorArray()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("vertexDescriptor") static func vertexDescriptor() -> MTLVertexDescriptor { MTLVertexDescriptor() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLVertexDescriptor {
        let copy = MTLVertexDescriptor()
        copy.load(from: self)
        return copy
    }

    func load(from other: MTLVertexDescriptor) {
        for (index, attribute) in other.attributeArray.slots.elements { attributeArray.slots.set(attribute, at: index) }
        for (index, layout) in other.layoutArray.slots.elements { layoutArray.slots.set(layout, at: index) }
    }

    @ObjCMethod("attributes") func attributes() -> MTLVertexAttributeDescriptorArray { attributeArray }
    @ObjCMethod("layouts") func layouts() -> MTLVertexBufferLayoutDescriptorArray { layoutArray }
    @ObjCMethod("reset") func reset() {
        attributeArray.slots.elements = [:]
        layoutArray.slots.elements = [:]
    }
}

@ObjCClass("MTLRenderPipelineDescriptor")
open class MTLRenderPipelineDescriptor: NSObject {
    var vertexFunction: MTLFunction?
    var fragmentFunction: MTLFunction?
    var vertex: MTLVertexDescriptor?
    var colors = MTLRenderPipelineColorAttachmentDescriptorArray()
    var depthFormat: UInt32 = 0
    var stencilFormat: UInt32 = 0
    var rasterSampleCount: UInt32 = 1
    var alphaToCoverage = false
    var alphaToOne = false
    var rasterizationEnabled = true
    var inputPrimitiveTopology: UInt32 = 0
    var label: String?
    /// Tessellation's settings, with Metal's defaults. metal2vulkan's ABI
    /// has no tessellation, so pipelines are made without them; only a
    /// pipeline with a post-tessellation vertex function would need them.
    var tessellation = Tessellation()

    struct Tessellation {
        var maxFactor: UInt = 16
        var factorScaleEnabled = false
        var factorFormat: UInt = 0
        var controlPointIndexType: UInt = 0
        var factorStepFunction: UInt = 0
        var outputWindingOrder: UInt = 0
        var partitionMode: UInt = 0
    }

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("maxTessellationFactor") func maxTessellationFactor() -> UInt { tessellation.maxFactor }
    @ObjCMethod("setMaxTessellationFactor:") func setMaxTessellationFactor(_ value: UInt) { tessellation.maxFactor = value }
    @ObjCMethod("isTessellationFactorScaleEnabled") func isTessellationFactorScaleEnabled() -> Bool { tessellation.factorScaleEnabled }
    @ObjCMethod("setTessellationFactorScaleEnabled:")
    func setTessellationFactorScaleEnabled(_ value: Bool) { tessellation.factorScaleEnabled = value }
    @ObjCMethod("tessellationFactorFormat") func tessellationFactorFormat() -> UInt { tessellation.factorFormat }
    @ObjCMethod("setTessellationFactorFormat:") func setTessellationFactorFormat(_ value: UInt) { tessellation.factorFormat = value }
    @ObjCMethod("tessellationControlPointIndexType") func tessellationControlPointIndexType() -> UInt { tessellation.controlPointIndexType }
    @ObjCMethod("setTessellationControlPointIndexType:")
    func setTessellationControlPointIndexType(_ value: UInt) { tessellation.controlPointIndexType = value }
    @ObjCMethod("tessellationFactorStepFunction") func tessellationFactorStepFunction() -> UInt { tessellation.factorStepFunction }
    @ObjCMethod("setTessellationFactorStepFunction:")
    func setTessellationFactorStepFunction(_ value: UInt) { tessellation.factorStepFunction = value }
    @ObjCMethod("tessellationOutputWindingOrder") func tessellationOutputWindingOrder() -> UInt { tessellation.outputWindingOrder }
    @ObjCMethod("setTessellationOutputWindingOrder:")
    func setTessellationOutputWindingOrder(_ value: UInt) { tessellation.outputWindingOrder = value }
    @ObjCMethod("tessellationPartitionMode") func tessellationPartitionMode() -> UInt { tessellation.partitionMode }
    @ObjCMethod("setTessellationPartitionMode:") func setTessellationPartitionMode(_ value: UInt) { tessellation.partitionMode = value }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLRenderPipelineDescriptor {
        let copy = MTLRenderPipelineDescriptor()
        copy.vertexFunction = vertexFunction
        copy.fragmentFunction = fragmentFunction
        if let vertex { copy.vertex = vertex.copy(zone: nil) }
        for (index, color) in colors.slots.elements { copy.colors.slots.set(color, at: index) }
        (copy.depthFormat, copy.stencilFormat, copy.rasterSampleCount) = (depthFormat, stencilFormat, rasterSampleCount)
        (copy.alphaToCoverage, copy.alphaToOne, copy.rasterizationEnabled) = (alphaToCoverage, alphaToOne, rasterizationEnabled)
        copy.inputPrimitiveTopology = inputPrimitiveTopology
        copy.label = label
        copy.tessellation = tessellation
        return copy
    }

    /// The descriptor for metal2vulkan; its functions stay alive with this.
    var value: perry_m2v_render_pipeline_descriptor {
        var d = perry_m2v_render_pipeline_descriptor()
        d.vertex_function = vertexFunction?.handle
        d.fragment_function = fragmentFunction?.handle
        withUnsafeMutableBytes(of: &d.color_attachments) { raw in
            let slots = raw.bindMemory(to: perry_m2v_color_attachment.self)
            for index in 0..<8 { slots[index] = colors.slots.elements[index]?.value ?? MTLRenderPipelineColorAttachmentDescriptor().value }
        }
        d.depth_attachment_pixel_format = depthFormat
        d.stencil_attachment_pixel_format = stencilFormat
        d.raster_sample_count = rasterSampleCount
        d.alpha_to_coverage_enabled = alphaToCoverage
        d.alpha_to_one_enabled = alphaToOne
        d.rasterization_enabled = rasterizationEnabled
        d.input_primitive_topology = inputPrimitiveTopology
        if let vertex {
            d.has_vertex_descriptor = true
            withUnsafeMutableBytes(of: &d.attributes) { raw in
                let slots = raw.bindMemory(to: perry_m2v_vertex_attribute.self)
                for index in 0..<31 { slots[index] = vertex.attributeArray.slots.elements[index]?.value ?? MTLVertexAttributeDescriptor().value }
            }
            withUnsafeMutableBytes(of: &d.layouts) { raw in
                let slots = raw.bindMemory(to: perry_m2v_vertex_layout.self)
                for index in 0..<31 { slots[index] = vertex.layoutArray.slots.elements[index]?.value ?? MTLVertexBufferLayoutDescriptor().value }
            }
        }
        return d
    }

    @ObjCMethod("vertexFunction") func getVertexFunction() -> MTLFunction? { vertexFunction }
    @ObjCMethod("setVertexFunction:") func setVertexFunction(_ function: MTLFunction?) { vertexFunction = function }
    @ObjCMethod("fragmentFunction") func getFragmentFunction() -> MTLFunction? { fragmentFunction }
    @ObjCMethod("setFragmentFunction:") func setFragmentFunction(_ function: MTLFunction?) { fragmentFunction = function }
    @ObjCMethod("vertexDescriptor") func vertexDescriptor() -> MTLVertexDescriptor? { vertex }
    @ObjCMethod("setVertexDescriptor:") func setVertexDescriptor(_ descriptor: MTLVertexDescriptor?) {
        vertex = descriptor?.copy(zone: nil)
    }
    @ObjCMethod("colorAttachments") func colorAttachments() -> MTLRenderPipelineColorAttachmentDescriptorArray { colors }
    @ObjCMethod("depthAttachmentPixelFormat") func depthAttachmentPixelFormat() -> UInt { UInt(depthFormat) }
    @ObjCMethod("setDepthAttachmentPixelFormat:") func setDepthAttachmentPixelFormat(_ format: UInt) { depthFormat = UInt32(format) }
    @ObjCMethod("stencilAttachmentPixelFormat") func stencilAttachmentPixelFormat() -> UInt { UInt(stencilFormat) }
    @ObjCMethod("setStencilAttachmentPixelFormat:") func setStencilAttachmentPixelFormat(_ format: UInt) { stencilFormat = UInt32(format) }
    @ObjCMethod("sampleCount") func sampleCount() -> UInt { UInt(rasterSampleCount) }
    @ObjCMethod("setSampleCount:") func setSampleCount(_ count: UInt) { rasterSampleCount = UInt32(count) }
    @ObjCMethod("rasterSampleCount") func getRasterSampleCount() -> UInt { UInt(rasterSampleCount) }
    @ObjCMethod("setRasterSampleCount:") func setRasterSampleCount(_ count: UInt) { rasterSampleCount = UInt32(count) }
    @ObjCMethod("isAlphaToCoverageEnabled") func isAlphaToCoverageEnabled() -> Bool { alphaToCoverage }
    @ObjCMethod("setAlphaToCoverageEnabled:") func setAlphaToCoverageEnabled(_ enabled: Bool) { alphaToCoverage = enabled }
    @ObjCMethod("isAlphaToOneEnabled") func isAlphaToOneEnabled() -> Bool { alphaToOne }
    @ObjCMethod("setAlphaToOneEnabled:") func setAlphaToOneEnabled(_ enabled: Bool) { alphaToOne = enabled }
    @ObjCMethod("isRasterizationEnabled") func isRasterizationEnabled() -> Bool { rasterizationEnabled }
    @ObjCMethod("setRasterizationEnabled:") func setRasterizationEnabled(_ enabled: Bool) { rasterizationEnabled = enabled }
    @ObjCMethod("inputPrimitiveTopology") func getInputPrimitiveTopology() -> UInt { UInt(inputPrimitiveTopology) }
    @ObjCMethod("setInputPrimitiveTopology:") func setInputPrimitiveTopology(_ topology: UInt) { inputPrimitiveTopology = UInt32(topology) }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("reset") func reset() {
        vertexFunction = nil
        fragmentFunction = nil
        vertex = nil
        colors.slots.elements = [:]
        (depthFormat, stencilFormat, rasterSampleCount) = (0, 0, 1)
        (alphaToCoverage, alphaToOne, rasterizationEnabled) = (false, false, true)
        inputPrimitiveTopology = 0
    }
}

// MARK: - Render passes

/// An attachment of a render pass: colour, depth or stencil.
@ObjCClass("MTLRenderPassAttachmentDescriptor")
open class MTLRenderPassAttachmentDescriptor: NSObject {
    var texture: MTLTexture?
    var resolveTexture: MTLTexture?
    var value = perry_m2v_pass_attachment()

    @ObjCMethod("init") public required override init() { super.init() }

    func copy(from other: MTLRenderPassAttachmentDescriptor) {
        texture = other.texture
        resolveTexture = other.resolveTexture
        value = other.value
    }

    /// The C attachment, its textures' handles alive while this is.
    var attachment: perry_m2v_pass_attachment {
        var a = value
        a.texture = texture?.handle
        a.resolve_texture = resolveTexture?.handle
        return a
    }

    @ObjCMethod("texture") func getTexture() -> MTLTexture? { texture }
    @ObjCMethod("setTexture:") func setTexture(_ texture: MTLTexture?) { self.texture = texture }
    @ObjCMethod("level") func level() -> UInt { UInt(value.level) }
    @ObjCMethod("setLevel:") func setLevel(_ level: UInt) { value.level = UInt64(level) }
    @ObjCMethod("slice") func slice() -> UInt { UInt(value.slice) }
    @ObjCMethod("setSlice:") func setSlice(_ slice: UInt) { value.slice = UInt64(slice) }
    @ObjCMethod("depthPlane") func depthPlane() -> UInt { UInt(value.depth_plane) }
    @ObjCMethod("setDepthPlane:") func setDepthPlane(_ plane: UInt) { value.depth_plane = UInt64(plane) }
    @ObjCMethod("resolveTexture") func getResolveTexture() -> MTLTexture? { resolveTexture }
    @ObjCMethod("setResolveTexture:") func setResolveTexture(_ texture: MTLTexture?) { resolveTexture = texture }
    @ObjCMethod("resolveLevel") func resolveLevel() -> UInt { UInt(value.resolve_level) }
    @ObjCMethod("setResolveLevel:") func setResolveLevel(_ level: UInt) { value.resolve_level = UInt64(level) }
    @ObjCMethod("resolveSlice") func resolveSlice() -> UInt { UInt(value.resolve_slice) }
    @ObjCMethod("setResolveSlice:") func setResolveSlice(_ slice: UInt) { value.resolve_slice = UInt64(slice) }
    @ObjCMethod("resolveDepthPlane") func resolveDepthPlane() -> UInt { UInt(value.resolve_depth_plane) }
    @ObjCMethod("setResolveDepthPlane:") func setResolveDepthPlane(_ plane: UInt) { value.resolve_depth_plane = UInt64(plane) }
    @ObjCMethod("loadAction") func loadAction() -> UInt { UInt(value.load_action) }
    @ObjCMethod("setLoadAction:") func setLoadAction(_ action: UInt) { value.load_action = UInt64(action) }
    @ObjCMethod("storeAction") func storeAction() -> UInt { UInt(value.store_action) }
    @ObjCMethod("setStoreAction:") func setStoreAction(_ action: UInt) { value.store_action = UInt64(action) }
    @ObjCMethod("storeActionOptions") func storeActionOptions() -> UInt { 0 }
    @ObjCMethod("setStoreActionOptions:") func setStoreActionOptions(_ options: UInt) {}
}

@ObjCClass("MTLRenderPassColorAttachmentDescriptor")
open class MTLRenderPassColorAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    /// Don't care, store, opaque black.
    @ObjCMethod("init") public required init() {
        super.init()
        value.load_action = 0
        value.store_action = 1
        value.clear = (0, 0, 0, 1)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLRenderPassColorAttachmentDescriptor {
        let copy = MTLRenderPassColorAttachmentDescriptor()
        copy.copy(from: self)
        return copy
    }

    @ObjCMethod("clearColor") func clearColor() -> MTLClearColor {
        MTLClearColor(red: value.clear.0, green: value.clear.1, blue: value.clear.2, alpha: value.clear.3)
    }
    @ObjCMethod("setClearColor:") func setClearColor(_ color: MTLClearColor) {
        value.clear = (color.red, color.green, color.blue, color.alpha)
    }
}

@ObjCClass("MTLRenderPassDepthAttachmentDescriptor")
open class MTLRenderPassDepthAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    /// Clear to 1, don't store.
    @ObjCMethod("init") public required init() {
        super.init()
        value.load_action = 2
        value.store_action = 0
        value.clear.0 = 1
    }

    @ObjCMethod("clearDepth") func clearDepth() -> Double { value.clear.0 }
    @ObjCMethod("setClearDepth:") func setClearDepth(_ depth: Double) { value.clear.0 = depth }
    @ObjCMethod("depthResolveFilter") func depthResolveFilter() -> UInt { 0 }
    @ObjCMethod("setDepthResolveFilter:") func setDepthResolveFilter(_ filter: UInt) {}
}

@ObjCClass("MTLRenderPassStencilAttachmentDescriptor")
open class MTLRenderPassStencilAttachmentDescriptor: MTLRenderPassAttachmentDescriptor {
    /// Clear to 0, don't store.
    @ObjCMethod("init") public required init() {
        super.init()
        value.load_action = 2
        value.store_action = 0
    }

    @ObjCMethod("clearStencil") func clearStencil() -> UInt32 { UInt32(value.clear.0) }
    @ObjCMethod("setClearStencil:") func setClearStencil(_ stencil: UInt32) { value.clear.0 = Double(stencil) }

    /// MTLMultisampleStencilResolveFilter: kept for the app; metal2vulkan's
    /// passes resolve with the sample's own.
    var resolveFilter: UInt = 0
    @ObjCMethod("stencilResolveFilter") func stencilResolveFilter() -> UInt { resolveFilter }
    @ObjCMethod("setStencilResolveFilter:") func setStencilResolveFilter(_ filter: UInt) { resolveFilter = filter }
}

// MARK: - Counter sample buffer attachments

/// Where a pass samples GPU counters into. Devices here have no counter
/// sets, so no sample buffer can be made and passes sample nothing; the
/// attachments only keep what the app sets.
@ObjCClass("MTLPassSampleBufferAttachmentDescriptor")
open class MTLPassSampleBufferAttachmentDescriptor: NSObject {
    var sampleBuffer: NSObject?
    var indices = [UInt](repeating: UInt.max, count: 4)

    @ObjCMethod("init") public required override init() { super.init() }

    func copy(from other: MTLPassSampleBufferAttachmentDescriptor) {
        sampleBuffer = other.sampleBuffer
        indices = other.indices
    }

    @ObjCMethod("sampleBuffer") func getSampleBuffer() -> NSObject? { sampleBuffer }
    @ObjCMethod("setSampleBuffer:") func setSampleBuffer(_ buffer: NSObject?) { sampleBuffer = buffer }
    @ObjCMethod("startOfEncoderSampleIndex") func startOfEncoderSampleIndex() -> UInt { indices[0] }
    @ObjCMethod("setStartOfEncoderSampleIndex:") func setStartOfEncoderSampleIndex(_ index: UInt) { indices[0] = index }
    @ObjCMethod("endOfEncoderSampleIndex") func endOfEncoderSampleIndex() -> UInt { indices[1] }
    @ObjCMethod("setEndOfEncoderSampleIndex:") func setEndOfEncoderSampleIndex(_ index: UInt) { indices[1] = index }
    @ObjCMethod("startOfVertexSampleIndex") func startOfVertexSampleIndex() -> UInt { indices[0] }
    @ObjCMethod("setStartOfVertexSampleIndex:") func setStartOfVertexSampleIndex(_ index: UInt) { indices[0] = index }
    @ObjCMethod("endOfVertexSampleIndex") func endOfVertexSampleIndex() -> UInt { indices[1] }
    @ObjCMethod("setEndOfVertexSampleIndex:") func setEndOfVertexSampleIndex(_ index: UInt) { indices[1] = index }
    @ObjCMethod("startOfFragmentSampleIndex") func startOfFragmentSampleIndex() -> UInt { indices[2] }
    @ObjCMethod("setStartOfFragmentSampleIndex:") func setStartOfFragmentSampleIndex(_ index: UInt) { indices[2] = index }
    @ObjCMethod("endOfFragmentSampleIndex") func endOfFragmentSampleIndex() -> UInt { indices[3] }
    @ObjCMethod("setEndOfFragmentSampleIndex:") func setEndOfFragmentSampleIndex(_ index: UInt) { indices[3] = index }
}

@ObjCClass("MTLPassSampleBufferAttachmentDescriptorArray")
open class MTLPassSampleBufferAttachmentDescriptorArray: NSObject {
    var slots = Slots<MTLPassSampleBufferAttachmentDescriptor>(make: { MTLPassSampleBufferAttachmentDescriptor() },
                                                               copy: { $0.copy(from: $1) })

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("objectAtIndexedSubscript:")
    func object(at index: UInt) -> MTLPassSampleBufferAttachmentDescriptor { slots.at(Int(index)) }
    @ObjCMethod("setObject:atIndexedSubscript:")
    func setObject(_ object: MTLPassSampleBufferAttachmentDescriptor?, at index: UInt) { slots.set(object, at: Int(index)) }
}

/// A blit pass: only its counter sample buffers.
@ObjCClass("MTLBlitPassDescriptor")
open class MTLBlitPassDescriptor: NSObject {
    var attachments = MTLPassSampleBufferAttachmentDescriptorArray()

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCClassMethod("blitPassDescriptor") static func blitPassDescriptor() -> MTLBlitPassDescriptor { MTLBlitPassDescriptor() }
    @ObjCMethod("sampleBufferAttachments") func sampleBufferAttachments() -> MTLPassSampleBufferAttachmentDescriptorArray { attachments }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLBlitPassDescriptor {
        let copy = MTLBlitPassDescriptor()
        for (index, attachment) in attachments.slots.elements { copy.attachments.slots.set(attachment, at: index) }
        return copy
    }
}

/// A compute pass: its dispatch type and counter sample buffers.
@ObjCClass("MTLComputePassDescriptor")
open class MTLComputePassDescriptor: NSObject {
    var attachments = MTLPassSampleBufferAttachmentDescriptorArray()
    /// MTLDispatchTypeSerial.
    var dispatchType: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCClassMethod("computePassDescriptor") static func computePassDescriptor() -> MTLComputePassDescriptor { MTLComputePassDescriptor() }
    @ObjCMethod("sampleBufferAttachments") func sampleBufferAttachments() -> MTLPassSampleBufferAttachmentDescriptorArray { attachments }
    @ObjCMethod("dispatchType") func getDispatchType() -> UInt { dispatchType }
    @ObjCMethod("setDispatchType:") func setDispatchType(_ type: UInt) { dispatchType = type }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLComputePassDescriptor {
        let copy = MTLComputePassDescriptor()
        for (index, attachment) in attachments.slots.elements { copy.attachments.slots.set(attachment, at: index) }
        copy.dispatchType = dispatchType
        return copy
    }
}

@ObjCClass("MTLRenderPassColorAttachmentDescriptorArray")
open class MTLRenderPassColorAttachmentDescriptorArray: NSObject {
    var slots = Slots<MTLRenderPassColorAttachmentDescriptor>(make: { MTLRenderPassColorAttachmentDescriptor() },
                                                              copy: { $0.copy(from: $1) })

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("objectAtIndexedSubscript:")
    func object(at index: UInt) -> MTLRenderPassColorAttachmentDescriptor { slots.at(Int(index)) }
    @ObjCMethod("setObject:atIndexedSubscript:")
    func setObject(_ object: MTLRenderPassColorAttachmentDescriptor?, at index: UInt) { slots.set(object, at: Int(index)) }
}

@ObjCClass("MTLRenderPassDescriptor")
open class MTLRenderPassDescriptor: NSObject {
    var colors = MTLRenderPassColorAttachmentDescriptorArray()
    var depth = MTLRenderPassDepthAttachmentDescriptor()
    var stencil = MTLRenderPassStencilAttachmentDescriptor()
    var visibilityResultBuffer: MTLBuffer?
    var renderTargetWidth: UInt = 0
    var renderTargetHeight: UInt = 0
    var renderTargetArrayLength: UInt = 0
    var defaultRasterSampleCount: UInt = 0
    var sampleAttachments = MTLPassSampleBufferAttachmentDescriptorArray()

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("sampleBufferAttachments")
    func sampleBufferAttachments() -> MTLPassSampleBufferAttachmentDescriptorArray { sampleAttachments }

    @ObjCClassMethod("renderPassDescriptor") static func renderPassDescriptor() -> MTLRenderPassDescriptor { MTLRenderPassDescriptor() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLRenderPassDescriptor {
        let copy = MTLRenderPassDescriptor()
        for (index, color) in colors.slots.elements { copy.colors.slots.set(color, at: index) }
        copy.depth.copy(from: depth)
        copy.stencil.copy(from: stencil)
        copy.visibilityResultBuffer = visibilityResultBuffer
        (copy.renderTargetWidth, copy.renderTargetHeight) = (renderTargetWidth, renderTargetHeight)
        (copy.renderTargetArrayLength, copy.defaultRasterSampleCount) = (renderTargetArrayLength, defaultRasterSampleCount)
        return copy
    }

    /// The pass for metal2vulkan, and the textures and buffer it names.
    func value() -> (perry_m2v_render_pass_descriptor, [NSObject]) {
        var d = perry_m2v_render_pass_descriptor()
        var kept: [NSObject] = []
        withUnsafeMutableBytes(of: &d.color_attachments) { raw in
            let slots = raw.bindMemory(to: perry_m2v_pass_attachment.self)
            for index in 0..<8 {
                let color = colors.slots.elements[index] ?? MTLRenderPassColorAttachmentDescriptor()
                slots[index] = color.attachment
                kept += [color.texture, color.resolveTexture].compactMap { $0 }
            }
        }
        d.depth_attachment = depth.attachment
        d.stencil_attachment = stencil.attachment
        kept += [depth.texture, depth.resolveTexture, stencil.texture, stencil.resolveTexture, visibilityResultBuffer]
            .compactMap { $0 }
        d.visibility_result_buffer = visibilityResultBuffer?.handle
        d.render_target_width = UInt64(renderTargetWidth)
        d.render_target_height = UInt64(renderTargetHeight)
        d.render_target_array_length = UInt64(renderTargetArrayLength)
        d.default_raster_sample_count = UInt64(defaultRasterSampleCount)
        return (d, kept)
    }

    @ObjCMethod("colorAttachments") func colorAttachments() -> MTLRenderPassColorAttachmentDescriptorArray { colors }
    @ObjCMethod("depthAttachment") func depthAttachment() -> MTLRenderPassDepthAttachmentDescriptor { depth }
    @ObjCMethod("setDepthAttachment:") func setDepthAttachment(_ attachment: MTLRenderPassDepthAttachmentDescriptor?) {
        depth.copy(from: attachment ?? MTLRenderPassDepthAttachmentDescriptor())
    }
    @ObjCMethod("stencilAttachment") func stencilAttachment() -> MTLRenderPassStencilAttachmentDescriptor { stencil }
    @ObjCMethod("setStencilAttachment:") func setStencilAttachment(_ attachment: MTLRenderPassStencilAttachmentDescriptor?) {
        stencil.copy(from: attachment ?? MTLRenderPassStencilAttachmentDescriptor())
    }
    @ObjCMethod("visibilityResultBuffer") func getVisibilityResultBuffer() -> MTLBuffer? { visibilityResultBuffer }
    @ObjCMethod("setVisibilityResultBuffer:") func setVisibilityResultBuffer(_ buffer: MTLBuffer?) { visibilityResultBuffer = buffer }
    @ObjCMethod("renderTargetWidth") func getRenderTargetWidth() -> UInt { renderTargetWidth }
    @ObjCMethod("setRenderTargetWidth:") func setRenderTargetWidth(_ width: UInt) { renderTargetWidth = width }
    @ObjCMethod("renderTargetHeight") func getRenderTargetHeight() -> UInt { renderTargetHeight }
    @ObjCMethod("setRenderTargetHeight:") func setRenderTargetHeight(_ height: UInt) { renderTargetHeight = height }
    @ObjCMethod("renderTargetArrayLength") func getRenderTargetArrayLength() -> UInt { renderTargetArrayLength }
    @ObjCMethod("setRenderTargetArrayLength:") func setRenderTargetArrayLength(_ length: UInt) { renderTargetArrayLength = length }
    @ObjCMethod("defaultRasterSampleCount") func getDefaultRasterSampleCount() -> UInt { defaultRasterSampleCount }
    @ObjCMethod("setDefaultRasterSampleCount:") func setDefaultRasterSampleCount(_ count: UInt) { defaultRasterSampleCount = count }
}
