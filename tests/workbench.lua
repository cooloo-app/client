package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;./?.lua;./?/init.lua;'..package.path
local input={}
local function frame_input(...)
  input={...}
  return cooloo.frame({},0.016)
end
cooloo={renderer=assert(native_renderer,'run with renderer-test (real font userdata)'),offline=true,time=os.clock,screen=function()return 960,640 end,
 poll_event=function() local e=table.remove(input,1);if e then return table.unpack(e) end end,
 clear_ime=function()end,
 text_width=function(s)return utf8.len(s)*8 end,line_height=function()return 18 end,
 set_ime_rect=function()end,clipboard={get=function()return '' end,set=function()end},
 quit=function()end,
 platform={write_file=native_platform.write_file,resolve_path=native_platform.resolve_path,fuzzy_match=native_platform.fuzzy_match,exedir='.',exefile='',userdir='.',set_fps=function()end,focus=function()return true end,cursor=function()end,title=function()end,mode=function()end,
 confirm=function()return false end,list_dir=function()return {} end,info=function()end,absolute_path=function(s)return s end},
 runtime={start=function()return true end,poll=function()return {} end,send=function()return true end,stop=function()end}}
require('platform.lite')
local host=require 'core.host';host.init()
local Doc=require 'core.doc'
local d=Doc();d.virtual=true;d.readonly=true;d:set_projection('中文\nhello')
local before=table.concat(d.lines)
d:insert(1,1,'bad');d:remove(1,1,2,1);d:text_input('bad');d:replace(function()return 'bad' end);d:undo();d:redo()
assert(table.concat(d.lines)==before and not d:is_dirty())
assert(not pcall(function()d:save('/should-not-write')end))
d:set_selection(2,2);d:set_projection('older\n中文\nhello',1);assert(select(1,d:get_selection())==3)
local p=require('adapters.local').new()
local w=require('plugins.workspace.model').new(p)
local messages,draft=w:select('<local>');draft:text_input('你好');assert(w:send());w:refresh()
assert(messages.projection:find('你好',1,true));assert(#p:open('<local>')==1)
local Wrapped=require 'core.wrappedview';local view=Wrapped(messages);view.size.x=90;view.size.y=100;view:layout()
assert(#view.rows>#messages.lines)
view.follow=false;view.scroll.y=view:get_line_height();view.scroll.to.y=view.scroll.y
view:layout();local old=view.rows[2];local oldline=old.line
local oldfirst=old.first
local first=p.messages[1]
table.insert(p.messages,1,{id='older',from='old',text='history',ts=0})
w:refresh();view:layout()
local anchor=view.rows[math.floor(view.scroll.y/view:get_line_height())+1]
assert(anchor.line>oldline and anchor.first==oldfirst)
view.selection_revision=messages.projection_revision
view:scroll_to_make_visible(#messages.lines,1)
assert(not view.follow and view.scroll.to.y>0)
for _,row in ipairs(view.rows)do assert(utf8.len(messages.lines[row.line]:sub(row.first,row.last-1))) end
local reflow_doc=Doc();reflow_doc.virtual=true;reflow_doc:set_projection(string.rep('abcdef ',20))
local reflow=Wrapped(reflow_doc);reflow.size.x=120;reflow:layout();local small_rows=#reflow.rows
local larger=native_renderer.font.load('embedded:monospace',28)
reflow.get_font=function()return larger end
reflow:layout();assert(#reflow.rows>small_rows,'font replacement must invalidate wrapped layout')
-- Drafts survive rejection/uncertainty; ACK only clears the unchanged submission.
local delivery={state='pending'}
local fake={open=function()return {}end,send=function()return true,'pending'end,
 delivery=function()return delivery end,subscribe=function()end,unsubscribe=function()end}
local pending=require('plugins.workspace.model').new(fake)
local _,pd=pending:select('r');pd:text_input('keep me');assert(pending:send())
delivery.state='rejected';pending:refresh();assert(pd.lines[1]:find('keep me',1,true))
delivery.state='pending';assert(pending:send());pd:text_input(' edited')
delivery.state='sent';pending:refresh();assert(pd.lines[1]:find('edited',1,true))
assert(pending:send());pending:refresh();assert(pd.lines[1]=='\n')
pending:reset();assert(pending.selected==nil)
-- Unicode editing/undo and readonly search remain source-byte based.
local editdoc=Doc();editdoc:text_input('中文🙂');assert(utf8.len(editdoc.lines[1]))
editdoc:undo();assert(editdoc.lines[1]=='\n');editdoc:redo();assert(editdoc.lines[1]=='中文🙂\n')
local search=require 'core.doc.search'
assert(search.find(editdoc,1,1,'文'))
local busy=require('plugins.console').new{start=function()return true end,send=function()return false end}
assert(not busy:submit('not queued') and #busy.history==0)
local fixture=os.tmpname();local f=assert(io.open(fixture,'wb'));f:write('mock one\n中文 fixture\n');f:close()
local imported=require('adapters.local').new();assert(imported:load(fixture));assert(#imported.messages==0)
while imported.loading do imported:poll() end
assert(#imported.messages==2 and imported.messages[2].text=='中文 fixture')
imported:close();assert(not imported:send('<local>','closed'));os.remove(fixture)
local con=require('plugins.console').new(cooloo.runtime)
con:append('\228\184');assert(utf8.len(con.doc.projection))
con:append('\173');assert(con.doc.projection=='中');con:clear()
con:append('\255');assert(utf8.len(con.doc.projection));con:clear()
con:submit('x=42');con:recall(-1);assert(con.input.lines[1]:find('x=42',1,true))
con:append(string.rep('a',300000));assert(#con.output<=con.limit);assert(not con.doc:is_dirty())
-- Exercise actual composition, event dispatch, drawing, editing and split commands.
dofile('lua/apps/workbench/gui.lua')
for i=1,3 do cooloo.frame({},0.016) end
-- Use the real key + text event sequence: text-only injection misses swallowed
-- input when a globally registered shortcut is invalid in the focused view.
local core=require 'core'
local command=require 'core.command'
local keymap=require 'core.keymap'
local function space()
  frame_input({'keypressed','space'},{'textinput',' '},{'keyreleased','space'})
end
local chat=core.active_view
assert(chat:is(require 'plugins.workspace.chatview'))
chat:focus(chat.input)
local draft_before=table.concat(chat.doc.lines)
space()
assert(table.concat(chat.doc.lines)==' '..draft_before,'chat draft must accept Space')
frame_input({'keypressed','left ctrl'},{'keypressed','n'},{'keyreleased','n'},{'keyreleased','left ctrl'})
frame_input({'textinput','print("你好")'})
assert(core.active_view.doc.lines[1]:find('你好',1,true))
local edit=core.active_view
local before_space=table.concat(edit.doc.lines)
assert(not command.perform('workspace:tree-toggle'))
assert(not keymap.on_key_pressed('space'),'inapplicable binding must not consume input')
space()
assert(table.concat(edit.doc.lines)==before_space:gsub('\n$',' \n'))
-- A consumed shortcut must not suppress an unrelated character delivered in
-- the same poll batch (the event queue may contain Left followed by `a`).
edit.doc:set_selection(1,1)
frame_input({'keypressed','left'},{'keyreleased','left'},
  {'keypressed','a'},{'textinput','a'},{'keyreleased','a'})
assert(table.concat(edit.doc.lines):find('a',1,true),
  'a after a consumed navigation key must not be swallowed')
-- Shared bindings still fall through to document commands.
frame_input({'keypressed','return'},{'keyreleased','return'})
assert(#edit.doc.lines==2,'Return must fall through to doc:newline')
frame_input({'keypressed','up'},{'keyreleased','up'})
assert(select(1,edit.doc:get_selection())==1)
frame_input({'keypressed','down'},{'keyreleased','down'})
assert(select(1,edit.doc:get_selection())==2)
assert(command.perform('console:open'))
local console_doc=core.active_view.doc
space()
assert(console_doc.lines[1]==' \n','console input must accept Space')
-- Both installed sidebars must still consume Space and invoke tree-toggle.
local Sidebar=require 'plugins.workspace.sidebar'
local sidebars=0
for _,view in ipairs(core.root_view.root_node:get_children()) do
  if view:is(Sidebar) then
    sidebars=sidebars+1
    local choose=view.choose
    local toggled=false
    view.choose=function(_,toggle) toggled=toggle end
    core.set_active_view(view)
    assert(keymap.on_key_pressed('space') and toggled)
    view.choose=choose
  end
end
assert(sidebars==2)
core.set_active_view(edit)
require('core.command').perform('root:split-right')
cooloo.frame({},0.016)
local tmp=os.tmpname()
for _,text in ipairs({'no newline','one\ntwo\n','中文\r\n尾',''}) do
  local f=assert(io.open(tmp,'wb'));assert(f:write(text));f:close()
  local file=Doc(tmp);file:save()
  f=assert(io.open(tmp,'rb'));assert(f:read('*a')==text);f:close()
end
os.remove(tmp)
-- Thread decoration uses source coordinates: guide is not copied, wrapped
-- rows resolve clicks back to the same message, and scroll follows UUID.
local Threads=require 'workbench.threads'
local rid='550e8400e29b41d4a716446655440000'
local bid='550e8400e29b41d4a716446655440001'
local fixture={{id=rid,from='A',text='root',ts=0},
 {id=bid,from='B',text=Threads.header(rid,string.rep('中文 reply ',30)),ts=1}}
local fp={open=function()return fixture end,send=function()return true end}
local fw=require('plugins.workspace.model').new(fp)
local hd,dd=fw:select('r')
local hv=require('plugins.workspace.historyview')(hd);hv.size.x=160;hv.size.y=100
hv:layout();assert(#hv.rows>#hd.lines)
local line=hd.anchors[bid]
local x,y=hv:get_line_screen_position(line)
local resolved,col=hv:resolve_screen_position(x,y+hv:get_line_height()/2)
assert(resolved==line and col==1)
assert(not table.concat(hd.lines):find('│',1,true))
assert(fw:reply('r',bid));assert(dd.lines[1]=='@thread/1 msg:'..rid..'\n')
dd:undo();assert(dd.lines[1]=='\n','reply header must be undoable')
hv.follow=false;hv.scroll.y=(hv.line_rows[line]-1)*hv:get_line_height();hv.scroll.to.y=hv.scroll.y
local before=hd.anchors[bid]
table.insert(fixture,1,{id='older',from='old',text='older',ts=0})
fw:refresh();hv:layout()
assert(hd.anchors[bid]>before)
assert(hv.rows[math.floor(hv.scroll.y/hv:get_line_height())+1].line==hd.anchors[bid])
-- Actual command palette freezes target UUID before any projection change.
core.set_active_view(chat);chat:focus(chat.history)
chat.history.doc.ranges={{id=rid,first_line=1,last_line=1,raw='raw'}}
chat.history.doc:set_selection(1,1)
assert(command.perform('core:find-command'))
local found=false
for _,item in ipairs(core.command_view.suggestions) do
 if item.command=='chat:reply-in-thread' then found=true end
end
-- Suggestions are bounded; use the actual palette search.
core.command_view:set_text('Chat: Reply In Thread');core.command_view:update_suggestions()
assert(core.command_view.suggestions[1].command=='chat:reply-in-thread')
core.command_view:exit(false)
assert(keymap.get_binding('chat:reply-in-thread')=='alt+r')
-- Mixed Chat/File snapshot shares a single tree and prunes locked chrome.
local Layout=require 'core.session_layout'
local snap,path=Layout.capture(core.root_view.root_node,function(view)
  if view==chat then return {kind='chat',room_id='room-a'} end
  return Layout.file(view)
end)
assert(snap and type(path)=='table')
local target=core.root_view:get_active_node()
local restored={type='split',axis='y',ratio=0.6,
 a={type='leaf',active_tab=2,tabs={{resource={kind='chat',room_id='a'}},{resource={kind='chat',room_id='b'}}}},
 b={type='leaf',active_tab=1,tabs={{resource={kind='chat',room_id='missing'}}}}}
local opened={}
assert(Layout.restore(target,restored,{'a'},function(resource,node)
  if resource.room_id=='missing' then return end
  local view=require('core.docview')(Doc());node:add_view(view)
  opened[resource.room_id]=view;return view
end))
assert(target.type=='vsplit' and target.divider==0.6)
assert(target.a.active_view==opened.b and core.active_view==opened.b)
assert(not Layout.restore(target,{type='split',axis='bad'},nil,function()error('must not open')end))
print('workbench: readonly, wrap, composition, thread geometry/undo/UUID scroll/palette, mixed layout passed')
