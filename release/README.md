# cooloo client — development artifact refresh (2026-10-18, untagged)

## Latest: Windows text editor caret alignment fix (2026-10-18)

Only `cooloo-text-windows-x86_64.exe` is refreshed. Other seven artifacts retain
previous provenance. This supersedes earlier Windows text artifact notes below.

- Font fix source commit: `b57a6407de83afdbb5381e1febbfb6aee84ce0b4`.
  Glyph advances are rounded once in the font cache and shared by text width
  and drawing, eliminating cumulative caret/selection/hit-test drift while
  preserving the existing per-glyph drawing spacing.
- Build includes pre-existing, uncommitted event-bridge/IME working-tree changes;
  those changes are not part of the caret-fix commit. This is a working-tree
  snapshot build, **not a clean-commit build or a tagged release**.
- Exact input archive (client + sibling server, excluding release files) SHA-256:
  `effc467f3c1ae47f61e6398de539182ad1aab9a04812b9d25bcac03b3554aa07`.
  Server source: `de4f3d21aecaa2190564c329608c02a9decd8010`; not built or used.
- Isolated m106 build: `/tmp/cooloo-caret-fix-cWFJR5/client`, MinGW GCC 16.2.0,
  `make -j4 cooloo-text.exe` only.
- Installed artifact: **4,167,201 bytes**, SHA-256
  `5a33a47a2f16980df00aed9dfa6758069411d00a429d2632df2a450be46ba8ae`.
  Transfer and installed-file hashes matched. Static inspection: PE32+ x86_64,
  GUI subsystem, system DLL imports only.
- **No tests or application execution performed, at explicit user request.**
  Caret alignment, selection, mouse hit testing and IME desktop acceptance remain
  unverified for this build. Earlier test results are not this build's results.
- The running local editor was not terminated: its old executable was moved to
  local temporary backup before installing the new artifact. Restart the editor
  to use the refreshed binary. No tag, GitHub Release or Python publication.

## Previous: Windows text editor Lite-baseline update

Only `cooloo-text-windows-x86_64.exe` is replaced by this update. Other seven
artifacts below retain their earlier provenance and behavior.

- Source: `6d3b4fd64b23e3c2a48377ee701eeecbd55cde15` **plus uncommitted working-tree
  changes** implementing Lite host/project/plugins stages 0–5. Not a clean-commit
  build and not a tagged release.
- Snapshot (tracked + new source, excluding release binaries) SHA-256:
  `4bbfe7482f6dd037085d1eafc55c7684ceb59739d9eba0e9f67c6641d366dab2`.
- Isolated m106 tree: `/tmp/cooloo-text-lite-20261017-2241/client`; Apple clang
  21.0.0 and MinGW GCC 16.2.0. `make cooloo-text.exe cooloo-text build/lua-runner`
  passed. macOS text was built/tested for validation, not copied to release.
- Windows artifact: 4,164,921 bytes; SHA-256
  `e19f842d07ac76b58fcde34155ea0c8056abcd8b2b729d0d79b1350775fe4bd6`.
  Rechecked after transfer to local staging and Windows m101. PE32+ x86_64 GUI,
  system DLL imports only; no communication/cache/runner entry-point symbols.
- Passed `tests/editor_integration.py` on m106 and native Windows m101 with SDL
  dummy: normal + safe mode, 16 plugins, extension order and load-error recovery,
  user helper modules, project scan/Ctrl+P/project search, pane drop dispatch,
  macro replay, dirty-file reload protection, final newline/CRLF, virtual/readonly,
  Chinese file/project paths, 60-frame pacing and actual argv directory child
  launch with spaces/Unicode/shell metacharacters.
- Passed workbench Doc/View/composition and provider tests on m106 and locally;
  local `make test-workbench-headless` passed. No client/server protocol changes;
  no server or production service used for this refresh (server checkout remains
  `de4f3d21aecaa2190564c329608c02a9decd8010`).
- **Not verified:** real OS drag-and-drop delivery, visual blink, desktop
  clipboard/Chinese IME, window/icon/console behavior, older Windows/macOS matrix.
  SDL dummy's unsupported-icon warning is expected, not a desktop icon test.
  UTF-8 filename manifest requires Windows 10 1903+.
