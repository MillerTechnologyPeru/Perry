import Foundation

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLDevice {
    @available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
    public func getDefaultSamplePositions(sampleCount: Int) -> [MTLSamplePosition] {
        var positions = [MTLSamplePosition](repeating: MTLSamplePosition(), count: sampleCount)
        __getDefaultSamplePositions(&positions, count: sampleCount)
        return positions
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    public func sampleTimestamps() -> (cpu: MTLTimestamp, gpu: MTLTimestamp) {
        var cpu: MTLTimestamp = 0
        var gpu: MTLTimestamp = 0
        __sampleTimestamps(&cpu, gpuTimestamp: &gpu)
        return (cpu, gpu)
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func makeRenderPipelineState(descriptor: MTLMeshRenderPipelineDescriptor, options: MTLPipelineOption) throws
        -> (MTLRenderPipelineState, MTLRenderPipelineReflection?) {
        var reflection: MTLAutoreleasedRenderPipelineReflection?
        let pipeline = try __newRenderPipelineState(withMeshDescriptor: descriptor, options: options, reflection: &reflection)
        return (pipeline, reflection)
    }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, *)
extension MTLFunctionConstantValues {
    public func setConstantValues(_ values: UnsafeRawPointer, type: MTLDataType, range: Range<Int>) {
        __setConstantValues(values, type: type, with: NSRange(range))
    }
}

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLRenderPassDescriptor {
    @available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
    public func setSamplePositions(_ positions: [MTLSamplePosition]) {
        __setSamplePositions(positions, count: positions.count)
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
    public func getSamplePositions() -> [MTLSamplePosition] {
        // Called with no array it gives the number of positions set.
        let count = __getSamplePositions(nil, count: 0)
        var positions = [MTLSamplePosition](repeating: MTLSamplePosition(), count: count)
        _ = __getSamplePositions(&positions, count: count)
        return positions
    }
}

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLTexture {
    @available(macOS 10.11, iOS 9.0, tvOS 9.0, *)
    public func makeTextureView(pixelFormat: MTLPixelFormat, textureType: MTLTextureType,
                                levels levelRange: Range<Int>, slices sliceRange: Range<Int>) -> MTLTexture? {
        __newTextureView(with: pixelFormat, textureType: textureType, levels: NSRange(levelRange), slices: NSRange(sliceRange))
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    public func makeTextureView(pixelFormat: MTLPixelFormat, textureType: MTLTextureType,
                                levels levelRange: Range<Int>, slices sliceRange: Range<Int>,
                                swizzle: MTLTextureSwizzleChannels) -> MTLTexture? {
        __newTextureView(with: pixelFormat, textureType: textureType, levels: NSRange(levelRange), slices: NSRange(sliceRange), swizzle: swizzle)
    }
}

@available(macOS 10.15.4, macCatalyst 13.4, iOS 13.0, tvOS 16.0, *)
extension MTLRasterizationRateSampleArray {
    public subscript(index: Int) -> Float {
        get { __objectAtIndexedSubscript(index).floatValue }
        set { __setObject(NSNumber(value: newValue), atIndexedSubscript: index) }
    }
}

@available(macOS 10.15.4, macCatalyst 13.4, iOS 13.0, tvOS 16.0, *)
extension MTLRasterizationRateLayerDescriptor {
    convenience public init(horizontal: [Float], vertical: [Float]) {
        let size = MTLSize(width: horizontal.count, height: vertical.count, depth: 0)
        self.init(__sampleCount: size, horizontal: horizontal, vertical: vertical)
    }
}

@available(macOS 10.15.4, macCatalyst 13.4, iOS 13.0, tvOS 16.0, *)
extension MTLRasterizationRateMapDescriptor {
    convenience public init(screenSize: MTLSize, label: String? = nil) {
        self.init()
        self.screenSize = screenSize
        self.label = label
    }

    convenience public init(screenSize: MTLSize, layer: MTLRasterizationRateLayerDescriptor, label: String? = nil) {
        self.init(screenSize: screenSize, layers: [layer], label: label)
    }

    convenience public init(screenSize: MTLSize, layers: [MTLRasterizationRateLayerDescriptor], label: String? = nil) {
        self.init(screenSize: screenSize, label: label)
        for (index, layer) in layers.enumerated() {
            setLayer(layer, at: index)
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4RenderPassDescriptor {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var samplePositions: [MTLSamplePosition] {
        get {
            let count = __getSamplePositions(nil, count: 0)
            var positions = [MTLSamplePosition](repeating: MTLSamplePosition(), count: count)
            _ = __getSamplePositions(&positions, count: count)
            return positions
        }
        set(positions) {
            __setSamplePositions(positions, count: positions.count)
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTLLogicalToPhysicalColorAttachmentMap {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public subscript(logicalIndex: Int) -> Int {
        get { __getPhysicalIndex(forLogicalIndex: logicalIndex) }
        set(physicalIndex) { __setPhysicalIndex(physicalIndex, forLogicalIndex: logicalIndex) }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTLTensorExtents {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    convenience public init?(_ values: [Int]) {
        self.init(__rank: values.count, values: values)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var extents: [Int] {
        (0 ..< rank).map { __extent(atDimensionIndex: $0) }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4MachineLearningPipelineDescriptor {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setInputDimensions(_ dimensions: [MTLTensorExtents], bufferIndex: Int) {
        __setInputDimensions(dimensions, with: NSRange(location: bufferIndex, length: dimensions.count))
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTLResourceViewPool {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func copyResourceViews(sourcePool: MTLResourceViewPool, sourceRange: Range<Int>, destinationIndex: Int) -> MTLResourceID {
        __copyResourceViews(from: sourcePool, sourceRange: NSRange(sourceRange), destinationIndex: destinationIndex)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTLTextureViewDescriptor {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var levelRange: Range<Int> {
        get { Range(__levelRange) }
        set(value) { __levelRange = NSRange(value) }
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var sliceRange: Range<Int> {
        get { Range(__sliceRange) }
        set(value) { __sliceRange = NSRange(value) }
    }
}
