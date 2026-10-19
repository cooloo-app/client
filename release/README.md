# cooloo client 0.3.0 artifacts

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
| `cooloo-darwin-arm64` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 2877656 |
| `cooloo-windows-x86_64.exe` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 5125480 |
| `cooloo-text-darwin-arm64` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 2651128 |
| `cooloo-text-windows-x86_64.exe` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 4827231 |
| `cooloo-workbench-darwin-arm64` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 298784 |
| `cooloo-workbench-windows-x86_64.exe` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 647246 |
| `cooloo-cli-darwin-arm64` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 161672 |
| `cooloo-cli-windows-x86_64.exe` | `2a2713ec1682addc202e00d1c3b96a2be51c38ee` | 2026-10-19 | 604821 |

All artifacts use the same source revision.

SHA-256 values and toolchain details are in `manifest.json`; `SHA256SUMS`
is derived from it. This development refresh does not create a tag,
GitHub Release or Python publication.

## Verification

- `cooloo-darwin-arm64`, `cooloo-text-darwin-arm64`, `cooloo-text-windows-x86_64.exe`, `cooloo-workbench-darwin-arm64`, `cooloo-workbench-windows-x86_64.exe`, `cooloo-cli-darwin-arm64`, `cooloo-cli-windows-x86_64.exe`: Isolated make test, headless workbench and provider tests passed; architecture, subsystem and system dependencies checked; macOS GUI, SDL dummy and Windows runtime/desktop tests not run by m106 build.

- `cooloo-windows-x86_64.exe`: Isolated make test, headless workbench and provider tests passed; architecture, subsystem and system dependencies checked; macOS GUI, SDL dummy and Windows runtime/desktop tests not run by m106 build. Additionally, Windows local startup and window/icon/console probes passed; visual UX acceptance pending.

Validate with `python3 tools/release_manifest.py`.