- User/project Lua now executes in normal text mode; see
  [extension/trust guide](../modules/EDITOR.md). `--safe-mode` skips external
  extensions, not an OS sandbox. Full workbench still has no automatic discovery.
- No commit, push, tag, GitHub Release or Python publication performed.

## Earlier all-product refresh (unchanged artifacts except Windows text)

Source commit: `f768a1cc3e9ddb036f2a73e343b3d24d99824be9`.
Integration server: `de4f3d21aecaa2190564c329608c02a9decd8010`.
Built from committed `git archive` exports in isolated sibling client/server trees
at `/tmp/cooloo-text-refresh-f768a1c-20261017` on m106 (macOS arm64).
Toolchain: Apple clang 21.0.0, mingw-w64 GCC 16.2.0, vendored SDL3/Lua.
This is a development refresh, not a formal release. The client version remains
0.3.0; no new tag, GitHub Release or Python SDK publication is part of this update.

## Products

- **cooloo**: full communication CLI + GUI workbench. Bare invocation prints help;
  use `--gui` to launch the GUI, optionally `--debug` for console logs.
- **cooloo-text**: standalone general-purpose text editor, `cooloo-text [FILE ...]`.
  No message workspace, execution console/runtime, client network/identity/cache
  core or `~/.cooloo` access. The old `editor` source build names are aliases for
  this pure editor, not the old offline mock-message workbench.
- **cooloo-workbench**: headless message JSONL validate/render and Lua runner CLI.
  No SDL or communication identity/config/network core. `--lua-run` and the
  length-framed `--lua-console` live here, not in cooloo-text.
- **cooloo-cli**: existing headless communication CLI, without SDL/editor modules.

The obsolete `editor-windows-x86_64.exe` offline workbench artifact has been
removed; use `cooloo-text-windows-x86_64.exe` for ordinary text editing and
`cooloo-workbench-windows-x86_64.exe` for headless projection/runner commands.
Full GUI console and messaging remain in `cooloo-windows-x86_64.exe --gui`.
Message projection timestamps now use UTC consistently in CLI and GUI.
The planner's `windows/cooloo-dev.cmd` continues to use the unchanged full-client
artifact path; no launcher update is required.

## Artifacts

All macOS files are Mach-O arm64 with deployment target 11.0. Windows files are
PE32+ x86_64: cooloo/text use the GUI subsystem, workbench/cli use console.
Windows imports are system DLLs only (including Windows UCRT API-set DLLs).
No separate SDL/Lua DLL is needed. Git LFS tracked; unsigned/not notarized.
Deployment target and import checks do not prove oldest-OS runtime compatibility.

| File | Bytes | SHA-256 |
|---|---:|---|
| cooloo-darwin-arm64 | 2740680 | 19dbe8447c5c46d1a0ef572df8a4b704bbdab6ec401fc9b3ae4fc3c76e183bcd |
| cooloo-windows-x86_64.exe | 4313940 | d62d3e6634ba4873a79c607bbcaa53f8c3161e6a3fab7f5e77d3716406b8e023 |
| cooloo-text-darwin-arm64 | 2546888 | 8b7034f26ddbb4f32c8f265959b7fc50cb094296d2d8ca5703086e51f89435a5 |
| cooloo-text-windows-x86_64.exe | 4167201 | 5a33a47a2f16980df00aed9dfa6758069411d00a429d2632df2a450be46ba8ae |
| cooloo-workbench-darwin-arm64 | 298784 | d7e5ae2a99febbf4e6f5152c3e86cdfe076e480ae0e948628d2d9fc299bdc9c3 |
| cooloo-workbench-windows-x86_64.exe | 645198 | 6bba542e60c7eef4d61094720f7ab8b4d18a917fe04d181d377f2baf7d4fe6c3 |
| cooloo-cli-darwin-arm64 | 161592 | 3d516b005635da5d54d7a2c921f01cec4411081f2e8cf41c3160e0660f359bc8 |
| cooloo-cli-windows-x86_64.exe | 603010 | a7c75d0ec7f39572f2c8eb72adf29c0adfb7b85dd0f5782ea1cdd6aebab9eb49 |

