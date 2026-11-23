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
//   - results are in r3 (and r4 for a long long), f1 for floating point, and
//     a structure is returned through a pointer in r3, before the arguments
//
// Linux's side is the C signature the Swift providers give such functions
// on 32-bit, through ObjCValue (PerryObjCInterop): a float is its bits as a
// UInt32; a double or long long is an ObjCWordPair (a structure of its low
// and high words); a structure is ObjCWords2, ObjCWords4 and so on; results
// are UInt64 for a double or long long, and UInt32 for a float. SysV passes
// every structure through a pointer to a copy, and the rest as words, so the
// Linux side of a call is all words: r3-r10, then 8(r1).

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

typedef struct perry_ppc_registers {
    uint32_t r3, r4;
    double f1;
} perry_ppc_registers;

void perry_ppc_darwin_trampoline(void);
void perry_ppc_invoke_sysv(void *function, const uint32_t gprs[8], const uint32_t *stack, uint32_t stack_words,
                           perry_ppc_registers *result);
void perry_ppc_invoke_darwin(void *function, const uint32_t gprs[8], const double fprs[13], const uint32_t *words,
                             uint32_t word_count, perry_ppc_registers *result);

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

// Whether a plan's arguments and result all pass the same in both ABIs.
static bool all_words(const perry_ppc_plan *plan) {
    if (plan->result.kind != KIND_WORD && plan->result.kind != KIND_VOID && plan->result.kind != KIND_PAIR &&
        !is_structure(plan->result.kind))
        return false;
    for (uint32_t i = 0; i < plan->count; i++)
        if (plan->arguments[i].kind != KIND_WORD)
            return false;
    return true;
}

// MARK: - Darwin to Linux

static uint32_t darwin_word(const uint32_t *gprs, const uint32_t *caller_stack, uint32_t index) {
    return index < 8 ? gprs[index] : caller_stack[6 + index];   // 24(r1) is word 6
}

