// SQLite: the variadic API (configuration, formatting, logging), prepared
// statements and binds, callbacks, custom functions, errors, and features
// that depend on how Apple builds SQLite (JSON, FTS5, math functions,
// normalized SQL, no automatic reset of finished statements).

#import <Foundation/Foundation.h>
#include <sqlite3.h>
#include <stdarg.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

/// SQLite's log, without positions inside the library, which depend on how
/// it was built: the line of sqlite3.c some messages end with, and the
/// bytecode address a statement aborted at.
static void logged(void *context, int code, const char *message) {
    NSString *text = [NSString stringWithUTF8String:message];
    NSRange position = [text rangeOfString:@" at line "];
    if (position.location != NSNotFound) {
        text = [text substringToIndex:position.location];
    }
    NSRange aborts = [text rangeOfString:@"statement aborts at "];
    if (aborts.location != NSNotFound) {
        NSRange end = [text rangeOfString:@":" options:0
                                    range:NSMakeRange(NSMaxRange(aborts), text.length - NSMaxRange(aborts))];
        text = [text stringByReplacingCharactersInRange:NSMakeRange(aborts.location, end.location - aborts.location)
                                             withString:@"statement aborts"];
    }
    say([NSString stringWithFormat:@"log %d: %@", code, text]);
}

static int printRow(void *context, int columns, char **values, char **names) {
    NSMutableArray *pairs = [NSMutableArray array];
    for (int i = 0; i < columns; i++) {
        [pairs addObject:[NSString stringWithFormat:@"%s=%s", names[i], values[i] ?: "NULL"]];
    }
    say([NSString stringWithFormat:@"row %@ (%s)", [pairs componentsJoinedByString:@", "], (const char *)context]);
    return 0;
}

/// reverse(text): a custom scalar function.
static void reverseFunction(sqlite3_context *context, int count, sqlite3_value **values) {
    const unsigned char *text = sqlite3_value_text(values[0]);
    if (!text) {
        sqlite3_result_null(context);
        return;
    }
    NSString *string = [NSString stringWithUTF8String:(const char *)text];
    NSMutableString *reversed = [NSMutableString string];
    for (NSInteger i = (NSInteger)string.length - 1; i >= 0; i--) {
        [reversed appendFormat:@"%C", [string characterAtIndex:(NSUInteger)i]];
    }
    sqlite3_result_text(context, reversed.UTF8String, -1, SQLITE_TRANSIENT);
}

static char *formatted(const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    char *text = sqlite3_vmprintf(format, ap);
    va_end(ap);
    return text;
}

static void exec(sqlite3 *db, const char *sql) {
    char *error = NULL;
    int status = sqlite3_exec(db, sql, NULL, NULL, &error);
    if (status != SQLITE_OK) {
        say([NSString stringWithFormat:@"exec %d: %s", status, error]);
        sqlite3_free(error);
    }
}

static void query(sqlite3 *db, const char *sql) {
    sqlite3_stmt *statement;
    if (sqlite3_prepare_v2(db, sql, -1, &statement, NULL) != SQLITE_OK) {
        say([NSString stringWithFormat:@"prepare failed: %s", sqlite3_errmsg(db)]);
        return;
    }
    while (sqlite3_step(statement) == SQLITE_ROW) {
        NSMutableArray *values = [NSMutableArray array];
        for (int i = 0; i < sqlite3_column_count(statement); i++) {
            switch (sqlite3_column_type(statement, i)) {
                case SQLITE_INTEGER: [values addObject:[NSString stringWithFormat:@"%lld", sqlite3_column_int64(statement, i)]]; break;
                case SQLITE_FLOAT: [values addObject:[NSString stringWithFormat:@"%.4f", sqlite3_column_double(statement, i)]]; break;
                case SQLITE_TEXT: [values addObject:[NSString stringWithFormat:@"'%s'", sqlite3_column_text(statement, i)]]; break;
                case SQLITE_BLOB: [values addObject:[NSString stringWithFormat:@"blob(%d)", sqlite3_column_bytes(statement, i)]]; break;
                default: [values addObject:@"NULL"];
            }
        }
        say([NSString stringWithFormat:@"  %@", [values componentsJoinedByString:@" | "]]);
    }
    sqlite3_finalize(statement);
}

