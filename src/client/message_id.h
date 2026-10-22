#ifndef COOLOO_MESSAGE_ID_H
#define COOLOO_MESSAGE_ID_H
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <bcrypt.h>
#endif
static inline int message_id_valid(const char *s)
{
    size_t i;
    if(!s || strlen(s)!=32 || s[12]!='4' || !strchr("89ab",s[16]))return 0;
    for(i=0;i<32;i++)if(!strchr("0123456789abcdef",s[i]))return 0;
    return 1;
}
static inline int message_id_generate(char out[33])
{
    unsigned char b[16];size_t i;
#ifdef _WIN32
    /* Resolve the OS RNG without imposing a new link dependency on text builds. */
    HMODULE lib=LoadLibraryA("bcrypt.dll");
    typedef NTSTATUS (WINAPI *rng_fn)(BCRYPT_ALG_HANDLE,PUCHAR,ULONG,ULONG);
    rng_fn rng=lib?(rng_fn)(void *)GetProcAddress(lib,"BCryptGenRandom"):NULL;
    if(!rng){if(lib)FreeLibrary(lib);return -1;}
    NTSTATUS rc=rng(NULL,b,sizeof b,BCRYPT_USE_SYSTEM_PREFERRED_RNG);FreeLibrary(lib);
    if(rc<0)return -1;
#else
    FILE *f=fopen("/dev/urandom","rb");size_t n;
    if(!f)return -1;
    n=fread(b,1,sizeof b,f);fclose(f);if(n!=sizeof b)return -1;
#endif
    b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
    for(i=0;i<16;i++)snprintf(out+i*2,3,"%02x",b[i]);
    return 0;
}
#endif
