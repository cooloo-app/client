# cooloo client release artifacts

This directory contains development binaries for client version `0.3.0`.
The current artifact facts are maintained in
[`manifest.json`](manifest.json), which is the machine-readable source of truth
for filenames, hashes, source commits, and verification scope.

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
