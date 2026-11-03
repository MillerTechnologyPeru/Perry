#ifndef CPERRY_DISPATCH_H
#define CPERRY_DISPATCH_H

// Linux's libdispatch (swift-corelibs-libdispatch), which the Darwin API is
// built on. Swift hides its C API behind the Dispatch overlay, so the
// functions are declared here under other names, bound with asm labels to
// the library's own. Only the function-pointer (_f) variants are used:
// Darwin's blocks never reach Linux's blocks runtime. Objects are opaque.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

typedef void *linux_dispatch_object;
typedef uint64_t linux_dispatch_time_t;
typedef void (*linux_dispatch_function)(void *context);

#define LINUX_DISPATCH(name) __asm__(#name)

// Objects.
void linux_dispatch_retain(linux_dispatch_object object) LINUX_DISPATCH(dispatch_retain);
void linux_dispatch_release(linux_dispatch_object object) LINUX_DISPATCH(dispatch_release);
void linux_dispatch_suspend(linux_dispatch_object object) LINUX_DISPATCH(dispatch_suspend);
void linux_dispatch_resume(linux_dispatch_object object) LINUX_DISPATCH(dispatch_resume);
void linux_dispatch_activate(linux_dispatch_object object) LINUX_DISPATCH(dispatch_activate);
void linux_dispatch_set_context(linux_dispatch_object object, void *context) LINUX_DISPATCH(dispatch_set_context);
void *linux_dispatch_get_context(linux_dispatch_object object) LINUX_DISPATCH(dispatch_get_context);
void linux_dispatch_set_finalizer_f(linux_dispatch_object object, linux_dispatch_function finalizer)
    LINUX_DISPATCH(dispatch_set_finalizer_f);
void linux_dispatch_set_target_queue(linux_dispatch_object object, linux_dispatch_object queue)
    LINUX_DISPATCH(dispatch_set_target_queue);

// Queues.
linux_dispatch_object linux_dispatch_queue_create(const char *label, linux_dispatch_object attr)
    LINUX_DISPATCH(dispatch_queue_create);
linux_dispatch_object linux_dispatch_queue_create_with_target(const char *label, linux_dispatch_object attr,
                                                              linux_dispatch_object target)
    LINUX_DISPATCH(dispatch_queue_create_with_target);
linux_dispatch_object linux_dispatch_get_global_queue(intptr_t identifier, uintptr_t flags)
    LINUX_DISPATCH(dispatch_get_global_queue);
linux_dispatch_object linux_dispatch_get_current_queue(void) LINUX_DISPATCH(dispatch_get_current_queue);
const char *linux_dispatch_queue_get_label(linux_dispatch_object queue) LINUX_DISPATCH(dispatch_queue_get_label);
uint32_t linux_dispatch_queue_get_qos_class(linux_dispatch_object queue, int *relative_priority)
    LINUX_DISPATCH(dispatch_queue_get_qos_class);
void linux_dispatch_queue_set_specific(linux_dispatch_object queue, const void *key, void *context,
                                       linux_dispatch_function destructor)
    LINUX_DISPATCH(dispatch_queue_set_specific);
void *linux_dispatch_queue_get_specific(linux_dispatch_object queue, const void *key)
    LINUX_DISPATCH(dispatch_queue_get_specific);
void *linux_dispatch_get_specific(const void *key) LINUX_DISPATCH(dispatch_get_specific);
void linux_dispatch_assert_queue(linux_dispatch_object queue) LINUX_DISPATCH(dispatch_assert_queue);
void linux_dispatch_assert_queue_not(linux_dispatch_object queue) LINUX_DISPATCH(dispatch_assert_queue_not);
void linux_dispatch_assert_queue_barrier(linux_dispatch_object queue) LINUX_DISPATCH(dispatch_assert_queue_barrier);

linux_dispatch_object linux_dispatch_queue_attr_make_with_qos_class(linux_dispatch_object attr, uint32_t qos,
                                                                    int relative_priority)
    LINUX_DISPATCH(dispatch_queue_attr_make_with_qos_class);
linux_dispatch_object linux_dispatch_queue_attr_make_initially_inactive(linux_dispatch_object attr)
    LINUX_DISPATCH(dispatch_queue_attr_make_initially_inactive);
