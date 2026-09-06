/*
 * font.c - see font.h.
 */
#include "font.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wtype-limits"
#endif
#define STB_TRUETYPE_IMPLEMENTATION
#include "vendor/stb_truetype.h"
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

#define MAX_FONTS   8
#define CACHE_SIZE  8192            /* power of two */

typedef struct {
    stbtt_fontinfo info;
    uint8_t *data;                  /* owned */
    const char *dbg;                /* source path or "embedded" */
} ffont;

typedef struct {
    uint32_t cp;                    /* 0 = empty slot */
    int      size;
    int      fi;                    /* font index, -1 = .notdef */
    glyph    g;
    uint8_t *bmp;                   /* owned (same pointer as g.bmp) */
} cent;

static ffont fonts[MAX_FONTS];
static int   nfonts;
static int   fallback_tried;
static cent  cache[CACHE_SIZE];
static int   cache_used;

/* CJK fallback candidates per platform (doc 4.4: hardcoded paths probed
 * with fopen; first font containing the codepoint wins and is reused). */
static const char *const fallback_paths[] = {
#ifdef __APPLE__
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
#elif defined(_WIN32)
    "C:\\Windows\\Fonts\\msyh.ttc",
    "C:\\Windows\\Fonts\\msjh.ttc",
    "C:\\Windows\\Fonts\\DengXian.ttf",
    "C:\\Windows\\Fonts\\simsun.ttc",
    "C:\\Windows\\Fonts\\simhei.ttf",
#else
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf",
    "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
    "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
#endif
    NULL
};

int font_init(const void *ttf, size_t len)
{
    uint8_t *copy = malloc(len);
    int off;
    if (!copy)
        return -1;
    memcpy(copy, ttf, len);
    off = stbtt_GetFontOffsetForIndex(copy, 0);
    if (off < 0 || !stbtt_InitFont(&fonts[0].info, copy, off)) {
        free(copy);
        return -1;
    }
    fonts[0].data = copy;
    fonts[0].dbg = "embedded";
    nfonts = 1;
    fallback_tried = 0;
    return 0;
}

/* fallback font file bytes: mmap on POSIX (pages fault in on demand -
 * unused pages of a 30MB CJK font cost no RSS), plain read on Windows */
static uint8_t *font_file_bytes(const char *path, size_t *out_len)
{
#ifndef _WIN32
    int fd;
    struct stat st;
    uint8_t *p;
    fd = open(path, O_RDONLY);
    if (fd < 0)
        return NULL;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        close(fd);
        return NULL;
    }
    p = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (p == MAP_FAILED)
        return NULL;
    *out_len = (size_t)st.st_size;
    return p;
#else
    FILE *f;
    long sz;
    uint8_t *buf;
    f = fopen(path, "rb");
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = malloc((size_t)sz);
    if (!buf || fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *out_len = (size_t)sz;
    return buf;
#endif
}

static void font_file_release(uint8_t *p, size_t len)
{
#ifndef _WIN32
    munmap(p, len);
#else
    (void)len;
    free(p);
#endif
}

static int load_fallback(void)
{
    while (fallback_paths[fallback_tried]) {
        const char *path = fallback_paths[fallback_tried++];
        size_t sz = 0;
        uint8_t *buf;
        int off;
        if (nfonts >= MAX_FONTS)
            return -1;
        buf = font_file_bytes(path, &sz);
        if (!buf)
            continue;
        off = stbtt_GetFontOffsetForIndex(buf, 0);
        if (off < 0 || !stbtt_InitFont(&fonts[nfonts].info, buf, off)) {
            font_file_release(buf, sz);
            continue;
        }
        fonts[nfonts].data = buf;   /* kept for process lifetime */
        fonts[nfonts].dbg = path;
        fprintf(stderr, "font: CJK fallback -> %s\n", path);
        return nfonts++;
    }
    return -1;
}

static int font_for_cp(uint32_t cp)
{
    int i;
    if (stbtt_FindGlyphIndex(&fonts[0].info, (int)cp))
        return 0;
    for (i = 1; i < nfonts; i++)
        if (stbtt_FindGlyphIndex(&fonts[i].info, (int)cp))
            return i;
    for (;;) {
        int idx = load_fallback();
        if (idx < 0)
            return -1;
        if (stbtt_FindGlyphIndex(&fonts[idx].info, (int)cp))
            return idx;
    }
}

static uint32_t chash(uint32_t cp, int size)
{
    uint32_t h = cp * 2654435761u;
    h ^= (uint32_t)size * 2246822519u;
    h ^= h >> 13;
    return h & (CACHE_SIZE - 1);
}

static void cache_flush(void)
{
    int i;
    for (i = 0; i < CACHE_SIZE; i++)
        free(cache[i].bmp);
    memset(cache, 0, sizeof cache);
    cache_used = 0;
}

