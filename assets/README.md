# Client icons

Transparent orange geometric C for cooloo and T for cooloo-text (`#D9622B`).
The C matches the website's geometry without its cream background; the T uses
matching height and stroke width. No external fonts, image libraries or runtime assets.

Generate from any directory:

```sh
python3 tools/generate_icon.py
```

Outputs:
- `assets/cooloo.png`: 256px RGBA preview (transparent background)
- `assets/cooloo.ico`: 16/24/32/48/64/128/256px Windows resource
- `build/generated/embedded_icon.h`: 64px RGBA for SDL window/title-bar/taskbar icon
- `assets/cooloo-text.png`: 256px transparent T preview
- `assets/cooloo-text.ico`: matching multi-size Windows resource for cooloo-text
- `build/generated/embedded_text_icon.h`: 64px T RGBA, selected by `COOLOO_EDITOR_ONLY`

Use `--mark C` or `--mark T` to regenerate only one product's assets.

ICO images below 256px use alpha-aware DIB with AND mask; 256px uses PNG.
Windows executables embed their respective ICO via `assets/apps/cooloo/windows.rc`
and `assets/apps/editor/windows.rc` with windres. SDL selects the same product's
icon at runtime so the running window/taskbar icon matches the executable.
