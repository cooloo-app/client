# cooloo client v0.2.4 — Shanghai official endpoint

GUI+CLI single binaries, Protocol 2; server v0.2.2 unchanged.
Source commit: `953f38f892a5ae1ff56f3ead51eaaba2ea92fd42`.
Integration server: `de4f3d21aecaa2190564c329608c02a9decd8010`.
Built 2026-10-16 in isolated `/tmp/cooloo-shanghai-v024` on m106.
The artifact commit contains these outputs; it is not their build input.

| File | Target | Bytes | SHA256 |
|---|---|---:|---|
| cooloo-darwin-arm64 | macOS arm64, deployment target 11.0 | 2589896 | 656f55bcaa8a5760468b8397e8628b5b04176a70e0487699f167f13ecfcd8e9e |
| cooloo-windows-x86_64.exe | Windows x86_64 GUI subsystem | 4162521 | c45904326045ee5fff57dac5261759970406ddfa59f866a7ab175c80179e83d4 |

Git LFS tracked; unsigned/not notarized. Windows cross-built with mingw-w64,
only system DLL imports. macOS deployment target is 11.0, not runtime-verified on 11.

## Changes

- Default endpoint is Shanghai `123.206.215.121:4222`.
- Persisted old official `43.133.202.144:4222` config resolves to Shanghai without
  rewriting configuration, identity or cache. Explicit environment/SDK host overrides
  and custom endpoints are preserved.
- Reuse an old official pin only when it exactly equals the verified unchanged
  server fingerprint. Explicit new-endpoint pins always take precedence; fresh
  installations still require trust. No new blanket TOFU or pin reset.
- Includes post-v0.2.3 bare-help / explicit `--gui` startup behavior.

## Validation

- Linux client tests: configuration relocation/pin/override/no-mutation regressions,
  startup, protocol integration, Lua GUI state and cache all passed.
- macOS isolated server/client suites passed; actual GUI-linked binary separately
  passed protocol integration; GUI first-frame probe 49 ms.
- Windows m101 startup/redirection/errors/keygen, bare help and explicit/debug GUI
  first-frame probes passed (1 ms). PE32+ x64 GUI subsystem verified.
- Windows desktop window/icon/console probe reported `GUI window missing` in SSH
  session: not a passing desktop acceptance test. Full manual desktop GUI, oldest
  supported OS/Python and full compatibility matrix remain unverified.
- SDK wheel packaging, installed-wheel checks and publication are tracked separately
  in python-sdk release notes. Tests use isolated servers, not production mutations.

Rebuild: `make release-macos; make test; make release-windows`, with sibling server.
