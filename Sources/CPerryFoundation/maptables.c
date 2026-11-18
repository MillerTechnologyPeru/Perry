// Foundation's C map and hash tables (NSCreateMapTable, NSHashInsert and
// the rest), from before NSMapTable and NSHashTable were classes, which
// programs of Mac OS X 10.6 and earlier still use: each table hashes and
// compares its keys, and keeps and lets go of its keys and values, with the
// callbacks it was made with, NULL ones by pointer. Tables are their own
// structures, not objects.

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

typedef void *id;

// MARK: - Messages to objects

static id (*msg_send)(id, void *, ...);
static void *(*register_selector)(const char *);

static bool objc_ready(void) {
    if (msg_send) return true;
    void *library = dlopen("libPerryobjc.so", RTLD_NOW | RTLD_NOLOAD);
    if (!library) return false;
    *(void **)&register_selector = dlsym(library, "_sel_registerName");
    *(void **)&msg_send = dlsym(library, "_objc_msgSend");
    return msg_send && register_selector;
}

static id send0(id object, const char *selector) {
    if (!object || !objc_ready()) return NULL;
    return msg_send(object, register_selector(selector));
}

static id send1(id object, const char *selector, const void *argument) {
    if (!object || !objc_ready()) return NULL;
    return ((id (*)(id, void *, const void *))msg_send)(object, register_selector(selector), argument);
}

static id class_named(const char *name) {
    static id (*get_class)(const char *);
    if (!get_class) {
        void *library = dlopen("libPerryobjc.so", RTLD_NOW | RTLD_NOLOAD);
        if (library) *(void **)&get_class = dlsym(library, "_objc_getClass");
    }
    return get_class ? get_class(name) : NULL;
}

/// An autoreleased NSString of UTF-8 text.
static id string(const char *text) {
    id cls = class_named("NSString");
    return cls ? send1(cls, "stringWithUTF8String:", text) : NULL;
}

// MARK: - Callbacks

typedef struct {
    uintptr_t (*hash)(void *table, const void *);
    signed char (*isEqual)(void *table, const void *, const void *);
    void (*retain)(void *table, const void *);
    void (*release)(void *table, void *);
    id (*describe)(void *table, const void *);
    const void *notAKeyMarker;
} map_key_callbacks;

typedef struct {
    void (*retain)(void *table, const void *);
    void (*release)(void *table, void *);
    id (*describe)(void *table, const void *);
} map_value_callbacks;

typedef struct {
    uintptr_t (*hash)(void *table, const void *);
    signed char (*isEqual)(void *table, const void *, const void *);
    void (*retain)(void *table, const void *);
    void (*release)(void *table, void *);
    id (*describe)(void *table, const void *);
} hash_callbacks;

static uintptr_t pointer_hash(void *table, const void *item) {
    (void)table;
    uintptr_t value = (uintptr_t)item;
    return value ^ (value >> 4) ^ (value >> 12);
}

static signed char pointer_equal(void *table, const void *a, const void *b) {
    (void)table;
    return a == b;
}

static id pointer_describe(void *table, const void *item) {
    (void)table;
    char text[32];
    snprintf(text, sizeof text, "%p", item);
    return string(text);
}

static id integer_describe(void *table, const void *item) {
    (void)table;
    char text[32];
    snprintf(text, sizeof text, "%ld", (long)(intptr_t)item);
    return string(text);
}

static uintptr_t object_hash(void *table, const void *item) {
    (void)table;
    return (uintptr_t)send0((id)item, "hash");
}

static signed char object_equal(void *table, const void *a, const void *b) {
    (void)table;
    if (a == b) return 1;
    if (!a || !b) return 0;
    return (signed char)(uintptr_t)send1((id)a, "isEqual:", b);
}

static void object_retain(void *table, const void *item) {
    (void)table;
    send0((id)item, "retain");
}

static void object_release(void *table, void *item) {
    (void)table;
    send0(item, "release");
}

static id object_describe(void *table, const void *item) {
    (void)table;
    return send0((id)item, "description");
}

static void owned_release(void *table, void *item) {
    (void)table;
    free(item);
}

// The callbacks Foundation defines. NSNotAnIntMapKey is NSIntegerMin.
#define NOT_AN_INT_KEY ((const void *)(uintptr_t)INTPTR_MIN)

