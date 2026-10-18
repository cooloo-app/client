local config = require "core.config"

-- functions for translating a Doc position to another position these functions
-- can be passed to Doc:move_to|select_to|delete_to()

local translate = {}


local function is_non_word(char)
  return config.non_word_chars:find(char, nil, true)
end


-- Invalid UTF-8 is retained byte-for-byte and navigated one byte at a time.
-- Only a complete, valid Unicode scalar can consume multiple bytes.
local function char_size(text, col)
  local byte = text:byte(col) or 0
  local size = byte >= 0xc2 and byte <= 0xdf and 2
    or byte >= 0xe0 and byte <= 0xef and 3
    or byte >= 0xf0 and byte <= 0xf4 and 4 or 1
  if size > 1 and utf8.len(text:sub(col, col + size - 1)) == 1 then
    return size
  end
  return 1
end

function translate.previous_char(doc, line, col)
  line, col = doc:sanitize_position(line, col)
  if col > 1 then
    local text = doc.lines[line]
    for start = math.max(1, col - 4), col - 1 do
      local size = char_size(text, start)
      if size > 1 and start + size == col then return line, start end
    end
  end
  return doc:position_offset(line, col, -1)
end


function translate.next_char(doc, line, col)
  line, col = doc:sanitize_position(line, col)
  return doc:position_offset(line, col, char_size(doc.lines[line], col))
end


function translate.previous_word_start(doc, line, col)
  local prev
  while line > 1 or col > 1 do
    local l, c = doc:position_offset(line, col, -1)
    local char = doc:get_char(l, c)
    if prev and prev ~= char or not is_non_word(char) then
      break
    end
    prev, line, col = char, l, c
  end
  return translate.start_of_word(doc, line, col)
end


function translate.next_word_end(doc, line, col)
  local prev
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if prev and prev ~= char or not is_non_word(char) then
      break
    end
    line, col = doc:position_offset(line, col, 1)
    prev = char
  end
  return translate.end_of_word(doc, line, col)
end


function translate.start_of_word(doc, line, col)
  while true do
    local line2, col2 = doc:position_offset(line, col, -1)
    local char = doc:get_char(line2, col2)
    if is_non_word(char)
    or line == line2 and col == col2 then
      break
    end
    line, col = line2, col2
  end
  return line, col
end


function translate.end_of_word(doc, line, col)
  while true do
    local line2, col2 = doc:position_offset(line, col, 1)
    local char = doc:get_char(line, col)
    if is_non_word(char)
    or line == line2 and col == col2 then
      break
    end
    line, col = line2, col2
  end
  return line, col
end


function translate.previous_block_start(doc, line, col)
  while true do
    line = line - 1
    if line <= 1 then
      return 1, 1
    end
    if doc.lines[line-1]:find("^%s*$")
    and not doc.lines[line]:find("^%s*$") then
      return line, (doc.lines[line]:find("%S"))
    end
  end
end


function translate.next_block_end(doc, line, col)
  while true do
    if line >= #doc.lines then
      return #doc.lines, 1
    end
    if doc.lines[line+1]:find("^%s*$")
    and not doc.lines[line]:find("^%s*$") then
      return line+1, #doc.lines[line+1]
    end
    line = line + 1
  end
end


function translate.start_of_line(doc, line, col)
  return line, 1
end


function translate.end_of_line(doc, line, col)
  return line, math.huge
end


function translate.start_of_doc(doc, line, col)
  return 1, 1
end


function translate.end_of_doc(doc, line, col)
  return #doc.lines, #doc.lines[#doc.lines]
end


return translate
