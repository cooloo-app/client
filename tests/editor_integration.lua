-- Appended to a generated text bundle by editor_integration.py, in an isolated project.
local core=require 'core'
local command=require 'core.command'
local config=require 'core.config'
local Doc=require 'core.doc'
local mode=os.getenv('COOLOO_EDITOR_TEST_MODE')
assert(core.project_dir==system.absolute_path('.'))
assert(cooloo.net==nil and cooloo.config==nil and cooloo.runtime==nil)
assert(not package.preload['plugins.workspace'] and not package.preload['plugins.console'])
assert(#require('core.plugin_manifest')==16)
for _,name in ipairs(require 'core.plugin_manifest') do assert(package.loaded[name],name) end
assert(not package.loaded['plugins.broken'])
if mode=='safe' then
  assert(core.safe_mode and not core.test_user and not core.test_project and not core.test_plugin)
else
  assert(core.test_plugin and core.test_user and core.test_project)
  assert(core.test_order=='plugin,user,project')
  local found=false
  for _,item in ipairs(core.log_items) do if item.text:find('expected broken plugin',1,true) then found=true end end
  assert(found,'plugin error must be logged and startup must continue')
end
config.project_scan_rate=0.05
local function content(doc) return doc:get_text(1,1,math.huge,math.huge) end
local function write(path,text) local f=assert(io.open(path,'wb'));assert(f:write(text));assert(f:close()) end
local file=core.open_doc('中文 file.lua')
assert(content(file)=='local hello = 1\n')
assert(core.open_doc('./中文 file.lua')==file)
local new=core.open_doc('new file.txt');new:text_input('new');new:save()
assert(content(Doc('new file.txt'))=='new')
local v=Doc();v.virtual=true;v.readonly=true;v:set_projection('message is not Lua\n  ')
local before=content(v);v:insert(1,1,'bad');assert(content(v)==before)
assert(not pcall(v.save,v,'virtual.txt'))
local outer=cooloo.frame
local frame=0
local started=system.get_time()
local selected
function cooloo.frame(events,dt)
  frame=frame+1
  if frame==2 then
    core.root_view:open_doc(file)
    command.perform('root:split-right')
    selected=core.root_view:get_active_node()
  elseif frame==3 then
    events={{type='filedropped',path=system.absolute_path('drop.txt'),x=selected.position.x+20,y=selected.position.y+40}}
  elseif frame==4 then
    assert(core.active_view.doc.filename:find('drop.txt',1,true))
    assert(core.root_view:get_active_node()==selected,'drop must target pane')
    local called=false
    local open=system.open_project
    system.open_project=function(path,safe) called=true;assert(path=='.' and safe==core.safe_mode) end
    core.on_event('filedropped','.',0,0);assert(called);system.open_project=open
    core.root_view:open_doc(file)
    command.perform('macro:toggle-record')
    events={{type='text',text='-- macro\n'}}
  elseif frame==5 then
    command.perform('macro:toggle-record')
    local old=content(file);command.perform('macro:play');assert(#content(file)>#old)
    file:undo();file:undo();file:clean()
    write('中文 file.lua','changed\r\n')
  elseif frame==25 then
    assert(content(file)=='changed\n','autoreload preserves final newline')
    assert(file.crlf)
    file:text_input('unsaved')
    write('中文 file.lua','external\n')
  elseif frame==40 then
    assert(content(file):find('unsaved',1,true),'autoreload must not overwrite dirty doc')
    assert(#core.project_files>=3,'project scanner must populate candidates')
    command.perform('core:find-file')
    assert(#core.command_view.state.suggest('drop')>0)
    core.command_view:exit()
    command.perform('project-search:find')
    core.command_view:set_text('needle');core.command_view:submit()
  elseif frame==60 then
    assert(core.active_view.results and #core.active_view.results>=1,'project search')
    assert(system.get_time()-started>=0.75,'fixed pacing: frames must not run unbounded')
    for _,item in ipairs(core.log_items) do
      assert(not item.info or item.text:find('expected broken plugin',1,true),item.text)
    end
    print('editor integration '..mode..': OK (60 frames, plugins/project/drop/search/macro/reload/readonly)')
    cooloo.quit()
  end
  return outer(events,dt)
end
