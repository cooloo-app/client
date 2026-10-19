-- Chat-specific decoration; source byte positions and wrapping remain inherited.
local Wrapped=require 'core.wrappedview'
local style=require 'core.style'
local core=require 'core'
local History=Wrapped:extend()
local palette={
  {229,138,201}, {247,164,135}, {255,201,112}, {193,207,120},
  {132,205,161}, {126,204,211}, {147,185,250}, {190,161,235},
}
function History.color(sender)
  local hash=0
  for i=1,#sender do hash=(hash*31+sender:byte(i))%2147483647 end
  return palette[hash%#palette+1]
end
function History:update()
  if self.headers~=self.doc.chat_headers then
    self.headers=self.doc.chat_headers;core.redraw=true
  end
  History.super.update(self)
end
function History:draw()
  self:layout();self:draw_background(style.background)
  local ox,oy=self:get_content_offset();local lh=self:get_line_height()
  local l1,c1,l2,c2=self.doc:get_selection(true)
  local first=math.max(1,math.floor((self.position.y-oy-style.padding.y)/lh)+1)
  local last=math.min(#self.rows,math.ceil((self.position.y+self.size.y-oy-style.padding.y)/lh)+1)
  local font=self:get_font()
  for i=first,last do
    local r=self.rows[i]
    local y=oy+(i-1)*lh+style.padding.y
    if y+lh>=self.position.y and y<self.position.y+self.size.y then
      local x=ox+style.padding.x;local text=self.doc.lines[r.line]
      if r.line>=l1 and r.line<=l2 then
        local a=math.max(r.first,r.line==l1 and c1 or r.first)
        local b=math.min(r.last,r.line==l2 and c2 or r.last)
        if b>a then
          renderer.draw_rect(x+font:get_width(text:sub(r.first,a-1)),y,
            font:get_width(text:sub(a,b-1)),lh,style.selection)
        end
      end
      local header=(self.doc.chat_headers or {})[r.line]
      local function segment(a,b,color)
        a=math.max(a,r.first);b=math.min(b,r.last)
        if b>a then
          renderer.draw_text(font,text:sub(a,b-1),
            x+font:get_width(text:sub(r.first,a-1)),y,color)
        end
      end
      if header then
        segment(r.first,header.first,style.text)
        segment(header.first,header.last,History.color(header.sender))
      else
        segment(r.first,r.last,style.syntax.normal or style.text)
      end
    end
  end
  self:draw_scrollbar()
end
return History
