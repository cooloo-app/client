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
function M.interval(now)
  if cooloo.text_files then return 0 end
  if not system.window_has_focus() then return 0.1 end
  return now - (core.last_input or now) > 1 and 0.1 or 0
end
function M.tick(frame_start)
  core.frame_start = frame_start or system.get_time()
  core.last_input = core.last_input or core.frame_start
  local interval = M.interval(core.frame_start)
  local did_redraw = core.step(interval)
  core.run_threads()
  if not M.next_save or core.frame_start >= M.next_save then
    M.save(false)
    M.next_save = core.frame_start + 0.25
  end
  -- Text matches Lite's inactive wait. Workbench must not block its network
  -- pump here; C pacing below supplies its bounded idle receive budget.
  if cooloo.text_files and not did_redraw and not system.window_has_focus() then
    system.wait_event(0.25)
  end
  -- Keep C pacing and Lite's per-frame animation/blink increments in agreement.
  -- Network/events keep a bounded 50ms budget independent of 100ms idle UI.
  -- Re-evaluate after input so an interaction immediately restores animation FPS.
  cooloo.platform.set_fps(M.interval(core.frame_start) > 0 and math.min(config.fps,20) or config.fps)
end
return M
