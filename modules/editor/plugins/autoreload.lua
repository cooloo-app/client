local core = require "core"
local config = require "core.config"
local Doc = require "core.doc"


local times = setmetatable({}, { __mode = "k" })

local function update_time(doc)
  if doc.readonly or doc.virtual or not doc.filename then return end
  local info = system.get_file_info(doc.filename)
  times[doc] = info and info.modified
end


local function reload_doc(doc)
  local fp = io.open(doc.filename, "rb")
  if not fp then return end
  local text = fp:read("*a")
  fp:close()
  if not text then return end
  doc.crlf = text:find('\r\n', 1, true) ~= nil

  local sel = { doc:get_selection() }
  doc:remove(1, 1, math.huge, math.huge)
  doc:insert(1, 1, text:gsub("\r\n", "\n"))
  doc:set_selection(table.unpack(sel))

  update_time(doc)
  doc:clean()
  core.log_quiet("Auto-reloaded doc \"%s\"", doc.filename)
end


core.add_thread(function()
  while true do
    -- check all doc modified times
    for _, doc in ipairs(core.docs) do
      local info = system.get_file_info(doc.filename or "")
      if info and info.type == 'file' and not doc.virtual and not doc.readonly
      and not doc:is_dirty() and times[doc] ~= info.modified then
        reload_doc(doc)
      end
      coroutine.yield()
    end

    -- wait for next scan
    coroutine.yield(config.project_scan_rate)
  end
end)


-- patch `Doc.save|load` to store modified time
local load = Doc.load
local save = Doc.save

Doc.load = function(self, ...)
  local res = load(self, ...)
  update_time(self)
  return res
end

Doc.save = function(self, ...)
  local res = save(self, ...)
  update_time(self)
  return res
end
