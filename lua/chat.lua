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
    M.login_id=cooloo.public_id()
end

function M.identity()
    return M.effective or M.login_id or cooloo.public_id()
end

-- One explicit identity per window. Clear streams/views before switching.
function M.use_identity(id)
    if id and (#id ~= 64 or not id:match('^[0-9a-f]+$')) then return false end
    M.close_all()
    M.requested_effective = id ~= cooloo.public_id() and id or nil
    M.effective = M.requested_effective
    M.identity_confirmed = false
    M.auth_failed = false
    M.rooms, M.order, M.by_conn = {}, {}, {}
    M.sel, M.rooms_loaded = nil, false
    M.sent_conns, M.sent_seen, M.sent_offsets = {}, {}, {}
    M.names, M.registered, M.nick, M.want_register = {}, false, '', false
    M.read_denied=false
    M.want_reconnect = false
    M.connect_ctrl()
    return true
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

function M.refresh_rooms()
    if not M.ctrl_up or not M.registered or M.rooms_pending then return false end
    M.rooms_pending = {}
    M.rooms_requested_at = cooloo.time()
    cooloo.net.send(M.ctrl, 'ROOMS\n')
    return true
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
    local saved = r.newest_end and tostring(r.newest_end)
    if saved then
        cooloo.net.send(r.conn, ("FOLLOW %s %s\n"):format(r.name, saved))
    elseif r.newest_end then
        cooloo.net.send(r.conn, ("FOLLOW %s %d\n"):format(r.name, r.newest_end))
    else
        cooloo.net.send(r.conn, ("FOLLOW %s\n"):format(r.name))
    end
end

function M.start_follows()
    -- D25: unregistered conns may only HELLO/WHOAMI/PING/ROOMS, so a
    -- room conn opened before registration gets its READ rejected and
    -- would wedge in "reading" forever (the register-race bug)
    if not M.registered then return end
    for _, name in ipairs(M.order) do
        local r = M.rooms[name]
        if not r.conn and (not M.subscriptions or M.subscriptions[name]) and not r.denied then
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
    if M.auth_failed then return end
    if not M.ctrl then M.connect_ctrl() end
    if M.rooms_loaded then M.start_follows() end
end

local function add_msg(r, endoff, ts, nick, text, from)
    if r.ends[endoff] then return end           -- dedupe (backfill overlap)
    r.ends[endoff] = true
    r.revision=(r.revision or 0)+1
    local m = { endoff = endoff, ts = ts, nick = nick, text = text, from=from }
    local i = #r.buf + 1
    if r.name == M.identity() then
        local lo,hi=1,#r.buf
        while lo<=hi do
            local mid=(lo+hi)//2;local old=r.buf[mid]
            local less=old.ts<ts or (old.ts==ts and ((old.to or r.name)<r.name or
                ((old.to or r.name)==r.name and old.endoff<endoff)))
            if less then lo=mid+1 else hi=mid-1 end
        end
        i=lo
    elseif #r.buf > 0 and r.buf[#r.buf].endoff > endoff then
        i = 1
        while i <= #r.buf and r.buf[i].endoff < endoff do i = i + 1 end
    end
    table.insert(r.buf, i, m)
    r.newest_end = math.max(r.newest_end or 0, endoff)
    if not r.oldest_end or endoff < r.oldest_end then r.oldest_end = endoff end
    if #r.buf > (r.display_cap or ROOM_CAP) then
        local old = table.remove(r.buf, 1)
        if not old.sent then r.ends[old.endoff] = nil end
        r.oldest_end = r.buf[1] and r.buf[1].endoff or nil
    end
    -- Reading and notification policy belong to the adapter, not selection.
    if M.message_added then M.message_added(r,m) end
end

local function query_identity(conn,nick)
    M.identity_pending=M.identity_pending or {}
    M.identity_pending[conn]=nick
    cooloo.net.send(conn,'IDENTITY\n')
end

function M.on_ready(conn, nick)
    local selected=M.requested_effective or (conn~=M.ctrl and M.effective)
    if selected then
        M.as_pending = M.as_pending or {}
        M.as_pending[conn] = nick
        cooloo.net.send(conn, 'AS ' .. selected .. '\n')
        return
    end
    query_identity(conn,nick)
end

function M.ready_identity(conn, nick)
    local s = (M.sent_conns or {})[conn]
    if s then
        cooloo.net.send(conn, 'SENT ' .. s.peer .. ' ' .. tostring((M.sent_offsets or {})[s.peer] or 0) .. '\n')
        return
    end
    if conn == M.ctrl then
        M.ctrl_up = true
        M.status = ""
        if nick == "" then
            M.want_register = true
        else
            M.nick = nick
            M.registered = true
        end
        if M.registered then M.refresh_rooms() end
        return
    end
    local r = M.by_conn[conn]
    if r then
        r.phase = "reading"
        r.read_requested = r.read_n
        r.read_received = 0
        r.server_fp = cooloo.net.fp(conn)
        r.self_id = M.identity()
        local offset
        local function loaded(ok, records, checkpoint)
            if r.conn ~= conn or M.by_conn[conn] ~= r then return end
            if not ok or checkpoint < 0 then
                M.status='cache read failure';cooloo.net.close(conn);M.on_closed(conn,M.status);return
            end
            if records then
                for _,v in ipairs(records) do
                    local msg=cooloo.record(v.json)
                    if msg then
                        add_msg(r,v.offset,msg.ts,(M.names or {})[msg.from] or msg.from,msg.content,msg.from)
                    end
                end
            end
            r.newest_end=checkpoint
            cooloo.net.send(conn,('READ %s %d\n'):format(r.name,checkpoint))
        end
        if M.load_cache then M.load_cache(r,loaded);return end
        local ok = cooloo.cache_read(r.server_fp, r.self_id, r.name, function(endoff, json)
            local msg = cooloo.record(json)
            if msg then
                add_msg(r, endoff, msg.ts, (M.names or {})[msg.from] or msg.from, msg.content,msg.from)
            end
        end)
        offset = cooloo.cache_offset(r.server_fp, r.self_id, r.name)
        loaded(ok,nil,offset)
    end
end

function M.on_line(conn, line)
    if M.identity_pending and M.identity_pending[conn] then
        local nick=M.identity_pending[conn];M.identity_pending[conn]=nil
        local login,effective=line:match('^IDENTITY ([0-9a-f]+) ([0-9a-f]+)$')
        if login~=cooloo.public_id() or not effective or #effective~=64 or
           (M.requested_effective and effective~=M.requested_effective) or
           ((conn~=M.ctrl or M.identity_confirmed) and effective~=M.identity()) then
            M.status='identity changed or invalid; reset Workspace: Identity'
            M.auth_failed=true;M.close_all();return
        end
        M.login_id=login;M.effective=effective~=login and effective or nil
        M.identity_confirmed=true;M.auth_failed=false
        M.ready_identity(conn,nick);return
    end
    if M.as_pending and M.as_pending[conn] then
        local nick = M.as_pending[conn]
        M.as_pending[conn] = nil
        if line ~= 'OK' then
            M.status = line
            M.auth_failed = true
            M.close_all() -- never fall back to login identity on failed delegation
            return
        end
        M.auth_failed = false
        query_identity(conn,nick)
        return
    end
    local s = (M.sent_conns or {})[conn]
    if s then
        if s.pending then
            local h = s.pending; s.pending = nil
            local msg = cooloo.record(line)
            if not msg or #line ~= h.len or msg.from ~= M.identity() or msg.to ~= s.peer then
                M.status = 'invalid sent history'; cooloo.net.close(conn); return
            end
            local key = s.peer .. ':' .. h.endoff
            s.room.sent_ends = s.room.sent_ends or {}
            if not s.room.sent_ends[key] then
                s.room.sent_ends[key] = true
                s.room.revision=(s.room.revision or 0)+1
                table.insert(s.room.buf, {endoff=h.endoff, ts=msg.ts, from=msg.from,
                    nick=msg.from, text=msg.content, to=msg.to, sent=true})
                table.sort(s.room.buf, function(a,b)
                    if a.ts ~= b.ts then return a.ts < b.ts end
                    if (a.to or s.room.name) ~= (b.to or s.room.name) then
                        return (a.to or s.room.name) < (b.to or s.room.name)
                    end
                    return a.endoff < b.endoff
                end)
                if #s.room.buf > ROOM_CAP then table.remove(s.room.buf, 1) end
            end
            return
        end
        local off, len = line:match('^MSG (%d+) (%d+)$')
        if off then s.pending = {endoff=tonumber(off),len=tonumber(len)}; return end
        if line:match('^END %d+$') or line:sub(1,4) == 'ERR ' then
            local offset=tonumber(line:match('^END (%d+)$'))
            if offset then M.sent_offsets=M.sent_offsets or {};M.sent_offsets[s.peer]=offset end
            if line:sub(1,4) == 'ERR ' then M.status = line end
            M.sent_conns[conn] = nil
            cooloo.net.close(conn)
            M.fetch_sent(s.room)
        end
        return
    end
    if conn == M.ctrl then
        local room, nickname = line:match("^ROOM (%x+) (.+)$")
        if room then
            local r = M.ensure_room(room)
            r.nickname = nickname
            if M.rooms_pending then M.rooms_pending[room] = true end
            if not M.subscriptions then cooloo.net.send(conn, "METAFILE " .. room .. "\n") end
            return
        end
        local meta = line:match("^META (.+)$")
        if meta then
            if M.metadata then M.metadata(meta)
            elseif not cooloo.cache_meta(cooloo.net.fp(conn), M.identity(), meta) then
                M.status = "metadata cache failure"
            end
            return
        end
        local id, kind, owner, slot, name = line:match("^INFO (%x+) (%S+) (%S+) (%d+) (.+)$")
        if id then
            M.names = M.names or {}; M.names[id] = name
            for _, r in pairs(M.rooms) do
                for _, m in ipairs(r.buf) do
                    if m.from == id then m.nick = name; m.wrap = nil;r.revision=(r.revision or 0)+1 end
                end
            end
            return
        end
        if line == "END" then
            if M.rooms_pending then
                for id,r in pairs(M.rooms) do
                    if r.listed and not M.rooms_pending[id] then r.denied=true end
                    if M.rooms_pending[id] then r.listed=true;r.denied=nil end
                end
                M.rooms_pending=nil
                M.rooms_refreshed_at=cooloo.time()
            end
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
        if nick and nick ~= "-" then
            M.nick = nick
            M.registered = true
            M.want_register = false
            M.status = ""   -- clear a stale "registering as ..." text
            cfgset("nick", nick)
            -- Registration creates the inbox; refresh the visible address list.
            M.refresh_rooms()
            if M.rooms_loaded then M.start_follows() end
            return
        end
        if line:sub(1, 4) == "ERR " then
            M.status = line
            M.rooms_pending=nil
            if M.effective and line:match('^ERR forbidden') then
                -- AS already succeeded. A read-only command denial must not
                -- revoke an independent write grant for this identity.
                M.read_denied=true
            end
            return
        end
        return -- OK / PONG: fine
    end

    local r = M.by_conn[conn]
    if not r then return end
    if r.pending then
        local h = r.pending
        r.pending = nil
        local msg = cooloo.record(line)
        if not msg or #line ~= h.len or msg.to ~= r.name then
            M.status='invalid message';cooloo.net.close(conn);M.on_closed(conn,M.status);return
        end
        local function persisted(ok)
        if M.by_conn[conn] ~= r then return end
        if not ok then
            M.status = "cache write failure"
            cooloo.net.close(conn);M.on_closed(conn,M.status)
            return
        end
        M.names = M.names or {}
        if not M.names[msg.from] then
            M.names[msg.from] = msg.from
            cooloo.net.send(M.ctrl, "META " .. msg.from .. "\n")
        end
        add_msg(r, h.endoff, msg.ts, M.names[msg.from], msg.content,msg.from)
        if r.following and r.name == M.identity() then M.fetch_sent(r) end
        end
        if M.persist then M.persist(r,h.endoff,line,persisted)
        else persisted(cooloo.cache_append(r.server_fp,r.self_id,r.name,h.endoff,line)) end
        return
    end
    local e, len = line:match("^MSG (%d+) (%d+)$")
    if e then
        -- READ pauses live push, so MSG lines in a READ window are all
        -- READ results; count them raw (pre-dedupe) to detect a short read
        if r.phase == "reading" or r.backfilling then
            r.read_received = r.read_received + 1
        end
        r.pending = { endoff = tonumber(e), len = tonumber(len) }
        return
    end
    if line == "END" then
        if (r.phase == "reading" or r.backfilling) and
            r.read_received < r.read_requested then
            r.exhausted = true
        end
        r.backfilling = false
        if not r.following then send_follow(r) end
        if r.name == M.identity() then M.fetch_sent(r) end
        return
    end
    if line:sub(1, 4) == "ERR " then
        M.status = line
        if line:match('^ERR forbidden') then
            r.denied=true
            cooloo.net.close(conn);M.on_closed(conn,line);return
        end
        -- an ERR before FOLLOW is terminal for the current op (e.g. D25
        -- not-registered): close so on_closed schedules a reconnect that
        -- re-opens the room conn once we're allowed (registered)
        if not r.following then
            cooloo.net.close(conn);r.denied=true;M.on_closed(conn,line)
        end
        return
    end
end

-- Peers come only from received messages. Filtered results stay outside the
-- contiguous inbox cache. One query at a time, bounded to 256 peers per refresh.
function M.fetch_sent(r)
    M.sent_conns, M.sent_seen = M.sent_conns or {}, M.sent_seen or {}
    if next(M.sent_conns) then return end
    local count = 0; for _ in pairs(M.sent_seen) do count = count + 1 end
    if count >= 256 then return end
    for i = #r.buf, 1, -1 do
        local peer = r.buf[i].from
        if peer and peer ~= M.identity() and not M.sent_seen[peer] then
            local conn = cooloo.net.connect(M.host, M.port)
            if not conn then return end
            M.sent_seen[peer] = true
            M.sent_conns[conn] = {peer=peer, room=r}
            return
        end
    end
end

function M.on_closed(conn, reason)
    if M.identity_pending then M.identity_pending[conn]=nil end
    if M.as_pending then M.as_pending[conn] = nil end
    if M.sent_conns and M.sent_conns[conn] then
        M.sent_conns[conn] = nil
        M.status = 'sent history interrupted: ' .. reason
        return
    end
    if conn == M.ctrl then
        M.ctrl = nil
        M.ctrl_up = false
        M.rooms_pending=nil
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
    local as = text:match('^/as ([0-9a-f]+)$')
    if as then return M.use_identity(as) end
    if text == '/self' then return M.use_identity(nil) end
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
    if #r.buf >= ROOM_CAP then M.status = "older history is available in local JSONL" end
end

function M.register(nick)
    if M.ctrl_up then
        cooloo.net.send(M.ctrl, ("HELLO %s\n"):format(nick))
    end
end

function M.select(name)
    if M.rooms[name] then
        M.sel = name
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
    for conn in pairs(M.sent_conns or {}) do cooloo.net.close(conn) end
    M.sent_conns, M.as_pending, M.identity_pending = {}, {}, {}
    if M.ctrl then cooloo.net.close(M.ctrl); M.ctrl = nil end
    M.ctrl_up = false
    M.rooms_pending=nil
    M.registered = false
    for conn, r in pairs(M.by_conn) do
        cooloo.net.close(conn)
        r.conn = nil
        r.pending = nil
        r.phase = "idle"
        r.following = false
    end
    M.by_conn = {}
end

function M.reconnect()
    M.close_all()
    M.want_reconnect = false
    M.auth_failed = false
    M.read_denied = false
    M.sent_seen = {}
    for _,r in pairs(M.rooms) do r.denied=nil end
    M.connect_ctrl()
    if M.rooms_loaded then M.start_follows() end
end
