#include "log.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned perry_trace_flags;

void perry_log_init(void) {
    const char *spec = getenv("PERRY_TRACE");
    if (!spec)
        return;
    static const struct { const char *name; unsigned flag; } names[] = {
        { "load", PERRY_TRACE_LOAD },
        { "bind", PERRY_TRACE_BIND },
        { "init", PERRY_TRACE_INIT },
        { "all", ~0u },
    };
    char *copy = strdup(spec);
    for (char *save = NULL, *tok = strtok_r(copy, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
            if (strcmp(tok, names[i].name) == 0)
                perry_trace_flags |= names[i].flag;
    }
    free(copy);
}

static void vlog(const char *prefix, const char *fmt, va_list args) {
    fputs(prefix, stderr);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);
}

void perry_trace(unsigned category, const char *fmt, ...) {
    if (!(perry_trace_flags & category))
        return;
    va_list args;
    va_start(args, fmt);
    vlog("perry: ", fmt, args);
    va_end(args);
}

void perry_warn(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vlog("perry: warning: ", fmt, args);
    va_end(args);
}

void perry_fatal(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vlog("perry: error: ", fmt, args);
    va_end(args);
    exit(127);
}
