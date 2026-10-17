/*
 * luabind.h - the C <-> Lua boundary (04 doc 4.2).
 *
 * gui.c drives events_begin -> net_pump -> frame(dt). The events array
 * carries network notifications only. Lite core.step calls gui_poll_event
 * directly for SDL input. Native renderer.end_frame presents during core.step.
 */
#ifndef COOLOO_LUABIND_H
#define COOLOO_LUABIND_H

void luabind_set_args(int argc, char **argv);
int  luabind_init(const char *lua_dev_dir);
void luabind_shutdown(void);

void luabind_events_begin(void);

void luabind_net_pump(void);

/* call cooloo.frame(events, dt, frame_start).
 * returns 1 on requested quit or fatal Lua error; failed reports exit status. */
int  luabind_frame(double dt, double frame_start);
int  luabind_failed(void);
const char *luabind_last_error(void);

#endif /* COOLOO_LUABIND_H */
