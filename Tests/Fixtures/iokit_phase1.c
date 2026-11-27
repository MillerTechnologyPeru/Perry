#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <stdio.h>
#include <unistd.h>
#include <assert.h>
int main(void) {
    io_service_t platform = IOServiceGetMatchingService(0, IOServiceMatching("IOPlatformExpertDevice"));
    assert(platform);
    CFTypeRef uuid = IORegistryEntryCreateCFProperty(platform, CFSTR("IOPlatformUUID"), 0, 0);
    assert(uuid && CFGetTypeID(uuid) == CFStringGetTypeID());
    char text[128]; assert(CFStringGetCString(uuid, text, sizeof(text), kCFStringEncodingUTF8));
    printf("IOPlatformUUID=%s\n", text); CFRelease(uuid);
    CFTypeRef model = IORegistryEntryCreateCFProperty(platform, CFSTR("model"), 0, 0);
    assert(model && CFGetTypeID(model) == CFDataGetTypeID());
    printf("model=%s\n", CFDataGetBytePtr(model)); CFRelease(model);
    io_service_t net = IOServiceGetMatchingService(0, IOBSDNameMatching(0, 0, "en0"));
    assert(net);
    CFDataRef mac = IORegistryEntryCreateCFProperty(net, CFSTR("IOMACAddress"), 0, 0);
    assert(mac && CFDataGetLength(mac) == 6);
    const UInt8 *b = CFDataGetBytePtr(mac);
    printf("en0 MAC=%02x:%02x:%02x:%02x:%02x:%02x\n",b[0],b[1],b[2],b[3],b[4],b[5]); CFRelease(mac);
    CFTypeRef info = IOPSCopyPowerSourcesInfo(); assert(info);
    CFArrayRef list = IOPSCopyPowerSourcesList(info); assert(list);
    printf("power sources=%ld\n", CFArrayGetCount(list));
    for(CFIndex i=0;i<CFArrayGetCount(list);i++) assert(IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list,i)));
    CFRelease(list); CFRelease(info);
    IOPMAssertionID assertion = 0;
    assert(IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn, CFSTR("Perry Phase 1 smoke test"), &assertion) == 0);
    printf("assertion=%u\n", assertion); fflush(stdout);
    sleep(8);
    assert(IOPMAssertionRelease(assertion) == 0);
    IOObjectRelease(net); IOObjectRelease(platform);
    puts("IOKit Phase 1 ABI smoke test passed"); fflush(stdout); sleep(4);
    return 0;
}
