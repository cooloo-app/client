# Protocol 2 client — v0.3.2 text workbench

The modular workbench replaces the v0.2 GUI. Protocol 2, Machine API schema 1,
identity and cache formats remain compatible. See [docs/README.md](docs/README.md)
for dependency boundaries and runner API, and [release/README.md](release/README.md)
for the release overview. Machine-readable artifact provenance is in
[release/manifest.json](release/manifest.json).

## Source layout

Project-owned C sources are in `src/`, Lua sources in `lua/`, with functional
subdirectories in each. Entry points live in `src/apps/`, `src/cli/` and
`lua/apps/`; adapters follow the same language split. Third-party native code is
in `vendor/`, fonts and executable resources in `assets/`, and generated code in
`build/generated/`. See [source layout and boundaries](docs/README.md).

Existing checkouts need a fresh SDL build directory after this migration
(`make distclean` removes the old CMake caches and local build products).

## Workbench development

```sh
make cooloo-cli                  # headless, no SDL/editor dependencies
make cooloo-text                # native macOS general-purpose editor
make cooloo-workbench           # headless message projection / Lua runner CLI
make cooloo-text.exe cooloo-workbench.exe cli.exe # MinGW Windows targets
make cooloo-text-linux cooloo-linux # Linux development builds, requires CMake
make test-workbench-headless    # no GUI/SDL dummy tests
make test-workbench             # Linux headless + SDL dummy + loopback tests
make test-workbench-macos       # macOS workbench/runtime + SDL dummy + loopback tests
```

`cooloo-text [--safe-mode] [FILE|DIR ...]` is the standalone general-purpose text editor, built on
 the same Lite-derived editor core and SDL3/Chinese-input platform as the full
product. It supports project scanning, file/directory drops, Lite's 16 default
plugins and user/project Lua extensions. See [editor guide](docs/EDITOR.md)
for directory layout, trust policy and validation. Normal mode executes trusted
user/project modules; `--safe-mode` skips external extensions. With no files
supplied it shows an empty welcome view; Ctrl+N creates an unnamed document.
It does not bundle message/workspace/console plugins, link the execution runtime
or client network/identity/cache core, or read/write `~/.cooloo`. Existing `editor`,
`editor.exe`, `editor-linux` build names remain aliases with this new pure-editor
behavior; they no longer start a mock conversation or execute `--lua-run`.

`cooloo --gui` explicitly installs the workspace and console plugins. The local
mock provider remains a development fixture, not the text-editor product.

On Windows, launching the full `cooloo.exe` with no arguments and no terminal or
redirected standard handles (for example, double-clicking it in Explorer) opens
this same GUI without allocating a console. A bare launch from PowerShell, CMD,
or a Bash terminal prints CLI help; pipes and file redirection also keep CLI
behavior. Explicit commands and flags retain their existing meanings, including
`--gui`, `--help`, `--json`, and runner modes. CLI-only builds and non-Windows
platforms continue to print help on bare launches. Detection uses standard
handles and parent-console attachment, not parent executable names; a custom
launcher that supplies neither console nor standard handles behaves like a
desktop launch.

For terminal commands on Windows, use the Python package's `cooloo` console
entry point (or `python -m cooloo` to bypass a stale native exe on PATH). It waits
for the same bundled GUI executable; a separate CLI artifact is not needed.
A GUI-subsystem exe cannot make an interactive PowerShell/CMD session wait merely
by attaching to its console. Direct native launches therefore refuse terminal
input for trust prompts and stdin `send`, with a launcher diagnostic. Redirected
pipes/files remain usable. Desktop shortcuts may target the native exe with
`--gui`. The SDK sets `COOLOO_LAUNCHER_WAIT=1` in its child environment while waiting;
this is an internal launch contract, not a user setting or a trust decision.

Trust prompts only read a terminal and accept a complete `y`, `Y`, `yes` or `YES`
line. EOF, other answers and redirected input never pin an unknown server.
For automation, verify the fingerprint and opt in with `-y/--tofu`; this never
accepts a changed pin. This also prevents piped message content from becoming
consent. Release binaries are unchanged until an explicit artifact refresh.

Offline Windows dispatch regression (GUI is replaced with an exit-code stub):

```sh
make build/startup-dispatch.exe build/startup-console-parent.exe build/console-input-probe.exe
```

```powershell
powershell -NoProfile -File tests/windows-dispatch.ps1 -Exe build/startup-dispatch.exe -ConsoleParent build/startup-console-parent.exe
python tests/windows_input_test.py build/console-input-probe.exe
```

