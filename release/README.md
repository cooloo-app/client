# cooloo client v0.2.0 — Protocol 2

**Breaking release: requires a protocol-2 server. Production is still protocol 1;
production cutover is explicitly deferred. Do not use these binaries against the
current production deployment. No legacy history/config migration is provided.**

## Artifacts (Git LFS)

Built on 2026-10-14 in an isolated m106 macOS arm64 directory.
Exact source commit: `ed5b5f57e9e47a87dd566d0efbfa16803c557a26`.
Integration-test server: `a891fff40cf58805bfe208220fede43bf18be6af`.
The release tag includes these artifacts and subsequent test-script/documentation
changes; it does not claim the artifact-containing commit was the build input.

| File | Platform | Bytes | SHA-256 |
|---|---|---:|---|
| `cooloo-darwin-arm64` | macOS arm64 | 2552664 | `c4e7289d947b37fc058617a3adca6e9f949f084ed4720cc1336cde00393b1aa5` |
| `cooloo-windows-x86_64.exe` | Windows 10+ x86_64 | 4143853 | `5e4aff37fe1e2861ae10aba0a97d6fa2ec658f22f42464d1582f87061121cdab` |

macOS: Mach-O arm64. Windows: PE32+ x86_64, GUI subsystem, static vendored
libraries; imports only Windows system DLLs (including UCRT). Linux GUI is not
included. Binaries are not signed/notarized.

## Validation

- Linux server/client protocol-2 tests pass.
- macOS clean-source server tests, CLI/cache/Lua state tests pass; the actual
  GUI-linked binary also passes the isolated protocol integration suite.
- macOS real SDL window startup and first-frame probe pass.
- Windows m101 real-machine help, errors/exit codes, public-key generation,
  redirected output, bare/debug GUI first-frame startup pass.
- Windows interactive TOFU through redirected stdin, registration, room creation,
  multiline piped send, raw readback and durable cache pass against a dedicated
  protocol-2 test listener, not production. This caught and fixed long cache
  paths exceeding MAX_PATH.
- **Not validated:** Windows desktop-visible icons and console-presence probe.
  m101 SSH runs in session 0; the GUI process stays alive but has no observable
  MainWindowHandle. First-frame startup is not a substitute for interactive
  desktop validation. Full manual GUI conversation/scrolling is not tested on
  either platform. Actual sshd identity binding and production cutover are not
  tested.

## Usage

Set `COOLOO_HOST` to your **protocol-2 test server**, not current production.

```sh
chmod +x cooloo-darwin-arm64
export COOLOO_HOST=127.0.0.1:4222
./cooloo-darwin-arm64 keygen
./cooloo-darwin-arm64 -y whoami --register alice
./cooloo-darwin-arm64 create general   # returns ROOM <64-hex-id> general
./cooloo-darwin-arm64 send <room-id> "hello"
./cooloo-darwin-arm64 read --raw <room-id> 0
./cooloo-darwin-arm64                 # GUI
```

Windows has the same CLI commands; double-click enters GUI and `--debug` enables
console logs. Config/private identity/cache default to `~/.cooloo` (USERPROFILE
fallback on Windows); `COOLOO_CONFIG` selects an isolated root. Backups include
private keys: stop processes and protect the entire directory.

## Known limitations

- No protocol-1 compatibility or legacy migration. IDs are actual public keys;
  nicknames may repeat and must not be used as addresses.
- CLI interactive `chat` is unavailable; FOLLOW resumes on re-invocation but
  does not automatically reconnect or send idle keepalives.
- GUI keeps 2000 messages in memory; older JSONL history cannot yet be paged in
  the UI. GUI registration still uses the old 16-character ASCII form.
- Cache append scans the full log; large-history performance is not benchmarked.
- Windows >2 GB cache offsets, non-ASCII paths/ACL behavior and concurrent GUI
  cache writers have not been validated.

## Rebuilding

See the Makefile: `make release-macos`, `make test`, `make release-windows`.
Use fresh isolated sibling client/server checkouts at the recorded commits.
Verify checksums after copying/downloading. The two files are tracked by Git LFS;
GitHub Release assets are standalone binaries, not LFS pointer files.
