import CPerryGeometry
import CPerryMetal
import PerryObjCInterop

// Render and blit command encoders. Like the compute encoder, each warns
// with the selector of a call metal2vulkan refuses, and keeps what it binds
// alive until its command buffer completes.

@ObjCProtocol("MTLRenderCommandEncoder")
protocol MTLRenderCommandEncoderProtocol: MTLCommandEncoderProtocol {}

@ObjCProtocol("MTLBlitCommandEncoder")
protocol MTLBlitCommandEncoderProtocol: MTLCommandEncoderProtocol {}

@ObjCClass("_MTLRenderCommandEncoder")
open class MTLRenderCommandEncoder: NSObject, MTLRenderCommandEncoderProtocol {
    var handle: perry_m2v_handle?
    var commandBuffer: MTLCommandBuffer?
    var label: String?

    init(handle: perry_m2v_handle, commandBuffer: MTLCommandBuffer) {
        self.handle = handle
        self.commandBuffer = commandBuffer
        super.init()
    }

    deinit {
        if let handle { M2V.api.render_encoder_release(handle) }
    }

    private func encode(_ selector: String, _ body: (perry_m2v_handle, perry_m2v_error) -> Bool) {
        guard let handle else {
            metalWarning("-[MTLRenderCommandEncoder \(selector)] after endEncoding")
            return
        }
        let (_, message) = M2V.call { body(handle, $0) }
        if let message { metalWarning("-[MTLRenderCommandEncoder \(selector)]: \(message)") }
    }

    private func keep(_ object: NSObject?) {
        if let object { commandBuffer?.keep(object) }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { commandBuffer?.device() }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }

    @ObjCMethod("setRenderPipelineState:") func setRenderPipelineState(_ state: MTLRenderPipelineState?) {
        guard let state, let stateHandle = state.handle else { return }
        keep(state)
        encode("setRenderPipelineState:") { M2V.api.render_encoder_set_render_pipeline_state($0, stateHandle, $1) }
    }

    // MARK: Vertex stage

    @ObjCMethod("setVertexBuffer:offset:atIndex:") func setVertexBuffer(_ buffer: MTLBuffer?, offset: UInt, index: UInt) {
        Trace.log("setVertexBuffer", "\(buffer.map { "\(M2V.api.buffer_length($0.handle))" } ?? "nil") +\(offset) at \(index): \(Trace.floats(buffer.flatMap { M2V.api.buffer_contents($0.handle) }.map { UnsafeRawPointer($0 + Int(offset)) }, 48))")
        keep(buffer)
        encode("setVertexBuffer:offset:atIndex:") {
            M2V.api.render_encoder_set_vertex_buffer($0, buffer?.handle, UInt64(offset), UInt32(index), $1)
        }
    }

    @ObjCMethod("setVertexBuffers:offsets:withRange:")
    func setVertexBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setVertexBuffer(buffers?[i].map { MTLBuffer.objCInstance($0, ownership: .retain) }, offset: offsets?[i] ?? 0,
                            index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setVertexBufferOffset:atIndex:") func setVertexBufferOffset(_ offset: UInt, index: UInt) {
        Trace.log("setVertexBufferOffset", "+\(offset) at \(index)")
        encode("setVertexBufferOffset:atIndex:") {
            M2V.api.render_encoder_set_vertex_buffer_offset($0, UInt64(offset), UInt32(index), $1)
        }
    }

    @ObjCMethod("setVertexBytes:length:atIndex:") func setVertexBytes(_ bytes: UnsafeRawPointer?, length: UInt, index: UInt) {
        Trace.log("setVertexBytes", "\(length) at \(index): \(Trace.floats(bytes, length))")
        encode("setVertexBytes:length:atIndex:") {
            M2V.api.render_encoder_set_vertex_bytes($0, bytes, Int(length), UInt32(index), $1)
        }
    }

    @ObjCMethod("setVertexTexture:atIndex:") func setVertexTexture(_ texture: MTLTexture?, index: UInt) {
        keep(texture)
        encode("setVertexTexture:atIndex:") {
            M2V.api.render_encoder_set_vertex_texture($0, texture?.handle, UInt32(index), $1)
        }
    }

