"""Real GUI provider + isolated Native daemon: discovery, live latency, SENT refresh."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cooloo-refresh-') as tmp:
    base = Path(tmp)
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    env = dict(os.environ, COOLOO_CONFIG=str(base/'a'), COOLOO_HOST=f'127.0.0.1:{port}', SDL_VIDEODRIVER='dummy')
    def cli(*args, config=None):
        e = dict(env, COOLOO_CONFIG=str(config or base/'a'))
        return subprocess.check_output([str(root/'cooloo-cli'), *args], env=e, text=True, timeout=15).strip()
    with (base/'server.log').open('w') as log:
        server = subprocess.Popen([str(root.parent/'server/coolood'), '-b', '127.0.0.1', '-p', str(port)], env=dict(env, COOLOO_HOME=str(base/'server')), stdout=log, stderr=log)
        gui = None
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1', port), .1): break
                except OSError: time.sleep(.02)
            a = cli('keygen'); cli('-y', 'whoami', '--register', 'refresh-a')
            b = cli('keygen', config=base/'b'); cli('-y', 'whoami', '--register', 'refresh-b', config=base/'b')
            cli('send', a, 'peer seed', config=base/'b')
            dev = base/'dev'; dev.mkdir()
            subprocess.run(['python3', str(root/'tools/embed_workbench.py'), str(dev/'workbench.lua'), '--lua'], check=True, stdout=subprocess.DEVNULL)
            with (dev/'workbench.lua').open('a') as f:
                f.write('''
local old=cooloo.frame
local ready, discovered, live, sent=false,false,false,false
function cooloo.frame(events,dt,start)
 old(events,dt,start)
 local inbox=chat.rooms[chat.identity()]
 if inbox and inbox.following and not ready then print('READY');io.stdout:flush();ready=true end
 for _,r in pairs(chat.rooms) do
  if r.nickname=='created-after-start' and not discovered then
   print('DISCOVERED');io.stdout:flush();discovered=true
  end
  for _,m in ipairs(r.buf) do
   if m.text=='live latency probe' and not live then print('LIVE');io.stdout:flush();live=true end
   if m.text=='external sent probe' and m.sent and not sent then print('SENT_REFRESH');io.stdout:flush();sent=true end
  end
 end
 if live and sent then cooloo.quit() end
end
''')
            out = base/'gui.log'
            with out.open('w') as output:
                gui = subprocess.Popen([str(root/'cooloo-linux'), '--gui', '--debug', '--lua-dev', str(dev)], env=env, stdout=output, stderr=output)
                def wait(marker, timeout):
                    start = time.monotonic()
                    while marker not in out.read_text():
                        if gui.poll() is not None or time.monotonic()-start > timeout:
                            raise AssertionError((marker, out.read_text()))
                        time.sleep(.02)
                    return time.monotonic()-start
                wait('READY', 15)
                room = cli('create', 'created-after-start').split()[1]
                discovery = wait('DISCOVERED', 6)
                # Allow the bounded background scheduler to admit the newly listed room.
                time.sleep(3)
                cli('send', room, 'live latency probe', config=base/'b')
                live = wait('LIVE', 1)
                cli('send', b, 'external sent probe')
                sent = wait('SENT_REFRESH', 7)
                assert gui.wait(timeout=5) == 0
                print(f'refresh integration: discovery={discovery:.3f}s live={live:.3f}s SENT={sent:.3f}s')
        finally:
            if gui and gui.poll() is None: gui.terminate(); gui.wait(timeout=5)
            server.terminate(); server.wait(timeout=5)
