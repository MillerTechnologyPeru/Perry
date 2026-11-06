// Darwin armv7 varargs for the printf family.
//
// A Darwin armv7 va_list points at one run of 4-byte slots: a 64-bit value
// takes the next two slots wherever they fall. glibc armhf's va_arg aligns a
// 64-bit value's address to 8 bytes. The two layouts agree only when no 64-bit
// value follows an odd number of words, so the arguments are copied into a
// buffer in glibc's layout, which needs the format to know which are 64 bits
// wide: long long, intmax_t and every floating-point conversion.

#if defined(__arm__)

#include "PerrySystem.h"

#include <stdint.h>
#include <string.h>

typedef struct repacker {
    const uint32_t *source;     // the next Darwin slot
    uint8_t *out;               // NULL when only measuring
    size_t size;
} repacker;

static void copy_word(repacker *r) {
    if (r->out)
        memcpy(r->out + r->size, r->source, 4);
    r->source++;
    r->size += 4;
}

static void copy_double_word(repacker *r) {
    r->size = (r->size + 7) & ~(size_t)7;
    if (r->out)
        memcpy(r->out + r->size, r->source, 8);
    r->source += 2;
    r->size += 8;
}

size_t perry_repack_arguments(const char *format, const void *darwin_ap, void *out) {
    repacker r = { darwin_ap, out, 0 };
    for (const char *p = format; *p; p++) {
        if (*p != '%')
            continue;
        p++;
        if (*p == '%')
            continue;
        // Positional arguments (%1$d) reorder the slots; not handled.
        const char *digits = p;
        while (*digits >= '0' && *digits <= '9')
            digits++;
        if (digits != p && *digits == '$')
            break;
        // Flags, then width and precision, each of which may take an int.
        while (*p == '-' || *p == '+' || *p == ' ' || *p == '#' || *p == '0' || *p == '\'')
            p++;
        if (*p == '*') {
            copy_word(&r);
            p++;
        } else {
            while (*p >= '0' && *p <= '9')
                p++;
        }
        if (*p == '.') {
            p++;
            if (*p == '*') {
                copy_word(&r);
                p++;
            } else {
                while (*p >= '0' && *p <= '9')
                    p++;
            }
        }
        // Length modifiers.
        int wide = 0;
        for (;; p++) {
            if (*p == 'l' && p[1] == 'l') {
                wide = 1;
                p++;
            } else if (*p == 'q' || *p == 'j') {
                wide = 1;
            } else if (*p != 'h' && *p != 'l' && *p != 'z' && *p != 't' && *p != 'L') {
                break;
            }
        }
        switch (*p) {
        case 'd': case 'i': case 'o': case 'u': case 'x': case 'X': case 'D': case 'O': case 'U':
            if (wide)
                copy_double_word(&r);
            else
                copy_word(&r);
            break;
        case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A':
            copy_double_word(&r);       // a long double is a double on armv7
            break;
        case 'c': case 'C': case 's': case 'S': case 'p': case 'n':
            copy_word(&r);
            break;
        case 0:
            return (r.size + 7) & ~(size_t)7;
        default:
            break;
        }
    }
    return (r.size + 7) & ~(size_t)7;
}

#endif
