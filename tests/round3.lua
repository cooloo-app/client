-- Correct-behavior assertions using real commands, Docs and default plugins.
local core = require 'core'
local command = require 'core.command'
local keymap = require 'core.keymap'
local translate = require 'core.doc.translate'
local ime = require 'core.ime'
local function text(d) return table.concat(d.lines):sub(1,-2) end
local function show(d) core.root_view:open_doc(d); return d end
local function fresh(s)
  local d=show(core.open_doc());d:text_input(s or '');d:clean();return d
end
local function cmd(name) assert(command.perform(name),name) end
local function read(path)
  local f=assert(io.open(path,'rb'));local s=assert(f:read('*a'));assert(f:close());return s
end
local function rename(name)
  cmd('doc:rename');assert(core.active_view==core.command_view)
  core.command_view:set_text(name);core.command_view:submit()
end
local d=show(core.open_doc('file.txt'));d:text_input('UNSAVED')
local id=d:get_change_id()
rename('./file.txt')
assert(d.filename=='file.txt' and d:get_change_id()==id and d:is_dirty())
assert(read('file.txt')=='valuable') -- equivalent rename is a true no-op
assert(not pcall(rename,'missing-parent/new.txt'))
assert(d.filename=='file.txt' and d:is_dirty() and read('file.txt')=='valuable')
assert(not pcall(rename,'hard.txt'))
assert(read('hard.txt')=='hard' and read('hard-alias.txt')=='hard')
assert(d.filename=='file.txt' and d:is_dirty())
rename('sub/new.txt')
assert(not system.get_file_info('file.txt'))
assert(read('sub/new.txt')=='UNSAVEDvaluable' and not d:is_dirty())
-- A delete failure must be visible, leaving the saved copy and original intact.
d:text_input('X')
local remove=os.remove;os.remove=function() return nil,'injected remove failure' end
rename('other.txt');os.remove=remove
assert(read('other.txt')==text(d) and system.get_file_info('sub/new.txt'))
assert(core.log_items[#core.log_items].text:find('could not remove',1,true))
print('R3-01: activated rename no-op, ordinary move, failed save/hard-link/delete OK')

-- Observe the full state (including identity of history/selection/highlighter).
d:set_selection(1,2,1,4);d:text_input('edit');d:undo()
local snapshot={}
for k,v in pairs(d) do snapshot[k]=v end
local before=text(d);local selection=table.concat({d:get_selection()},',')
local function intact()
  for k,v in pairs(snapshot) do assert(d[k]==v,'state changed: '..k) end
  for k in pairs(d) do assert(snapshot[k]~=nil,'new state: '..k) end
  assert(text(d)==before and table.concat({d:get_selection()},',')==selection)
end
assert(not pcall(d.load,d,'missing-file.txt'));intact()
assert(not pcall(d.load,d,'directory'));intact()
local open=io.open
for _,mode in ipairs{'read-return','read-throw','close-return','close-throw','open-denied'} do
  local closes=0
  io.open=function()
    if mode=='open-denied' then return nil,'permission denied' end
    return {
      read=function()
        if mode=='read-return' then return nil,'partial read failed' end
        if mode=='read-throw' then error('read failed') end
        return 'new\r\ncontent'
      end,
      close=function()
        closes=closes+1
        if mode=='close-return' then return nil,'close failed' end
        if mode=='close-throw' then error('close failed') end
        return true
      end
    }
  end
  local ok=pcall(d.load,d,'injected.txt');io.open=open
  assert(not ok);assert(closes==(mode=='open-denied' and 0 or 1));intact()
end
d:load('valid.txt');assert(text(d)=='new\ncontent\n' and d.crlf and not d:is_dirty())
assert(d.undo_stack.idx==1 and d.redo_stack.idx==1 and d.filename=='valid.txt')
print('R3-03: open/read/close failure preserves all state and closes handle; success OK')

-- Validate a real malformed disk file as well as constructed documents.
d=show(core.open_doc('invalid.bin'));d:set_selection(1,2)
cmd('doc:move-to-previous-char')
local first_line,first_col=d:get_selection();assert(first_line==1 and first_col==1)
assert(text(d)=='\x80abc' and not d:is_dirty())
-- Validate single-byte fallback, valid Unicode, all boundaries and edit commands.
for _,s in ipairs{'\x80abc','a\x80\xbf','\xc2','\xe4\xb8','\xc0\xaf',
  '\xed\xa0\x80','\xf4\x90\x80\x80','\xff\xfe', '\x80\n\x80',
  '中🙂a','a\x80中\xbf','', '\x80'} do
  d=fresh(s)
  for line=1,#d.lines do
    for col=1,#d.lines[line] do
      local a,b=translate.previous_char(d,line,col)
      assert(a<line or a==line and b<col or line==1 and col==1)
      local c,e=translate.next_char(d,line,col)
      assert(c>line or c==line and e>col or line==#d.lines and col==#d.lines[line])
      translate.previous_word_start(d,line,col);translate.next_word_end(d,line,col)
    end
  end
  translate.previous_char(d,-100,-100);translate.next_char(d,math.huge,math.huge)
  d:set_selection(1,1)
  for _=1,#s+1 do cmd('doc:select-to-next-char') end
  assert(d:get_text(d:get_selection())==s)
  d:set_selection(1,1)
  for _=1,#s+1 do cmd('doc:delete-to-next-char') end
  assert(text(d)=='')
  d=fresh(s)
  for _=1,#s+1 do cmd('doc:backspace') end
  assert(text(d)=='')
end
d=fresh('\x80\xbf');d:set_selection(1,3);cmd('doc:backspace');assert(text(d)=='\x80')
d:set_selection(1,1);cmd('doc:delete-to-next-char');assert(text(d)=='')
d=fresh('中🙂');local a,b=translate.previous_char(d,1,8);assert(a==1 and b==4)
a,b=translate.next_char(d,1,1);assert(a==1 and b==4)
assert(not require('core.common').is_utf8_cont(''))
print('R3-04: invalid byte/scalar/truncation boundaries, words, selection, delete/backspace OK')

for _,modifier in ipairs{'left ctrl','right ctrl','left shift','right shift',
                         'left alt','right alt','left gui','right gui'} do
  keymap.reset_state()
  d=show(core.open_doc('focus.txt'));d:text_input('x')
  local old=read('focus.txt');local before=text(d)
  core.on_event('keypressed',modifier)
  core.on_event('textediting','ni',2,0);assert(ime.editing)
  core.on_event('focuslost');assert(not ime.editing)
  assert(next(keymap.capture_state())==nil)
  for _,v in pairs(keymap.modkeys) do assert(not v) end
  core.on_event('keyreleased',modifier) -- late release is harmless
  core.on_event('keypressed','s');core.on_event('textinput','s')
  assert(d:is_dirty() and read('focus.txt')==old and #text(d)==#before+1)
end
-- Recording must preserve the focus-loss reset, or Shift/Ctrl will resurrect.
for _,modifier in ipairs{'left shift','left ctrl','right alt'} do
  keymap.reset_state();d=fresh('abc')
  core.on_event('keypressed',modifier);cmd('macro:toggle-record')
  core.on_event('focuslost');core.on_event('keypressed','left')
  cmd('macro:toggle-record')
  local expected=table.concat({d:get_selection()},',')
  local replay=fresh('abc')
  core.on_event('keypressed','right shift')
  cmd('macro:play')
  assert(table.concat({replay:get_selection()},',')==expected)
  assert(keymap.modkeys.shift and keymap.capture_state()['right shift'])
  core.on_event('keyreleased','right shift')
end
keymap.reset_state()
print('R3-05: all modifiers, IME, plain s/no-save, late release and macro isolation OK')
core.quit(true)
