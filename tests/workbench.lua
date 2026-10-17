package.path='modules/editor/?.lua;modules/editor/?/init.lua;modules/?.lua;modules/?/init.lua;./?.lua;./?/init.lua;'..package.path
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
 platform={fuzzy_match=native_platform.fuzzy_match,exedir='.',exefile='',userdir='.',set_fps=function()end,focus=function()return true end,cursor=function()end,title=function()end,mode=function()end,
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
dofile('apps/workbench/gui.lua')
for i=1,3 do cooloo.frame({},0.016) end
frame_input({'keypressed','left ctrl'},{'keypressed','n'},{'keyreleased','n'},{'keyreleased','left ctrl'})
frame_input({'textinput','print("你好")'})
local core=require 'core';assert(core.active_view.doc.lines[1]:find('你好',1,true))
require('core.command').perform('root:split-right')
cooloo.frame({},0.016)
local tmp=os.tmpname()
for _,text in ipairs({'no newline','one\ntwo\n','中文\r\n尾',''}) do
  local f=assert(io.open(tmp,'wb'));assert(f:write(text));f:close()
  local file=Doc(tmp);file:save()
  f=assert(io.open(tmp,'rb'));assert(f:read('*a')==text);f:close()
end
os.remove(tmp)
print('workbench: readonly, virtual, local provider, console buffer, wrap, composition and input passed')
