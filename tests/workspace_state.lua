package.path='lua/editor/?.lua;lua/editor/?/init.lua;lua/?.lua;lua/?/init.lua;'..package.path
cooloo={renderer=native_renderer,offline=true,time=os.clock,screen=function()return 960,640 end,
 poll_event=function()end,clear_ime=function()end,set_ime_rect=function()end,
 clipboard={get=function()return ''end,set=function()end},quit=function()end,
 platform={exedir='.',exefile='',userdir='.',set_fps=function()end,focus=function()return true end,
 cursor=function()end,title=function()end,mode=function()end,confirm=function()return false end,
 list_dir=function()return {}end,info=native_platform.info,absolute_path=native_platform.absolute_path}}
require 'platform.lite'
local host=require 'core.host';host.init()
local State=require 'core.ui_state'
local fs={get_file_info=function()end,make_dir=function()return true end,write_file=function()return true end}
host.state=State.new('/unused/state','cooloo-workbench',fs)
local core=require 'core'
local ctx={server_fp='server',identity_id='one'}
local entry=host.state:workspace(ctx,'workbench')
entry.browser={room_id='b',collapsed_groups={'group'}}
entry.layout={type='split',axis='x',ratio=0.7,
 a={type='leaf',active_tab=1,tabs={{resource={kind='chat',room_id='a'}}}},
 b={type='leaf',active_tab=1,tabs={{resource={kind='chat',room_id='b'}},{resource={kind='chat',room_id='deleted'}}}}}
entry.active_pane={'a'}
local ready=false
local provider={list=function()return {{id='a',name='a'},{id='b',name='b'}}end,
 state_context=function()return ctx,ready end,
 open=function()return {}end,send=function()return true end,poll=function()end}
local workspace=require('plugins.workspace').install(provider)
local Chat=require 'plugins.workspace.chatview'
local function chats()
 local count=0
 for _,view in ipairs(core.root_view.root_node:get_children())do if view:is(Chat)then count=count+1 end end
 return count
end
workspace.poll({});assert(chats()==0,'must wait for room listing')
ready=true;workspace.poll({});assert(chats()==2,'restore valid rooms, skip deleted room')
assert(core.active_view:is(Chat))
host.snapshot()
assert(entry.layout.type=='split' and entry.layout.ratio==0.7)
assert(entry.active_pane[1]=='a' and entry.browser.room_id=='b','browser is independent of active chat')
workspace.poll({});assert(chats()==2,'restore once, not every poll')
ctx={server_fp='server',identity_id='two'};ready=false
workspace.poll({});assert(chats()==0,'identity boundary closes old views')
ready=true;workspace.poll({});assert(chats()==1,'new identity defaults to first room')
host.snapshot()
assert(#host.state.data.workspaces==2)
assert(entry.browser.room_id=='b','new identity must not overwrite previous workspace')
print('Workspace state: async readiness, mixed layout, missing rooms, browser/focus and identity isolation OK')
