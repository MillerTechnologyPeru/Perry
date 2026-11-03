#ifndef PERRY_WRAPPED_H
#define PERRY_WRAPPED_H

// Providers that bind a Darwin library's imports to the Linux build of the
// same library (libxml2, zlib, SQLite…). On arm64 most functions have the
// same ABI on both, so a provider's perry_provider_symbol hook resolves each
// Mach-O name in the Linux library; the ELF symbols the provider defines
// itself, its thunks for what differs, are found first.

#ifndef __ASSEMBLER__

#include <pthread.h>

/// The Linux library a provider wraps, found from one function in it, or
/// opened by its soname.
typedef struct perry_wrapped_library {
    /// A function the library defines, to locate it by.
    const void *anchor;
    /// Or the library's soname, opened on its own (RTLD_LOCAL): for a
    /// library that the process may also have a namesake of, as libc++abi's
    /// __cxa functions are libstdc++'s too, or that it may not have at all.
    const char *soname;
    pthread_mutex_t lock;
    int loaded;
    void *handle;
    void *base;
} perry_wrapped_library;

#define PERRY_WRAPPED_LIBRARY(anchor_function) \
    { (const void *)(anchor_function), 0, PTHREAD_MUTEX_INITIALIZER, 0, 0, 0 }

#define PERRY_WRAPPED_SONAME(name) \
    { 0, (name), PTHREAD_MUTEX_INITIALIZER, 0, 0, 0 }

/// The library's symbol for a Mach-O name ("_deflate" is deflate), or NULL.
/// Only symbols the library itself defines count: names it imports from
/// libc and elsewhere are not its API. `allowed`, if not NULL, is a
/// NULL-terminated list of the only names (without the underscore) to bind.
void *perry_wrapped_symbol(perry_wrapped_library *library, const char *name, const char *const *allowed);

#endif

#ifdef __ASSEMBLER__

// Darwin entry points for variadic and va_list functions.
//
// Apple's arm64 ABI passes variadic arguments on the stack in 8-byte slots
// and makes va_list a plain pointer to them; AAPCS64 (Linux) starts
// variadic arguments in registers and makes va_list a 32-byte struct,
// passed by reference. Both thunks build an AAPCS64 va_list whose register
// save areas are empty (gr_offs and vr_offs are 0), so va_arg reads every
// argument from Darwin's stack slots, and call a va_list function.

// VARIADIC darwin_name, va_function, fixed_count
//
// For f(fixed..., ...): the variadic arguments start at the caller's sp,
// and the va_list goes in the register after the fixed arguments.
.macro VARIADIC name, target, nfixed
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    add x9, sp, #48             // variadic arguments start at the caller's sp
    stp x9, xzr, [sp, #16]      // __stack, __gr_top
    stp xzr, xzr, [sp, #32]     // __vr_top, __gr_offs = 0, __vr_offs = 0
    add x\nfixed, sp, #16
    bl \target
    ldp x29, x30, [sp], #48
    ret
    .size \name, . - \name
.endm

// VA_LIST darwin_name, va_function, index
//
// For f(fixed..., va_list): register x<index> holds Darwin's va_list, the
// address of the next stack slot; it is replaced by an AAPCS64 va_list
// over the same slots.
.macro VA_LIST name, target, index
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x\index, xzr, [sp, #16] // __stack, __gr_top
    stp xzr, xzr, [sp, #32]     // __vr_top, __gr_offs = 0, __vr_offs = 0
    add x\index, sp, #16
    bl \target
    ldp x29, x30, [sp], #48
    ret
    .size \name, . - \name
.endm

#endif

#endif
