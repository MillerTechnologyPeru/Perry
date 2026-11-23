import CPerryGeometry
import CPerryMetal
import PerryObjCInterop

// Metal 4's descriptors that Metal's Swift overlay names, and tensor
// extents. They keep what they are given; the device makes no Metal 4
// compiler or queue (Overlay.swift), so nothing builds from them here.

/// A tensor's size in each of up to MTL_TENSOR_MAX_RANK (16) dimensions.
@ObjCClass("MTLTensorExtents")
open class MTLTensorExtents: NSObject {
    static let maxRank = 16
    var values: [Int] = []

    /// A scalar: rank zero.
    @ObjCMethod("init") public required override init() { super.init() }

    /// nil for a rank above 16, or for values missing at a rank above zero.
    @ObjCMethod("initWithRank:values:") public required init?(rank: UInt, values: UnsafePointer<Int>?) {
        guard Int(rank) <= MTLTensorExtents.maxRank, rank == 0 || values != nil else { return nil }
        self.values = values.map { Array(UnsafeBufferPointer(start: $0, count: Int(rank))) } ?? []
        super.init()
    }

    @ObjCMethod("rank") func rank() -> UInt { UInt(values.count) }

    /// The extent of a dimension; -1 past the rank, as Metal answers.
    @ObjCMethod("extentAtDimensionIndex:") func extent(atDimensionIndex index: UInt) -> Int {
        Int(index) < values.count ? values[Int(index)] : -1
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTLTensorExtents {
        let copy = MTLTensorExtents()
        copy.values = values
        return copy
    }

    @ObjCMethod("isEqual:") func isEqual(_ other: NSObject?) -> Bool {
        guard let other, other.is(MTLTensorExtents.self) else { return false }
        return other.unsafeCast(to: MTLTensorExtents.self).values == values
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: values.hashValue) }
}

/// Options every Metal 4 pipeline takes: shader validation and reflection.
@ObjCClass("MTL4PipelineOptions")
open class MTL4PipelineOptions: NSObject {
    var shaderValidation = 0
    var shaderReflection: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("shaderValidation") func getShaderValidation() -> Int { shaderValidation }
    @ObjCMethod("setShaderValidation:") func setShaderValidation(_ value: Int) { shaderValidation = value }
    @ObjCMethod("shaderReflection") func getShaderReflection() -> UInt { shaderReflection }
    @ObjCMethod("setShaderReflection:") func setShaderReflection(_ value: UInt) { shaderReflection = value }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTL4PipelineOptions {
        let copy = MTL4PipelineOptions()
        (copy.shaderValidation, copy.shaderReflection) = (shaderValidation, shaderReflection)
        return copy
    }
}

/// The base of Metal 4's pipeline descriptors: a label and options.
@ObjCClass("MTL4PipelineDescriptor")
open class MTL4PipelineDescriptor: NSObject {
    var label: String?
    var options: MTL4PipelineOptions?

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("options") func getOptions() -> MTL4PipelineOptions? { options }
    @ObjCMethod("setOptions:") func setOptions(_ options: MTL4PipelineOptions?) { self.options = options }

    func copyBase(to copy: MTL4PipelineDescriptor) {
        (copy.label, copy.options) = (label, options)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTL4PipelineDescriptor {
        let copy = MTL4PipelineDescriptor()
        copyBase(to: copy)
        return copy
    }
}

@ObjCClass("MTL4ComputePipelineDescriptor")
open class MTL4ComputePipelineDescriptor: MTL4PipelineDescriptor {
    var computeFunctionDescriptor: NSObject?
    var multipleOfExecutionWidth = false
    var maxThreads: UInt = 0
    var requiredThreads = MTLSize(width: 0, height: 0, depth: 0)
    var supportBinaryLinking = false
    var staticLinkingDescriptor: NSObject?
    var supportIndirectCommandBuffers = 0
    var forwardProgressUsage = 0
    var contentionRelief = 0
    var optimizeForPersistentKernel = false

    @ObjCMethod("init") public required init() { super.init() }

