-- Real adapter/state-machine with deterministic transport/cache boundaries.
package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;./?.lua;./?/init.lua;'..package.path
global=function()end
package.preload['client.chat']=function()dofile('lua/chat.lua');return chat end
local A,B,R=string.rep('a',64),string.rep('b',64),string.rep('c',64)
local time,serial,job_serial=0,0,0
local state_files={}
local original_open=io.open
io.open=function(path,mode)
 if path:match('/read%-state') then
   local value=state_files[path]
   if not value then return nil,'missing',2 end
   return {read=function()return value end,close=function()return true end}
 end
 return original_open(path,mode)
end
system={write_file=function(path,value)state_files[path]=value;return true end,
 read_file=function(path)if state_files[path]~=nil then return state_files[path] end;return nil,'missing',2 end}
local sender=A
local conns,writes,jobs,results={},{},{},{}
cooloo={message_id=function()return '550e8400e29b41d4a716446655440000' end,public_id=function()return A end,ensure_identity=function()return true end,server=function()return 'localhost',4222 end,
 time=function()return time end,config={get=function()end,set=function()return true end},
 net={connect=function()
   local count=0;for _ in pairs(conns)do count=count+1 end
   if count>=16 then return nil,'full' end
   serial=serial+1;conns[serial]=true;return serial
 end,close=function(c)conns[c]=nil end,pause=function()end,fp=function()return B end,
 send=function(c,s)writes[#writes+1]={c=c,s=s};return conns[c]~=nil end},
 cache_async={submit=function(kind,server,self,room,a,b)
   job_serial=job_serial+1;jobs[job_serial]={kind=kind,room=room};return job_serial
 end,poll=function()local r=results;results={};return r end},
 record=function(json)return {ts=1,from=sender,to=R,content=json}end}
local p=require('adapters.cooloo').new()
local function event(kind,c,line)
 p:poll{{type=kind,conn=c,line=line,nick='user',reason='test'}}
 if chat.identity_pending and chat.identity_pending[c] then
   p:poll{{type='net_line',conn=c,line='IDENTITY '..A..' '..(chat.requested_effective or chat.effective or A)}}
 end
 local room=chat.by_conn[c]
 if room and room.generation_wait then
   p:poll{{type='net_line',conn=c,line='ERR unknown-command STREAM'}}
 end
 if kind=='net_ready' and p.sending and p.sending.conn==c and p.sending.phase=='as' then
   assert(writes[#writes].s=='AS '..chat.identity()..'\n')
   p:poll{{type='net_line',conn=c,line='OK'}}
 end
end
local function complete(id,records,offset,ok)
 results[#results+1]={id=id,ok=ok~=false,records=records or {},offset=offset or 0}
 p:poll{}
end
event('net_ready',chat.ctrl)
event('net_line',chat.ctrl,'ROOM '..R..' room')
event('net_line',chat.ctrl,'END')
assert(chat.rooms[R],'room list loaded')
assert(p:subscribe(R));local c=chat.rooms[R].conn
assert(c)
event('net_ready',c);assert(p.blocked[c])
local initial=job_serial;complete(initial,{{offset=100,json='cached'}},100)
assert(writes[#writes].s=='READ '..R..' 100\n')
p:poll{{type='net_line',conn=c,line='MSG 200 4'},{type='net_line',conn=c,line='live'},{type='net_line',conn=c,line='END'}}
assert(#chat.rooms[R].buf==1 and p.blocked[c])
complete(job_serial,{},0)
assert(#chat.rooms[R].buf==2 and writes[#writes].s=='FOLLOW '..R..' 200\n')
-- Cache baseline and own sends never add unread. Selection is not reading.
assert(p:list()[1].unread==0)
sender=B
local function incoming(offset)
 event('net_line',c,'MSG '..offset..' 4');event('net_line',c,'live');complete(job_serial)
end
incoming(300);assert(p:list()[1].unread==1)
chat.select(R);p:reading(R,false);assert(p:list()[1].unread==1)
assert(p:notifications()==1)
assert(p:toggle_mute(R));assert(p:list()[1].muted and p:notifications()==0)
local _,attention=p:notifications()
incoming(400);assert(p:list()[1].unread==2)
local _,muted_attention=p:notifications();assert(attention==muted_attention)
p:reading(nil,true);assert(p:list()[1].unread==2,'ordinary document must not read chat')
p:reading(R,true);assert(p:list()[1].unread==0)
assert(chat.rooms[R].read_state.watermark==400)
assert(p:toggle_mute(R));incoming(500);incoming(500)
assert(p:list()[1].unread==1,'duplicate endpoint counted twice')
p:reading(R,true)
-- Shared files merge in the client; CAS conflicts refetch, mute stays local.
time=2;p:poll{};local fs=assert(p.file_sync);local fc=fs.conn
local FileSync=require 'workbench.filesync'
local State=require 'workbench.readstate'
event('net_ready',fc);event('net_line',fc,'OK')
assert(writes[#writes].s=='FGET self '..fs.path..'\n')
local remote=State.encode(700)
event('net_line',fc,'FILE '..fs.path..' 1 '..#remote..' '..FileSync.hex(remote))
event('net_line',fc,'END')
assert(not p.file_sync and chat.rooms[R].read_state.watermark==700)
assert(chat.rooms[R].read_state.muted==false)
assert(chat.rooms[R].newest_end==500,'shared read must not advance download cursor')
time=4;p:poll{};fs=assert(p.file_sync);fc=fs.conn
event('net_ready',fc);event('net_line',fc,'OK')
remote=State.encode(600)
event('net_line',fc,'FILE '..fs.path..' 2 '..#remote..' '..FileSync.hex(remote))
event('net_line',fc,'END')
assert(writes[#writes].s:match('^FPUT self .+ 2 '))
event('net_line',fc,'ERR conflict stale');assert(not p.file_sync)
-- Reset watermark for the independent pagination fixture below.
assert(chat.rooms[R].read_state:save(500,false))
-- Reopening must count beyond the 2000-record display window before READ resumes.
p:reconnect();event('net_ready',chat.ctrl);assert(p:subscribe(R))
c=chat.rooms[R].conn;event('net_ready',c)
local page={};for offset=1000,2999 do page[#page+1]={offset=offset,json='cached'} end
complete(job_serial,page,2999);assert(p.blocked[c])
complete(job_serial,{{offset=600,json='cached'},{offset=700,json='cached'}},2999)
assert(chat.rooms[R].unread==2002 and not p.blocked[c])
assert(writes[#writes].s=='READ '..R..' 2999\n')
p:reading(R,true);assert(chat.rooms[R].unread==0)
event('net_line',c,'END');sender=A
-- A dedicated send stream cannot consume unrelated ctrl ERR as an ACK.
assert(p:send(R,'/as '..B));local send=p.sending.conn
event('net_ready',send)
assert(writes[#writes].s=='SEND '..R..' '..cooloo.message_id()..' 68\n/as '..B)
event('net_line',chat.ctrl,'ERR internal unrelated metadata')
assert(p:delivery(R).state=='pending')
event('net_line',send,'OK 300 '..cooloo.message_id()..' 1');assert(p:delivery(R).state=='sent' and chat.identity()==A)
assert(p:send(R,'uncertain'));send=p.sending.conn;event('net_ready',send);event('net_closed',send)
assert(p:delivery(R).state=='unknown')
assert(p:send(R,'denied'));send=p.sending.conn;event('net_ready',send);event('net_line',send,'ERR forbidden read-only grant')
assert(not p:capabilities(R).can_send and not p:send(R,'again'))
p:reconnect();assert(p:capabilities(R).write_state=='allowed')
event('net_ready',chat.ctrl)
assert(p:send(R,'timeout'));time=time+21;p:poll{};assert(p:delivery(R).state=='rejected')
-- Async completion from an old identity must not leak into the new workspace.
assert(p:subscribe(R));c=chat.rooms[R].conn;event('net_ready',c);local stale=job_serial
assert(p:identity(B));complete(stale,{{offset=100,json='old identity'}},100)
assert(next(chat.rooms)==nil and next(p.subscriptions)==nil and not chat.registered)
event('net_line',c,'END');assert(next(chat.rooms)==nil)
-- More rooms than socket slots: selection can always replace the previous stream.
event('net_ready',chat.ctrl);event('net_line',chat.ctrl,'OK')
for i=1,30 do local id=('%064x'):format(i);chat.ensure_room(id);assert(p:subscribe(id)) end
local n=0;for _ in pairs(chat.by_conn)do n=n+1 end;assert(n<=12 and chat.rooms[p.selected].conn)
local visited={}
for tick=1,6 do
  for id,r in pairs(chat.rooms) do if r.conn then visited[id]=true;r.phase='following' end end
  time=time+6;p:poll{}
end
local seen=0;for _ in pairs(visited)do seen=seen+1 end
assert(seen>=30,'overflow subscriptions starved')
for id in pairs(p.subscriptions)do p:unsubscribe(id)end
assert(next(chat.by_conn)==nil)
-- A read denial following successful AS preserves an independent write grant.
p:identity(B);event('net_ready',chat.ctrl);event('net_line',chat.ctrl,'OK')
event('net_line',chat.ctrl,'ERR forbidden no read grant')
assert(chat.ctrl_up and chat.read_denied and not chat.auth_failed)
assert(p:address(R));assert(p:capabilities(R).can_send and not p:capabilities(R).can_read)
-- Mirror directories remain visible/readable, but cannot be send targets.
chat.read_denied=false
chat.metadata('{"id":"'..R..'","type":"user","nickname":"mirror","owner":"'..B..'","slot":1,"mirror":1}')
assert(p:capabilities(R).can_read and not p:capabilities(R).can_send)
assert(not p:send(R,'must not send to mirror'))
-- Periodic discovery, coalescing and permission reconciliation.
p:identity(A);event('net_ready',chat.ctrl)
local ctrl=chat.ctrl
local function requests(text)
 local n=0;for _,w in ipairs(writes)do if w.s==text then n=n+1 end end;return n
end
local count=requests('ROOMS\n')
assert(not p:refresh_rooms(),'overlapping ROOMS request')
event('net_line',ctrl,'ROOM '..R..' original');event('net_line',ctrl,'END')
time=time+5;p:poll{};assert(requests('ROOMS\n')==count+1)
local fresh=string.rep('d',64)
event('net_line',ctrl,'ROOM '..fresh..' new room');event('net_line',ctrl,'END')
assert(chat.rooms[fresh] and chat.rooms[R].denied)
assert(p:refresh_rooms());event('net_line',ctrl,'ROOM '..R..' renamed');event('net_line',ctrl,'END')
assert(not chat.rooms[R].denied and chat.rooms[R].nickname=='renamed')
-- Keep control and a synchronized room alive for over ten minutes.
assert(p:subscribe(R));c=chat.rooms[R].conn;event('net_ready',c);complete(job_serial,{},0)
event('net_line',c,'END')
for tick=1,22 do
 time=time+30;p:poll{}
 event('net_line',ctrl,'PONG');event('net_line',c,'PONG')
 event('net_line',ctrl,'ROOM '..R..' renamed');event('net_line',ctrl,'END')
 assert(chat.ctrl==ctrl and chat.rooms[R].conn==c)
end
assert(requests('PING\n')>=44)
assert(p:diagnostics().last_receive==time)
-- A missed heartbeat closes the stream instead of silently waiting forever.
time=time+30;p:poll{};event('net_line',ctrl,'ROOM '..R..' renamed');event('net_line',ctrl,'END')
time=time+60;p:poll{};assert(not conns[c])
p:close();assert(next(conns)==nil)
io.open=original_open
print('provider: read/focus/mute/attention, async checkpoint ordering, subscriptions/overflow, stale identity, send ACK/rejection/uncertainty/capabilities passed')
