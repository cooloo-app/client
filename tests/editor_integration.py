"""SDL dummy end-to-end text tests; uses only temporary user/project/config files."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cooloo-text-test-') as tmp:
    base = Path(tmp)
    user = base / 'user'
    (user / 'plugins').mkdir(parents=True)
    (user / 'plugins' / 'sample.lua').write_text("local c=require 'core';c.test_plugin=true;c.test_order='plugin'\n")
    (user / 'plugins' / 'broken.lua').write_text("error('expected broken plugin')\n")
    (user / 'helper.lua').write_text("return 'user-helper'\n")
    (user / 'init.lua').write_text("local c=require 'core';assert(require('user.helper')=='user-helper');assert(c.test_plugin);c.test_user=true;c.test_order=c.test_order..',user'\n")
    dev = base / 'dev'
    dev.mkdir()
    subprocess.run([sys.executable, str(root / 'tools/embed_workbench.py'), str(dev / 'workbench.lua'), '--profile', 'text', '--lua'], check=True)
    with (dev / 'workbench.lua').open('a', encoding='utf-8') as f:
        f.write('\n' + (root / 'tests/editor_integration.lua').read_text(encoding='utf-8'))
    for mode in ('normal', 'safe'):
        project = base / (mode + ' project 中文 & space')
        project.mkdir()
        (project / '中文 file.lua').write_bytes(b'local hello = 1\n')
        (project / 'drop.txt').write_bytes(b'needle in project\n')
        (project / '.lite_project.lua').write_text("local c=require 'core';assert(c.test_user);c.test_project=true;c.test_order=c.test_order..',project'\n")
        env = dict(os.environ, SDL_VIDEODRIVER='dummy', LITE_SCALE='1.25', COOLOO_TEXT_USERDIR=str(user),
                   COOLOO_EDITOR_TEST_MODE=mode, COOLOO_CONFIG=str(base / 'no-config'))
        env.pop('COOLOO_PROBE_STARTUP', None)
        args = [str(binary), '--lua-dev', str(dev)]
        if mode == 'safe':
            args.append('--safe-mode')
        args += [str(project), str(project / '中文 file.lua')]
        p = subprocess.run(args, cwd=base, env=env, capture_output=True, timeout=20)
        output = p.stdout.decode(errors='replace') + p.stderr.decode(errors='replace')
        assert p.returncode == 0 and f'editor integration {mode}: OK' in output, (p.returncode, output)
        assert 'lua error:' not in output and 'draw op' not in output, output
        print(output.strip())
        assert not (project / 'virtual.txt').exists()
    # Real argv-based launch, with shell metacharacters/Unicode in the project path.
    child = base / 'child 中文 & space'
    child.mkdir()
    marker = child / 'launched.txt'
    (child / '.lite_project.lua').write_text("local f=assert(io.open('launched.txt','w'));f:write('child OK');f:close();cooloo.quit()\n")
    launch = base / 'launch'
    launch.mkdir()
    subprocess.run([sys.executable, str(root / 'tools/embed_workbench.py'), str(launch / 'workbench.lua'), '--profile', 'text', '--lua'], check=True)
    # No optional safe argument must not be confused with C API stack temporaries.
    with (launch / 'workbench.lua').open('a', encoding='utf-8') as f:
        f.write("\nsystem.open_project(assert(os.getenv('COOLOO_TEST_CHILD')));cooloo.quit()\n")
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', COOLOO_TEXT_USERDIR=str(base / 'empty-user'),
               COOLOO_TEST_CHILD=str(child), COOLOO_CONFIG=str(base / 'no-config'))
    env.pop('COOLOO_PROBE_STARTUP', None)
    p = subprocess.run([str(binary), '--lua-dev', str(launch), '--safe-mode', str(base)],
                       cwd=base, env=env, capture_output=True, timeout=10)
    assert p.returncode == 0, p.stderr
    for _ in range(100):
        if marker.exists():
            break
        time.sleep(0.05)
    assert marker.read_text() == 'child OK', 'directory launch must run embedded child in selected project'
    assert not (base / 'no-config').exists()
print('text startup, external extension errors, safe mode, UTF-8, directory child and dependency boundaries: OK')