    @ObjCMethod("computeFunctionDescriptor") func getComputeFunctionDescriptor() -> NSObject? { computeFunctionDescriptor }
    @ObjCMethod("setComputeFunctionDescriptor:") func setComputeFunctionDescriptor(_ value: NSObject?) { computeFunctionDescriptor = value }
    @ObjCMethod("threadGroupSizeIsMultipleOfThreadExecutionWidth")
    func threadGroupSizeIsMultipleOfThreadExecutionWidth() -> Bool { multipleOfExecutionWidth }
    @ObjCMethod("setThreadGroupSizeIsMultipleOfThreadExecutionWidth:")
    func setThreadGroupSizeIsMultipleOfThreadExecutionWidth(_ value: Bool) { multipleOfExecutionWidth = value }
    @ObjCMethod("maxTotalThreadsPerThreadgroup") func maxTotalThreadsPerThreadgroup() -> UInt { maxThreads }
    @ObjCMethod("setMaxTotalThreadsPerThreadgroup:") func setMaxTotalThreadsPerThreadgroup(_ value: UInt) { maxThreads = value }
    @ObjCMethod("requiredThreadsPerThreadgroup") func requiredThreadsPerThreadgroup() -> MTLSize { requiredThreads }
    @ObjCMethod("setRequiredThreadsPerThreadgroup:") func setRequiredThreadsPerThreadgroup(_ value: MTLSize) { requiredThreads = value }
    @ObjCMethod("supportBinaryLinking") func getSupportBinaryLinking() -> Bool { supportBinaryLinking }
    @ObjCMethod("setSupportBinaryLinking:") func setSupportBinaryLinking(_ value: Bool) { supportBinaryLinking = value }
    @ObjCMethod("staticLinkingDescriptor") func getStaticLinkingDescriptor() -> NSObject? { staticLinkingDescriptor }
    @ObjCMethod("setStaticLinkingDescriptor:") func setStaticLinkingDescriptor(_ value: NSObject?) { staticLinkingDescriptor = value }
    /// MTL4IndirectCommandBufferSupportState.
    @ObjCMethod("supportIndirectCommandBuffers") func getSupportIndirectCommandBuffers() -> Int { supportIndirectCommandBuffers }
    @ObjCMethod("setSupportIndirectCommandBuffers:") func setSupportIndirectCommandBuffers(_ value: Int) { supportIndirectCommandBuffers = value }
    @ObjCMethod("forwardProgressUsage") func getForwardProgressUsage() -> Int { forwardProgressUsage }
    @ObjCMethod("setForwardProgressUsage:") func setForwardProgressUsage(_ value: Int) { forwardProgressUsage = value }
    @ObjCMethod("contentionRelief") func getContentionRelief() -> Int { contentionRelief }
    @ObjCMethod("setContentionRelief:") func setContentionRelief(_ value: Int) { contentionRelief = value }
    @ObjCMethod("optimizeForPersistentKernel") func getOptimizeForPersistentKernel() -> Bool { optimizeForPersistentKernel }
    @ObjCMethod("setOptimizeForPersistentKernel:") func setOptimizeForPersistentKernel(_ value: Bool) { optimizeForPersistentKernel = value }

    @ObjCMethod("reset") func reset() {
        (label, options, computeFunctionDescriptor, multipleOfExecutionWidth, maxThreads) = (nil, nil, nil, false, 0)
        (requiredThreads, supportBinaryLinking, staticLinkingDescriptor) = (MTLSize(width: 0, height: 0, depth: 0), false, nil)
        (supportIndirectCommandBuffers, forwardProgressUsage, contentionRelief, optimizeForPersistentKernel) = (0, 0, 0, false)
    }

    @ObjCMethod("copyWithZone:") override func copy(zone: UnsafeMutableRawPointer?) -> MTL4ComputePipelineDescriptor {
        let copy = MTL4ComputePipelineDescriptor()
        copyBase(to: copy)
        (copy.computeFunctionDescriptor, copy.multipleOfExecutionWidth, copy.maxThreads) =
            (computeFunctionDescriptor, multipleOfExecutionWidth, maxThreads)
        (copy.requiredThreads, copy.supportBinaryLinking, copy.staticLinkingDescriptor) =
            (requiredThreads, supportBinaryLinking, staticLinkingDescriptor)
        (copy.supportIndirectCommandBuffers, copy.forwardProgressUsage, copy.contentionRelief, copy.optimizeForPersistentKernel) =
            (supportIndirectCommandBuffers, forwardProgressUsage, contentionRelief, optimizeForPersistentKernel)
        return copy
    }
}

/// A machine-learning pipeline's function and its inputs' dimensions, by
/// buffer index.
@ObjCClass("MTL4MachineLearningPipelineDescriptor")
open class MTL4MachineLearningPipelineDescriptor: MTL4PipelineDescriptor {
    var machineLearningFunctionDescriptor: NSObject?
    var inputDimensions: [Int: MTLTensorExtents] = [:]

