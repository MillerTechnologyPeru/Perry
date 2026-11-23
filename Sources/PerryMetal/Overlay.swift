import CPerryGeometry
import CPerryMetal
import Glibc
import PerryObjCInterop

// The calls Metal's Swift overlay makes beyond the ones the encoders and
// the device answer elsewhere: the pointer-and-count and NSRange forms the
// overlay's array and Range calls send (each set in turn through the single
// form), the device's sample positions and timestamps, the async waits of
// command buffers, texture views with a swizzle; and the answers a device
// without a feature gives for it, as its supports… calls already say:
// no ray tracing, function pointers, dynamic or binary libraries, mesh or
// tile pipelines, counters, rasterization rate maps, indirect command
// buffers, residency sets, sparse resources, IO queues, tensors or Metal 4
// queues and compilers. What makes one of those gives nil (and an error
// where the call takes one), so nothing that takes one can ever be given
// one; those calls do nothing.

enum Unsupported {
    /// An error for a feature the device lacks, in Metal's library domain
    /// as Metal reports one (MTLLibraryErrorUnsupported).
    static func fail(_ error: UnsupportedError, _ what: String) {
        Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.unsupported, "\(what) is not supported on this device")
    }

    /// The same, to a completion handler taking (object, error).
    static func fail(_ handler: ObjCBlock?, _ what: String) {
        guard let handler else { return }
        var error: UnsafeMutableRawPointer?
        fail(&error, what)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        handler.function(as: Invoke.self)(handler.object, nil, error)
    }

    typealias UnsupportedError = UnsafeMutablePointer<UnsafeMutableRawPointer?>?
}

/// Calls a completion handler taking (object, error).
private func complete(_ handler: ObjCBlock?, _ object: NSObject?, _ error: UnsafeMutableRawPointer?) {
    guard let handler else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    handler.function(as: Invoke.self)(handler.object, object?.objcObject, error)
}

/// Calls a completion handler taking (object, reflection, error).
private func complete(_ handler: ObjCBlock?, _ object: NSObject?, _ reflection: UnsafeMutableRawPointer?,
                      _ error: UnsafeMutableRawPointer?) {
    guard let handler else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                       UnsafeMutableRawPointer?) -> Void
    handler.function(as: Invoke.self)(handler.object, object?.objcObject, reflection, error)
}

/// Runs `body` on a thread of its own.
func detachThread(_ body: @escaping () -> Void) {
    final class Box { let body: () -> Void; init(_ body: @escaping () -> Void) { self.body = body } }
    var thread = pthread_t()
    let context = Unmanaged.passRetained(Box(body)).toOpaque()
    let started = pthread_create(&thread, nil, { context in
        Unmanaged<Box>.fromOpaque(context!).takeRetainedValue().body()
        return nil
    }, context)
    if started == 0 {
        pthread_detach(thread)
    } else {
        Unmanaged<Box>.fromOpaque(context).takeRetainedValue().body()
    }
}

/// Nanoseconds of the monotonic clock, which both of the device's
/// timestamps are read from.
private func monotonicNanoseconds() -> UInt64 {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
}

/// The standard sample positions of each count, as Vulkan's devices (and
/// Metal's) place them: x and y in a pixel, from its top left.
private let standardSamplePositions: [Int: [Float]] = [
    1: [0.5, 0.5],
    2: [0.75, 0.75, 0.25, 0.25],
    4: [0.375, 0.125, 0.875, 0.375, 0.125, 0.625, 0.625, 0.875],
    8: [0.5625, 0.3125, 0.4375, 0.6875, 0.8125, 0.5625, 0.3125, 0.1875,
        0.1875, 0.8125, 0.0625, 0.4375, 0.6875, 0.9375, 0.9375, 0.0625],
    16: [0.5625, 0.5625, 0.4375, 0.3125, 0.3125, 0.625, 0.75, 0.4375, 0.1875, 0.375, 0.625, 0.8125, 0.8125, 0.6875,
         0.6875, 0.1875, 0.375, 0.875, 0.5, 0.0625, 0.25, 0.125, 0.125, 0.75, 0.0, 0.5, 0.9375, 0.25, 0.875, 0.9375,
         0.0625, 0.0],
]

/// The objects of a C array of ids.
private func objects<T: NSObject>(_ pointers: UnsafePointer<UnsafeMutableRawPointer?>?, _ count: Int, as type: T.Type) -> [T?] {
    (0..<count).map { index in pointers?[index].map { T.objCInstance($0, ownership: .retain) } }
}

// MARK: - Device

/// What MTLDevice.architecture gives: the GPU's name.
@ObjCClass("MTLArchitecture")
open class MTLArchitecture: NSObject {
    var value = ""

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("name") func name() -> String { value }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLArchitecture {
        let copy = MTLArchitecture()
        copy.value = value
        return copy
    }
}

@ObjCCategory("PerryOverlay")
extension MTLDevice {
    @ObjCMethod("architecture") func architecture() -> MTLArchitecture {
        let architecture = MTLArchitecture()
        architecture.value = name()
        return architecture
    }

    @ObjCMethod("newCommandQueueWithDescriptor:") func newCommandQueue(queueDescriptor: NSObject?) -> MTLCommandQueue? { newCommandQueue() }

    /// An event orders work between command buffers; a shared event is one.
    @ObjCMethod("newEvent") func newEvent() -> MTLSharedEvent? { MTLSharedEvent(device: self) }

