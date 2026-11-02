// BSD sockets with Darwin's ABI over glibc's.
//
// Darwin's socket addresses start with a length byte and a one-byte family
// where Linux has a two-byte family; AF_INET6 is 30 rather than 10, and
// AF_UNIX paths are 104 bytes rather than 108. Socket options at
// SOL_SOCKET (0xffff on Darwin, 1 on Linux) have other numbers, as do some
// message flags, and struct addrinfo puts ai_canonname before ai_addr.
// Every address crossing the boundary is converted.

#include "PerrySystem.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

enum {
    DARWIN_AF_UNIX = 1,
    DARWIN_AF_INET = 2,
    DARWIN_AF_INET6 = 30,
    DARWIN_SOL_SOCKET = 0xffff,
    DARWIN_IPV6_V6ONLY = 27,
    DARWIN_TCP_KEEPALIVE = 0x10,
};

// The Darwin layouts.
struct darwin_sockaddr {
    uint8_t sa_len;
    uint8_t sa_family;
    char sa_data[14];
};

struct darwin_sockaddr_un {
    uint8_t sun_len;
    uint8_t sun_family;
    char sun_path[104];
};

struct darwin_addrinfo {
    int ai_flags;
    int ai_family;
    int ai_socktype;
    int ai_protocol;
    uint32_t ai_addrlen;
    char *ai_canonname;
    struct darwin_sockaddr *ai_addr;
    struct darwin_addrinfo *ai_next;
};

// MARK: - Families and addresses

static int family_to_linux(int family) {
    switch (family) {
    case DARWIN_AF_INET6: return AF_INET6;
    default: return family;  // AF_UNSPEC, AF_UNIX and AF_INET agree
    }
}

static int family_to_darwin(int family) {
    switch (family) {
    case AF_INET6: return DARWIN_AF_INET6;
    default: return family;
    }
}

static int fail(int linux_errno) {
    errno = linux_errno;
    return -1;
}

// Converts a Darwin address into `out`; its Linux length, or 0 if invalid.
static socklen_t address_to_linux(const void *address, socklen_t length, struct sockaddr_storage *out) {
    if (!address || length < 2)
        return 0;
    const struct darwin_sockaddr *darwin = address;
    memset(out, 0, sizeof(*out));
    switch (darwin->sa_family) {
    case DARWIN_AF_INET: {
        if (length < sizeof(struct sockaddr_in))
            return 0;
        struct sockaddr_in *in = (struct sockaddr_in *)out;
        memcpy(in, address, sizeof(*in));
        in->sin_family = AF_INET;
        return sizeof(*in);
    }
    case DARWIN_AF_INET6: {
        if (length < sizeof(struct sockaddr_in6))
            return 0;
        struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)out;
        memcpy(in6, address, sizeof(*in6));
        in6->sin6_family = AF_INET6;
        return sizeof(*in6);
    }
    case DARWIN_AF_UNIX: {
        const struct darwin_sockaddr_un *un = address;
        struct sockaddr_un *linux_un = (struct sockaddr_un *)out;
        linux_un->sun_family = AF_UNIX;
        size_t path = length > 2 ? length - 2 : 0;
        if (path > sizeof(un->sun_path))
            path = sizeof(un->sun_path);
        memcpy(linux_un->sun_path, un->sun_path, path);
        return (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strnlen(linux_un->sun_path, path) + 1);
    }
    default:
        return 0;
    }
}

// Writes a Linux address to a Darwin buffer of *length bytes, truncating as
// the kernel does, and sets *length to the address's full Darwin length.
static void address_to_darwin(const struct sockaddr *linux_address, socklen_t linux_length, void *address,
                              socklen_t *length) {
    if (!address || !length)
        return;
    union {
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
        struct darwin_sockaddr_un un;
        unsigned char bytes[128];
    } darwin;
    memset(&darwin, 0, sizeof(darwin));
    socklen_t size = 0;
    switch (linux_address->sa_family) {
    case AF_INET:
        memcpy(&darwin.in, linux_address, sizeof(darwin.in));
        size = sizeof(darwin.in);
        darwin.bytes[1] = DARWIN_AF_INET;
        break;
    case AF_INET6:
        memcpy(&darwin.in6, linux_address, sizeof(darwin.in6));
        size = sizeof(darwin.in6);
        darwin.bytes[1] = DARWIN_AF_INET6;
        break;
    case AF_UNIX: {
        const struct sockaddr_un *un = (const struct sockaddr_un *)linux_address;
        size_t path = linux_length > offsetof(struct sockaddr_un, sun_path)
            ? linux_length - offsetof(struct sockaddr_un, sun_path) : 0;
        if (path > sizeof(darwin.un.sun_path))
            path = sizeof(darwin.un.sun_path);
        memcpy(darwin.un.sun_path, un->sun_path, path);
        size = (socklen_t)(2 + path);
        darwin.un.sun_family = DARWIN_AF_UNIX;
        break;
    }
    default:
        size = 2;
        darwin.bytes[1] = (unsigned char)linux_address->sa_family;
        break;
    }
    darwin.bytes[0] = (unsigned char)size;
    memcpy(address, &darwin, *length < size ? *length : size);
    *length = size;
}

