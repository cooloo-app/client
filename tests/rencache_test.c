/* Exercise the production cache with an instrumented renderer backend. */
#include "rencache.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
struct RenFont {int tab;};
static int width=960,height=640,presents,freed,draws,area;
void ren_get_size(int *w,int *h){*w=width;*h=height;}
void ren_update_rects(RenRect *r,int n){presents++;area=0;for(int i=0;i<n;i++)area+=r[i].width*r[i].height;}
void ren_set_clip_rect(RenRect r){assert(r.x>=0 && r.y>=0 && r.x+r.width<=width && r.y+r.height<=height);}
void ren_draw_rect(RenRect r,RenColor c){(void)r;(void)c;draws++;}
int ren_get_font_width(RenFont *f,const char *s){return (int)strlen(s)*f->tab;}
int ren_get_font_height(RenFont *f){(void)f;return 16;}
int ren_get_font_tab_width(RenFont *f){return f->tab;}
void ren_set_font_tab_width(RenFont *f,int n){f->tab=n;}
int ren_draw_text(RenFont *f,const char *s,int x,int y,RenColor c){(void)y;(void)c;draws++;return x+ren_get_font_width(f,s);}
void ren_free_font(RenFont *f){(void)f;freed++;}
static void frame(int color){
 rencache_begin_frame();rencache_set_clip_rect((RenRect){0,0,width,height});
 rencache_draw_rect((RenRect){0,0,width,height},(RenColor){0,0,0,255});
 rencache_draw_rect((RenRect){10,10,20,20},(RenColor){0,0,color,255});
 rencache_end_frame();
}
int main(void){
 frame(1);assert(presents==1);int previous=draws;
 frame(1);assert(presents==1 && draws==previous);
 frame(2);assert(presents==2 && area<width*height);
 rencache_invalidate();frame(2);assert(presents==3 && area==width*height);
 struct RenFont font={3};rencache_free_font(&font);frame(2);assert(freed==1 && presents==3);
 rencache_begin_frame();rencache_draw_text(&font,"abc",0,0,(RenColor){255,255,255,255});
 font.tab=7;rencache_end_frame();assert(font.tab==7);
 width=10000;height=6000;frame(1);assert(area==width*height);
 rencache_begin_frame();
 for(int i=0;i<210000;i++)rencache_draw_rect((RenRect){0,0,1,1},(RenColor){0,0,i,255});
 rencache_end_frame();assert(draws>210000);
 rencache_free_font(&font);rencache_shutdown();assert(freed==2);
 puts("rencache: idle, dirty regions, invalidation, deferred free, tab snapshot, large screen/command stream OK");return 0;
}
