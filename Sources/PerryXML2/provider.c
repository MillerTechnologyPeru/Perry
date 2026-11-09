// libPerryxml2: the provider for /usr/lib/libxml2.2.dylib, over Linux's
// libxml2.
//
// The iOS SDK's libxml2 (2.9.13) and Linux's (2.9.x) share their public
// structs and, on arm64, their calling convention, so most imports bind
// straight to Linux's libxml2: perry_provider_symbol looks each one up
// there. What differs is variadic: Darwin passes variadic arguments on the
// stack and va_list as a pointer. thunks.S converts libxml2's variadic and
// va_list functions; this file bridges the variadic error handlers that
// libxml2 calls back, much as box64's wrapper does: a fixed pool of native
// trampolines, each forwarding to one Darwin handler.

#define _GNU_SOURCE
#include "PerryXML2.h"
#include "perry_wrapped.h"

#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))
#define INTERNAL __attribute__((visibility("hidden")))

// The parts of libxml2's API this file calls, declared here rather than
// from its headers: the provider needs only these.
typedef void (*xml_generic_error_func)(void *ctx, const char *msg, ...);
extern void xmlSetGenericErrorFunc(void *ctx, xml_generic_error_func handler);
extern void initGenericErrorDefaultFunc(xml_generic_error_func *handler);
extern xml_generic_error_func *__xmlGenericError(void);
extern void xmlParserError(void *ctx, const char *msg, ...);
extern void xmlParserWarning(void *ctx, const char *msg, ...);
extern void xmlParserValidityError(void *ctx, const char *msg, ...);
extern void xmlParserValidityWarning(void *ctx, const char *msg, ...);
extern int xmlStrlen(const unsigned char *string);

// thunks.S
INTERNAL extern void perry_xml_call_darwin_variadic(void *function, void *ctx, const char *format, const char *argument);
INTERNAL extern void perry_xml_generic_error_darwin(void *ctx, const char *msg, ...);

// MARK: - Binding to Linux's libxml2

static perry_wrapped_library libxml2 = PERRY_WRAPPED_LIBRARY(xmlStrlen);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&libxml2, name, NULL);
}

// MARK: - Formatting

/// The message, formatted with glibc; free it.
static char *format_message(const char *msg, va_list ap) {
    char *text = NULL;
    if (vasprintf(&text, msg ? msg : "", ap) < 0)
        return NULL;
    return text;
}

// The va_list forms of libxml2's variadic error reporters, which it lacks:
// thunks.S calls these with Darwin's arguments as a va_list.
#define REPORTER(name, function)                                        \
    INTERNAL void name(void *ctx, const char *msg, va_list ap) {        \
        char *text = format_message(msg, ap);                           \
        function(ctx, "%s", text ? text : "");                          \
        free(text);                                                     \
    }

REPORTER(perry_xml_parser_error_v, xmlParserError)
REPORTER(perry_xml_parser_warning_v, xmlParserWarning)
REPORTER(perry_xml_parser_validity_error_v, xmlParserValidityError)
REPORTER(perry_xml_parser_validity_warning_v, xmlParserValidityWarning)

// MARK: - Generic error handlers

// libxml2 calls its generic error handler as a Linux variadic function, but
// a handler from Darwin code reads its arguments from the stack. Each
// Darwin handler gets a native trampoline that formats the message and
// calls the handler with "%s" and the text, Darwin's way.

#define HANDLER_SLOTS 8

static void *darwin_handlers[HANDLER_SLOTS];
static pthread_mutex_t slots_lock = PTHREAD_MUTEX_INITIALIZER;

static void forward(void *handler, void *ctx, const char *msg, va_list ap) {
    char *text = format_message(msg, ap);
    perry_xml_call_darwin_variadic(handler, ctx, "%s", text ? text : "");
    free(text);
}

#define SLOT(n)                                                         \
    static void slot##n(void *ctx, const char *msg, ...) {              \
        va_list ap;                                                     \
        va_start(ap, msg);                                              \
        forward(darwin_handlers[n], ctx, msg, ap);                      \
        va_end(ap);                                                     \
    }