// MARK: - Options and flags

// A Darwin socket option as Linux's; false if Linux has no such option.
// *ignored is set for options Linux lacks that are safe to accept.
static int option_to_linux(int *level, int *name, int *ignored) {
    *ignored = 0;
    if (*level == DARWIN_SOL_SOCKET) {
        *level = SOL_SOCKET;
        switch (*name) {
        case 0x0001: *name = SO_DEBUG; return 1;
        case 0x0002: *name = SO_ACCEPTCONN; return 1;
        case 0x0004: *name = SO_REUSEADDR; return 1;
        case 0x0008: *name = SO_KEEPALIVE; return 1;
        case 0x0010: *name = SO_DONTROUTE; return 1;
        case 0x0020: *name = SO_BROADCAST; return 1;
        case 0x0080: *name = SO_LINGER; return 1;
        case 0x0100: *name = SO_OOBINLINE; return 1;
        case 0x0200: *name = SO_REUSEPORT; return 1;
        case 0x1001: *name = SO_SNDBUF; return 1;
        case 0x1002: *name = SO_RCVBUF; return 1;
        case 0x1003: *name = SO_SNDLOWAT; return 1;
        case 0x1004: *name = SO_RCVLOWAT; return 1;
        case 0x1005: *name = SO_SNDTIMEO; return 1;
        case 0x1006: *name = SO_RCVTIMEO; return 1;
        case 0x1007: *name = SO_ERROR; return 1;
        case 0x1008: *name = SO_TYPE; return 1;
        case 0x1022:    // SO_NOSIGPIPE: Perry's sends never raise SIGPIPE
            *ignored = 1;
            return 1;
        default: return 0;
        }
    }
    if (*level == IPPROTO_IPV6 && *name == DARWIN_IPV6_V6ONLY) {
        *name = IPV6_V6ONLY;
        return 1;
    }
    if (*level == IPPROTO_TCP && *name == DARWIN_TCP_KEEPALIVE) {
        *name = TCP_KEEPIDLE;
        return 1;
    }
    return 1;
}

// Darwin's message flags as Linux's. Sends never raise SIGPIPE, which
// Darwin programs avoid with SO_NOSIGPIPE.
static int flags_to_linux(int flags) {
    int out = flags & (MSG_OOB | MSG_PEEK | MSG_DONTROUTE);
    if (flags & 0x8) out |= MSG_EOR;
    if (flags & 0x10) out |= MSG_TRUNC;
    if (flags & 0x20) out |= MSG_CTRUNC;
    if (flags & 0x40) out |= MSG_WAITALL;
    if (flags & 0x80) out |= MSG_DONTWAIT;
    return out;
}

// MARK: - Sockets

int darwin_socket(int domain, int type, int protocol) DARWIN_SYMBOL(socket);
int darwin_socket(int domain, int type, int protocol) {
    return socket(family_to_linux(domain), type, protocol);
}

int darwin_socketpair(int domain, int type, int protocol, int sockets[2]) DARWIN_SYMBOL(socketpair);
int darwin_socketpair(int domain, int type, int protocol, int sockets[2]) {
    return socketpair(family_to_linux(domain), type, protocol, sockets);
}

int darwin_bind(int socket, const void *address, socklen_t length) DARWIN_SYMBOL(bind);
int darwin_bind(int socket, const void *address, socklen_t length) {
    struct sockaddr_storage linux_address;
    socklen_t linux_length = address_to_linux(address, length, &linux_address);
    if (!linux_length)
        return fail(EINVAL);
    return bind(socket, (struct sockaddr *)&linux_address, linux_length);
}

int darwin_connect(int socket, const void *address, socklen_t length) DARWIN_SYMBOL(connect);
int darwin_connect(int socket, const void *address, socklen_t length) {
    struct sockaddr_storage linux_address;
    socklen_t linux_length = address_to_linux(address, length, &linux_address);
    if (!linux_length)
        return fail(EINVAL);
    return connect(socket, (struct sockaddr *)&linux_address, linux_length);
}

int darwin_accept(int socket, void *address, socklen_t *length) DARWIN_SYMBOL(accept);
int darwin_accept(int socket, void *address, socklen_t *length) {
    struct sockaddr_storage linux_address;
    socklen_t linux_length = sizeof(linux_address);
    int client = accept(socket, (struct sockaddr *)&linux_address, &linux_length);
    if (client >= 0)
        address_to_darwin((struct sockaddr *)&linux_address, linux_length, address, length);
    return client;
}

