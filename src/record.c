#define _POSIX_C_SOURCE 200809L
#include "record.h"
#include "config.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <windows.h>
#define mkdir(p,m) _mkdir(p)
#else
#include <unistd.h>
#include <sys/file.h>
#endif
static int hex(char c) { return c >= '0' && c <= '9' ? c-'0' : c >= 'a' && c <= 'f' ? c-'a'+10 : -1; }
static int id(const char *s) { size_t i; if (!s || strlen(s)!=64) return 0; for(i=0;i<64;i++) if(hex(s[i])<0)return 0; return 1; }
static int string(const char **p, char *out, size_t cap)
{
    size_t n=0;
    if (*(*p)++ != '"') return -1;
    while (**p && **p != '"') {
        unsigned char c=(unsigned char)*(*p)++;
        if (c=='\\') {
            c=(unsigned char)*(*p)++;
            if (c=='u') {
                int a,b;
                if (strlen(*p)<4 || (*p)[0]!='0' || (*p)[1]!='0' || (a=hex((*p)[2]))<0 || (b=hex((*p)[3]))<0) return -1;
                c=(unsigned char)(a*16+b); *p+=4;
            } else if (c=='n') c='\n'; else if(c=='r')c='\r'; else if(c=='t')c='\t';
            else if(c!='"' && c!='\\' && c!='/')return -1;
        }
        if (!c || n+1>=cap)return -1;
        out[n++]=(char)c;
    }
    if (**p!='"')return -1;
    (*p)++; out[n]=0; return 0;
}
static int literal(const char **p,const char *s)
{size_t n=strlen(s);if(strncmp(*p,s,n))return -1;*p+=n;return 0;}
int record_parse(const char *p,struct record *r)
{
    char *e;
    if(literal(&p,"{\"ts\":"))return -1;
    errno=0;r->ts=strtoll(p,&e,10);if(errno||e==p||r->ts<0)return -1;p=e;
    if(literal(&p,",\"from\":")||string(&p,r->from,sizeof r->from)||!id(r->from)||
       literal(&p,",\"to\":")||string(&p,r->to,sizeof r->to)||!id(r->to)||
       literal(&p,",\"content\":")||string(&p,r->content,sizeof r->content)||strcmp(p,"}"))return -1;
    return 0;
}
static int dir(const char *p){struct stat st;if(!mkdir(p,0700))return 0;return errno==EEXIST&&!stat(p,&st)&&S_ISDIR(st.st_mode)?0:-1;}
static int cache_path(char *p,size_t cap,const char *server,const char *self,const char *room)
{
    char base[1024];int n;
    if(!id(server)||!id(self)||!id(room)||cfg_dir(base,sizeof base))return -1;
    n=snprintf(p,cap,"%s/cache",base);if(n<0||(size_t)n>=cap||dir(p))return -1;
    n=snprintf(p,cap,"%s/cache/%s",base,server);if(n<0||(size_t)n>=cap||dir(p))return -1;
    n=snprintf(p,cap,"%s/cache/%s/%s",base,server,self);if(n<0||(size_t)n>=cap||dir(p))return -1;
    n=snprintf(p,cap,"%s/cache/%s/%s/rooms",base,server,self);if(n<0||(size_t)n>=cap||dir(p))return -1;
    n=snprintf(p,cap,"%s/cache/%s/%s/rooms/%s",base,server,self,room);if(n<0||(size_t)n>=cap||dir(p))return -1;
    n=snprintf(p,cap,"%s/cache/%s/%s/rooms/%s/messages.jsonl",base,server,self,room);
    return n<0||(size_t)n>=cap?-1:0;
}
int cache_meta(const char *server,const char *self,const char *json)
{
    char room[65],p[1400],tmp[1450];const char *s=json;FILE *f;int rc=0;
    if(literal(&s,"{\"id\":")||string(&s,room,sizeof room)||!id(room)||
       strlen(json)>1023||strchr(json,'\n')||cache_path(p,sizeof p,server,self,room))return -1;
    strcpy(strrchr(p,'/')+1,".meta");
#ifdef _WIN32
    snprintf(tmp,sizeof tmp,"%s.%lu.tmp",p,(unsigned long)GetCurrentProcessId());
#else
    snprintf(tmp,sizeof tmp,"%s.%ld.tmp",p,(long)getpid());
#endif
    f=fopen(tmp,"wb");if(!f)return -1;
    if(fputs(json,f)==EOF||fputc('\n',f)==EOF)rc=-1;
    if(fclose(f))rc=-1;
#ifdef _WIN32
    if(!rc&&!MoveFileExA(tmp,p,MOVEFILE_REPLACE_EXISTING))rc=-1;
#else
    if(!rc&&rename(tmp,p))rc=-1;
#endif
    if(rc)remove(tmp);
    return rc;
}
static int lock(FILE *f)
{
#ifdef _WIN32
    OVERLAPPED o={0};return LockFileEx((HANDLE)_get_osfhandle(_fileno(f)),LOCKFILE_EXCLUSIVE_LOCK,0,MAXDWORD,MAXDWORD,&o)?0:-1;
#else
    return flock(fileno(f),LOCK_EX);
#endif
}
static int truncate_file(FILE *f,long long n)
{
#ifdef _WIN32
    return _chsize_s(_fileno(f),n)?-1:0;
#else
    return ftruncate(fileno(f),(off_t)n);
#endif
}
/* Scan complete records under the process-shared file lock. Discard only an
 * incomplete final record; malformed complete records fail closed. */
