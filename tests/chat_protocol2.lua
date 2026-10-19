-- GUI state-machine test without SDL, using the same chat.lua as the GUI.
local sent, cached = {}, {}
local A, R = string.rep('a',64), string.rep('b',64)
cooloo = {
    config={get=function()end,set=function()return true end},
    public_id=function()return A end,
    net={fp=function()return string.rep('c',64)end,
         send=function(conn,s)sent[#sent+1]=s;return true end,
         connect=function()return 2 end,close=function()end},
    cache_read=function(server,self,room,cb)
        cb(200,'cached');return true
    end,
    cache_offset=function()return 200 end,
    cache_append=function(server,self,room,off,json)
        cached[#cached+1]={off,json};return true
    end,
    cache_meta=function()return true end,
    record=function(s)
        return {ts=123,from=A,to=R,content=s}
    end,
}
dofile('lua/chat.lua')
chat.ctrl=1
chat.on_ready(1,'same')
assert(sent[#sent]=='IDENTITY\n' and not chat.ctrl_up)
chat.on_line(1,'IDENTITY '..A..' '..A)
chat.on_line(1,'ROOM '..R..' shared')
chat.on_line(1,'END')
chat.on_ready(2,'same')
chat.on_line(2,'IDENTITY '..A..' '..A)
assert(sent[#sent]=='READ '..R..' 200\n')
assert(#chat.rooms[R].buf==1)
chat.on_line(2,'MSG 400 4')
chat.on_line(2,'live')
assert(#cached==1 and cached[1][1]==400)
assert(#chat.rooms[R].buf==2)
chat.on_line(2,'END')
assert(sent[#sent]=='FOLLOW '..R..' 400\n')
chat.on_line(1,'INFO '..A..' user - 000 same')
assert(chat.rooms[R].buf[2].nick=='same')
-- A new identity must refresh ROOMS after HELLO (its inbox did not exist yet).
chat.registered=false
chat.on_ready(1,'')
chat.on_line(1,'IDENTITY '..A..' '..A)
chat.on_line(1,'NICK new-user')
assert(sent[#sent]=='ROOMS\n')
-- Explicit window identity handshake precedes ALL reads/sends/cache use.
local owner = string.rep('d',64)
assert(chat.use_identity(owner))
chat.on_ready(2,'same')
assert(sent[#sent]=='AS '..owner..'\n' and not chat.ctrl_up)
chat.on_line(2,'OK')
assert(sent[#sent]=='IDENTITY\n')
chat.on_line(2,'IDENTITY '..A..' '..owner)
assert(sent[#sent]=='ROOMS\n' and chat.ctrl_up)
chat.on_line(2,'ROOM '..R..' delegated-room')
chat.sel=R
assert(chat.send_text('as owner'))
assert(sent[#sent]=='SEND '..R..' 8\nas owner')
assert(chat.identity()==owner)
-- Denied AS never silently falls back to B.
assert(chat.use_identity(owner))
chat.on_ready(2,'same')
chat.on_line(2,'ERR forbidden revoked')
assert(chat.auth_failed and not chat.ctrl_up)
assert(not chat.send_text('must not send'))
assert(chat.send_text('/self'))
assert(chat.identity()==A)
-- Filtered sent view cannot advance the inbox checkpoint or enter its cache.
local inbox=chat.ensure_room(A)
inbox.newest_end=200
chat.sent_conns={[9]={peer=R,room=inbox}}
cooloo.record=function()return {ts=123,from=A,to=R,content='outgoing'}end
local old_count=#cached
chat.on_line(9,'MSG 900 8')
chat.on_line(9,'outgoing')
assert(inbox.newest_end==200 and #cached==old_count)
assert(#inbox.buf==1 and inbox.buf[1].sent)
chat.on_line(9,'END 1200')
assert(chat.sent_conns[9]==nil)
-- A mirror discovers its default parent without an explicit /as.
chat.use_identity(nil);chat.on_ready(chat.ctrl,'mirror')
chat.on_line(chat.ctrl,'IDENTITY '..A..' '..owner)
assert(chat.identity()==owner and chat.ctrl_up)
chat.reconnect();chat.on_ready(chat.ctrl,'mirror')
chat.on_line(chat.ctrl,'IDENTITY '..A..' '..A)
assert(chat.auth_failed and not chat.ctrl_up) -- detach cannot reuse old cache/view
print('GUI state: default mirror discovery, explicit identity, fail-closed change, sparse sent cache and FOLLOW checkpoints passed')
