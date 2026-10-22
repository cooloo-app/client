#define _POSIX_C_SOURCE 200809L
#ifdef _WIN32
#define _CRT_RAND_S
#endif
#include "net.h"
#include "cli.h"
#include "config.h"
#include "record.h"
#include "message_id.h"
#include "machine.h"
#include "win_console.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif
static int tofu;
static char effective[65];
void cooloo_cli_reset(void) { tofu=0;effective[0]=0; }
int cooloo_cli_set_as(const char *id)
{
    size_t i;
    if(strlen(id)!=64)return -1;
    for(i=0;i<64;i++)if(!strchr("0123456789abcdef",id[i]))return -1;
    strcpy(effective,id);return 0;
}
void cooloo_cli_set_tofu(int on) { tofu=on; }
static void public_id(char id[65],const uint8_t sk[32])
{uint8_t pk[32];int i;noise_public_key(pk,sk);for(i=0;i<32;i++)sprintf(id+i*2,"%02x",pk[i]);}
static int connect_client(netconn *c,char self[65])
{
    uint8_t sk[32];char host[256],error[512]={0};int port,rc;
    if(cfg_identity_load(sk)){if(cooloo_machine)machine_error("identity-missing","run cooloo keygen first");else fprintf(stderr,"run cooloo keygen first\n");return -1;}
    public_id(self,sk);cfg_server(host,sizeof host,&port);
    rc=net_connect(c,host,port,sk,tofu,error,sizeof error);
    if(rc==NET_TOFU_UNKNOWN && !cooloo_machine) {
        if (cooloo_console_can_read()) {
            char answer[16];
            fprintf(stderr,"Trust server %s:%d (%s)? [y/N] ",host,port,c->server_fp);
            fflush(stderr);
            if(fgets(answer,sizeof answer,stdin) &&
               (!strcmp(answer,"y\n") || !strcmp(answer,"Y\n") ||
                !strcmp(answer,"yes\n") || !strcmp(answer,"YES\n")))
                rc=net_connect_trust(c,host,port,sk,error,sizeof error);
        } else {
            fprintf(stderr,"Server %s:%d (%s) is untrusted. Verify the fingerprint, then use -y/--tofu to pin it.\n",host,port,c->server_fp);
        }
    }
    memset(sk,0,sizeof sk);
    if(rc){if(cooloo_machine)machine_error(rc==NET_TOFU_UNKNOWN?"server-untrusted":rc==NET_ERR_TOFU_DIFF?"server-key-changed":"network-error",rc==NET_TOFU_UNKNOWN?"server fingerprint is not trusted":error);else fprintf(stderr,"cooloo: %s\n",error);return -1;}
    {
        char line[256],login[65],selected[65],extra;
        if(net_send_line(c,"IDENTITY\n") || net_read_line(c,line,sizeof line) ||
           sscanf(line,"IDENTITY %64[0-9a-f] %64[0-9a-f] %c",login,selected,&extra)!=2 ||
           strcmp(login,self) || strlen(selected)!=64) {
            if(cooloo_machine)machine_error("identity-selection-failed","server IDENTITY response required");
            else fprintf(stderr,"server IDENTITY response required\n");
            net_close(c);return -1;
        }
        strcpy(self,selected);
    }
    if(effective[0]) {
        char line[256];snprintf(line,sizeof line,"AS %s\n",effective);
        if(net_send_line(c,line)||net_read_line(c,line,sizeof line)||strcmp(line,"OK")) {
            if(cooloo_machine){if(!strncmp(line,"ERR ",4))machine_server_error(line);else machine_error("identity-selection-failed","AS did not return OK");}else fprintf(stderr,"identity selection failed: %s\n",line);net_close(c);return -1;
        }
        strcpy(self,effective);
    }
    return 0;
}
int cooloo_cli_keygen(int argc,char **argv)
{
    uint8_t sk[32];char id[65];size_t i;
    (void)argv;if(argc!=2)return 2;
#ifdef _WIN32
    for(i=0;i<32;i++){unsigned int v;if(rand_s(&v))return 1;sk[i]=(uint8_t)v;}
#else
    {FILE *f=fopen("/dev/urandom","rb");if(!f)return 1;i=fread(sk,1,32,f);fclose(f);if(i!=32)return 1;}
#endif
    if(cfg_identity_create(sk)){memset(sk,0,sizeof sk);if(cooloo_machine)machine_error("identity-create-failed","identity exists or cannot be created");else fprintf(stderr,"identity exists or cannot be created\n");return 1;}
    public_id(id,sk);memset(sk,0,sizeof sk);if(cooloo_machine)machine_result("id",id);else printf("%s\n",id);return 0;
}
int cooloo_cli_request(int argc,char **argv)
{
    netconn c;char self[65],line[2048],response[2048];size_t used;int i,rc=1;
    const char *cmd=argv[1];
    if((!strcmp(cmd,"create")||!strcmp(cmd,"meta"))&&argc!=3)return 2;
    if(!strcmp(cmd,"rename")&&argc!=4)return 2;
    if((!strcmp(cmd,"avatar")||!strcmp(cmd,"mirror"))&&argc!=5)return 2;
    if(!strcmp(cmd,"detach")&&argc!=3)return 2;
    if(!strcmp(cmd,"join")) {
        char text[100]; char *sendargs[5]; size_t j;
        if(argc!=3 || strlen(argv[2])!=64)return 2;
        for(j=0;j<64;j++)if(!strchr("0123456789abcdef",argv[2][j]))return 2;
        snprintf(text,sizeof text,"@%s join-request",argv[2]);
        sendargs[0]=argv[0];sendargs[1]="send";sendargs[2]=argv[2];sendargs[3]=text;sendargs[4]=NULL;
        return cooloo_cli_send(4,sendargs);
    }
    if(!strcmp(cmd,"room-mode")) {
        if(argc!=4 || (strcmp(argv[3],"public") && strcmp(argv[3],"private")))return 2;
        if(!strcmp(argv[3],"public"))fprintf(stderr,"Warning: this makes ALL room history public to registered users.\n");
        cmd="ROOMMODE";
    }
    else if(!strcmp(cmd,"delegate")) {
        if(argc!=4)return 2;
        cmd="DELEGATE";
    }
    else if(!strcmp(cmd,"identity")){if(argc!=2)return 2;cmd="IDENTITY";}
    else if(!strcmp(cmd,"create"))cmd="CREATE";
    else if(!strcmp(cmd,"avatar"))cmd="AVATAR";
    else if(!strcmp(cmd,"mirror"))cmd="MIRROR";
    else if(!strcmp(cmd,"detach"))cmd="DETACH";
    else if(!strcmp(cmd,"meta"))cmd="META";
    else if(!strcmp(cmd,"rename"))cmd="RENAME";
    else return 2;
    used=(size_t)snprintf(line,sizeof line,"%s",cmd);
    for(i=2;i<argc;i++) {
        size_t n=strlen(argv[i]);if(strpbrk(argv[i],"\r\n")||used+n+2>=sizeof line)return 2;
        line[used++]=' ';memcpy(line+used,argv[i],n);used+=n;
    }
    line[used++]='\n';line[used]=0;
    if(connect_client(&c,self))return 1;
    if(!net_send_line(&c,line)&&!net_read_line(&c,response,sizeof response)) {if(cooloo_machine)rc=machine_response(cmd,response);else {puts(response);rc=!strncmp(response,"ERR ",4);}}
    net_close(&c);return rc;
}
int cooloo_cli_whoami(int argc,char **argv)
{
    netconn c;char self[65],line[512];int rc=1;
    if(effective[0])return 2; /* WHOAMI is always the login identity. */
    if(connect_client(&c,self))return 1;
    { uint8_t sk[32];if(cfg_identity_load(sk)){net_close(&c);return 1;}public_id(self,sk);memset(sk,0,sizeof sk); }
    if(argc==4&&!strcmp(argv[2],"--register")) {
        if(strlen(argv[3])>64||strpbrk(argv[3],"\r\n")){net_close(&c);return 2;}
        snprintf(line,sizeof line,"HELLO %s\n",argv[3]);
    } else if(argc==2)strcpy(line,"WHOAMI\n");
    else {net_close(&c);return 2;}
    if(!net_send_line(&c,line)&&!net_read_line(&c,line,sizeof line)){
        if(cooloo_machine){
            if(!strncmp(line,"NICK ",5)){printf("{\"schema\":1,\"type\":\"result\",\"id\":");machine_string(self);printf(",\"nickname\":");machine_string(line+5);puts("}");rc=0;}
            else rc=machine_server_error(line);
        }else{printf("%s\n%s\n",self,line);rc=!strncmp(line,"ERR ",4);}
    }
    net_close(&c);return rc;
}
int cooloo_cli_rooms(int argc,char **argv)
{
    netconn c;char self[65],line[512];int rc=1;(void)argv;
    if(argc!=2)return 2;
    if(connect_client(&c,self))return 1;
    if(net_send_line(&c,"ROOMS\n"))goto out;
    while(!net_read_line(&c,line,sizeof line)) {
        if(!strcmp(line,"END")){if(cooloo_machine)puts("{\"schema\":1,\"type\":\"end\"}");rc=0;break;}
        if(cooloo_machine){if(machine_response("ROOM",line))break;}else{puts(line);if(!strncmp(line,"ERR ",4))break;}
    }
out:net_close(&c);return rc;
}
int cooloo_cli_send(int argc,char **argv)
{
    netconn c;char self[65],text[4097],line[512],uuid[33];size_t n=0;int i,rc=1;
    if(argc>=5 && !strcmp(argv[3],"--message-id")) {
        if(!message_id_valid(argv[4]))return 2;
        strcpy(uuid,argv[4]);for(i=3;i<argc-2;i++)argv[i]=argv[i+2];argc-=2;
    } else if(message_id_generate(uuid))return 1;
    if(argc<3||strlen(argv[2])>68||strpbrk(argv[2]," \r\n"))return 2;
    if(argc==3){
        if(cooloo_console_input_is_terminal() && !cooloo_console_can_read())return 1;
        n=fread(text,1,sizeof text,stdin);if(ferror(stdin))return 1;
    }
    else for(i=3;i<argc;i++) {
        size_t k=strlen(argv[i]);if(n+k+(i>3)>4096)return 2;
        if(i>3)text[n++]=' ';
        memcpy(text+n,argv[i],k);n+=k;
    }
    if(!n||n>4096||memchr(text,0,n))return 2;
    if(connect_client(&c,self))return 1;
    if(cooloo_machine)printf("{\"schema\":1,\"type\":\"sending\",\"message_id\":\"%s\"}\n",uuid);
    else fprintf(stderr,"message_id=%s\n",uuid);
    fflush(stdout);
    snprintf(line,sizeof line,"SEND %s %s %zu\n",argv[2],uuid,n);
    if(!net_send_line(&c,line)&&!net_send(&c,text,n)&&!net_read_line(&c,line,sizeof line)){
        if(cooloo_machine)rc=machine_response("SEND",line);else{puts(line);rc=strncmp(line,"OK ",3)!=0;}
    }else if(cooloo_machine)machine_error("send-outcome-unknown","connection lost before send acknowledgement");
    net_close(&c);return rc;
}
static int sync_meta(netconn *c,const char *self,const char *address)
{
    char line[1200];
    snprintf(line,sizeof line,"METAFILE %s\n",address);
    if(net_send_line(c,line)||net_read_line(c,line,sizeof line)||strncmp(line,"META ",5)) {fprintf(stderr,"metadata request failed: %s\n",line);return -1;}
    if(cache_meta(c->server_fp,self,line+5)) {fprintf(stderr,"metadata cache I/O failed\n");return -1;}
    return 0;
}
static int receive(netconn *c,const char *self,int raw,int cache,int follow,long long cursor)
{
    char line[RECORD_MAX],json[RECORD_MAX];struct record r;
    for(;;){
        long long end;size_t len;char extra;
        if(net_read_line(c,line,sizeof line))return 1;
        if(!strcmp(line,"END")){if(follow)return cooloo_machine?machine_error("protocol-error","unexpected FOLLOW end"):1;if(cooloo_machine)machine_offset("end","next_offset",cursor);return 0;}
        if(sscanf(line,"MSG %lld %zu %c",&end,&len,&extra)!=2||end<=cursor||len>=sizeof json){if(cooloo_machine)return machine_server_error(line);fprintf(stderr,"%s\n",line);return 1;}
        if(net_read_line(c,json,sizeof json)||strlen(json)!=len||record_parse(json,&r)){if(cooloo_machine)return machine_error("protocol-error","invalid message payload");fprintf(stderr,"invalid message payload (expected %zu bytes)\n",len);return 1;}
        if(cache&&cache_append(c->server_fp,self,r.to,end,json)){fprintf(stderr,"cache failure (gap, conflict or I/O error)\n");return 1;}
        cursor=end;
        if(cooloo_machine)machine_message(end,json);else if(raw)puts(json);else printf("%lld <%s> %s\n",r.ts,r.from,r.content);
        if(cooloo_machine && machine_output_limited())return machine_error("output-limit","script result exceeds 1 MiB");
        fflush(stdout);
        (void)follow;
    }
}
int cooloo_cli_read(int argc,char **argv)
{
    netconn c;char self[65],line[512];int ai=2,raw=0,rc;
    if(argc>2&&!strcmp(argv[2],"--raw")){raw=1;ai++;}
    if(argc-ai!=2||strlen(argv[ai])>68||strpbrk(argv[ai]," \r\n")||strpbrk(argv[ai+1]," \r\n"))return 2;
    {char *end;size_t i;if(!argv[ai+1][0])return 2;for(i=0;argv[ai+1][i];i++)if(argv[ai+1][i]<'0'||argv[ai+1][i]>'9')return 2;errno=0;(void)strtoll(argv[ai+1],&end,10);if(errno||*end)return 2;}
    if(connect_client(&c,self))return 1;
    if(!cooloo_machine&&sync_meta(&c,self,argv[ai])){net_close(&c);return 1;}
    snprintf(line,sizeof line,"READ %s %s\n",argv[ai],argv[ai+1]);
    rc=net_send_line(&c,line)?1:receive(&c,self,raw,!cooloo_machine&&!strcmp(argv[ai+1],"0"),0,strtoll(argv[ai+1],NULL,10));
    net_close(&c);return rc;
}
int cooloo_cli_follow(int argc,char **argv)
{
    netconn c;char self[65],line[512],resolved[65];long long off;int rc;
    if(argc!=(cooloo_machine?4:3)||strlen(argv[2])>68||strpbrk(argv[2]," \r\n"))return 2;
    if(cooloo_machine){
        char *end;size_t i;
        if(!argv[3][0])return 2;
        for(i=0;argv[3][i];i++)if(argv[3][i]<'0'||argv[3][i]>'9')return 2;
        errno=0;off=strtoll(argv[3],&end,10);if(errno||*end||off<0)return 2;
        if(connect_client(&c,self))return 1;
        snprintf(line,sizeof line,"FOLLOW %s %lld\n",argv[2],off);
        rc=net_send_line(&c,line)?1:receive(&c,self,1,0,1,off);net_close(&c);return rc;
    }
    if(connect_client(&c,self))return 1;
    snprintf(line,sizeof line,"META %s\n",argv[2]);
    if(net_send_line(&c,line)||net_read_line(&c,line,sizeof line)||sscanf(line,"INFO %64s",resolved)!=1){net_close(&c);return 1;}
    if(sync_meta(&c,self,resolved)){net_close(&c);return 1;}
    off=cache_offset(c.server_fp,self,resolved);
    if(off<0){net_close(&c);return 1;}
    snprintf(line,sizeof line,"FOLLOW %s %lld\n",resolved,off);
    rc=net_send_line(&c,line)?1:receive(&c,self,0,1,1,off);
    net_close(&c);return rc;
}
/* Filtered history is a separate view: never append sparse peer inbox records
 * to the contiguous room cache. The CLI prints a fresh, bounded merged snapshot. */
