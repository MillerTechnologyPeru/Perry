// glibc functions box86's libc bridge lacks, for i386 Perry built against
// glibc 2.38 or newer, as the older names box86 does wrap. Preloaded with
// BOX86_LD_PRELOAD; libc23box.map gives each its glibc version, which the
// libraries asking for it name.
#include <stdarg.h>
#include <stdio.h>
#include <wchar.h>

unsigned long strtoul(const char *, char **, int);
int __isoc99_vfscanf(FILE *, const char *, va_list);
int __isoc99_vscanf(const char *, va_list);
int __isoc99_vsscanf(const char *, const char *, va_list);
int __isoc99_vswscanf(const wchar_t *, const wchar_t *, va_list);

// C23's scanf and strtol families, which take 0b numbers: as C99's.
unsigned long __isoc23_strtoul(const char *s, char **e, int b) { return strtoul(s, e, b); }
int __isoc23_vfscanf(FILE *f, const char *t, va_list a) { return __isoc99_vfscanf(f, t, a); }
int __isoc23_vscanf(const char *t, va_list a) { return __isoc99_vscanf(t, a); }
int __isoc23_vsscanf(const char *s, const char *t, va_list a) { return __isoc99_vsscanf(s, t, a); }
int __isoc23_vswscanf(const wchar_t *s, const wchar_t *t, va_list a) { return __isoc99_vswscanf(s, t, a); }

// capget and capset, for the i386 libcap where no native one is installed:
// the i386 system calls.
long syscall(long, ...);
int capget(void *header, void *data) { return (int)syscall(184, header, data); }
int capset(void *header, const void *data) { return (int)syscall(185, header, data); }

// <search.h>'s binary trees, which box86 doesn't wrap and libPerrySystem
// passes on to programs: an unbalanced tree. A node begins with its key, as
// twalk's and tfind's callers read it.
#include <stdlib.h>

typedef struct tree_node { const void *key; struct tree_node *left, *right; } tree_node;
typedef enum { preorder, postorder, endorder, leaf } VISIT;

void *tsearch(const void *key, void **root, int (*compare)(const void *, const void *)) {
    if (!root) return NULL;
    tree_node **slot = (tree_node **)root;
    while (*slot) {
        int order = compare(key, (*slot)->key);
        if (order == 0) return *slot;
        slot = order < 0 ? &(*slot)->left : &(*slot)->right;
    }
    tree_node *made = calloc(1, sizeof *made);
    if (!made) return NULL;
    made->key = key;
    *slot = made;
    return made;
}

void *tfind(const void *key, void *const *root, int (*compare)(const void *, const void *)) {
    for (tree_node *node = root ? *(tree_node *const *)root : NULL; node;) {
        int order = compare(key, node->key);
        if (order == 0) return node;
        node = order < 0 ? node->left : node->right;
    }
    return NULL;
}

// The removed node's parent, or the root's address's contents for the root.
void *tdelete(const void *key, void **root, int (*compare)(const void *, const void *)) {
    if (!root || !*root) return NULL;
    tree_node **slot = (tree_node **)root, *parent = *slot;
    while (*slot) {
        int order = compare(key, (*slot)->key);
        if (order == 0) break;
        parent = *slot;
        slot = order < 0 ? &(*slot)->left : &(*slot)->right;
    }
    tree_node *found = *slot;
    if (!found) return NULL;
    if (!found->left) {
        *slot = found->right;
    } else if (!found->right) {
        *slot = found->left;
    } else {
        // The next key in order takes its place.
        tree_node **next = &found->right;
        while ((*next)->left) next = &(*next)->left;
        tree_node *moved = *next;
        *next = moved->right;
        moved->left = found->left;
        moved->right = found->right;
        *slot = moved;
    }
    free(found);
    return parent;
}

static void walk(const tree_node *node, void (*action)(const void *, VISIT, int), int depth) {
    if (!node->left && !node->right) {
        action(node, leaf, depth);
        return;
    }
    action(node, preorder, depth);
    if (node->left) walk(node->left, action, depth + 1);
    action(node, postorder, depth);
    if (node->right) walk(node->right, action, depth + 1);
    action(node, endorder, depth);
}

void twalk(const void *root, void (*action)(const void *, VISIT, int)) {
    if (root && action) walk(root, action, 0);
}

// openpty, which glibc 2.34 moved into libc from libutil, where box86 knows
// it: a pseudoterminal's two ends, by the calls it is made of.
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int posix_openpt(int);
int grantpt(int);
int unlockpt(int);
int ptsname_r(int, char *, size_t);

int openpty(int *controller, int *terminal, char *name, const struct termios *settings, const struct winsize *size) {
    int first = posix_openpt(O_RDWR | O_NOCTTY);
    if (first < 0) return -1;
    char path[128];
    if (grantpt(first) != 0 || unlockpt(first) != 0 || ptsname_r(first, path, sizeof path) != 0) {
        close(first);
        return -1;
    }
    int second = open(path, O_RDWR | O_NOCTTY);
    if (second < 0) {
        close(first);
        return -1;
    }
    if (settings) tcsetattr(second, TCSAFLUSH, settings);
    if (size) ioctl(second, TIOCSWINSZ, size);
    if (controller) *controller = first;
    if (terminal) *terminal = second;
    if (name) strcpy(name, path);
    return 0;
}

// Two X functions the i386 cairo names and box86's X11 and XCB bridges
// lack. They belong to cairo's Xlib and XCB surfaces, which Perry, drawing
// into images, never makes: nothing is read, and no reply is waiting.
int xcb_poll_for_reply(void *connection, unsigned int request, void **reply, void **error) {
    (void)connection, (void)request;
    if (reply) *reply = 0;
    if (error) *error = 0;
    return 0;
}

void _XReadEvents(void *display) { (void)display; }
