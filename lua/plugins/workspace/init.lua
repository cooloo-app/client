local core=require 'core'
local M={}
function M.install(provider)
  local command=require 'core.command'
  local keymap=require 'core.keymap'
  local DV=require 'core.docview'
  local Wrapped=require 'core.wrappedview'
  local Sidebar=require 'plugins.workspace.sidebar'
  local tree=require 'plugins.workspace.tree'
  local workspace=require('plugins.workspace.model').new(provider)
  local files=require('plugins.workspace.files').new(system)
  local sessions,collapsed,origins={},{},setmetatable({},{__mode='k'})
  local context,stamp,last_focus
  local list,filelist
  local History=Wrapped:extend()
  local Draft=DV:extend()
  -- Closing a view keeps the session draft in the model until exit/reset.
  function Draft:try_close(close) close() end
  local function find_edit(n)
    if n.type=='leaf' then return not n.locked and n or nil end
    return find_edit(n.a) or find_edit(n.b)
  end
  local function node_for(view)
    return view and core.root_view.root_node:get_node_for_view(view)
  end
  local function edit_node()
    local node=core.root_view:get_active_node()
    if not node or node.locked then node=find_edit(core.root_view.root_node) end
    return node
  end
  local function set_context(id)
    context=id;files:select(id);filelist.index=1
  end
  local function active_room()
    local doc=core.active_view and core.active_view.doc
    for id,s in pairs(sessions) do
      if doc==s.messages or doc==s.draft then return id,s end
    end
  end
  local function room_name(id)
    for _,r in ipairs(provider:list()) do if r.id==id then return r.name or id end end
    return id
  end
  function History:get_name() return 'Chat: '..room_name(self.room) end
  function Draft:get_name() return 'Draft: '..room_name(self.room) end
  local function select_room(id)
    local messages,draft=workspace:select(id)
    local s=sessions[id] or {messages=messages,draft=draft}
    sessions[id]=s
    local mn,dn=node_for(s.history),node_for(s.input)
    if not mn and not dn then
      s.history=History(messages);s.history.room=id
      s.input=Draft(draft);s.input.room=id
      -- Reuse existing history/draft panes as tab groups where possible.
      for other_id,other in pairs(sessions) do
        if other_id~=id then
          local a,b=node_for(other.history),node_for(other.input)
          if a and b and a~=b then mn,dn=a,b;break end
        end
      end
      if mn then mn:add_view(s.history);dn:add_view(s.input)
      else
        local node=edit_node();node:add_view(s.history)
        node:split('down',s.input);node.divider=0.72
      end
    else
      if not mn then
        s.history=History(messages);s.history.room=id
        dn:split('up',s.history)
      elseif not dn then
        s.input=Draft(draft);s.input.room=id
        mn:split('down',s.input)
      end
    end
    node_for(s.history):set_active_view(s.history)
    node_for(s.input):set_active_view(s.input)
    set_context(id)
  end
  local function refresh_tree()
    list:set_rows(tree.build(provider:list(),collapsed))
  end
  list=Sidebar('Conversations',function(row,toggle)
    if row.branch and (toggle or not row.room) then
      collapsed[row.key]=not collapsed[row.key];refresh_tree()
    elseif row.room then select_room(row.room.id) end
  end)
  filelist=Sidebar('Room files',function(row,toggle)
    if row.branch then files:toggle(row)
    elseif row.file and not toggle then
      local node=edit_node();node:set_active_view(node.active_view)
      local ok,doc=core.try(core.open_doc,row.path)
      if ok then
        -- Remember the explicit most recent room used to open this file.
        origins[doc]=context
        core.root_view:open_doc(doc)
      end
    end
  end)
  local middle=core.root_view:get_active_node():split('left',list,true)
  middle=middle:split('right',filelist,true)
  middle:set_active_view(middle.active_view)
  refresh_tree()
  local rooms=provider:list()
  if rooms[1] then select_room(rooms[1].id) end
  local function confirm_discard()
    return not workspace:has_unsent() or system.show_confirm_dialog('Unsent messages',
      'Discard all session drafts and pending delivery tracking? Messages already sent may still arrive.')
  end
  -- Retain the pre-existing workspace lifecycle hook; no editor overrides.
  local request_quit=system.request_quit
  system.request_quit=function()
    if not confirm_discard() then return end
    workspace:reset()
    if provider.close then provider:close() end
    request_quit()
  end
  local function reset_views()
    workspace:reset()
    for _,s in pairs(sessions) do
      s.draft.readonly=true
      for _,view in ipairs{s.history,s.input} do
        local node=node_for(view)
        if node then node:set_active_view(view);node:close_active_view(core.root_view.root_node) end
      end
    end
    sessions={};origins=setmetatable({},{__mode='k'});files:reset();context=nil;last_focus=nil
  end
  local function prompt(title,fn) core.command_view:enter(title,function(text) fn(text) end) end
  command.add(function()
    local _,s=active_room()
    return s and core.active_view.doc==s.draft
  end,{
    ['workspace:send']=function()
      local id=active_room()
      local ok,status=workspace:send(id);core.log('%s',status or (ok and 'sent' or 'send failed'))
    end,
  })
  command.add(nil,{
    ['workspace:switch']=function()
      core.command_view:enter('Conversation',function(_,item) if item then select_room(item.id) end end,
        function(text)
          local items={}
          for _,r in ipairs(provider:list()) do
            if (r.name or r.id):find(text,1,true) then items[#items+1]={text=(r.name or r.id)..' ['..r.id..']',id=r.id} end
          end
          return items
        end)
    end,
    ['workspace:address']=function()
      if provider.address then prompt('Destination ID',function(id)
        local ok,err=provider:address(id)
        if ok then select_room(id) else core.error('%s',err) end
      end) end
    end,
    ['workspace:history']=function()
      local id=active_room() or context
      if id then local _,status=provider:earlier(id);workspace:refresh();core.log('%s',status or '') end
    end,
    ['workspace:bind-directory']=function()
      local id=active_room() or context
      if not id then core.error('Select a conversation first');return end
      prompt('Local directory for '..room_name(id)..' (session only)',function(path)
        local ok,err=files:bind(id,path)
        if ok then set_context(id) else core.error('%s',err or 'Cannot bind directory') end
      end)
    end,
    ['workspace:refresh-files']=function() files:refresh() end,
    ['workspace:mock-load']=function()
      if provider.load then prompt('Mock text file',function(path)
        local ok,err=provider:load(path);if not ok then core.error('%s',err) end
      end) end
    end,
    ['workspace:trust-server']=function() if provider.trust_server then provider:trust_server() end end,
    ['workspace:register']=function()
      if provider.register then prompt('Register nickname',function(n) provider:register(n) end) end
    end,
    ['workspace:identity']=function()
      if provider.identity then prompt('Identity ID (empty = self)',function(id)
        if not confirm_discard() then return end
        if provider:identity(id~='' and id or nil) then reset_views()
        else core.error('Invalid identity ID') end
      end) end
    end,
    ['workspace:reconnect']=function() if provider.reconnect then provider:reconnect() end end,
  })
  command.add(function() return core.active_view==list or core.active_view==filelist end,{
    ['workspace:tree-up']=function() core.active_view:move(-1) end,
    ['workspace:tree-down']=function() core.active_view:move(1) end,
    ['workspace:tree-open']=function() core.active_view:choose(false) end,
    ['workspace:tree-toggle']=function() core.active_view:choose(true) end,
  })
  keymap.add{['ctrl+return']='workspace:send',['up']='workspace:tree-up',
    ['down']='workspace:tree-down',['return']='workspace:tree-open',['space']='workspace:tree-toggle'}
  local had_rooms=#rooms>0
  return {poll=function(events)
    provider:poll(events)
    local focus=core.active_view
    if focus~=last_focus then
      last_focus=focus
      local id,s=active_room()
      if id then
        workspace:select(id);set_context(id)
        -- Pair activation uses only node-local APIs and leaves keyboard focus intact.
        local partner=focus.doc==s.draft and s.history or s.input
        local node=node_for(partner)
        if node and node~=node_for(focus) then node:set_active_view(partner);core.set_active_view(focus) end
      elseif focus.doc and origins[focus.doc] then set_context(origins[focus.doc]) end
    end
    for id,s in pairs(sessions) do
      if not node_for(s.history) and not node_for(s.input) and workspace.opened[id] then workspace:release(id) end
    end
    workspace:refresh()
    local current=provider:list()
    if not had_rooms and current[1] then had_rooms=true;select_room(current[1].id) end
    local parts={provider.status or '',provider.identity_label or '',context or ''}
    for _,r in ipairs(current) do parts[#parts+1]=r.id..':'..(r.name or '')..':'..tostring(r.unread or 0) end
    local delivery=context and provider.delivery and provider:delivery(context)
    parts[#parts+1]=delivery and delivery.state or ''
    local now=table.concat(parts,'\n')
    if now~=stamp then
      stamp=now;refresh_tree()
      list.footer=(provider.status or '')..' '..(delivery and delivery.state or '')
      list.detail=provider.identity_label or '<local>'
      filelist.title=context and ('Files: '..room_name(context)) or 'Room files'
    end
    if files:step() then core.redraw=true end
    filelist.rows=files.rows;filelist.footer=files.status
    filelist.detail=files.root and 'Workspace: Refresh Files' or 'Workspace: Bind Directory'
  end}
end
return M
