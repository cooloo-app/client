#include "gui.h"
#include <stdio.h>
#include <string.h>
/* Passed directly to Lua after its host table is initialized, never evaluated. */
int cooloo_text_file_count;
char **cooloo_text_files;
int main(int argc,char **argv) {
    const char *dev=NULL;
    int i=1;
    if(i<argc && !strcmp(argv[i],"--help")) {
        puts("usage: cooloo-text [--lua-dev DIR] [--] [FILE ...]");return 0;
    }
    if(i<argc && !strcmp(argv[i],"--lua-dev")) {
        if(i+1>=argc){fprintf(stderr,"--lua-dev requires DIR\n");return 2;}
        dev=argv[i+1];i+=2;
    }
    if(i<argc && !strcmp(argv[i],"--"))i++;
    else if(i<argc && argv[i][0]=='-'){fprintf(stderr,"unknown option: %s\n",argv[i]);return 2;}
    cooloo_text_file_count=argc-i;cooloo_text_files=argv+i;
    return cooloo_gui_run(dev);
}
