local Doc = require 'core.doc'
local project = require('workbench.messages').project
local M = {}
local function text(d) return d:get_text(1, 1, #d.lines, #d.lines[#d.lines]) end
function M.new(provider)
  local self = {provider=provider, documents={}, drafts={}, selected=nil, pending={}, opened={}}
  function self:reset()
    for id, d in pairs(self.documents) do
      d:set_projection(''); d.projection=''; d.anchors={}
      self.drafts[id]:set_projection('')
      if self.provider.unsubscribe then self.provider:unsubscribe(id) end
    end
    self.documents={}; self.drafts={}; self.selected=nil; self.pending={}; self.opened={}
  end
  function self:select(id)
    if not self.opened[id] or self.selected ~= id then
      if self.provider.subscribe then self.provider:subscribe(id) end
    end
    self.opened[id]=true; self.selected=id
    if not self.documents[id] then
      local d=Doc(); d.virtual=true; d.readonly=true; d.filename='messages: '..id
      self.documents[id]=d
      local draft=Doc(); draft.virtual=true; draft.filename='draft: '..id
      self.drafts[id]=draft
    end
    self:refresh()
    return self.documents[id], self.drafts[id]
  end
  function self:release(id)
    self.opened[id]=nil
    if self.provider.unsubscribe then self.provider:unsubscribe(id) end
    if self.selected==id then self.selected=nil end
  end
  function self:has_unsent()
    if next(self.pending) then return true end
    for _, d in pairs(self.drafts) do if text(d)~='' then return true end end
    return false
  end
  function self:refresh()
    for id, pending in pairs(self.pending) do
      local delivery=self.provider:delivery(id)
      if delivery and delivery.state~='pending' then
        local draft=self.drafts[id]
        if delivery.state=='sent' and text(draft)==pending.text
          and draft:get_change_id()==pending.version then draft:set_projection('') end
        self.pending[id]=nil
      end
    end
    for id in pairs(self.opened) do
      local d=self.documents[id]
      local revision=self.provider.revision and self.provider:revision(id)
      if not revision or d.provider_revision~=revision then
        local projection=project(self.provider:open(id), {source_revision=revision})
        d.provider_revision=revision
        if d.projection~=projection.text then
          local delta=0
          for key, oldline in pairs(d.anchors or {}) do
            if projection.anchors[key] then delta=projection.anchors[key]-oldline; break end
          end
          d:set_projection(projection.text, delta)
          d.anchors=projection.anchors; d.projection=projection.text
        end
      end
    end
  end
  function self:send(id)
    id=id or self.selected
    local d=self.drafts[id]
    if not d then return false, 'select a conversation' end
    if self.pending[id] then return false, 'previous send still awaiting acknowledgment' end
    local submitted=text(d)
    local ok, status=self.provider:send(id, submitted)
    if ok then
      if self.provider.delivery then self.pending[id]={text=submitted, version=d:get_change_id()}
      else d:set_projection('') end
    end
    return ok, status
  end
  return self
end
return M
