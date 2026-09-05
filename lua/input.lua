-- input.lua - key handling, input box, IME state (04 doc 4.5).
-- Buffer is a UTF-8 string; cursor is a byte position (1..#buf+1,
-- insert happens before that byte). Data survives lua-dev reloads.

input = input or {
    buf = "",
    cursor = 1,
    ime = nil,      -- {text=, cursor=} composition in progress
    view_x = 0,     -- horizontal scroll (ui.lua adjusts)
}

local I = input

-- key mods bitmask from C: ctrl=1 alt=2 shift=4 gui=8
I.MOD_CTRL = 1
I.MOD_ALT = 2
I.MOD_SHIFT = 4
I.MOD_GUI = 8

function I.reset()
    I.buf = ""
    I.cursor = 1
    I.ime = nil
    I.view_x = 0
end

function I.insert_text(t)
    -- normalize newlines coming from the clipboard
    t = t:gsub("\r\n", "\n"):gsub("\r", "\n")
    I.buf = I.buf:sub(1, I.cursor - 1) .. t .. I.buf:sub(I.cursor)
    I.cursor = I.cursor + #t
end

function I.backspace()
    if I.cursor <= 1 then return end
    local prev = utf8.offset(I.buf, -1, I.cursor) or 1
    I.buf = I.buf:sub(1, prev - 1) .. I.buf:sub(I.cursor)
    I.cursor = prev
end

function I.del()
    if I.cursor > #I.buf then return end
    local nxt = utf8.offset(I.buf, 2, I.cursor) or (#I.buf + 1)
    I.buf = I.buf:sub(1, I.cursor - 1) .. I.buf:sub(nxt)
end

function I.move(d)
    if d < 0 then
        I.cursor = math.max(1, utf8.offset(I.buf, -1, I.cursor) or 1)
    elseif I.cursor <= #I.buf then
        I.cursor = utf8.offset(I.buf, 2, I.cursor) or (#I.buf + 1)
    end
end

-- editing keys; returns "submit" when Enter requests a send, nil otherwise.
-- (global keys like Ctrl-Q / F2 / room switching are handled in main.lua)
function I.on_key(key, mod)
    local ctrl = (mod & I.MOD_CTRL) ~= 0
    local gui = (mod & I.MOD_GUI) ~= 0
    local shift = (mod & I.MOD_SHIFT) ~= 0

    if key == "backspace" then I.backspace()
    elseif key == "delete" then I.del()
    elseif key == "left" then I.move(-1)
    elseif key == "right" then I.move(1)
    elseif key == "home" then I.cursor = 1
    elseif key == "end" then I.cursor = #I.buf + 1
    elseif key == "a" and ctrl then I.cursor = 1
    elseif key == "e" and ctrl then I.cursor = #I.buf + 1
    elseif key == "u" and ctrl then
        I.buf = I.buf:sub(I.cursor)
        I.cursor = 1
    elseif key == "k" and ctrl then
        I.buf = I.buf:sub(1, I.cursor - 1)
    elseif key == "v" and (ctrl or gui) then
        I.insert_text(cooloo.clipboard.get())
    elseif key == "return" then
        if shift or ctrl then
            I.insert_text("\n")
        else
            return "submit"
        end
    end
    return nil
end

function I.on_text(t)
    I.ime = nil        -- committed text replaces the composition
    I.insert_text(t)
end

function I.on_ime(text, cursor)
    if text == "" then
        I.ime = nil
    else
        I.ime = { text = text, cursor = cursor }
    end
end