int darwin_getsockname(int socket, void *address, socklen_t *length) DARWIN_SYMBOL(getsockname);
int darwin_getsockname(int socket, void *address, socklen_t *length) {
    struct sockaddr_storage linux_address;
    socklen_t linux_length = sizeof(linux_address);
    int result = getsockname(socket, (struct sockaddr *)&linux_address, &linux_length);
    if (result == 0)
        address_to_darwin((struct sockaddr *)&linux_address, linux_length, address, length);
    return result;
}

int darwin_getpeername(int socket, void *address, socklen_t *length) DARWIN_SYMBOL(getpeername);
int darwin_getpeername(int socket, void *address, socklen_t *length) {
    struct sockaddr_storage linux_address;
    socklen_t linux_length = sizeof(linux_address);
    int result = getpeername(socket, (struct sockaddr *)&linux_address, &linux_length);
    if (result == 0)
        address_to_darwin((struct sockaddr *)&linux_address, linux_length, address, length);
    return result;
}

int darwin_setsockopt(int socket, int level, int name, const void *value, socklen_t length) DARWIN_SYMBOL(setsockopt);
int darwin_setsockopt(int socket, int level, int name, const void *value, socklen_t length) {
    int ignored;
    if (!option_to_linux(&level, &name, &ignored))
        return fail(ENOPROTOOPT);
    if (ignored)
        return 0;
    return setsockopt(socket, level, name, value, length);
}

int darwin_getsockopt(int socket, int level, int name, void *value, socklen_t *length) DARWIN_SYMBOL(getsockopt);
int darwin_getsockopt(int socket, int level, int name, void *value, socklen_t *length) {
    int ignored;
    if (!option_to_linux(&level, &name, &ignored))
        return fail(ENOPROTOOPT);
    if (ignored) {
        if (value && length && *length >= sizeof(int))
            *(int *)value = 1;
        return 0;
    }
    int result = getsockopt(socket, level, name, value, length);
    // SO_ERROR reports an errno, in Darwin's numbering.
    if (result == 0 && level == SOL_SOCKET && name == SO_ERROR && value)
        *(int *)value = perry_darwin_errno_from_linux(*(int *)value);
    return result;
}

ssize_t darwin_send(int socket, const void *buffer, size_t length, int flags) DARWIN_SYMBOL(send);
ssize_t darwin_send(int socket, const void *buffer, size_t length, int flags) {
    return send(socket, buffer, length, flags_to_linux(flags) | MSG_NOSIGNAL);
}

ssize_t darwin_recv(int socket, void *buffer, size_t length, int flags) DARWIN_SYMBOL(recv);
ssize_t darwin_recv(int socket, void *buffer, size_t length, int flags) {
    return recv(socket, buffer, length, flags_to_linux(flags));
}

ssize_t darwin_sendto(int socket, const void *buffer, size_t length, int flags, const void *address,
                      socklen_t address_length) DARWIN_SYMBOL(sendto);
ssize_t darwin_sendto(int socket, const void *buffer, size_t length, int flags, const void *address,
                      socklen_t address_length) {
    if (!address)
        return sendto(socket, buffer, length, flags_to_linux(flags) | MSG_NOSIGNAL, NULL, 0);
    struct sockaddr_storage linux_address;
    socklen_t linux_length = address_to_linux(address, address_length, &linux_address);
    if (!linux_length)
        return fail(EINVAL);
    return sendto(socket, buffer, length, flags_to_linux(flags) | MSG_NOSIGNAL, (struct sockaddr *)&linux_address,
                  linux_length);
}

ssize_t darwin_recvfrom(int socket, void *buffer, size_t length, int flags, void *address,
                        socklen_t *address_length) DARWIN_SYMBOL(recvfrom);
ssize_t darwin_recvfrom(int socket, void *buffer, size_t length, int flags, void *address,
                        socklen_t *address_length) {
    struct sockaddr_storage linux_address;
    socklen_t linux_length = sizeof(linux_address);
    ssize_t received = recvfrom(socket, buffer, length, flags_to_linux(flags), (struct sockaddr *)&linux_address,
                                &linux_length);
    if (received >= 0 && address && linux_length > 0)
        address_to_darwin((struct sockaddr *)&linux_address, linux_length, address, address_length);
    return received;
}

// MARK: - Addresses as text

int darwin_inet_pton(int family, const char *text, void *address) DARWIN_SYMBOL(inet_pton);
int darwin_inet_pton(int family, const char *text, void *address) {
    return inet_pton(family_to_linux(family), text, address);
}

