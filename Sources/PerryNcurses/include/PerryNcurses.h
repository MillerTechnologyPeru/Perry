#ifndef PERRYNCURSES_H
#define PERRYNCURSES_H

// libPerryncurses: Darwin's ncurses 5.4 imports (curses, terminfo and
// termcap), bound to Linux's libtinfo and libncursesw.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