map_key_callbacks ns_integer_map_key DARWIN_SYMBOL("_NSIntegerMapKeyCallBacks") =
    {pointer_hash, pointer_equal, NULL, NULL, integer_describe, NOT_AN_INT_KEY};
map_key_callbacks ns_int_map_key DARWIN_SYMBOL("_NSIntMapKeyCallBacks") =
    {pointer_hash, pointer_equal, NULL, NULL, integer_describe, NOT_AN_INT_KEY};
map_key_callbacks ns_non_owned_pointer_map_key DARWIN_SYMBOL("_NSNonOwnedPointerMapKeyCallBacks") =
    {pointer_hash, pointer_equal, NULL, NULL, pointer_describe, NULL};
map_key_callbacks ns_non_owned_pointer_or_null_map_key DARWIN_SYMBOL("_NSNonOwnedPointerOrNullMapKeyCallBacks") =
    {pointer_hash, pointer_equal, NULL, NULL, pointer_describe, (const void *)(intptr_t)-1};
map_key_callbacks ns_non_retained_object_map_key DARWIN_SYMBOL("_NSNonRetainedObjectMapKeyCallBacks") =
    {object_hash, object_equal, NULL, NULL, object_describe, NULL};
map_key_callbacks ns_object_map_key DARWIN_SYMBOL("_NSObjectMapKeyCallBacks") =
    {object_hash, object_equal, object_retain, object_release, object_describe, NULL};
map_key_callbacks ns_owned_pointer_map_key DARWIN_SYMBOL("_NSOwnedPointerMapKeyCallBacks") =
    {pointer_hash, pointer_equal, NULL, owned_release, pointer_describe, NULL};

map_value_callbacks ns_integer_map_value DARWIN_SYMBOL("_NSIntegerMapValueCallBacks") = {NULL, NULL, integer_describe};
map_value_callbacks ns_int_map_value DARWIN_SYMBOL("_NSIntMapValueCallBacks") = {NULL, NULL, integer_describe};
map_value_callbacks ns_non_owned_pointer_map_value DARWIN_SYMBOL("_NSNonOwnedPointerMapValueCallBacks") = {NULL, NULL, pointer_describe};
map_value_callbacks ns_non_retained_object_map_value DARWIN_SYMBOL("_NSNonRetainedObjectMapValueCallBacks") =
    {NULL, NULL, object_describe};
map_value_callbacks ns_object_map_value DARWIN_SYMBOL("_NSObjectMapValueCallBacks") =
    {object_retain, object_release, object_describe};
map_value_callbacks ns_owned_pointer_map_value DARWIN_SYMBOL("_NSOwnedPointerMapValueCallBacks") =
    {NULL, owned_release, pointer_describe};

hash_callbacks ns_integer_hash DARWIN_SYMBOL("_NSIntegerHashCallBacks") = {pointer_hash, pointer_equal, NULL, NULL, integer_describe};
hash_callbacks ns_int_hash DARWIN_SYMBOL("_NSIntHashCallBacks") = {pointer_hash, pointer_equal, NULL, NULL, integer_describe};
hash_callbacks ns_non_owned_pointer_hash DARWIN_SYMBOL("_NSNonOwnedPointerHashCallBacks") =
    {pointer_hash, pointer_equal, NULL, NULL, pointer_describe};
hash_callbacks ns_non_retained_object_hash DARWIN_SYMBOL("_NSNonRetainedObjectHashCallBacks") =
    {object_hash, object_equal, NULL, NULL, object_describe};
hash_callbacks ns_object_hash DARWIN_SYMBOL("_NSObjectHashCallBacks") =
    {object_hash, object_equal, object_retain, object_release, object_describe};
hash_callbacks ns_owned_object_identity_hash DARWIN_SYMBOL("_NSOwnedObjectIdentityHashCallBacks") =
    {pointer_hash, pointer_equal, object_retain, object_release, object_describe};
hash_callbacks ns_owned_pointer_hash DARWIN_SYMBOL("_NSOwnedPointerHashCallBacks") =
    {pointer_hash, pointer_equal, NULL, owned_release, pointer_describe};

// MARK: - Tables

enum { EMPTY, FULL, REMOVED };

