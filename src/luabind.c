/*
 * luabind.c - see luabind.h. Implements the global `cooloo` table (the
 * only C<->Lua boundary, 04 doc 4.2) plus the conn-slot registry for
 * net.connect/send/close/trust/state.
 */
#ifdef _WIN32
#define _CRT_RAND_S
#endif

#include "luabind.h"
#include "gui.h"
#include "font.h"
#include "net.h"
#include "config.h"
#include "noise_xx.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <SDL3/SDL.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#ifndef _WIN32
#include <sys/time.h>
#endif

struct embedded_lua { const char *name; const char *src; };
extern const struct embedded_lua cooloo_embedded_lua[];
extern const int cooloo_embedded_lua_count;

#define MAX_CONNS 16

typedef struct {
    int used;
    int ready;
    int tofu;
    net_async a;
} conn_slot;

static lua_State *L;
static conn_slot conns[MAX_CONNS];
static int quitting;
static int ev_ref = LUA_NOREF;      /* current events array (registry ref) */
static int ev_count;
static int presented;
static char dev_dir[512];           /* --lua-dev dir; "" = embedded mode */
static time_t dev_last_check;
static long dev_mtimes[64];

/* ---------------------------------------------------------------- */
/* event marshaling (C -> Lua)                                      */
/* ---------------------------------------------------------------- */

void luabind_events_begin(void)
{
    if (ev_ref != LUA_NOREF)
        luaL_unref(L, LUA_REGISTRYINDEX, ev_ref);
    lua_createtable(L, 64, 0);
    ev_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    ev_count = 0;
}

static void ev_begin(const char *type)
{
    lua_createtable(L, 0, 8);
    lua_pushstring(L, type);
    lua_setfield(L, -2, "type");
}

static void ev_s(const char *k, const char *v)
{
    lua_pushstring(L, v);
    lua_setfield(L, -2, k);
}

static void ev_i(const char *k, lua_Integer v)
{
    lua_pushinteger(L, v);
    lua_setfield(L, -2, k);
}

static void ev_commit(void)
{
    lua_rawgeti(L, LUA_REGISTRYINDEX, ev_ref);
    lua_pushvalue(L, -2);
    lua_rawseti(L, -2, ++ev_count);
    lua_pop(L, 2);
}

void luabind_ev_key(const char *name, int mod)
{
    ev_begin("key");
    ev_s("key", name);
    ev_i("mod", mod);
    ev_commit();
}

void luabind_ev_text(const char *text)
{
    ev_begin("text");
    ev_s("text", text);
    ev_commit();
}

void luabind_ev_ime(const char *text, int cursor)
{
    ev_begin("ime_edit");
    ev_s("text", text);
    ev_i("cursor", cursor);
    ev_commit();
}

void luabind_ev_mouse(const char *kind, int x, int y, int button,
                      int wx, int wy)
{
    ev_begin("mouse");
    ev_s("kind", kind);
    ev_i("x", x);
    ev_i("y", y);
    ev_i("button", button);
    ev_i("wx", wx);
    ev_i("wy", wy);
    ev_commit();
}

void luabind_ev_resize(int w, int h)
{
    ev_begin("resize");
    ev_i("w", w);
    ev_i("h", h);
    ev_commit();
}

void luabind_ev_quit(void)
{
    ev_begin("quit");
    ev_commit();
}

static void ev_net_ready(int conn, const char *nick)
{
    ev_begin("net_ready");
    ev_i("conn", conn);
    ev_s("nick", nick);
    ev_commit();
}

static void ev_net_line(int conn, const char *line)
{
    ev_begin("net_line");
    ev_i("conn", conn);
    ev_s("line", line);
    ev_commit();
}

static void ev_net_closed(int conn, const char *reason)
{
    ev_begin("net_closed");
    ev_i("conn", conn);
    ev_s("reason", reason);
    ev_commit();
}

static void ev_net_tofu(int conn, const char *fp)
{
    ev_begin("net_tofu");
    ev_i("conn", conn);
    ev_s("fp", fp);
    ev_commit();
}