linux_dispatch_object linux_dispatch_queue_attr_make_with_autorelease_frequency(linux_dispatch_object attr,
                                                                                unsigned long frequency)
    LINUX_DISPATCH(dispatch_queue_attr_make_with_autorelease_frequency);

void linux_dispatch_async_f(linux_dispatch_object queue, void *context, linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_async_f);
void linux_dispatch_sync_f(linux_dispatch_object queue, void *context, linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_sync_f);
void linux_dispatch_async_and_wait_f(linux_dispatch_object queue, void *context, linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_async_and_wait_f);
void linux_dispatch_barrier_async_f(linux_dispatch_object queue, void *context, linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_barrier_async_f);
void linux_dispatch_barrier_sync_f(linux_dispatch_object queue, void *context, linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_barrier_sync_f);
void linux_dispatch_barrier_async_and_wait_f(linux_dispatch_object queue, void *context, linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_barrier_async_and_wait_f);
void linux_dispatch_after_f(linux_dispatch_time_t when, linux_dispatch_object queue, void *context,
                            linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_after_f);
void linux_dispatch_apply_f(size_t iterations, linux_dispatch_object queue, void *context,
                            void (*work)(void *context, size_t iteration))
    LINUX_DISPATCH(dispatch_apply_f);

// Time.
linux_dispatch_time_t linux_dispatch_time(linux_dispatch_time_t when, int64_t delta) LINUX_DISPATCH(dispatch_time);
linux_dispatch_time_t linux_dispatch_walltime(const struct timespec *when, int64_t delta) LINUX_DISPATCH(dispatch_walltime);

// Groups and semaphores.
linux_dispatch_object linux_dispatch_group_create(void) LINUX_DISPATCH(dispatch_group_create);
void linux_dispatch_group_enter(linux_dispatch_object group) LINUX_DISPATCH(dispatch_group_enter);
void linux_dispatch_group_leave(linux_dispatch_object group) LINUX_DISPATCH(dispatch_group_leave);
intptr_t linux_dispatch_group_wait(linux_dispatch_object group, linux_dispatch_time_t timeout)
    LINUX_DISPATCH(dispatch_group_wait);
void linux_dispatch_group_async_f(linux_dispatch_object group, linux_dispatch_object queue, void *context,
                                  linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_group_async_f);
void linux_dispatch_group_notify_f(linux_dispatch_object group, linux_dispatch_object queue, void *context,
                                   linux_dispatch_function work)
    LINUX_DISPATCH(dispatch_group_notify_f);
linux_dispatch_object linux_dispatch_semaphore_create(intptr_t value) LINUX_DISPATCH(dispatch_semaphore_create);
intptr_t linux_dispatch_semaphore_wait(linux_dispatch_object semaphore, linux_dispatch_time_t timeout)
    LINUX_DISPATCH(dispatch_semaphore_wait);
intptr_t linux_dispatch_semaphore_signal(linux_dispatch_object semaphore) LINUX_DISPATCH(dispatch_semaphore_signal);

// Sources.
linux_dispatch_object linux_dispatch_source_create(const void *type, uintptr_t handle, uintptr_t mask,
                                                   linux_dispatch_object queue)
    LINUX_DISPATCH(dispatch_source_create);
void linux_dispatch_source_set_event_handler_f(linux_dispatch_object source, linux_dispatch_function handler)
    LINUX_DISPATCH(dispatch_source_set_event_handler_f);
void linux_dispatch_source_set_cancel_handler_f(linux_dispatch_object source, linux_dispatch_function handler)
    LINUX_DISPATCH(dispatch_source_set_cancel_handler_f);
void linux_dispatch_source_set_registration_handler_f(linux_dispatch_object source, linux_dispatch_function handler)
    LINUX_DISPATCH(dispatch_source_set_registration_handler_f);
void linux_dispatch_source_cancel(linux_dispatch_object source) LINUX_DISPATCH(dispatch_source_cancel);
intptr_t linux_dispatch_source_testcancel(linux_dispatch_object source) LINUX_DISPATCH(dispatch_source_testcancel);
uintptr_t linux_dispatch_source_get_data(linux_dispatch_object source) LINUX_DISPATCH(dispatch_source_get_data);
uintptr_t linux_dispatch_source_get_handle(linux_dispatch_object source) LINUX_DISPATCH(dispatch_source_get_handle);
uintptr_t linux_dispatch_source_get_mask(linux_dispatch_object source) LINUX_DISPATCH(dispatch_source_get_mask);
void linux_dispatch_source_merge_data(linux_dispatch_object source, uintptr_t value)
    LINUX_DISPATCH(dispatch_source_merge_data);
