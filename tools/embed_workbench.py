#!/usr/bin/env python3
"""Embed require modules; offline image excludes the cooloo provider/chat model."""
import pathlib
import sys
from embed import c_escape_string

root = pathlib.Path(__file__).resolve().parent.parent
out = pathlib.Path(sys.argv[1])
offline = '--offline' in sys.argv[2:]
modules = {}
for base, prefix in [('modules/editor', ''), ('modules/platform', 'platform'),
                     ('modules/workspace', 'workspace'), ('modules/console', 'console'),
                     ('adapters/local', 'adapters.local')]:
    for path in (root / base).rglob('*.lua'):
        name = '.'.join(path.relative_to(root / base).with_suffix('').parts)
        if name == 'init':
            name = ''
        elif name.endswith('.init'):
            name = name[:-5]
        modules['.'.join(filter(None, [prefix, name]))] = path.read_text()
if not offline:
    modules['adapters.cooloo'] = (root / 'adapters/cooloo/init.lua').read_text()
    modules['client.chat'] = (root / 'lua/chat.lua').read_text() + '\nreturn chat\n'
loader = []
for name, source in sorted(modules.items()):
    loader.append('package.preload[%r] = function(...)\n%s\nend\n' % (name, source))
loader.append((root / 'apps/editor/workbench.lua').read_text())
source = '\n'.join(loader).encode()
out.parent.mkdir(parents=True, exist_ok=True)
if '--lua' in sys.argv[2:]:
    out.write_bytes(source)
    sys.exit(0)
out.write_text('/* generated: embedded workbench */\n'
               'struct embedded_lua { const char *name; const char *src; };\n'
               'const struct embedded_lua cooloo_embedded_lua[] = {{"workbench.lua",\n'
               + c_escape_string(source + b'\n') + '}};\n'
               'const int cooloo_embedded_lua_count = 1;\n')
