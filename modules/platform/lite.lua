-- Lite API facade over the SDL3 host. Drawing is emitted to the existing canvas.
local api = cooloo
local M = {draws={}, events={}, event_index=0}
SCALE, EXEDIR, PATHSEP, EXEFILE, ARGS = 1, api.platform.exedir, package.config:sub(1,1), api.platform.exefile, {}
USERDIR = api.platform.userdir
-- External Lua is opt-in for the workbench, enabled by default only for text.
if api.text_files and not api.safe_mode then
  package.path = USERDIR .. '/?.lua;' .. USERDIR .. '/?/init.lua;'
    .. EXEDIR .. '/data/?.lua;' .. EXEDIR .. '/data/?/init.lua'
  -- Embedded modules remain authoritative; user plugins may add new modules.
  table.insert(package.searchers, 2, function(name)
    local relative = name:match('^user%.(.+)$')
    if not relative then return '\n\tnot a user module' end
    local path = USERDIR .. '/' .. relative:gsub('%.', '/')
    local filename
    if api.platform.info(path .. '.lua') then filename = path .. '.lua'
    elseif api.platform.info(path .. '/init.lua') then filename = path .. '/init.lua' end
    if filename then return assert(loadfile(filename)), filename end
    return '\n\tno user module ' .. name
  end)
elseif api.safe_mode then
  package.path, package.cpath = '', ''
end
local function color(c) return (c[1] or 0)*65536 + (c[2] or 0)*256 + (c[3] or 0) end
local function emit(op) M.draws[#M.draws+1] = op end
local Font = {}
Font.__index = Font
function Font:get_width(s)
  return api.text_width(tostring(s):gsub('\t', string.rep(' ', self.tabs)), self.size)
end
function Font:get_height() return api.line_height(self.size) end
function Font:set_tab_width(w) self.tabs = math.max(1, math.floor(w/api.text_width(' ', self.size)+0.5)) end
renderer = {
  font={load=function(_, size) return setmetatable({size=math.floor(size),tabs=2}, Font) end},
  get_size=api.screen,
  begin_frame=function() M.draws={} end,
  end_frame=function() emit{op='present'} end,
  set_clip_rect=function(x,y,w,h) emit{op='clip',x=x,y=y,w=math.max(0,w),h=math.max(0,h)} end,
  draw_rect=function(x,y,w,h,c) emit{op='rect',x=x,y=y,w=w,h=h,color=color(c)} end,
  draw_text=function(f,s,x,y,c)
    s=tostring(s):gsub('\t',string.rep(' ',f.tabs)):gsub('\n','')
    emit{op='text',x=x,y=y,text=s,size=f.size,color=color(c)}
    return x+f:get_width(s)
  end,
}
system = {
  get_time=api.time, get_clipboard=api.clipboard.get, set_clipboard=api.clipboard.set,
  request_quit=api.quit, window_has_focus=api.platform.focus,
  set_cursor=api.platform.cursor, set_window_title=api.platform.title,
  set_window_mode=api.platform.mode, show_confirm_dialog=api.platform.confirm,
  list_dir=api.platform.list_dir, get_file_info=api.platform.info,
  absolute_path=api.platform.absolute_path, chdir=api.platform.chdir,
  exec=api.platform.exec, open_project=api.platform.open_project,
  sleep=api.platform.sleep,
  fuzzy_match=function(s,query)
    s,query=s:lower(),query:lower()
    local at, score=1,0
    for i=1,#query do
      local p=s:find(query:sub(i,i),at,true)
      if not p then return nil end
      score=score-(p-at); at=p+1
    end
    return score
  end,
  poll_event=function()
    M.event_index=M.event_index+1
    local e=M.events[M.event_index]
    if e then return table.unpack(e) end
  end,
}
-- Strict globals are installed by core after the facade is initialized.
local keymap
function M.events_begin(events)
  M.events, M.event_index, M.draws = {}, 0, {}
  keymap=keymap or require 'core.keymap'
  local function push(...) M.events[#M.events+1]={...} end
  for _, e in ipairs(events) do
    if e.type=='key' then
      -- Modifiers belong to each key event; no sticky modifier state on focus loss.
      if not M.preedit or M.preedit=='' then push('keypressed',e.key,e.mod) end
    elseif e.type=='text' then M.preedit='';push('textinput',e.text)
    elseif e.type=='filedropped' then push('filedropped',e.path,e.x,e.y)
    elseif e.type=='quit' then push('quit')
    elseif e.type=='mouse' then
      local button=({[1]='left',[2]='middle',[3]='right'})[e.button] or 'left'
      if e.kind=='down' then push('mousepressed',button,e.x,e.y,e.wx > 0 and e.wx or 1)
      elseif e.kind=='up' then push('mousereleased',button,e.x,e.y)
      elseif e.kind=='move' then push('mousemoved',e.x,e.y,e.wx,e.wy)
      elseif e.kind=='wheel' then push('mousewheel',e.wy) end
    elseif e.type=='ime_edit' then M.preedit=e.text end
  end
end
function M.install()
  local core=require 'core'
  local on_event=core.on_event
  core.on_event=function(kind, ...)
    if kind=='keypressed' then
      local _,mod=...
      if mod then
        local keys=require('core.keymap').modkeys
        keys.ctrl=(mod & 9)~=0; keys.alt=(mod & 2)~=0; keys.shift=(mod & 4)~=0
      end
    end
    return on_event(kind,...)
  end
  local DV=require 'core.docview'
  local draw=DV.draw
  function DV:draw()
    draw(self)
    if core.active_view~=self then return end
    local l,c=self.doc:get_selection()
    local x,y=self:get_line_screen_position(l)
    x=x+self:get_col_x_offset(l,c)
    api.set_ime_rect(x,y,2,self:get_line_height())
    if M.preedit and M.preedit~='' then
      renderer.draw_text(self:get_font(),M.preedit,x,y,require('core.style').accent)
    end
  end
end
return M