void linux_dispatch_source_set_timer(linux_dispatch_object source, linux_dispatch_time_t start, uint64_t interval,
                                     uint64_t leeway)
    LINUX_DISPATCH(dispatch_source_set_timer);

// Data.
linux_dispatch_object linux_dispatch_data_create(const void *buffer, size_t size, linux_dispatch_object queue,
                                                 void *destructor)
    LINUX_DISPATCH(dispatch_data_create);
size_t linux_dispatch_data_get_size(linux_dispatch_object data) LINUX_DISPATCH(dispatch_data_get_size);
linux_dispatch_object linux_dispatch_data_create_map(linux_dispatch_object data, const void **buffer, size_t *size)
    LINUX_DISPATCH(dispatch_data_create_map);
linux_dispatch_object linux_dispatch_data_create_concat(linux_dispatch_object first, linux_dispatch_object second)
    LINUX_DISPATCH(dispatch_data_create_concat);
linux_dispatch_object linux_dispatch_data_create_subrange(linux_dispatch_object data, size_t offset, size_t length)
    LINUX_DISPATCH(dispatch_data_create_subrange);
linux_dispatch_object linux_dispatch_data_copy_region(linux_dispatch_object data, size_t location, size_t *offset)
    LINUX_DISPATCH(dispatch_data_copy_region);
bool linux_dispatch_data_apply_f(linux_dispatch_object data, void *context,
                                 bool (*applier)(void *context, linux_dispatch_object region, size_t offset,
                                                 const void *buffer, size_t size))
    LINUX_DISPATCH(dispatch_data_apply_f);

// I/O channels and whole-file reads and writes. off_t is 64-bit.
typedef void (*linux_dispatch_io_cleanup)(void *context, int error);
typedef void (*linux_dispatch_io_handler)(void *context, bool done, linux_dispatch_object data, int error);
typedef void (*linux_dispatch_data_handler)(void *context, linux_dispatch_object data, int error);

linux_dispatch_object linux_dispatch_io_create_f(unsigned long type, int fd, linux_dispatch_object queue, void *context,
                                                 linux_dispatch_io_cleanup cleanup)
    LINUX_DISPATCH(dispatch_io_create_f);
linux_dispatch_object linux_dispatch_io_create_with_path_f(unsigned long type, const char *path, int oflag,
                                                           unsigned int mode, linux_dispatch_object queue,
                                                           void *context, linux_dispatch_io_cleanup cleanup)
    LINUX_DISPATCH(dispatch_io_create_with_path_f);
linux_dispatch_object linux_dispatch_io_create_with_io_f(unsigned long type, linux_dispatch_object io,
                                                         linux_dispatch_object queue, void *context,
                                                         linux_dispatch_io_cleanup cleanup)
    LINUX_DISPATCH(dispatch_io_create_with_io_f);
void linux_dispatch_io_read_f(linux_dispatch_object channel, int64_t offset, size_t length, linux_dispatch_object queue,
                              void *context, linux_dispatch_io_handler handler)
    LINUX_DISPATCH(dispatch_io_read_f);
void linux_dispatch_io_write_f(linux_dispatch_object channel, int64_t offset, linux_dispatch_object data,
                               linux_dispatch_object queue, void *context, linux_dispatch_io_handler handler)
    LINUX_DISPATCH(dispatch_io_write_f);
void linux_dispatch_io_close(linux_dispatch_object channel, unsigned long flags) LINUX_DISPATCH(dispatch_io_close);
void linux_dispatch_io_barrier_f(linux_dispatch_object channel, void *context, linux_dispatch_function barrier)
    LINUX_DISPATCH(dispatch_io_barrier_f);
int linux_dispatch_io_get_descriptor(linux_dispatch_object channel) LINUX_DISPATCH(dispatch_io_get_descriptor);
void linux_dispatch_io_set_high_water(linux_dispatch_object channel, size_t high_water)
    LINUX_DISPATCH(dispatch_io_set_high_water);
