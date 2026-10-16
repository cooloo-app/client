local Doc=require 'core.doc'
local function display_text(bytes)
  local out,i={},1
  while i<=#bytes do
    local b=bytes:byte(i)
    local n=b<128 and 1 or (b>=194 and b<=223 and 2 or (b>=224 and b<=239 and 3 or (b>=240 and b<=244 and 4 or 0)))
    if n==0 then out[#out+1]='�';i=i+1
    elseif i+n-1>#bytes then break
    else
      local chunk=bytes:sub(i,i+n-1)
      if utf8.len(chunk) then out[#out+1]=chunk;i=i+n
      else out[#out+1]='�';i=i+1 end
    end
  end
  return table.concat(out)
end
local M={}
function M.new(runtime)
  local self={runtime=runtime,history={},history_index=1,output='',running={},limit=256*1024}
  self.doc=Doc();self.doc.virtual=true;self.doc.readonly=true;self.doc.filename='Lua output'
  self.input=Doc();self.input.virtual=true;self.input.filename='Lua console input'
  function self:append(text)
    self.output=(self.output..text):sub(-self.limit)
    -- Drop a partial UTF-8 leading continuation after clipping the bounded buffer.
    self.output=self.output:gsub('^[\128-\191]+','')
    local visible=display_text(self.output)
    self.doc:set_projection(visible);self.doc.projection=visible
  end
  function self:start(slot,file)
    local ok,err=self.runtime.start(slot,file)
    self.running[slot]=ok
    if not ok then self:append(tostring(err)..'\n') end
    return ok
  end
  function self:submit(text)
    if #text>4096 then self:append('console input exceeds 4096 bytes\n');return false end
    if not self.running[2] and not self:start(2) then return false end
    if not self.runtime.send(2,text) then self:append('[console input busy or unavailable]\n');return false end
    self.history[#self.history+1]=text
    if #self.history>200 then table.remove(self.history,1) end
    self.history_index=#self.history+1
    self:append('> '..text..'\n')
    return true
  end
  function self:recall(delta)
    self.history_index=math.max(1,math.min(#self.history+1,self.history_index+delta))
    self.input:set_projection(self.history[self.history_index] or '')
  end
  function self:stop(slot)
    self.runtime.stop(slot);self.running[slot]=false;self:append('[stopped '..slot..']\n')
  end
  function self:restart() self:stop(2);self:start(2) end
  function self:clear() self.output='';self:append('') end
  function self:poll()
    for slot=1,2 do
      if self.running[slot] then
        local result=self.runtime.poll(slot)
        local text=(result.stdout or '')..(result.stderr or '')
        if result.input_error then text=text..'[input failed: '..result.input_error..']\n' end
        if result.output_error then text=text..'[output failed: '..result.output_error..']\n' end
        if text~='' then self:append(text) end
        if result.exitcode~=nil then
          self.running[slot]=false;self:append(('[exit %d: %d]\n'):format(slot,result.exitcode))
        end
      end
    end
  end
  return self
end
return M
