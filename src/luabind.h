/*
 * luabind.h - the C <-> Lua boundary (04 doc 4.2).
 *
 * gui.c drives the frame cycle: events_begin -> ev_* feeders (SDL) ->
 * net_pump (net_* events) -> frame(dt) which calls cooloo.frame and
 * executes the returned draw list.
 */
#ifndef COOLOO_LUABIND_H
#define COOLOO_LUABIND_H

int  luabind_init(const char *lua_dev_dir);
void luabind_shutdown(void);

void luabind_events_begin(void);
void luabind_ev_key(const char *name, int mod);
void luabind_ev_text(const char *text);
void luabind_ev_ime(const char *text, int cursor);
void luabind_ev_mouse(const char *kind, int x, int y, int button,
                      int wx, int wy);
void luabind_ev_resize(int w, int h);
void luabind_ev_quit(void);

void luabind_net_pump(void);

/* call cooloo.frame(events, dt), execute returned draw list.
 * returns 1 when Lua requested quit (cooloo.quit()). */
int  luabind_frame(double dt);

#endif /* COOLOO_LUABIND_H */
