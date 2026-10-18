# cooloo client — development artifact refresh (2026-10-18, untagged)

## Latest: round-3 adversarial fixes — Windows text only (2026-10-18)

`cooloo-text-windows-x86_64.exe` is rebuilt from committed client source
`89db9d01b0b2f0fd2e2e9e161b9b26e047753dcc` (initial fixes `69d838d`, edge-case
and regression follow-up `89db9d0`). Input git archive SHA-256:
`c35d6e2998499f2fcb73431d387abb93501388108fb1ca6b2aea6c30b3c97f43`.
Other seven artifacts retain the `2fc9021` provenance below.

- Fixes five reviewed root causes: equivalent-path rename deleting saved data,
  fatal diagnostics overwriting existing files/symlink targets, failed Doc load
  destroying edits/history, invalid UTF-8 navigation hanging, and focus-loss
  modifiers triggering unwanted shortcuts. Macro recordings also preserve
  focus-loss resets in their isolated playback state. See
  [editor contracts](../docs/EDITOR.md) and [event contract](../docs/EVENTS.md).
- Final isolated m106 build: `/tmp/cooloo-round3-final.rK0wlM/client`, Apple clang
  21.0.0 and MinGW GCC 16.2.0, vendored SDL3/Lua. macOS text and native harnesses
  are validation-only; the installed release refresh is Windows text only.
- Linux/macOS passed Round 3 and Round 2 acceptance, renderer/cache/event bridge,
  normal/safe editor integration, lifecycle, prior adversarial tests, native
  close/replace failure injection, workbench local smoke and headless tests.
  Five independent Linux negative controls rejected old implementations
  (four assertion failures, one navigation timeout).
- Linux/macOS `make test` passed after repairing the existing startup-test stub
  for `luabind_set_args` and building sibling server gate/daemon. These tests use
  isolated configuration and loopback only; server source remains
  `de4f3d21aecaa2190564c329608c02a9decd8010`, unchanged.
- Native Windows m101 passed Round 3 (including symlink cases), Round 2,
  renderer/event bridge, file close/replace fault injection, normal/safe editor
  integration, lifecycle and local workbench smoke. Test tree:
  `C:\Users\Plato\AppData\Local\Temp\cooloo-round3-final-ql7n577x`.
- PE32+ x86_64 GUI subsystem, Windows system DLLs only. Build, transfer, Windows
  execution copy and installed artifact hashes match. **4,222,131 bytes**, SHA-256:
  `0067db5f3a75b3b6f33d7d7d133dd71351a390e37d3f0285963a1ef7b6581f9d`.
- **Not verified:** real desktop focus/Alt-Tab and IME candidates, OS clipboard
  and drop delivery, multi-display DPI/visual acceptance, exhaustive ACL/UNC/
  reparse/network-filesystem behavior, concurrent external rename races,
  power-loss durability, native malformed-font safety or full workbench network
  integration. D04 remains deferred. SDL dummy is not desktop acceptance.
- Development refresh only; no tag, GitHub Release or Python publication.

## Historical: round-2 adversarial fixes — Windows text only (2026-10-18)

`cooloo-text-windows-x86_64.exe` is rebuilt from committed client source
`3eb7a2f73aa64eefc445dd9f5bfeb40a8e375f4d` (main changes `15709d5`, macOS ACL
follow-up `3eb7a2f`). Input archive SHA-256:
`ece40e3cec447ad4ebc50fa5a418f97e8fc89f76fbb77df2a652a6a9a0f20ef6`.
Other seven artifacts retain the `2fc9021` provenance below.

- Fixes eight reviewed root causes: unsafe failed saves, undo-branch dirty state,
  format dirty state, concurrent recovery overwrites, EOF selection mutation,
  macro modifier corruption, IME macro deletion, and invalid-ancestor path bypass.
  See [editor contracts](../docs/EDITOR.md) for save/format/link policies.
- Isolated m106 build: `/tmp/cooloo-round2.PVxHP4/client`, Apple clang 21.0.0 and
  MinGW GCC 16.2.0. Windows text and native test harnesses; macOS text/harnesses
  built for validation only. Both builds use vendored SDL3/Lua.
- Linux/macOS passed renderer/cache/event, `round2_test.py`, native close/replace
  fault tests, prior adversarial suite, normal/safe editor integration, lifecycle,
  local workbench smoke and headless projection/session. POSIX tests exercise
  real partial-write failure, mode/xattr preservation and symlink targets;
  macOS additionally verifies extended ACL preservation. The first macOS run
  exposed the absent-ACL convention; the source follow-up above fixes it, and
  the complete macOS suite was rerun successfully.
- Native Windows m101 passed renderer/event, file close/replace fault injection,
  round-2 regressions (including broken junction entry points and named/untitled
  concurrent recovery), normal/safe editor integration, lifecycle, safe-mode
  theme/modifier smoke and local workbench smoke. Isolated execution tree:
  `C:\Users\Plato\AppData\Local\Temp\cooloo-round2-qj__oupe\client`.
