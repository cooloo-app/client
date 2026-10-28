local core = require 'core'
local command = require 'core.command'
local translate = require 'core.doc.translate'
local function text(d) return table.concat(d.lines):sub(1,-2) end
local function fresh(s)
  local d=core.open_doc(); core.root_view:open_doc(d)
  d:text_input(s or ''); d:clean(); return d,core.active_view
end
local function cmd(n) assert(command.perform(n), n) end
local function batch(s)
  local queue={{'textinput',s},{'keypressed','return'}}
  local i,poll=0,system.poll_event
  system.poll_event=function() i=i+1; if queue[i] then return table.unpack(queue[i]) end end
  core.step(); system.poll_event=poll
end
local function submit(s) core.command_view:set_text(s); cmd('command:submit') end
local n=tonumber(os.getenv('REVIEW2_CASE'))
core.log_items={}
if n==1 then
  local d=fresh('valuable'); d:text_input(' unsaved'); cmd('root:close'); batch('s')
  assert(core.active_view==core.command_view and core.command_view.label=='Save As: ')
  assert(#core.get_views_referencing_doc(d)==1 and d:is_dirty())
  cmd('command:escape')
  assert(#core.get_views_referencing_doc(d)==1 and d:is_dirty())
elseif n==2 then
  local ac=require 'plugins.autocomplete'
  ac.map={}; ac.add{name='test',items={foobar=true}}
  local b,bv=fresh('xyz'); fresh(); core.root_view:on_text_input('foo')
  core.set_active_view(bv)
  assert(not command.perform('autocomplete:complete')); assert(text(b)=='xyz')
  fresh(); core.root_view:on_text_input('foo'); core.set_active_view(bv); core.root_view:update()
  assert(not command.perform('autocomplete:complete')); assert(text(b)=='xyz')
  local a=fresh(); core.root_view:on_text_input('foo'); cmd('autocomplete:complete'); assert(text(a)=='foobar')
  fresh(); core.root_view:on_text_input('foo'); core.active_view.doc:insert(1,1,'x')
  assert(not command.perform('autocomplete:complete'))
elseif n==3 then
  for _,s in ipairs({'你好世界\n再见世界','hello 中文\n世界 again','// 你好\n// 世界','你好\n\n世界'}) do
    local d=fresh(s); cmd('reflow:reflow')
    assert(utf8.len(text(d)))
    for token in s:gmatch('[^%s/]+') do assert(text(d):find(token,1,true),token) end
    assert(text(d):find('世界',1,true))
    if s:find('再见',1,true) then assert(text(d):find('再见世界',1,true)) end
    if s:find('//',1,true) then assert(text(d):match('^// ')) end
  end
elseif n==4 then
  for _,sep in ipairs({'，',',','%','[','::','。'}) do
    local s='a'..sep..'b\nc'..sep..'d'
    local d=fresh(s); d:set_selection(1,1,2,math.huge)
    cmd('tabularize:tabularize'); submit(sep)
    assert(text(d)==s, string.format('%q',text(d))); assert(utf8.len(text(d)))
  end
elseif n==5 then
  local d=fresh('session'); d:save('session.txt'); cmd('root:split-right')
  core.root_view.size.x=960; core.root_view.size.y=640; core.root_view:update()
  local node=core.root_view:get_active_node(); local parent=node:get_parent_node(core.root_view.root_node)
  core.root_view.dragged_divider=parent
  core.root_view:on_mouse_moved(0,0,-parent.size.x*0.48,0); core.root_view.dragged_divider=nil
  assert(parent.divider>=0.01 and parent.divider<0.05)
  local layout=require 'core.session_layout'
  for _,ratio in ipairs({parent.divider,0.01,0.99,0.98,0.5}) do
    parent.divider=ratio
    local saved,path=layout.capture(parent,layout.file)
    local root=require('core.rootview')().root_node
    assert(layout.restore(root,saved,path,layout.open_file)); assert(root.divider==ratio)
  end
elseif n==6 then
  local function write(p) local f=assert(io.open(p,'wb')); f:write(p); f:close() end
  write('alpha.txt'); write('beta.txt')
  core.project_files={{filename='alpha.txt',type='file'},{filename='beta.txt',type='file'}}
  fresh(); cmd('core:find-file'); core.command_view:set_text('alpha'); core.command_view:update_suggestions()
  core.command_view.doc:set_selection(1,1,1,math.huge); batch('beta')
  assert(core.active_view.doc.filename=='beta.txt')
elseif n==7 then
  fresh(); local chosen
  core.command_view:enter('Choose',function(_,item) chosen=item.text end,function() return {'alpha','beta','gamma'} end)
  core.command_view:move_suggestion_idx(1); cmd('command:submit'); assert(chosen=='beta')
elseif n==8 then
  for _,sep in ipairs({'，','。','！','？','；','：','、','“','”','（','）','—','…','　',',',' '}) do
    local d=fresh('你好'..sep..'世界')
    local right=7+#sep
    local _,c=translate.previous_word_start(d,1,#d.lines[1]); assert(c==right,sep..' left')
    _,c=translate.previous_word_start(d,1,right); assert(c==1,sep..' left across')
    _,c=translate.next_word_end(d,1,1); assert(c==7,sep..' right')
    _,c=translate.next_word_end(d,1,7); assert(c==#d.lines[1],sep..' right across')
    d:set_selection(1,#d.lines[1]); cmd('doc:select-to-previous-word-start')
    assert(d:get_text(d:get_selection())=='世界')
    d:set_selection(1,right); cmd('doc:select-word')
    assert(d:get_text(d:get_selection())=='世界')
    d:set_selection(1,1); cmd('doc:select-to-next-word-end')
    assert(d:get_text(d:get_selection())=='你好')
    d:set_selection(1,#d.lines[1]); cmd('doc:delete-to-previous-word-start')
    assert(text(d)=='你好'..sep); assert(utf8.len(text(d)))
  end
  local d=fresh('甲乙丙'); local _,c=translate.previous_word_start(d,1,#d.lines[1]); assert(c==1)
  d=fresh('a\128b'); _,c=translate.previous_word_start(d,1,4); assert(c==1)
elseif n==9 then
  local d=fresh('alpha beta'); d:set_selection(1,1); cmd('find-replace:find')
  core.command_view:set_text('alpha'); core.command_view:update_suggestions()
  core.command_view.doc:set_selection(1,1,1,math.huge); batch('beta')
  assert(d:get_text(d:get_selection())=='beta')
end
for _,item in ipairs(core.log_items) do assert(not item.info, item.text) end
print('R2 case '..n..' PASS')
core.quit(true)
