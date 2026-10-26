"""Actual SDL dummy process restart tests, isolated product state and files."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cooloo-ui-state-') as tmp:
    base = Path(tmp)
    user = base / 'user'
    user.mkdir()
    project = base / 'project'
    project.mkdir()
    file = project / '中文.txt'
    file.write_text('hello\n')
    dev = base / 'dev'
    dev.mkdir()
    bundle = dev / 'workbench.lua'
    subprocess.run([sys.executable, str(root / 'tools/embed_workbench.py'), str(bundle), '--profile', 'text', '--lua'], check=True)
    with bundle.open('a') as f:
        f.write('''
local core=require 'core'
local host=require 'core.host'
local layout=require 'core.session_layout'
local mode=os.getenv('STATE_MODE')
local path=assert(os.getenv('STATE_FILE'))
if mode=='write' then
  cooloo.platform.window_size(1111,777)
  local node=core.root_view:get_active_node()
  node:add_view(require('core.docview')(core.open_doc(path)))
  node:split('right')
  local right=node.b
  right:add_view(require('core.docview')(core.open_doc(path)))
  node.divider=0.63
  right:set_active_view(right.active_view)
elseif mode=='read' then
  local w,h=cooloo.platform.window_size();assert(w==1111 and h==777)
  local snap,active=layout.capture(core.root_view.root_node,layout.file)
  assert(snap.type=='split' and snap.axis=='x' and snap.ratio==0.63)
  assert(#snap.a.tabs==1 and #snap.b.tabs==1 and active[1]=='b')
elseif mode=='explicit' then
  local snap=layout.capture(core.root_view.root_node,layout.file)
  assert(snap.type=='leaf' and #snap.tabs==1)
elseif mode=='missing' then
  local snap=layout.capture(core.root_view.root_node,layout.file)
  assert(snap.type=='split' and #snap.a.tabs==0 and #snap.b.tabs==0)
end
system.request_quit()
print('UI restart '..mode..': OK')
''')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', COOLOO_TEXT_USERDIR=str(user),
               COOLOO_CONFIG=str(base / 'untouched-config'), STATE_FILE=str(file))
    env.pop('COOLOO_PROBE_STARTUP', None)
    def run(mode, extra=()):
        p = subprocess.run([str(binary), '--lua-dev', str(dev), '--safe-mode', *extra],
                           cwd=project, env=dict(env, STATE_MODE=mode), capture_output=True, timeout=15)
        assert p.returncode == 0, p.stderr.decode(errors='replace')
        assert f'UI restart {mode}: OK' in p.stdout.decode(), p.stdout
        print(p.stdout.decode().strip())
    run('write')
    state = user / 'ui-state.json'
    data = json.loads(state.read_text())
    assert data['window'] == {'width': 1111, 'height': 777}
    assert data['product'] == 'cooloo-text'
    run('read')
    saved = state.read_bytes()
    run('explicit', [str(file)])
    state.write_bytes(saved)
    file.unlink()
    run('missing')
    future = b'{"version":999,"product":"cooloo-text"}\n'
    state.write_bytes(future)
    run('noop')
    assert state.read_bytes() == future
    state.write_text('{broken')
    run('noop')
    assert json.loads(state.read_text())['version'] == 1
    assert not (base / 'untouched-config').exists()
print('UI state integration: OK')
