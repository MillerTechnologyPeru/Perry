// Metal's devices: the system default device, the list of all devices, and
// the properties every GPU answers the same way in kind. Names, sizes and
// limits differ by GPU, so only their shape is printed.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>

// MTLCopyAllDevices and recommendedMaxWorkingSetSize are newer than the
// fixtures' iOS 15; Perry has them at any version.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *yes(BOOL value) { return value ? @"yes" : @"no"; }

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        say([NSString stringWithFormat:@"device: %@", yes(device != nil)]);
        if (!device) return 1;
        say([NSString stringWithFormat:@"conforms to MTLDevice: %@",
             yes([device conformsToProtocol:@protocol(MTLDevice)])]);
        say([NSString stringWithFormat:@"same device again: %@", yes(MTLCreateSystemDefaultDevice() == device)]);
        say([NSString stringWithFormat:@"has a name: %@", yes(device.name.length > 0)]);
        say([NSString stringWithFormat:@"has a registry ID: %@", yes(device.registryID != 0)]);

        MTLSize threads = device.maxThreadsPerThreadgroup;
        say([NSString stringWithFormat:@"threads per threadgroup at least 256: %@",
             yes(threads.width >= 256 && threads.height >= 1 && threads.depth >= 1)]);
        say([NSString stringWithFormat:@"threadgroup memory at least 16 KB: %@",
             yes(device.maxThreadgroupMemoryLength >= 16384)]);
        say([NSString stringWithFormat:@"buffers of 64 MB: %@", yes(device.maxBufferLength >= 64u << 20)]);
        say([NSString stringWithFormat:@"working set at least 64 MB: %@",
             yes(device.recommendedMaxWorkingSetSize >= 64u << 20)]);

        say([NSString stringWithFormat:@"Apple1: %@", yes([device supportsFamily:MTLGPUFamilyApple1])]);
        say([NSString stringWithFormat:@"Common1: %@", yes([device supportsFamily:MTLGPUFamilyCommon1])]);
        say([NSString stringWithFormat:@"1 sample: %@", yes([device supportsTextureSampleCount:1])]);
        say([NSString stringWithFormat:@"4 samples: %@", yes([device supportsTextureSampleCount:4])]);
        say([NSString stringWithFormat:@"3 samples: %@", yes([device supportsTextureSampleCount:3])]);

        NSArray<id<MTLDevice>> *all = MTLCopyAllDevices();
        say([NSString stringWithFormat:@"all devices include it: %@", yes([all containsObject:device])]);
    }
    return 0;
}
