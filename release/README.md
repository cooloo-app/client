# cooloo client release artifacts

This directory contains development binaries for client version `0.3.0`.
The current artifact facts are maintained in
[`manifest.json`](manifest.json), which is the machine-readable source of truth
for filenames, hashes, source commits, and verification scope.

The full Windows `cooloo-windows-x86_64.exe` was refreshed on 2026-10-19
from base commit `e8a027eb43e405dc36c7ee58a72c567fe742275a` plus uncommitted
Workbench Lua changes; it is not a clean-commit build. Its size is 4,484,777
bytes and SHA-256 is
`006fa790d193c678b82d8d7f5a9497cd934b4112a0e93ff5b4be3818f7f0bf3b`.
The isolated m106 MinGW build and static PE/DLL checks passed. GUI, SDL dummy,
and Windows runtime tests were not run; human desktop acceptance is pending.
Other products and macOS artifacts were not refreshed.

Products:

- `cooloo`: full communication CLI and GUI workbench (`cooloo --gui`).
- `cooloo-text`: standalone general-purpose text editor.
- `cooloo-workbench`: headless message projection/validation and Lua runner.
- `cooloo-cli`: headless communication CLI without SDL/editor modules.

All macOS artifacts target arm64 and all Windows artifacts target x86_64.
Files are Git LFS tracked, unsigned, and not notarized. The obsolete editor
artifact is not included.

These are development artifacts, not a tagged GitHub Release or a Python
publication. Build and acceptance details belong in the release process and
Git history; update `manifest.json` when the artifact set changes. Validate the
set with `python3 tools/release_manifest.py`; render GitHub Release Markdown
with `python3 tools/release_manifest.py --release-notes`.
