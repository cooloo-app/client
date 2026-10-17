/* Test-only SDL_PushEvent binding. Production has no event injection API.
 * Links the same gui.c / Lua core as cooloo-text; draws use a test renderer. */
#define SDL_MAIN_HANDLED
#include <SDL3/SDL.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <string.h>
#include "gui.h"
#include "renderer_api.h"
#include "renderer.h"
#include "rencache.h"
#include "font.h"
#include "api.h"
extern const unsigned char cooloo_embedded_font[];
extern const unsigned int cooloo_embedded_font_len;

int cooloo_text_file_count, cooloo_text_safe_mode, cooloo_text_argc;
char **cooloo_text_files, **cooloo_text_argv;
const char *cooloo_text_executable;

static int push_event(lua_State *L)
{
    SDL_Event e;
    SDL_zero(e);
    const char *kind = luaL_checkstring(L, 1);
    if (!strcmp(kind, "keypressed") || !strcmp(kind, "keyreleased")) {
        e.type = !strcmp(kind, "keypressed") ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
        e.key.key = SDL_GetKeyFromName(luaL_checkstring(L, 2));
        luaL_argcheck(L, e.key.key != SDLK_UNKNOWN, 2, "unknown SDL key name");
    } else if (!strcmp(kind, "textinput")) {
        e.type = SDL_EVENT_TEXT_INPUT;
        e.text.text = luaL_checkstring(L, 2);
    } else if (!strcmp(kind, "textediting")) {
        e.type = SDL_EVENT_TEXT_EDITING;
        e.edit.text = luaL_checkstring(L, 2);
        e.edit.start = (int)luaL_checkinteger(L, 3);
        e.edit.length = (int)luaL_checkinteger(L, 4);
    } else if (!strcmp(kind, "mousepressed") || !strcmp(kind, "mousereleased")) {
        e.type = !strcmp(kind, "mousepressed") ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
        e.button.button = (Uint8)luaL_checkinteger(L, 2);
        e.button.x = (float)luaL_checknumber(L, 3);
        e.button.y = (float)luaL_checknumber(L, 4);
        e.button.clicks = (Uint8)luaL_optinteger(L, 5, 1);
    } else if (!strcmp(kind, "mousemoved")) {
        e.type = SDL_EVENT_MOUSE_MOTION;
        e.motion.x = (float)luaL_checknumber(L, 2);
        e.motion.y = (float)luaL_checknumber(L, 3);
        e.motion.xrel = (float)luaL_checknumber(L, 4);
        e.motion.yrel = (float)luaL_checknumber(L, 5);
    } else if (!strcmp(kind, "mousewheel")) {
        e.type = SDL_EVENT_MOUSE_WHEEL;
        e.wheel.integer_y = (int)luaL_checkinteger(L, 2);
    } else if (!strcmp(kind, "resized")) {
        e.type = SDL_EVENT_WINDOW_RESIZED;
        e.window.data1 = (int)luaL_checkinteger(L, 2);
        e.window.data2 = (int)luaL_checkinteger(L, 3);
    } else if (!strcmp(kind, "exposed")) {
        e.type = SDL_EVENT_WINDOW_EXPOSED;
    } else if (!strcmp(kind, "focuslost")) {
        e.type = SDL_EVENT_WINDOW_FOCUS_LOST;
    } else if (!strcmp(kind, "focusgained")) {
        e.type = SDL_EVENT_WINDOW_FOCUS_GAINED;
    } else if (!strcmp(kind, "filedropped")) {
        e.type = SDL_EVENT_DROP_FILE;
        e.drop.data = luaL_checkstring(L, 2);
        e.drop.x = (float)luaL_checknumber(L, 3);
        e.drop.y = (float)luaL_checknumber(L, 4);
    } else if (!strcmp(kind, "quit")) {
        e.type = SDL_EVENT_QUIT;
    } else {
        return luaL_error(L, "unknown test event: %s", kind);
    }
    if (!SDL_PushEvent(&e)) return luaL_error(L, "SDL_PushEvent: %s", SDL_GetError());
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    cooloo_text_executable = argv[0];
    if (!SDL_Init(SDL_INIT_VIDEO)) return 1;
    SDL_Window *window = SDL_CreateWindow("event bridge test", 960, 640, SDL_WINDOW_HIDDEN);
    if (!window) return 1;
    SDL_FlushEvents(SDL_EVENT_FIRST, SDL_EVENT_LAST);
    ren_init(window);
    if(font_init(cooloo_embedded_font,cooloo_embedded_font_len))return 1;
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    luaopen_renderer(L);lua_setglobal(L,"native_renderer");
    lua_newtable(L);platform_register(L);lua_getfield(L,-1,"platform");lua_setglobal(L,"native_platform");lua_pop(L,1);
    lua_pushcfunction(L, push_event); lua_setglobal(L, "push_event");
    lua_pushcfunction(L, gui_poll_event); lua_setglobal(L, "native_poll_event");
    int failed = luaL_dofile(L, argv[1]);
    if (failed) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    lua_close(L);
    rencache_shutdown();ren_shutdown();
    SDL_DestroyWindow(window);
    SDL_Quit();
    return failed ? 1 : 0;
}
