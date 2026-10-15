# cooloo client v0.2.1 — Simple private rooms

Requires a Protocol 2 server; `join` and `room-mode` require server v0.2.1.
No protocol-1 compatibility or legacy history/config migration is provided.

## Artifacts (Git LFS)

Built on 2026-10-15 in isolated `/tmp/cooloo-private-room-v021` on m106
(macOS arm64), with Windows x86_64 cross-compiled using mingw-w64.
Exact client source: `b5c2cdd267621bc911bac11f46b4454e047df9ff`.
Integration-test server: `3413938742993e407d2a42e8ff4d9bcf165e0a3b`.
The artifact-containing release commit is not the source build input.

| File | Platform | Bytes | SHA-256 |
|---|---|---:|---|
| `cooloo-darwin-arm64` | macOS arm64 | 2552664 | `6b745cfacef7664515cd7d188713e8968ca50c58c982f1c2df557737cfea0169` |
| `cooloo-windows-x86_64.exe` | Windows 10+ x86_64 | 4144936 | `c2c0de79510af41aad57ea829406f50e6eee605140fe817380c30434b6396bb7` |

Mach-O arm64 / PE32+ x86_64 GUI subsystem; static vendored libraries and
Windows system DLLs only (including UCRT). Unsigned/not notarized. No Linux GUI.

## Validation

- Linux server/client tests pass, including private-room cooldown, replay,
  historical-sender snapshots, capacity/concurrency, metadata ACL and FOLLOW.
- Clean macOS server/client, cache and Lua tests pass. The actual GUI-linked
  release binary passes the full protocol integration suite.
- macOS real SDL startup/first-frame probe passes (47 ms).
- Windows m101 real-machine help, error exit codes, keygen, redirected output,
  debug/bare GUI first-frame startup pass.
- Windows piped TOFU, registration, room creation, multiline stdin SEND and
  raw readback pass against a dedicated m106 test listener, not production.
- **Not validated:** Windows desktop-visible window icons/console-presence.
  The window probe reports `GUI window missing` in the SSH session; first-frame
  startup is not an interactive desktop test. Full manual GUI conversation/
  scrolling is not tested on either platform. Windows-specific private-room
  command workflows are not separately tested; the full workflows pass on
  Linux and the macOS release binary.

## Private-room commands

```sh
./cooloo-darwin-arm64 join <room-id>
./cooloo-darwin-arm64 room-mode <room-id> private
./cooloo-darwin-arm64 send <room-id> "@<room-id> join-approve <applicant-user-id>"
./cooloo-darwin-arm64 room-mode <room-id> public
```

**Temporary policy: any registered user can make any room public, exposing all
history. This is not a confidentiality guarantee against registered users.**
Public -> private includes owner, existing members and this room's historical
senders, not every registered user. Maximum 200 members; member blocks are
reserved (0–256 bytes), initially empty, with no block API. Requests are more
than 24 hours apart and expire after seven days. No kick/leave/owner transfer.

Default config/private identity/cache: `~/.cooloo` (USERPROFILE fallback on
Windows); `COOLOO_CONFIG` selects an isolated root and `COOLOO_HOST=host:port`
selects the server. Stop processes and protect the entire directory for backup.

## Other limitations and rebuilding

CLI interactive `chat` is unavailable. FOLLOW does not automatically reconnect
or send idle keepalives. GUI memory is capped at 2000 messages; on-disk history
paging and GUI private-room controls are not implemented. Cache append scans
the full log; large-history performance, Windows >2 GB offsets/non-ASCII paths/
ACL behavior and concurrent GUI cache writers remain unvalidated.

Use fresh isolated sibling client/server sources at the recorded commits:
`make release-macos`, `make test`, `make release-windows`. GitHub Release assets
are standalone binaries, not LFS pointer files. Verify SHA-256 after download.