    /// metal2vulkan's buffers are its own memory, so the bytes are copied
    /// into one and the deallocator runs once the buffer goes; writes to
    /// the bytes afterwards do not reach the buffer, and its contents are
    /// not at their address.
    @ObjCMethod("newBufferWithBytesNoCopy:length:options:deallocator:")
    func newBuffer(bytesNoCopy bytes: UnsafeMutableRawPointer?, length: UInt, options: UInt, deallocator: ObjCBlock?) -> MTLBuffer? {
        guard let buffer = newBuffer(bytes: bytes, length: length, options: options) else { return nil }
        if let deallocator {
            nonisolated(unsafe) let pointer = bytes
            buffer.onRelease = {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt) -> Void
                deallocator.function(as: Invoke.self)(deallocator.object, pointer, length)
            }
        }
        return buffer
    }

    /// Sparse buffers: none.
    @ObjCMethod("newBufferWithLength:options:placementSparsePageSize:")
    func newBuffer(length: UInt, options: UInt, placementSparsePageSize: Int) -> MTLBuffer? { nil }

    /// Linear textures and texture buffers start at 256-byte boundaries,
    /// which every Vulkan device's texel buffer alignment divides.
    @ObjCMethod("minimumLinearTextureAlignmentForPixelFormat:")
    func minimumLinearTextureAlignment(pixelFormat: UInt) -> UInt { 256 }
    @ObjCMethod("minimumTextureBufferAlignmentForPixelFormat:")
    func minimumTextureBufferAlignment(pixelFormat: UInt) -> UInt { 256 }

    /// The standard positions for 1, 2, 4, 8 and 16 samples; nothing for
    /// another count.
    @ObjCMethod("getDefaultSamplePositions:count:")
    func getDefaultSamplePositions(_ positions: UnsafeMutablePointer<Float>?, count: UInt) {
        guard let positions, let standard = standardSamplePositions[Int(count)] else { return }
        positions.update(from: standard, count: standard.count)
    }

    /// The CPU's and the GPU's time together: one clock, in nanoseconds.
    @ObjCMethod("sampleTimestamps:gpuTimestamp:")
    func sampleTimestamps(_ cpu: UnsafeMutablePointer<UInt64>?, gpuTimestamp gpu: UnsafeMutablePointer<UInt64>?) {
        let now = monotonicNanoseconds()
        cpu?.pointee = now
        gpu?.pointee = now
    }

    @ObjCMethod("queryTimestampFrequency") func queryTimestampFrequency() -> UInt64 { 1_000_000_000 }

    @ObjCMethod("areBarycentricCoordsSupported") func areBarycentricCoordsSupported() -> Bool { false }
    @ObjCMethod("supportsFunctionPointersFromRender") func supportsFunctionPointersFromRender() -> Bool { false }
    @ObjCMethod("supportsRaytracingFromRender") func supportsRaytracingFromRender() -> Bool { false }
    @ObjCMethod("supportsPlacementSparse") func supportsPlacementSparse() -> Bool { false }

    // Sparse textures: none, so tiles have no size.
    @ObjCMethod("sparseTileSizeInBytes") func sparseTileSizeInBytes() -> UInt { 0 }
    @ObjCMethod("sparseTileSizeInBytesForSparsePageSize:") func sparseTileSizeInBytes(sparsePageSize: Int) -> UInt { 0 }
    @ObjCMethod("sparseTileSizeWithTextureType:pixelFormat:sampleCount:")
    func sparseTileSize(textureType: UInt, pixelFormat: UInt, sampleCount: UInt) -> MTLSize { MTLSize(width: 0, height: 0, depth: 0) }
    @ObjCMethod("sparseTileSizeWithTextureType:pixelFormat:sampleCount:sparsePageSize:")
    func sparseTileSize(textureType: UInt, pixelFormat: UInt, sampleCount: UInt, sparsePageSize: Int) -> MTLSize {
        MTLSize(width: 0, height: 0, depth: 0)
    }
    @ObjCMethod("convertSparsePixelRegions:toTileRegions:withTileSize:alignmentMode:numRegions:")
    func convertSparsePixelRegions(_ pixels: UnsafeRawPointer?, toTileRegions tiles: UnsafeMutableRawPointer?, tileSize: MTLSize,
                                   alignmentMode: UInt, numRegions: UInt) {}
    @ObjCMethod("convertSparseTileRegions:toPixelRegions:withTileSize:numRegions:")
    func convertSparseTileRegions(_ tiles: UnsafeRawPointer?, toPixelRegions pixels: UnsafeMutableRawPointer?, tileSize: MTLSize,
                                  numRegions: UInt) {}

    // MARK: Pipelines, given to a completion handler

    @ObjCMethod("newRenderPipelineStateWithDescriptor:completionHandler:")
    func newRenderPipelineState(descriptor: MTLRenderPipelineDescriptor?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let state = newRenderPipelineState(descriptor: descriptor, error: &error)
        complete(completionHandler, state, error)
    }

    @ObjCMethod("newRenderPipelineStateWithDescriptor:options:completionHandler:")
    func newRenderPipelineState(descriptor: MTLRenderPipelineDescriptor?, options: UInt, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?, reflection: UnsafeMutableRawPointer?
        let state = newRenderPipelineState(descriptor: descriptor, options: options, reflection: &reflection, error: &error)
        complete(completionHandler, state, reflection, error)
    }

    @ObjCMethod("newComputePipelineStateWithFunction:completionHandler:")
    func newComputePipelineState(function: MTLFunction?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let state = newComputePipelineState(function: function, error: &error)
        complete(completionHandler, state, error)
    }

    @ObjCMethod("newComputePipelineStateWithFunction:options:completionHandler:")
    func newComputePipelineState(function: MTLFunction?, options: UInt, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?, reflection: UnsafeMutableRawPointer?
        let state = newComputePipelineState(function: function, options: options, reflection: &reflection, error: &error)
        complete(completionHandler, state, reflection, error)
    }

    @ObjCMethod("newComputePipelineStateWithDescriptor:options:completionHandler:")
    func newComputePipelineState(descriptor: MTLComputePipelineDescriptor?, options: UInt, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?, reflection: UnsafeMutableRawPointer?
        let state = newComputePipelineState(descriptor: descriptor, options: options, reflection: &reflection, error: &error)
        complete(completionHandler, state, reflection, error)
    }

    @ObjCMethod("newComputePipelineStateWithDescriptor:error:")
    func newComputePipelineState(descriptor: MTLComputePipelineDescriptor?, error: Unsupported.UnsupportedError) -> MTLComputePipelineState? {
        newComputePipelineState(descriptor: descriptor, options: 0, reflection: nil, error: error)
    }

    // MARK: What the device has none of

    @ObjCMethod("newRenderPipelineStateWithMeshDescriptor:options:reflection:error:")
    func newRenderPipelineState(meshDescriptor: NSObject?, options: UInt, reflection: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                error: Unsupported.UnsupportedError) -> MTLRenderPipelineState? {
        reflection?.pointee = nil
        Unsupported.fail(error, "A mesh render pipeline")
        return nil
    }

    @ObjCMethod("newRenderPipelineStateWithMeshDescriptor:options:completionHandler:")
    func newRenderPipelineState(meshDescriptor: NSObject?, options: UInt, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        Unsupported.fail(&error, "A mesh render pipeline")
        complete(completionHandler, nil, nil, error)
    }

    @ObjCMethod("newRenderPipelineStateWithTileDescriptor:options:reflection:error:")
    func newRenderPipelineState(tileDescriptor: NSObject?, options: UInt, reflection: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                error: Unsupported.UnsupportedError) -> MTLRenderPipelineState? {
        reflection?.pointee = nil
        Unsupported.fail(error, "A tile render pipeline")
        return nil
    }

    @ObjCMethod("newRenderPipelineStateWithTileDescriptor:options:completionHandler:")
    func newRenderPipelineState(tileDescriptor: NSObject?, options: UInt, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        Unsupported.fail(&error, "A tile render pipeline")
        complete(completionHandler, nil, nil, error)
    }

    @ObjCMethod("newIndirectCommandBufferWithDescriptor:maxCommandCount:options:")
    func newIndirectCommandBuffer(descriptor: NSObject?, maxCommandCount: UInt, options: UInt) -> NSObject? { nil }
    @ObjCMethod("newRasterizationRateMapWithDescriptor:") func newRasterizationRateMap(descriptor: NSObject?) -> NSObject? { nil }
    @ObjCMethod("newAccelerationStructureWithSize:") func newAccelerationStructure(size: UInt) -> NSObject? { nil }
    @ObjCMethod("newAccelerationStructureWithDescriptor:") func newAccelerationStructure(descriptor: NSObject?) -> NSObject? { nil }
    /// MTLAccelerationStructureSizes: three NSUIntegers, as MTLSize is.
    @ObjCMethod("accelerationStructureSizesWithDescriptor:")
    func accelerationStructureSizes(descriptor: NSObject?) -> MTLSize { MTLSize(width: 0, height: 0, depth: 0) }
    @ObjCMethod("heapAccelerationStructureSizeAndAlignWithSize:")
    func heapAccelerationStructureSizeAndAlign(size: UInt) -> MTLSizeAndAlign { MTLSizeAndAlign(size: 0, align: 0) }
    @ObjCMethod("heapAccelerationStructureSizeAndAlignWithDescriptor:")
    func heapAccelerationStructureSizeAndAlign(descriptor: NSObject?) -> MTLSizeAndAlign { MTLSizeAndAlign(size: 0, align: 0) }

    @ObjCMethod("newCounterSampleBufferWithDescriptor:error:")
    func newCounterSampleBuffer(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Counter sampling")
        return nil
    }

    @ObjCMethod("newDynamicLibrary:error:")
    func newDynamicLibrary(_ library: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A dynamic library")
        return nil
    }

    @ObjCMethod("newDynamicLibraryWithURL:error:")
    func newDynamicLibrary(url: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A dynamic library")
        return nil
    }

    @ObjCMethod("newDynamicLibrary:completionHandler:")
    func newDynamicLibrary(_ library: NSObject?, completionHandler: ObjCBlock?) { Unsupported.fail(completionHandler, "A dynamic library") }

    @ObjCMethod("newDynamicLibraryWithURL:completionHandler:")
    func newDynamicLibrary(url: NSObject?, completionHandler: ObjCBlock?) { Unsupported.fail(completionHandler, "A dynamic library") }

    @ObjCMethod("newBinaryArchiveWithDescriptor:error:")
    func newBinaryArchive(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A binary archive")
        return nil
    }

    @ObjCMethod("newLibraryWithStitchedDescriptor:error:")
    func newLibrary(stitchedDescriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A stitched library")
        return nil
    }

    @ObjCMethod("newLibraryWithStitchedDescriptor:completionHandler:")
    func newLibrary(stitchedDescriptor: NSObject?, completionHandler: ObjCBlock?) {
        Unsupported.fail(completionHandler, "A stitched library")
    }

    @ObjCMethod("newIOHandleWithURL:error:")
    func newIOHandle(url: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Metal IO")
        return nil
    }

    @ObjCMethod("newIOHandleWithURL:compressionMethod:error:")
    func newIOHandle(url: NSObject?, compressionMethod: Int, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Metal IO")
        return nil
    }

    @ObjCMethod("newIOFileHandleWithURL:error:")
    func newIOFileHandle(url: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Metal IO")
        return nil
    }

    @ObjCMethod("newIOFileHandleWithURL:compressionMethod:error:")
    func newIOFileHandle(url: NSObject?, compressionMethod: Int, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Metal IO")
        return nil
    }

    @ObjCMethod("newIOCommandQueueWithDescriptor:error:")
    func newIOCommandQueue(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Metal IO")
        return nil
    }

    @ObjCMethod("newResidencySetWithDescriptor:error:")
    func newResidencySet(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A residency set")
        return nil
    }

    @ObjCMethod("newLogStateWithDescriptor:error:")
    func newLogState(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "Shader logging")
        return nil
    }

    @ObjCMethod("newTensorWithDescriptor:error:")
    func newTensor(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A tensor")
        return nil
    }

    @ObjCMethod("tensorSizeAndAlignWithDescriptor:")
    func tensorSizeAndAlign(descriptor: NSObject?) -> MTLSizeAndAlign { MTLSizeAndAlign(size: 0, align: 0) }

    @ObjCMethod("newMTL4CommandQueue") func newMTL4CommandQueue() -> NSObject? { nil }

    @ObjCMethod("newMTL4CommandQueueWithDescriptor:error:")
    func newMTL4CommandQueue(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A Metal 4 command queue")
        return nil
    }

    @ObjCMethod("newCommandAllocator") func newCommandAllocator() -> NSObject? { nil }

    @ObjCMethod("newCommandAllocatorWithDescriptor:error:")
    func newCommandAllocator(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A Metal 4 command allocator")
        return nil
    }

    /// Metal 4's command buffers, which only Metal 4 queues commit.
    @ObjCMethod("newCommandBuffer") func newMTL4CommandBuffer() -> NSObject? { nil }

    @ObjCMethod("newCompilerWithDescriptor:error:")
    func newCompiler(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A Metal 4 compiler")
        return nil
    }

    @ObjCMethod("newArgumentTableWithDescriptor:error:")
    func newArgumentTable(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A Metal 4 argument table")
        return nil
    }

    @ObjCMethod("newTextureViewPoolWithDescriptor:error:")
    func newTextureViewPool(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A texture view pool")
        return nil
    }

    @ObjCMethod("newCounterHeapWithDescriptor:error:")
    func newCounterHeap(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A counter heap")
        return nil
    }

    @ObjCMethod("sizeOfCounterHeapEntry:") func sizeOfCounterHeapEntry(_ type: Int) -> UInt { 0 }

    @ObjCMethod("newArchiveWithURL:error:")
    func newArchive(url: NSObject?, error: Unsupported.UnsupportedError) -> NSObject? {
        Unsupported.fail(error, "A Metal 4 archive")
        return nil
    }

    @ObjCMethod("newPipelineDataSetSerializerWithDescriptor:")
    func newPipelineDataSetSerializer(descriptor: NSObject?) -> NSObject? { nil }

    // Shared textures, events by handle and IOSurfaces cross processes,
    // which nothing here shares with.
    @ObjCMethod("newSharedTextureWithDescriptor:") func newSharedTexture(descriptor: NSObject?) -> NSObject? { nil }
    @ObjCMethod("newSharedTextureWithHandle:") func newSharedTexture(handle: NSObject?) -> NSObject? { nil }
    @ObjCMethod("newSharedEventWithHandle:") func newSharedEvent(handle: NSObject?) -> NSObject? { nil }
    @ObjCMethod("newTextureWithDescriptor:iosurface:plane:")
    func newTexture(descriptor: NSObject?, iosurface: UnsafeMutableRawPointer?, plane: UInt) -> NSObject? { nil }
}

