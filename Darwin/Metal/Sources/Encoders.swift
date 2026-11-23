import Foundation

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLBlitCommandEncoder {
    public func fill(buffer: MTLBuffer, range: Range<Int>, value: UInt8) {
        __fill(buffer, range: NSRange(range), value: value)
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
    public func resetCommandsInBuffer(_ buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __resetCommands(in: buffer, with: NSRange(range))
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
    public func copyIndirectCommandBuffer(_ buffer: MTLIndirectCommandBuffer, sourceRange: Range<Int>,
                                          destination: MTLIndirectCommandBuffer, destinationIndex: Int) {
        __copy(buffer, sourceRange: NSRange(sourceRange), destination: destination, destinationIndex: destinationIndex)
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
    public func optimizeIndirectCommandBuffer(_ buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __optimizeIndirectCommandBuffer(buffer, with: NSRange(range))
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    public func resolveCounters(_ sampleBuffer: MTLCounterSampleBuffer, range: Range<Int>,
                                destinationBuffer: MTLBuffer, destinationOffset: Int) {
        __resolveCounters(sampleBuffer, in: NSRange(range), destinationBuffer: destinationBuffer, destinationOffset: destinationOffset)
    }
}

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLBuffer {
    @available(macOS 10.11, macCatalyst 14.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func didModifyRange(_ range: Range<Int>) {
        __didModifyRange(NSRange(range))
    }

    @available(macOS 10.12, iOS 10.0, tvOS 10.0, *)
    public func addDebugMarker(_ marker: String, range: Range<Int>) {
        __addDebugMarker(marker, range: NSRange(range))
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
extension MTLAccelerationStructureCommandEncoder {
    public func useResources(_ resources: [MTLResource], usage: MTLResourceUsage) {
        __use(resources, count: resources.count, usage: usage)
    }

    public func useHeaps(_ heaps: [MTLHeap]) {
        __use(heaps, count: heaps.count)
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
extension MTLVisibleFunctionTable {
    public func setFunctions(_ functions: [MTLFunctionHandle?], range: Range<Int>) {
        __setFunctions(functions, with: NSRange(range))
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
extension MTLIntersectionFunctionTable {
    public func setBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    public func setFunctions(_ functions: [MTLFunctionHandle?], range: Range<Int>) {
        __setFunctions(functions, with: NSRange(range))
    }

    public func setVisibleFunctionTables(_ functionTables: [MTLVisibleFunctionTable?], bufferRange: Range<Int>) {
        __setVisibleFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }
}

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLComputeCommandEncoder {
    @available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
    public func useResources(_ resources: [MTLResource], usage: MTLResourceUsage) {
        __use(resources, count: resources.count, usage: usage)
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
    public func useHeaps(_ heaps: [MTLHeap]) {
        __use(heaps, count: heaps.count)
    }

    public func setBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
    public func setBuffers(_ buffers: [MTLBuffer?], offsets: [Int], attributeStrides: [Int], range: Range<Int>) {
        __setBuffers(buffers, offsets: offsets, attributeStrides: attributeStrides, with: NSRange(range))
    }

    public func setTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        __setTextures(textures, with: NSRange(range))
    }

    public func setSamplerStates(_ samplers: [MTLSamplerState?], range: Range<Int>) {
        __setSamplerStates(samplers, with: NSRange(range))
    }

    public func setSamplerStates(_ samplers: [MTLSamplerState?], lodMinClamps: [Float], lodMaxClamps: [Float], range: Range<Int>) {
        __setSamplerStates(samplers, lodMinClamps: lodMinClamps, lodMaxClamps: lodMaxClamps, with: NSRange(range))
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
    public func memoryBarrier(resources: [MTLResource]) {
        __memoryBarrier(resources: resources, count: resources.count)
    }

    @available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
    public func setVisibleFunctionTables(_ visibleFunctionTables: [MTLVisibleFunctionTable?], bufferRange: Range<Int>) {
        __setVisibleFunctionTables(visibleFunctionTables, withBufferRange: NSRange(bufferRange))
    }

    @available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
    public func setIntersectionFunctionTables(_ intersectionFunctionTables: [MTLIntersectionFunctionTable?], bufferRange: Range<Int>) {
        __setIntersectionFunctionTables(intersectionFunctionTables, withBufferRange: NSRange(bufferRange))
    }
}

@available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
extension MTLArgumentEncoder {
    public func setBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    public func setTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        __setTextures(textures, with: NSRange(range))
    }

    public func setSamplerStates(_ samplers: [MTLSamplerState?], range: Range<Int>) {
        __setSamplerStates(samplers, with: NSRange(range))
    }

    @available(macOS 10.14, iOS 13.0, tvOS 13.0, *)
    public func setRenderPipelineStates(_ pipelines: [MTLRenderPipelineState?], range: Range<Int>) {
        __setRenderPipelineStates(pipelines, with: NSRange(range))
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
    public func setIndirectCommandBuffers(_ buffers: [MTLIndirectCommandBuffer?], range: Range<Int>) {
        __setIndirectCommandBuffers(buffers, with: NSRange(range))
    }

    @available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
    public func setVisibleFunctionTables(_ visibleFunctionTables: [MTLVisibleFunctionTable?], range: Range<Int>) {
        __setVisibleFunctionTables(visibleFunctionTables, withBufferRange: NSRange(range))
    }

    @available(macOS 11.0, iOS 14.0, tvOS 16.0, *)
    public func setIntersectionFunctionTables(_ intersectionFunctionTables: [MTLIntersectionFunctionTable?], range: Range<Int>) {
        __setIntersectionFunctionTables(intersectionFunctionTables, withBufferRange: NSRange(range))
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setDepthStencilStates(_ depthStencilStates: [MTLDepthStencilState?], range: Range<Int>) {
        __setDepthStencilStates(depthStencilStates, with: NSRange(range))
    }
}

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLRenderCommandEncoder {
    @available(macOS, introduced: 10.13, deprecated: 13.0, message: "Please specify stages with useResources(_:usage:stages:)")
    @available(iOS, introduced: 11.0, deprecated: 16.0, message: "Please specify stages with useResources(_:usage:stages:)")
    @available(tvOS, introduced: 11.0, deprecated: 16.0, message: "Please specify stages with useResources(_:usage:stages:)")
    public func useResources(_ resources: [MTLResource], usage: MTLResourceUsage) {
        __use(resources, count: resources.count, usage: usage)
    }

    @available(macOS, introduced: 10.13, deprecated: 13.0, message: "Please specify stages with useHeaps(_:stages:)")
    @available(iOS, introduced: 11.0, deprecated: 16.0, message: "Please specify stages with useHeaps(_:stages:)")
    @available(tvOS, introduced: 11.0, deprecated: 16.0, message: "Please specify stages with useHeaps(_:stages:)")
    public func useHeaps(_ heaps: [MTLHeap]) {
        __use(heaps, count: heaps.count)
    }

    @available(macOS 10.13, iOS 12.0, tvOS 14.5, *)
    public func setViewports(_ viewports: [MTLViewport]) {
        __setViewports(viewports, count: viewports.count)
    }

    @available(macOS 10.13, iOS 12.0, tvOS 14.5, *)
    public func setScissorRects(_ scissorRects: [MTLScissorRect]) {
        __setScissorRects(scissorRects, count: scissorRects.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setDepthTestBounds(_ bounds: ClosedRange<Float>) {
        __setDepthTestMinBound(bounds.lowerBound, maxBound: bounds.upperBound)
    }

    public func setVertexBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setVertexBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
    public func setVertexBuffers(_ buffers: [MTLBuffer?], offsets: [Int], attributeStrides: [Int], range: Range<Int>) {
        __setVertexBuffers(buffers, offsets: offsets, attributeStrides: attributeStrides, with: NSRange(range))
    }

    public func setVertexTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        __setVertexTextures(textures, with: NSRange(range))
    }

    public func setVertexSamplerStates(_ samplers: [MTLSamplerState?], range: Range<Int>) {
        __setVertexSamplerStates(samplers, with: NSRange(range))
    }

    public func setVertexSamplerStates(_ samplers: [MTLSamplerState?], lodMinClamps: [Float], lodMaxClamps: [Float], range: Range<Int>) {
        __setVertexSamplerStates(samplers, lodMinClamps: lodMinClamps, lodMaxClamps: lodMaxClamps, with: NSRange(range))
    }

    public func setFragmentBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setFragmentBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    public func setFragmentTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        __setFragmentTextures(textures, with: NSRange(range))
    }

    public func setFragmentSamplerStates(_ samplers: [MTLSamplerState?], range: Range<Int>) {
        __setFragmentSamplerStates(samplers, with: NSRange(range))
    }

    public func setFragmentSamplerStates(_ samplers: [MTLSamplerState?], lodMinClamps: [Float], lodMaxClamps: [Float], range: Range<Int>) {
        __setFragmentSamplerStates(samplers, lodMinClamps: lodMinClamps, lodMaxClamps: lodMaxClamps, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setObjectBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setObjectBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setObjectTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        __setObjectTextures(textures, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setObjectSamplerStates(_ samplers: [MTLSamplerState?], range: Range<Int>) {
        __setObjectSamplerStates(samplers, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setObjectSamplerStates(_ samplers: [MTLSamplerState?], lodMinClamps: [Float], lodMaxClamps: [Float], range: Range<Int>) {
        __setObjectSamplerStates(samplers, lodMinClamps: lodMinClamps, lodMaxClamps: lodMaxClamps, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setMeshBuffers(_ buffers: [MTLBuffer?], offsets: [Int], range: Range<Int>) {
        __setMeshBuffers(buffers, offsets: offsets, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setMeshTextures(_ textures: [MTLTexture?], range: Range<Int>) {
        __setMeshTextures(textures, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setMeshSamplerStates(_ samplers: [MTLSamplerState?], range: Range<Int>) {
        __setMeshSamplerStates(samplers, with: NSRange(range))
    }

    @available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
    public func setMeshSamplerStates(_ samplers: [MTLSamplerState?], lodMinClamps: [Float], lodMaxClamps: [Float], range: Range<Int>) {
        __setMeshSamplerStates(samplers, lodMinClamps: lodMinClamps, lodMaxClamps: lodMaxClamps, with: NSRange(range))
    }

    @available(macOS 10.14, macCatalyst 14.0, iOS 16.0, tvOS 16.0, *)
    public func memoryBarrier(resources: [MTLResource], after: MTLRenderStages, before: MTLRenderStages) {
        __memoryBarrier(resources: resources, count: resources.count, after: after, before: before)
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
    public func executeCommandsInBuffer(_ buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __executeCommands(in: buffer, with: NSRange(range))
    }

    @available(macOS 10.14, iOS 13.0, tvOS 13.0, *)
    public func executeCommandsInBuffer(_ buffer: MTLIndirectCommandBuffer, indirectBuffer indirectRangeBuffer: MTLBuffer, offset: Int) {
        __executeCommands(in: buffer, indirectBuffer: indirectRangeBuffer, indirectBufferOffset: offset)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func setVertexVisibleFunctionTables(_ functionTables: [MTLVisibleFunctionTable?], bufferRange: Range<Int>) {
        __setVertexVisibleFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }

    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func setFragmentVisibleFunctionTables(_ functionTables: [MTLVisibleFunctionTable?], bufferRange: Range<Int>) {
        __setFragmentVisibleFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }

    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func setTileVisibleFunctionTables(_ functionTables: [MTLVisibleFunctionTable?], bufferRange: Range<Int>) {
        __setTileVisibleFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }

    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func setVertexIntersectionFunctionTables(_ functionTables: [MTLIntersectionFunctionTable?], bufferRange: Range<Int>) {
        __setVertexIntersectionFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }

    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func setFragmentIntersectionFunctionTables(_ functionTables: [MTLIntersectionFunctionTable?], bufferRange: Range<Int>) {
        __setFragmentIntersectionFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }

    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func setTileIntersectionFunctionTables(_ functionTables: [MTLIntersectionFunctionTable?], bufferRange: Range<Int>) {
        __setTileIntersectionFunctionTables(functionTables, withBufferRange: NSRange(bufferRange))
    }
}

@available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
extension MTLIndirectCommandBuffer {
    public func reset(_ range: Range<Int>) {
        __reset(with: NSRange(range))
    }
}