int main(void) {
    @autoreleasepool {
        int configured = sqlite3_config(SQLITE_CONFIG_LOG, logged, NULL);
        say([NSString stringWithFormat:@"version %s, threadsafe %d, config log %d", sqlite3_libversion(),
             sqlite3_threadsafe(), configured]);
        sqlite3_log(SQLITE_NOTICE, "custom message %d of %s", 7, "seven");

        sqlite3 *db;
        sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
        int foreignKeys = -1;
        int status = sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_FKEY, 1, &foreignKeys);
        say([NSString stringWithFormat:@"db_config foreign keys: status %d, now %d", status, foreignKeys]);
        int defensive = -1;
        sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, -1, &defensive);
        say([NSString stringWithFormat:@"defensive %d", defensive]);
        query(db, "SELECT * FROM pragma_auto_vacuum, pragma_recursive_triggers, pragma_secure_delete,"
                  " pragma_legacy_alter_table, pragma_cache_size, pragma_foreign_keys");

        exec(db, "CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);"
                 "CREATE TABLE books (id INTEGER PRIMARY KEY, author INTEGER REFERENCES authors(id) ON DELETE CASCADE,"
                 " title TEXT, year INTEGER, price REAL, cover BLOB);");

        // Binds, in a transaction.
        exec(db, "BEGIN");
        sqlite3_stmt *insert;
        sqlite3_prepare_v2(db, "INSERT INTO authors (name) VALUES (?1)", -1, &insert, NULL);
        for (NSString *name in @[@"Stanisław Lem", @"Frank Herbert", @"Ursula K. Le Guin"]) {
            sqlite3_bind_text(insert, 1, name.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_step(insert);
            sqlite3_reset(insert);
        }
        sqlite3_finalize(insert);
        sqlite3_prepare_v2(db, "INSERT INTO books (author, title, year, price, cover) VALUES (?, ?, ?, ?, ?)", -1, &insert, NULL);
        struct { int author; const char *title; int year; double price; int cover; } books[] = {
            {1, "Solaris", 1961, 12.5, 4}, {1, "The Cyberiad", 1965, 9.99, 0}, {2, "Dune", 1965, 15.0, 8},
            {3, "The Dispossessed", 1974, 11.25, 2},
        };
        for (int i = 0; i < 4; i++) {
            sqlite3_bind_int(insert, 1, books[i].author);
            sqlite3_bind_text(insert, 2, books[i].title, -1, SQLITE_STATIC);
            sqlite3_bind_int64(insert, 3, books[i].year);
            sqlite3_bind_double(insert, 4, books[i].price);
            if (books[i].cover) {
                uint8_t bytes[8] = {1, 2, 3, 4, 5, 6, 7, 8};
                sqlite3_bind_blob(insert, 5, bytes, books[i].cover, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(insert, 5);
            }
            sqlite3_step(insert);
            sqlite3_reset(insert);
        }
        sqlite3_finalize(insert);
        exec(db, "COMMIT");
        say([NSString stringWithFormat:@"last row %lld, changes %d, total %d", sqlite3_last_insert_rowid(db),
             sqlite3_changes(db), sqlite3_total_changes(db)]);

        query(db, "SELECT a.name, b.title, b.year, b.price, b.cover FROM books b JOIN authors a ON a.id = b.author ORDER BY b.year, b.title");
        sqlite3_exec(db, "SELECT year, count(*) AS n FROM books GROUP BY year ORDER BY year", printRow, "by year", NULL);

        sqlite3_create_function_v2(db, "reverse", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, NULL, reverseFunction, NULL, NULL, NULL);
        query(db, "SELECT reverse(title) FROM books WHERE year < 1970 ORDER BY id");

        // Errors.
        exec(db, "INSERT INTO authors (name) VALUES ('Dune')");
        exec(db, "INSERT INTO authors (name) VALUES ('Frank Herbert')");
        say([NSString stringWithFormat:@"errcode %d, extended %d, errstr %s", sqlite3_errcode(db),
             sqlite3_extended_errcode(db), sqlite3_errstr(SQLITE_BUSY)]);
        exec(db, "INSERT INTO books (author, title) VALUES (99, 'Nobody')");
        exec(db, "SELEC nonsense");
        exec(db, "DELETE FROM authors WHERE id = 1");
        query(db, "SELECT count(*) FROM books");

        // Formatting.
        char *sql = sqlite3_mprintf("INSERT INTO %w VALUES(%Q, %q, %Q, %d, %lld, %.3f)", "odd\"table", "it's", "o'k",
                                    NULL, -5, (sqlite3_int64)1 << 40, 3.14159);
        say([NSString stringWithFormat:@"mprintf: %s", sql]);
        sqlite3_free(sql);
        char buffer[24];
        sqlite3_snprintf(sizeof buffer, buffer, "%s-%05d-%x-%c", "snprintf truncates here", 42, 255, 'z');
        say([NSString stringWithFormat:@"snprintf: %s", buffer]);
        char *viaList = formatted("%s/%d/%.1f%%", "vmprintf", 12, 99.5);
        say([NSString stringWithFormat:@"vmprintf: %s", viaList]);
        sqlite3_free(viaList);
        sqlite3_str *builder = sqlite3_str_new(db);
        for (int i = 1; i <= 3; i++) {
            sqlite3_str_appendf(builder, "%s%d=%Q", i > 1 ? ";" : "", i, i == 2 ? NULL : "v");
        }
        char *built = sqlite3_str_finish(builder);
        say([NSString stringWithFormat:@"str_appendf: %s", built]);
        sqlite3_free(built);

        // Features of Apple's build.
        query(db, "SELECT json_extract('{\"a\":[1,2,{\"b\":\"x\"}]}', '$.a[2].b'), json_array_length('[1,2,3]'),"
                  " json_group_array(year) FROM books");
        exec(db, "CREATE VIRTUAL TABLE notes USING fts5(body);"
                 "INSERT INTO notes VALUES ('the ocean of Solaris thinks'), ('spice must flow on Dune'),"
                 " ('anarchists on Anarres');");
        query(db, "SELECT highlight(notes, 0, '[', ']') FROM notes WHERE notes MATCH 'ocean OR spice' ORDER BY rowid");
        query(db, "SELECT sqrt(16), round(pi(), 5), pow(2, 10), log10(1000)");
        query(db, "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 5)"
                  " SELECT group_concat(i, ','), sum(i) FROM n");
        query(db, "SELECT title, rank() OVER (ORDER BY price DESC) FROM books ORDER BY 2");

        sqlite3_stmt *statement;
        sqlite3_prepare_v2(db, "SELECT title FROM books WHERE year > 1960 AND title LIKE 'S%'", -1, &statement, NULL);
        say([NSString stringWithFormat:@"normalized: %s", sqlite3_normalized_sql(statement)]);
        int first = sqlite3_step(statement);
        while (sqlite3_step(statement) == SQLITE_ROW) {}
        int again = sqlite3_step(statement);
        say([NSString stringWithFormat:@"steps: %d, after done %d", first, again]);
        sqlite3_finalize(statement);

        say([NSString stringWithFormat:@"close %d", sqlite3_close(db)]);
    }
    return 0;
}
