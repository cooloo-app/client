# cooloo-text: Lite baseline and extensions

`cooloo-text [--safe-mode] [--lua-dev DIR] [--] [FILE|DIR ...]`

The last directory argument is the project root; with no directory argument the
launch working directory is used. All file arguments are resolved **before**
changing directory. Missing files open as named empty documents. Files dropped
on an editor pane open there; drops on locked sidebars use the active document
pane. A dropped directory starts a separate text-editor process, with an argv
array (no shell interpolation). Safe mode is inherited by directory children;
a development `--lua-dev` bundle is deliberately not inherited.

With no file arguments, the editor restores the selected project's named file
session if available, otherwise shows an empty welcome view; Ctrl+N creates an unnamed document. Project scanning,
Ctrl+P file candidates, treeview and project search use the selected directory.
The window title includes the project path. The SDL3 host
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
configuration (the UI session directory/file is created automatically when saving state):

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

The native Lite renderer uses independent, garbage-collected font objects.
Default UI and body text use bundled Roboto Mono Regular, both at size 14
(multiplied by SCALE). Chinese glyphs still use
the system CJK fallback chain.
Each default text font rounds the advance of `0` once to an integer cell width:
ASCII occupies one cell; Unicode 15.0.0 East_Asian_Width W/F occupies two;
ambiguous (A) and other printable codepoints occupy one. Measurement and drawing
share that policy, including when fallback glyphs are missing. Controls retain
Lite behavior; `set_tab_width(n)` still takes pixels, not columns.

`renderer.font.load(path,size[,grid])` loads real TTF/TTC files. Grid defaults to
true for `embedded:monospace`, false otherwise; pass true explicitly for a custom
text font to opt in. `embedded:font` is the legacy Roboto Regular resource;
`embedded:icons` keeps its natural icon metrics. Corresponding
`EXEDIR/data/fonts/*.ttf` paths are aliases and accept the same optional flag.
Font sizes may be fractional. Glyphs are centered by advance inside their cell
allocation, not stretched; grid ink is clipped to its allocation and line height
so oversized custom/fallback glyphs cannot overlap neighbors or escape dirty
bounds. Such glyphs may be clipped and need visual acceptance.

This is codepoint layout, not full grapheme shaping: combining marks, variation
selectors and ZWJ sequences are not composed into clusters; emoji appearance and
coverage remain system-dependent. No full Unicode/emoji shaping guarantee is
made. The pinned width table is generated by `tools/generate_cell_width.py` from
the versioned Unicode data URL recorded in `src/platform/cell_width.h`.
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

## Local UI session state

Both GUI products share `core.ui_state`, `core.state_json` and
`core.session_layout`, but write independent UTF-8 JSON snapshots:

- Text: `$COOLOO_TEXT_USERDIR/ui-state.json` (default `~/.cooloo-text`).
- Workbench: `$COOLOO_CONFIG/ui-state.json` (default `~/.cooloo`), outside
  identity-private synced configuration.

Version 1 stores product-level logical SDL window width/height and up to 16
workspaces. Window size policy lives in Lua; native APIs only get/set size and
center the hidden window before its first frame. No window coordinates are
saved. Workbench reads legacy `gui.w`/`gui.h` only when no new window state is
available; these keys are no longer written.

Text workspaces are keyed by the launch project root. Explicit file/directory
arguments win over restoration; no persisted path selects a project or executes
its configuration. Workbench workspaces are keyed by the authenticated server
fingerprint and effective identity, never used as login instructions. Restoration
waits for authentication and the completed room list. Switching identity first
saves the old snapshot; edited files must be saved/closed before switching.

A single split tree stores File/Chat resource descriptors, tab order, active tab
and active pane. Locked chrome/console is excluded. Workbench also records tree
collapsed groups and the browsed room independently of the active Chat/File.
Missing files/rooms and unknown resource kinds are skipped. Protected cache
projections are not reopened as ordinary writable files. Unnamed documents,
unsaved text, cursor/scroll, right file-tree expansion and chat history anchors
are not session backups; message/draft persistence remains separate.

Snapshots use the existing atomic file writer, a 750 ms quiet period (five-second
maximum while changing) and a confirmed-quit flush. Size is capped at 1 MiB,
layout depth at 8 and restored tabs at 128. Invalid JSON falls back to defaults;
unreadable/oversized files and unsupported versions/products are preserved,
not overwritten. Failures are reported in Core: Open Log and never block startup.
Multiple processes use last successful writer wins; this is not a merge or
power-loss durability guarantee. Settings remain separate executable Lua files.

Validation: `build/lua-runner --lua-run tests/ui_state.lua`,
`SDL_VIDEODRIVER=dummy build/renderer-test tests/workspace_state.lua`, and
`python3 tests/ui_state_integration.py ./editor-linux` (use the macOS equivalents
on macOS). These exercise data parsing, limits, async identity isolation and
actual process restart with Unicode file paths, split/focus, explicit arguments,
missing resources and future/corrupt snapshots; desktop HiDPI/visual behavior
still needs platform acceptance.

## Word boundaries and formatting

Word navigation, selection (including double-click), word deletion and completion
prefixes advance on complete UTF-8 scalars. `config.non_word_chars` is a literal
set of separator characters; defaults include common Chinese/fullwidth punctuation
and ideographic space as well as ASCII punctuation. Adjacent Chinese characters
remain one word: this is delimiter navigation, not Chinese lexical segmentation
or full Unicode word breaking. User overrides replace the default separator set.
Invalid UTF-8 bytes remain independently navigable and are not matched against
bytes inside multibyte separators.

Reflow recognizes only ASCII indentation/comment prefix markers, so non-ASCII
body text is not stripped as a prefix. It still uses the inherited byte-based
wrapping width, not full Unicode typography. Tabularize splits on the entire
literal delimiter (including multibyte/multicharacter strings); its existing
nonempty-field and byte-width alignment semantics remain unchanged, so it is not
a CSV-preserving formatter.

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
python3 tests/review_round1_test.py ./cooloo-text
python3 tests/review_round2_test.py ./cooloo-text
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
