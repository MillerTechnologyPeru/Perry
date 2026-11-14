// Secure Transport's TLS engine: the system's OpenSSL (libssl.so.3), loaded
// when the first context is made, between memory BIOs. A context's records
// go out and come in through the program's own SSLWriteFunc and SSLReadFunc,
// as Secure Transport does it, so the program keeps its socket.

#include "CPerrySecurity.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// OSStatus codes.
enum {
    errSSLProtocol = -9800,
    errSSLWouldBlock = -9803,
    errSSLClosedGraceful = -9805,
    errSSLClosedAbort = -9806,
    errSSLXCertChainInvalid = -9807,
    errSSLInternal = -9810,
    errSSLUnknownRootCert = -9812,
    errSSLNoRootCert = -9813,
    errSSLCertExpired = -9814,
    errSSLCertNotYetValid = -9815,
    errSSLClosedNoNotify = -9816,
    errSSLPeerAuthCompleted = -9841,
    errSSLHostNameMismatch = -9843,
    paramErr = -50,
};

// SSLSessionState.
enum { kSSLIdle, kSSLHandshake, kSSLConnected, kSSLClosed, kSSLAborted };

// OpenSSL's constants this needs.
enum {
    SSL_ERROR_WANT_READ = 2,
    SSL_ERROR_WANT_WRITE = 3,
    SSL_ERROR_ZERO_RETURN = 6,
    SSL_CTRL_SET_TLSEXT_HOSTNAME = 55,
    SSL_CTRL_SET_MIN_PROTO_VERSION = 123,
    SSL_CTRL_SET_MAX_PROTO_VERSION = 124,
    SSL_VERIFY_NONE = 0,
    X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT = 2,
    X509_V_ERR_CERT_NOT_YET_VALID = 9,
    X509_V_ERR_CERT_HAS_EXPIRED = 10,
    X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT = 18,
    X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN = 19,
    X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY = 20,
    X509_V_ERR_HOSTNAME_MISMATCH = 62,
};

static struct {
    int (*init_ssl)(uint64_t, const void *);
    const void *(*client_method)(void);
    const void *(*server_method)(void);
    void *(*ctx_new)(const void *);
    void (*ctx_free)(void *);
    int (*ctx_default_verify_paths)(void *);
    void *(*ssl_new)(void *);
    void (*ssl_free)(void *);
    void (*set_bio)(void *, void *, void *);
    void (*set_connect_state)(void *);
    void (*set_accept_state)(void *);
    void (*set_verify)(void *, int, void *);
    int (*set1_host)(void *, const char *);
    long (*ctrl)(void *, int, long, void *);
    int (*do_handshake)(void *);
    int (*get_error)(const void *, int);
    int (*read)(void *, void *, int);
    int (*write)(void *, const void *, int);
    int (*pending)(const void *);
    int (*shutdown)(void *);
    long (*get_verify_result)(const void *);
    void *(*peer_chain)(const void *);
    int (*version)(const void *);
    const void *(*current_cipher)(const void *);
    uint32_t (*cipher_id)(const void *);
    void *(*ciphers)(const void *);
    const void *(*find_cipher)(void *, const unsigned char *);
    const char *(*cipher_name)(const void *);
    int (*set_cipher_list)(void *, const char *);
    int (*set_alpn)(void *, const unsigned char *, unsigned int);
    void (*alpn_selected)(const void *, const unsigned char **, unsigned int *);
    const void *(*mem_method)(void);
    void *(*bio_new)(const void *);
    int (*bio_read)(void *, void *, int);
    int (*bio_write)(void *, const void *, int);
    size_t (*bio_pending)(void *);
    int (*sk_num)(const void *);
    void *(*sk_value)(const void *, int);
    int (*i2d_x509)(const void *, unsigned char **);
    void (*clear_error)(void);
    void *client;
    void *server;
} ossl;

static int loaded;
static pthread_once_t load_once = PTHREAD_ONCE_INIT;

