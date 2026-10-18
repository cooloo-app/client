-- Soft-wrapped read-only virtual documents. Byte positions stay in the source
-- document; screen rows are a projection, never inserted newlines.
local core=require 'core'
local DV=require 'core.docview'
local style=require 'core.style'
local common=require 'core.common'
local W=DV:extend()
function W:new(doc) W.super.new(self,doc);self.rows={};self.follow=true end
function W:layout()
  local width=math.max(20,self.size.x-style.padding.x*2)
  local stamp=self.doc.projection_revision or self.doc.projection or table.concat(self.doc.lines)
  local font=self:get_font()
  local tab=font:get_width('\t')
  if self.layout_doc==self.doc and self.layout_width==width and self.layout_stamp==stamp
    and self.layout_font==font and self.layout_tab==tab then return end
  self.layout_font,self.layout_tab=font,tab
  core.redraw=true
  local oldrow=self.rows[math.floor(self.scroll.y/self:get_line_height())+1]
  self.rows={};self.line_rows={}
  local widths={};local font=self:get_font()
  for l,text in ipairs(self.doc.lines) do
    local start,col,w=1,1,0
    self.line_rows[l]=#self.rows+1
    for ch in common.utf8_chars(text:gsub('\n$','')) do
      local cw=widths[ch]
      if not cw then cw=font:get_width(ch);widths[ch]=cw end
      if w+cw>width and col>start then
        self.rows[#self.rows+1]={line=l,first=start,last=col}
        start,w=col,0
      end
      col,w=col+#ch,w+cw
    end
    self.rows[#self.rows+1]={line=l,first=start,last=col}
  end
  self.layout_doc,self.layout_width,self.layout_stamp=self.doc,width,stamp
  local shift=(self.doc.projection_shift or 0)-(self.last_shift or 0)
  self.last_shift=self.doc.projection_shift or 0
  if oldrow and not self.follow then
    for i,r in ipairs(self.rows) do
      if r.line==oldrow.line+shift and r.first<=oldrow.first and (r.last>oldrow.first or r.first==r.last) then
        self.scroll.y=(i-1)*self:get_line_height();self.scroll.to.y=self.scroll.y;break
      end
    end
  end
end
function W:get_gutter_width() return style.padding.x end
function W:get_scrollable_size() self:layout();return #self.rows*self:get_line_height()+style.padding.y*2 end
function W:get_line_screen_position(line)
  self:layout()
  local x,y=self:get_content_offset()
  local row=self.line_rows[line]
  if row then return x+style.padding.x,y+(row-1)*self:get_line_height()+style.padding.y end
  return x,y
end
function W:resolve_screen_position(x,y)
  self:layout()
  local ox,oy=self:get_content_offset()
  local i=common.clamp(math.floor((y-oy-style.padding.y)/self:get_line_height())+1,1,#self.rows)
  local r=self.rows[i];local text=self.doc.lines[r.line];local at=ox+style.padding.x
  local col=r.first
  for ch in common.utf8_chars(text:sub(r.first,r.last-1)) do
    local w=self:get_font():get_width(ch)
    if x<at+w/2 then break end
    at,col=at+w,col+#ch
  end
  return r.line,col
end
function W:scroll_to_make_visible(line,col)
  -- Search/navigation may reveal a match; external projection shifts must not
  -- steal the viewport from someone reading history.
  if self.selection_revision~=self.doc.projection_revision then return end
  self:layout()
  local at=self.line_rows[line]
  if not at then return end
  while self.rows[at+1] and self.rows[at+1].line==line and self.rows[at+1].first<=col do at=at+1 end
  local y=(at-1)*self:get_line_height()
  if y<self.scroll.to.y then self.scroll.to.y=y
  elseif y+self:get_line_height()>self.scroll.to.y+self.size.y then
    self.scroll.to.y=math.max(0,y+self:get_line_height()-self.size.y)
  end
  self.follow=false
end
function W:on_mouse_wheel(y)
  W.super.on_mouse_wheel(self,y)
  self.follow=self.scroll.to.y>=math.max(0,self:get_scrollable_size()-self.size.y)-2
end
function W:update()
  self:layout()
  if self.follow then self.scroll.to.y=math.max(0,self:get_scrollable_size()-self.size.y) end
  W.super.update(self)
  self.selection_revision=self.doc.projection_revision
end
function W:draw()
  self:layout();self:draw_background(style.background)
  local ox,oy=self:get_content_offset();local lh=self:get_line_height()
  local l1,c1,l2,c2=self.doc:get_selection(true)
  local first=math.max(1,math.floor((self.position.y-oy-style.padding.y)/lh)+1)
  local last=math.min(#self.rows,math.ceil((self.position.y+self.size.y-oy-style.padding.y)/lh)+1)
  for i=first,last do
    local r=self.rows[i]
    local y=oy+(i-1)*lh+style.padding.y
    if y+lh>=self.position.y and y<self.position.y+self.size.y then
      local x=ox+style.padding.x;local text=self.doc.lines[r.line]
      if r.line>=l1 and r.line<=l2 then
        local a=math.max(r.first,r.line==l1 and c1 or r.first)
        local b=math.min(r.last,r.line==l2 and c2 or r.last)
        if b>a then
          local dx=self:get_font():get_width(text:sub(r.first,a-1))
          renderer.draw_rect(x+dx,y,self:get_font():get_width(text:sub(a,b-1)),lh,style.selection)
        end
      end
      renderer.draw_text(self:get_font(),text:sub(r.first,r.last-1),x,y,style.text)
    end
  end
  self:draw_scrollbar()
end
return W
