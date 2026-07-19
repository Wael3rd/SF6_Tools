-- =========================================================
-- OpenableDropdown.lua - A dropdown that can be opened programmatically (via a
-- hotkey) and navigated with keyboard (arrows + Enter) or controller (FUNC +
-- D-pad/left-stick), unlike the native imgui.combo. Per-instance state keyed by
-- a caller-supplied id. Mirrors the ComboTrials combo dropdown behaviour.
-- =========================================================

local M = {}

local _state = {}          -- id -> { highlight, scroll, is_open, nav_up, nav_down, select, kb }
local _open_requests = {}   -- id -> true (consumed on next draw)

local function st(id)
    local s = _state[id]
    if not s then s = { kb = {} }; _state[id] = s end
    return s
end

-- Called from a hotkey: opens the list, or confirms the current highlight when
-- it is already open (so the same key opens then selects, like ComboTrials).
function M.request_open(id)
    local s = st(id)
    if s.is_open then
        s.select = true
    else
        _open_requests[id] = true
    end
end

local function bool_edge(s, down, key)
    down = down == true
    local prev = s.kb[key]
    s.kb[key] = down
    return down and not prev
end

local function kb_edge(s, vk, key)
    local ok, d = pcall(reframework.is_key_down, reframework, vk)
    return bool_edge(s, ok and d == true, key)
end

-- Up/down from the controller: HID button mask (D-pad / arcade stick) OR the
-- processed game input, both published by the framework. bit 0x1 = up, 0x2 = down.
local function pad_updown()
    local m = (_G.TrainingPadMask or 0) | (_G.TrainingGameInputMask or 0)
    return (m & 1) ~= 0, (m & 2) ~= 0
end

-- Draws the dropdown. Returns (changed, new_idx, is_open).
-- items: array of display strings. current_idx: 1-based. width: button width.
function M.draw(id, current_idx, items, width)
    items = items or {}
    local s = st(id)
    local popup_id = id .. "_popup"
    local preview = items[current_idx] or "---"

    local win_pos = imgui.get_window_pos()
    local cursor_pos = imgui.get_cursor_pos()
    local btn_x = win_pos.x + cursor_pos.x
    local btn_y = win_pos.y + cursor_pos.y

    local clicked = imgui.button(preview .. "  \xe2\x96\xbc##" .. id, Vector2f.new(width or -1, 0))

    local should_open = clicked or (_open_requests[id] == true)
    if should_open then
        local line_h = imgui.calc_text_size("W").y + 6
        local visible = math.min(#items, 10)
        local popup_h = (visible * line_h) + 8
        imgui.set_next_window_pos(Vector2f.new(btn_x, btn_y - popup_h), 1)
        imgui.open_popup(popup_id)
        s.highlight = current_idx
        s.scroll = true
        _open_requests[id] = nil
    end

    -- Native navigation while open (uses last frame's is_open; fine).
    if s.is_open then
        if kb_edge(s, 0x26, "up")    then s.nav_up = true end
        if kb_edge(s, 0x28, "down")  then s.nav_down = true end
        if kb_edge(s, 0x0D, "enter") then s.select = true end
        if _G.TrainingFuncHeld then
            local up, down = pad_updown()
            if bool_edge(s, up, "pu")   then s.nav_up = true end
            if bool_edge(s, down, "pd") then s.nav_down = true end
        else
            s.kb.pu = false; s.kb.pd = false
        end
    end

    if s.nav_up then
        s.nav_up = false
        if s.highlight and s.highlight > 1 then s.highlight = s.highlight - 1; s.scroll = true end
    end
    if s.nav_down then
        s.nav_down = false
        if s.highlight and s.highlight < #items then s.highlight = s.highlight + 1; s.scroll = true end
    end

    local changed = false
    local new_idx = current_idx
    if imgui.begin_popup(popup_id) then
        s.is_open = true
        if s.select then
            s.select = false
            if s.highlight then new_idx = s.highlight; changed = (new_idx ~= current_idx) end
            imgui.close_current_popup()
        end
        for i = 1, #items do
            local hl = (i == s.highlight)
            if imgui.menu_item(items[i], "", hl, true) then new_idx = i; changed = true end
            if hl and s.scroll then pcall(imgui.set_scroll_here_y); s.scroll = false end
        end
        imgui.end_popup()
    else
        s.is_open = false
        s.highlight = nil
    end

    return changed, new_idx, s.is_open
end

return M
