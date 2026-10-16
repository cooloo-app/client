-- Deliberately no cooloo API: all data stays in memory unless explicitly loaded.
local M = {}
function M.new()
  local p={rooms={{id='<local>',name='<local>',can_send=true}},messages={},status='offline',serial=0}
  function p:capabilities(id) return {can_read=id=='<local>',can_send=id=='<local>' and not self.closed,can_history=false} end
  function p:subscribe(id) if self.closed or id~='<local>' then return false end;self.subscribed=true;return true end
  function p:unsubscribe() self.subscribed=false end
  function p:close()
    self:unsubscribe();self.closed=true
    if self.loading then self.loading:close();self.loading=nil end
  end
  function p:list() return self.rooms end
  function p:open(id) assert(id=='<local>');return self.messages end
  function p:send(id,text)
    assert(id=='<local>')
    if not self:capabilities(id).can_send then return false,'send unavailable' end
    if text=='' or #text>4096 or text:find('%z') or not utf8.len(text) then return false,'message must contain 1..4096 UTF-8 bytes without NUL' end
    self.serial=self.serial+1
    self.messages[#self.messages+1]={id=tostring(self.serial),from='<local>',text=text,ts=os.time()}
    if #self.messages>2000 then table.remove(self.messages,1) end
    return true,'sent'
  end
  function p:earlier() return {},'exhausted' end
  function p:poll()
    if not self.loading then return end
    local chunk=self.loading:read(4096)
    self.load_buffer=self.load_buffer..(chunk or '')
    while true do
      local at=self.load_buffer:find('\n',1,true)
      if not at then break end
      local line=self.load_buffer:sub(1,at-1):gsub('\r$','')
      self.load_buffer=self.load_buffer:sub(at+1)
      if line~='' then
        local ok,err=self:send('<local>',line)
        if not ok then self.status='mock import failed: '..err;self.loading:close();self.loading=nil;return end
      end
    end
    if #self.load_buffer>4096 then self.status='mock line exceeds 4096 bytes';self.loading:close();self.loading=nil;return end
    if not chunk then
      if self.load_buffer~='' then
        local ok,err=self:send('<local>',self.load_buffer)
        self.status=ok and 'mock loaded' or ('mock import failed: '..err)
      else self.status='mock loaded' end
      self.loading:close();self.loading=nil;self.load_buffer=''
    end
  end
  -- Explicit file load only, plain text, one mock message per line. Never eval fixtures.
  function p:load(path)
    local f,err=io.open(path,'rb');if not f then return false,err end
    if self.loading then self.loading:close() end
    self.loading=f;self.load_buffer='';self.status='loading mock';return true
  end
  return p
end
return M
