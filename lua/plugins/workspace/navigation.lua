-- Workbench resource navigation. Resource identity is independent of focus and
-- views; reuse is local to a leaf. The registry belongs to one provider identity
-- epoch and is discarded on identity changes.
local core=require 'core'
local M={}
function M.new(create,closed,identify)
  local self={views={},target_view=nil,leaves={}}
  local function node_for(view)
    return view and core.root_view.root_node:get_node_for_view(view)
  end
  local function editable(view)
    local node=node_for(view)
    return node and node.type=='leaf' and not node.locked and node or nil
  end
  local function walk(node,fn)
    if node.type=='leaf' then fn(node) else walk(node.a,fn);walk(node.b,fn) end
  end
  function self:observe()
    local node=editable(core.active_view) or editable(core.last_active_view)
    if node then self.target_view=node.active_view end
  end
  function self:target()
    self:observe()
    local node=editable(self.target_view)
    if not node then
      walk(core.root_view.root_node,function(candidate)
        if not node and not candidate.locked then node=candidate end
      end)
    end
    assert(node,'No editor pane available')
    return node
  end
  function self:resource(view)
    if not view then return end
    local resource=self.views[view]
    if resource and resource.kind=='file' and resource.filename~=view.doc.filename then
      resource=nil -- Save As / Rename changes file identity for every shared view.
    end
    if not resource and identify then
      resource=identify(view)
      if resource then
        resource.filename=view.doc.filename
        self.views[view]=resource
      end
    end
    return resource
  end
  function self:open(resource,node,activate)
    node=node or self:target()
    assert(node.type=='leaf' and not node.locked,'Invalid target pane')
    local view
    for _,candidate in ipairs(node.views) do
      local current=self:resource(candidate)
      if current and current.key==resource.key then view=candidate;break end
      -- Native file splits create another ordinary DocView of the same Doc.
      if resource.kind=='file' and resource.doc and candidate.doc==resource.doc then
        view=candidate;self.views[view]=resource;break
      end
    end
    local previous=core.active_view
    if not view then
      view=create(resource)
      if resource.kind=='file' then resource.filename=view.doc.filename end
      self.views[view]=resource
      node:add_view(view)
    elseif activate~=false then node:set_active_view(view) end
    if activate==false then core.set_active_view(previous)
    else self.target_view=view end
    core.redraw=true
    return view
  end
  function self:split(direction)
    local node=self:target()
    local resource=self.views[node.active_view]
    assert(resource and resource.kind=='chat','Select a chat before splitting')
    node:split(direction)
    self:open(resource,core.root_view:get_active_node())
  end
  local function empty(node)
    -- Only the editor's blank leaf has this shape; never replace Console or
    -- ordinary documents. Confirm it is a newly split descendant below.
    return not node.locked and #node.views==1 and not node.active_view.doc
      and node.active_view:get_name()=='---'
  end
  function self:sync()
    -- Native Root: Split (including the command palette) makes a blank leaf for
    -- composite Views. Fill only newly split blank descendants of a Chat leaf.
    -- Called by the workspace sidebar update after events, before editor draw.
    local present={}
    local function mark(node)
      present[node]=true
      if node.type~='leaf' then mark(node.a);mark(node.b) end
    end
    mark(core.root_view.root_node)
    for node,previous in pairs(self.leaves) do
      if present[node] and node.type~='leaf' then
        local source
        walk(node,function(leaf)
          for _,view in ipairs(leaf.views) do
            if previous[view] then
              local resource=self.views[leaf.active_view]
              if resource and resource.kind=='chat' then source=resource end
              break
            end
          end
        end)
        if source then
          walk(node,function(leaf)
            if empty(leaf) then
              self:open(source,leaf,core.active_view==leaf.active_view)
            end
          end)
        end
      end
    end
    local alive,leaves,counts,keys,by_doc={},{},{},{},{}
    for view,resource in pairs(self.views) do
      if resource.kind=='file' then by_doc[view.doc]=resource end
    end
    walk(core.root_view.root_node,function(node)
      if not node.locked then
        local previous={};leaves[node]=previous
        for _,view in ipairs(node.views) do
          previous[view]=true;alive[view]=true
          local resource=self:resource(view) or (view.doc and by_doc[view.doc])
          if resource then
            self.views[view]=resource;keys[resource.key]=true
            if resource.kind=='chat' then counts[resource.room]=(counts[resource.room] or 0)+1 end
          end
        end
      end
    end)
    for view,resource in pairs(self.views) do
      if not alive[view] then self.views[view]=nil end
    end
    self.leaves=leaves
    closed(counts,keys)
    self:observe()
  end
  function self:reset()
    self.views={};self.leaves={};self.target_view=nil
  end
  return self
end
return M
