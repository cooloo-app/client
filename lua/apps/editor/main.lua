-- Standalone general-purpose text editor. No workspace, messaging or execution.
local platform=require 'platform.lite'
local core=require 'core'
local host=require 'core.host'
host.init{app_name='cooloo-text', project=true,
          files=cooloo.text_files, safe_mode=cooloo.safe_mode}
function cooloo.frame(events,dt,frame_start)
  host.tick(frame_start)
end