// MARK: - Command queues and buffers

@ObjCCategory("PerryOverlay")
extension MTLCommandQueue {
    /// Residency sets: none can be made, so none are added.
    @ObjCMethod("addResidencySets:count:")
    func addResidencySets(_ sets: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt) {}
    @ObjCMethod("removeResidencySets:count:")
    func removeResidencySets(_ sets: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt) {}
}

@ObjCCategory("PerryOverlay")
extension MTLCommandBuffer {
    /// The shaders' logs: none, as no log state can be made.
    @ObjCMethod("logs") func logs() -> NSObject { NSObject.array([]) }
    @ObjCMethod("kernelStartTime") func kernelStartTime() -> Double { 0 }
    @ObjCMethod("kernelEndTime") func kernelEndTime() -> Double { 0 }
    /// MTLCommandBufferErrorOption: none asked for.
    @ObjCMethod("errorOptions") func errorOptions() -> UInt { 0 }

    @ObjCMethod("useResidencySet:") func useResidencySet(_ set: NSObject?) {}
    @ObjCMethod("useResidencySets:count:") func useResidencySets(_ sets: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt) {}

    @ObjCMethod("accelerationStructureCommandEncoder") func accelerationStructureCommandEncoder() -> NSObject? { nil }
    @ObjCMethod("accelerationStructureCommandEncoderWithDescriptor:")
    func accelerationStructureCommandEncoder(descriptor: NSObject?) -> NSObject? { nil }
    @ObjCMethod("resourceStateCommandEncoder") func resourceStateCommandEncoder() -> NSObject? { nil }
    @ObjCMethod("resourceStateCommandEncoderWithDescriptor:")
    func resourceStateCommandEncoder(descriptor: NSObject?) -> NSObject? { nil }

