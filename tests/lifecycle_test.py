"""Fatal recovery and graceful temporary-file cleanup using the real host."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cooloo-recovery-') as tmp:
    base = Path(tmp)
    bundle = base / 'base.lua'
    subprocess.run([sys.executable, str(root / 'tools/embed_workbench.py'), str(bundle), '--profile', 'text', '--lua'], check=True)
    source = bundle.read_text()
    for mode in ('init', 'frame', 'thread', 'draw', 'quit', 'cancel'):
        case = base / mode
        case.mkdir()
        (case / 'original.txt').write_bytes(b'original')
        (case / 'original.txt~').write_bytes(b'older recovery')
        setup = r'''
local core=require 'core'
EXEDIR=assert(os.getenv('RECOVERY_DIR'))
local doc=core.open_doc('original.txt');doc:text_input('edit');core.root_view:open_doc(doc)
local unnamed=core.open_doc();unnamed:text_input('unnamed');core.root_view:open_doc(unnamed)
local virtual=core.open_doc();virtual.virtual=true;virtual:set_projection('not user data')
local temporary=core.temp_filename();local f=assert(io.open(temporary,'w'));f:write('temp');f:close()
local failure=assert(os.getenv('RECOVERY_MODE'))
if failure=='init' then error('injected init failure')
elseif failure=='frame' then cooloo.frame=function() error('injected frame failure') end
elseif failure=='thread' then core.threads.failure={cr=coroutine.create(function() error('injected thread failure') end),wake=0}
elseif failure=='draw' then core.root_view.draw=function() error('injected draw failure') end
elseif failure=='quit' then core.quit(true)
elseif failure=='cancel' then
  system.show_confirm_dialog=function()return false end
  core.quit();assert(system.get_file_info(temporary),'cancel must keep temp files')
  system.show_confirm_dialog=function()return true end
  core.quit()
end
'''
        (case / 'workbench.lua').write_text(source + setup)
        env = dict(os.environ, SDL_VIDEODRIVER='dummy', COOLOO_TEXT_USERDIR=str(base / 'empty'),
                   RECOVERY_DIR=str(case), RECOVERY_MODE=mode)
        env.pop('COOLOO_PROBE_STARTUP', None)
        p = subprocess.run([str(binary), '--safe-mode', '--lua-dev', str(case), str(case)], cwd=case, env=env,
                           capture_output=True, timeout=15)
        output = p.stderr.decode(errors='replace')
        assert (case / 'original.txt').read_bytes() == b'original'
        assert (case / 'original.txt~').read_bytes() == b'older recovery'
        assert not list(case.glob('.lite_temp_*')), (mode, output)
        if mode in ('quit', 'cancel'):
            assert p.returncode == 0, output
        else:
            assert p.returncode == 1, (mode, p.returncode, output)
            assert 'injected ' + mode + ' failure' in output and 'stack traceback' in output, output
            assert (case / 'original.txt~1').exists(), (mode, output, list(case.iterdir()))
            assert (case / 'original.txt~1').read_bytes() != b'original'
            assert list(case.glob('unsaved-*~'))
            assert 'injected ' + mode + ' failure' in (case / 'error.txt').read_text()
        print('lifecycle ' + mode + ': OK')
    # An explicitly requested broken development bundle must never fall back.
    broken = base / 'broken'
    broken.mkdir()
    (broken / 'workbench.lua').write_text('this is not valid Lua !!!')
    p = subprocess.run([str(binary), '--safe-mode', '--lua-dev', str(broken)], env=env, capture_output=True, timeout=10)
    assert p.returncode == 1 and b'cooloo fatal:' in p.stderr
print('lifecycle: fatal recovery, backups, temporary cleanup, cancel/confirm and dev failure OK')
