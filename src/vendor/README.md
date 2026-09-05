# Vendored components (v2 GUI)

Pinned versions; sha256 of the exact bytes vendored. On networks where
github.com is blocked, the mirror URL below is what was actually fetched
(content identical to the canonical source at the same tag/commit).

## stb_truetype.h 6e9f34d5429c
- canonical: https://github.com/nothings/stb/blob/6e9f34d5429cf16790ec43c9bac3f1ee4ad1f760/stb_truetype.h
- fetched: https://cdn.jsdelivr.net/gh/nothings/stb@6e9f34d5429cf16790ec43c9bac3f1ee4ad1f760/stb_truetype.h
- sha256: `ecd30b05e0dd4fea3a13c26810dd9e1992dc379049482c393d5a19e6b5090aab`

## SDL2 2.30.12
- canonical: https://github.com/libsdl-org/SDL/tree/release-2.30.12
- fetched: https://codeload.github.com/libsdl-org/SDL/tar.gz/refs/tags/release-2.30.12
- sha256: `560da2e54dd8af933e35bd08fb1b6cf80d4f6938c67710fecf13b7e9bdd6c47e`

## Lua 5.4.9
- canonical: https://www.lua.org/versions.html#5.4.9
- fetched: https://www.lua.org/ftp/lua-5.4.9.tar.gz
- sha256: `2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6`

## JetBrainsMono 2.304
- canonical: https://github.com/JetBrains/JetBrainsMono/tree/v2.304
- fetched: https://cdn.jsdelivr.net/gh/JetBrains/JetBrainsMono@v2.304/fonts/ttf/JetBrainsMono-Regular.ttf
- sha256: `a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f`

## Licenses
- SDL2: zlib (vendor/sdl2/LICENSE.txt)
- Lua: MIT (vendor/lua/readme.html / lua.h header)
- stb_truetype: public domain / MIT dual (file header)
- JetBrains Mono: SIL OFL 1.1 (vendor/fonts/OFL.txt)

## Notes
- SDL2 tree trimmed of test/docs/IDE-project dirs (script SDL_TRIM);
  CMake static build validated after trim.
- Lua: interpreter (lua.c) and compiler (luac.c) mains excluded; the
  library is compiled directly into the cooloo binary.
- SDL2 came from the git tag archive (not the autotools dist tarball);
  CMake build only, which is all we use.
