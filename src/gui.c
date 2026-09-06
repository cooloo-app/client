/*
 * gui.c - see gui.h.
 *
 * Framebuffer: own ARGB8888 software canvas blitted to the window surface
 * each present (D25 software rendering; no SDL renderer, no HiDPI scaling -
 * 1:1 pixels, documented minimal choice).
 */
#include "gui.h"
#include "font.h"
#include "luabind.h"
#include "config.h"

/* SDL_MAIN_HANDLED: plain main() everywhere (single exe is CLI+GUI) */
#define SDL_MAIN_HANDLED
#include <SDL3/SDL.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

extern const unsigned char cooloo_embedded_font[];
extern const unsigned int  cooloo_embedded_font_len;

static SDL_Window  *win;
static SDL_Surface *canvas;
static int scr_w = 960, scr_h = 640;
static SDL_Rect clip_rect;
static int clip_active;

int gui_screen_w(void) { return scr_w; }
int gui_screen_h(void) { return scr_h; }

static int make_canvas(int w, int h)
{
    if (canvas)
        SDL_DestroySurface(canvas);
    canvas = SDL_CreateSurface(w, h, SDL_PIXELFORMAT_ARGB8888);
    if (!canvas) {
        fprintf(stderr, "cooloo gui: canvas: %s\n", SDL_GetError());
        return -1;
    }
    SDL_SetSurfaceClipRect(canvas, NULL);
    return 0;
}

void gui_set_clip(int x, int y, int w, int h)
{
    clip_rect.x = x;
    clip_rect.y = y;
    clip_rect.w = w;
    clip_rect.h = h;
    clip_active = 1;
    SDL_SetSurfaceClipRect(canvas, &clip_rect);
}

void gui_clear_clip(void)
{
    clip_active = 0;
    SDL_SetSurfaceClipRect(canvas, NULL);
}

void gui_draw_rect(int x, int y, int w, int h, unsigned rgb)
{
    SDL_Rect r = { x, y, w, h };
    SDL_FillSurfaceRect(canvas, &r,
                        SDL_MapSurfaceRGB(canvas, (rgb >> 16) & 0xff,
                                          (rgb >> 8) & 0xff, rgb & 0xff));
}

void gui_draw_text(int x, int y, const char *utf8, unsigned rgb, int size)
{
    const char *p = utf8, *end = utf8 + strlen(utf8);
    int pen_x = x, base_y = y + font_ascent(size);
    int fr = (int)((rgb >> 16) & 0xff), fg = (int)((rgb >> 8) & 0xff),
        fb = (int)(rgb & 0xff);

    /* canvas is a plain software surface: pixels directly accessible */
    while (p < end && *p) {
        uint32_t cp = font_utf8_next(&p, end);
        const glyph *g;
        int gx, gy, i, j;
        if (!cp)
            break;
        if (cp < 0x20)
            continue;
        g = font_glyph(cp, size);
        gx = pen_x + g->xoff;
        gy = base_y + g->yoff;
        if (g->bmp) {
            for (j = 0; j < g->h; j++) {
                int py = gy + j;
                const uint8_t *row;
                if (py < 0 || py >= canvas->h)
                    continue;
                if (clip_active &&
                    (py < clip_rect.y || py >= clip_rect.y + clip_rect.h))
                    continue;
                row = g->bmp + j * g->w;
                for (i = 0; i < g->w; i++) {
                    int px = gx + i;
                    unsigned a;
                    uint8_t *px8;
                    if (px < 0 || px >= canvas->w)
                        continue;
                    a = row[i];
                    if (!a)
                        continue;
                    if (clip_active &&
                        (px < clip_rect.x ||
                         px >= clip_rect.x + clip_rect.w))
                        continue;
                    /* ARGB8888 little-endian bytes: B G R A */
                    px8 = (uint8_t *)canvas->pixels +
                          py * canvas->pitch + px * 4;
                    if (a == 255) {
                        px8[0] = (uint8_t)fb;
                        px8[1] = (uint8_t)fg;
                        px8[2] = (uint8_t)fr;
                        px8[3] = 255;
                    } else {
                        px8[0] = (uint8_t)((a * (unsigned)fb +
                                            (255 - a) * px8[0]) / 255);
                        px8[1] = (uint8_t)((a * (unsigned)fg +
                                            (255 - a) * px8[1]) / 255);
                        px8[2] = (uint8_t)((a * (unsigned)fr +
                                            (255 - a) * px8[2]) / 255);
                        px8[3] = 255;
                    }
                }
            }
        }
        pen_x += (int)(g->advance + 0.5f);
    }
}

void gui_set_ime_rect(int x, int y, int w, int h)
{
    SDL_Rect r = { x, y, w, h };
    SDL_SetTextInputArea(win, &r, 0);
}

void gui_present(void)
{
    SDL_Surface *ws = SDL_GetWindowSurface(win);
    if (!ws)
        return;
    if (ws->w != canvas->w || ws->h != canvas->h)
        if (make_canvas(ws->w, ws->h) != 0)
            return;
    SDL_BlitSurface(canvas, NULL, ws, NULL);
    SDL_UpdateWindowSurface(win);
}

/* ---------------------------------------------------------------- */
/* event translation                                                */
/* ---------------------------------------------------------------- */

static const char *special_key(SDL_Keycode k)
{
    switch (k) {
    case SDLK_RETURN:    return "return";
    case SDLK_KP_ENTER:  return "return";
    case SDLK_BACKSPACE: return "backspace";
    case SDLK_DELETE:    return "delete";
    case SDLK_TAB:       return "tab";
    case SDLK_ESCAPE:    return "escape";
    case SDLK_SPACE:     return "space";
    case SDLK_PAGEUP:    return "pageup";
    case SDLK_PAGEDOWN:  return "pagedown";
    case SDLK_UP:        return "up";
    case SDLK_DOWN:      return "down";
    case SDLK_LEFT:      return "left";
    case SDLK_RIGHT:     return "right";
    case SDLK_HOME:      return "home";
    case SDLK_END:       return "end";
    default:             return NULL;
    }
}

