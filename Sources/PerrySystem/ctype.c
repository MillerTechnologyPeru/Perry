// Darwin's ctype table: inlined isspace, isdigit, toupper and the rest read
// _DefaultRuneLocale's __runetype, __maplower and __mapupper for the first
// 256 characters directly. The table is the C locale's, laid out as
// <runetype.h> has it, with a digit's value in the low bits.

#include "PerrySystem.h"

#include <stdint.h>
#include <string.h>

enum {
    A = 0x100, C = 0x200, D = 0x400, G = 0x800, L = 0x1000, P = 0x2000, S = 0x4000, U = 0x8000,
    X = 0x10000, B = 0x20000, R = 0x40000, SW1 = 0x40000000,
};

typedef struct {
    int nranges;
    void *ranges;
} rune_range;

struct darwin_rune_locale {
    char magic[8];
    char encoding[32];
    void *sgetrune;
    void *sputrune;
    int32_t invalid_rune;
    uint32_t runetype[256];
    int32_t maplower[256];
    int32_t mapupper[256];
    rune_range runetype_ext, maplower_ext, mapupper_ext;
    void *variable;
    int variable_len;
    int ncharclasses;
    void *charclasses;
};

struct darwin_rune_locale darwin_DefaultRuneLocale DARWIN_SYMBOL(_DefaultRuneLocale);
struct darwin_rune_locale *darwin_CurrentRuneLocale DARWIN_SYMBOL(_CurrentRuneLocale);

__attribute__((constructor))
static void make_rune_locale(void) {
    struct darwin_rune_locale *locale = &darwin_DefaultRuneLocale;
    memcpy(locale->magic, "RuneMagA", 8);
    strcpy(locale->encoding, "NONE");
    locale->invalid_rune = 0xfffd;
    for (int c = 0; c < 256; c++) {
        uint32_t type = 0;
        if (c < 128) {
            if (c < 32 || c == 127) type |= C;
            if (c == ' ' || c == '\t') type |= B;
            if (c == ' ' || (c >= '\t' && c <= '\r')) type |= S;
            if (c >= 32 && c < 127) type |= R | SW1;
            if (c > 32 && c < 127) type |= G;
            if (c >= '0' && c <= '9') type |= D | X | (uint32_t)(c - '0');
            if (c >= 'a' && c <= 'z') type |= A | L;
            if (c >= 'A' && c <= 'Z') type |= A | U;
            if (c >= 'a' && c <= 'f') type |= X | (uint32_t)(c - 'a' + 10);
            if (c >= 'A' && c <= 'F') type |= X | (uint32_t)(c - 'A' + 10);
            if ((type & G) && !(type & (A | D))) type |= P;
        }
        locale->runetype[c] = type;
        locale->maplower[c] = (c >= 'A' && c <= 'Z') ? c + 32 : c;
        locale->mapupper[c] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    darwin_CurrentRuneLocale = locale;
}
