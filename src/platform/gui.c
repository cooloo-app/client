/* SDL3 host. Lite renderer/rencache own software drawing and presentation. */
#include "gui.h"
#include "font.h"
#include "luabind.h"
#include "api.h"
#include "renderer.h"
#include "rencache.h"
#include <lua.h>
#include <lauxlib.h>
#ifdef COOLOO_EDITOR_ONLY
#include "embedded_text_icon.h"
#else
#include "embedded_icon.h"
#endif
#define SDL_MAIN_HANDLED
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

extern const unsigned char cooloo_embedded_font[];
extern const unsigned int cooloo_embedded_font_len;
static SDL_Window *win;
static int scr_w = 960, scr_h = 640;
static float pixel_x = 1, pixel_y = 1;

static void update_size(void) {
    if (!win) return; /* standalone event-bridge harness */
    int w,h;
    SDL_GetWindowSize(win,&w,&h);
    ren_get_size(&scr_w,&scr_h);
    pixel_x = w ? (float)scr_w/w : 1;
    pixel_y = h ? (float)scr_h/h : 1;
}
int gui_screen_w(void) { update_size(); return scr_w; }
int gui_screen_h(void) { update_size(); return scr_h; }
void gui_set_ime_rect(int x,int y,int w,int h) {
    SDL_Rect r={(int)(x/pixel_x),(int)(y/pixel_y),SDL_max(1,(int)(w/pixel_x)),SDL_max(1,(int)(h/pixel_y))};
    SDL_SetTextInputArea(win,&r,0);
}
void gui_clear_ime(void) { SDL_ClearComposition(win); }

/* Port of rxi/lite src/api/system.c. SDL owns event strings. */
static const char *button_name(int button) {
    switch(button) { case 1:return "left"; case 2:return "middle"; case 3:return "right"; default:return "?"; }
}
static const char *key_name(char *dst,size_t size,SDL_Keycode key) {
    snprintf(dst,size,"%s",SDL_GetKeyName(key));
    for(char *p=dst;*p;p++)*p=(char)tolower((unsigned char)*p);
    return dst;
}
int gui_wait_event(lua_State *L) {
    double seconds=luaL_optnumber(L,1,0.25);
    luaL_argcheck(L,seconds>=0 && seconds<=2147483,1,"invalid timeout");
    /* SDL's NULL event argument waits without removing/reordering the event. */
    lua_pushboolean(L,SDL_WaitEventTimeout(NULL,(int)(seconds*1000)));
    return 1;
}
int gui_poll_event(lua_State *L) {
    char buf[128];
    SDL_Event e;
top:
    if(!SDL_PollEvent(&e))return 0;
    switch(e.type) {
    case SDL_EVENT_QUIT: lua_pushliteral(L,"quit");return 1;
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        scr_w=e.window.data1;scr_h=e.window.data2;update_size();
        rencache_invalidate();
        lua_pushliteral(L,"resized");lua_pushnumber(L,scr_w);lua_pushnumber(L,scr_h);return 3;
    case SDL_EVENT_WINDOW_EXPOSED:
        rencache_invalidate();lua_pushliteral(L,"exposed");return 1;
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
        SDL_FlushEvent(SDL_EVENT_KEY_DOWN);goto top;
    case SDL_EVENT_WINDOW_FOCUS_LOST:
        lua_pushliteral(L,"focuslost");return 1;
    case SDL_EVENT_DROP_FILE:
        lua_pushliteral(L,"filedropped");lua_pushstring(L,e.drop.data);
        lua_pushnumber(L,e.drop.x*pixel_x);lua_pushnumber(L,e.drop.y*pixel_y);return 4;
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
        lua_pushstring(L,e.type==SDL_EVENT_KEY_DOWN?"keypressed":"keyreleased");
        lua_pushstring(L,key_name(buf,sizeof buf,e.key.key));return 2;
    case SDL_EVENT_TEXT_INPUT:
        lua_pushliteral(L,"textinput");lua_pushstring(L,e.text.text);return 2;
    case SDL_EVENT_TEXT_EDITING:
        lua_pushliteral(L,"textediting");lua_pushstring(L,e.edit.text);
        lua_pushinteger(L,e.edit.start);lua_pushinteger(L,e.edit.length);return 4;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
        if(e.button.button==1)SDL_CaptureMouse(true);
        lua_pushliteral(L,"mousepressed");lua_pushstring(L,button_name(e.button.button));
        lua_pushnumber(L,e.button.x*pixel_x);lua_pushnumber(L,e.button.y*pixel_y);
        lua_pushnumber(L,e.button.clicks);return 5;
    case SDL_EVENT_MOUSE_BUTTON_UP:
        if(e.button.button==1)SDL_CaptureMouse(false);
        lua_pushliteral(L,"mousereleased");lua_pushstring(L,button_name(e.button.button));
        lua_pushnumber(L,e.button.x*pixel_x);lua_pushnumber(L,e.button.y*pixel_y);return 4;
    case SDL_EVENT_MOUSE_MOTION:
        lua_pushliteral(L,"mousemoved");lua_pushnumber(L,e.motion.x*pixel_x);lua_pushnumber(L,e.motion.y*pixel_y);
        lua_pushnumber(L,e.motion.xrel*pixel_x);lua_pushnumber(L,e.motion.yrel*pixel_y);return 5;
    case SDL_EVENT_MOUSE_WHEEL:
        lua_pushliteral(L,"mousewheel");lua_pushnumber(L,e.wheel.integer_y);return 2;
    default:goto top;
    }
}

