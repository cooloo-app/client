# cooloo client 0.3.2 artifacts

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
| `cooloo-darwin-arm64` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 2894424 |
| `cooloo-windows-x86_64.exe` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 5128633 |
| `cooloo-text-darwin-arm64` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 2667720 |
| `cooloo-text-windows-x86_64.exe` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 4830255 |
| `cooloo-workbench-darwin-arm64` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 298784 |
| `cooloo-workbench-windows-x86_64.exe` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 647246 |
| `cooloo-cli-darwin-arm64` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 161848 |
| `cooloo-cli-windows-x86_64.exe` | `0149d964c09708dfaa17cf5a2328990db3f19024` | 2026-10-20 | 606172 |

All artifacts use the same source revision.

SHA-256 values and toolchain details are in `manifest.json`; `SHA256SUMS`
is derived from it. This development refresh does not create a tag,
GitHub Release or Python publication.

## Verification

- `cooloo-darwin-arm64`, `cooloo-windows-x86_64.exe`, `cooloo-text-darwin-arm64`, `cooloo-text-windows-x86_64.exe`, `cooloo-workbench-darwin-arm64`, `cooloo-workbench-windows-x86_64.exe`, `cooloo-cli-darwin-arm64`, `cooloo-cli-windows-x86_64.exe`: Isolated make test, headless workbench and provider tests passed; architecture, subsystem and system dependencies checked; macOS GUI, SDL dummy and Windows runtime/desktop tests not run by m106 build.

Validate with `python3 tools/release_manifest.py`.
