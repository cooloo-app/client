"""Headless CLI, bundle isolation and runner regression. No GUI tests."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    env = dict(os.environ, HOME=tmp, COOLOO_CONFIG=str(base / 'config'))
    def run(*args, code=0, **kwargs):
        p = subprocess.run([str(binary), *map(str, args)], cwd=tmp, env=env,
                           capture_output=True, timeout=10, **kwargs)
        assert p.returncode == code, (args, p.returncode, p.stdout, p.stderr)
        return p
    run('--help')
    run('bad', code=2)
    fixture = base / 'messages.jsonl'
    record = {'ts': 0, 'from': 'a'*64, 'to': 'b'*64, 'content': '中文\nhello', 'id': '550e8400e29b41d4a716446655440000'}
    raw = (json.dumps(record, ensure_ascii=False, separators=(',', ':'))+'\n').encode()
    fixture.write_bytes(raw)
    run('message', 'validate', fixture)
    text = run('message', 'render', fixture).stdout.decode()
    projection = json.loads(run('message', 'render', fixture, '--format', 'json').stdout)
    assert projection['text'] == text
    assert projection['anchors'] == {str(len(raw)): 1}
    assert projection['source_revision'] == str(len(raw))
    for data in [b'bad\n', b'x'*26000, raw.replace('中文'.encode(), b'\xff'), raw.replace(b'hello', b'he\x00llo')]:
        fixture.write_bytes(data)
        p = run('message', 'render', fixture, code=1)
        assert not p.stdout
    fixture.write_bytes(raw.rstrip(b'\n'))
    run('message', 'validate', fixture)
    fixture.write_bytes(raw.replace(b'\n', b'\r\n'))
    run('message', 'validate', fixture)
    run('message', 'validate', base, code=1)
    fixture.write_bytes(b'')
    assert run('message', 'render', fixture).stdout == b''
    fixture.write_bytes(raw*10001)
    run('message', 'validate', fixture, code=1)
    run('message', 'validate', base/'missing', code=1)
    script = base/'test.lua'
    script.write_text('assert(cooloo == nil); print("runner OK")')
    assert b'runner OK' in run('--lua-run', script).stdout
    frame = b'print("console OK")'
    assert b'console OK' in run('--lua-console', input=str(len(frame)).encode()+b'\n'+frame).stdout
    run('--lua-console', input=b'invalid\n', code=2)
    assert not (base/'config').exists() and not (base/'.cooloo').exists()
    for profile in ('text', 'gui', 'cli'):
        bundle = base/(profile+'.lua')
        subprocess.run([sys.executable, str(root/'tools/embed_workbench.py'), str(bundle),
                        '--profile', profile, '--lua'], check=True)
        source = bundle.read_text()
        if profile == 'text':
            for name in ('workbench.', 'plugins.console', 'plugins.workspace', 'adapters.', 'client.chat'):
                assert 'package.preload[\''+name not in source
            assert 'workspace:send' not in source and 'console:open' not in source
        if profile == 'gui':
            # Execute the real provider tests using ONLY embedded modules. Source
            # paths in ordinary provider tests otherwise hide missing bundle files.
            entry = (root/'lua/apps/workbench/gui.lua').read_text()
            assert source.endswith(entry)
            provider = (root/'tests/provider.lua').read_text().splitlines()
            provider = '\n'.join(line for line in provider
                                 if not line.startswith(('package.path=',
                                                         "package.preload['client.chat']=")))
            bundled_test = base/'bundled-provider.lua'
            bundled_test.write_text("package.path=''; package.cpath=''\n" +
                                    source[:-len(entry)] + '\n' + provider)
            run('--lua-run', bundled_test)
        if profile == 'cli':
            assert "package.preload['core" not in source
            assert "require 'core" not in source
    symbols = subprocess.run(['nm', str(binary)], capture_output=True, text=True, check=True).stdout
    for name in ('SDL_', 'cfg_identity_load', 'cache_read', 'net_connect', 'cooloo_gui_run'):
        assert name not in symbols, name
print('headless CLI/bundles/runner: OK')