typedef struct {
    const void *key;
    const void *value;
    unsigned char state;
} slot;

#define TABLE_MAGIC 0x5045525259544142ull   // "PERRYTAB"

typedef struct table {
    // An object's isa: a class whose retain and release do nothing, so a
    // table can be kept in a collection or another table that retains its
    // objects, as Foundation's tables, which are objects, can.
    void *isa;
    uint64_t magic;
    map_key_callbacks keys;
    map_value_callbacks values;
    size_t count, used, capacity;   // used counts removed slots too
    slot *slots;
    bool is_hash;
} table;

/// Whether a table is one of these, not an NSMapTable or NSHashTable
/// object, which the functions take too, as Foundation's do from 10.5.
static void *table_class;

void perry_foundation_set_table_class(void *cls) { table_class = cls; }

static bool ours(const table *t) { return t && t->isa == table_class && t->magic == TABLE_MAGIC; }

static uintptr_t count_of_object(const void *object) { return (uintptr_t)send0((id)object, "count"); }

static uintptr_t hash_of(table *t, const void *key) {
    return t->keys.hash ? t->keys.hash(t, key) : pointer_hash(t, key);
}

static bool equal(table *t, const void *a, const void *b) {
    return t->keys.isEqual ? t->keys.isEqual(t, a, b) != 0 : a == b;
}

static table *make(const map_key_callbacks *keys, const map_value_callbacks *values, size_t capacity, bool is_hash) {
    table *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->isa = table_class;
    t->magic = TABLE_MAGIC;
    if (keys) t->keys = *keys;
    if (values) t->values = *values;
    t->is_hash = is_hash;
    t->capacity = 16;
    while (t->capacity < capacity * 2) t->capacity *= 2;
    t->slots = calloc(t->capacity, sizeof *t->slots);
    if (!t->slots) {
        free(t);
        return NULL;
    }
    return t;
}

/// The slot holding `key`, or NULL.
static slot *find(table *t, const void *key) {
    if (!t) return NULL;
    size_t mask = t->capacity - 1;
    for (size_t index = hash_of(t, key) & mask, probes = 0; probes < t->capacity; index = (index + 1) & mask, probes++) {
        slot *s = &t->slots[index];
        if (s->state == EMPTY) return NULL;
        if (s->state == FULL && equal(t, s->key, key)) return s;
    }
    return NULL;
}

static void grow(table *t) {
    slot *old = t->slots;
    size_t old_capacity = t->capacity;
    size_t capacity = t->count * 4 > old_capacity ? old_capacity * 2 : old_capacity;
    slot *slots = calloc(capacity, sizeof *slots);
    if (!slots) return;
    t->slots = slots;
    t->capacity = capacity;
    t->used = t->count;
    for (size_t index = 0; index < old_capacity; index++) {
        if (old[index].state != FULL) continue;
        size_t mask = capacity - 1, at = hash_of(t, old[index].key) & mask;
        while (slots[at].state == FULL) at = (at + 1) & mask;
        slots[at] = old[index];
    }
    free(old);
}

/// Puts a key known to be absent in an empty slot.
static void add(table *t, const void *key, const void *value) {
    if ((t->used + 1) * 2 > t->capacity) grow(t);
    size_t mask = t->capacity - 1, at = hash_of(t, key) & mask;
    while (t->slots[at].state == FULL) at = (at + 1) & mask;
    if (t->slots[at].state == EMPTY) t->used++;
    if (t->keys.retain) t->keys.retain(t, key);
    if (t->values.retain) t->values.retain(t, value);
    t->slots[at] = (slot){key, value, FULL};
    t->count++;
}

static void let_go(table *t, slot *s) {
    if (t->keys.release) t->keys.release(t, (void *)s->key);
    if (t->values.release) t->values.release(t, (void *)s->value);
}

static void remove_slot(table *t, slot *s) {
    slot taken = *s;
    s->state = REMOVED;
    s->key = s->value = NULL;
    t->count--;
    let_go(t, &taken);
}

static void reset(table *t) {
    if (!t) return;
    for (size_t index = 0; index < t->capacity; index++)
        if (t->slots[index].state == FULL) let_go(t, &t->slots[index]);
    memset(t->slots, 0, t->capacity * sizeof *t->slots);
    t->count = t->used = 0;
}