- PE32+ x86_64 GUI subsystem; only Windows system DLL imports. Build, transfer,
  Windows execution and installed file hashes match. **4,220,083 bytes**, SHA-256:
  `de2a2f921fa3bcde74ef2a3b8521f59b488527765f41310877a46e0733313fa2`.
- **Not verified:** real desktop IME/candidates, OS clipboard/drop delivery,
  cross-window key release, multi-display DPI/visual acceptance, exhaustive
  ACL/UNC/reparse/network-filesystem behavior, power-loss durability, native
  malformed-font safety or full workbench/network regression. D04 remains
  explicitly deferred. Dummy tests are not desktop acceptance.
- Sibling server `de4f3d21aecaa2190564c329608c02a9decd8010` exported for layout,
  not built or run. Text-specific tests were used rather than CLI-oriented
  Windows startup scripts. Development refresh; no tag, Release or PyPI publish.

## Historical: adversarial integration fixes — Windows text only (2026-10-18)

Only `cooloo-text-windows-x86_64.exe` is refreshed; the other seven artifacts
retain the `2fc9021` provenance below. Client source:
`7e4ef89d46f93be90ebb0b9df9ad6cdec94ec20b` (committed git archive, no source edits
after export). Input archive SHA-256:
`de372ffa2639a49834be1cedd2c2623b4859a1bfbaacc49810d83febe564f785`.

- Fixes exclusive temporary-file reservation/session cleanup, document-open error
  propagation, POSIX executable discovery, portable user-theme precedence, and
  overlapping physical modifiers. Malformed external fonts can still crash the
  inherited stb parser; comprehensive validation is explicitly deferred. Lua
  recovery does not cover native crashes; see [editor guide](../docs/EDITOR.md).
- Isolated m106 build: `/tmp/cooloo-adversarial.hkcxEP/client`; Apple clang 21.0.0,
  MinGW GCC 16.2.0, vendored SDL3/Lua. Built Windows text + renderer/event harnesses,
  native macOS text + harnesses; macOS output is validation-only, not installed.
- Passed Linux and macOS renderer/cache/event tests, new `adversarial_test.py`
  (concurrent normal/fatal cleanup, file failures/aliases, actual directory child
  launches from absolute/relative/PATH/renamed symlink entries, theme and modifier
  matrices), normal/safe editor integration, and lifecycle init/frame/thread/draw/
  quit/cancel. Linux workbench Doc/View/composition smoke also passed.
- Passed native Windows m101 SDL dummy renderer and event bridge, normal/safe
  `editor_integration.py` (Unicode paths and actual directory child),
  `lifecycle_test.py`, and file/package theme + modifier matrices in
  `tests/adversarial.lua`. Test tree:
  `C:\Users\Plato\AppData\Local\Temp\cooloo-adversarial-w7xj_dyk\client`.
  Isolated fixtures only; no network or production configuration used.
- PE32+ x86_64 GUI subsystem; system DLL imports only. Remote build, local staging,
  Windows execution copy and installed artifact SHA-256 all matched:
  `0efb18195880706eaf8055901d2ca75cea5bc85925b88562a5f125502c1cc414`;
  **4,209,492 bytes**.
- **Not verified:** real OS IME/candidates, clipboard, drag/drop, cross-window key
  release, multi-display DPI and visual acceptance; full Windows ACL/junction
  matrices, malformed-font sanitizer coverage, full workbench/network regression.
  CLI-oriented `windows-startup.ps1` / `windows-window.ps1` are not text-product
  tests; the text-specific integrations above were used instead.
- Existing local exe was locked by a running application; preserved it under
  planner `temp/adversarial-artifacts/previous-running-cooloo-text.exe` before
  replacement. The running process was not terminated; restart to use this build.
- Sibling server `de4f3d21aecaa2190564c329608c02a9decd8010` exported for layout,
  not built or run. Development refresh only; no tag, GitHub Release or PyPI publish.

## Historical: Lite native baseline restoration — all products (2026-10-18)

All eight product artifacts were rebuilt from committed client source
`2fc9021f48ab343a8e1c46893eca711d43ab8643` using `git archive` exports.
This supersedes all older artifact provenance and pending-replacement notes below.

- Isolated m106 directory: `/tmp/cooloo-lite-release.gbPiU3/client`.
  Apple clang 21.0.0 and MinGW GCC 16.2.0; vendored SDL3/Lua; macOS target 11.0.
- Commands: `make release-macos release-windows`; exit code 0.
  Native renderer/font userdata, dirty-region cache, event bridge/IME and fatal
  recovery changes are included in the GUI and standalone text products.
- Client input archive SHA-256:
  `27914b3b224cc4efbb4d703ccd7d35e66d84a5c9e14b4bbdcad7c6e91fc65640`.
  Sibling server export: `de4f3d21aecaa2190564c329608c02a9decd8010`;
  not built, run or used by this artifact refresh.
- All eight remote, staging and installed-file SHA-256 values matched; see the
  current artifact table below. Both macOS headless files are byte-identical to
  their prior versions; they were rebuilt and installed nonetheless.
- Static inspection only: Mach-O arm64 / PE32+ x86_64, expected GUI/console
  subsystems, macOS system libraries and Windows system DLL imports only.
