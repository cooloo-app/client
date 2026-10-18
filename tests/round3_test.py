"""Round-3 adversarial fixes on an isolated real text host."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

CLIENT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory(prefix='cooloo-round3-') as tmp:
    base = Path(tmp)
    staged = base / BINARY.name
    shutil.copy2(BINARY, staged)
    BINARY = staged
    bundle = base / 'bundle.lua'
    subprocess.run([sys.executable, str(CLIENT/'tools/embed_workbench.py'),
                    str(bundle), '--profile', 'text', '--lua'], check=True)
    source = bundle.read_text(encoding='utf-8')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', COOLOO_TEXT_USERDIR=str(base/'user'))

    def run(name, code, setup=None, expected=0):
        case = base / name
        case.mkdir()
        if setup:
            setup(case)
        (case/'workbench.lua').write_text(
            source + '\nEXEDIR=' + json.dumps(case.as_posix()) + '\n' + code,
            encoding='utf-8')
        p = subprocess.run(
            [str(BINARY), '--safe-mode', '--lua-dev', str(case), '--', str(case)],
            cwd=case, env=env, capture_output=True, text=True, timeout=15)
        assert p.returncode == expected, (name, p.returncode, p.stdout, p.stderr)
        print(name + ': ' + p.stdout.strip(), flush=True)
        return case

    def rename_setup(case):
        (case/'file.txt').write_bytes(b'valuable')
        (case/'alias.txt').symlink_to('file.txt')

    case = run('rename-equivalent', r'''
local core=require 'core'
local command=require 'core.command'
local d=core.open_doc('file.txt')
command.perform('doc:rename')
core.command_view:set_text('./file.txt')
core.command_view:submit()
assert(not d:is_dirty())
assert(io.open('file.txt','rb'):read('*a')=='valuable')
core.quit(true)
''', rename_setup)
    assert (case/'file.txt').read_bytes() == b'valuable'

    case = run('rename-symlink', r'''
local core=require 'core'
local command=require 'core.command'
local d=core.open_doc('file.txt')
command.perform('doc:rename')
core.command_view:set_text('alias.txt')
core.command_view:submit()
assert(not d:is_dirty())
core.quit(true)
''', rename_setup)
    assert (case/'file.txt').read_bytes() == b'valuable'
    assert (case/'alias.txt').is_symlink()

    case = run('fatal-diagnostic', r'''
local core=require 'core'
core.docs={}
local d=core.open_doc('error.txt')
assert(not d:is_dirty())
error('intentional fatal')
''', lambda c: (c/'error.txt').write_bytes(b'valuable existing document'), expected=1)
    assert (case/'error.txt').read_bytes() == b'valuable existing document'
    assert (case/'error.txt~1').read_text().startswith('Error: ')

    case = run('load-failure-preserves-state', r'''
local core=require 'core'
local d=core.open_doc('file.txt')
d:text_input('UNSAVED')
local before=d:get_change_id(); local old=d.filename
assert(not pcall(d.load,d,'directory'))
assert(d.filename==old and d:is_dirty())
assert(table.concat(d.lines):find('UNSAVED',1,true))
assert(d:get_change_id()==before)
core.quit(true)
''', lambda c: ((c/'file.txt').write_bytes(b'original'), (c/'directory').mkdir()))

    run('invalid-utf8-navigation', r'''
local core=require 'core'
local d=core.open_doc('invalid.bin')
d:set_selection(1,2)
local ok=pcall(function() d:move_to(require('core.doc.translate').previous_char) end)
assert(ok)
core.quit(true)
''', lambda c: (c/'invalid.bin').write_bytes(b'\x80abc'))

    run('focus-loss-modifiers', r'''
local core=require 'core'
local keymap=require 'core.keymap'
core.on_event('keypressed','left ctrl')
assert(keymap.modkeys.ctrl)
core.on_event('focuslost')
assert(not keymap.modkeys.ctrl and not keymap.modkeys.shift and not keymap.modkeys.alt)
core.quit(true)
''')

print('round3: PASS')
