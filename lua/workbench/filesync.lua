-- Bounded, line-framed opaque file client. One request at a time; no message API.
local M={}
function M.hex(s) return (s:gsub('.',function(c)return ('%02x'):format(c:byte())end)) end
function M.unhex(s)
  if s=='-' then return '' end
  if #s%2~=0 or s:find('[^0-9a-f]') then return nil end
  return (s:gsub('..',function(v)return string.char(tonumber(v,16))end))
end
function M.request(net,conn,op,path,revision,data)
  local line=op..' self'
  if path then line=line..' '..path end
  if op=='FPUT' then
    if #data>4096 then return false,'file too large' end
    line=line..' '..revision..' '..(#data==0 and '-' or M.hex(data))
  end
  return net.send(conn,line..'\n')
end
function M.parse(line)
  local path,rev,size,data=line:match('^FILE ([%w/._-]+) (%d+) (%d+) ?(.*)$')
  if not path then return nil end
  rev=tonumber(rev);size=tonumber(size)
  if data~='' then data=M.unhex(data);if not data or #data~=size then return nil end else data=nil end
  return {path=path,revision=rev,size=size,data=data}
end
return M
