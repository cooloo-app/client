#include "runtime.h"
#include <lauxlib.h>
#include <lualib.h>
#include <SDL3/SDL.h>
#include <stdio.h>
int main(int argc,char **argv) {
    lua_State *L=luaL_newstate();int rc;
    if(argc!=3)return 2;
    SDL_SetEnvironmentVariable(SDL_GetEnvironment(),"COOLOO_EXECUTABLE",argv[1],true);
    luaL_openlibs(L);lua_newtable(L);runtime_register(L);lua_setglobal(L,"host");
    rc=luaL_dofile(L,argv[2]);
    if(rc)fprintf(stderr,"%s\n",lua_tostring(L,-1));
    runtime_shutdown();lua_close(L);return rc?1:0;
}
