// libPerryicucore: the provider for /usr/lib/libicucore.A.dylib, over the
// system's ICU.
//
// Darwin's ICU is one library with plain names; Linux's is libicuuc and
// libicui18n with the version in each name (uregex_open_76). The C API's
// types are the same (UChar is 16 bits, UErrorCode an int), so each
// function here calls ICU's, found the first time it's needed. What Mac
// programs use: regular expressions (Xcode's build output parsing), error
// names and combining classes.

#define _GNU_SOURCE
#include "PerryICUCore.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef uint16_t UChar;
typedef int UErrorCode;
typedef int8_t UBool;
typedef struct URegularExpression URegularExpression;
typedef struct UParseError UParseError;

// U_UNSUPPORTED_ERROR: what a call reports when there is no ICU.
enum { unsupported = 16 };

static void *uc, *i18n;
static int version;
static pthread_once_t once = PTHREAD_ONCE_INIT;

static void *open_library(const char *base) {
    char name[64];
    snprintf(name, sizeof name, "%s.so", base);
    void *handle = dlopen(name, RTLD_NOW | RTLD_GLOBAL);
    for (int number = 90; !handle && number >= 50; number--) {
        snprintf(name, sizeof name, "%s.so.%d", base, number);
        handle = dlopen(name, RTLD_NOW | RTLD_GLOBAL);
    }
    return handle;
}

// The libraries, and the version their names carry (0 for none).
static void load(void) {
    uc = open_library("libicuuc");
    i18n = open_library("libicui18n");
    if (!uc || dlsym(uc, "u_errorName")) return;
    char name[64];
    for (int number = 90; number >= 50; number--) {
        snprintf(name, sizeof name, "u_errorName_%d", number);
        if (dlsym(uc, name)) {
            version = number;
            return;
        }
    }
}

static void *function(const char *name) {
    pthread_once(&once, load);
    char versioned[96];
    if (version) {
        snprintf(versioned, sizeof versioned, "%s_%d", name, version);
        name = versioned;
    }
    void *found = i18n ? dlsym(i18n, name) : NULL;
    return found ? found : (uc ? dlsym(uc, name) : NULL);
}

#define RESOLVE(type, name) \
    static __typeof__(type) real; \
    if (!real) real = (__typeof__(type))function(#name)

const char *darwin_u_errorName(UErrorCode code) DARWIN_SYMBOL(u_errorName);
const char *darwin_u_errorName(UErrorCode code) {
    RESOLVE(const char *(*)(UErrorCode), u_errorName);
    return real ? real(code) : "U_UNSUPPORTED_ERROR";
}

URegularExpression *darwin_uregex_open(const UChar *pattern, int32_t length, uint32_t flags, UParseError *error,
                                       UErrorCode *status) DARWIN_SYMBOL(uregex_open);
URegularExpression *darwin_uregex_open(const UChar *pattern, int32_t length, uint32_t flags, UParseError *error,
                                       UErrorCode *status) {
    RESOLVE(URegularExpression *(*)(const UChar *, int32_t, uint32_t, UParseError *, UErrorCode *), uregex_open);
    if (!real) {
        if (status) *status = unsupported;
        return NULL;
    }
    return real(pattern, length, flags, error, status);
}

void darwin_uregex_close(URegularExpression *regex) DARWIN_SYMBOL(uregex_close);
void darwin_uregex_close(URegularExpression *regex) {
    RESOLVE(void (*)(URegularExpression *), uregex_close);
    if (real && regex) real(regex);
}

void darwin_uregex_setText(URegularExpression *regex, const UChar *text, int32_t length, UErrorCode *status)
    DARWIN_SYMBOL(uregex_setText);
void darwin_uregex_setText(URegularExpression *regex, const UChar *text, int32_t length, UErrorCode *status) {
    RESOLVE(void (*)(URegularExpression *, const UChar *, int32_t, UErrorCode *), uregex_setText);
    if (real) real(regex, text, length, status);
    else if (status) *status = unsupported;
}

void darwin_uregex_reset(URegularExpression *regex, int32_t index, UErrorCode *status) DARWIN_SYMBOL(uregex_reset);
void darwin_uregex_reset(URegularExpression *regex, int32_t index, UErrorCode *status) {
    RESOLVE(void (*)(URegularExpression *, int32_t, UErrorCode *), uregex_reset);
    if (real) real(regex, index, status);
    else if (status) *status = unsupported;
}

UBool darwin_uregex_find(URegularExpression *regex, int32_t start, UErrorCode *status) DARWIN_SYMBOL(uregex_find);
UBool darwin_uregex_find(URegularExpression *regex, int32_t start, UErrorCode *status) {
    RESOLVE(UBool (*)(URegularExpression *, int32_t, UErrorCode *), uregex_find);
    if (real) return real(regex, start, status);
    if (status) *status = unsupported;
    return 0;
}

int32_t darwin_uregex_groupCount(URegularExpression *regex, UErrorCode *status) DARWIN_SYMBOL(uregex_groupCount);
int32_t darwin_uregex_groupCount(URegularExpression *regex, UErrorCode *status) {
    RESOLVE(int32_t (*)(URegularExpression *, UErrorCode *), uregex_groupCount);
    if (real) return real(regex, status);
    if (status) *status = unsupported;
    return 0;
}

int32_t darwin_uregex_start(URegularExpression *regex, int32_t group, UErrorCode *status) DARWIN_SYMBOL(uregex_start);
int32_t darwin_uregex_start(URegularExpression *regex, int32_t group, UErrorCode *status) {
    RESOLVE(int32_t (*)(URegularExpression *, int32_t, UErrorCode *), uregex_start);
    if (real) return real(regex, group, status);
    if (status) *status = unsupported;
    return -1;
}

int32_t darwin_uregex_end(URegularExpression *regex, int32_t group, UErrorCode *status) DARWIN_SYMBOL(uregex_end);
int32_t darwin_uregex_end(URegularExpression *regex, int32_t group, UErrorCode *status) {
    RESOLVE(int32_t (*)(URegularExpression *, int32_t, UErrorCode *), uregex_end);
    if (real) return real(regex, group, status);
    if (status) *status = unsupported;
    return -1;
}

// A code point's canonical combining class (0 for none), which text editors
// read to keep accents with their base characters.
uint8_t darwin_u_getCombiningClass(int32_t c) DARWIN_SYMBOL(u_getCombiningClass);
uint8_t darwin_u_getCombiningClass(int32_t c) {
    RESOLVE(uint8_t (*)(int32_t), u_getCombiningClass);
    return real ? real(c) : 0;
}
