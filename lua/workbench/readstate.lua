-- Local, non-executable state. Stream byte endpoints are independent of views
-- and of filtered SENT records. The cache remains the source of unread records.
local M={}
function M.decode(data)
  local generation
  if data then
    generation=data:match('"generation":"([0-9a-f]+)"')
    if generation then
      if #generation~=64 then return nil end
      data=data:gsub('"version":2,"generation":"[0-9a-f]+",','"version":1,')
    end
  end
  local offset=data and data:match('^%s*{%s*"version"%s*:%s*1%s*,%s*"read_offset"%s*:%s*(%d+)%s*}%s*$')
  offset=offset and math.tointeger(tonumber(offset))
  if offset and offset>=0 and offset<=9007199254740991 then return offset,generation end
end
function M.encode(offset,generation)
  if generation then return ('{"version":2,"generation":"%s","read_offset":%d}\n'):format(generation,offset) end
  return ('{"version":1,"read_offset":%d}\n'):format(offset)
end
function M.new(path,write)
  local s={path=path,write=write,watermark=0,muted=false,pending={},unread=0}
  local f,err,code=io.open(path,'rb')
  if f then
    local data=f:read(1024);local ok=f:close()
    local offset
    offset,s.generation=M.decode(data)
    if not ok or not offset or offset<0 then return nil,'Invalid local read state: '..path end
    s.watermark=offset;s.initialized=true
  elseif code~=2 then return nil,err end
  local pref=io.open(path..'.local','rb')
  if pref then local value=pref:read(8);pref:close();s.muted=value=='1\n' end
  function s:save(offset,muted)
    local ok,message=self.write(self.path,M.encode(offset,self.generation))
    if not ok then return false,message end
    self.watermark=offset;self.muted=muted;self.initialized=true
    return true
  end
  function s:bind(generation)
    if self.generation==generation then return true end
    local previous=self.generation
    self.generation=generation
    local ok,err=self:save(0,self.muted)
    if not ok then self.generation=previous;return false,err end
    self.pending={};self.unread=0
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
  function s:mute(value)
    local ok,err=self.write(self.path..'.local',value and '1\n' or '0\n')
    if ok then self.muted=value end
    return ok,err
  end
  return s
end
return M