    /// The overlay's async waits on macOS 26 and later: the block is called
    /// with the buffer once it is scheduled or complete, from a thread of
    /// its own that waits for it.
    @ObjCMethod("__waitUntilScheduledAsync:") func waitUntilScheduledAsync(_ block: ObjCBlock?) {
        guard let block else { return }
        nonisolated(unsafe) let buffer = self
        detachThread {
            buffer.waitUntilScheduled()
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
            ObjCRuntime.autoreleasepool { block.function(as: Invoke.self)(block.object, buffer.objcObject) }
        }
    }

    @ObjCMethod("__waitUntilCompletedAsync:") func waitUntilCompletedAsync(_ block: ObjCBlock?) {
        guard let block else { return }
        nonisolated(unsafe) let buffer = self
        detachThread {
            buffer.waitUntilCompleted()
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
            ObjCRuntime.autoreleasepool { block.function(as: Invoke.self)(block.object, buffer.objcObject) }
        }
    }
}

// MARK: - Render encoders

@ObjCCategory("PerryOverlay")
extension MTLRenderCommandEncoder {
    /// Viewports and scissor rects past the first are chosen per primitive
    /// by a viewport array index, which no pipeline here writes: the first
    /// is the one every primitive uses.
    @ObjCMethod("setViewports:count:") func setViewports(_ viewports: UnsafePointer<MTLViewport>?, count: UInt) {
        guard let viewports, count > 0 else { return }
        setViewport(viewports[0])
    }

    @ObjCMethod("setScissorRects:count:") func setScissorRects(_ rects: UnsafePointer<MTLScissorRect>?, count: UInt) {
        guard let rects, count > 0 else { return }
        setScissorRect(rects[0])
    }

    /// The depth bounds test (Metal 4's), which metal2vulkan's encoders
    /// don't set: fragments are not tested against the bounds.
    @ObjCMethod("setDepthTestMinBound:maxBound:") func setDepthTestBounds(min: Float, max: Float) {
        Trace.log("setDepthTestMinBound:maxBound:", "\(min)…\(max) not applied")
    }

