-- Run by event_bridge_test.c: SDL_PushEvent -> production gui_poll_event -> Lite.
package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;'..package.path
local function equal(actual,expected)
  assert(#actual==#expected, 'event arity')
  for i,v in ipairs(expected) do assert(actual[i]==v,tostring(actual[i])..' ~= '..tostring(v)) end
end
local function bridge(input,expected)
  push_event(table.unpack(input))
  equal({native_poll_event()},expected or input)
  while native_poll_event() do end
end
bridge({'keypressed','Left Shift'},{'keypressed','left shift'})
bridge({'keyreleased','Left Shift'},{'keyreleased','left shift'})
bridge({'keypressed','Keypad Enter'},{'keypressed','keypad enter'})
bridge({'keyreleased','Right Alt'},{'keyreleased','right alt'})
bridge({'textediting','中文🙂',1,2})
bridge({'textinput','中文🙂'})
bridge({'mousepressed',4,12.5,20.5,2},{'mousepressed','?',12.5,20.5,2})
bridge({'mousereleased',1,12,20},{'mousereleased','left',12,20})
bridge({'mousemoved',12.5,20.5,1.5,-2.5})
bridge({'mousewheel',-2})
bridge({'resized',960,640})
bridge({'exposed'})
bridge({'filedropped','测试.lua',50,60})
bridge({'focuslost'})
bridge({'quit'})
-- Lite flushes Alt-Tab keydowns on focus gain, never pending releases.
push_event('focusgained');push_event('keypressed','Tab');push_event('keyreleased','Left Alt')
equal({native_poll_event()},{'keyreleased','left alt'})
while native_poll_event() do end

local clears, locations, quit = 0, {}, false
local now=0
cooloo={renderer=native_renderer,offline=true,poll_event=native_poll_event,time=function()return now end,
 screen=function()return 960,640 end,
 text_width=function(s)return utf8.len(s)*8 end,line_height=function()return 18 end,
 set_ime_rect=function(...)locations[#locations+1]={...}end,
 clear_ime=function()clears=clears+1 end,
 clipboard={get=function()return '' end,set=function()end},quit=function()quit=true end,
 platform={fuzzy_match=native_platform.fuzzy_match,name='macOS',exedir='.',exefile='',userdir='.',set_fps=function()end,
 focus=function()return true end,cursor=function()end,title=function()end,mode=function()end,
 confirm=function()return false end,list_dir=function()return {} end,info=function()end,
 absolute_path=function(s)return s end}}
local platform=require 'platform.lite'
-- Record calls for assertions while executing the real native renderer.
local draws={}
local draw_text,draw_rect=renderer.draw_text,renderer.draw_rect
renderer.draw_text=function(font,text,...)
  draws[#draws+1]={op='text',text=text}
  return draw_text(font,text,...)
end
renderer.draw_rect=function(...)
  draws[#draws+1]={op='rect'}
  return draw_rect(...)
end
local core=require 'core'
local host=require 'core.host'
host.init()
local Doc=require 'core.doc'
local command=require 'core.command'
local keymap=require 'core.keymap'
local ime=require 'core.ime'
local doc=Doc();doc:text_input('abcdef\nsecond');doc:clean();doc:set_selection(1,1)
core.root_view:open_doc(doc)
local function tick(...)
  now=now+1 -- separate user edits beyond Lite's undo merge interval
  for _,event in ipairs{...} do push_event(table.unpack(event)) end
  draws={};host.tick()
  for _,item in ipairs(core.log_items) do assert(not item.info,item.text) end
  return draws
end
tick()
-- Showing the first native frame generates window/focus events. Consume those
-- before injecting shortcuts; Lite intentionally flushes keydowns on focus gain.
while native_poll_event() do end
local function key(kind,name)return {kind,name}end
local function click(shift)
  local view=core.active_view
  local x,y=view:get_line_screen_position(1)
  x=x+view:get_col_x_offset(1,4);y=y+view:get_line_height()/2
  if shift then push_event('keypressed','Left Shift') end
  tick({'mousepressed',1,x,y,1},{'mousereleased',1,x,y})
  assert(doc:has_selection()==not not shift,'plain click / true Shift-click')
  assert(not view.mouse_selecting,'release must finish selection')
  if shift then tick(key('keyreleased','Left Shift')) end
end
-- Focus loss travels through native SDL delivery before Lua resets modifiers.
for _,modifier in ipairs{'Left Ctrl','Right Ctrl','Left Shift','Right Shift','Left Alt','Right Alt','Left GUI'} do
  tick(key('keypressed',modifier), {'textediting','ni',2,0})
  assert(ime.editing)
  tick({'focuslost'})
  assert(not ime.editing and next(keymap.capture_state())==nil)
  for _,down in pairs(keymap.modkeys) do assert(not down) end
  tick({'focusgained'})
  tick(key('keyreleased',modifier),key('keypressed','S'))
  assert(not keymap.modkeys.ctrl and not keymap.modkeys.shift)
end
-- All four splits: no command.perform shortcut around the actual event bridge.
for _,k in ipairs{'L','J','I','K'} do
  doc:set_selection(1,1)
  tick(key('keypressed','Left Alt'),key('keypressed','Left Shift'),key('keypressed',k),
       key('keyreleased',k),key('keyreleased','Left Shift'),key('keyreleased','Left Alt'))
  assert(not keymap.modkeys.shift and not keymap.modkeys.alt)
  click(false)
  doc:set_selection(1,1);click(true)
  assert(command.perform('root:close'))
  tick()
end
-- Standalone modifiers, AltGr, and documented macOS Command aliases.
for _,k in ipairs{'Left Shift','Left Ctrl','Left Alt','Right Alt','Left GUI'} do
  tick(key('keypressed',k),key('keyreleased',k))
end
for _,held in pairs(keymap.modkeys) do assert(not held) end
-- Drag out of the pane and release; SDL desktop capture remains a manual test.
local view=core.active_view
local x,y=view:get_line_screen_position(1)
tick({'mousepressed',1,x,y+5,1},{'mousemoved',x+60,y+5,60,0})
assert(doc:has_selection())
tick({'mousereleased',1,-10,-10});assert(not view.mouse_selecting)

-- Composition-only events must redraw, preserve Doc/undo, and keep event order.
doc:set_selection(1,1)
local original=table.concat(doc.lines)
local draws=tick({'textediting','中文🙂',1,1})
assert(#draws>0 and ime.text=='中文🙂' and ime.start==3 and ime.length==3)
assert(table.concat(doc.lines)==original and not doc:is_dirty())
assert(#locations>0)
local found=false
for _,op in ipairs(draws)do if op.op=='text' and op.text=='中文🙂' then found=true end end
assert(found,'composition must be rendered')
-- A key-up must not be filtered; a modifier pressed within composition also works.
tick(key('keypressed','Left Shift'),key('keypressed','Backspace'))
assert(keymap.modkeys.shift and table.concat(doc.lines)==original)
tick(key('keyreleased','Left Shift'));assert(not keymap.modkeys.shift)
draws=tick({'textediting','',0,0});assert(not ime.editing and #draws>0)
assert(table.concat(doc.lines)==original and not doc:is_dirty())
-- Same-frame clear / ordinary key / new composition cannot be batch-preprocessed.
doc:set_selection(1,2)
tick({'textediting','ni',2,0},key('keypressed','Backspace'),{'textediting','',0,0},
     key('keypressed','Right'),{'textediting','好',1,0},key('keyreleased','Right'))
assert(select(2,doc:get_selection())==3 and ime.text=='好')
tick({'textinput','好'},{'textediting','',0,0})
assert(table.concat(doc.lines)=='ab好cdef\nsecond\n')
doc:undo();assert(table.concat(doc.lines)==original)
-- Invalid/negative SDL offsets and multi-byte conversion (Lite XL ingest).
local text,from,size=ime.ingest('中文🙂',-1,0);assert(from==10 and size==0)
text,from,size=ime.ingest('中文🙂',99,99);assert(from==10 and size==0)
ime.reset()
-- Lifecycle: switching panes, command box, click, focus loss and close.
tick({'textediting','cancel',0,0});assert(command.perform('root:split-right'))
assert(not ime.editing and clears>0)
tick({'textediting','cancel',0,0},{'focuslost'});assert(not ime.editing)
tick({'textediting','cancel',0,0});click(false);assert(not ime.editing)
assert(command.perform('core:find-command'))
local command_doc=core.command_view.doc
local old=table.concat(command_doc.lines)
tick({'textediting','搜索',1,1});assert(ime.view==core.command_view)
assert(table.concat(command_doc.lines)==old)
core.command_view:exit();assert(not ime.editing)
tick({'textediting','cancel',0,0});assert(command.perform('root:close'));assert(not ime.editing)
-- Expose/resize are redraw triggers even with an idle document.
core.redraw=false;assert(#tick({'exposed'})>0)
core.redraw=false;assert(#tick({'resized',960,640})>0)
print('event bridge: SDL -> C -> Lite split/modifiers/drag/IME/order/redraw/lifecycle OK')
