import CPerryGeometry
import CPerryMetal
import Glibc
import PerryObjCInterop

// Command queues, command buffers and compute command encoders. A command
// buffer keeps the encoders' resources alive until it completes, as Metal's
// does with retained references.

@ObjCProtocol("MTLCommandQueue")
protocol MTLCommandQueueProtocol {}

@ObjCProtocol("MTLCommandBuffer")
protocol MTLCommandBufferProtocol {}

@ObjCProtocol("MTLCommandEncoder")
protocol MTLCommandEncoderProtocol {}

@ObjCProtocol("MTLComputeCommandEncoder")
protocol MTLComputeCommandEncoderProtocol: MTLCommandEncoderProtocol {}

@ObjCClass("_MTLCommandQueue")
open class MTLCommandQueue: NSObject, MTLCommandQueueProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice) {
        self.handle = handle
        owner = device
        super.init()
    }

    deinit {
        if let handle { M2V.api.command_queue_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }

    @ObjCMethod("commandBuffer") func commandBuffer() -> MTLCommandBuffer? {
        let (buffer, message) = M2V.call { M2V.api.command_queue_command_buffer(handle, $0) }
        guard let buffer else {
            metalWarning("commandBuffer: \(message ?? "failed")")
            return nil
        }
        return MTLCommandBuffer(handle: buffer, queue: self)
    }

    @ObjCMethod("commandBufferWithUnretainedReferences")
    func commandBufferWithUnretainedReferences() -> MTLCommandBuffer? { commandBuffer() }

    @ObjCMethod("commandBufferWithDescriptor:")
    func commandBuffer(descriptor: NSObject?) -> MTLCommandBuffer? { commandBuffer() }

    @ObjCMethod("insertDebugCaptureBoundary") func insertDebugCaptureBoundary() {}
}

/// A block a command buffer calls once, with the command buffer.
final class CommandBufferHandler {
    let block: ObjCBlock
    let buffer: MTLCommandBuffer

    init(block: ObjCBlock, buffer: MTLCommandBuffer) {
        self.block = block
        self.buffer = buffer
    }

    static let invoke: perry_m2v_handler = { context in
        guard let context else { return }
        let handler = Unmanaged<CommandBufferHandler>.fromOpaque(context).takeRetainedValue()
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void
        ObjCRuntime.autoreleasepool {
            handler.block.function(as: Invoke.self)(handler.block.object, handler.buffer.objcObject)
        }
    }
}

@ObjCClass("_MTLCommandBuffer")
open class MTLCommandBuffer: NSObject, MTLCommandBufferProtocol {
    var handle: perry_m2v_handle?
    var queue: MTLCommandQueue?
    var label: String?
    /// The encoders' pipelines and buffers, kept until it completes.
    var resources: [NSObject] = []
    var committed = false
    private let lock = Lock()

    init(handle: perry_m2v_handle, queue: MTLCommandQueue) {
        self.handle = handle
        self.queue = queue
        super.init()
    }

    deinit {
        if let handle { M2V.api.command_buffer_release(handle) }
    }

