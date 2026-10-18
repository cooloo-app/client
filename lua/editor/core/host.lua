-- Lite initialization/thread scheduler; the C host owns poll/frame/fixed-FPS sleep.
local core = require 'core'
local config = require 'core.config'
local M = {}
function M.init(options)
  core.init(options)
end
function M.tick(frame_start)
  core.frame_start = frame_start or system.get_time()
  local did_redraw = core.step()
  core.run_threads()
  -- Text matches Lite's inactive wait. Workbench keeps the fixed-frame network
  -- pump budget (at most one normal frame of extra background message latency).
  if cooloo.text_files and not did_redraw and not system.window_has_focus() then
    system.wait_event(0.25)
  end
  -- Keep C pacing and Lite's per-frame animation/blink increments in agreement.
  cooloo.platform.set_fps(config.fps)
end
return M
