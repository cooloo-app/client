/*
 * gui.h - SDL2 window + event pump + draw-list execution (04 doc D29/D30).
 *
 * cooloo_gui_run owns the whole GUI lifecycle. The draw primitives are
 * called by luabind.c while executing a Lua draw list; gui.c only knows
 * pixels, never rooms/messages.
 */
#ifndef COOLOO_GUI_H
#define COOLOO_GUI_H

int  cooloo_gui_run(const char *lua_dev_dir);

/* draw primitives (clip applies to both rect and text) */
void gui_draw_rect(int x, int y, int w, int h, unsigned rgb);
void gui_draw_text(int x, int y, const char *utf8, unsigned rgb, int size);
void gui_set_clip(int x, int y, int w, int h);
void gui_clear_clip(void);
void gui_present(void);

int  gui_screen_w(void);
int  gui_screen_h(void);

#endif /* COOLOO_GUI_H */
