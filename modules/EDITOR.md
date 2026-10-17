# cooloo-text: Lite baseline and extensions

`cooloo-text [--safe-mode] [--lua-dev DIR] [--] [FILE|DIR ...]`

The last directory argument is the project root; with no directory argument the
launch working directory is used. All file arguments are resolved **before**
changing directory. Missing files open as named empty documents. Files dropped
on an editor pane open there; drops on locked sidebars use the active document
pane. A dropped directory starts a separate text-editor process, with an argv
array (no shell interpolation). Safe mode is inherited by directory children;
a development `--lua-dev` bundle is deliberately not inherited.

Project scanning, Ctrl+P file candidates, treeview and project search use the
selected directory. The window title includes the project path. The SDL3 host
uses Lite's poll → editor step → coroutine work → sleep-remaining-frame sequence,
not event-triggered frame scheduling. `config.fps` (1–1000, default 60) controls
both host pacing and Lite's existing per-frame timers. There is no new dt/deadline
scheduler. Frames that overrun their budget are not compensated by catch-up steps.

## Extension layout and order

1. Embedded Lite plugins plus discovered external plugins, sorted by module name.
2. User `init.lua`.
3. Project `.lite_project.lua`.

All 16 upstream default plugins are embedded: autocomplete, autoreload, treeview,
projectsearch, trimwhitespace, macro, reflow, tabularize, quote, and Lua/C/CSS/JS/
Markdown/Python/XML syntax. Source is copied from the pinned upstream, not
reimplemented. See [vendor/lite/README.md](../vendor/lite/README.md).

The user directory (`USERDIR`) defaults to `~/.cooloo-text`, or the absolute path
of `COOLOO_TEXT_USERDIR` if set. It is independent of communication credentials
in `~/.cooloo`. Create these files/directories yourself; startup does not write
configuration:

```
~/.cooloo-text/
  init.lua                 # user settings, commands, keymaps
  helper.lua               # require 'user.helper'
  plugins/example.lua      # require 'plugins.example'
  plugins/example/init.lua # alternative package form
```

For Lite-style portable layouts, `<exe-dir>/data/plugins/` is also scanned and
`<exe-dir>/data/user/init.lua` is used when `USERDIR/init.lua` is absent. External
module search order is USERDIR then `<exe-dir>/data`. Embedded core/default
plugins remain authoritative (external plugins add new names rather than
silently replace core). `user.*` resolves relative to USERDIR, then the portable
layout. An example user module is in `vendor/lite/user-init.lua`.

`core:open-user-module` opens the selected user init file (or a new named document;
create its parent directory before saving). Lua errors are caught, recorded in
Core: Open Log, and do not stop loading later plugins. Plugins may use ordinary
Lite `core`, `Doc`, `View`, command/keymap/syntax APIs and `core.add_thread`.
`system.chdir`, filesystem, clipboard, monotonic time and asynchronous shell
`system.exec(command)` are available. The renderer still uses cooloo's embedded
font/CJK fallback; arbitrary font-file loading/native Lite C plugins and every
third-party plugin are **not** a compatibility guarantee.

## Trust and workbench boundaries

**Normal mode executes user and project Lua. Only open trusted projects.**
`--safe-mode` loads the embedded default plugins but does not discover external
plugins, load user/project modules, or use filesystem Lua module search paths.
It is a diagnostic/trust switch, **not an OS sandbox**; explicitly passing
`--lua-dev` still executes the requested development bundle. Lua's standard
libraries and `system.exec` are not sandboxed, and plugins run with the user's OS
permissions. Absence of a network/identity binding is not a filesystem security
boundary against malicious Lua.

Text bundles exclude workspace, console, providers and client communication,
identity/cache and runner APIs. Full `cooloo --gui` still explicitly installs
workspace/console and loads only its existing Lua syntax plugin; it does not
discover user/project modules or scan/change project directories. Received
message text remains a read-only projection, never executable Lua.

Autoreload skips dirty/virtual/read-only documents and preserves final newline
and CRLF metadata. Trimwhitespace skips virtual/read-only documents. Other
editing plugins use the existing guarded Doc mutation methods.

## Validation

Build `cooloo-text` (macOS), `cooloo-text.exe` (MinGW), or the development
`cooloo-text-linux`, then run:

```
python3 tests/editor_integration.py ./cooloo-text
make test-workbench-headless
build/lua-runner --lua-run tests/workbench.lua
build/lua-runner --lua-run tests/provider.lua
```

The integration test uses SDL dummy and isolated temporary projects/user modules,
checks fixed pacing, extension order/error recovery/safe mode, project scan and
search, pane drop dispatch, macros, reload safety, UTF-8 paths, readonly behavior
and a real directory child process. It does not synthesize OS drag-and-drop or
prove desktop IME/clipboard/visual blink behavior. Windows UTF-8 CRT filenames
use an embedded active-codepage manifest (Windows 10 1903+); older Windows is not
claimed by this change.
