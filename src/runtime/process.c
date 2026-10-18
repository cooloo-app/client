#include "runtime.h"
#include <lauxlib.h>
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
/* One file task and one persistent console. No shell command interpolation. */
static SDL_Process *tasks[2];
static int console_task[2];
static char pending[2][4160];
static size_t pending_len[2], pending_pos[2];
static int slot(lua_State *L) {int n=(int)luaL_checkinteger(L,1);luaL_argcheck(L,n>=1&&n<=2,1,"task slot must be 1 or 2");return n-1;}
static void stop(int i) {pending_len[i]=pending_pos[i]=0;if(tasks[i]){SDL_KillProcess(tasks[i],true);SDL_WaitProcess(tasks[i],true,NULL);SDL_DestroyProcess(tasks[i]);tasks[i]=NULL;}}
static int start(lua_State *L) {
    int i=slot(L);const char *file=luaL_optstring(L,2,NULL);SDL_PropertiesID props;
    const char *exe=SDL_GetEnvironmentVariable(SDL_GetEnvironment(),"COOLOO_EXECUTABLE");
    const char *args[]={exe,file?"--lua-run":"--lua-console",file,NULL};
    if(!exe)return luaL_error(L,"executable path not initialized");
    stop(i);props=SDL_CreateProperties();
    SDL_SetPointerProperty(props,SDL_PROP_PROCESS_CREATE_ARGS_POINTER,(void *)args);
    SDL_SetNumberProperty(props,SDL_PROP_PROCESS_CREATE_STDIN_NUMBER,file?SDL_PROCESS_STDIO_NULL:SDL_PROCESS_STDIO_APP);
    SDL_SetNumberProperty(props,SDL_PROP_PROCESS_CREATE_STDOUT_NUMBER,SDL_PROCESS_STDIO_APP);
    SDL_SetNumberProperty(props,SDL_PROP_PROCESS_CREATE_STDERR_NUMBER,SDL_PROCESS_STDIO_APP);
    tasks[i]=SDL_CreateProcessWithProperties(props);SDL_DestroyProperties(props);
    console_task[i]=file==NULL;
    lua_pushboolean(L,tasks[i]!=NULL);if(!tasks[i]){lua_pushstring(L,SDL_GetError());return 2;}return 1;
}
static int poll(lua_State *L) {
    int i=slot(L),status;char buf[8192];size_t n;SDL_PropertiesID props;
    lua_newtable(L);if(!tasks[i])return 1;
    if(pending_pos[i]<pending_len[i]) {
        SDL_IOStream *in=SDL_GetProcessInput(tasks[i]);
        size_t wrote=in?SDL_WriteIO(in,pending[i]+pending_pos[i],pending_len[i]-pending_pos[i]):0;
        pending_pos[i]+=wrote;
        if(!in || (SDL_GetIOStatus(in)!=SDL_IO_STATUS_READY && SDL_GetIOStatus(in)!=SDL_IO_STATUS_NOT_READY)){
            lua_pushstring(L,SDL_GetError());lua_setfield(L,-2,"input_error");
            pending_len[i]=pending_pos[i]=0;
        }
    }
    props=SDL_GetProcessProperties(tasks[i]);
    SDL_IOStream *out=SDL_GetProcessOutput(tasks[i]);
    SDL_IOStream *err=SDL_GetPointerProperty(props,SDL_PROP_PROCESS_STDERR_POINTER,NULL);
    n=out?SDL_ReadIO(out,buf,sizeof buf):0;lua_pushlstring(L,buf,n);lua_setfield(L,-2,"stdout");
    n=err?SDL_ReadIO(err,buf,sizeof buf):0;lua_pushlstring(L,buf,n);lua_setfield(L,-2,"stderr");
    if((out && SDL_GetIOStatus(out)==SDL_IO_STATUS_ERROR) || (err && SDL_GetIOStatus(err)==SDL_IO_STATUS_ERROR)) {
        lua_pushstring(L,SDL_GetError());lua_setfield(L,-2,"output_error");stop(i);lua_pushinteger(L,-1);lua_setfield(L,-2,"exitcode");return 1;
    }
    if(SDL_WaitProcess(tasks[i],false,&status)) {
        /* Keep the handle until both pipes have drained, avoiding final-output loss. */
        SDL_IOStream *out=SDL_GetProcessOutput(tasks[i]);
        SDL_IOStream *err=SDL_GetPointerProperty(props,SDL_PROP_PROCESS_STDERR_POINTER,NULL);
        if((!out || SDL_GetIOStatus(out)==SDL_IO_STATUS_EOF) && (!err || SDL_GetIOStatus(err)==SDL_IO_STATUS_EOF)){
            lua_pushinteger(L,status);lua_setfield(L,-2,"exitcode");SDL_DestroyProcess(tasks[i]);tasks[i]=NULL;
        }
    }
    return 1;
}
static int send_input(lua_State *L) {
    int i=slot(L);size_t n;const char *s=luaL_checklstring(L,2,&n);int h;
    luaL_argcheck(L,n<=4096,2,"console submission limit is 4096 bytes");
    if(!tasks[i] || !console_task[i] || pending_pos[i]<pending_len[i]){lua_pushboolean(L,0);return 1;}
    h=snprintf(pending[i],sizeof pending[i],"%zu\n",n);
    memcpy(pending[i]+h,s,n);pending_len[i]=(size_t)h+n;pending_pos[i]=0;
    lua_pushboolean(L,1);return 1;
}
static int kill_task(lua_State *L) {stop(slot(L));return 0;}
void runtime_register(lua_State *L) {
    static const luaL_Reg f[]={{"start",start},{"poll",poll},{"send",send_input},{"stop",kill_task},{NULL,NULL}};
    luaL_newlib(L,f);lua_setfield(L,-2,"runtime");
}
void runtime_shutdown(void){stop(0);stop(1);}