static void load(void) {
    void *ssl = dlopen("libssl.so.3", RTLD_NOW | RTLD_LOCAL);
    void *crypto = dlopen("libcrypto.so.3", RTLD_NOW | RTLD_LOCAL);
    if (!ssl || !crypto) return;
#define S(field, name) if (!(*(void **)&ossl.field = dlsym(ssl, name))) return;
#define C(field, name) if (!(*(void **)&ossl.field = dlsym(crypto, name))) return;
    S(init_ssl, "OPENSSL_init_ssl")
    S(client_method, "TLS_client_method")
    S(server_method, "TLS_server_method")
    S(ctx_new, "SSL_CTX_new")
    S(ctx_free, "SSL_CTX_free")
    S(ctx_default_verify_paths, "SSL_CTX_set_default_verify_paths")
    S(ssl_new, "SSL_new")
    S(ssl_free, "SSL_free")
    S(set_bio, "SSL_set_bio")
    S(set_connect_state, "SSL_set_connect_state")
    S(set_accept_state, "SSL_set_accept_state")
    S(set_verify, "SSL_set_verify")
    S(set1_host, "SSL_set1_host")
    S(ctrl, "SSL_ctrl")
    S(do_handshake, "SSL_do_handshake")
    S(get_error, "SSL_get_error")
    S(read, "SSL_read")
    S(write, "SSL_write")
    S(pending, "SSL_pending")
    S(shutdown, "SSL_shutdown")
    S(get_verify_result, "SSL_get_verify_result")
    S(peer_chain, "SSL_get_peer_cert_chain")
    S(version, "SSL_version")
    S(current_cipher, "SSL_get_current_cipher")
    S(cipher_id, "SSL_CIPHER_get_protocol_id")
    S(ciphers, "SSL_get_ciphers")
    S(find_cipher, "SSL_CIPHER_find")
    S(cipher_name, "SSL_CIPHER_get_name")
    S(set_cipher_list, "SSL_set_cipher_list")
    S(set_alpn, "SSL_set_alpn_protos")
    S(alpn_selected, "SSL_get0_alpn_selected")
    C(mem_method, "BIO_s_mem")
    C(bio_new, "BIO_new")
    C(bio_read, "BIO_read")
    C(bio_write, "BIO_write")
    C(bio_pending, "BIO_ctrl_pending")
    C(sk_num, "OPENSSL_sk_num")
    C(sk_value, "OPENSSL_sk_value")
    C(i2d_x509, "i2d_X509")
    C(clear_error, "ERR_clear_error")
#undef S
#undef C
    ossl.init_ssl(0, NULL);
    ossl.client = ossl.ctx_new(ossl.client_method());
    ossl.server = ossl.ctx_new(ossl.server_method());
    if (!ossl.client || !ossl.server) return;
    ossl.ctx_default_verify_paths(ossl.client);
    loaded = 1;
}

struct perry_tls {
    void *ssl;
    void *in;   // records read from the connection, for OpenSSL
    void *out;  // records OpenSSL wrote, for the connection
    perry_tls_io read;
    perry_tls_io write;
    const void *connection;
    // Records taken from `out` that the connection hasn't accepted yet.
    unsigned char *pending;
    size_t pending_length;
    size_t pending_offset;
    int server;
    int state;
    int verify_host;
    int break_on_server_auth;
    int auth_reported;
    int min_version;
    int max_version;
};

perry_tls *perry_tls_create(int server) {
    pthread_once(&load_once, load);
    if (!loaded) return NULL;
    perry_tls *tls = calloc(1, sizeof *tls);
    if (!tls) return NULL;
    tls->server = server;
    tls->ssl = ossl.ssl_new(server ? ossl.server : ossl.client);
    tls->in = ossl.bio_new(ossl.mem_method());
    tls->out = ossl.bio_new(ossl.mem_method());
    if (!tls->ssl || !tls->in || !tls->out) {
        if (tls->ssl) ossl.ssl_free(tls->ssl);
        free(tls);
        return NULL;
    }
    ossl.set_bio(tls->ssl, tls->in, tls->out);
    // Secure Transport checks the server's chain itself once the handshake
    // is done, unless the program asked to check it (break on server auth).
    ossl.set_verify(tls->ssl, SSL_VERIFY_NONE, NULL);
    if (server) ossl.set_accept_state(tls->ssl);
    else ossl.set_connect_state(tls->ssl);
    tls->state = kSSLIdle;
    return tls;
}

void perry_tls_free(perry_tls *tls) {
    if (!tls) return;
    ossl.ssl_free(tls->ssl);  // frees both BIOs
    free(tls->pending);
    free(tls);
}

