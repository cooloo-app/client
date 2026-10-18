"""Round-3 acceptance in isolated real text hosts; no personal files/network.
Usage: python3 tests/round3_test.py ./cooloo-text-linux
"""
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
    env.pop('COOLOO_PROBE_STARTUP', None)

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
            cwd=case, env=env, capture_output=True, text=True, timeout=25)
        assert p.returncode == expected, (name, p.returncode, p.stdout, p.stderr)
        print(name + ': ' + p.stdout.strip(), flush=True)
        return case

    def fixtures(c):
        (c/'file.txt').write_bytes(b'valuable')
        (c/'hard.txt').write_bytes(b'hard')
        os.link(c/'hard.txt', c/'hard-alias.txt')
        (c/'sub').mkdir()
        (c/'directory').mkdir()
        (c/'valid.txt').write_bytes(b'new\r\ncontent\r\n')
        (c/'focus.txt').write_bytes(b'original')
        (c/'invalid.bin').write_bytes(b'\x80abc')
    run('editing', (CLIENT/'tests/round3.lua').read_text(encoding='utf-8'), fixtures)

    fatal = """
local core=require 'core';core.docs={}
local d=core.open_doc('error.txt');d:text_input('UNSAVED')
local other=core.open_doc('other.txt');other:text_input('keep')
error('intentional fatal diagnostic')
"""
    case = run('fatal-existing', fatal,
               lambda c: (c/'error.txt').write_bytes(b'valuable'), expected=1)
    assert (case/'error.txt').read_bytes() == b'valuable'
    assert (case/'error.txt~').read_bytes() == b'UNSAVEDvaluable'
    assert (case/'error.txt~1').read_bytes().startswith(b'Error: ')
    assert (case/'other.txt~').read_bytes() == b'keep'

    for kind in ('directory', 'write-failure', 'exception'):
        code = """
local core=require 'core';core.docs={}
local d=core.open_doc('good.txt');d:text_input('keep')
"""
        if kind != 'directory':
            code += """
local write=system.write_file
system.write_file=function(path,...)
 if path:find('error.txt',1,true) then
  if MODE=='exception' then error('injected diagnostic failure') end
  return nil,'injected permission denial',false
 end
 return write(path,...)
end
""".replace('MODE', repr(kind))
        code += "error('intentional fatal')\n"
        case = run('fatal-'+kind, code,
                   (lambda c: (c/'error.txt').mkdir()) if kind == 'directory' else None,
                   expected=1)
        assert (case/'good.txt~').read_bytes() == b'keep'
        if kind == 'directory':
            assert (case/'error.txt').is_dir()
        # Windows may report a directory collision as ACCESS_DENIED: stderr
        # remains the diagnostic fallback; dirty recovery must still succeed.

    # Symlinks require a privilege on Windows; report an explicit skip there if
    # unavailable. Hard-link refusal above runs on all three platforms.
    can_symlink = True
    try:
        (base/'link-probe').symlink_to('absent')
    except OSError as exc:
        can_symlink = False
        print('SKIP symlink fixtures:', exc, flush=True)
    if can_symlink:
        def links(c):
            (c/'file.txt').write_bytes(b'valuable')
            (c/'alias.txt').symlink_to('file.txt')
        for old, new in [('file.txt', 'alias.txt'), ('alias.txt', './file.txt'),
                         ('alias.txt', 'moved.txt')]:
            code = """
local core=require 'core';local command=require 'core.command'
local d=core.open_doc(OLD);core.root_view:open_doc(d);d:text_input('X')
assert(command.perform('doc:rename'));assert(core.active_view==core.command_view)
core.command_view:set_text(NEW);core.command_view:submit()
assert(d:is_dirty()==SAME)
core.quit(true)
""".replace('OLD', repr(old)).replace('NEW', repr(new)).replace(
                'SAME', 'false' if new == 'moved.txt' else 'true')
            case = run('rename-link-'+str(len(list(base.iterdir()))), code, links)
            assert (case/'file.txt').read_bytes() == b'valuable'
            if new == 'moved.txt':
                assert not (case/'alias.txt').is_symlink()
                assert (case/'moved.txt').read_bytes() == b'Xvaluable'
            else:
                assert (case/'alias.txt').is_symlink()
        def fatal_link(c):
            (c/'valuable.txt').write_bytes(b'valuable')
            (c/'error.txt').symlink_to('valuable.txt')
        case = run('fatal-symlink', fatal, fatal_link, expected=1)
        assert (case/'error.txt').is_symlink()
        assert (case/'valuable.txt').read_bytes() == b'valuable'
        assert (case/'error.txt~').read_bytes() == b'UNSAVEDvaluable'
        assert (case/'error.txt~1').read_bytes().startswith(b'Error: ')

    # Two real processes collide on the diagnostic name without overwriting it.
    shared = base/'concurrent'; shared.mkdir()
    processes = []
    try:
        for index in range(2):
            dev=shared/str(index);dev.mkdir()
            (dev/'workbench.lua').write_text(source+'\nEXEDIR='+json.dumps(shared.as_posix())+
                                           "\nerror('fatal instance " + str(index) + "')\n", encoding='utf-8')
            processes.append(subprocess.Popen(
                [str(BINARY),'--safe-mode','--lua-dev',str(dev),str(shared)],
                cwd=shared,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE))
        for p in processes:
            output=p.communicate(timeout=25);assert p.returncode==1,output
        logs=[p.read_text() for p in shared.glob('error.txt*')]
        assert len(logs)==2 and any('fatal instance 0' in s for s in logs) and any('fatal instance 1' in s for s in logs)
    finally:
        for p in processes:
            if p.poll() is None:
                p.kill();p.communicate()
    print('R3-02: diagnostic collision/link/dir/failure, dirty recovery and concurrent logs OK')
print('round3: PASS')
