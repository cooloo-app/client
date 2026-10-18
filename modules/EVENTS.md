# Lite event bridge (SDL3 port)

Baseline: rxi/lite `38bd9b3326c02e43f244623f97a622b11f074415`,
`src/api/system.c` (`f_poll_event`, `key_name`, `button_name`) and
`src/main.c` (focus click-through). License: [Lite](../vendor/lite/LICENSE).

```
SDL_PollEvent -> gui_poll_event (C) -> system.poll_event
             -> Lite core.step -> core.on_event -> keymap / rootview / plugins
```

`platform/lite.lua` binds the C poll function directly. There is no GUI event
array, modifier snapshot, facade filtering, or pre-scan of composition events.
The existing `cooloo.frame(events, dt)` array carries **network notifications
only**; workbench providers keep their existing contract. Fixed-frame scheduling,
Lite's mouse-motion coalescing and split/selection algorithms are unchanged.

## Contract and intentional differences

| Source | Lite event / behavior | SDL3 / host adaptation |
|---|---|---|
| Key down/up | `keypressed/keyreleased(name)` | SDL key names lowercased, including keypad names; no modifier bitmask |
| Modifiers | Lite keymap owns paired press/release state and AltGr workaround | macOS GUI keys alias Ctrl in keymap; other platforms keep Lite behavior |
| Text input | `textinput(text)` | SDL3-owned strings copied by Lua |
| Mouse buttons | `mousepressed(button,x,y,clicks)`, `mousereleased(button,x,y)` | `left/middle/right/?`; explicit left-button capture like Lite |
| Motion | `mousemoved(x,y,dx,dy)` | Keep SDL3 floating-point coordinates |
| Wheel | `mousewheel(y)` | SDL3 `integer_y`; raw sign matches Lite, no extra direction inversion |
| Resize | `resized(w,h)` | Rebuild software canvas, event triggers core redraw |
| Expose | `exposed` | Invalidates the native rencache and requests redraw |
| Focus gain | Flush queued keydowns (Lite Alt-Tab workaround) | Keyups are never flushed; SDL3 emits releases when keyboard focus is lost |
| First activation click | Click-through enabled | Same SDL hint as Lite |
| File drop | `filedropped(path,x,y)` | SDL3 supplies window-local coordinates and owns drop memory |
| Quit | `quit` | Existing core quit/dirty-document confirmation |
| Composition | `textediting(text,start,length)` | [Lite XL increment](../vendor/lite-xl/README.md); all parameters, in poll order |
| Focus loss | `focuslost` | Stops IME and clears physical modifier state; SDL may not deliver matching key-up events after focus loss |

IME is display-only. Final commit follows normal Doc text input and undo.
The active editable view draws composition text, underline, segment and caret;
candidate location uses UTF-8 byte offsets and is cached as in Lite XL. Command
and search inputs inherit the same DocView behavior. Composition rendering uses
plain text for the affected line, clips at the pane edge, and does not reflow
long preedit text or collapse the layout of a multi-line selection. Read-only
message views do not start composition. Native candidate windows stay with the OS.

## Automated validation

```
make test-event-bridge          # Linux development host
make test-event-bridge-macos    # macOS
make build/event-bridge-test.exe
# Windows, from client source root with SDL_VIDEODRIVER=dummy:
build/event-bridge-test.exe tests/event_bridge.lua
python3 tests/editor_integration.py ./cooloo-text
SDL_VIDEODRIVER=dummy build/renderer-test tests/workbench.lua
python3 tests/round2_test.py ./cooloo-text-linux
```

The test executable alone exposes `SDL_PushEvent`. It links production `gui.c`
and runs the real Lua facade/core/keymap/DocView and native renderer. Tests cover tuple arity/values, all four split shortcuts followed by
plain/Shift click, modifier releases/AltGr, drag release, focus-gain keydown flush,
IME-only redraw/clear, UTF-8 selection offsets, event order, commit/undo,
command-box/view/focus/mouse cancellation, resize and exposure. Existing text
integration exercises the actual bundled app/canvas and plugin stack; workbench
integration separately exercises network event delivery. Round-2 regression
also checks macro replay with held modifiers, exception cleanup, and IME-consumed
keys in document and command views; replay never drives real OS composition.

SDL dummy is **not** desktop acceptance: real IME composition/candidate placement,
Alt-Tab delivery, activation click-through, outside-window capture and OS drag
and drop still require Windows/macOS interactive verification. Synthetic focus
loss does not prove the OS generated its expected keyups.