// Calls the plan's Linux function with Darwin's arguments; leaves Darwin's
// result registers in `result`. Called by perry_ppc_darwin_trampoline.
__attribute__((visibility("hidden")))
void perry_ppc_from_darwin(const perry_ppc_plan *plan, const uint32_t *gprs, const double *fprs,
                           const uint32_t *caller_stack, perry_ppc_registers *result) {
    uint32_t words[MAX_ARGUMENTS * 2 + 8];
    uint32_t count = 0;
    // Copies of what goes through a pointer: up to two words for each value,
    // and structures' words.
    uint32_t copies_size = 0;
    for (uint32_t i = 0; i < plan->count; i++)
        copies_size += plan->arguments[i].kind == KIND_STRUCT ? plan->arguments[i].words : 2;
    uint32_t *copies = __builtin_alloca(copies_size * sizeof(uint32_t) + 8);
    uint32_t copied = 0;

    uint32_t word = 0, fpr = 0;
    // A structure result comes through a pointer before the arguments, the
    // same on both.
    if (is_structure(plan->result.kind))
        words[count++] = darwin_word(gprs, caller_stack, word++);
    for (uint32_t i = 0; i < plan->count; i++) {
        const plan_value *argument = &plan->arguments[i];
        switch (argument->kind) {
        case KIND_WORD:
        case KIND_VOID:
            words[count++] = darwin_word(gprs, caller_stack, word++);
            break;
        case KIND_PAIR: {
            uint32_t *pair = &copies[copied];
            copied += 2;
            pair[1] = darwin_word(gprs, caller_stack, word++);     // high
            pair[0] = darwin_word(gprs, caller_stack, word++);     // low
            words[count++] = (uint32_t)(uintptr_t)pair;
            break;
        }
        case KIND_DOUBLE: {
            uint64_t bits;
            if (fpr < 13) {
                memcpy(&bits, &fprs[fpr++], 8);
            } else {
                uint32_t high = darwin_word(gprs, caller_stack, word), low = darwin_word(gprs, caller_stack, word + 1);
                bits = (uint64_t)high << 32 | low;
            }
            word += 2;
            uint32_t *pair = &copies[copied];
            copied += 2;
            pair[0] = (uint32_t)bits;
            pair[1] = (uint32_t)(bits >> 32);
            words[count++] = (uint32_t)(uintptr_t)pair;
            break;
        }
        case KIND_FLOAT: {
            uint32_t bits;
            if (fpr < 13) {
                float single = (float)fprs[fpr++];
                memcpy(&bits, &single, 4);
            } else {
                bits = darwin_word(gprs, caller_stack, word);
            }
            word += 1;
            words[count++] = bits;
            break;
        }
        case KIND_STRUCT: {
            uint32_t *copy = &copies[copied];
            copied += argument->words;
            for (uint32_t w = 0; w < argument->words; w++)
                copy[w] = darwin_word(gprs, caller_stack, word++);
            words[count++] = (uint32_t)(uintptr_t)copy;
            break;
        }
        case KIND_STRUCT_DOUBLE: {
            // Its memory, which is the double's.
            uint32_t *copy = &copies[copied];
            copied += 2;
            if (fpr < 13) {
                memcpy(copy, &fprs[fpr++], 8);
            } else {
                copy[0] = darwin_word(gprs, caller_stack, word);
                copy[1] = darwin_word(gprs, caller_stack, word + 1);
            }
            word += 2;
            words[count++] = (uint32_t)(uintptr_t)copy;
            break;
        }
        case KIND_STRUCT_FLOAT: {
            uint32_t *copy = &copies[copied];
            copied += 1;
            if (fpr < 13) {
                float single = (float)fprs[fpr++];
                memcpy(copy, &single, 4);
            } else {
                copy[0] = darwin_word(gprs, caller_stack, word);
            }
            word += 1;
            words[count++] = (uint32_t)(uintptr_t)copy;
            break;
        }
        }
    }

    perry_ppc_registers registers;
    perry_ppc_invoke_sysv(plan->function, words, count > 8 ? words + 8 : NULL, count > 8 ? count - 8 : 0,
                          &registers);
    result->r3 = registers.r3;
    result->r4 = registers.r4;
    result->f1 = 0;
    switch (plan->result.kind) {
    case KIND_DOUBLE: {
        uint64_t bits = (uint64_t)registers.r3 << 32 | registers.r4;    // a UInt64, r3 high
        memcpy(&result->f1, &bits, 8);
        break;
    }
    case KIND_FLOAT: {
        float single;
        memcpy(&single, &registers.r3, 4);
        result->f1 = single;
        break;
    }
    default:
        break;
    }
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

void perry_ppc_call_darwin(void *function, const char *types, const uint32_t *linux_words, uint32_t linux_count,
                           uint32_t result[2]) {
    perry_ppc_plan plan;
    if (!parse(types, &plan))
        perry_fatal("cannot move the arguments of %s for Darwin's ppc ABI", types);
    uint32_t gprs[8] = { 0 };
    double fprs[13] = { 0 };
    uint32_t words[MAX_ARGUMENTS * 4 + 8];
    uint32_t word = 0, fpr = 0, in = 0;
#define NEXT_LINUX() (in < linux_count ? linux_words[in++] : 0)
    if (is_structure(plan.result.kind))
        words[word++] = NEXT_LINUX();
    for (uint32_t i = 0; i < plan.count; i++) {
        const plan_value *argument = &plan.arguments[i];
        switch (argument->kind) {
        case KIND_WORD:
        case KIND_VOID:
            words[word++] = NEXT_LINUX();
            break;
        case KIND_PAIR: {
            const uint32_t *pair = (const uint32_t *)(uintptr_t)NEXT_LINUX();
            words[word++] = pair[1];
            words[word++] = pair[0];
            break;
        }
        case KIND_DOUBLE: {
            const uint32_t *pair = (const uint32_t *)(uintptr_t)NEXT_LINUX();
            uint64_t bits = (uint64_t)pair[1] << 32 | pair[0];
            words[word++] = pair[1];
            words[word++] = pair[0];
            if (fpr < 13)
                memcpy(&fprs[fpr++], &bits, 8);
            break;
        }
        case KIND_FLOAT: {
            uint32_t bits = NEXT_LINUX();
            float single;
            memcpy(&single, &bits, 4);
            words[word++] = bits;
            if (fpr < 13)
                fprs[fpr++] = single;
            break;
        }
        case KIND_STRUCT: {
            const uint32_t *copy = (const uint32_t *)(uintptr_t)NEXT_LINUX();
            for (uint32_t w = 0; w < argument->words; w++)
                words[word++] = copy[w];
            break;
        }
        case KIND_STRUCT_DOUBLE: {
            const uint32_t *copy = (const uint32_t *)(uintptr_t)NEXT_LINUX();
            words[word++] = copy[0];
            words[word++] = copy[1];
            if (fpr < 13)
                memcpy(&fprs[fpr++], copy, 8);
            break;
        }
        case KIND_STRUCT_FLOAT: {
            const uint32_t *copy = (const uint32_t *)(uintptr_t)NEXT_LINUX();
            float single;
            memcpy(&single, copy, 4);
            words[word++] = copy[0];
            if (fpr < 13)
                fprs[fpr++] = single;
            break;
        }
        }
    }
#undef NEXT_LINUX
    for (uint32_t i = 0; i < 8 && i < word; i++)
        gprs[i] = words[i];
    perry_ppc_registers registers;
    perry_ppc_invoke_darwin(function, gprs, fprs, words, word, &registers);
    switch (plan.result.kind) {
    case KIND_DOUBLE: {
        uint64_t bits;
        memcpy(&bits, &registers.f1, 8);
        result[0] = (uint32_t)(bits >> 32);
        result[1] = (uint32_t)bits;
        break;
    }
    case KIND_FLOAT: {
        float single = (float)registers.f1;
        memcpy(&result[0], &single, 4);
        result[1] = 0;
        break;
    }
    default:
        result[0] = registers.r3;
        result[1] = registers.r4;
        break;
    }
}

// MARK: - Sends from Linux code

static perry_ppc_method_lookup method_lookup;

void perry_ppc_set_method_lookup(perry_ppc_method_lookup lookup) {
    method_lookup = lookup;
}

// Called by the perry_ppc_send_* entry points (ppc_abi.S) with Linux's
// argument words: r3-r10, then the caller's stack from 8(r1). `kind` says
// which send: bit 0 a structure result (a pointer first), bit 1 a super
// send (the first word an objc_super: receiver, then the class whose
// superclass to start at).
__attribute__((visibility("hidden")))
void perry_ppc_send_from_linux(uint32_t kind, const uint32_t *gprs, const uint32_t *caller_stack,
                               perry_ppc_registers *result) {
    uint32_t words[MAX_ARGUMENTS + 8];
    for (uint32_t i = 0; i < MAX_ARGUMENTS + 8; i++)
        words[i] = i < 8 ? gprs[i] : caller_stack[2 + (i - 8)];    // 8(r1) is word 2
    uint32_t self_index = kind & 1 ? 1 : 0;
    void *receiver = (void *)(uintptr_t)words[self_index];
    void *start = NULL;
    if (kind & 2) {
        const uint32_t *super = (const uint32_t *)(uintptr_t)words[self_index];
        receiver = (void *)(uintptr_t)super[0];
        start = *(void **)((uintptr_t)super[1] + 4);    // its superclass
        words[self_index] = super[0];
    }
    const void *selector = (const void *)(uintptr_t)words[self_index + 1];
    result->r3 = result->r4 = 0;
    result->f1 = 0;
    if (!receiver || !method_lookup)
        return;
    const char *types = NULL;
    void *imp = method_lookup(receiver, selector, start, &types);
    if (!imp)
        return;
    uint32_t out[2];
    if (!types) {
        // No encoding: words, as many as there can be in registers.
        perry_ppc_registers registers;
        double fprs[13] = { 0 };
        perry_ppc_invoke_darwin(imp, words, fprs, words, 8, &registers);
        result->r3 = registers.r3;
        result->r4 = registers.r4;
        return;
    }
    perry_ppc_call_darwin(imp, types, words, MAX_ARGUMENTS + 8, out);
    result->r3 = out[0];
    result->r4 = out[1];
}

bool perry_ppc_types_need_moves(const char *types) {
    perry_ppc_plan plan;
    return types && (!parse(types, &plan) || !all_words(&plan));
}

#endif
