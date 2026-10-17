/* SDL-only host API: intentionally no config, identity or network includes. */
#ifndef _WIN32
#define _XOPEN_SOURCE 700
#endif
#include "api.h"
#include <lauxlib.h>
#include <SDL3/SDL.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#else
#include <unistd.h>
#endif
static double fps = 60;
double platform_frame_period(void) { return 1.0 / fps; }
static int set_fps(lua_State *L) {
    double value=luaL_checknumber(L,1);
    if(value>=1 && value<=1000)fps=value;
    else return luaL_error(L,"config.fps must be between 1 and 1000");
    return 0;
}
#ifdef _WIN32
static wchar_t *wide(lua_State *L,const char *s) {
    int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,NULL,0);
    if(!n){luaL_error(L,"invalid UTF-8 path");return NULL;}
    wchar_t *p=malloc((size_t)n*sizeof *p);
    if(!p){luaL_error(L,"out of memory");return NULL;}
    MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,p,n);return p;
}
static void push_wide(lua_State *L,const wchar_t *s) {
    int n=WideCharToMultiByte(CP_UTF8,0,s,-1,NULL,0,NULL,NULL);
    char *p=malloc((size_t)n);
    if(!p){luaL_error(L,"out of memory");return;}
    WideCharToMultiByte(CP_UTF8,0,s,-1,p,n,NULL,NULL);lua_pushstring(L,p);free(p);
}
#endif
static int chdir_api(lua_State *L) {
#ifdef _WIN32
    wchar_t *p=wide(L,luaL_checkstring(L,1));int rc=_wchdir(p);free(p);
#else
    int rc=chdir(luaL_checkstring(L,1));
#endif
    if(rc)return luaL_error(L,"chdir failed: %s",lua_tostring(L,1));
    return 0;
}
static int sleep_api(lua_State *L) {
    double seconds=luaL_checknumber(L,1);
    if(seconds>0)SDL_DelayNS((Uint64)(seconds*1e9));
    return 0;
}
/* Detached OS process, not the workbench execution/console runtime. */
static int spawn(lua_State *L,const char *const *args) {
    SDL_PropertiesID props=SDL_CreateProperties();
    SDL_SetPointerProperty(props,SDL_PROP_PROCESS_CREATE_ARGS_POINTER,(void *)args);
    SDL_SetBooleanProperty(props,SDL_PROP_PROCESS_CREATE_BACKGROUND_BOOLEAN,true);
    SDL_Process *p=SDL_CreateProcessWithProperties(props);
    SDL_DestroyProperties(props);
    if(!p)return luaL_error(L,"process launch failed: %s",SDL_GetError());
    SDL_DestroyProcess(p);return 0;
}
static int exec_api(lua_State *L) {
#ifdef _WIN32
    const char *args[]={"cmd.exe","/c",luaL_checkstring(L,1),NULL};
#else
    const char *args[]={"/bin/sh","-c",luaL_checkstring(L,1),NULL};
#endif
    return spawn(L,args);
}
static int open_project(lua_State *L) {
#ifdef COOLOO_EDITOR_ONLY
    const char *path=luaL_checkstring(L,1);
    int safe=lua_toboolean(L,2);
    /* argv avoids shell quoting/injection, including spaces and metacharacters. */
    lua_getglobal(L,"cooloo");lua_getfield(L,-1,"platform");lua_getfield(L,-1,"exefile");
    const char *args[]={lua_tostring(L,-1),NULL,NULL,NULL,NULL};
    int n=1;if(safe)args[n++]="--safe-mode";
    args[n++]="--";args[n++]=path;
    return spawn(L,args);
#else
    return luaL_error(L,"directory projects require cooloo-text");
#endif
}
static SDL_Window *window(void) {
    SDL_Window *focused=SDL_GetKeyboardFocus();
    if(focused)return focused;
    int count=0;SDL_Window **windows=SDL_GetWindows(&count);
    SDL_Window *first=count?windows[0]:NULL;SDL_free(windows);return first;
}
static int focus(lua_State *L) { lua_pushboolean(L,SDL_GetKeyboardFocus()!=NULL); return 1; }
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
#ifdef _WIN32
    wchar_t *w=wide(L,p), *full=_wfullpath(NULL,w,0);free(w);
    if(!full)return luaL_error(L,"cannot resolve path: %s",p);
    push_wide(L,full);free(full);
#else
    char *resolved=realpath(p,NULL);
    if(resolved){lua_pushstring(L,resolved);free(resolved);}
    else if(p[0]=='/')lua_pushstring(L,p);
    else {char *cwd=SDL_GetCurrentDirectory();lua_pushfstring(L,"%s%s",cwd?cwd:"",p);SDL_free(cwd);}
#endif
    return 1;
}
void platform_register(lua_State *L) {
    static const luaL_Reg f[]={{"focus",focus},{"title",title},{"mode",mode},{"cursor",cursor},{"confirm",confirm},{"list_dir",list},{"info",info},{"absolute_path",absolute},{"chdir",chdir_api},{"exec",exec_api},{"open_project",open_project},{"sleep",sleep_api},{"set_fps",set_fps},{NULL,NULL}};
    luaL_newlib(L,f);
    const char *base=SDL_GetBasePath();
    lua_pushstring(L,base?base:".");lua_setfield(L,-2,"exedir");
#ifdef COOLOO_EDITOR_ONLY
    extern const char *cooloo_text_executable;
#ifdef _WIN32
    wchar_t path[32768];
    DWORD n=GetModuleFileNameW(NULL,path,32768);
    if(!n || n>=32768)luaL_error(L,"cannot resolve executable path");
    push_wide(L,path);
#else
    const char *name=strrchr(cooloo_text_executable,'/');
    lua_pushfstring(L,"%s%s",base?base:"",name?name+1:cooloo_text_executable);
#endif
#else
    lua_pushliteral(L,"");
#endif
    lua_setfield(L,-2,"exefile");
    const char *user=SDL_getenv("COOLOO_TEXT_USERDIR");
    if(user && *user) {
        lua_pushcfunction(L,absolute);lua_pushstring(L,user);lua_call(L,1,1);
    } else {
        const char *home=SDL_GetUserFolder(SDL_FOLDER_HOME);
        lua_pushfstring(L,"%s.cooloo-text",home?home:"./");
    }
    lua_setfield(L,-2,"userdir");
    lua_setfield(L,-2,"platform");
}
