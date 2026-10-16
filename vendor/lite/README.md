# Lite provenance

Source: https://github.com/rxi/lite
Commit: `38bd9b3326c02e43f244623f97a622b11f074415`
License: MIT, retained in LICENSE.

Vendored Lua core lives in `modules/editor/core`; only `language_lua` is bundled
from plugins. No upstream C runtime, SDL2, Lua 5.2 or fonts are imported.
Local changes: host-driven initialization/tick, no automatic project/user code
execution, virtual/read-only documents, platform bridge and wrapped views.
Third-party plugin compatibility is not a supported contract.
