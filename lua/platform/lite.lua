-- Lite system facade; renderer/font/rencache execute directly in C (D04/D09/D12).
local api = cooloo
local M = {}
SCALE, EXEDIR, PATHSEP, EXEFILE, ARGS = api.platform.scale or 1, api.platform.exedir, package.config:sub(1,1), api.platform.exefile, api.args or {}
VERSION, PLATFORM = 'cooloo 0.3.7', api.platform.name
USERDIR = api.platform.userdir
if api.text_files and not api.safe_mode then
  package.path = USERDIR .. '/?.lua;' .. USERDIR .. '/?/init.lua;'
    .. EXEDIR .. '/data/?.lua;' .. EXEDIR .. '/data/?/init.lua'
  table.insert(package.searchers, 1, function(name)
    local relative = name:match('^user%.(.+)$')
    if not relative then return '\n\tnot a user module' end
    for _, root in ipairs { USERDIR, EXEDIR .. '/data/user' } do
      local path = root .. '/' .. relative:gsub('%.', '/')
      local filename
      if api.platform.info(path .. '.lua') then filename = path .. '.lua'
      elseif api.platform.info(path .. '/init.lua') then filename = path .. '/init.lua' end
      if filename then return assert(loadfile(filename)), filename end
    end
    return '\n\tno user module ' .. name
  end)
elseif api.safe_mode then
  package.path, package.cpath = '', ''
end
renderer = api.renderer
-- Explicit aliases preserve upstream style/user examples in embedded products.
local load_font = renderer.font.load
renderer.font.load = function(filename, size)
  for _, name in ipairs { 'font', 'icons', 'monospace' } do
    if filename == EXEDIR .. '/data/fonts/' .. name .. '.ttf' then
      filename = 'embedded:' .. name
      break
    end
  end
  return load_font(filename, size)
end
system = {
  platform=api.platform.name,
  make_dir=api.platform.make_dir, remove_file=api.platform.remove_file,
  temp_file=api.platform.temp_file, write_file=api.platform.write_file, read_file=api.platform.read_file,
  get_time=api.time, get_clipboard=api.clipboard.get, set_clipboard=api.clipboard.set,
  request_quit=api.quit, window_has_focus=api.platform.focus, set_unread=api.platform.set_unread,
  clear_ime=api.clear_ime, set_text_input_rect=api.set_ime_rect,
  set_cursor=api.platform.cursor, set_window_title=api.platform.title,
  set_window_mode=api.platform.mode, show_confirm_dialog=api.platform.confirm,
  list_dir=api.platform.list_dir, get_file_info=api.platform.info,
  absolute_path=api.platform.absolute_path, resolve_path=api.platform.resolve_path,
  chdir=api.platform.chdir, exec=api.platform.exec, open_project=api.platform.open_project,
  sleep=api.platform.sleep, fuzzy_match=api.platform.fuzzy_match,
  poll_event=api.poll_event, wait_event=api.wait_event,
}
return M
