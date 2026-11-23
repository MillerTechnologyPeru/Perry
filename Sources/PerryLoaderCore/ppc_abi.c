// Moving arguments between Darwin's ppc ABI and Linux's (SysV), by type
// encoding, for functions and methods whose arguments are not all words.
//
// Darwin, as Apple's GCC compiles calls (checked with Xcode 3.2.6's cc1):
//
//   - words go in r3-r10, then the parameter area at 24(r1), which has a word
//     for every argument, those in registers included
//   - a long long takes the next two words, high first, unaligned
//   - a double or float goes in the next of f1-f13 and also takes the words
//     it would have (two, or one), which stay unset; past f13 it is in those
//     words
//   - a structure goes in its words, as it is laid out in memory, unless it
//     holds just one float or double, which goes as that does
//
// Linux's (SysV), for the same C signature, as Swift's types give it on ppc
// (ObjCValue's types are the types themselves there, as on i386):
//
//   - words go in r3-r10, then from 8(r1)
//   - a long long takes an even register pair (r3:r4, r5:r6, ...), or 8
//     aligned bytes of the stack
//   - a double or float goes in f1-f8, then 8 aligned bytes of the stack,
//     and takes no general registers
//   - a structure goes as a pointer to a copy of it
//
// Results are in the same registers on both: r3, r3:r4 for a long long, f1
// for floating point, and memory through a pointer in r3, before the
// arguments, for a structure.

#define _GNU_SOURCE

#if defined(__powerpc__) && !defined(__powerpc64__)

#include "image.h"
#include "log.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

void perry_ppc_darwin_trampoline(void);
void perry_ppc_invoke_sysv(void *function, const uint32_t gprs[8], const double fprs[8], const uint32_t *stack,
                           uint32_t stack_words, perry_ppc_registers *result);
void perry_ppc_invoke_darwin(void *function, const uint32_t gprs[8], const double fprs[13], const uint32_t *words,
                             uint32_t word_count, perry_ppc_registers *result);
void perry_ppc_darwin_from_linux(void);

// MARK: - Plans

enum kind {
    KIND_WORD,      // anything of four bytes or less but a float
    KIND_PAIR,      // long long
    KIND_DOUBLE,
    KIND_FLOAT,
    KIND_STRUCT,    // `words` words
    KIND_STRUCT_DOUBLE, // a structure of one double: in an FPR on Darwin, copied on Linux
    KIND_STRUCT_FLOAT,  // and of one float
    KIND_VOID,      // results only
};

typedef struct plan_value {
    enum kind kind;
    uint32_t words;
    uint32_t size;  // in memory, as Darwin lays it out
    char code;      // the encoding's type character
} plan_value;

enum { MAX_ARGUMENTS = 32 };

static bool is_structure(enum kind kind) {
    return kind == KIND_STRUCT || kind == KIND_STRUCT_DOUBLE || kind == KIND_STRUCT_FLOAT;
}

typedef struct perry_ppc_plan {
    void *function;
    plan_value result;
    uint32_t count;
    plan_value arguments[MAX_ARGUMENTS];
} perry_ppc_plan;

static const char *skip_qualifiers(const char *p) {
    while (*p && strchr("rnNoORVA+", *p))
        p++;
    return p;
}

static const char *skip_digits(const char *p) {
    while (*p == '-' || (*p >= '0' && *p <= '9'))
        p++;
    return p;
}

