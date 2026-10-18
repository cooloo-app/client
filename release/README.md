# cooloo client release artifacts

Development artifacts, refreshed 2026-10-18. The client version remains `0.3.0`.
This directory is not a tagged release: no tag, GitHub Release, or Python
publication is implied by these files.

## Products

- `cooloo`: full communication CLI and GUI workbench. Use `cooloo --gui` to
  launch the GUI; `--debug` enables console logs.
- `cooloo-text`: standalone general-purpose text editor, `cooloo-text [FILE ...]`.
  It has no message workspace, network/identity/cache core, runtime, or
  `~/.cooloo` access.
- `cooloo-workbench`: headless message projection/validation and Lua runner.
- `cooloo-cli`: headless communication CLI without SDL/editor modules.

The obsolete `editor-windows-x86_64.exe` artifact is removed. Use
`cooloo-text-windows-x86_64.exe` for text editing,
`cooloo-workbench-windows-x86_64.exe` for headless projection/runner commands,
and `cooloo-windows-x86_64.exe --gui` for the full workbench.

## Current artifact set

All macOS files are Mach-O arm64 with deployment target 11.0. Windows files are
PE32+ x86_64; `cooloo` and `cooloo-text` use the GUI subsystem, while
workbench/CLI use the console subsystem. Windows imports are system DLLs only;
no separate SDL/Lua DLL is required. Files are Git LFS tracked, unsigned, and
not notarized. These checks do not prove compatibility with every older OS.

| File | Bytes | SHA-256 |
|---|---:|---|
| `cooloo-darwin-arm64` | 2827080 | `59eb85349b4b87a70ef275d8869cf235dec0fe819280cd91b508032572d3bc16` |
| `cooloo-windows-x86_64.exe` | 4401747 | `3f90764aa16b814e0ff57f63c82f666528a986dfef93999623d2ba411bc56e6d` |
| `cooloo-text-darwin-arm64` | 2650056 | `ddfe93aadf4102b0f12c3797db66905922d0ddf58251c8c23a7eb4aac2aa1351` |
| `cooloo-text-windows-x86_64.exe` | 4221107 | `8f02183f97a8d0670c7f65a1f2877246880ec4fe45c83f71c84aabc3fd5cfb5d` |
| `cooloo-workbench-darwin-arm64` | 298784 | `d7e5ae2a99febbf4e6f5152c3e86cdfe076e480ae0e948628d2d9fc299bdc9c3` |
| `cooloo-workbench-windows-x86_64.exe` | 645198 | `d45e0de2ce1dc74e9f10aa58ce3836ef1a8c312b2b21b28f2c8e65f2a7fae8f7` |
| `cooloo-cli-darwin-arm64` | 161592 | `3d516b005635da5d54d7a2c921f01cec4411081f2e8cf41c3160e0660f359bc8` |
| `cooloo-cli-windows-x86_64.exe` | 603010 | `ce51f081e29f7c3c80239e13303f281279c19093387cf6f9f0828dfa41b3954f` |

## Latest refresh: Windows text editor

Only `cooloo-text-windows-x86_64.exe` was refreshed in the latest update. It
was built from committed client source `6a7f8dbc7499953e4afd847c523c04da656704ab`.
The input git archive SHA-256 is
`7932b888d54867e7bc47b53d0ea520690cf73c1f37370b8783a37d0db671ec05`.

- Isolated m106 build with Apple clang, MinGW GCC 16.2.0, and vendored SDL3/Lua;
  `make -j4 cooloo-text.exe` passed.
- PE32+ x86_64 GUI inspection passed. The artifact is 4,221,107 bytes with
  SHA-256 `8f02183f97a8d0670c7f65a1f2877246880ec4fe45c83f71c84aabc3fd5cfb5d`.
- The dedicated orange T icon is embedded for the text product; the full
  product's C icon and artifact were unchanged.
- A desktop icon probe on m101 could not create a GUI window in the available
  session. Windows desktop/taskbar visual acceptance remains unverified.

The other seven artifacts retain the all-product baseline provenance:
client source `2fc9021f48ab343a8e1c46893eca711d43ab8643`, input archive
`27914b3b224cc4efbb4d703ccd7d35e66d84a5c9e14b4bbdcad7c6e91fc65640`, and
sibling server export `de4f3d21aecaa2190564c329608c02a9decd8010` (not built or
run for that refresh). All remote, transfer, and installed hashes matched.

## Verification scope

The baseline refresh ran `make release-macos release-windows` in an isolated
m106 tree. Static format, subsystem, library, and import checks passed. The
latest Windows text build also passed the dedicated text/editor regression
coverage on Linux/macOS and native Windows m101, including renderer/event
bridge, normal/safe editor integration, lifecycle, file failure injection, and
workbench local smoke tests. Tests used isolated configuration and loopback
services; no production service or messages were used.

Not established by this artifact set: real desktop IME/candidates, clipboard or
drop delivery, multi-display DPI and visual acceptance, exhaustive ACL/UNC/
reparse/network-filesystem behavior, power-loss durability, malformed-font
safety, and full workbench network integration. SDL dummy tests are not desktop
acceptance. Historical test results do not automatically apply to a newly
rebuilt artifact.

To rebuild the standard set (a sibling server checkout is normally required):

```sh
make -C ../server all
make release-macos
make test
make test-workbench-headless
build/lua-runner --lua-run tests/provider.lua
make release-windows
```

These targets build artifacts only; they do not publish, tag, or upload them.

## Upstream comparison archives

The following archives are retained for editor comparison only, not as cooloo
build inputs:

- Lite v1.11: `lite-v1.11-windows.zip`, 1,072,498 bytes,
  SHA-256 `da3701cf6985bc493cb11b37556325551c7ce8606f5502ff3f15199039835eef`.
  [Release](https://github.com/rxi/lite/releases/tag/v1.11)
- Lite XL v2.1.8: `lite-xl-v2.1.8-windows-x86_64.zip`, 2,303,776 bytes,
  SHA-256 `de4983f8f537e3876d0c326423537914b576b6970e35b9c9cc62eafe72719ec2`.
  [Release](https://github.com/lite-xl/lite-xl/releases/tag/v2.1.8)

Extract each complete archive beside its data files. Neither archive was
changed here; Windows execution/manual comparison was not tested.
