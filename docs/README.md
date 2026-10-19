# Client module boundaries (text/workbench separation)

Development implementation: stages 1–4, followed by a macOS/Windows artifact
refresh and headless validation. GUI/desktop acceptance remains deferred; see
`../release/README.md` for the overview and `../release/manifest.json` for the
current artifact facts. `cooloo-text` is a full general-purpose
editor product, not an offline messaging UI or a text widget.

The Makefile's source sets enforce the link boundary. Project-owned native code
lives under `src/`; Lua source lives under `lua/`. Both trees group files by
responsibility, including product entry points (`apps/`) and adapters.

## Source layout

```text
src/
  apps/editor/           # text-editor C entry
  apps/workbench/        # headless workbench C entry
  cli/                   # full-client/CLI entry and command dispatch
  client/                # network, config, records and Noise protocol
  platform/              # SDL host, rendering and Lua host integration
    api/                 # Lua-facing platform bindings
  runtime/               # runner and child-process management
  adapters/cooloo/       # native messaging/cache bindings
lua/
  apps/                  # text, GUI and headless composition
  editor/                # Lite core, default plugins and sample themes
  platform/              # Lua platform bridge
  workbench/             # message projection and console session
  plugins/               # workspace and console editor plugins
  adapters/              # local and cooloo providers
  chat.lua               # shared protocol state model
vendor/                  # third-party native sources and upstream provenance
assets/                  # fonts, icons and Windows executable resources
docs/                    # architecture and editor contracts
build/generated/         # generated C bundles/fonts/icon; never hand-edit
```

Lua module names and the portable runtime `data/` layout are unchanged. Bundle
profiles remain explicit in `tools/embed_workbench.py`; moving a file does not
make it part of every product. `BUILD=...` also relocates generated files.
After updating an existing checkout, use a fresh build directory or run
`make distclean` to remove SDL CMake caches containing the old vendor path.

## Dependency boundaries

| Unit | Implementation | Allowed dependencies |
|---|---|---|
| client | `src/client/net.c`, `config.c`, `record.c`, `noise_xx.c` | OS + vendored crypto |
| CLI | `src/cli/main.c`, `cli.c`, `machine.c`, `win_console.c` | client |
| platform | `src/platform/gui.c`, `font.c`, `luabind.c`, `src/platform/api/` | SDL3, Lua 5.4, fonts; client binding excluded for editor |
| editor | `lua/editor/core/` | platform API, no messaging/config API |
| message model/projection | `lua/workbench/messages.lua` | Lua + injected record decoder; no editor |
| workspace plugin | `lua/plugins/workspace/` | editor + message projection + injected provider |
| runtime | `src/runtime/` | Lua; SDL process API for host, no window/client dependency |
| console session | `lua/workbench/console.lua` | Lua + injected runtime; no editor |
| console plugin | `lua/plugins/console/` | editor + console session |
| local adapter | `lua/adapters/local/` | Lua standard library, explicit fixture file |
| cooloo adapter | `src/adapters/cooloo/`, `lua/adapters/cooloo/`, `lua/chat.lua` | client binding, same workspace contract |
| text composition | `lua/apps/editor/main.lua` | editor/platform only, ordinary documents |
| full composition | `lua/apps/workbench/gui.lua` | explicitly installs independent workspace/console plugins |
| headless workbench | `src/apps/workbench/main.c`, `lua/apps/workbench/cli.lua` | model + shared record decoder + Lua runner; no SDL |

`COOLOO_EDITOR_ONLY` excludes client includes, symbols, identity/config APIs and
chat/provider embedded sources. Its source set also excludes the runner/process
runtime, and its explicit `text` bundle excludes all workbench business modules.
`COOLOO_RECORD_ONLY` builds only the existing canonical record parser from
`src/client/record.c`, without cache/config implementations; the CLI never needs to read
credentials. `text`, `gui`, and `cli` bundle manifests are tested for isolation. `COOLOO_CLI_ONLY` excludes SDL, editor and runtime.
`COOLOO_WORKBENCH` adds runner dispatch and explicit script client API to the full
application, without changing normal CLI arguments or Machine API schema.

Provider contract:

- `list()`, `open(id)` (snapshot only), `capabilities(id)`, `send(id,text)`,
  `earlier(id)`, `poll(events)`, `subscribe(id)`, `unsubscribe(id)`, `close()`.
- Optional `revision(id)` avoids rebuilding unchanged projections; `delivery(id)`
  returns pending/sent/rejected/unknown plus detail. IDs are provider identities,
  never document lines or protocol offsets. Messages contain `id/from/text/ts`.
- Workspace keeps submitted drafts until ACK; rejection/unknown retains text.
  ACK clears only an unchanged draft. No resend. A dedicated SEND connection
  prevents metadata/registration errors from being mistaken for SEND replies.
- Capabilities distinguish read/send/history, offline, known denial, and
  **unverified** delegated write access. Protocol 2 has no permission-query API:
  the adapter cannot claim a grant it has not verified. A forbidden SEND disables
  sending until explicit reconnect/identity reset; a denied read does not erase
  an independent write grant. `Workspace: Address` supports explicit destinations.
