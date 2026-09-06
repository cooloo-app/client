-- chat.lua - connection lifecycle, room/message buffers, line protocol,
-- offset management (04 doc 4.1: all UI state lives in Lua).
--
-- Connection model (wiki reference/native-api.md): MSG has no room field,
-- so one FOLLOW connection per room + one ctrl connection for
-- ROOMS/HELLO/SEND/WHOAMI. READ pauses a conn's live push until END, so
-- backfill READ runs on the room's own conn with dedupe by end_offset.
--
-- Globals survive lua-dev reloads: data tables are preserved, functions
-- are replaced (guard idiom below).

chat = chat or {
    rooms = {},        -- name -> room
    order = {},        -- room names in server order
    by_conn = {},      -- conn id -> room (room conns only)
    ctrl = nil,        -- ctrl conn id
    ctrl_up = false,
    nick = "",
    registered = false,
    want_register = false,
    want_reconnect = false,
    rooms_loaded = false,
    sel = nil,         -- selected room name
    status = "",
    host = nil,
    port = nil,
}

local M = chat

local ROOM_CAP = 2000          -- messages kept per room (doc 4.1)
local READ_INIT = 50           -- initial READ -N
local READ_MAX = 1000          -- protocol cap for READ -N

local function cfgget(k) return cooloo.config.get(k) end
local function cfgset(k, v) cooloo.config.set(k, v) end

-- reverse of the storage escape table: \\, \n, \r (data-formats.md)
local function unescape(s)
    return (s:gsub("\\(.)", function(c)
        if c == "n" then return "\n" end
        if c == "r" then return "\r" end
        return c
    end))
end

local function newroom(name)
    return {
        name = name,
        buf = {},          -- {endoff=, ts=, nick=, text=, wrap=nil}
        ends = {},         -- dedupe set: endoff -> true
        conn = nil,
        phase = "idle",    -- idle|connecting|reading|following
        pending = nil,     -- parsed MSG header awaiting its text line
        following = false, -- FOLLOW sent (refollow never re-sent)
        read_n = READ_INIT,
        backfilling = false,
        read_requested = 0, -- READ -N in flight: requested count
        read_received = 0,  -- raw MSG lines seen in that READ window
        exhausted = false,  -- server returned a short READ: no older history
        scroll = 0,        -- lines up from the bottom (0 = tail)
        unread = 0,
    }
end

function M.init(host, port)
    M.host, M.port = host, port
end

function M.current()
    return M.sel and M.rooms[M.sel] or nil
end

