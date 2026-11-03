// std::string's out-of-line members as Darwin's libc++ lays the string out
// on arm64. Apple builds libc++ with _LIBCPP_ABI_ALTERNATE_STRING_LAYOUT,
// Linux's libc++ without, so code compiled for iOS (Swift's runtime among
// it) passes strings that Linux's members would misread. These stand in
// for the ones such code calls.
//
// A string is 24 bytes. Long: the data pointer, the size, then the
// allocation's size in the low 63 bits of the last word, whose top bit
// marks the string long. Short: up to 22 characters and their terminator
// inline, then the size in the low 7 bits of the last byte. Memory comes
// from malloc, as libc++'s operator new, which the inline code frees it
// with, does.

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct darwin_string {
    union {
        struct { char *data; size_t size; size_t cap; } l;
        struct { char data[23]; uint8_t size; } s;
    };
} darwin_string;

#define LONG_FLAG ((size_t)1 << 63)
#define SHORT_CAPACITY 22

#define CXX_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

static bool is_long(const darwin_string *string) { return string->s.size & 0x80; }

static char *data(darwin_string *string) { return is_long(string) ? string->l.data : string->s.data; }

static size_t size(const darwin_string *string) { return is_long(string) ? string->l.size : string->s.size & 0x7f; }

static size_t capacity(const darwin_string *string) {
    return is_long(string) ? (string->l.cap & ~LONG_FLAG) - 1 : SHORT_CAPACITY;
}

_Noreturn static void fail(const char *what) {
    fflush(stdout);
    fprintf(stderr, "perry: std::string: %s\n", what);
    abort();
}

static void set_size(darwin_string *string, size_t length) {
    if (is_long(string))
        string->l.size = length;
    else
        string->s.size = (uint8_t)length;
    data(string)[length] = 0;
}

// Makes room for `wanted` characters, keeping the contents.
static void grow(darwin_string *string, size_t wanted) {
    if (wanted <= capacity(string))
        return;
    size_t length = size(string);
    size_t allocation = (wanted + 16) & ~(size_t)15;
    char *buffer = malloc(allocation);
    if (!buffer)
        fail("out of memory");
    memcpy(buffer, data(string), length + 1);
    if (is_long(string))
        free(string->l.data);
    string->l.data = buffer;
    string->l.size = length;
    string->l.cap = allocation | LONG_FLAG;
}

static darwin_string *replace_contents(darwin_string *string, const char *chars, size_t count) {
    // `chars` may be in the string's own buffer, which growing frees.
    char *copy = NULL;
    if (count > capacity(string) && chars >= data(string) && chars < data(string) + capacity(string) + 1) {
        copy = malloc(count);
        memcpy(copy, chars, count);
        chars = copy;
    }
    grow(string, count);
    memmove(data(string), chars, count);
    set_size(string, count);
    free(copy);
    return string;
}

static darwin_string *insert_at(darwin_string *string, size_t position, const char *chars, size_t count) {
    size_t length = size(string);
    if (position > length)
        fail("insert position out of range");
    char *copy = NULL;
    if (chars >= data(string) && chars < data(string) + length + 1) {
        copy = malloc(count ? count : 1);
        memcpy(copy, chars, count);
        chars = copy;
    }
    grow(string, length + count);
    char *bytes = data(string);
    memmove(bytes + position + count, bytes + position, length - position);
    memcpy(bytes + position, chars, count);
    set_size(string, length + count);
    free(copy);
    return string;
}

static darwin_string from_chars(const char *chars, size_t count) {
    darwin_string string = {0};
    replace_contents(&string, chars, count);
    return string;
}

// MARK: - Members

// basic_string::reserve(size_type)
void darwin_string_reserve(darwin_string *string, size_t wanted)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7reserveEm");
void darwin_string_reserve(darwin_string *string, size_t wanted) { grow(string, wanted); }

// basic_string::operator=(const basic_string &)
darwin_string *darwin_string_copy_assign(darwin_string *string, const darwin_string *other)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSERKS5_");
darwin_string *darwin_string_copy_assign(darwin_string *string, const darwin_string *other) {
    if (string == other)
        return string;
    return replace_contents(string, data((darwin_string *)other), size(other));
}

