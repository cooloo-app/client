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
chat.on_line(1,'ROOM '..R..' shared')
chat.on_line(1,'END')
chat.on_ready(2,'same')
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
chat.on_line(1,'NICK new-user')
assert(sent[#sent]=='ROOMS\n')
print('GUI state: cached history, incremental READ, JSON receive, persistence, nickname lookup and FOLLOW checkpoint passed')
