local core = require 'core'
local command = require 'core.command'
local ac = require 'plugins.autocomplete'
local function text(d) return table.concat(d.lines):sub(1,-2) end
local function fresh(s)
  local d=core.open_doc();core.root_view:open_doc(d)
  d:text_input(s or '');d:clean();return d,core.active_view
end
local function cmd(name)
  local c=assert(command.map[name]);assert(c.predicate(),name);c.perform()
end
local function submit(s)
  core.command_view:set_text(s);core.command_view:update_suggestions();core.command_view:submit()
end
local function input(s) core.root_view:on_text_input(s) end
local function write(path,s) local f=assert(io.open(path,'wb'));assert(f:write(s));assert(f:close()) end
local function resume(cr) local ok,err=coroutine.resume(cr);assert(ok,err) end
core.log_items={}
local n=tonumber(os.getenv('REVIEW_CASE'))
if n==1 then
  ac.map={};ac.add{name='test',items={foobar=true,foobaz=true,foozoo=true}}
  local d=fresh();input('foo');cmd('autocomplete:next');cmd('autocomplete:next')
  input('zo');cmd('autocomplete:complete');assert(text(d)=='foozoo', 'completion: '..text(d))
elseif n==2 then
  ac.map={};ac.add{name='one',items={fooA=true,fooB=true,fooC=true}}
  ac.add{name='two',items={fooA='info'}}
  -- Deterministic ordering isolates the input/output cursor bug from tie sorting.
  local common=require 'core.common';local fuzzy=common.fuzzy_match
  common.fuzzy_match=function(items) table.sort(items,function(a,b) return a.text<b.text end);return items end
  local d=fresh();input('foo');cmd('autocomplete:next');cmd('autocomplete:next');cmd('autocomplete:complete')
  common.fuzzy_match=fuzzy;assert(text(d)=='fooC',text(d))
elseif n==3 then
  local d=fresh('uniqueLastSymbol');core.docs={d}
  for _,thread in pairs(core.threads) do
    for i=1,3 do if coroutine.status(thread.cr)~='dead' then resume(thread.cr) end end
  end
  local found=false
  for _,item in ipairs(assert(ac.map['open-docs']).items) do if item.text=='uniqueLastSymbol' then found=true end end
  assert(found,'last line missing')
elseif n==4 then
  write('long.txt',string.rep('needle\n',201));write('short.txt','needle\n')
  core.project_files={{type='file',filename='long.txt'},{type='file',filename='short.txt'}}
  fresh();cmd('project-search:find');submit('needle')
  local view=core.active_view;local old=core.threads[view.results].cr
  resume(old);assert(#view.results==100)
  view:refresh();local current=core.threads[view.results].cr
  while coroutine.status(old)~='dead' do resume(old) end
  assert(#view.results==0 and view.searching,'stale task published')
  while coroutine.status(current)~='dead' do resume(current) end
  assert(#view.results==202 and not view.searching)
  -- Invalid pattern must close its file and settle the spinner as well.
  local closed=0;local open=io.open
  io.open=function(...) local fp=assert(open(...));return setmetatable({},{__close=function() closed=closed+1;fp:close() end,__index=function(_,k)
    if k=='close' then return function() closed=closed+1;return fp:close() end end
    return function(_,...) return fp[k](fp,...) end
  end}) end
  view:begin_search('[',function(s) return s:find('[') end)
  local cr=core.threads[view.results].cr
  while coroutine.status(cr)~='dead' do resume(cr) end
  io.open=open;assert(not view.searching and closed==1, 'searching='..tostring(view.searching)..' closed='..closed)
  core.log_items={} -- the injected pattern error is expected
elseif n==5 then
  local d,v=fresh();d:text_input('valuable');local closed=false
  local function close() closed=true end
  v:try_close(close);submit('s');assert(core.active_view==core.command_view,'missing Save As')
  core.command_view:exit();assert(not closed and d:is_dirty())
  v:try_close(close);submit('s');assert(not pcall(submit,'missing-parent/file'));assert(not closed and d:is_dirty())
  v:try_close(close);submit('s');submit('saved.txt');assert(closed and not d:is_dirty())
  local f=assert(io.open('saved.txt'));assert(f:read('*a')=='valuable');f:close()
  d:text_input('more');closed=false;v:try_close(close);submit('s');assert(closed)
elseif n==6 then
  local d,v=fresh();d:text_input('keep');local closed=false
  v:try_close(function() closed=true end);submit('xyz');assert(not closed and text(d)=='keep')
elseif n==7 then
  local d=fresh('abc');local id=d:get_change_id();cmd('doc:move-lines-up')
  assert(text(d)=='abc' and d:get_change_id()==id and not d:is_dirty())
  d=fresh('a\nb');d:set_selection(1,1,2,2);id=d:get_change_id();cmd('doc:move-lines-up')
  assert(text(d)=='a\nb' and d:get_change_id()==id)
  d:set_selection(2,1);cmd('doc:move-lines-up');assert(text(d)=='b\na\n')
elseif n==8 then
  local tree
  for _,v in ipairs(core.root_view.root_node:get_children()) do if v:get_name()=='Project' then tree=v end end
  assert(tree);core.project_files={{filename='same',type='file'}};tree:check_cache()
  assert(tree:get_cached(core.project_files[1]).type=='file')
  core.project_files={{filename='same',type='dir'}};tree:check_cache()
  local item=tree:get_cached(core.project_files[1]);assert(item.type=='dir');item.expanded=true
  core.project_files={{filename='same',type='dir'}};tree:check_cache();assert(tree:get_cached(core.project_files[1]).expanded)
  core.project_files={{filename='same',type='file'}};tree:check_cache();assert(tree:get_cached(core.project_files[1]).type=='file')
  core.project_files={};tree:check_cache();assert(tree.cache.same==nil)
elseif n==9 then
  local a,av=fresh('one one');a:set_selection(1,1);cmd('find-replace:previous-find')
  cmd('find-replace:find');submit('one');cmd('find-replace:repeat-find')
  local expected={a:get_selection()};cmd('find-replace:repeat-find')
  fresh('other');cmd('find-replace:previous-find');core.set_active_view(av)
  cmd('find-replace:previous-find');assert(table.concat({a:get_selection()},',')==table.concat(expected,','))
  for _,item in ipairs(core.log_items) do if item.info then assert(item.text=='No previous finds',item.text) end end
  core.log_items={}
end
for _,item in ipairs(core.log_items) do assert(not item.info,item.text) end
for key,thread in pairs(core.threads) do
  if coroutine.status(thread.cr)=='dead' then core.threads[key]=nil end
end
print('review regression '..n..': OK');core.quit(true)
