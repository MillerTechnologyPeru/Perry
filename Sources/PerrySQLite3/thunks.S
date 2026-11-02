// Darwin entry points for SQLite's variadic and va_list functions.

#include "perry_wrapped.h"

#if defined(__aarch64__) && defined(__ELF__)

.text

// Formatting, which has va_list forms.
VARIADIC _sqlite3_mprintf, sqlite3_vmprintf, 1
VA_LIST _sqlite3_vmprintf, sqlite3_vmprintf, 1
VARIADIC _sqlite3_snprintf, sqlite3_vsnprintf, 3
VA_LIST _sqlite3_vsnprintf, sqlite3_vsnprintf, 3
VARIADIC _sqlite3_str_appendf, sqlite3_str_vappendf, 2
VA_LIST _sqlite3_str_vappendf, sqlite3_str_vappendf, 2

// The rest, through provider.c.
VARIADIC _sqlite3_config, perry_sqlite3_config_v, 1
VARIADIC _sqlite3_db_config, perry_sqlite3_db_config_v, 2
VARIADIC _sqlite3_vtab_config, perry_sqlite3_vtab_config_v, 2
VARIADIC _sqlite3_test_control, perry_sqlite3_test_control_v, 1
VARIADIC _sqlite3_log, perry_sqlite3_log_v, 2

#endif

.section .note.GNU-stack, "", %progbits
