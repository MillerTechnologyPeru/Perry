import CPerryMetal
import PerryObjCInterop

// Heaps, which a program makes to place many buffers and textures in one
// allocation, and to let resources that are never used together share
// memory. metal2vulkan allocates each resource itself, so a heap here is a
// budget: what is made from it is made by the device, as a resource of its
// own, and the heap counts it. Resources placed on the same bytes do not
// share them, which a program that only needs them to be there at the right
// times does not notice.

extension MTLSizeAndAlign: ObjCScalar {
    public static var objCTypeEncoding: String { "{MTLSizeAndAlign=QQ}" }
}

@ObjCClass("MTLHeapDescriptor")
open class MTLHeapDescriptor: NSObject {
    var size: UInt = 0
    var storageMode: UInt = 0
    var cpuCacheMode: UInt = 0
    var hazardTrackingMode: UInt = 0
    var type: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLHeapDescriptor {
        let copy = MTLHeapDescriptor()
        copy.size = size
        copy.storageMode = storageMode
        copy.cpuCacheMode = cpuCacheMode
        copy.hazardTrackingMode = hazardTrackingMode
        copy.type = type
        return copy
    }

    @ObjCMethod("size") func getSize() -> UInt { size }
    @ObjCMethod("setSize:") func setSize(_ size: UInt) { self.size = size }
    @ObjCMethod("storageMode") func getStorageMode() -> UInt { storageMode }
    @ObjCMethod("setStorageMode:") func setStorageMode(_ mode: UInt) { storageMode = mode }
    @ObjCMethod("cpuCacheMode") func getCPUCacheMode() -> UInt { cpuCacheMode }
    @ObjCMethod("setCpuCacheMode:") func setCPUCacheMode(_ mode: UInt) { cpuCacheMode = mode }
    @ObjCMethod("hazardTrackingMode") func getHazardTrackingMode() -> UInt { hazardTrackingMode }
    @ObjCMethod("setHazardTrackingMode:") func setHazardTrackingMode(_ mode: UInt) { hazardTrackingMode = mode }
    @ObjCMethod("type") func getType() -> UInt { type }
    @ObjCMethod("setType:") func setType(_ type: UInt) { self.type = type }
    @ObjCMethod("resourceOptions") func resourceOptions() -> UInt {
        cpuCacheMode | (storageMode << 4) | (hazardTrackingMode << 8)
    }
    @ObjCMethod("setResourceOptions:") func setResourceOptions(_ options: UInt) {
        cpuCacheMode = options & 0xf
        storageMode = (options >> 4) & 0xf
        hazardTrackingMode = (options >> 8) & 0x3
    }
}

@ObjCProtocol("MTLHeap")
protocol MTLHeapProtocol {}

@ObjCClass("_MTLHeap")
open class MTLHeap: NSObject, MTLHeapProtocol {
    var owner: MTLDevice?
    var label: String?
    var size: UInt = 0
    var options: UInt = 0
    var type: UInt = 0
    var used: UInt = 0

    init(device: MTLDevice, descriptor: MTLHeapDescriptor) {
        owner = device
        size = descriptor.size
        options = descriptor.resourceOptions()
        type = descriptor.type
        super.init()
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("size") func getSize() -> UInt { size }
    @ObjCMethod("usedSize") func usedSize() -> UInt { used }
    @ObjCMethod("currentAllocatedSize") func currentAllocatedSize() -> UInt { size }
    @ObjCMethod("resourceOptions") func resourceOptions() -> UInt { options }
    @ObjCMethod("cpuCacheMode") func cpuCacheMode() -> UInt { options & 0xf }
    @ObjCMethod("storageMode") func storageMode() -> UInt { (options >> 4) & 0xf }
    @ObjCMethod("hazardTrackingMode") func hazardTrackingMode() -> UInt { (options >> 8) & 0x3 }
    @ObjCMethod("type") func getType() -> UInt { type }

    /// What can still be made: the heap's size, as resources are not placed
    /// in its bytes.
    @ObjCMethod("maxAvailableSizeWithAlignment:") func maxAvailableSize(alignment: UInt) -> UInt { size }

    /// No purgeable states: always MTLPurgeableStateNonVolatile.
    @ObjCMethod("setPurgeableState:") func setPurgeableState(_ state: UInt) -> UInt { 2 }

    @ObjCMethod("newBufferWithLength:options:")
    func newBuffer(length: UInt, options: UInt) -> MTLBuffer? { make(length: length, options: options) }

    @ObjCMethod("newBufferWithLength:options:offset:")
    func newBuffer(length: UInt, options: UInt, offset: UInt) -> MTLBuffer? { make(length: length, options: options) }

    @ObjCMethod("newTextureWithDescriptor:")
    func newTexture(descriptor: MTLTextureDescriptor?) -> MTLTexture? { make(descriptor) }

    @ObjCMethod("newTextureWithDescriptor:offset:")
    func newTexture(descriptor: MTLTextureDescriptor?, offset: UInt) -> MTLTexture? { make(descriptor) }

    private func make(length: UInt, options: UInt) -> MTLBuffer? {
        let buffer = owner?.newBuffer(length: length, options: options)
        if buffer != nil { used += Self.aligned(length) }
        return buffer
    }

    private func make(_ descriptor: MTLTextureDescriptor?) -> MTLTexture? {
        guard let descriptor else { return nil }
        let texture = owner?.newTexture(descriptor: descriptor)
        if texture != nil { used += MTLHeap.textureSizeAndAlign(descriptor).size }
        return texture
    }

    static func aligned(_ length: UInt) -> UInt { (length + 255) & ~255 }

    /// What a texture takes, to the nearest estimate: its levels, slices
    /// and samples at the format's bytes a pixel, in whole 256-byte units.
    static func textureSizeAndAlign(_ descriptor: MTLTextureDescriptor) -> MTLSizeAndAlign {
        let value = descriptor.value
        var width = max(value.width, 1), height = max(value.height, 1), depth = max(value.depth, 1)
        var total: UInt64 = 0
        for _ in 0..<max(value.mipmap_level_count, 1) {
            total += width * height * depth
            width = max(width / 2, 1)
            height = max(height / 2, 1)
            depth = max(depth / 2, 1)
        }
        let slices = max(value.array_length, 1) * (value.texture_type == 5 || value.texture_type == 6 ? 6 : 1)
        let bytes = total * slices * max(value.sample_count, 1) * UInt64(bytesPerPixel(value.pixel_format))
        return MTLSizeAndAlign(size: UInt(aligned(UInt(bytes))), align: 256)
    }

    private static func bytesPerPixel(_ format: UInt32) -> Int {
        switch format {
        case 0: return 0
        case 1...19: return 1
        case 20...49: return 2
        case 50...69: return 4
        case 70...79: return 4
        case 80...89: return 8
        case 90...109: return 8
        case 110...124: return 16
        case 130...149: return 1
        case 160...169: return 1
        case 170...189: return 1
        case 200...229: return 1
        default: return 4
        }
    }
}
