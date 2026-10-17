-- Editor adapter only; session state and runtime policy live outside the editor.
local Doc=require 'core.doc'
local M={}
function M.new(runtime)
  local session=require('workbench.console').new(runtime)
  session.doc=Doc();session.doc.virtual=true;session.doc.readonly=true;session.doc.filename='Lua output'
  session.input=Doc();session.input.virtual=true;session.input.filename='Lua console input'
  session.on_output=function(text)
    session.doc:set_projection(text);session.doc.projection=text
  end
  local recall=session.recall
  function session:recall(delta)
    local text=recall(self,delta)
    self.input:set_projection(text)
    return text
  end
  return session
end
function M.install(runtime)
  local core=require 'core'
  local command=require 'core.command'
  local DV=require 'core.docview'
  local Wrapped=require 'core.wrappedview'
  local console=M.new(runtime)
  local function find_edit(n)
    if n.type=='leaf' then return not n.locked and n or nil end
    return find_edit(n.a) or find_edit(n.b)
  end
  local function show(doc,wrapped)
    local node=core.root_view:get_active_node()
    if node.locked then node=find_edit(core.root_view.root_node) end
    node:add_view(wrapped and Wrapped(doc) or DV(doc))
    return node
  end
  command.add(nil,{
    ['console:open']=function()
      local node=show(console.doc,true)
      node:split('down',DV(console.input));node.divider=0.75
    end,
    ['console:stop-file']=function()console:stop(1)end,
    ['console:stop-session']=function()console:stop(2)end,
    ['console:restart']=function()console:restart()end,
    ['console:clear']=function()console:clear()end,
  })
  command.add(function()return core.active_view.doc==console.input end,{
    ['console:submit']=function()
      local d=console.input
      if console:submit(d:get_text(1,1,#d.lines,#d.lines[#d.lines])) then d:set_projection('') end
    end,
    ['console:previous']=function()console:recall(-1)end,
    ['console:next']=function()console:recall(1)end,
  })
  command.add(function()local d=core.active_view.doc;return d and not d.virtual end,{
    ['runtime:run-file']=function()
      local d=core.active_view.doc
      if not d.filename then core.error('Save the Lua file before running');return end
      if d:is_dirty() then d:save() end
      console:start(1,d.filename);show(console.doc,true)
    end,
  })
  require('core.keymap').add{['ctrl+return']='console:submit',
    ['f5']='runtime:run-file',['ctrl+`']='console:open',
    ['alt+up']='console:previous',['alt+down']='console:next'}
  local quit=system.request_quit
  system.request_quit=function()runtime.stop(1);runtime.stop(2);quit()end
  return console
end
return M
