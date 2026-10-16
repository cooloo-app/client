/* Independent VM. Framed stdin supports multiline REPL submissions without eval
 * in the UI process. This is fault isolation, NOT a security sandbox. */
#include "runtime.h"
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
#ifdef COOLOO_WORKBENCH
void script_client_register(lua_State *L,const char *exe);
#endif
static int traceback(lua_State *L) { luaL_traceback(L,L,lua_tostring(L,1),1);return 1; }
static int print_results(lua_State *L) {
    int n=lua_gettop(L);
    for(int i=1;i<=n;i++){size_t len;const char *s=luaL_tolstring(L,i,&len);fwrite(s,1,len,stdout);fputc(i==n?'\n':'\t',stdout);lua_pop(L,1);}
    return 0;
}
static int execute(lua_State *L,const char *src,size_t n,const char *name) {
    int base=lua_gettop(L),rc;
    lua_pushcfunction(L,traceback);
    rc=luaL_loadbuffer(L,src,n,name);
    if(rc) {
        char *expression=malloc(n+8);
        if(expression) {
            memcpy(expression,"return ",7);memcpy(expression+7,src,n);expression[n+7]=0;
            lua_pop(L,1);rc=luaL_loadbuffer(L,expression,n+7,name);free(expression);
        }
    }
    if(!rc)rc=lua_pcall(L,0,LUA_MULTRET,base+1);
    if(!rc) {
        int results=lua_gettop(L)-base-1;
        lua_pushcfunction(L,print_results);lua_insert(L,base+2);
        rc=lua_pcall(L,results,0,base+1);
    }
    if(rc)fprintf(stderr,"%s\n",lua_tostring(L,-1));
    lua_settop(L,base);return rc?1:0;
}
int runtime_dispatch(int argc,char **argv) {
    lua_State *L;int status=0;
    if(argc<2 || (strcmp(argv[1],"--lua-run") && strcmp(argv[1],"--lua-console")))return -1;
#ifdef _WIN32
    _setmode(_fileno(stdin),_O_BINARY);_setmode(_fileno(stdout),_O_BINARY);
#endif
    setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);
    L=luaL_newstate();if(!L)return 1;luaL_openlibs(L);
#ifdef COOLOO_WORKBENCH
    script_client_register(L,argv[0]);
#endif
    if(!strcmp(argv[1],"--lua-run")) {
        if(argc!=3)status=2;
        else {lua_pushcfunction(L,traceback);status=luaL_loadfile(L,argv[2]);if(!status)status=lua_pcall(L,0,0,1);if(status)fprintf(stderr,"%s\n",lua_tostring(L,-1));status=status?1:0;}
    } else {
        char header[64];
        while(fgets(header,sizeof header,stdin)) {
            char *end;unsigned long n=strtoul(header,&end,10);char *src;
            if(end==header || strcmp(end,"\n") || n>1024*1024){status=2;break;}
            src=malloc(n+1);if(!src){status=1;break;}
            if(fread(src,1,n,stdin)!=n){free(src);status=2;break;}src[n]=0;
            execute(L,src,n,"=console");free(src);
        }
    }
    lua_close(L);return status;
}
#ifdef COOLOO_RUNNER_ONLY
int main(int argc,char **argv) {int rc=runtime_dispatch(argc,argv);return rc<0?2:rc;}
#endif
