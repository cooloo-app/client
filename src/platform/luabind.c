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
#include "api.h"
#include "renderer_api.h"
#include "rencache.h"
#include "runtime.h"
#ifndef COOLOO_EDITOR_ONLY
#include "net.h"
#include "config.h"
#include "record.h"
#include "message_id.h"
#include "noise_xx.h"
#ifdef COOLOO_WORKBENCH
#include "cache.h"
#endif
#endif

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

#ifndef COOLOO_EDITOR_ONLY
typedef struct {
    int used;
    int ready;
    int tofu;
    int paused;
    int token;
    SDL_Thread *resolver;
    SDL_AtomicInt resolving;
    char host[256];
    int port;
    uint8_t key[32];
    uint8_t output[64*1024];
    size_t output_len,output_pos;
    net_async a;
} conn_slot;

static conn_slot conns[MAX_CONNS];
static int next_token;
static int resolve_connection(void *ctx) {
    conn_slot *s=ctx;
    net_async_start(&s->a,s->host,s->port,s->key);
    memset(s->key,0,sizeof s->key);SDL_SetAtomicInt(&s->resolving,0);return 0;
}
static void abort_connection(conn_slot *s) {
    /* A DNS worker owns its slot until finished; never reuse its memory early. */
    if(s->resolver && SDL_GetAtomicInt(&s->resolving)){s->used=2;return;}
    if(s->resolver){SDL_WaitThread(s->resolver,NULL);s->resolver=NULL;}
    net_async_abort(&s->a);s->used=0;
}
static conn_slot *connection(int token) {
    int i;for(i=0;i<MAX_CONNS;i++)if(conns[i].used==1 && conns[i].token==token)return &conns[i];
    return NULL;
}
#endif
static lua_State *L;
static int raw_argc;
static char **raw_argv;
void luabind_set_args(int argc, char **argv) {
    free(raw_argv);
    raw_argv = malloc((size_t)argc * sizeof *raw_argv);
    if (!raw_argv && argc) abort();
    memcpy(raw_argv, argv, (size_t)argc * sizeof *raw_argv);
    raw_argc = argc;
}
static int quitting;
static int ev_ref = LUA_NOREF;      /* current events array (registry ref) */
static int ev_count;
static int failed;
static char last_error[2048] = "Lua initialization failed; see stderr for details.";
const char *luabind_last_error(void) { return last_error; }
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

