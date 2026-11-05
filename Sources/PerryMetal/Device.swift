import CPerryMetal
import PerryObjCInterop

// MTLDevice: one object per metal2vulkan device, made when an app first asks
// for a device and kept for the life of the process, as Metal keeps one per
// GPU. Apps reach it only through the MTLDevice protocol; its class is
// _MTLDevice, Metal's own base class for devices.

extension MTLSize: ObjCScalar {
    public static var objCTypeEncoding: String { "{MTLSize=QQQ}" }
}

@ObjCProtocol("MTLDevice")
protocol MTLDeviceProtocol {}

@ObjCClass("_MTLDevice")
open class MTLDevice: NSObject, MTLDeviceProtocol {
    var handle: perry_m2v_handle?
    var properties = perry_m2v_device_properties()

    init(handle: perry_m2v_handle) {
        self.handle = handle
        super.init()
        M2V.api.device_properties_get(handle, &properties)
    }

    @ObjCMethod("name") func name() -> String {
        M2V.api.device_name(handle).map { String(cString: $0) } ?? ""
    }

    @ObjCMethod("registryID") func registryID() -> UInt64 { properties.registry_id }
    @ObjCMethod("maxThreadsPerThreadgroup") func maxThreadsPerThreadgroup() -> MTLSize { properties.max_threads_per_threadgroup }
    @ObjCMethod("maxThreadgroupMemoryLength") func maxThreadgroupMemoryLength() -> UInt { UInt(properties.max_threadgroup_memory_length) }
    @ObjCMethod("hasUnifiedMemory") func hasUnifiedMemory() -> Bool { properties.has_unified_memory }
    @ObjCMethod("maxBufferLength") func maxBufferLength() -> UInt { UInt(properties.max_buffer_length) }
    /// What a buffer may be: the runtime has no working-set estimate.
    @ObjCMethod("recommendedMaxWorkingSetSize") func recommendedMaxWorkingSetSize() -> UInt64 { properties.max_buffer_length }
    @ObjCMethod("currentAllocatedSize") func currentAllocatedSize() -> UInt { 0 }

    @ObjCMethod("isLowPower") func isLowPower() -> Bool { false }
    @ObjCMethod("isHeadless") func isHeadless() -> Bool { false }
    @ObjCMethod("isRemovable") func isRemovable() -> Bool { false }
    /// MTLDeviceLocation: built in, or in a slot for a discrete GPU.
    @ObjCMethod("location") func location() -> UInt { properties.kind == 0 ? 1 : 0 }
    @ObjCMethod("locationNumber") func locationNumber() -> UInt { 0 }
    @ObjCMethod("peerGroupID") func peerGroupID() -> UInt64 { 0 }
    @ObjCMethod("peerIndex") func peerIndex() -> UInt32 { 0 }
    @ObjCMethod("peerCount") func peerCount() -> UInt32 { 0 }

    /// metal2vulkan's answer, which is true only where every row of Apple's
    /// table for the family is exact on the device; and Apple1 and Common1
    /// always, which every iOS device has and apps take for granted.
    @ObjCMethod("supportsFamily:") func supportsFamily(_ family: Int) -> Bool {
        family == 1001 || family == 3001 || M2V.api.device_supports_family(handle, Int64(family))
    }

    /// The older feature sets of the iOS GPU families the device's family
    /// answers say it has.
    @ObjCMethod("supportsFeatureSet:") func supportsFeatureSet(_ featureSet: UInt) -> Bool {
        // MTLFeatureSet_iOS_GPUFamilyN_vM, as Metal numbers them.
        let families: [UInt: Int] = [0: 1, 1: 2, 2: 1, 3: 2, 4: 3, 5: 1, 6: 2, 7: 3, 8: 1, 9: 2, 10: 3, 11: 4,
                                     12: 1, 13: 2, 14: 3, 15: 4, 16: 5]
        guard let family = families[featureSet] else { return false }
        return supportsFamily(1000 + family)
    }

    @ObjCMethod("supportsTextureSampleCount:") func supportsTextureSampleCount(_ count: UInt) -> Bool {
        M2V.api.device_supports_texture_sample_count(handle, UInt64(count)) == 1
    }

    @ObjCMethod("readWriteTextureSupport") func readWriteTextureSupport() -> UInt { UInt(properties.read_write_texture_support) }
    @ObjCMethod("argumentBuffersSupport") func argumentBuffersSupport() -> UInt { UInt(properties.argument_buffers_support) }
    @ObjCMethod("areRasterOrderGroupsSupported") func areRasterOrderGroupsSupported() -> Bool { false }
    @ObjCMethod("areProgrammableSamplePositionsSupported") func areProgrammableSamplePositionsSupported() -> Bool { false }
    @ObjCMethod("supportsShaderBarycentricCoordinates") func supportsShaderBarycentricCoordinates() -> Bool { false }
    @ObjCMethod("supportsRaytracing") func supportsRaytracing() -> Bool { false }
    @ObjCMethod("supportsDynamicLibraries") func supportsDynamicLibraries() -> Bool { false }
    @ObjCMethod("supportsFunctionPointers") func supportsFunctionPointers() -> Bool { false }
    @ObjCMethod("isDepth24Stencil8PixelFormatSupported") func isDepth24Stencil8PixelFormatSupported() -> Bool { false }

    // MARK: Queues

    @ObjCMethod("newCommandQueue") func newCommandQueue() -> MTLCommandQueue? {
        let (queue, message) = M2V.call { M2V.api.device_new_command_queue(handle, $0) }
        guard let queue else {
            metalWarning("newCommandQueue: \(message ?? "failed")")
            return nil
        }
        return MTLCommandQueue(handle: queue, device: self)
    }

