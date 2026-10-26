package.path='lua/editor/?.lua;lua/editor/?/init.lua;'..package.path
local json=require 'core.state_json'
local State=require 'core.ui_state'
local original={version=1,unicode='中文😀',empty=json.array(),path='C:\\foo\nbar',n=1.25,flag=false}
local raw=json.encode(original)
local copy=json.decode(raw)
assert(copy.unicode==original.unicode and copy.path==original.path and copy.flag==false)
assert(json.encode(copy.empty)=='[]\n')
assert(json.decode('"\\ud83d\\ude00"')=='😀')
for _,bad in ipairs({'{"a":1,}','[1,]','{"a":1,"a":2}','01','1.','true false','"\\uDC00"',string.rep('[',40)}) do
  assert(not pcall(json.decode,bad),bad)
end
local disk,writes,warnings={},0,{}
local fs={get_file_info=function(p) return disk[p] and {size=#disk[p]} end,
 read_file=function(p)return disk[p]end,make_dir=function()return true end,
 write_file=function(p,s) writes=writes+1;disk[p]=s;return true end}
local function load() return State.new('/state/ui-state.json','test',fs,function(s)warnings[#warnings+1]=s end) end
local s=load();local entry=s:workspace({server_fp='a',identity_id='b'},'workbench');entry.layout={type='leaf'}
s:save(0,false);assert(writes==0);s:save(1,false);assert(writes==1)
s:save(2,true);assert(writes==1)
s=load();assert(#s.data.workspaces==1);assert(s:workspace({server_fp='a',identity_id='b'}).layout.type=='leaf')
assert(s:workspace({server_fp='a',identity_id='c'}).layout==nil)
for i=1,30 do s:workspace(tostring(i),'project') end
assert(#s.data.workspaces==16)
s:save(3,true);assert(writes==2)
local saved=disk[s.path]
disk[s.path]='{"version":2,"product":"test"}';s=load();assert(s.blocked);s:save(4,true);assert(writes==2)
disk[s.path]='not json';s=load();assert(not s.blocked and #warnings>0)
s:save(5,true);assert(writes==3)
disk[s.path]=saved
local width,height,center
State.window(load(),{window_size=function(w,h)width,height=w,h end,center_window=function()center=true end},function(k)return k=='gui.w' and '1234' or '789' end)
assert(width==1234 and height==789 and center)
s=load();s.data.window={width=-1,height='bad'}
State.window(s,{window_size=function(w,h)width,height=w,h end,center_window=function()end})
assert(width==960 and height==640)
print('UI state JSON/store: OK')
