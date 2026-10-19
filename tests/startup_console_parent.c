/* Console-subsystem parent for testing attachment with no inherited stdio. */
#include <windows.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    DWORD code;
    if (argc != 2) return 2;
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES; /* Deliberately all NULL. */
    if (!CreateProcessA(argv[1], NULL, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return 3;
    if (WaitForSingleObject(pi.hProcess, 10000) != WAIT_OBJECT_0) {
        TerminateProcess(pi.hProcess, 4);
        return 4;
    }
    if (!GetExitCodeProcess(pi.hProcess, &code)) return 5;
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    printf("child exit=%lu\n", (unsigned long)code);
    return (int)code;
}
