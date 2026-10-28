# cooloo client 0.3.8 artifacts

Generated from `manifest.json`; edit the build inputs/report, not this file.

Four products for macOS arm64 and Windows x86_64. Binaries are unsigned,
not notarized, and tracked by Git LFS. No Linux GUI artifact is published.

- `cooloo`: communication CLI + GUI workbench.
- `cooloo-text`: standalone text editor.
- `cooloo-cli`: headless communication CLI.
- `cooloo-workbench`: headless projection/validation and Lua runner.

## Provenance

| File | Source commit | Build date | Bytes |
|---|---|---|---|
| `cooloo-darwin-arm64` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 2944248 |
| `cooloo-windows-x86_64.exe` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 5186790 |
| `cooloo-text-darwin-arm64` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 2667864 |
| `cooloo-text-windows-x86_64.exe` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 4846385 |
| `cooloo-workbench-darwin-arm64` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 315344 |
| `cooloo-workbench-windows-x86_64.exe` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 663630 |
| `cooloo-cli-darwin-arm64` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 161944 |
| `cooloo-cli-windows-x86_64.exe` | `caf2bf03e88d64334b31d1c6adaa39c9a75c3117` | 2026-10-28 | 608286 |

All artifacts use the same source revision.

SHA-256 values and toolchain details are in `manifest.json`; `SHA256SUMS`
is derived from it. This development refresh does not create a tag,
GitHub Release or Python publication.

## Verification

- `cooloo-darwin-arm64`, `cooloo-text-darwin-arm64`, `cooloo-text-windows-x86_64.exe`, `cooloo-workbench-darwin-arm64`, `cooloo-workbench-windows-x86_64.exe`, `cooloo-cli-darwin-arm64`, `cooloo-cli-windows-x86_64.exe`: Isolated make test, headless workbench and provider tests passed; architecture, subsystem and system dependencies checked; macOS GUI, SDL dummy and Windows runtime/desktop tests not run by m106 build.

- `cooloo-windows-x86_64.exe`: Isolated make test, headless workbench and provider tests passed; architecture, subsystem and system dependencies checked; macOS GUI, SDL dummy and Windows runtime/desktop tests not run by m106 build. Additionally, Windows local startup and window/icon/console probes passed; visual UX acceptance pending.

Validate with `python3 tools/release_manifest.py`.
