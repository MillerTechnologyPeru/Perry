#ifndef PERRY_SQLITE3_H
#define PERRY_SQLITE3_H

// libPerrysqlite3: Darwin's SQLite imports, bound to SQLite 3.54 built for
// Perry (libperry-sqlite3).

/// SQLite's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
