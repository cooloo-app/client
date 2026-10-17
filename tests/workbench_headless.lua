package.path='modules/?.lua;modules/?/init.lua;'..package.path
local project=require('workbench.messages').project
local p=project({{id='a',ts=0,from='sender',text='中文\nsecond'},
 {id='b',ts=60,from='other',text='hello'}},{source_revision='r'})
assert(p.text=='00:00  sender\n中文\nsecond\n\n00:01  other\nhello\n')
assert(p.anchors.a==1 and p.anchors.b==5 and p.ranges[1].last_line==3)
assert(p.source_revision=='r')
assert(project({}).text=='')
assert(not pcall(project,{{id='x',text='a'},{id='x',text='b'}}))
assert(not pcall(project,{{id='x',text='\255'}}))
local stopped={}
local results={}
local runtime={start=function()return true end,send=function()return true end,
 stop=function(n)stopped[n]=true end,poll=function(n)return results[n] or {} end}
local c=require('workbench.console').new(runtime)
assert(c:submit('中文'));assert(c:recall(-1)=='中文');assert(c:recall(1)=='')
c:clear();c:append('\228\184');assert(c.visible=='');c:append('\173');assert(c.visible=='中')
c:append(string.rep('a',300000));assert(#c.output<=c.limit and utf8.len(c.visible))
results[2]={stdout='out',stderr='err',exitcode=7};c:poll()
assert(not c.running[2] and c.visible:find('[exit 2: 7]',1,true))
c:restart();assert(stopped[2] and c.running[2]);c:stop(2);assert(not c.running[2])
local busy=require('workbench.console').new{start=function()return true end,send=function()return false end}
assert(not busy:submit('not queued') and #busy.history==0)
assert(not c:submit(string.rep('x',4097)))
assert(not package.loaded['core.doc'] and not package.loaded['core'] and not _G.renderer)
print('headless projection/session: OK')
