// libPerrysqlite3: the provider for /usr/lib/libsqlite3.dylib.
//
// It binds to libperry-sqlite3: SQLite 3.54.0, the iOS SDK's version, built
// with Apple's compile options where they change behaviour (see the
// Dockerfile). SQLite's handles are opaque and its callbacks are not
// variadic, so every import binds straight to it except the variadic
// functions: thunks.S converts those with va_list forms, and this file
// handles the rest.
//
// Apple's SQLite also opens every connection in defensive mode, with
// legacy ALTER TABLE behaviour and fast secure delete; sqlite3_open and its
// variants here apply the same settings.
//
// sqlite3_config, sqlite3_db_config, sqlite3_vtab_config and
// sqlite3_test_control take arguments that depend on the operation, but
// only integers and pointers, which Darwin passes in 8-byte stack slots and
// Linux in general registers, in order. So each forwards the slots as
// words, as many as any operation takes: the callee reads the ones its
// operation uses, as it would have read the registers.

#include "PerrySQLite3.h"
#include "perry_wrapped.h"

#include <stdarg.h>
#include <stdint.h>

#define INTERNAL __attribute__((visibility("hidden")))

typedef struct sqlite3 sqlite3;

extern const char *sqlite3_libversion(void);
extern int sqlite3_config(int op, ...);
extern int sqlite3_db_config(sqlite3 *db, int op, ...);
extern int sqlite3_vtab_config(sqlite3 *db, int op, ...);
extern int sqlite3_test_control(int op, ...);
extern void sqlite3_log(int code, const char *format, ...);
extern char *sqlite3_vmprintf(const char *format, va_list ap);
extern void sqlite3_free(void *pointer);
extern int sqlite3_open(const char *filename, sqlite3 **db);
extern int sqlite3_open16(const void *filename, sqlite3 **db);
extern int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs);
extern int sqlite3_exec(sqlite3 *db, const char *sql, void *callback, void *context, char **error);

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

enum {
    SQLITE_OK = 0,
    SQLITE_DBCONFIG_DEFENSIVE = 1010,
    SQLITE_DBCONFIG_LEGACY_ALTER_TABLE = 1012,
};

static perry_wrapped_library sqlite = PERRY_WRAPPED_LIBRARY(sqlite3_libversion);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&sqlite, name, NULL);
}

/// The next `count` Darwin argument slots.
static void words(va_list ap, uint64_t *out, int count) {
    for (int i = 0; i < count; i++)
        out[i] = va_arg(ap, uint64_t);
}

// The longest operations take three arguments after the operation
// (SQLITE_CONFIG_PAGECACHE: pointer, size, count); test controls up to four.

INTERNAL int perry_sqlite3_config_v(int op, va_list ap) {
    uint64_t w[3];
    words(ap, w, 3);
    return sqlite3_config(op, w[0], w[1], w[2]);
}

INTERNAL int perry_sqlite3_db_config_v(sqlite3 *db, int op, va_list ap) {
    uint64_t w[3];
    words(ap, w, 3);
    return sqlite3_db_config(db, op, w[0], w[1], w[2]);
}

INTERNAL int perry_sqlite3_vtab_config_v(sqlite3 *db, int op, va_list ap) {
    uint64_t w[3];
    words(ap, w, 3);
    return sqlite3_vtab_config(db, op, w[0], w[1], w[2]);
}

INTERNAL int perry_sqlite3_test_control_v(int op, va_list ap) {
    uint64_t w[4];
    words(ap, w, 4);
    return sqlite3_test_control(op, w[0], w[1], w[2], w[3]);
}

/// sqlite3_log has no va_list form: the message is formatted, then logged.
INTERNAL void perry_sqlite3_log_v(int code, const char *format, va_list ap) {
    char *message = sqlite3_vmprintf(format, ap);
    sqlite3_log(code, "%s", message ? message : "");
    sqlite3_free(message);
}

// MARK: - Opening connections as Apple's SQLite does

static int with_apple_defaults(int status, sqlite3 *db) {
    if (status == SQLITE_OK && db) {
        sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, (int *)0);
        sqlite3_db_config(db, SQLITE_DBCONFIG_LEGACY_ALTER_TABLE, 1, (int *)0);
        sqlite3_exec(db, "PRAGMA secure_delete = FAST", 0, 0, 0);
    }
    return status;
}

int darwin_sqlite3_open(const char *filename, sqlite3 **db) DARWIN_SYMBOL(sqlite3_open);
int darwin_sqlite3_open(const char *filename, sqlite3 **db) {
    return with_apple_defaults(sqlite3_open(filename, db), db ? *db : 0);
}

int darwin_sqlite3_open16(const void *filename, sqlite3 **db) DARWIN_SYMBOL(sqlite3_open16);
int darwin_sqlite3_open16(const void *filename, sqlite3 **db) {
    return with_apple_defaults(sqlite3_open16(filename, db), db ? *db : 0);
}

int darwin_sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) DARWIN_SYMBOL(sqlite3_open_v2);
int darwin_sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    return with_apple_defaults(sqlite3_open_v2(filename, db, flags, vfs), db ? *db : 0);
}
