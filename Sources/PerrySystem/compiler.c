// What armv6 and armv7 programs take from the compiler's runtime
// (libgcc_s) and, built with GCC, from libstdc++.
//
// armv6 has no integer division, and code built for it calls libgcc's
// routines for that and, compiled as Thumb (which cannot use VFP on armv6),
// for floating-point arithmetic: the *vfp routines, which take and return
// floats and doubles in core registers and do the arithmetic with VFP.
// Darwin names 64-bit division as GCC does (__divdi3), where Linux's armhf
// has the EABI's __aeabi_ldivmod.
//
// Programs that use no more of libstdc++ than the operators new and delete
// bind those here.

#include "PerrySystem.h"

#if defined(__arm__)

#include <stdlib.h>
#include <unistd.h>

#define LIBGCC(name) __asm__("_" #name) __attribute__((visibility("default"), used)) DARWIN_FLOAT_ABI

double perry_adddf3vfp(double a, double b) LIBGCC(__adddf3vfp);
double perry_adddf3vfp(double a, double b) { return a + b; }
double perry_subdf3vfp(double a, double b) LIBGCC(__subdf3vfp);
double perry_subdf3vfp(double a, double b) { return a - b; }
double perry_muldf3vfp(double a, double b) LIBGCC(__muldf3vfp);
double perry_muldf3vfp(double a, double b) { return a * b; }
double perry_divdf3vfp(double a, double b) LIBGCC(__divdf3vfp);
double perry_divdf3vfp(double a, double b) { return a / b; }
float perry_addsf3vfp(float a, float b) LIBGCC(__addsf3vfp);
float perry_addsf3vfp(float a, float b) { return a + b; }
float perry_subsf3vfp(float a, float b) LIBGCC(__subsf3vfp);
float perry_subsf3vfp(float a, float b) { return a - b; }
float perry_mulsf3vfp(float a, float b) LIBGCC(__mulsf3vfp);
float perry_mulsf3vfp(float a, float b) { return a * b; }
float perry_divsf3vfp(float a, float b) LIBGCC(__divsf3vfp);
float perry_divsf3vfp(float a, float b) { return a / b; }

// Comparisons give 1 or 0; with a NaN only "ne" and "unord" hold.
#define COMPARE(suffix, type, name, expression) \
    int perry_##name##suffix(type a, type b) LIBGCC(__##name##suffix); \
    int perry_##name##suffix(type a, type b) { return expression; }
COMPARE(df2vfp, double, eq, a == b) COMPARE(df2vfp, double, ne, a != b) COMPARE(df2vfp, double, lt, a < b)
COMPARE(df2vfp, double, le, a <= b) COMPARE(df2vfp, double, gt, a > b) COMPARE(df2vfp, double, ge, a >= b)
COMPARE(df2vfp, double, unord, a != a || b != b)
COMPARE(sf2vfp, float, eq, a == b) COMPARE(sf2vfp, float, ne, a != b) COMPARE(sf2vfp, float, lt, a < b)
COMPARE(sf2vfp, float, le, a <= b) COMPARE(sf2vfp, float, gt, a > b) COMPARE(sf2vfp, float, ge, a >= b)
COMPARE(sf2vfp, float, unord, a != a || b != b)

double perry_extendsfdf2vfp(float a) LIBGCC(__extendsfdf2vfp);
double perry_extendsfdf2vfp(float a) { return a; }
float perry_truncdfsf2vfp(double a) LIBGCC(__truncdfsf2vfp);
float perry_truncdfsf2vfp(double a) { return (float)a; }
int perry_fixdfsivfp(double a) LIBGCC(__fixdfsivfp);
int perry_fixdfsivfp(double a) { return (int)a; }
int perry_fixsfsivfp(float a) LIBGCC(__fixsfsivfp);
int perry_fixsfsivfp(float a) { return (int)a; }
unsigned perry_fixunsdfsivfp(double a) LIBGCC(__fixunsdfsivfp);
unsigned perry_fixunsdfsivfp(double a) { return (unsigned)a; }
unsigned perry_fixunssfsivfp(float a) LIBGCC(__fixunssfsivfp);
unsigned perry_fixunssfsivfp(float a) { return (unsigned)a; }
double perry_floatsidfvfp(int a) LIBGCC(__floatsidfvfp);
double perry_floatsidfvfp(int a) { return a; }
float perry_floatsisfvfp(int a) LIBGCC(__floatsisfvfp);
float perry_floatsisfvfp(int a) { return (float)a; }
double perry_floatunssidfvfp(unsigned a) LIBGCC(__floatunssidfvfp);
double perry_floatunssidfvfp(unsigned a) { return a; }
float perry_floatunssisfvfp(unsigned a) LIBGCC(__floatunssisfvfp);
float perry_floatunssisfvfp(unsigned a) { return (float)a; }

