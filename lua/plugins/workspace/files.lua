-- Session-only bindings; never change CWD or execute files/project modules.
local M={}
local function normal(path)
  path=path:gsub('\\','/'):gsub('/+$','')
  if package.config:sub(1,1)=='\\' then path=path:lower() end
  return path
end
function M.new(fs)
  local self={bindings={},generation=0,rows={},expanded={},status='No room selected'}
  function self:bind(id,path)
    local root,err=fs.absolute_path(path)
    if not root then return false,err end
    local info; info,err=fs.get_file_info(root)
    if not info or info.type~='dir' then return false,err or 'Select an existing directory' end
    self.bindings[id]=root
    self:select(id,true)
    return true
  end
  function self:reset()
    self.bindings={};self.id=nil;self:select(nil,true)
  end
  function self:select(id,force)
    if id==self.id and not force then return end
    self.id=id;self.root=id and self.bindings[id];self.expanded={};self:refresh()
  end
  function self:refresh()
    self.generation=self.generation+1;self.rows={};self.worker=nil
    local root=self.root
    if not root then self.status=self.id and 'Bind a directory via Workspace: Bind Directory' or 'No room selected';return end
    self.status=root
    self.worker=coroutine.create(function()
      local count=0
      local function scan(path,depth)
        local names,err=fs.list_dir(path)
        if not names then self.rows[#self.rows+1]={label='[unavailable] '..tostring(err),depth=depth};return end
        table.sort(names)
        for _,name in ipairs(names) do
          if name~='.' and name~='..' then
            if count>=2000 then self.status=root..' (2000 entry limit; collapse folders)';return end
            local full=path:gsub('[/\\]+$','')..'/'..name
            local info=fs.get_file_info(full)
            local canonical=fs.absolute_path(full)
            local dir=info and info.type=='dir'
            -- Canonical aliases (including directory links) are not traversed.
            local alias=canonical and normal(canonical)~=normal(full)
            local row={label=name..(alias and ' [link]' or ''),path=full,depth=depth,
              branch=dir and not alias,expanded=self.expanded[full],file=info and info.type=='file'}
            self.rows[#self.rows+1]=row;count=count+1
            coroutine.yield()
            if row.branch and row.expanded and depth<24 then scan(full,depth+1) end
          end
        end
      end
      scan(root,0)
    end)
  end
  function self:step()
    if not self.worker then return false end
    for _=1,32 do
      local ok,err=coroutine.resume(self.worker)
      if not ok then self.status=tostring(err);self.worker=nil;break end
      if coroutine.status(self.worker)=='dead' then self.worker=nil;break end
    end
    return true
  end
  function self:toggle(row)
    if row.branch then self.expanded[row.path]=not self.expanded[row.path];self:refresh() end
  end
  return self
end
return M
