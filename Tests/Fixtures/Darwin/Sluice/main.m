// CFFileDescriptor and CFMachPort on the run loop, built on a Mac with
// Xcode: a pipe's read and write callbacks, each called once until enabled
// again, and a port's messages, received on the loop.
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <unistd.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static int callouts;

static void descriptorCallout(CFFileDescriptorRef descriptor, CFOptionFlags types, void *info) {
    callouts += 1;
    print([NSString stringWithFormat:@"descriptor callout types %lu info %s", (unsigned long)types, (const char *)info]);
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static void portCallout(CFMachPortRef port, void *message, CFIndex size, void *info) {
    mach_msg_header_t *header = message;
    int body = *(int *)((char *)message + sizeof(mach_msg_header_t));
    print([NSString stringWithFormat:@"port callout id %d size %ld body %d info %s", header->msgh_id, (long)size, body, (const char *)info]);
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static void portInvalidated(CFMachPortRef port, void *info) {
    print([NSString stringWithFormat:@"port invalidated %s", (const char *)info]);
}

static const char *result(SInt32 code) {
    switch (code) {
    case kCFRunLoopRunFinished: return "finished";
    case kCFRunLoopRunStopped: return "stopped";
    case kCFRunLoopRunTimedOut: return "timed out";
    case kCFRunLoopRunHandledSource: return "handled";
    default: return "?";
    }
}

static void descriptors(void) {
    int pipes[2];
    pipe(pipes);
    CFFileDescriptorContext context = {0, "pipe", NULL, NULL, NULL};
    CFFileDescriptorRef reader = CFFileDescriptorCreate(NULL, pipes[0], true, descriptorCallout, &context);
    print([NSString stringWithFormat:@"descriptor type %d valid %d native %d", CFGetTypeID(reader) == CFFileDescriptorGetTypeID(),
           CFFileDescriptorIsValid(reader), CFFileDescriptorGetNativeDescriptor(reader) == pipes[0]]);
    CFRunLoopSourceRef source = CFFileDescriptorCreateRunLoopSource(NULL, reader, 0);
    CFRunLoopSourceRef again = CFFileDescriptorCreateRunLoopSource(NULL, reader, 0);
    print([NSString stringWithFormat:@"one source %d valid %d", source == again, CFRunLoopSourceIsValid(source)]);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);

    // Nothing to read, and nothing enabled: the loop waits it out.
    print([NSString stringWithFormat:@"idle %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false))]);
    CFFileDescriptorEnableCallBacks(reader, kCFFileDescriptorReadCallBack);
    print([NSString stringWithFormat:@"enabled, empty %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false))]);
    write(pipes[1], "x", 1);
    print([NSString stringWithFormat:@"written %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false))]);
    // Still readable, but called once until enabled again.
    print([NSString stringWithFormat:@"not enabled again %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false))]);
    CFFileDescriptorEnableCallBacks(reader, kCFFileDescriptorReadCallBack);
    print([NSString stringWithFormat:@"enabled again %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false))]);

    char byte;
    read(pipes[0], &byte, 1);
    CFFileDescriptorEnableCallBacks(reader, kCFFileDescriptorReadCallBack);
    CFFileDescriptorDisableCallBacks(reader, kCFFileDescriptorReadCallBack);
    write(pipes[1], "y", 1);
    print([NSString stringWithFormat:@"disabled %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false))]);

    CFFileDescriptorContext got;
    CFFileDescriptorGetContext(reader, &got);
    print([NSString stringWithFormat:@"context %s", (const char *)got.info]);
    CFFileDescriptorInvalidate(reader);
    print([NSString stringWithFormat:@"invalidated valid %d closed %d native %d source valid %d", CFFileDescriptorIsValid(reader),
           fcntl(pipes[0], F_GETFD) == -1, CFFileDescriptorGetNativeDescriptor(reader), CFRunLoopSourceIsValid(source)]);
    CFRelease(source);
    CFRelease(again);
    CFRelease(reader);

    CFFileDescriptorRef writer = CFFileDescriptorCreate(NULL, pipes[1], false, descriptorCallout, &context);
    CFRunLoopSourceRef writing = CFFileDescriptorCreateRunLoopSource(NULL, writer, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), writing, kCFRunLoopDefaultMode);
    CFFileDescriptorEnableCallBacks(writer, kCFFileDescriptorWriteCallBack);
    print([NSString stringWithFormat:@"writable %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false))]);
    CFFileDescriptorInvalidate(writer);
    print([NSString stringWithFormat:@"kept open %d callouts %d", fcntl(pipes[1], F_GETFD) != -1, callouts]);
    CFRelease(writing);
    CFRelease(writer);
    close(pipes[1]);
}

static void ports(void) {
    CFMachPortContext context = {0, "port", NULL, NULL, NULL};
    Boolean shouldFree = 7;
    CFMachPortRef port = CFMachPortCreate(NULL, portCallout, &context, &shouldFree);
    print([NSString stringWithFormat:@"port type %d has port %d free %d valid %d", CFGetTypeID(port) == CFMachPortGetTypeID(),
           CFMachPortGetPort(port) != MACH_PORT_NULL, shouldFree, CFMachPortIsValid(port)]);
    Boolean shouldFreeAgain = 7;
    CFMachPortRef same = CFMachPortCreateWithPort(NULL, CFMachPortGetPort(port), portCallout, &context, &shouldFreeAgain);
    print([NSString stringWithFormat:@"same port %d free %d", same == port, shouldFreeAgain]);
    CFRelease(same);
    CFMachPortSetInvalidationCallBack(port, portInvalidated);
    print([NSString stringWithFormat:@"invalidation set %d", CFMachPortGetInvalidationCallBack(port) == portInvalidated]);

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, port, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    struct { mach_msg_header_t header; int body; } message = {0};
    message.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MAKE_SEND, 0);
    message.header.msgh_size = sizeof message;
    message.header.msgh_remote_port = CFMachPortGetPort(port);
    message.header.msgh_id = 42;
    message.body = 7;
    kern_return_t sent = mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof message, 0, MACH_PORT_NULL, 100, MACH_PORT_NULL);
    print([NSString stringWithFormat:@"sent %d", sent]);
    print([NSString stringWithFormat:@"received %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false))]);
    message.header.msgh_id = 43;
    message.body = 8;
    mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof message, 0, MACH_PORT_NULL, 100, MACH_PORT_NULL);
    print([NSString stringWithFormat:@"received again %s", result(CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false))]);

    CFMachPortContext got;
    CFMachPortGetContext(port, &got);
    print([NSString stringWithFormat:@"context %s", (const char *)got.info]);
    CFMachPortInvalidate(port);
    print([NSString stringWithFormat:@"invalidated valid %d source valid %d", CFMachPortIsValid(port), CFRunLoopSourceIsValid(source)]);
    CFRelease(source);
    CFRelease(port);
}

int main(void) {
    @autoreleasepool {
        descriptors();
        ports();
    }
    return 0;
}
