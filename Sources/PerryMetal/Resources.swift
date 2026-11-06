import CPerryGeometry
import CPerryMetal
import PerryObjCInterop

// MTLBuffer, and the libraries, functions and compute pipeline states made
// from metallibs. Each holds metal2vulkan's handle and its device.

@ObjCProtocol("MTLResource")
protocol MTLResourceProtocol {}

@ObjCProtocol("MTLBuffer")
protocol MTLBufferProtocol: MTLResourceProtocol {}

@ObjCProtocol("MTLLibrary")
protocol MTLLibraryProtocol {}

@ObjCProtocol("MTLFunction")
protocol MTLFunctionProtocol {}

@ObjCProtocol("MTLComputePipelineState")
protocol MTLComputePipelineStateProtocol {}

@ObjCClass("_MTLBuffer")
open class MTLBuffer: NSObject, MTLBufferProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var options: UInt = 0
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice, options: UInt) {
        self.handle = handle
        owner = device
        self.options = options
        super.init()
    }

    deinit {
        if let handle { M2V.api.buffer_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("length") func length() -> UInt { UInt(M2V.api.buffer_length(handle)) }
    @ObjCMethod("contents") func contents() -> UnsafeMutableRawPointer? { M2V.api.buffer_contents(handle) }
    @ObjCMethod("resourceOptions") func resourceOptions() -> UInt { options }
    /// MTLCPUCacheMode, MTLStorageMode and MTLHazardTrackingMode, as the
    /// options pack them.
    @ObjCMethod("cpuCacheMode") func cpuCacheMode() -> UInt { options & 0xf }
    @ObjCMethod("storageMode") func storageMode() -> UInt { (options >> 4) & 0xf }
    @ObjCMethod("hazardTrackingMode") func hazardTrackingMode() -> UInt { (options >> 8) & 0x3 }
    @ObjCMethod("allocatedSize") func allocatedSize() -> UInt { length() }
    @ObjCMethod("gpuAddress") func gpuAddress() -> UInt64 { 0 }

    @ObjCMethod("didModifyRange:") func didModifyRange(_ range: PerryRange) {
        let (_, message) = M2V.call {
            M2V.api.buffer_did_modify_range(handle, UInt64(range.location), UInt64(range.length), $0)
        }
        if let message { metalWarning("didModifyRange: \(message)") }
    }

    /// No purgeable states: always MTLPurgeableStateNonVolatile.
    @ObjCMethod("setPurgeableState:") func setPurgeableState(_ state: UInt) -> UInt { 2 }
    @ObjCMethod("makeAliasable") func makeAliasable() {}
    @ObjCMethod("isAliasable") func isAliasable() -> Bool { false }
    /// A buffer made by the device, not from a heap.
    @ObjCMethod("heap") func heap() -> NSObject? { nil }
    @ObjCMethod("heapOffset") func heapOffset() -> UInt { 0 }
}

@ObjCClass("_MTLLibrary")
open class MTLLibrary: NSObject, MTLLibraryProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice) {
        self.handle = handle
        owner = device
        super.init()
    }

    deinit {
        if let handle { M2V.api.library_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }

    @ObjCMethod("functionNames") func functionNames() -> NSObject {
        var names: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        let count = M2V.api.library_function_names(handle, &names)
        defer { M2V.api.strings_free(names, count) }
        let strings = (0..<count).compactMap { names?[$0] }.map { NSObject.string(String(cString: $0)) }
        return NSObject.array(strings)
    }

    @ObjCMethod("newFunctionWithName:") func newFunction(name: String?) -> MTLFunction? {
        guard let name else { return nil }
        let (function, _) = M2V.call { M2V.api.library_new_function_with_name(handle, name, $0) }
        guard let function, let owner else { return nil }
        return MTLFunction(handle: function, device: owner)
    }
}

