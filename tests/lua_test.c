/* Run GUI state-machine tests using the vendored Lua interpreter. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdio.h>
int main(int argc, char **argv)
{
    lua_State *l = luaL_newstate();
    int i;
    if (!l) return 1;
    luaL_openlibs(l);
    for (i = 1; i < argc; i++) {
        if (luaL_dofile(l, argv[i])) {
            fprintf(stderr, "%s\n", lua_tostring(l, -1));
            lua_close(l);
            return 1;
        }
    }
    lua_close(l);
    return 0;
}
