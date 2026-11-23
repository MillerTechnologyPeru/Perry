// The Linux side of Scripts/test-ppc-abi.sh: functions with the C
// signatures the Swift providers give these types on 32-bit (ObjCValue: a
// float as its bits, a double or long long as a structure of its low and
// high words, a structure as its words, each through a pointer), called by
// code Apple's GCC compiled (ppc_abi_darwin.c) through the loader's Darwin
// entries; and calls and sends from here to Darwin functions and methods.
// Exits with the number of checks that failed.
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void perry_ppc_note_thread(void);
void *perry_ppc_darwin_entry(void *function, const char *types);
void perry_ppc_call_darwin(void *function, const char *types, const uint32_t *words, uint32_t count, uint32_t result[2]);
typedef void *(*lookup_fn)(void *, const void *, void *, const char **);
void perry_ppc_set_method_lookup(lookup_fn);
void perry_ppc_send(void);
void perry_ppc_send_stret(void);

typedef struct { uint32_t low, high; } pair;
typedef struct { uint32_t w[4]; } words4;

static int failures;

static void check(const char *what, const char *got, const char *want) {
    int ok = strcmp(got, want) == 0;
    failures += !ok;
    printf("%s %s: %s%s%s\n", ok ? "ok  " : "FAIL", what, got, ok ? "" : ", want ", ok ? "" : want);
}

static float f_of(uint32_t bits) { float f; memcpy(&f, &bits, 4); return f; }
static uint32_t bits_of(float f) { uint32_t b; memcpy(&b, &f, 4); return b; }
static double d_of(const pair *p) { uint64_t b = (uint64_t)p->high << 32 | p->low; double d; memcpy(&d, &b, 8); return d; }
static uint64_t dbits(double d) { uint64_t b; memcpy(&b, &d, 8); return b; }
static char text[256];

__attribute__((noinline)) void lin_rect(uint32_t a, const words4 *r, uint32_t b) {
    snprintf(text, sizeof(text), "%u {%g %g %g %g} %u", a, f_of(r->w[0]), f_of(r->w[1]), f_of(r->w[2]), f_of(r->w[3]), b);
    check("int, rect, int", text, "7 {1.5 2.5 3.5 4.5} 8");
}
__attribute__((noinline)) uint32_t lin_mixed(uint32_t a, const pair *d, uint32_t f, const pair *q, uint32_t b) {
    snprintf(text, sizeof(text), "%u %g %g 0x%llx %u", a, d_of(d), f_of(f), (unsigned long long)q->high << 32 | q->low, b);
    check("int, double, float, long long, int", text, "1 2.75 3.5 0x100000002 9");
    return 42;
}
__attribute__((noinline)) void lin_one(uint32_t a, const uint32_t *o, uint32_t b) {
    double d;
    memcpy(&d, o, 8);
    snprintf(text, sizeof(text), "%u {%g} %u", a, d, b);
    check("int, structure of a double, int", text, "10 {6.25} 11");
}
__attribute__((noinline)) uint64_t lin_ret_double(uint32_t a) { return dbits(a * 1.5); }
__attribute__((noinline)) uint32_t lin_ret_float(uint32_t f) { return bits_of(f_of(f) * 3); }
__attribute__((noinline)) words4 lin_ret_rect(uint32_t a, const pair *scale) {
    words4 r = {{ bits_of(a), bits_of(a * d_of(scale)), bits_of(-1), bits_of(0.5f) }};
    return r;
}
__attribute__((noinline)) void lin_many(uint32_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t e, uint32_t f,
                                        uint32_t g, uint32_t h, uint32_t i, const pair *x, uint32_t y, const pair *z) {
    snprintf(text, sizeof(text), "%u %u %u %u %u %u %u %u %u %g %g 0x%llx", a, b, c, d, e, f, g, h, i, d_of(x), f_of(y),
             (unsigned long long)z->high << 32 | z->low);
    check("nine ints, then double, float, long long", text, "1 2 3 4 5 6 7 8 9 10.5 11.5 0x300000004");
}

// The Darwin side.
extern void *p_rect __asm__("_p_rect"), *p_mixed __asm__("_p_mixed"), *p_one __asm__("_p_one"),
    *p_ret_double __asm__("_p_ret_double"), *p_ret_float __asm__("_p_ret_float"), *p_ret_rect __asm__("_p_ret_rect"),
    *p_many __asm__("_p_many");
