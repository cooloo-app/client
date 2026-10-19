-- Composition adapter: protocol offsets and durable cache jobs never escape here.
global{chat=false}
local chat=require 'client.chat'
local M={}
function M.new()
  local p={status='connecting',trust={},jobs={},blocked={},deferred={},subscriptions={},epoch=0,
    deliveries={},permissions={},closed=false,clock=cooloo.time}
  assert(cooloo.ensure_identity())
  -- Bound streams independently of the number of listed conversations. Only
  -- explicit subscribers consume sockets; selected conversation has priority.
  chat.subscriptions={}
  local function close_room(r)
    for c,s in pairs(chat.sent_conns or {}) do
      if s.room==r then cooloo.net.close(c);chat.sent_conns[c]=nil end
    end
    if r and r.conn then
      local c=r.conn;cooloo.net.close(c);chat.by_conn[c]=nil
      chat.on_closed(c,'unsubscribed')
      r.conn=nil;r.pending=nil;r.following=false;r.phase='idle';r.lease_started=nil
      p.blocked[c]=nil;p.deferred[c]=nil;p.trust[c]=nil
    end
  end
  local function job(kind,r,a,b,callback)
    local id,err=cooloo.cache_async.submit(kind,r.server_fp,r.self_id,r.name,a,b)
    if not id then callback(false,{},-1);return false,err end
    p.jobs[id]={epoch=p.epoch,callback=callback};return true
  end
  chat.load_cache=function(r,done)
    local c=r.conn;p.blocked[c]=true;cooloo.net.pause(c,true)
    job('read',r,nil,2000,function(ok,records,offset)
      done(ok,records,offset);p.blocked[c]=nil;cooloo.net.pause(c,false)
    end)
  end
  chat.persist=function(r,offset,json,done)
    local c=r.conn;p.blocked[c]=true;cooloo.net.pause(c,true)
    job('append',r,offset,json,function(ok)
      done(ok);p.blocked[c]=nil;cooloo.net.pause(c,false)
    end)
  end
  chat.metadata=function(meta)
    -- Parse only canonical structural fields, not nickname text or executable Lua.
    local id,kind=meta:match('^%{"id":"([0-9a-f]+)","type":"([a-z]+)"')
    if not id then return end
    local r=chat.rooms[id];if r then r.kind=kind end
    job('meta',{server_fp=cooloo.net.fp(chat.ctrl),self_id=chat.identity(),name=id},0,meta,function(ok)
      if not ok then chat.status='metadata cache failure' end
    end)
  end
  chat.init(cooloo.server());chat.connect_ctrl()
  -- Match cfg_dir/cache_path without exposing credentials or changing cache formats.
  function p:directory(id)
    local r=chat.rooms[id]
    local server=r and r.server_fp or (chat.ctrl_up and cooloo.net.fp(chat.ctrl))
    local identity=chat.identity()
    local function valid(value) return type(value)=='string' and #value==64 and value:match('^[0-9a-f]+$') end
    if not valid(server) or not valid(identity) or not valid(id) then
      return nil,'Waiting for authenticated conversation directory'
    end
    local base=os.getenv('COOLOO_CONFIG')
    if not base or base=='' then
      local home=os.getenv('HOME') or (package.config:sub(1,1)=='\\' and os.getenv('USERPROFILE'))
      if not home then return nil,'Configuration directory unavailable' end
      base=home..'/.cooloo'
    end
    return base:gsub('[/\\]+$','')..'/cache/'..server..'/'..identity..'/rooms/'..id
  end
  function p:prepare_directory(id)
    local root=self:directory(id)
    if not root then return end
    self.directory_jobs=self.directory_jobs or {}
    if self.directory_jobs[root]==self.epoch then return end
    local server,identity=root:match('/cache/([0-9a-f]+)/([0-9a-f]+)/rooms/[^/]+$')
    self.directory_jobs[root]=self.epoch
    -- The existing cache reader creates missing room directories on its worker.
    -- This also supports an addressed send-only conversation without METAFILE.
    job('read',{server_fp=server,self_id=identity,name=id},nil,1,function()
      self.directory_jobs[root]=nil
    end)
  end
  function p:capabilities(id)
    local r=chat.rooms[id]
    local permission=self.permissions[id] or {}
    local online=not self.closed and chat.ctrl_up and chat.registered and not chat.auth_failed
    local readable=r and not r.denied and not chat.read_denied -- ROOMS lists readable rooms / own inbox
    return {can_read=not not readable,can_send=not not (r and online and not permission.write_denied),
      can_history=not not (readable and r.server_fp),
      write_state=permission.write_denied and 'denied' or (chat.effective and not permission.write_verified and 'unverified' or 'allowed'),
      reason=permission.reason or (not online and 'offline or unregistered' or nil)}
  end
  function p:list()
    local rooms={}
    for _,id in ipairs(chat.order) do
      local r=chat.rooms[id];local caps=self:capabilities(id)
      rooms[#rooms+1]={id=id,name=r.nickname or id,can_send=caps.can_send,can_read=caps.can_read,
        capabilities=caps,unread=r.unread,subscribed=self.subscriptions[id]~=nil}
    end
    return rooms
  end
  function p:schedule()
    if self.closed or chat.read_denied then
      for _,r in pairs(chat.rooms) do close_room(r) end
      chat.subscriptions={};return
    end
    local wanted={};local count=0
    local now=self.clock()
    if self.selected and self.subscriptions[self.selected] then wanted[self.selected]=true;count=1 end
    for id,r in pairs(chat.rooms) do
      if id~=self.selected and r.conn and r.lease_started and now-r.lease_started>=30 then
        self.subscriptions[id]=now;close_room(r)
      end
    end
    -- Do not evict a partially synchronized stream. Initial catch-up must reach
    -- its durable checkpoint before a lease rotates; selection still preempts.
    for id,r in pairs(chat.rooms) do
      if count<12 and self.subscriptions[id] and r.conn and not wanted[id] and
          (r.phase~='following' or self.blocked[r.conn] or #(self.deferred[r.conn] or {})>0) and
          now-(r.lease_started or now)<30 then wanted[id]=true;count=count+1 end
    end
    -- FIFO subscriptions; overflow rotates after a completed five-second lease.
    local ids={};for id,stamp in pairs(self.subscriptions) do ids[#ids+1]={id=id,stamp=stamp} end
    table.sort(ids,function(a,b)return a.stamp==b.stamp and a.id<b.id or a.stamp<b.stamp end)
    for _,entry in ipairs(ids) do
      if count>=12 then break end
      local id=entry.id
      if not wanted[id] then wanted[id]=true;count=count+1 end
    end
    for id,r in pairs(chat.rooms) do if not wanted[id] then close_room(r) end end
    chat.subscriptions=wanted;chat.start_follows()
    for id in pairs(wanted) do
      local r=chat.rooms[id];if r and r.conn and not r.lease_started then r.lease_started=now end
    end
  end
  function p:subscribe(id)
    if self.closed or not chat.rooms[id] then return false,'unknown conversation' end
    if not chat.rooms[id].metadata_requested and chat.ctrl_up and not chat.read_denied then
      chat.rooms[id].metadata_requested=true;cooloo.net.send(chat.ctrl,'METAFILE '..id..'\n')
    end
    self.suppressed=self.suppressed or {};self.suppressed[id]=nil
    self.subscriptions[id]=self.subscriptions[id] or self.clock()
    self.selected=id;chat.select(id);self:schedule();return true
  end
  function p:unsubscribe(id)
    self.suppressed=self.suppressed or {};self.suppressed[id]=true
    self.subscriptions[id]=nil
    if self.selected==id then self.selected=nil end
    local current=self.selected
    close_room(chat.rooms[id]);self:schedule()
    if current then chat.select(current) end
  end
  function p:revision(id) local r=chat.rooms[id];return r and (r.revision or 0) or 0 end
  function p:address(id)
    if #id~=64 or not id:match('^[0-9a-f]+$') then return false,'invalid address ID' end
    chat.ensure_room(id);return true
  end
  function p:open(id)
    local r=chat.rooms[id];local messages={}
    for _,m in ipairs(r and r.buf or {}) do
      messages[#messages+1]={id=(m.to or id)..':'..tostring(m.endoff),from=m.nick,text=m.text,ts=m.ts}
    end
    return messages
  end
  local function finish(state,detail)
    local s=p.sending;if not s then return end
    p.deliveries[s.room]={state=state,detail=detail,text=s.text}
    if s.conn then cooloo.net.close(s.conn);p.trust[s.conn]=nil end
    p.sending=nil
  end
  function p:send(id,text)
    if self.sending then return false,'previous send still awaiting acknowledgment' end
    local caps=self:capabilities(id)
    if not caps.can_send then return false,caps.reason or 'send unavailable' end
    if #text==0 or #text>4096 or text:find('%z') or not utf8.len(text) then return false,'message must contain 1..4096 UTF-8 bytes without NUL' end
    local c,err=cooloo.net.connect(chat.host,chat.port)
    if not c then return false,err end
    self.sending={conn=c,room=id,text=text,phase='connecting',deadline=self.clock()+20}
    self.deliveries[id]={state='pending',detail='connecting; not delivered',text=text}
    return true,'pending; draft retained until acknowledgment'
  end
  function p:delivery(id) return self.deliveries[id] end
  function p:earlier(id)
    local r=chat.rooms[id]
    if r and r.conn and (self.blocked[r.conn] or #(self.deferred[r.conn] or {})>0) then return {},'history waits for current cache write' end
    if not self:capabilities(id).can_history then return {},'history unavailable' end
    if r.history_pending then return {},'history already loading' end
    if #r.buf>=10000 then return {},'history display limit: 10000 messages; use CLI for full history' end
    local before=math.huge
    for _,m in ipairs(r.buf) do if not m.sent then before=math.min(before,m.endoff) end end
    if before==math.huge then before=nil end
    r.history_pending=true
    job('read',r,before,math.min(200,10000-#r.buf),function(ok,records)
      r.history_pending=false
      if not ok then self.history_status='history cache read failed';return end
      local all={}
      for _,v in ipairs(records) do
        local m=cooloo.record(v.json)
        if m and not r.ends[v.offset] then
          all[#all+1]={endoff=v.offset,ts=m.ts,nick=(chat.names or {})[m.from] or m.from,from=m.from,text=m.content}
          r.ends[v.offset]=true
        end
      end
      for _,m in ipairs(r.buf) do all[#all+1]=m end
      table.sort(all,function(a,b)
        if id~=chat.identity() then return a.endoff<b.endoff end
        if a.ts~=b.ts then return a.ts<b.ts end
        if (a.to or id)~=(b.to or id) then return (a.to or id)<(b.to or id) end
        return a.endoff<b.endoff
      end)
      r.buf=all;r.revision=(r.revision or 0)+1;r.display_cap=math.min(10000,math.max(2000,#all+200))
      self.history_status=#records==0 and 'no earlier cached messages' or 'earlier cached messages loaded'
    end)
    return {},'loading earlier cached messages'
  end
  local function process(e)
    local s=p.sending
    if s and e.conn==s.conn then
      if e.type=='net_ready' then
        if chat.effective then s.phase='as';cooloo.net.send(s.conn,'AS '..chat.effective..'\n')
        else s.phase='ready' end
      elseif e.type=='net_line' then
        if s.phase=='as' and e.line=='OK' then s.phase='ready'
        elseif s.phase=='sent' and e.line:match('^OK %d+$') then
          p.permissions[s.room]={write_verified=true};finish('sent',e.line)
        elseif e.line:match('^ERR ') then
          if e.line:match('^ERR forbidden') then p.permissions[s.room]={write_denied=true,reason=e.line} end
          finish('rejected',e.line)
        end
      elseif e.type=='net_closed' then finish(s.phase=='sent' and 'unknown' or 'rejected',e.reason)
      elseif e.type=='net_tofu' then p.trust[e.conn]=e.fp end
      if p.sending and s.phase=='ready' then
        s.phase='sent'
        if not cooloo.net.send(s.conn,('SEND %s %d\n'):format(s.room,#s.text)..s.text) then
          finish('unknown','transport write failed; do not blindly retry')
        end
      end
      return
    end
    if e.conn~=chat.ctrl and not chat.by_conn[e.conn] and not (chat.sent_conns or {})[e.conn] then return end
    if e.type=='net_ready' then chat.on_ready(e.conn,e.nick)
    elseif e.type=='net_line' then chat.on_line(e.conn,e.line)
    elseif e.type=='net_closed' then
      p.trust[e.conn]=nil;p.blocked[e.conn]=nil;p.deferred[e.conn]=nil
      chat.on_closed(e.conn,e.reason)
    elseif e.type=='net_tofu' then p.trust[e.conn]=e.fp end
  end
  function p:poll(events)
    if self.closed then return end
    for _,result in ipairs(cooloo.cache_async.poll()) do
      local j=self.jobs[result.id];self.jobs[result.id]=nil
      if j and j.epoch==self.epoch then j.callback(result.ok,result.records,result.offset) end
    end
    -- Drain at most one cached frame's deferred lines per stream; a durable
    -- append pauses the stream again. END/FOLLOW cannot overtake persistence.
    for c,q in pairs(self.deferred) do
      local q=self.deferred[c] or {}
      while not self.blocked[c] and #q>0 do process(table.remove(q,1)) end
      if #q==0 then self.deferred[c]=nil end
    end
    for _,e in ipairs(events or {}) do
      if e.type:match('^net_') then
        if self.blocked[e.conn] and e.type~='net_closed' then
          local q=self.deferred[e.conn] or {};self.deferred[e.conn]=q;q[#q+1]=e
        else process(e) end
      end
    end
    if self.sending and self.clock()>self.sending.deadline then
      finish(self.sending.phase=='sent' and 'unknown' or 'rejected','request timed out; no automatic resend')
    end
    local now=self.clock()
    -- One bounded background subscription per listed conversation, admitted
    -- incrementally. Explicit unsubscribe suppresses automatic resubscription.
    if chat.rooms_loaded and not chat.read_denied then
      self.suppressed=self.suppressed or {}
      for _,id in ipairs(chat.order) do
        if not self.subscriptions[id] and not self.suppressed[id] then self.subscriptions[id]=now;break end
      end
    end
    for id,stamp in pairs(self.subscriptions) do
      local r=chat.rooms[id]
      if id~=self.selected and now-stamp>=5 and r and r.phase=='following' then
        self.subscriptions[id]=now
        if r.lease_started and now-r.lease_started>=5 then r.lease_started=now end
      end
    end
    if now>=(self.retry_at or 0) then
      self.retry_at=now+2
      if not chat.auth_failed and not chat.ctrl then chat.connect_ctrl() end
      self:schedule()
    end
    self.status=(self.history_status or '')..' '..chat.status
    if chat.read_denied then self.status=self.status..' | read denied; explicit destination may still allow send' end
    if not chat.registered and chat.ctrl_up then self.status=self.status..' | Workspace: Register' end
    if next(self.trust) then self.status='Trust required: Workspace: Trust Server' end
    self.identity_label='effective '..tostring(chat.identity())..' / login '..tostring(cooloo.public_id())
  end
  function p:trust_server()
    for c,fp in pairs(self.trust) do
      if system.show_confirm_dialog('Trust server?', 'Verify fingerprint before trusting:\n'..fp) then cooloo.net.trust(c)
      else cooloo.net.close(c);process{type='net_closed',conn=c,reason='trust declined'} end
      self.trust[c]=nil
    end
  end
  function p:register(nick)
    if #nick<1 or #nick>64 or nick:find('[\r\n%z]') or not utf8.len(nick) then return false,'invalid nickname' end
    if not chat.ctrl_up then return false,'not connected' end
    chat.register(nick);return true
  end
  local function reset()
    if p.sending then finish(p.sending.phase=='sent' and 'unknown' or 'rejected','connection reset') end
    p.epoch=p.epoch+1;p.jobs={};p.blocked={};p.deferred={};p.trust={};p.permissions={};p.history_status=nil
    for _,r in pairs(chat.rooms) do r.history_pending=false;r.metadata_requested=false;r.lease_started=nil end
  end
  function p:identity(id)
    if id and (#id~=64 or not id:match('^[0-9a-f]+$')) then return false end
    reset();self.deliveries={};self.subscriptions={};self.suppressed={};self.selected=nil;chat.subscriptions={}
    return chat.use_identity(id)
  end
  function p:reconnect() reset();chat.reconnect();self:schedule() end
  function p:close()
    reset();chat.close_all();self.closed=true;self.subscriptions={};chat.subscriptions={}
  end
  return p
end
return M
