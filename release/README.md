# cooloo client v0.3.0 — development workbench binaries (untagged)

GUI+CLI single binaries, Protocol 2 and Machine API schema 1.
Source commit: `3bea7ad391681cd329ba1ca18b9ddd16cc4b4f43`.
Integration server: `de4f3d21aecaa2190564c329608c02a9decd8010`.
Built 2026-10-16 in isolated `/tmp/cooloo-workbench-v030` on m106.
Installed into `release/` on 2026-10-17 after retrieving the original artifacts
and matching both SHA-256 values against the stage-6 validation record.
These are development refresh artifacts, not a tagged release. The user authorized
replacement without a tag despite the remaining manual acceptance items below.

| File | Target | Bytes | SHA256 |
|---|---|---:|---|
| cooloo-darwin-arm64 | macOS arm64, deployment target 11.0 | 2724168 | a639c508b671e5b3fc35be54e3cf51b6f706db89ea77238daf052dda1717505f |
| cooloo-windows-x86_64.exe | Windows x86_64 GUI subsystem | 4310356 | ed9864a52f15b99b6cb2580acaa25822bd7c6a6d804554da1e4400907a9b90d7 |

Git LFS tracked; unsigned/not notarized. Windows cross-built with mingw-w64,
only system DLL imports. macOS deployment target is 11.0, not runtime-verified on 11.

## Standalone offline editor — Windows development build (2026-10-17)

`editor-windows-x86_64.exe` is an optional standalone offline workbench, not a
replacement for the full cooloo client above. Launch it directly (no `--gui`
argument). It includes file editing, the Lua runner/console and local mock
messages, but no client network/identity/cache core or script messaging API.
It does not read/write `~/.cooloo`.

- Source commit: `3bea7ad391681cd329ba1ca18b9ddd16cc4b4f43` (committed source
  exported with `git archive`; existing local release changes were excluded).
- Built on m106 using mingw-w64, `make editor.exe`, in isolated directory
  `/tmp/cooloo-editor-win-hD8Tl7n2/client` on 2026-10-17.
- File: `editor-windows-x86_64.exe`; bytes: `4138999`.
- SHA-256: `733a76783aebf2b14393d23a078e5d6bd75b49b6fff7b000970a5d48486077d6`.
- Static checks: PE32+ x86_64, Windows GUI subsystem, only system DLL imports;
  client network/identity/cache/crypto entry-point symbols absent.
- Local Windows validation passed with isolated temporary HOME/config: SDL dummy
  and native first-frame probes; workbench and provider Lua suites; runtime
  persistence, traceback, stop/restart, output flood, file isolation and exit
  status suite using the same-source runtime test harness; offline runner has
  no `cooloo.request` / `cooloo.request_as`; no client config was created.
- The dummy video driver reported unsupported window-icon setup (expected);
  native first-frame startup passed. Manual desktop/IME/clipboard/file workflow,
  complete window/icon/console acceptance and oldest-OS compatibility remain
  unverified for this editor build. No server/network test was needed or run.
- Git LFS tracked, unsigned, untagged; no commit, push or external publication.
  Existing cooloo binaries were not replaced by this editor build.

## Upstream Lite — Windows comparison build

`lite-v1.11-windows.zip` is the unmodified official rxi/lite v1.11 release
archive, kept only for occasional UI/editor comparison. It is not Lite XL,
not a cooloo build input, and does not replace any cooloo/editor binary.

- Release: https://github.com/rxi/lite/releases/tag/v1.11
- Download: https://github.com/rxi/lite/releases/download/v1.11/lite.zip
- Bytes: `1072498`.
- SHA-256: `da3701cf6985bc493cb11b37556325551c7ce8606f5502ff3f15199039835eef`.
- The upstream archive includes `lite.exe`, `SDL2.dll`, `data/` and a Unix
  executable named `lite`. Extract the complete archive into a separate folder
  and run `lite.exe` there; the Windows executable needs its bundled DLL/data.
- Download size and ZIP integrity checked locally. The checksum above is a
  local fingerprint, not an independently published upstream checksum.
  Windows execution and manual comparison have not been tested.

## Upstream Lite XL — Windows comparison build

`lite-xl-v2.1.8-windows-x86_64.zip` is the official Lite XL Windows x86_64
archive, retained only for occasional comparison. It is not a cooloo build input.

- Release: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.8
- Download: https://github.com/lite-xl/lite-xl/releases/download/v2.1.8/lite-xl-v2.1.8-windows-x86_64.zip
- Bytes: `2303776`.
- SHA-256: `de4983f8f537e3876d0c326423537914b576b6970e35b9c9cc62eafe72719ec2`.
- The archive contains `lite-xl/lite-xl.exe` and an external `data/` tree
  (including Lua modules and fonts). No non-system DLLs were found in the PE
  import table. Extract the complete archive and run the exe beside `data/`;
  it is not a self-contained editor exe. The separate `setup.exe` assets are
  installers, not standalone editor builds.
- Archive SHA-256 matched GitHub's published digest and ZIP integrity checked.
  Windows execution and manual comparison have not been tested.

## Changes

- Replaces the legacy GUI with the modular Lite-based text workbench: file editing,
  tabs/splits, command palette, message workspace, local-cache history paging,
  independent Lua runner and persistent console.
- Retains Protocol 2, Machine API schema 1, identity and cache format compatibility.
- Keeps the Shanghai endpoint and verified official-server pin continuity from v0.2.4.
- Bare invocation prints help; launch the workbench explicitly with `--gui`.
- The planner's `windows/cooloo-dev.cmd` uses this fixed Windows artifact path;
  replacing the file updates the next launch without changing the command script.

## Validation

Original 2026-10-16 validation (same artifacts, verified by SHA-256):

- Linux client/workbench and Python SDK compatibility tests passed (7 SDK tests);
  no SDK publication was performed.
- macOS isolated server/client suites, full GUI-linked protocol integration and
  workbench/runtime integration passed. Native first-frame probe passed (50 ms).
- Windows m101 startup/redirection/exit/keygen, bare help, explicit/debug GUI
  first-frame probes, and workbench/provider/runtime tests passed.
- Windows desktop window/icon/console probe failed with `GUI window missing`
  in SSH Session 0. It was not a passing desktop acceptance test.
- Windows protocol network testing was not run in that validation round.

2026-10-17 refresh checks:

- Retrieved both original binaries from m106, verified sizes, SHA-256 and executable
  formats; macOS binary reports `cooloo 0.3.0` on m106.
- On the local Windows host, `tests/windows-startup.ps1` passed using an isolated
  temporary config, without a network test host. Explicit/debug GUI first-frame
  probes passed; this is not manual desktop/IME acceptance.
- The unchanged `cooloo-dev.cmd version` reports `cooloo 0.3.0`; an invalid command
  preserves exit code 2. No production registration or messages were sent.

Still unverified: real Windows/macOS Chinese IME preedit/candidate placement and
commit/cancel, clipboard, shortcuts, file open/save, tabs/splits, runner controls,
window closing, complete window/icon/console acceptance, oldest supported OS and
full compatibility matrix. Development replacement does not close these gates.
No tag, GitHub Release or SDK publication was performed.

Rebuild from the source commit with sibling server:
`make release-macos; make test; make test-workbench-macos; make release-windows`.
