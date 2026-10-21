-- One bounded request at a time on a dedicated authenticated connection.
local Codec=require 'workbench.filesync'
local M={}
function M.new(send,done)
  local s={send=send,done=done}
  function s:request(op,path,revision,data)
    self.op=op;self.path=path;self.result=nil;self.entries={};self.parts={};self.received=0;self.data=data
    local line=op..' self'..(path and ' '..path or '')
    if op=='FBEGIN' then line=line..' '..revision..' '..#data
    elseif op=='FDELETE' then line=line..' '..revision end
    return self.send(line..'\n')
  end
  function s:line(line)
    if line:match('^ERR ') then self.done(nil,line);return end
    local ready=line:match('^READY (%d+)$')
    if ready then
      local offset=tonumber(ready)
      if self.op~='FBEGIN' or offset~=self.received then self.done(nil,'invalid upload acknowledgment');return end
      if offset==#self.data then self.send('FCOMMIT\n')
      else
        local part=self.data:sub(offset+1,offset+2048);self.received=offset+#part
        self.send(('FCHUNK %d %s\n'):format(offset,Codec.hex(part)))
      end
      return
    end
    local pos,hex=line:match('^DATA (%d+) ([0-9a-f]+)$')
    if pos then
      local data=Codec.unhex(hex)
      if self.op~='FREAD' or not self.result or tonumber(pos)~=self.received or not data or self.received+#data>self.result.size then self.done(nil,'invalid file chunk');return end
      self.parts[#self.parts+1]=data;self.received=self.received+#data;return
    end
    if line=='END' then
      if self.op=='FLIST' then self.done(self.entries);return end
      if not self.result or self.result.path~=self.path then self.done(nil,'missing file result');return end
      if self.op=='FREAD' and not self.result.deleted then
        if self.received~=self.result.size then self.done(nil,'incomplete file');return end
        self.result.data=table.concat(self.parts)
      end
      self.done(self.result);return
    end
    local path,rev=line:match('^DELETED ([%w/._-]+) (%d+)$')
    local item=path and {path=path,revision=tonumber(rev),deleted=true} or Codec.parse(line)
    if not item or (item.size and item.size>1024*1024) then self.done(nil,'invalid file record');return end
    if self.op=='FLIST' then
      if #self.entries>=65536 then self.done(nil,'file list limit');return end
      self.entries[#self.entries+1]=item
    else self.result=item end
  end
  return s
end
return M