    @ObjCMethod("setVertexTextures:withRange:")
    func setVertexTextures(_ textures: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setVertexTexture(textures?[i].map { MTLTexture.objCInstance($0, ownership: .retain) }, index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setVertexSamplerState:atIndex:") func setVertexSamplerState(_ sampler: MTLSamplerState?, index: UInt) {
        keep(sampler)
        encode("setVertexSamplerState:atIndex:") {
            M2V.api.render_encoder_set_vertex_sampler_state($0, sampler?.handle, UInt32(index), $1)
        }
    }

    // MARK: Fragment stage

    @ObjCMethod("setFragmentBuffer:offset:atIndex:") func setFragmentBuffer(_ buffer: MTLBuffer?, offset: UInt, index: UInt) {
        keep(buffer)
        encode("setFragmentBuffer:offset:atIndex:") {
            M2V.api.render_encoder_set_fragment_buffer($0, buffer?.handle, UInt64(offset), UInt32(index), $1)
        }
    }

    @ObjCMethod("setFragmentBuffers:offsets:withRange:")
    func setFragmentBuffers(_ buffers: UnsafePointer<UnsafeMutableRawPointer?>?, offsets: UnsafePointer<UInt>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setFragmentBuffer(buffers?[i].map { MTLBuffer.objCInstance($0, ownership: .retain) }, offset: offsets?[i] ?? 0,
                              index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setFragmentBufferOffset:atIndex:") func setFragmentBufferOffset(_ offset: UInt, index: UInt) {
        encode("setFragmentBufferOffset:atIndex:") {
            M2V.api.render_encoder_set_fragment_buffer_offset($0, UInt64(offset), UInt32(index), $1)
        }
    }

    @ObjCMethod("setFragmentBytes:length:atIndex:") func setFragmentBytes(_ bytes: UnsafeRawPointer?, length: UInt, index: UInt) {
        Trace.log("setFragmentBytes", "\(length) at \(index): \(Trace.floats(bytes, length))")
        encode("setFragmentBytes:length:atIndex:") {
            M2V.api.render_encoder_set_fragment_bytes($0, bytes, Int(length), UInt32(index), $1)
        }
    }

    @ObjCMethod("setFragmentTexture:atIndex:") func setFragmentTexture(_ texture: MTLTexture?, index: UInt) {
        Trace.log("setFragmentTexture", "\(texture.map { "\($0.descriptor.width)×\($0.descriptor.height) f\($0.descriptor.pixel_format)" } ?? "nil") at \(index)")
        keep(texture)
        encode("setFragmentTexture:atIndex:") {
            M2V.api.render_encoder_set_fragment_texture($0, texture?.handle, UInt32(index), $1)
        }
    }

    @ObjCMethod("setFragmentTextures:withRange:")
    func setFragmentTextures(_ textures: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setFragmentTexture(textures?[i].map { MTLTexture.objCInstance($0, ownership: .retain) }, index: range.location + UInt(i))
        }
    }

    @ObjCMethod("setFragmentSamplerState:atIndex:") func setFragmentSamplerState(_ sampler: MTLSamplerState?, index: UInt) {
        keep(sampler)
        encode("setFragmentSamplerState:atIndex:") {
            M2V.api.render_encoder_set_fragment_sampler_state($0, sampler?.handle, UInt32(index), $1)
        }
    }

    @ObjCMethod("setFragmentSamplerStates:withRange:")
    func setFragmentSamplerStates(_ samplers: UnsafePointer<UnsafeMutableRawPointer?>?, range: PerryRange) {
        for i in 0..<Int(range.length) {
            setFragmentSamplerState(samplers?[i].map { MTLSamplerState.objCInstance($0, ownership: .retain) },
                                    index: range.location + UInt(i))
        }
    }

    // MARK: Fixed-function state

    @ObjCMethod("setViewport:") func setViewport(_ viewport: MTLViewport) {
        Trace.log("setViewport", "\(viewport.originX),\(viewport.originY) \(viewport.width)×\(viewport.height) z \(viewport.znear)…\(viewport.zfar)")
        encode("setViewport:") { M2V.api.render_encoder_set_viewport($0, viewport, $1) }
    }

    @ObjCMethod("setScissorRect:") func setScissorRect(_ rect: MTLScissorRect) {
        Trace.log("setScissorRect", "\(rect.x),\(rect.y) \(rect.width)×\(rect.height)")
        if Trace.debugNoScissor { return }
        encode("setScissorRect:") {
            M2V.api.render_encoder_set_scissor_rect($0, UInt64(rect.x), UInt64(rect.y), UInt64(rect.width), UInt64(rect.height), $1)
        }
    }

    @ObjCMethod("setCullMode:") func setCullMode(_ mode: UInt) {
        Trace.log("setCullMode", "\(mode)")
        if Trace.debugNoCull { return }
        encode("setCullMode:") { M2V.api.render_encoder_set_cull_mode($0, UInt32(mode), $1) }
    }

    @ObjCMethod("setFrontFacingWinding:") func setFrontFacingWinding(_ winding: UInt) {
        Trace.log("setFrontFacingWinding", "\(winding)")
        encode("setFrontFacingWinding:") { M2V.api.render_encoder_set_front_facing_winding($0, UInt32(winding), $1) }
    }

    @ObjCMethod("setTriangleFillMode:") func setTriangleFillMode(_ mode: UInt) {
        encode("setTriangleFillMode:") { M2V.api.render_encoder_set_triangle_fill_mode($0, UInt32(mode), $1) }
    }

    @ObjCMethod("setDepthStencilState:") func setDepthStencilState(_ state: MTLDepthStencilState?) {
        keep(state)
        encode("setDepthStencilState:") { M2V.api.render_encoder_set_depth_stencil_state($0, state?.handle, $1) }
    }

    @ObjCMethod("setStencilReferenceValue:") func setStencilReferenceValue(_ value: UInt32) {
        encode("setStencilReferenceValue:") { M2V.api.render_encoder_set_stencil_reference_values($0, value, value, $1) }
    }

    @ObjCMethod("setStencilFrontReferenceValue:backReferenceValue:")
    func setStencilReferenceValues(front: UInt32, back: UInt32) {
        encode("setStencilFrontReferenceValue:backReferenceValue:") {
            M2V.api.render_encoder_set_stencil_reference_values($0, front, back, $1)
        }
    }

    @ObjCMethod("setBlendColorRed:green:blue:alpha:") func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {
        encode("setBlendColorRed:green:blue:alpha:") { M2V.api.render_encoder_set_blend_color($0, red, green, blue, alpha, $1) }
    }

    @ObjCMethod("setDepthBias:slopeScale:clamp:") func setDepthBias(_ bias: Float, slopeScale: Float, clamp: Float) {
        encode("setDepthBias:slopeScale:clamp:") { M2V.api.render_encoder_set_depth_bias($0, bias, slopeScale, clamp, $1) }
    }

    @ObjCMethod("setVisibilityResultMode:offset:") func setVisibilityResultMode(_ mode: UInt, offset: UInt) {
        encode("setVisibilityResultMode:offset:") {
            M2V.api.render_encoder_set_visibility_result_mode($0, UInt64(mode), UInt64(offset), $1)
        }
    }

    @ObjCMethod("setDepthClipMode:") func setDepthClipMode(_ mode: UInt) {}

    // MARK: Draws

    @ObjCMethod("drawPrimitives:vertexStart:vertexCount:")
    func draw(_ type: UInt, vertexStart: UInt, vertexCount: UInt) {
        draw(type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: 1, baseInstance: 0)
    }

    @ObjCMethod("drawPrimitives:vertexStart:vertexCount:instanceCount:")
    func draw(_ type: UInt, vertexStart: UInt, vertexCount: UInt, instanceCount: UInt) {
        draw(type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount, baseInstance: 0)
    }

    @ObjCMethod("drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:")
    func draw(_ type: UInt, vertexStart: UInt, vertexCount: UInt, instanceCount: UInt, baseInstance: UInt) {
        Trace.log("drawPrimitives", "type \(type) count \(vertexCount)")
        encode("drawPrimitives:vertexStart:vertexCount:") {
            M2V.api.render_encoder_draw_primitives($0, UInt64(type), UInt32(vertexStart), UInt32(vertexCount),
                                                   UInt32(instanceCount), UInt32(baseInstance), $1)
        }
    }

    @ObjCMethod("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:")
    func drawIndexed(_ type: UInt, indexCount: UInt, indexType: UInt, indexBuffer: MTLBuffer?, indexBufferOffset: UInt) {
        drawIndexed(type, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: indexBufferOffset, instanceCount: 1, baseVertex: 0, baseInstance: 0)
    }

    @ObjCMethod("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:")
    func drawIndexed(_ type: UInt, indexCount: UInt, indexType: UInt, indexBuffer: MTLBuffer?, indexBufferOffset: UInt,
                     instanceCount: UInt) {
        drawIndexed(type, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer,
                    indexBufferOffset: indexBufferOffset, instanceCount: instanceCount, baseVertex: 0, baseInstance: 0)
    }

    @ObjCMethod("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:")
    func drawIndexed(_ type: UInt, indexCount: UInt, indexType: UInt, indexBuffer: MTLBuffer?, indexBufferOffset: UInt,
                     instanceCount: UInt, baseVertex: Int, baseInstance: UInt) {
        guard let indexBuffer else { return }
        Trace.log("drawIndexedPrimitives", "type \(type) count \(indexCount)")
        keep(indexBuffer)
        encode("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:") {
            M2V.api.render_encoder_draw_indexed_primitives($0, UInt64(type), UInt32(indexCount), UInt32(indexType),
                                                           indexBuffer.handle, UInt64(indexBufferOffset),
                                                           UInt32(instanceCount), Int32(baseVertex), UInt32(baseInstance), $1)
        }
    }

    @ObjCMethod("drawPrimitives:indirectBuffer:indirectBufferOffset:")
    func draw(_ type: UInt, indirectBuffer: MTLBuffer?, indirectBufferOffset: UInt) {
        guard let indirectBuffer else { return }
        keep(indirectBuffer)
        encode("drawPrimitives:indirectBuffer:indirectBufferOffset:") {
            M2V.api.render_encoder_draw_primitives_indirect($0, UInt64(type), indirectBuffer.handle,
                                                            UInt64(indirectBufferOffset), $1)
        }
    }

    @ObjCMethod("drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:")
    func drawIndexed(_ type: UInt, indexType: UInt, indexBuffer: MTLBuffer?, indexBufferOffset: UInt,
                     indirectBuffer: MTLBuffer?, indirectBufferOffset: UInt) {
        guard let indexBuffer, let indirectBuffer else { return }
        keep(indexBuffer)
        keep(indirectBuffer)
        encode("drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:") {
            M2V.api.render_encoder_draw_indexed_primitives_indirect($0, UInt64(type), UInt32(indexType), indexBuffer.handle,
                                                                    UInt64(indexBufferOffset), indirectBuffer.handle,
                                                                    UInt64(indirectBufferOffset), $1)
        }
    }

    // MARK: Other

    @ObjCMethod("useResource:usage:") func useResource(_ resource: NSObject?, usage: UInt) {}
    @ObjCMethod("useResource:usage:stages:") func useResource(_ resource: NSObject?, usage: UInt, stages: UInt) {}
    @ObjCMethod("pushDebugGroup:") func pushDebugGroup(_ name: String?) {}
    // Fences order nothing here (Fences.swift).
    @ObjCMethod("updateFence:") func updateFence(_ fence: NSObject?) {}
    @ObjCMethod("waitForFence:") func waitForFence(_ fence: NSObject?) {}
    @ObjCMethod("updateFence:afterStages:") func updateFence(_ fence: NSObject?, afterStages stages: UInt) {}
    @ObjCMethod("waitForFence:beforeStages:") func waitForFence(_ fence: NSObject?, beforeStages stages: UInt) {}
    @ObjCMethod("popDebugGroup") func popDebugGroup() {}
    @ObjCMethod("insertDebugSignpost:") func insertDebugSignpost(_ name: String?) {}

    @ObjCMethod("endEncoding") func endEncoding() {
        guard let ended = handle else { return }
        handle = nil
        let (_, message) = M2V.call { M2V.api.render_encoder_end(ended, $0) }
        if let message { metalWarning("-[MTLRenderCommandEncoder endEncoding]: \(message)") }
    }
}

@ObjCClass("_MTLBlitCommandEncoder")
open class MTLBlitCommandEncoder: NSObject, MTLBlitCommandEncoderProtocol {
    var handle: perry_m2v_handle?
    var commandBuffer: MTLCommandBuffer?
    var label: String?