struct history_item { char *json; long long ts,end; char to[65]; };
struct history_view { struct history_item *items; size_t count,cap; char peers[256][65]; size_t npeers; };
static int history_add(struct history_view *h,const struct record *r,long long end,const char *json)
{
    size_t i,n=strlen(json); char *copy;
    for(i=0;i<h->count;i++)if(h->items[i].end==end&&!strcmp(h->items[i].to,r->to))return 0;
    if(h->count==10000){fprintf(stderr,"history limit 10000 messages; use read/sent with offsets\n");return -1;}
    if(h->count==h->cap) {
        size_t cap=h->cap?h->cap*2:128;
        struct history_item *items=realloc(h->items,cap*sizeof *items);
        if(!items)return -1;
        h->items=items;h->cap=cap;
    }
    copy=malloc(n+1);if(!copy)return -1;memcpy(copy,json,n+1);
    h->items[h->count].json=copy;h->items[h->count].ts=r->ts;h->items[h->count].end=end;
    strcpy(h->items[h->count++].to,r->to);return 0;
}
static int history_fetch(netconn *c,const char *self,const char *peer,const char *offset,int sent,struct history_view *h)
{
    char line[RECORD_MAX],json[RECORD_MAX];struct record r;long long end,last=strtoll(offset,NULL,10);size_t len;char extra;
    snprintf(line,sizeof line,"%s %s %s\n",sent?"SENT":"READ",peer,offset);
    if(net_send_line(c,line))return -1;
    for(;;) {
        if(net_read_line(c,line,sizeof line))return -1;
        if((!sent&&!strcmp(line,"END")) || (sent&&sscanf(line,"END %lld %c",&end,&extra)==1&&end>=last)) {
            if(!h&&sent){if(cooloo_machine)machine_offset("end","scan_offset",end);else fprintf(stderr,"scan-offset: %lld\n",end);}
            return 0;
        }
        if(sscanf(line,"MSG %lld %zu %c",&end,&len,&extra)!=2 || end<=last || len>=sizeof json) {if(cooloo_machine)machine_server_error(line);else fprintf(stderr,"%s\n",line);return -1;}
        if(net_read_line(c,json,sizeof json)||strlen(json)!=len||record_parse(json,&r)||strcmp(r.to,peer)||(sent&&strcmp(r.from,self)))return -1;
        last=end;
        if(!h){
            if(cooloo_machine){
                machine_message(end,json);
                if(machine_output_limited())return machine_error("output-limit","script result exceeds 1 MiB");
            }else puts(json);
        }
        else {
            size_t i;
            if(history_add(h,&r,end,json))return -1;
            if(!sent&&strcmp(r.from,self)) {
                for(i=0;i<h->npeers;i++)if(!strcmp(h->peers[i],r.from))break;
                if(i==h->npeers) {
                    if(h->npeers==256){fprintf(stderr,"history peer limit 256; use sent explicitly\n");return -1;}
                    strcpy(h->peers[h->npeers++],r.from);
                }
            }
        }
    }
}
static int history_order(const void *x,const void *y)
{
    const struct history_item *a=x,*b=y;int c;
    if(a->ts!=b->ts)return a->ts<b->ts?-1:1;
    c=strcmp(a->to,b->to);if(c)return c;
    return a->end==b->end?0:a->end<b->end?-1:1;
}
int cooloo_cli_sent(int argc,char **argv)
{
    netconn c;char self[65];int rc;size_t i;
    if(argc!=4||strlen(argv[2])!=64||!argv[3][0])return 2;
    for(i=0;i<64;i++)if(!strchr("0123456789abcdef",argv[2][i]))return 2;
    for(i=0;argv[3][i];i++)if(argv[3][i]<'0'||argv[3][i]>'9')return 2;
    errno=0;(void)strtoll(argv[3],NULL,10);if(errno)return 2;
    if(connect_client(&c,self))return 1;
    rc=history_fetch(&c,self,argv[2],argv[3],1,NULL);net_close(&c);return rc?1:0;
}
int cooloo_cli_history(int argc,char **argv)
{
    netconn c;char self[65];struct history_view h={0};size_t i;int rc=1;(void)argv;
    if(argc!=2)return 2;
    if(connect_client(&c,self))return 1;
    if(history_fetch(&c,self,self,"0",0,&h))goto out;
    for(i=0;i<h.npeers;i++)if(history_fetch(&c,self,h.peers[i],"0",1,&h))goto out;
    qsort(h.items,h.count,sizeof *h.items,history_order);
    for(i=0;i<h.count;i++)puts(h.items[i].json);
    rc=0;
out:
    for(i=0;i<h.count;i++)free(h.items[i].json);
    free(h.items);net_close(&c);return rc;
}
int cooloo_cli_chat(int argc,char **argv)
{
    (void)argc;(void)argv;
    fprintf(stderr,"protocol 2: use GUI for interactive chat, or send/follow in separate terminals\n");return 2;
}
