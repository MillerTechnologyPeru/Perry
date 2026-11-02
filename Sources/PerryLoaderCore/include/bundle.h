#ifndef PERRY_BUNDLE_H
#define PERRY_BUNDLE_H

#include "plist.h"

// An iOS (.app with a flat layout) or macOS (Contents/MacOS) bundle.
typedef struct perry_bundle {
    char *path;                 // bundle directory, absolute
    char *executable_path;      // absolute path of CFBundleExecutable
    char *identifier;           // CFBundleIdentifier, may be NULL
    perry_plist *info;          // parsed Info.plist
} perry_bundle;

// Returns true and fills `bundle` when `path` is a bundle directory.
// Exits with an error when it is a directory that is not a valid bundle.
bool perry_bundle_open(const char *path, perry_bundle *bundle);
void perry_bundle_close(perry_bundle *bundle);

#endif
