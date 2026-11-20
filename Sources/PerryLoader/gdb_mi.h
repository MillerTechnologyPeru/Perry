#pragma once

#include <stdbool.h>

// Whether `executable` is Apple's gdb, which perry answers for itself.
bool perry_gdb_mi_wanted(const char *executable);

// Answers Xcode's GDB/MI on standard input and output; gdb's arguments.
int perry_gdb_mi(int argc, char **argv);
