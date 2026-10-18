# Lite XL IME reference

Source: https://github.com/lite-xl/lite-xl
Commit: `234fa0998016f3da9eb9ceaf3c4bc79b93462276`
License: MIT, retained in [LICENSE](LICENSE).

`lua/editor/core/ime.lua` is adapted from `data/core/ime.lua`: UTF-8
character-to-byte conversion, composition reset/stop and input-area caching.
The underline, selected-segment and caret drawing in `core/docview.lua` follows
Lite XL's `DocView:draw_ime_decoration`; the event dispatch and active-view
cancellation follow its `core/init.lua`.

Explicit adaptations to the Lite baseline:

- No Lite XL core, scheduler, document undo or multi-selection implementation is
  imported. Composition stays in IME display state until ordinary `textinput`.
- One window, so `clear_ime` and `set_text_input_rect` have no window argument.
- IME owns the active editable DocView (including CommandView), not a global
  facade string. Mouse press, view changes, quit and focus loss cancel it.
- Modifier presses/releases still reach Lite's state machine during composition;
  only non-modifier commands are suppressed.
- A `textediting` boundary clears Lite's per-frame shortcut/text suppression so
  an earlier shortcut cannot swallow a later IME commit in the same frame.
- SDL3 uses `SDL_HINT_IME_IMPLEMENTED_UI="composition"`; native candidates remain
  OS-managed. Intermediate text never changes dirty state, search or undo.

See [event contract](../../docs/EVENTS.md) for tests and desktop limitations.