function M.ensure_room(name)
    local r = M.rooms[name]
    if not r then
        r = newroom(name)
        M.rooms[name] = r
        M.order[#M.order + 1] = name
    end
    return r
end

function M.connect_ctrl()
    if M.ctrl then return end
    local conn, err = cooloo.net.connect(M.host, M.port)
    if not conn then
        M.status = "connect: " .. tostring(err)
        M.want_reconnect = true
        return
    end
    M.ctrl = conn
    M.ctrl_up = false
end

local function send_follow(r)
    r.following = true
    r.phase = "following"
    -- resume from the persisted offset so a restart/reconnect loses
    -- nothing (04 doc 6.3); fall back to live tail when unknown
    local saved = cfgget("offset." .. r.name)
    if saved then
        cooloo.net.send(r.conn, ("FOLLOW %s %s\n"):format(r.name, saved))
    elseif r.newest_end then
        cooloo.net.send(r.conn, ("FOLLOW %s %d\n"):format(r.name, r.newest_end))
    else
        cooloo.net.send(r.conn, ("FOLLOW %s\n"):format(r.name))
    end
end

function M.start_follows()
    for _, name in ipairs(M.order) do
        local r = M.rooms[name]
        if not r.conn then
            local conn = cooloo.net.connect(M.host, M.port)
            if conn then
                r.conn = conn
                M.by_conn[conn] = r
                r.phase = "connecting"
            end
        end
    end
end

function M.ensure_conns()
    if not M.ctrl then M.connect_ctrl() end
    if M.rooms_loaded then M.start_follows() end
end

local function add_msg(r, endoff, ts, nick, text)
    if r.ends[endoff] then return end           -- dedupe (backfill overlap)
    r.ends[endoff] = true
    local m = { endoff = endoff, ts = ts, nick = nick, text = text }
    local i = #r.buf + 1
    if #r.buf > 0 and r.buf[#r.buf].endoff > endoff then
        i = 1
        while i <= #r.buf and r.buf[i].endoff < endoff do i = i + 1 end
    end
    table.insert(r.buf, i, m)
    r.newest_end = math.max(r.newest_end or 0, endoff)
    if not r.oldest_end or endoff < r.oldest_end then r.oldest_end = endoff end
    if #r.buf > ROOM_CAP then
        local old = table.remove(r.buf, 1)
        r.ends[old.endoff] = nil
        r.oldest_end = r.buf[1] and r.buf[1].endoff or nil
    end
    cfgset("offset." .. r.name, tostring(r.newest_end))
    if r ~= M.current() then r.unread = r.unread + 1 end
end

function M.on_ready(conn, nick)
    if conn == M.ctrl then
        M.ctrl_up = true
        M.status = ""
        if nick == "" then
            M.want_register = true
        else
            M.nick = nick
            M.registered = true
        end
        cooloo.net.send(conn, "ROOMS\n")
        return
    end
    local r = M.by_conn[conn]
    if r then
        r.phase = "reading"
        r.read_requested = r.read_n
        r.read_received = 0
        cooloo.net.send(conn, ("READ %s -%d\n"):format(r.name, r.read_n))
    end
end

function M.on_line(conn, line)
    if conn == M.ctrl then
        local room = line:match("^ROOM (.+)$")
        if room then M.ensure_room(room); return end
        if line == "END" then
            -- every ROOMS response (initial or periodic refresh) is a
            -- chance to pick up rooms created after connect
            if not M.rooms_loaded and not M.sel then
                M.sel = M.rooms.general and "general" or M.order[1]
            end
            M.rooms_loaded = true
            M.start_follows()
            return
        end
        local nick = line:match("^NICK (.+)$")
        if nick then
            M.nick = nick
            M.registered = true
            M.want_register = false
            cfgset("nick", nick)
            return
        end
        if line:sub(1, 4) == "ERR " then M.status = line; return end
        return -- OK / PONG: fine
    end

    local r = M.by_conn[conn]
    if not r then return end
    if r.pending then
        local h = r.pending
        r.pending = nil
        add_msg(r, h.endoff, h.ts, h.nick, unescape(line))
        return
    end
    local e, ts, nick = line:match("^MSG (%d+) (%d+) (%S+) %d+$")
    if e then
        -- READ pauses live push, so MSG lines in a READ window are all
        -- READ results; count them raw (pre-dedupe) to detect a short read
        if r.phase == "reading" or r.backfilling then
            r.read_received = r.read_received + 1
        end
        r.pending = { endoff = tonumber(e), ts = tonumber(ts), nick = nick }
        return
    end
    if line == "END" then
        if (r.phase == "reading" or r.backfilling) and
            r.read_received < r.read_requested then
            r.exhausted = true
        end
        r.backfilling = false
        if not r.following then send_follow(r) end
        return
    end
    if line:sub(1, 4) == "ERR " then M.status = line; return end
end

function M.on_closed(conn, reason)
    if conn == M.ctrl then
        M.ctrl = nil
        M.ctrl_up = false
        M.status = "disconnected: " .. reason
        M.want_reconnect = true
        return
    end
    local r = M.by_conn[conn]
    if r then
        M.by_conn[conn] = nil
        r.conn = nil
        r.phase = "idle"
        r.pending = nil
        r.following = false
        M.status = "disconnected: " .. reason
        M.want_reconnect = true
    end
end

function M.send_text(text)
    local r = M.current()
    if not r or not M.ctrl_up or not M.registered or text == "" then
        return false
    end
    return cooloo.net.send(M.ctrl, ("SEND %s %d\n"):format(r.name, #text) .. text)
end

function M.scroll(r, dlines)
    r.scroll = math.max(0, r.scroll + dlines)
end

function M.maybe_backfill(r)
    if r.phase ~= "following" or r.backfilling or not r.conn or r.exhausted then
        return
    end
    local n = math.min(r.read_n + 50, READ_MAX)
    if n <= r.read_n then
        if r.read_n >= READ_MAX then M.status = "history limit (1000)" end
        return
    end
    r.read_n = n
    r.backfilling = true
    r.read_requested = n
    r.read_received = 0
    cooloo.net.send(r.conn, ("READ %s -%d\n"):format(r.name, n))
end

function M.register(nick)
    if M.ctrl_up then
        cooloo.net.send(M.ctrl, ("HELLO %s\n"):format(nick))
    end
end

function M.select(name)
    if M.rooms[name] then
        M.sel = name
        M.rooms[name].unread = 0
    end
end

function M.cycle(d)
    if #M.order == 0 then return end
    local idx = 1
    for i, n in ipairs(M.order) do
        if n == M.sel then idx = i; break end
    end
    idx = ((idx - 1 + d) % #M.order) + 1
    M.select(M.order[idx])
end

function M.close_all()
    if M.ctrl then cooloo.net.close(M.ctrl); M.ctrl = nil end
    M.ctrl_up = false
    for conn, r in pairs(M.by_conn) do
        cooloo.net.close(conn)
        r.conn = nil
        r.phase = "idle"
        r.following = false
    end
    M.by_conn = {}
end

function M.reconnect()
    M.close_all()
    M.want_reconnect = false
    M.connect_ctrl()
    if M.rooms_loaded then M.start_follows() end
end
