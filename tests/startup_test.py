"""Offline startup regression tests, including GUI dispatch without SDL/display."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

client = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cooloo-startup-') as tmp:
    base = Path(tmp)
    config = base / 'config'
    env = dict(os.environ, COOLOO_CONFIG=str(config), COOLOO_HOST='127.0.0.1:1')
    stub = base / 'gui_stub.c'
    stub.write_text('''#include <stdio.h>
int cooloo_gui_run(const char *dev) {
    printf("GUI:%s\\n", dev ? dev : "embedded");
    return 0;
}
''')
    gui = base / 'cooloo-gui-dispatch'
    sources = ['main.c', 'win_console.c', 'cli.c', 'machine.c', 'net.c',
               'config.c', 'record.c', 'noise_xx.c', 'vendor/monocypher.c']
    subprocess.run([*shlex.split(os.environ.get('CC', 'cc')),
                    *shlex.split(os.environ.get('CFLAGS', '-O2 -Wall -Wextra -std=c99')),
                    '-I', str(client / 'src'), '-o', str(gui), str(stub),
                    *(str(client / 'src' / src) for src in sources)], check=True)

    def run(exe, args, code=0):
        result = subprocess.run([str(exe), *args], env=env, input='',
                                text=True, capture_output=True, timeout=5)
        assert result.returncode == code, (args, result)
        return result

    for exe in (client / 'cooloo-cli', gui):
        bare = run(exe, [])
        assert 'usage:' in bare.stdout and '--gui' in bare.stdout
        assert '--help' in bare.stdout and not bare.stderr
        full = run(exe, ['--help'])
        assert 'delegate' in full.stdout and not full.stderr
        assert full.stdout != bare.stdout
        for args in (['--debug'], ['--lua-dev', str(base)], ['--debug', '--lua-dev', str(base)]):
            result = run(exe, args)
            assert result.stdout == bare.stdout and not result.stderr
        assert 'unknown command' in run(exe, ['bogus'], 2).stderr
        assert 'requires a directory' in run(exe, ['--lua-dev'], 2).stderr
        assert 'usage:' in run(exe, ['-y'], 2).stderr
        assert run(exe, ['send'], 2).returncode == 2
        for args in (['--json'], ['--json', '--gui'], ['--gui', 'rooms']):
            result = run(exe, args, 2)
            assert 'GUI:' not in result.stdout and 'usage:' not in result.stdout
            if '--json' in args:
                assert json.loads(result.stdout)['type'] == 'error'
        assert not config.exists(), 'help/errors must not create identity/config files'

    assert 'not available' in run(client / 'cooloo-cli', ['--gui'], 2).stderr
    assert run(gui, ['--gui']).stdout == 'GUI:embedded\n'
    assert run(gui, ['--gui', '--debug']).stdout == 'GUI:embedded\n'
    assert run(gui, ['--lua-dev', str(base), '--gui']).stdout == f'GUI:{base}\n'
    assert run(gui, ['--gui', '--debug', '--lua-dev', str(base)]).stdout == f'GUI:{base}\n'

print('PASS: offline bare/full help, explicit GUI dispatch, errors and no config side effects')
