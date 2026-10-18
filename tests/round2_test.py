"""Round-2 acceptance, isolated real text hosts; no network or personal files.
Usage: python3 tests/round2_test.py ./cooloo-text-linux
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

CLIENT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cooloo-round2-') as tmp:
    base = Path(tmp)
    # Startup can fail before the bundle's EXEDIR override; isolate error.txt too.
    staged=base/BINARY.name
    shutil.copy2(BINARY,staged)
    BINARY=staged
    bundle = base / 'bundle.lua'
    subprocess.run([sys.executable, str(CLIENT/'tools/embed_workbench.py'), str(bundle), '--profile', 'text', '--lua'], check=True)
    source = bundle.read_text(encoding='utf-8')
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', COOLOO_TEXT_USERDIR=str(base/'user'))
    env.pop('COOLOO_PROBE_STARTUP', None)

    def prepare(name, code, setup=None):
        case=base/name;case.mkdir()
        if setup: setup(case)
        (case/'workbench.lua').write_text(source+'\nEXEDIR='+json.dumps(case.as_posix())+'\n'+code,encoding='utf-8')
        return case

    def run(name, code, setup=None, args=None, expected=0, preexec=None):
        case=prepare(name,code,setup)
        options={} if preexec is None else {'preexec_fn':preexec}
        p=subprocess.run([str(BINARY),'--safe-mode','--lua-dev',str(case),'--',*(args or [str(case)])],
                         cwd=case,env=env,capture_output=True,text=True,timeout=25,**options)
        assert p.returncode==expected,(name,p.returncode,p.stdout,p.stderr)
        print(name+': '+p.stdout.strip(),flush=True)
        return case

    run('editing', (CLIENT/'tests/round2.lua').read_text(encoding='utf-8'))
    case=run('branch-recovery',r'''
local core=require 'core'
local d=core.open_doc('file.txt');d:text_input('X');d:save();d:undo();d:text_input('Y')
assert(d:is_dirty());error('intentional branch recovery')
''',lambda c:(c/'file.txt').write_bytes(b'abc'),expected=1)
    assert (case/'file.txt').read_bytes()==b'Xabc'
    assert (case/'file.txt~').read_bytes()==b'Yabc'
    case=run('recovery-error',r'''
local core=require 'core'
core.docs={}
local a=core.open_doc('missing-parent/file.txt');a:text_input('cannot write')
local b=core.open_doc('good.txt');b:text_input('keep')
error('intentional partial recovery failure')
''',expected=1)
    assert (case/'good.txt~').read_bytes()==b'keep'

    # Original files must survive save failure, and success through a symlink
    # must keep the symlink itself. Hard links explicitly require Save As.
    case=run('save',r'''
local core=require 'core'; local d=core.open_doc('file.txt');d:text_input('new')
assert(not pcall(d.save,d,'missing-parent/file.txt'));assert(d:is_dirty())
assert(not pcall(d.save,d,'directory'));assert(d:is_dirty())
d:save();assert(not d:is_dirty())
assert(not pcall(d.save,d,'hard.txt'))
assert(d.filename=='file.txt' and not d:is_dirty())
d:save('新文件.txt');assert(not d:is_dirty());core.quit(true)
''',lambda c:((c/'file.txt').write_bytes(b'old'),(c/'directory').mkdir(),
              (c/'hard.txt').write_bytes(b'hard'),os.link(c/'hard.txt',c/'hard-alias.txt')))
    assert (case/'file.txt').read_bytes()==b'newold'
    assert (case/'hard.txt').read_bytes()==(case/'hard-alias.txt').read_bytes()==b'hard'
    assert not list(case.glob('.cooloo-save-*'))

    if os.name!='nt':
        import resource
        import signal
        def limit():
            signal.signal(signal.SIGXFSZ,signal.SIG_IGN)
            resource.setrlimit(resource.RLIMIT_FSIZE,(1024,1024))
        case=run('write-failure',r'''
local core=require 'core';local d=core.open_doc('file.txt');d:text_input(string.rep('Y',8192))
assert(not pcall(d.save,d));assert(d:is_dirty());core.quit(true)
''',lambda c:(c/'file.txt').write_bytes(b'X'*4096),preexec=limit)
        assert (case/'file.txt').read_bytes()==b'X'*4096
        assert not list(case.glob('.cooloo-save-*'))
        def paths(c):
            (c/'existing.txt').write_bytes(b'original')
            (c/'existing.txt').chmod(0o640)
            if hasattr(os,'setxattr'):
                key='com.cooloo.test' if sys.platform=='darwin' else 'user.cooloo-test'
                os.setxattr(c/'existing.txt',key,b'preserved')
            (c/'dangling').symlink_to(c/'absent')
            (c/'alias').symlink_to(c/'existing.txt')
        run('path-open',r'''
local core=require 'core'
assert(not pcall(core.open_doc,'dangling/../existing.txt'))
local d=core.open_doc('existing.txt')
assert(not pcall(core.open_doc,'dangling/../existing.txt'))
local n=#core.docs;core.on_event('filedropped','dangling/../existing.txt',10,10);assert(#core.docs==n)
assert(core.open_doc('alias')==d)
assert(core.open_doc('missing/parent/new.txt'))
assert(core.open_doc('missing/../new.txt'))
d:text_input('new');d:save('alias');core.quit(true)
''',paths)
        assert (base/'path-open'/'alias').is_symlink()
        assert (base/'path-open'/'existing.txt').read_bytes()==b'neworiginal'
        assert (base/'path-open'/'existing.txt').stat().st_mode & 0o777 == 0o640
        if hasattr(os,'listxattr'):
            key='com.cooloo.test' if sys.platform=='darwin' else 'user.cooloo-test'
            attrs=os.listxattr(base/'path-open'/'existing.txt')
            assert key in attrs and os.getxattr(base/'path-open'/'existing.txt',key)==b'preserved'
        run('path-startup',"error('must not reach bundle tail')",paths,
            args=['dangling/../existing.txt'],expected=1)
        print('POSIX: real partial-write failure, path entry points and symlink save OK',flush=True)
    else:
        def junctions(c):
            (c/'existing.txt').write_bytes(b'original')
            (c/'target').mkdir()
            subprocess.run(['cmd','/c','mklink','/J',str(c/'dangling'),str(c/'target')],check=True,capture_output=True)
            (c/'target').rmdir()
        run('junction-open',r'''
local core=require 'core'
assert(not pcall(core.open_doc,'dangling/../existing.txt'))
local d=core.open_doc('existing.txt')
assert(not pcall(core.open_doc,'dangling/../existing.txt'))
local n=#core.docs;core.on_event('filedropped','dangling/../existing.txt',10,10);assert(#core.docs==n)
assert(core.open_doc('missing/parent/new.txt'));core.quit(true)
''',junctions)
        run('junction-startup',"error('must not reach bundle tail')",junctions,
            args=['dangling/../existing.txt'],expected=1)
        print('Windows: dangling junction open/dedup/drop/startup rejection OK',flush=True)

    for untitled in (False,True):
        shared=base/('untitled-race' if untitled else 'named-race');shared.mkdir()
        (shared/'original.txt').write_bytes(b'original')
        (shared/('unsaved-1~' if untitled else 'original.txt~')).write_bytes(b'prior')
        processes=[]
        try:
            for name in ('a','b'):
                dev=shared/name;dev.mkdir()
                code=r'''
local core=require 'core';local name=assert(os.getenv('ROUND2_NAME'))
EXEDIR='.'
core.docs={}
local d=core.open_doc(UNTITLED and nil or 'original.txt');d:text_input(name)
local write=system.write_file
system.write_file=function(path,text,exclusive)
 if exclusive and not path:match('~%d+$') then
  local f=assert(io.open(name..'.ready','wb'));f:write('ready');f:close()
  local deadline=system.get_time()+12
  while not system.get_file_info('release') do
   assert(system.get_time()<deadline);system.sleep(.01)
  end
 end
 return write(path,text,exclusive)
end
error('intentional concurrent recovery')
'''.replace("core.open_doc(UNTITLED and nil or 'original.txt')", "core.open_doc()" if untitled else "core.open_doc('original.txt')")
                (dev/'workbench.lua').write_text(source+'\n'+code,encoding='utf-8')
                processes.append(subprocess.Popen([str(BINARY),'--safe-mode','--lua-dev',str(dev),str(shared)],
                    cwd=shared,env=dict(env,ROUND2_NAME=name),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
            deadline=time.monotonic()+15
            while not all((shared/(n+'.ready')).exists() for n in ('a','b')):
                assert time.monotonic()<deadline,'barrier timeout'
                assert all(p.poll() is None for p in processes),'premature exit'
                time.sleep(.01)
            (shared/'release').touch()
            for p in processes:
                out=p.communicate(timeout=20);assert p.returncode==1,out
            backups=list(shared.glob('unsaved-1~*' if untitled else 'original.txt~*'))
            assert sorted(p.read_bytes() for p in backups)==sorted([b'prior',b'a' if untitled else b'aoriginal',b'b' if untitled else b'boriginal'])
            assert (shared/'original.txt').read_bytes()==b'original'
        finally:
            for p in processes:
                if p.poll() is None:p.kill();p.communicate()
    print('R2-04: concurrent named/untitled recovery preserves both versions and prior backup',flush=True)
print('round2: PASS')
