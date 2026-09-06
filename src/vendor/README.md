# Vendored components (v2 GUI)

Pinned versions; sha256 of the exact bytes vendored. On networks where
github.com is blocked, the mirror URL below is what was actually fetched
(content identical to the canonical source at the same tag/commit).

## stb_truetype.h 6e9f34d5429c
- canonical: https://github.com/nothings/stb/blob/6e9f34d5429cf16790ec43c9bac3f1ee4ad1f760/stb_truetype.h
- fetched: https://cdn.jsdelivr.net/gh/nothings/stb@6e9f34d5429cf16790ec43c9bac3f1ee4ad1f760/stb_truetype.h
- sha256: `ecd30b05e0dd4fea3a13c26810dd9e1992dc379049482c393d5a19e6b5090aab`

## SDL3 3.2.30 (LTS)
- canonical: https://github.com/libsdl-org/SDL/tree/release-3.2.30
- fetched: https://codeload.github.com/libsdl-org/SDL/tar.gz/refs/tags/release-3.2.30
- sha256: `8bfb8f70a72f216dff66cde64b9d7b863d5e8aa46be7f2fd400d7f1f9baafe76`

## Lua 5.4.9
- canonical: https://www.lua.org/versions.html#5.4.9
- fetched: https://www.lua.org/ftp/lua-5.4.9.tar.gz
- sha256: `2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6`

## JetBrainsMono 2.304
- canonical: https://github.com/JetBrains/JetBrainsMono/tree/v2.304
- fetched: https://cdn.jsdelivr.net/gh/JetBrains/JetBrainsMono@v2.304/fonts/ttf/JetBrainsMono-Regular.ttf
- sha256: `a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f`

## Licenses
- SDL3: zlib (vendor/sdl3/LICENSE.txt)
- Lua: MIT (vendor/lua/readme.html / lua.h header)
- stb_truetype: public domain / MIT dual (file header)
- JetBrains Mono: SIL OFL 1.1 (vendor/fonts/OFL.txt)

## Notes
- SDL3 tree trimmed of test/docs/examples/IDE-project dirs
  (VisualC*/Xcode/android-project); CMake static build validated after trim.
- Lua: interpreter (lua.c) and compiler (luac.c) mains excluded; the
  library is compiled directly into the cooloo binary.
- SDL3 came from the git tag archive; CMake build only, which is all we
  use. Public headers are self-contained (apps don't need the generated
  SDL_build_config.h). macOS static link additionally needs
  -framework UniformTypeIdentifiers (UTType, cocoa clipboard).
