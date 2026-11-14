#ifndef CPERRY_SECURITY_H
#define CPERRY_SECURITY_H

#include <stddef.h>
#include <stdint.h>

// Security's exported data that Swift cannot define: kSecRandomDefault, a
// NULL SecRandomRef that programs pass by value.

// Secure Transport's TLS engine (tls.c), over the system's OpenSSL. Its
// functions answer with Secure Transport's OSStatus codes.

/// SSLReadFunc and SSLWriteFunc: the program's own functions.
typedef int32_t (*perry_tls_io)(const void *connection, void *data, size_t *length);

typedef struct perry_tls perry_tls;

/// NULL when OpenSSL can't be loaded.
perry_tls *perry_tls_create(int server);
void perry_tls_free(perry_tls *tls);
int perry_tls_set_io(perry_tls *tls, perry_tls_io read, perry_tls_io write);
int perry_tls_set_connection(perry_tls *tls, const void *connection);
const void *perry_tls_connection(perry_tls *tls);
int perry_tls_set_peer_name(perry_tls *tls, const char *name);
/// An SSLProtocol, as the least or the most to negotiate.
int perry_tls_set_version(perry_tls *tls, int maximum, int value);
int perry_tls_version_limit(perry_tls *tls, int maximum);
int perry_tls_set_break_on_server_auth(perry_tls *tls, int value);
int perry_tls_break_on_server_auth(perry_tls *tls);
/// ALPN's wire format: each protocol after its length byte.
int perry_tls_set_alpn(perry_tls *tls, const unsigned char *wire, unsigned length);
size_t perry_tls_alpn(perry_tls *tls, const unsigned char **protocol);
/// SSLSessionState.
int perry_tls_state(perry_tls *tls);
int perry_tls_handshake(perry_tls *tls);
int perry_tls_read(perry_tls *tls, void *data, size_t length, size_t *processed);
int perry_tls_write(perry_tls *tls, const void *data, size_t length, size_t *processed);
size_t perry_tls_buffered(perry_tls *tls);
int perry_tls_close(perry_tls *tls);
/// The SSLProtocol negotiated, or kSSLProtocolUnknown.
int perry_tls_negotiated_protocol(perry_tls *tls);
int perry_tls_negotiated_cipher(perry_tls *tls, uint16_t *cipher);
/// The enabled cipher suites, by IANA number: how many there are.
size_t perry_tls_ciphers(perry_tls *tls, uint16_t *ciphers, size_t capacity);
/// Limits the suites to these, of those OpenSSL has, before the handshake.
int perry_tls_set_ciphers(perry_tls *tls, const uint16_t *ciphers, size_t count);
/// The server's chain, leaf first, in DER: a certificate's length, which
/// is copied when it fits.
size_t perry_tls_peer_certificates(perry_tls *tls);
size_t perry_tls_peer_certificate(perry_tls *tls, size_t index, unsigned char *der, size_t capacity);

#endif
