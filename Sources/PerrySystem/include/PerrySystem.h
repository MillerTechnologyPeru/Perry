#ifndef PERRY_SYSTEM_H
#define PERRY_SYSTEM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

// libPerrySystem: the Darwin libSystem ABI implemented over glibc.
//
// Exported ELF symbols use the exact Mach-O symbol names (with the leading
// underscore), so the loader binds an import of `_printf` from
// /usr/lib/libSystem.B.dylib to the ELF symbol `_printf` in this library.

// Declares a function or variable under its Darwin Mach-O name.
#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

// For a Darwin function with floating-point arguments or results: on armv7,
// Darwin passes them in core registers, as AAPCS's base standard does, where
// glibc's armhf passes them in VFP registers. AAPCS also starts a 64-bit
// argument at an even register, which Darwin does not, so only functions whose
// 64-bit arguments start at r0 or r2 (or on the stack after an even number of
// words) take it as they are.
#if defined(__arm__)
#define DARWIN_FLOAT_ABI __attribute__((pcs("aapcs")))
#else
#define DARWIN_FLOAT_ABI
#endif

// Runs `call`, which may run Darwin code, from a function glibc's or another
// Linux library's code called. On armv7 Darwin's code may change r9, which
// Linux's keeps across calls; Perry's code leaves it alone (it is built with
// -ffixed-r9), so keeping r9 here keeps it for the Linux code that called.
#if defined(__arm__)
#define PERRY_KEEP_R9(call) do { \
        unsigned long perry_r9; \
        __asm__ volatile("mov %0, r9" : "=r"(perry_r9)); \
        call; \
        __asm__ volatile("mov r9, %0" : : "r"(perry_r9) : "memory"); \
    } while (0)
#else
#define PERRY_KEEP_R9(call) do { call; } while (0)
#endif

// The device Darwin code is told it runs on: an arm64 iPhone, or for armv7
// programs an iPhone 4S (armv7, iOS 5 to 9), with Darwin's page size.
#if defined(__arm__)
#define PERRY_HW_MACHINE "iPhone4,1"
#define PERRY_HW_MODEL "N94AP"
#define PERRY_CPU_TYPE 12               // CPU_TYPE_ARM
#define PERRY_CPU_SUBTYPE 9             // CPU_SUBTYPE_ARM_V7
#define PERRY_CPU_FREQUENCY 800000000u
#define PERRY_PAGE_SIZE 4096
#define PERRY_KINFO_PROC_SIZE 492
#elif defined(__i386__)
#define PERRY_HW_MACHINE "i386"
#define PERRY_HW_MODEL "MacBook5,1"
#define PERRY_CPU_TYPE 7                // CPU_TYPE_I386
#define PERRY_CPU_SUBTYPE 3             // CPU_SUBTYPE_I386_ALL
#define PERRY_CPU_FREQUENCY 2000000000u
#define PERRY_PAGE_SIZE 4096
#define PERRY_KINFO_PROC_SIZE 492
#elif defined(__x86_64__)
#define PERRY_HW_MACHINE "x86_64"
#define PERRY_HW_MODEL "Macmini8,1"
#define PERRY_CPU_TYPE 0x01000007       // CPU_TYPE_X86_64
#define PERRY_CPU_SUBTYPE 3             // CPU_SUBTYPE_X86_64_ALL
#define PERRY_CPU_FREQUENCY 3200000000u
#define PERRY_PAGE_SIZE 4096
#define PERRY_KINFO_PROC_SIZE 648
#else
#define PERRY_HW_MACHINE "iPhone14,7"
#define PERRY_HW_MODEL "D27AP"
#define PERRY_CPU_TYPE 0x0100000c       // CPU_TYPE_ARM64
#define PERRY_CPU_SUBTYPE 0
#define PERRY_CPU_FREQUENCY 3230000000u
#define PERRY_PAGE_SIZE 16384
#define PERRY_KINFO_PROC_SIZE 648
#endif

// Darwin errno values (sys/errno.h). Values 1-34 match Linux except EAGAIN
// and EDEADLK.
int perry_darwin_errno_from_linux(int linux_errno);
int perry_linux_errno_from_darwin(int darwin_errno);

// Darwin's __error(): the calling thread's Darwin-numbered errno.
int *darwin_error(void) DARWIN_SYMBOL(__error);

// Linux's number for a Darwin signal, or -1 where Linux has none.
int perry_signal_to_linux(int signal);

// A thread's pthread_t as Darwin code has it, and glibc's for one Darwin code
// gives. On x86 they differ: Darwin's pthread_cleanup_push and _pop are
// macros compiled into apps, which link their handlers through the word
// after `sig` in Darwin's struct _opaque_pthread_t, and that word of glibc's
// pthread_t is its thread's DTV there. Elsewhere they are the same.
#include <pthread.h>
#if defined(__i386__) || defined(__x86_64__)
pthread_t perry_pthread_to_darwin(pthread_t thread);
pthread_t perry_pthread_to_linux(pthread_t thread);
#else
static inline pthread_t perry_pthread_to_darwin(pthread_t thread) { return thread; }
static inline pthread_t perry_pthread_to_linux(pthread_t thread) { return thread; }
#endif

// A section's header in a Mach-O image's load commands (section_64).
struct darwin_section_64 {
    char sectname[16], segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};

// The section's header in a mapped image, or NULL.
const struct darwin_section_64 *darwin_getsectbynamefromheader_64(const void *header, const char *segment, const char *section)
    DARWIN_SYMBOL(getsectbynamefromheader_64);

// mmap where the kernel picks the address, placed and sized by Darwin's
// 16 KB pages. `flags` are Linux's.
void *perry_map_pages(size_t length, int protection, int flags, int fd, off_t offset);

// The loader's symbol lookup (perry_startup_info.lookup_symbol), once
// libSystem has started: by Mach-O name, in a library or (NULL) anywhere.
extern void *(*perry_system_lookup)(const char *install_name, const char *name);
// The main executable's mach header, for what the system says it is.
extern const void *perry_system_main_header;
// For a macOS program, the Darwin release of its SDK's macOS (25.5 for
// macOS 26.5); zeros for others.
typedef struct { int darwin, minor; } perry_macos_release;
perry_macos_release perry_system_macos_release(void);

#if defined(__arm__)
#include <stddef.h>
// Darwin armv7's varargs for a printf-style format, in glibc armhf's layout:
// the bytes `format`'s arguments take, and, when `out` is not NULL (8-byte
// aligned, that big), the arguments copied there from the Darwin va_list.
size_t perry_repack_arguments(const char *format, const void *darwin_ap, void *out);
#endif

// The loader's way to load a Mach-O library while the program runs
// (perry_startup_info.load_library); false if the file isn't one.
extern bool (*perry_system_load_library)(const char *path);

// The loader's dlsym(RTLD_NEXT): `name`, a Mach-O name, in what was loaded
// after the image `caller` is in (perry_startup_info.lookup_symbol_after).
extern void *(*perry_system_lookup_after)(const void *caller, const char *name);

#endif