    @ObjCMethod("newCommandQueueWithMaxCommandBufferCount:")
    func newCommandQueue(maxCommandBufferCount: UInt) -> MTLCommandQueue? { newCommandQueue() }

    // MARK: Buffers

    @ObjCMethod("newBufferWithLength:options:")
    func newBuffer(length: UInt, options: UInt) -> MTLBuffer? { makeBuffer(nil, length, options) }

    @ObjCMethod("newBufferWithBytes:length:options:")
    func newBuffer(bytes: UnsafeRawPointer?, length: UInt, options: UInt) -> MTLBuffer? {
        makeBuffer(bytes, length, options)
    }

    private func makeBuffer(_ bytes: UnsafeRawPointer?, _ length: UInt, _ options: UInt) -> MTLBuffer? {
        let (buffer, message) = M2V.call { M2V.api.device_new_buffer(handle, bytes, UInt64(length), UInt64(options), $0) }
        guard let buffer else {
            metalWarning("newBufferWithLength:\(length) options:\(options): \(message ?? "failed")")
            return nil
        }
        return MTLBuffer(handle: buffer, device: self, options: options)
    }

    // MARK: Libraries

    /// From a metallib's bytes.
    func makeLibrary(_ bytes: [UInt8], _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        let (library, message) = M2V.call { out in
            bytes.withUnsafeBytes { M2V.api.device_new_library_with_data(handle, $0.baseAddress, $0.count, out) }
        }
        guard let library else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.unsupported, message ?? "Invalid library")
            return nil
        }
        return MTLLibrary(handle: library, device: self)
    }

    func makeLibrary(path: String?, _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        guard let path, let bytes = readFile(path) else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.fileNotFound,
                         "Library file \(path ?? "(null)") not found")
            return nil
        }
        return makeLibrary(bytes, error)
    }

    @ObjCMethod("newLibraryWithData:error:")
    func newLibrary(data: UnsafeMutableRawPointer?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        guard let bytes = DispatchData.bytes(data) else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.unsupported, "Invalid library data")
            return nil
        }
        return makeLibrary(bytes, error)
    }

    @ObjCMethod("newLibraryWithFile:error:")
    func newLibrary(file: String?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        makeLibrary(path: file, error)
    }

    @ObjCMethod("newLibraryWithURL:error:")
    func newLibrary(url: NSURL?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        makeLibrary(path: url?.path(), error)
    }

    /// The app's default.metallib, which Xcode builds from its .metal files.
    @ObjCMethod("newDefaultLibrary") func newDefaultLibrary() -> MTLLibrary? {
        guard let path = NSBundle.main().path(forResource: "default", ofType: "metallib") else { return nil }
        return makeLibrary(path: path, nil)
    }

    @ObjCMethod("newDefaultLibraryWithBundle:error:")
    func newDefaultLibrary(bundle: NSObject?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        let bundle = bundle?.unsafeCast(to: NSBundle.self) ?? NSBundle.main()
        return makeLibrary(path: bundle.path(forResource: "default", ofType: "metallib"), error)
    }

    // MARK: Compute pipelines

    func makeComputePipeline(_ function: MTLFunction?,
                             _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLComputePipelineState? {
        guard let function, let functionHandle = function.handle else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure, "No function")
            return nil
        }
        let (state, message) = M2V.call {
            M2V.api.device_new_compute_pipeline_state_with_function(handle, functionHandle, $0)
        }
        guard let state else {
            let text = message ?? "Compiler encountered an internal error"
            metalWarning("newComputePipelineStateWithFunction: \(function.name()): \(text)")
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure, text)
            return nil
        }
        return MTLComputePipelineState(handle: state, device: self)
    }

    @ObjCMethod("newComputePipelineStateWithFunction:error:")
    func newComputePipelineState(function: MTLFunction?,
                                 error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLComputePipelineState? {
        makeComputePipeline(function, error)
    }

    /// Without reflection: *reflection is left nil.
    @ObjCMethod("newComputePipelineStateWithFunction:options:reflection:error:")
    func newComputePipelineState(function: MTLFunction?, options: UInt, reflection: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                 error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLComputePipelineState? {
        reflection?.pointee = nil
        return makeComputePipeline(function, error)
    }
}

enum Devices {
    /// Every device, preferred first; none without metal2vulkan or Vulkan.
    nonisolated(unsafe) static let all: [MTLDevice] = {
        guard let api = perry_metal2vulkan()?.pointee else {
            metalWarning("no Metal devices: \(perry_metal2vulkan_error().map { String(cString: $0) } ?? "no metal2vulkan")")
            return []
        }
        var handles = [perry_m2v_handle?](repeating: nil, count: 16)
        let (count, message) = M2V.call { api.copy_all_devices(&handles, handles.count, $0) }
        guard count > 0 else {
            metalWarning("no Metal devices: \(message ?? "metal2vulkan found no Vulkan 1.2 device")")
            return []
        }
        return handles.prefix(Int(min(count, Int64(handles.count)))).compactMap { $0 }.map { MTLDevice(handle: $0) }
    }()
}

/// id<MTLDevice> MTLCreateSystemDefaultDevice(void), returned retained.
@c(_MTLCreateSystemDefaultDevice)
public func MTLCreateSystemDefaultDevice() -> UnsafeMutableRawPointer? {
    Devices.all.first?.objCOwnedReturnValue()
}

/// NSArray<id<MTLDevice>> *MTLCopyAllDevices(void), returned retained.
@c(_MTLCopyAllDevices)
public func MTLCopyAllDevices() -> UnsafeMutableRawPointer? {
    NSObject.array(Devices.all).objCOwnedReturnValue()
}
