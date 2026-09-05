/*
 * net.c - client side of the native protocol. See net.h.
 */
#include "net.h"
#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/types.h>

static int read_full(int fd, uint8_t *buf, size_t len)
{
    size_t got = 0;
    while (got < len) {
        ssize_t n = read(fd, buf + got, len - got);
        if (n <= 0)
            return -1;
        got += (size_t)n;
    }
    return 0;
}

static int write_full(int fd, const uint8_t *buf, size_t len)
{
    size_t put = 0;
    while (put < len) {
        ssize_t n = write(fd, buf + put, len - put);
        if (n <= 0)
            return -1;
        put += (size_t)n;
    }
    return 0;
}

static int tcp_connect(const char *host, int port, char *errbuf, size_t errcap)
{
    struct addrinfo hints, *res = NULL, *ai;
    char port_s[16];
    int fd = -1;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(port_s, sizeof port_s, "%d", port);
    if (getaddrinfo(host, port_s, &hints, &res) != 0) {
        snprintf(errbuf, errcap, "cannot resolve %s", host);
        return -1;
    }
    for (ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0)
            continue;
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0)
            break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0)
        snprintf(errbuf, errcap, "cannot connect to %s:%d", host, port);
    return fd;
}

/* Handshake phases are split so the TOFU decision happens between msg2
 * (server static known) and msg3 (which would leak our identity). */

/* variant that also reports the pre-msg3 server fingerprint without
 * completing the handshake (for the TOFU prompt flow). */
static int handshake_until_tofu(netconn *c, const uint8_t sk[32],
                                noise_hs *hs_out,
                                char *errbuf, size_t errcap)
{
    uint8_t msg[NOISE_MSG2_LEN];
    size_t n;
    uint8_t dummy[1];
    size_t dummy_len;

    noise_hs_init_initiator(hs_out, sk, (const uint8_t *)"cooloo-v1", 9);
    n = noise_hs_write_msg1(hs_out, msg, sizeof msg, NULL, 0);
    if (!n || write_full(c->fd, msg, n) != 0)
        goto hs_fail;
    if (read_full(c->fd, msg, NOISE_MSG2_LEN) != 0)
        goto hs_fail;
    if (noise_hs_read_msg2(hs_out, msg, NOISE_MSG2_LEN,
                           dummy, sizeof dummy, &dummy_len) != 0)
        goto hs_fail;
    noise_fingerprint_hex(c->server_fp, hs_out->rs);
    return 0;

hs_fail:
    snprintf(errbuf, errcap, "handshake failed");
    return -1;
}

static int handshake_finish(netconn *c, noise_hs *hs,
                            char *errbuf, size_t errcap)
{
    uint8_t msg[NOISE_MSG3_LEN];
    size_t n = noise_hs_write_msg3(hs, msg, sizeof msg, NULL, 0);
    if (!n || write_full(c->fd, msg, n) != 0) {
        snprintf(errbuf, errcap, "handshake failed");
        memset(hs, 0, sizeof *hs);
        return -1;
    }
    noise_hs_split(hs, &c->sess);
    memset(hs, 0, sizeof *hs);
    return 0;
}

/* read the greeting line and record nick */
static int read_greeting(netconn *c, char *errbuf, size_t errcap)
{
    char line[128];
    if (net_read_line(c, line, sizeof line) != 0) {
        snprintf(errbuf, errcap, "no greeting from server");
        return -1;
    }
    if (strncmp(line, "COOLOO 1 ", 9) != 0) {
        snprintf(errbuf, errcap, "bad greeting: %s", line);
        return -1;
    }
    if (strcmp(line + 9, "-") != 0)
        snprintf(c->nick, sizeof c->nick, "%s", line + 9);
    return 0;
}

