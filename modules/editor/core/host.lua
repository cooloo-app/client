-- Host-owned scheduling: no second event loop and no automatic user/project code.
local core = require 'core'
local RootView = require 'core.rootview'
local CommandView = require 'core.commandview'
local StatusView = require 'core.statusview'
local command = require 'core.command'
local M = {}
function M.init()
  core.frame_start = 0
  core.clip_rect_stack = {{0, 0, 0, 0}}
  core.log_items, core.docs, core.project_files = {}, {}, {}
  core.threads = setmetatable({}, {__mode='k'})
  core.redraw = true
  core.root_view = RootView()
  core.command_view = CommandView()
  core.status_view = StatusView()
  core.root_view.root_node:split('down', core.command_view, true)
  core.root_view.root_node.b:split('down', core.status_view, true)
  command.add_defaults()
  require 'plugins.language_lua'
end
function M.tick()
  core.frame_start = system.get_time()
  for k, thread in pairs(core.threads) do
    if thread.wake <= core.frame_start then
      local ok, wait = coroutine.resume(thread.cr)
      if not ok then core.error('%s', wait) end
      if not ok or coroutine.status(thread.cr) == 'dead' then
        core.threads[k] = nil
      else thread.wake = core.frame_start + (wait or 0) end
    end
  end
  core.step()
end
return M
