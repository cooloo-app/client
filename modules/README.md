# Client module boundaries (v0.3 development)

The Makefile's source sets, not directory names, enforce the link boundary.
Existing stable client C files remain under `src/` to avoid unnecessary churn.

| Unit | Implementation | Allowed dependencies |
|---|---|---|
| client | `src/net.c`, `config.c`, `record.c`, `noise_xx.c` | OS + vendored crypto |
| CLI | `src/main.c`, `cli.c`, `machine.c`, `win_console.c` | client |
| platform | `src/gui.c`, `font.c`, `luabind.c`, `modules/platform/` | SDL3, Lua 5.4, fonts; client binding excluded for editor |
| editor | `modules/editor/core/` | platform API, no messaging/config API |
| workspace | `modules/workspace/` | editor + injected provider |
| runtime | `modules/runtime/` | Lua; SDL process API for host, no window/client dependency |
| console | `modules/console/` | editor + injected runtime |
| local adapter | `adapters/local/` | Lua standard library, explicit fixture file |
| cooloo adapter | `adapters/cooloo/`, `lua/chat.lua` | client binding, same workspace contract |
| composition | `apps/editor/workbench.lua` | selects provider, commands and panel layout |

`COOLOO_EDITOR_ONLY` excludes client includes, symbols, identity/config APIs and
chat/provider embedded sources. `COOLOO_CLI_ONLY` excludes SDL, editor and runtime.
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

The platform C loop owns SDL events, network pump and frame pacing. Lite's
`core.run()` is not invoked. `core.host` schedules editor coroutines. No automatic
execution of `.lite_project.lua`, user modules or received message text.

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
Offline editor runners expose neither API.

For vendor provenance see `vendor/lite/README.md` and LICENSE. Lua core is based
on rxi/lite, not Lite XL. Upstream module/plugin compatibility is not promised.
