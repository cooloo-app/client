# cooloo client

Single-binary cooloo client: **v1 CLI + v2 GUI in one exe**
(C core + vendored SDL3/Lua/stb_truetype, software rendering, terminal
aesthetic). No runtime dependencies beyond the OS.

```
cooloo                  bare -> GUI (D31)
cooloo --debug          GUI with console logs (Windows: attach or allocate console)
cooloo --lua-dev <dir>  GUI with script hot reload; no gui subcommand
cooloo keygen           create identity, print fingerprint
cooloo send <room> [text...]        append (stdin when no text args)
cooloo read [--raw] <room> <off|-N> read messages
cooloo follow <room>    stream (persists offset, auto-resume)
cooloo chat <room>      interactive read/write
cooloo rooms | whoami [--register <nick>]
flags: -y/--tofu  auto-trust unknown server fingerprint
env:   COOLOO_HOST=host[:port]  COOLOO_CONFIG=<dir>
```

## Build

| target | tool | result |
|---|---|---|
| `make` | clang (macOS) | `./cooloo` native binary |
| `make test` | + sibling `server` repo | loopback integration (24 checks) |
| `make release-windows` | mingw-w64 (`brew install mingw-w64`) | `./cooloo.exe` (PE32+, system DLLs only) |
| `make release-macos` | clang | native binary (arm64 on m106) |

First build runs CMake on the vendored SDL3 (static, video+events only)
and `tools/embed.py` to compile `lua/*.lua` + the primary TTF into the
binary. Vendored components with versions/sha256: `src/vendor/README.md`.

Linux GUI is currently **out of scope** (owner decision 2025-09-06);
the CLI remains POSIX-portable.

## GUI key bindings

| key | action |
|---|---|
| `Ctrl-J` / `Ctrl-K` | switch room |
| `Enter` | send; `Shift-Enter` / `Ctrl-Enter` inserts a newline |
| `PageUp` / `PageDown` | scroll history (top-of-history auto-fetches older) |
| `Ctrl-L` | reconnect |
| `Ctrl-Q` | quit |
| `F2` | server fingerprint / own nick & fingerprint overlay |
| `Ctrl/Cmd-V` | paste (multi-line ok) |

Mouse: click a room to select, wheel scrolls. Scrolling away from the
bottom pauses follow-tail; returning to the bottom resumes it.

## GUI behavior notes

- One FOLLOW connection per room + one ctrl connection (ROOMS/HELLO/SEND);
  MSG lines carry no room field, so per-room conns are what make
  multi-room follow unambiguous (wiki reference/native-api.md).
- Room list refreshes every 30s (piggybacked on PING); rooms created
  after connect appear without a restart.
- TOFU: unknown server fingerprint shows a trust dialog (`T` trust /
  `Esc` abort), same semantics as the CLI prompt. Changed fingerprint
  refuses to connect.
- Offsets persist per room (`offset.<room>` in config) on every message:
  restart/reconnect resumes without loss.
- IME (macOS pinyin tested path): preedit renders inline with an
  underline; the OS candidate window is placed at the input cursor.
- CJK: embedded JetBrains Mono has no CJK glyphs; a platform fallback
  chain probes hardcoded paths (macOS PingFang/STHeiti, Windows msyh/
  simsun, Linux Noto/WQY) and mmap's the first hit.
- Window size persists across runs (`gui.w`/`gui.h` in config).

## Config (~/.config/cooloo/)

`identity` (0600 X25519 secret), `known_servers` (TOFU pins),
`config` kv: `host` `port` `nick` `offset.<room>` `gui.w` `gui.h`.
Full field reference: planner wiki `reference/client-config.md`.

## Repo layout

```
src/        main cli net noise_xx config (v1) + gui font luabind (v2)
lua/        all UI logic: main (frame dispatch) chat ui input
tools/      embed.py (asset->C), generate_icon.py, mingw-toolchain.cmake
assets/     transparent orange-C PNG/ICO (generated without fonts or dependencies)
tests/      nettest.sh (CLI loopback integration)
src/vendor/ monocypher lua sdl3 stb_truetype.h fonts/ (see README.md)
```

## Platform caveats

- **Windows startup**: GUI subsystem (`-mwindows`): double-click/bare launch
  creates no console. `--debug` attaches to the parent's console or allocates
  one. CLI commands initialize console I/O while preserving pipes/redirection.
  CMD may return immediately for an interactive GUI-subsystem launch; use
  `start "" /wait cooloo.exe --debug` when synchronous waiting is wanted.
- **Icons**: transparent orange C (`#D9622B`), multi-size ICO embedded via
  windres; embedded RGBA is passed to SDL_SetWindowIcon. No image sidecars.
  Regenerate with `python3 tools/generate_icon.py`.
- **Windows tests**: `powershell -File tests/windows-startup.ps1 -Exe <exe>`
  verifies startup, redirection and exit codes. Set `COOLOO_TEST_HOST` to an
  **isolated test server** to also test TOFU/stdin send/read. Run
  `tests/windows-window.ps1` to check actual window icons and console presence.
  Verified on Windows 10, 2026-10-10.
- **Windows CLI**: builds and socket paths work; `chat`/`follow` poll
  stdin via WSAPoll which does not support console handles - use
  `send`/`read` there.
- **macOS**: 1:1 pixels (no HiDPI flag); on Retina the OS scales the
  window x2 (deliberate minimal choice).
