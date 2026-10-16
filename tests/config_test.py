"""Offline endpoint migration and trust-pin regressions; never connects."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

CLIENT = Path(__file__).resolve().parents[1]
FP = 'e6da669a4763acc8e790c6c757f698eed8eeab2c56007a62d28fd48f421c06bf'
NEW = '123.206.215.121'
OLD = '43.133.202.144'
with tempfile.TemporaryDirectory(prefix='cooloo-config-test-') as tmp:
    root = Path(tmp)
    src = root / 'probe.c'
    src.write_text('''#include "config.h"
#include <stdio.h>
int main(int argc, char **argv) {
    char host[256], fp[65]; int port;
    cfg_server(host, sizeof host, &port);
    printf("%s:%d\\n", host, port);
    if (cfg_known_server_get(argc > 1 ? argv[1] : "123.206.215.121:4222", fp))
        puts(fp);
    else puts("unknown");
    return 0;
}
''')
    exe = root / 'probe'
    subprocess.run([*shlex.split(os.environ.get('CC', 'cc')),
                    *shlex.split(os.environ.get('CFLAGS', '-O2 -Wall -Wextra -std=c99')),
                    '-I', str(CLIENT / 'src'), str(src), str(CLIENT / 'src/config.c'),
                    '-o', str(exe)], check=True)
    cfg = root / 'config-dir'
    cfg.mkdir()
    identity = bytes(range(32))
    (cfg / 'identity').write_bytes(identity)
    cases = [
        ('', None, f'{NEW}:4222'),
        (f'host {OLD}\n', None, f'{NEW}:4222'),
        (f'host {OLD}\nport 4222\n', '', f'{NEW}:4222'),
        (f'host {OLD}\nport 5000\n', None, f'{OLD}:5000'),
        ('host private.example\nport 5000\n', None, 'private.example:5000'),
        (f'host {OLD}\n', f'{OLD}:4222', f'{OLD}:4222'),
        (f'host {OLD}\n', 'localhost:12345', 'localhost:12345'),
    ]
    def run(config, envhost=None, pins='', target=f'{NEW}:4222'):
        (cfg / 'config').write_text(config)
        (cfg / 'known_servers').write_text(pins)
        env = dict(os.environ, COOLOO_CONFIG=str(cfg))
        env.pop('COOLOO_HOST', None)
        if envhost is not None:
            env['COOLOO_HOST'] = envhost
        result = subprocess.run([str(exe), target], env=env, capture_output=True,
                                text=True, check=True, timeout=5).stdout.splitlines()
        assert (cfg / 'config').read_text() == config
        assert (cfg / 'known_servers').read_text() == pins
        assert (cfg / 'identity').read_bytes() == identity
        return result
    for config, envhost, expected in cases:
        assert run(config, envhost)[0] == expected
    assert run('', pins=f'{OLD}:4222 {FP}\n')[1] == FP
    assert run('', pins=f'{OLD}:4222 {"a" * 64}\n')[1] == 'unknown'
    assert run('', pins=f'{OLD}:4222 {FP}\n{NEW}:4222 {"b" * 64}\n')[1] == 'b' * 64
    assert run('', pins=f'{OLD}:4222 {FP}\n', target=f'{NEW}:5000')[1] == 'unknown'
    assert run('', pins=f'{OLD}:4222 {FP}\n', target='private.example:4222')[1] == 'unknown'
print('PASS: default/legacy relocation, explicit overrides, exact legacy pin continuity, no file mutation')
