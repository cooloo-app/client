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

#endif /* COOLOO_NET_H */
