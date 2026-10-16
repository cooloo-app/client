-- Real adapter/state-machine with deterministic transport/cache boundaries.
package.path='modules/editor/?.lua;modules/editor/?/init.lua;modules/?.lua;modules/?/init.lua;./?.lua;./?/init.lua;'..package.path
global=function()end
package.preload['client.chat']=function()dofile('lua/chat.lua');return chat end
local A,B,R=string.rep('a',64),string.rep('b',64),string.rep('c',64)
local time,serial,job_serial=0,0,0
local conns,writes,jobs,results={},{},{},{}
cooloo={public_id=function()return A end,ensure_identity=function()return true end,server=function()return 'localhost',4222 end,
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
 record=function(json)return {ts=1,from=A,to=R,content=json}end}
local p=require('adapters.cooloo').new()
local function event(kind,c,line)p:poll{{type=kind,conn=c,line=line,nick='user',reason='test'}}end
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
event('net_ready',c);assert(writes[#writes].s=='METAFILE '..R..'\n')
local initial=job_serial;complete(initial,{{offset=100,json='cached'}},100)
assert(writes[#writes].s=='READ '..R..' 100\n')
p:poll{{type='net_line',conn=c,line='MSG 200 4'},{type='net_line',conn=c,line='live'},{type='net_line',conn=c,line='END'}}
assert(#chat.rooms[R].buf==1 and p.blocked[c])
complete(job_serial,{},0)
assert(#chat.rooms[R].buf==2 and writes[#writes].s=='FOLLOW '..R..' 200\n')
-- A dedicated send stream cannot consume unrelated ctrl ERR as an ACK.
assert(p:send(R,'/as '..B));local send=p.sending.conn
event('net_ready',send)
assert(writes[#writes].s=='SEND '..R..' 68\n/as '..B)
event('net_line',chat.ctrl,'ERR internal unrelated metadata')
assert(p:delivery(R).state=='pending')
event('net_line',send,'OK 300');assert(p:delivery(R).state=='sent' and chat.identity()==A)
assert(p:send(R,'uncertain'));send=p.sending.conn;event('net_ready',send);event('net_closed',send)
assert(p:delivery(R).state=='unknown')
assert(p:send(R,'denied'));send=p.sending.conn;event('net_ready',send);event('net_line',send,'ERR forbidden read-only grant')
assert(not p:capabilities(R).can_send and not p:send(R,'again'))
p:reconnect();assert(p:capabilities(R).write_state=='allowed')
event('net_ready',chat.ctrl)
assert(p:send(R,'timeout'));time=21;p:poll{};assert(p:delivery(R).state=='rejected')
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
p:close();assert(next(conns)==nil)
print('provider: async checkpoint ordering, subscriptions/overflow, stale identity, send ACK/rejection/uncertainty/capabilities passed')