int perry_tls_set_io(perry_tls *tls, perry_tls_io read, perry_tls_io write) {
    if (tls->state != kSSLIdle) return errSSLProtocol;
    tls->read = read;
    tls->write = write;
    return 0;
}

int perry_tls_set_connection(perry_tls *tls, const void *connection) {
    tls->connection = connection;
    return 0;
}

const void *perry_tls_connection(perry_tls *tls) { return tls->connection; }

int perry_tls_set_peer_name(perry_tls *tls, const char *name) {
    if (tls->state != kSSLIdle) return errSSLProtocol;
    if (!name || !*name) {
        tls->verify_host = 0;
        return 0;
    }
    ossl.ctrl(tls->ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, (void *)name);
    ossl.set1_host(tls->ssl, name);
    tls->verify_host = 1;
    return 0;
}

// SSLProtocol and OpenSSL's version numbers.
static int openssl_version(int protocol) {
    switch (protocol) {
    case 2: return 0x300;   // kSSLProtocol3
    case 4: return 0x301;   // kTLSProtocol1
    case 7: return 0x302;   // kTLSProtocol11
    case 8: return 0x303;   // kTLSProtocol12
    case 10: return 0x304;  // kTLSProtocol13
    case 0: return 0;       // kSSLProtocolUnknown: no limit
    default: return -1;
    }
}

static int protocol(int version) {
    switch (version) {
    case 0x300: return 2;
    case 0x301: return 4;
    case 0x302: return 7;
    case 0x303: return 8;
    case 0x304: return 10;
    default: return 0;
    }
}

int perry_tls_set_version(perry_tls *tls, int maximum, int value) {
    int version = openssl_version(value);
    if (version < 0) return paramErr;
    if (tls->state != kSSLIdle) return errSSLProtocol;
    ossl.ctrl(tls->ssl, maximum ? SSL_CTRL_SET_MAX_PROTO_VERSION : SSL_CTRL_SET_MIN_PROTO_VERSION, version, NULL);
    if (maximum) tls->max_version = value;
    else tls->min_version = value;
    return 0;
}

int perry_tls_version_limit(perry_tls *tls, int maximum) {
    if (maximum) return tls->max_version ? tls->max_version : 10;
    return tls->min_version ? tls->min_version : 4;
}

int perry_tls_set_break_on_server_auth(perry_tls *tls, int value) {
    tls->break_on_server_auth = value;
    return 0;
}

int perry_tls_break_on_server_auth(perry_tls *tls) { return tls->break_on_server_auth; }

int perry_tls_set_alpn(perry_tls *tls, const unsigned char *wire, unsigned length) {
    if (tls->state != kSSLIdle) return errSSLProtocol;
    return ossl.set_alpn(tls->ssl, wire, length) == 0 ? 0 : errSSLInternal;
}

size_t perry_tls_alpn(perry_tls *tls, const unsigned char **protocol) {
    unsigned length = 0;
    *protocol = NULL;
    ossl.alpn_selected(tls->ssl, protocol, &length);
    return length;
}

int perry_tls_state(perry_tls *tls) { return tls->state; }

// MARK: - The connection

// Hands OpenSSL's records to the connection, until it has them all or would
// block.
static int flush(perry_tls *tls) {
    for (;;) {
        if (tls->pending_offset == tls->pending_length) {
            size_t waiting = ossl.bio_pending(tls->out);
            if (waiting == 0) return 0;
            unsigned char *buffer = realloc(tls->pending, waiting);
            if (!buffer) return errSSLInternal;
            tls->pending = buffer;
            int got = ossl.bio_read(tls->out, buffer, (int)waiting);
            tls->pending_length = got > 0 ? (size_t)got : 0;
            tls->pending_offset = 0;
            if (got <= 0) return 0;
        }
        if (!tls->write) return errSSLInternal;
        size_t length = tls->pending_length - tls->pending_offset;
        int status = tls->write(tls->connection, tls->pending + tls->pending_offset, &length);
        if (length > tls->pending_length - tls->pending_offset) length = tls->pending_length - tls->pending_offset;
        tls->pending_offset += length;
        if (status != 0) return status;
        if (length == 0) return errSSLWouldBlock;
    }
}

