// The return addresses of the calling frames, by their frame records, for
// reports of uncaught exceptions: Darwin's arm64 code keeps
// {previous fp, return address} records in x29 as Linux's does, so the
// walk goes through an app's Mach-O frames, which have no unwind tables
// glibc's backtrace() could use.

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#include "CPerryFoundation.h"

size_t perry_frame_return_addresses(uintptr_t *addresses, size_t capacity) {
#if defined(__aarch64__)
    uintptr_t fp = (uintptr_t)__builtin_frame_address(0), low = fp;
    size_t count = 0;
    while (count < capacity && fp && (fp & 7) == 0 && fp >= low && fp - low < (64 << 20)) {
        uintptr_t *record = (uintptr_t *)fp;
        if (!record[1])
            break;
        addresses[count++] = record[1];
        low = fp;
        fp = record[0];
    }
    return count;
#else
    (void)addresses;
    (void)capacity;
    return 0;
#endif
}

void perry_describe_address(uintptr_t address, char *line, size_t capacity) {
    Dl_info info;
    if (address && dladdr((void *)address, &info) && info.dli_fname) {
        const char *name = strrchr(info.dli_fname, '/');
        name = name ? name + 1 : info.dli_fname;
        if (info.dli_sname)
            snprintf(line, capacity, "0x%016lx %s(%s+0x%lx)", (unsigned long)address, name, info.dli_sname,
                     (unsigned long)(address - (uintptr_t)info.dli_saddr));
        else
            snprintf(line, capacity, "0x%016lx %s+0x%lx", (unsigned long)address, name,
                     (unsigned long)(address - (uintptr_t)info.dli_fbase));
        return;
    }
    snprintf(line, capacity, "0x%016lx", (unsigned long)address);
}
