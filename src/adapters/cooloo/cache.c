/* Bounded asynchronous cache jobs. Only this worker touches its job records;
 * Lua callbacks always run on the UI thread. Queue-full is explicit backpressure. */
#include <SDL3/SDL.h>
#include <lua.h>
#include <lauxlib.h>
#include "record.h"
#include "cache.h"
#include <stdlib.h>
#include <string.h>
#define JOBS 32
#define PAGE 2000
typedef struct { long long offset; char *json; } item;
typedef struct {
    int state, kind, ok, count, first, limit;
    unsigned serial;
    char server[65], self[65], room[65];
    long long before, offset;
    char *json;
    item *items;
} job;
static job jobs[JOBS];
static SDL_Mutex *mutex;
static SDL_Condition *wake;
static SDL_Thread *thread;
static bool closing;
static unsigned serial;
static int visit(void *ctx,long long offset,const char *json) {
    job *j=ctx; int at;
    j->offset=offset;
    if(offset>=j->before)return 0;
    if(j->count<j->limit)at=j->count++;
    else {at=j->first;SDL_free(j->items[at].json);j->first=(j->first+1)%j->limit;}
    j->items[at].offset=offset;
    j->items[at].json=SDL_strdup(json);
    return j->items[at].json?0:-1;
}
static int cancelled(void *ctx) {
    int result;(void)ctx;SDL_LockMutex(mutex);result=closing;SDL_UnlockMutex(mutex);return result;
}
static int worker(void *unused) {
    (void)unused;
    SDL_LockMutex(mutex);
    while(!closing) {
        int i; job *j=NULL;
        for(i=0;i<JOBS;i++)if(jobs[i].state==1 && (!j || jobs[i].serial<j->serial))j=&jobs[i];
        if(!j){SDL_WaitCondition(wake,mutex);continue;}
        j->state=2;SDL_UnlockMutex(mutex);
        if(j->kind==0)j->ok=cache_read_controlled(j->server,j->self,j->room,visit,j,cancelled,NULL)==0;
        else if(j->kind==1)j->ok=cache_append_controlled(j->server,j->self,j->room,j->offset,j->json,cancelled,NULL)==0;
        else j->ok=cache_meta(j->server,j->self,j->json)==0;
        SDL_LockMutex(mutex);j->state=3;
    }
    SDL_UnlockMutex(mutex);return 0;
}
static void clear(job *j) {
    int i;for(i=0;i<j->count;i++)SDL_free(j->items[i].json);
    free(j->items);SDL_free(j->json);memset(j,0,sizeof *j);
}
static int submit(lua_State *L) {
    const char *kind=luaL_checkstring(L,1),*server=luaL_checkstring(L,2),*self=luaL_checkstring(L,3),*room=luaL_checkstring(L,4);
    job value={0};int i;
    luaL_argcheck(L,strlen(server)==64 && strlen(self)==64 && strlen(room)==64,2,"invalid cache ID");
    SDL_strlcpy(value.server,server,sizeof value.server);SDL_strlcpy(value.self,self,sizeof value.self);SDL_strlcpy(value.room,room,sizeof value.room);
    if(!strcmp(kind,"read")) {
        value.before=luaL_optinteger(L,5,LUA_MAXINTEGER);value.limit=(int)luaL_optinteger(L,6,200);
        luaL_argcheck(L,value.limit>0 && value.limit<=PAGE,6,"page limit is 1..2000");
        value.items=calloc((size_t)value.limit,sizeof(item));if(!value.items)return luaL_error(L,"out of memory");
    } else {
        const char *json;
        luaL_argcheck(L,!strcmp(kind,"append")||!strcmp(kind,"meta"),1,"invalid cache operation");
        value.kind=!strcmp(kind,"append")?1:2;
        value.offset=luaL_checkinteger(L,5);json=luaL_checkstring(L,6);
        luaL_argcheck(L,strlen(json)<RECORD_MAX,6,"record too large");
        value.json=SDL_strdup(json);if(!value.json)return luaL_error(L,"out of memory");
    }
    SDL_LockMutex(mutex);
    for(i=0;i<JOBS;i++)if(!jobs[i].state)break;
    if(i==JOBS){SDL_UnlockMutex(mutex);clear(&value);lua_pushnil(L);lua_pushliteral(L,"cache queue full");return 2;}
    value.state=1;value.serial=++serial;jobs[i]=value;
    SDL_SignalCondition(wake);SDL_UnlockMutex(mutex);lua_pushinteger(L,value.serial);return 1;
}
static int poll(lua_State *L) {
    int i,n=0,records=0;lua_newtable(L);
    for(i=0;i<JOBS;i++) {
        job value;
        SDL_LockMutex(mutex);
        if(jobs[i].state!=3 || n>=4 || records+jobs[i].count>PAGE){SDL_UnlockMutex(mutex);continue;}
        records+=jobs[i].count;
        value=jobs[i];memset(&jobs[i],0,sizeof jobs[i]);SDL_UnlockMutex(mutex);
        lua_newtable(L);
        lua_pushinteger(L,value.serial);lua_setfield(L,-2,"id");
        lua_pushboolean(L,value.ok);lua_setfield(L,-2,"ok");
        lua_pushinteger(L,value.offset);lua_setfield(L,-2,"offset");
        lua_newtable(L);
        for(int k=0;k<value.count;k++) {
            item *it=&value.items[(value.first+k)%value.limit];
            lua_newtable(L);lua_pushinteger(L,it->offset);lua_setfield(L,-2,"offset");
            lua_pushstring(L,it->json);lua_setfield(L,-2,"json");lua_rawseti(L,-2,k+1);
        }
        lua_setfield(L,-2,"records");lua_rawseti(L,-2,++n);clear(&value);
    }
    return 1;
}
void workbench_cache_register(lua_State *L) {
    static const luaL_Reg api[]={{"submit",submit},{"poll",poll},{NULL,NULL}};
    mutex=SDL_CreateMutex();wake=SDL_CreateCondition();closing=false;
    if(!mutex||!wake || !(thread=SDL_CreateThread(worker,"cache",NULL)))luaL_error(L,"cache worker: %s",SDL_GetError());
    luaL_newlib(L,api);lua_setfield(L,-2,"cache_async");
}
void workbench_cache_shutdown(void) {
    int i;if(thread){SDL_LockMutex(mutex);closing=true;SDL_SignalCondition(wake);SDL_UnlockMutex(mutex);SDL_WaitThread(thread,NULL);thread=NULL;}
    for(i=0;i<JOBS;i++)clear(&jobs[i]);
    SDL_DestroyCondition(wake);SDL_DestroyMutex(mutex);wake=NULL;mutex=NULL;
}
