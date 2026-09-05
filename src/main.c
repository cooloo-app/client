/*
 * main.c - cooloo CLI entry point (handoff §7)
 *
 *   cooloo keygen                       create identity, print fingerprint
 *   cooloo send <room> [text...]        append (stdin when no text args)
 *   cooloo read [--raw] <room> <off|-N> read messages
 *   cooloo follow <room>                stream (persists offset, auto-resume)
 *   cooloo chat <room>                  interactive read/write
 *   cooloo rooms | whoami [--register <nick>]
 *   global flag: -y/--tofu              auto-trust unknown server fingerprint
 * Running bare (no args) is reserved for the v2 GUI.
 */
#include "cli.h"

#include <stdio.h>
#include <string.h>

static void usage(FILE *out)
{
    fprintf(out,
            "usage:\n"
            "  cooloo keygen                        create identity\n"
            "  cooloo send <room> [text...]         append a message\n"
            "  cooloo read [--raw] <room> <off|-N>  read messages\n"
            "  cooloo follow <room>                 stream new messages\n"
            "  cooloo chat <room>                   interactive chat\n"
            "  cooloo rooms                         list rooms\n"
            "  cooloo whoami [--register <nick>]    show / register nick\n"
            "  flags: -y/--tofu auto-trust new server fingerprint\n"
            "  env:   COOLOO_HOST=host[:port] override server\n");
}

int main(int argc, char **argv)
{
    int i, j;

    if (argc < 2) {
        fprintf(stderr, "cooloo: GUI is not implemented yet (v2); "
                        "this build is the CLI\n\n");
        usage(stderr);
        return 2;
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
