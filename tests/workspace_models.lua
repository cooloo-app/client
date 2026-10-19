-- Pure Lua model checks. No window, renderer, event loop, DocView or SDL.
package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;'..package.path
SCALE=1
system={get_time=os.clock}
package.loaded.core={add_thread=function() end}
local tree=require 'plugins.workspace.tree'
local rooms={{id='1',name='A:B'},{id='2',name='A:C'},{id='3',name='A'},
  {id='4',name='A:B'},{id='5',name=':literal'},{id='6',name=''}}
local rows=tree.build(rooms,{})
local found={};local a
for _,r in ipairs(rows) do
  if r.room then assert(not found[r.room.id]);found[r.room.id]=true end
  if r.label=='A' then a=r;assert(r.room.id=='3' and r.branch) end
end
for _,r in ipairs(rooms) do assert(found[r.id],r.id) end
local folded=tree.build(rooms,{[a.key]=true})
assert(#folded==3)
assert(tree.build({{id='x',name='A::B'}},{})[1].label=='A::B')

local p={subscriptions={},sent={},deliveries={},messages={},revisions={}}
function p:subscribe(id) self.subscriptions[id]=true end
function p:unsubscribe(id) self.subscriptions[id]=nil end
function p:open(id) return self.messages[id] or {} end
function p:revision(id) return self.revisions[id] or 0 end
function p:send(id,text)
  self.sent[#self.sent+1]={id=id,text=text};self.deliveries[id]={state='pending'};return true
end
function p:delivery(id) return self.deliveries[id] end
local w=require('plugins.workspace.model').new(p)
local ma,da=w:select('a');da:text_input('first')
local mb,db=w:select('b');db:text_input('second')
assert(p.subscriptions.a and p.subscriptions.b)
assert(w:send('a'));assert(p.sent[1].id=='a' and p.sent[1].text=='first')
assert(not w:send('a') and #p.sent==1)
da:text_input(' edited');p.deliveries.a.state='sent';w:refresh()
assert(da.lines[1]=='first edited\n')
assert(w:send('b'));p.deliveries.b.state='rejected';w:refresh();assert(db.lines[1]=='second\n')
assert(w:send('b'));p.deliveries.b.state='unknown';w:refresh();assert(db.lines[1]=='second\n')
assert(w:send('b'));p.deliveries.b.state='sent';w:refresh();assert(db.lines[1]=='\n')
assert(w:send('a'));da:remove(1,1,1,#da.lines[1]);da:text_input('first edited')
p.deliveries.a.state='sent';w:refresh();assert(da.lines[1]=='first edited\n','retyped same text is a new draft')
p.messages.a={{id='m',from='peer',text='background',ts=0}};p.revisions.a=1
w:refresh();assert(ma.projection:find('background',1,true),'background room refresh')
w:release('a');assert(not p.subscriptions.a and p.subscriptions.b)
assert(w:has_unsent());local _,reopened=w:select('a');assert(reopened==da)
w:reset();assert(not w:has_unsent() and not next(p.subscriptions))
assert(ma.projection=='' and da.lines[1]=='\n' and mb.projection=='')

local fs={}
local dirs={['/work']={'folder','file.lua','loop','broken'},['/work/folder']={'nested.lua'}}
function fs.absolute_path(path)
  if path=='/work/loop' then return '/work' end
  if path=='/work/broken' then return nil,'broken' end
  return path
end
function fs.get_file_info(path)
  if path=='/work/loop' or dirs[path] then return {type='dir'} end
  if path:match('%.lua$') then return {type='file'} end
  return nil,'missing'
end
function fs.list_dir(path) return dirs[path], 'unavailable' end
local f=require('plugins.workspace.files').new(fs)
assert(not f:bind('a','/missing'))
assert(f:bind('a','/work'))
while f:step() do end
local folder
for _,row in ipairs(f.rows) do
  if row.label=='folder' then folder=row end
  if row.path=='/work/loop' then assert(not row.branch) end
end
assert(#f.rows==4 and folder.branch)
f:toggle(folder);while f:step() do end;assert(#f.rows==5)
f:select('b');assert(not f.root and #f.rows==0)
f:select('a');while f:step() do end;assert(f.root=='/work')
f:reset();assert(not next(f.bindings) and #f.rows==0)
assert(not _G.renderer and not package.loaded['core.docview'])
print('workspace models: tree IDs, background refresh, draft/ACK isolation, bindings and link traversal OK')
