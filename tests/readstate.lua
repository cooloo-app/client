package.path='lua/?.lua;lua/?/init.lua;'..package.path
local State=require 'workbench.readstate'
local path=os.tmpname();os.remove(path)
local function write(p,value)
 local f=assert(io.open(p,'wb'));assert(f:write(value));assert(f:close());return true
end
local s=assert(State.new(path,write))
assert(s:baseline(100));assert(not s:observe(100,'peer','self'))
assert(not s:observe(200,'self','self'))
assert(s:observe(300,'peer','self'));assert(not s:observe(300,'peer','self'))
assert(s:mute(true));assert(s.unread==1)
-- A process restart reconstructs unread from cache, without marking downloads read.
s=assert(State.new(path,write));assert(s.muted and s.watermark==100)
assert(s:baseline(300));assert(s.watermark==100)
assert(s:observe(300,'peer','self'));assert(s.unread==1)
-- Failure must not clear visible unread or advance the durable watermark.
s.write=function()return false,'disk full' end
assert(not s:mark(300));assert(s.unread==1 and s.watermark==100)
s.write=write;assert(s:mark(300));assert(s.unread==0)
s=assert(State.new(path,write));assert(not s:observe(300,'peer','self'))
assert(s:mark(200));assert(s.watermark==300)
-- Counting stays exact beyond the display cap, old-history overlap is idempotent.
for i=301,5300 do assert(s:observe(i,'peer','self')) end
assert(s.unread==5000);assert(s:mark(400));assert(s.unread==4900)
assert(not s:observe(399,'peer','self'))
local other=path..'-identity';local isolated=assert(State.new(other,write))
assert(isolated:baseline(0));assert(not isolated.muted and isolated.watermark==0)
write(path,'return os.execute("never execute config")')
assert(not State.new(path,write),'corrupt state must not silently mark history read')
os.remove(path);os.remove(other)
print('readstate: upgrade, restart, mute, dedupe, own messages, failure, monotonicity, 5000 unread, identity isolation passed')
