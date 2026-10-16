#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
/* Runs the existing headless CLI inside the isolated runner, not a grandchild.
 * Killing/restarting the runner therefore closes every managed request socket.
 * No keys, connections or GUI state are exported to Lua. */
#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../../src/cli.h"
#include "../../src/machine.h"
#ifdef _WIN32
#include <io.h>
#define dup _dup
#define dup2 _dup2
#define close _close
#define fileno _fileno
#else
#include <unistd.h>
#endif
#define RESULT_LIMIT (1024*1024)
static int request(lua_State *L) {
    const char *allowed[]={"whoami","rooms","meta","send","read","sent",NULL};
    int delegated=lua_toboolean(L,lua_upvalueindex(1)),base=delegated?2:1;
    const char *identity=delegated?luaL_checkstring(L,1):NULL;
    const char *cmd=luaL_checkstring(L,base);char *args[20];int i,n=lua_gettop(L)-base+1,ok=0,status,saved;
    FILE *capture;char *data;size_t length;
    for(i=0;allowed[i];i++)if(!strcmp(cmd,allowed[i]))ok=1;
    luaL_argcheck(L,ok,base,"unsupported script command");
    luaL_argcheck(L,n<=16,base,"too many arguments");
    luaL_argcheck(L,strcmp(cmd,"send") || n>=3,base,"send requires explicit text (no stdin)");
    luaL_argcheck(L,strcmp(cmd,"whoami") || (!delegated && n==1),base,"whoami is read-only login identity");
    args[0]=(char *)"cooloo";
    for(i=0;i<n;i++) {
        size_t len;const char *s=luaL_checklstring(L,base+i,&len);
        luaL_argcheck(L,strlen(s)==len,base+i,"NUL in argument");args[i+1]=(char *)s;
    }
    args[n+1]=NULL;
    cooloo_cli_reset();machine_reset();
    if(identity)luaL_argcheck(L,cooloo_cli_set_as(identity)==0,1,"invalid delegated identity");
    capture=tmpfile();if(!capture)return luaL_error(L,"cannot create request capture");
    fflush(stdout);saved=dup(fileno(stdout));
    if(saved<0 || dup2(fileno(capture),fileno(stdout))<0){if(saved>=0)close(saved);fclose(capture);return luaL_error(L,"cannot redirect request output");}
    cooloo_machine=1;machine_output_limit(RESULT_LIMIT-512);
    if(!strcmp(cmd,"whoami"))status=cooloo_cli_whoami(n+1,args);
    else if(!strcmp(cmd,"rooms"))status=cooloo_cli_rooms(n+1,args);
    else if(!strcmp(cmd,"meta"))status=cooloo_cli_request(n+1,args);
    else if(!strcmp(cmd,"send"))status=cooloo_cli_send(n+1,args);
    else if(!strcmp(cmd,"read"))status=cooloo_cli_read(n+1,args);
    else status=cooloo_cli_sent(n+1,args);
    status=machine_finish(status);cooloo_machine=0;machine_output_limit(0);cooloo_cli_reset();
    fflush(stdout);
    if(dup2(saved,fileno(stdout))<0){close(saved);fclose(capture);return luaL_error(L,"cannot restore runner output");}
    close(saved);clearerr(stdout);rewind(capture);
    data=malloc(RESULT_LIMIT+1);if(!data){fclose(capture);return luaL_error(L,"out of memory");}
    length=fread(data,1,RESULT_LIMIT+1,capture);
    if(length>RESULT_LIMIT || ferror(capture)){free(data);fclose(capture);return luaL_error(L,"request output exceeds 1 MiB or capture failed; do not retry sends blindly");}
    fclose(capture);lua_pushlstring(L,data,length);lua_pushinteger(L,status);free(data);return 2;
}
void script_client_register(lua_State *L,const char *exe) {
    (void)exe;lua_newtable(L);
    lua_pushboolean(L,0);lua_pushcclosure(L,request,1);lua_setfield(L,-2,"request");
    lua_pushboolean(L,1);lua_pushcclosure(L,request,1);lua_setfield(L,-2,"request_as");
    lua_setglobal(L,"cooloo");
}
