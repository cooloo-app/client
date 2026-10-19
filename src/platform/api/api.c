/* SDL-only host API: intentionally no config, identity or network includes. */
#ifndef _WIN32
#define _XOPEN_SOURCE 700
#endif
#include "api.h"
#include "file.h"
#include <lauxlib.h>
#include <SDL3/SDL.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>
#ifdef _WIN32
#define COBJMACROS
#include <windows.h>
#include <shobjidl.h>
#include <direct.h>
#else
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#include <objc/message.h>
#include <objc/runtime.h>
#endif
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
static int focus(lua_State *L) {
    SDL_Window *w=window();
    lua_pushboolean(L,w && (SDL_GetWindowFlags(w)&SDL_WINDOW_INPUT_FOCUS) &&
        !(SDL_GetWindowFlags(w)&SDL_WINDOW_MINIMIZED));return 1;
}
/* Policy is supplied by Lua. Native code only displays its aggregate. */
static int set_unread(lua_State *L) {
    int unread=luaL_checkinteger(L,1)>0;
    SDL_Window *w=window();
    if(!w)return 0;
#ifdef _WIN32
    HWND hwnd=SDL_GetPointerProperty(SDL_GetWindowProperties(w),SDL_PROP_WINDOW_WIN32_HWND_POINTER,NULL);
    HRESULT initialized=CoInitializeEx(NULL,COINIT_APARTMENTTHREADED);
    ITaskbarList3 *taskbar=NULL;
    if(hwnd && SUCCEEDED(CoCreateInstance(&CLSID_TaskbarList,NULL,CLSCTX_INPROC_SERVER,
            &IID_ITaskbarList3,(void **)&taskbar))) {
        if(SUCCEEDED(ITaskbarList3_HrInit(taskbar))) {
            HICON icon=NULL;
            if(unread) {
                BITMAPINFO info;memset(&info,0,sizeof info);
                info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
                info.bmiHeader.biWidth=16;info.bmiHeader.biHeight=-16;
                info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;
                void *pixels=NULL;
                HBITMAP color=CreateDIBSection(NULL,&info,DIB_RGB_COLORS,&pixels,NULL,0);
                BYTE maskbits[32]={0};HBITMAP mask=CreateBitmap(16,16,1,1,maskbits);
                if(color && mask && pixels) {
                    Uint32 *p=pixels;
                    for(int y=0;y<16;y++)for(int x=0;x<16;x++)
                        p[y*16+x]=((x-8)*(x-8)+(y-8)*(y-8)<=49)?0xfff05a5a:0;
                    ICONINFO ii={TRUE,0,0,mask,color};icon=CreateIconIndirect(&ii);
                }
                if(color)DeleteObject(color);
                if(mask)DeleteObject(mask);
            }
            ITaskbarList3_SetOverlayIcon(taskbar,hwnd,icon,unread?L"Unread messages":L"");
            if(icon)DestroyIcon(icon);
        }
        ITaskbarList3_Release(taskbar);
    }
    if(SUCCEEDED(initialized))CoUninitialize();
#elif defined(__APPLE__)
    id app=((id(*)(id,SEL))objc_msgSend)((id)objc_getClass("NSApplication"),sel_registerName("sharedApplication"));
    id dock=((id(*)(id,SEL))objc_msgSend)(app,sel_registerName("dockTile"));
    id label=unread?((id(*)(id,SEL,const char *))objc_msgSend)((id)objc_getClass("NSString"),
        sel_registerName("stringWithUTF8String:"),"●"):NULL;
    ((void(*)(id,SEL,id))objc_msgSend)(dock,sel_registerName("setBadgeLabel:"),label);
#endif
    if(!unread)SDL_FlashWindow(w,SDL_FLASH_CANCEL);
    else if(lua_toboolean(L,2))SDL_FlashWindow(w,SDL_FLASH_BRIEFLY);
    return 0;
}
static int title(lua_State *L) { if(window())SDL_SetWindowTitle(window(),luaL_checkstring(L,1)); return 0; }
static int mode(lua_State *L) {
    SDL_Window *w = window();
    const char *name = luaL_optstring(L,1,"normal");
    if (strcmp(name,"normal") && strcmp(name,"maximized") && strcmp(name,"fullscreen"))
        return luaL_error(L,"unknown window mode: %s",name);
    if (!w) return 0;
    if (!strcmp(name, "fullscreen")) SDL_SetWindowFullscreen(w, true);
    else if (!strcmp(name, "maximized")) { SDL_SetWindowFullscreen(w, false); SDL_MaximizeWindow(w); }
    else if (!strcmp(name, "normal")) { SDL_SetWindowFullscreen(w, false); SDL_RestoreWindow(w); }
    else return luaL_error(L, "unknown window mode: %s", name);
    return 0;
}
static int cursor(lua_State *L) {
    static SDL_Cursor *c[5];
    const char *s=luaL_optstring(L,1,"arrow");
    int i=!strcmp(s,"arrow")?0:!strcmp(s,"ibeam")?1:!strcmp(s,"sizeh")?2:!strcmp(s,"sizev")?3:!strcmp(s,"hand")?4:-1;
    SDL_SystemCursor ids[]={SDL_SYSTEM_CURSOR_DEFAULT,SDL_SYSTEM_CURSOR_TEXT,SDL_SYSTEM_CURSOR_EW_RESIZE,SDL_SYSTEM_CURSOR_NS_RESIZE,SDL_SYSTEM_CURSOR_POINTER};
    if (i < 0) return luaL_error(L, "unknown cursor: %s", s);
    if(!c[i])c[i]=SDL_CreateSystemCursor(ids[i]);
    if(c[i])SDL_SetCursor(c[i]);
    return 0;
}
static int confirm(lua_State *L) {
    SDL_MessageBoxButtonData buttons[]={{SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT,0,"No"},{SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT,1,"Yes"}};
    SDL_MessageBoxData d={SDL_MESSAGEBOX_WARNING,window(),luaL_checkstring(L,1),luaL_checkstring(L,2),2,buttons,NULL};
    int result=0; SDL_ShowMessageBox(&d,&result); lua_pushboolean(L,result==1);return 1;
}
static SDL_EnumerationResult entry(void *ctx,const char *dir,const char *name) {
    lua_State *L=ctx;(void)dir;lua_pushstring(L,name);lua_rawseti(L,-2,(lua_Integer)lua_rawlen(L,-2)+1);return SDL_ENUM_CONTINUE;
}
static int list(lua_State *L) { const char *p=luaL_checkstring(L,1);lua_newtable(L);if (!SDL_EnumerateDirectory(p,entry,L)) { lua_pop(L,1); lua_pushnil(L); lua_pushstring(L,SDL_GetError()); return 2; } return 1; }
static int info(lua_State *L) {
    const char *path=luaL_checkstring(L,1);
    /* A third result distinguishes missing paths from access/I/O failures. */
#ifdef _WIN32
    wchar_t *w=wide(L,path);
    DWORD attrs=GetFileAttributesW(w), error=GetLastError();free(w);
    if(attrs==INVALID_FILE_ATTRIBUTES) {
        lua_pushnil(L);lua_pushfstring(L,"path lookup failed (%d): %s",(int)error,path);
        lua_pushboolean(L,error==ERROR_FILE_NOT_FOUND || error==ERROR_PATH_NOT_FOUND);return 3;
    }
#else
    struct stat st;
    if(stat(path,&st)) {
        int error=errno;
        struct stat link;
        int missing=error==ENOENT && lstat(path,&link)!=0 && errno==ENOENT;
        lua_pushnil(L);lua_pushstring(L,strerror(error));lua_pushboolean(L,missing);return 3;
    }
#endif
    SDL_PathInfo i;if(!SDL_GetPathInfo(path,&i)){lua_pushnil(L);lua_pushstring(L,SDL_GetError());return 2;}
    lua_newtable(L);lua_pushstring(L,i.type==SDL_PATHTYPE_DIRECTORY?"dir":i.type==SDL_PATHTYPE_FILE?"file":NULL);lua_setfield(L,-2,"type");
    lua_pushinteger(L,(lua_Integer)i.size);lua_setfield(L,-2,"size");
    lua_pushnumber(L,(lua_Number)i.modify_time/1e9);lua_setfield(L,-2,"modified");return 1;
}
static int absolute(lua_State *L);
static int resolve_path(lua_State *L) {
    const char *p=luaL_checkstring(L,1);
#ifdef _WIN32
    wchar_t *w=wide(L,p);
    /* Check raw prefixes before _wfullpath can erase an invalid ancestor/.. . */
    wchar_t *root=w;
    if(w[0]==L'\\' && w[1]==L'\\') {
        if(!wcsncmp(w,L"\\\\?\\",4) && wcslen(w)>=7 && w[5]==L':') root=w+7;
        else {
            root=!wcsncmp(w,L"\\\\?\\UNC\\",8)?w+8:w+2;
            /* UNC server and share together form the root, not ancestors. */
            for(int n=0;n<2 && *root;n++) {
                while(*root && *root!=L'\\' && *root!=L'/') root++;
                if(*root)root++;
            }
        }
    }
    for (wchar_t *end=root; *end; end++) {
        if ((*end!=L'/' && *end!=L'\\') || end==w || end[-1]==L':') continue;
        wchar_t separator=*end; *end=0;
        DWORD attrs=GetFileAttributesW(w);
        if (attrs!=INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) {
            HANDLE h=CreateFileW(w,0,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
                NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,NULL);
            if(h==INVALID_HANDLE_VALUE){free(w);lua_pushnil(L);lua_pushliteral(L,"invalid reparse ancestor");return 2;}
            CloseHandle(h);
        } else if (attrs!=INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
            free(w);lua_pushnil(L);lua_pushliteral(L,"not a directory ancestor");return 2;
        } else if (attrs==INVALID_FILE_ATTRIBUTES && GetLastError()!=ERROR_FILE_NOT_FOUND
                   && GetLastError()!=ERROR_PATH_NOT_FOUND) {
            free(w);lua_pushnil(L);lua_pushliteral(L,"inaccessible ancestor");return 2;
        }
        *end=separator;
    }
    free(w);
    int results=absolute(L);
    if(!lua_isnil(L,-results))return results;
    DWORD error=(DWORD)lua_tointeger(L,-1);
    if(error!=ERROR_FILE_NOT_FOUND && error!=ERROR_PATH_NOT_FOUND)return results;
    lua_pop(L,results);
    w=wide(L,p);
    wchar_t *full=_wfullpath(NULL,w,0);free(w);
    if(!full)return luaL_error(L,"cannot resolve path: %s",p);
    push_wide(L,full);free(full);
#else
    char *resolved=realpath(p,NULL);
    if(resolved){lua_pushstring(L,resolved);free(resolved);}
    else {
        if(errno!=ENOENT){lua_pushnil(L);lua_pushstring(L,strerror(errno));return 2;}
        char *cwd=SDL_GetCurrentDirectory();
        size_t length=strlen(p)+(cwd?strlen(cwd):0)+2;
        char *path=malloc(length),*out=calloc(length,1);
        if(!path || !out){free(path);free(out);SDL_free(cwd);return luaL_error(L,"out of memory");}
        snprintf(path,length,"%s%s",p[0]=='/'?"":(cwd?cwd:""),p);
        SDL_free(cwd);
        strcpy(out,"/");
        char *save=NULL;
        for(char *part=strtok_r(path,"/",&save);part;part=strtok_r(NULL,"/",&save)) {
            if(!strcmp(part,"."))continue;
            if(!strcmp(part,"..")) {
                char *slash=strrchr(out,'/');
                if(slash==out)out[1]=0;else if(slash)*slash=0;
            } else {
                if(strlen(out)>1)strcat(out,"/");
                strcat(out,part);
                char *canonical=realpath(out,NULL);
                if(canonical) {
                    size_t need=strlen(canonical)+strlen(p)+2;
                    if(need>length){char *grown=realloc(out,need);if(!grown){free(canonical);free(out);free(path);return luaL_error(L,"out of memory");}out=grown;length=need;}
                    strcpy(out,canonical);free(canonical);
                } else {
                    int error=errno;
                    struct stat entry;
                    int present=lstat(out,&entry)==0;
                    if(error!=ENOENT || (present && S_ISLNK(entry.st_mode))) {
                        free(out);free(path);lua_pushnil(L);
                        lua_pushstring(L,error==ENOENT?"dangling symlink ancestor":strerror(error));return 2;
                    }
                }
            }
        }
        lua_pushstring(L,out);free(out);free(path);
    }
#endif
    return 1;
}
static int absolute(lua_State *L) {
    const char *p=luaL_checkstring(L,1);
#ifdef _WIN32
    wchar_t *w=wide(L,p);
    HANDLE h=CreateFileW(w,0,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,NULL);
    DWORD error=GetLastError();free(w);
    if(h==INVALID_HANDLE_VALUE){lua_pushnil(L);lua_pushfstring(L,"cannot open path (%d)",(int)error);lua_pushinteger(L,error);return 3;}
    DWORD n=GetFinalPathNameByHandleW(h,NULL,0,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    wchar_t *full=malloc(((size_t)n+1)*sizeof *full);
    if(!full){CloseHandle(h);return luaL_error(L,"out of memory");}
    DWORD got=GetFinalPathNameByHandleW(h,full,n+1,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    CloseHandle(h);
    if(!got || got>n){free(full);lua_pushnil(L);lua_pushliteral(L,"cannot resolve path");return 2;}
    /* Preserve extended UNC paths; strip the ordinary drive prefix. */
    push_wide(L,!wcsncmp(full,L"\\\\?\\",4) && full[5]==L':'?full+4:full);
    free(full);
#else
    char *resolved=realpath(p,NULL);
    if(!resolved){lua_pushnil(L);lua_pushstring(L,strerror(errno));return 2;}
    lua_pushstring(L,resolved);free(resolved);
#endif
    return 1;
}

/* rxi/lite system.c; unsigned char avoids ctype UB, and the terminal-space
 * guard avoids the upstream one-past-NUL read. Scores otherwise unchanged. */
static int fuzzy_match(lua_State *L) {
    const unsigned char *str=(const unsigned char *)luaL_checkstring(L,1);
    const unsigned char *ptn=(const unsigned char *)luaL_checkstring(L,2);
    int score=0,run=0;
    while(*str && *ptn) {
        while(*str==' ')str++;
        while(*ptn==' ')ptn++;
        if(!*str || !*ptn)break;
        if(tolower(*str)==tolower(*ptn)){score+=run*10-(*str!=*ptn);run++;ptn++;}
        else {score-=10;run=0;}
        str++;
    }
    if(*ptn)return 0;
    lua_pushinteger(L,score-(int)strlen((const char *)str));return 1;
}
/* Reserve the exact name exclusively; Lua records only successfully owned files. */
static int temp_file(lua_State *L) {
    const char *dir=luaL_checkstring(L,1), *ext=luaL_optstring(L,2,"");
    if(strchr(ext,'/') || strchr(ext,'\\'))return luaL_error(L,"invalid temporary extension");
    static unsigned long counter;
#ifdef _WIN32
    unsigned long pid=GetCurrentProcessId();
#else
    unsigned long pid=(unsigned long)getpid();
#endif
    for(int attempt=0;attempt<10000;attempt++) {
        lua_pushfstring(L,"%s/.lite_temp_%I_%I%s",dir,(lua_Integer)pid,(lua_Integer)++counter,ext);
        const char *path=lua_tostring(L,-1);
#ifdef _WIN32
        wchar_t *w=wide(L,path);
        HANDLE h=CreateFileW(w,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
        DWORD error=GetLastError();free(w);
        if(h!=INVALID_HANDLE_VALUE){CloseHandle(h);return 1;}
        if(error!=ERROR_FILE_EXISTS && error!=ERROR_ALREADY_EXISTS)
            return luaL_error(L,"cannot reserve temporary file (%d)",(int)error);
#else
        int fd=open(path,O_WRONLY|O_CREAT|O_EXCL,0600);
        if(fd>=0){close(fd);return 1;}
        if(errno!=EEXIST)return luaL_error(L,"cannot reserve temporary file: %s",strerror(errno));
#endif
        lua_pop(L,1);
    }
    return luaL_error(L,"temporary filename attempts exhausted");
}

void platform_register(lua_State *L) {
    static const luaL_Reg f[]={{"write_file",platform_write_file},{"temp_file",temp_file},{"focus",focus},{"set_unread",set_unread},{"title",title},{"mode",mode},{"cursor",cursor},{"confirm",confirm},{"list_dir",list},{"info",info},{"absolute_path",absolute},{"resolve_path",resolve_path},{"fuzzy_match",fuzzy_match},{"chdir",chdir_api},{"exec",exec_api},{"open_project",open_project},{"sleep",sleep_api},{"set_fps",set_fps},{NULL,NULL}};
    luaL_newlib(L,f);
    lua_pushstring(L,SDL_GetPlatform());lua_setfield(L,-2,"name");
    float scale=window()?SDL_GetWindowDisplayScale(window()):SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
    const char *scale_env=SDL_getenv("LITE_SCALE");
    if(scale_env) {
        char *end;
        double requested=strtod(scale_env,&end);
        while(isspace((unsigned char)*end))end++;
        if(end!=scale_env && !*end && isfinite(requested) && requested>0)
            scale=(float)requested;
    }
    if(!isfinite(scale) || scale<=0)scale=1;
    lua_pushnumber(L,scale);lua_setfield(L,-2,"scale");
    const char *base=SDL_GetBasePath();
    lua_pushstring(L,base?base:".");lua_setfield(L,-2,"exedir");
#ifdef COOLOO_EDITOR_ONLY
#ifdef _WIN32
    wchar_t path[32768];
    DWORD n=GetModuleFileNameW(NULL,path,32768);
    if(!n || n>=32768)luaL_error(L,"cannot resolve executable path");
    push_wide(L,path);
#elif defined(__APPLE__)
    uint32_t size=0;
    _NSGetExecutablePath(NULL,&size);
    char *path=malloc(size);
    if(!path || _NSGetExecutablePath(path,&size)) {free(path);luaL_error(L,"cannot resolve executable path");}
    char *resolved=realpath(path,NULL);free(path);
    if(!resolved)luaL_error(L,"cannot resolve executable path");
    lua_pushstring(L,resolved);free(resolved);
#else
    char path[4096];
    ssize_t n=readlink("/proc/self/exe",path,sizeof(path)-1);
    if(n<0 || n>=(ssize_t)sizeof(path)-1)luaL_error(L,"cannot resolve executable path");
    path[n]=0;lua_pushstring(L,path);
#endif
#else
    lua_pushliteral(L,"");
#endif
    lua_setfield(L,-2,"exefile");
    const char *user=SDL_getenv("COOLOO_TEXT_USERDIR");
    if(user && *user) {
        lua_pushcfunction(L,resolve_path);lua_pushstring(L,user);lua_call(L,1,1);
    } else {
        const char *home=SDL_GetUserFolder(SDL_FOLDER_HOME);
        lua_pushfstring(L,"%s.cooloo-text",home?home:"./");
    }
    lua_setfield(L,-2,"userdir");
    lua_setfield(L,-2,"platform");
}
