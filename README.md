# Protocol 2 client — v0.3.0 text workbench

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

Messages/output are read-only virtual documents with UTF-8 soft wrap, selection,
copy and find. Lua files use the upstream unwrapped code view. History loads
cached messages asynchronously in batches of 200, with a 10,000-message display
limit. Initial display is the latest 2000 records. Disk scans/writes and lock
waits run on a bounded worker queue; live sync pauses behind durable writes.
Search covers loaded text. Drafts remain until acknowledgment; errors and unknown
outcomes retain them, and the client never automatically resends. Delegated
write capability is marked unverified until an operation establishes its outcome;
known permission denial disables send until explicit reconnect/identity reset.

The runner's explicit `cooloo.request_as(owner_id, command, ...)` selects delegated
identity per request; `cooloo.request(...)` always uses login identity. Requests
reuse the CLI core inside the runner, so Stop does not leave request subprocesses.

`--lua-dev DIR` expects a generated `workbench.lua` bundle (use
`python3 tools/embed_workbench.py DIR/workbench.lua --lua`, add `--offline` for
the pure text-editor bundle; `--profile text` is preferred). Changes are detected but require restart: destructive hot reload of
live documents/connections is intentionally disabled. The old GUI entry/layout/input
scripts have been removed; `lua/chat.lua` remains the shared protocol state model.


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
cooloo rooms
cooloo meta <id-or-alias>
cooloo rename <id-or-alias> <nickname>
cooloo send <id-or-alias> [text...]     # stdin preserves exact bytes
cooloo read [--raw] <id-or-alias> <offset>
cooloo follow <id-or-alias>            # durable catch-up then live stream
cooloo delegate <child-id> read|write|read,write|none # replace grant; owner credential
cooloo --as <owner-id> send <id> [text...] # explicit delegated sender
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

## Delegated identities and history — v0.2.2

Login identity remains the default. `--as <owner-id>` must precede the command;
owner grants read/write separately to existing avatars, with `none` revoking both.
Delegates cannot administer grants, avatars, names or room modes as the owner.
No identity block or slot-based implicit permissions are introduced.

`Workspace: Identity` selects the window's effective identity (empty restores login).
Status shows effective/login IDs, and new connections must receive AS
acknowledgment before sending/reading. Message caches use the effective identity.
The GUI recovers sent messages from recent incoming peers into its inbox view;
filtered records do not enter the contiguous room cache. This filtered view is
in-memory and refreshed on reconnect, not continuously followed or persisted yet.

`sent` prints filtered JSONL and a scan cursor on stderr. `history` prints a merged
snapshot (max 10,000 messages/256 received peers, explicit error on overflow).
No server-side sent index or duplicate body storage is added. **Peers that never
replied are not automatically discovered**; their sent history is omitted unless
queried explicitly. This is not complete multi-device synchronization. New clients
require server v0.2.2 for delegation and filtered history. Read-only delegation can browse; write-only
is usable via CLI but cannot populate the GUI's room list.

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
