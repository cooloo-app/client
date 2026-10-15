# cooloo client v0.2.2 — Message delegation and sent recovery

Requires Protocol 2; delegation, AS, SENT and history require server v0.2.2.
No protocol-1 compatibility or legacy history/config migration.

## Artifacts (Git LFS)

Built on 2026-10-15 in isolated `/tmp/cooloo-delegation-v022` on m106
(macOS arm64), Windows x86_64 cross-compiled with mingw-w64.
Exact client source: `5a39a43844f661c23f47c78e51c290372727fe3c`.
Integration-test server: `de4f3d21aecaa2190564c329608c02a9decd8010`.
The artifact-containing release commit is not the source build input.

| File | Platform | Bytes | SHA-256 |
|---|---|---:|---|
| `cooloo-darwin-arm64` | macOS arm64 | 2569528 | `cb264e988ded1c5e3b7c619947422ccc3f336016195b593b8b6c3ea898a2805a` |
| `cooloo-windows-x86_64.exe` | Windows 10+ x86_64 | 4153766 | `cc8c1192f2dad5091b6c233197875d517829f498fca30d222a8e8f475732aafb` |

Mach-O arm64 / PE32+ x86_64 GUI subsystem, static vendored libraries and
Windows system DLLs only (including UCRT). Unsigned/not notarized. No Linux GUI.

## Validation

- Linux server/client tests pass: private-room regressions, independent read/write
  grants, effective/default sender, escalation/invalid-grant denial, filtered SENT,
  merged history/discovery gap, cross-transport and FOLLOW revocation, cache isolation.
- Clean macOS server/client tests pass, including cache and GUI Lua state mocks.
  The actual GUI-linked release passes the full protocol integration suite.
- macOS SDL startup/first-frame probe passes (49 ms).
- Windows m101 help, error exit codes, keygen, redirected output and debug/bare GUI
  first-frame pass. Piped TOFU, registration, room creation, multiline stdin SEND
  and raw READ/cache pass against a dedicated m106 listener, not production.
- **Not validated:** desktop-visible Windows icons/console-presence (window probe
  reports `GUI window missing` in SSH session), full manual GUI conversation,
  identity switching and scrolling on either platform. Windows delegation-specific
  workflows are not separately tested; complete workflows pass on Linux/macOS.

## Delegation and recovery

```sh
cooloo delegate <child-id> read,write  # actual owner credentials; replaces grant
cooloo --as <owner-id> send <peer-id> "delegated sender"
cooloo --as <owner-id> sent <peer-id> 0
cooloo --as <owner-id> history
cooloo delegate <child-id> none       # revoke
```

Login identity remains the default. Grant only to an existing avatar; read/write
are independent, with no transitive grants or delegated management. GUI `/as <id>`
and `/self` select a window identity; ordinary caches are identity-partitioned.
SENT is filtered server-side and never written to the contiguous peer inbox cache.
History discovers peers from incoming messages: **peers that never replied are
omitted unless explicitly queried with sent**. GUI outgoing recovery is online/
in-memory, refreshed on reconnect, not persistent or continuously followed.
Physical SENT offsets reveal peer inbox size/activity, not unrelated content.

Private-room temporary policy remains: **any registered user can make any room
public, exposing all history; not a confidentiality guarantee**. No kick/leave/
owner transfer, room block API or GUI private-room controls.

Default private identity/config/cache: `~/.cooloo` (USERPROFILE fallback on Windows).
`COOLOO_CONFIG` selects an isolated root; `COOLOO_HOST=host:port` selects server.
Protect backups of the entire directory. Server backups must also include authz.

## Other limitations and rebuilding

No complete multi-device recovery, read receipts, contact/subscription sync or E2EE.
CLI chat is unavailable; FOLLOW does not automatically reconnect or send idle
keepalives. GUI memory is capped at 2000 messages; no older on-disk history paging.
Large-history performance, Windows >2 GB offsets/non-ASCII paths/ACL behavior and
concurrent GUI cache writers remain unvalidated.

Use fresh sibling sources at recorded commits: `make release-macos`, `make test`,
`make release-windows`. GitHub Release assets are standalone binaries, not LFS
pointers. Verify SHA-256 after download.