const char *darwin_inet_ntop(int family, const void *address, char *text, socklen_t size) DARWIN_SYMBOL(inet_ntop);
const char *darwin_inet_ntop(int family, const void *address, char *text, socklen_t size) {
    return inet_ntop(family_to_linux(family), address, text, size);
}

// MARK: - Name resolution

// EAI_* codes in Darwin's numbering.
static int gai_error_to_darwin(int error) {
    switch (error) {
    case 0: return 0;
    case EAI_AGAIN: return 2;
    case EAI_BADFLAGS: return 3;
    case EAI_FAIL: return 4;
    case EAI_FAMILY: return 5;
    case EAI_MEMORY: return 6;
    case EAI_NONAME: return 8;
    case EAI_SERVICE: return 9;
    case EAI_SOCKTYPE: return 10;
    case EAI_SYSTEM: return 11;
    case EAI_OVERFLOW: return 14;
    default: return 4;
    }
}

int darwin_getaddrinfo(const char *node, const char *service, const struct darwin_addrinfo *hints,
                       struct darwin_addrinfo **result) DARWIN_SYMBOL(getaddrinfo);
int darwin_getaddrinfo(const char *node, const char *service, const struct darwin_addrinfo *hints,
                       struct darwin_addrinfo **result) {
    struct addrinfo linux_hints, *found = NULL;
    memset(&linux_hints, 0, sizeof(linux_hints));
    if (hints) {
        // AI_PASSIVE, AI_CANONNAME and AI_NUMERICHOST agree; Darwin's
        // AI_NUMERICSERV (0x1000), AI_ADDRCONFIG (0x400) and AI_V4MAPPED
        // (0x800) do not.
        int flags = hints->ai_flags & 0x7;
        if (hints->ai_flags & 0x1000) flags |= AI_NUMERICSERV;
        if (hints->ai_flags & 0x400) flags |= AI_ADDRCONFIG;
        if (hints->ai_flags & 0x800) flags |= AI_V4MAPPED;
        linux_hints.ai_flags = flags;
        linux_hints.ai_family = family_to_linux(hints->ai_family);
        linux_hints.ai_socktype = hints->ai_socktype;
        linux_hints.ai_protocol = hints->ai_protocol;
    }
    int error = getaddrinfo(node, service, hints ? &linux_hints : NULL, &found);
    if (error) {
        *result = NULL;
        return gai_error_to_darwin(error);
    }
    struct darwin_addrinfo *head = NULL, **tail = &head;
    for (struct addrinfo *entry = found; entry; entry = entry->ai_next) {
        // One allocation per entry: the entry, its address, its name.
        size_t name = entry->ai_canonname ? strlen(entry->ai_canonname) + 1 : 0;
        struct darwin_addrinfo *darwin = calloc(1, sizeof(*darwin) + sizeof(struct sockaddr_storage) + name);
        if (!darwin)
            break;
        darwin->ai_flags = entry->ai_flags;
        darwin->ai_family = family_to_darwin(entry->ai_family);
        darwin->ai_socktype = entry->ai_socktype;
        darwin->ai_protocol = entry->ai_protocol;
        darwin->ai_addr = (struct darwin_sockaddr *)(darwin + 1);
        socklen_t length = sizeof(struct sockaddr_storage);
        address_to_darwin(entry->ai_addr, entry->ai_addrlen, darwin->ai_addr, &length);
        darwin->ai_addrlen = length;
        if (name) {
            darwin->ai_canonname = (char *)darwin->ai_addr + sizeof(struct sockaddr_storage);
            memcpy(darwin->ai_canonname, entry->ai_canonname, name);
        }
        *tail = darwin;
        tail = &darwin->ai_next;
    }
    freeaddrinfo(found);
    *result = head;
    return 0;
}

void darwin_freeaddrinfo(struct darwin_addrinfo *list) DARWIN_SYMBOL(freeaddrinfo);
void darwin_freeaddrinfo(struct darwin_addrinfo *list) {
    while (list) {
        struct darwin_addrinfo *next = list->ai_next;
        free(list);
        list = next;
    }
}

const char *darwin_gai_strerror(int error) DARWIN_SYMBOL(gai_strerror);
const char *darwin_gai_strerror(int error) {
    static const char *const messages[] = {
        "Success", "Address family for hostname not supported", "Temporary failure in name resolution",
        "Invalid value for ai_flags", "Non-recoverable failure in name resolution", "ai_family not supported",
        "Memory allocation failure", "No address associated with hostname", "nodename nor servname provided, or not known",
        "servname not supported for ai_socktype", "ai_socktype not supported", "System error returned in errno",
        "Invalid value for hints", "Resolved protocol is unknown", "Argument buffer overflow",
    };
    return error >= 0 && error < (int)(sizeof(messages) / sizeof(messages[0])) ? messages[error] : "Unknown error";
}
