// libPerryncurses: the provider for /usr/lib/libncurses.5.4.dylib, Darwin's
// ncurses, over Linux's. Its termcap and terminfo functions (tgetent, tputs,
// setupterm…) live in libtinfo, and its screen functions in libncursesw,
// which depends on libtinfo; both are opened by soname, so where neither is
// installed the imports stay unresolved and only fail if called. The data
// symbols termcap programs read (BC, PC, UP, ospeed) are libtinfo's own.
// The variadic functions are not bound: arm64's Darwin passes variadic
// arguments differently. A WINDOW's fields are not laid out like Linux's.

#include "PerryNcurses.h"
#include "perry_wrapped.h"

#include <string.h>

static perry_wrapped_library tinfo = PERRY_WRAPPED_SONAME("libtinfo.so.6");
static perry_wrapped_library ncurses = PERRY_WRAPPED_SONAME("libncursesw.so.6");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
#if defined(__aarch64__)
    static const char *const variadic[] = {
        "_tparm", "_printw", "_wprintw", "_mvprintw", "_mvwprintw", "_scanw", "_wscanw", "_mvscanw",
        "_mvwscanw", "_vw_printw", "_vwprintw", NULL,
    };
    if (name)
        for (const char *const *v = variadic; *v; v++)
            if (strcmp(name, *v) == 0)
                return NULL;
#endif
    void *symbol = perry_wrapped_symbol(&tinfo, name, NULL);
    return symbol ? symbol : perry_wrapped_symbol(&ncurses, name, NULL);
}