static long long scan(FILE *f)
{
    char line[RECORD_MAX];struct record r;long long off=0;
    rewind(f);
    while(fgets(line,sizeof line,f)) {
        size_t n=strlen(line);
        if(!n||line[n-1]!='\n') {if(!feof(f))return -1;if(truncate_file(f,off))return -1;break;}
        line[n-1]=0;if(record_parse(line,&r))return -1;off+=(long long)n;
    }
    return ferror(f)?-1:off;
}
static FILE *open_cache(const char *server,const char *self,const char *room)
{
    char p[1400];FILE *f;
    if(cache_path(p,sizeof p,server,self,room))return NULL;
    f=fopen(p,"a+b");if(f&&lock(f)){fclose(f);return NULL;}return f;
}
long long cache_offset(const char *server,const char *self,const char *room)
{FILE *f=open_cache(server,self,room);long long n;if(!f)return -1;n=scan(f);fclose(f);return n;}
int cache_read(const char *server,const char *self,const char *room,cache_visit visit,void *ctx)
{
    FILE *f=open_cache(server,self,room);char line[RECORD_MAX];long long end=0;int rc=0;
    if(!f)return -1;
    if(scan(f)<0){fclose(f);return -1;}
    rewind(f);
    while(fgets(line,sizeof line,f)) {
        size_t n=strlen(line);end+=(long long)n;line[n-1]=0;
        rc=visit(ctx,end,line);if(rc)break;
    }
    if(ferror(f))rc=-1;
    fclose(f);return rc;
}
int cache_append(const char *server,const char *self,const char *room,long long end,const char *json)
{
    FILE *f;struct record r;long long off;size_t n=strlen(json);int rc=-1;
    if(record_parse(json,&r)||strcmp(room,r.to)||end<(long long)n+1)return -1;
    f=open_cache(server,self,room);if(!f)return -1;off=scan(f);if(off<0)goto out;
    if(end<=off) {
        char old[RECORD_MAX];
        if(n+2>sizeof old||end-(long long)n-1>LONG_MAX)goto out;
        if(fseek(f,(long)(end-(long long)n-1),SEEK_SET)||fread(old,1,n+1,f)!=n+1)goto out;
        rc=memcmp(old,json,n)||old[n]!='\n'?-1:0;goto out;
    }
    if(end!=off+(long long)n+1||fseek(f,0,SEEK_END))goto out;
    if(fwrite(json,1,n,f)!=n||fputc('\n',f)==EOF||fflush(f))goto out;
#ifdef _WIN32
    if(_commit(_fileno(f)))goto out;
#else
    if(fsync(fileno(f)))goto out;
#endif
    rc=0;
out:
    fclose(f);return rc;
}
