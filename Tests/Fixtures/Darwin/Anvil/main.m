// Metal's render path, offscreen: a render pipeline with a vertex
// descriptor, a depth-tested pass that clears colour and depth, triangles
// drawn from a vertex buffer and a textured quad drawn from the vertex ID
// with a sampler, a texture filled with replaceRegion:, and the result read
// back with getBytes: and with a blit into a buffer. Pixels are checked well
// inside each shape, where every GPU agrees.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *yes(BOOL value) { return value ? @"yes" : @"no"; }

#define size ((NSUInteger)64)

static NSString *pixel(const uint8_t *rows, NSUInteger x, NSUInteger y) {
    const uint8_t *p = rows + (y * size + x) * 4;
    return [NSString stringWithFormat:@"%02x%02x%02x%02x", p[2], p[1], p[0], p[3]];
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        id<MTLLibrary> library = [device newDefaultLibrary];

        MTLVertexDescriptor *layout = [MTLVertexDescriptor vertexDescriptor];
        layout.attributes[0].format = MTLVertexFormatFloat3;
        layout.attributes[0].offset = 0;
        layout.attributes[0].bufferIndex = 0;
        layout.attributes[1].format = MTLVertexFormatUChar4Normalized;
        layout.attributes[1].offset = 12;
        layout.attributes[1].bufferIndex = 0;
        layout.layouts[0].stride = 16;

        MTLRenderPipelineDescriptor *solid = [MTLRenderPipelineDescriptor new];
        solid.vertexFunction = [library newFunctionWithName:@"solid_vertex"];
        solid.fragmentFunction = [library newFunctionWithName:@"solid_fragment"];
        solid.vertexDescriptor = layout;
        solid.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        solid.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        NSError *error = nil;
        id<MTLRenderPipelineState> solidState = [device newRenderPipelineStateWithDescriptor:solid error:&error];
        say([NSString stringWithFormat:@"solid pipeline: %@, error: %@", yes(solidState != nil), yes(error != nil)]);

        MTLRenderPipelineDescriptor *quad = [MTLRenderPipelineDescriptor new];
        quad.vertexFunction = [library newFunctionWithName:@"quad_vertex"];
        quad.fragmentFunction = [library newFunctionWithName:@"quad_fragment"];
        quad.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        quad.colorAttachments[0].blendingEnabled = YES;
        quad.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        quad.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        quad.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> quadState = [device newRenderPipelineStateWithDescriptor:quad error:&error];
        say([NSString stringWithFormat:@"quad pipeline: %@", yes(quadState != nil)]);

        // Two triangles over the left half: red in front (z 0.2), green
        // behind (z 0.8) and drawn after, hidden by the depth test.
        struct { float x, y, z; uint8_t r, g, b, a; } vertices[] = {
            {-1, -1, 0.2, 255, 0, 0, 255}, {0, -1, 0.2, 255, 0, 0, 255}, {-1, 1, 0.2, 255, 0, 0, 255},
            {-1, -1, 0.8, 0, 255, 0, 255}, {0, -1, 0.8, 0, 255, 0, 255}, {-1, 1, 0.8, 0, 255, 0, 255},
        };
        id<MTLBuffer> vertexBuffer = [device newBufferWithBytes:vertices length:sizeof vertices
                                                        options:MTLResourceStorageModeShared];

        // A 2×2 texture: white, yellow / cyan, magenta (BGRA).
        MTLTextureDescriptor *imageDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:2 height:2 mipmapped:NO];
        id<MTLTexture> image = [device newTextureWithDescriptor:imageDescriptor];
        uint8_t texels[] = {255, 255, 255, 255, 0, 255, 255, 255, 255, 255, 0, 255, 255, 0, 255, 255};
        [image replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:texels bytesPerRow:8];
        say([NSString stringWithFormat:@"texture: %lux%lu, format %lu", (unsigned long)image.width,
             (unsigned long)image.height, (unsigned long)image.pixelFormat]);
        MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
        id<MTLSamplerState> nearest = [device newSamplerStateWithDescriptor:samplerDescriptor];

        MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
        depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        depthDescriptor.depthWriteEnabled = YES;
        id<MTLDepthStencilState> depthState = [device newDepthStencilStateWithDescriptor:depthDescriptor];
        say([NSString stringWithFormat:@"sampler and depth state: %@", yes(nearest && depthState)]);

        MTLTextureDescriptor *targetDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:size height:size mipmapped:NO];
        targetDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        id<MTLTexture> target = [device newTextureWithDescriptor:targetDescriptor];
        MTLTextureDescriptor *depthTargetDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:size height:size mipmapped:NO];
        depthTargetDescriptor.usage = MTLTextureUsageRenderTarget;
        depthTargetDescriptor.storageMode = MTLStorageModePrivate;
        id<MTLTexture> depthTarget = [device newTextureWithDescriptor:depthTargetDescriptor];

        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = target;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);
        pass.depthAttachment.texture = depthTarget;
        pass.depthAttachment.clearDepth = 1.0;

        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> commands = [queue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
        [encoder setViewport:(MTLViewport){0, 0, size, size, 0, 1}];
        [encoder setDepthStencilState:depthState];
        [encoder setRenderPipelineState:solidState];
        [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:3 vertexCount:3];
        // The textured quad over the right half's top, its corners'
        // texels in its four quarters.
        [encoder setRenderPipelineState:quadState];
        float rect[4] = {0.25, 0.0, 0.75, 1.0};
        [encoder setVertexBytes:rect length:sizeof rect atIndex:0];
        [encoder setFragmentTexture:image atIndex:0];
        [encoder setFragmentSamplerState:nearest atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [encoder endEncoding];

        id<MTLBuffer> readback = [device newBufferWithLength:size * size * 4 options:MTLResourceStorageModeShared];
        id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
        [blit copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(size, size, 1) toBuffer:readback destinationOffset:0
       destinationBytesPerRow:size * 4 destinationBytesPerImage:size * size * 4];
        [blit endEncoding];
        [commands commit];
        [commands waitUntilCompleted];
        say([NSString stringWithFormat:@"status: %lu, error: %@", (unsigned long)commands.status, yes(commands.error != nil)]);

        uint8_t rows[size * size * 4];
        [target getBytes:rows bytesPerRow:size * 4 fromRegion:MTLRegionMake2D(0, 0, size, size) mipmapLevel:0];
        // Rows top first: the triangle's lower left, the clear colour at the
        // lower right, and the quad's four quarters.
        say([NSString stringWithFormat:@"triangle: %@", pixel(rows, 4, 56)]);
        say([NSString stringWithFormat:@"clear: %@", pixel(rows, 56, 56)]);
        say([NSString stringWithFormat:@"quad: %@ %@ / %@ %@", pixel(rows, 44, 4), pixel(rows, 52, 4), pixel(rows, 44, 28),
             pixel(rows, 52, 28)]);
        say([NSString stringWithFormat:@"blit matches getBytes: %@", yes(memcmp(readback.contents, rows, sizeof rows) == 0)]);
    }
    return 0;
}
