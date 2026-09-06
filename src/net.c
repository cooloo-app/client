/*
 * net.c - client side of the native protocol. See net.h.
 */
#include "net.h"
#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* platform socket layer: POSIX vs winsock2 (v2 Windows GUI build) */
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
static long sock_read(int fd, void *buf, size_t len)
{ return (long)recv(fd, (char *)buf, (int)len, 0); }
static long sock_write(int fd, const void *buf, size_t len)
{ return (long)send(fd, (const char *)buf, (int)len, 0); }
#define sock_close(fd) closesocket(fd)
static int  sock_wouldblock(void) { return WSAGetLastError() == WSAEWOULDBLOCK; }
static int  sock_err(void) { return WSAGetLastError(); }
static int  sock_inprogress(void)
{ int e = WSAGetLastError(); return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS; }
static int  sock_nonblock(int fd)
{ u_long m = 1; return ioctlsocket(fd, FIONBIO, &m); }
static void net_platform_init(void)
{ static int done; WSADATA d; if (!done) { WSAStartup(MAKEWORD(2, 2), &d); done = 1; } }
#else
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <fcntl.h>
static long sock_read(int fd, void *buf, size_t len)
{ return (long)read(fd, buf, len); }
static long sock_write(int fd, const void *buf, size_t len)
{ return (long)write(fd, buf, len); }
#define sock_close(fd) close(fd)
static int  sock_wouldblock(void)
{ return errno == EAGAIN || errno == EWOULDBLOCK; }
static int  sock_err(void) { return errno; }
static int  sock_inprogress(void) { return errno == EINPROGRESS; }
static int  sock_nonblock(int fd)
{ return fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK); }
static void net_platform_init(void) { }
#endif

static int read_full(int fd, uint8_t *buf, size_t len)
{
    size_t got = 0;
    while (got < len) {
        long n = sock_read(fd, buf + got, len - got);
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
        long n = sock_write(fd, buf + put, len - put);
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

    net_platform_init();
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
        sock_close(fd);
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
    if (!n) {
        /* msg1 build failed before any IO: OS RNG unavailable
         * (was the silent Windows kill path when /dev/urandom was used) */
        snprintf(errbuf, errcap, "handshake init failed (RNG)");
        return -1;
    }
    if (write_full(c->fd, msg, n) != 0)
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
    sock_close(c->fd);
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
        sock_close(c->fd);
    c->fd = -1;
    memset(&c->sess, 0, sizeof c->sess);
}

/* ---------------------------------------------------------------- */
/* v2: nonblocking receive + async handshake (see net.h)             */
/* ---------------------------------------------------------------- */

int net_try_recv(netconn *c)
{
    for (;;) {
        if (c->raw_len >= NOISE_FRAME_HDR_LEN) {
            size_t len = (size_t)c->raw[0] | ((size_t)c->raw[1] << 8);
            size_t total;
            long n;
            if (len > NOISE_FRAME_MAX_PT)
                return -1;
            total = len + NOISE_FRAME_OVERHEAD;
            if (c->raw_len >= total) {
                n = noise_session_recv(&c->sess, c->raw, total,
                                       c->plain + c->plain_len,
                                       sizeof c->plain - 1 - c->plain_len);
                if (n < 0)
                    return -1;
                c->plain_len += (size_t)n;
                c->plain[c->plain_len] = '\0';
                memmove(c->raw, c->raw + total, c->raw_len - total);
                c->raw_len -= total;
                return 1;
            }
        }
        {
            long r = sock_read(c->fd, c->raw + c->raw_len,
                               sizeof c->raw - c->raw_len);
            if (r > 0) {
                c->raw_len += (size_t)r;
                continue;
            }
            if (r == 0)
                return -1;              /* EOF */
            if (sock_wouldblock())
                return 0;
#ifndef _WIN32
            if (errno == EINTR)
                continue;
#endif
            return -1;
        }
    }
}

int net_try_line(netconn *c, char *out, size_t cap)
{
    uint8_t *nl = memchr(c->plain, '\n', c->plain_len);
    size_t ll;
    if (!nl)
        return 0;
    ll = (size_t)(nl - c->plain);
    if (ll >= cap)
        ll = cap - 1;
    memcpy(out, c->plain, ll);
    out[ll] = '\0';
    ll = (size_t)(nl - c->plain) + 1;
    memmove(c->plain, nl + 1, c->plain_len - ll);
    c->plain_len -= ll;
    return 1;
}

static void nas_fail(net_async *a, const char *msg)
{
    snprintf(a->err, sizeof a->err, "%s", msg);
    a->state = NAS_FAILED;
    if (a->c.fd >= 0) {
        sock_close(a->c.fd);
        a->c.fd = -1;
    }
}

/* nas_fail + last socket error, so GUI logs can tell failure stages apart */
static void nas_fail_io(net_async *a, const char *msg, int errnum)
{
#ifdef _WIN32
    snprintf(a->err, sizeof a->err, "%s (WSA %d)", msg, errnum);
#else
    snprintf(a->err, sizeof a->err, "%s (%s)", msg, strerror(errnum));
#endif
    a->state = NAS_FAILED;
    if (a->c.fd >= 0) {
        sock_close(a->c.fd);
        a->c.fd = -1;
    }
}

/* give up a connect/handshake with no progress for this many pump ticks
 * (~60s at the GUI's ~60fps frame pump); reset on any byte of progress */
#define NAS_PUMP_TIMEOUT 3600u

int net_async_start(net_async *a, const char *host, int port,
                    const uint8_t sk[32])
{
    struct addrinfo hints, *res = NULL, *ai;
    char port_s[16];
    int fd = -1;

    net_platform_init();
    memset(a, 0, sizeof *a);
    a->state = NAS_FAILED;
    a->c.fd = -1;
    snprintf(a->host, sizeof a->host, "%s", host);
    a->port = port;
    memcpy(a->sk, sk, 32);
    snprintf(a->hostport, sizeof a->hostport, "%s:%d", host, port);

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(port_s, sizeof port_s, "%d", port);
    if (getaddrinfo(host, port_s, &hints, &res) != 0) {
        snprintf(a->err, sizeof a->err, "cannot resolve %s", host);
        return -1;
    }
    for (ai = res; ai; ai = ai->ai_next) {
        fd = (int)socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0)
            continue;
        sock_nonblock(fd);
        if (connect(fd, ai->ai_addr, (socklen_t)ai->ai_addrlen) == 0)
            break;                      /* instant (loopback) */
        if (sock_inprogress())
            break;
        sock_close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) {
        snprintf(a->err, sizeof a->err, "cannot connect to %s:%d",
                 host, port);
        return -1;
    }
    a->c.fd = fd;
    a->state = NAS_TCP;
    return 0;
}