    init(handle: perry_m2v_handle, commandBuffer: MTLCommandBuffer) {
        self.handle = handle
        self.commandBuffer = commandBuffer
        super.init()
    }

    deinit {
        if let handle { M2V.api.blit_encoder_release(handle) }
    }

    private func encode(_ selector: String, _ objects: [NSObject?], _ body: (perry_m2v_handle, perry_m2v_error) -> Bool) {
        guard let handle else {
            metalWarning("-[MTLBlitCommandEncoder \(selector)] after endEncoding")
            return
        }
        for object in objects { if let object { commandBuffer?.keep(object) } }
        let (_, message) = M2V.call { body(handle, $0) }
        if let message { metalWarning("-[MTLBlitCommandEncoder \(selector)]: \(message)") }
    }

    @ObjCMethod("device") func device() -> MTLDevice? { commandBuffer?.device() }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }

    @ObjCMethod("copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:")
    func copy(from source: MTLBuffer?, sourceOffset: UInt, to destination: MTLBuffer?, destinationOffset: UInt, size: UInt) {
        guard let source, let destination else { return }
        encode("copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:", [source, destination]) {
            M2V.api.blit_encoder_copy_buffer_to_buffer($0, source.handle, UInt64(sourceOffset), destination.handle,
                                                       UInt64(destinationOffset), UInt64(size), $1)
        }
    }