    /// Per-buffer strides for vertex descriptors with dynamic strides,
    /// which metal2vulkan's pipelines take from the descriptor: the buffers
    /// are bound, with the descriptor's strides.
    @ObjCMethod("setVertexBuffers:offsets:attributeStrides:withRange:")
    func setVertexBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?,
                          attributeStrides: UnsafePointer<UInt>?, withRange range: PerryRange) {
        setVertexBuffers(buffers, offsets: offsets, range: range)
    }

    @ObjCMethod("setVertexSamplerStates:withRange:")
    func setVertexSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {
        for (i, sampler) in objects(samplers, Int(range.length), as: MTLSamplerState.self).enumerated() {
            setVertexSamplerState(sampler, index: range.location + UInt(i))
        }
    }

    /// Each sampler with its own descriptor's level-of-detail clamps:
    /// metal2vulkan binds samplers as they were made.
    @ObjCMethod("setVertexSamplerStates:lodMinClamps:lodMaxClamps:withRange:")
    func setVertexSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, lodMinClamps: UnsafePointer<Float>?,
                                lodMaxClamps: UnsafePointer<Float>?, withRange range: PerryRange) {
        setVertexSamplerStates(samplers, withRange: range)
    }

    @ObjCMethod("setVertexSamplerState:lodMinClamp:lodMaxClamp:atIndex:")
    func setVertexSamplerState(_ sampler: MTLSamplerState?, lodMinClamp: Float, lodMaxClamp: Float, index: UInt) {
        setVertexSamplerState(sampler, index: index)
    }

    @ObjCMethod("setFragmentSamplerStates:lodMinClamps:lodMaxClamps:withRange:")
    func setFragmentSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, lodMinClamps: UnsafePointer<Float>?,
                                  lodMaxClamps: UnsafePointer<Float>?, withRange range: PerryRange) {
        setFragmentSamplerStates(samplers, range: range)
    }

    @ObjCMethod("setFragmentSamplerState:lodMinClamp:lodMaxClamp:atIndex:")
    func setFragmentSamplerState(_ sampler: MTLSamplerState?, lodMinClamp: Float, lodMaxClamp: Float, index: UInt) {
        setFragmentSamplerState(sampler, index: index)
    }

    /// A heap's resources, for argument buffers, made resident for reading.
    @ObjCMethod("useHeap:") func useHeap(_ heap: MTLHeap?) { useHeap(heap, stages: 3) }

    @ObjCMethod("useHeap:stages:") func useHeap(_ heap: MTLHeap?, stages: UInt) {
        for resource in heap?.resources ?? [] { useResource(resource, usage: 1, stages: stages) }
    }

    @ObjCMethod("useHeaps:count:") func useHeaps(_ heaps: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt) {
        for heap in objects(heaps, Int(count), as: MTLHeap.self) { useHeap(heap, stages: 3) }
    }

    @ObjCMethod("useHeaps:count:stages:") func useHeaps(_ heaps: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt, stages: UInt) {
        for heap in objects(heaps, Int(count), as: MTLHeap.self) { useHeap(heap, stages: stages) }
    }

    /// Render passes here keep their writes and reads in order already
    /// (metal2vulkan's pass barriers), so a barrier between them adds none.
    @ObjCMethod("memoryBarrierWithScope:afterStages:beforeStages:")
    func memoryBarrier(scope: UInt, afterStages: UInt, beforeStages: UInt) {}

    @ObjCMethod("memoryBarrierWithResources:count:afterStages:beforeStages:")
    func memoryBarrier(resources: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt, afterStages: UInt, beforeStages: UInt) {}

    // Object and mesh stages: no mesh pipeline can be made, so nothing
    // bound for them is ever read.
    @ObjCMethod("setObjectBuffers:offsets:withRange:")
    func setObjectBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?, withRange range: PerryRange) {}
    @ObjCMethod("setObjectTextures:withRange:")
    func setObjectTextures(_ textures: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setObjectSamplerStates:withRange:")
    func setObjectSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setObjectSamplerStates:lodMinClamps:lodMaxClamps:withRange:")
    func setObjectSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, lodMinClamps: UnsafePointer<Float>?,
                                lodMaxClamps: UnsafePointer<Float>?, withRange range: PerryRange) {}
    @ObjCMethod("setMeshBuffers:offsets:withRange:")
    func setMeshBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?, withRange range: PerryRange) {}
    @ObjCMethod("setMeshTextures:withRange:")
    func setMeshTextures(_ textures: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setMeshSamplerStates:withRange:")
    func setMeshSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setMeshSamplerStates:lodMinClamps:lodMaxClamps:withRange:")
    func setMeshSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, lodMinClamps: UnsafePointer<Float>?,
                              lodMaxClamps: UnsafePointer<Float>?, withRange range: PerryRange) {}

    // Indirect command buffers and function tables: none can be made.
    @ObjCMethod("executeCommandsInBuffer:withRange:") func executeCommands(in buffer: NSObject?, withRange range: PerryRange) {}
    @ObjCMethod("executeCommandsInBuffer:indirectBuffer:indirectBufferOffset:")
    func executeCommands(in buffer: NSObject?, indirectBuffer: NSObject?, indirectBufferOffset: UInt) {}
    @ObjCMethod("setVertexVisibleFunctionTables:withBufferRange:")
    func setVertexVisibleFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setFragmentVisibleFunctionTables:withBufferRange:")
    func setFragmentVisibleFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setTileVisibleFunctionTables:withBufferRange:")
    func setTileVisibleFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setVertexIntersectionFunctionTables:withBufferRange:")
    func setVertexIntersectionFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setFragmentIntersectionFunctionTables:withBufferRange:")
    func setFragmentIntersectionFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setTileIntersectionFunctionTables:withBufferRange:")
    func setTileIntersectionFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}

    /// One view: an amplification count of one is the only one supported.
    @ObjCMethod("setVertexAmplificationCount:viewMappings:")
    func setVertexAmplificationCount(_ count: UInt, viewMappings: UnsafeRawPointer?) {
        if count > 1 { Trace.log("setVertexAmplificationCount:viewMappings:", "\(count) views drawn as one") }
    }
}

