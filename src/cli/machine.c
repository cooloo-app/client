#include "machine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
int cooloo_machine;
static int failed;
void machine_reset(void) { failed=0;cooloo_machine=0; }
static size_t output_limit,output_bytes;
static int output_limited;
void machine_output_limit(size_t limit) { output_limit=limit;output_bytes=0;output_limited=0; }
int machine_output_limited(void) { return output_limited; }
void machine_string(const char *s)
{
    const unsigned char *p=(const unsigned char *)s;
    putchar('"');
    for(;*p;p++) {
        if(*p=='"'||*p=='\\')printf("\\%c",*p);
        else if(*p<32)printf("\\u%04x",*p);
        else putchar(*p);
    }
    putchar('"');
}
int machine_error(const char *code,const char *message)
{
    failed=1;
    printf("{\"schema\":1,\"type\":\"error\",\"code\":");machine_string(code);
    printf(",\"message\":");machine_string(message);puts("}");fflush(stdout);return 1;
}
int machine_server_error(const char *line)
{
    char code[80];const char *p;size_t n;
    if(strncmp(line,"ERR ",4))return machine_error("protocol-error","unexpected server response");
    p=strchr(line+4,' ');n=p?(size_t)(p-line-4):strlen(line+4);
    if(!n||n>=sizeof code)return machine_error("protocol-error","invalid server error");
    memcpy(code,line+4,n);code[n]=0;
    return machine_error(code,p?p+1:code);
}
void machine_result(const char *field,const char *value)
{
    printf("{\"schema\":1,\"type\":\"result\",");machine_string(field);putchar(':');machine_string(value);puts("}");
}
void machine_offset(const char *type,const char *field,long long offset)
{printf("{\"schema\":1,\"type\":\"%s\",\"%s\":%lld}\n",type,field,offset);fflush(stdout);}
void machine_message(long long end,const char *json)
{
    if(output_limit && output_bytes+strlen(json)+100>output_limit){output_limited=1;return;}
    output_bytes+=strlen(json)+100;
    printf("{\"schema\":1,\"type\":\"message\",\"end_offset\":%lld,\"message\":%s}\n",end,json);fflush(stdout);
}
int machine_response(const char *command,const char *line)
{
    char id[65],kind[16],owner[65],slot[8];int pos=0;
    if(!strncmp(line,"ERR ",4))return machine_server_error(line);
    if(!strcmp(line,"OK")){puts("{\"schema\":1,\"type\":\"result\"}");return 0;}
    if(!strncmp(line,"OK ",3)) {
        char *end;long long off;errno=0;off=strtoll(line+3,&end,10);
        if(errno||end==line+3||*end||off<0)return machine_error("protocol-error","invalid send offset");
        machine_offset("result","end_offset",off);return 0;
    }
    if(!strcmp(command,"IDENTITY") && sscanf(line,"IDENTITY %64[0-9a-f] %64[0-9a-f]%n",id,owner,&pos)==2 &&
       strlen(id)==64 && strlen(owner)==64 && !line[pos]) {
        printf("{\"schema\":1,\"type\":\"result\",\"authenticated_id\":");machine_string(id);
        printf(",\"effective_id\":");machine_string(owner);puts("}");return 0;
    }
    if((!strcmp(command,"CREATE")||!strcmp(command,"AVATAR")||!strcmp(command,"MIRROR")||!strcmp(command,"ROOM")) &&
       sscanf(line,"%15s %64s %n",kind,id,&pos)==2 && strlen(id)==64 && pos>0) {
        if(output_limit && output_bytes+strlen(line)+100>output_limit){output_limited=1;return machine_error("output-limit","script result exceeds 1 MiB");}
        output_bytes+=strlen(line)+100;
        printf("{\"schema\":1,\"type\":\"%s\",\"id\":",!strcmp(command,"ROOM")?"room":"result");machine_string(id);
        printf(",\"nickname\":");machine_string(line+pos);puts("}");return 0;
    }
    if(!strcmp(command,"META")&&sscanf(line,"INFO %64s %15s %64s %7s %n",id,kind,owner,slot,&pos)==4&&pos>0) {
        printf("{\"schema\":1,\"type\":\"result\",\"id\":");machine_string(id);
        printf(",\"kind\":");machine_string(kind);printf(",\"owner\":");machine_string(owner);
        printf(",\"slot\":%d,\"nickname\":",atoi(slot));machine_string(line+pos);puts("}");return 0;
    }
    return machine_error("protocol-error","unexpected server response");
}
int machine_finish(int status)
{
    if(status&&!failed)machine_error(status==2?"invalid-argument":"network-error",status==2?"invalid command arguments":"operation failed or connection closed");
    if(fflush(stdout)||ferror(stdout))return 1;
    return status;
}
void machine_version(void)
{
    puts("{\"schema\":1,\"type\":\"result\",\"binary_version\":\"0.3.2\",\"schema_versions\":[1],\"capabilities\":[\"json-output\",\"follow-offset\",\"no-cache\",\"sent\",\"delegation\",\"mirror\"]}");
}