// The size and alignment of one encoded type as 32-bit Darwin lays it out,
// and where its encoding ends. In a structure a double is aligned to 4 but
// for the first member, which aligns the whole structure to 8 (the "power"
// rule); a long long is aligned to 8.
static const char *measure(const char *p, uint32_t *size, uint32_t *align, enum kind *single_fp) {
    p = skip_qualifiers(p);
    *single_fp = KIND_VOID;
    switch (*p) {
    case 'c': case 'C': case 'B': *size = 1; *align = 1; return p + 1;
    case 's': case 'S': *size = 2; *align = 2; return p + 1;
    case 'i': case 'I': case 'l': case 'L': case '*': case '@': case '#': case ':': case '?':
        *size = 4; *align = 4;
        p++;
        if (p[-1] == '@' && *p == '"') {        // @"ClassName"
            p = strchr(p + 1, '"');
            p = p ? p + 1 : p;
        } else if (p[-1] == '@' && *p == '?') { // a block
            p++;
        }
        return p;
    case 'f': *size = 4; *align = 4; *single_fp = KIND_FLOAT; return p + 1;
    case 'd': *size = 8; *align = 8; *single_fp = KIND_DOUBLE; return p + 1;
    case 'q': case 'Q': *size = 8; *align = 8; return p + 1;
    case 'D': *size = 16; *align = 16; return p + 1;   // long double
    case 'v': *size = 0; *align = 1; return p + 1;
    case 'b': {                                         // a bit field: as its int
        *size = 4; *align = 4;
        return skip_digits(p + 1);
    }
    case '^': {
        uint32_t s, a;
        enum kind k;
        *size = 4; *align = 4;
        return measure(p + 1, &s, &a, &k);
    }
    case '[': {
        uint32_t count = (uint32_t)strtoul(p + 1, NULL, 10);
        p = skip_digits(p + 1);
        uint32_t s, a;
        enum kind k;
        p = measure(p, &s, &a, &k);
        *size = s * count;
        *align = a;
        return *p == ']' ? p + 1 : p;
    }
    case '{': case '(': {
        bool is_union = *p == '(';
        char close = is_union ? ')' : '}';
        p++;
        // The name, up to '=', or the whole of an opaque structure.
        const char *equals = p;
        int depth = 0;
        while (*equals && !(depth == 0 && (*equals == '=' || *equals == close))) {
            if (*equals == '{' || *equals == '(') depth++;
            if (*equals == '}' || *equals == ')') depth--;
            equals++;
        }
        uint32_t total = 0, max_align = 1, members = 0;
        enum kind only = KIND_VOID;
        if (*equals == '=') {
            p = equals + 1;
            while (*p && *p != close) {
                if (*p == '"') {                        // a member's name
                    const char *end = strchr(p + 1, '"');
                    p = end ? end + 1 : p + 1;
                    continue;
                }
                uint32_t s, a;
                enum kind k;
                p = measure(p, &s, &a, &k);
                if (k == KIND_DOUBLE && members > 0 && !is_union)
                    a = 4;
                if (is_union) {
                    total = s > total ? s : total;
                } else {
                    total = (total + a - 1) & ~(a - 1);
                    total += s;
                }
                if (a > max_align)
                    max_align = a;
                only = members == 0 ? k : KIND_VOID;
                members++;
            }
        } else {
            p = equals;
        }
        if (*p == close)
            p++;
        total = (total + max_align - 1) & ~(max_align - 1);
        *size = total;
        *align = max_align;
        // A structure of one float or double is passed as that.
        *single_fp = members == 1 ? only : KIND_VOID;
        return p;
    }
    default:
        *size = 4; *align = 4;
        return *p ? p + 1 : p;
    }
}

static const char *value(const char *p, plan_value *out, bool *ok) {
    uint32_t size, align;
    enum kind single;
    const char *start = skip_qualifiers(p);
    p = measure(start, &size, &align, &single);
    out->size = size;
    out->code = *start;
    switch (*start) {
    case 'v': out->kind = KIND_VOID; break;
    case 'f': out->kind = KIND_FLOAT; break;
    case 'd': out->kind = KIND_DOUBLE; break;
    case 'q': case 'Q': out->kind = KIND_PAIR; break;
    case 'D': *ok = false; break;           // long double: not yet
    case '{': case '(':
        if (single == KIND_DOUBLE)
            out->kind = KIND_STRUCT_DOUBLE;
        else if (single == KIND_FLOAT)
            out->kind = KIND_STRUCT_FLOAT;
        else {
            out->kind = KIND_STRUCT;
            out->words = (size + 3) / 4;
        }
        break;
    default: out->kind = KIND_WORD; break;
    }
    return skip_digits(p);
}

// A method's or function's type encoding as a plan, or false when it has
// something this cannot move.
static bool parse(const char *types, perry_ppc_plan *plan) {
    bool ok = true;
    memset(plan, 0, sizeof(*plan));
    const char *p = value(types, &plan->result, &ok);
    while (ok && *p) {
        if (plan->count == MAX_ARGUMENTS)
            return false;
        p = value(p, &plan->arguments[plan->count++], &ok);
    }
    return ok;
}