static int connect_once(netconn *c, const char *host, int port,
                        const uint8_t sk[32], int tofu_mode,
                        char *errbuf, size_t errcap)
{
    char hostport[300], pinned[65];
    noise_hs hs;
    int rc = NET_ERR_IO;

    memset(c, 0, sizeof *c);
    c->fd = tcp_connect(host, port, errbuf, errcap);
    if (c->fd < 0)
        return NET_ERR_IO;

    if (handshake_until_tofu(c, sk, &hs, errbuf, errcap) != 0) {
        rc = NET_ERR_HANDSHAKE;
        goto out;
    }

    snprintf(hostport, sizeof hostport, "%s:%d", host, port);
    if (cfg_known_server_get(hostport, pinned)) {
        if (strcmp(pinned, c->server_fp) != 0) {
            snprintf(errbuf, errcap,
                     "SERVER FINGERPRINT CHANGED for %s\n"
                     "  pinned: %s\n  got:    %s\n"
                     "  refusing to connect (possible MITM). "
                     "Remove the pin in known_servers to re-trust.",
                     hostport, pinned, c->server_fp);
            rc = NET_ERR_TOFU_DIFF;
            goto out;
        }
    } else if (!tofu_mode) {
        rc = NET_TOFU_UNKNOWN;      /* caller prompts, then retries */
        goto out;
    } else {
        if (cfg_known_server_set(hostport, c->server_fp) != 0) {
            snprintf(errbuf, errcap, "cannot write known_servers");
            rc = NET_ERR_IO;
            goto out;
        }
    }

    if (handshake_finish(c, &hs, errbuf, errcap) != 0) {
        rc = NET_ERR_HANDSHAKE;
        goto out;
    }
    if (read_greeting(c, errbuf, errcap) != 0) {
        rc = NET_ERR_HANDSHAKE;
        goto out;
    }
    return NET_OK;

out:
    close(c->fd);
    c->fd = -1;
    return rc;
}

int net_connect(netconn *c, const char *host, int port,
                const uint8_t sk[32], int tofu_mode,
                char *errbuf, size_t errcap)
{
    return connect_once(c, host, port, sk, tofu_mode, errbuf, errcap);
}

int net_connect_trust(netconn *c, const char *host, int port,
                      const uint8_t sk[32], char *errbuf, size_t errcap)
{
    char hostport[300];
    snprintf(hostport, sizeof hostport, "%s:%d", host, port);
    if (cfg_known_server_set(hostport, c->server_fp) != 0) {
        snprintf(errbuf, errcap, "cannot write known_servers");
        return NET_ERR_IO;
    }
    return connect_once(c, host, port, sk, 0, errbuf, errcap);
}

int net_send(netconn *c, const void *pt, size_t len)
{
    uint8_t frame[NOISE_FRAME_MAX_PT + NOISE_FRAME_OVERHEAD];
    size_t n;

    if (len > NOISE_FRAME_MAX_PT)
        return -1;
    n = noise_session_send(&c->sess, pt, len, frame, sizeof frame);
    if (!n)
        return -1;
    return write_full(c->fd, frame, n);
}

int net_send_line(netconn *c, const char *line)
{
    return net_send(c, line, strlen(line));
}

int net_recv(netconn *c)
{
    uint8_t hdr[2];
    size_t len;
    long n;
    uint8_t frame[NOISE_FRAME_MAX_PT + NOISE_FRAME_OVERHEAD];

    if (read_full(c->fd, hdr, 2) != 0)
        return -1;
    len = (size_t)hdr[0] | ((size_t)hdr[1] << 8);
    if (len > NOISE_FRAME_MAX_PT)
        return -1;
    memcpy(frame, hdr, 2);
    if (read_full(c->fd, frame + 2, len + NOISE_TAG_LEN) != 0)
        return -1;
    n = noise_session_recv(&c->sess, frame, len + NOISE_FRAME_OVERHEAD,
                           c->plain + c->plain_len,
                           sizeof c->plain - 1 - c->plain_len);
    if (n < 0)
        return -1;
    c->plain_len += (size_t)n;
    c->plain[c->plain_len] = '\0';
    return 0;
}

int net_read_line(netconn *c, char *out, size_t cap)
{
    for (;;) {
        uint8_t *nl = memchr(c->plain, '\n', c->plain_len);
        size_t ll;
        if (nl) {
            ll = (size_t)(nl - c->plain);
            if (ll >= cap)
                ll = cap - 1;
            memcpy(out, c->plain, ll);
            out[ll] = '\0';
            ll = (size_t)(nl - c->plain) + 1;
            memmove(c->plain, nl + 1, c->plain_len - ll);
            c->plain_len -= ll;
            return 0;
        }
        if (net_recv(c) != 0)
            return -1;
    }
}

void net_close(netconn *c)
{
    if (c->fd >= 0)
        close(c->fd);
    c->fd = -1;
    memset(&c->sess, 0, sizeof c->sess);
}
