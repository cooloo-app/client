local Doc = require 'core.doc'
local project = require('workbench.messages').project
local M = {}
local Threads=require 'workbench.threads'
local function text(d) return d:get_text(1, 1, #d.lines, #d.lines[#d.lines]) end
function M.new(provider,storage,transcripts)
  local self = {provider=provider, documents={}, drafts={}, selected=nil, pending={}, reservations={}, opened={}, view_counts={}}
  function self:reset()
    if transcripts then transcripts:reset() end
    if storage then storage:reset() end
    for id, d in pairs(self.documents) do
      d:set_projection(''); d.projection=''; d.anchors={}; d.chat_headers=nil
      self.drafts[id]:set_projection('')
      if self.provider.unsubscribe then self.provider:unsubscribe(id) end
    end
    self.documents={}; self.drafts={}; self.selected=nil; self.pending={}; self.reservations={}; self.opened={}; self.view_counts={}
  end
  function self:select(id)
    if storage and self.selected and self.selected~=id then storage:save(self.selected) end
    if not self.opened[id] or self.selected ~= id then
      if self.provider.subscribe then self.provider:subscribe(id) end
    end
    self.opened[id]=true; self.selected=id
    if not self.documents[id] then
      local d=Doc(); d.virtual=true; d.readonly=true; d.filename='messages: '..id
      self.documents[id]=d
      local draft=Doc(); draft.virtual=true; draft.filename='draft: '..id
      self.drafts[id]=draft
      if storage then storage:attach(id,draft) end
    end
    self:refresh()
    return self.documents[id], self.drafts[id]
  end
  function self:release(id)
    if transcripts then transcripts:flush() end
    self.opened[id]=nil
    if self.provider.unsubscribe then self.provider:unsubscribe(id) end
    if self.selected==id then self.selected=nil end
  end
  function self:reconcile_views(counts)
    self.view_counts=counts
    for id in pairs(self.opened) do
      if not counts[id] then self:release(id) end
    end
  end
  function self:has_unsent()
    if next(self.pending) then return true end
    for _, d in pairs(self.drafts) do if text(d)~='' then return true end end
    return false
  end
  function self:refresh()
    for id, pending in pairs(self.pending) do
      local delivery=self.provider:delivery(pending.target or id)
      if delivery and delivery.state~='pending' then
        if delivery.state=='rejected' and delivery.message_id then self.reservations[delivery.message_id]=nil end
        local draft=self.drafts[id]
        if delivery.state=='sent' and text(draft)==pending.text
          and draft:get_change_id()==pending.version then
          draft:set_projection('')
          if storage then storage:save(id) end
        end
        self.pending[id]=nil
      end
    end
    for id in pairs(self.opened) do
      local d=self.documents[id]
      local revision=self.provider.revision and self.provider:revision(id)
      local index=self.provider.thread_index and self.provider:thread_index(id)
      if not revision or d.provider_revision~=revision or (index and d.thread_index~=index)
        or (index and d.thread_revision~=index.revision) then
        local projection=project(self.provider:open(id), {source_revision=revision,thread_index=index})
        d.thread_index=projection.thread_index;d.thread_revision=index and index.revision
        d.chat_decorations=projection.decorations
        d.previous_ranges=d.ranges;d.ranges=projection.ranges
        d.provider_revision=revision
        local headers_changed=false
        local old=d.chat_headers or {}
        for line,header in pairs(projection.headers) do
          local before=old[line]
          if not before or before.sender~=header.sender or before.first~=header.first
            or before.last~=header.last then headers_changed=true;break end
        end
        if not headers_changed then
          for line in pairs(old) do
            if not projection.headers[line] then headers_changed=true;break end
          end
        end
        if headers_changed or not d.chat_headers then d.chat_headers=projection.headers end
        if transcripts then transcripts:queue(id,projection.text) end
        if d.projection~=projection.text then
          local delta=0
          local a,_,c=d:get_selection()
          local selected=Threads.at(d.previous_ranges,math.min(a,c),math.max(a,c))
          if selected and projection.anchors[selected.id] then
            delta=projection.anchors[selected.id]-selected.first_line
          else
            for key,oldline in pairs(d.anchors or {}) do
              if projection.anchors[key] then delta=projection.anchors[key]-oldline;break end
            end
          end
          d:set_projection(projection.text, delta)
          d.anchors=projection.anchors; d.projection=projection.text
        end
      end
    end
  end
  function self:reply(id,message_id,confirm)
    self:refresh()
    local d,h=self.drafts[id],self.documents[id]
    if not d or d.readonly then return false,'草稿尚不可编辑' end
    if self.pending[id] then return false,'发送中不能切换回复目标' end
    local root,err=h.thread_index:root(h.thread_index.messages[message_id])
    if not root then return false,err end
    local old,body=Threads.parse(text(d))
    if old and old~=root.id and not (confirm and confirm()) then return false,'已取消切换回复目标' end
    local value=Threads.header(root.id,body)
    d:set_selection(1,1,#d.lines,#d.lines[#d.lines]);d:text_input(value)
    d:set_selection(3,1)
    if storage and not storage:save(id) then return false,'保存草稿失败' end
    return true
  end
  function self:send(id)
    id=id or self.selected
    local d=self.drafts[id]
    if not d then return false, 'select a conversation' end
    if d.readonly then return false, 'draft is waiting for its local directory' end
    if storage and not storage:save(id) then return false, 'save draft before sending' end
    if self.pending[id] then return false, 'previous send still awaiting acknowledgment' end
    local original=text(d)
    local submitted,ref=Threads.prepare(original)
    if not submitted then return false,ref end
    if #submitted>4096 or submitted:find('%z') or not utf8.len(submitted) then
      return false,'message must contain 1..4096 UTF-8 bytes without NUL'
    end
    local target=id
    if ref then
      self:refresh()
      local index=self.documents[id].thread_index
      local root=index.messages[ref]
      if not root or Threads.parse(root.text) then return false,'原消息未加载/不可用' end
      if not index.ready then return false,index.error or '线程历史索引加载中，请稍后重试' end
      target=root.target or id
      local delivery=self.provider.delivery and self.provider:delivery(target)
      local count,ids=index:count(root,delivery)
      for uuid,reservation in pairs(self.reservations) do
        if reservation.room==id and reservation.root==ref and not ids[uuid] then
          ids[uuid]=true;count=count+1
        end
      end
      local retry=delivery and delivery.state=='unknown' and delivery.text==submitted
        and ids[delivery.message_id]
      if count>=9 and not retry then return false,'此讨论已有 9 条跟帖，建议整理后作为新消息发送' end
    end
    if target~=id and self.provider.address then
      local ok,err=self.provider:address(target)
      if not ok then return false,err end
    end
    local ok, status=self.provider:send(target, submitted)
    if ok then
      local delivery=self.provider.delivery and self.provider:delivery(target)
      if ref and delivery and delivery.message_id then
        self.reservations[delivery.message_id]={room=id,root=ref}
      end
      if self.provider.delivery then self.pending[id]={text=original, submitted=submitted,target=target,version=d:get_change_id()}
      else
        d:set_projection('')
        if storage then storage:save(id) end
      end
    end
    return ok, status
  end
  return self
end
return M