/* ---------------------------------------------------------------- */
/* conn registry + pump                                             */
/* ---------------------------------------------------------------- */

void luabind_net_pump(void)
{
    int i;
    for (i = 0; i < MAX_CONNS; i++) {
        conn_slot *s = &conns[i];
        if (!s->used)
            continue;
        if (!s->ready) {
            int rc;
            if (s->tofu)
                continue;           /* parked until Lua net.trust/close */
            rc = net_async_pump(&s->a);
            if (rc == 1) {
                s->ready = 1;
                ev_net_ready(i, s->a.c.nick);
            } else if (rc == 2) {
                s->tofu = 1;
                ev_net_tofu(i, s->a.c.server_fp);
            } else if (rc < 0) {
                ev_net_closed(i, s->a.err[0] ? s->a.err : "connect failed");
                net_async_abort(&s->a);
                s->used = 0;
            }
            continue;
        }
        for (;;) {
            int rc = net_try_recv(&s->a.c);
            if (rc == 0)
                break;
            if (rc < 0) {
                ev_net_closed(i, "connection lost");
                net_async_abort(&s->a);
                s->used = 0;
                break;
            }
            {
                char line[8192];
                while (net_try_line(&s->a.c, line, sizeof line))
                    ev_net_line(i, line);
            }
        }
    }
}

/* ---------------------------------------------------------------- */
/* Lua API (global table `cooloo`)                                  */
/* ---------------------------------------------------------------- */

static int l_net_connect(lua_State *l)
{
    const char *host = luaL_checkstring(l, 1);
    int port = (int)luaL_checkinteger(l, 2);
    uint8_t sk[32];
    int i;

    for (i = 0; i < MAX_CONNS; i++)
        if (!conns[i].used)
            break;
    if (i == MAX_CONNS) {
        lua_pushnil(l);
        lua_pushstring(l, "too many connections");
        return 2;
    }
    if (cfg_identity_load(sk) != 0) {
        lua_pushnil(l);
        lua_pushstring(l, "no identity (call ensure_identity first)");
        return 2;
    }
    if (net_async_start(&conns[i].a, host, port, sk) != 0) {
        lua_pushnil(l);
        lua_pushstring(l, conns[i].a.err);
        memset(sk, 0, sizeof sk);
        return 2;
    }
    memset(sk, 0, sizeof sk);
    conns[i].used = 1;
    conns[i].ready = 0;
    conns[i].tofu = 0;
    lua_pushinteger(l, i);
    return 1;
}

static int l_net_send(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    size_t len;
    const char *data = luaL_checklstring(l, 2, &len);

    if (id < 0 || id >= MAX_CONNS || !conns[id].used || !conns[id].ready) {
        lua_pushboolean(l, 0);
        return 1;
    }
    lua_pushboolean(l, net_send(&conns[id].a.c, data, len) == 0);
    return 1;
}

static int l_net_close(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    if (id >= 0 && id < MAX_CONNS && conns[id].used) {
        net_async_abort(&conns[id].a);
        conns[id].used = 0;
    }
    return 0;
}

static int l_net_trust(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    if (id >= 0 && id < MAX_CONNS && conns[id].used && conns[id].tofu) {
        net_async_trust(&conns[id].a);
        conns[id].tofu = 0;
        lua_pushboolean(l, 1);
        return 1;
    }
    lua_pushboolean(l, 0);
    return 1;
}

static int l_net_state(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    const char *st = "closed";
    if (id >= 0 && id < MAX_CONNS && conns[id].used)
        st = conns[id].ready ? "up" : (conns[id].tofu ? "tofu" : "connecting");
    lua_pushstring(l, st);
    return 1;
}

static int l_net_fp(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    if (id >= 0 && id < MAX_CONNS && conns[id].used &&
        conns[id].a.c.server_fp[0]) {
        lua_pushstring(l, conns[id].a.c.server_fp);
        return 1;
    }
    lua_pushnil(l);
    return 1;
}

