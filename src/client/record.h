#ifndef COOLOO_RECORD_H
#define COOLOO_RECORD_H
#include <stddef.h>
#define RECORD_MAX 25088
struct record { long long ts; char from[65], to[65], content[4097]; };
int record_parse(const char *json, struct record *r);
/* Contiguous server byte prefix, segregated by server and local public ID. */
int cache_generation(const char *server,const char *self,const char *room,const char *generation);
long long cache_offset(const char *server, const char *self, const char *room);
int cache_append(const char *server, const char *self, const char *room,
                 long long end, const char *json);
int cache_meta(const char *server, const char *self, const char *json);
typedef int (*cache_visit)(void *ctx, long long end, const char *json);
int cache_read(const char *server, const char *self, const char *room,
               cache_visit visit, void *ctx);
/* Cancelable worker variants preserve the same format/locking semantics. */
int cache_read_controlled(const char *server,const char *self,const char *room,
    cache_visit visit,void *ctx,int (*cancel)(void *),void *cancel_ctx);
int cache_append_controlled(const char *server,const char *self,const char *room,
    long long end,const char *json,int (*cancel)(void *),void *cancel_ctx);
#endif
