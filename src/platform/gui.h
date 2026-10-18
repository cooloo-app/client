/* SDL3 window, input and fixed-frame host; renderer/rencache own drawing. */
#ifndef COOLOO_GUI_H
#define COOLOO_GUI_H

struct lua_State;
int  cooloo_gui_run(const char *lua_dev_dir);
int  gui_poll_event(struct lua_State *L);
int  gui_wait_event(struct lua_State *L);

/* position the IME candidate window (SDL_SetTextInputArea wrapper) */
void gui_set_ime_rect(int x, int y, int w, int h);
void gui_clear_ime(void);

int  gui_screen_w(void);
int  gui_screen_h(void);

#endif /* COOLOO_GUI_H */