// Conversions with 64-bit integers, in core registers too.
long long perry_fixdfdi(double a) LIBGCC(__fixdfdi);
long long perry_fixdfdi(double a) { return (long long)a; }
long long perry_fixsfdi(float a) LIBGCC(__fixsfdi);
long long perry_fixsfdi(float a) { return (long long)a; }
unsigned long long perry_fixunsdfdi(double a) LIBGCC(__fixunsdfdi);
unsigned long long perry_fixunsdfdi(double a) { return (unsigned long long)a; }
unsigned long long perry_fixunssfdi(float a) LIBGCC(__fixunssfdi);
unsigned long long perry_fixunssfdi(float a) { return (unsigned long long)a; }
double perry_floatdidf(long long a) LIBGCC(__floatdidf);
double perry_floatdidf(long long a) { return (double)a; }
float perry_floatdisf(long long a) LIBGCC(__floatdisf);
float perry_floatdisf(long long a) { return (float)a; }
double perry_floatundidf(unsigned long long a) LIBGCC(__floatundidf);
double perry_floatundidf(unsigned long long a) { return (double)a; }
float perry_floatundisf(unsigned long long a) LIBGCC(__floatundisf);
float perry_floatundisf(unsigned long long a) { return (float)a; }

// Integer division. Dividing by zero gives zero, as libgcc's does on ARM.
int perry_divsi3(int a, int b) LIBGCC(__divsi3);
int perry_divsi3(int a, int b) { return b ? (a == (-2147483647 - 1) && b == -1 ? a : a / b) : 0; }
int perry_modsi3(int a, int b) LIBGCC(__modsi3);
int perry_modsi3(int a, int b) { return b ? (b == -1 ? 0 : a % b) : a; }
unsigned perry_udivsi3(unsigned a, unsigned b) LIBGCC(__udivsi3);
unsigned perry_udivsi3(unsigned a, unsigned b) { return b ? a / b : 0; }
unsigned perry_umodsi3(unsigned a, unsigned b) LIBGCC(__umodsi3);
unsigned perry_umodsi3(unsigned a, unsigned b) { return b ? a % b : a; }
long long perry_divdi3(long long a, long long b) LIBGCC(__divdi3);
long long perry_divdi3(long long a, long long b) { return b ? (b == -1 ? (long long)(0 - (unsigned long long)a) : a / b) : 0; }
long long perry_moddi3(long long a, long long b) LIBGCC(__moddi3);
long long perry_moddi3(long long a, long long b) { return b ? (b == -1 ? 0 : a % b) : a; }
long long perry_muldi3(long long a, long long b) LIBGCC(__muldi3);
long long perry_muldi3(long long a, long long b) { return (long long)((unsigned long long)a * (unsigned long long)b); }
unsigned long long perry_udivdi3(unsigned long long a, unsigned long long b) LIBGCC(__udivdi3);
unsigned long long perry_udivdi3(unsigned long long a, unsigned long long b) { return b ? a / b : 0; }
unsigned long long perry_umoddi3(unsigned long long a, unsigned long long b) LIBGCC(__umoddi3);
unsigned long long perry_umoddi3(unsigned long long a, unsigned long long b) { return b ? a % b : a; }

// Division that also gives the remainder, through a pointer.
int perry_divmodsi4(int a, int b, int *remainder) LIBGCC(__divmodsi4);
int perry_divmodsi4(int a, int b, int *remainder) {
    if (remainder)
        *remainder = perry_modsi3(a, b);
    return perry_divsi3(a, b);
}
unsigned perry_udivmodsi4(unsigned a, unsigned b, unsigned *remainder) LIBGCC(__udivmodsi4);
unsigned perry_udivmodsi4(unsigned a, unsigned b, unsigned *remainder) {
    if (remainder)
        *remainder = perry_umodsi3(a, b);
    return perry_udivsi3(a, b);
}
long long perry_divmoddi4(long long a, long long b, long long *remainder) LIBGCC(__divmoddi4);
long long perry_divmoddi4(long long a, long long b, long long *remainder) {
    if (remainder)
        *remainder = perry_moddi3(a, b);
    return perry_divdi3(a, b);
}
unsigned long long perry_udivmoddi4(unsigned long long a, unsigned long long b, unsigned long long *remainder)
    LIBGCC(__udivmoddi4);