// Lets go of the table's keys and values and its slots. The table itself,
// a few words, stays: an object whose release does nothing, as programs
// release a table after freeing it, Foundation's tables being objects
// (Xcode's indexer does).
static void free_table(table *t) {
    if (!t) return;
    reset(t);
    t->magic = 0;
    free(t->slots);
    t->slots = NULL;
    t->capacity = 0;
}

// Enumerators: { the table, the next slot, unused }.
typedef struct {
    uintptr_t table;
    uintptr_t index;
    void *unused;
} enumerator;

static slot *next(enumerator *e) {
    table *t = (table *)e->table;
    if (!t) return NULL;
    while (e->index < t->capacity) {
        slot *s = &t->slots[e->index++];
        if (s->state == FULL) return s;
    }
    return NULL;
}

/// An autoreleased NSMutableArray of a table's keys or values.
static id all(table *t, bool values) {
    id cls = class_named("NSMutableArray");
    id array = cls ? send0(cls, "array") : NULL;
    if (!array || !t) return array;
    for (size_t index = 0; index < t->capacity; index++)
        if (t->slots[index].state == FULL)
            send1(array, "addObject:", values ? t->slots[index].value : t->slots[index].key);
    return array;
}

static id describe(table *t) {
    if (!t) return string("");
    size_t capacity = 64, length = 0;
    char *text = malloc(capacity);
    if (!text) return NULL;
    text[0] = 0;
    for (size_t index = 0; index < t->capacity; index++) {
        if (t->slots[index].state != FULL) continue;
        const char *pieces[4];
        id key = t->keys.describe ? t->keys.describe(t, t->slots[index].key) : pointer_describe(t, t->slots[index].key);
        pieces[0] = key ? (const char *)send0(key, "UTF8String") : "";
        pieces[1] = t->is_hash ? "\n" : " = ";
        id value = t->is_hash ? NULL : (t->values.describe ? t->values.describe(t, t->slots[index].value)
                                                            : pointer_describe(t, t->slots[index].value));
        pieces[2] = value ? (const char *)send0(value, "UTF8String") : "";
        pieces[3] = t->is_hash ? "" : ";\n";
        for (int piece = 0; piece < 4; piece++) {
            const char *add_text = pieces[piece] ? pieces[piece] : "";
            size_t add_length = strlen(add_text);
            if (length + add_length + 1 > capacity) {
                while (length + add_length + 1 > capacity) capacity *= 2;
                char *grown = realloc(text, capacity);
                if (!grown) { free(text); return NULL; }
                text = grown;
            }
            memcpy(text + length, add_text, add_length + 1);
            length += add_length;
        }
    }
    id result = string(text);
    free(text);
    return result;
}

// MARK: - Map tables

table *ns_create_map_table_with_zone(map_key_callbacks keys, map_value_callbacks values, uintptr_t capacity, void *zone)
    DARWIN_SYMBOL("_NSCreateMapTableWithZone");
table *ns_create_map_table_with_zone(map_key_callbacks keys, map_value_callbacks values, uintptr_t capacity, void *zone) {
    (void)zone;
    return make(&keys, &values, capacity, false);
}

table *ns_create_map_table(map_key_callbacks keys, map_value_callbacks values, uintptr_t capacity) DARWIN_SYMBOL("_NSCreateMapTable");
table *ns_create_map_table(map_key_callbacks keys, map_value_callbacks values, uintptr_t capacity) {
    return make(&keys, &values, capacity, false);
}

table *ns_copy_map_table_with_zone(table *t, void *zone) DARWIN_SYMBOL("_NSCopyMapTableWithZone");
table *ns_copy_map_table_with_zone(table *t, void *zone) {
    (void)zone;
    if (!t) return NULL;
    table *copy = make(&t->keys, &t->values, t->count, false);
    for (size_t index = 0; copy && index < t->capacity; index++)
        if (t->slots[index].state == FULL) add(copy, t->slots[index].key, t->slots[index].value);
    return copy;
}

void ns_free_map_table(table *t) DARWIN_SYMBOL("_NSFreeMapTable");
void ns_free_map_table(table *t) {
    if (ours(t)) free_table(t); else send0((id)t, "release");
}

