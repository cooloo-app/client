/*
 * cli.c - cooloo CLI subcommands (handoff §7).
 *
 * Display format: "HH:MM <nick> text" (local time); escaped storage form
 * is unescaped for display, multi-line messages indent continuation lines.
 */
#include "net.h"
#include "cli.h"
#include "config.h"
#include "noise_xx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <poll.h>

static int g_tofu;                      /* -y/--tofu: auto-trust new server */
static volatile sig_atomic_t g_stop;

void cooloo_cli_set_tofu(int on)
{
    g_tofu = on;
}

static void on_sigint(int sig)
{
    (void)sig;
    g_stop = 1;
}

/* ---------------------------------------------------------------- */
/* identity + connect helpers                                       */
/* ---------------------------------------------------------------- */

static int read_random(uint8_t *out, size_t len)
{
#ifdef __APPLE__
    arc4random_buf(out, len);
    return 0;
#else
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f)
        return -1;
    if (fread(out, 1, len, f) != len) {
        fclose(f);
        return -1;
    }
    fclose(f);
    return 0;
#endif
}

static int load_identity(uint8_t sk[32])
{
    if (cfg_identity_load(sk) != 0) {
        fprintf(stderr,
                "cooloo: no identity yet - run 'cooloo keygen' first\n");
        return -1;
    }
    return 0;
}

/* Connect with the full TOFU flow; exits the process on hard failure. */
static void cli_connect(netconn *c, const uint8_t sk[32])
{
    char host[256], err[512];
    int port, rc;

    cfg_server(host, sizeof host, &port);
    rc = net_connect(c, host, port, sk, g_tofu, err, sizeof err);
    if (rc == NET_OK)
        return;
    if (rc == NET_TOFU_UNKNOWN) {
        char answer[16];
        fprintf(stderr,
                "cooloo: unknown server %s:%d\n"
                "  fingerprint: %s\n"
                "trust and pin it? [y/N] ", host, port, c->server_fp);
        if (!fgets(answer, sizeof answer, stdin) ||
            (answer[0] != 'y' && answer[0] != 'Y')) {
            fprintf(stderr, "cooloo: not trusted, aborting\n");
            exit(1);
        }
        rc = net_connect_trust(c, host, port, sk, err, sizeof err);
        if (rc == NET_OK)
            return;
    }
    fprintf(stderr, "cooloo: %s\n", err);
    exit(1);
}

/* fail early with a useful hint when the command needs a registered nick */
static void need_registered(const netconn *c)
{
    if (!c->nick[0]) {
        fprintf(stderr,
                "cooloo: this key is not registered yet -\n"
                "  run 'cooloo whoami --register <nick>' first\n");
        exit(1);
    }
}

/* ---------------------------------------------------------------- */
/* display helpers                                                  */
/* ---------------------------------------------------------------- */

/* reverse of the storage escape table (escape.c): \\, \n, \r */
static size_t unescape(char *dst, size_t cap, const char *src, size_t srclen)
{
    size_t i, n = 0;
    for (i = 0; i < srclen && n + 1 < cap; i++) {
        if (src[i] == '\\' && i + 1 < srclen) {
            i++;
            if (src[i] == 'n')
                dst[n++] = '\n';
            else if (src[i] == 'r')
                dst[n++] = '\r';
            else
                dst[n++] = src[i];      /* '\\' and anything else literal */
        } else {
            dst[n++] = src[i];
        }
    }
    dst[n] = '\0';
    return n;
}

/* "HH:MM <nick> text", continuation lines aligned past the timestamp */
static void print_msg(const char *ts_s, const char *nick,
                      const char *text_escaped)
{
    char text[8192];
    char hm[6] = "??:??";
    long ts = strtol(ts_s, NULL, 10);
    time_t t = (time_t)ts;
    struct tm tmv;
    const char *p, *e;

    if (localtime_r(&t, &tmv))
        strftime(hm, sizeof hm, "%H:%M", &tmv);
    unescape(text, sizeof text, text_escaped, strlen(text_escaped));

    printf("%s <%s> ", hm, nick);
    for (p = text; ; p = e + 1) {
        e = strchr(p, '\n');
        if (!e) {
            printf("%s\n", p);
            break;
        }
        printf("%.*s\n      ", (int)(e - p), p);
        if (!e[1]) {                    /* trailing newline ends message */
            printf("\n");
            break;
        }
    }
}

