import Foundation

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4RenderCommandEncoder {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setViewports(_ viewports: [MTLViewport]) {
        __setViewports(viewports, count: viewports.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setScissorRects(_ scissorRects: [MTLScissorRect]) {
        __setScissorRects(scissorRects, count: scissorRects.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setVertexAmplificationCount(_ count: Int) {
        __setVertexAmplificationCount(count, viewMappings: nil)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setVertexAmplificationCount(_ viewMappings: [MTLVertexAmplificationViewMapping]) {
        __setVertexAmplificationCount(viewMappings.count, viewMappings: viewMappings)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func setDepthTestBounds(_ bounds: ClosedRange<Float>) {
        __setDepthTestMinBound(bounds.lowerBound, maxBound: bounds.upperBound)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func executeCommands(buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __executeCommands(in: buffer, with: NSRange(range))
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4ComputeCommandEncoder {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func executeCommands(buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __executeCommands(in: buffer, with: NSRange(range))
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func copy(sourceTexture: MTLTexture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: MTLOrigin, sourceSize: MTLSize,
                     destinationBuffer: MTLBuffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int,
                     options: MTLBlitOption = []) {
        __copy(from: sourceTexture, sourceSlice: sourceSlice, sourceLevel: sourceLevel, sourceOrigin: sourceOrigin, sourceSize: sourceSize,
               to: destinationBuffer, destinationOffset: destinationOffset, destinationBytesPerRow: destinationBytesPerRow,
               destinationBytesPerImage: destinationBytesPerImage, options: options)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func copy(sourceBuffer: MTLBuffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: MTLSize,
                     destinationTexture: MTLTexture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: MTLOrigin,
                     options: MTLBlitOption = []) {
        __copy(from: sourceBuffer, sourceOffset: sourceOffset, sourceBytesPerRow: sourceBytesPerRow, sourceBytesPerImage: sourceBytesPerImage,
               sourceSize: sourceSize, to: destinationTexture, destinationSlice: destinationSlice, destinationLevel: destinationLevel,
               destinationOrigin: destinationOrigin, options: options)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func fill(buffer: MTLBuffer, range: Range<Int>, value: UInt8) {
        __fill(buffer, range: NSRange(range), value: value)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func copyCommands(sourceBuffer: MTLIndirectCommandBuffer, sourceRange: Range<Int>,
                             destinationBuffer: MTLIndirectCommandBuffer, destinationIndex: Int) {
        __copy(sourceBuffer, sourceRange: NSRange(sourceRange), destination: destinationBuffer, destinationIndex: destinationIndex)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func resetCommands(buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __resetCommands(in: buffer, with: NSRange(range))
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func optimizeCommands(buffer: MTLIndirectCommandBuffer, range: Range<Int>) {
        __optimizeIndirectCommandBuffer(buffer, with: NSRange(range))
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4CommandQueue {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func commit(_ commandBuffers: [MTL4CommandBuffer], options: MTL4CommitOptions? = nil) {
        if let options {
            __commit(commandBuffers, count: commandBuffers.count, options: options)
        } else {
            __commit(commandBuffers, count: commandBuffers.count)
        }
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func addResidencySets(_ residencySets: [MTLResidencySet]) {
        __add(residencySets, count: residencySets.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func removeResidencySets(_ residencySets: [MTLResidencySet]) {
        __remove(residencySets, count: residencySets.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func updateMappings(texture: MTLTexture, heap: MTLHeap?, operations: [MTL4UpdateSparseTextureMappingOperation]) {
        __updateTextureMappings(texture, heap: heap, operations: operations, count: operations.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func updateMappings(buffer: MTLBuffer, heap: MTLHeap?, operations: [MTL4UpdateSparseBufferMappingOperation]) {
        __updateBufferMappings(buffer, heap: heap, operations: operations, count: operations.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func copyMappings(sourceTexture: MTLTexture, destinationTexture: MTLTexture, operations: [MTL4CopySparseTextureMappingOperation]) {
        __copyTextureMappings(from: sourceTexture, to: destinationTexture, operations: operations, count: operations.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func copyMappings(sourceBuffer: MTLBuffer, destinationBuffer: MTLBuffer, operations: [MTL4CopySparseBufferMappingOperation]) {
        __copyBufferMappings(from: sourceBuffer, to: destinationBuffer, operations: operations, count: operations.count)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4CommandBuffer {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func useResidencySets(_ residencySets: [MTLResidencySet]) {
        __use(residencySets, count: residencySets.count)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func resolveCounterHeap(_ counterHeap: MTL4CounterHeap, range: Range<Int>, buffer: MTL4BufferRange,
                                   fenceToWait: MTLFence? = nil, fenceToUpdate: MTLFence? = nil) {
        __resolve(counterHeap, with: NSRange(range), intoBuffer: buffer, wait: fenceToWait, update: fenceToUpdate)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4CommandEncoder {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func barrier(afterQueueStages: MTLStages, beforeStages: MTLStages, visibilityOptions: MTL4VisibilityOptions = [.device]) {
        __barrier(afterQueue: afterQueueStages, before: beforeStages, visibilityOptions: visibilityOptions)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func barrier(afterStages: MTLStages, beforeQueueStages: MTLStages, visibilityOptions: MTL4VisibilityOptions = [.device]) {
        __barrier(after: afterStages, beforeQueue: beforeQueueStages, visibilityOptions: visibilityOptions)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func barrier(afterEncoderStages: MTLStages, beforeEncoderStages: MTLStages, visibilityOptions: MTL4VisibilityOptions = [.device]) {
        __barrier(afterEncoderStages: afterEncoderStages, beforeEncoderStages: beforeEncoderStages, visibilityOptions: visibilityOptions)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4CounterHeap {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func resolveCounterRange(_ range: Range<Int>) throws -> Data? {
        __resolveCounterRange(NSRange(range))
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func invalidateCounterRange(_ range: Range<Int>) {
        __invalidateCounterRange(NSRange(range))
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4Archive {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeComputePipelineState(descriptor: MTL4ComputePipelineDescriptor,
                                         dynamicLinkingDescriptor: MTL4PipelineStageDynamicLinkingDescriptor? = nil) throws -> MTLComputePipelineState {
        if let dynamicLinkingDescriptor {
            return try __newComputePipelineState(with: descriptor, dynamicLinkingDescriptor: dynamicLinkingDescriptor)
        }
        return try __newComputePipelineState(with: descriptor)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeRenderPipelineState(descriptor: MTL4PipelineDescriptor,
                                        dynamicLinkingDescriptor: MTL4RenderPipelineDynamicLinkingDescriptor? = nil) throws -> MTLRenderPipelineState {
        if let dynamicLinkingDescriptor {
            return try __newRenderPipelineState(with: descriptor, dynamicLinkingDescriptor: dynamicLinkingDescriptor)
        }
        return try __newRenderPipelineState(with: descriptor)
    }
}
