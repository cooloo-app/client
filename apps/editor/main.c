#include "gui.h"
#include "runtime.h"
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char **argv) {
    int rc=runtime_dispatch(argc,argv);const char *dev=NULL;
    if(rc>=0)return rc;
    if(argc==3 && !strcmp(argv[1],"--lua-dev"))dev=argv[2];
    else if(argc!=1){fprintf(stderr,"usage: editor [--lua-dev DIR]\n");return 2;}
    SDL_SetEnvironmentVariable(SDL_GetEnvironment(),"COOLOO_EXECUTABLE",argv[0],true);
    return cooloo_gui_run(dev);
}
