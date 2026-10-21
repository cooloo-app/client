-- User-private workspace reconciliation. Baselines are exact bytes, not mtimes.
-- A completed LIST is required before inferring any deletion. No execution.
local M={}
local function valid(path)
  if #path>120 or not (path:match('^scripts/') or path:match('^config/')) or path:find('[^%w/._-]') then return false end
  for part in (path..'/'):gmatch('(.-)/') do
    if part=='' or part=='.' or part=='..' or part:match('^%.cooloo') then return false end
  end
  return true
end
M.valid=valid
-- Pure three-way planner. nil content means absent; false baseline means tombstone.
function M.plan(base,local_data,remote_data,revision)
  if local_data==remote_data then return 'adopt' end
  if not base then return local_data==nil and 'download' or remote_data==nil and revision==0 and 'upload' or 'conflict' end
  local old=base.data
  if old==false or base.deleted then old=nil end
  if local_data==old then return remote_data==nil and 'remove' or 'download' end
  if remote_data==old then return local_data==nil and 'delete' or 'upload' end
  return 'conflict'
end
function M.new(fs,root,prefix)
  local s={fs=fs,root=root,prefix=prefix}
  local function full(path) return root..'/'..path end
  local function safe(path)
    local resolved=fs.resolve_path(full(path))
    local expected=full(path):gsub('\\','/')
    resolved=resolved and resolved:gsub('\\','/')
    if package.config:sub(1,1)=='\\' then expected=expected:lower();resolved=resolved and resolved:lower() end
    return resolved==expected
  end
  local function read(path)
    if not safe(path) then error('sync refuses linked path: '..path) end
    local info,err,missing=fs.get_file_info(full(path))
    if not info then if missing then return nil end;error(err or 'cannot stat '..path) end
    if info.type~='file' or info.size>1024*1024+(path:match('^%.cooloo%-sync/') and 128 or 0) then error('invalid sync file: '..path) end
    local data,message=fs.read_file(full(path));if data==nil then error(message) end
    return data
  end
  local function write(path,data)
    if not safe(path) then error('sync refuses linked path: '..path) end
    local parent=path:match('^(.*)/[^/]+$')
    local accum=''
    for part in (parent or ''):gmatch('[^/]+') do
      accum=accum=='' and part or accum..'/'..part
      if not safe(accum) then error('sync refuses linked directory') end
      local ok,err=fs.make_dir(full(accum));if not ok then error(err) end
    end
    assert(fs.write_file(full(path),data))
  end
  local function basepath(path) return '.cooloo-sync/'..path end
  function s:baseline(path)
    local data=read(basepath(path));if not data then return nil end
    local rev,deleted,body=data:match('^(%d+) ([01])\n(.*)$')
    if not rev then error('invalid sync baseline') end
    return {revision=tonumber(rev),data=body,deleted=deleted=='1'}
  end
  function s:remember(path,rev,data)
    write(basepath(path),('%d %d\n'):format(rev,data==nil and 1 or 0)..(data or ''))
  end
  function s:scan()
    local found={};local count=0
    local function walk(path,depth,baselines)
      if depth>16 then error('sync directory depth limit') end
      if not safe(path) then error('sync refuses linked directory') end
      local info,err,missing=fs.get_file_info(full(path))
      if not info then if missing then return end;error(err) end
      if info.type~='dir' then error('expected directory: '..path) end
      local names,message=fs.list_dir(full(path));if not names then error(message) end
      for _,name in ipairs(names) do
        if name~='.' and name~='..' then
          local p=path..'/'..name
          local relative=baselines and p:gsub('^%.cooloo%-sync/','') or p
          if valid(relative) then
            count=count+1;if count>8192 then error('sync scan entry limit') end
            if not safe(p) then error('sync refuses linked entry') end
            local entry=assert(fs.get_file_info(full(p)))
            if entry.type=='dir' then walk(p,depth+1,baselines)
            elseif entry.type=='file' then found[relative]=true end
          end
        end
      end
    end
    for _,dir in ipairs{'scripts','config'} do walk(dir,0,false);walk('.cooloo-sync/'..dir,0,true) end
    return found
  end
  function s:reconcile(path,remote,rev)
    if not valid(path) or #prefix+#path>120 then error('invalid sync path') end
    local current=read(path);local base=self:baseline(path)
    local action=M.plan(base,current,remote,rev)
    if action=='upload' or action=='delete' then return action,current end
    if action=='conflict' then
      -- Preserve the local edit outside the watched namespace before replacing.
      if current then
        local candidate='.cooloo-conflicts/'..path..'.'..tostring(rev)
        local n=0
        while read(candidate)~=nil do n=n+1;candidate='.cooloo-conflicts/'..path..'.'..tostring(rev)..'.'..n end
        write(candidate,current)
      else write('.cooloo-conflicts/'..path..'.deleted.'..tostring(rev),'Local deletion conflicted with remote change.\n') end
    end
    if action~='adopt' then
      if remote~=nil then write(path,remote)
      elseif current~=nil then assert(fs.remove_file(full(path))) end
    end
    self:remember(path,rev,remote)
    return action
  end
  return s
end
return M