/* read one MSG pair (header + text line); 1 ok, 0 not-an-MSG */
static int read_msg(netconn *c, char *hdr, size_t hcap,
                    char *text, size_t tcap)
{
    if (net_read_line(c, hdr, hcap) != 0)
        return -1;
    if (strncmp(hdr, "MSG ", 4) != 0)
        return 0;
    if (net_read_line(c, text, tcap) != 0)
        return -1;
    return 1;
}

/* parse "MSG <end> <ts> <nick> <tlen>" */
static int parse_msg_hdr(const char *hdr, long long *end,
                         char *ts, size_t tscap,
                         char *nick, size_t ncap)
{
    long long tlen;
    if (sscanf(hdr, "MSG %lld %15s %16s %lld", end, ts, nick, &tlen) != 4)
        return -1;
    (void)tlen;
    ts[tscap - 1] = '\0';
    nick[ncap - 1] = '\0';
    return 0;
}

/* ---------------------------------------------------------------- */
/* keygen                                                           */
/* ---------------------------------------------------------------- */

int cooloo_cli_keygen(int argc, char **argv)
{
    uint8_t sk[32], pk[32];
    char fp[65];
    (void)argc;
    (void)argv;

    if (read_random(sk, sizeof sk) != 0) {
        fprintf(stderr, "cooloo: RNG failure\n");
        return 1;
    }
    if (cfg_identity_create(sk) != 0) {
        fprintf(stderr, "cooloo: identity already exists (or config dir "
                        "unwritable); refusing to overwrite\n");
        return 1;
    }
    noise_public_key(pk, sk);
    noise_fingerprint_hex(fp, pk);
    memset(sk, 0, sizeof sk);
    printf("identity created\nfingerprint: %s\n", fp);
    printf("register with: cooloo whoami --register <nick>\n");
    return 0;
}

/* ---------------------------------------------------------------- */
/* send / read / rooms / whoami                                     */
/* ---------------------------------------------------------------- */

static size_t join_text(char *buf, size_t buflen, int argc, char **argv,
                        int first)
{
    size_t len = 0;
    int i;
    for (i = first; i < argc; i++) {
        size_t al = strlen(argv[i]);
        if (len && len + 1 < buflen)
            buf[len++] = ' ';
        if (len + al >= buflen)
            al = buflen - len - 1;
        memcpy(buf + len, argv[i], al);
        len += al;
    }
    buf[len] = '\0';
    while (len && (buf[len - 1] == ' ' || buf[len - 1] == '\t'))
        buf[--len] = '\0';
    return len;
}

int cooloo_cli_send(int argc, char **argv)
{
    static char text[8192];
    char hdr[160], line[512];
    uint8_t sk[32];
    netconn c;
    size_t len;
    int n;

    if (argc < 3) {
        fprintf(stderr, "usage: cooloo send <room> [text...] [-y]\n");
        return 2;
    }
    if (argc > 3)
        len = join_text(text, sizeof text, argc, argv, 3);
    else {
        len = 0;
        while (len < sizeof text - 1) {
            int ch = getchar();
            if (ch == EOF)
                break;
            text[len++] = (char)ch;
        }
        text[len] = '\0';
        while (len && (text[len - 1] == '\n' || text[len - 1] == '\r' ||
                       text[len - 1] == ' ' || text[len - 1] == '\t'))
            text[--len] = '\0';
    }
    if (len == 0) {
        fprintf(stderr, "cooloo: empty message\n");
        return 2;
    }
    if (load_identity(sk))
        return 1;
    cli_connect(&c, sk);
    need_registered(&c);

    n = snprintf(hdr, sizeof hdr, "SEND %s %zu\n", argv[2], len);
    if (net_send(&c, hdr, (size_t)n) != 0 ||
        net_send(&c, text, len) != 0 ||
        net_read_line(&c, line, sizeof line) != 0) {
        fprintf(stderr, "cooloo: connection lost\n");
        return 1;
    }
    if (strncmp(line, "ERR ", 4) == 0) {
        fprintf(stderr, "%s\n", line);
        return 1;
    }
    printf("%s\n", line);           /* OK <end_offset> */
    net_close(&c);
    return 0;
}