extern double got_double __asm__("_got_double");
extern float got_float __asm__("_got_float");
extern float got_rect[4] __asm__("_got_rect");
extern int got_int __asm__("_got_int");
void darwin_calls(void) __asm__("_darwin_calls");
void darwin_scale(void) __asm__("_darwin_scale");
void darwin_halve(void) __asm__("_darwin_halve");
void darwin_method(void) __asm__("_darwin_method");
void darwin_rect_method(void) __asm__("_darwin_rect_method");

// libgcc's, which Darwin code calls by its Darwin name; it passes the same.
double darwin_floatdidf(long long a) __asm__("___floatdidf");
double darwin_floatdidf(long long a) { return (double)a; }

static void *lookup(void *receiver, const void *selector, void *start, const char **types) {
    (void)receiver; (void)start;
    if (strcmp(selector, "method") == 0) {
        *types = "d@:dif{Rect=ffff}q";
        return (void *)darwin_method;
    }
    *types = "{Rect=ffff}@:f";
    return (void *)darwin_rect_method;
}

int main(void) {
    perry_ppc_note_thread();

    // Darwin to Linux.
    p_rect = perry_ppc_darwin_entry((void *)lin_rect, "vi{Rect=ffff}i");
    p_mixed = perry_ppc_darwin_entry((void *)lin_mixed, "iidfqi");
    p_one = perry_ppc_darwin_entry((void *)lin_one, "vi{OneDouble=d}i");
    p_ret_double = perry_ppc_darwin_entry((void *)lin_ret_double, "di");
    p_ret_float = perry_ppc_darwin_entry((void *)lin_ret_float, "ff");
    p_ret_rect = perry_ppc_darwin_entry((void *)lin_ret_rect, "{Rect=ffff}id");
    p_many = perry_ppc_darwin_entry((void *)lin_many, "viiiiiiiiidfq");
    unsigned long r2;
    __asm__ volatile("mr %0, 2" : "=r"(r2));
    darwin_calls();     // Darwin code: it may change r2, which this keeps
    __asm__ volatile("mr 2, %0" : : "r"(r2) : "memory");
    snprintf(text, sizeof(text), "int %d double %g float %g rect {%g %g %g %g}", got_int, got_double, got_float,
             got_rect[0], got_rect[1], got_rect[2], got_rect[3]);
    check("results to Darwin", text, "int 42 double 18 float 3.75 rect {13 26 -1 0.5}");

    // Linux to Darwin.
    pair a = { (uint32_t)dbits(1.5), (uint32_t)(dbits(1.5) >> 32) };
    words4 r = {{ bits_of(1), bits_of(2), bits_of(3), bits_of(4) }};
    pair q = { 1000, 0 };
    uint32_t words[] = { (uint32_t)(uintptr_t)&a, 4, bits_of(0.25f), (uint32_t)(uintptr_t)&r, (uint32_t)(uintptr_t)&q };
    uint32_t result[2];
    perry_ppc_call_darwin((void *)darwin_scale, "ddif{Rect=ffff}q", words, 5, result);
    uint64_t bits = (uint64_t)result[0] << 32 | result[1];
    double scaled;
    memcpy(&scaled, &bits, 8);
    uint32_t half_words[] = { bits_of(5) };
    perry_ppc_call_darwin((void *)darwin_halve, "ff", half_words, 1, result);
    snprintf(text, sizeof(text), "%g %g", scaled, f_of(result[0]));
    check("calls to Darwin functions", text, "1016.25 2.5");

    // Sends from Linux code.
    perry_ppc_set_method_lookup(lookup);
    int object = 1;
    uint64_t (*send)(void *, const char *, const pair *, uint32_t, uint32_t, const words4 *, const pair *) =
        (void *)perry_ppc_send;
    uint64_t sent = send(&object, "method", &a, 4, bits_of(0.25f), &r, &q);
    double sent_value;
    memcpy(&sent_value, &sent, 8);
    words4 (*send_rect)(void *, const char *, uint32_t) = (void *)perry_ppc_send_stret;
    words4 rect = send_rect(&object, "rect", bits_of(1.5f));
    snprintf(text, sizeof(text), "%g {%g %g %g %g}", sent_value, f_of(rect.w[0]), f_of(rect.w[1]), f_of(rect.w[2]),
             f_of(rect.w[3]));
    check("sends to Darwin methods", text, "1018.25 {1.5 3 4.5 6}");
    return failures;
}
