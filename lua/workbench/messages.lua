-- Headless message projection. No editor, renderer, network or identity access.
local M = {}
local Threads = require 'workbench.threads'
function M.project(messages, options)
  options = options or {}
  local lines, anchors, ranges, headers, line = {}, {}, {}, {}, 1
  local decorations={}
  local entries,index=Threads.project(messages,options.thread_index)
  for i, entry in ipairs(entries) do
    local m=entry.message
    assert(type(m.id)=='string' and not anchors[m.id], 'missing or duplicate message ID')
    assert(type(m.text)=='string' and utf8.len(m.text), 'invalid UTF-8 message')
    local stamp = assert(os.date(options.local_time and '%H:%M' or '!%H:%M', m.ts or 0))
    local name = (m.from or '?'):gsub('[%c]', ' ')
    local _,body=Threads.parse(m.text)
    if entry.problem then body='['..entry.problem..']\n'..body end
    if i>1 and not entry.reply then lines[#lines+1]='\n';line=line+1 end
    local block = ('%s  %s\n%s\n'):format(stamp, name, body)
    headers[line] = {first= #stamp+3, last= #stamp+3+#name,
      sender=m.sender_id or m.from or '?'}
    lines[#lines+1] = block
    anchors[m.id] = line
    local _, count = block:gsub('\n', '')
    ranges[#ranges+1] = {id=m.id, first_line=line, last_line=line+count-1, raw=m.text}
    if entry.reply then
      for l=line,line+count-1 do decorations[l]=true end
    end
    line = line + count
  end
  return {text=table.concat(lines), anchors=anchors, ranges=ranges, headers=headers,
    decorations=decorations,thread_index=index,source_revision=options.source_revision}
end
-- Decoder is injected so the CLI and native GUI use the same C record parser.
-- IDs are source byte endpoints, not display line numbers. Input is never executed.
function M.read(path, decode)
  local f, err = io.open(path, 'rb')
  if not f then return nil, err end
  local messages, offset, buffer, count = {}, 0, '', 0
  local function consume(raw, bytes)
    count = count + 1
    if #raw > 25088 then error('record too large') end
    local m = assert(decode(raw), 'invalid canonical message record')
    assert(utf8.len(m.text) and utf8.len(m.from), 'invalid UTF-8 record')
    offset = offset + bytes
    m.id = tostring(offset)
    messages[#messages+1] = m
    assert(#messages <= 10000, 'record limit exceeded (10000)')
  end
  local ok, failure = pcall(function()
    while true do
      local chunk, read_error = f:read(4096)
      if not chunk then
        assert(not read_error, read_error)
        break
      end
      buffer = buffer .. chunk
      while true do
        local at = buffer:find('\n', 1, true)
        if not at then break end
        consume(buffer:sub(1, at-1):gsub('\r$', ''), at)
        buffer = buffer:sub(at+1)
      end
      assert(#buffer <= 25088, 'record too large')
    end
    if #buffer > 0 then consume(buffer, #buffer) end
  end)
  f:close()
  if not ok then return nil, ('record %d: %s'):format(math.max(count, 1), failure) end
  return messages, tostring(offset)
end
return M