static int l_config_get(lua_State *l)
{
    char val[128];
    if (cfg_get(luaL_checkstring(l, 1), val, sizeof val) != 0) {
        lua_pushnil(l);
        return 1;
    }
    lua_pushstring(l, val);
    return 1;
}

static int l_config_set(lua_State *l)
{
    lua_pushboolean(l, cfg_set(luaL_checkstring(l, 1),
                               luaL_checkstring(l, 2)) == 0);
    return 1;
}

static int l_time(lua_State *l)
{
#ifdef _WIN32
    lua_pushnumber(l, (lua_Number)time(NULL));
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    lua_pushnumber(l, (lua_Number)tv.tv_sec + (lua_Number)tv.tv_usec / 1e6);
#endif
    return 1;
}

static int l_screen(lua_State *l)
{
    lua_pushinteger(l, gui_screen_w());
    lua_pushinteger(l, gui_screen_h());
    return 2;
}

static int l_text_width(lua_State *l)
{
    size_t n;
    const char *s = luaL_checklstring(l, 1, &n);
    int size = (int)luaL_optinteger(l, 2, 15);
    lua_pushinteger(l, font_text_width_n(s, n, size));
    return 1;
}

static int l_line_height(lua_State *l)
{
    lua_pushinteger(l, font_line_height((int)luaL_optinteger(l, 1, 15)));
    return 1;
}

static int l_set_ime_rect(lua_State *l)
{
    gui_set_ime_rect((int)luaL_checkinteger(l, 1),
                     (int)luaL_checkinteger(l, 2),
                     (int)luaL_checkinteger(l, 3),
                     (int)luaL_checkinteger(l, 4));
    return 0;
}

static int l_clipboard_get(lua_State *l)
{
    char *t = SDL_GetClipboardText();
    lua_pushstring(l, t ? t : "");
    if (t)
        SDL_free(t);
    return 1;
}

static int l_clipboard_set(lua_State *l)
{
    SDL_SetClipboardText(luaL_checkstring(l, 1));
    return 0;
}

static int l_quit(lua_State *l)
{
    (void)l;
    quitting = 1;
    return 0;
}

static int l_log(lua_State *l)
{
    fprintf(stderr, "lua: %s\n", luaL_optstring(l, 1, ""));
    return 1;
}