// Takes what the connection has for OpenSSL: 0 when something came,
// else why nothing did.
static int fill(perry_tls *tls) {
    unsigned char buffer[16384];
    size_t length = sizeof buffer;
    if (!tls->read) return errSSLInternal;
    int status = tls->read(tls->connection, buffer, &length);
    if (length > sizeof buffer) length = sizeof buffer;
    if (length > 0) {
        ossl.bio_write(tls->in, buffer, (int)length);
        return 0;
    }
    if (status == 0) return errSSLWouldBlock;
    // The peer went away without a close_notify.
    if (status == errSSLClosedGraceful) return errSSLClosedNoNotify;
    return status;
}

/// After OpenSSL asks for more: sends what it wrote and reads what came.
/// 0 to try again, else the status to return.
static int resume(perry_tls *tls, int result) {
    int error = ossl.get_error(tls->ssl, result);
    ossl.clear_error();
    int status = flush(tls);
    if (status != 0) return status;
    if (error == SSL_ERROR_WANT_WRITE) return 0;
    if (error == SSL_ERROR_WANT_READ) return fill(tls);
    if (error == SSL_ERROR_ZERO_RETURN) {
        tls->state = kSSLClosed;
        return errSSLClosedGraceful;
    }
    tls->state = kSSLAborted;
    return errSSLProtocol;
}

static int chain_status(perry_tls *tls) {
    long result = ossl.get_verify_result(tls->ssl);
    switch (result) {
    case 0: return 0;
    case X509_V_ERR_HOSTNAME_MISMATCH: return tls->verify_host ? errSSLHostNameMismatch : 0;
    case X509_V_ERR_CERT_HAS_EXPIRED: return errSSLCertExpired;
    case X509_V_ERR_CERT_NOT_YET_VALID: return errSSLCertNotYetValid;
    case X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT:
    case X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN: return errSSLUnknownRootCert;
    case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT:
    case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY: return errSSLNoRootCert;
    default: return errSSLXCertChainInvalid;
    }
}

int perry_tls_handshake(perry_tls *tls) {
    if (tls->state == kSSLConnected) {
        // The program checked the server's chain after errSSLPeerAuthCompleted.
        return flush(tls);
    }
    if (tls->state == kSSLClosed || tls->state == kSSLAborted) return errSSLClosedAbort;
    tls->state = kSSLHandshake;
    for (;;) {
        int result = ossl.do_handshake(tls->ssl);
        if (result == 1) break;
        int status = resume(tls, result);
        if (status != 0) return status;
    }
    int status = flush(tls);
    tls->state = kSSLConnected;
    if (!tls->server) {
        if (tls->break_on_server_auth) {
            if (!tls->auth_reported) {
                tls->auth_reported = 1;
                return errSSLPeerAuthCompleted;
            }
        } else {
            int chain = chain_status(tls);
            if (chain != 0) {
                tls->state = kSSLAborted;
                return chain;
            }
        }
    }
    return status;
}

int perry_tls_read(perry_tls *tls, void *data, size_t length, size_t *processed) {
    *processed = 0;
    if (tls->state == kSSLIdle || tls->state == kSSLHandshake) {
        int status = perry_tls_handshake(tls);
        if (status != 0) return status;
    }
    if (tls->state == kSSLClosed) return errSSLClosedGraceful;
    if (tls->state == kSSLAborted) return errSSLClosedAbort;
    while (*processed < length) {
        size_t wanted = length - *processed;
        int result = ossl.read(tls->ssl, (char *)data + *processed, wanted > 0x40000000 ? 0x40000000 : (int)wanted);
        if (result > 0) {
            *processed += (size_t)result;
            continue;
        }
        // Return what has come rather than wait for the rest.
        if (*processed > 0 && ossl.get_error(tls->ssl, result) == SSL_ERROR_WANT_READ) {
            ossl.clear_error();
            if (ossl.bio_pending(tls->out)) flush(tls);
            return 0;
        }
        int status = resume(tls, result);
        if (status != 0) return *processed > 0 && status == errSSLWouldBlock ? 0 : status;
    }
    return 0;
}