    @ObjCMethod("copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:")
    func copy(from source: MTLBuffer?, sourceOffset: UInt, sourceBytesPerRow: UInt, sourceBytesPerImage: UInt, sourceSize: MTLSize,
              to texture: MTLTexture?, destinationSlice: UInt, destinationLevel: UInt, destinationOrigin: MTLOrigin) {
        copy(from: source, sourceOffset: sourceOffset, sourceBytesPerRow: sourceBytesPerRow, sourceBytesPerImage: sourceBytesPerImage,
             sourceSize: sourceSize, to: texture, destinationSlice: destinationSlice, destinationLevel: destinationLevel,
             destinationOrigin: destinationOrigin, options: 0)
    }

    @ObjCMethod("copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:options:")
    func copy(from source: MTLBuffer?, sourceOffset: UInt, sourceBytesPerRow: UInt, sourceBytesPerImage: UInt, sourceSize: MTLSize,
              to texture: MTLTexture?, destinationSlice: UInt, destinationLevel: UInt, destinationOrigin: MTLOrigin, options: UInt) {
        guard let source, let texture else { return }
        Trace.log("copyBufferToTexture", "+\(sourceOffset) \(sourceBytesPerRow)/row \(sourceSize.width)×\(sourceSize.height) to \(destinationOrigin.x),\(destinationOrigin.y) level \(destinationLevel) of \(texture.descriptor.width)×\(texture.descriptor.height) f\(texture.descriptor.pixel_format)")
        encode("copyFromBuffer:…toTexture:", [source, texture]) {
            M2V.api.blit_encoder_copy_buffer_to_texture($0, source.handle, UInt64(sourceOffset), UInt64(sourceBytesPerRow),
                                                        UInt64(sourceBytesPerImage), sourceSize, texture.handle,
                                                        UInt64(destinationSlice), UInt64(destinationLevel), destinationOrigin,
                                                        UInt64(options), $1)
        }
    }

