local Session=require 'workbench.file_session'
local Folder=require 'workbench.folder_sync'
local M={}
function M.new(fs,root,room,send,finish)
  local prefix='rooms/'..room..'/'
  local folder=Folder.new(fs,root,prefix)
  local s={};local queue,index={},0;local stage,current,upload
  local function next_file()
    index=index+1;current=queue[index]
    if not current then finish();return end
    stage='read';assert(s.wire:request('FREAD',prefix..current))
  end
  local function received(result,err)
    if err then
      if stage=='read' and err:match('^ERR not%-found ') then result={revision=0,deleted=true}
      else finish(err);return end
    end
    if stage=='list' then
      local paths=folder:scan()
      for _,v in ipairs(result) do
        if v.path:sub(1,#prefix)==prefix then
          local path=v.path:sub(#prefix+1)
          if Folder.valid(path) then paths[path]=true end
        end
      end
      for path in pairs(paths) do queue[#queue+1]=path end
      table.sort(queue);next_file()
    elseif stage=='read' then
      local action,data=folder:reconcile(current,result.data,result.revision)
      if action=='upload' then
        upload=data;stage='write';assert(s.wire:request('FBEGIN',prefix..current,result.revision,data))
      elseif action=='delete' then
        upload=nil;stage='write';assert(s.wire:request('FDELETE',prefix..current,result.revision))
      else next_file() end
    else
      -- Remember the uploaded snapshot, not potentially newer on-disk edits.
      folder:remember(current,result.revision,upload);next_file()
    end
  end
  s.wire=Session.new(send,function(result,err)
    local ok,message=pcall(received,result,err);if not ok then finish(tostring(message)) end
  end)
  function s:start() stage='list';return self.wire:request('FLIST') end
  function s:line(line) self.wire:line(line) end
  return s
end
return M