This covers desktop-style detached launches, parent-console attachment and
partial/full stdio redirection without opening a GUI or accessing a server.
Real Explorer and terminal acceptance additionally requires the full binary.

`cooloo-workbench` is a separate headless binary (C + Lua, no SDL):

```sh
cooloo-workbench message validate messages.jsonl
cooloo-workbench message render messages.jsonl --format text
cooloo-workbench message render messages.jsonl --format json
cooloo-workbench --lua-run script.lua
```

Input uses canonical Protocol 2 records (`ts/from/to/content`), validated by the
same C decoder as the client. No network/config access is needed. Rendering is a
read-only projection, not a JSONL round-trip editor. Time labels use UTC in both
CLI and GUI. JSON output contains `text`, `anchors`, `ranges`, and
`source_revision`; IDs/revision are source byte endpoints/length for file input,
not display line numbers. Anchors/ranges use one-based logical lines. Limits:
10,000 records, 25,088 bytes per input record, 4,096 decoded content bytes.
Invalid input produces a nonzero exit without partial rendered stdout; usage
errors return 2. UTF-8, CRLF and a final record without LF are supported.
`--lua-console` retains the existing length-framed runner protocol; it is not a
terminal emulator or interactive line-oriented shell. Scripts are not sandboxed.

The Lite baseline restoration includes native renderer/font userdata, dirty-region
caching, the SDL event bridge, IME integration and fatal-recovery lifecycle fixes.
Development artifacts cover all four products on macOS arm64 and Windows x86_64.
The release manifest records each artifact's source and verification scope;
historical test results are not new artifact acceptance. Real GUI/desktop
acceptance remains deferred. See [release/README.md](release/README.md) for the
overview and [release/manifest.json](release/manifest.json) for exact facts.
`make release-macos` / `make release-windows` build all four products without
publishing, tagging or uploading a Release.

Useful commands/keys (Cmd maps to Ctrl on macOS); workspace, console and runtime
commands below are available only in the full workbench, not `cooloo-text`:

- Ctrl+Shift+P: command palette; Ctrl+O/N/S/F: open/new/save/find.
- Alt+Shift+J/L/I/K: split left/right/up/down; Ctrl+Tab: next tab.
- Ctrl+Enter in a message draft: send; elsewhere it does not send hidden drafts.
- F5: save and run the current named Lua file in a new child VM.
- Ctrl+backtick: Lua console output/input split; Ctrl+Enter submits multiline input.
- Alt+Up/Down in console input: history. `Console: Stop File`, `Stop Session`,
  `Restart`, `Clear` are available in the command palette.
- `Workspace: Switch`, `Address`, `History`, `Trust Server`, `Register`, `Identity`,
  `Reconnect`: provider operations. Trust requires explicit fingerprint approval.
- `Workspace: Refresh Rooms` requests a fresh room snapshot; automatic refresh is
  every five seconds, independently of the 30-second control/FOLLOW heartbeat.
  `Workspace: Sync Status` logs phase and receive/persist/model/list timestamps,
  without message bodies or credentials. Footer reports catch-up/following and
  pending durable writes. Missing heartbeat replies trigger reconnect after 60
  seconds, excluding time blocked behind cache processing.

Messages/output are read-only virtual documents with UTF-8 soft wrap, selection,
copy and find. Lua files use the upstream unwrapped code view. History loads
cached messages asynchronously in batches of 200, with a 10,000-message display
limit. Initial display is the latest 2000 records. Disk scans/writes and lock
waits run on a bounded worker queue; live sync pauses behind durable writes.
Search covers loaded text. Drafts remain until acknowledgment; errors and unknown
outcomes retain them, and the client never automatically resends. Delegated
write capability is marked unverified until an operation establishes its outcome;
known permission denial disables send until explicit reconnect/identity reset.

The runner's explicit `cooloo.request_as(identity_id, command, ...)` selects an
authorized message identity per request; `cooloo.request(...)` uses the server
default (parent for mirror credentials). `whoami` always reports the actual login. Requests
reuse the CLI core inside the runner, so Stop does not leave request subprocesses.

`--lua-dev DIR` expects a generated `workbench.lua` bundle (use
`python3 tools/embed_workbench.py DIR/workbench.lua --lua`, add `--offline` for
the pure text-editor bundle; `--profile text` is preferred). Changes are detected but require restart: destructive hot reload of
live documents/connections is intentionally disabled. The old GUI entry/layout/input
scripts have been removed; `lua/chat.lua` remains the shared protocol state model.


## Workbench navigation (development; desktop acceptance pending)