int perry_tls_write(perry_tls *tls, const void *data, size_t length, size_t *processed) {
    *processed = 0;
    if (tls->state == kSSLIdle || tls->state == kSSLHandshake) {
        int status = perry_tls_handshake(tls);
        if (status != 0) return status;
    }
    if (tls->state != kSSLConnected) return errSSLClosedAbort;
    // What a write that would have blocked left is sent first: a write of
    // nothing sends only that.
    int status = flush(tls);
    if (status != 0) return status;
    while (*processed < length) {
        size_t left = length - *processed;
        int result = ossl.write(tls->ssl, (const char *)data + *processed, left > 0x40000000 ? 0x40000000 : (int)left);
        if (result <= 0) {
            ossl.clear_error();
            tls->state = kSSLAborted;
            return errSSLProtocol;
        }
        *processed += (size_t)result;
    }
    // The records are kept until the connection takes them, as Secure
    // Transport keeps them: the data counts as written.
    return flush(tls);
}

size_t perry_tls_buffered(perry_tls *tls) {
    int pending = ossl.pending(tls->ssl);
    return pending > 0 ? (size_t)pending : 0;
}

int perry_tls_close(perry_tls *tls) {
    if (tls->state == kSSLConnected) {
        ossl.shutdown(tls->ssl);
        ossl.clear_error();
        flush(tls);
    }
    tls->state = kSSLClosed;
    return 0;
}

int perry_tls_negotiated_protocol(perry_tls *tls) {
    return tls->state == kSSLConnected ? protocol(ossl.version(tls->ssl)) : 0;
}

int perry_tls_negotiated_cipher(perry_tls *tls, uint16_t *cipher) {
    const void *current = ossl.current_cipher(tls->ssl);
    if (!current) return errSSLProtocol;
    *cipher = (uint16_t)ossl.cipher_id(current);
    return 0;
}

size_t perry_tls_ciphers(perry_tls *tls, uint16_t *ciphers, size_t capacity) {
    void *list = ossl.ciphers(tls->ssl);
    int count = list ? ossl.sk_num(list) : 0;
    if (count < 0) count = 0;
    for (int index = 0; ciphers && index < count && (size_t)index < capacity; index++)
        ciphers[index] = (uint16_t)ossl.cipher_id(ossl.sk_value(list, index));
    return (size_t)count;
}

int perry_tls_set_ciphers(perry_tls *tls, const uint16_t *ciphers, size_t count) {
    if (tls->state != kSSLIdle) return errSSLProtocol;
    // TLS 1.3's suites (0x13xx) are OpenSSL's own list; the rest go by name.
    size_t capacity = 1, used = 0;
    char *names = malloc(capacity);
    if (!names) return errSSLInternal;
    names[0] = 0;
    for (size_t index = 0; index < count; index++) {
        if ((ciphers[index] >> 8) == 0x13) continue;
        unsigned char bytes[2] = { (unsigned char)(ciphers[index] >> 8), (unsigned char)ciphers[index] };
        const void *cipher = ossl.find_cipher(tls->ssl, bytes);
        const char *name = cipher ? ossl.cipher_name(cipher) : NULL;
        if (!name) continue;
        size_t length = strlen(name);
        char *grown = realloc(names, capacity + length + 1);
        if (!grown) { free(names); return errSSLInternal; }
        names = grown;
        capacity += length + 1;
        if (used) names[used++] = ':';
        memcpy(names + used, name, length + 1);
        used += length;
    }
    int status = used == 0 || ossl.set_cipher_list(tls->ssl, names) == 1 ? 0 : paramErr;
    ossl.clear_error();
    free(names);
    return status;
}

size_t perry_tls_peer_certificates(perry_tls *tls) {
    void *chain = ossl.peer_chain(tls->ssl);
    int count = chain ? ossl.sk_num(chain) : 0;
    return count > 0 ? (size_t)count : 0;
}

size_t perry_tls_peer_certificate(perry_tls *tls, size_t index, unsigned char *der, size_t capacity) {
    void *chain = ossl.peer_chain(tls->ssl);
    if (!chain || (int)index >= ossl.sk_num(chain)) return 0;
    void *certificate = ossl.sk_value(chain, (int)index);
    int length = ossl.i2d_x509(certificate, NULL);
    if (length <= 0) return 0;
    if (der && (size_t)length <= capacity) {
        unsigned char *cursor = der;
        ossl.i2d_x509(certificate, &cursor);
    }
    return (size_t)length;
}