void ns_reset_map_table(table *t) DARWIN_SYMBOL("_NSResetMapTable");
void ns_reset_map_table(table *t) {
    if (ours(t)) reset(t); else send0((id)t, "removeAllObjects");
}

uintptr_t ns_count_map_table(table *t) DARWIN_SYMBOL("_NSCountMapTable");
uintptr_t ns_count_map_table(table *t) { return ours(t) ? t->count : t ? count_of_object(t) : 0; }

void *ns_map_get(table *t, const void *key) DARWIN_SYMBOL("_NSMapGet");
void *ns_map_get(table *t, const void *key) {
    if (t && !ours(t)) return send1((id)t, "objectForKey:", key);
    slot *s = find(t, key);
    return s ? (void *)s->value : NULL;
}

signed char ns_map_member(table *t, const void *key, void **original, void **value) DARWIN_SYMBOL("_NSMapMember");
signed char ns_map_member(table *t, const void *key, void **original, void **value) {
    if (t && !ours(t)) {
        id found = send1((id)t, "objectForKey:", key);
        if (!found) return 0;
        if (original) *original = (void *)key;
        if (value) *value = found;
        return 1;
    }
    slot *s = find(t, key);
    if (!s) return 0;
    if (original) *original = (void *)s->key;
    if (value) *value = (void *)s->value;
    return 1;
}

/// Puts a value in for a key, replacing (and letting go of) any it had.
void ns_map_insert(table *t, const void *key, const void *value) DARWIN_SYMBOL("_NSMapInsert");
void ns_map_insert(table *t, const void *key, const void *value) {
    if (!t) return;
    if (!ours(t)) {
        if (objc_ready())
            ((id (*)(id, void *, const void *, const void *))msg_send)((id)t, register_selector("setObject:forKey:"), value, key);
        return;
    }
    slot *s = find(t, key);
    if (!s) {
        add(t, key, value);
        return;
    }
    if (t->values.retain) t->values.retain(t, value);
    if (t->values.release) t->values.release(t, (void *)s->value);
    s->value = value;
}

void ns_map_insert_known_absent(table *t, const void *key, const void *value) DARWIN_SYMBOL("_NSMapInsertKnownAbsent");
void ns_map_insert_known_absent(table *t, const void *key, const void *value) {
    if (t && !ours(t)) { ns_map_insert(t, key, value); return; }
    if (t) add(t, key, value);
}

/// The key already there, else NULL with the pair put in.
void *ns_map_insert_if_absent(table *t, const void *key, const void *value) DARWIN_SYMBOL("_NSMapInsertIfAbsent");
void *ns_map_insert_if_absent(table *t, const void *key, const void *value) {
    if (!t) return NULL;
    if (!ours(t)) {
        if (send1((id)t, "objectForKey:", key)) return (void *)key;
        ns_map_insert(t, key, value);
        return NULL;
    }
    slot *s = find(t, key);
    if (s) return (void *)s->key;
    add(t, key, value);
    return NULL;
}

void ns_map_remove(table *t, const void *key) DARWIN_SYMBOL("_NSMapRemove");
void ns_map_remove(table *t, const void *key) {
    if (t && !ours(t)) { send1((id)t, "removeObjectForKey:", key); return; }
    slot *s = find(t, key);
    if (s) remove_slot(t, s);
}

enumerator ns_enumerate_map_table(table *t) DARWIN_SYMBOL("_NSEnumerateMapTable");
/// An enumerator of a table object: its keys (a hash table's objects),
/// taken when it starts, retained in the enumerator's last word.
static enumerator enumerate_object(table *t, bool map) {
    id keys = map ? send0(send0((id)t, "keyEnumerator"), "allObjects") : send0((id)t, "allObjects");
    return (enumerator){(uintptr_t)t, 0, send0(keys, "retain")};
}

/// The next key of a table object's enumerator, or NULL at the end.
static id next_of_object(enumerator *e) {
    if (!e->unused || e->index >= (uintptr_t)send0(e->unused, "count")) return NULL;
    return ((id (*)(id, void *, uintptr_t))msg_send)(e->unused, register_selector("objectAtIndex:"), e->index++);
}

static void end_object(enumerator *e) {
    if (e->unused) send0(e->unused, "release");
    e->unused = NULL;
}

