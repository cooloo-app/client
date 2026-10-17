-- Lite initialization/thread scheduler; the C host owns poll/frame/fixed-FPS sleep.
local core = require 'core'
local config = require 'core.config'
local M = {}
function M.init(options)
  core.init(options)
end
function M.tick()
  core.frame_start = system.get_time()
  core.step()
  core.run_threads()
  -- Keep C pacing and Lite's per-frame animation/blink increments in agreement.
  cooloo.platform.set_fps(config.fps)
end
return M
