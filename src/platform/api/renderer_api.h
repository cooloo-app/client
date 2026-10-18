#ifndef COOLOO_RENDERER_API_H
#define COOLOO_RENDERER_API_H
#include <lua.h>
#include <lauxlib.h>
#define API_TYPE_FONT "RenFont"
#include "renderer.h"
static inline RenFont *renderer_check_font(lua_State *L, int index) {
    RenFont **font = luaL_checkudata(L, index, API_TYPE_FONT);
    luaL_argcheck(L, *font != NULL, index, "closed font");
    return *font;
}
int luaopen_renderer(lua_State *L);
#endif