    func keep(_ object: NSObject) {
        guard !committed else { return }
        lock.withLock { resources.append(object) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { queue?.owner }
    @ObjCMethod("commandQueue") func commandQueue() -> MTLCommandQueue? { queue }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("retainedReferences") func retainedReferences() -> Bool { true }

    @ObjCMethod("computeCommandEncoder") func computeCommandEncoder() -> MTLComputeCommandEncoder? {
        let (encoder, message) = M2V.call { M2V.api.command_buffer_compute_command_encoder(handle, $0) }
        guard let encoder else {
            metalWarning("computeCommandEncoder: \(message ?? "failed")")
            return nil
        }
        return MTLComputeCommandEncoder(handle: encoder, commandBuffer: self)
    }

    @ObjCMethod("computeCommandEncoderWithDispatchType:")
    func computeCommandEncoder(dispatchType: UInt) -> MTLComputeCommandEncoder? {
        Trace.log("computeCommandEncoder", "dispatch type \(dispatchType)")
        return computeCommandEncoder()
    }

    @ObjCMethod("renderCommandEncoderWithDescriptor:")
    func renderCommandEncoder(descriptor: MTLRenderPassDescriptor?) -> MTLRenderCommandEncoder? {
        guard let descriptor else { return nil }
        var (pass, textures) = descriptor.value()
        if Trace.enabled {
            let color = descriptor.colors.slots.elements[0]
            let target = color?.texture.map { "\($0.descriptor.width)×\($0.descriptor.height) format \($0.descriptor.pixel_format)" } ?? "none"
            Trace.log("renderCommandEncoder", "colour \(target) level \(color?.value.level ?? 0) mips \(color?.texture?.descriptor.mipmap_level_count ?? 0), load \(color?.value.load_action ?? 0), clear \(color?.value.clear ?? (0, 0, 0, 0))")
        }
        if Trace.debugClear {
            // Drawables (BGRA8) clear to magenta, other targets to green.
            let drawable = descriptor.colors.slots.elements[0]?.texture?.descriptor.pixel_format == 80
            pass.color_attachments.0.clear = drawable ? (1, 0, 1, 1) : (0, 1, 0, 1)
        }
        if let texture = descriptor.colors.slots.elements[0]?.texture { dumpPass(texture) }
        for texture in textures { keep(texture) }
        let (encoder, message) = M2V.call { M2V.api.command_buffer_render_command_encoder(handle, &pass, $0) }
        guard let encoder else {
            metalWarning("renderCommandEncoderWithDescriptor: \(message ?? "failed")")
            return nil
        }
        return MTLRenderCommandEncoder(handle: encoder, commandBuffer: self)
    }

    @ObjCMethod("blitCommandEncoder") func blitCommandEncoder() -> MTLBlitCommandEncoder? {
        let (encoder, message) = M2V.call { M2V.api.command_buffer_blit_command_encoder(handle, $0) }
        guard let encoder else {
            metalWarning("blitCommandEncoder: \(message ?? "failed")")
            return nil
        }
        return MTLBlitCommandEncoder(handle: encoder, commandBuffer: self)
    }

    @ObjCMethod("enqueue") func enqueue() {}

    @ObjCMethod("commit") func commit() {
        Trace.log("commit")
        // The resources go once the work is done.
        keepResourcesUntilCompleted()
        committed = true
        let (_, message) = M2V.call { M2V.api.command_buffer_commit(handle, $0) }
        if let message { metalWarning("commit: \(message)") }
    }

    @ObjCMethod("waitUntilScheduled") func waitUntilScheduled() {
        let (_, message) = M2V.call { M2V.api.command_buffer_wait_until_scheduled(handle, $0) }
        if let message { metalWarning("waitUntilScheduled: \(message)") }
    }

    @ObjCMethod("waitUntilCompleted") func waitUntilCompleted() {
        let (_, message) = M2V.call { M2V.api.command_buffer_wait_until_completed(handle, $0) }
        if let message { metalWarning("waitUntilCompleted: \(message)") }
    }

    /// MTLCommandBufferStatus.
    @ObjCMethod("status") func status() -> UInt { UInt(M2V.api.command_buffer_status(handle)) }

    @ObjCMethod("error") func error() -> NSObject? {
        guard let message = M2V.api.command_buffer_error(handle) else { return nil }
        defer { M2V.api.string_free(message) }
        // MTLCommandBufferErrorInternal.
        return Errors.make(MetalConstants.MTLCommandBufferErrorDomain, 1, String(cString: message))
    }

    @ObjCMethod("addScheduledHandler:") func addScheduledHandler(_ block: ObjCBlock?) {
        guard let block else { return }
        addHandler(block, scheduled: true)
    }

    @ObjCMethod("addCompletedHandler:") func addCompletedHandler(_ block: ObjCBlock?) {
        guard let block else { return }
        addHandler(block, scheduled: false)
    }

    private func addHandler(_ block: ObjCBlock, scheduled: Bool) {
        let context = Unmanaged.passRetained(CommandBufferHandler(block: block, buffer: self)).toOpaque()
        let add = scheduled ? M2V.api.command_buffer_add_scheduled_handler : M2V.api.command_buffer_add_completed_handler
        let (added, message) = M2V.call { add(handle, CommandBufferHandler.invoke, context, $0) }
        if !added {
            Unmanaged<CommandBufferHandler>.fromOpaque(context).release()
            metalWarning("\(scheduled ? "addScheduledHandler" : "addCompletedHandler"): \(message ?? "failed")")
        }
    }

    /// PERRY_METAL_DUMP_PASSES=<directory>: the colour targets of render
    /// passes PERRY_METAL_DUMP_PASS (1000 by default) to 20 after it, as
    /// PPMs, once their command buffer completes.
    nonisolated(unsafe) static var passes = 0
    nonisolated(unsafe) static let dumpDirectory = getenv("PERRY_METAL_DUMP_PASSES").map { String(cString: $0) }
    nonisolated(unsafe) static let dumpFrom = getenv("PERRY_METAL_DUMP_PASS").flatMap { Int(String(cString: $0)) } ?? 1000

    private func dumpPass(_ texture: MTLTexture) {
        guard let directory = Self.dumpDirectory else { return }
        Self.passes += 1
        let pass = Self.passes
        guard pass >= Self.dumpFrom, pass < Self.dumpFrom + 20 else { return }
        onCompletion {
            let width = Int(texture.descriptor.width), height = Int(texture.descriptor.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let read = pixels.withUnsafeMutableBytes { texture.readRGBA($0.baseAddress, width: UInt(width), height: UInt(height)) }
            guard read, let file = fopen("\(directory)/pass-\(pass)-\(width)x\(height)-f\(texture.descriptor.pixel_format).ppm", "wb") else {
                metalWarning("pass \(pass): not read")
                return
            }
            defer { fclose(file) }
            let header = "P6\n\(width) \(height)\n255\n"
            _ = header.withCString { fwrite($0, 1, strlen($0), file) }
            var row = [UInt8](repeating: 0, count: width * 3)
            for y in (0..<height).reversed() {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    (row[x * 3], row[x * 3 + 1], row[x * 3 + 2]) = (pixels[i], pixels[i + 1], pixels[i + 2])
                }
                _ = row.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) }
            }
        }
    }