@ObjCClass("_MTLFunction")
open class MTLFunction: NSObject, MTLFunctionProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?
    var label: String?

    init(handle: perry_m2v_handle, device: MTLDevice) {
        self.handle = handle
        owner = device
        super.init()
    }

    deinit {
        if let handle { M2V.api.function_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("name") func name() -> String { M2V.api.function_name(handle).map { String(cString: $0) } ?? "" }
    /// MTLFunctionType.
    @ObjCMethod("functionType") func functionType() -> UInt { UInt(M2V.api.function_type(handle)) }
    @ObjCMethod("options") func options() -> UInt { 0 }
    /// MTLPatchTypeNone, and no control points.
    @ObjCMethod("patchType") func patchType() -> UInt { 0 }
    @ObjCMethod("patchControlPointCount") func patchControlPointCount() -> Int { -1 }

    /// A vertex function's inputs, or nil.
    @ObjCMethod("vertexAttributes") func vertexAttributes() -> NSObject? {
        var list: UnsafeMutablePointer<perry_m2v_attribute>?
        let count = M2V.api.function_vertex_attributes(handle, &list)
        guard count >= 0 else { return nil }
        defer { M2V.api.attributes_free(list, Int(count)) }
        let attributes = (0..<Int(count)).compactMap { list?[$0] }.map { MTLVertexAttribute(attribute: $0) }
        return NSObject.array(attributes)
    }

    @ObjCMethod("stageInputAttributes") func stageInputAttributes() -> NSObject? { vertexAttributes() }
}

final class AttributeState {
    var name = ""
    var index = 0
    var type: UInt = 0
    var active = false
    var patchData = false
    var patchControlPointData = false
}

@ObjCClass("MTLVertexAttribute")
open class MTLVertexAttribute: NSObject {
    var attribute = AttributeState()

    init(attribute a: perry_m2v_attribute) {
        super.init()
        attribute.name = a.name.map { String(cString: $0) } ?? ""
        attribute.index = Int(a.attribute_index)
        attribute.type = UInt(a.attribute_type)
        attribute.active = a.active
        attribute.patchData = a.patch_data
        attribute.patchControlPointData = a.patch_control_point_data
    }

    @ObjCMethod("name") func name() -> String { attribute.name }
    @ObjCMethod("attributeIndex") func attributeIndex() -> UInt { UInt(attribute.index) }
    /// MTLDataType.
    @ObjCMethod("attributeType") func attributeType() -> UInt { attribute.type }
    @ObjCMethod("isActive") func isActive() -> Bool { attribute.active }
    @ObjCMethod("active") func active() -> Bool { attribute.active }
    @ObjCMethod("isPatchData") func isPatchData() -> Bool { attribute.patchData }
    @ObjCMethod("isPatchControlPointData") func isPatchControlPointData() -> Bool { attribute.patchControlPointData }
}

@ObjCClass("_MTLComputePipelineState")
open class MTLComputePipelineState: NSObject, MTLComputePipelineStateProtocol {
    var handle: perry_m2v_handle?
    var owner: MTLDevice?

    init(handle: perry_m2v_handle, device: MTLDevice) {
        self.handle = handle
        owner = device
        super.init()
    }

    deinit {
        if let handle { M2V.api.compute_pipeline_release(handle) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func label() -> String? { nil }
    @ObjCMethod("maxTotalThreadsPerThreadgroup") func maxTotalThreadsPerThreadgroup() -> UInt {
        UInt(M2V.api.compute_pipeline_max_total_threads_per_threadgroup(handle))
    }
    @ObjCMethod("threadExecutionWidth") func threadExecutionWidth() -> UInt {
        UInt(M2V.api.compute_pipeline_thread_execution_width(handle))
    }
    @ObjCMethod("staticThreadgroupMemoryLength") func staticThreadgroupMemoryLength() -> UInt {
        UInt(M2V.api.compute_pipeline_static_threadgroup_memory_length(handle))
    }
    @ObjCMethod("supportIndirectCommandBuffers") func supportIndirectCommandBuffers() -> Bool { false }
}
