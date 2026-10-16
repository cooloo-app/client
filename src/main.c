/*
 * main.c - cooloo CLI entry point (handoff §7)
 *
 *   cooloo keygen                       create identity, print fingerprint
 *   cooloo send <room> [text...]        append (stdin when no text args)
 *   cooloo read [--raw] <room> <off|-N> read messages
 *   cooloo follow <room>                stream (persists offset, auto-resume)
 *   cooloo chat <room>                  interactive read/write
 *   cooloo rooms | whoami [--register <nick>]
 *   cooloo --gui [--debug] [--lua-dev DIR]  GUI
 *   global flag: -y/--tofu              auto-trust unknown server fingerprint
 * Running bare (no args) prints a short help summary without side effects.
 */
#include "cli.h"
#include "gui.h"
#include "win_console.h"
#include "machine.h"
#ifndef _WIN32
#include <signal.h>
#else
#include <io.h>
#include <fcntl.h>
#endif

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
            "  cooloo rooms                         list rooms and own inbox\n"
            "  cooloo create <nickname>             create public room\n"
            "  cooloo join <room-id>                request membership\n"
            "  cooloo room-mode <room-id> public|private\n"
            "  cooloo avatar <slot> <public-id> <nickname>\n"
            "  cooloo meta <id> | rename <id> <nickname>\n"
            "  cooloo whoami [--register <nick>]    show / register nick\n"
            "  cooloo delegate <child-id> read|write|read,write|none\n"
            "  cooloo sent <peer-id> <scan-offset>  own messages only\n"
            "  cooloo history                     merge inbox and discovered sent history\n"
            "  cooloo --gui [--debug] [--lua-dev DIR]  launch GUI\n"
            "  cooloo --help                      show full help\n"
            "  cooloo version                     print client version\n"
            "  flags: --json JSONL schema 1; noninteractive, no read/follow cache\n"
            "         --json follow <id> <offset> explicit business cursor\n"
            "         --as <owner-id> select delegated message identity\n"
            "         -y/--tofu auto-trust new server fingerprint\n"
            "  env:   COOLOO_HOST=host[:port] override server\n");
}

static void quick_help(void)
{
    puts("cooloo - messaging client\n"
         "\nusage: cooloo <command> [options]\n"
         "       cooloo --gui [--debug] [--lua-dev DIR]\n"
         "\nGet started:\n"
         "  cooloo --gui                       launch GUI\n"
         "  cooloo whoami                      show current identity\n"
         "  cooloo rooms                       list rooms and own inbox\n"
         "  cooloo send <id> [text...]          send a message\n"
         "  cooloo read <id> <offset>           read messages\n"
         "  cooloo --help                      show full help");
}

static int run(int argc, char **argv)
{
    int i, j, debug = 0, gui = 0;
    const char *dev = NULL;

    /* Parse startup flags; only --gui selects the GUI. */
    for (i = 1; i < argc && argv[i][0]=='-'; i++) {
        int remove = 0;
        if (!strcmp(argv[i], "--json")) {
            cooloo_machine = 1;
            remove = 1;
        } else if (!strcmp(argv[i], "--gui")) {
            gui = 1;
            remove = 1;
        } else if (!strcmp(argv[i], "--as")) {
            if(i+1<argc)i++;
            continue;
        } else if (!strcmp(argv[i], "--debug")) {
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
    cooloo_console_init(debug || !gui || argc >= 2 || cooloo_machine);
#ifdef _WIN32
    if(cooloo_machine){_setmode(_fileno(stdin),_O_BINARY);_setmode(_fileno(stdout),_O_BINARY);}
#endif
    if(gui&&(cooloo_machine||argc!=1))return 2;
    if(cooloo_machine&&argc<2)return 2;
    if (gui) {
#ifdef COOLOO_CLI_ONLY
        (void)dev;
        fprintf(stderr, "cooloo: GUI is not available in this CLI-only build\n");
        return 2;
#else
        return cooloo_gui_run(dev);
#endif
    }
    if (argc < 2) {
        quick_help();
        return 0;
    }

    /* --as must precede the command; never consume message text as a flag. */
    for(i=1;i<argc;) {
        if(!strcmp(argv[i],"-y") || !strcmp(argv[i],"--tofu")) { i++; continue; }
        if(strcmp(argv[i],"--as"))break;
        if(i+1>=argc || cooloo_cli_set_as(argv[i+1]))return 2;
        for(j=i;j+2<argc;j++)argv[j]=argv[j+2];
        argc-=2;argv[argc]=NULL;
    }
    /* pull global flags out of argv before dispatch */
    while (argc > 1 && (!strcmp(argv[1], "-y") || !strcmp(argv[1], "--tofu"))) {
        cooloo_cli_set_tofu(1);
        for (j = 1; j + 1 < argc; j++) argv[j] = argv[j + 1];
        argc--;
        argv[argc] = NULL;
    }
    if (argc < 2) {
        usage(stderr);
        return 2;
    }

    if (!strcmp(argv[1], "version") && argc==2) {
        if(cooloo_machine)machine_version();else puts("cooloo 0.2.4");return 0;
    }
    if(cooloo_machine&&(!strcmp(argv[1],"history")||!strcmp(argv[1],"chat")||!strcmp(argv[1],"help")||!strcmp(argv[1],"--help")))return 2;
    if (!strcmp(argv[1], "create") || !strcmp(argv[1], "avatar") ||
        !strcmp(argv[1], "meta") || !strcmp(argv[1], "rename") ||
        !strcmp(argv[1], "join") || !strcmp(argv[1], "room-mode") ||
        !strcmp(argv[1], "delegate"))
        return cooloo_cli_request(argc, argv);
    if (!strcmp(argv[1], "sent"))return cooloo_cli_sent(argc,argv);
    if (!strcmp(argv[1], "history"))return cooloo_cli_history(argc,argv);
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

int main(int argc,char **argv)
{
    int status;
#ifndef _WIN32
    signal(SIGPIPE,SIG_IGN);
#endif
    status=run(argc,argv);
    return cooloo_machine?machine_finish(status):status;
}
