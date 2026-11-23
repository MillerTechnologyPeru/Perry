// libPerryresolv: the provider for /usr/lib/libresolv.9.dylib, Darwin's
// BIND 9 resolver, whose names carry a res_9_ prefix.
//
// Programs set up a resolver state to read the system's name servers from
// it (ad and analytics SDKs report them). res_9_ninit fills Darwin's state
// from glibc's own resolver configuration (/etc/resolv.conf): the IPv4 name
// servers, the search domains and the options a fresh state has. The state
// is Darwin's layout, mirrored below: its fields are ints, longs, pointers
// and arrays of them, which lie alike on Darwin and Linux for the same
// word size; only sockaddr_in differs (Darwin's starts with a length byte).

#define _GNU_SOURCE
#include "PerryResolv.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <resolv.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

// Darwin's <resolv.h> limits.
#define DARWIN_MAXNS 3
#define DARWIN_MAXDNSRCH 6
#define DARWIN_MAXRESOLVSORT 10
#define DARWIN_MAXDNAME 256

// Darwin's option flags a fresh state has (RES_INIT, and RES_DEFAULT:
// RES_RECURSE | RES_DEFNAMES | RES_DNSRCH), its timeout and retries.
#define DARWIN_RES_INIT 0x00000001UL
#define DARWIN_RES_DEFAULT (0x00000040UL | 0x00000080UL | 0x00000200UL)
#define DARWIN_RES_TIMEOUT 5
#define DARWIN_RES_DFLRETRY 2

/// Darwin's struct sockaddr_in: a length byte before an 8-bit family.
struct darwin_sockaddr_in {
    uint8_t sin_len;
    uint8_t sin_family;
    uint16_t sin_port;
    uint32_t sin_addr;
    char sin_zero[8];
};

/// Darwin's struct __res_9_state.
struct darwin_res_state {
    int retrans;
    int retry;
    unsigned long options;
    int nscount;
    struct darwin_sockaddr_in nsaddr_list[DARWIN_MAXNS];
    unsigned short id;
    char *dnsrch[DARWIN_MAXDNSRCH + 1];
    char defdname[DARWIN_MAXDNAME];
    unsigned long pfcode;
    unsigned ndots : 4;
    unsigned nsort : 4;
    char unused[3];
    struct {
        uint32_t addr;
        uint32_t mask;
    } sort_list[DARWIN_MAXRESOLVSORT];
    void *qhook;
    void *rhook;
    int res_h_errno;
    int _vcsock;
    unsigned _flags;
    unsigned _pad;
    union {
        char pad[72 - 4 * sizeof(int) - 3 * sizeof(void *)];
        struct {
            uint16_t nscount;
            uint16_t nstimes[DARWIN_MAXNS];
            int nssocks[DARWIN_MAXNS];
            void *ext;
        } _ext;
    } _u;
    unsigned char *_rnd;
};

#if defined(__LP64__)
_Static_assert(offsetof(struct darwin_res_state, nsaddr_list) == 20, "Darwin's res_state layout");
_Static_assert(offsetof(struct darwin_res_state, dnsrch) == 72, "Darwin's res_state layout");
_Static_assert(offsetof(struct darwin_res_state, sort_list) == 396, "Darwin's res_state layout");
_Static_assert(offsetof(struct darwin_res_state, _u) == 512, "Darwin's res_state layout");
_Static_assert(sizeof(struct darwin_res_state) == 552, "Darwin's res_state layout");
#endif

int darwin_res_ninit(struct darwin_res_state *state) DARWIN_SYMBOL(res_9_ninit);
void darwin_res_ndestroy(struct darwin_res_state *state) DARWIN_SYMBOL(res_9_ndestroy);
void darwin_res_nclose(struct darwin_res_state *state) DARWIN_SYMBOL(res_9_nclose);

/// Fills `state` as Darwin's res_9_ninit does, from glibc's configuration;
/// 0, or -1 when there is no state. A system with no configuration gets a
/// state with no name servers, as Darwin's does.
int darwin_res_ninit(struct darwin_res_state *state) {
    if (!state)
        return -1;
    memset(state, 0, sizeof *state);
    state->retrans = DARWIN_RES_TIMEOUT;
    state->retry = DARWIN_RES_DFLRETRY;
    state->options = DARWIN_RES_INIT | DARWIN_RES_DEFAULT;
    state->ndots = 1;
    state->_vcsock = -1;
    for (int i = 0; i < DARWIN_MAXNS; i++)
        state->_u._ext.nssocks[i] = -1;
    unsigned short id = 0;
    if (getrandom(&id, sizeof id, GRND_NONBLOCK) != sizeof id)
        id = (unsigned short)rand();
    state->id = id;

    struct __res_state linux_state;
    memset(&linux_state, 0, sizeof linux_state);
    if (res_ninit(&linux_state) != 0)
        return 0;
    state->retrans = linux_state.retrans > 0 ? linux_state.retrans : DARWIN_RES_TIMEOUT;
    state->retry = linux_state.retry > 0 ? linux_state.retry : DARWIN_RES_DFLRETRY;
    state->ndots = linux_state.ndots < 15 ? linux_state.ndots : 15;

    // The IPv4 name servers: glibc keeps IPv6 ones elsewhere, with an
    // empty slot here.
    int count = 0;
    for (int i = 0; i < linux_state.nscount && i < MAXNS && count < DARWIN_MAXNS; i++) {
        const struct sockaddr_in *server = &linux_state.nsaddr_list[i];
        if (server->sin_family != AF_INET)
            continue;
        struct darwin_sockaddr_in *slot = &state->nsaddr_list[count++];
        slot->sin_len = sizeof *slot;
        slot->sin_family = AF_INET;
        slot->sin_port = server->sin_port;
        slot->sin_addr = server->sin_addr.s_addr;
    }
    state->nscount = count;
    state->_u._ext.nscount = (uint16_t)count;

    // The search list, its names copied into defdname one after another.
    size_t used = 0;
    int domains = 0;
    for (int i = 0; linux_state.dnsrch[i] && domains < DARWIN_MAXDNSRCH; i++) {
        size_t length = strlen(linux_state.dnsrch[i]);
        if (used + length + 1 > sizeof state->defdname)
            break;
        memcpy(state->defdname + used, linux_state.dnsrch[i], length + 1);
        state->dnsrch[domains++] = state->defdname + used;
        used += length + 1;
    }
    res_nclose(&linux_state);
    return 0;
}

/// Ends the state: nothing here holds sockets or memory of its own.
void darwin_res_nclose(struct darwin_res_state *state) {
    if (state)
        state->_vcsock = -1;
}

void darwin_res_ndestroy(struct darwin_res_state *state) {
    if (!state)
        return;
    darwin_res_nclose(state);
    state->options &= ~DARWIN_RES_INIT;
}