#ifndef COOLOO_EDITOR_ONLY
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
        if (!s->used)continue;
        if(s->resolver) {
            if(SDL_GetAtomicInt(&s->resolving))continue;
            SDL_WaitThread(s->resolver,NULL);s->resolver=NULL;
            if(s->used==2){abort_connection(s);continue;}
        }
        if(s->ready && s->output_pos<s->output_len) {
            size_t wrote;
            if(net_try_write(&s->a.c,s->output+s->output_pos,s->output_len-s->output_pos,&wrote)<0) {
                ev_net_closed(s->token,"send failed; delivery may be unknown");abort_connection(s);continue;
            }
            s->output_pos+=wrote;
            if(s->output_pos==s->output_len)s->output_pos=s->output_len=0;
        }
        if(s->paused)continue;
        if (!s->ready) {
            int rc;
            if (s->tofu)
                continue;           /* parked until Lua net.trust/close */
            rc = net_async_pump(&s->a);
            if (rc == 1) {
                s->ready = 1;
                ev_net_ready(s->token, s->a.c.nick);
            } else if (rc == 2) {
                s->tofu = 1;
                ev_net_tofu(s->token, s->a.c.server_fp);
            } else if (rc < 0) {
                ev_net_closed(s->token, s->a.err[0] ? s->a.err : "connect failed");
                net_async_abort(&s->a);
                s->used = 0;
            }
            continue;
        }
        /* One decrypted frame per connection/tick: bounded UI event work. */
        for (int budget=0; budget<1; budget++) {
            int rc = net_try_recv(&s->a.c);
            if (rc == 0)
                break;
            if (rc < 0) {
                ev_net_closed(s->token, "connection lost");
                net_async_abort(&s->a);
                s->used = 0;
                break;
            }
            {
                char line[RECORD_MAX];
                while (net_try_line(&s->a.c, line, sizeof line))
                    ev_net_line(s->token, line);
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
    SDL_strlcpy(conns[i].host,host,sizeof conns[i].host);
    conns[i].port=port;memcpy(conns[i].key,sk,sizeof sk);
    memset(sk, 0, sizeof sk);
    SDL_SetAtomicInt(&conns[i].resolving,1);
    conns[i].resolver=SDL_CreateThread(resolve_connection,"resolve",&conns[i]);
    if(!conns[i].resolver){
        memset(conns[i].key,0,sizeof conns[i].key);
        lua_pushnil(l);lua_pushstring(l,SDL_GetError());return 2;
    }
    conns[i].used = 1;
    conns[i].ready = 0;
    conns[i].tofu = 0;
    conns[i].paused = 0;
    conns[i].output_len=conns[i].output_pos=0;
    conns[i].token = ++next_token;
    lua_pushinteger(l, conns[i].token);
    return 1;
}

static int l_net_send(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    size_t len;
    const char *data = luaL_checklstring(l, 2, &len);

    conn_slot *s=connection(id);
    if (!s || !s->ready) {
        lua_pushboolean(l, 0);
        return 1;
    }
    if(s->output_pos){
        memmove(s->output,s->output+s->output_pos,s->output_len-s->output_pos);
        s->output_len-=s->output_pos;s->output_pos=0;
    }
    if(len>NOISE_FRAME_MAX_PT || len+NOISE_FRAME_OVERHEAD>sizeof s->output-s->output_len){
        ev_net_closed(s->token,"send queue full; reconnect required");abort_connection(s);lua_pushboolean(l,0);return 1;
    }
    size_t n=noise_session_send(&s->a.c.sess,(const uint8_t *)data,len,s->output+s->output_len,sizeof s->output-s->output_len);
    if(!n){ev_net_closed(s->token,"encrypt failed");abort_connection(s);}
    else s->output_len+=n;
    lua_pushboolean(l,n!=0);
    return 1;
}

static int l_net_close(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    conn_slot *s=connection(id);
    if (s) {
        abort_connection(s);
    }
    return 0;
}

static int l_net_trust(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    conn_slot *s=connection(id);
    if (s && s->tofu) {
        net_async_trust(&s->a);
        s->tofu = 0;
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
    conn_slot *s=connection(id);
    if (s)
        st = s->ready ? "up" : (s->tofu ? "tofu" : "connecting");
    lua_pushstring(l, st);
    return 1;
}

static int l_net_fp(lua_State *l)
{
    int id = (int)luaL_checkinteger(l, 1);
    conn_slot *s=connection(id);
    if (s && !s->resolver && s->a.c.server_fp[0]) {
        lua_pushstring(l, s->a.c.server_fp);
        return 1;
    }
    lua_pushnil(l);
    return 1;
}

static int l_net_pause(lua_State *l) {
    conn_slot *s=connection((int)luaL_checkinteger(l,1));
    if(s)s->paused=lua_toboolean(l,2);
    return 0;
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

#else
void luabind_net_pump(void) {}
#endif

static int l_time(lua_State *l)
{
    lua_pushnumber(l, (lua_Number)SDL_GetTicksNS() / 1e9);
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
    float size = (float)luaL_optnumber(l, 2, 15);
    if (lua_isstring(l, 3)) font_select(lua_tostring(l, 3));
    lua_pushinteger(l, font_text_width_n(s, n, size));
    return 1;
}

static int l_line_height(lua_State *l)
{
    if (lua_isstring(l, 2)) font_select(lua_tostring(l, 2));
    lua_pushinteger(l, font_line_height((float)luaL_optnumber(l, 1, 15)));
    return 1;
}

static int l_clear_ime(lua_State *l)
{
    (void)l;
    gui_clear_ime();
    return 0;
}

static int l_set_ime_rect(lua_State *l)
{
    gui_set_ime_rect((int)luaL_checknumber(l, 1),
                     (int)luaL_checknumber(l, 2),
                     (int)luaL_checknumber(l, 3),
                     (int)luaL_checknumber(l, 4));
    return 0;
}

static int l_clipboard_get(lua_State *l)
{
    char *t = SDL_GetClipboardText();
    if (!t) return 0;
    lua_pushstring(l, t);
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

#ifndef COOLOO_EDITOR_ONLY
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

static int l_public_id(lua_State *l)
{
    uint8_t sk[32], pk[32]; char id[65]; int i;
    if (cfg_identity_load(sk)) { lua_pushnil(l); return 1; }
    noise_public_key(pk, sk); memset(sk, 0, sizeof sk);
    for (i = 0; i < 32; i++) sprintf(id + i * 2, "%02x", pk[i]);
    lua_pushstring(l, id); return 1;
}
static int l_message_id(lua_State *l)
{ char id[33];if(message_id_generate(id))return luaL_error(l,"secure random unavailable");lua_pushstring(l,id);return 1; }
static int l_record(lua_State *l)
{
    struct record r;
    if (record_parse(luaL_checkstring(l, 1), &r)) { lua_pushnil(l); return 1; }
    lua_newtable(l);
    lua_pushstring(l, r.id); lua_setfield(l, -2, "id");
    lua_pushinteger(l, r.ts); lua_setfield(l, -2, "ts");
    lua_pushstring(l, r.from); lua_setfield(l, -2, "from");
    lua_pushstring(l, r.to); lua_setfield(l, -2, "to");
    lua_pushstring(l, r.content); lua_setfield(l, -2, "content");
    return 1;
}
static int cached_line(void *ctx, long long end, const char *json)
{
    lua_State *l = ctx;
    lua_pushvalue(l, 4);
    lua_pushinteger(l, end);
    lua_pushstring(l, json);
    return lua_pcall(l, 2, 0, 0) == LUA_OK ? 0 : -1;
}
static int l_cache_read(lua_State *l)
{
    luaL_checktype(l, 4, LUA_TFUNCTION);
    lua_pushboolean(l, cache_read(luaL_checkstring(l, 1), luaL_checkstring(l, 2),
        luaL_checkstring(l, 3), cached_line, l) == 0);
    return 1;
}
static int l_cache_meta(lua_State *l)
{
    lua_pushboolean(l, cache_meta(luaL_checkstring(l, 1), luaL_checkstring(l, 2), luaL_checkstring(l, 3)) == 0);
    return 1;
}
static int l_cache_offset(lua_State *l)
{
    lua_pushinteger(l, cache_offset(luaL_checkstring(l, 1), luaL_checkstring(l, 2), luaL_checkstring(l, 3)));
    return 1;
}
static int l_cache_append(lua_State *l)
{
    lua_pushboolean(l, cache_append(luaL_checkstring(l, 1), luaL_checkstring(l, 2),
        luaL_checkstring(l, 3), luaL_checkinteger(l, 4), luaL_checkstring(l, 5)) == 0);
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

#endif

static void register_api(void)
{
    static const luaL_Reg top[] = {
        { "time", l_time },
        { "screen", l_screen },
        { "text_width", l_text_width },
        { "line_height", l_line_height },
        { "set_ime_rect", l_set_ime_rect },
        { "clear_ime", l_clear_ime },
        { "poll_event", gui_poll_event },
        { "wait_event", gui_wait_event },
#ifndef COOLOO_EDITOR_ONLY
        { "ensure_identity", l_ensure_identity },
        { "identity_fp", l_identity_fp },
        { "public_id", l_public_id },
        { "record", l_record },
        { "message_id", l_message_id },
        { "cache_offset", l_cache_offset },
        { "cache_read", l_cache_read },
        { "cache_meta", l_cache_meta },
        { "cache_append", l_cache_append },
        { "server", l_server },
#endif
        { "quit", l_quit },
        { "log", l_log },
        { NULL, NULL }
    };
#ifndef COOLOO_EDITOR_ONLY
    static const luaL_Reg netf[] = {
        { "connect", l_net_connect },
        { "send", l_net_send },
        { "close", l_net_close },
        { "trust", l_net_trust },
        { "state", l_net_state },
        { "fp", l_net_fp },
        { "pause", l_net_pause },
        { NULL, NULL }
    };
    static const luaL_Reg cfgf[] = {
        { "get", l_config_get },
        { "set", l_config_set },
        { NULL, NULL }
    };
#endif
    static const luaL_Reg clipf[] = {
        { "get", l_clipboard_get },
        { "set", l_clipboard_set },
        { NULL, NULL }
    };

    luaL_newlib(L, top);
    platform_register(L);
    luaopen_renderer(L);
    lua_setfield(L, -2, "renderer");
    lua_newtable(L);
    for (int i=0;i<raw_argc;i++) {
        lua_pushstring(L,raw_argv[i]);lua_rawseti(L,-2,i+1);
    }
    lua_setfield(L,-2,"args");
#ifndef COOLOO_EDITOR_ONLY
    runtime_register(L);
#endif
#ifdef COOLOO_WORKBENCH
    /* Workers start only after platform socket initialization on the host. */
    net_initialize();
    workbench_cache_register(L);
#endif
#ifdef COOLOO_EDITOR_ONLY
    extern int cooloo_text_file_count;
    extern int cooloo_text_safe_mode;
    lua_pushboolean(L,cooloo_text_safe_mode);lua_setfield(L,-2,"safe_mode");
    extern char **cooloo_text_files;
    lua_newtable(L);
    for (int i=0;i<cooloo_text_file_count;i++) {
        lua_pushstring(L,cooloo_text_files[i]);lua_rawseti(L,-2,i+1);
    }
    lua_setfield(L,-2,"text_files");

    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "offline");
#else
    luaL_newlib(L, netf);
    lua_setfield(L, -2, "net");
    luaL_newlib(L, cfgf);
    lua_setfield(L, -2, "config");
#endif
    luaL_newlib(L, clipf);
    lua_setfield(L, -2, "clipboard");
    lua_setglobal(L, "cooloo");
}

/* ---------------------------------------------------------------- */
/* script loading (embedded, or --lua-dev dir with mtime hot reload) */
/* ---------------------------------------------------------------- */

/* Called as xpcall's handler while the failing Lua stack still exists. */
static int fatal_error(lua_State *l)
{
    luaL_traceback(l, l, lua_tostring(l, 1), 1);
    snprintf(last_error, sizeof last_error, "%s", lua_tostring(l, -1));
    fprintf(stderr, "cooloo fatal: %s\n", lua_tostring(l, -1));
    lua_getglobal(l, "package");
    lua_getfield(l, -1, "loaded");
    lua_getfield(l, -1, "core");
    if (lua_istable(l, -1)) {
        lua_getfield(l, -1, "on_error");
        if (lua_isfunction(l, -1)) {
            lua_pushvalue(l, 2);
            if (lua_pcall(l, 1, 0, 0) != LUA_OK)
                fprintf(stderr, "recovery failed: %s\n", lua_tostring(l, -1));
        }
    }
    lua_settop(l, 2);
    failed = quitting = 1;
    return 1;
}

static int run_source(const char *name, const char *src)
{
    int base = lua_gettop(L);
    lua_pushcfunction(L, fatal_error);
    if (luaL_loadbuffer(L, src, strlen(src), name) != LUA_OK) {
        lua_pushcfunction(L, fatal_error);
        lua_pushvalue(L, -2);
        lua_call(L, 1, 1);
    } else if (lua_pcall(L, 0, 0, base + 1) == LUA_OK) {
        lua_settop(L, base);
        return 0;
    }
    lua_settop(L, base);
    return -1;
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
        fprintf(stderr, "cooloo gui: lua-dev: %s missing\n", path);
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
        if (dev_dir[0]) {
            if (run_disk_script(name) != 0) { failed = quitting = 1; return; }
        } else if (run_source(name, cooloo_embedded_lua[i].src) != 0) return;
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
    fprintf(stderr, "cooloo gui: workbench changed; restart to reload modules safely\n");
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
    if (failed) return -1;
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
#ifndef COOLOO_EDITOR_ONLY
    int i;
    for (i = 0; i < MAX_CONNS; i++)
        if (conns[i].used) {
            if(conns[i].resolver){SDL_WaitThread(conns[i].resolver,NULL);conns[i].resolver=NULL;}
            net_async_abort(&conns[i].a);conns[i].used=0;
        }
#endif
#ifndef COOLOO_EDITOR_ONLY
    runtime_shutdown();
#endif
#ifdef COOLOO_WORKBENCH
    workbench_cache_shutdown();
#endif
    if (L) {
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "loaded");
        lua_getfield(L, -1, "core");
        if (lua_istable(L, -1)) {
            lua_getfield(L, -1, "cleanup");
            if (lua_isfunction(L, -1) && lua_pcall(L, 0, 0, 0) != LUA_OK)
                fprintf(stderr, "cleanup failed: %s\n", lua_tostring(L, -1));
        }
        lua_close(L);
    }
    L = NULL;
    free(raw_argv);raw_argv=NULL;raw_argc=0;
}

/* Native renderer ends its frame during core.step, before coroutine work. */
int luabind_failed(void) { return failed; }

int luabind_frame(double dt, double frame_start)
{
    if (dev_dir[0]) dev_hotreload();
    int base = lua_gettop(L);
    lua_pushcfunction(L, fatal_error);
    lua_getglobal(L, "cooloo");
    lua_getfield(L, -1, "frame");
    lua_rawgeti(L, LUA_REGISTRYINDEX, ev_ref);
    lua_pushnumber(L, dt);
    lua_pushnumber(L, frame_start);
    lua_pcall(L, 3, 0, base + 1);
    lua_settop(L, base);
    return quitting;
}
