#define _POSIX_C_SOURCE 200809L
#ifdef _WIN32
#define _CRT_RAND_S
#endif
#include "net.h"
#include "cli.h"
#include "config.h"
#include "record.h"
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
    uint8_t sk[32];char host[256],error[512];int port,rc;
    if(cfg_identity_load(sk)){fprintf(stderr,"run cooloo keygen first\n");return -1;}
    public_id(self,sk);cfg_server(host,sizeof host,&port);
    rc=net_connect(c,host,port,sk,tofu,error,sizeof error);
    if(rc==NET_TOFU_UNKNOWN) {
        char answer[16];fprintf(stderr,"Trust server %s:%d (%s)? [y/N] ",host,port,c->server_fp);
        if(fgets(answer,sizeof answer,stdin)&&(answer[0]=='y'||answer[0]=='Y'))rc=net_connect_trust(c,host,port,sk,error,sizeof error);
    }
    memset(sk,0,sizeof sk);
    if(rc){fprintf(stderr,"cooloo: %s\n",error);return -1;}
    if(effective[0]) {
        char line[256];snprintf(line,sizeof line,"AS %s\n",effective);
        if(net_send_line(c,line)||net_read_line(c,line,sizeof line)||strcmp(line,"OK")) {
            fprintf(stderr,"identity selection failed: %s\n",line);net_close(c);return -1;
        }
        strcpy(self,effective);
    }
    return 0;
}
int cooloo_cli_keygen(int argc,char **argv)
{
    uint8_t sk[32];char id[65];size_t i;
    (void)argc;(void)argv;
#ifdef _WIN32
    for(i=0;i<32;i++){unsigned int v;if(rand_s(&v))return 1;sk[i]=(uint8_t)v;}
#else
    {FILE *f=fopen("/dev/urandom","rb");if(!f)return 1;i=fread(sk,1,32,f);fclose(f);if(i!=32)return 1;}
#endif
    if(cfg_identity_create(sk)){fprintf(stderr,"identity exists or cannot be created\n");return 1;}
    public_id(id,sk);memset(sk,0,sizeof sk);printf("%s\n",id);return 0;
}
int cooloo_cli_request(int argc,char **argv)
{
    netconn c;char self[65],line[2048],response[2048];size_t used;int i,rc=1;
    const char *cmd=argv[1];
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
    else if(!strcmp(cmd,"create"))cmd="CREATE";
    else if(!strcmp(cmd,"avatar"))cmd="AVATAR";
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
    if(!net_send_line(&c,line)&&!net_read_line(&c,response,sizeof response)) {puts(response);rc=!strncmp(response,"ERR ",4);}
    net_close(&c);return rc;
}
int cooloo_cli_whoami(int argc,char **argv)
{
    netconn c;char self[65],line[512];int rc=1;
    if(connect_client(&c,self))return 1;
    if(argc==4&&!strcmp(argv[2],"--register")) {
        if(strlen(argv[3])>64||strpbrk(argv[3],"\r\n")){net_close(&c);return 2;}
        snprintf(line,sizeof line,"HELLO %s\n",argv[3]);
    } else if(argc==2)strcpy(line,"WHOAMI\n");
    else {net_close(&c);return 2;}
    if(!net_send_line(&c,line)&&!net_read_line(&c,line,sizeof line)){printf("%s\n%s\n",self,line);rc=!strncmp(line,"ERR ",4);}
    net_close(&c);return rc;
}
int cooloo_cli_rooms(int argc,char **argv)
{
    netconn c;char self[65],line[512];int rc=1;(void)argc;(void)argv;
    if(connect_client(&c,self))return 1;
    if(net_send_line(&c,"ROOMS\n"))goto out;
    while(!net_read_line(&c,line,sizeof line)) {
        if(!strcmp(line,"END")){rc=0;break;}puts(line);if(!strncmp(line,"ERR ",4))break;
    }
out:net_close(&c);return rc;
}
int cooloo_cli_send(int argc,char **argv)
{
    netconn c;char self[65],text[4097],line[512];size_t n=0;int i,rc=1;
    if(argc<3||strlen(argv[2])>68||strpbrk(argv[2]," \r\n"))return 2;
    if(argc==3){n=fread(text,1,sizeof text,stdin);if(ferror(stdin))return 1;}
    else for(i=3;i<argc;i++) {
        size_t k=strlen(argv[i]);if(n+k+(i>3)>4096)return 2;
        if(i>3)text[n++]=' ';
        memcpy(text+n,argv[i],k);n+=k;
    }
    if(!n||n>4096)return 2;
    if(connect_client(&c,self))return 1;
    snprintf(line,sizeof line,"SEND %s %zu\n",argv[2],n);
    if(!net_send_line(&c,line)&&!net_send(&c,text,n)&&!net_read_line(&c,line,sizeof line)){puts(line);rc=strncmp(line,"OK ",3)!=0;}
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
static int receive(netconn *c,const char *self,int raw,int cache,int follow)
{
    char line[RECORD_MAX],json[RECORD_MAX];struct record r;
    for(;;){
        long long end;size_t len;char extra;
        if(net_read_line(c,line,sizeof line))return 1;
        if(!strcmp(line,"END"))return 0;
        if(sscanf(line,"MSG %lld %zu %c",&end,&len,&extra)!=2){fprintf(stderr,"%s\n",line);return 1;}
        if(net_read_line(c,json,sizeof json)||strlen(json)!=len||record_parse(json,&r)){fprintf(stderr,"invalid message payload (expected %zu bytes)\n",len);return 1;}
        if(cache&&cache_append(c->server_fp,self,r.to,end,json)){fprintf(stderr,"cache failure (gap, conflict or I/O error)\n");return 1;}
        if(raw)puts(json);else printf("%lld <%s> %s\n",r.ts,r.from,r.content);
        fflush(stdout);
        (void)follow;
    }
}
int cooloo_cli_read(int argc,char **argv)
{
    netconn c;char self[65],line[512];int ai=2,raw=0,rc;
    if(argc>2&&!strcmp(argv[2],"--raw")){raw=1;ai++;}
    if(argc-ai!=2||strlen(argv[ai])>68||strpbrk(argv[ai]," \r\n")||strpbrk(argv[ai+1]," \r\n"))return 2;
    if(connect_client(&c,self))return 1;
    if(sync_meta(&c,self,argv[ai])){net_close(&c);return 1;}
    snprintf(line,sizeof line,"READ %s %s\n",argv[ai],argv[ai+1]);
    rc=net_send_line(&c,line)?1:receive(&c,self,raw,!strcmp(argv[ai+1],"0"),0);
    net_close(&c);return rc;
}
int cooloo_cli_follow(int argc,char **argv)
{
    netconn c;char self[65],line[512],resolved[65];long long off;int rc;
    if(argc!=3||strlen(argv[2])>68||strpbrk(argv[2]," \r\n"))return 2;
    if(connect_client(&c,self))return 1;
    snprintf(line,sizeof line,"META %s\n",argv[2]);
    if(net_send_line(&c,line)||net_read_line(&c,line,sizeof line)||sscanf(line,"INFO %64s",resolved)!=1){net_close(&c);return 1;}
    if(sync_meta(&c,self,resolved)){net_close(&c);return 1;}
    off=cache_offset(c.server_fp,self,resolved);
    if(off<0){net_close(&c);return 1;}
    snprintf(line,sizeof line,"FOLLOW %s %lld\n",resolved,off);
    rc=net_send_line(&c,line)?1:receive(&c,self,0,1,1);
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
    char line[RECORD_MAX],json[RECORD_MAX];struct record r;long long end,last=0;size_t len;char extra;
    snprintf(line,sizeof line,"%s %s %s\n",sent?"SENT":"READ",peer,offset);
    if(net_send_line(c,line))return -1;
    for(;;) {
        if(net_read_line(c,line,sizeof line))return -1;
        if((!sent&&!strcmp(line,"END")) || (sent&&sscanf(line,"END %lld %c",&end,&extra)==1&&end>=last)) {
            if(!h&&sent)fprintf(stderr,"scan-offset: %lld\n",end);
            return 0;
        }
        if(sscanf(line,"MSG %lld %zu %c",&end,&len,&extra)!=2 || end<=last) {fprintf(stderr,"%s\n",line);return -1;}
        if(net_read_line(c,json,sizeof json)||strlen(json)!=len||record_parse(json,&r)||strcmp(r.to,peer)||(sent&&strcmp(r.from,self)))return -1;
        last=end;
        if(!h)puts(json);
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
