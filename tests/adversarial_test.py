"""Regression assertions for R01/R02/R04/R05/R06; no malformed-font execution.
Usage: python3 tests/adversarial_test.py ./cooloo-text-linux ./build/renderer-test
POSIX host tests (Linux/macOS); fixtures and child launches are isolated.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary, renderer = (Path(arg).resolve() for arg in sys.argv[1:3])

def wait_file(path, process):
    deadline = time.monotonic() + 10
    while not path.exists():
        assert process.poll() is None, process.communicate()
        assert time.monotonic() < deadline, str(path)
        time.sleep(.02)

with tempfile.TemporaryDirectory(prefix='cooloo-adversarial-') as tmp:
    base = Path(tmp)
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', COOLOO_TEXT_USERDIR=str(base/'user'), BOUNDARY_DIR=str(base))
    env.pop('COOLOO_PROBE_STARTUP', None)
    themes = base/'data/user/colors'
    themes.mkdir(parents=True)
    user = base/'user/colors'
    user.mkdir(parents=True)
    for package in (False, True):
        portable = themes/('summer/init.lua' if package else 'summer.lua')
        personal = user/('summer/init.lua' if package else 'summer.lua')
        portable.parent.mkdir(exist_ok=True)
        personal.parent.mkdir(exist_ok=True)
        portable.write_text("return 'PORTABLE'")
        personal.write_text("return 'USER'")
        for expected, safe in [('USER', False), ('EMBEDDED', True), ('PORTABLE', False), ('EMBEDDED', False)]:
            if expected == 'PORTABLE': personal.unlink()
            if expected == 'EMBEDDED' and not safe: portable.unlink()
            p = subprocess.run([str(renderer), 'tests/adversarial.lua'], cwd=root,
                               env=dict(env, BOUNDARY_THEME=expected, BOUNDARY_SAFE=str(int(safe))),
                               capture_output=True, text=True, timeout=15)
            assert p.returncode == 0, p.stdout+p.stderr
    print('R05/R06: file/package themes and physical modifier matrix OK')
    bundle = base/'base.lua'
    subprocess.run([sys.executable, str(root/'tools/embed_workbench.py'), str(bundle), '--profile', 'text', '--lua'], check=True)
    source = bundle.read_text()
    def run(code, executable=binary, extra_env=None):
        dev = base/'dev'
        dev.mkdir(exist_ok=True)
        (dev/'workbench.lua').write_text(source+code)
        p = subprocess.run([str(executable), '--safe-mode', '--lua-dev', str(dev), str(base)],
                           cwd=base, env=dict(env, **(extra_env or {})), capture_output=True, text=True, timeout=15)
        assert p.returncode == 0, p.stdout+p.stderr
        return p

    (base/'existing.txt').write_text('original')
    (base/'alias.txt').symlink_to(base/'existing.txt')
    (base/'dangling').symlink_to(base/'absent')
    locked = base/'locked'
    locked.mkdir()
    (locked/'a').write_text('a')
    (locked/'b').write_text('b')
    locked.chmod(0)
    try:
        run(r'''
local core=require 'core'
local d=core.open_doc('existing.txt')
assert(core.open_doc('alias.txt')==d)
local new=core.open_doc('new.txt');assert(new.filename=='new.txt')
assert(core.open_doc('missing-parent/child').filename=='missing-parent/child')
local before=#core.docs
for _,path in ipairs{'dangling','existing.txt/child','locked/a','locked/b'} do
  assert(not pcall(core.open_doc,path), 'must reject '..path)
  assert(#core.docs==before, 'failed open must not add a document')
end
assert(not system.get_file_info('new.txt'))
core.quit(true)
''')
    finally:
        locked.chmod(0o700)
    print('R02: missing leaf, aliases, permissions, dangling link and parent failures OK')

    # Start from each supported invocation form and actually launch a directory child.
    alias = base/'editor-alias'
    alias.symlink_to(binary)
    child = base/'child project'
    child.mkdir()
    marker = child/'started'
    (child/'.lite_project.lua').write_text("local f=assert(io.open('started','w'));f:write('child');f:close();require('core').quit(true)")
    for executable in (binary, alias, './editor-alias', 'editor-alias'):
        marker.unlink(missing_ok=True)
        run(r'''
local core=require 'core'
assert(system.get_file_info(EXEFILE).type=='file')
system.open_project('child project',false)
core.quit(true)
''', executable, {'PATH':str(base)+os.pathsep+env['PATH']})
        deadline = time.monotonic()+10
        while not marker.exists() and time.monotonic()<deadline: time.sleep(.02)
        assert marker.read_text() == 'child'
    print('R04: absolute, relative, PATH and renamed symlink launches plus real children OK')

    # Two live hosts share EXEDIR; quitting/failing either cannot remove the other's file.
    for fatal in (False, True):
        processes=[]
        try:
            for name in ('a', 'b'):
                dev=base/('dev-'+name)
                dev.mkdir(exist_ok=True)
                ready=base/(name+'.ready'); ready.unlink(missing_ok=True)
                stop=base/(name+'.stop'); stop.unlink(missing_ok=True)
                (dev/'workbench.lua').write_text(source+r'''
local core=require 'core'
EXEDIR=assert(os.getenv('BOUNDARY_DIR'))
local name=assert(os.getenv('BOUNDARY_NAME'))
local path=core.temp_filename('.txt')
local f=assert(io.open(path,'w'));f:write(name);f:close()
f=assert(io.open(name..'.ready','w'));f:write(path);f:close()
cooloo.frame=function()
 if system.get_file_info(name..'.stop') then
   if os.getenv('BOUNDARY_FATAL')=='1' then error('intentional concurrent failure') end
   core.quit(true)
 end
end
''')
                p=subprocess.Popen([str(binary),'--safe-mode','--lua-dev',str(dev),str(base)], cwd=base,
                                   env=dict(env, BOUNDARY_NAME=name, BOUNDARY_FATAL=str(int(fatal and name=='a'))),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                processes.append(p)
                wait_file(ready,p)
            paths=[Path((base/(name+'.ready')).read_text()) for name in ('a','b')]
            assert paths[0]!=paths[1]
            assert [p.read_text() for p in paths]==['a','b']
            (base/'a.stop').touch()
            out=processes[0].communicate(timeout=10)
            assert processes[0].returncode==int(fatal),out
            assert not paths[0].exists() and paths[1].read_text()=='b'
            (base/'b.stop').touch()
            out=processes[1].communicate(timeout=10)
            assert processes[1].returncode==0,out
            assert not paths[1].exists()
        finally:
            for p in processes:
                if p.poll() is None: p.kill();p.communicate()
    print('R01: concurrent reservation and normal/fatal ownership cleanup OK')
print('adversarial regressions: PASS (R03 explicitly deferred)')