SHA-256 values were computed on m106 and rechecked after retrieval to local
staging. All four Windows artifact hashes also matched on m101.

## Earlier refresh's validation (not the latest text test scope)

Passed on m106:

- `make release-macos` and `make release-windows`: all four products per platform.
- `make -C ../server all` then `make test`: config relocation/pin continuity,
  offline help/errors and stub-only entry dispatch, Protocol 2 private rooms,
  delegation, filtered/merged history, cross-transport revocation, identity-cache
  isolation, Lua protocol state, cache gaps/duplicates/conflicts/crash-tail tests.
  The current suite reports named groups rather than the historical 24-case count.
- `make test-workbench-headless`: projection/anchors, console session, CLI
  success/errors, UTF-8/size limits, bundle isolation, file/framed runners and
  binary-symbol dependency isolation.
- `build/lua-runner --lua-run tests/provider.lua`: async checkpoints,
  subscriptions/overflow, stale identity, send ACK/rejection/uncertainty.
- Binary formats, macOS system-library dependencies and 11.0 load commands,
  Windows subsystem and DLL imports; both text-editor binaries exclude client
  communication/cache and execution-runtime entry-point symbols.

Passed on Windows m101 with temporary, isolated HOME/config and no network:

- Full client and communication CLI: bare/full help, version, redirected
  stdout/stderr, invalid-command/missing-argument exit codes and key generation.
- Workbench: UTF-8 text/JSON projection and anchors, malformed/oversized input,
  invalid UTF-8/NUL, record limits, CRLF/no-final-LF, missing file, Lua file runner,
  length-framed console and malformed-frame exit code.

**Intentionally skipped:** all GUI self-tests, SDL dummy/first-frame probes,
Doc/View interaction, desktop window/icon/console acceptance, Chinese IME,
clipboard, file workflows, tabs/splits and GUI runner/message interactions.
The standalone text binary was built and statically inspected, not run.
Windows network tests, full GUI-linked protocol integration, macOS 11 runtime
and the complete supported-OS compatibility matrix were not tested this round.
Previous artifacts' GUI acceptance results do not apply to these new binaries.
No production service was accessed and no production messages were sent.

Rebuild (sibling server required):

```sh
make -C ../server all
make release-macos
make test
make test-workbench-headless
build/lua-runner --lua-run tests/provider.lua
make release-windows
```

These `release-*` targets build artifacts only; they do not publish anything.
GUI validation remains a separate outstanding acceptance task.

## Upstream Lite — Windows comparison build

`lite-v1.11-windows.zip` is the unmodified official rxi/lite v1.11 archive,
retained only for UI/editor comparison, not a cooloo build input.

- Release: https://github.com/rxi/lite/releases/tag/v1.11
- Download: https://github.com/rxi/lite/releases/download/v1.11/lite.zip
- Bytes: `1072498`.
- SHA-256: `da3701cf6985bc493cb11b37556325551c7ce8606f5502ff3f15199039835eef`.
- Extract the complete archive, including `SDL2.dll` and `data/`, separately.
  It also contains a Unix executable named `lite`.
- Previously checked download size and ZIP integrity; checksum is a local
  fingerprint, not an independently published upstream checksum. Windows
  execution/manual comparison not tested. This archive was not changed here.

## Upstream Lite XL — Windows comparison build

`lite-xl-v2.1.8-windows-x86_64.zip` is the official Lite XL Windows archive,
retained only for comparison, not a cooloo build input.

- Release: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.8
- Download: https://github.com/lite-xl/lite-xl/releases/download/v2.1.8/lite-xl-v2.1.8-windows-x86_64.zip
- Bytes: `2303776`.
- SHA-256: `de4983f8f537e3876d0c326423537914b576b6970e35b9c9cc62eafe72719ec2`.
- Extract the whole archive and run `lite-xl/lite-xl.exe` beside its `data/`.
  Previously found system DLL imports only; this is not a self-contained exe.
  Separate `setup.exe` assets are installers.
- Previously matched GitHub's published digest and checked ZIP integrity.
  Windows execution/manual comparison not tested. This archive was not changed here.