/* returns 0 working, 1 ready, 2 tofu-wait, -1 failed */
int net_async_pump(net_async *a)
{
    netconn *c = &a->c;

    /* ~1 pump per GUI frame: bound a stuck connect/handshake. NAS_TOFU
     * parks for the user and READY/FAILED are terminal, so no ticking. */
    if (a->state <= NAS_GREET && ++a->stall_ticks >= NAS_PUMP_TIMEOUT) {
        nas_fail(a, "connection timed out");
        return -1;
    }
    switch (a->state) {
    case NAS_TCP: {
        int soerr = 0;
        socklen_t sl = sizeof soerr;
        fd_set wf, ef;
        struct timeval tv;
        /* BSD/macOS reports SO_ERROR==0 while a connect is still in
         * flight; only trust it once the socket polls writable. Winsock
         * reports a *failed* nonblocking connect via exceptfds — pass it
         * or select may never wake and the GUI would spin forever. */
        FD_ZERO(&wf);
        FD_SET(c->fd, &wf);
        FD_ZERO(&ef);
        FD_SET(c->fd, &ef);
        tv.tv_sec = 0;
        tv.tv_usec = 0;
        if (select(c->fd + 1, NULL, &wf, &ef, &tv) <= 0)
            return 0;                       /* still connecting */
        if (getsockopt(c->fd, SOL_SOCKET, SO_ERROR, (char *)&soerr, &sl) != 0)
            soerr = -1;
        if (soerr != 0) {
            nas_fail_io(a, "connect failed", soerr);
            return -1;
        }
        noise_hs_init_initiator(&a->hs, a->sk, (const uint8_t *)"cooloo-v1", 9);
        a->wlen = noise_hs_write_msg1(&a->hs, a->wbuf, sizeof a->wbuf, NULL, 0);
        a->woff = 0;
        if (!a->wlen) {
            /* OS RNG unavailable — see ensure_ephemeral() */
            nas_fail(a, "handshake init failed (RNG)");
            return -1;
        }
        a->state = NAS_HS1;
    }
    /* fall through */
    case NAS_HS1:
        while (a->woff < a->wlen) {
            long n = sock_write(c->fd, a->wbuf + a->woff, a->wlen - a->woff);
            if (n > 0) {
                a->woff += (size_t)n;
                a->stall_ticks = 0;
                continue;
            }
            if (n < 0 && sock_wouldblock())
                return 0;
#ifndef _WIN32
            if (n < 0 && errno == EINTR)
                continue;
#endif
            nas_fail_io(a, "handshake msg1 send", sock_err());
            return -1;
        }
        a->rlen = 0;
        a->state = NAS_HS2;
    /* fall through */
    case NAS_HS2:
        while (a->rlen < NOISE_MSG2_LEN) {
            long n = sock_read(c->fd, a->rbuf + a->rlen,
                               NOISE_MSG2_LEN - a->rlen);
            if (n > 0) {
                a->rlen += (size_t)n;
                a->stall_ticks = 0;
                continue;
            }
            if (n == 0) {
                /* recv()==0 means a graceful close: the server hung up
                 * mid-handshake. Retrying recv would just spin. */
                nas_fail(a, "handshake closed by server");
                return -1;
            }
            if (sock_wouldblock())
                return 0;
#ifndef _WIN32
            if (errno == EINTR)
                continue;
#endif
            nas_fail_io(a, "handshake msg2 recv", sock_err());
            return -1;
        }
        {
            uint8_t dummy[1];
            size_t dummy_len;
            char pinned[65];
            if (noise_hs_read_msg2(&a->hs, a->rbuf, NOISE_MSG2_LEN,
                                   dummy, sizeof dummy, &dummy_len) != 0) {
                nas_fail(a, "handshake msg2 rejected");
                return -1;
            }
            noise_fingerprint_hex(c->server_fp, a->hs.rs);
            if (cfg_known_server_get(a->hostport, pinned)) {
                if (strcmp(pinned, c->server_fp) != 0) {
                    snprintf(a->err, sizeof a->err,
                             "SERVER FINGERPRINT CHANGED for %s "
                             "(pinned %.16s..., got %.16s...)",
                             a->hostport, pinned, c->server_fp);
                    a->state = NAS_FAILED;
                    sock_close(c->fd);
                    c->fd = -1;
                    return -1;
                }
                net_async_trust(a);     /* known-good: straight to msg3 */
                return net_async_pump(a);
            }
            a->state = NAS_TOFU;
            return 2;
        }
    case NAS_TOFU:
        return 2;
    case NAS_HS3:
        while (a->woff < a->wlen) {
            long n = sock_write(c->fd, a->wbuf + a->woff, a->wlen - a->woff);
            if (n > 0) {
                a->woff += (size_t)n;
                a->stall_ticks = 0;
                continue;
            }
            if (n < 0 && sock_wouldblock())
                return 0;
#ifndef _WIN32
            if (n < 0 && errno == EINTR)
                continue;
#endif
            nas_fail_io(a, "handshake msg3 send", sock_err());
            return -1;
        }
        noise_hs_split(&a->hs, &c->sess);
        memset(&a->hs, 0, sizeof a->hs);
        a->state = NAS_GREET;
    /* fall through */
    case NAS_GREET: {
        char line[128];
        int rc = net_try_recv(c);
        if (rc < 0) {
            nas_fail(a, "no greeting from server");
            return -1;
        }
        if (rc > 0)
            a->stall_ticks = 0;
        if (!net_try_line(c, line, sizeof line))
            return 0;
        if (strncmp(line, "COOLOO 1 ", 9) != 0) {
            snprintf(a->err, sizeof a->err, "bad greeting: %.64s", line);
            a->state = NAS_FAILED;
            return -1;
        }
        if (strcmp(line + 9, "-") != 0)
            snprintf(c->nick, sizeof c->nick, "%s", line + 9);
        a->state = NAS_READY;
        return 1;
    }
    case NAS_READY:
        return 1;
    default:
        return -1;
    }
}

void net_async_trust(net_async *a)
{
    if (a->state != NAS_TOFU && a->state != NAS_HS2)
        return;
    cfg_known_server_set(a->hostport, a->c.server_fp);
    a->wlen = noise_hs_write_msg3(&a->hs, a->wbuf, sizeof a->wbuf, NULL, 0);
    a->woff = 0;
    if (!a->wlen) {
        nas_fail(a, "handshake msg3 build failed");
        return;
    }
    a->stall_ticks = 0;
    a->state = NAS_HS3;
}

void net_async_abort(net_async *a)
{
    if (a->c.fd >= 0) {
        sock_close(a->c.fd);
        a->c.fd = -1;
    }
    memset(&a->hs, 0, sizeof a->hs);
    a->state = NAS_FAILED;
}
