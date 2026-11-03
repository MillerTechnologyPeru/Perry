// Darwin libdispatch's exported data. The headers' macros take the address
// of these: dispatch_get_main_queue() is &_dispatch_main_q, and
// DISPATCH_QUEUE_CONCURRENT and DISPATCH_SOURCE_TYPE_TIMER are likewise
// addresses. The static objects get their classes at startup.

#define _GNU_SOURCE
#include "CPerryDispatch.h"

#define DARWIN_DATA(name) __asm__("_" #name) __attribute__((visibility("default"), used))
#define EXPORTED __attribute__((visibility("default"), used))

// The header gives these their Darwin names.
EXPORTED perry_dispatch_static_object perry_dispatch_main_q;
EXPORTED perry_dispatch_static_object perry_dispatch_queue_attr_concurrent;
EXPORTED perry_dispatch_static_object perry_dispatch_data_empty;

// MARK: - Source types

typedef struct source_type {
    int kind;
} source_type;

#define SOURCE_TYPE(name, value) \
    const source_type darwin_dispatch_source_type_##name DARWIN_DATA(_dispatch_source_type_##name) = {value}

SOURCE_TYPE(data_add, PERRY_SOURCE_DATA_ADD);
SOURCE_TYPE(data_or, PERRY_SOURCE_DATA_OR);
SOURCE_TYPE(data_replace, PERRY_SOURCE_DATA_REPLACE);
SOURCE_TYPE(mach_send, PERRY_SOURCE_MACH_SEND);
SOURCE_TYPE(mach_recv, PERRY_SOURCE_MACH_RECV);
SOURCE_TYPE(memorypressure, PERRY_SOURCE_MEMORYPRESSURE);
SOURCE_TYPE(proc, PERRY_SOURCE_PROC);
SOURCE_TYPE(read, PERRY_SOURCE_READ);
SOURCE_TYPE(signal, PERRY_SOURCE_SIGNAL);
SOURCE_TYPE(timer, PERRY_SOURCE_TIMER);
SOURCE_TYPE(vnode, PERRY_SOURCE_VNODE);
SOURCE_TYPE(write, PERRY_SOURCE_WRITE);

// Exclaves' notifications, which no device here has: a source of this
// type cannot be made.
SOURCE_TYPE(exclaves_notification, -1);

static const source_type *const source_types[PERRY_SOURCE_COUNT] = {
    &darwin_dispatch_source_type_data_add, &darwin_dispatch_source_type_data_or,
    &darwin_dispatch_source_type_data_replace, &darwin_dispatch_source_type_mach_send,
    &darwin_dispatch_source_type_mach_recv, &darwin_dispatch_source_type_memorypressure,
    &darwin_dispatch_source_type_proc, &darwin_dispatch_source_type_read,
    &darwin_dispatch_source_type_signal, &darwin_dispatch_source_type_timer,
    &darwin_dispatch_source_type_vnode, &darwin_dispatch_source_type_write,
};

int perry_dispatch_source_kind(const void *type) {
    for (int kind = 0; kind < PERRY_SOURCE_COUNT; kind++)
        if (source_types[kind] == type)
            return kind;
    return -1;
}

// MARK: - Data destructors

// Darwin declares these as blocks; callers pass their values.
static const char destructor_free_marker;
static const char destructor_munmap_marker;
EXPORTED const void *perry_dispatch_data_destructor_free = &destructor_free_marker;
EXPORTED const void *perry_dispatch_data_destructor_munmap = &destructor_munmap_marker;

// MARK: - Unified logging

EXPORTED perry_dispatch_static_object perry_os_log_default;
EXPORTED perry_dispatch_static_object perry_os_log_disabled;
EXPORTED perry_dispatch_static_object perry_os_activity_current;
EXPORTED perry_dispatch_static_object perry_os_activity_none;

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

const char *perry_dispatch_program_name(void) { return program_invocation_short_name; }
int perry_dispatch_thread_id(void) { return (int)gettid(); }

int perry_format_integer(char *buffer, unsigned long size, const char *spec, long long value) {
    return snprintf(buffer, size, spec, value);
}

int perry_format_double(char *buffer, unsigned long size, const char *spec, double value) {
    return snprintf(buffer, size, spec, value);
}
