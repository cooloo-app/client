-- ui.lua - layout + draw-list generation (04 doc 4.1/4.2, D33/D34).
-- Terminal aesthetic: dark bg, monospace, no rounded corners, no icons.
-- Data table survives lua-dev reloads; functions are replaced.

ui = ui or {
    size = 15,
}

local U = ui

local C = {
    bg        = 0x1a1a1a,
    panel     = 0x1f1f1f,
    input_bg  = 0x232323,
    status_bg = 0x121212,
    fg        = 0xd8d8d8,
    gray      = 0x777777,
    dim       = 0x4a4a4a,
    border    = 0x3a3a3a,
    sel       = 0x2d3a4d,
    cursor    = 0xc0c0c0,
    err       = 0xd05050,
    ime_line  = 0xaaaa55,
}

-- 8-color nick palette (hash by nick, D34)
local NICK_COLORS = {
    0x6cb6ff, 0xff9e64, 0x9ece6a, 0xf7768e,
    0xbb9af7, 0x4fd6be, 0xffc777, 0x7aa2f7,
}

local SIZE = 15

local function nick_color(nick)
    local h = 0
    for i = 1, #nick do
        h = (h * 31 + nick:byte(i)) & 0x7fffffff
    end
    return NICK_COLORS[h % #NICK_COLORS + 1]
end

-- ------------------------------------------------------------------
-- text wrapping (cached per message per width)
-- ------------------------------------------------------------------

local function wrap_para(para, avail)
    -- returns array of chunk strings, hard-broken at avail px
    local chunks = {}
    local cur, curw, last_sp = "", 0, nil
    for _, cp in utf8.codes(para, true) do
        local ch = utf8.char(cp)
        local cw = cooloo.text_width(ch, SIZE)
        if curw + cw > avail and cur ~= "" then
            if last_sp and last_sp > 1 then
                chunks[#chunks + 1] = cur:sub(1, last_sp - 1)
                cur = cur:sub(last_sp + 1) .. ch
                curw = cooloo.text_width(cur, SIZE)
            else
                chunks[#chunks + 1] = cur
                cur, curw = ch, cw
            end
            last_sp = nil
        else
            cur = cur .. ch
            curw = curw + cw
            if ch == " " then last_sp = #cur end
        end
    end
    chunks[#chunks + 1] = cur
    return chunks
end

local function wrap_msg(m, avail)
    if m.wrap and m.wrap.avail == avail then return m.wrap.chunks end
    local chunks = {}
    local paras = {}
    m.text:gsub("([^\n]*)\n?", function(p) paras[#paras + 1] = p end)
    if paras[#paras] == "" then paras[#paras] = nil end
    if #paras == 0 then paras = { "" } end
    for _, p in ipairs(paras) do
        local w = wrap_para(p, avail)
        for _, c in ipairs(w) do chunks[#chunks + 1] = c end
    end
    m.wrap = { avail = avail, chunks = chunks }
    return chunks
end

-- ------------------------------------------------------------------
-- layout
-- ------------------------------------------------------------------

local function layout()
    local w, h = cooloo.screen()
    local lh = cooloo.line_height(SIZE)
    local status_h = lh + 8
    local input_h = lh * 3 // 2 + 10
    local L = {
        w = w, h = h, lh = lh,
        rooms_w = 160,
        status_h = status_h,
        input_h = input_h,
        msg_x = 168,
        msg_y = 4,
        msg_w = w - 168 - 8,
        msg_h = h - status_h - input_h - 8,
        input_x = 168,
        input_y = h - status_h - input_h,
        input_w = w - 168 - 8,
    }
    return L
end

-- exposed so main.lua can place the OS IME candidate window
function U.input_cursor_pos()
    local L = layout()
    local pre = input.buf:sub(1, input.cursor - 1)
    if input.ime then pre = pre .. input.ime.text end
    pre = pre:gsub("\n", " ")
    local px = cooloo.text_width("> " .. pre, SIZE) - (input.view_x or 0)
    return L.input_x + 6 + px, L.input_y + 4, 8, L.lh
end

-- ------------------------------------------------------------------
-- draw-list helpers
-- ------------------------------------------------------------------

local function newlist()
    local dl = {}
    local o = {}
    function o.rect(x, y, w, h, c)
        dl[#dl + 1] = { op = "rect", x = x, y = y, w = w, h = h, color = c }
    end
    function o.text(x, y, s, c, size)
        dl[#dl + 1] = { op = "text", x = x, y = y, text = s,
                        color = c, size = size or SIZE }
    end
    function o.clip(x, y, w, h)
        dl[#dl + 1] = { op = "clip", x = x, y = y, w = w, h = h }
    end
    function o.unclip() dl[#dl + 1] = { op = "unclip" } end
    function o.done()
        dl[#dl + 1] = { op = "present" }
        return dl
    end
    return o
end

-- ------------------------------------------------------------------
-- partial renderers
-- ------------------------------------------------------------------

local function render_status(o, L, st)
    o.rect(0, L.h - L.status_h, L.w, L.status_h, C.status_bg)
    local left = chat.status
    if left == "" then
        local n_up = 0
        for _, r in pairs(chat.rooms) do
            if r.phase == "following" then n_up = n_up + 1 end
        end
        left = ("%d rooms | %s"):format(#chat.order,
              chat.ctrl_up and "online" or "connecting...")
        if n_up < #chat.order then left = left .. " (rooms connecting)" end
    end
    o.text(8, L.h - L.status_h + 4, left,
           left:sub(1, 4) == "ERR " and C.err or C.gray)
    local right = ("%s@%s:%d"):format(chat.nick ~= "" and chat.nick or "?",
                                      chat.host or "?", chat.port or 0)
    o.text(L.w - cooloo.text_width(right, SIZE) - 8, L.h - L.status_h + 4,
           right, C.gray)
end

local function render_rooms(o, L)
    o.rect(0, 0, L.rooms_w, L.h - L.status_h, C.panel)
    o.rect(L.rooms_w, 0, 1, L.h - L.status_h, C.border)
    o.text(10, 8, "rooms", C.dim)
    local y = 8 + L.lh + 4
    for _, name in ipairs(chat.order) do
        local r = chat.rooms[name]
        if name == chat.sel then
            o.rect(4, y - 3, L.rooms_w - 8, L.lh + 6, C.sel)
        end
        o.text(10, y, "#" .. name, name == chat.sel and C.fg or C.gray)
        if r.unread > 0 then
            local b = ("+%d"):format(r.unread)
            o.text(L.rooms_w - cooloo.text_width(b, SIZE) - 10, y, b,
                   C.fg)
        end
        y = y + L.lh + 6
        if y > L.h - L.status_h - L.lh then break end
    end
end

local function render_messages(o, L)
    local r = chat.current()
    o.rect(L.msg_x, L.msg_y, L.msg_w, L.msg_h, C.bg)
    if not r then
        o.text(L.msg_x + 8, L.msg_y + 8, "(no room selected)", C.dim)
        return
    end
    if #r.buf == 0 then
        local hint = r.phase == "following" and "(no messages)"
            or ("(" .. (r.phase or "idle") .. "...)")
        o.text(L.msg_x + 8, L.msg_y + 8, hint, C.dim)
        return
    end

    local indent = cooloo.text_width("      ", SIZE)
    local avail = L.msg_w - 16
    local lines, need = {}, L.msg_h // L.lh
    local skip, skipped = r.scroll, 0
    local mi = #r.buf
    local exhausted = false

    while mi >= 1 and #lines < need do
        local m = r.buf[mi]
        local chunks = wrap_msg(m, avail - indent)
        local ci = #chunks
        while ci >= 1 and #lines < need do
            if skip > 0 then
                skip = skip - 1
                skipped = skipped + 1
            else
                table.insert(lines, 1, { m = m, idx = ci,
                                         chunk = chunks[ci] })
            end
            ci = ci - 1
        end
        mi = mi - 1
    end
    exhausted = mi == 0

    -- overscroll clamp + top-of-history backfill trigger (04 doc 6.3)
    if exhausted then
        if skipped < r.scroll then r.scroll = skipped end
        if r.scroll > 0 or #lines < need then
            chat.maybe_backfill(r)
        end
    end

    o.clip(L.msg_x, L.msg_y, L.msg_w, L.msg_h)
    local y = L.msg_y + L.msg_h - #lines * L.lh
    for _, ln in ipairs(lines) do
        local m, chunk = ln.m, ln.chunk
        if ln.idx == 1 then
            local ts = os.date("%H:%M", m.ts)
            o.text(L.msg_x + 4, y, ts, C.dim)
            local x2 = L.msg_x + 4 + cooloo.text_width(ts .. " ", SIZE)
            local nick = "<" .. m.nick .. ">"
            o.text(x2, y, nick, nick_color(m.nick))
            x2 = x2 + cooloo.text_width(nick .. " ", SIZE)
            o.text(x2, y, chunk, C.fg)
        else
            o.text(L.msg_x + 4 + indent, y, chunk, C.fg)
        end
        y = y + L.lh
    end
    o.unclip()
end

local function render_input(o, L)
    o.rect(L.input_x, L.input_y, L.input_w, L.input_h, C.input_bg)
    o.rect(L.input_x, L.input_y, L.input_w, 1, C.border)
    local disp = input.buf
    if input.ime then
        disp = disp:sub(1, input.cursor - 1) .. input.ime.text ..
               disp:sub(input.cursor)
    end
    disp = disp:gsub("\n", " ")
    local full = "> " .. disp

    -- horizontal scroll keeps the cursor visible
    local pre = input.buf:sub(1, input.cursor - 1)
    if input.ime then pre = pre .. input.ime.text end
    pre = pre:gsub("\n", " ")
    local cur_px = cooloo.text_width("> " .. pre, SIZE)
    input.view_x = input.view_x or 0
    local boxw = L.input_w - 16
    if cur_px - input.view_x > boxw then
        input.view_x = cur_px - boxw
    elseif cur_px - input.view_x < 0 then
        input.view_x = cur_px
    end

    o.clip(L.input_x, L.input_y, L.input_w, L.input_h)
    o.text(L.input_x + 6 - input.view_x, L.input_y + 5, full, C.fg)
    -- IME preedit underline
    if input.ime then
        local base = cooloo.text_width("> " ..
                     input.buf:sub(1, input.cursor - 1):gsub("\n", " "), SIZE)
        local iw = cooloo.text_width(input.ime.text, SIZE)
        o.rect(L.input_x + 6 + base - input.view_x,
               L.input_y + 5 + L.lh - 2, iw, 1, C.ime_line)
    end
    -- cursor (blinks ~2Hz)
    if math.floor(cooloo.time() * 2) % 2 == 0 then
        o.rect(L.input_x + 6 + cur_px - input.view_x, L.input_y + 5,
               8, L.lh, C.cursor)
    end
    o.unclip()
end

local function render_center(o, L, lines, title)
    o.rect(0, 0, L.w, L.h - L.status_h, C.bg)
    local y = (L.h - L.status_h) // 2 - (#lines + 1) * L.lh
    if title then
        o.text((L.w - cooloo.text_width(title, SIZE)) // 2, y, title, C.fg)
        y = y + L.lh * 2
    end
    for _, s in ipairs(lines) do
        o.text((L.w - cooloo.text_width(s, SIZE)) // 2, y, s, C.gray)
        y = y + L.lh + 4
    end
end

local function render_info(o, L, st)
    local lines = {
        "nick:    " .. (chat.nick ~= "" and chat.nick or "(unregistered)"),
        "self fp: " .. (st.fp or "?"),
        "server:  " .. tostring(chat.host) .. ":" .. tostring(chat.port),
        "srv fp:  " .. (st.server_fp or "?"),
        "rooms:   " .. #chat.order,
        "",
        "[F2/Esc] close",
    }
    local bw, bh = 560, #lines * (L.lh + 4) + 32
    local bx, by = (L.w - bw) // 2, (L.h - bh) // 2
    o.rect(bx, by, bw, bh, C.panel)
    o.rect(bx, by, bw, 1, C.border)
    o.rect(bx, by + bh - 1, bw, 1, C.border)
    o.rect(bx, by, 1, bh, C.border)
    o.rect(bx + bw - 1, by, 1, bh, C.border)
    local y = by + 16
    for _, s in ipairs(lines) do
        o.text(bx + 20, y, s, s:sub(1, 1) == "[" and C.dim or C.fg)
        y = y + L.lh + 4
    end
end

-- ------------------------------------------------------------------
-- main render (called from main.lua's cooloo.frame)
-- ------------------------------------------------------------------

function U.render(st)
    local L = layout()
    local o = newlist()

    if st.mode == "chat" then
        o.rect(0, 0, L.w, L.h, C.bg)
        render_rooms(o, L)
        render_messages(o, L)
        render_input(o, L)
        render_status(o, L, st)
        if st.info then render_info(o, L, st) end
    elseif st.mode == "tofu" then
        render_center(o, L, {
            "unknown server fingerprint:",
            "",
            st.tofu and st.tofu.fp or "?",
            "",
            "[T] trust and pin    [Esc] reject",
        }, "TOFU")
        render_status(o, L, st)
    elseif st.mode == "register" then
        o.rect(0, 0, L.w, L.h, C.bg)
        render_center(o, L, {
            "this key is not registered yet.",
            "nick rules: [a-z0-9_-]{1,16}",
            "",
            "> " .. input.buf,
            "",
            "[Enter] register",
        }, "register")
        render_status(o, L, st)
    else -- boot / connect
        render_center(o, L, {
            "connecting to " .. tostring(chat.host) .. ":" ..
                tostring(chat.port) .. " ...",
        }, "cooloo")
        render_status(o, L, st)
    end
    return o.done()
end
