#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#include <assert.h>
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        assert(app);
        io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("IOPlatformExpertDevice"));
        assert(service);
        CFTypeRef uuid = IORegistryEntryCreateCFProperty(service, CFSTR("IOPlatformUUID"), 0, 0);
        assert(uuid);
        CFRelease(uuid); IOObjectRelease(service);
        puts("AppKit initialization and IOKit identity passed");
    }
    return 0;
}
