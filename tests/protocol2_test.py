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
            # Private-room CLI/control messages cross both transports.
            cli('b', 'room-mode', room, 'private')
            d = cli('d', 'keygen').strip()
            cli('d', 'whoami', '--register', 'late-user')
            cli('d', 'read', room, '0', ok=False)
            cli('d', 'meta', room, ok=False)
            cli('d', 'follow', room, ok=False)
            assert room not in cli('d', 'rooms')
            cli('d', 'send', room, 'not a member', ok=False)
            cli('d', 'join', room)
            cli('d', 'join', room, ok=False)
            gate(b, f'send {room}', input=f'@{room} join-approve {d}')
            assert 'join-request' in cli('d', 'read', '--raw', room, '0')
            cli('d', 'send', room, 'approved via SSH')
            e = cli('e', 'keygen').strip()
            cli('e', 'whoami', '--register', 'late-two')
            gate(e, f'join {room}')
            cli('d', 'send', room, f'@{room} join-approve {e}')
            assert 'approved via SSH' in gate(e, f'read {room} 0')
            f = cli('f', 'keygen').strip()
            cli('f', 'whoami', '--register', 'outsider')
            cli('f', 'room-mode', room, 'public')
            assert 'approved via SSH' in cli('f', 'read', '--raw', room, '0')
            # A read-only public follower must stop after the room becomes private.
            fe = dict(os.environ, COOLOO_CONFIG=str(base / 'f'), COOLOO_HOST=f'127.0.0.1:{port}')
            with open(base / 'readonly-follow.log', 'w+') as follow_log:
                follower = subprocess.Popen([str(client / 'cooloo-cli'), '-y', 'follow', room],
                                            env=fe, stdout=follow_log, stderr=follow_log)
                try:
                    cli('a', 'send', room, 'readonly-follow-ready')
                    for _ in range(200):
                        follow_log.seek(0)
                        if 'readonly-follow-ready' in follow_log.read():
                            break
                        time.sleep(.02)
                    else:
                        raise AssertionError('read-only follower not ready')
                    gate(f, f'room-mode {room} private')
                    assert follower.wait(timeout=5) != 0
                finally:
                    if follower.poll() is None:
                        follower.terminate()
                        follower.wait(timeout=5)
            cli('f', 'send', room, 'not a historical sender', ok=False)
            cli('f', 'read', room, '0', ok=False)
            cli('f', 'room-mode', room, 'public')
            cli('f', 'send', room, 'historical participant')
            gate(f, f'room-mode {room} private')
            cli('f', 'send', room, 'included in snapshot')
            print('client2: native/SSH interoperability, private-room CLI/join/approval, metadata ACL, exact JSONL cache and FOLLOW restart passed')
        finally:
            daemon.terminate()
            daemon.wait(timeout=5)
