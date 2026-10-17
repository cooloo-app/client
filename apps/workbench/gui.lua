-- Full product composition; plugins can also be installed independently.
local platform=require 'platform.lite'
local core=require 'core'
local host=require 'core.host'
host.init()
platform.install()
local provider=require(cooloo.offline and 'adapters.local' or 'adapters.cooloo').new()
local workspace=require('plugins.workspace').install(provider)
local console=require('plugins.console').install(cooloo.runtime)
function cooloo.frame(events,dt)
  workspace.poll(events);console:poll()
  platform.events_begin(events)
  core.redraw=true
  host.tick()
  return platform.draws
end