// MARK: - Compute encoders

@ObjCCategory("PerryOverlay")
extension MTLComputeCommandEncoder {
    /// The writes to the resources are seen by the dispatches after: a
    /// barrier on buffers and textures.
    @ObjCMethod("memoryBarrierWithResources:count:")
    func memoryBarrier(resources: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt) {
        var scope: UInt = 0
        for resource in objects(resources, Int(count), as: NSObject.self) {
            guard let resource else { continue }
            if resource.is(MTLBuffer.self) { scope |= 1 }
            if resource.is(MTLTexture.self) { scope |= 2 }
        }
        if scope != 0 { memoryBarrier(scope: scope) }
    }

    @ObjCMethod("useHeap:") func useHeap(_ heap: MTLHeap?) {
        for resource in heap?.resources ?? [] { useResource(resource, usage: 1) }
    }

    @ObjCMethod("useHeaps:count:") func useHeaps(_ heaps: UnsafePointer<UnsafeMutableRawPointer?>?, count: UInt) {
        for heap in objects(heaps, Int(count), as: MTLHeap.self) { useHeap(heap) }
    }

    @ObjCMethod("useResource:usage:stages:") func useResource(_ resource: NSObject?, usage: UInt, stages: UInt) {
        useResource(resource, usage: usage)
    }

    /// The buffers, with the pipeline's own strides (see the render encoder's).
    @ObjCMethod("setBuffers:offsets:attributeStrides:withRange:")
    func setBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?,
                    attributeStrides: UnsafePointer<UInt>?, withRange range: PerryRange) {
        setBuffers(buffers, offsets: offsets, range: range)
    }

    @ObjCMethod("setSamplerStates:lodMinClamps:lodMaxClamps:withRange:")
    func setSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, lodMinClamps: UnsafePointer<Float>?,
                          lodMaxClamps: UnsafePointer<Float>?, withRange range: PerryRange) {
        setSamplerStates(samplers, range: range)
    }

    @ObjCMethod("setSamplerState:lodMinClamp:lodMaxClamp:atIndex:")
    func setSamplerState(_ sampler: MTLSamplerState?, lodMinClamp: Float, lodMaxClamp: Float, index: UInt) {
        setSamplerState(sampler, index: index)
    }

    @ObjCMethod("setVisibleFunctionTables:withBufferRange:")
    func setVisibleFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setIntersectionFunctionTables:withBufferRange:")
    func setIntersectionFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("executeCommandsInBuffer:withRange:") func executeCommands(in buffer: NSObject?, withRange range: PerryRange) {}
    @ObjCMethod("executeCommandsInBuffer:indirectBuffer:indirectBufferOffset:")
    func executeCommands(in buffer: NSObject?, indirectBuffer: NSObject?, indirectBufferOffset: UInt) {}
}

// MARK: - Blit encoders

@ObjCCategory("PerryOverlay")
extension MTLBlitCommandEncoder {
    /// MTLBlitOption's row-linear PVRTC and depth/stencil-from-combined
    /// choices name a part of the texture the plain copy already takes.
    @ObjCMethod("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:options:")
    func copy(from texture: MTLTexture?, sourceSlice: UInt, sourceLevel: UInt, sourceOrigin: MTLOrigin, sourceSize: MTLSize,
              to buffer: MTLBuffer?, destinationOffset: UInt, destinationBytesPerRow: UInt, destinationBytesPerImage: UInt,
              options: UInt) {
        copy(from: texture, sourceSlice: sourceSlice, sourceLevel: sourceLevel, sourceOrigin: sourceOrigin, sourceSize: sourceSize,
             to: buffer, destinationOffset: destinationOffset, destinationBytesPerRow: destinationBytesPerRow,
             destinationBytesPerImage: destinationBytesPerImage)
    }

    // Indirect command buffers and counter sample buffers: none can be made.
    @ObjCMethod("resetCommandsInBuffer:withRange:") func resetCommands(in buffer: NSObject?, withRange range: PerryRange) {}
    @ObjCMethod("copyIndirectCommandBuffer:sourceRange:destination:destinationIndex:")
    func copyIndirectCommandBuffer(_ buffer: NSObject?, sourceRange: PerryRange, destination: NSObject?, destinationIndex: UInt) {}
    @ObjCMethod("optimizeIndirectCommandBuffer:withRange:") func optimizeIndirectCommandBuffer(_ buffer: NSObject?, withRange range: PerryRange) {}
    @ObjCMethod("resolveCounters:inRange:destinationBuffer:destinationOffset:")
    func resolveCounters(_ buffer: NSObject?, inRange range: PerryRange, destinationBuffer: NSObject?, destinationOffset: UInt) {}
    @ObjCMethod("sampleCountersInBuffer:atSampleIndex:withBarrier:")
    func sampleCounters(in buffer: NSObject?, atSampleIndex index: UInt, withBarrier barrier: Bool) {}
}

// MARK: - Argument encoders