unsigned long long perry_udivmoddi4(unsigned long long a, unsigned long long b, unsigned long long *remainder) {
    if (remainder)
        *remainder = perry_umoddi3(a, b);
    return perry_udivdi3(a, b);
}

// operator new, new[], delete and delete[], mangled with Darwin's 32-bit
// size_t (unsigned long). A failed allocation ends the program, as an
// exception nothing catches would.
void *perry_operator_new(size_t size) __asm__("__Znwm") __attribute__((visibility("default"), used));
void *perry_operator_new(size_t size) {
    void *block = malloc(size ? size : 1);
    if (!block)
        abort();
    return block;
}
void *perry_operator_new_array(size_t size) __asm__("__Znam") __attribute__((visibility("default"), used));
void *perry_operator_new_array(size_t size) { return perry_operator_new(size); }
void perry_operator_delete(void *block) __asm__("__ZdlPv") __attribute__((visibility("default"), used));
void perry_operator_delete(void *block) { free(block); }
void perry_operator_delete_array(void *block) __asm__("__ZdaPv") __attribute__((visibility("default"), used));
void perry_operator_delete_array(void *block) { free(block); }

// The rest of what C++ code built with GCC takes from libstdc++ when it
// neither throws nor casts dynamically: the function a pure virtual
// function's place in a vtable calls, the vtables its classes' type
// information is made with, which only those would read, and the
// personality routine its cleanups name, which only an exception would
// call.
void perry_cxa_pure_virtual(void) __asm__("___cxa_pure_virtual") __attribute__((visibility("default"), used));
void perry_cxa_pure_virtual(void) {
    static const char message[] = "pure virtual method called\n";
    if (write(2, message, sizeof(message) - 1) < 0) { }
    abort();
}
void *const perry_class_type_info_vtable[16] __asm__("__ZTVN10__cxxabiv117__class_type_infoE")
    __attribute__((visibility("default"), used)) = { 0 };
void *const perry_si_class_type_info_vtable[16] __asm__("__ZTVN10__cxxabiv120__si_class_type_infoE")
    __attribute__((visibility("default"), used)) = { 0 };
void *const perry_vmi_class_type_info_vtable[16] __asm__("__ZTVN10__cxxabiv121__vmi_class_type_infoE")
    __attribute__((visibility("default"), used)) = { 0 };
int perry_gxx_personality_sj0(int version, int actions, unsigned long long exception_class, void *exception, void *context)
    __asm__("___gxx_personality_sj0") __attribute__((visibility("default"), used));
int perry_gxx_personality_sj0(int version, int actions, unsigned long long exception_class, void *exception, void *context) {
    (void)version, (void)actions, (void)exception_class, (void)exception, (void)context;
    return 8;   // _URC_CONTINUE_UNWIND: nothing here catches
}

#endif

#if defined(__i386__)
// Darwin's names for 64-bit division, which libgcc on Linux has privately.
#define I386_LIBGCC(name) __asm__("_" #name) __attribute__((visibility("default"), used))

long long perry_i386_divdi3(long long a, long long b) I386_LIBGCC(__divdi3);
long long perry_i386_divdi3(long long a, long long b) { return a / b; }
long long perry_i386_moddi3(long long a, long long b) I386_LIBGCC(__moddi3);
long long perry_i386_moddi3(long long a, long long b) { return a % b; }
unsigned long long perry_i386_udivdi3(unsigned long long a, unsigned long long b) I386_LIBGCC(__udivdi3);
unsigned long long perry_i386_udivdi3(unsigned long long a, unsigned long long b) { return a / b; }
unsigned long long perry_i386_umoddi3(unsigned long long a, unsigned long long b) I386_LIBGCC(__umoddi3);
unsigned long long perry_i386_umoddi3(unsigned long long a, unsigned long long b) { return a % b; }
#endif