// Whether a plan's arguments all pass the same in both ABIs: words only.
// Results always do (r3, r3:r4, f1, or memory through a pointer in r3).
static bool all_words(const perry_ppc_plan *plan) {
    for (uint32_t i = 0; i < plan->count; i++)
        if (plan->arguments[i].kind != KIND_WORD)
            return false;
    return true;
}

// MARK: - Linux's side of a call

// Where Linux's ABI puts a call's arguments, as they are laid out one after
// another: by perry_ppc_from_darwin to make a call, and by
// perry_ppc_call_darwin to read one.
typedef struct sysv_call {
    uint32_t gprs[8];
    double fprs[8];
    uint32_t stack[MAX_ARGUMENTS * 2 + 8];
    uint32_t gpr, fpr, stack_count;
} sysv_call;

static void sysv_align_stack(sysv_call *call) {
    if (call->stack_count & 1)
        call->stack_count++;
}

static void sysv_put_word(sysv_call *call, uint32_t word) {
    if (call->gpr < 8)
        call->gprs[call->gpr++] = word;
    else
        call->stack[call->stack_count++] = word;
}

static void sysv_put_pair(sysv_call *call, uint32_t high, uint32_t low) {
    if (call->gpr & 1)
        call->gpr++;
    if (call->gpr <= 6) {
        call->gprs[call->gpr++] = high;
        call->gprs[call->gpr++] = low;
    } else {
        call->gpr = 8;
        sysv_align_stack(call);
        call->stack[call->stack_count++] = high;
        call->stack[call->stack_count++] = low;
    }
}

static void sysv_put_double(sysv_call *call, double value) {
    if (call->fpr < 8) {
        call->fprs[call->fpr++] = value;
    } else {
        uint64_t bits;
        memcpy(&bits, &value, 8);
        sysv_align_stack(call);
        call->stack[call->stack_count++] = (uint32_t)(bits >> 32);
        call->stack[call->stack_count++] = (uint32_t)bits;
    }
}

// The same, reading a call Linux code made: its registers, and its stack
// from 8(r1).
typedef struct sysv_args {
    const uint32_t *gprs;
    const double *fprs;
    const uint32_t *stack;
    uint32_t gpr, fpr, stack_index;
} sysv_args;

static uint32_t sysv_word(sysv_args *args) {
    return args->gpr < 8 ? args->gprs[args->gpr++] : args->stack[args->stack_index++];
}

static void sysv_pair(sysv_args *args, uint32_t *high, uint32_t *low) {
    if (args->gpr & 1)
        args->gpr++;
    if (args->gpr <= 6) {
        *high = args->gprs[args->gpr++];
        *low = args->gprs[args->gpr++];
    } else {
        args->gpr = 8;
        if (args->stack_index & 1)
            args->stack_index++;
        *high = args->stack[args->stack_index++];
        *low = args->stack[args->stack_index++];
    }
}

static double sysv_double(sysv_args *args) {
    if (args->fpr < 8)
        return args->fprs[args->fpr++];
    if (args->stack_index & 1)
        args->stack_index++;
    uint64_t bits = (uint64_t)args->stack[args->stack_index] << 32 | args->stack[args->stack_index + 1];
    args->stack_index += 2;
    double value;
    memcpy(&value, &bits, 8);
    return value;
}

// MARK: - Darwin to Linux

static uint32_t darwin_word(const uint32_t *gprs, const uint32_t *caller_stack, uint32_t index) {
    return index < 8 ? gprs[index] : caller_stack[6 + index];   // 24(r1) is word 6
}

static double darwin_double(const double *fprs, uint32_t *fpr, const uint32_t *gprs, const uint32_t *caller_stack,
                            uint32_t word) {
    if (*fpr < 13)
        return fprs[(*fpr)++];
    uint64_t bits = (uint64_t)darwin_word(gprs, caller_stack, word) << 32 | darwin_word(gprs, caller_stack, word + 1);
    double value;
    memcpy(&value, &bits, 8);
    return value;
}