int cooloo_cli_read(int argc, char **argv)
{
    uint8_t sk[32];
    netconn c;
    char line[512], hdr[512], text[8192];
    int raw = 0, ai = 2, rc;

    if (argc > ai && !strcmp(argv[ai], "--raw")) {
        raw = 1;
        ai++;
    }
    if (argc - ai < 2) {
        fprintf(stderr, "usage: cooloo read [--raw] <room> <offset|-N>\n");
        return 2;
    }
    if (load_identity(sk))
        return 1;
    cli_connect(&c, sk);
    need_registered(&c);

    snprintf(line, sizeof line, "READ %s %s\n", argv[ai], argv[ai + 1]);
    if (net_send_line(&c, line) != 0) {
        fprintf(stderr, "cooloo: connection lost\n");
        return 1;
    }
    for (;;) {
        long long end;
        char ts[16], nick[17];
        rc = read_msg(&c, hdr, sizeof hdr, text, sizeof text);
        if (rc < 0) {
            fprintf(stderr, "cooloo: connection lost\n");
            return 1;
        }
        if (rc == 0) {
            if (!strcmp(hdr, "END"))
                break;
            if (strncmp(hdr, "ERR ", 4) == 0) {
                fprintf(stderr, "%s\n", hdr);
                return 1;
            }
            break;                  /* unexpected line: tolerate */
        }
        if (parse_msg_hdr(hdr, &end, ts, sizeof ts, nick, sizeof nick))
            continue;
        if (raw)
            printf("%lld %s %s %s\n", end, ts, nick, text);
        else
            print_msg(ts, nick, text);
    }
    net_close(&c);
    return 0;
}

int cooloo_cli_rooms(int argc, char **argv)
{
    uint8_t sk[32];
    netconn c;
    char line[512];
    (void)argc;
    (void)argv;

    if (load_identity(sk))
        return 1;
    cli_connect(&c, sk);
    if (net_send_line(&c, "ROOMS\n") != 0) {
        fprintf(stderr, "cooloo: connection lost\n");
        return 1;
    }
    for (;;) {
        if (net_read_line(&c, line, sizeof line) != 0) {
            fprintf(stderr, "cooloo: connection lost\n");
            return 1;
        }
        if (!strcmp(line, "END"))
            break;
        if (strncmp(line, "ROOM ", 5) == 0)
            printf("%s\n", line + 5);
        else if (strncmp(line, "ERR ", 4) == 0) {
            fprintf(stderr, "%s\n", line);
            return 1;
        }
    }
    net_close(&c);
    return 0;
}

int cooloo_cli_whoami(int argc, char **argv)
{
    uint8_t sk[32];
    netconn c;
    char line[512];

    if (load_identity(sk))
        return 1;
    cli_connect(&c, sk);

    if (argc > 2 && !strcmp(argv[2], "--register")) {
        if (argc < 4) {
            fprintf(stderr, "usage: cooloo whoami --register <nick>\n");
            return 2;
        }
        if (c.nick[0]) {
            fprintf(stderr, "cooloo: already registered as '%s'\n", c.nick);
            return 1;
        }
        snprintf(line, sizeof line, "HELLO %s\n", argv[3]);
        if (net_send_line(&c, line) != 0 ||
            net_read_line(&c, line, sizeof line) != 0) {
            fprintf(stderr, "cooloo: connection lost\n");
            return 1;
        }
        if (strncmp(line, "ERR ", 4) == 0) {
            fprintf(stderr, "%s\n", line);
            return 1;
        }
        printf("%s\n", line);       /* NICK <nick> */
        cfg_set("nick", argv[3]);
        net_close(&c);
        return 0;
    }

    if (net_send_line(&c, "WHOAMI\n") != 0 ||
        net_read_line(&c, line, sizeof line) != 0) {
        fprintf(stderr, "cooloo: connection lost\n");
        return 1;
    }
    if (!strcmp(line, "NICK -")) {
        printf("not registered (cooloo whoami --register <nick>)\n");
        printf("fingerprint: %s\n", "(see keygen output)");
    } else if (strncmp(line, "NICK ", 5) == 0) {
        printf("%s\n", line + 5);
    } else {
        printf("%s\n", line);
    }
    net_close(&c);
    return 0;
}

