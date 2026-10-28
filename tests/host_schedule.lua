-- Host pacing regression without SDL or user configuration.
package.path='lua/editor/?.lua;lua/editor/?/init.lua;'..package.path
local now,focus,fps,steps=0,true,0,0
local core={step=function(interval) steps=steps+1;return false end,run_threads=function() end}
package.loaded.core=core
package.loaded['core.config']={fps=60}
cooloo={platform={set_fps=function(value) fps=value end}}
system={get_time=function() return now end,window_has_focus=function() return focus end}
local host=require 'core.host'
host.tick(0);assert(fps==60)
now=2;host.tick(now);assert(fps==20 and host.interval(now)==0.1)
core.last_input=now;host.tick(now);assert(fps==60)
focus=false;host.tick(now);assert(fps==20)
-- Focus returning with recent input restores foreground animation pacing.
focus=true;host.tick(now);assert(fps==60)
-- The pure text editor retains its existing inactive wait and configured FPS.
cooloo.text_files={};focus=false
local waits=0;system.wait_event=function(t) assert(t==0.25);waits=waits+1 end
host.tick(now);assert(fps==60 and waits==1)
assert(steps==6)
print('host schedule: idle/background pacing, input recovery, text isolation OK')