// Calls the plan's Linux function with Darwin's arguments; leaves the result
// registers, the same on both, in `result`. Called by
// perry_ppc_darwin_trampoline.
__attribute__((visibility("hidden")))
void perry_ppc_from_darwin(const perry_ppc_plan *plan, const uint32_t *gprs, const double *fprs,
                           const uint32_t *caller_stack, perry_ppc_registers *result) {
    sysv_call call;
    memset(&call, 0, sizeof(call));
    // Copies of structures, which Linux passes through pointers.
    uint32_t copies_size = 0;
    for (uint32_t i = 0; i < plan->count; i++)
        copies_size += is_structure(plan->arguments[i].kind) ? (plan->arguments[i].words ? plan->arguments[i].words : 2) : 0;
    uint32_t *copies = __builtin_alloca(copies_size * sizeof(uint32_t) + 8);
    uint32_t copied = 0;

    uint32_t word = 0, fpr = 0;
    if (is_structure(plan->result.kind))
        sysv_put_word(&call, darwin_word(gprs, caller_stack, word++));
    for (uint32_t i = 0; i < plan->count; i++) {
        const plan_value *argument = &plan->arguments[i];
        switch (argument->kind) {
        case KIND_WORD:
        case KIND_VOID:
            sysv_put_word(&call, darwin_word(gprs, caller_stack, word++));
            break;
        case KIND_PAIR: {
            uint32_t high = darwin_word(gprs, caller_stack, word), low = darwin_word(gprs, caller_stack, word + 1);
            word += 2;
            sysv_put_pair(&call, high, low);
            break;
        }
        case KIND_DOUBLE:
            sysv_put_double(&call, darwin_double(fprs, &fpr, gprs, caller_stack, word));
            word += 2;
            break;
        case KIND_FLOAT: {
            double value;
            if (fpr < 13) {
                value = fprs[fpr++];
            } else {
                uint32_t bits = darwin_word(gprs, caller_stack, word);
                float single;
                memcpy(&single, &bits, 4);
                value = single;
            }
            word += 1;
            sysv_put_double(&call, value);
            break;
        }
        case KIND_STRUCT: {
            uint32_t *copy = &copies[copied];
            copied += argument->words;
            for (uint32_t w = 0; w < argument->words; w++)
                copy[w] = darwin_word(gprs, caller_stack, word++);
            sysv_put_word(&call, (uint32_t)(uintptr_t)copy);
            break;
        }
        case KIND_STRUCT_DOUBLE: {
            uint32_t *copy = &copies[copied];
            copied += 2;
            double value = darwin_double(fprs, &fpr, gprs, caller_stack, word);
            memcpy(copy, &value, 8);
            word += 2;
            sysv_put_word(&call, (uint32_t)(uintptr_t)copy);
            break;
        }
        case KIND_STRUCT_FLOAT: {
            uint32_t *copy = &copies[copied];
            copied += 1;
            float single;
            if (fpr < 13) {
                single = (float)fprs[fpr++];
            } else {
                uint32_t bits = darwin_word(gprs, caller_stack, word);
                memcpy(&single, &bits, 4);
            }
            memcpy(copy, &single, 4);
            word += 1;
            sysv_put_word(&call, (uint32_t)(uintptr_t)copy);
            break;
        }
        }
    }
    perry_ppc_invoke_sysv(plan->function, call.gprs, call.fprs, call.stack, call.stack_count, result);
}

// MARK: - Stubs

enum { STUB_WORDS = 16 };

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t *stub_page;
static size_t stub_page_used;

static uint32_t *new_stub(void) {
    if (!stub_page || (stub_page_used + 1) * STUB_WORDS * 4 > 0x4000) {
        stub_page = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (stub_page == MAP_FAILED)
            perry_fatal("cannot allocate a page of ABI stubs");
        stub_page_used = 0;
    }
    return stub_page + STUB_WORDS * stub_page_used++;
}

// Whether an address is in a Linux library or perry: Mach-O images and the
// pages of stubs are in none.
static bool in_linux_code(void *address) {
    Dl_info info;
    return dladdr(address, &info) && info.dli_fname;
}

// Linux libraries' code that takes Darwin's arguments itself, written in
// assembly (KVO's setter): it gets r2 set, and nothing moved.
enum { MAX_DARWIN_CODE = 64 };
static void *darwin_code[MAX_DARWIN_CODE];
static unsigned darwin_code_count;

