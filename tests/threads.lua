package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;'..package.path
local T=require 'workbench.threads'
local project=require('workbench.messages').project
local function uuid(n) return ('%08x000040008000000000000000'):format(n) end
local root=uuid(1)
assert(T.uuid(root) and not T.uuid(root:upper()..'x'))
local header=T.header(root,'body')
assert(T.parse(header)==root)
assert(T.parse(header:gsub('\n','\r\n'))==root)
for _,raw in ipairs{'\\'..header,'```\n'..header,header:gsub('/1','/2'),header:gsub('\n\n','\n'),(header:gsub('4000','5000'))} do
  local ref,body=T.parse(raw);assert(not ref and body==raw)
end
assert(T.prepare(' \n\t hello\n\n  world \r\n ' )=='hello\n\n  world')
assert(T.prepare('  '..T.header(root,' \n hi \n '))==T.header(root,'hi'))
assert(not T.prepare(T.header(root,' \n ')))
assert(not T.prepare(' \t\r\n'))
local index=T.index()
local a={id=root,ts=1,from='A',text='root',context='peer',target='peer'}
local b={id=uuid(3),ts=3,from='B',text=T.header(root,'later'),context='peer'}
local c={id=uuid(2),ts=3,from='C',text=T.header(root,'earlier'),context='peer'}
for _,m in ipairs{b,c,a,b} do index:add(m) end
assert(index:count(a)==2)
local snapshot={id=a.id,text=a.text,from=a.from,ts=a.ts,context=a.context}
assert(#project({snapshot},{thread_index=index}).ranges==3,'provider snapshots differ from indexed tables')
local p=project({b,a,c},{thread_index=index})
assert(p.ranges[1].id==root and p.ranges[2].id==c.id and p.ranges[3].id==b.id)
assert(not p.text:find('@thread',1,true) and not p.text:find('│',1,true))
assert(p.decorations[p.anchors[b.id]] and p.ranges[2].raw==c.text)
assert(#project({b},{thread_index=index}).ranges==3,'off-window root and cached replies materialized')
assert(T.at(p.ranges,p.anchors[b.id],p.anchors[b.id]).id==b.id)
assert(not T.at(p.ranges,1,p.anchors[b.id]))
local forged={id=uuid(4),text=T.header(root,'forged'),context='other'}
index:add(forged);assert(not index:root(forged) and index:count(a)==2)
local nested={id=uuid(5),text=T.header(b.id,'nested'),context='peer'}
index:add(nested);assert(not index:root(nested))
local selfref={id=uuid(6),text=T.header(uuid(6),'self')};index:add(selfref);assert(not index:root(selfref))
assert(project({b}).text:find('原消息未加载/不可用',1,true))
local blank=T.header(root,'');assert(T.parse(blank)==root)
-- Workspace send boundary, inbox routing, trim/ACK comparison, 9 soft cap.
SCALE=1;system={get_time=os.clock};package.loaded.core={add_thread=function()end}
local messages={a};local delivery;local sent={};local serial=20
local provider={open=function()return messages end,thread_index=function()return index end,
 delivery=function()return delivery end,send=function(_,id,text)
   serial=serial+1;delivery={state='pending',message_id=uuid(serial),text=text}
   sent[#sent+1]={id=id,text=text};return true
 end}
local w=require('plugins.workspace.model').new(provider)
local _,draft=w:select('inbox')
assert(w:reply('inbox',b.id))
assert(T.parse(draft:get_text(1,1,#draft.lines,#draft.lines[#draft.lines]))==root)
draft:set_projection(T.header(root,' \n hello \n '))
assert(w:send('inbox'));assert(sent[1].id=='peer' and sent[1].text==T.header(root,'hello'))
assert(not w:send('inbox'))
delivery.state='sent';w:refresh();assert(draft.lines[1]=='\n')
for n=7,11 do index:add{id=uuid(n),text=T.header(root,'reply'),context='peer'} end
assert(index:count(a)==7)
draft:set_projection(T.header(root,'ninth'))
assert(w:send('inbox')) -- seven cached + one ACK reservation -> ninth
delivery.state='sent';w:refresh()
draft:set_projection(T.header(root,'tenth'))
local before=table.concat(draft.lines);local count=#sent
assert(not w:send('inbox') and #sent==count and before==table.concat(draft.lines))
-- Ordinary sends are independent; edits after send survive ACK.
draft:set_projection(' \n ordinary \n ');assert(w:send('inbox'))
assert(sent[#sent].text=='ordinary')
draft:text_input('edited');delivery.state='sent';w:refresh();assert(draft.lines[1]~='\n')
-- Incremental worker paging indexes records outside the display window.
local jobs={};local chat={rooms={room={server_fp='s',buf={a}}},identity=function()return 'self' end}
local cache=require('adapters.cooloo.threadcache').new(chat,function(_,_,before,limit,done)
  assert(limit==200);jobs[#jobs+1]={before=before,done=done}
end,function(v)return v end)
local ix=cache:get('room');assert(not ix.ready)
local page={};for n=1,200 do page[n]={offset=n+200,json={id=uuid(n+100),from='peer',content='old'}} end
jobs[1].done(true,page);assert(#jobs==2 and jobs[2].before==201)
jobs[2].done(true,{{offset=1,json={id=uuid(400),from='peer',content=T.header(root,'old reply')}}})
assert(ix.ready and ix.messages[uuid(400)])
cache:reset();assert(cache.indexes.room==nil)
-- Incoming and sent private records share only their actual peer context.
local dmchat={rooms={self={buf={}}},identity=function()return 'self' end}
local dm=require('adapters.cooloo.threadcache').new(dmchat,function()end,function(v)return v end)
local incoming=dm:message('self',{id=root,from='peer',content='root'})
local outgoing=dm:message('self',{id=uuid(600),from='self',to='peer',content=T.header(root,'reply')})
local other=dm:message('self',{id=uuid(601),from='other',content=T.header(root,'spoof')})
local di=T.index();di:add(incoming);di:add(outgoing);di:add(other)
assert(incoming.target=='peer' and outgoing.context==incoming.context)
assert(di:root(outgoing)==incoming and not di:root(other))
-- Unknown ninth can only retry the same payload/UUID, not allocate a tenth.
local ui=T.index();ui:add(a)
for n=700,707 do ui:add{id=uuid(n),context='peer',text=T.header(root,'cached')} end
local unknown={state='unknown',text=T.header(root,'retry'),message_id=uuid(708)}
local calls=0
local up={open=function()return {a} end,thread_index=function()return ui end,
 delivery=function()return unknown end,send=function(_,_,value)
  assert(value==unknown.text);calls=calls+1;return true
 end}
local uw=require('plugins.workspace.model').new(up);local _,ud=uw:select('inbox')
ud:set_projection(T.header(root,'different'));assert(not uw:send('inbox') and calls==0)
ud:set_projection(unknown.text);assert(uw:send('inbox') and calls==1)
print('threads: grammar, projection, privacy, history paging, inbox routing, trim/ACK, 9-cap OK')
