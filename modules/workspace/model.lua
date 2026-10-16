local Doc=require 'core.doc'
local M={}
function M.new(provider)
  local self={provider=provider,documents={},drafts={},selected=nil,pending={}}
  function self:reset()
    for id,d in pairs(self.documents) do
      d:set_projection('');d.projection='';d.anchors={}
      self.drafts[id]:set_projection('')
      if self.provider.unsubscribe then self.provider:unsubscribe(id) end
    end
    self.documents={};self.drafts={};self.selected=nil;self.pending={}
  end
  function self:select(id)
    if self.selected~=id then
      if self.selected and self.provider.unsubscribe then self.provider:unsubscribe(self.selected) end
      if self.provider.subscribe then self.provider:subscribe(id) end
    end
    self.selected=id
    if not self.documents[id] then
      local d=Doc();d.virtual=true;d.readonly=true;d.filename='messages: '..id
      self.documents[id]=d
      local draft=Doc();draft.virtual=true;draft.filename='draft: '..id
      self.drafts[id]=draft
    end
    self:refresh()
    return self.documents[id],self.drafts[id]
  end
  function self:refresh()
    for id,pending in pairs(self.pending) do
      local delivery=self.provider:delivery(id)
      if delivery and delivery.state~='pending' then
        local draft=self.drafts[id]
        local text=draft:get_text(1,1,#draft.lines,#draft.lines[#draft.lines])
        if delivery.state=='sent' and text==pending.text then draft:set_projection('') end
        self.pending[id]=nil
      end
    end
    if not self.selected then return end
    local d=self.documents[self.selected]
    local revision=self.provider.revision and self.provider:revision(self.selected)
    if revision and d.provider_revision==revision then return end
    d.provider_revision=revision
    local messages=self.provider:open(self.selected)
    local lines, anchors, line = {}, {}, 1
    for _,m in ipairs(messages) do
      local block=('%s  %s\n%s\n'):format(os.date('%H:%M',m.ts or 0),m.from or '?',m.text)
      lines[#lines+1]=block
      anchors[m.id]=line
      local _,count=block:gsub('\n','')
      line=line+count+1
    end
    local text=table.concat(lines,'\n')
    if d.projection~=text then
      local delta=0
      for id,oldline in pairs(d.anchors or {}) do
        if anchors[id] then delta=anchors[id]-oldline;break end
      end
      d:set_projection(text,delta)
      d.anchors=anchors
      d.projection=text
    end
  end
  function self:send()
    local d=self.drafts[self.selected]
    if not d then return false,'select a conversation' end
    local text=d:get_text(1,1,#d.lines,#d.lines[#d.lines])
    local ok,status=self.provider:send(self.selected,text)
    if ok then
      if self.provider.delivery then self.pending[self.selected]={text=text}
      else d:set_projection('') end
    end
    return ok,status
  end
  return self
end
return M
