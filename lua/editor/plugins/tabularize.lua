local core = require "core"
local command = require "core.command"
local translate = require "core.doc.translate"


local function gmatch_to_array(text, ptn)
  local res = {}
  for x in text:gmatch(ptn) do
    table.insert(res, x)
  end
  return res
end


local function tabularize_lines(lines, delim)
  local rows = {}
  local cols = {}

  -- split lines at delimiters and get maximum width of columns
  for i, line in ipairs(lines) do
    rows[i] = {}
    local start = 1
    while true do
      local first, last = line:find(delim, start, true)
      local field = line:sub(start, first and first - 1 or #line)
      -- Preserve the existing nonempty-field formatting semantics.
      if field ~= "" then table.insert(rows[i], field) end
      if not first then break end
      start = last + 1
    end
    for j, col in ipairs(rows[i]) do
      cols[j] = math.max(#col, cols[j] or 0)
    end
  end

  -- pad columns with space
  for _, row in ipairs(rows) do
    for i = 1, #row - 1 do
      row[i] = row[i] .. string.rep(" ", cols[i] - #row[i])
    end
  end

  -- write columns back to lines array
  for i, line in ipairs(lines) do
    lines[i] = table.concat(rows[i], delim)
  end
end


command.add("core.docview", {
  ["tabularize:tabularize"] = function()
    core.command_view:enter("Tabularize On Delimiter", function(delim)
      if delim == "" then delim = " " end

      local doc = core.active_view.doc
      local line1, col1, line2, col2, swap = doc:get_selection(true)
      line1, col1 = doc:position_offset(line1, col1, translate.start_of_line)
      line2, col2 = doc:position_offset(line2, col2, translate.end_of_line)
      doc:set_selection(line1, col1, line2, col2, swap)

      doc:replace(function(text)
        local lines = gmatch_to_array(text, "[^\n]*\n?")
        tabularize_lines(lines, delim)
        return table.concat(lines)
      end)
    end)
  end,
})
