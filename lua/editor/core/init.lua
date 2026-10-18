require "core.strict"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local command
local keymap
local RootView
local StatusView
local CommandView
local Doc

local core = {}


local function project_scan_thread()
  local function diff_files(a, b)
    if #a ~= #b then return true end
    for i, v in ipairs(a) do
      if b[i].filename ~= v.filename
      or b[i].modified ~= v.modified then
        return true
      end
    end
  end

  local function compare_file(a, b)
    return a.filename < b.filename
  end

  local visited
  local function get_files(path, t)
    coroutine.yield()
    t = t or {}
    local absolute = system.absolute_path(path)
    if not absolute or visited[absolute] then return t end
    visited[absolute] = true
    local size_limit = config.file_size_limit * 10e5
    local all = system.list_dir(path) or {}
    local dirs, files = {}, {}

    for _, file in ipairs(all) do
      if not common.match_pattern(file, config.ignore_files) then
        local file = (path ~= "." and path .. PATHSEP or "") .. file
        local info = system.get_file_info(file)
        if info and info.size < size_limit then
          info.filename = file
          table.insert(info.type == "dir" and dirs or files, info)
        end
      end
    end

    table.sort(dirs, compare_file)
    for _, f in ipairs(dirs) do
      table.insert(t, f)
      get_files(f.filename, t)
    end

    table.sort(files, compare_file)
    for _, f in ipairs(files) do
      table.insert(t, f)
    end

    return t
  end

  while true do
    -- get project files and replace previous table if the new table is
    -- different
    visited = {}
    local t = get_files(".")
    if diff_files(core.project_files, t) then
      core.project_files = t
      core.redraw = true
    end

    -- wait for next scan
    coroutine.yield(config.project_scan_rate)
  end
end


function core.init(options)
  options = options or {}
  core.app_name = options.app_name or 'cooloo'
  core.safe_mode = options.safe_mode or false
  core.project_enabled = options.project or false
  command = require "core.command"
  keymap = require "core.keymap"
  RootView = require "core.rootview"
  StatusView = require "core.statusview"
  CommandView = require "core.commandview"
  Doc = require "core.doc"

  -- Resolve every argument before chdir, including files that do not exist yet.
  local project_dir = system.absolute_path('.')
  local files = {}
  for _, path in ipairs(options.files or {}) do
    local absolute = assert((system.resolve_path or system.absolute_path)(path))
    local info = system.get_file_info(absolute) or {}
    if info.type == 'dir' then
      project_dir = absolute
    else
      table.insert(files, absolute)
    end
  end
  if core.project_enabled then
    system.chdir(project_dir)
    core.project_dir = system.absolute_path('.')
  end

  core.frame_start = 0
  core.clip_rect_stack = {{ 0,0,0,0 }}
  core.log_items = {}
  core.docs = {}
  core.threads = setmetatable({}, { __mode = "k" })
  core.project_files = {}
  core.redraw = true

  core.root_view = RootView()
  core.command_view = CommandView()
  core.status_view = StatusView()

  core.root_view.root_node:split("down", core.command_view, true)
  core.root_view.root_node.b:split("down", core.status_view, true)

  if core.project_enabled then core.add_thread(project_scan_thread) end
  command.add_defaults()
  local got_plugin_error, got_user_error, got_project_error = false, false, false
  if core.project_enabled then
    got_plugin_error = not core.load_plugins()
    if not core.safe_mode then
      got_user_error = not core.load_user_module()
      got_project_error = not core.load_project_module()
    end
  else
    -- Full workbench does not discover or execute external editor extensions.
    require 'plugins.language_lua'
  end

  for _, filename in ipairs(files) do
    core.try(function() core.root_view:open_doc(core.open_doc(filename)) end)
  end

  if got_plugin_error or got_user_error or got_project_error then
    command.perform("core:open-log")
  end
end


local temp_files = {}

local function delete_temp_files()
  for filename in pairs(temp_files) do
    if os.remove(filename) or not system.get_file_info(filename) then
      temp_files[filename] = nil
    end
  end
end

core.cleanup = delete_temp_files

function core.temp_filename(ext)
  local filename = system.temp_file(EXEDIR, ext or "")
  temp_files[filename] = true
  return filename
end


