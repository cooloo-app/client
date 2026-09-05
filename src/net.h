/*
 * net.h - client side of the native protocol (handoff §4).
 *
 * One blocking connection per process invocation (the CLI is
 * command-per-process; chat/follow keep it and poll stdin+socket).
 */
#ifndef COOLOO_NET_H
#define COOLOO_NET_H

#include <stddef.h>
#include <stdint.h>

#include "noise_xx.h"

typedef struct {
    int      fd;
    noise_session sess;
    char     server_fp[65];            /* server static key fingerprint */
    char     nick[17];                 /* greeting nick; "" = unregistered */
    /* decrypted stream buffer (line extraction) */
    uint8_t  plain[NOISE_FRAME_MAX_PT + 1];
    size_t   plain_len;
    /* v2: raw frame accumulator for nonblocking net_try_recv */
    uint8_t  raw[NOISE_FRAME_MAX_PT + NOISE_FRAME_OVERHEAD];
    size_t   raw_len;
} netconn;

/* Connect + Noise_XX handshake as initiator (prologue "cooloo-v1").
 * TOFU (D22): if known_servers has a pin for host:port it must match,
 * otherwise we abort *before* msg3 (which would leak our identity).
 * tofu_mode: 0 = strict (unknown server -> NET_TOFU_UNKNOWN, caller prompts),
 *            1 = auto-trust-and-pin (the -y/--tofu flag).
 * Returns 0 ok, NET_ERR_* otherwise; errbuf gets a human message. */
#define NET_OK            0
#define NET_ERR_IO        1
#define NET_ERR_HANDSHAKE 2
#define NET_ERR_TOFU_DIFF 3
#define NET_TOFU_UNKNOWN  4

int  net_connect(netconn *c, const char *host, int port,
                 const uint8_t sk[32], int tofu_mode,
                 char *errbuf, size_t errcap);

/* After a NET_TOFU_UNKNOWN the caller confirmed with the user:
 * retry the handshake pinning the fingerprint we just saw. */
int  net_connect_trust(netconn *c, const char *host, int port,
                       const uint8_t sk[32],
                       char *errbuf, size_t errcap);

/* Send helpers: whole plaintext chunk in one frame. 0 ok. */
int  net_send(netconn *c, const void *pt, size_t len);
int  net_send_line(netconn *c, const char *line);

/* Read one decrypted line (strips \n). Blocking. 0 ok, -1 closed/error. */
int  net_read_line(netconn *c, char *out, size_t cap);

/* Read one frame's plaintext (for SEND payloads and chat loops). */
int  net_recv(netconn *c);

void net_close(netconn *c);

/* ---------------------------------------------------------------- */
/* v2: nonblocking API for the GUI event pump (04 doc D30/D32)       */
/* ---------------------------------------------------------------- */

/* Nonblocking frame receive (c->fd must be nonblocking):
 * 1 = one frame decrypted into c->plain, 0 = would block, -1 closed/error. */
int  net_try_recv(netconn *c);
/* Extract one buffered line (strips \n): 1 = got a line, 0 = need more. */
int  net_try_line(netconn *c, char *out, size_t cap);

/* async connect + Noise_XX handshake, TOFU pause between msg2 and msg3 */
enum { NAS_TCP, NAS_HS1, NAS_HS2, NAS_HS3, NAS_GREET,
       NAS_READY, NAS_TOFU, NAS_FAILED };
typedef struct {
    int      state;
    netconn  c;                     /* usable once state == NAS_READY */
    noise_hs hs;
    char     host[256];
    int      port;
    uint8_t  sk[32];
    uint8_t  wbuf[NOISE_MSG3_LEN];
    size_t   wlen, woff;
    uint8_t  rbuf[NOISE_MSG2_LEN];
    size_t   rlen;
    char     err[160];
    char     hostport[300];
} net_async;

int  net_async_start(net_async *a, const char *host, int port,
                     const uint8_t sk[32]);
/* pump once per UI frame: 0 working, 1 ready, 2 tofu-wait, -1 failed (a.err) */
int  net_async_pump(net_async *a);
/* NAS_TOFU only: pin the seen fingerprint and finish the handshake */
void net_async_trust(net_async *a);
void net_async_abort(net_async *a);

#endif /* COOLOO_NET_H */