- **No tests or application execution performed, at explicit user request.**
  Earlier source-validation results do not constitute acceptance of these newly
  built artifacts. Real IME/candidates, drag/drop, cross-window key release,
  multi-display DPI, clipboard and visual acceptance remain outstanding.
- Development refresh only: no new tag, GitHub Release or Python publication.

## Historical: Windows text editor caret alignment fix (2026-10-18)

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

## Historical pending note: Windows text editor Lite event bridge + IME fix

The pending/replacement status in this historical note is superseded by the
installed caret-fix artifact above.

The new Windows text artifact is validated and staged, **not installed here yet**.
Replacement was blocked by a running local editor holding the existing exe open.
Save and close it before replacement. All eight release binaries currently retain
previous provenance; shared-source fixes do not update those binaries.
The intended replacement is only `cooloo-text-windows-x86_64.exe`.

- Source: `3e7a07961c758face3e0975eb9e06789b7925972` **plus uncommitted working-tree
  changes**. This is not a clean-commit build or a tagged release.
- Build input archive (client + sibling server sources, excluding release files)
  SHA-256: `f794848d18cbea4aeff82f2995ec003d9e19cc4edf4e4dc9eaa29f2b14621868`.
  Release documentation was updated after building; code inputs were compared
  against the archive before attempting replacement.
- Isolated m106 build: `/tmp/cooloo-event-fix-13L1ON/client`, Apple clang 21.0.0
  and MinGW GCC 16.2.0. macOS text/full GUI and Windows text/test harness built.
- Staged Windows text (`temp/event-artifacts/cooloo-text.exe` in planner):
  **4,167,201 bytes**, SHA-256
  `29191b8147a777b7bb606ebdd14fb8c4e99abdbda37a802186330b2f1d099f47`.
  PE32+ x86_64, GUI subsystem, system DLL imports only. Transfer hashes verified.
- Input now ports Lite's C `system.poll_event` to SDL3, removing the GUI event
  array, modifier snapshots and facade event filtering. Key press/release,
  mouse, resize/expose and focus handling follow Lite. IME is a separate
  Lite XL-derived increment; see [event contract](../docs/EVENTS.md).
- Passed **macOS and native Windows SDL dummy event-bridge regression**:
  SDL_PushEvent → production C poll → Lua core/keymap/DocView, four split
  shortcuts then plain/Shift click, releases/AltGr, drag release, IME ordering,
  UTF-8 composition, commit/undo, cancellation and event-driven redraw.
- Passed macOS `tests/editor_integration.py` (normal + safe),
  `make test-workbench-macos` (including runtime and isolated loopback provider
  integration), and local headless/workbench/provider tests. Integration server
  source: `de4f3d21aecaa2190564c329608c02a9decd8010`; no production service used.
- **Windows editor application integration did not pass**: the temporary
  PowerShell fixture/argument wrapper failed startup assertions and timed out.
  Further Windows GUI/dummy application attempts were stopped at user request.
  Two residual isolated test editor processes were stopped; none remained.
  This does not invalidate the independently passed Windows event-bridge test.
- **Not verified on either desktop:** real IME preedit/candidates, Alt-Tab,
  activation click-through, outside-window capture, OS drops or clipboard.
  SDL dummy is not desktop acceptance. Preedit uses plain text on the affected
  line, clips at the pane edge and does not collapse multi-line selection layout.
- No commit, push, tag, GitHub Release or Python publication performed.

## Previous: Windows text editor Lite-baseline update (2026-10-17)

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
  [extension/trust guide](../docs/EDITOR.md). `--safe-mode` skips external
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
| cooloo-darwin-arm64 | 2827080 | 59eb85349b4b87a70ef275d8869cf235dec0fe819280cd91b508032572d3bc16 |
| cooloo-windows-x86_64.exe | 4401747 | 3f90764aa16b814e0ff57f63c82f666528a986dfef93999623d2ba411bc56e6d |
| cooloo-text-darwin-arm64 | 2650056 | ddfe93aadf4102b0f12c3797db66905922d0ddf58251c8c23a7eb4aac2aa1351 |
| cooloo-text-windows-x86_64.exe | 4222131 | 0067db5f3a75b3b6f33d7d7d133dd71351a390e37d3f0285963a1ef7b6581f9d |
| cooloo-workbench-darwin-arm64 | 298784 | d7e5ae2a99febbf4e6f5152c3e86cdfe076e480ae0e948628d2d9fc299bdc9c3 |
| cooloo-workbench-windows-x86_64.exe | 645198 | d45e0de2ce1dc74e9f10aa58ce3836ef1a8c312b2b21b28f2c8e65f2a7fae8f7 |
| cooloo-cli-darwin-arm64 | 161592 | 3d516b005635da5d54d7a2c921f01cec4411081f2e8cf41c3160e0660f359bc8 |
| cooloo-cli-windows-x86_64.exe | 603010 | ce51f081e29f7c3c80239e13303f281279c19093387cf6f9f0828dfa41b3954f |

SHA-256 values were computed on m106 and rechecked after retrieval to local
staging and installation. The latest Windows text refresh also verified the m101
execution copy; other artifacts retain their earlier validation scope.

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
