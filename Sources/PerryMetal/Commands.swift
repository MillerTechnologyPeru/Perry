import CPerryGeometry
import CPerryMetal
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
    func computeCommandEncoder(dispatchType: UInt) -> MTLComputeCommandEncoder? { computeCommandEncoder() }

    @ObjCMethod("enqueue") func enqueue() {}

    @ObjCMethod("commit") func commit() {
        // The resources go once the work is done.
        keepResourcesUntilCompleted()
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

    @ObjCMethod("presentDrawable:") func presentDrawable(_ drawable: NSObject?) {
        metalWarning("presentDrawable: is not supported yet")
    }

    @ObjCMethod("pushDebugGroup:") func pushDebugGroup(_ name: String?) {}
    @ObjCMethod("popDebugGroup") func popDebugGroup() {}
    @ObjCMethod("GPUStartTime") func gpuStartTime() -> Double { 0 }
    @ObjCMethod("GPUEndTime") func gpuEndTime() -> Double { 0 }
}

@ObjCClass("_MTLComputeCommandEncoder")
open class MTLComputeCommandEncoder: NSObject, MTLComputeCommandEncoderProtocol {
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
        if let buffer { commandBuffer?.keep(buffer) }
        encode("setBuffer:offset:atIndex:") {
            M2V.api.compute_encoder_set_buffer($0, buffer?.handle, UInt64(offset), UInt32(index), $1)
        }
    }

    @ObjCMethod("setBufferOffset:atIndex:") func setBufferOffset(_ offset: UInt, index: UInt) {
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
        encode("setBytes:length:atIndex:") { M2V.api.compute_encoder_set_bytes($0, bytes, Int(length), UInt32(index), $1) }
    }

    @ObjCMethod("setThreadgroupMemoryLength:atIndex:") func setThreadgroupMemoryLength(_ length: UInt, index: UInt) {
        encode("setThreadgroupMemoryLength:atIndex:") {
            M2V.api.compute_encoder_set_threadgroup_memory_length($0, UInt32(length), UInt32(index), $1)
        }
    }

    @ObjCMethod("dispatchThreads:threadsPerThreadgroup:") func dispatchThreads(_ threads: MTLSize, perThreadgroup: MTLSize) {
        encode("dispatchThreads:threadsPerThreadgroup:") {
            M2V.api.compute_encoder_dispatch_threads($0, threads, perThreadgroup, $1)
        }
    }

    @ObjCMethod("dispatchThreadgroups:threadsPerThreadgroup:")
    func dispatchThreadgroups(_ groups: MTLSize, perThreadgroup: MTLSize) {
        encode("dispatchThreadgroups:threadsPerThreadgroup:") {
            M2V.api.compute_encoder_dispatch_threadgroups($0, groups, perThreadgroup, $1)
        }
    }

    /// Resources are tracked by the runtime as Metal's are.
    @ObjCMethod("useResource:usage:") func useResource(_ resource: NSObject?, usage: UInt) {}
    @ObjCMethod("memoryBarrierWithScope:") func memoryBarrier(scope: UInt) {}
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
