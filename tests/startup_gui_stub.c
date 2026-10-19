/* Startup dispatch fixture: no SDL, window, network or identity side effects. */
#include "luabind.h"
void luabind_set_args(int argc, char **argv) { (void)argc; (void)argv; }
int cooloo_gui_run(const char *dev) { (void)dev; return 73; }