    /// A texture's pixels once the work completes, as a PPM of its colour
    /// beside one of its alpha, rows as stored.
    func dumpOnCompletion(_ texture: MTLTexture, to path: String) {
        onCompletion {
            let width = Int(texture.descriptor.width), height = Int(texture.descriptor.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: UInt(width), height: UInt(height), depth: 1))
            let (read, message) = M2V.call { out in
                pixels.withUnsafeMutableBytes {
                    M2V.api.texture_get_bytes(texture.handle, $0.baseAddress, $0.count, UInt64(width * 4), 0, region, 0, 0, out)
                }
            }
            guard read, let file = fopen(path, "wb") else {
                metalWarning("dump \(path): \(message ?? "not read")")
                return
            }
            defer { fclose(file) }
            let header = "P6\n\(width * 2) \(height)\n255\n"
            _ = header.withCString { fwrite($0, 1, strlen($0), file) }
            var row = [UInt8](repeating: 0, count: width * 6)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    (row[x * 3], row[x * 3 + 1], row[x * 3 + 2]) = (pixels[i], pixels[i + 1], pixels[i + 2])
                    let a = (width + x) * 3
                    (row[a], row[a + 1], row[a + 2]) = (pixels[i + 3], pixels[i + 3], pixels[i + 3])
                }
                _ = row.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) }
            }
        }
    }

    private func keepResourcesUntilCompleted() {
        let buffer = self
        onCompletion { buffer.releaseResources() }
    }

    private func releaseResources() {
        lock.withLock { resources.removeAll() }
    }

    /// A Swift closure run when the command buffer completes.
    private func onCompletion(_ body: @escaping () -> Void) {
        let context = Unmanaged.passRetained(Completion(body)).toOpaque()
        let (added, _) = M2V.call { M2V.api.command_buffer_add_completed_handler(handle, Completion.invoke, context, $0) }
        if !added { Unmanaged<Completion>.fromOpaque(context).release() }
    }

    final class Completion {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }

        static let invoke: perry_m2v_handler = { context in
            guard let context else { return }
            Unmanaged<Completion>.fromOpaque(context).takeRetainedValue().body()
        }
    }

    /// The drawable is shown once the work that drew it completes: -present,
    /// which CAMetalLayer's drawables read their texture back for.
    @ObjCMethod("presentDrawable:") func presentDrawable(_ drawable: NSObject?) {
        Trace.log("presentDrawable", drawable == nil ? "nil" : "")
        guard let drawable else { return }
        onCompletion {
            typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
            unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)(drawable.objcObject, ObjCRuntime.selector("present"))
        }
    }

    @ObjCMethod("presentDrawable:atTime:") func presentDrawable(_ drawable: NSObject?, atTime time: Double) {
        presentDrawable(drawable)
    }

    @ObjCMethod("presentDrawable:afterMinimumDuration:") func presentDrawable(_ drawable: NSObject?, afterMinimumDuration: Double) {
        presentDrawable(drawable)
    }

    @ObjCMethod("pushDebugGroup:") func pushDebugGroup(_ name: String?) {}
    @ObjCMethod("popDebugGroup") func popDebugGroup() {}
    @ObjCMethod("GPUStartTime") func gpuStartTime() -> Double { 0 }
    @ObjCMethod("GPUEndTime") func gpuEndTime() -> Double { 0 }
}

