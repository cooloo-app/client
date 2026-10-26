-- Lite initialization/thread scheduler; the C host owns poll/frame/fixed-FPS sleep.
local core = require 'core'
local config = require 'core.config'
local M = {}
function M.init(options)
  core.init(options)
  -- Minimal embedders/test hosts may intentionally provide no native window.
  if not cooloo.platform.window_size then return end
  local state=require 'core.ui_state'
  local text=cooloo.text_files~=nil
  local base=USERDIR
  if not text then
    base=os.getenv('COOLOO_CONFIG')
    if not base or base=='' then base=(os.getenv('HOME') or os.getenv('USERPROFILE') or '.')..'/.cooloo' end
    base=(system.resolve_path or system.absolute_path)(base) or base
  end
  M.state=state.new(base..'/ui-state.json',text and 'cooloo-text' or 'cooloo-workbench',system,
    function(message) core.error('%s',message) end)
  state.window(M.state,cooloo.platform,not text and cooloo.config and cooloo.config.get or nil)
  if text then
    local layout=require 'core.session_layout'
    local entry=M.state:workspace(core.project_dir,'project')
    entry.project_path=core.project_dir
    local function editor_root(node)
      if node.type=='leaf' then return not node.locked and node or nil end
      local a,b=editor_root(node.a),editor_root(node.b)
      return a and b and node or a or b
    end
    if #cooloo.text_files==0 and entry.layout then
      layout.restore(editor_root(core.root_view.root_node),entry.layout,entry.active_pane,layout.open_file)
    end
    M.snapshot=function()
      entry.layout,entry.active_pane=layout.capture(core.root_view.root_node,layout.file)
    end
  end
  local quit=system.request_quit
  system.request_quit=function() M.save(true);quit() end
end
function M.save(force)
  if not M.state then return end
  if M.snapshot then M.snapshot() end
  local w,h=cooloo.platform.window_size()
  M.state.data.window={width=w,height=h}
  M.state:save(system.get_time(),force)
end
function M.tick(frame_start)
  core.frame_start = frame_start or system.get_time()
  local did_redraw = core.step()
  core.run_threads()
  M.save(false)
  -- Text matches Lite's inactive wait. Workbench keeps the fixed-frame network
  -- pump budget (at most one normal frame of extra background message latency).
  if cooloo.text_files and not did_redraw and not system.window_has_focus() then
    system.wait_event(0.25)
  end
  -- Keep C pacing and Lite's per-frame animation/blink increments in agreement.
  cooloo.platform.set_fps(config.fps)
end
return M
