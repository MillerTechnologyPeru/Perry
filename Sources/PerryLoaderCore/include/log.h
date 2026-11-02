#ifndef PERRY_LOG_H
#define PERRY_LOG_H

#include <stdbool.h>

// Trace categories, enabled with PERRY_TRACE=load,bind,init or PERRY_TRACE=all.
enum {
    PERRY_TRACE_LOAD = 1 << 0,
    PERRY_TRACE_BIND = 1 << 1,
    PERRY_TRACE_INIT = 1 << 2,
};

extern unsigned perry_trace_flags;

void perry_log_init(void);
void perry_trace(unsigned category, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void perry_warn(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
_Noreturn void perry_fatal(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

#define PERRY_TRACING(category) ((perry_trace_flags & (category)) != 0)

#endif
