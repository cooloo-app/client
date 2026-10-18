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
`renderer.end_frame()` submits changed regions before coroutine work. Identical
frames do not present; inactive text frames wait for events for up to 250 ms.
Workbench retains its bounded fixed-frame network pump, with redraw requested by
projection/status changes. Window, rendering, mouse and IME coordinates use the
same surface pixels; the window is shown only after its first rendered frame.
`LITE_SCALE` overrides the startup SDL window display scale.

Input uses the [Lite C event bridge](EVENTS.md), with paired key press/release
and an explicit Lite XL-derived IME increment. Intermediate composition is
rendered without modifying the document; final text follows ordinary undo.

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
layout. An example user module is in `vendor/lite/user-init.lua`, also embedded as
the string returned by `require 'user.example'`. Both upstream sample themes,
`user.colors.fall` and `user.colors.summer`, are embedded; external USERDIR themes
then portable themes take precedence over embedded fallback in normal text mode.

`core:open-user-module` opens the selected user init file (or a new named document
filled with the upstream template; create its parent directory before saving). Lua errors are caught, recorded in
Core: Open Log, and do not stop loading later plugins. Plugins may use ordinary
Lite `core`, `Doc`, `View`, command/keymap/syntax APIs and `core.add_thread`.
`system.chdir`, filesystem, clipboard, monotonic time and asynchronous shell
`system.exec(command)` are available. `system.absolute_path` canonicalizes existing
paths and returns `nil,error` on failure; the separate `system.resolve_path`
extension resolves new filenames. Directory/stat failures also return `nil,error`.
`get_file_info` additionally returns a third `true` for missing paths;
interactive opening rejects access errors, broken links and non-directory parents
without adding a document. Missing parent directories remain allowed for new
named documents (create the directories before saving). `core.temp_filename(ext)` exclusively reserves an empty
file in EXEDIR and tracks that exact path for session cleanup; it may fail if the
directory is not writable.

The native Lite renderer uses independent, garbage-collected font objects and the
upstream pixel tab/advance/height rules. `renderer.font.load(path,size)` loads real
TTF/TTC files; `embedded:font`, `embedded:icons` and `embedded:monospace` select the
bundled resources (the corresponding `EXEDIR/data/fonts/*.ttf` paths are aliases).
Missing primary glyphs use the existing system CJK fallback chain; unavailable
fallback glyphs retain blank replacement spacing. Font sizes may be fractional.
`renderer.show_debug(true)` displays actual dirty regions. Arbitrary native Lite
C plugins and every third-party Lua plugin are not a compatibility guarantee.
Malformed external fonts can still crash the inherited stb parser; font loading
is not a validation boundary for untrusted fonts. This native failure is outside
Lua error recovery; comprehensive font validation is deferred.

Fatal startup/frame/thread/draw errors print a traceback, attempt an exclusive
`error.txt` diagnostic (falling back to numbered siblings without following
symlinks) and non-overwriting recovery copies of dirty ordinary documents, then exit nonzero.
Untitled dirty documents also receive recovery copies; virtual projections are
excluded. Write failures are diagnosed on stderr. Normal confirmed/forced exits
and fatal recovery remove this session's temporary files. Plugin `core.try`
errors remain locally recoverable; explicitly broken `--lua-dev` bundles fail.

## Saving and edit state

Text history uses distinct version identities across undo branches. Undo/redo can
return to a saved version, and saved points form undo merge boundaries. LF/CRLF
is tracked separately: changing format marks the document dirty, switching back
to the saved format clears that format difference, and text undo does not toggle
the format. Select Lines never adds an EOF newline or changes undo history.

Saving writes a same-directory exclusive temporary file, checks write and close,
and then replaces the target. Failures keep the document unsaved and remove the
partial temporary file. Existing symlinks continue to address their target;
hard-linked files are rejected with a Save As diagnostic rather than splitting
aliases. Existing POSIX owner/mode, extended attributes and ACLs are copied (a
copy failure aborts); Windows uses ReplaceFile for existing-file metadata.
New POSIX files are private (0600). The parent directory must permit creating and
renaming files. This is not a power-loss durability or concurrent-edit conflict
detection guarantee. Recovery uses an exclusive create/write/close handle per
backup and retries name collisions, including simultaneous editor instances.

Rename resolves old/new canonical paths before saving; an equivalent path is a
true no-op, retaining dirty edits and the current name. A distinct target is
saved before the old path is removed; deletion failure reports both names and
retains both copies. Existing hard-linked targets remain rejected by Save.
This is not a transaction against concurrent external path replacement.

`Doc:load` stages open/read/close and line parsing before replacing current
state. I/O failure preserves text, filename, selection, history and dirty state;
the read handle is closed even when reading fails. Invalid UTF-8 bytes are kept
unchanged: character navigation/deletion treats each invalid byte as one unit
and only groups complete valid Unicode scalars.

Macros record committed input and focus-loss modifier resets, omit non-modifier
keys consumed by composition, and replay with a separate modifier state.
Failure also restores the real held keys. Focus loss clears physical modifiers
and stops IME; a late key release is harmless. Playback is ignored while an OS composition is active; it does not replay
preedit into the OS.

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
make test-renderer-macos test-event-bridge-macos
python3 tests/editor_integration.py ./cooloo-text
python3 tests/lifecycle_test.py ./cooloo-text
python3 tests/adversarial_test.py ./cooloo-text ./build/renderer-test-macos
python3 tests/round2_test.py ./cooloo-text
python3 tests/round3_test.py ./cooloo-text
make build/file-write-test
fixture=$(mktemp -d)
build/file-write-test "$fixture/file.txt"
make test-workbench-headless
SDL_VIDEODRIVER=dummy build/renderer-test-macos tests/workbench.lua
build/lua-runner --lua-run tests/provider.lua
```

On Linux, use `make test-renderer test-event-bridge`, `build/renderer-test`, and
`cooloo-text-linux` instead. A Linux machine without desktop development libraries
can configure SDL with `make SDL_LINUX_EXTRA_FLAGS=-DSDL_UNIX_CONSOLE_BUILD=ON
cooloo-text-linux` for dummy-only validation;
that build does not validate a Linux desktop backend.

The integration test uses SDL dummy and isolated temporary projects/user modules,
checks fixed pacing, extension order/error recovery/safe mode, project scan and
search, pane drop dispatch, macros, reload safety (including undo branches), UTF-8 paths, readonly behavior
and a real directory child process. It does not synthesize OS drag-and-drop or
prove desktop IME/clipboard/visual blink behavior. Windows UTF-8 CRT filenames
use an embedded active-codepage manifest (Windows 10 1903+); older Windows is not
claimed by this change.
