# cooloo client release artifacts

This directory contains development binaries for client version `0.3.0`.
The current artifact facts are maintained in
[`manifest.json`](manifest.json), which is the machine-readable source of truth
for filenames, hashes, source commits, and verification scope.

The full Windows `cooloo-windows-x86_64.exe` was refreshed on 2026-10-19
from base commit `4cfdd17018a823837b169737254e2db075e69a49` plus uncommitted
unified resource navigation, per-pane Chat views, browser/focus separation,
view-count lifecycle, and durable draft changes; it is not a clean-commit build.
Its size is 4,505,257 bytes and SHA-256 is
`aba78d9f46c5abf0b898260f03bf54b12caf816df7680ec1559adbd420da23a3`.
Lua syntax compilation, the isolated m106 MinGW build and static PE/DLL checks
passed. All automated tests, GUI, SDL dummy and runtime smoke tests were skipped
at the user's request; human desktop acceptance is pending. The standalone text
bundle is byte-identical to the source baseline. Other products and macOS
artifacts were not refreshed.

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
