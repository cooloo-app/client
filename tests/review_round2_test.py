"""Isolated round-two correctness regressions; optional baseline source tree."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

CLIENT = Path(__file__).resolve().parents[1]
HOST = Path(sys.argv[1] if len(sys.argv) > 1 else CLIENT / 'cooloo-text-linux').resolve()
SOURCE = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else CLIENT
with tempfile.TemporaryDirectory(prefix='cooloo-review2-') as tmp:
    base = Path(tmp)
    host = base / HOST.name
    shutil.copy2(HOST, host)
    bundle = base / 'bundle.lua'
    subprocess.run([sys.executable, str(SOURCE / 'tools/embed_workbench.py'),
                    str(bundle), '--profile', 'text', '--lua'], cwd=SOURCE, check=True)
    source = bundle.read_text() + '\n' + (CLIENT / 'tests/review_round2.lua').read_text()
    failures = []
    for number in range(1, 10):
        case = base / str(number)
        case.mkdir()
        (case / 'workbench.lua').write_text(source)
        env = dict(os.environ, SDL_VIDEODRIVER='dummy',
                   COOLOO_TEXT_USERDIR=str(case / 'user'), REVIEW2_CASE=str(number))
        env.pop('COOLOO_PROBE_STARTUP', None)
        p = subprocess.run([str(host), '--safe-mode', '--lua-dev', str(case), '--', str(case)],
                           cwd=case, env=env, capture_output=True, text=True, errors='replace', timeout=30)
        print(f'CASE {number}: {p.returncode}\n{p.stdout}\n{p.stderr}', flush=True)
        if p.returncode:
            failures.append(number)
    if failures:
        sys.exit(1)
