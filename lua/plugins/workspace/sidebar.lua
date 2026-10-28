local core=require 'core'
local View=require 'core.view'
local style=require 'core.style'
local Sidebar=View:extend()
local function row_key(row)
  if not row then return end
  if row.path then return 'file:'..row.path end
  if row.room then return 'room:'..row.room.id end
  return row.key and 'group:'..row.key
end
function Sidebar:new(title, activate)
  Sidebar.super.new(self)
  self.title=title;self.activate=activate;self.rows={};self.index=1
  self.size.x=240*SCALE;self.scrollable=true;self.footer='';self.detail=''
end
function Sidebar:height() return math.max(24*SCALE,style.font:get_height()+8*SCALE) end
function Sidebar:update()
  if self.before_update then self.before_update() end
  -- Fit both sidebars without changing the editor's layout machinery.
  local width=math.min(240*SCALE,math.max(80*SCALE,core.root_view.size.x*0.22))
  -- Split layout subtraction can leave a subpixel floating-point tail.
  if math.abs(self.size.x-width)>0.01 then self.size.x=width;core.redraw=true end
  Sidebar.super.update(self)
end
function Sidebar:get_name() return self.title end
function Sidebar:get_scrollable_size() return (#self.rows+4)*self:height() end
function Sidebar:set_rows(rows)
  local selected=row_key(self.rows[self.index])
  if selected then
    for i,row in ipairs(rows) do
      if row_key(row)==selected then self.index=i;break end
    end
  end
  self.rows=rows;self.index=math.max(1,math.min(self.index,#rows));core.redraw=true
end
function Sidebar:move(delta)
  self.index=math.max(1,math.min(#self.rows,self.index+delta))
  local y=self.index*self:height()
  if y<self.scroll.to.y+self:height() then self.scroll.to.y=y-self:height() end
  if y>self.scroll.to.y+self.size.y-3*self:height() then self.scroll.to.y=y-self.size.y+3*self:height() end
  core.redraw=true
end
function Sidebar:choose(toggle)
  if self.before_interact then self.before_interact() end
  local row=self.rows[self.index]
  if row then self.activate(row,toggle) end
end
function Sidebar:on_mouse_pressed(button,x,y,clicks)
  if self.before_interact then self.before_interact() end
  if Sidebar.super.on_mouse_pressed(self,button,x,y,clicks) then return end
  if button~='left' then return end
  local h=self:height()
  if y<self.position.y+h or y>=self.position.y+self.size.y-2*h then return end
  self.index=math.floor((y-self.position.y+self.scroll.y)/h)
  local row=self.rows[self.index]
  if row then self:choose(x<self.position.x+24*SCALE+row.depth*14*SCALE) end
end
function Sidebar:draw()
  self:draw_background(style.background2)
  local h=self:height()
  core.push_clip_rect(self.position.x,self.position.y+h,self.size.x,math.max(0,self.size.y-3*h))
  for i,row in ipairs(self.rows) do
    local y=self.position.y+i*h-self.scroll.y
    if y+h>self.position.y+h and y<self.position.y+self.size.y-2*h then
      local selected=self.selected_room and row.room and row.room.id==self.selected_room
        or not self.selected_room and i==self.index
      if selected then renderer.draw_rect(self.position.x,y,self.size.x,h,style.line_highlight) end
      if self.selected_room and core.active_view==self and i==self.index then
        renderer.draw_rect(self.position.x,y,2*SCALE,h,style.accent)
      end
      local mark=row.branch and (row.expanded and '- ' or '+ ') or '  '
      local unread=row.room and (row.room.unread or 0)>0 and (' ['..row.room.unread..']') or ''
      local x=renderer.draw_text(style.font,mark..row.label,self.position.x+8*SCALE+row.depth*14*SCALE,y+3*SCALE,style.text)
      if unread~='' then
        renderer.draw_text(style.font,unread,x,y+3*SCALE,row.room.muted and style.dim or {240,90,90,255})
      end
    end
  end
  core.pop_clip_rect()
  core.push_clip_rect(self.position.x,self.position.y,self.size.x,self.size.y)
  renderer.draw_text(style.font,self.title,self.position.x+8*SCALE,self.position.y+3*SCALE,style.accent)
  renderer.draw_text(style.font,self.footer,self.position.x+8*SCALE,self.position.y+self.size.y-2*h,style.dim)
  renderer.draw_text(style.font,self.detail,self.position.x+8*SCALE,self.position.y+self.size.y-h,style.dim)
  core.pop_clip_rect()
  self:draw_scrollbar()
end
return Sidebar
