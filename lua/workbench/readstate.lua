-- Local, non-executable state. Stream byte endpoints are independent of views
-- and of filtered SENT records. The cache remains the source of unread records.
local M={}
function M.new(path,write)
  local s={path=path,write=write,watermark=0,muted=false,pending={},unread=0}
  local f,err,code=io.open(path,'rb')
  if f then
    local data=f:read(256);local ok=f:close()
    local offset,mute
    if data then offset,mute=data:match('^v1\n(%d+)\n([01])\n$') end
    offset=offset and math.tointeger(tonumber(offset))
    if not ok or not offset or offset<0 then return nil,'Invalid local read state: '..path end
    s.watermark=offset;s.muted=mute=='1';s.initialized=true
  elseif code~=2 then return nil,err end
  function s:save(offset,muted)
    local ok,message=self.write(self.path,('v1\n%d\n%d\n'):format(offset,muted and 1 or 0))
    if not ok then return false,message end
    self.watermark=offset;self.muted=muted;self.initialized=true
    return true
  end
  function s:baseline(checkpoint)
    if self.initialized then return true end
    return self:save(checkpoint,self.muted)
  end
  function s:observe(offset,sender,identity)
    if offset<=self.watermark or sender==identity or self.pending[offset] then return false end
    self.pending[offset]=true;self.unread=self.unread+1;return true
  end
  function s:mark(checkpoint)
    checkpoint=math.max(self.watermark,checkpoint or 0)
    if checkpoint>self.watermark then
      local ok,err=self:save(checkpoint,self.muted)
      if not ok then return false,err end
    end
    for offset in pairs(self.pending) do
      if offset<=checkpoint then self.pending[offset]=nil;self.unread=self.unread-1 end
    end
    return true
  end
  function s:mute(value) return self:save(self.watermark,value) end
  return s
end
return M