void perry_ppc_darwin_code(void *address) {
    pthread_mutex_lock(&lock);
    if (darwin_code_count < MAX_DARWIN_CODE)
        darwin_code[darwin_code_count++] = address;
    pthread_mutex_unlock(&lock);
}

static bool is_darwin_code(void *address) {
    pthread_mutex_lock(&lock);
    bool found = false;
    for (unsigned i = 0; i < darwin_code_count && !found; i++)
        found = darwin_code[i] == address;
    pthread_mutex_unlock(&lock);
    return found;
}

void *perry_ppc_darwin_entry(void *function, const char *types) {
    if (!function || !types || !in_linux_code(function))
        return function;
    if (is_darwin_code(function))
        return perry_ppc_thread_stub(function);
    perry_ppc_plan plan;
    if (!parse(types, &plan)) {
        perry_warn("cannot move the arguments of %s for Darwin's ppc ABI", types);
        return perry_ppc_thread_stub(function);
    }
    if (all_words(&plan))
        return perry_ppc_thread_stub(function);
    perry_ppc_plan *kept = malloc(sizeof(plan));
    *kept = plan;
    kept->function = function;
    pthread_mutex_lock(&lock);
    uint32_t *code = new_stub();
    pthread_mutex_unlock(&lock);
    uint32_t planned = (uint32_t)(uintptr_t)kept, trampoline = (uint32_t)(uintptr_t)perry_ppc_darwin_trampoline;
    int n = perry_ppc_emit_thread_pointer(code);
    code[n++] = 0x3d600000u | (planned >> 16);          // lis r11, plan@h
    code[n++] = 0x616b0000u | (planned & 0xffff);       // ori r11, r11, plan@l
    code[n++] = 0x3d800000u | (trampoline >> 16);       // lis r12, trampoline@h
    code[n++] = 0x618c0000u | (trampoline & 0xffff);    // ori r12, r12, trampoline@l
    code[n++] = 0x7d8903a6u;                            // mtctr r12
    code[n++] = 0x4e800420u;                            // bctr
    __builtin___clear_cache((char *)code, (char *)(code + n));
    perry_trace(PERRY_TRACE_BIND, "ABI stub %p for %p (%s)", (void *)code, function, types);
    return code;
}

// MARK: - Linux to Darwin

// What Linux code calls for a Darwin function whose arguments are words, or
// floating point after every word (a block's invoke, a callback): a stub
// that calls it through perry_ppc_darwin_from_linux, from a frame laid out
// as Darwin's caller's, keeping r2. Linux code comes back as it is. A stub
// is made once for each function.
static struct { void *function; uint32_t *stub; } *callables;
static size_t callables_size, callables_count;

static size_t callable_slot(void *function) {
    size_t mask = callables_size - 1;
    size_t i = ((uintptr_t)function >> 2) & mask;
    while (callables[i].function && callables[i].function != function)
        i = (i + 1) & mask;
    return i;
}

void *perry_ppc_linux_callable(void *function) {
    if (!function || in_linux_code(function))
        return function;
    return perry_ppc_callable_stub(function);
}

void *perry_ppc_callable_stub(void *function) {
    pthread_mutex_lock(&lock);
    if (callables_count * 2 >= callables_size) {
        __typeof__(callables) old = callables;
        size_t old_size = callables_size;
        callables_size = old_size ? old_size * 2 : 256;
        callables = calloc(callables_size, sizeof(*callables));
        for (size_t i = 0; i < old_size; i++)
            if (old[i].function)
                callables[callable_slot(old[i].function)] = old[i];
        free(old);
    }
    size_t slot = callable_slot(function);
    if (!callables[slot].function) {
        uint32_t *code = new_stub();
        uint32_t target = (uint32_t)(uintptr_t)function, through = (uint32_t)(uintptr_t)perry_ppc_darwin_from_linux;
        code[0] = 0x3d600000u | (target >> 16);         // lis r11, function@h
        code[1] = 0x616b0000u | (target & 0xffff);      // ori r11, r11, function@l
        code[2] = 0x3d800000u | (through >> 16);        // lis r12, perry_ppc_darwin_from_linux@h
        code[3] = 0x618c0000u | (through & 0xffff);     // ori r12, r12, perry_ppc_darwin_from_linux@l
        code[4] = 0x7d8903a6u;                          // mtctr r12
        code[5] = 0x4e800420u;                          // bctr
        __builtin___clear_cache((char *)code, (char *)(code + 6));
        callables[slot].function = function;
        callables[slot].stub = code;
        callables_count++;
        perry_trace(PERRY_TRACE_BIND, "Linux-callable stub %p for %p", (void *)code, function);
    }
    uint32_t *stub = callables[slot].stub;
    pthread_mutex_unlock(&lock);
    return stub;
}