- At most 12 room streams plus control/SEND/SENT within 16 transport slots.
  Subscriptions are admitted incrementally, selected room wins, completed
  background streams rotate on five-second leases, stalled background catch-up
  yields after 30 seconds. Unsubscribe closes its stream and filtered SENT query.
  Unread reflects synchronized data, not an instantaneous server-side counter.
- Connection tokens are never reused with their slot, so queued old-identity
  events cannot attach to a new connection. Cache callbacks carry an epoch.
- DNS/connect setup and all workbench cache scans/appends/metadata writes run on
  workers, not in UI frames. Network reads are one frame/connection/tick and
  encrypted output queues are bounded to 64 KiB/connection with partial writes.
- Cache worker: 32 jobs, 2000-message initial window, 200-message history pages,
  10000 displayed messages maximum. Queue full fails explicitly. Per-stream
  backpressure keeps END/FOLLOW behind durable appends. Disk format is unchanged;
  scans remain linear on the worker (not an on-disk index). File-lock waits and
  scans are cancelable during shutdown. OS DNS/filesystem calls themselves have
  OS-controlled latency; shutdown joins owned workers, never leaves them running.
- Local mock import is incremental (4 KiB/tick), validates 4096-byte UTF-8 lines,
  and retains the latest 2000 in-memory messages. Fixture text is never executed.

The platform C loop owns the network pump and Lite-style fixed FPS pacing.
`core.step` polls SDL directly through the Lite-derived C `system.poll_event`
(step/poll/draw → coroutine work → sleep remainder); the frame event array is
network-only. See [event contract](EVENTS.md) for SDL3 differences and IME. Lite's `core.run()` is not
invoked; `core.host` reuses `core.init` and the upstream coroutine scheduler.
Text enables project scanning, all default plugins, user and project modules;
`--safe-mode` disables external extension loading. Full workbench retains the
stricter no-discovery/no-project-script policy. Received message text is never
executed. See [EDITOR.md](EDITOR.md) for the extension and trust contract.

Runtime modes:

- `--lua-run FILE`: a fresh Lua VM in a child process for each run.
- `--lua-console`: persistent VM; stdin uses decimal byte length + LF + source.
- stdout/stderr are independently polled (8 KiB/channel/frame); display retains
  256 KiB; console history retains 200 entries. Pending input is bounded to 4096
  source bytes, queued to nonblocking pipes without truncating a partial write.
- Stop/restart terminates and reaps the managed process. Arbitrary descendants
  launched by user scripts are not a managed process tree.
- Isolation is not a sandbox. Scripts have OS file/network/process permissions.

Full-client runners expose `cooloo.request(command, ...)` and
`cooloo.request_as(owner_id, command, ...)`, returning JSONL and status.
Supported commands: whoami, rooms, meta, send, read, sent. These call the **same
headless CLI functions inside the isolated runner**, not a Machine API grandchild.
Stop/restart/GUI exit therefore terminates in-flight managed requests too.
No raw key/connection/UI objects are passed. Default identity is login, never
implicitly the GUI identity; delegation must be explicit per call and is reset
after every request. `whoami` is read-only login inspection (no registration).
Send requires explicit text, never stdin. Script result capture is capped at
1 MiB; large READ/SENT returns an `output-limit` error rather than unbounded RAM
or temporary-file growth. Request latency is the CLI's blocking latency inside
the runner; Stop remains available in the UI. Trust is configured explicitly
outside this API. Inspect JSONL errors and uncertainty; never blindly resend.
The pure editor has no runner. The standalone workbench runner exposes neither
communication API; full-client runners retain their existing explicit APIs.

Workspace navigation extensions live entirely in `lua/plugins/workspace/`:
`tree.lua` groups nickname paths without replacing provider IDs; `files.lua`
manages session-only directory bindings and incremental entry processing;
`sidebar.lua` subclasses View; the workspace model owns open subscriptions,
per-room drafts and ACK/version tracking. GUI assembly installs the existing
console before workspace so the workspace's pre-existing quit hook can ask about
unsent drafts before console cleanup. No editor class/global method is patched
for navigation, layout, input or file editing. These changes are compiled and
non-GUI checked; desktop interaction acceptance is pending.

Workspace and console plugins install their own commands and lifecycle handlers;
the full composition only selects dependencies and schedules them. Virtual/read-only
Doc and wrapped View remain editor mechanisms, not message-specific types.
Message projections use UTC, stable message IDs and logical-line anchors. CLI file
IDs use byte endpoints; source revisions are input byte lengths (not content hashes).
Projection is not a write-back format. Console session state has no Doc dependency;
only the plugin creates input/output documents. Third-party Lua editor plugins
are loaded only by text's explicit composition policy; no hot-unload contract
or OS sandbox is introduced.

For vendor provenance see `vendor/lite/README.md` and LICENSE. Lua core is based
on rxi/lite, not Lite XL. The 16 default plugins and Lite-style Lua extension
model are supported as described in EDITOR.md; arbitrary native/third-party
plugin compatibility is not promised.