int cooloo_gui_run(const char *lua_dev_dir) {
    int w=960,h=640,quit=0,result=1;
    SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH,"1");
    SDL_SetHint(SDL_HINT_IME_IMPLEMENTED_UI,"composition");
    SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR,"0");
    if(!SDL_Init(SDL_INIT_VIDEO)){fprintf(stderr,"SDL_Init: %s\n",SDL_GetError());return 1;}
    SDL_EnableScreenSaver();
    w=SDL_max(320,w);h=SDL_max(240,h);
#ifdef COOLOO_EDITOR_ONLY
    const char *title="cooloo-text";
#else
    const char *title="cooloo";
#endif
    win=SDL_CreateWindow(title,w,h,SDL_WINDOW_RESIZABLE|SDL_WINDOW_HIDDEN|SDL_WINDOW_HIGH_PIXEL_DENSITY);
    if(!win){fprintf(stderr,"window: %s\n",SDL_GetError());goto done;}
    SDL_Surface *icon=SDL_CreateSurfaceFrom(COOLOO_ICON_SIZE,COOLOO_ICON_SIZE,SDL_PIXELFORMAT_RGBA32,(void*)cooloo_icon_rgba,COOLOO_ICON_SIZE*4);
    if(icon){SDL_SetWindowIcon(win,icon);SDL_DestroySurface(icon);}
    SDL_SetWindowPosition(win,SDL_WINDOWPOS_CENTERED,SDL_WINDOWPOS_CENTERED);
    ren_init(win);update_size();
    if(font_init(cooloo_embedded_font,cooloo_embedded_font_len)!=0)goto done;
    if(luabind_init(lua_dev_dir)!=0)goto shutdown;
    SDL_StartTextInput(win);
    Uint64 last=SDL_GetTicksNS();
    while(!quit) {
        Uint64 now=SDL_GetTicksNS();
        double dt=(double)(now-last)/1e9;last=now;
        luabind_events_begin();
        luabind_net_pump();
        quit=luabind_frame(dt,(double)now/1e9);
        if(getenv("COOLOO_PROBE_STARTUP")) {
            fprintf(stderr,"cooloo gui: first frame in %llu ms\n",(unsigned long long)((SDL_GetTicksNS()-now)/1000000));break;
        }
        Uint64 elapsed=SDL_GetTicksNS()-now;
        Uint64 period=(Uint64)(platform_frame_period()*1e9);
        if(!quit && elapsed<period)SDL_DelayNS(period-elapsed);
    }
    result=luabind_failed()?1:0;
shutdown:
    if (luabind_failed() && strcmp(SDL_GetCurrentVideoDriver(), "dummy"))
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "cooloo fatal error",
                                 luabind_last_error(), win);
    luabind_shutdown();
    rencache_shutdown();
    ren_shutdown();
done:
    SDL_DestroyWindow(win);win=NULL;
    SDL_Quit();return result;
}
