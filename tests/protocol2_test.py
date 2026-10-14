"""CLI + native daemon + forced-command gate + exact cache interoperability."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

client = Path(__file__).resolve().parents[1]
server = client.parent / 'server'
with tempfile.TemporaryDirectory(prefix='cooloo-client2-') as tmp:
    base = Path(tmp)
    data = base / 'server'
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, COOLOO_HOME=str(data))
    def cli(user, *args, input=None, ok=True):
        ce = dict(os.environ, COOLOO_CONFIG=str(base / user), COOLOO_HOST=f'127.0.0.1:{port}')
        p = subprocess.run([str(client / 'cooloo-cli'), '-y', *args], env=ce, input=input, text=True, capture_output=True, timeout=10)
        assert (p.returncode == 0) == ok, (args, p.stdout, p.stderr, p.returncode)
        return p.stdout
    def gate(user_id, command, input=None, ok=True):
        p = subprocess.run([str(server / 'cooloo'), '__gate', user_id], env=dict(env, SSH_ORIGINAL_COMMAND=command), input=input, text=True, capture_output=True, timeout=10)
        assert (p.returncode == 0) == ok, (command, p.stdout, p.stderr)
        return p.stdout
    with open(base / 'daemon.log', 'w') as log:
        daemon = subprocess.Popen([str(server / 'coolood'), '-b', '127.0.0.1', '-p', str(port)], env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if daemon.poll() is not None:
                    raise RuntimeError('daemon failed')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=.1):
                        break
                except OSError:
                    time.sleep(.02)
            else:
                raise RuntimeError('daemon not ready')
            a = cli('a', 'keygen').strip()
            b = cli('b', 'keygen').strip()
            c = cli('c', 'keygen').strip()
            assert len(a) == len(b) == len(c) == 64
            for user in ['a', 'b']:
                cli(user, 'whoami', '--register', 'same')
            room = cli('a', 'create', 'room').split()[1]
            cli('a', 'avatar', '001', c, 'agent')
            cli('c', 'whoami')
            text = 'hello\n"世界"\\\t\n'
            cli('b', 'send', a + ':001', input=text)
            gate(a, f'read {c} 0', ok=False)
            cli('a', 'read', '--raw', c, '0', ok=False)
            received = cli('c', 'read', '--raw', c, '0')
            assert json.loads(received)['content'] == text
            gate(b, f'send {room}', input='from SSH\n')
            cli('a', 'send', room, 'from native')
            first = cli('a', 'read', '--raw', room, '0')
            second = cli('a', 'read', '--raw', room, '0')
            assert first == second
            # A valid raw message can expand past a single encrypted frame.
            large = '\t' * 4096
            cli('a', 'send', room, input=large)
            expanded = cli('a', 'read', '--raw', room, '0')
            assert json.loads(expanded.splitlines()[-1])['content'] == large
            cache = list((base / 'a' / 'cache').glob(f'*/{a}/rooms/{room}/messages.jsonl'))
            assert len(cache) == 1
            authoritative = data / 'rooms' / room / 'messages.jsonl'
            assert cache[0].read_bytes() == authoritative.read_bytes()
            assert cache[0].with_name('.meta').read_bytes() == authoritative.with_name('.meta').read_bytes()
            cli('a', 'rename', room, 'renamed')
            assert 'renamed' in cli('b', 'rooms')
            gate(b, f'rename {room} stolen', ok=False)
            gate(a, f'--as {b} send {room} forged', ok=False)
            assert 'from native' in gate(b, f'read {room} 0')
            # FOLLOW catches up from the durable prefix, then receives live appends.
            ce = dict(os.environ, COOLOO_CONFIG=str(base / 'b'), COOLOO_HOST=f'127.0.0.1:{port}')
            for attempt in range(2):
                with open(base / f'follow-{attempt}.log', 'w') as follow_log:
                    follower = subprocess.Popen([str(client / 'cooloo-cli'), '-y', 'follow', room], env=ce, stdout=follow_log, stderr=follow_log)
                    try:
                        cli('a', 'send', room, f'live-{attempt}')
                        for _ in range(200):
                            copies = list((base / 'b' / 'cache').glob(f'*/{b}/rooms/{room}/messages.jsonl'))
                            if copies and copies[0].read_bytes() == authoritative.read_bytes():
                                break
                            if follower.poll() is not None:
                                raise AssertionError('FOLLOW exited early')
                            time.sleep(.02)
                        else:
                            raise AssertionError('FOLLOW cache did not catch up')
                    finally:
                        follower.terminate()
                        follower.wait(timeout=5)
            print('client2: native/SSH interoperability, independent avatars, private ACL, exact JSONL cache, deduplication and FOLLOW restart passed')
        finally:
            daemon.terminate()
            daemon.wait(timeout=5)
