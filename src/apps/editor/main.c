#include "gui.h"
#include "luabind.h"
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>
#endif
/* Passed directly to Lua after its host table is initialized, never evaluated. */
int cooloo_text_file_count;
char **cooloo_text_files;
int cooloo_text_safe_mode;
const char *cooloo_text_executable;
int main(int argc,char **argv) {
#ifdef _WIN32
    /* SDL paths and Lua strings use UTF-8, not the current ANSI codepage. */
    int count;
    wchar_t **wide=CommandLineToArgvW(GetCommandLineW(),&count);
    if(!wide)return 1;
    argv=calloc((size_t)count+1,sizeof *argv);
    if(!argv){LocalFree(wide);return 1;}
    for(int n=0;n<count;n++) {
        int len=WideCharToMultiByte(CP_UTF8,0,wide[n],-1,NULL,0,NULL,NULL);
        argv[n]=malloc((size_t)len);
        if(!argv[n])return 1;
        WideCharToMultiByte(CP_UTF8,0,wide[n],-1,argv[n],len,NULL,NULL);
    }
    LocalFree(wide);argc=count;
#endif
    const char *dev=NULL;
    int i=1;
    luabind_set_args(argc,argv);
    cooloo_text_executable=argv[0];
    for(;i<argc;i++) {
        if(!strcmp(argv[i],"--")){i++;break;}
        if(!strcmp(argv[i],"--help")) {
            puts("usage: cooloo-text [--safe-mode] [--lua-dev DIR] [--] [FILE|DIR ...]");
            puts("Projects may execute .lite_project.lua; --safe-mode skips external plugins/user/project modules.");
            return 0;
        }
        if(!strcmp(argv[i],"--safe-mode")){cooloo_text_safe_mode=1;continue;}
        if(!strcmp(argv[i],"--lua-dev")) {
            if(i+1>=argc){fprintf(stderr,"--lua-dev requires DIR\n");return 2;}
            dev=argv[++i];continue;
        }
        if(argv[i][0]=='-'){fprintf(stderr,"unknown option: %s\n",argv[i]);return 2;}
        break;
    }
    cooloo_text_file_count=argc-i;cooloo_text_files=argv+i;
    return cooloo_gui_run(dev);
}
