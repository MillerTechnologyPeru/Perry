// The Linux side of Scripts/test-ppc-abi.sh: functions with plain C
// signatures (doubles, floats, long longs, structures by value), as Swift's
// types give them on ppc, called by code Apple's GCC compiled
// (ppc_abi_darwin.c) through the loader's Darwin entries; and calls and
// sends from here to Darwin functions and methods. Exits with the number of
// checks that failed.
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct perry_ppc_registers {
    uint32_t r3, r4;
    double f1;
} perry_ppc_registers;
void perry_ppc_note_thread(void);
void *perry_ppc_darwin_entry(void *function, const char *types);
void perry_ppc_call_darwin(void *function, const char *types, const uint32_t gprs[8], const double fprs[8],
                           const uint32_t *stack, perry_ppc_registers *result);
typedef void *(*lookup_fn)(void *, const void *, void *, const char **);
void perry_ppc_set_method_lookup(lookup_fn);
void perry_ppc_send(void);
void perry_ppc_send_stret(void);

typedef struct { float x, y, w, h; } Rect;
typedef struct { double a; } OneDouble;

static int failures;

static void check(const char *what, const char *got, const char *want) {
    int ok = strcmp(got, want) == 0;
    failures += !ok;
    printf("%s %s: %s%s%s\n", ok ? "ok  " : "FAIL", what, got, ok ? "" : ", want ", ok ? "" : want);
}

static char text[256];

__attribute__((noinline)) void lin_rect(int a, Rect r, int b) {
    snprintf(text, sizeof(text), "%d {%g %g %g %g} %d", a, r.x, r.y, r.w, r.h, b);
    check("int, rect, int", text, "7 {1.5 2.5 3.5 4.5} 8");
}
__attribute__((noinline)) int lin_mixed(int a, double d, float f, long long q, int b) {
    snprintf(text, sizeof(text), "%d %g %g 0x%llx %d", a, d, f, (unsigned long long)q, b);
    check("int, double, float, long long, int", text, "1 2.75 3.5 0x100000002 9");
    return 42;
}
__attribute__((noinline)) void lin_one(int a, OneDouble o, int b) {
    snprintf(text, sizeof(text), "%d {%g} %d", a, o.a, b);
    check("int, structure of a double, int", text, "10 {6.25} 11");
}
__attribute__((noinline)) double lin_ret_double(int a) { return a * 1.5; }
__attribute__((noinline)) float lin_ret_float(float f) { return f * 3; }
__attribute__((noinline)) Rect lin_ret_rect(int a, double scale) {
    Rect r = { (float)a, (float)(a * scale), -1, 0.5f };
    return r;
}
__attribute__((noinline)) void lin_many(int a, int b, int c, int d, int e, int f, int g, int h, int i, double x,
                                        float y, long long z) {
    snprintf(text, sizeof(text), "%d %d %d %d %d %d %d %d %d %g %g 0x%llx", a, b, c, d, e, f, g, h, i, x, y,
             (unsigned long long)z);
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

    // Linux to Darwin: the registers a Linux call to
    // darwin_scale(1.5, 4, 0.25f, rect, 1000LL) has: f1, r3, f2, r4 (the
    // rectangle's copy), and the long long in the pair r5:r6.
    Rect r = { 1, 2, 3, 4 };
    uint32_t gprs[8] = { 4, (uint32_t)(uintptr_t)&r, 0, 1000 };
    double fprs[8] = { 1.5, 0.25 };
    perry_ppc_registers result;
    perry_ppc_call_darwin((void *)darwin_scale, "ddif{Rect=ffff}q", gprs, fprs, NULL, &result);
    double scaled = result.f1;
    uint32_t no_words[8] = { 0 };
    double half_fprs[8] = { 5 };
    perry_ppc_call_darwin((void *)darwin_halve, "ff", no_words, half_fprs, NULL, &result);
    snprintf(text, sizeof(text), "%g %g", scaled, result.f1);
    check("calls to Darwin functions", text, "1016.25 2.5");

    // Sends from Linux code, with plain C types.
    perry_ppc_set_method_lookup(lookup);
    int object = 1;
    double (*send)(void *, const char *, double, int, float, Rect, long long) = (void *)perry_ppc_send;
    double sent = send(&object, "method", 1.5, 4, 0.25f, r, 1000LL);
    Rect (*send_rect)(void *, const char *, float) = (void *)perry_ppc_send_stret;
    Rect rect = send_rect(&object, "rect", 1.5f);
    snprintf(text, sizeof(text), "%g {%g %g %g %g}", sent, rect.x, rect.y, rect.w, rect.h);
    check("sends to Darwin methods", text, "1018.25 {1.5 3 4.5 6}");
    return failures;
}
