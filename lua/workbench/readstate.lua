-- Local, non-executable state. Stream byte endpoints are independent of views
-- and of filtered SENT records. The cache remains the source of unread records.
local M={}
function M.decode(data)
  local offset=data and data:match('^%s*{%s*"version"%s*:%s*1%s*,%s*"read_offset"%s*:%s*(%d+)%s*}%s*$')
  offset=offset and math.tointeger(tonumber(offset))
  if offset and offset>=0 and offset<=9007199254740991 then return offset end
end
function M.encode(offset) return ('{"version":1,"read_offset":%d}\n'):format(offset) end
function M.new(path,write)
  local s={path=path,write=write,watermark=0,muted=false,pending={},unread=0}
  local f,err,code=io.open(path,'rb')
  local legacy=false
  if not f and code==2 and path:match('%.json$') then
    f,err,code=io.open(path:gsub('%.json$',''),'rb');legacy=f~=nil
  end
  if f then
    local data=f:read(1024);local ok=f:close()
    local offset,mute
    if data then
      offset,mute=data:match('^v1\n(%d+)\n([01])\n$')
      if offset then legacy=true;offset=math.tointeger(tonumber(offset))
      else offset=M.decode(data) end
    end
    if not ok or not offset or offset<0 then return nil,'Invalid local read state: '..path end
    s.watermark=offset;s.muted=mute=='1';s.initialized=true
  elseif code~=2 then return nil,err end
  if not legacy then
    local pref=io.open(path..'.local','rb')
    if pref then local value=pref:read(8);pref:close();s.muted=value=='1\n' end
  else
    local ok,message=write(path..'.local',s.muted and '1\n' or '0\n')
    if not ok then return nil,message end
    ok,message=write(path,M.encode(s.watermark))
    if not ok then return nil,message end
  end
  function s:save(offset,muted)
    local ok,message=self.write(self.path,M.encode(offset))
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
  function s:mute(value)
    local ok,err=self.write(self.path..'.local',value and '1\n' or '0\n')
    if ok then self.muted=value end
    return ok,err
  end
  return s
end
return M
