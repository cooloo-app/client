#ifndef COOLOO_PLATFORM_FILE_H
#define COOLOO_PLATFORM_FILE_H
#include <lua.h>
int platform_write_file(lua_State *L);
int platform_read_file(lua_State *L);
#ifdef _WIN32
#include <wchar.h>
/* Caller owns the normalized absolute extended-length path. */
wchar_t *platform_windows_path(lua_State *L, const char *path);
#endif
#endif