/* ---------------------------------------------------------------- */
/* follow / chat: long-lived loops with poll + keepalive            */
/* ---------------------------------------------------------------- */

/* non-blocking line extraction from the decrypted buffer:
 * 1 = got a line, 0 = need more frames */
static int try_line(netconn *c, char *out, size_t cap)
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

/* process buffered lines in follow mode; returns 0 ok, -1 on ERR/close.
 * *want_text tracks the MSG header->text pairing; persists offsets. */
static int follow_drain(netconn *c, const char *room, int *want_text)
{
    char line[8192], ts[16], nick[17], hdr[512];
    long long end;

    while (try_line(c, line, sizeof line)) {
        if (*want_text) {
            *want_text = 0;
            if (parse_msg_hdr(hdr, &end, ts, sizeof ts,
                              nick, sizeof nick) == 0) {
                char key[64], val[24];
                print_msg(ts, nick, line);
                fflush(stdout);
                snprintf(key, sizeof key, "offset.%s", room);
                snprintf(val, sizeof val, "%lld", end);
                cfg_set(key, val);   /* resume point (D22) */
            }
            continue;
        }
        if (strncmp(line, "MSG ", 4) == 0) {
            snprintf(hdr, sizeof hdr, "%s", line);
            *want_text = 1;
        } else if (strncmp(line, "ERR ", 4) == 0) {
            fprintf(stderr, "%s\n", line);
            return -1;
        } else if (!strcmp(line, "PONG")) {
            /* keepalive answer: fine */
        }
    }
    return 0;
}

static int follow_once(const char *room, const uint8_t sk[32])
{
    netconn c;
    char line[512], key[64], saved[24];
    time_t last_ping = time(NULL);
    int want_text = 0;

    cli_connect(&c, sk);
    need_registered(&c);

    snprintf(key, sizeof key, "offset.%s", room);
    if (cfg_get(key, saved, sizeof saved) == 0)
        snprintf(line, sizeof line, "FOLLOW %s %s\n", room, saved);
    else
        snprintf(line, sizeof line, "FOLLOW %s\n", room);
    if (net_send_line(&c, line) != 0) {
        net_close(&c);
        return -1;
    }

    while (!g_stop) {
        struct pollfd pfd;
        int pr;
        pfd.fd = c.fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        pr = poll(&pfd, 1, 1000);
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (pr == 0) {              /* idle: keepalive every 30s */
            if (time(NULL) - last_ping >= 30) {
                if (net_send_line(&c, "PING\n") != 0)
                    break;
                last_ping = time(NULL);
            }
            continue;
        }
        if (pfd.revents & (POLLERR | POLLHUP))
            break;
        if (net_recv(&c) != 0)
            break;
        if (follow_drain(&c, room, &want_text) != 0) {
            net_close(&c);
            return -2;              /* protocol ERR: do not reconnect */
        }
    }
    net_close(&c);
    return g_stop ? 0 : -1;
}