void linux_dispatch_io_set_low_water(linux_dispatch_object channel, size_t low_water)
    LINUX_DISPATCH(dispatch_io_set_low_water);
void linux_dispatch_io_set_interval(linux_dispatch_object channel, uint64_t interval, unsigned long flags)
    LINUX_DISPATCH(dispatch_io_set_interval);
void linux_dispatch_read_f(int fd, size_t length, linux_dispatch_object queue, void *context,
                           linux_dispatch_data_handler handler)
    LINUX_DISPATCH(dispatch_read_f);
void linux_dispatch_write_f(int fd, linux_dispatch_object data, linux_dispatch_object queue, void *context,
                            linux_dispatch_data_handler handler)
    LINUX_DISPATCH(dispatch_write_f);

// Workloops: serial queues with their own threads.
linux_dispatch_object linux_dispatch_workloop_create(const char *label) LINUX_DISPATCH(dispatch_workloop_create);
linux_dispatch_object linux_dispatch_workloop_create_inactive(const char *label)
    LINUX_DISPATCH(dispatch_workloop_create_inactive);
void linux_dispatch_workloop_set_autorelease_frequency(linux_dispatch_object workloop, unsigned long frequency)
    LINUX_DISPATCH(dispatch_workloop_set_autorelease_frequency);

// The main queue, and the hooks CoreFoundation's run loop drains it with.
// On Linux the handle is an eventfd.
int linux_dispatch_get_main_queue_handle_4CF(void) LINUX_DISPATCH(_dispatch_get_main_queue_handle_4CF);
void linux_dispatch_main_queue_callback_4CF(void *message) LINUX_DISPATCH(_dispatch_main_queue_callback_4CF);

extern char linux_dispatch_main_q LINUX_DISPATCH(_dispatch_main_q);
extern char linux_dispatch_queue_attr_concurrent LINUX_DISPATCH(_dispatch_queue_attr_concurrent);
extern char linux_dispatch_data_empty LINUX_DISPATCH(_dispatch_data_empty);
extern char linux_dispatch_source_type_data_add LINUX_DISPATCH(_dispatch_source_type_data_add);
extern char linux_dispatch_source_type_data_or LINUX_DISPATCH(_dispatch_source_type_data_or);
extern char linux_dispatch_source_type_data_replace LINUX_DISPATCH(_dispatch_source_type_data_replace);
extern char linux_dispatch_source_type_read LINUX_DISPATCH(_dispatch_source_type_read);
extern char linux_dispatch_source_type_write LINUX_DISPATCH(_dispatch_source_type_write);
extern char linux_dispatch_source_type_signal LINUX_DISPATCH(_dispatch_source_type_signal);
extern char linux_dispatch_source_type_timer LINUX_DISPATCH(_dispatch_source_type_timer);
extern void *const linux_dispatch_data_destructor_free LINUX_DISPATCH(_dispatch_data_destructor_free);
extern void *const linux_dispatch_data_destructor_munmap LINUX_DISPATCH(_dispatch_data_destructor_munmap);

// Whether the calling thread is the main thread: its ID is the process's.
#include <sys/syscall.h>
#include <unistd.h>
static inline bool perry_dispatch_is_main_thread(void) { return syscall(SYS_gettid) == getpid(); }

// Their addresses, for Swift.
static inline void *perry_linux_main_q(void) { return &linux_dispatch_main_q; }
static inline void *perry_linux_queue_attr_concurrent(void) { return &linux_dispatch_queue_attr_concurrent; }
static inline void *perry_linux_data_empty(void) { return &linux_dispatch_data_empty; }
static inline void *perry_linux_data_destructor_free(void) { return linux_dispatch_data_destructor_free; }
static inline void *perry_linux_data_destructor_munmap(void) { return linux_dispatch_data_destructor_munmap; }

// MARK: - Darwin's exported data

// Static objects the headers' macros take the address of: an isa, then the
// two words every Perry dispatch object carries (the Linux object and its
// Swift state). Words past them are spare.
typedef struct perry_dispatch_static_object {
    void *isa;
    void *linux_object;
    void *state;
    void *spare[5];
} perry_dispatch_static_object;

