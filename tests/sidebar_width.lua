-- Sidebar width regression: real View update, no renderer/window/network.
package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;'..package.path
SCALE=1
local core={root_view={size={x=960}},redraw=false}
package.loaded.core=core
package.loaded['core.style']={font={get_height=function() return 14 end}}
local Sidebar=require 'plugins.workspace.sidebar'
local sidebar=Sidebar('Rooms',function() end)
sidebar.size.y=640

local function update(actual,expected,redraw)
  sidebar.size.x=actual;core.redraw=false
  sidebar:update()
  assert(core.redraw==redraw,'unexpected redraw for width '..actual)
  assert(sidebar.size.x==expected,'unexpected sidebar width')
end

-- Captured right-sidebar subtraction at the default 960px window width.
local target=960*0.22
for _,delta in ipairs({0, 5.6843418860808e-14, -5.6843418860808e-14, 0.005, -0.005}) do
  update(target+delta,target+delta,false)
end
update(target+0.02,target,true)
update(target-0.02,target,true)

-- Resizing and DPI changes must still update, including both width clamps.
for _,scale in ipairs({1,1.25,1.5,2}) do
  SCALE=scale
  for _,window in ipairs({200,960,1000,2000}) do
    core.root_view.size.x=window
    local width=math.min(240*SCALE,math.max(80*SCALE,window*0.22))
    update(0,width,true)
    for _=1,100 do update(width+5.6843418860808e-14,width+5.6843418860808e-14,false) end
  end
end

local called=false
sidebar.before_update=function() called=true end
sidebar:update();assert(called,'sidebar lifecycle callback must still run')
print('sidebar width: floating-point tails stay idle; resize, DPI, clamps and lifecycle OK')