    @ObjCMethod("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:")
    func copy(from texture: MTLTexture?, sourceSlice: UInt, sourceLevel: UInt, sourceOrigin: MTLOrigin, sourceSize: MTLSize,
              to buffer: MTLBuffer?, destinationOffset: UInt, destinationBytesPerRow: UInt, destinationBytesPerImage: UInt) {
        guard let texture, let buffer else { return }
        encode("copyFromTexture:…toBuffer:", [texture, buffer]) {
            M2V.api.blit_encoder_copy_texture_to_buffer($0, texture.handle, UInt64(sourceSlice), UInt64(sourceLevel), sourceOrigin,
                                                        sourceSize, buffer.handle, UInt64(destinationOffset),
                                                        UInt64(destinationBytesPerRow), UInt64(destinationBytesPerImage), 0, $1)
        }
    }

    @ObjCMethod("copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:")
    func copy(from source: MTLTexture?, sourceSlice: UInt, sourceLevel: UInt, sourceOrigin: MTLOrigin, sourceSize: MTLSize,
              to destination: MTLTexture?, destinationSlice: UInt, destinationLevel: UInt, destinationOrigin: MTLOrigin) {
        guard let source, let destination else { return }
        Trace.log("copyTextureToTexture", "\(sourceOrigin.x),\(sourceOrigin.y) \(sourceSize.width)×\(sourceSize.height) level \(sourceLevel) of \(source.descriptor.width)×\(source.descriptor.height) to \(destinationOrigin.x),\(destinationOrigin.y) level \(destinationLevel) of \(destination.descriptor.width)×\(destination.descriptor.height) mips \(destination.descriptor.mipmap_level_count)")
        encode("copyFromTexture:…toTexture:", [source, destination]) {
            M2V.api.blit_encoder_copy_texture_to_texture($0, source.handle, UInt64(sourceSlice), UInt64(sourceLevel), sourceOrigin,
                                                         sourceSize, destination.handle, UInt64(destinationSlice),
                                                         UInt64(destinationLevel), destinationOrigin, $1)
        }
    }

