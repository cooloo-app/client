package.path='lua/?.lua;'..package.path
local Folder=require 'workbench.folder_sync'
local Session=require 'workbench.file_session'
local Codec=require 'workbench.filesync'
assert(Folder.plan(nil,nil,'remote',1)=='download')
assert(Folder.plan(nil,'local',nil,0)=='upload')
assert(Folder.plan(nil,'local',nil,5)=='conflict')
assert(Folder.plan({data='old'},nil,'old',1)=='delete')
assert(Folder.plan({data='old'},'old',nil,2)=='remove')
assert(Folder.plan({data='old'},'edit',nil,2)=='conflict')
assert(Folder.plan({data=false},'new',nil,2)=='upload')
assert(Folder.plan({data='old'},'edit','other',2)=='conflict')
assert(not Folder.valid('configs/a') and Folder.valid('config/a'))
assert(not Folder.valid('scripts/../key'))
local files,dirs={}, {['/room']=true}
local fs={resolve_path=function(p)return p end}
fs.get_file_info=function(p)
 if files[p]~=nil then return {type='file',size=#files[p]} end
 if dirs[p] then return {type='dir',size=0} end
 return nil,'missing',true
end
fs.read_file=function(p)return files[p] end
fs.write_file=function(p,d)files[p]=d;return true end
fs.make_dir=function(p)dirs[p]=true;return true end
fs.remove_file=function(p)files[p]=nil;return true end
fs.list_dir=function(p)
 local names={};local seen={}
 for path in pairs(files) do
  local name=path:sub(1,#p+1)==p..'/' and path:sub(#p+2):match('^[^/]+')
  if name and not seen[name] then names[#names+1]=name;seen[name]=true end
 end
 for path in pairs(dirs) do
  local name=path:sub(1,#p+1)==p..'/' and path:sub(#p+2):match('^[^/]+')
  if name and not seen[name] then names[#names+1]=name;seen[name]=true end
 end
 return names
end
local f=Folder.new(fs,'/room','rooms/id/')
assert(f:reconcile('config/a','one',1)=='download')
assert(files['/room/config/a']=='one')
files['/room/config/a']='local edit'
assert(f:reconcile('config/a','remote edit',2)=='conflict')
assert(files['/room/.cooloo-conflicts/config/a.2']=='local edit')
assert(files['/room/config/a']=='remote edit')
assert(f:reconcile('config/a',nil,3)=='remove')
assert(files['/room/config/a']==nil and f:baseline('config/a').deleted)
assert(f:scan()['config/a'],'deleted baseline must participate in reconciliation')
files['/room/config/a']='recreate'
assert(f:reconcile('config/a',nil,3)=='upload')
local sent,result,err={},nil,nil
local session=Session.new(function(s)sent[#sent+1]=s;return true end,function(r,e)result=r;err=e end)
local payload=string.rep('a\0\n',349525)..'x'
assert(#payload==1024*1024)
session:request('FBEGIN','scripts/large',0,payload)
session:line('READY 0')
while session.received<#payload do session:line('READY '..session.received) end
session:line('READY '..#payload)
assert(sent[#sent]=='FCOMMIT\n')
session:line('FILE scripts/large 1 '..#payload);session:line('END');assert(result and not err)
result=nil;session:request('FREAD','scripts/large')
session:line('FILE scripts/large 1 '..#payload)
for i=1,#payload,2048 do session:line(('DATA %d %s'):format(i-1,Codec.hex(payload:sub(i,i+2047)))) end
session:line('END');assert(result.data==payload)
local State=require 'workbench.readstate'
local generation=string.rep('a',64)
local offset,gen=State.decode(State.encode(123,generation));assert(offset==123 and gen==generation)
print('folder sync: three-way edits/deletion/conflicts, restart baselines, private config paths, 1 MiB chunk roundtrip and generation JSON passed')
