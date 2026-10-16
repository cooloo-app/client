#ifndef COOLOO_WORKBENCH_CACHE_H
#define COOLOO_WORKBENCH_CACHE_H
#include <lua.h>
void workbench_cache_register(lua_State *L);
void workbench_cache_shutdown(void);
#endif
