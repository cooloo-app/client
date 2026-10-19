-- Register Chat-local aliases of existing editor operations. The composite
-- facade supplies the focused document/geometry but does not claim to be a
-- DocView. Original commands, predicates and classes remain untouched.
local core=require 'core'
local command=require 'core.command'
local keymap=require 'core.keymap'
local ChatView=require 'plugins.workspace.chatview'
local M={}
function M.install(split)
  local aliases={}
  for name,entry in pairs(command.map) do
    local document=name:match('^doc:') or name:match('^find%-replace:')
    if document and name~='doc:save' and name~='doc:save-as' and name~='doc:rename' then
      aliases[name]={name='workspace:chat-'..name:gsub(':','-'),perform=entry.perform}
    end
  end
  for name,entry in pairs(aliases) do
    command.add(function()
      local view=core.active_view
      return view:is(ChatView) and (name~='find-replace:select-next' or view.doc:has_selection())
    end,{[entry.name]=entry.perform})
  end
  local bindings={}
  for stroke,names in pairs(keymap.map) do
    for _,name in ipairs(names) do
      if aliases[name] then
        bindings[stroke]=bindings[stroke] or {}
        table.insert(bindings[stroke],aliases[name].name)
      end
    end
  end
  keymap.add(bindings)
  local keys={left='alt+shift+j',right='alt+shift+l',up='alt+shift+i',down='alt+shift+k'}
  for direction,key in pairs(keys) do
    local name='workspace:split-chat-'..direction
    command.add(function() return core.active_view:is(ChatView) end,{
      [name]=function() split(direction) end,
    })
    keymap.add{[key]=name}
  end
end
return M
