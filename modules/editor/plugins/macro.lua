local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"

local handled_events = {
  ["keypressed"]  = true,
  ["keyreleased"] = true,
  ["textinput"]   = true,
}

local state = "stopped"
local event_buffer = {}
local ime = require "core.ime"
local modkeys = {}

local on_event = core.on_event

core.on_event = function(type, ...)
  local recording = state == "recording"
  local consumed = ime.editing and (type == "keypressed" or type == "keyreleased")
    and not keymap.is_modifier((...))
  local res = on_event(type, ...)
  if recording and state == "recording" and handled_events[type] and not consumed then
    table.insert(event_buffer, { type, ... })
  end
  return res
end


local function predicate()
  return state ~= "playing"
end


command.add(predicate, {
  ["macro:toggle-record"] = function()
    if state == "stopped" then
      state = "recording"
      event_buffer = {}
      modkeys = keymap.capture_state()
      core.log("Recording macro...")
    else
      state = "stopped"
      core.log("Stopped recording macro (%d events)", #event_buffer)
    end
  end,

  ["macro:play"] = function()
    -- Do not replay into an active OS composition or synthesize preedit events.
    if ime.editing then return end
    state = "playing"
    core.log("Playing macro... (%d events)", #event_buffer)
    local ok, err = xpcall(function()
      keymap.with_state(modkeys, function()
        for _, ev in ipairs(event_buffer) do
          on_event(table.unpack(ev))
          core.root_view:update()
        end
      end)
    end, debug.traceback)
    state = "stopped"
    if not ok then error(err, 0) end
  end,
})


keymap.add {
  ["ctrl+shift+;"] = "macro:toggle-record",
  ["ctrl+;"] = "macro:play",
}