enumerator ns_enumerate_map_table(table *t) {
    if (t && !ours(t)) return enumerate_object(t, true);
    return (enumerator){(uintptr_t)t, 0, NULL};
}

signed char ns_next_map_enumerator_pair(enumerator *e, void **key, void **value) DARWIN_SYMBOL("_NSNextMapEnumeratorPair");
signed char ns_next_map_enumerator_pair(enumerator *e, void **key, void **value) {
    if (e && e->table && !ours((table *)e->table)) {
        id found = next_of_object(e);
        if (!found) return 0;
        if (key) *key = found;
        if (value) *value = send1((id)e->table, "objectForKey:", found);
        return 1;
    }
    slot *s = e ? next(e) : NULL;
    if (!s) return 0;
    if (key) *key = (void *)s->key;
    if (value) *value = (void *)s->value;
    return 1;
}

void ns_end_map_table_enumeration(enumerator *e) DARWIN_SYMBOL("_NSEndMapTableEnumeration");
void ns_end_map_table_enumeration(enumerator *e) {
    if (!e) return;
    if (e->table && !ours((table *)e->table)) end_object(e);
    e->table = 0;
}

id ns_all_map_table_keys(table *t) DARWIN_SYMBOL("_NSAllMapTableKeys");
id ns_all_map_table_keys(table *t) {
    return t && !ours(t) ? send0(send0((id)t, "keyEnumerator"), "allObjects") : all(t, false);
}

id ns_all_map_table_values(table *t) DARWIN_SYMBOL("_NSAllMapTableValues");
id ns_all_map_table_values(table *t) {
    return t && !ours(t) ? send0(send0((id)t, "objectEnumerator"), "allObjects") : all(t, true);
}

id ns_string_from_map_table(table *t) DARWIN_SYMBOL("_NSStringFromMapTable");
id ns_string_from_map_table(table *t) { return describe(t); }

signed char ns_compare_map_tables(table *a, table *b) DARWIN_SYMBOL("_NSCompareMapTables");
signed char ns_compare_map_tables(table *a, table *b) {
    if (!a || !b) return a == b;
    if (a->count != b->count) return 0;
    for (size_t index = 0; index < a->capacity; index++) {
        if (a->slots[index].state != FULL) continue;
        slot *s = find(b, a->slots[index].key);
        if (!s || s->value != a->slots[index].value) return 0;
    }
    return 1;
}

// MARK: - Hash tables

static map_key_callbacks keys_of(const hash_callbacks *callbacks) {
    map_key_callbacks keys = {0};
    if (callbacks) {
        keys.hash = callbacks->hash;
        keys.isEqual = callbacks->isEqual;
        keys.retain = callbacks->retain;
        keys.release = callbacks->release;
        keys.describe = callbacks->describe;
    }
    return keys;
}

table *ns_create_hash_table_with_zone(hash_callbacks callbacks, uintptr_t capacity, void *zone) DARWIN_SYMBOL("_NSCreateHashTableWithZone");
table *ns_create_hash_table_with_zone(hash_callbacks callbacks, uintptr_t capacity, void *zone) {
    (void)zone;
    map_key_callbacks keys = keys_of(&callbacks);
    return make(&keys, NULL, capacity, true);
}

table *ns_create_hash_table(hash_callbacks callbacks, uintptr_t capacity) DARWIN_SYMBOL("_NSCreateHashTable");
table *ns_create_hash_table(hash_callbacks callbacks, uintptr_t capacity) {
    map_key_callbacks keys = keys_of(&callbacks);
    return make(&keys, NULL, capacity, true);
}

table *ns_copy_hash_table_with_zone(table *t, void *zone) DARWIN_SYMBOL("_NSCopyHashTableWithZone");
table *ns_copy_hash_table_with_zone(table *t, void *zone) {
    (void)zone;
    if (!t) return NULL;
    table *copy = make(&t->keys, NULL, t->count, true);
    for (size_t index = 0; copy && index < t->capacity; index++)
        if (t->slots[index].state == FULL) add(copy, t->slots[index].key, NULL);
    return copy;
}

void ns_free_hash_table(table *t) DARWIN_SYMBOL("_NSFreeHashTable");
void ns_free_hash_table(table *t) {
    if (ours(t)) free_table(t); else send0((id)t, "release");
}