// basic_string::assign(const char *)
darwin_string *darwin_string_assign(darwin_string *string, const char *chars)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6assignEPKc");
darwin_string *darwin_string_assign(darwin_string *string, const char *chars) {
    return replace_contents(string, chars, strlen(chars));
}

// basic_string::append(const char *, size_type)
darwin_string *darwin_string_append_count(darwin_string *string, const char *chars, size_t count)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKcm");
darwin_string *darwin_string_append_count(darwin_string *string, const char *chars, size_t count) {
    return insert_at(string, size(string), chars, count);
}

// basic_string::append(const char *)
darwin_string *darwin_string_append(darwin_string *string, const char *chars)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKc");
darwin_string *darwin_string_append(darwin_string *string, const char *chars) {
    return insert_at(string, size(string), chars, strlen(chars));
}

// basic_string::append(size_type, char)
darwin_string *darwin_string_append_repeated(darwin_string *string, size_t count, char character)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEmc");
darwin_string *darwin_string_append_repeated(darwin_string *string, size_t count, char character) {
    size_t length = size(string);
    grow(string, length + count);
    memset(data(string) + length, character, count);
    set_size(string, length + count);
    return string;
}

// basic_string::push_back(char)
void darwin_string_push_back(darwin_string *string, char character)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9push_backEc");
void darwin_string_push_back(darwin_string *string, char character) {
    darwin_string_append_repeated(string, 1, character);
}

// basic_string::insert(size_type, const char *, size_type)
darwin_string *darwin_string_insert_count(darwin_string *string, size_t position, const char *chars, size_t count)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6insertEmPKcm");
darwin_string *darwin_string_insert_count(darwin_string *string, size_t position, const char *chars, size_t count) {
    return insert_at(string, position, chars, count);
}

// basic_string::insert(size_type, const char *)
darwin_string *darwin_string_insert(darwin_string *string, size_t position, const char *chars)
    CXX_SYMBOL("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6insertEmPKc");
darwin_string *darwin_string_insert(darwin_string *string, size_t position, const char *chars) {
    return insert_at(string, position, chars, strlen(chars));
}

// basic_string::find(char, size_type) const
size_t darwin_string_find_char(const darwin_string *string, char character, size_t position)
    CXX_SYMBOL("__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE4findEcm");
size_t darwin_string_find_char(const darwin_string *string, char character, size_t position) {
    size_t length = size(string);
    if (position >= length)
        return (size_t)-1;
    const char *bytes = data((darwin_string *)string);
    const char *found = memchr(bytes + position, character, length - position);
    return found ? (size_t)(found - bytes) : (size_t)-1;
}

// MARK: - Functions

// operator+(const char *, const basic_string &)
darwin_string darwin_string_concat(const char *left, const darwin_string *right)
    CXX_SYMBOL("__ZNSt3__1plIcNS_11char_traitsIcEENS_9allocatorIcEEEENS_12basic_stringIT_T0_T1_EEPKS6_RKS9_");
darwin_string darwin_string_concat(const char *left, const darwin_string *right) {
    size_t count = strlen(left);
    darwin_string string = from_chars(left, count);
    insert_at(&string, count, data((darwin_string *)right), size(right));
    return string;
}

#define TO_STRING(suffix, type, format)                                                         \
    darwin_string darwin_to_string_##suffix(type value) CXX_SYMBOL("__ZNSt3__19to_stringE" #suffix); \
    darwin_string darwin_to_string_##suffix(type value) {                                       \
        char buffer[32];                                                                        \
        int count = snprintf(buffer, sizeof(buffer), format, value);                            \
        return from_chars(buffer, (size_t)count);                                               \
    }

TO_STRING(i, int, "%d")
TO_STRING(j, unsigned, "%u")
TO_STRING(l, long, "%ld")
TO_STRING(m, unsigned long, "%lu")
TO_STRING(x, long long, "%lld")
TO_STRING(y, unsigned long long, "%llu")
