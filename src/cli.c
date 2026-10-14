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
    if(rc){fprintf(stderr,"cooloo: %s\n",error);return -1;}return 0;
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
    if(!strcmp(cmd,"create"))cmd="CREATE";
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
int cooloo_cli_chat(int argc,char **argv)
{
    (void)argc;(void)argv;
    fprintf(stderr,"protocol 2: use GUI for interactive chat, or send/follow in separate terminals\n");return 2;
}
