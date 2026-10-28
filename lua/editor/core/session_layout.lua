-- One layout tree, extensible resource descriptors. Locked product chrome is
-- pruned, never serialized; composite views are described by their owner.
local core=require 'core'
local json=require 'core.state_json'
local M={}
function M.capture(root,describe)
  local active=core.active_view
  local function walk(node)
    if node.type=='leaf' then
      if node.locked then return end
      local tabs=json.array();local index=1
      for _,view in ipairs(node.views) do
        local resource=describe(view)
        if resource then
          tabs[#tabs+1]={resource=resource}
          if view==node.active_view then index=#tabs end
        end
      end
      return {type='leaf',tabs=tabs,active_tab=index},node:get_node_for_view(active) and json.array() or nil
    end
    local a,pa=walk(node.a);local b,pb=walk(node.b)
    if not a then return b,pb end
    if not b then return a,pa end
    local path=pa or pb
    if path then table.insert(path,1,pa and 'a' or 'b') end
    return {type='split',axis=node.type=='hsplit' and 'x' or 'y',ratio=node.divider,a=a,b=b},path
  end
  local layout,path=walk(root)
  return layout,path or json.array()
end
function M.restore(root,layout,path,open)
  local count=0
  local function valid(t,depth)
    if type(t)~='table' or depth>8 then return false end
    if t.type=='split' then
      return (t.axis=='x' or t.axis=='y') and type(t.ratio)=='number' and t.ratio>=0.01 and t.ratio<=0.99
        and valid(t.a,depth+1) and valid(t.b,depth+1)
    end
    if t.type~='leaf' or type(t.tabs)~='table' then return false end
    count=count+#t.tabs
    return count<=128
  end
  if not valid(layout,0) then return false end
  local function build(node,t)
    if t.type=='split' then
      node:split(t.axis=='x' and 'right' or 'down')
      node.divider=t.ratio
      build(node.a,t.a);build(node.b,t.b)
    else
      local selected
      for i,tab in ipairs(t.tabs) do
        if type(tab)=='table' and type(tab.resource)=='table' then
          local ok,view=pcall(open,tab.resource,node)
          if ok and view and i==t.active_tab then selected=view end
        end
      end
      if selected then node:set_active_view(selected) end
    end
  end
  build(root,layout)
  local node=root
  if type(path)=='table' and #path<=8 then
    for _,side in ipairs(path) do
      if node.type=='leaf' or (side~='a' and side~='b') then break end
      node=node[side]
    end
  end
  while node.type~='leaf' do node=node.a end
  node:set_active_view(node.active_view)
  return true
end
function M.file(view)
  local DV=require 'core.docview'
  if view:is(DV) and view.doc.filename and not view.doc.virtual then
    local path=system.absolute_path(view.doc.filename)
    if path then return {kind='file',path=path} end
  end
end
function M.open_file(resource,node)
  if resource.kind~='file' or type(resource.path)~='string' or #resource.path>32768 then return end
  -- Persisted paths are absolute; never reinterpret them after project chdir.
  if not resource.path:match('^/') and not resource.path:match('^%a:[/\\]') and not resource.path:match('^\\\\') then return end
  local info=system.get_file_info(resource.path)
  if not info or info.type~='file' then return end
  local view=require('core.docview')(core.open_doc(resource.path));node:add_view(view);return view
end
return M
