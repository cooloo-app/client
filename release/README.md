# cooloo client v0.3.0 artifacts

This directory contains all eight client artifacts for macOS arm64 and Windows
x86_64. Exact filenames, sizes, SHA-256 checksums and provenance are maintained
in [`manifest.json`](manifest.json); [`SHA256SUMS`](SHA256SUMS) is derived from it.

## Build provenance

All products were rebuilt on 2026-10-19 in an isolated m106 directory from
clean client source commit `017638f5e202c5035ebaf8dec4625fb71640dda8`.
Apple clang built the native macOS products; MinGW-w64 cross-compiled Windows.
The release commit contains these artifacts and metadata only; its client tag
`v0.3.0` retains the same build inputs as that source commit.
No GitHub Release or Python publication is included in this operation.

## Products

- `cooloo`: full communication CLI and GUI workbench (`cooloo --gui`).
- `cooloo-text`: standalone general-purpose text editor.
- `cooloo-workbench`: headless message projection/validation and Lua runner.
- `cooloo-cli`: headless communication CLI without SDL/editor modules; no GUI.

All eight binaries are Git LFS tracked, unsigned and not notarized. No Linux
release artifact is included.

## Verification

- `make release-macos` and `make release-windows`: passed for all four products.
- `make test`: passed config, startup, Protocol 2 loopback integration, Lua
  protocol state and cache checks. Test server source commit:
  `de4f3d21aecaa2190564c329608c02a9decd8010`.
- Static formats: Mach-O arm64 and PE32+ x86_64. Windows GUI products use the GUI
  subsystem; headless products use the console subsystem. DLL imports are
  Windows system/UCRT libraries only.
- Native `cooloo --json version` and `cooloo-cli --json version` report `0.3.0`.
- Transfers and installed artifact checksums were verified.
- Per the earlier test boundary, macOS GUI, SDL dummy and Windows runtime/desktop
  tests were not run; human desktop acceptance remains pending. Build/static
  checks are not a claim of desktop acceptance.

Validate the set with `python3 tools/release_manifest.py`; render Markdown with
`python3 tools/release_manifest.py --release-notes`.