SLOT(0) SLOT(1) SLOT(2) SLOT(3) SLOT(4) SLOT(5) SLOT(6) SLOT(7)

static const xml_generic_error_func slots[HANDLER_SLOTS] = {
    slot0, slot1, slot2, slot3, slot4, slot5, slot6, slot7,
};

/// The native handler ___xmlGenericError last showed Darwin code as
/// perry_xml_generic_error_darwin.
static __thread xml_generic_error_func shown_native_handler;

/// The native handler for a Darwin one: its trampoline.
static xml_generic_error_func native_handler(void *handler) {
    if (!handler)
        return NULL;
    if (handler == (void *)perry_xml_generic_error_darwin)
        return shown_native_handler;
    pthread_mutex_lock(&slots_lock);
    xml_generic_error_func result = NULL;
    for (int i = 0; i < HANDLER_SLOTS && !result; i++)
        if (darwin_handlers[i] == handler)
            result = slots[i];
    for (int i = 0; i < HANDLER_SLOTS && !result; i++)
        if (!darwin_handlers[i]) {
            darwin_handlers[i] = handler;
            result = slots[i];
        }
    pthread_mutex_unlock(&slots_lock);
    if (!result)
        fprintf(stderr, "perry: libxml2: no slot left for generic error handler %p; using the default\n", handler);
    return result;
}

/// The Darwin handler for a native one: the handler a trampoline forwards
/// to, or a Darwin-callable thunk into a native handler.
static void *darwin_handler(xml_generic_error_func handler) {
    if (!handler)
        return NULL;
    for (int i = 0; i < HANDLER_SLOTS; i++)
        if (slots[i] == handler)
            return darwin_handlers[i];
    shown_native_handler = handler;
    return (void *)perry_xml_generic_error_darwin;
}

/// What perry_xml_generic_error_darwin runs: the message, formatted, to the
/// native handler it stands for.
INTERNAL void perry_xml_generic_error_v(void *ctx, const char *msg, va_list ap) {
    char *text = format_message(msg, ap);
    if (shown_native_handler)
        shown_native_handler(ctx, "%s", text ? text : "");
    free(text);
}

#if defined(__x86_64__)
// Darwin's x86_64 variadic ABI is Linux's, so these need no assembly, and
// libxml2's variadic functions bind to Linux's with no thunks.
INTERNAL void perry_xml_call_darwin_variadic(void *function, void *ctx, const char *format, const char *argument) {
    ((void (*)(void *, const char *, ...))function)(ctx, format, argument);
}

INTERNAL void perry_xml_generic_error_darwin(void *ctx, const char *msg, ...) {
    va_list ap;
    va_start(ap, msg);
    perry_xml_generic_error_v(ctx, msg, ap);
    va_end(ap);
}
#endif

void darwin_xmlSetGenericErrorFunc(void *ctx, void *handler) DARWIN_SYMBOL(xmlSetGenericErrorFunc);

void darwin_xmlSetGenericErrorFunc(void *ctx, void *handler) {
    xmlSetGenericErrorFunc(ctx, native_handler(handler));
}

void darwin_initGenericErrorDefaultFunc(void **handler) DARWIN_SYMBOL(initGenericErrorDefaultFunc);

void darwin_initGenericErrorDefaultFunc(void **handler) {
    xml_generic_error_func native = handler ? native_handler(*handler) : NULL;
    initGenericErrorDefaultFunc(native ? &native : NULL);
}

/// The xmlGenericError macro reads the handler through this pointer and
/// calls it Darwin's way, so it points at the Darwin view of the thread's
/// handler. Assigning through it does not change libxml2's handler; use
/// xmlSetGenericErrorFunc.
void **darwin___xmlGenericError(void) DARWIN_SYMBOL(__xmlGenericError);

void **darwin___xmlGenericError(void) {
    static __thread void *view;
    view = darwin_handler(*__xmlGenericError());
    return &view;
}
