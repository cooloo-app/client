/*
 * config.c - see config.h. Plain-text, fixed buffers, atomicity via
 * write-temp-then-rename for the kv config (follow offsets get rewritten
 * often; a crash must not truncate the file).
 */
#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <fcntl.h>
/* POSIX permission calls as no-op-ish win32 shims (files land in the
 * user's profile dir; ACLs are the win32 permission model) */
static int  win_mkdir(const char *p, int m) { (void)m; return _mkdir(p); }
static int  win_umask(int m) { (void)m; return 0; }
static int  win_chmod(const char *p, int m) { (void)p; (void)m; return 0; }
#define mkdir(p, m)   win_mkdir(p, m)
#define umask(m)      win_umask(m)
#define chmod(p, m)   win_chmod(p, m)
#else
#include <unistd.h>
#endif

#define PATH_BUF 1024
#define MAX_KV   256

static int cfg_path(char *buf, size_t buflen, const char *name)
{
    char dir[PATH_BUF];
    if (cfg_dir(dir, sizeof dir) != 0)
        return -1;
    if (snprintf(buf, buflen, "%s/%s", dir, name) >= (int)buflen)
        return -1;
    return 0;
}

int cfg_dir(char *buf, size_t buflen)
{
    const char *env = getenv("COOLOO_CONFIG");
    const char *home;
    mode_t old_umask;
    int n;

    if (env && env[0])
        n = snprintf(buf, buflen, "%s", env);
    else {
        home = getenv("HOME");
#ifdef _WIN32
        if (!home)
            home = getenv("USERPROFILE");
#endif
        if (!home)
            return -1;
        n = snprintf(buf, buflen, "%s/.config/cooloo", home);
    }
    if (n <= 0 || n >= (int)buflen)
        return -1;
    old_umask = umask(077);
    if (mkdir(buf, 0700) != 0 && errno != EEXIST) {
        umask(old_umask);
        return -1;
    }
    umask(old_umask);
    return 0;
}

void cfg_server(char *host, size_t host_cap, int *port)
{
    char val[256];
    const char *env = getenv("COOLOO_HOST");

    snprintf(host, host_cap, "43.133.202.144");
    *port = 4222;
    if (cfg_get("host", val, sizeof val) == 0)
        snprintf(host, host_cap, "%s", val);
    if (cfg_get("port", val, sizeof val) == 0)
        *port = atoi(val);
    if (env && env[0]) {
        const char *colon = strrchr(env, ':');
        if (colon) {
            snprintf(host, host_cap, "%.*s", (int)(colon - env), env);
            *port = atoi(colon + 1);
        } else {
            snprintf(host, host_cap, "%s", env);
        }
    }
}

int cfg_identity_load(uint8_t sk[32])
{
    char path[PATH_BUF];
    FILE *f;
    size_t n;

    if (cfg_path(path, sizeof path, "identity") != 0)
        return -1;
    f = fopen(path, "rb");
    if (!f)
        return -1;
    n = fread(sk, 1, 32, f);
    fclose(f);
    return n == 32 ? 0 : -1;
}

int cfg_identity_create(const uint8_t sk[32])
{
    char path[PATH_BUF];
    FILE *f;
    mode_t old_umask;

    if (cfg_path(path, sizeof path, "identity") != 0)
        return -1;
    old_umask = umask(077);
#ifdef _WIN32
    {
        int fd = _open(path, _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY,
                       0600);
        f = fd < 0 ? NULL : _fdopen(fd, "wb");
    }
#else
    f = fopen(path, "wbx");        /* fail if exists (C11 x; POSIX 2024 ok) */
#endif
    if (!f) {
        umask(old_umask);
        return -1;
    }
    if (fwrite(sk, 1, 32, f) != 32) {
        fclose(f);
        umask(old_umask);
        return -1;
    }
    fclose(f);
    umask(old_umask);
    chmod(path, 0600);             /* in case umask was bypassed */
    return 0;
}

/* ---------------------------------------------------------------- */
/* line-based stores (known_servers, config kv)                     */
/* ---------------------------------------------------------------- */

struct kv {
    char key[128];
    char val[128];
};

static int kv_load(const char *name, struct kv *out, int cap)
{
    char path[PATH_BUF];
    FILE *f;
    int n = 0;

    if (cfg_path(path, sizeof path, name) != 0)
        return 0;
    f = fopen(path, "r");
    if (!f)
        return 0;
    while (n < cap &&
           fscanf(f, "%127s %127s", out[n].key, out[n].val) == 2)
        n++;
    fclose(f);
    return n;
}

static int kv_save(const char *name, const struct kv *kv, int n,
                   mode_t mode)
{
    char path[PATH_BUF], tmp[PATH_BUF];
    FILE *f;
    int i;
    mode_t old_umask;

    if (cfg_path(path, sizeof path, name) != 0)
        return -1;
    if (snprintf(tmp, sizeof tmp, "%s.tmp", path) >= (int)sizeof tmp)
        return -1;
    old_umask = umask(077);
    f = fopen(tmp, "w");
    if (!f) {
        umask(old_umask);
        return -1;
    }
    for (i = 0; i < n; i++)
        fprintf(f, "%s %s\n", kv[i].key, kv[i].val);
    if (fclose(f) != 0 || rename(tmp, path) != 0) {
        umask(old_umask);
        return -1;
    }
    chmod(path, mode);
    umask(old_umask);
    return 0;
}

static int kv_set(const char *name, const char *key, const char *val,
                  mode_t mode)
{
    static struct kv kv[MAX_KV];
    int n, i;

    n = kv_load(name, kv, MAX_KV);
    for (i = 0; i < n; i++)
        if (!strcmp(kv[i].key, key)) {
            snprintf(kv[i].val, sizeof kv[i].val, "%s", val);
            return kv_save(name, kv, n, mode);
        }
    if (n >= MAX_KV)
        return -1;
    snprintf(kv[n].key, sizeof kv[n].key, "%s", key);
    snprintf(kv[n].val, sizeof kv[n].val, "%s", val);
    return kv_save(name, kv, n + 1, mode);
}

int cfg_known_server_get(const char *hostport, char fp_out[65])
{
    static struct kv kv[MAX_KV];
    int n, i;

    n = kv_load("known_servers", kv, MAX_KV);
    for (i = 0; i < n; i++)
        if (!strcmp(kv[i].key, hostport)) {
            snprintf(fp_out, 65, "%s", kv[i].val);
            return 1;
        }
    return 0;
}

int cfg_known_server_set(const char *hostport, const char *fp_hex)
{
    return kv_set("known_servers", hostport, fp_hex, 0644);
}

int cfg_get(const char *key, char *val, size_t val_cap)
{
    static struct kv kv[MAX_KV];
    int n, i;

    n = kv_load("config", kv, MAX_KV);
    for (i = 0; i < n; i++)
        if (!strcmp(kv[i].key, key)) {
            snprintf(val, val_cap, "%s", kv[i].val);
            return 0;
        }
    return -1;
}

int cfg_set(const char *key, const char *val)
{
    return kv_set("config", key, val, 0600);
}
