#ifndef COOLOO_WIN_CONSOLE_H
#define COOLOO_WIN_CONSOLE_H
int cooloo_console_default_gui(void);
void cooloo_console_init(int enabled);
/* Interactive reads require a terminal and, for a Windows GUI image, a waiting launcher. */
int cooloo_console_input_is_terminal(void);
int cooloo_console_can_read(void);
#endif
