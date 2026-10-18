/* Headless workbench entry: shared record decoder and Lua model, no SDL. */
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "record.h"
#include "runtime.h"
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
struct embedded_lua { const char *name; const char *src; };
extern const struct embedded_lua cooloo_embedded_lua[];
static int decode(lua_State *L) {
    struct record r;
    size_t n;
    const char *s=luaL_checklstring(L,1,&n);
    if(n>RECORD_MAX || memchr(s,0,n) || record_parse(s,&r))return 0;
    lua_newtable(L);
    lua_pushinteger(L,r.ts);lua_setfield(L,-2,"ts");
    lua_pushstring(L,r.from);lua_setfield(L,-2,"from");
    lua_pushstring(L,r.to);lua_setfield(L,-2,"to");
    lua_pushstring(L,r.content);lua_setfield(L,-2,"text");
    return 1;
}
int main(int argc,char **argv) {
    int rc=runtime_dispatch(argc,argv);
    if(rc>=0)return rc;
#ifdef _WIN32
    _setmode(_fileno(stdout),_O_BINARY);
#endif
    lua_State *L=luaL_newstate();if(!L)return 1;
    luaL_openlibs(L);
    lua_pushcfunction(L,decode);lua_setglobal(L,"decode_record");
    lua_newtable(L);
    for(int i=1;i<argc;i++){lua_pushstring(L,argv[i]);lua_rawseti(L,-2,i);}
    lua_setglobal(L,"arg");
    rc=luaL_loadstring(L,cooloo_embedded_lua[0].src);
    if(!rc)rc=lua_pcall(L,0,1,0);
    if(rc){fprintf(stderr,"%s\n",lua_tostring(L,-1));rc=1;}
    else rc=(int)lua_tointeger(L,-1);
    lua_close(L);return rc;
}