void ns_reset_hash_table(table *t) DARWIN_SYMBOL("_NSResetHashTable");
void ns_reset_hash_table(table *t) {
    if (ours(t)) reset(t); else send0((id)t, "removeAllObjects");
}

uintptr_t ns_count_hash_table(table *t) DARWIN_SYMBOL("_NSCountHashTable");
uintptr_t ns_count_hash_table(table *t) { return ours(t) ? t->count : t ? count_of_object(t) : 0; }

void *ns_hash_get(table *t, const void *item) DARWIN_SYMBOL("_NSHashGet");
void *ns_hash_get(table *t, const void *item) {
    if (t && !ours(t)) return send1((id)t, "member:", item);
    slot *s = find(t, item);
    return s ? (void *)s->key : NULL;
}

/// Puts an item in, replacing (and letting go of) an equal one.
void ns_hash_insert(table *t, const void *item) DARWIN_SYMBOL("_NSHashInsert");
void ns_hash_insert(table *t, const void *item) {
    if (!t) return;
    if (!ours(t)) { send1((id)t, "addObject:", item); return; }
    slot *s = find(t, item);
    if (s) remove_slot(t, s);
    add(t, item, NULL);
}

void ns_hash_insert_known_absent(table *t, const void *item) DARWIN_SYMBOL("_NSHashInsertKnownAbsent");
void ns_hash_insert_known_absent(table *t, const void *item) {
    if (t && !ours(t)) { send1((id)t, "addObject:", item); return; }
    if (t) add(t, item, NULL);
}

void *ns_hash_insert_if_absent(table *t, const void *item) DARWIN_SYMBOL("_NSHashInsertIfAbsent");
void *ns_hash_insert_if_absent(table *t, const void *item) {
    if (!t) return NULL;
    if (!ours(t)) {
        id found = send1((id)t, "member:", item);
        if (found) return found;
        send1((id)t, "addObject:", item);
        return NULL;
    }
    slot *s = find(t, item);
    if (s) return (void *)s->key;
    add(t, item, NULL);
    return NULL;
}

void ns_hash_remove(table *t, const void *item) DARWIN_SYMBOL("_NSHashRemove");
void ns_hash_remove(table *t, const void *item) {
    if (t && !ours(t)) { send1((id)t, "removeObject:", item); return; }
    slot *s = find(t, item);
    if (s) remove_slot(t, s);
}

enumerator ns_enumerate_hash_table(table *t) DARWIN_SYMBOL("_NSEnumerateHashTable");
enumerator ns_enumerate_hash_table(table *t) {
    if (t && !ours(t)) return enumerate_object(t, false);
    return (enumerator){(uintptr_t)t, 0, NULL};
}

void *ns_next_hash_enumerator_item(enumerator *e) DARWIN_SYMBOL("_NSNextHashEnumeratorItem");
void *ns_next_hash_enumerator_item(enumerator *e) {
    if (e && e->table && !ours((table *)e->table)) return next_of_object(e);
    slot *s = e ? next(e) : NULL;
    return s ? (void *)s->key : NULL;
}

void ns_end_hash_table_enumeration(enumerator *e) DARWIN_SYMBOL("_NSEndHashTableEnumeration");
void ns_end_hash_table_enumeration(enumerator *e) {
    if (!e) return;
    if (e->table && !ours((table *)e->table)) end_object(e);
    e->table = 0;
}

id ns_all_hash_table_objects(table *t) DARWIN_SYMBOL("_NSAllHashTableObjects");
id ns_all_hash_table_objects(table *t) { return t && !ours(t) ? send0((id)t, "allObjects") : all(t, false); }

id ns_string_from_hash_table(table *t) DARWIN_SYMBOL("_NSStringFromHashTable");
id ns_string_from_hash_table(table *t) { return describe(t); }

signed char ns_compare_hash_tables(table *a, table *b) DARWIN_SYMBOL("_NSCompareHashTables");
signed char ns_compare_hash_tables(table *a, table *b) {
    if (!a || !b) return a == b;
    if (a->count != b->count) return 0;
    for (size_t index = 0; index < a->capacity; index++)
        if (a->slots[index].state == FULL && !find(b, a->slots[index].key)) return 0;
    return 1;
}
