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
    /// table for the family is exact on the device; and always Apple1 to
    /// Apple3 and Common1 and Common2, whose features a Vulkan 1.2 device
    /// has (not Apple4's imageblocks and tile shaders), and which apps choose
    /// their renderers by, every iOS 16 device having Apple4.
    @ObjCMethod("supportsFamily:") func supportsFamily(_ family: Int) -> Bool {
        let answer = [1001, 1002, 1003, 3001, 3002].contains(family) || M2V.api.device_supports_family(handle, Int64(family))
        Trace.log("supportsFamily:\(family)", "\(answer)")
        return answer
    }

    /// The older feature sets of the iOS GPU families the device's family
    /// answers say it has.
    @ObjCMethod("supportsFeatureSet:") func supportsFeatureSet(_ featureSet: UInt) -> Bool {
        // MTLFeatureSet_iOS_GPUFamilyN_vM, as Metal numbers them.
        let families: [UInt: Int] = [0: 1, 1: 2, 2: 1, 3: 2, 4: 3, 5: 1, 6: 2, 7: 3, 8: 1, 9: 2, 10: 3, 11: 4,
                                     12: 1, 13: 2, 14: 3, 15: 4, 16: 5]
        guard let family = families[featureSet] else { return false }
        Trace.log("supportsFeatureSet:\(featureSet)")
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

    // The answers a Mac's GPU gives, which Mac games ask before they start:
    // BC compressed textures, filtering and multisampling 32-bit floats, and
    // texture LOD queries, as every Apple-silicon Mac has. metal2vulkan's ABI
    // doesn't report the Vulkan features behind them yet, so these aren't
    // the device's own answers.
    @ObjCMethod("supportsBCTextureCompression") func supportsBCTextureCompression() -> Bool { true }
    @ObjCMethod("supports32BitFloatFiltering") func supports32BitFloatFiltering() -> Bool { true }
    @ObjCMethod("supports32BitMSAA") func supports32BitMSAA() -> Bool { true }
    @ObjCMethod("supportsQueryTextureLOD") func supportsQueryTextureLOD() -> Bool { true }
    @ObjCMethod("supportsPullModelInterpolation") func supportsPullModelInterpolation() -> Bool { false }
    @ObjCMethod("supportsPrimitiveMotionBlur") func supportsPrimitiveMotionBlur() -> Bool { false }
    @ObjCMethod("supportsRenderDynamicLibraries") func supportsRenderDynamicLibraries() -> Bool { false }
    /// Vertex amplification: one view, without it.
    @ObjCMethod("supportsVertexAmplificationCount:") func supportsVertexAmplificationCount(_ count: UInt) -> Bool { count <= 1 }
    /// Variable rasterization rates: none, so no rate maps are made.
    @ObjCMethod("supportsRasterizationRateMapWithLayerCount:")
    func supportsRasterizationRateMap(layerCount: UInt) -> Bool { false }
    /// Counter sampling at stage, draw, dispatch, tile or blit boundaries: none.
    @ObjCMethod("supportsCounterSampling:") func supportsCounterSampling(_ point: UInt) -> Bool { false }
    @ObjCMethod("counterSets") func counterSets() -> NSObject? { nil }
    /// Samplers an argument buffer holds: Apple's tier 2 limit, or tier 1's.
    @ObjCMethod("maxArgumentBufferSamplerCount")
    func maxArgumentBufferSamplerCount() -> UInt { properties.argument_buffers_support >= 1 ? 1024 : 16 }
    /// Bytes a second between the CPU and the GPU: 0, as for unified memory.
    @ObjCMethod("maxTransferRate") func maxTransferRate() -> UInt64 { 0 }
    @ObjCMethod("shouldMaximizeConcurrentCompilation") func shouldMaximizeConcurrentCompilation() -> Bool { false }
    @ObjCMethod("setShouldMaximizeConcurrentCompilation:") func setShouldMaximizeConcurrentCompilation(_ value: Bool) {}
    @ObjCMethod("maximumConcurrentCompilationTaskCount") func maximumConcurrentCompilationTaskCount() -> UInt { 1 }

    // MARK: Queues

    @ObjCMethod("newCommandQueue") func newCommandQueue() -> MTLCommandQueue? {
        Trace.log("newCommandQueue")
        let (queue, message) = M2V.call { M2V.api.device_new_command_queue(handle, $0) }
        guard let queue else {
            metalWarning("newCommandQueue: \(message ?? "failed")")
            return nil
        }
        return MTLCommandQueue(handle: queue, device: self)
    }

    @ObjCMethod("newCommandQueueWithMaxCommandBufferCount:")
    func newCommandQueue(maxCommandBufferCount: UInt) -> MTLCommandQueue? { newCommandQueue() }


    @ObjCMethod("newFence") func newFence() -> MTLFence? { MTLFence(device: self) }

    // MARK: Heaps

    @ObjCMethod("newHeapWithDescriptor:") func newHeap(descriptor: MTLHeapDescriptor?) -> MTLHeap? {
        guard let descriptor else { return nil }
        return MTLHeap(device: self, descriptor: descriptor)
    }

    @ObjCMethod("heapBufferSizeAndAlignWithLength:options:")
    func heapBufferSizeAndAlign(length: UInt, options: UInt) -> MTLSizeAndAlign {
        MTLSizeAndAlign(size: MTLHeap.aligned(length), align: 256)
    }

    @ObjCMethod("heapTextureSizeAndAlignWithDescriptor:")
    func heapTextureSizeAndAlign(descriptor: MTLTextureDescriptor?) -> MTLSizeAndAlign {
        guard let descriptor else { return MTLSizeAndAlign(size: 0, align: 256) }
        return MTLHeap.textureSizeAndAlign(descriptor)
    }

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

    /// Metal Shading Language source, which metal2vulkan cannot compile:
    /// the library Scripts/compile-metal-sources.sh built from the same
    /// source on a Mac, from the source cache. A source not there yet is
    /// written to the cache for that script, and fails here.
    @ObjCMethod("newLibraryWithSource:options:error:")
    func newLibrary(source: String?, options: NSObject?,
                    error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLLibrary? {
        guard let source else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure, "No source")
            return nil
        }
        Trace.log("newLibraryWithSource")
        switch SourceCache.library(for: source) {
        case .compiled(let bytes):
            return makeLibrary(bytes, error)
        case .missing(let path):
            metalWarning("no compiled library for Metal source \(path); compile it with Scripts/compile-metal-sources.sh")
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure,
                         "Perry has no compiled library for this source (\(path))")
            return nil
        }
    }

    /// The same, calling `completionHandler` with the library and error.
    @ObjCMethod("newLibraryWithSource:options:completionHandler:")
    func newLibrary(source: String?, options: NSObject?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let library = newLibrary(source: source, options: options, error: &error)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        guard let completionHandler else { return }
        completionHandler.function(as: Invoke.self)(completionHandler.object, library?.objcObject, error)
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

    // MARK: Textures, samplers and states

    @ObjCMethod("newTextureWithDescriptor:") func newTexture(descriptor: MTLTextureDescriptor?) -> MTLTexture? {
        guard var value = descriptor?.value else { return nil }
        let (texture, message) = M2V.call { M2V.api.device_new_texture(handle, &value, $0) }
        guard let texture else {
            metalWarning("newTextureWithDescriptor: \(value.width)×\(value.height) format \(value.pixel_format): \(message ?? "failed")")
            return nil
        }
        return MTLTexture(handle: texture, device: self)
    }

    @ObjCMethod("newSamplerStateWithDescriptor:") func newSamplerState(descriptor: MTLSamplerDescriptor?) -> MTLSamplerState? {
        guard let descriptor else { return nil }
        var value = descriptor.value
        Trace.log("newSamplerState", "min \(value.min_filter) mag \(value.mag_filter) mip \(value.mip_filter) lod \(value.lod_min_clamp)…\(value.lod_max_clamp) aniso \(value.max_anisotropy)")
        if Trace.debugNoMips { value.mip_filter = 0 }
        let (sampler, message) = M2V.call { M2V.api.device_new_sampler_state(handle, &value, $0) }
        guard let sampler else {
            metalWarning("newSamplerStateWithDescriptor: \(message ?? "failed")")
            return nil
        }
        return MTLSamplerState(handle: sampler, device: self, label: descriptor.label)
    }

    @ObjCMethod("newDepthStencilStateWithDescriptor:")
    func newDepthStencilState(descriptor: MTLDepthStencilDescriptor?) -> MTLDepthStencilState? {
        guard let descriptor else { return nil }
        var value = descriptor.value
        let (state, message) = M2V.call { M2V.api.device_new_depth_stencil_state(handle, &value, $0) }
        guard let state else {
            metalWarning("newDepthStencilStateWithDescriptor: \(message ?? "failed")")
            return nil
        }
        return MTLDepthStencilState(handle: state, device: self, label: descriptor.label)
    }

    // MARK: Render pipelines

    func makeRenderPipeline(_ descriptor: MTLRenderPipelineDescriptor?,
                            _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLRenderPipelineState? {
        guard let descriptor, descriptor.vertexFunction != nil else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure, "No vertex function")
            return nil
        }
        var value = descriptor.value
        if Trace.enabled {
            let c = value.color_attachments.0
            var attributes = ""
            if value.has_vertex_descriptor {
                withUnsafeBytes(of: value.attributes) { raw in
                    for (i, a) in raw.bindMemory(to: perry_m2v_vertex_attribute.self).enumerated() where a.format != 0 {
                        attributes += " a\(i):f\(a.format)@\(a.offset)b\(a.buffer_index)"
                    }
                }
                withUnsafeBytes(of: value.layouts) { raw in
                    for (i, l) in raw.bindMemory(to: perry_m2v_vertex_layout.self).enumerated() where l.stride != 0 {
                        attributes += " l\(i):s\(l.stride)/\(l.step_function)"
                    }
                }
            }
            metalWarning("pipeline \(descriptor.vertexFunction?.name() ?? "")/\(descriptor.fragmentFunction?.name() ?? ""): c0 f\(c.pixel_format) blend \(c.blending_enabled) \(c.source_rgb_blend_factor),\(c.destination_rgb_blend_factor),\(c.rgb_blend_operation) \(c.source_alpha_blend_factor),\(c.destination_alpha_blend_factor),\(c.alpha_blend_operation) mask \(c.write_mask) depth f\(value.depth_attachment_pixel_format) raster \(value.rasterization_enabled) samples \(value.raster_sample_count)\(attributes)")
        }
        let (state, message) = M2V.call { M2V.api.device_new_render_pipeline_state(handle, &value, $0) }
        guard let state else {
            let text = message ?? "Compiler encountered an internal error"
            metalWarning("newRenderPipelineStateWithDescriptor: \(descriptor.vertexFunction?.name() ?? "")/\(descriptor.fragmentFunction?.name() ?? ""): \(text)")
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure, text)
            return nil
        }
        return MTLRenderPipelineState(handle: state, device: self, label: descriptor.label)
    }

    @ObjCMethod("newRenderPipelineStateWithDescriptor:error:")
    func newRenderPipelineState(descriptor: MTLRenderPipelineDescriptor?,
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLRenderPipelineState? {
        makeRenderPipeline(descriptor, error)
    }

    /// With *reflection the state's arguments, autoreleased, or nil.
    @ObjCMethod("newRenderPipelineStateWithDescriptor:options:reflection:error:")
    func newRenderPipelineState(descriptor: MTLRenderPipelineDescriptor?, options: UInt,
                                reflection: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLRenderPipelineState? {
        reflection?.pointee = nil
        let state = makeRenderPipeline(descriptor, error)
        if let reflection, let handle = state?.handle, let object = MTLRenderPipelineReflection.of(handle) {
            if Trace.enabled {
                let describe = { (list: [MTLArgument]) in
                    list.map { "\($0.argument.name)#\($0.argument.index)t\($0.argument.type)\($0.argument.active ? "" : "-")\($0.argument.bufferStructType.map { "{\($0.structure.members.map { "\($0.member.name)@\($0.member.offset)" }.joined(separator: ","))}" } ?? "")" }.joined(separator: " ")
                }
                metalWarning("reflection: vertex \(describe(object.stages.vertex)); fragment \(describe(object.stages.fragment))")
            }
            reflection.pointee = object.objCReturnValue()
        }
        return state
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

    /// With *reflection the kernel's arguments, autoreleased, or nil.
    @ObjCMethod("newComputePipelineStateWithFunction:options:reflection:error:")
    func newComputePipelineState(function: MTLFunction?, options: UInt, reflection: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                 error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLComputePipelineState? {
        reflection?.pointee = nil
        let state = makeComputePipeline(function, error)
        if let reflection, let handle = state?.handle, let object = MTLComputePipelineReflection.of(handle) {
            reflection.pointee = object.objCReturnValue()
        }
        return state
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
    Trace.log("MTLCreateSystemDefaultDevice")
    return Devices.all.first?.objCOwnedReturnValue()
}

/// NSArray<id<MTLDevice>> *MTLCopyAllDevices(void), returned retained.
@c(_MTLCopyAllDevices)
public func MTLCopyAllDevices() -> UnsafeMutableRawPointer? {
    NSObject.array(Devices.all).objCOwnedReturnValue()
}

/// NSArray<id<MTLDevice>> *MTLCopyAllDevicesWithObserver(id<NSObject> *observer,
/// MTLDeviceNotificationHandler handler): the devices, retained. Devices
/// are never added or removed, so the handler is never called and the
/// observer is nil.
@c(_MTLCopyAllDevicesWithObserver)
public func MTLCopyAllDevicesWithObserver(_ observer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                          _ handler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    observer?.pointee = nil
    return MTLCopyAllDevices()
}

@c(_MTLRemoveDeviceObserver) public func MTLRemoveDeviceObserver(_ observer: UnsafeMutableRawPointer?) {}

/// The device notifications' names, and the common counters' and counter
/// sets' names.
@ObjCConstants
enum DeviceNotifications {
    static let MTLDeviceWasAddedNotification = "MTLDeviceWasAddedNotification"
    static let MTLDeviceRemovalRequestedNotification = "MTLDeviceRemovalRequestedNotification"
    static let MTLDeviceWasRemovedNotification = "MTLDeviceWasRemovedNotification"
    static let MTLCommonCounterTimestamp = "timestamp"
    static let MTLCommonCounterSetTimestamp = "timestamp"
}
