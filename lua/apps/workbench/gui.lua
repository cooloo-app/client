-- Full product composition; plugins can also be installed independently.
local platform=require 'platform.lite'
local core=require 'core'
local host=require 'core.host'
host.init()
local provider=require(cooloo.offline and 'adapters.local' or 'adapters.cooloo').new()
local workspace=require('plugins.workspace').install(provider)
local console=require('plugins.console').install(cooloo.runtime)
function cooloo.frame(events,dt,frame_start)
  workspace.poll(events);console:poll()
  host.tick(frame_start)
end
