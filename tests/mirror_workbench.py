"""Real loopback mirror runner + SDL dummy GUI; no production configuration."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

root=Path(__file__).resolve().parents[1]
server=root.parent/'server'

def run(args,env):
    p=subprocess.run([str(x) for x in args],env=env,text=True,capture_output=True,timeout=30)
    assert p.returncode==0 and 'lua error:' not in p.stderr,(args,p.returncode,p.stdout,p.stderr)
    return p.stdout

with tempfile.TemporaryDirectory(prefix='cooloo-mirror-gui-') as tmp:
    base=Path(tmp)
    with socket.socket() as s:
        s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    env=dict(os.environ,HOME=tmp,COOLOO_HOST=f'127.0.0.1:{port}',SDL_VIDEODRIVER='dummy')
    aenv=dict(env,COOLOO_CONFIG=str(base/'a'))
    benv=dict(env,COOLOO_CONFIG=str(base/'b'))
    with (base/'daemon.log').open('w') as log:
        daemon=subprocess.Popen([str(server/'coolood'),'-b','127.0.0.1','-p',str(port)],env=dict(env,COOLOO_HOME=str(base/'data')),stdout=log,stderr=log)
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',port),.1):break
                except OSError:time.sleep(.02)
            def cli(e,*args):return run([root/'cooloo-cli','-y',*args],e)
            a=cli(aenv,'keygen').strip();b=cli(benv,'keygen').strip()
            cli(aenv,'whoami','--register','parent')
            cli(aenv,'mirror','001',b,'mirror')
            cli(benv,'whoami')
            script=base/'runner.lua'
            script.write_text(f'''
local sent,rc=cooloo.request("send","{a}","mirror runner message")
assert(rc==0,sent)
local who,status=cooloo.request("whoami")
assert(status==0 and who:find("{b}",1,true),who)
local denied,failed=cooloo.request_as("{b}","send","{a}","must not send as B")
assert(failed~=0,denied)
local own,ok=cooloo.request("read","{a}","0")
assert(ok==0 and own:find("mirror runner message",1,true),own)
print("MIRROR_RUNNER_OK")
''')
            assert 'MIRROR_RUNNER_OK' in run([root/'cooloo-linux','--lua-run',script],benv)
            dev=base/'dev';dev.mkdir()
            run(['python3',root/'tools/embed_workbench.py',dev/'workbench.lua','--lua'],env)
            with (dev/'workbench.lua').open('a') as f:
                f.write(f'''
local frame=cooloo.frame
local ticks=0
function cooloo.frame(events,dt,start)
  local result=frame(events,dt,start)
  ticks=ticks+1
  if chat and chat.rooms_loaded then
    assert(chat.identity()=="{a}" and chat.login_id=="{b}")
    local parent,mirror=chat.rooms["{a}"],chat.rooms["{b}"]
    assert(parent and mirror,"both inbox directories must be listed")
    if #parent.buf>0 and parent.phase=="following" and mirror.phase=="following" and mirror.mirror then
      assert(parent.self_id=="{a}" and mirror.self_id=="{a}")
      print("MIRROR_GUI_OK")
      cooloo.quit()
    end
  end
  assert(ticks<600,"mirror GUI synchronization timed out")
  return result
end
''')
            assert 'MIRROR_GUI_OK' in run([root/'cooloo-linux','--gui','--lua-dev',dev],benv)
            for id in [a,b]:
                paths=list((base/'b'/'cache').glob(f'*/{a}/rooms/{id}/.meta'))
                assert len(paths)==1
                meta=json.loads(paths[0].read_text())
                assert meta['id']==id
                if id==b:assert meta['mirror']==1
            cache=list((base/'b'/'cache').glob(f'*/{a}/rooms/{a}/messages.jsonl'))[0]
            records=[json.loads(x) for x in cache.read_text().splitlines()]
            assert records[0]['from']==a and records[0]['content']=='mirror runner message'
            assert not list((base/'b'/'cache').glob(f'*/{b}/rooms/{a}'))
        finally:
            daemon.terminate();daemon.wait(timeout=5)
print('mirror workbench: real runner default identity, sender rejection, SDL dummy dual-directory sync and metadata/cache partition passed')