static void rasterize(cent *e, uint32_t cp, int size)
{
    ffont *f;
    float scale;
    int adv = 0, lsb = 0;
    int w = 0, h = 0, xo = 0, yo = 0;
    uint8_t *bmp = NULL;

    e->g.w = e->g.h = e->g.xoff = e->g.yoff = 0;
    e->g.bmp = NULL;
    if (e->fi < 0) {                /* .notdef: blank box of spacing */
        e->g.advance = (float)size * 0.6f;
        return;
    }
    /* em-to-pixels: size means em size (9px Latin advance at 15px).
     * ScaleForPixelHeight would size by the ascender-descender span,
     * which is 1.32x upm for JetBrains Mono -> text came out ~25% small
     * and out of proportion with CJK fallback fonts. */
    f = &fonts[e->fi];
    scale = stbtt_ScaleForMappingEmToPixels(&f->info, (float)size);
    stbtt_GetCodepointHMetrics(&f->info, (int)cp, &adv, &lsb);
    e->g.advance = scale * (float)adv;
    bmp = stbtt_GetCodepointBitmap(&f->info, scale, scale, (int)cp,
                                   &w, &h, &xo, &yo);
    e->g.w = w;
    e->g.h = h;
    e->g.xoff = xo;
    e->g.yoff = yo;
    e->g.bmp = bmp;
    e->bmp = bmp;
}

const glyph *font_glyph(uint32_t cp, int size)
{
    uint32_t h = chash(cp, size);
    uint32_t i;

    for (i = 0; i < CACHE_SIZE; i++) {
        uint32_t slot = (h + i) & (CACHE_SIZE - 1);
        cent *e = &cache[slot];
        if (!e->cp) {
            if (cache_used >= CACHE_SIZE * 3 / 4) {
                cache_flush();
                return font_glyph(cp, size);
            }
            e->cp = cp;
            e->size = size;
            e->fi = font_for_cp(cp);
            rasterize(e, cp, size);
            cache_used++;
            return &e->g;
        }
        if (e->cp == cp && e->size == size)
            return &e->g;
    }
    cache_flush();
    return font_glyph(cp, size);
}

uint32_t font_utf8_next(const char **p, const char *end)
{
    const uint8_t *s = (const uint8_t *)*p;
    uint32_t cp;
    int extra, i;

    if (s >= (const uint8_t *)end || !*s)
        return 0;
    if (s[0] < 0x80) {
        *p += 1;
        return s[0];
    }
    if ((s[0] & 0xE0) == 0xC0) {
        cp = s[0] & 0x1F;
        extra = 1;
    } else if ((s[0] & 0xF0) == 0xE0) {
        cp = s[0] & 0x0F;
        extra = 2;
    } else if ((s[0] & 0xF8) == 0xF0) {
        cp = s[0] & 0x07;
        extra = 3;
    } else {
        *p += 1;
        return 0xFFFD;
    }
    if (s + 1 + extra > (const uint8_t *)end) {
        *p = (const char *)end;
        return 0xFFFD;
    }
    for (i = 1; i <= extra; i++) {
        if ((s[i] & 0xC0) != 0x80) {
            *p += 1;
            return 0xFFFD;
        }
        cp = (cp << 6) | (uint32_t)(s[i] & 0x3F);
    }
    if ((extra == 1 && cp < 0x80) || (extra == 2 && cp < 0x800) ||
        (extra == 3 && cp < 0x10000) || cp > 0x10FFFF ||
        (cp >= 0xD800 && cp <= 0xDFFF)) {
        *p += 1 + extra;
        return 0xFFFD;
    }
    *p += 1 + extra;
    return cp;
}

int font_text_width_n(const char *utf8, size_t n, int size)
{
    const char *p = utf8, *end = utf8 + n;
    float w = 0;
    while (p < end && *p) {
        uint32_t cp = font_utf8_next(&p, end);
        if (!cp)
            break;
        if (cp < 0x20)
            continue;
        w += font_glyph(cp, size)->advance;
    }
    return (int)(w + 0.5f);
}

int font_text_width(const char *utf8, int size)
{
    return font_text_width_n(utf8, strlen(utf8), size);
}

int font_ascent(int size)
{
    int a = 0, d = 0, g = 0;
    stbtt_GetFontVMetrics(&fonts[0].info, &a, &d, &g);
    return (int)(stbtt_ScaleForMappingEmToPixels(&fonts[0].info,
                                                 (float)size) *
                 (float)a + 0.5f);
}

int font_line_height(int size)
{
    int a = 0, d = 0, g = 0, h;
    float s;
    stbtt_GetFontVMetrics(&fonts[0].info, &a, &d, &g);
    s = stbtt_ScaleForMappingEmToPixels(&fonts[0].info, (float)size);
    h = (int)(s * (float)(a - d + g) + 0.999f);
    return (h + 1) & ~1;
}
