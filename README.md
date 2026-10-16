# Protocol 2 client — v0.3.0 text workbench

The modular workbench replaces the v0.2 GUI. Protocol 2, Machine API schema 1,
identity and cache formats remain compatible. See [modules/README.md](modules/README.md)
for dependency boundaries and runner API, and [release/README.md](release/README.md)
for artifact provenance, platform verification and manual acceptance limitations.

## Workbench development

```sh
make cooloo-cli                  # headless, no SDL/editor dependencies
make editor                     # native macOS offline workbench
make editor.exe cli.exe         # MinGW Windows targets
make editor-linux cooloo-linux  # Linux development builds, requires CMake
make test-workbench             # Linux headless + SDL dummy + loopback tests
make test-workbench-macos       # macOS workbench/runtime + SDL dummy + loopback tests
```

`editor` starts with an empty `<local>` conversation. It does not link the client
network/identity/cache core or read/write `~/.cooloo`. `Workspace: Mock Load`
explicitly imports a text file (one mock message per line); nothing is loaded or
created implicitly in the current directory. Messages are in-memory mock data.

Useful commands/keys (Cmd maps to Ctrl on macOS):

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
editor). Changes are detected but require restart: destructive hot reload of
live documents/connections is intentionally disabled. The old GUI entry/layout/input
scripts have been removed; `lua/chat.lua` remains the shared protocol state model.


## License

Project-owned client code is licensed under [MIT](LICENSE). Vendored components
and fonts retain their respective licenses; see their notices under `src/vendor/`.

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