extern perry_dispatch_static_object perry_dispatch_main_q __asm__("__dispatch_main_q");
extern perry_dispatch_static_object perry_dispatch_queue_attr_concurrent __asm__("__dispatch_queue_attr_concurrent");
extern perry_dispatch_static_object perry_dispatch_data_empty __asm__("__dispatch_data_empty");

// Unified logging's static objects: OS_LOG_DEFAULT and OS_LOG_DISABLED,
// and OS_ACTIVITY_CURRENT and OS_ACTIVITY_NONE.
extern perry_dispatch_static_object perry_os_log_default __asm__("__os_log_default");
extern perry_dispatch_static_object perry_os_log_disabled __asm__("__os_log_disabled");
extern perry_dispatch_static_object perry_os_activity_current __asm__("__os_activity_current");
extern perry_dispatch_static_object perry_os_activity_none __asm__("__os_activity_none");
static inline void *perry_log_default(void) { return &perry_os_log_default; }
static inline void *perry_log_disabled(void) { return &perry_os_log_disabled; }
static inline void *perry_activity_current(void) { return &perry_os_activity_current; }
static inline void *perry_activity_none(void) { return &perry_os_activity_none; }

// One printf conversion of a value, for os_log's messages: `spec` is the
// conversion ("%5.2f"), with length modifiers.
int perry_format_integer(char *buffer, unsigned long size, const char *spec, long long value);
int perry_format_double(char *buffer, unsigned long size, const char *spec, double value);

// The process's short name and the calling thread's kernel id, for log lines.
const char *perry_dispatch_program_name(void);
int perry_dispatch_thread_id(void);

// DISPATCH_SOURCE_TYPE_*: only their addresses matter.
enum perry_dispatch_source_kind {
    PERRY_SOURCE_DATA_ADD, PERRY_SOURCE_DATA_OR, PERRY_SOURCE_DATA_REPLACE, PERRY_SOURCE_MACH_SEND,
    PERRY_SOURCE_MACH_RECV, PERRY_SOURCE_MEMORYPRESSURE, PERRY_SOURCE_PROC, PERRY_SOURCE_READ,
    PERRY_SOURCE_SIGNAL, PERRY_SOURCE_TIMER, PERRY_SOURCE_VNODE, PERRY_SOURCE_WRITE, PERRY_SOURCE_COUNT,
};

// The source kind for a DISPATCH_SOURCE_TYPE_* address; -1 if it is none.
int perry_dispatch_source_kind(const void *type);

// Linux's source type for a kind; NULL where Linux has none (Mach ports,
// memory pressure, processes and vnodes).
static inline const void *perry_linux_source_type(int kind) {
    switch (kind) {
    case PERRY_SOURCE_DATA_ADD: return &linux_dispatch_source_type_data_add;
    case PERRY_SOURCE_DATA_OR: return &linux_dispatch_source_type_data_or;
    case PERRY_SOURCE_DATA_REPLACE: return &linux_dispatch_source_type_data_replace;
    case PERRY_SOURCE_READ: return &linux_dispatch_source_type_read;
    case PERRY_SOURCE_WRITE: return &linux_dispatch_source_type_write;
    case PERRY_SOURCE_SIGNAL: return &linux_dispatch_source_type_signal;
    case PERRY_SOURCE_TIMER: return &linux_dispatch_source_type_timer;
    default: return 0;
    }
}

// DISPATCH_DATA_DESTRUCTOR_FREE and _MUNMAP: variables holding distinct
// markers, compared against what callers pass.
extern const void *perry_dispatch_data_destructor_free __asm__("__dispatch_data_destructor_free");
extern const void *perry_dispatch_data_destructor_munmap __asm__("__dispatch_data_destructor_munmap");

// For Swift, which does not reach C globals directly.
static inline void *perry_main_q(void) { return &perry_dispatch_main_q; }
static inline void *perry_queue_attr_concurrent(void) { return &perry_dispatch_queue_attr_concurrent; }
static inline void *perry_data_empty(void) { return &perry_dispatch_data_empty; }
static inline const void *perry_data_destructor_free(void) { return perry_dispatch_data_destructor_free; }
static inline const void *perry_data_destructor_munmap(void) { return perry_dispatch_data_destructor_munmap; }

#endif
