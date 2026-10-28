-- Full product composition; plugins can also be installed independently.
local platform=require 'platform.lite'
local core=require 'core'
local host=require 'core.host'
host.init()
local provider=require(cooloo.offline and 'adapters.local' or 'adapters.cooloo').new()
-- Workspace owns the outer quit guard, so canceling draft discard keeps
-- the existing console session alive.
local console=require('plugins.console').install(cooloo.runtime)
local workspace=require('plugins.workspace').install(provider)
local next_business = 0
function cooloo.frame(events,dt,frame_start)
  local interval = host.interval(frame_start)
  local business = interval == 0 or frame_start >= next_business or #events > 0
  workspace.poll(events,not business)
  if business then
    console:poll()
    next_business = frame_start + interval
  end
  host.tick(frame_start)
end
