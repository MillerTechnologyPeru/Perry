// A crash report for finding where a program fails: with
// PERRY_CRASH_REPORT=1, a fatal signal prints the faulting thread's
// registers and its frames, by following frame pointers, each as the
// Mach-O image and offset it is in (for atos -l 0), or the Linux library
// and symbol. On armv7 the frames are Darwin code's, chained through r7. Use it with PERRY_KEEP_CRASH_HANDLERS=1, so an app's own crash
// reporter doesn't take the signals first.

#define _GNU_SOURCE
#include "image.h"

#include <dlfcn.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ucontext.h>
#include <unistd.h>

static perry_loader *crash_loader;

static void crash_print(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void crash_print(const char *format, ...) {
    char line[1024];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);
    if (length > 0)
        (void)!write(2, line, (size_t)length < sizeof(line) ? (size_t)length : sizeof(line) - 1);
}

static void describe(const char *label, uintptr_t address) {
    for (perry_image *image = crash_loader ? crash_loader->images : NULL; image; image = image->next) {
        uintptr_t base = (uintptr_t)image->base;
        if (address >= base && address < base + image->vm_size) {
            const char *name = image->path ? strrchr(image->path, '/') : NULL;
            crash_print("  %s 0x%016lx %s+0x%lx\n", label, (unsigned long)address,
                        name ? name + 1 : (image->path ? image->path : "?"), (unsigned long)(address - base));
            return;
        }
    }
    Dl_info info;
    if (address && dladdr((void *)address, &info) && info.dli_fname) {
        const char *name = strrchr(info.dli_fname, '/');
        if (info.dli_sname)
            crash_print("  %s 0x%016lx %s(%s+0x%lx)\n", label, (unsigned long)address, name ? name + 1 : info.dli_fname,
                        info.dli_sname, (unsigned long)(address - (uintptr_t)info.dli_saddr));
        else
            crash_print("  %s 0x%016lx %s+0x%lx\n", label, (unsigned long)address, name ? name + 1 : info.dli_fname,
                        (unsigned long)(address - (uintptr_t)info.dli_fbase));
        return;
    }
    crash_print("  %s 0x%016lx\n", label, (unsigned long)address);
}

#if defined(__arm__)
// Darwin's armv7 code keeps its frame records, {previous r7, return
// address}, in r7; they are 4-byte aligned.
#define FRAME_POINTER(machine) ((machine)->arm_r7)
#define FRAME_ALIGNMENT 3

static void print_registers(const mcontext_t *machine) {
    describe("pc", machine->arm_pc);
    describe("lr", machine->arm_lr);
    crash_print("  sp 0x%08lx r7 0x%08lx cpsr 0x%08lx\n", machine->arm_sp, machine->arm_r7, machine->arm_cpsr);
    const unsigned long r[] = {
        machine->arm_r0, machine->arm_r1, machine->arm_r2, machine->arm_r3, machine->arm_r4, machine->arm_r5,
        machine->arm_r6, machine->arm_r7, machine->arm_r8, machine->arm_r9, machine->arm_r10, machine->arm_fp,
        machine->arm_ip,
    };
    for (int i = 0; i < 13; i += 4) {
        crash_print("  r%-2d %08lx", i, r[i]);
        for (int j = i + 1; j < i + 4 && j < 13; j++)
            crash_print(" r%-2d %08lx", j, r[j]);
        crash_print("\n");
    }
}
#elif defined(__i386__)
#define FRAME_POINTER(machine) ((uintptr_t)(machine)->gregs[REG_EBP])
#define FRAME_ALIGNMENT 3

static void print_registers(const mcontext_t *machine) {
    describe("eip", (uintptr_t)machine->gregs[REG_EIP]);
    crash_print("  esp %08lx ebp %08lx eflags %08lx\n", (unsigned long)machine->gregs[REG_ESP],
                (unsigned long)machine->gregs[REG_EBP], (unsigned long)machine->gregs[REG_EFL]);
    crash_print("  eax %08lx ebx %08lx ecx %08lx edx %08lx\n", (unsigned long)machine->gregs[REG_EAX],
                (unsigned long)machine->gregs[REG_EBX], (unsigned long)machine->gregs[REG_ECX],
                (unsigned long)machine->gregs[REG_EDX]);
    crash_print("  esi %08lx edi %08lx\n", (unsigned long)machine->gregs[REG_ESI], (unsigned long)machine->gregs[REG_EDI]);
}
#elif defined(__x86_64__)
#define FRAME_POINTER(machine) ((uintptr_t)(machine)->gregs[REG_RBP])
#define FRAME_ALIGNMENT 7

