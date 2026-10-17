/* Real SDL surface + production Lua renderer/platform API. No font stubs. */
#define SDL_MAIN_HANDLED
#include <SDL3/SDL.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include "renderer_api.h"
#include "renderer.h"
#include "rencache.h"
#include "font.h"
#include "api.h"
#include "gui.h"
int cooloo_text_file_count,cooloo_text_safe_mode,cooloo_text_argc;
char **cooloo_text_files,**cooloo_text_argv;
const char *cooloo_text_executable;
extern const unsigned char cooloo_embedded_font[];
extern const unsigned int cooloo_embedded_font_len;
static int pixel(lua_State *L) {
    SDL_Surface *s=ren_surface();
    int x=(int)luaL_checkinteger(L,1),y=(int)luaL_checkinteger(L,2);
    luaL_argcheck(L,x>=0 && x<s->w && y>=0 && y<s->h,1,"outside surface");
    Uint32 p=*(Uint32*)((char*)s->pixels+y*s->pitch+x*4);
    lua_pushinteger(L,(p>>16)&255);lua_pushinteger(L,(p>>8)&255);lua_pushinteger(L,p&255);return 3;
}
static int push_keys(lua_State *L) {
    (void)L;
    SDL_FlushEvents(SDL_EVENT_FIRST,SDL_EVENT_LAST);
    SDL_Event e;SDL_zero(e);e.type=SDL_EVENT_KEY_DOWN;e.key.key=SDLK_A;SDL_PushEvent(&e);
    e.key.key=SDLK_B;SDL_PushEvent(&e);return 0;
}
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    cooloo_text_executable=argv[0];
    if(!SDL_Init(SDL_INIT_VIDEO))return 1;
    SDL_Window *w=SDL_CreateWindow("renderer contract",960,640,SDL_WINDOW_HIDDEN);
    if(!w)return 1;
    ren_init(w);if(font_init(cooloo_embedded_font,cooloo_embedded_font_len))return 1;
    lua_State *L=luaL_newstate();luaL_openlibs(L);
    luaopen_renderer(L);lua_setglobal(L,"native_renderer");
    lua_newtable(L);platform_register(L);lua_getfield(L,-1,"platform");lua_setglobal(L,"native_platform");lua_pop(L,1);
    lua_pushcfunction(L,pixel);lua_setglobal(L,"pixel");
    lua_pushcfunction(L,push_keys);lua_setglobal(L,"push_keys");
    lua_pushcfunction(L,gui_wait_event);lua_setglobal(L,"native_wait_event");
    lua_pushcfunction(L,gui_poll_event);lua_setglobal(L,"native_poll_event");
    int result=luaL_dofile(L,argv[1]);
    if(result)fprintf(stderr,"%s\n",lua_tostring(L,-1));
    lua_close(L);rencache_shutdown();ren_shutdown();SDL_DestroyWindow(w);SDL_Quit();return result?1:0;
}
