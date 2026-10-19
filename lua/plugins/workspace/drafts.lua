-- Workbench-only durable drafts. Native cache jobs create the room directory;
-- the existing platform writer performs atomic replacement on both platforms.
local M={}
local function text(d) return d:get_text(1,1,#d.lines,#d.lines[#d.lines]) end
function M.new(provider,fs,report)
  local self={entries={},provider=provider,fs=fs,report=report}
  function self:attach(id,doc)
    if not provider.directory then return end -- local fixtures remain in memory
    doc.readonly=true
    self.entries[id]={doc=doc,status='Waiting for conversation directory'}
  end
  function self:fail(e,message)
    if e.status~=message then self.report('Draft: '..message) end
    e.status=message
    return false
  end
  function self:load(id,e)
    local root,err=provider:directory(id)
    if not root then e.status=err;return false end
    local info=fs.get_file_info(root)
    if not info or info.type~='dir' then
      if provider.prepare_directory then provider:prepare_directory(id) end
      e.status='Waiting for local conversation directory';return false
    end
    local path=root..'/draft.txt'
    local f,openerr,code=io.open(path,'rb')
    local saved=''
    if f then
      local data,readerr=f:read('*a')
      local closed,closeerr=f:close()
      if not data or not closed then return self:fail(e,tostring(readerr or closeerr)) end
      saved=data:gsub('\r\n','\n')
    elseif code~=2 then
      return self:fail(e,tostring(openerr))
    end
    e.path=path;e.saved=saved;e.loaded=true
    e.doc:set_projection(saved);e.doc.readonly=false
    e.version=e.doc:get_change_id()
    e.status=nil
    -- Materialize even an empty draft so the room tree describes the chat.
    if not f then e.saved=nil end
    return true
  end
  function self:save(id)
    local e=self.entries[id]
    if not e then return true end
    if not e.loaded and not self:load(id,e) then return false end
    local value=text(e.doc)
    if value==e.saved then e.status=nil;return true end
    local ok,err=fs.write_file(e.path,value)
    if not ok then return self:fail(e,'Cannot save '..e.path..': '..tostring(err)) end
    e.saved=value;e.status=nil;e.version=e.doc:get_change_id()
    return true
  end
  function self:poll(now)
    for id,e in pairs(self.entries) do
      if not e.loaded then
        if now>=(e.retry or 0) then self:load(id,e);e.retry=now+1 end
      end
      if e.loaded then
        local version=e.doc:get_change_id()
        if version~=e.version then e.version=version;e.due=now+0.5 end
        if text(e.doc)~=e.saved and now>=(e.due or 0) then
          self:save(id);e.due=now+2
        end
      end
    end
  end
  function self:flush()
    local ok=true
    for id,e in pairs(self.entries) do
      -- An unopened/unavailable draft cannot contain edits (it is read-only).
      if e.loaded and not self:save(id) then ok=false end
    end
    return ok
  end
  function self:status(id)
    local e=self.entries[id]
    return e and e.status
  end
  function self:reset() self.entries={} end
  return self
end
return M
