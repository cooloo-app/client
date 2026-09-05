/* cli.h - cooloo CLI subcommands (handoff §7) */
#ifndef COOLOO_CLI_H
#define COOLOO_CLI_H

int cooloo_cli_keygen(int argc, char **argv);
int cooloo_cli_send(int argc, char **argv);
int cooloo_cli_read(int argc, char **argv);
int cooloo_cli_follow(int argc, char **argv);
int cooloo_cli_rooms(int argc, char **argv);
int cooloo_cli_whoami(int argc, char **argv);
int cooloo_cli_chat(int argc, char **argv);

/* -y/--tofu: auto-trust-and-pin unknown server fingerprints */
void cooloo_cli_set_tofu(int on);

#endif /* COOLOO_CLI_H */
