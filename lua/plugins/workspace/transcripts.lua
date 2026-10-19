-- Derived, loaded-history snapshots. Never a source of message truth.
local M={}
function M.new(provider,fs,report)
  local self={entries={}}
  function self:reset() self.entries={} end
  function self:queue(id,value)
    if not provider.directory then return end
    local e=self.entries[id] or {}
    self.entries[id]=e
    if e.value~=value then e.value=value;e.changed=true end
  end
  function self:save(id,e)
    local root=provider:directory(id)
    if not root then return false end
    local info=fs.get_file_info(root)
    if not info or info.type~='dir' then
      if provider.prepare_directory then provider:prepare_directory(id) end
      return false
    end
    local ok,err=fs.write_file(root..'/messages.chat',e.value)
    if not ok then
      local message='Cannot save messages.chat: '..tostring(err)
      if e.error~=message then report(message) end
      e.error=message;return false
    end
    e.saved=e.value;e.error=nil
    return true
  end
  function self:poll(now)
    for id,e in pairs(self.entries) do
      -- Bound latency even while messages arrive continuously.
      if e.changed then e.due=e.due or now+0.5;e.changed=nil end
      if e.value~=e.saved and now>=(e.due or 0) then
        if self:save(id,e) then e.due=nil else e.due=now+2 end
      end
    end
  end
  function self:flush()
    for id,e in pairs(self.entries) do
      if e.value~=e.saved then self:save(id,e) end
    end
  end
  return self
end
return M
