# cooloo client v0.2.3 — JSON machine API and Python distribution

GUI+CLI single binaries. Protocol 2; delegation/SENT require server v0.2.2.
Source commit: `2ac3f027aca3b5f6a746e490bf5dd3384fc0b746`.
Integration server: `de4f3d21aecaa2190564c329608c02a9decd8010` (unchanged).
Built 2026-10-15 in isolated `/tmp/cooloo-python-v023-final` on m106.
The later artifact commit contains these outputs; it is not their build input.

| File | Target | Bytes | SHA256 |
|---|---|---:|---|
| cooloo-darwin-arm64 | macOS arm64, deployment target 11.0 | 2589896 | 701cdeab865967ec15a41a5d1d44ed607ceca2329d04a775f421e693d1fe84f8 |
| cooloo-windows-x86_64.exe | Windows x86_64 GUI subsystem | 4161497 | 19079ec6c559eb58c5ddac6807669ba51b34fa830103246cdae003b7613fc28a |

Git LFS tracked; unsigned/not notarized. Windows cross-built with mingw-w64, system
DLLs only. macOS minimum is pinned for both SDL and final link, not inferred from host OS.
Actual execution on macOS 11 has NOT been tested.

## Changes

- `--json` JSONL schema 1, noninteractive TOFU, structured results/errors and version query.
- Machine READ/FOLLOW do not write normal caches; explicit FOLLOW byte offset.
- Message end-offset and SENT scan-offset preserved. No automatic retries/ACKs.
- SEND lost acknowledgement reports uncertain delivery; AS failure never falls back.
- `--gui` explicit GUI alias; ordinary CLI and GUI remain available.
- Redirected Windows machine processes do not allocate a console solely for stdio.
- See ../MACHINE_API.md and https://github.com/cooloo-app/python-sdk .

## This release's validation

- Linux existing client integration, Lua state and cache tests passed.
- Clean macOS server/client tests passed; Python integration/process suite 7/7 passed
  against the GUI-linked release and again from the installed final wheel (Python 3.14).
- macOS GUI startup first-frame probe passed (28 ms final run).
- Windows m101 Python 3.12 wheel import, JSON output/exit status, pip/pipx install/run,
  explicit GUI first-frame (1 ms) and Unicode package installation path passed.
- Windows Python against isolated m106 port 24223: multiline Unicode SEND/READ, explicit
  FOLLOW + cancellation, delegation/revocation, filtered SENT empty cursor and no cache passed.
- Both platform wheels built and twine check passed; bundled hashes verified after transfer.
- No production mutation/deployment. macOS/Windows full interactive GUI, desktop-visible
  window/icon/console state, macOS 11 runtime, Windows Unicode identity-directory paths,
  Python 3.10/3.11/3.13 and full architecture/OS matrix remain unverified.
- Binary default blocking calls still have no new network deadline; Python enforces process
  deadlines. No automatic follow reconnect or keepalive. See SDK docs for explicit close.

## Rebuild / publication

Use sibling source commits above: make release-macos; make test; make release-windows.
Python wheels include this same GUI+CLI binary, not a CLI-only build.
Local tag requested as v0.2.3; pushing tags/LFS, GitHub Release and PyPI upload are separate.
SDK 0.1.0 public-package release is blocked on owner license approval and publication setup.