static void print_registers(const mcontext_t *machine) {
    static const struct { const char *name; int index; } registers[] = {
        {"rax", REG_RAX}, {"rbx", REG_RBX}, {"rcx", REG_RCX}, {"rdx", REG_RDX},
        {"rsi", REG_RSI}, {"rdi", REG_RDI}, {"r8", REG_R8}, {"r9", REG_R9},
        {"r10", REG_R10}, {"r11", REG_R11}, {"r12", REG_R12}, {"r13", REG_R13},
        {"r14", REG_R14}, {"r15", REG_R15},
    };
    describe("rip", (uintptr_t)machine->gregs[REG_RIP]);
    crash_print("  rsp 0x%016lx rbp 0x%016lx\n", (unsigned long)machine->gregs[REG_RSP], (unsigned long)machine->gregs[REG_RBP]);
    for (size_t i = 0; i < sizeof(registers) / sizeof(registers[0]); i += 2)
        crash_print("  %-3s %016lx %-3s %016lx\n", registers[i].name, (unsigned long)machine->gregs[registers[i].index],
                    registers[i + 1].name, (unsigned long)machine->gregs[registers[i + 1].index]);
}
#else
#define FRAME_POINTER(machine) ((machine)->regs[29])
#define FRAME_ALIGNMENT 7

static void print_registers(const mcontext_t *machine) {
    describe("pc", machine->pc);
    describe("lr", machine->regs[30]);
    crash_print("  sp 0x%016lx fp 0x%016lx\n", (unsigned long)machine->sp, (unsigned long)machine->regs[29]);
    for (int i = 0; i < 29; i += 4)
        crash_print("  x%-2d %016lx x%-2d %016lx x%-2d %016lx x%-2d %016lx\n", i, (unsigned long)machine->regs[i],
                    i + 1, (unsigned long)machine->regs[i + 1], i + 2, (unsigned long)(i + 2 < 31 ? machine->regs[i + 2] : 0),
                    i + 3, (unsigned long)(i + 3 < 31 ? machine->regs[i + 3] : 0));
}
#endif

static void crash_handler(int signal, siginfo_t *info, void *raw_context) {
    ucontext_t *context = raw_context;
    mcontext_t *machine = &context->uc_mcontext;
    crash_print("perry: crash: signal %d (%s) at 0x%lx, thread %ld\n", signal, strsignal(signal),
                (unsigned long)(uintptr_t)info->si_addr, (long)gettid());
    print_registers(machine);
    // Frame records are {previous fp, return address}, ascending the stack.
#if defined(__arm__)
    uintptr_t fp = FRAME_POINTER(machine), low = machine->arm_sp;
#elif defined(__i386__)
    uintptr_t fp = FRAME_POINTER(machine), low = (uintptr_t)machine->gregs[REG_ESP];
#elif defined(__x86_64__)
    uintptr_t fp = FRAME_POINTER(machine), low = (uintptr_t)machine->gregs[REG_RSP];
#else
    uintptr_t fp = FRAME_POINTER(machine), low = machine->sp;
#endif
    for (int frame = 0; frame < 48 && fp && (fp & FRAME_ALIGNMENT) == 0 && fp >= low && fp - low < (64 << 20); frame++) {
        uintptr_t *record = (uintptr_t *)fp;
        uintptr_t next = record[0], ret = record[1];
        if (!ret)
            break;
        char label[16];
        snprintf(label, sizeof(label), "#%-2d", frame);
        describe(label, ret);
        low = fp;
        fp = next;
    }
    struct sigaction action = { .sa_handler = SIG_DFL };
    sigaction(signal, &action, NULL);
    raise(signal);
}

void perry_install_crash_reporter(perry_loader *loader) {
    const char *setting = getenv("PERRY_CRASH_REPORT");
    if (!setting || !*setting || strcmp(setting, "0") == 0)
        return;
    crash_loader = loader;
    static char alternate[1 << 16];
    stack_t stack = { .ss_sp = alternate, .ss_size = sizeof(alternate) };
    sigaltstack(&stack, NULL);
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = crash_handler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP, SIGABRT };
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
        // libSystem's provider owns SIGILL on cores that lack instructions
        // Apple silicon has, to rewrite them; a real one reaches the
        // default there.
        struct sigaction current;
        if (signals[i] == SIGILL && sigaction(SIGILL, NULL, &current) == 0 && (current.sa_flags & SA_SIGINFO))
            continue;
        sigaction(signals[i], &action, NULL);
    }
}