int cooloo_cli_follow(int argc, char **argv)
{
    uint8_t sk[32];
    int rc;

    if (argc < 3) {
        fprintf(stderr, "usage: cooloo follow <room> [-y]\n");
        return 2;
    }
    if (load_identity(sk))
        return 1;
    signal(SIGINT, on_sigint);
    signal(SIGTERM, on_sigint);

    /* resume from the persisted offset on every (re)connect */
    while (!g_stop) {
        rc = follow_once(argv[2], sk);
        if (rc == 0 || rc == -2)
            break;
        fprintf(stderr, "cooloo: connection lost, retrying in 1s...\n");
        sleep(1);
    }
    return rc == -2 ? 1 : 0;
}

int cooloo_cli_chat(int argc, char **argv)
{
    uint8_t sk[32];
    netconn c;
    char line[4096], hdr[512], ts[16], nick[17];
    int want_text = 0;
    time_t last_ping = time(NULL);

    if (argc < 3) {
        fprintf(stderr, "usage: cooloo chat <room> [-y]\n");
        return 2;
    }
    if (load_identity(sk))
        return 1;
    signal(SIGINT, on_sigint);
    cli_connect(&c, sk);
    need_registered(&c);

    /* join at tail (live messages only), like v0 follow without offset */
    {
        char fline[128];
        snprintf(fline, sizeof fline, "FOLLOW %s\n", argv[2]);
        if (net_send_line(&c, fline) != 0) {
            fprintf(stderr, "cooloo: connection lost\n");
            return 1;
        }
    }
    fprintf(stderr, "chatting in #%s as %s - Ctrl-C or EOF to exit\n",
            argv[2], c.nick);
    printf("> ");
    fflush(stdout);

    while (!g_stop) {
        struct pollfd pfds[2];
        int pr;

        pfds[0].fd = 0;             /* stdin */
        pfds[0].events = POLLIN;
        pfds[0].revents = 0;
        pfds[1].fd = c.fd;
        pfds[1].events = POLLIN;
        pfds[1].revents = 0;
        pr = poll(pfds, 2, 1000);
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        if (pr == 0) {
            if (time(NULL) - last_ping >= 30) {
                if (net_send_line(&c, "PING\n") != 0)
                    break;
                last_ping = time(NULL);
            }
            continue;
        }

        if (pfds[0].revents & POLLIN) {
            size_t len;
            if (!fgets(line, sizeof line, stdin))
                break;              /* EOF: leave chat */
            len = strlen(line);
            while (len && (line[len - 1] == '\n' || line[len - 1] == '\r'))
                line[--len] = '\0';
            if (len) {
                char shdr[160];
                int hl = snprintf(shdr, sizeof shdr, "SEND %s %zu\n",
                                  argv[2], len);
                if (net_send(&c, shdr, (size_t)hl) != 0 ||
                    net_send(&c, line, len) != 0) {
                    fprintf(stderr, "\ncooloo: connection lost\n");
                    break;
                }
            }
            printf("> ");
            fflush(stdout);
        }

        if (pfds[1].revents & POLLIN) {
            if (net_recv(&c) != 0) {
                fprintf(stderr, "\ncooloo: connection lost\n");
                break;
            }
            while (try_line(&c, line, sizeof line)) {
                if (want_text) {
                    long long end;
                    want_text = 0;
                    if (parse_msg_hdr(hdr, &end, ts, sizeof ts,
                                      nick, sizeof nick) == 0) {
                        /* canonical terminal: clear the prompt line,
                         * print the message, redraw the prompt */
                        printf("\r\x1b[K");
                        print_msg(ts, nick, line);
                        printf("> ");
                        fflush(stdout);
                    }
                } else if (strncmp(line, "MSG ", 4) == 0) {
                    snprintf(hdr, sizeof hdr, "%s", line);
                    want_text = 1;
                } else if (strncmp(line, "OK ", 3) == 0 ||
                           !strcmp(line, "PONG")) {
                    /* our own SEND ack / keepalive: stay quiet */
                } else if (strncmp(line, "ERR ", 4) == 0) {
                    printf("\r\x1b[K%s\n> ", line);
                    fflush(stdout);
                }
            }
        }
        if (pfds[1].revents & (POLLERR | POLLHUP))
            break;
    }
    net_close(&c);
    printf("\n");
    return 0;
}
