/* SDL-only host API: intentionally no config, identity or network includes. */
#include "api.h"
#include <lauxlib.h>
#include <SDL3/SDL.h>
#include <string.h>
#include <stdio.h>
static SDL_Window *window(void) { return SDL_GetKeyboardFocus(); }
static int focus(lua_State *L) { lua_pushboolean(L,window()!=NULL); return 1; }
static int title(lua_State *L) { if(window())SDL_SetWindowTitle(window(),luaL_checkstring(L,1)); return 0; }
static int mode(lua_State *L) { if(window())SDL_SetWindowFullscreen(window(),!strcmp(luaL_checkstring(L,1),"fullscreen")); return 0; }
static int cursor(lua_State *L) {
    static SDL_Cursor *c[4];
    const char *s=luaL_checkstring(L,1);
    int i=!strcmp(s,"ibeam")?1:!strcmp(s,"sizeh")?2:!strcmp(s,"sizev")?3:0;
    SDL_SystemCursor ids[]={SDL_SYSTEM_CURSOR_DEFAULT,SDL_SYSTEM_CURSOR_TEXT,SDL_SYSTEM_CURSOR_EW_RESIZE,SDL_SYSTEM_CURSOR_NS_RESIZE};
    if(!c[i])c[i]=SDL_CreateSystemCursor(ids[i]);
    if(c[i])SDL_SetCursor(c[i]);
    return 0;
}
static int confirm(lua_State *L) {
    SDL_MessageBoxButtonData buttons[]={{SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT,0,"Cancel"},{0,1,"Discard"}};
    SDL_MessageBoxData d={SDL_MESSAGEBOX_WARNING,window(),luaL_checkstring(L,1),luaL_checkstring(L,2),2,buttons,NULL};
    int result=0; SDL_ShowMessageBox(&d,&result); lua_pushboolean(L,result==1);return 1;
}
static SDL_EnumerationResult entry(void *ctx,const char *dir,const char *name) {
    lua_State *L=ctx;(void)dir;lua_pushstring(L,name);lua_rawseti(L,-2,(lua_Integer)lua_rawlen(L,-2)+1);return SDL_ENUM_CONTINUE;
}
static int list(lua_State *L) { const char *p=luaL_checkstring(L,1);lua_newtable(L);SDL_EnumerateDirectory(p,entry,L);return 1; }
static int info(lua_State *L) {
    SDL_PathInfo i;if(!SDL_GetPathInfo(luaL_checkstring(L,1),&i)){lua_pushnil(L);return 1;}
    lua_newtable(L);lua_pushstring(L,i.type==SDL_PATHTYPE_DIRECTORY?"dir":"file");lua_setfield(L,-2,"type");
    lua_pushinteger(L,(lua_Integer)i.size);lua_setfield(L,-2,"size");
    lua_pushnumber(L,(lua_Number)i.modify_time/1e9);lua_setfield(L,-2,"modified");return 1;
}
static int absolute(lua_State *L) {
    const char *p=luaL_checkstring(L,1);
    if(p[0]=='/' || p[0]=='\\' || (p[0] && p[1]==':'))lua_pushstring(L,p);
    else {char *cwd=SDL_GetCurrentDirectory();lua_pushfstring(L,"%s%s",cwd?cwd:"",p);SDL_free(cwd);}return 1;
}
void platform_register(lua_State *L) {
    static const luaL_Reg f[]={{"focus",focus},{"title",title},{"mode",mode},{"cursor",cursor},{"confirm",confirm},{"list_dir",list},{"info",info},{"absolute_path",absolute},{NULL,NULL}};
    luaL_newlib(L,f);lua_setfield(L,-2,"platform");
}