@ObjCClass("_MTLComputeCommandEncoder")
open class MTLComputeCommandEncoder: NSObject, MTLComputeCommandEncoderProtocol {
    var bound: [UInt: MTLTexture?] = [:]
    var handle: perry_m2v_handle?
    var commandBuffer: MTLCommandBuffer?
    var label: String?

    init(handle: perry_m2v_handle, commandBuffer: MTLCommandBuffer) {
        self.handle = handle
        self.commandBuffer = commandBuffer
        super.init()
    }

    deinit {
        if let handle { M2V.api.compute_encoder_release(handle) }
    }

    /// Runs an encoder call, warning with its selector when it fails.
    private func encode(_ selector: String, _ body: (perry_m2v_handle, perry_m2v_error) -> Bool) {
        guard let handle else {
            metalWarning("-[MTLComputeCommandEncoder \(selector)] after endEncoding")
            return
        }
        let (_, message) = M2V.call { body(handle, $0) }
        if let message { metalWarning("-[MTLComputeCommandEncoder \(selector)]: \(message)") }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { commandBuffer?.device() }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    /// MTLDispatchTypeSerial.
    @ObjCMethod("dispatchType") func dispatchType() -> UInt { 0 }

    @ObjCMethod("setComputePipelineState:") func setComputePipelineState(_ state: MTLComputePipelineState?) {
        guard let state, let stateHandle = state.handle else { return }
        commandBuffer?.keep(state)
        encode("setComputePipelineState:") { M2V.api.compute_encoder_set_compute_pipeline_state($0, stateHandle, $1) }
    }

    @ObjCMethod("setBuffer:offset:atIndex:") func setBuffer(_ buffer: MTLBuffer?, offset: UInt, index: UInt) {
        Trace.log("computeSetBuffer", "\(buffer.map { "\($0.objcObject) len \(M2V.api.buffer_length($0.handle))" } ?? "nil") +\(offset) at \(index): \((0..<8).map { i in "\(buffer.flatMap { M2V.api.buffer_contents($0.handle) }?.loadUnaligned(fromByteOffset: Int(offset) + i * 4, as: Int32.self) ?? 0)" }.joined(separator: " "))")
        if let buffer { commandBuffer?.keep(buffer) }
        encode("setBuffer:offset:atIndex:") {
            M2V.api.compute_encoder_set_buffer($0, buffer?.handle, UInt64(offset), UInt32(index), $1)
        }
    }

    @ObjCMethod("setBufferOffset:atIndex:") func setBufferOffset(_ offset: UInt, index: UInt) {
        Trace.log("computeSetBufferOffset", "+\(offset) at \(index)")
        encode("setBufferOffset:atIndex:") { M2V.api.compute_encoder_set_buffer_offset($0, UInt64(offset), UInt32(index), $1) }
    }

    @ObjCMethod("setBuffers:offsets:withRange:")
    func setBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            let buffer = buffers?[i].map { MTLBuffer.objCInstance($0, ownership: .retain) }
            setBuffer(buffer, offset: offsets?[i] ?? 0, index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setBytes:length:atIndex:") func setBytes(_ bytes: UnsafeRawPointer?, length: UInt, index: UInt) {
        Trace.log("computeSetBytes", "\(length) at \(index): \((0..<min(Int(length) / 4, 8)).map { "\(bytes?.loadUnaligned(fromByteOffset: $0 * 4, as: Int32.self) ?? 0)" }.joined(separator: " "))")
        encode("setBytes:length:atIndex:") { M2V.api.compute_encoder_set_bytes($0, bytes, Int(length), UInt32(index), $1) }
    }

    @ObjCMethod("setTexture:atIndex:") func setTexture(_ texture: MTLTexture?, index: UInt) {
        bound[index] = texture
        Trace.log("computeSetTexture", "\(texture.map { "\($0.objcObject) \($0.descriptor.width)×\($0.descriptor.height) mips \($0.descriptor.mipmap_level_count) parent \($0.parent.map { "\($0.objcObject)" } ?? "none")" } ?? "nil") at \(index)")
        if let texture { commandBuffer?.keep(texture) }
        encode("setTexture:atIndex:") { M2V.api.compute_encoder_set_texture($0, texture?.handle, UInt32(index), $1) }
    }

    @ObjCMethod("setTextures:withRange:") func setTextures(_ textures: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setTexture(textures?[i].map { MTLTexture.objCInstance($0, ownership: .retain) }, index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setSamplerState:atIndex:") func setSamplerState(_ sampler: MTLSamplerState?, index: UInt) {
        if let sampler { commandBuffer?.keep(sampler) }
        encode("setSamplerState:atIndex:") {
            M2V.api.compute_encoder_set_sampler_state($0, sampler?.handle, UInt32(index), $1)
        }
    }

    @ObjCMethod("setSamplerStates:withRange:")
    func setSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setSamplerState(samplers?[i].map { MTLSamplerState.objCInstance($0, ownership: .retain) },
                            index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setThreadgroupMemoryLength:atIndex:") func setThreadgroupMemoryLength(_ length: UInt, index: UInt) {
        encode("setThreadgroupMemoryLength:atIndex:") {
            M2V.api.compute_encoder_set_threadgroup_memory_length($0, UInt32(length), UInt32(index), $1)
        }
    }

    @ObjCMethod("dispatchThreads:threadsPerThreadgroup:") func dispatchThreads(_ threads: MTLSize, perThreadgroup: MTLSize) {
        Trace.log("dispatch", "threads \(threads.width)×\(threads.height) by \(perThreadgroup.width)×\(perThreadgroup.height)")
        debugBarrier()
        encode("dispatchThreads:threadsPerThreadgroup:") {
            M2V.api.compute_encoder_dispatch_threads($0, threads, perThreadgroup, $1)
        }
    }

    @ObjCMethod("dispatchThreadgroups:threadsPerThreadgroup:")
    func dispatchThreadgroups(_ groups: MTLSize, perThreadgroup: MTLSize) {
        Trace.log("dispatch", "groups \(groups.width)×\(groups.height) by \(perThreadgroup.width)×\(perThreadgroup.height)")
        debugBarrier()
        encode("dispatchThreadgroups:threadsPerThreadgroup:") {
            M2V.api.compute_encoder_dispatch_threadgroups($0, groups, perThreadgroup, $1)
        }
    }

    @ObjCMethod("dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:")
    func dispatchThreadgroups(indirectBuffer: MTLBuffer?, indirectBufferOffset: UInt, perThreadgroup: MTLSize) {
        guard let indirectBuffer else { return }
        commandBuffer?.keep(indirectBuffer)
        debugBarrier()
        encode("dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:") {
            M2V.api.compute_encoder_dispatch_threadgroups_indirect($0, indirectBuffer.handle, UInt64(indirectBufferOffset),
                                                                   perThreadgroup, $1)
        }
    }

    /// Resources are tracked by the runtime as Metal's are.
    @ObjCMethod("useResource:usage:") func useResource(_ resource: NSObject?, usage: UInt) {}
    @ObjCMethod("memoryBarrierWithScope:") func memoryBarrier(scope: UInt) {
        encode("memoryBarrierWithScope:") { M2V.api.compute_encoder_memory_barrier($0, UInt64(scope), $1) }
    }

    /// PERRY_METAL_DEBUG_BARRIERS: a barrier on buffers and textures before
    /// every dispatch.
    /// PERRY_METAL_DUMP_DISPATCH=<n>: the textures bound for dispatch n,
    /// into PERRY_METAL_DUMP_PASSES (or /tmp).
    nonisolated(unsafe) static var dispatches = 0
    nonisolated(unsafe) static let dumpDispatches = Set((getenv("PERRY_METAL_DUMP_DISPATCH").map { String(cString: $0) } ?? "").split(separator: ",").compactMap { Int($0) })

    private func dumpDispatch() {
        Self.dispatches += 1
        guard Self.dumpDispatches.contains(Self.dispatches), let commandBuffer else { return }
        let directory = MTLCommandBuffer.dumpDirectory ?? "/tmp"
        for (index, texture) in bound {
            guard let texture else { continue }
            commandBuffer.dumpOnCompletion(texture, to: "\(directory)/dispatch-\(Self.dispatches)-t\(index)-\(texture.descriptor.width)x\(texture.descriptor.height).ppm")
        }
    }

    private func debugBarrier() {
        dumpDispatch()
        guard Trace.debugBarriers else { return }
        encode("memoryBarrierWithScope:") { M2V.api.compute_encoder_memory_barrier($0, 3, $1) }
    }
    @ObjCMethod("pushDebugGroup:") func pushDebugGroup(_ name: String?) {}
    @ObjCMethod("popDebugGroup") func popDebugGroup() {}
    @ObjCMethod("insertDebugSignpost:") func insertDebugSignpost(_ name: String?) {}

    @ObjCMethod("endEncoding") func endEncoding() {
        guard let ended = handle else { return }
        handle = nil
        let (_, message) = M2V.call { M2V.api.compute_encoder_end(ended, $0) }
        if let message { metalWarning("-[MTLComputeCommandEncoder endEncoding]: \(message)") }
    }
}