static int read_random(uint8_t *out, size_t len)
{
#if defined(__APPLE__)
    arc4random_buf(out, len);
    return 0;
#elif defined(_WIN32)
    unsigned int i, v = 0;
    for (i = 0; i < len; i++) {
        if (i % 4 == 0 && rand_s(&v) != 0)
            return -1;
        out[i] = (uint8_t)(v >> ((i % 4) * 8));
    }
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

static int l_ensure_identity(lua_State *l)
{
    uint8_t sk[32], pk[32];
    char fp[65];

    if (cfg_identity_load(sk) != 0) {
        if (read_random(sk, sizeof sk) != 0 || cfg_identity_create(sk) != 0) {
            memset(sk, 0, sizeof sk);
            lua_pushnil(l);
            lua_pushstring(l, "cannot create identity");
            return 2;
        }
    }
    noise_public_key(pk, sk);
    noise_fingerprint_hex(fp, pk);
    memset(sk, 0, sizeof sk);
    lua_pushstring(l, fp);
    return 1;
}

static int l_identity_fp(lua_State *l)
{
    uint8_t sk[32], pk[32];
    char fp[65];

    if (cfg_identity_load(sk) != 0) {
        lua_pushnil(l);
        return 1;
    }
    noise_public_key(pk, sk);
    noise_fingerprint_hex(fp, pk);
    memset(sk, 0, sizeof sk);
    lua_pushstring(l, fp);
    return 1;
}

static int l_server(lua_State *l)
{
    char host[256];
    int port;
    cfg_server(host, sizeof host, &port);
    lua_pushstring(l, host);
    lua_pushinteger(l, port);
    return 2;
}

static void register_api(void)
{
    static const luaL_Reg top[] = {
        { "time", l_time },
        { "screen", l_screen },
        { "text_width", l_text_width },
        { "line_height", l_line_height },
        { "set_ime_rect", l_set_ime_rect },
        { "ensure_identity", l_ensure_identity },
        { "identity_fp", l_identity_fp },
        { "server", l_server },
        { "quit", l_quit },
        { "log", l_log },
        { NULL, NULL }
    };
    static const luaL_Reg netf[] = {
        { "connect", l_net_connect },
        { "send", l_net_send },
        { "close", l_net_close },
        { "trust", l_net_trust },
        { "state", l_net_state },
        { "fp", l_net_fp },
        { NULL, NULL }
    };
    static const luaL_Reg cfgf[] = {
        { "get", l_config_get },
        { "set", l_config_set },
        { NULL, NULL }
    };
    static const luaL_Reg clipf[] = {
        { "get", l_clipboard_get },
        { "set", l_clipboard_set },
        { NULL, NULL }
    };

    luaL_newlib(L, top);
    luaL_newlib(L, netf);
    lua_setfield(L, -2, "net");
    luaL_newlib(L, cfgf);
    lua_setfield(L, -2, "config");
    luaL_newlib(L, clipf);
    lua_setfield(L, -2, "clipboard");
    lua_setglobal(L, "cooloo");
}

/* ---------------------------------------------------------------- */
/* script loading (embedded, or --lua-dev dir with mtime hot reload) */
/* ---------------------------------------------------------------- */

static int run_source(const char *name, const char *src)
{
    if (luaL_loadbuffer(L, src, strlen(src), name) != LUA_OK ||
        lua_pcall(L, 0, 0, 0) != LUA_OK) {
        fprintf(stderr, "cooloo gui: %s: %s\n", name, lua_tostring(L, -1));
        lua_pop(L, 1);
        return -1;
    }
    return 0;
}

static int run_disk_script(const char *name)
{
    char path[600];
    FILE *f;
    long sz;
    char *buf;
    int rc;

    snprintf(path, sizeof path, "%s/%s", dev_dir, name);
    f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "cooloo gui: lua-dev: %s missing, embedded used\n",
                path);
        return -1;
    }
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = malloc((size_t)sz + 1);
    if (!buf || fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return -1;
    }
    fclose(f);
    buf[sz] = '\0';
    rc = run_source(name, buf);
    free(buf);
    return rc;
}

static void run_scripts(void)
{
    int i;
    for (i = 0; i < cooloo_embedded_lua_count; i++) {
        const char *name = cooloo_embedded_lua[i].name;
        if (dev_dir[0] && run_disk_script(name) == 0)
            continue;
        run_source(name, cooloo_embedded_lua[i].src);
    }
}

static void dev_snapshot(long *out)
{
    int i;
    for (i = 0; i < cooloo_embedded_lua_count; i++) {
        char path[600];
        struct stat st;
        snprintf(path, sizeof path, "%s/%s", dev_dir,
                 cooloo_embedded_lua[i].name);
        out[i] = stat(path, &st) == 0 ? (long)st.st_mtime : 0;
    }
}

static void dev_hotreload(void)
{
    long cur[64];
    int i, changed = 0;

    if (!dev_dir[0] || time(NULL) == dev_last_check)
        return;
    dev_last_check = time(NULL);
    dev_snapshot(cur);
    for (i = 0; i < cooloo_embedded_lua_count; i++)
        if (cur[i] != dev_mtimes[i])
            changed = 1;
    if (!changed)
        return;
    memcpy(dev_mtimes, cur, sizeof dev_mtimes);
    fprintf(stderr, "cooloo gui: lua-dev reload\n");
    run_scripts();
}

int luabind_init(const char *dir)
{
    L = luaL_newstate();
    if (!L) {
        fprintf(stderr, "cooloo gui: lua alloc failed\n");
        return -1;
    }
    luaL_openlibs(L);
    register_api();
    if (dir) {
        snprintf(dev_dir, sizeof dev_dir, "%s", dir);
        dev_snapshot(dev_mtimes);
    }
    run_scripts();
    lua_getglobal(L, "cooloo");
    lua_getfield(L, -1, "frame");
    if (!lua_isfunction(L, -1)) {
        fprintf(stderr, "cooloo gui: lua: cooloo.frame not defined\n");
        return -1;
    }
    lua_pop(L, 2);
    return 0;
}

