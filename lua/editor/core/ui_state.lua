-- Shared product-local snapshot store. UI data is separate from user settings.
local json=require 'core.state_json'
local M={json=json}
function M.new(path,product,fs,report)
  local self={path=path,data={version=1,product=product,workspaces=json.array()},blocked=false}
  local function warn(err) if report then report('UI state: '..tostring(err)) end end
  local info=fs.get_file_info(path)
  if info then
    if info.size>1024*1024 then self.blocked=true;warn('file exceeds 1 MiB; preserved')
    else
      local raw,err=fs.read_file(path)
      if not raw then self.blocked=true;warn(err or 'read failed; file preserved') end
      local ok,data=pcall(json.decode,raw)
      if ok and type(data)=='table' and data.version==1 and data.product==product then
        self.data=data
        if type(data.workspaces)~='table' then data.workspaces=json.array() end
        while #data.workspaces>16 do table.remove(data.workspaces,1) end
      elseif ok and type(data)=='table' and (data.version~=nil or data.product~=nil) then
        self.blocked=true;warn('unsupported version/product; file preserved')
      else warn(err or 'invalid JSON; using defaults') end
    end
  end
  local last
  function self:save(now,force)
    if self.blocked then return false end
    local ok,raw=pcall(json.encode,self.data)
    if not ok or #raw>1024*1024 then warn(ok and 'snapshot too large' or raw);return false end
    if raw==last then return true end
    if raw~=self.pending then self.pending=raw;self.changed=now end
    -- A five-second maximum avoids starving saves while continuously resizing.
    self.first=self.first or now
    if not force and now-self.changed<0.75 and now-self.first<5 then return true end
    local parent=path:match('^(.*)[/\\]')
    if parent and not fs.get_file_info(parent) then fs.make_dir(parent) end
    local saved,err=fs.write_file(path,raw)
    if not saved then
      if not self.warned then warn(err);self.warned=true end
      return false
    end
    last=raw;self.pending=nil;self.first=nil;self.warned=false;return true
  end
  function self:workspace(id,kind)
    local key=json.encode(id)
    for _,entry in ipairs(self.data.workspaces) do
      if type(entry)=='table' and entry.id and json.encode(entry.id)==key then return entry end
    end
    local entry={id=id,kind=kind};table.insert(self.data.workspaces,entry)
    while #self.data.workspaces>16 do table.remove(self.data.workspaces,1) end
    return entry
  end
  return self
end
function M.window(store,platform,legacy)
  local state=store.data.window
  if type(state)~='table' and legacy then
    state={width=tonumber(legacy('gui.w')),height=tonumber(legacy('gui.h'))}
  end
  local function dimension(n,min,default)
    return type(n)=='number' and n==math.floor(n) and n>=min and n<=16384 and n or default
  end
  state=type(state)=='table' and state or {}
  platform.window_size(dimension(state.width,320,960),dimension(state.height,240,640))
  platform.center_window()
end
return M
