#ifndef COOLOO_MACHINE_H
#define COOLOO_MACHINE_H
#include <stddef.h>
/* JSONL schema 1: output-only adapter; no transport implementation. */
extern int cooloo_machine;
void machine_reset(void);
void machine_output_limit(size_t limit);
int machine_output_limited(void);
void machine_string(const char *s);
int machine_error(const char *code, const char *message);
int machine_server_error(const char *line);
void machine_result(const char *field, const char *value);
void machine_offset(const char *type, const char *field, long long offset);
void machine_message(long long end, const char *json);
int machine_response(const char *command, const char *line);
int machine_finish(int status);
void machine_version(void);
#endif