void luabind_shutdown(void)
{
    int i;
    for (i = 0; i < MAX_CONNS; i++)
        if (conns[i].used)
            net_async_abort(&conns[i].a);
    if (L)
        lua_close(L);
    L = NULL;
}

/* ---------------------------------------------------------------- */
/* draw list execution (tolerant: bad ops warn + skip, doc 4.2/6.2)  */
/* ---------------------------------------------------------------- */

static lua_Integer geti(const char *k)
{
    lua_Integer v;
    lua_getfield(L, -1, k);
    v = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return v;
}

static lua_Integer opti(const char *k, lua_Integer dflt)
{
    lua_Integer v;
    lua_getfield(L, -1, k);
    v = lua_isnumber(L, -1) ? lua_tointeger(L, -1) : dflt;
    lua_pop(L, 1);
    return v;
}

static void exec_draw_list(void)
{
    lua_Integer n, i;

    presented = 0;
    if (!lua_istable(L, -1)) {
        if (!lua_isnil(L, -1))
            fprintf(stderr, "cooloo gui: draw list is %s, want table\n",
                    lua_typename(L, lua_type(L, -1)));
        return;
    }
    n = (lua_Integer)luaL_len(L, -1);
    if (n > 200000)
        n = 200000;
    for (i = 1; i <= n; i++) {
        const char *op;
        lua_geti(L, -1, i);
        if (!lua_istable(L, -1)) {
            fprintf(stderr, "cooloo gui: draw op #%lld not a table, skip\n",
                    (long long)i);
            lua_pop(L, 1);
            continue;
        }
        lua_getfield(L, -1, "op");
        op = lua_tostring(L, -1);
        lua_pop(L, 1);
        if (!op) {
            fprintf(stderr, "cooloo gui: draw op #%lld missing op, skip\n",
                    (long long)i);
        } else if (!strcmp(op, "rect")) {
            gui_draw_rect((int)geti("x"), (int)geti("y"),
                          (int)geti("w"), (int)geti("h"),
                          (unsigned)geti("color"));
        } else if (!strcmp(op, "text")) {
            const char *t;
            lua_getfield(L, -1, "text");
            t = lua_tostring(L, -1);
            if (t)
                gui_draw_text((int)geti("x"), (int)geti("y"), t,
                              (unsigned)geti("color"),
                              (int)opti("size", 15));
            lua_pop(L, 1);
        } else if (!strcmp(op, "clip")) {
            gui_set_clip((int)geti("x"), (int)geti("y"),
                         (int)geti("w"), (int)geti("h"));
        } else if (!strcmp(op, "unclip")) {
            gui_clear_clip();
        } else if (!strcmp(op, "present")) {
            gui_present();
            presented = 1;
        } else {
            fprintf(stderr, "cooloo gui: unknown draw op '%s', skip\n", op);
        }
        lua_pop(L, 1);
    }
}

int luabind_frame(double dt)
{
    if (dev_dir[0])
        dev_hotreload();

    lua_getglobal(L, "cooloo");
    lua_getfield(L, -1, "frame");
    if (!lua_isfunction(L, -1)) {
        fprintf(stderr, "cooloo gui: cooloo.frame missing\n");
        lua_pop(L, 2);
        gui_present();
        return quitting;
    }
    lua_rawgeti(L, LUA_REGISTRYINDEX, ev_ref);
    lua_pushnumber(L, dt);
    if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
        fprintf(stderr, "cooloo gui: lua error: %s\n", lua_tostring(L, -1));
        lua_pop(L, 2);
        gui_present();
        return quitting;
    }
    /* stack: cooloo table, draw list */
    exec_draw_list();
    lua_pop(L, 2);
    if (!presented)
        gui_present();
    return quitting;
}