@ObjCCategory("PerryOverlay")
extension MTLArgumentEncoder {
    // Pipeline states, depth-stencil states and indirect command buffers
    // in argument buffers are for indirect command buffers, which can't be
    // made; function tables can't be made either.
    @ObjCMethod("setRenderPipelineStates:withRange:")
    func setRenderPipelineStates(_ states: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setDepthStencilStates:withRange:")
    func setDepthStencilStates(_ states: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setIndirectCommandBuffers:withRange:")
    func setIndirectCommandBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, withRange range: PerryRange) {}
    @ObjCMethod("setVisibleFunctionTables:withBufferRange:")
    func setVisibleFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
    @ObjCMethod("setIntersectionFunctionTables:withBufferRange:")
    func setIntersectionFunctionTables(_ tables: UnsafePointer<UnsafeMutableRawPointer?>?, withBufferRange range: PerryRange) {}
}

// MARK: - Resources

@ObjCCategory("PerryOverlay")
extension MTLBuffer {
    /// Debug markers are for Metal's tools, which aren't here.
    @ObjCMethod("addDebugMarker:range:") func addDebugMarker(_ marker: String?, range: PerryRange) {}
    @ObjCMethod("removeAllDebugMarkers") func removeAllDebugMarkers() {}
}

@ObjCCategory("PerryOverlay")
extension MTLTexture {
    /// A view whose channels come from the swizzle: MTLTextureSwizzleChannels'
    /// four bytes, red to alpha (zero 0, one 1, red 2 … alpha 5). metal2vulkan's
    /// views read the channels as they are, so a view asking for another
    /// order reads them unswizzled, with a warning.
    @ObjCMethod("newTextureViewWithPixelFormat:textureType:levels:slices:swizzle:")
    func newTextureView(pixelFormat: UInt, textureType: UInt, levels: PerryRange, slices: PerryRange, swizzle: UInt32) -> MTLTexture? {
        if swizzle != 0x0504_0302 {
            metalWarning("newTextureViewWithPixelFormat:…swizzle: \(String(swizzle, radix: 16)) is read unswizzled")
        }
        return newTextureView(pixelFormat: pixelFormat, textureType: textureType, levels: levels, slices: slices)
    }

    /// MTLTextureSwizzleChannels: the identity, as views here read.
    @ObjCMethod("swizzle") func swizzle() -> UInt32 { 0x0504_0302 }
}

// MARK: - Pipeline states

@ObjCCategory("PerryOverlay")
extension MTLRenderPipelineState {
    // No tile shaders, imageblocks, mesh stages or function pointers.
    @ObjCMethod("imageblockSampleLength") func imageblockSampleLength() -> UInt { 0 }
    @ObjCMethod("imageblockMemoryLengthForDimensions:") func imageblockMemoryLength(dimensions: MTLSize) -> UInt { 0 }
    @ObjCMethod("threadgroupSizeMatchesTileSize") func threadgroupSizeMatchesTileSize() -> Bool { false }
    @ObjCMethod("maxTotalThreadsPerThreadgroup") func maxTotalThreadsPerThreadgroup() -> UInt { 0 }
    @ObjCMethod("maxTotalThreadsPerObjectThreadgroup") func maxTotalThreadsPerObjectThreadgroup() -> UInt { 0 }
    @ObjCMethod("maxTotalThreadsPerMeshThreadgroup") func maxTotalThreadsPerMeshThreadgroup() -> UInt { 0 }
    @ObjCMethod("maxTotalThreadgroupsPerMeshGrid") func maxTotalThreadgroupsPerMeshGrid() -> UInt { 0 }
    @ObjCMethod("objectThreadExecutionWidth") func objectThreadExecutionWidth() -> UInt { 0 }
    @ObjCMethod("meshThreadExecutionWidth") func meshThreadExecutionWidth() -> UInt { 0 }
    @ObjCMethod("requiredThreadsPerTileThreadgroup") func requiredThreadsPerTileThreadgroup() -> MTLSize { MTLSize(width: 0, height: 0, depth: 0) }
    @ObjCMethod("requiredThreadsPerObjectThreadgroup") func requiredThreadsPerObjectThreadgroup() -> MTLSize { MTLSize(width: 0, height: 0, depth: 0) }
    @ObjCMethod("requiredThreadsPerMeshThreadgroup") func requiredThreadsPerMeshThreadgroup() -> MTLSize { MTLSize(width: 0, height: 0, depth: 0) }
    /// MTLShaderValidation: the default, off.
    @ObjCMethod("shaderValidation") func shaderValidation() -> Int { 0 }
    @ObjCMethod("functionHandleWithFunction:stage:") func functionHandle(function: NSObject?, stage: UInt) -> NSObject? { nil }
    @ObjCMethod("functionHandleWithName:stage:") func functionHandle(name: String?, stage: UInt) -> NSObject? { nil }
    @ObjCMethod("functionHandleWithBinaryFunction:stage:") func functionHandle(binaryFunction: NSObject?, stage: UInt) -> NSObject? { nil }
    @ObjCMethod("newVisibleFunctionTableWithDescriptor:stage:")
    func newVisibleFunctionTable(descriptor: NSObject?, stage: UInt) -> NSObject? { nil }
    @ObjCMethod("newIntersectionFunctionTableWithDescriptor:stage:")
    func newIntersectionFunctionTable(descriptor: NSObject?, stage: UInt) -> NSObject? { nil }

    @ObjCMethod("newRenderPipelineStateWithAdditionalBinaryFunctions:error:")
    func newRenderPipelineState(additionalBinaryFunctions: NSObject?, error: Unsupported.UnsupportedError) -> MTLRenderPipelineState? {
        Unsupported.fail(error, "Binary functions")
        return nil
    }

    @ObjCMethod("newRenderPipelineStateWithBinaryFunctions:error:")
    func newRenderPipelineState(binaryFunctions: NSObject?, error: Unsupported.UnsupportedError) -> MTLRenderPipelineState? {
        Unsupported.fail(error, "Binary functions")
        return nil
    }

    @ObjCMethod("newRenderPipelineDescriptorForSpecialization") func newRenderPipelineDescriptorForSpecialization() -> NSObject? { nil }
    @ObjCMethod("reflection") func reflection() -> NSObject? { handle.flatMap { MTLRenderPipelineReflection.of($0) } }
}

@ObjCCategory("PerryOverlay")
extension MTLComputePipelineState {
    @ObjCMethod("requiredThreadsPerThreadgroup") func requiredThreadsPerThreadgroup() -> MTLSize { MTLSize(width: 0, height: 0, depth: 0) }
    @ObjCMethod("shaderValidation") func shaderValidation() -> Int { 0 }
    @ObjCMethod("imageblockMemoryLengthForDimensions:") func imageblockMemoryLength(dimensions: MTLSize) -> UInt { 0 }
    @ObjCMethod("functionHandleWithFunction:") func functionHandle(function: NSObject?) -> NSObject? { nil }
    @ObjCMethod("functionHandleWithName:") func functionHandle(name: String?) -> NSObject? { nil }
    @ObjCMethod("functionHandleWithBinaryFunction:") func functionHandle(binaryFunction: NSObject?) -> NSObject? { nil }
    @ObjCMethod("newVisibleFunctionTableWithDescriptor:") func newVisibleFunctionTable(descriptor: NSObject?) -> NSObject? { nil }
    @ObjCMethod("newIntersectionFunctionTableWithDescriptor:") func newIntersectionFunctionTable(descriptor: NSObject?) -> NSObject? { nil }

