/* GUI-subsystem fixture: exercise the same native console/input gate as CLI. */
#include "win_console.h"
#include <stdio.h>
int main(void)
{
    cooloo_console_init(1);
    printf("terminal=%d readable=%d\n", cooloo_console_input_is_terminal(),
           cooloo_console_can_read());
    return 0;
}
