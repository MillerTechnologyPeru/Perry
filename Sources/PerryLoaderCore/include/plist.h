#ifndef PERRY_PLIST_H
#define PERRY_PLIST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Property list reader for XML and binary (bplist00) formats.

typedef enum {
    PERRY_PLIST_STRING,
    PERRY_PLIST_INTEGER,
    PERRY_PLIST_REAL,
    PERRY_PLIST_BOOL,
    PERRY_PLIST_DATE,       // seconds since 2001-01-01, stored in `real`
    PERRY_PLIST_DATA,
    PERRY_PLIST_UID,        // stored in `integer`
    PERRY_PLIST_ARRAY,
    PERRY_PLIST_DICT,
} perry_plist_type;

typedef struct perry_plist {
    perry_plist_type type;
    union {
        char *string;
        int64_t integer;
        double real;
        bool boolean;
        struct { uint8_t *bytes; size_t length; } data;
        struct {
            struct perry_plist **values;
            char **keys;        // dictionaries only
            size_t count;
        } container;
    };
} perry_plist;

perry_plist *perry_plist_parse(const uint8_t *bytes, size_t length, const char **error);
perry_plist *perry_plist_load(const char *path, const char **error);
void perry_plist_free(perry_plist *plist);

const perry_plist *perry_plist_get(const perry_plist *dict, const char *key);
const char *perry_plist_get_string(const perry_plist *dict, const char *key);

#endif
