/* Windows single-exe GUI/CLI console setup. Never overwrite redirected pipes. */
#include "win_console.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <stdint.h>

/* Called only for a bare full-client launch, before console initialization.
 * Pipes/files (including mintty/WSL stdio) mean CLI even without a console.
 * Do not attach in that case: AttachConsole can replace redirected handles.
 * A successful attachment is retained for the subsequent CLI initialization.
 */
int cooloo_console_default_gui(void)
{
    const DWORD ids[3] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
    DWORD process;
    int i;
    for (i = 0; i < 3; ++i) {
        HANDLE h = GetStdHandle(ids[i]);
        if (h && h != INVALID_HANDLE_VALUE && GetFileType(h) != FILE_TYPE_UNKNOWN)
            return 0;
    }
    if (GetConsoleProcessList(&process, 1) || AttachConsole(ATTACH_PARENT_PROCESS))
        return 0;
    /* No parent console is the desktop case. On other errors prefer CLI. */
    return GetLastError() == ERROR_INVALID_HANDLE;
}

void cooloo_console_init(int enabled)
{
    const DWORD ids[3] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
    FILE *streams[3] = {stdin, stdout, stderr};
    HANDLE saved[3] = {NULL, NULL, NULL};
    int i;
    if (!enabled)
        return;
    /* Snapshot before AttachConsole: it can replace the standard handles. */
    for (i = 0; i < 3; ++i) {
        HANDLE h = GetStdHandle(ids[i]);
        if (h && h != INVALID_HANDLE_VALUE && GetFileType(h) != FILE_TYPE_UNKNOWN)
            DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(),
                            &saved[i], 0, FALSE, DUPLICATE_SAME_ACCESS);
    }
    /* Fully redirected SDK calls need CRT pipes, not a visible console. */
    if (!(saved[0] && saved[1] && saved[2]) &&
        !GetConsoleWindow() && !AttachConsole(ATTACH_PARENT_PROCESS))
        AllocConsole();
    for (i = 0; i < 3; ++i) {
        if (saved[i]) {
            /* Reserve the FILE descriptor first: a GUI CRT starts at -2;
             * opening the saved handle first could take fd 0, then freopen
             * would close that very handle while initializing stdin. */
            if (freopen("NUL", i == 0 ? "r" : "w", streams[i])) {
                int fd = _open_osfhandle((intptr_t)saved[i],
                                        (i == 0 ? _O_RDONLY : _O_WRONLY) | _O_TEXT);
                if (fd >= 0) {
                    _dup2(fd, _fileno(streams[i]));
                    SetStdHandle(ids[i], (HANDLE)_get_osfhandle(_fileno(streams[i])));
                    _close(fd);
                    clearerr(streams[i]);
                } else {
                    CloseHandle(saved[i]);
                }
            } else {
                CloseHandle(saved[i]);
            }
        } else {
            freopen(i == 0 ? "CONIN$" : "CONOUT$", i == 0 ? "r" : "w", streams[i]);
        }
    }
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
}
int cooloo_console_input_is_terminal(void)
{
    DWORD mode;
    return GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &mode) != 0;
}

int cooloo_console_can_read(void)
{
    if (!cooloo_console_input_is_terminal()) return 0;
#ifndef COOLOO_CLI_ONLY
    /* AttachConsole cannot make an interactive shell wait for a GUI image.
     * The SDK console entry point opts in only while it waits for this child. */
    const char *waiting = getenv("COOLOO_LAUNCHER_WAIT");
    if (!waiting || strcmp(waiting, "1")) {
        fprintf(stderr, "cooloo: interactive input requires the Python launcher; use python -m cooloo (the native GUI exe does not make PowerShell/CMD wait).\n");
        return 0;
    }
#endif
    return 1;
}

#else
#include <unistd.h>
int cooloo_console_input_is_terminal(void) { return isatty(STDIN_FILENO); }
int cooloo_console_can_read(void) { return cooloo_console_input_is_terminal(); }
int cooloo_console_default_gui(void) { return 0; }
void cooloo_console_init(int enabled) { (void)enabled; }
#endif
