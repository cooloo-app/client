#define _POSIX_C_SOURCE 200809L
#include "record.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv)
{
    char a[65],b[65],c[65],json[512],p[1600];long long end;FILE *f;
    assert(argc==2);assert(!setenv("COOLOO_CONFIG",argv[1],1));
    memset(a,'a',64);a[64]=0;memset(b,'b',64);b[64]=0;memset(c,'c',64);c[64]=0;
    snprintf(json,sizeof json,"{\"ts\":1,\"from\":\"%s\",\"to\":\"%s\",\"content\":\"hello\"}",b,c);
    end=(long long)strlen(json)+1;
    assert(cache_offset(a,b,c)==0);
    assert(cache_append(a,b,c,end+1,json)<0); /* gap */
    assert(!cache_append(a,b,c,end,json));
    assert(!cache_append(a,b,c,end,json)); /* exact duplicate */
    assert(cache_offset(a,b,c)==end);
    strcpy(strstr(json,"hello"),"other\"}");
    assert(cache_append(a,b,c,end,json)<0); /* conflicting duplicate */
    snprintf(p,sizeof p,"%s/cache/%s/%s/rooms/%s/messages.jsonl",argv[1],a,b,c);
    f=fopen(p,"ab");assert(f);fputs("{partial",f);assert(!fclose(f));
    assert(cache_offset(a,b,c)==end); /* repair incomplete tail only */
    f=fopen(p,"ab");assert(f);fputs("bad record\n",f);assert(!fclose(f));
    assert(cache_offset(a,b,c)<0); /* complete corruption fails closed */
    assert(cache_offset(a,c,c)==0); /* identities segregated */
    assert(cache_generation(a,b,c,a)==0); /* migration keeps existing history */
    assert(cache_generation(a,b,c,a)==0);
    assert(cache_generation(a,b,c,b)==1); /* new epoch archives and resets */
    assert(cache_offset(a,b,c)==0);
    assert(cache_generation(a,b,c,b)==0);
    snprintf(p,sizeof p,"%s/cache/%s/%s/rooms/%s/messages.jsonl.%s",argv[1],a,b,c,a);
    f=fopen(p,"rb");assert(f);assert(fgetc(f)!=EOF);fclose(f);
    puts("cache: gaps, duplicates, conflicts, crash tail and identity isolation passed");
    return 0;
}
