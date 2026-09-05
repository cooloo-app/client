/*
 * font.h - stb_truetype glyph rasterization + cache (04 doc D25/D26, 4.4).
 *
 * Primary font = embedded TTF (font_init from memory). CJK via platform
 * fallback chain, lazy-loaded on first missing glyph. Glyph bitmaps are
 * cached individually (software rendering needs no GPU atlas); the cache
 * is an open-addressing hash keyed by (codepoint, size) with flush-all
 * eviction at 3/4 full (documented simplification vs the doc's LRU).
 */
#ifndef COOLOO_FONT_H
#define COOLOO_FONT_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int      w, h;          /* bitmap size (0x0 for blank glyphs) */
    int      xoff, yoff;    /* draw offset; yoff is baseline-relative */
    float    advance;       /* pen advance in px */
    const uint8_t *bmp;     /* w*h 8-bit coverage; NULL = blank */
} glyph;

int          font_init(const void *ttf, size_t len);
const glyph *font_glyph(uint32_t cp, int size);
int          font_text_width_n(const char *utf8, size_t n, int size);
int          font_text_width(const char *utf8, int size);
int          font_line_height(int size);   /* even-rounded (doc 4.4) */
int          font_ascent(int size);

/* decode one UTF-8 codepoint, advancing *p; U+FFFD on invalid sequences */
uint32_t     font_utf8_next(const char **p, const char *end);

#endif /* COOLOO_FONT_H */
