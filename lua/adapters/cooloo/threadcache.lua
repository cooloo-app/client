-- Incremental, conversation-scoped history index. Disk pages run on the cache
-- worker; decode at most 200 records per completion, not a UI-thread file scan.
local Threads=require 'workbench.threads'
local M={}
function M.new(chat,job,decode)
  local self={indexes={}}
  function self:message(id,m)
    local own=chat.identity()
    local peer=id==own and ((m.to and m.to~=own) and m.to or m.from) or nil
    return {id=m.id,from=m.nick or (chat.names or {})[m.from] or m.from,
      sender_id=m.from,text=m.text or m.content,ts=m.ts,source=m.to or id,
      context=peer,target=peer or id,cursor=m.endoff}
  end
  function self:add(id,m)
    local index=self.indexes[id]
    if not index then index=Threads.index();index.ready=false;self.indexes[id]=index end
    if m.id then index:add(self:message(id,m)) end
  end
  function self:get(id)
    local r=chat.rooms[id]
    local index=self.indexes[id]
    if not index then
      index=Threads.index();index.ready=false;self.indexes[id]=index
    end
    if r and (not index.buffer_loaded or index.buffer_revision~=r.revision) then
      for _,m in ipairs(r.buf or {}) do self:add(id,m) end
      index.buffer_revision=r.revision;index.buffer_loaded=true
    end
    if r and r.server_fp and not index.started then
      index.started=true
      local function page(before)
        job('read',r,before,200,function(ok,records)
          if self.indexes[id]~=index then return end
          if not ok then index.started=false;index.error='线程历史索引读取失败';return end
          for _,v in ipairs(records) do
            local m=decode(v.json)
            if m then m.endoff=v.offset;self:add(id,m) end
          end
          local first=records[1] and records[1].offset
          if #records==200 and first and (not before or first<before) then
            page(first)
          else index.ready=true;index.revision=index.revision+1 end
        end)
      end
      page(nil)
    end
    return index
  end
  function self:reset(id)
    if id then self.indexes[id]=nil else self.indexes={} end
  end
  return self
end
return M
