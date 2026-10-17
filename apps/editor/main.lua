-- Standalone general-purpose text editor. No workspace, messaging or execution.
local platform=require 'platform.lite'
local core=require 'core'
local host=require 'core.host'
-- The facade must wrap events before plugins (notably macro) wrap core.on_event.
platform.install()
host.init{app_name='cooloo-text', project=true,
          files=cooloo.text_files, safe_mode=cooloo.safe_mode}
if #core.docs==0 then
  core.root_view:open_doc(core.open_doc())
end
function cooloo.frame(events,dt)
  platform.events_begin(events)
  host.tick()
  return platform.draws
end
