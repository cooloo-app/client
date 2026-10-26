local core=require 'core'
local M={}
function M.install(provider)
  local command=require 'core.command'
  local keymap=require 'core.keymap'
  local DV=require 'core.docview'
  local ChatView=require 'plugins.workspace.chatview'
  local Sidebar=require 'plugins.workspace.sidebar'
  local tree=require 'plugins.workspace.tree'
  local storage=require('plugins.workspace.drafts').new(provider,system,function(message) core.error('%s',message) end)
  local transcripts=require('plugins.workspace.transcripts').new(provider,system,function(message) core.error('%s',message) end)
  local workspace=require('plugins.workspace.model').new(provider,storage,transcripts)
  local files=require('plugins.workspace.files').new(system,provider)
  local chats,file_resources,collapsed={},{},{}
  local browser,last_focus,stamp
  local host=require 'core.host'
  local layout=require 'core.session_layout'
  local json=require 'core.state_json'
  local state_entry,state_key,restored
  local notification_count,notification_serial=0,0
  local list,filelist,navigation
  local function node_for(view)
    return core.root_view.root_node:get_node_for_view(view)
  end
  local function room_name(id)
    for _,r in ipairs(provider:list()) do if r.id==id then return r.name or id end end
    return id
  end
  local function refresh_tree()
    list:set_rows(tree.build(provider:list(),collapsed))
  end
  local function browse(id)
    -- Choosing a target file pane must not navigate away from the room being
    -- browsed. Only explicit Chat navigation/activation calls this function.
    local changed=browser~=id
    if changed then
      browser=id;files:select(id)
      filelist:set_rows(files.rows);filelist.index=1
    end
    list.selected_room=id
    refresh_tree()
    if changed then
      for i,row in ipairs(list.rows) do
        if row.room and row.room.id==id then list.index=i;break end
      end
    end
    filelist.title=id and ('Files: '..room_name(id)) or 'Room files'
  end
  local function chat_resource(id)
    -- This registry is scoped to the current server/effective-identity epoch.
    chats[id]=chats[id] or {kind='chat',key='chat:'..id,room=id}
    return chats[id]
  end
  navigation=require('plugins.workspace.navigation').new(function(resource)
    if resource.kind=='file' then return DV(resource.doc) end
    local id=resource.room
    local history,draft=workspace:select(id)
    return ChatView(history,draft,function() return 'Chat: '..room_name(id) end,function()
      local entry=storage.entries[id]
      -- Actual unsubscription is reconciled after removal, when the last view
      -- is gone. Closing either of two views never closes the room session.
      return not entry or not entry.loaded or storage:save(id)
    end)
  end,function(counts,keys)
    workspace:reconcile_views(counts)
    for key in pairs(file_resources) do
      if not keys[key] then file_resources[key]=nil end
    end
  end,function(view)
    -- Also recognize files opened/split through native editor commands. All
    -- opening routes use the same canonical identity and shared Doc.
    if not view:is(DV) or not view.doc.filename then return end
    local path=system.absolute_path(view.doc.filename)
    if not path then return end
    local normalized=path:gsub('\\','/')
    if package.config:sub(1,1)=='\\' then normalized=normalized:lower() end
    local key='file:'..normalized
    file_resources[key]=file_resources[key] or {kind='file',key=key,path=path,doc=view.doc}
    return file_resources[key]
  end)
  local function active_room()
    local resource=navigation:resource(core.active_view)
    if resource and resource.kind=='chat' then return resource.room end
  end
  local function select_room(id,node)
    node=node or navigation:target()
    workspace:select(id)
    local view=navigation:open(chat_resource(id),node)
    browse(id)
    return view
  end
  local function canonical(path)
    local absolute,err=system.absolute_path(path)
    assert(absolute,err)
    local key=absolute:gsub('\\','/')
    if package.config:sub(1,1)=='\\' then key=key:lower() end
    return absolute,key
  end
  local function open_file(row)
    -- Every published row carries its own room/root. Never reinterpret a row
    -- using a later global browser context or a basename such as messages.jsonl.
    local node=navigation:target()
    local path,path_key=canonical(row.path)
    local name=path:match('[^/\\]+$')
    local native=row.room and provider.directory and provider:directory(row.room)
    local native_key=native and select(2,canonical(native))
    local _,parent_key=canonical(path:match('^(.*)[/\\]'))
    local room_file=native_key and native_key==parent_key
    if room_file and name=='draft.txt' then
      local view=select_room(row.room,node);view:focus(view.input)
      return
    end
    local key='file:'..path_key
    local protected=room_file and (name=='.meta' or name=='messages.jsonl' or name=='messages.chat' or name=='read-state.json' or name=='read-state.json.local')
    local resource=file_resources[key]
    if not resource then
      resource={kind='file',key=key,path=path,doc=core.open_doc(path)}
      file_resources[key]=resource
    end
    if protected then
      assert(not resource.doc:is_dirty(),'Save or close the edited cache file before viewing its snapshot')
      resource.doc.virtual=true;resource.doc.readonly=true;resource.protected=true
    end
    navigation:open(resource,node)
  end
  list=Sidebar('Conversations',function(row,toggle)
    if row.branch and (toggle or not row.room) then
      collapsed[row.key]=not collapsed[row.key];refresh_tree()
    elseif row.room then select_room(row.room.id) end
  end)
  filelist=Sidebar('Room files',function(row,toggle)
    if row.branch then files:toggle(row)
    elseif row.file and not toggle then core.try(open_file,row) end
  end)
  list.before_interact=function() navigation:observe() end
  filelist.before_interact=list.before_interact
  local middle=core.root_view:get_active_node():split('left',list,true)
  middle=middle:split('right',filelist,true)
  middle:set_active_view(middle.active_view)
  refresh_tree()
  local rooms=provider:list()
  -- Full provider restoration waits for authenticated identity AND a completed
  -- room listing. Offline fixtures retain their original startup behavior.
  if not provider.state_context and rooms[1] then select_room(rooms[1].id) end
  local function snapshot()
    if not state_entry or not restored then return end
    local groups=json.array()
    for key,value in pairs(collapsed) do if value then groups[#groups+1]=key end end
    table.sort(groups)
    state_entry.browser={room_id=browser,collapsed_groups=groups}
    state_entry.layout,state_entry.active_pane=layout.capture(middle,function(view)
      local resource=navigation:resource(view)
      if resource and resource.kind=='chat' then return {kind='chat',room_id=resource.room} end
      -- Cache projections keep their protected opening route, not plain files.
      if resource and resource.protected then return end
      return layout.file(view)
    end)
  end
  host.snapshot=snapshot
  local function confirm_leave()
    transcripts:flush()
    if not storage:flush() then
      core.error('Draft save failed; keep the window open and retry after fixing the directory')
      return false
    end
    if not provider.directory and workspace:has_unsent() then
      return system.show_confirm_dialog('Unsent messages','Discard in-memory local fixture drafts?')
    end
    return not next(workspace.pending) or system.show_confirm_dialog('Pending delivery',
      'Some sends are awaiting acknowledgment. Saved drafts will be kept; check delivery before resending after restart.')
  end
  local request_quit=system.request_quit
  system.request_quit=function()
    if not confirm_leave() then return end
    host.save(true);host.snapshot=nil
    workspace:reset()
    if provider.close then provider:close() end
    request_quit()
  end
  local function reset_views()
    workspace:reset()
    local closing={}
    for view,resource in pairs(navigation.views) do
      if resource.kind=='chat' or resource.kind=='file' then closing[#closing+1]=view end
    end
    for _,view in ipairs(closing) do
      local node=node_for(view)
      if node then node:set_active_view(view);node:close_active_view(core.root_view.root_node) end
    end
    chats={};file_resources={};navigation:reset();files:reset()
    browser=nil;last_focus=nil;stamp=nil;list.selected_room=nil
    filelist:set_rows(files.rows);filelist.title='Room files'
  end
  local function prompt(title,fn) core.command_view:enter(title,function(text) fn(text) end) end
  require('plugins.workspace.chatcommands').install(function(direction) navigation:split(direction) end)
  command.add(function()
    local id=active_room()
    return id and core.active_view.doc==workspace.drafts[id]
  end,{
    ['workspace:save-draft']=function()
      if storage:save(active_room()) then core.log('Draft saved') end
    end,
    ['workspace:send']=function()
      local ok,status=workspace:send(active_room())
      core.log('%s',status or (ok and 'sent' or 'send failed'))
    end,
  })
  -- Capture UUID before the palette takes focus; never retain a line number.
  local reply_target
  local function capture_reply()
    local id=active_room()
    local view=core.active_view
    if not id or not view.history or view.pane~=view.history then return end
    local a,_,b=view.doc:get_selection(true)
    local range=require('workbench.threads').at(view.doc.ranges,a,b)
    return {room=id,id=range and range.id,view=view,raw=range and range.raw}
  end
  local find_command=command.map['core:find-command'].perform
  command.map['core:find-command'].perform=function()
    reply_target=capture_reply();find_command()
    local state=core.command_view.state
    local submit,cancel=state.submit,state.cancel
    state.submit=function(...)
      submit(...);reply_target=nil
    end
    state.cancel=function(...)
      reply_target=nil;cancel(...)
    end
  end
  command.add(function()
    local view=core.active_view
    return (active_room() and view.history and view.pane==view.history)
      or (view==core.command_view and reply_target~=nil)
  end,{
    ['chat:reply-in-thread']=function()
      local target=reply_target or capture_reply();reply_target=nil
      if not target or not target.id then core.error('请选定一条消息');return end
      local ok,err=workspace:reply(target.room,target.id,function()
        return system.show_confirm_dialog('切换回复目标','保留草稿正文并切换到另一个讨论？')
      end)
      if ok then target.view:focus(target.view.input);core.set_active_view(target.view)
      else core.error('%s',err) end
    end,
    ['chat:copy-message-source']=function()
      local target=reply_target or capture_reply();reply_target=nil
      if target and target.raw then system.set_clipboard(target.raw)
      else core.error('请选定一条消息') end
    end,
  })
  keymap.add{['alt+r']='chat:reply-in-thread'}
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
      local id=active_room() or browser
      if id then local _,status=provider:earlier(id);workspace:refresh();core.log('%s',status or '') end
    end,
    ['workspace:bind-directory']=function()
      local id=browser
      if not id then core.error('Select a conversation first');return end
      prompt('Local directory for '..room_name(id)..' (session only)',function(path)
        local ok,err=files:bind(id,path)
        if ok then filelist:set_rows(files.rows) else core.error('%s',err or 'Cannot bind directory') end
      end)
    end,
    ['workspace:toggle-mute']=function()
      local id=active_room() or browser
      if id and provider.toggle_mute then
        local ok,err=provider:toggle_mute(id)
        if not ok then core.error('%s',err) end
      end
    end,
    ['workspace:refresh-files']=function() files:refresh() end,
    ['workspace:refresh-rooms']=function() if provider.refresh_rooms then provider:refresh_rooms() end end,
    ['workspace:sync-status']=function()
      if provider.diagnostics then
        local d=provider:diagnostics()
        core.log('Sync: %s; rooms=%s receive=%s persist=%s model=%s',d.phase,
          tostring(d.rooms_refreshed_at),tostring(d.last_receive),tostring(d.last_persist),tostring(d.last_model))
      end
    end,
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
        if not confirm_leave() then return end
        for view,resource in pairs(navigation.views) do
          if resource.kind=='file' and view.doc:is_dirty() then
            core.error('Save or close edited files before switching identity');return
          end
        end
        host.save(true)
        if provider:identity(id~='' and id or nil) then
          state_entry=nil;state_key=nil;restored=false;collapsed={}
          reset_views()
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
  keymap.add{['ctrl+return']='workspace:send',['ctrl+s']='workspace:save-draft',['up']='workspace:tree-up',
    ['down']='workspace:tree-down',['return']='workspace:tree-open',['space']='workspace:tree-toggle'}
  local had_rooms=#rooms>0
  local function sync_ui()
    if provider.state_context and host.state then
      local context,ready=provider:state_context()
      local key=context and json.encode(context)
      if key and key~=state_key then
        if state_key then snapshot();host.state:save(system.get_time(),true);reset_views() end
        state_key=key;state_entry=host.state:workspace(context,'workbench');restored=false;collapsed={}
        local saved=type(state_entry.browser)=='table' and state_entry.browser or {}
        if type(saved.collapsed_groups)=='table' then
          for i,group in ipairs(saved.collapsed_groups) do
            if i>2048 then break end
            if type(group)=='string' and #group<=4096 then collapsed[group]=true end
          end
        end
      end
      if state_entry and not restored and ready then
        local available={};for _,room in ipairs(provider:list()) do available[room.id]=true end
        if state_entry.layout then
          layout.restore(middle,state_entry.layout,state_entry.active_pane,function(resource,node)
            if resource.kind=='chat' and available[resource.room_id] then
              return navigation:open(chat_resource(resource.room_id),node)
            end
            return layout.open_file(resource,node)
          end)
        end
        navigation:sync()
        local saved=type(state_entry.browser)=='table' and state_entry.browser or {}
        if saved.room_id and available[saved.room_id] then browse(saved.room_id) end
        local current=provider:list()
        if not next(navigation.views) and current[1] then select_room(current[1].id) end
        if not browser and current[1] then browse(current[1].id) end
        last_focus=core.active_view;had_rooms=true;restored=true
      end
    end
    navigation:sync()
    local focus=core.active_view
    if focus~=last_focus then
      -- Save on leaving either view of a shared room; the store owns one draft.
      local previous=navigation:resource(last_focus)
      if previous and previous.kind=='chat' then storage:save(previous.room) end
      last_focus=focus
      local id=active_room()
      if id then workspace:select(id);browse(id) end
    end
    if provider.reading then provider:reading(active_room(),system.window_has_focus()) end
    if provider.notifications and system.set_unread then
      local count,serial=provider:notifications()
      if count~=notification_count or serial~=notification_serial then
        system.set_unread(count,count>0 and serial>notification_serial and not system.window_has_focus())
        notification_count,notification_serial=count,serial
      end
    end
    local current=provider:list()
    if not provider.state_context and not had_rooms and current[1] then had_rooms=true;select_room(current[1].id) end
    local parts={provider.status or '',provider.identity_label or '',browser or ''}
    for _,r in ipairs(current) do parts[#parts+1]=r.id..':'..(r.name or '')..':'..tostring(r.unread or 0)..':'..tostring(r.muted) end
    local delivery=browser and provider.delivery and provider:delivery(browser)
    parts[#parts+1]=delivery and delivery.state or ''
    local now=table.concat(parts,'\n')
    if now~=stamp then
      stamp=now;refresh_tree()
      list.footer=(provider.status or '')..' '..(delivery and delivery.state or '')
      list.detail=provider.identity_label or '<local>'
      filelist.title=browser and ('Files: '..room_name(browser)) or 'Room files'
    end
    local footer=storage:status(browser) or files.status
    if filelist.footer~=footer then core.redraw=true end
    if filelist.rows~=files.rows then filelist:set_rows(files.rows) end
    filelist.footer=footer
    filelist.detail=files.root and 'Workspace: Refresh Files' or (provider.directory and 'Local conversation files' or 'Workspace: Bind Directory')
  end
  -- Own sidebar lifecycle, not an editor patch: reconcile after input events
  -- and before central views update/draw, including native palette splits.
  list.before_update=sync_ui
  navigation:sync()
  return {poll=function(events)
    provider:poll(events)
    sync_ui()
    workspace:refresh()
    local clock=system.get_time()
    storage:poll(clock);transcripts:poll(clock);files:poll(clock)
    if files:step() then core.redraw=true end
  end}
end
return M
