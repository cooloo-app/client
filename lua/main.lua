-- main.lua - entry point: cooloo.frame implementation + app state machine
-- (04 doc 4.1). Runs last (embed order: chat, ui, input, main).
--
-- Key bindings (04 doc 4.5):
--   Ctrl-J / Ctrl-K   switch room          Enter       send
--   Shift/Ctrl-Enter  newline in input     PageUp/Dn   scroll history
--   Ctrl-L            reconnect            Ctrl-Q      quit
--   F2                server/self info overlay
--
-- `state` survives lua-dev reloads (guard idiom); conns live in C slots
-- so a reload keeps the session.

state = state or {
    mode = "connect",     -- connect | tofu | register | chat
    booted = false,
    fp = nil,             -- own identity fingerprint
    server_fp = nil,
    tofu_conns = {},      -- conns parked at TOFU prompt
    tofu = nil,           -- {conn=, fp=} being displayed
    info = false,         -- F2 overlay
    last_ping = 0,
    reconnect_at = 0,
}

local st = state

local MOD_CTRL = 1

local function page_lines()
    local _, h = cooloo.screen()
    local lh = cooloo.line_height(15)
    return math.max(1, (h - (lh + 8) - (lh * 3 // 2 + 10) - 8) // lh - 1)
end

-- ------------------------------------------------------------------
-- boot (once)
-- ------------------------------------------------------------------

if not st.booted then
    st.booted = true
    st.fp = cooloo.ensure_identity()
    local host, port = cooloo.server()
    chat.init(host, port)
    chat.connect_ctrl()
end

-- ------------------------------------------------------------------
-- event handlers
-- ------------------------------------------------------------------

local function on_tofu_key(key)
    if key == "t" then
        for _, c in ipairs(st.tofu_conns) do cooloo.net.trust(c) end
        st.tofu_conns = {}
        st.tofu = nil
        st.mode = "connect"
    elseif key == "escape" then
        cooloo.quit()     -- rejected: abort like the v1 CLI does
    end
end

local function on_key(ev)
    local key, mod = ev.key, ev.mod
    local ctrl = (mod & MOD_CTRL) ~= 0

    if st.mode == "tofu" then
        on_tofu_key(key)
        return
    end

    -- global keys
    if key == "q" and ctrl then cooloo.quit(); return end
    if key == "l" and ctrl then
        chat.reconnect()
        chat.status = "reconnecting..."
        return
    end
    if key == "f2" then st.info = not st.info; return end
    if key == "escape" and st.info then st.info = false; return end
    if st.mode ~= "chat" and st.mode ~= "register" then return end
    if key == "j" and ctrl then chat.cycle(1); return end
    if key == "k" and ctrl then chat.cycle(-1); return end
    if key == "pageup" then
        local r = chat.current()
        if r then chat.scroll(r, page_lines()) end
        return
    end
    if key == "pagedown" then
        local r = chat.current()
        if r then chat.scroll(r, -page_lines()) end
        return
    end

    local r = input.on_key(key, mod)
    if r ~= "submit" then return end

    if st.mode == "register" then
        local nick = input.buf
        if nick:match("^[a-z0-9_%-]+$") and #nick <= 16 then
            chat.register(nick)
            chat.status = "registering as " .. nick .. "..."
        else
            chat.status = "invalid nick ([a-z0-9_-]{1,16})"
        end
        input.reset()
    else
        if chat.send_text(input.buf) then
            input.reset()
        end
    end
end

local function on_mouse(ev)
    if st.mode ~= "chat" then return end
    local lh = cooloo.line_height(15)
    if ev.kind == "wheel" then
        local r = chat.current()
        if r then chat.scroll(r, ev.wy * 3) end
    elseif ev.kind == "down" and ev.button == 1 then
        if ev.x < 160 then
            local idx = (ev.y - (8 + lh + 4)) // (lh + 6) + 1
            local name = chat.order[idx]
            if name then chat.select(name) end
        end
    end
end

local function handle(ev)
    local t = ev.type
    if t == "key" then on_key(ev)
    elseif t == "text" then
        if st.mode == "chat" or st.mode == "register" then
            input.on_text(ev.text)
        end
    elseif t == "ime_edit" then
        if st.mode == "chat" or st.mode == "register" then
            input.on_ime(ev.text, ev.cursor)
        end
    elseif t == "mouse" then on_mouse(ev)
    elseif t == "net_ready" then
        chat.on_ready(ev.conn, ev.nick)
        if ev.conn == chat.ctrl then
            st.server_fp = cooloo.net.fp(ev.conn)
        end
    elseif t == "net_line" then
        chat.on_line(ev.conn, ev.line)
    elseif t == "net_closed" then
        chat.on_closed(ev.conn, ev.reason)
        if chat.want_reconnect and st.reconnect_at < cooloo.time() then
            st.reconnect_at = cooloo.time() + 2
        end
    elseif t == "net_tofu" then
        st.tofu_conns[#st.tofu_conns + 1] = ev.conn
        st.tofu = { conn = ev.conn, fp = ev.fp }
        st.mode = "tofu"
    elseif t == "quit" then
        cooloo.quit()
    end
end

-- ------------------------------------------------------------------
-- periodic work (keepalive, reconnect, mode transitions, IME rect)
-- ------------------------------------------------------------------

local function periodic()
    local now = cooloo.time()

    if now - st.last_ping > 30 then
        st.last_ping = now
        if chat.ctrl_up then
            cooloo.net.send(chat.ctrl, "PING\n")
            -- piggyback a room-list refresh so rooms created after
            -- connect show up (start_follows only opens missing conns)
            cooloo.net.send(chat.ctrl, "ROOMS\n")
        end
        for conn, _ in pairs(chat.by_conn) do
            cooloo.net.send(conn, "PING\n")
        end
    end

    if chat.want_reconnect and now >= st.reconnect_at then
        st.reconnect_at = now + 2
        chat.want_reconnect = false   -- re-set if this attempt fails
        chat.ensure_conns()
    end

    -- mode transitions driven by chat flags
    if st.mode == "connect" then
        if chat.want_register then
            st.mode = "register"
            input.reset()
        elseif chat.ctrl_up then
            st.mode = "chat"
        end
    elseif st.mode == "register" then
        if chat.registered then st.mode = "chat" end
    end

    if chat.ctrl and chat.ctrl_up then
        st.server_fp = cooloo.net.fp(chat.ctrl) or st.server_fp
    end

    -- place the OS IME candidate window at the input cursor
    if st.mode == "chat" or st.mode == "register" then
        local x, y, w, h = ui.input_cursor_pos()
        cooloo.set_ime_rect(x, y + h, w, h)
    end
end

-- ------------------------------------------------------------------
-- the one C->Lua entry point (04 doc 4.2)
-- ------------------------------------------------------------------

function cooloo.frame(events, dt)
    for _, ev in ipairs(events) do
        local ok, err = pcall(handle, ev)
        if not ok then cooloo.log("event error: " .. tostring(err)) end
    end
    periodic()
    return ui.render(st)
end
