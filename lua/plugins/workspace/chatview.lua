-- Composite chat view. It deliberately is not a DocView: generic editor split
-- commands must not treat the currently focused child document as the chat.
local core=require 'core'
local DV=require 'core.docview'
local Wrapped=require 'plugins.workspace.historyview'
local View=require 'core.view'
local style=require 'core.style'
local ime=require 'core.ime'
local ChatView=View:extend()

function ChatView:new(history,draft,name,close)
  View.new(self)
  self.history=Wrapped(history)
  self.input=DV(draft)
  self.name,self.close=name,close
  self.ratio=0.72
  self:focus(self.input)
end
function ChatView:focus(pane)
  if self.pane~=pane then ime.stop() end
  self.pane=pane;self.doc=pane.doc;self.scroll=pane.scroll
  self.last_x_offset=pane.last_x_offset;self.cursor=pane.cursor
  core.redraw=true
end
function ChatView:get_name() return self.name() end
function ChatView:try_close(close)
  if self.close() then ime.stop();close() end
end
function ChatView:layout()
  local h=math.max(0,self.size.y-2)
  local top=math.floor(h*self.ratio)
  self.history.position.x,self.history.position.y=self.position.x,self.position.y
  self.history.size.x,self.history.size.y=self.size.x,top
  self.input.position.x,self.input.position.y=self.position.x,self.position.y+top+2
  self.input.size.x,self.input.size.y=self.size.x,h-top
end
-- Scope focus/IME identity to the child only while invoking its existing API.
-- Restore even if a child raises; command dispatch and tab ownership stay outer.
function ChatView:invoke(pane,method,...)
  self:layout()
  local active,composition=core.active_view,ime.view
  if active==self and pane==self.pane then core.active_view=pane end
  if composition==self and pane==self.pane then ime.view=pane end
  local result=table.pack(pcall(pane[method],pane,...))
  core.active_view,ime.view=active,composition
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
end
-- Commands target the facade's document and use the focused child's geometry.
for _,method in ipairs{'get_font','get_line_height','get_gutter_width',
  'get_line_screen_position','get_line_text_y_offset','get_visible_line_range',
  'get_col_x_offset','get_x_offset_col','resolve_screen_position',
  'scroll_to_line','scroll_to_make_visible','get_scrollable_size','get_content_offset'} do
  ChatView[method]=function(self,...) return self:invoke(self.pane,method,...) end
end
function ChatView:pane_at(y)
  self:layout()
  return y<self.input.position.y and self.history or self.input
end
function ChatView:on_mouse_pressed(button,x,y,clicks)
  self:layout()
  if button=='left' and math.abs(y-self.input.position.y+1)<=3 then
    self.resizing=true;return
  end
  self:focus(self:pane_at(y));self.captured=self.pane
  self:invoke(self.pane,'on_mouse_pressed',button,x,y,clicks)
end
function ChatView:on_mouse_moved(x,y,dx,dy)
  if self.resizing then
    self.ratio=math.max(0.15,math.min(0.85,(y-self.position.y)/math.max(1,self.size.y)))
    core.redraw=true;return
  end
  local pane=self.captured or self:pane_at(y)
  self:invoke(pane,'on_mouse_moved',x,y,dx,dy)
  self.cursor=pane.cursor
end
function ChatView:on_mouse_released(...)
  if self.captured then self:invoke(self.captured,'on_mouse_released',...) end
  self.captured=nil;self.resizing=false
end
function ChatView:on_mouse_wheel(...)
  self:invoke(self:pane_at(core.root_view.mouse.y),'on_mouse_wheel',...)
end
function ChatView:on_text_input(text) self:invoke(self.pane,'on_text_input',text) end
function ChatView:update()
  self:invoke(self.history,'update');self:invoke(self.input,'update')
end
function ChatView:draw()
  self:layout()
  for _,pane in ipairs{self.history,self.input} do
    core.push_clip_rect(pane.position.x,pane.position.y,pane.size.x,pane.size.y)
    local ok,err=pcall(self.invoke,self,pane,'draw')
    core.pop_clip_rect()
    if not ok then error(err,0) end
  end
  renderer.draw_rect(self.position.x,self.input.position.y-2,self.size.x,2,style.divider)
end
return ChatView
