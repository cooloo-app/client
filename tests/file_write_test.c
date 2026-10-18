/* Inject failures only in this executable; production file.c is included intact.
 * The close hook really closes the handle before reporting a delayed I/O error.
 */
#ifndef _WIN32
#define _XOPEN_SOURCE 700
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
static int fail_close, fail_replace;
#ifdef _WIN32
#include <windows.h>
static HANDLE written = INVALID_HANDLE_VALUE;
static BOOL test_write(HANDLE h, LPCVOID p, DWORD n, LPDWORD got, LPOVERLAPPED o) {
    written=h;return WriteFile(h,p,n,got,o);
}
static BOOL test_close(HANDLE h) {
    BOOL ok=CloseHandle(h);
    if(fail_close && h==written){fail_close=0;SetLastError(ERROR_WRITE_FAULT);return FALSE;}
    return ok;
}
static BOOL test_replace(LPCWSTR a,LPCWSTR b,LPCWSTR c,DWORD f,LPVOID x,LPVOID y) {
    if(fail_replace){SetLastError(ERROR_ACCESS_DENIED);return FALSE;}
    return ReplaceFileW(a,b,c,f,x,y);
}
#define WriteFile test_write
#define CloseHandle test_close
#define ReplaceFileW test_replace
#else
#include <unistd.h>
static int test_close(int fd) {
    int rc=close(fd);
    if(fail_close){fail_close=0;errno=EIO;return -1;}
    return rc;
}
static int test_rename(const char *a,const char *b) {
    if(fail_replace){errno=EACCES;return -1;}
    return rename(a,b);
}
#define close test_close
#define rename test_rename
#endif
#include "../src/platform/api/file.c"

int main(int argc,char **argv) {
    assert(argc==2);
    lua_State *L=luaL_newstate();assert(L);
    for(int mode=0;mode<3;mode++) {
        FILE *f=fopen(argv[1],"wb");assert(f);assert(fwrite("original",1,8,f)==8);assert(!fclose(f));
        fail_close=mode==0;fail_replace=mode==1;
        lua_pushcfunction(L,platform_write_file);lua_pushstring(L,argv[1]);lua_pushliteral(L,"replacement");
        assert(lua_pcall(L,2,LUA_MULTRET,0)==LUA_OK);
        assert(lua_toboolean(L,1)==(mode==2));lua_settop(L,0);
        char text[32]={0};f=fopen(argv[1],"rb");assert(f);fread(text,1,31,f);fclose(f);
        assert(!strcmp(text,mode==2?"replacement":"original"));
    }
    /* Exclusive recovery close failure cleans its partial file, then retries. */
    assert(!remove(argv[1]));fail_close=1;fail_replace=0;
    lua_pushcfunction(L,platform_write_file);lua_pushstring(L,argv[1]);lua_pushliteral(L,"recovery");lua_pushboolean(L,1);
    assert(lua_pcall(L,3,LUA_MULTRET,0)==LUA_OK && lua_isnil(L,1));lua_settop(L,0);
    FILE *f=fopen(argv[1],"rb");assert(!f);
    lua_pushcfunction(L,platform_write_file);lua_pushstring(L,argv[1]);lua_pushliteral(L,"recovery");lua_pushboolean(L,1);
    assert(lua_pcall(L,3,LUA_MULTRET,0)==LUA_OK && lua_toboolean(L,1));lua_settop(L,0);
    lua_pushcfunction(L,platform_write_file);lua_pushstring(L,argv[1]);lua_pushliteral(L,"must not overwrite");lua_pushboolean(L,1);
    assert(lua_pcall(L,3,LUA_MULTRET,0)==LUA_OK && lua_isnil(L,1) && lua_toboolean(L,3));
    assert(!remove(argv[1]));lua_close(L);
    puts("file write: close/replace failure preserves original; exclusive close failure/collision OK");return 0;
}
