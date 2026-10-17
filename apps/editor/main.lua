-- Standalone general-purpose text editor. No workspace, messaging or execution.
local platform=require 'platform.lite'
local core=require 'core'
local host=require 'core.host'
host.init{app_name='cooloo-text'}
platform.install()
local DocView=require 'core.docview'
local paths=cooloo.text_files or {}
if #paths==0 then
  core.root_view:get_active_node():add_view(DocView(core.open_doc()))
else
  for _,path in ipairs(paths) do
    local ok,doc=pcall(core.open_doc,path)
    if ok then core.root_view:get_active_node():add_view(DocView(doc))
    else core.error('%s',doc) end
  end
end
function cooloo.frame(events,dt)
  platform.events_begin(events)
  host.tick()
  return platform.draws
end
