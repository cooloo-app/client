"""CLI + native daemon + forced-command gate + exact cache interoperability."""
import json
import uuid
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
        if command.startswith('send '):
            parts=command.split(' ',2);command=' '.join(parts[:2])+ ' '+uuid.uuid4().hex+(' '+parts[2] if len(parts)>2 else '')
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
            gate(a, f'read {c} 0')
            cli('a', 'read', '--raw', c, '0')
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
            # Parent owns access to the child; ordinary children never act as A.
            cli('c', '--as', a, 'read', a, '0', ok=False)
            cli('a', 'delegate', c, 'read')
            cli('a', '--as', c, 'read', c, '0')
            cli('a', '--as', c, 'send', b, 'forbidden write', ok=False)
            cli('a', '--as', c, 'rename', c, 'forbidden admin', ok=False)
            cli('a', 'delegate', c, 'write')
            cli('a', 'read', c, '0', ok=False)
            cli('a', '--as', c, 'read', c, '0', ok=False)
            cli('a', '--as', c, 'send', b, 'parent as child')
            cli('c', 'send', b, 'child default write')
            gate(a, f'delegate {c} read,write')
            assert 'parent as child' in gate(a, f'--as {c} sent {b} 0')
            # Pure mirror: B is a credential for A, never a second inbox/sender.
            mirror = cli('mirror', 'keygen').strip()
            cli('a', '--json', 'mirror', '002', mirror, 'mirror')
            context=json.loads(cli('mirror','--json','identity'))
            assert context['authenticated_id']==mirror and context['effective_id']==a
            assert json.loads(cli('mirror','--json','whoami'))['id']==mirror
            assert gate(mirror,'whoami').split()[1]==mirror
            assert gate(mirror,'identity').split()[2]==a
            cli('mirror','send',b,'mirror native')
            gate(mirror,f'send {b} mirror SSH')
            messages=[json.loads(x) for x in cli('b','read','--raw',b,'0').splitlines()]
            assert all(m['from']==a for m in messages[-2:])
            for sender in ['a','b','mirror']:
                cli(sender,'send',mirror,'no mirror inbox',ok=False)
                cli(sender,'send',a+':002','no mirror alias',ok=False)
            cli('mirror','--as',mirror,'send',b,'no mirror sender',ok=False)
            gate(mirror,f'--as {mirror} send {b} no',ok=False)
            gate(mirror,f'--as {mirror} create no',ok=False)
            gate(mirror,f'--as {mirror} rename {mirror} no',ok=False)
            gate(b,f'send {a}:002 no',ok=False)
            for args in [('delegate',c,'read'),('detach',mirror),('rename',a,'bad'),('create','bad')]:
                cli('mirror',*args,ok=False)
            cli('b','send',a,'reply discovers peer')
            cli('d','send',b,'unrelated secret')
            filtered=cli('mirror','sent',b,'0')
            assert 'mirror native' in filtered and 'unrelated secret' not in filtered
            merged=cli('mirror','history')
            assert 'mirror native' in merged and 'reply discovers peer' in merged
            assert 'unrelated secret' not in merged
            cli('a','send',f,'unreplied message remains undiscovered')
            assert 'unreplied message remains undiscovered' not in cli('mirror','history')
            assert 'unreplied message remains undiscovered' in cli('mirror','sent',f,'0')
            peer_end=(data/'rooms'/b/'messages.jsonl').stat().st_size
            assert cli('mirror','sent',b,str(peer_end))==''
            cli('mirror','sent',b,'1',ok=False)
            cli('mirror','sent',room,'0',ok=False)
            # A and B folders exist in A's effective cache partition, not B's.
            for inbox in [a,mirror]:
                cli('mirror','read','--raw',inbox,'0')
                assert list((base/'mirror'/'cache').glob(f'*/{a}/rooms/{inbox}/.meta'))
            assert not list((base/'mirror'/'cache').glob(f'*/{mirror}/rooms/{a}/messages.jsonl'))
            # Both direct parent and AS-child FOLLOW stop after revocation.
            ae=dict(os.environ,COOLOO_CONFIG=str(base/'a'),COOLOO_HOST=f'127.0.0.1:{port}')
            for flags in [[],['--as',c]]:
                cli('a','delegate',c,'read,write')
                with open(base/'parent-follow.log','w+') as follow_log:
                    follower=subprocess.Popen([str(client/'cooloo-cli'),'-y',*flags,'follow',c],env=ae,stdout=follow_log,stderr=follow_log)
                    try:
                        marker='parent-follow-ready-'+str(bool(flags))
                        cli('b','send',c,marker)
                        for _ in range(200):
                            follow_log.seek(0)
                            if marker in follow_log.read(): break
                            time.sleep(.02)
                        else: raise AssertionError('parent follower not ready')
                        gate(a,f'delegate {c} none')
                        assert follower.wait(timeout=5)!=0
                    finally:
                        if follower.poll() is None: follower.terminate();follower.wait(timeout=5)
            cli('a','--as',c,'send',b,'revoked',ok=False)
            cli('c','send',b,'own identity still works')
            # Untrusted metadata and obsolete authz cannot authorize access.
            child_meta=data/'rooms'/c/'.meta';saved_meta=child_meta.read_bytes()
            child_meta.write_bytes(saved_meta.replace(f'"owner":"{a}"'.encode(),f'"owner":"{b}"'.encode()))
            cli('b','--as',c,'read',c,'0',ok=False)
            child_meta.write_bytes(saved_meta)
            legacy=data/'authz'/a/c;legacy.parent.mkdir(parents=True);legacy.write_text('DELEGATE-1 3\n')
            cli('c','--as',a,'read',a,'0',ok=False)
            record=data/'relations'/c;saved=record.read_bytes();record.write_text('RELATION-1 invalid\n')
            cli('a','--as',c,'read',c,'0',ok=False)
            record.write_bytes(saved)
            # Detach invalidates existing mirror streams and returns independent IDs.
            me=dict(os.environ,COOLOO_CONFIG=str(base/'mirror'),COOLOO_HOST=f'127.0.0.1:{port}')
            with open(base/'mirror-follow.log','w+') as follow_log:
                follower=subprocess.Popen([str(client/'cooloo-cli'),'-y','--json','follow',a,'0'],env=me,stdout=follow_log,stderr=follow_log)
                try:
                    for _ in range(200):
                        follow_log.seek(0)
                        if 'reply discovers peer' in follow_log.read(): break
                        time.sleep(.02)
                    else: raise AssertionError('mirror follower not ready')
                    cli('a','detach',mirror)
                    assert follower.wait(timeout=5)!=0
                finally:
                    if follower.poll() is None: follower.terminate();follower.wait(timeout=5)
            assert json.loads(cli('mirror','--json','identity'))['effective_id']==mirror
            cli('mirror','--as',a,'read',a,'0',ok=False)
            cli('mirror','send',b,'independent again')
            cli('b','send',mirror,'independent inbox')
            assert 'independent inbox' in cli('mirror','read','--raw',mirror,'0')
            print('client2: parent permissions, pure mirrors, detach/FOLLOW revocation, transport parity, filtered history and identity-isolated caches passed')
        finally:
            daemon.terminate()
            daemon.wait(timeout=5)
