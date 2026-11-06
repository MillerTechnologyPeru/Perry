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
    /// MTLLibraryTypeExecutable: libraries here are made from metallibs.
    @ObjCMethod("type") func type() -> Int { 0 }
    @ObjCMethod("installName") func installName() -> NSObject? { nil }

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

    /// The function specialized with the values: metal2vulkan folds them
    /// into its translation, as Metal's compiler does.
    @ObjCMethod("newFunctionWithName:constantValues:error:")
    func newFunction(name: String?, constantValues: MTLFunctionConstantValues?,
                     error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> MTLFunction? {
        guard let name, let owner else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.functionNotFound, "No function name")
            return nil
        }
        let entries = constantValues?.entries ?? []
        let (function, message) = MTLFunctionConstantValues.withValues(entries) { values, count in
            M2V.call { M2V.api.library_new_function_with_constant_values(handle, name, values, count, $0) }
        }
        guard let function else {
            Errors.store(error, MetalConstants.MTLLibraryErrorDomain, LibraryError.compileFailure,
                         message ?? "Function \(name) could not be specialized")
            return nil
        }
        return MTLFunction(handle: function, device: owner)
    }

    @ObjCMethod("newFunctionWithName:constantValues:completionHandler:")
    func newFunction(name: String?, constantValues: MTLFunctionConstantValues?, completionHandler: ObjCBlock?) {
        var error: UnsafeMutableRawPointer?
        let function = newFunction(name: name, constantValues: constantValues, error: &error)
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        guard let completionHandler else { return }
        completionHandler.function(as: Invoke.self)(completionHandler.object, function?.objcObject, error)
    }
}

// MARK: - Function constants

/// The values a specialized function is made with, by index or by name:
/// each value's MTLDataType and its packed bytes, copied when set.
@ObjCClass("MTLFunctionConstantValues")
open class MTLFunctionConstantValues: NSObject {
    struct Entry {
        var name: String?
        var index: UInt32
        var type: UInt32
        var bytes: [UInt8]
    }

    private(set) var entries: [Entry] = []

    @ObjCMethod("init") public required override init() { super.init() }

    /// The packed size of a scalar or vector MTLDataType's value; 0 for a
    /// type a function constant can't have.
    static func size(of type: UInt) -> Int {
        let vector: (first: UInt, scalar: Int)?
        switch type {
        case 3...6: vector = (3, 4)        // float
        case 16...19: vector = (16, 2)     // half
        case 29...32: vector = (29, 4)     // int
        case 33...36: vector = (33, 4)     // uint
        case 37...40: vector = (37, 2)     // short
        case 41...44: vector = (41, 2)     // ushort
        case 45...48: vector = (45, 1)     // char
        case 49...52: vector = (49, 1)     // uchar
        case 53...56: vector = (53, 1)     // bool
        case 81...84: vector = (81, 8)     // long
        case 85...88: vector = (85, 8)     // ulong
        case 121...124: vector = (121, 2)  // bfloat
        default: vector = nil
        }
        guard let vector else { return 0 }
        return vector.scalar * Int(type - vector.first + 1)
    }

    private func set(_ value: UnsafeRawPointer?, type: UInt, name: String?, index: UInt32) {
        let size = MTLFunctionConstantValues.size(of: type)
        let bytes = value.map { Array(UnsafeRawBufferPointer(start: $0, count: size)) } ?? []
        entries.removeAll { $0.name == name && (name != nil || $0.index == index) }
        entries.append(Entry(name: name, index: index, type: UInt32(type), bytes: bytes))
    }

    @ObjCMethod("setConstantValue:type:atIndex:")
    func setConstantValue(_ value: UnsafeRawPointer?, type: UInt, index: UInt) {
        set(value, type: type, name: nil, index: UInt32(index))
    }

    @ObjCMethod("setConstantValue:type:withName:")
    func setConstantValue(_ value: UnsafeRawPointer?, type: UInt, name: String?) {
        guard let name else { return }
        set(value, type: type, name: name, index: 0)
    }

    /// Values for consecutive indices, each of the type's packed size.
    @ObjCMethod("setConstantValues:type:withRange:")
    func setConstantValues(_ values: UnsafeRawPointer?, type: UInt, range: PerryRange) {
        let size = MTLFunctionConstantValues.size(of: type)
        for i in 0..<Int(range.length) {
            set(values.map { $0 + i * size }, type: type, name: nil, index: UInt32(range.location) + UInt32(i))
        }
    }

    @ObjCMethod("reset") func reset() { entries.removeAll() }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLFunctionConstantValues {
        let copy = MTLFunctionConstantValues()
        copy.entries = entries
        return copy
    }

    /// The entries as metal2vulkan's ABI takes them, good during `body`.
    static func withValues<Result>(_ entries: [Entry],
                                   _ body: (UnsafePointer<perry_m2v_function_constant_value>?, Int) -> Result) -> Result {
        var values: [perry_m2v_function_constant_value] = []
        var names: [UnsafeMutablePointer<CChar>?] = []
        var buffers: [UnsafeMutablePointer<UInt8>] = []
        defer {
            names.forEach { $0?.deallocate() }
            buffers.forEach { $0.deallocate() }
        }
        for entry in entries {
            let name = entry.name.map { text -> UnsafeMutablePointer<CChar> in
                let utf8 = Array(text.utf8CString)
                let copy = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count)
                copy.initialize(from: utf8, count: utf8.count)
                return copy
            }
            names.append(name)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(entry.bytes.count, 1))
            buffer.initialize(from: entry.bytes, count: entry.bytes.count)
            buffers.append(buffer)
            values.append(perry_m2v_function_constant_value(name: UnsafePointer(name), index: entry.index, data_type: entry.type,
                                                            bytes: UnsafePointer(buffer), length: entry.bytes.count))
        }
        return values.withUnsafeBufferPointer { body($0.baseAddress, $0.count) }
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
    /// The GPU memory the state holds: none Metal's apps can count here.
    @ObjCMethod("allocatedSize") func allocatedSize() -> UInt { 0 }
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
