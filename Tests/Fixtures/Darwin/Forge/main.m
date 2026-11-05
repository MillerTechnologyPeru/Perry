// Metal's compute path: the app's default library and one loaded from
// dispatch data, functions and compute pipeline states, shared buffers,
// command queues and buffers, and compute encoders that bind buffers, bytes
// and threadgroup memory and dispatch by threads and by threadgroups. The
// results are integers or sums of floats that every GPU computes exactly.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *yes(BOOL value) { return value ? @"yes" : @"no"; }

static NSString *statusName(MTLCommandBufferStatus status) {
    switch (status) {
    case MTLCommandBufferStatusNotEnqueued: return @"not enqueued";
    case MTLCommandBufferStatusEnqueued: return @"enqueued";
    case MTLCommandBufferStatusCommitted: return @"committed";
    case MTLCommandBufferStatusScheduled: return @"scheduled";
    case MTLCommandBufferStatusCompleted: return @"completed";
    case MTLCommandBufferStatusError: return @"error";
    }
    return @"?";
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            say(@"no device");
            return 1;
        }

        // Libraries and functions.
        id<MTLLibrary> library = [device newDefaultLibrary];
        say([NSString stringWithFormat:@"default library: %@", yes(library != nil)]);
        NSArray<NSString *> *names = [library.functionNames sortedArrayUsingSelector:@selector(compare:)];
        say([NSString stringWithFormat:@"functions: %@", [names componentsJoinedByString:@", "]]);
        id<MTLFunction> add = [library newFunctionWithName:@"add_arrays"];
        say([NSString stringWithFormat:@"add_arrays: %@, kernel: %@", add.name,
             yes(add.functionType == MTLFunctionTypeKernel)]);
        say([NSString stringWithFormat:@"missing function: %@", yes([library newFunctionWithName:@"missing"] == nil)]);

        NSString *path = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"metallib"];
        NSData *bytes = [NSData dataWithContentsOfFile:path];
        dispatch_data_t data = dispatch_data_create(bytes.bytes, bytes.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        NSError *error = nil;
        id<MTLLibrary> fromData = [device newLibraryWithData:data error:&error];
        say([NSString stringWithFormat:@"library from data: %@, error: %@", yes(fromData != nil), yes(error != nil)]);

        uint8_t garbage[64] = {1, 2, 3};
        error = nil;
        id<MTLLibrary> invalid = [device newLibraryWithData:dispatch_data_create(garbage, sizeof garbage, nil,
                                                                                 DISPATCH_DATA_DESTRUCTOR_DEFAULT)
                                                      error:&error];
        say([NSString stringWithFormat:@"invalid library: %@, error: %@, domain: %@", yes(invalid == nil),
             yes(error != nil), error.domain]);

        // Pipelines.
        error = nil;
        id<MTLComputePipelineState> addState = [device newComputePipelineStateWithFunction:add error:&error];
        say([NSString stringWithFormat:@"pipeline: %@, error: %@", yes(addState != nil), yes(error != nil)]);
        say([NSString stringWithFormat:@"threads per threadgroup at least 64: %@",
             yes(addState.maxTotalThreadsPerThreadgroup >= 64)]);
        say([NSString stringWithFormat:@"execution width: %@", yes(addState.threadExecutionWidth > 0)]);
        id<MTLComputePipelineState> scaleState =
            [device newComputePipelineStateWithFunction:[fromData newFunctionWithName:@"scale"] error:nil];
        id<MTLComputePipelineState> sumState =
            [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"sum_groups"] error:nil];

        // Buffers.
        const NSUInteger count = 4096;
        id<MTLBuffer> a = [device newBufferWithLength:count * sizeof(float) options:MTLResourceStorageModeShared];
        float *values = a.contents;
        for (NSUInteger i = 0; i < count; i++) values[i] = (float)i;
        float bValues[4096];
        for (NSUInteger i = 0; i < count; i++) bValues[i] = (float)(2 * i + 1);
        id<MTLBuffer> b = [device newBufferWithBytes:bValues length:sizeof bValues options:MTLResourceStorageModeShared];
        id<MTLBuffer> result = [device newBufferWithLength:count * sizeof(float) options:MTLResourceStorageModeShared];
        say([NSString stringWithFormat:@"buffer length: %lu, shared: %@", (unsigned long)b.length,
             yes(b.storageMode == MTLStorageModeShared)]);
        say([NSString stringWithFormat:@"copied bytes: %@", yes(((float *)b.contents)[4095] == 8191.0f)]);

        // One command buffer, two encoders: add, then scale the sums by 0.5.
        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> commands = [queue commandBuffer];
        say([NSString stringWithFormat:@"before commit: %@", statusName(commands.status)]);
        __block BOOL completed = NO;
        __block id<MTLCommandBuffer> completedBuffer = nil;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [commands addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
            completed = YES;
            completedBuffer = buffer;
            dispatch_semaphore_signal(done);
        }];

        id<MTLComputeCommandEncoder> encoder = [commands computeCommandEncoder];
        [encoder setComputePipelineState:addState];
        [encoder setBuffer:a offset:0 atIndex:0];
        [encoder setBuffer:b offset:0 atIndex:1];
        [encoder setBuffer:result offset:0 atIndex:2];
        [encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
        [encoder endEncoding];

        encoder = [commands computeCommandEncoder];
        [encoder setComputePipelineState:scaleState];
        [encoder setBuffer:result offset:0 atIndex:0];
        float factor = 0.5f;
        [encoder setBytes:&factor length:sizeof factor atIndex:1];
        [encoder dispatchThreadgroups:MTLSizeMake(count / 32, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
        [encoder endEncoding];

        [commands commit];
        [commands waitUntilCompleted];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        say([NSString stringWithFormat:@"after wait: %@, error: %@", statusName(commands.status),
             yes(commands.error != nil)]);
        say([NSString stringWithFormat:@"completed handler: %@, with the buffer: %@", yes(completed),
             yes(completedBuffer == commands)]);

        // (i + 2i + 1) / 2, exact in floats.
        const float *sums = result.contents;
        NSUInteger wrong = 0;
        for (NSUInteger i = 0; i < count; i++)
            if (sums[i] != (float)(3 * i + 1) * 0.5f) wrong++;
        say([NSString stringWithFormat:@"results wrong: %lu of %lu", (unsigned long)wrong, (unsigned long)count]);
        say([NSString stringWithFormat:@"result[0], [1], [4095]: %g, %g, %g", sums[0], sums[1], sums[4095]]);

        // Threadgroup memory: the sums of 16 groups of 256.
        const NSUInteger group = 256, groups = 16;
        id<MTLBuffer> input = [device newBufferWithLength:group * groups * sizeof(uint32_t)
                                                  options:MTLResourceStorageModeShared];
        uint32_t *numbers = input.contents;
        for (NSUInteger i = 0; i < group * groups; i++) numbers[i] = (uint32_t)i;
        id<MTLBuffer> groupSums = [device newBufferWithLength:groups * sizeof(uint32_t)
                                                      options:MTLResourceStorageModeShared];
        commands = [queue commandBuffer];
        encoder = [commands computeCommandEncoder];
        [encoder setComputePipelineState:sumState];
        [encoder setBuffer:input offset:0 atIndex:0];
        [encoder setBuffer:groupSums offset:0 atIndex:1];
        [encoder setThreadgroupMemoryLength:group * sizeof(uint32_t) atIndex:0];
        [encoder dispatchThreadgroups:MTLSizeMake(groups, 1, 1) threadsPerThreadgroup:MTLSizeMake(group, 1, 1)];
        [encoder endEncoding];
        [commands commit];
        [commands waitUntilCompleted];
        const uint32_t *got = groupSums.contents;
        NSMutableArray<NSString *> *line = [NSMutableArray array];
        for (NSUInteger g = 0; g < 4; g++) [line addObject:[NSString stringWithFormat:@"%u", got[g]]];
        say([NSString stringWithFormat:@"group sums: %@, ... %u", [line componentsJoinedByString:@", "], got[15]]);
    }
    return 0;
}
