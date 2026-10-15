/*
 * main.c - cooloo CLI entry point (handoff §7)
 *
 *   cooloo keygen                       create identity, print fingerprint
 *   cooloo send <room> [text...]        append (stdin when no text args)
 *   cooloo read [--raw] <room> <off|-N> read messages
 *   cooloo follow <room>                stream (persists offset, auto-resume)
 *   cooloo chat <room>                  interactive read/write
 *   cooloo rooms | whoami [--register <nick>]
 *   cooloo [--debug] [--lua-dev DIR]    GUI (default)
 *   global flag: -y/--tofu              auto-trust unknown server fingerprint
 * Running bare (no args) enters the v2 GUI (D31).
 */
#include "cli.h"
#include "gui.h"
#include "win_console.h"

#include <stdio.h>
#include <string.h>

static void usage(FILE *out)
{
    fprintf(out,
            "usage:\n"
            "  cooloo keygen                        create identity\n"
            "  cooloo send <room> [text...]         append a message\n"
            "  cooloo read [--raw] <id> <offset>    read messages\n"
            "  cooloo follow <room>                 stream new messages\n"
            "  cooloo chat <room>                   interactive chat\n"
            "  cooloo [--debug] [--lua-dev DIR]     GUI (default)\n"
            "  cooloo rooms                         list rooms and own inbox\n"
            "  cooloo create <nickname>             create public room\n"
            "  cooloo join <room-id>                request membership\n"
            "  cooloo room-mode <room-id> public|private\n"
            "  cooloo avatar <slot> <public-id> <nickname>\n"
            "  cooloo meta <id> | rename <id> <nickname>\n"
            "  cooloo whoami [--register <nick>]    show / register nick\n"
            "  flags: -y/--tofu auto-trust new server fingerprint\n"
            "  env:   COOLOO_HOST=host[:port] override server\n");
}

int main(int argc, char **argv)
{
    int i, j, debug = 0;
    const char *dev = NULL;

    /* Parse startup flags before GUI selection: --debug alone still runs GUI. */
    for (i = 1; i < argc; i++) {
        int remove = 0;
        if (!strcmp(argv[i], "--debug")) {
            debug = 1;
            remove = 1;
        } else if (!strcmp(argv[i], "--lua-dev")) {
            if (i + 1 >= argc) {
                cooloo_console_init(1);
                fprintf(stderr, "cooloo: --lua-dev requires a directory\n");
                return 2;
            }
            dev = argv[i + 1];
            remove = 2;
        }
        if (remove) {
            for (j = i; j + remove < argc; j++)
                argv[j] = argv[j + remove];
            argc -= remove;
            argv[argc] = NULL;
            i--;
        }
    }
    cooloo_console_init(debug || argc >= 2);
    if (argc < 2) {
#ifdef COOLOO_CLI_ONLY
        (void)dev;
        usage(stderr);
        return 2;
#else
        return cooloo_gui_run(dev);
#endif
    }

    /* pull global flags out of argv before dispatch */
    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-y") || !strcmp(argv[i], "--tofu")) {
            cooloo_cli_set_tofu(1);
            for (j = i; j + 1 < argc; j++)
                argv[j] = argv[j + 1];
            argc--;
            i--;
        }
    }
    if (argc < 2) {
        usage(stderr);
        return 2;
    }

    if (!strcmp(argv[1], "create") || !strcmp(argv[1], "avatar") ||
        !strcmp(argv[1], "meta") || !strcmp(argv[1], "rename") ||
        !strcmp(argv[1], "join") || !strcmp(argv[1], "room-mode"))
        return cooloo_cli_request(argc, argv);
    if (!strcmp(argv[1], "keygen"))
        return cooloo_cli_keygen(argc, argv);
    if (!strcmp(argv[1], "send"))
        return cooloo_cli_send(argc, argv);
    if (!strcmp(argv[1], "read"))
        return cooloo_cli_read(argc, argv);
    if (!strcmp(argv[1], "follow"))
        return cooloo_cli_follow(argc, argv);
    if (!strcmp(argv[1], "rooms"))
        return cooloo_cli_rooms(argc, argv);
    if (!strcmp(argv[1], "whoami"))
        return cooloo_cli_whoami(argc, argv);
    if (!strcmp(argv[1], "chat"))
        return cooloo_cli_chat(argc, argv);
    if (!strcmp(argv[1], "help") || !strcmp(argv[1], "--help") ||
        !strcmp(argv[1], "-h")) {
        usage(stdout);
        return 0;
    }

    fprintf(stderr, "cooloo: unknown command: %s\n", argv[1]);
    usage(stderr);
    return 2;
}
