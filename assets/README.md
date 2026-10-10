# Client icon

Transparent orange geometric C (`#D9622B`), matching the website's C geometry
without its cream background. No external fonts, image libraries or runtime assets.

Generate from any directory:

```sh
python3 tools/generate_icon.py
```

Outputs:
- `assets/cooloo.png`: 256px RGBA preview (transparent background)
- `assets/cooloo.ico`: 16/24/32/48/64/128/256px Windows resource
- `src/embedded_icon.h`: 64px RGBA for SDL window/title-bar/taskbar icon

ICO images below 256px use alpha-aware DIB with AND mask; 256px uses PNG.
The Windows executable embeds the ICO via `src/cooloo.rc` and windres.