static void on_keydown(SDL_Keycode key, SDL_Keymod kmod)
{
    char name[32];
    const char *sp = special_key(key);
    int mod = 0;

    if (sp) {
        snprintf(name, sizeof name, "%s", sp);
    } else {
        const char *sn = SDL_GetKeyName(key);
        size_t i, n = sn ? strlen(sn) : 0;
        if (!n || n >= sizeof name)
            return;
        for (i = 0; i < n; i++)
            name[i] = (char)tolower((unsigned char)sn[i]);
        name[n] = '\0';
    }
    if (kmod & SDL_KMOD_CTRL)  mod |= 1;
    if (kmod & SDL_KMOD_ALT)   mod |= 2;
    if (kmod & SDL_KMOD_SHIFT) mod |= 4;
    if (kmod & SDL_KMOD_GUI)   mod |= 8;
    luabind_ev_key(name, mod);
}

static void translate(SDL_Event *ev)
{
    switch (ev->type) {
    case SDL_EVENT_QUIT:
        luabind_ev_quit();
        break;
    case SDL_EVENT_KEY_DOWN:
        on_keydown(ev->key.key, ev->key.mod);
        break;
    case SDL_EVENT_TEXT_INPUT:
        luabind_ev_text(ev->text.text);
        break;
    case SDL_EVENT_TEXT_EDITING:
        luabind_ev_ime(ev->edit.text, ev->edit.start);
        break;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
        luabind_ev_mouse(ev->type == SDL_EVENT_MOUSE_BUTTON_DOWN ? "down" : "up",
                         (int)ev->button.x, (int)ev->button.y,
                         ev->button.button, 0, 0);
        break;
    case SDL_EVENT_MOUSE_WHEEL: {
        int wx = ev->wheel.integer_x, wy = ev->wheel.integer_y;
        if (ev->wheel.direction == SDL_MOUSEWHEEL_FLIPPED) {
            wx = -wx;
            wy = -wy;
        }
        luabind_ev_mouse("wheel", 0, 0, 0, wx, wy);
        break;
    }
    case SDL_EVENT_WINDOW_RESIZED:
        scr_w = ev->window.data1;
        scr_h = ev->window.data2;
        if (make_canvas(scr_w, scr_h) == 0)
            luabind_ev_resize(scr_w, scr_h);
        break;
    }
}

/* ---------------------------------------------------------------- */
/* main loop                                                        */
/* ---------------------------------------------------------------- */

int cooloo_gui_run(const char *lua_dev_dir)
{
    char val[32];
    int w = 960, h = 640, quit = 0;
    Uint64 last;

    if (getenv("COOLOO_PROBE_STARTUP"))
        fprintf(stderr, "probe: main enter %llu ms\n",
                (unsigned long long)SDL_GetTicks());
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "cooloo gui: SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    if (getenv("COOLOO_PROBE_STARTUP"))
        fprintf(stderr, "probe: SDL_Init done %llu ms\n",
                (unsigned long long)SDL_GetTicks());
    if (cfg_get("gui.w", val, sizeof val) == 0)
        w = atoi(val);
    if (cfg_get("gui.h", val, sizeof val) == 0)
        h = atoi(val);
    if (w < 320)
        w = 320;
    if (h < 240)
        h = 240;

    win = SDL_CreateWindow("cooloo", w, h, SDL_WINDOW_RESIZABLE);
    if (!win) {
        fprintf(stderr, "cooloo gui: window: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_SetWindowPosition(win, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
    SDL_GetWindowSize(win, &scr_w, &scr_h);
    if (getenv("COOLOO_PROBE_STARTUP"))
        fprintf(stderr, "probe: window created %llu ms\n",
                (unsigned long long)SDL_GetTicks());
    if (make_canvas(scr_w, scr_h) != 0)
        return 1;
    if (font_init(cooloo_embedded_font, cooloo_embedded_font_len) != 0) {
        fprintf(stderr, "cooloo gui: bad embedded font\n");
        return 1;
    }
    if (luabind_init(lua_dev_dir) != 0)
        return 1;
    SDL_StartTextInput(win);
    if (getenv("COOLOO_PROBE_STARTUP"))
        fprintf(stderr, "probe: lua+font ready %llu ms\n",
                (unsigned long long)SDL_GetTicks());

    last = SDL_GetTicks();
    while (!quit) {
        Uint64 now = SDL_GetTicks();
        double dt = (double)(now - last) / 1000.0;
        SDL_Event ev;

        last = now;
        luabind_events_begin();
        if (SDL_WaitEventTimeout(&ev, 16)) {        /* ~60fps cap (D30) */
            translate(&ev);
            while (SDL_PollEvent(&ev))
                translate(&ev);
        }
        luabind_net_pump();
        quit = luabind_frame(dt);
        if (getenv("COOLOO_PROBE_STARTUP")) {   /* acceptance measurement */
            fprintf(stderr, "cooloo gui: first frame in %llu ms\n",
                    (unsigned long long)(SDL_GetTicks() - last));
            break;
        }
    }

    {
        char b[16];
        snprintf(b, sizeof b, "%d", scr_w);
        cfg_set("gui.w", b);
        snprintf(b, sizeof b, "%d", scr_h);
        cfg_set("gui.h", b);
    }
    luabind_shutdown();
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
