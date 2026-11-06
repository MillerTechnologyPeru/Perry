import CPerryGeometry
import CPerryMetal
import Glibc
import PerryObjCInterop

// Textures, sampler states and depth-stencil states, each holding
// metal2vulkan's handle and its device.

@ObjCProtocol("MTLTexture")
protocol MTLTextureProtocol: MTLResourceProtocol {}

@ObjCProtocol("MTLSamplerState")
protocol MTLSamplerStateProtocol {}

@ObjCProtocol("MTLDepthStencilState")
protocol MTLDepthStencilStateProtocol {}

@ObjCProtocol("MTLRenderPipelineState")
protocol MTLRenderPipelineStateProtocol {}

/// Rows of blocks a compressed format's `height` texels take; the height
/// for others.
func rows(format: UInt32, height: UInt64) -> UInt64 {
    let blockHeight: UInt64
    switch format {
    case 130...143, 160...167, 170...183: blockHeight = 4                 // BC, PVRTC, ETC2 and EAC
    case 186...236: blockHeight = astcBlockHeight(format)                 // ASTC
    default: blockHeight = 1
    }
    return (height + blockHeight - 1) / blockHeight
}

private func astcBlockHeight(_ format: UInt32) -> UInt64 {
    // MTLPixelFormatASTC_<w>x<h>, from each group's 4x4: sRGB at 186, LDR at
    // 204, HDR at 222, each with a gap after 6x6: 4x4 5x4 5x5 6x5 6x6 _ 8x5
    // 8x6 8x8 10x5 10x6 10x8 10x10 12x10 12x12.
    let heights: [UInt64] = [4, 4, 5, 5, 6, 4, 5, 6, 8, 5, 6, 8, 10, 10, 12]
    let base: UInt32 = format >= 222 ? 222 : format >= 204 ? 204 : 186
    let index = Int(format - base)
    return index < heights.count ? heights[index] : 4
}