    @ObjCMethod("newComputePipelineStateWithAdditionalBinaryFunctions:error:")
    func newComputePipelineState(additionalBinaryFunctions: NSObject?, error: Unsupported.UnsupportedError) -> MTLComputePipelineState? {
        Unsupported.fail(error, "Binary functions")
        return nil
    }

    @ObjCMethod("newComputePipelineStateWithBinaryFunctions:error:")
    func newComputePipelineState(binaryFunctions: NSObject?, error: Unsupported.UnsupportedError) -> MTLComputePipelineState? {
        Unsupported.fail(error, "Binary functions")
        return nil
    }

    @ObjCMethod("reflection") func reflection() -> NSObject? { handle.flatMap { MTLComputePipelineReflection.of($0) } }
}

// MARK: - Libraries and functions

/// What a library makes a function from: its name, the specialized name it
/// is given, constant values and options.
@ObjCClass("MTLFunctionDescriptor")
open class MTLFunctionDescriptor: NSObject {
    var name: String?
    var specializedName: String?
    var constantValues: MTLFunctionConstantValues?
    var options: UInt = 0
    var binaryArchives: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCClassMethod("functionDescriptor") static func functionDescriptor() -> MTLFunctionDescriptor { MTLFunctionDescriptor() }

    @ObjCMethod("name") func getName() -> String? { name }
    @ObjCMethod("setName:") func setName(_ name: String?) { self.name = name }
    @ObjCMethod("specializedName") func getSpecializedName() -> String? { specializedName }
    @ObjCMethod("setSpecializedName:") func setSpecializedName(_ name: String?) { specializedName = name }
    @ObjCMethod("constantValues") func getConstantValues() -> MTLFunctionConstantValues? { constantValues }
    @ObjCMethod("setConstantValues:") func setConstantValues(_ values: MTLFunctionConstantValues?) { constantValues = values }
    @ObjCMethod("options") func getOptions() -> UInt { options }
    @ObjCMethod("setOptions:") func setOptions(_ options: UInt) { self.options = options }
    @ObjCMethod("binaryArchives") func getBinaryArchives() -> NSObject? { binaryArchives }
    @ObjCMethod("setBinaryArchives:") func setBinaryArchives(_ archives: NSObject?) { binaryArchives = archives }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLFunctionDescriptor {
        let copy = MTLFunctionDescriptor()
        (copy.name, copy.specializedName, copy.constantValues) = (name, specializedName, constantValues)
        (copy.options, copy.binaryArchives) = (options, binaryArchives)
        return copy
    }
}

@ObjCCategory("PerryOverlay")
extension MTLLibrary {
    /// The function by its descriptor's name and constant values (its
    /// specialized name labels it on Darwin; the function keeps its own).
    @ObjCMethod("newFunctionWithDescriptor:error:")
    func newFunction(descriptor: MTLFunctionDescriptor?, error: Unsupported.UnsupportedError) -> MTLFunction? {
        guard let descriptor, let name = descriptor.name else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.functionNotFound, "No function name")
            return nil
        }
        if let values = descriptor.constantValues { return newFunction(name: name, constantValues: values, error: error) }
        guard let function = newFunction(name: name) else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.functionNotFound, "Function \(name) was not found")
            return nil
        }
        return function
    }

    @ObjCMethod("newFunctionWithDescriptor:completionHandler:")
    func newFunction(descriptor: MTLFunctionDescriptor?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let function = newFunction(descriptor: descriptor, error: &error)
        complete(completionHandler, function, error)
    }

    @ObjCMethod("newIntersectionFunctionWithDescriptor:error:")
    func newIntersectionFunction(descriptor: NSObject?, error: Unsupported.UnsupportedError) -> MTLFunction? {
        Unsupported.fail(error, "An intersection function")
        return nil
    }

    @ObjCMethod("newIntersectionFunctionWithDescriptor:completionHandler:")
    func newIntersectionFunction(descriptor: NSObject?, completionHandler: ObjCBlock?) {
        Unsupported.fail(completionHandler, "An intersection function")
    }

    /// Function reflection (Metal 4's): none is kept apart from pipelines.
    @ObjCMethod("reflectionForFunctionWithName:") func reflectionForFunction(name: String?) -> NSObject? { nil }
}

@ObjCCategory("PerryOverlay")
extension MTLFunction {
    /// An argument encoder for a buffer binding's argument buffer, by its index.
    @ObjCMethod("newArgumentEncoderWithBufferBinding:")
    func newArgumentEncoder(bufferBinding: NSObject?) -> MTLArgumentEncoder? {
        guard let bufferBinding else { return nil }
        return newArgumentEncoder(bufferIndex: bufferBinding.overlayIndex())
    }
}

// MARK: - Render pass descriptors

@ObjCCategory("PerryOverlay")
extension MTLRenderPassDescriptor {
    @ObjCMethod("setSamplePositions:count:") func setSamplePositions(_ positions: UnsafePointer<Float>?, count: UInt) {
        samplePositions = positions.map { Array(UnsafeBufferPointer(start: $0, count: Int(count) * 2)) } ?? []
    }

    /// The positions set, as many as fit; with no array, how many there are.
    @ObjCMethod("getSamplePositions:count:") func getSamplePositions(_ positions: UnsafeMutablePointer<Float>?, count: UInt) -> UInt {
        let have = samplePositions.count / 2
        guard let positions else { return UInt(have) }
        let copied = min(have, Int(count))
        positions.update(from: samplePositions, count: copied * 2)
        return UInt(copied)
    }
}

extension NSObject {
    @ObjCMethod("index") func overlayIndex() -> UInt
}