    @ObjCMethod("generateMipmapsForTexture:") func generateMipmaps(for texture: MTLTexture?) {
        guard let texture else { return }
        Trace.log("generateMipmaps", "\(texture.descriptor.width)×\(texture.descriptor.height) f\(texture.descriptor.pixel_format) mips \(texture.descriptor.mipmap_level_count) usage \(texture.descriptor.usage)")
        encode("generateMipmapsForTexture:", [texture]) { M2V.api.blit_encoder_generate_mipmaps($0, texture.handle, $1) }
    }

    @ObjCMethod("fillBuffer:range:value:") func fill(_ buffer: MTLBuffer?, range: PerryRange, value: UInt8) {
        guard let buffer else { return }
        encode("fillBuffer:range:value:", [buffer]) {
            M2V.api.blit_encoder_fill_buffer($0, buffer.handle, UInt64(range.location), UInt64(range.length), value, $1)
        }
    }

    @ObjCMethod("synchronizeResource:") func synchronize(_ resource: NSObject?) {
        guard let resource else { return }
        let buffer = resource.as(MTLBuffer.self), texture = resource.as(MTLTexture.self)
        encode("synchronizeResource:", [resource]) {
            M2V.api.blit_encoder_synchronize_resource($0, buffer?.handle, texture?.handle, $1)
        }
    }

    @ObjCMethod("optimizeContentsForGPUAccess:") func optimizeContentsForGPUAccess(_ texture: NSObject?) {}
    @ObjCMethod("pushDebugGroup:") func pushDebugGroup(_ name: String?) {}
    // Fences order nothing here (Fences.swift).
    @ObjCMethod("updateFence:") func updateFence(_ fence: NSObject?) {}
    @ObjCMethod("waitForFence:") func waitForFence(_ fence: NSObject?) {}
    @ObjCMethod("popDebugGroup") func popDebugGroup() {}

    @ObjCMethod("endEncoding") func endEncoding() {
        guard let ended = handle else { return }
        handle = nil
        let (_, message) = M2V.call { M2V.api.blit_encoder_end(ended, $0) }
        if let message { metalWarning("-[MTLBlitCommandEncoder endEncoding]: \(message)") }
    }
}
