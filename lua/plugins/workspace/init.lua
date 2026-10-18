local core=require 'core'
local M={}
function M.install(provider)
local command=require 'core.command'
local keymap=require 'core.keymap'
local DV=require 'core.docview'
local Wrapped=require 'core.wrappedview'
local View=require 'core.view'
local style=require 'core.style'
local workspace=require('plugins.workspace.model').new(provider)
local List=View:extend()
function List:new() List.super.new(self);self.size.x=220 end
function List:get_name() return 'Conversations' end
function List:update()
  List.super.update(self)
  local parts={provider.status or '',provider.identity_label or ''}
  local delivery=workspace.selected and provider.delivery and provider:delivery(workspace.selected)
  parts[#parts+1]=delivery and delivery.state or ''
  for _,room in ipairs(provider:list()) do
    parts[#parts+1]=tostring(room.id)..':'..room.name..':'..tostring(room.unread or 0)
  end
  local stamp=table.concat(parts,'\n')
  if stamp~=self.stamp then self.stamp=stamp;core.redraw=true end
end
function List:draw()
  self:draw_background(style.background2)
  renderer.draw_text(style.font,'Conversations',self.position.x+10,self.position.y+8,style.accent)
  for i,r in ipairs(provider:list()) do
    local unread=r.unread and r.unread>0 and (' ['..r.unread..']') or ''
    renderer.draw_text(style.font,r.name..unread,self.position.x+10,self.position.y+12+i*25,style.text)
  end
  renderer.draw_text(style.font,(workspace.selected and provider.delivery and provider:delivery(workspace.selected) and provider:delivery(workspace.selected).state or '')..' '..(provider.status or ''),self.position.x+10,self.position.y+self.size.y-48,style.accent)
  renderer.draw_text(style.font,provider.identity_label or '<local>',self.position.x+10,self.position.y+self.size.y-25,style.text)
end
local message_view,draft_view
local function find_edit(n)
  if n.type=='leaf' then return not n.locked and n or nil end
  return find_edit(n.a) or find_edit(n.b)
end
local function select_room(id)
  local messages,draft=workspace:select(id)
  if message_view and core.root_view.root_node:get_node_for_view(message_view)
    and core.root_view.root_node:get_node_for_view(draft_view) then
    message_view.doc=messages;draft_view.doc=draft;message_view.follow=true
    message_view.layout_stamp=nil;message_view.last_shift=nil
    core.set_active_view(draft_view)
  else
    message_view=Wrapped(messages);draft_view=DV(draft)
    local node=core.root_view:get_active_node()
    if node.locked then node=find_edit(core.root_view.root_node) end
    node:add_view(message_view)
    node:split('down',draft_view)
  end
end
function List:on_mouse_pressed(_,x,y)
  local r=provider:list()[math.floor((y-self.position.y-12)/25)]
  if r then select_room(r.id) end
end
local list=List()
core.root_view:get_active_node():split('left',list,true)
-- Set the editable region active rather than the locked sidebar.
local node=core.root_view.root_node
local edit=find_edit(node)
if edit then edit:set_active_view(edit.active_view) end
local rooms=provider:list()
if rooms[1] then select_room(rooms[1].id) end
local request_quit=system.request_quit
system.request_quit=function()
  workspace:reset()
  if provider.close then provider:close() end
  request_quit()
end
local function prompt(title,fn) core.command_view:enter(title,function(text) fn(text) end) end
command.add(nil,{
  ['workspace:send']=function()
    if core.active_view~=draft_view then return end
    local ok,status=workspace:send();core.log('%s',status or (ok and 'sent' or 'send failed'))
  end,
  ['workspace:switch']=function()
    core.command_view:enter('Conversation',function(_,item) if item then select_room(item.id) end end,
      function(text)
        local items={}
        for _,r in ipairs(provider:list()) do if r.name:find(text,1,true) then items[#items+1]={text=r.name,id=r.id} end end
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
    if workspace.selected then
      local _,status=provider:earlier(workspace.selected);workspace:refresh();core.log('%s',status)
    end
  end,
  ['workspace:mock-load']=function()
    if provider.load then prompt('Mock text file',function(path) local ok,err=provider:load(path);if not ok then core.error('%s',err) end end) end
  end,
  ['workspace:trust-server']=function() if provider.trust_server then provider:trust_server() end end,
  ['workspace:register']=function() if provider.register then prompt('Register nickname',function(n) provider:register(n) end) end end,
  ['workspace:identity']=function()
    if provider.identity then prompt('Identity ID (empty = self)',function(id)
      if provider:identity(id~='' and id or nil) then
        -- Never display the previous identity's data while the new AS is pending.
        workspace:reset()
      else core.error('Invalid identity ID') end
    end) end
  end,
  ['workspace:reconnect']=function() if provider.reconnect then provider:reconnect() end end,
})
keymap.add{['ctrl+return']='workspace:send'}
return {poll=function(events)
  provider:poll(events);workspace:refresh()
  if not workspace.selected then local r=provider:list();if r[1] then select_room(r[1].id) end end
end}
end
return M
