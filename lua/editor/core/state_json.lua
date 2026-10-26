-- Data-only JSON for local UI snapshots. Bounded input/depth; no Lua evaluation.
local M={}
local array_mt={}
function M.array(t) return setmetatable(t or {},array_mt) end
local escapes={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
local function quote(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c) return escapes[c] or string.format('\\u%04x',c:byte()) end)..'"'
end
function M.encode(value)
  local function encode(v,depth)
    assert(depth<=32,'JSON nesting limit')
    if v==M.null then return 'null' end
    local kind=type(v)
    if kind=='string' then return quote(v) end
    if kind=='boolean' then return tostring(v) end
    if kind=='number' then assert(v==v and math.abs(v)<math.huge,'invalid number');return tostring(v) end
    assert(kind=='table','unsupported JSON value')
    local parts={}
    if getmetatable(v)==array_mt or #v>0 then
      for _,item in ipairs(v) do parts[#parts+1]=encode(item,depth+1) end
      return '['..table.concat(parts,', ')..']'
    end
    local keys={};for k in pairs(v) do assert(type(k)=='string');keys[#keys+1]=k end;table.sort(keys)
    for _,k in ipairs(keys) do parts[#parts+1]=string.rep('  ',depth+1)..quote(k)..': '..encode(v[k],depth+1) end
    if #parts==0 then return '{}' end
    return '{\n'..table.concat(parts,',\n')..'\n'..string.rep('  ',depth)..'}'
  end
  return encode(value,0)..'\n'
end
function M.decode(s)
  assert(type(s)=='string' and #s<=1024*1024,'JSON size limit')
  local i=1
  local function skip() local _,last=s:find('^[ \t\r\n]*',i);i=(last or i-1)+1 end
  local function str()
    assert(s:sub(i,i)=='"');i=i+1
    local out={}
    while i<=#s do
      local c=s:sub(i,i);i=i+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        c=s:sub(i,i);i=i+1
        local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if c=='u' then
          local h=s:sub(i,i+3);assert(h:match('^%x%x%x%x$'),'invalid unicode');i=i+4
          local n=tonumber(h,16)
          if n>=0xd800 and n<=0xdbff then
            assert(s:sub(i,i+1)=='\\u','missing surrogate');i=i+2
            h=s:sub(i,i+3);assert(h:match('^%x%x%x%x$'));i=i+4
            local low=tonumber(h,16);assert(low>=0xdc00 and low<=0xdfff)
            n=0x10000+(n-0xd800)*1024+low-0xdc00
          else assert(n<0xdc00 or n>0xdfff,'invalid surrogate') end
          out[#out+1]=utf8.char(n)
        else out[#out+1]=assert(map[c],'invalid escape') end
      else assert(c:byte()>=32,'control character');out[#out+1]=c end
    end
    error('unterminated string')
  end
  local parse
  parse=function(depth)
    assert(depth<=32,'JSON nesting limit');skip()
    local c=s:sub(i,i)
    if c=='"' then return str() end
    if c=='{' or c=='[' then
      local object=c=='{';local t=object and {} or M.array();i=i+1;skip()
      local close=object and '}' or ']'
      if s:sub(i,i)==close then i=i+1;return t end
      while true do
        skip();local k
        if object then k=str();skip();assert(s:sub(i,i)==':');i=i+1 end
        local v=parse(depth+1)
        if object then assert(t[k]==nil,'duplicate key');t[k]=v else t[#t+1]=v end
        skip();c=s:sub(i,i);i=i+1
        if c==close then return t end
        assert(c==',','expected comma')
      end
    end
    for word,v in pairs({['true']=true,['false']=false}) do
      if s:sub(i,i+#word-1)==word then i=i+#word;return v end
    end
    -- Null is represented by a private sentinel (never mistaken for a field).
    if s:sub(i,i+3)=='null' then i=i+4;return M.null end
    local token=s:sub(i):match('^-?%d+%.?%d*[eE]?[+-]?%d*')
    assert(token and not token:match('^-?0%d'),'invalid number')
    local mantissa,exponent=token:match('^(.-)[eE](.*)$')
    mantissa=mantissa or token
    assert(mantissa:match('^-?%d+$') or mantissa:match('^-?%d+%.%d+$'),'invalid mantissa')
    assert(not exponent or exponent:match('^[+-]?%d+$'),'invalid exponent')
    local n=tonumber(token);assert(n and n==n and math.abs(n)<math.huge,'invalid number');i=i+#token;return n
  end
  local v=parse(0);skip();assert(i>#s,'trailing JSON');return v
end
M.null=function() end
return M