The full GUI now uses a conversation tree on the left, ordinary editor panes in
 the center, and a room file tree on the right. These are Lua workspace
extensions; the text-editor core, platform and standalone text bundle are unchanged.

- Nickname `A:B` appears under `A`. Click the `+`/`-` area to expand/collapse,
  and click a real conversation name to open it. Duplicate names retain separate
  ID-labelled entries. Up/Down, Enter and Space navigate a focused sidebar.
- Chat and file navigation use the same target-pane rule: reuse an existing tab
  only in that pane, otherwise create another view there. A room can have a
  complete `ChatView` in each split. Its history, draft, undo/selection state
  (following the editor's shared-Doc behavior) and pending-send guard are shared;
  each view has its own scroll, focused child and divider. Closing one view does
  not unsubscribe other views; the last close releases the room subscription.
- ChatView is a composite View, not a DocView. Its history and draft are private
  child DocViews without separate tab bars. Chat-local editing/find commands
  reuse existing editor operations. Chat split shortcuts and native `Root: Split`
  commands preserve the complete chat instead of exposing a raw history/draft
  document. Ordinary file splits retain their existing behavior.
- Ctrl+Enter sends only the focused draft. A pending send cannot be repeated;
  ACK clears only the unchanged submitted document version. Rejected or unknown
  delivery retains the draft. Drafts save to `draft.txt` after a short idle delay,
  on focus changes, close and normal exit; Ctrl+S saves the focused draft now.
  Reopening a conversation after restart restores its saved draft. Until the
  authenticated room directory and existing draft are available, input is
  read-only and the right footer explains the waiting/error state. Save failures
  keep the in-memory draft and prevent normal close/exit until saving succeeds.
- The right tree browses the room selected through the left conversation tree
  or an activated Chat tab. Activating an ordinary file pane only changes the
  target pane: it never switches the browser back to that file's room. Thus you
  can select general, focus either old file pane, then open general's file there.
  The conversation highlight and right-tree title use the same browser state.
- Room directories include `.meta`, `messages.jsonl`, and `draft.txt`. Cache files
  open as read-only snapshots; opening `draft.txt` focuses the room's draft in
  the target pane's ChatView. Each file row carries its own room and full path;
  identical basenames in different rooms are distinct resources. Other files
  use ordinary editable Docs. Refresh publishes complete snapshots and retains
  selection by resource identity. Root directory changes are detected periodically;
  `Workspace: Refresh Files` also rescans expanded subdirectories.
- `Workspace: Bind Directory` optionally overrides the right tree with another
  existing directory for this session; draft storage remains in the room cache.
  Browsing does not change CWD, load project scripts, or execute Lua files.
  The local fixture provider has no durable room directory and keeps drafts in
  memory only.
- File scanning is on demand, processes 32 entries per frame, and displays at
  most 2000 entries with 24 nested levels. Canonical directory aliases are not
  traversed. The existing filesystem API enumerates each directory synchronously;
  a very large or slow directory can still pause its initial enumeration/sort.
- Identity changes flush drafts before clearing old chat views and bindings.
  Exit also flushes drafts. Pending delivery asks for confirmation; retained
  drafts are never automatically resent. Check history before resending after
  an interrupted send. Existing Console functionality remains available.

The ChatView/durable-draft iteration is built for Windows; no automated tests,
GUI tests, SDL dummy tests, or runtime smoke tests were run at the user's request.
Real desktop layout, focus, Chinese IME, clipboard, split interaction, draft
recovery and sending await human validation. Use one GUI process per identity
when editing drafts; this version does not merge concurrent external edits.

## Local unread and desktop attention

The full GUI keeps a local read watermark for each server fingerprint, effective
message identity and conversation. Opening a chat in the focused, non-minimized
window marks its synchronized messages read; incoming messages in that active
chat are also read without requiring a scroll to the bottom. Background tabs,
ordinary documents, unfocused and minimized windows retain unread messages.
Own messages and recovered SENT records do not add unread. On first upgrade,
existing local cache becomes the baseline; subsequent downloads remain unread.
Restart and reconnect reconstruct counts from the durable cache, paging beyond
the 2000-message display limit when necessary.

Use **Workspace: Toggle Mute** in the command palette for the active or browsed
conversation. Unread counts are red normally and gray when muted. Muting keeps
unread intact and removes that conversation from the desktop aggregate. A local
`read-state` file beside `messages.jsonl` stores the watermark and mute flag using
atomic replacement; it is a read-only snapshot in the room file browser. Failed
writes retain unread and report an error. Corrupt state fails closed instead of
silently treating history as read. Use one GUI process per local identity; state
is not merged between simultaneous processes or synchronized between devices.

Windows uses a taskbar overlay dot; macOS uses a Dock badge. Non-muted live
messages request attention while the window is in the background. Restored
history sets the persistent badge without requesting attention. The badge clears
when no non-muted unread remains. Closing a chat releases its foreground stream,
but listed rooms remain eligible for background sync. Notifications require the
application to stay running; this does not add system notification banners.
Native bindings are build/runtime tested on Windows and macOS; actual Explorer
and Dock appearance still needs desktop visual acceptance. Artifact provenance
and the verification performed for each binary are recorded in `release/manifest.json`.

## License

Project-owned client code is licensed under [MIT](LICENSE). Vendored components
and fonts retain their respective licenses; see their notices under `vendor/`.

## Machine API and Python distribution

`--json` enables noninteractive JSONL schema 1; machine READ/FOLLOW bypass normal caches,
FOLLOW requires an explicit byte offset. `version` reports the local client version and
`--json version` its capabilities. Bare `cooloo` prints a short help summary and exits
successfully; `cooloo --help` prints full help. Neither starts the GUI or connects to
a server. `cooloo --gui` opens the embedded workbench; add `--debug` for console logs or
`--lua-dev DIR` for a development bundle (restart required after changes). These options alone no longer start the GUI.
Desktop shortcuts and launch scripts must pass `--gui` explicitly.
See [MACHINE_API.md](MACHINE_API.md) for results, errors, cursors and delivery uncertainty.
The [Python SDK](https://github.com/cooloo-app/python-sdk) wraps this executable and ships
platform wheels containing the GUI+CLI binary; it does not reimplement the Native protocol.


Requires a protocol-2 server. Production uses Protocol 2; the new simple private
room commands require server v0.2.1 or later. No old config/history migration
is provided.

## CLI

```
cooloo keygen                         # print actual public-key ID (64 hex)
cooloo whoami --register <nickname>    # duplicate nicknames allowed
cooloo whoami
cooloo create <nickname>               # create public room, returns its ID
cooloo join <room-id>                  # sends @<room-id> join-request
cooloo room-mode <room-id> public|private
cooloo avatar <001..899> <child-public-id> <nickname>
cooloo mirror <001..899> <child-public-id> <nickname>
cooloo detach <child-public-id>      # parent actual credential; preserve account/data
cooloo identity                      # actual login and effective message identity
cooloo rooms
cooloo meta <id-or-alias>
cooloo rename <id-or-alias> <nickname>
cooloo send <id-or-alias> [text...]     # stdin preserves exact bytes
cooloo read [--raw] <id-or-alias> <offset>
cooloo follow <id-or-alias>            # durable catch-up then live stream
cooloo delegate <child-id> read|write|read,write|none # parent's access TO ordinary child
cooloo --as <child-id> send <id> [text...] # parent sends with child's identity
cooloo --as <owner-id> read <owner-id> 0
cooloo sent <peer-id> <scan-offset>    # only your messages in peer's inbox
cooloo history                       # inbox + discovered peer sent history
```

Simple private rooms require the matching updated server. Approve with:

```sh
cooloo send <room-id> '@<room-id> join-approve <applicant-user-id>'
```

Replace placeholders with complete IDs. Any member may approve; requests must
be more than 24 hours apart and expire after seven days. Owner counts toward the
200-member limit. Private rooms share their full history with members.
**Temporary policy: any registered user may switch any room to public, exposing
all history.** Switching public -> private adds user IDs that have sent messages
in this room, retaining owner and existing members; over 200 rejects conversion.
Registration, reading, or switching mode alone does not grant membership.
Member blocks are reserved, empty, and have no client API yet. No GUI controls
are added; ordinary GUI messages can carry the exact control text.

`-y/--tofu` trusts and pins a previously unknown server; a changed pin fails.
Create a child key in its own `COOLOO_CONFIG` directory, then authorize its public
ID through the parent `avatar` command. Do not register the child as a root
first: an existing identity cannot be claimed as somebody else's child.

Nicknames are presentation attributes. Use IDs for commands, not nicknames.
`read --raw` prints original JSON records. Non-raw CLI output currently displays
sender IDs. Interactive CLI `chat` is temporarily unavailable; use GUI or
separate send/follow terminals. FOLLOW resumes on the next invocation; automatic
retry and idle keepalive are not implemented in this revision.

## Ordinary avatars, pure mirrors and history

This source requires the matching pure-mirror server with `IDENTITY` support.
Ordinary children keep their own message identity; the parent defaults to read/write
access **to the child**, independently configurable with `delegate`. This command
no longer grants children access to the parent. `--as <child-id>` must precede the
command and selects a permitted message identity; it never grants administration.

`mirror` creates a credential whose default message identity is its parent. A mirror
cannot send as itself or receive messages, including through slot aliases. It has
the parent's message read/write capabilities, but cannot administer as the parent.
`detach` splits either relationship into independent accounts, preserving data.
The old child/authz model is reset on the server, not migrated or emulated.

`identity` reports actual login/effective IDs; `whoami` always reports the login.
CLI and GUI query `IDENTITY` before using caches. `Workspace: Identity` selects an
explicit identity (empty restores the server default, parent for mirrors). Status
shows both IDs. Streams verify their selected identity; changes to a default on
reconnect fail closed until the workspace is explicitly reset. Message caches are
partitioned by effective identity; each readable child has its own room directory.
A mirror login syncs A and B directories/metadata through background subscriptions,
while known mirror targets have sending disabled. No second credential/key is loaded.
The GUI recovers sent messages from recent incoming peers into its inbox view;
filtered records do not enter the contiguous room cache. This filtered view is
in-memory and incrementally refreshed every five seconds for discovered peers,
using SENT scan cursors; it is not a persistent sent index or a live subscription.

`sent` prints filtered JSONL and a scan cursor on stderr. `history` prints a merged
snapshot (max 10,000 messages/256 received peers, explicit error on overflow).
No server-side sent index or duplicate body storage is added. **Peers that never
replied are not automatically discovered**; their sent history is omitted unless
queried explicitly. This is not complete multi-device synchronization. New clients
require the matching pure-mirror server. Read-only parent access can browse a child;
write-only parent access is usable via CLI but cannot populate that child's GUI room list.

Validation: server/client `make test`, provider state mocks, and
`python3 tests/mirror_workbench.py` (after building `cooloo-linux`) verify the new
model, real runner requests and SDL-dummy mirror A/B directory synchronization.
Platform artifact revisions and verification are recorded in `release/manifest.json`;
real desktop validation remains separate.

## Official server relocation — v0.2.4

The default server is now Shanghai `123.206.215.121:4222`. A persisted config
pointing to the old official `43.133.202.144:4222` is resolved to Shanghai without
rewriting configuration, identity or cache files. Other hosts/ports are unchanged.
Explicit `COOLOO_HOST` (including Python `Client(host=...)`) always wins: remove
or update an explicit old-IP override when upgrading.

An existing old-endpoint pin is reused only if it exactly matches the verified
unchanged official fingerprint
`e6da669a4763acc8e790c6c757f698eed8eeab2c56007a62d28fd48f421c06bf`.
An explicit new-endpoint pin takes precedence, including conflicting pins; there
is no silent trust reset. Fresh installations still require explicit first-use
trust. Cache keys remain server fingerprint / identity, so history is preserved.

## Local files

Default root: `~/.cooloo` (Windows HOME, otherwise USERPROFILE).
`COOLOO_CONFIG` overrides it. `COOLOO_HOST=host:port` overrides the server.

```
identity                         # private key
known_servers                    # TOFU fingerprints
config                           # GUI/window/server settings
cache/<server-fingerprint>/<own-public-id>/rooms/<destination-id>/
    .meta                        # server's canonical metadata snapshot
    messages.jsonl               # server's original JSONL bytes
    draft.txt                    # Workbench autosaved draft (effective identity)
```

Cache writes reject gaps or conflicting duplicates. Full history is synchronized
before following new messages. Only a complete durable prefix advances the
checkpoint. An incomplete final cached line is removed on reopen; malformed
complete lines fail closed. Cache files and server files are directly comparable.
Metadata is a snapshot, not a live change feed. Stop processes before backup;
the directory includes private keys. Windows ACLs inherit from the user profile.

The previous v0.2 GUI used the existing C/SDL/Lua architecture. It loaded cached history, resumed
READ from the cache end, then FOLLOWed. Its display was capped at 2000 messages;
older history remained in JSONL without a paging UI. The v0.3 workbench above
adds explicit local-cache paging and registration through commands. Room creation
and avatar administration still use CLI; no dedicated GUI controls are added.

## Build and tests

```
make -C ../server all
make cooloo-cli                  # portable CLI-only build
make test                       # isolated CLI/gate/cache + Lua state tests
```

Platform release validation and remaining limitations are recorded in
`release/README.md`. Windows scripts use an isolated config and optional isolated
protocol-2 test server; never point their network tests at production.