function core.quit(force)
  if force then
    delete_temp_files()
    system.request_quit()
    return
  end
  local dirty_count = 0
  local dirty_name
  for _, doc in ipairs(core.docs) do
    if doc:is_dirty() then
      dirty_count = dirty_count + 1
      dirty_name = doc:get_name()
    end
  end
  if dirty_count > 0 then
    local text
    if dirty_count == 1 then
      text = string.format("\"%s\" has unsaved changes. Quit anyway?", dirty_name)
    else
      text = string.format("%d docs have unsaved changes. Quit anyway?", dirty_count)
    end
    local confirm = system.show_confirm_dialog("Unsaved Changes", text)
    if not confirm then return end
  end
  core.quit(true)
end


function core.load_plugins()
  local no_errors = true
  local names = {}
  for _, name in ipairs(require 'core.plugin_manifest') do names[name] = true end
  if not core.safe_mode then
    for _, dir in ipairs { EXEDIR .. '/data/plugins', USERDIR .. '/plugins' } do
      for _, filename in ipairs(system.list_dir(dir) or {}) do
        local name = filename:match('^(.*)%.lua$')
        if not name then
          local info = system.get_file_info(dir .. '/' .. filename .. '/init.lua')
          if info and info.type == 'file' then name = filename end
        end
        if name then names['plugins.' .. name] = true end
      end
    end
  end
  local sorted = {}
  for name in pairs(names) do table.insert(sorted, name) end
  table.sort(sorted)
  for _, modname in ipairs(sorted) do
    local ok = core.try(require, modname)
    if ok then
      core.log_quiet("Loaded plugin %q", modname)
    else
      no_errors = false
    end
  end
  return no_errors
end


function core.load_user_module()
  for _, filename in ipairs { USERDIR .. '/init.lua', EXEDIR .. '/data/user/init.lua' } do
    if system.get_file_info(filename) then
      core.user_module = filename
      package.preload.user = function() return assert(loadfile(filename))() end
      return core.try(require, 'user')
    end
  end
  return true
end


function core.load_project_module()
  local filename = ".lite_project.lua"
  if system.get_file_info(filename) then
    return core.try(function()
      local fn, err = loadfile(filename)
      if not fn then error("Error when loading project module:\n\t" .. err) end
      fn()
      core.log_quiet("Loaded project module")
    end)
  end
  return true
end


function core.reload_module(name)
  local old = package.loaded[name]
  package.loaded[name] = nil
  local new = require(name)
  if type(old) == "table" then
    for k, v in pairs(new) do old[k] = v end
    package.loaded[name] = old
  end
end


function core.set_active_view(view)
  assert(view, "Tried to set active view to nil")
  if view ~= core.active_view then
    require('core.ime').stop() -- Lite XL: cancel composition before changing view.
    core.last_active_view = core.active_view
    core.active_view = view
  end
end


function core.add_thread(f, weak_ref)
  local key = weak_ref or #core.threads + 1
  local fn = function() return core.try(f) end
  core.threads[key] = { cr = coroutine.create(fn), wake = 0 }
end