// Calls a Darwin function with the arguments of a call Linux code made (its
// registers, and its stack from 8(r1)), laid out for Darwin by `types`; the
// result registers are the same on both.
void perry_ppc_call_darwin(void *function, const char *types, const uint32_t linux_gprs[8], const double linux_fprs[8],
                           const uint32_t *linux_stack, perry_ppc_registers *result) {
    perry_ppc_plan plan;
    if (!parse(types, &plan))
        perry_fatal("cannot move the arguments of %s for Darwin's ppc ABI", types);
    sysv_args args = { linux_gprs, linux_fprs, linux_stack, 0, 0, 0 };
    uint32_t gprs[8] = { 0 };
    double fprs[13] = { 0 };
    uint32_t words[MAX_ARGUMENTS * 4 + 8];
    uint32_t word = 0, fpr = 0;
    if (is_structure(plan.result.kind))
        words[word++] = sysv_word(&args);
    for (uint32_t i = 0; i < plan.count; i++) {
        const plan_value *argument = &plan.arguments[i];
        switch (argument->kind) {
        case KIND_WORD:
        case KIND_VOID:
            words[word++] = sysv_word(&args);
            break;
        case KIND_PAIR:
            sysv_pair(&args, &words[word], &words[word + 1]);
            word += 2;
            break;
        case KIND_DOUBLE: {
            double value = sysv_double(&args);
            uint64_t bits;
            memcpy(&bits, &value, 8);
            words[word++] = (uint32_t)(bits >> 32);
            words[word++] = (uint32_t)bits;
            if (fpr < 13)
                fprs[fpr++] = value;
            break;
        }
        case KIND_FLOAT: {
            float single = (float)sysv_double(&args);
            memcpy(&words[word++], &single, 4);
            if (fpr < 13)
                fprs[fpr++] = single;
            break;
        }
        case KIND_STRUCT: {
            const uint32_t *copy = (const uint32_t *)(uintptr_t)sysv_word(&args);
            for (uint32_t w = 0; w < argument->words; w++)
                words[word++] = copy[w];
            break;
        }
        case KIND_STRUCT_DOUBLE: {
            const uint32_t *copy = (const uint32_t *)(uintptr_t)sysv_word(&args);
            words[word++] = copy[0];
            words[word++] = copy[1];
            if (fpr < 13)
                memcpy(&fprs[fpr++], copy, 8);
            break;
        }
        case KIND_STRUCT_FLOAT: {
            const uint32_t *copy = (const uint32_t *)(uintptr_t)sysv_word(&args);
            float single;
            memcpy(&single, copy, 4);
            words[word++] = copy[0];
            if (fpr < 13)
                fprs[fpr++] = single;
            break;
        }
        }
    }
    for (uint32_t i = 0; i < 8 && i < word; i++)
        gprs[i] = words[i];
    perry_ppc_invoke_darwin(function, gprs, fprs, words, word, result);
}