    @ObjCMethod("init") public required init() { super.init() }

    @ObjCMethod("machineLearningFunctionDescriptor") func getMachineLearningFunctionDescriptor() -> NSObject? {
        machineLearningFunctionDescriptor
    }
    @ObjCMethod("setMachineLearningFunctionDescriptor:") func setMachineLearningFunctionDescriptor(_ value: NSObject?) {
        machineLearningFunctionDescriptor = value
    }

    @ObjCMethod("setInputDimensions:atBufferIndex:") func setInputDimensions(_ dimensions: MTLTensorExtents?, atBufferIndex index: Int) {
        inputDimensions[index] = dimensions
    }

    /// The array's extents at the range's indices, in order.
    @ObjCMethod("setInputDimensions:withRange:") func setInputDimensions(_ dimensions: NSObject?, withRange range: PerryRange) {
        guard let dimensions else { return }
        let list = dimensions.unsafeCast(to: NSArray.self)
        for offset in 0..<min(Int(range.length), Int(list.count())) {
            inputDimensions[Int(range.location) + offset] = list.object(at: UInt(offset)).unsafeCast(to: MTLTensorExtents.self)
        }
    }

    @ObjCMethod("inputDimensionsAtBufferIndex:") func inputDimensions(atBufferIndex index: Int) -> MTLTensorExtents? { inputDimensions[index] }

    @ObjCMethod("reset") func reset() {
        (label, options, machineLearningFunctionDescriptor, inputDimensions) = (nil, nil, nil, [:])
    }

    @ObjCMethod("copyWithZone:") override func copy(zone: UnsafeMutableRawPointer?) -> MTL4MachineLearningPipelineDescriptor {
        let copy = MTL4MachineLearningPipelineDescriptor()
        copyBase(to: copy)
        (copy.machineLearningFunctionDescriptor, copy.inputDimensions) = (machineLearningFunctionDescriptor, inputDimensions)
        return copy
    }
}

/// A binary function's name, function descriptor and options.
@ObjCClass("MTL4BinaryFunctionDescriptor")
open class MTL4BinaryFunctionDescriptor: NSObject {
    var name = ""
    var functionDescriptor: NSObject?
    var options: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("name") func getName() -> String { name }
    @ObjCMethod("setName:") func setName(_ name: String?) { self.name = name ?? "" }
    @ObjCMethod("functionDescriptor") func getFunctionDescriptor() -> NSObject? { functionDescriptor }
    @ObjCMethod("setFunctionDescriptor:") func setFunctionDescriptor(_ value: NSObject?) { functionDescriptor = value }
    /// MTL4BinaryFunctionOptions.
    @ObjCMethod("options") func getOptions() -> UInt { options }
    @ObjCMethod("setOptions:") func setOptions(_ value: UInt) { options = value }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTL4BinaryFunctionDescriptor {
        let copy = MTL4BinaryFunctionDescriptor()
        (copy.name, copy.functionDescriptor, copy.options) = (name, functionDescriptor, options)
        return copy
    }
}

/// A library to compile: its source, compile options and name.
@ObjCClass("MTL4LibraryDescriptor")
open class MTL4LibraryDescriptor: NSObject {
    var source: String?
    var options: NSObject?
    var name: String?

    @ObjCMethod("init") public required override init() { super.init() }
    @ObjCMethod("source") func getSource() -> String? { source }
    @ObjCMethod("setSource:") func setSource(_ value: String?) { source = value }
    @ObjCMethod("options") func getOptions() -> NSObject? { options }
    @ObjCMethod("setOptions:") func setOptions(_ value: NSObject?) { options = value }
    @ObjCMethod("name") func getName() -> String? { name }
    @ObjCMethod("setName:") func setName(_ value: String?) { name = value }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MTL4LibraryDescriptor {
        let copy = MTL4LibraryDescriptor()
        (copy.source, copy.options, copy.name) = (source, options, name)
        return copy
    }
}
