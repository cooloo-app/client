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
-- Old text files are ignored, never migrated; text at the JSON path is invalid.
local legacy=path..'-legacy';write(legacy,'v1\n42\n1\n')
local json_path=legacy..'.json'
local fresh=assert(State.new(json_path,write))
assert(not fresh.initialized and fresh.watermark==0 and not fresh.muted)
local function absent(p)
 local f=io.open(p,'rb');if f then f:close();error('Unexpected file: '..p) end
end
absent(json_path);absent(json_path..'.local')
write(json_path,'v1\n42\n1\n')
assert(not State.new(json_path,write),'text state at the JSON path must be rejected')
-- JSON and device-local mute remain supported; JSON wins over an old sibling.
write(json_path,State.encode(42));write(json_path..'.local','1\n')
local current=assert(State.new(json_path,write))
assert(current.watermark==42 and current.muted)
assert(not State.encode(current.watermark):find('mute'))
assert(not State.decode('{"version":2,"read_offset":42}'))
assert(not State.decode('{"version":1,"read_offset":-1}'))
assert(current:mark(100));assert(current:mark(60));assert(current.watermark==100)
assert(current:bind(string.rep('a',64)));assert(current.watermark==0)
assert(current:bind(string.rep('b',64)));assert(current.watermark==0)
assert(current:mark(12));local restarted=assert(State.new(json_path,write))
assert(restarted.watermark==12 and restarted.generation==string.rep('b',64))
for _,p in ipairs{path,other,legacy,legacy..'.json',legacy..'.json.local',path..'.local',other..'.local'} do os.remove(p) end
print('readstate: JSON-only state, restart, mute, dedupe, own messages, failure, monotonicity, 5000 unread, identity isolation passed')
