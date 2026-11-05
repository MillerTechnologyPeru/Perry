// A crash report for finding where a program fails: with
// PERRY_CRASH_REPORT=1, a fatal signal prints the faulting thread's
// registers and its frames, by following frame pointers, each as the
// Mach-O image and offset it is in (for atos -l 0), or the Linux library
// and symbol. Use it with PERRY_KEEP_CRASH_HANDLERS=1, so an app's own crash
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

static void crash_handler(int signal, siginfo_t *info, void *raw_context) {
    ucontext_t *context = raw_context;
    mcontext_t *machine = &context->uc_mcontext;
    crash_print("perry: crash: signal %d (%s) at 0x%lx, thread %ld\n", signal, strsignal(signal),
                (unsigned long)(uintptr_t)info->si_addr, (long)gettid());
    describe("pc", machine->pc);
    describe("lr", machine->regs[30]);
    crash_print("  sp 0x%016lx fp 0x%016lx\n", (unsigned long)machine->sp, (unsigned long)machine->regs[29]);
    for (int i = 0; i < 29; i += 4)
        crash_print("  x%-2d %016lx x%-2d %016lx x%-2d %016lx x%-2d %016lx\n", i, (unsigned long)machine->regs[i],
                    i + 1, (unsigned long)machine->regs[i + 1], i + 2, (unsigned long)(i + 2 < 31 ? machine->regs[i + 2] : 0),
                    i + 3, (unsigned long)(i + 3 < 31 ? machine->regs[i + 3] : 0));
    // Frame records are {previous fp, return address}, ascending the stack.
    uintptr_t fp = machine->regs[29], low = machine->sp;
    for (int frame = 0; frame < 48 && fp && (fp & 7) == 0 && fp >= low && fp - low < (64 << 20); frame++) {
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
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
        sigaction(signals[i], &action, NULL);
}
