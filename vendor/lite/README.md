# Lite provenance

Source: https://github.com/rxi/lite
Commit: `38bd9b3326c02e43f244623f97a622b11f074415`
License: MIT, retained in LICENSE.

Vendored Lua core lives in `modules/editor/core`; all 16 upstream default plugins
are copied into `modules/editor/plugins`. `user-init.lua` is the upstream user
module example. No upstream C runtime, SDL2, Lua 5.2 or fonts are imported.

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
