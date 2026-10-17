#!/usr/bin/env python3
"""Explicit product bundles: text, gui, or headless workbench CLI."""
import pathlib
import sys
from embed import c_escape_string

root = pathlib.Path(__file__).resolve().parent.parent
out = pathlib.Path(sys.argv[1])
profile = 'text' if '--offline' in sys.argv else 'gui'
if '--profile' in sys.argv:
    profile = sys.argv[sys.argv.index('--profile') + 1]
if profile not in ('text', 'gui', 'cli'):
    raise SystemExit('invalid bundle profile')
modules = {}
bases = []
if profile != 'cli':
    bases += [('modules/editor', ''), ('modules/platform', 'platform')]
if profile != 'text':
    bases += [('modules/workbench', 'workbench')]
if profile == 'gui':
    bases += [('modules/plugins', 'plugins'), ('adapters/local', 'adapters.local')]
for base, prefix in bases:
    for path in (root / base).rglob('*.lua'):
        name = '.'.join(path.relative_to(root / base).with_suffix('').parts)
        if name == 'init':
            name = ''
        elif name.endswith('.init'):
            name = name[:-5]
        modules['.'.join(filter(None, [prefix, name]))] = path.read_text()
if profile == 'gui':
    modules['adapters.cooloo'] = (root / 'adapters/cooloo/init.lua').read_text()
    modules['client.chat'] = (root / 'lua/chat.lua').read_text() + '\nreturn chat\n'
loader = []
for name, source in sorted(modules.items()):
    loader.append('package.preload[%r] = function(...)\n%s\nend\n' % (name, source))
entry = {'text': 'apps/editor/main.lua', 'gui': 'apps/workbench/gui.lua',
         'cli': 'apps/workbench/cli.lua'}[profile]
loader.append((root / entry).read_text())
source = '\n'.join(loader).encode()
out.parent.mkdir(parents=True, exist_ok=True)
if '--lua' in sys.argv:
    out.write_bytes(source)
else:
    out.write_text('/* generated: explicit product bundle */\n'
                   'struct embedded_lua { const char *name; const char *src; };\n'
                   'const struct embedded_lua cooloo_embedded_lua[] = {{"workbench.lua",\n'
                   + c_escape_string(source + b'\n') + '}};\n'
                   'const int cooloo_embedded_lua_count = 1;\n')