// Calls a Darwin function (an IMP, a block's invoke) by its type encoding
// with its arguments as they are in memory, `arguments` pointing at each:
// NSInvocation's and key-value coding's calls. A structure result goes to
// `structure`; the others are in `result`'s registers.
void perry_ppc_call_darwin_values(void *function, const char *types, void *const *arguments, void *structure,
                                  perry_ppc_registers *result) {
    perry_ppc_plan plan;
    if (!parse(types, &plan))
        perry_fatal("cannot move the arguments of %s for Darwin's ppc ABI", types);
    uint32_t gprs[8] = { 0 };
    double fprs[13] = { 0 };
    uint32_t words[MAX_ARGUMENTS * 4 + 8];
    uint32_t word = 0, fpr = 0;
    if (is_structure(plan.result.kind))
        words[word++] = (uint32_t)(uintptr_t)structure;
    for (uint32_t i = 0; i < plan.count; i++) {
        const plan_value *argument = &plan.arguments[i];
        const unsigned char *bytes = arguments[i];
        switch (argument->kind) {
        case KIND_WORD:
        case KIND_VOID: {
            // Promoted to a word as C passes it: chars and shorts by their sign.
            uint32_t value = 0;
            if (argument->size == 1)
                value = argument->code == 'c' ? (uint32_t)(int32_t)*(const int8_t *)bytes : *bytes;
            else if (argument->size == 2) {
                uint16_t half;
                memcpy(&half, bytes, 2);
                value = argument->code == 's' ? (uint32_t)(int32_t)(int16_t)half : half;
            } else
                memcpy(&value, bytes, 4);
            words[word++] = value;
            break;
        }
        case KIND_PAIR:
            memcpy(&words[word], bytes, 8);
            word += 2;
            break;
        case KIND_DOUBLE:
        case KIND_STRUCT_DOUBLE:
            memcpy(&words[word], bytes, 8);
            word += 2;
            if (fpr < 13)
                memcpy(&fprs[fpr++], bytes, 8);
            break;
        case KIND_FLOAT:
        case KIND_STRUCT_FLOAT: {
            float single;
            memcpy(&single, bytes, 4);
            memcpy(&words[word++], bytes, 4);
            if (fpr < 13)
                fprs[fpr++] = single;
            break;
        }
        case KIND_STRUCT:
            if (word + argument->words > MAX_ARGUMENTS * 4)
                perry_fatal("the arguments of %s are too large to move for Darwin's ppc ABI", types);
            memset(&words[word], 0, argument->words * 4);
            memcpy(&words[word], bytes, argument->size);
            word += argument->words;
            break;
        }
    }
    for (uint32_t i = 0; i < 8 && i < word; i++)
        gprs[i] = words[i];
    perry_ppc_invoke_darwin(function, gprs, fprs, words, word, result);
}

// MARK: - Sends from Linux code

static perry_ppc_method_lookup method_lookup;

void perry_ppc_set_method_lookup(perry_ppc_method_lookup lookup) {
    method_lookup = lookup;
}

// Called by the perry_ppc_send_* entry points (ppc_abi.S) with the
// registers and stack of a send Linux code made. `kind` says which send: bit
// 0 a structure result (a pointer first), bit 1 a super send (the first word
// an objc_super: receiver, then the class whose superclass to start at).
__attribute__((visibility("hidden")))
void perry_ppc_send_from_linux(uint32_t kind, uint32_t *gprs, const double *fprs, const uint32_t *caller_stack,
                               perry_ppc_registers *result) {
    const uint32_t *stack = caller_stack + 2;   // 8(r1)
    uint32_t self_index = kind & 1 ? 1 : 0;
    void *receiver = (void *)(uintptr_t)gprs[self_index];
    void *start = NULL;
    if (kind & 2) {
        const uint32_t *super = (const uint32_t *)(uintptr_t)gprs[self_index];
        receiver = (void *)(uintptr_t)super[0];
        start = *(void **)((uintptr_t)super[1] + 4);    // its superclass
        gprs[self_index] = super[0];
    }
    const void *selector = (const void *)(uintptr_t)gprs[self_index + 1];
    result->r3 = result->r4 = 0;
    result->f1 = 0;
    if (!receiver || !method_lookup)
        return;
    const char *types = NULL;
    void *imp = method_lookup(receiver, selector, start, &types);
    if (!imp)
        return;
    if (!types) {
        // No encoding: words, as many as there can be in registers.
        double none[13] = { 0 };
        perry_ppc_invoke_darwin(imp, gprs, none, gprs, 8, result);
        return;
    }
    perry_ppc_call_darwin(imp, types, gprs, fprs, stack, result);
}

bool perry_ppc_types_need_moves(const char *types) {
    perry_ppc_plan plan;
    return types && (!parse(types, &plan) || !all_words(&plan));
}

#endif
