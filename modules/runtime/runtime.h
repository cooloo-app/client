#ifndef COOLOO_RUNTIME_H
#define COOLOO_RUNTIME_H
#include <lua.h>
/* Called before normal argument/config parsing. -1 means not a runner request. */
int runtime_dispatch(int argc, char **argv);
void runtime_register(lua_State *L);
void runtime_shutdown(void);
#endif
