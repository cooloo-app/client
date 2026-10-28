"""Run review regressions in isolated SDL-dummy text hosts."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

CLIENT = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cooloo-review1-') as tmp:
    base = Path(tmp)
    host = base / binary.name
    shutil.copy2(binary, host)
    bundle = base / 'bundle.lua'
    subprocess.run([sys.executable, str(CLIENT/'tools/embed_workbench.py'),
                    str(bundle), '--profile', 'text', '--lua'], check=True)
    source = bundle.read_text()
    tests = (CLIENT/'tests/review_round1.lua').read_text()
    failures = []
    for number in range(1, 10):
        case = base / str(number)
        case.mkdir()
        (case/'workbench.lua').write_text(source + '\n' + tests)
        env = dict(os.environ, SDL_VIDEODRIVER='dummy',
                   COOLOO_TEXT_USERDIR=str(case/'user'), REVIEW_CASE=str(number))
        env.pop('COOLOO_PROBE_STARTUP', None)
        p = subprocess.run([str(host), '--safe-mode', '--lua-dev', str(case), '--', str(case)],
                           cwd=case, env=env, capture_output=True, text=True, timeout=25)
        print(f'CT-{number:02}: {"PASS" if p.returncode == 0 else "FAIL"}', p.stdout, p.stderr, flush=True)
        if p.returncode:
            failures.append(number)
    assert not failures, failures
