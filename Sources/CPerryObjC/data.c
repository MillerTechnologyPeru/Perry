// Data symbols libobjc exports, under their Mach-O names. Swift reaches them
// through the accessors in CPerryObjC.h.

#include "CPerryObjC.h"

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

// One empty bucket with mask 0: every probe misses.
static perry_cache_bucket empty_table_storage[2];

// _objc_empty_cache. Its first word is read as a cache table, like a
// realized class's perry_class_header.
void *darwin_objc_empty_cache[2] DARWIN_SYMBOL("__objc_empty_cache") = { empty_table_storage, 0 };
void *darwin_objc_empty_vtable DARWIN_SYMBOL("__objc_empty_vtable");

void *perry_objc_empty_cache_table(void) { return empty_table_storage; }
void *perry_objc_empty_cache(void) { return darwin_objc_empty_cache; }

// Root classes. The Swift runtime fills these in at startup, before any
// Mach-O code runs; images bind to the addresses when they load.
perry_objc_class nsobject_class DARWIN_SYMBOL("_OBJC_CLASS_$_NSObject");
perry_objc_class nsobject_metaclass DARWIN_SYMBOL("_OBJC_METACLASS_$_NSObject");
perry_objc_class protocol_class DARWIN_SYMBOL("_OBJC_CLASS_$_Protocol");
perry_objc_class protocol_metaclass DARWIN_SYMBOL("_OBJC_METACLASS_$_Protocol");

perry_objc_class *perry_objc_nsobject_class(void) { return &nsobject_class; }
perry_objc_class *perry_objc_nsobject_metaclass(void) { return &nsobject_metaclass; }
perry_objc_class *perry_objc_protocol_class(void) { return &protocol_class; }
perry_objc_class *perry_objc_protocol_metaclass(void) { return &protocol_metaclass; }
