"""Isolated loopback composition tests; never uses production config/server."""
import json
import fcntl
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
editor = Path(os.environ.get('COOLOO_TEST_EDITOR', root/'editor-linux'))
gui_binary = Path(os.environ.get('COOLOO_TEST_GUI', root/'cooloo-linux'))

def run(args, env, **kw):
    p = subprocess.run([str(a) for a in args], env=env, capture_output=True, text=True, timeout=20, **kw)
    assert p.returncode == 0, (args, p.stdout, p.stderr)
    assert 'lua error:' not in p.stderr and 'lua: cooloo.frame not defined' not in p.stderr, p.stderr
    return p

with tempfile.TemporaryDirectory(prefix='cooloo-workbench-') as tmp:
    base = Path(tmp)
    env = dict(os.environ, HOME=str(base), COOLOO_CONFIG=str(base/'config'), SDL_VIDEODRIVER='dummy')
    run([editor], dict(env, COOLOO_PROBE_STARTUP='1'))
    assert not (base/'config').exists() and not (base/'.cooloo').exists()
    # Pure editor has neither message plugins nor a user execution runtime.
    offline_dev=base/'offline-dev';offline_dev.mkdir()
    run(['python3',root/'tools/embed_workbench.py',offline_dev/'workbench.lua','--lua','--offline'],env)
    with (offline_dev/'workbench.lua').open('a') as f:
        f.write('''
local original=cooloo.frame
local frames=0
assert(cooloo.runtime==nil)
assert(not package.loaded['plugins.workspace'])
assert(not package.loaded['plugins.console'])
function cooloo.frame(events,dt,frame_start)
  local draws=original(events,dt,frame_start)
  frames=frames+1
  if frames==30 then
    print('PURE_TEXT_READY')
    cooloo.quit()
  end
  return draws
end
''')
    alive=run([editor,'--lua-dev',offline_dev],env)
    assert 'PURE_TEXT_READY' in alive.stdout
    assert not (base/'config').exists() and not (base/'.cooloo').exists()
    symbols = run(['nm', editor], env).stdout
    for symbol in ['net_connect', 'cfg_identity_load', 'cache_read', 'noise_public_key', 'runtime_dispatch', 'runtime_register']:
        assert symbol not in symbols, symbol
    for args in [[], ['--help'], ['--json','version']]:
        cli = run([root/'cooloo-cli', *args], env)
        full = run([gui_binary, *args], env)
        assert cli.stdout == full.stdout
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    env['COOLOO_HOST'] = f'127.0.0.1:{port}'
    log = open(base/'server.log', 'w')
    server = subprocess.Popen([str(root.parent/'server/coolood'), '-b', '127.0.0.1', '-p', str(port)],
                              env=dict(env, COOLOO_HOME=str(base/'server')), stdout=log, stderr=log)
    gui = None
    try:
        for _ in range(100):
            try:
                with socket.create_connection(('127.0.0.1',port),.1): break
            except OSError: time.sleep(.02)
        identity = run([root/'cooloo-cli','keygen'],env).stdout.strip()
        run([root/'cooloo-cli','-y','whoami','--register','workbench-test'],env)
        run([root/'cooloo-cli','send',identity,'seed message'],env)
        script = base/'request.lua'
        script.write_text('local data, code = cooloo.request("send", "'+identity+'", "from runner")\nassert(code == 0, data)\nprint(data)\n')
        run([gui_binary,'--lua-run',script],env)
        child_env=dict(env,COOLOO_CONFIG=str(base/'child-config'))
        child=run([root/'cooloo-cli','keygen'],child_env).stdout.strip()
        run([root/'cooloo-cli','mirror','001',child,'runner-child'],env)
        run([root/'cooloo-cli','-y','whoami'],child_env)
        script.write_text('''
local data, code=cooloo.request_as("'''+identity+'''", "send", "'''+identity+'''", "delegated runner")
assert(code==0,data)
local implicit, implicit_rc=cooloo.request("send", "'''+identity+'''", "default mirror runner")
assert(implicit_rc==0,implicit)
local who, rc=cooloo.request("whoami")
assert(rc==0 and who:find("'''+child+'''",1,true),who)
assert(not pcall(cooloo.request,"whoami","--register","forbidden"))
assert(not pcall(cooloo.request,"send","'''+identity+'''"))
local bad, failed=cooloo.request("meta","bad-id")
assert(failed~=0,bad)
local good, success=cooloo.request("rooms")
assert(success==0,good)
''')
        run([gui_binary,'--lua-run',script],child_env)
        run([root/'cooloo-cli','detach',child],env)
        script.write_text('local data,code=cooloo.request_as("'+identity+'","send","'+identity+'","must fail");assert(code~=0,data)')
        run([gui_binary,'--lua-run',script],child_env)
        received = run([root/'cooloo-cli','--json','read',identity,'0'],env).stdout
        assert 'from runner' in received
        # Test-only harness exercises the actual embedded provider/UI and gracefully quits.
        dev = base/'dev';dev.mkdir()
        run(['python3', root/'tools/embed_workbench.py',dev/'workbench.lua','--lua'],env)
        with (dev/'workbench.lua').open('a') as f:
            f.write('''
local original=cooloo.frame
local count,submitted=0,false
function cooloo.frame(events,dt,frame_start)
  local draws=original(events,dt,frame_start)
  count=count+1
  local core=require 'core'
  local cmd=require 'core.command'
  if chat and chat.current() and #chat.current().buf>=2 and not submitted then
    submitted=true
    core.active_view.doc:text_input('from workbench draft')
    assert(cmd.perform('workspace:send'))
  elseif submitted and core.active_view.doc.lines[1]=='\\n' then
    print("PROVIDER_READY")
    assert(cmd.perform('workspace:history'))
    cooloo.quit()
  elseif count>250 then error('provider never synchronized or send never acknowledged') end
  return draws
end
''')
        p = run([gui_binary,'--gui','--debug','--lua-dev',dev],env)
        assert 'PROVIDER_READY' in p.stdout, p.stderr
        # Real provider/cache restart checks with deterministic window focus.
        run([root/'cooloo-cli','send',identity,'unread from another identity'],child_env)
        for phase in ('background', 'read', 'restart'):
            read_dev=base/('read-'+phase);read_dev.mkdir()
            run(['python3',root/'tools/embed_workbench.py',read_dev/'workbench.lua','--lua'],env)
            with (read_dev/'workbench.lua').open('a') as f:
                f.write('local phase='+json.dumps(phase)+'\n')
                f.write('''
local original=cooloo.frame
local focused=false
system.window_has_focus=function()return focused end
local frames,marked=0,false
function cooloo.frame(events,dt,frame_start)
  local draws=original(events,dt,frame_start);frames=frames+1
  local r=chat.current()
  if r and r.phase=='following' and r.read_state and not r.loading_state then
    if phase=='background' then
      assert(r.unread==1,'background message lost or history counted')
      assert(require('core.command').perform('workspace:toggle-mute'))
      assert(r.read_state.muted and r.unread==1)
      print('READ_STATE_OK');cooloo.quit()
    elseif phase=='read' and not marked then
      assert(r.unread==1 and r.read_state.muted,'restart lost unread/mute')
      focused=true;marked=true
    elseif phase=='restart' or marked then
      assert(r.unread==0 and r.read_state.muted,'read watermark did not survive')
      print('READ_STATE_OK');cooloo.quit()
    end
  end
  if frames>300 then error('read state stalled') end
  return draws
end
''')
            checked=run([gui_binary,'--gui','--debug','--lua-dev',read_dev],env)
            assert 'READ_STATE_OK' in checked.stdout,checked.stderr
        # A cache held by another process must not stall even one UI poll.
        cache=next((base/'config'/'cache').glob('*/'+identity+'/rooms/'+identity+'/messages.jsonl'))
        locked_dev=base/'locked-dev';locked_dev.mkdir()
        run(['python3',root/'tools/embed_workbench.py',locked_dev/'workbench.lua','--lua'],env)
        with (locked_dev/'workbench.lua').open('a') as f:
            f.write('local cache_server="'+cache.parents[3].name+'"\nlocal cache_self="'+identity+'"\n')
            f.write('''
local original=cooloo.frame
local frames=0
for i=1,32 do assert(cooloo.cache_async.submit('read',cache_server,cache_self,cache_self,math.maxinteger,200)) end
assert(not cooloo.cache_async.submit('read',cache_server,cache_self,cache_self,math.maxinteger,200))
function cooloo.frame(events,dt,frame_start)
  local before=cooloo.time()
  local draws=original(events,dt,frame_start)
  assert(cooloo.time()-before<0.5,'cache blocked UI')
  frames=frames+1
  if frames==40 then print('LOCKED_CACHE_UI_ALIVE');cooloo.quit() end
  return draws
end
''')
        with cache.open('rb') as locked:
            fcntl.flock(locked,fcntl.LOCK_EX)
            started=time.monotonic()
            p=run([gui_binary,'--gui','--debug','--lua-dev',locked_dev],env)
            assert 'LOCKED_CACHE_UI_ALIVE' in p.stdout and time.monotonic()-started<5
        # Page a large on-disk history without projecting its full size or rescanning in UI.
        record=json.dumps(dict(ts=1,**{'from':identity,'to':identity},content='bulk',id='550e8400e29b41d4a716446655440000'),separators=(',',':'))+'\n'
        cache.write_text(''.join(record.replace('550e8400e29b41d4a716446655440000',f'{i:012x}41d4a716446655440000') for i in range(12000)))
        history_dev=base/'history-dev';history_dev.mkdir()
        run(['python3',root/'tools/embed_workbench.py',history_dev/'workbench.lua','--lua'],env)
        with (history_dev/'workbench.lua').open('a') as f:
            f.write('''
local original=cooloo.frame
local frames,requested=0,false
function cooloo.frame(events,dt,frame_start)
  local before=cooloo.time()
  local draws=original(events,dt,frame_start)
  assert(cooloo.time()-before<0.5,'large history blocked UI')
  frames=frames+1
  local r=chat.current()
  if r and #r.buf==2000 and not requested then
    require('core.command').perform('workspace:history');requested=true
  elseif r and #r.buf==2200 then print('ASYNC_HISTORY_PAGED');cooloo.quit() end
  if frames>300 then error('history paging stalled') end
  return draws
end
''')
        p=run([gui_binary,'--gui','--debug','--lua-dev',history_dev],env)
        assert 'ASYNC_HISTORY_PAGED' in p.stdout,p.stderr
        cache.write_text('malformed complete record\n')
        # Script READ/SENT results are bounded before capture grows without limit.
        journal=base/'server'/'rooms'/identity/'messages.jsonl'
        with journal.open('ab') as f: f.write(record.encode()*7000)
        script.write_text('''
local data,code=cooloo.request("read","'''+identity+'''","0")
assert(code~=0 and #data<=1024*1024 and data:find('output-limit',1,true),data:sub(-300))
local who,ok=cooloo.request("whoami");assert(ok==0,who)
''')
        run([gui_binary,'--lua-run',script],env)
        corrupt_dev=base/'corrupt-dev';corrupt_dev.mkdir()
        run(['python3',root/'tools/embed_workbench.py',corrupt_dev/'workbench.lua','--lua'],env)
        with (corrupt_dev/'workbench.lua').open('a') as f:
            f.write('''
local original=cooloo.frame
local frames=0
function cooloo.frame(events,dt,frame_start)
  local draws=original(events,dt,frame_start);frames=frames+1
  if chat.status:find('cache read failure',1,true) then
    assert(#chat.current().buf==0);print('CACHE_FAILED_CLOSED');cooloo.quit()
  end
  if frames>150 then error('corrupt cache not rejected') end
  return draws
end
''')
        p=run([gui_binary,'--gui','--debug','--lua-dev',corrupt_dev],env)
        assert 'CACHE_FAILED_CLOSED' in p.stdout
        # Stop a runner while its headless request is stalled at a TCP peer.
        # No Machine API subprocess exists to outlive the runner.
        with socket.socket() as stalled:
            stalled.bind(('127.0.0.1',0));stalled.listen()
            stop_env=dict(env,COOLOO_HOST='127.0.0.1:'+str(stalled.getsockname()[1]))
            blocked_script=base/'blocked-request.lua'
            blocked_script.write_text('cooloo.request("rooms")')
            stop_dev=base/'stop-dev';stop_dev.mkdir()
            run(['python3',root/'tools/embed_workbench.py',stop_dev/'workbench.lua','--lua'],env)
            with (stop_dev/'workbench.lua').open('a') as f:
                f.write('''
assert(cooloo.runtime.start(1, '''+json.dumps(str(blocked_script))+'''))
local frames=0
function cooloo.frame(events,dt)
  frames=frames+1
  cooloo.runtime.poll(1)
  if frames==30 then
    cooloo.runtime.stop(1)
    assert(cooloo.runtime.poll(1).exitcode==nil)
    print('REQUEST_STOPPED');cooloo.quit()
  end
  return {}
end
''')
            p=run([gui_binary,'--gui','--debug','--lua-dev',stop_dev],stop_env)
            assert 'REQUEST_STOPPED' in p.stdout
            stalled.settimeout(2)
            peer,_=stalled.accept()
            with peer:
                peer.settimeout(2)
                while peer.recv(4096): pass  # EOF proves no orphan owns the socket.
    finally:
        server.terminate();server.wait(timeout=5);log.close()
print('integration: offline/CLI isolation, delegated runner reset/revocation, locked/large/corrupt async cache, queue bounds and request-stop cleanup passed')
