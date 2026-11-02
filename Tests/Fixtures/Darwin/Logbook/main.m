// Unified logging: logs, every level with scalars, strings, objects,
// pointers and privacy qualifiers, which levels are enabled, signposts and
// activities. Messages go to the system log, not standard output, so this
// prints what the program can observe.

#import <Foundation/Foundation.h>
#import <os/activity.h>
#import <os/log.h>
#import <os/signpost.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        os_log_t log = os_log_create("org.perry.logbook", "general");
        os_log_t same = os_log_create("org.perry.logbook", "general");
        os_log_t other = os_log_create("org.perry.logbook", "network");
        printf("logs: %d %d %d\n", log != NULL, log == same, log != other);
        printf("enabled default: debug %d info %d default %d error %d fault %d\n",
               os_log_type_enabled(OS_LOG_DEFAULT, OS_LOG_TYPE_DEBUG), os_log_type_enabled(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO),
               os_log_type_enabled(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT), os_log_type_enabled(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR),
               os_log_type_enabled(OS_LOG_DEFAULT, OS_LOG_TYPE_FAULT));
        printf("enabled disabled: %d\n", os_log_type_enabled(OS_LOG_DISABLED, OS_LOG_TYPE_FAULT));
        printf("info enabled: %d, debug enabled: %d\n", os_log_info_enabled(log), os_log_debug_enabled(log));

        int count = 42;
        double ratio = 0.5;
        const char *name = "perry";
        NSString *object = @"an object";
        os_log(OS_LOG_DEFAULT, "default: %d items, ratio %.2f, name %s, object %@", count, ratio, name, object);
        os_log_info(log, "info: %{public}s and %{private}s", name, "secret");
        os_log_debug(log, "debug: %lu %lld %x", (unsigned long)7, -5LL, 255);
        os_log_error(log, "error: %{public}@ pointer %p", object, (void *)0x1234);
        os_log_fault(other, "fault: %{errno}d %%", 2);
        os_log_with_type(log, OS_LOG_TYPE_DEFAULT, "with type: %{BOOL}d %{bool}d", YES, NO);
        printf("logged\n");

        os_signpost_id_t first = os_signpost_id_generate(log);
        os_signpost_id_t second = os_signpost_id_generate(log);
        os_signpost_id_t pointer = os_signpost_id_make_with_pointer(log, (void *)0x1000);
        printf("signposts: %d %d %d, enabled %d\n", first != OS_SIGNPOST_ID_NULL && first != OS_SIGNPOST_ID_INVALID,
               first != second, pointer == os_signpost_id_make_with_pointer(log, (void *)0x1000), os_signpost_enabled(log));
        os_signpost_interval_begin(log, first, "Load", "start %d", 1);
        os_signpost_event_emit(log, first, "Step");
        os_signpost_interval_end(log, first, "Load", "end");

        os_activity_t activity = os_activity_create("Working", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT);
        __block int ran = 0;
        os_activity_apply(activity, ^{ ran = 1; });
        struct os_activity_scope_state_s state;
        os_activity_scope_enter(activity, &state);
        os_activity_scope_leave(&state);
        printf("activity: ran %d, id %d\n", ran, os_activity_get_identifier(activity, NULL) != 0);
        NSLog(@"after logging");
    }
    return 0;
}
