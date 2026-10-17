local function quote(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)
    if c=='"' then return '\\"' elseif c=='\\' then return '\\\\' end
    return ('\\u%04x'):format(c:byte())
  end)..'"'
end
local function usage()
  io.stderr:write('usage: cooloo-workbench message validate FILE\n',
    '       cooloo-workbench message render FILE [--format text|json]\n',
    '       cooloo-workbench --lua-run FILE\n',
    '       cooloo-workbench --lua-console (length-framed stdin)\n')
end
if #arg==1 and arg[1]=='--help' then usage();return 0 end
if arg[1]~='message' or (arg[2]~='validate' and arg[2]~='render') or not arg[3] then usage();return 2 end
local format='text'
if #arg~=3 then
  if arg[2]~='render' or #arg~=5 or arg[4]~='--format' or (arg[5]~='text' and arg[5]~='json') then usage();return 2 end
  format=arg[5]
end
local model=require 'workbench.messages'
local messages,revision=model.read(arg[3],decode_record)
if not messages then io.stderr:write(revision,'\n');return 1 end
if arg[2]=='validate' then
  assert(io.stdout:write(('valid: %d records\n'):format(#messages)))
else
  local projection=model.project(messages,{source_revision=revision})
  if format=='text' then assert(io.stdout:write(projection.text))
  else
    local anchors,ranges={},{}
    for _,r in ipairs(projection.ranges) do
      anchors[#anchors+1]=quote(r.id)..':'..r.first_line
      ranges[#ranges+1]=('{"id":%s,"first_line":%d,"last_line":%d}'):format(quote(r.id),r.first_line,r.last_line)
    end
    assert(io.stdout:write('{"text":',quote(projection.text),',"anchors":{',table.concat(anchors,','),
      '},"ranges":[',table.concat(ranges,','),'],"source_revision":',quote(revision),'}\n'))
  end
end
assert(io.stdout:flush())
return 0
