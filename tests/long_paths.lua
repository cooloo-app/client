-- Run via windows-long-paths.ps1 and the existing renderer-test.exe host.
local fs=native_platform
local root=assert(os.getenv('COOLOO_LONG_PATH_ROOT'))
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
package.path=source:match('^(.*)/tests/[^/]+$')..'/lua/?.lua;'..package.path
local failures=0
local function check(name,fn)
  local ok,err=pcall(fn)
  print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(err)))
  if not ok then failures=failures+1 end
end
for _,length in ipairs{245,285} do
  local dir=root..string.rep('x',length-#root)
  assert(#dir==length)
  check(length..' directory info',function() assert(fs.info(dir).type=='dir') end)
  check(length..' overwrite pre-existing file',function()
    assert(fs.write_file(dir..'/existing.txt','replacement'))
  end)
  for _,name in ipairs{'draft.txt','messages.chat'} do
    local path=dir..'/'..name
    check(length..' first create '..name,function() assert(fs.write_file(path,'first')) end)
    check(length..' overwrite '..name,function() assert(fs.write_file(path,'second')) end)
    check(length..' reopen '..name,function()
      local value
      if fs.read_file then value=assert(fs.read_file(path))
      else local f=assert(io.open(path,'rb'));value=f:read('*a');assert(f:close()) end
      assert(value=='second')
    end)
  end
  check(length..' reserve temporary file',function() assert(fs.temp_file(dir,'.tmp')) end)
  check(length..' list directory',function()
    local found={}
    for _,name in ipairs(assert(fs.list_dir(dir))) do
      assert(not name:match('^%.cooloo%-save%-'),'leftover atomic-write temporary file')
      found[name]=true
    end
    assert(found['draft.txt'] and found['messages.chat'])
  end)
  check(length..' missing draft read',function()
    local value,_,code=fs.read_file(dir..'/not-created.txt')
    assert(value==nil and code==2)
  end)
  check(length..' restart draft store',function()
    local drafts=require 'plugins.workspace.drafts'
    local provider={directory=function() return dir end}
    local storagefs={get_file_info=fs.info,read_file=fs.read_file,write_file=fs.write_file}
    local function open()
      local doc={get_change_id=function() return 1 end,
        set_projection=function(self,value) self.lines={value};self.value=value end,
        get_text=function(self) return self.value end}
      local store=drafts.new(provider,storagefs,function(message) error(message) end)
      store:attach('room',doc);assert(store:load('room',store.entries.room))
      return store,doc
    end
    local store,doc=open()
    assert(doc.value=='second')
    doc:set_projection('persisted draft\n中文')
    assert(store:save('room'))
    local _,reopened=open()
    assert(reopened.value==doc.value)
  end)
  check(length..' relative and prefixed paths',function()
    fs.chdir(root)
    local relative='./'..dir:sub(#root+1)..'/relative.txt'
    assert(fs.write_file(relative,'relative'))
    assert(fs.read_file(relative:gsub('/','\\'))=='relative')
    local prefixed='\\\\?\\'..dir:gsub('/','\\')..'/relative.txt'
    assert(fs.write_file(prefixed,'prefixed'))
    assert(fs.read_file(prefixed)=='prefixed')
    fs.chdir(root)
  end)
  check(length..' resolve existing file',function() assert(fs.absolute_path(dir..'/draft.txt')) end)
end
assert(failures==0,tostring(failures)..' long-path checks failed')