@ObjCClass("_MTLTexture")
open class MTLTexture: NSObject, MTLTextureProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var parent: MTLTexture?
    var descriptor = perry_m2v_texture_descriptor()
    var label: String?
    var framebufferOnly = false

    init(handle: perry_m2v_handle, device: MTLDevice, parent: MTLTexture? = nil) {
        self.handle = handle
        owner = device
        self.parent = parent
        super.init()
        M2V.api.texture_descriptor_get(handle, &descriptor)
    }

    deinit {
        if let handle { M2V.api.texture_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("textureType") func textureType() -> UInt { UInt(descriptor.texture_type) }
    @ObjCMethod("pixelFormat") func pixelFormat() -> UInt { UInt(descriptor.pixel_format) }
    @ObjCMethod("width") func width() -> UInt { UInt(descriptor.width) }
    @ObjCMethod("height") func height() -> UInt { UInt(descriptor.height) }
    @ObjCMethod("depth") func depth() -> UInt { UInt(descriptor.depth) }
    @ObjCMethod("mipmapLevelCount") func mipmapLevelCount() -> UInt { UInt(descriptor.mipmap_level_count) }
    @ObjCMethod("sampleCount") func sampleCount() -> UInt { UInt(descriptor.sample_count) }
    @ObjCMethod("arrayLength") func arrayLength() -> UInt { UInt(descriptor.array_length) }
    @ObjCMethod("usage") func usage() -> UInt { UInt(descriptor.usage) }
    @ObjCMethod("resourceOptions") func resourceOptions() -> UInt { UInt(descriptor.resource_options) }
    @ObjCMethod("cpuCacheMode") func cpuCacheMode() -> UInt { UInt(descriptor.resource_options & 0xf) }
    @ObjCMethod("storageMode") func storageMode() -> UInt { UInt((descriptor.resource_options >> 4) & 0xf) }
    @ObjCMethod("hazardTrackingMode") func hazardTrackingMode() -> UInt { UInt((descriptor.resource_options >> 8) & 0x3) }
    @ObjCMethod("isFramebufferOnly") func isFramebufferOnly() -> Bool { framebufferOnly }
    @ObjCMethod("framebufferOnly") func getFramebufferOnly() -> Bool { framebufferOnly }
    @ObjCMethod("parentTexture") func parentTexture() -> MTLTexture? { parent }
    @ObjCMethod("allowGPUOptimizedContents") func allowGPUOptimizedContents() -> Bool { true }
    @ObjCMethod("isShareable") func isShareable() -> Bool { false }
    @ObjCMethod("setPurgeableState:") func setPurgeableState(_ state: UInt) -> UInt { 2 }
    /// A texture made by the device, not from a heap, so never aliasable.
    @ObjCMethod("heap") func heap() -> NSObject? { nil }
    @ObjCMethod("heapOffset") func heapOffset() -> UInt { 0 }
    @ObjCMethod("isAliasable") func isAliasable() -> Bool { false }
    @ObjCMethod("makeAliasable") func makeAliasable() {}

    // MARK: Contents

    private func length(_ region: MTLRegion, bytesPerRow: UInt, bytesPerImage: UInt) -> Int {
        let images = UInt64(max(region.size.depth, 1))
        let rowCount = rows(format: descriptor.pixel_format, height: UInt64(region.size.height))
        let image = bytesPerImage != 0 ? UInt64(bytesPerImage) : UInt64(bytesPerRow) * rowCount
        return Int(image * (images - 1) + UInt64(bytesPerRow) * rowCount)
    }

    @ObjCMethod("replaceRegion:mipmapLevel:withBytes:bytesPerRow:")
    func replace(region: MTLRegion, mipmapLevel: UInt, bytes: UnsafeRawPointer?, bytesPerRow: UInt) {
        replace(region: region, mipmapLevel: mipmapLevel, slice: 0, bytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: 0)
    }

    @ObjCMethod("replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:")
    func replace(region: MTLRegion, mipmapLevel: UInt, slice: UInt, bytes: UnsafeRawPointer?, bytesPerRow: UInt,
                 bytesPerImage: UInt) {
        let count = length(region, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        Trace.log("replaceRegion", "\(region.origin.x),\(region.origin.y) \(region.size.width)×\(region.size.height) level \(mipmapLevel) of \(descriptor.width)×\(descriptor.height) f\(descriptor.pixel_format) usage \(descriptor.usage) options \(descriptor.resource_options) mips \(descriptor.mipmap_level_count), \(bytesPerRow)/row")
        if let directory = Trace.uploadDirectory, descriptor.pixel_format == 70, region.size.width < 256, let bytes {
            // RGBA as a PPM of the colour beside one of the alpha.
            Trace.uploads += 1
            let width = Int(region.size.width), height = Int(region.size.height)
            if let file = fopen("\(directory)/upload-\(Trace.uploads)-\(width)x\(height).ppm", "wb") {
                let header = "P6\n\(width * 2) \(height)\n255\n"
                _ = header.withCString { fwrite($0, 1, strlen($0), file) }
                for y in 0..<height {
                    for x in 0..<width * 2 {
                        let p = bytes.advanced(by: y * Int(bytesPerRow) + (x % width) * 4).assumingMemoryBound(to: UInt8.self)
                        var rgb: [UInt8] = x < width ? [p[0], p[1], p[2]] : [p[3], p[3], p[3]]
                        fwrite(&rgb, 1, 3, file)
                    }
                }
                fclose(file)
            }
        }
        let (_, message) = M2V.call {
            M2V.api.texture_replace_region(handle, region, UInt64(mipmapLevel), UInt64(slice), bytes, count,
                                           UInt64(bytesPerRow), UInt64(bytesPerImage), $0)
        }
        if let message {
            metalWarning("replaceRegion: \(region.size.width)×\(region.size.height)×\(region.size.depth) at level \(mipmapLevel) of a \(descriptor.width)×\(descriptor.height) format \(descriptor.pixel_format) texture, \(bytesPerRow) bytes a row, \(bytesPerImage) an image, \(count) given: \(message)")
        }
    }

    @ObjCMethod("getBytes:bytesPerRow:fromRegion:mipmapLevel:")
    func getBytes(_ bytes: UnsafeMutableRawPointer?, bytesPerRow: UInt, region: MTLRegion, mipmapLevel: UInt) {
        getBytes(bytes, bytesPerRow: bytesPerRow, bytesPerImage: 0, region: region, mipmapLevel: mipmapLevel, slice: 0)
    }

    @ObjCMethod("getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:")
    func getBytes(_ bytes: UnsafeMutableRawPointer?, bytesPerRow: UInt, bytesPerImage: UInt, region: MTLRegion,
                  mipmapLevel: UInt, slice: UInt) {
        let count = length(region, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        Trace.log("replaceRegion", "\(region.origin.x),\(region.origin.y) \(region.size.width)×\(region.size.height) level \(mipmapLevel) of \(descriptor.width)×\(descriptor.height) f\(descriptor.pixel_format) usage \(descriptor.usage) options \(descriptor.resource_options) mips \(descriptor.mipmap_level_count), \(bytesPerRow)/row")
        let (_, message) = M2V.call {
            M2V.api.texture_get_bytes(handle, bytes, count, UInt64(bytesPerRow), UInt64(bytesPerImage), region,
                                      UInt64(mipmapLevel), UInt64(slice), $0)
        }
        if let message { metalWarning("getBytes: \(message)") }
    }

    /// Perry's, for CAMetalLayer: the 2D texture's pixels as they are, rows
    /// top first, into `pixels`; their layout as
    /// -[CALayer _perrySetPixels:width:height:opaque:layout:] takes it (3 for
    /// BGRA8, 2 for RGBA8), or -1 for another format or size.
    @ObjCMethod("_perryReadPixels:width:height:")
    func readPixels(_ pixels: UnsafeMutableRawPointer?, width: UInt, height: UInt) -> Int {
        guard let pixels, UInt64(width) == descriptor.width, UInt64(height) == descriptor.height else { return -1 }
        let layout: Int
        switch descriptor.pixel_format {
        case 70, 71: layout = 2
        case 80, 81: layout = 3
        default: return -1
        }
        let rowBytes = Int(width) * 4
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1))
        let (read, message) = M2V.call {
            M2V.api.texture_get_bytes(handle, pixels, rowBytes * Int(height), UInt64(rowBytes), 0, region, 0, 0, $0)
        }
        guard read else {
            metalWarning("reading a drawable: \(message ?? "failed")")
            return -1
        }
        return layout
    }

    /// Perry's, for CAMetalLayer: the 2D texture's pixels as RGBA rows,
    /// bottom first, as a GL frame's are; false for a format other than
    /// RGBA8 or BGRA8 or another size.
    @ObjCMethod("_perryReadRGBA:width:height:")
    func readRGBA(_ pixels: UnsafeMutableRawPointer?, width: UInt, height: UInt) -> Bool {
        guard let pixels, UInt64(width) == descriptor.width, UInt64(height) == descriptor.height else { return false }
        let bgra: Bool
        switch descriptor.pixel_format {
        case 70, 71: bgra = false
        case 80, 81: bgra = true
        default: return false
        }
        let rowBytes = Int(width) * 4
        var top = [UInt8](repeating: 0, count: rowBytes * Int(height))
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1))
        let (read, message) = M2V.call { out in
            top.withUnsafeMutableBytes {
                M2V.api.texture_get_bytes(handle, $0.baseAddress, $0.count, UInt64(rowBytes), 0, region, 0, 0, out)
            }
        }
        guard read else {
            metalWarning("reading a drawable: \(message ?? "failed")")
            return false
        }
        let out = pixels.assumingMemoryBound(to: UInt8.self)
        top.withUnsafeBufferPointer { source in
            for row in 0..<Int(height) {
                let from = source.baseAddress! + row * rowBytes
                let to = out + (Int(height) - 1 - row) * rowBytes
                if bgra {
                    for x in stride(from: 0, to: rowBytes, by: 4) {
                        to[x] = from[x + 2]
                        to[x + 1] = from[x + 1]
                        to[x + 2] = from[x]
                        to[x + 3] = from[x + 3]
                    }
                } else {
                    to.update(from: from, count: rowBytes)
                }
            }
        }
        return true
    }

    // MARK: Views

    @ObjCMethod("newTextureViewWithPixelFormat:")
    func newTextureView(pixelFormat: UInt) -> MTLTexture? {
        makeView(pixelFormat, UInt(descriptor.texture_type), PerryRange(location: 0, length: UInt(descriptor.mipmap_level_count)),
                 PerryRange(location: 0, length: UInt(descriptor.texture_type == 5 ? descriptor.array_length * 6 : descriptor.array_length)))
    }

    @ObjCMethod("newTextureViewWithPixelFormat:textureType:levels:slices:")
    func newTextureView(pixelFormat: UInt, textureType: UInt, levels: PerryRange, slices: PerryRange) -> MTLTexture? {
        makeView(pixelFormat, textureType, levels, slices)
    }

    private func makeView(_ pixelFormat: UInt, _ textureType: UInt, _ levels: PerryRange, _ slices: PerryRange) -> MTLTexture? {
        Trace.log("newTextureView", "f\(pixelFormat) type \(textureType) levels \(levels.location)+\(levels.length) slices \(slices.location)+\(slices.length) of \(descriptor.width)×\(descriptor.height) f\(descriptor.pixel_format) mips \(descriptor.mipmap_level_count)")
        let (view, message) = M2V.call {
            M2V.api.texture_new_view(handle, UInt32(pixelFormat), UInt32(textureType), UInt64(levels.location),
                                     UInt64(levels.length), UInt64(slices.location), UInt64(slices.length), $0)
        }
        guard let view, let owner else {
            metalWarning("newTextureViewWithPixelFormat:\(pixelFormat): \(message ?? "failed")")
            return nil
        }
        return MTLTexture(handle: view, device: owner, parent: self)
    }
}

@ObjCClass("_MTLSamplerState")
open class MTLSamplerState: NSObject, MTLSamplerStateProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice, label: String?) {
        self.handle = handle
        owner = device
        self.label = label
        super.init()
    }

    deinit {
        if let handle { M2V.api.sampler_state_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
}

@ObjCClass("_MTLDepthStencilState")
open class MTLDepthStencilState: NSObject, MTLDepthStencilStateProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice, label: String?) {
        self.handle = handle
        owner = device
        self.label = label
        super.init()
    }

    deinit {
        if let handle { M2V.api.depth_stencil_state_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
}

@ObjCClass("_MTLRenderPipelineState")
open class MTLRenderPipelineState: NSObject, MTLRenderPipelineStateProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice, label: String?) {
        self.handle = handle
        owner = device
        self.label = label
        super.init()
    }

    deinit {
        if let handle { M2V.api.render_pipeline_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("supportIndirectCommandBuffers") func supportIndirectCommandBuffers() -> Bool { false }
}