function core.push_clip_rect(x, y, w, h)
  local x2, y2, w2, h2 = table.unpack(core.clip_rect_stack[#core.clip_rect_stack])
  local r, b, r2, b2 = x+w, y+h, x2+w2, y2+h2
  x, y = math.max(x, x2), math.max(y, y2)
  b, r = math.min(b, b2), math.min(r, r2)
  w, h = r-x, b-y
  table.insert(core.clip_rect_stack, { x, y, w, h })
  renderer.set_clip_rect(x, y, w, h)
end


function core.pop_clip_rect()
  table.remove(core.clip_rect_stack)
  local x, y, w, h = table.unpack(core.clip_rect_stack[#core.clip_rect_stack])
  renderer.set_clip_rect(x, y, w, h)
end


function core.open_doc(filename)
  if filename then
    -- try to find existing doc for filename
    local abs_filename = assert((system.resolve_path or system.absolute_path)(filename))
    for _, doc in ipairs(core.docs) do
      if doc.filename
      and abs_filename == (system.resolve_path or system.absolute_path)(doc.filename) then
        return doc
      end
    end
  end
  -- no existing doc for filename; create new
  local doc = require('core.doc')()
  if filename then
    local info, err, missing = system.get_file_info(filename)
    if info then
      assert(info.type == 'file', 'not a regular file: ' .. filename)
      doc:load(filename)
    else
      assert(missing, err)
      local parent = filename
      while true do
        parent = parent:match('^(.*)[/\\]') or '.'
        if parent == '' then parent = PATHSEP end
        local parent_info, parent_err, parent_missing = system.get_file_info(parent)
        if parent_info then
          assert(parent_info.type == 'dir', 'invalid parent directory')
          break
        end
        assert(parent_missing and parent ~= PATHSEP and parent ~= '.', parent_err)
      end
      doc.filename = filename
      doc:reset_syntax()
    end
  end
  table.insert(core.docs, doc)
  core.log_quiet(filename and "Opened doc \"%s\"" or "Opened new doc", filename)
  return doc
end


function core.get_views_referencing_doc(doc)
  local res = {}
  local views = core.root_view.root_node:get_children()
  for _, view in ipairs(views) do
    if view.doc == doc then table.insert(res, view) end
  end
  return res
end


local function log(icon, icon_color, fmt, ...)
  local text = string.format(fmt, ...)
  if icon then
    core.status_view:show_message(icon, icon_color, text)
  end

  local info = debug.getinfo(2, "Sl")
  local at = string.format("%s:%d", info.short_src, info.currentline)
  local item = { text = text, time = os.time(), at = at }
  table.insert(core.log_items, item)
  if #core.log_items > config.max_log_items then
    table.remove(core.log_items, 1)
  end
  return item
end


function core.log(...)
  return log("i", style.text, ...)
end


function core.log_quiet(...)
  return log(nil, nil, ...)
end


function core.error(...)
  return log("!", style.accent, ...)
end


function core.try(fn, ...)
  local err
  local ok, res = xpcall(fn, function(msg)
    local item = core.error("%s", msg)
    item.info = debug.traceback(nil, 2):gsub("\t", "")
    err = msg
  end, ...)
  if ok then
    return true, res
  end
  return false, err
end


function core.on_event(type, ...)
  local did_keymap = false
  if type == "textinput" then
    require('core.ime').reset()
    core.root_view:on_text_input(...)
  elseif type == "textediting" then
    require('core.ime').on_text_editing(...)
  elseif type == "focuslost" then
    require('core.ime').stop()
    require('core.keymap').reset_state()
  elseif type == "keypressed" then
    -- Lite XL suppresses editing shortcuts during composition. Keep modifier
    -- press/release pairs observable even while those shortcuts are suppressed.
    local key = ...
    did_keymap = require('core.keymap').on_key_pressed(key, not require('core.ime').editing)
  elseif type == "keyreleased" then
    require('core.keymap').on_key_released(...)
  elseif type == "mousemoved" then
    core.root_view:on_mouse_moved(...)
  elseif type == "mousepressed" then
    require('core.ime').stop()
    core.root_view:on_mouse_pressed(...)
  elseif type == "mousereleased" then
    core.root_view:on_mouse_released(...)
  elseif type == "mousewheel" then
    core.root_view:on_mouse_wheel(...)
  elseif type == "filedropped" then
    local filename, mx, my = ...
    local info = system.get_file_info(filename)
    if info and info.type == "dir" then
      assert(core.project_enabled, 'Directory projects are opened by cooloo-text, not the workbench')
      system.open_project(filename, core.safe_mode)
    else
      local ok, doc = core.try(core.open_doc, filename)
      if ok then
        local node = core.root_view.root_node:get_child_overlapping_point(mx, my)
        -- Locked sidebars/status bars are not document panes.
        if node and not node.locked then node:set_active_view(node.active_view) end
        core.root_view:open_doc(doc)
      end
    end
  elseif type == "quit" then
    require('core.ime').stop()
    core.quit()
  end
  return did_keymap
end


function core.step()
  -- handle events
  local did_keymap = false
  local mouse_moved = false
  local mouse = { x = 0, y = 0, dx = 0, dy = 0 }

  for type, a,b,c,d in system.poll_event do
    if type == "mousemoved" then
      mouse_moved = true
      mouse.x, mouse.y = a, b
      mouse.dx, mouse.dy = mouse.dx + c, mouse.dy + d
    elseif type == "textinput" and did_keymap then
      did_keymap = false
    else
      local _, res = core.try(core.on_event, type, a, b, c, d)
      did_keymap = res or did_keymap
      -- A composition boundary ends shortcut text suppression; its eventual
      -- commit is IME text, not the text generated by an earlier shortcut.
      if type == "textediting" then did_keymap = false end
    end
    core.redraw = true
  end
  if mouse_moved then
    core.try(core.on_event, "mousemoved", mouse.x, mouse.y, mouse.dx, mouse.dy)
  end

  local width, height = renderer.get_size()

  -- update
  core.root_view.size.x, core.root_view.size.y = width, height
  core.root_view:update()
  if not core.redraw then return false end
  core.redraw = false

  -- close unreferenced docs
  for i = #core.docs, 1, -1 do
    local doc = core.docs[i]
    if #core.get_views_referencing_doc(doc) == 0 then
      table.remove(core.docs, i)
      core.log_quiet("Closed doc \"%s\"", doc:get_name())
    end
  end

  -- update window title
  local name = core.active_view:get_name()
  local app_name = core.app_name or 'cooloo-text'
  if core.project_dir then app_name = app_name .. ' [' .. core.project_dir .. ']' end
  local title = (name ~= "---") and (name .. " - " .. app_name) or app_name
  if title ~= core.window_title then
    system.set_window_title(title)
    core.window_title = title
  end

  -- draw
  renderer.begin_frame()
  core.clip_rect_stack[1] = { 0, 0, width, height }
  renderer.set_clip_rect(table.unpack(core.clip_rect_stack[1]))
  core.root_view:draw()
  renderer.end_frame()
  return true
end


local run_threads = coroutine.wrap(function()
  while true do
    local max_time = 1 / config.fps - 0.004
    local ran_any_threads = false

    for k, thread in pairs(core.threads) do
      -- run thread
      if thread.wake < system.get_time() then
        local _, wait = assert(coroutine.resume(thread.cr))
        if coroutine.status(thread.cr) == "dead" then
          if type(k) == "number" then
            table.remove(core.threads, k)
          else
            core.threads[k] = nil
          end
        elseif wait then
          thread.wake = system.get_time() + wait
        end
        ran_any_threads = true
      end

      -- stop running threads if we're about to hit the end of frame
      if system.get_time() - core.frame_start > max_time then
        coroutine.yield()
      end
    end

    if not ran_any_threads then coroutine.yield() end
  end
end)


core.run_threads = run_threads

function core.run()
  while true do
    core.frame_start = system.get_time()
    local did_redraw = core.step()
    run_threads()
    if not did_redraw and not system.window_has_focus() then
      system.wait_event(0.25)
    end
    local elapsed = system.get_time() - core.frame_start
    system.sleep(math.max(0, 1 / config.fps - elapsed))
  end
end


function core.on_error(err)
  -- Recovery must not mutate documents, overwrite originals, or stop after one
  -- unwritable path. Virtual projections contain no unsaved user file data.
  local diagnostic = 'Error: ' .. tostring(err) .. '\n'
  local error_base = EXEDIR .. '/error.txt'
  local error_written = false
  -- Never truncate a user file or follow a symlink.  Use the conventional
  -- name only when it can be created exclusively, then retain the error with
  -- a numbered sibling if that name is occupied.
  for suffix = 0, 9999 do
    local path = error_base .. (suffix == 0 and '' or '~' .. suffix)
    local called, ok, why, collision = pcall(system.write_file, path, diagnostic, true)
    if called and ok then error_written = true; break end
    if not called or not collision then
      io.stderr:write('recovery: ', path, ': ', tostring(called and why or ok), '\n')
      break
    end
  end
  if not error_written then
    io.stderr:write('recovery: could not write fatal diagnostic\n')
  end
  for index, doc in ipairs(core.docs or {}) do
    if not doc.virtual and doc:is_dirty() then
      local base = (doc.filename or (EXEDIR .. '/unsaved-' .. index)) .. '~'
      local text = table.concat(doc.lines):sub(1, -2)
      if doc.crlf then text = text:gsub('\n', '\r\n') end
      -- The file is created and written under one exclusive native handle.
      -- A stale existence check must never authorize truncating a backup.
      for suffix = 0, 9999 do
        local path = base .. (suffix == 0 and '' or suffix)
        local called, ok, why, collision = pcall(system.write_file, path, text, true)
        if called and ok then break end
        if not called or not collision or suffix == 9999 then
          io.stderr:write('recovery: ', path, ': ', tostring(called and why or ok), '\n')
          break
        end
      end
    end
  end
  delete_temp_files()
end


return core
