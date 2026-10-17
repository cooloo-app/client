# Lite provenance

Source: https://github.com/rxi/lite
Commit: `38bd9b3326c02e43f244623f97a622b11f074415`
License: MIT, retained in LICENSE.

Vendored Lua core lives in `modules/editor/core`; all 16 upstream default plugins
are copied into `modules/editor/plugins`. `user-init.lua` is the upstream user
module example. `src/gui.c` ports the upstream C `system.poll_event` event
bridge to SDL3; see [event contract](../../modules/EVENTS.md).

`src/renderer.{c,h}`, `src/rencache.{c,h}` and
`modules/platform/renderer{,_font}.c` are copied from the same Lite commit.
Port changes preserve the software renderer/command-hash cache: SDL3 pitch-aware
ARGB surface and dirty-region conversion, dynamic grid/command storage, aligned
commands, unconditional deferred-font cleanup, tab-state restoration, strict UTF-8,
full Unicode indexing, explicit embedded font aliases, TTC/CJK fallback, and safe
font-load failure handling. Lua font objects are native userdata. SDL2 and Lua 5.2
remain replaced by SDL3 and Lua 5.4.

`src/vendor/fonts/{font,icons,monospace}.ttf`, `modules/editor/user/colors/`
and `user-init.lua` come from the same pinned Lite tree. The three fonts are
embedded by `tools/embed_fonts.py`; JetBrains Mono remains an optional external
font. The `user.example` bundle entry contains the original user-module template.

Default plugin changes are limited to:
- `autoreload`: skip dirty/virtual/read-only docs, tolerate missing files, retain
  cooloo's final-newline sentinel and CRLF metadata.
- `trimwhitespace`: skip virtual/read-only docs; preserve save return value.
- `projectsearch`: Lua 5.4 integer formatting and empty-project division guard.

Core/platform adaptations: C-owned Lite-style fixed FPS loop with upstream
initialization and coroutine scheduling, embedded plugin manifest, explicit
text/workbench extension policy, argv directory launch, SDL3 event bridge,
virtual/read-only documents and wrapped views. See
[editor guide](../../modules/EDITOR.md) for user/project layout and limitations.
