-- Round 2 acceptance: real Doc, commands, default plugins and host APIs.
local core = require 'core'
local command = require 'core.command'
local keymap = require 'core.keymap'
local Doc = require 'core.doc'
local function cmd(name) assert(command.perform(name), name) end
local function text(d) return table.concat(d.lines):sub(1, -2) end
local function fresh(s)
  local d=core.open_doc(); d:text_input(s or ''); d:clean()
  core.root_view:open_doc(d); return d
end
local function read(path)
  local f=assert(io.open(path,'rb'));local s=f:read('*a');assert(f:close());return s
end
local function selection(d) return table.concat({d:get_selection()}, ',') end
local d=fresh('abc')
d:set_selection(1,1);d:text_input('X');d:save('branch.txt')
local saved=d:get_change_id()
d:undo();assert(text(d)=='abc' and d:is_dirty())
d:redo();assert(text(d)=='Xabc' and not d:is_dirty() and saved==d:get_change_id())
d:undo();d:text_input('Y');assert(text(d)=='Yabc' and d:is_dirty())
assert(read('branch.txt')=='Xabc')
local prompts=0
local confirm=system.show_confirm_dialog
system.show_confirm_dialog=function() prompts=prompts+1;return false end
core.quit();assert(prompts==1)
system.show_confirm_dialog=confirm
-- A save point inside the usual undo merge timeout is a real boundary.
d:save();d:text_input('Z');d:undo();assert(text(d)=='Yabc' and not d:is_dirty())
d:redo();assert(text(d)=='YZabc' and d:is_dirty())
d:save();d:remove(1,1,1,3);d:insert(1,1,'Q');assert(d:is_dirty())
d:undo();assert(text(d)=='YZabc' and not d:is_dirty())
d:redo();assert(text(d)=='Qabc' and d:is_dirty())
local before=d:get_change_id();d:remove(1,1,1,1);d:insert(1,1,'');assert(before==d:get_change_id())
print('N01: branch identity, save boundary, undo/redo and quit guard OK')

for _,s in ipairs{'', 'abc', 'abc\n', 'abc\ndef', 'abc\ndef\n'} do
  d=fresh(s);d:set_selection(1,1,#d.lines,#d.lines[#d.lines])
  local id,idx=d:get_change_id(),d.undo_stack.idx
  cmd('doc:select-lines')
  assert(text(d)==s and not d:is_dirty() and d:get_change_id()==id and d.undo_stack.idx==idx)
  assert(d:get_text(d:get_selection())==s)
  if s~='' then
    cmd('doc:copy');assert(system.get_clipboard()==s)
    cmd('doc:cut');assert(text(d)=='');d:undo();assert(text(d)==s and not d:is_dirty())
    d:set_selection(1,1,#d.lines,#d.lines[#d.lines]);cmd('doc:select-lines');d:text_input('x');assert(text(d)=='x')
  end
end
print('N03: selection leaves text/history/dirty intact; copy/cut/replace OK')

d=fresh('abc\ndef\n');d:save('format.txt')
cmd('doc:toggle-line-ending');assert(d:is_dirty())
cmd('doc:toggle-line-ending');assert(not d:is_dirty())
cmd('doc:toggle-line-ending');d:text_input('x');d:undo()
assert(d.crlf and d:is_dirty()) -- format choice is independent of text undo
prompts=0;system.show_confirm_dialog=function() prompts=prompts+1;return false end
core.quit();assert(prompts==1);system.show_confirm_dialog=confirm
d:save();assert(not d:is_dirty() and read('format.txt')=='abc\r\ndef\r\n')
d:load('format.txt');assert(d.crlf and not d:is_dirty())
cmd('doc:toggle-line-ending');assert(d:is_dirty());d:save();assert(not d:is_dirty())
print('N04: format toggle, undo policy, save/reload and quit guard OK')

-- Both normal and exceptional playback must leave the real held set intact.
cmd('macro:toggle-record');core.on_event('keypressed','left ctrl');core.on_event('keyreleased','left ctrl');cmd('macro:toggle-record')
core.on_event('keypressed','left ctrl');core.on_event('keypressed',';')
core.on_event('keypressed','left shift');assert(keymap.modkeys.ctrl and keymap.modkeys.shift)
local update=core.root_view.update
core.root_view.update=function() error('injected playback failure') end
assert(not pcall(command.map['macro:play'].perform))
core.root_view.update=update
core.on_event('keypressed','right shift');core.on_event('keyreleased','left shift')
assert(keymap.modkeys.ctrl and keymap.modkeys.shift)
core.on_event('keyreleased','right shift');core.on_event('keyreleased','left ctrl')
assert(not keymap.modkeys.ctrl and not keymap.modkeys.shift)
if system.platform=='macOS' then
  core.on_event('keypressed','left gui');cmd('macro:play')
  core.on_event('keypressed','left shift');assert(keymap.modkeys.ctrl)
  core.on_event('keyreleased','left gui');core.on_event('keyreleased','left shift')
end
-- Capture a modifier already held at recording start.
d=fresh('abc');core.on_event('keypressed','left shift');cmd('macro:toggle-record')
core.on_event('keypressed','left');core.on_event('keyreleased','left');cmd('macro:toggle-record')
local sel=selection(d);core.on_event('keyreleased','left shift')
d=fresh('abc');cmd('macro:play');assert(selection(d)==sel and not keymap.modkeys.shift)
print('R2-02: initial, overlapping, subsequent-event and exception modifier state OK')

for _,early in ipairs{false,true} do
 for _,cancel in ipairs{false,true} do
  local a=fresh('abc')
  if early then core.on_event('textediting','ni',2,0) end
  cmd('macro:toggle-record')
  core.on_event('textediting','ni',2,0)
  for _,key in ipairs{'backspace','delete','left','right','up','down','escape'} do
    core.on_event('keypressed',key);core.on_event('keyreleased',key)
  end
  if cancel then core.on_event('textediting','',0,0)
  else core.on_event('textinput','你') end
  cmd('macro:toggle-record')
  local b=fresh('abc');cmd('macro:play')
  assert(text(a)==text(b) and selection(a)==selection(b))
 end
end
-- CommandView has its own document, and must obey the same recording semantics.
core.command_view:enter('Probe',function() end);core.command_view:set_text('abc')
core.command_view.doc:set_selection(1,4)
cmd('macro:toggle-record');core.on_event('textediting','ni',2,0)
core.on_event('keypressed','backspace');core.on_event('keyreleased','backspace')
core.on_event('textinput','你');cmd('macro:toggle-record')
local a=text(core.command_view.doc);local sel=selection(core.command_view.doc)
core.command_view:set_text('abc');core.command_view.doc:set_selection(1,4)
cmd('macro:play');assert(text(core.command_view.doc)==a and selection(core.command_view.doc)==sel)
core.on_event('textediting','ni',2,0);cmd('macro:play');assert(text(core.command_view.doc)==a)
core.on_event('textediting','',0,0)
print('R2-03: IME edit/cancel/commit, early recording and command view replay OK')
core.quit(true)
