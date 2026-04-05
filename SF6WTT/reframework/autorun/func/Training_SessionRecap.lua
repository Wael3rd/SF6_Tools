-- =========================================================
-- Training_SessionRecap.lua
-- D2D overlay : barres (Reactions/PostGuard) ou courbes (HitConfirm)
-- =========================================================

local M = {}

-- State
local _visible = false
local _sessions = {}
local _title = ""
local _mode = ""  -- "reactions", "hitconfirm", "postguard"
local _font = nil
local _font_small = nil
local _last_font_h = 0
local _last_font_h_small = 0
local _debug_msg = ""

-- Colors (ABGR : 0xAABBGGRR)
local COL_BG        = 0xF0181818
local COL_BORDER    = 0xFFAAAAAA
local COL_HEADER_BG = 0x44FFFFFF
local COL_HEADER    = 0xFF00DDFF
local COL_TEXT      = 0xFFDADADA
local COL_TEXT_DIM  = 0xFF888888
local COL_BAR_BG    = 0xFF333333
local COL_BAR_RED   = 0xFF4444FF
local COL_BAR_ORG   = 0xFF00A5FF
local COL_BAR_YEL   = 0xFF00FFFF
local COL_BAR_GRN   = 0xFF00DD00
local COL_SHADOW    = 0xFF000000
local COL_CLOSE_BG  = 0x44FFFFFF
local COL_CLOSE_HOV = 0x884444FF
local COL_CLOSE_TXT = 0xFFDADADA
local COL_HIT       = 0xFF00A5FF  -- orange (hit confirm)
local COL_BLK       = 0xFFFFFF00  -- cyan (block confirm)
local COL_GRID      = 0xFF2D3246

local _close_btn = { x = 0, y = 0, w = 0, h = 0 }

local function bar_color(pct)
    if pct < 40 then return COL_BAR_RED
    elseif pct < 60 then return COL_BAR_ORG
    elseif pct < 75 then return COL_BAR_YEL
    else return COL_BAR_GRN end
end

-- =========================================================
-- D2D LINE DRAWING (pixel stepping)
-- =========================================================
local function draw_line(x1, y1, x2, y2, thickness, color)
    local dx = x2 - x1
    local dy = y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy), 1)
    local sx = dx / steps
    local sy = dy / steps
    local t = thickness or 2
    for i = 0, math.floor(steps) do
        d2d.fill_rect(x1 + sx * i, y1 + sy * i, t, t, color)
    end
end

-- =========================================================
-- PARSERS
-- =========================================================

local function tail_n(results, count)
    local n = #results
    local start = math.max(1, n - count + 1)
    local out = {}
    for i = start, n do out[#out + 1] = results[i] end
    return out
end

local function extract_date(raw)
    local y, mo, da, hh, mm = raw:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+)")
    if da and hh then
        return (da or "??") .. "/" .. (mo or "??") .. " " .. hh .. ":" .. mm
    end
    local y2, mo2, da2 = raw:match("(%d+)-(%d+)-(%d+)")
    return (da2 or "??") .. "/" .. (mo2 or "??")
end

local function extract_short_time(raw)
    local hh, mm = raw:match("(%d+):(%d+)")
    return hh and (hh .. ":" .. mm) or "?"
end

-- Reactions : date\tduration\tmode\tp1\tp2\tscore\ttotal  (pas de header)
local function parse_reactions(filepath)
    local results = {}
    local f = io.open(filepath, "r")
    if not f then return results end
    for line in f:lines() do
        local parts = {}
        for p in line:gmatch("[^\t]+") do parts[#parts + 1] = p end
        if #parts >= 7 then
            local score = tonumber(parts[6])
            local total = tonumber(parts[7])
            if score and total and total > 0 then
                results[#results + 1] = {
                    date  = extract_date(parts[1]),
                    pct   = (score / total) * 100,
                    score = score,
                    total = total
                }
            end
        end
    end
    f:close()
    return tail_n(results, 7)
end

-- HitConfirm : 14 cols avec hit_pct et blk_pct separees
-- date\ttime\tmode\tduration\ttotal\tsuccess\tpct%\tscore\thit_tot\thit_ok\thit_pct%\tblk_tot\tblk_ok\tblk_pct%
local function parse_hitconfirm(filepath)
    local results = {}
    local f = io.open(filepath, "r")
    if not f then return results end
    for line in f:lines() do
        if not line:match("^DATE") then
            local parts = {}
            for p in line:gmatch("[^\t]+") do parts[#parts + 1] = p end
            if #parts >= 14 then
                local total   = tonumber(parts[5])
                local hit_pct = tonumber((parts[11]:gsub("%%", "")))
                local blk_pct = tonumber((parts[14]:gsub("%%", "")))
                local pct     = tonumber((parts[7]:gsub("%%", "")))
                if total and total > 0 and hit_pct and blk_pct then
                    results[#results + 1] = {
                        date    = extract_date(parts[1]),
                        time    = extract_short_time(parts[2]),
                        pct     = pct or 0,
                        hit_pct = hit_pct,
                        blk_pct = blk_pct,
                        score   = tonumber(parts[6]) or 0,
                        total   = total
                    }
                end
            end
        end
    end
    f:close()
    return tail_n(results, 10)
end

-- PostGuard : date\tduration\tscore\tpct%\ttotal\tdetails
local function parse_postguard(filepath)
    local results = {}
    local f = io.open(filepath, "r")
    if not f then return results end
    for line in f:lines() do
        if not line:match("^DATE") then
            local parts = {}
            for p in line:gmatch("[^\t]+") do parts[#parts + 1] = p end
            if #parts >= 5 then
                local score = tonumber(parts[3])
                local pct   = tonumber((parts[4]:gsub("%%", "")))
                local total = tonumber(parts[5])
                if pct and total and total > 0 then
                    results[#results + 1] = {
                        date  = extract_date(parts[1]),
                        pct   = pct,
                        score = score or 0,
                        total = total
                    }
                end
            end
        end
    end
    f:close()
    return tail_n(results, 7)
end

local PARSERS = {
    reactions  = parse_reactions,
    hitconfirm = parse_hitconfirm,
    postguard  = parse_postguard
}

-- =========================================================
-- PUBLIC API
-- =========================================================

function M.show(mode_name, stats_file, parser_type)
    local parser = PARSERS[parser_type]
    if not parser then
        _debug_msg = "ERROR: unknown parser type '" .. tostring(parser_type) .. "'"
        return
    end

    local test_f = io.open(stats_file, "r")
    if not test_f then
        _debug_msg = "ERROR: file not found '" .. stats_file .. "'"
        return
    end
    local file_content = test_f:read("*a")
    test_f:close()
    local line_count = 0
    for _ in file_content:gmatch("[^\n]+") do line_count = line_count + 1 end
    _debug_msg = "File OK: '" .. stats_file .. "' (" .. line_count .. " lines)"

    _sessions = parser(stats_file)
    _mode = parser_type
    local n = #_sessions
    _debug_msg = _debug_msg .. " -> parsed " .. n .. " sessions"
    if n == 0 then return end
    _title = mode_name .. "  -  LAST " .. n .. " SESSION" .. (n > 1 and "S" or "")
    _visible = true
end

function M.hide()
    _visible = false
    _sessions = {}
    _mode = ""
end

function M.is_visible()
    return _visible
end

-- =========================================================
-- D2D: SHARED HEADER + CLOSE BUTTON
-- =========================================================

local function draw_header(panel_x, panel_y, panel_w, header_h, fh, pad)
    d2d.fill_rect(panel_x, panel_y, panel_w, header_h, COL_HEADER_BG)
    local tx = panel_x + pad
    local ty = panel_y + (header_h - fh) * 0.5
    d2d.text(_font, _title, tx + 1, ty + 1, COL_SHADOW)
    d2d.text(_font, _title, tx, ty, COL_HEADER)

    -- Close button [X]
    local btn_size = header_h * 0.65
    local btn_x = panel_x + panel_w - pad - btn_size
    local btn_y = panel_y + (header_h - btn_size) * 0.5
    _close_btn.x = btn_x
    _close_btn.y = btn_y
    _close_btn.w = btn_size
    _close_btn.h = btn_size

    local is_hovered = false
    pcall(function()
        local m = imgui.get_mouse()
        if m then
            is_hovered = m.x >= btn_x and m.x <= btn_x + btn_size
                     and m.y >= btn_y and m.y <= btn_y + btn_size
        end
    end)

    d2d.fill_rect(btn_x, btn_y, btn_size, btn_size, is_hovered and COL_CLOSE_HOV or COL_CLOSE_BG)
    d2d.outline_rect(btn_x, btn_y, btn_size, btn_size, 1, 0x66FFFFFF)
    local x_tx = btn_x + btn_size * 0.25
    local x_ty = btn_y + (btn_size - fh) * 0.5
    d2d.text(_font, "X", x_tx + 1, x_ty + 1, COL_SHADOW)
    d2d.text(_font, "X", x_tx, x_ty, COL_CLOSE_TXT)
end

-- =========================================================
-- D2D: BAR CHART (Reactions / PostGuard)
-- =========================================================

local function draw_bars(sw, sh, fh, fh_s)
    local n        = #_sessions
    local row_h    = fh * 2.2
    local header_h = fh * 2.8
    local footer_h = fh * 2.5
    local pad      = sh * 0.012
    local panel_w  = sw * 0.34
    local panel_h  = header_h + (n * row_h) + footer_h + pad
    local panel_x  = (sw - panel_w) * 0.5
    local panel_y  = (sh - panel_h) * 0.5

    d2d.fill_rect(panel_x, panel_y, panel_w, panel_h, COL_BG)
    d2d.outline_rect(panel_x, panel_y, panel_w, panel_h, 2, COL_BORDER)
    draw_header(panel_x, panel_y, panel_w, header_h, fh, pad)

    local date_x    = panel_x + pad
    local bar_x     = panel_x + panel_w * 0.22
    local bar_max_w = panel_w * 0.40
    local pct_x     = bar_x + bar_max_w + pad
    local score_x   = pct_x + panel_w * 0.11
    local bar_h     = row_h * 0.50
    local sum_pct   = 0

    for i, s in ipairs(_sessions) do
        pcall(function()
            local ry  = panel_y + header_h + (i - 1) * row_h
            local by  = ry + (row_h - bar_h) * 0.5
            local tty = ry + (row_h - fh_s) * 0.5

            if i % 2 == 0 then
                d2d.fill_rect(panel_x, ry, panel_w, row_h, 0x11FFFFFF)
            end

            d2d.text(_font_small, tostring(s.date or "?"), date_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, tostring(s.date or "?"), date_x, tty, COL_TEXT_DIM)

            d2d.fill_rect(bar_x, by, bar_max_w, bar_h, COL_BAR_BG)
            local pct_safe = tonumber(s.pct) or 0
            local fill_w = bar_max_w * math.min(pct_safe, 100) / 100
            local col = bar_color(pct_safe)
            d2d.fill_rect(bar_x, by, fill_w, bar_h, col)
            d2d.outline_rect(bar_x, by, bar_max_w, bar_h, 1, 0x44FFFFFF)

            local pct_str = string.format("%d%%", math.floor(pct_safe))
            d2d.text(_font_small, pct_str, pct_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, pct_str, pct_x, tty, col)

            local sc_str = string.format("%d/%d", tonumber(s.score) or 0, tonumber(s.total) or 0)
            d2d.text(_font_small, sc_str, score_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, sc_str, score_x, tty, COL_TEXT)

            sum_pct = sum_pct + pct_safe
        end)
    end

    -- Footer
    local avg = sum_pct / n
    local fy = panel_y + header_h + n * row_h + (footer_h - fh) * 0.5

    if n >= 2 then
        local trend = _sessions[n].pct - _sessions[1].pct
        local trend_str = trend >= 0
            and string.format("+%d%%", math.floor(trend))
            or  string.format("%d%%", math.floor(trend))
        local trend_col = trend >= 0 and COL_BAR_GRN or COL_BAR_RED
        d2d.text(_font, trend_str, panel_x + pad + 1, fy + 1, COL_SHADOW)
        d2d.text(_font, trend_str, panel_x + pad, fy, trend_col)
    end

    local avg_str = string.format("AVG: %d%%", math.floor(avg))
    local avg_w = #avg_str * fh * 0.6
    local avg_x = panel_x + panel_w - pad - avg_w
    d2d.text(_font, avg_str, avg_x + 1, fy + 1, COL_SHADOW)
    d2d.text(_font, avg_str, avg_x, fy, bar_color(avg))
end

-- =========================================================
-- D2D: LINE CHART (HitConfirm - hit% & block% courbes)
-- =========================================================

local function draw_chart(sw, sh, fh, fh_s)
    local n        = #_sessions
    local header_h = fh * 2.8
    local pad      = sh * 0.012
    local chart_h  = sh * 0.28
    local legend_h = fh * 2.0
    local footer_h = fh * 2.5
    local panel_w  = sw * 0.40
    local panel_h  = header_h + pad + chart_h + legend_h + footer_h + pad
    local panel_x  = (sw - panel_w) * 0.5
    local panel_y  = (sh - panel_h) * 0.5

    d2d.fill_rect(panel_x, panel_y, panel_w, panel_h, COL_BG)
    d2d.outline_rect(panel_x, panel_y, panel_w, panel_h, 2, COL_BORDER)
    draw_header(panel_x, panel_y, panel_w, header_h, fh, pad)

    -- Chart area
    local cx = panel_x + pad * 4  -- leave space for Y axis labels
    local cy = panel_y + header_h + pad
    local cw = panel_w - pad * 6
    local ch = chart_h

    -- Background du graphique
    d2d.fill_rect(cx, cy, cw, ch, 0xFF111111)
    d2d.outline_rect(cx, cy, cw, ch, 1, COL_GRID)

    -- Grille Y (0%, 25%, 50%, 75%, 100%)
    for _, pct in ipairs({0, 25, 50, 75, 100}) do
        local gy = cy + ch - (ch * pct / 100)
        d2d.fill_rect(cx, gy, cw, 1, COL_GRID)
        local label = tostring(pct) .. "%"
        d2d.text(_font_small, label, panel_x + pad * 0.5, gy - fh_s * 0.5, COL_TEXT_DIM)
    end

    -- Helper: map session index to X position
    local function sx(i)
        if n == 1 then return cx + cw * 0.5 end
        return cx + (i - 1) * cw / (n - 1)
    end

    -- Helper: map percentage to Y position
    local function sy(pct)
        return cy + ch - (ch * math.min(math.max(pct, 0), 100) / 100)
    end

    -- Dessiner les courbes
    local dot_r = math.max(3, fh * 0.2)
    local hover_r = dot_r * 2.5  -- zone de detection hover plus large que le point
    local tooltip = nil  -- { x, y, text, color } si hover detecte

    -- Lire la position de la souris une seule fois
    local mx, my = 0, 0
    pcall(function()
        local m = imgui.get_mouse()
        if m then mx, my = m.x, m.y end
    end)

    -- Hit% curve (orange)
    for i = 1, n do
        pcall(function()
            local hp = tonumber(_sessions[i].hit_pct) or 0
            if i > 1 then
                local hp_prev = tonumber(_sessions[i-1].hit_pct) or 0
                draw_line(sx(i-1), sy(hp_prev), sx(i), sy(hp), 2, COL_HIT)
            end
            local px, py = sx(i), sy(hp)
            local is_hov = math.abs(mx - px) < hover_r and math.abs(my - py) < hover_r
            local size = is_hov and dot_r * 1.6 or dot_r
            d2d.fill_rect(px - size, py - size, size * 2, size * 2, COL_HIT)
            if is_hov then
                tooltip = { x = px, y = py, text = string.format("HIT: %.1f%%", hp), color = COL_HIT }
            end
        end)
    end

    -- Block% curve (cyan)
    for i = 1, n do
        pcall(function()
            local bp = tonumber(_sessions[i].blk_pct) or 0
            if i > 1 then
                local bp_prev = tonumber(_sessions[i-1].blk_pct) or 0
                draw_line(sx(i-1), sy(bp_prev), sx(i), sy(bp), 2, COL_BLK)
            end
            local px, py = sx(i), sy(bp)
            local is_hov = math.abs(mx - px) < hover_r and math.abs(my - py) < hover_r
            local size = is_hov and dot_r * 1.6 or dot_r
            d2d.fill_rect(px - size, py - size, size * 2, size * 2, COL_BLK)
            if is_hov and not tooltip then  -- hit a priorite si les deux se chevauchent
                tooltip = { x = px, y = py, text = string.format("BLK: %.1f%%", bp), color = COL_BLK }
            end
        end)
    end

    -- Tooltip au dessus du point
    if tooltip then
        local tt = tooltip
        local tt_w = #tt.text * fh_s * 0.62 + pad * 2
        local tt_h = fh_s + pad
        local tt_x = tt.x - tt_w * 0.5
        local tt_y = tt.y - tt_h - dot_r * 2
        d2d.fill_rect(tt_x, tt_y, tt_w, tt_h, 0xEE222222)
        d2d.outline_rect(tt_x, tt_y, tt_w, tt_h, 1, tt.color)
        d2d.text(_font_small, tt.text, tt_x + pad, tt_y + pad * 0.3, tt.color)
    end

    -- X axis labels (session time)
    for i = 1, n do
        pcall(function()
            local label = _sessions[i].time or tostring(i)
            local lx = sx(i) - #label * fh_s * 0.25
            d2d.text(_font_small, label, lx, cy + ch + 2, COL_TEXT_DIM)
        end)
    end

    -- Legende
    local leg_y = cy + ch + fh_s * 1.5
    local leg_x1 = cx + cw * 0.15
    local leg_x2 = cx + cw * 0.55

    d2d.fill_rect(leg_x1, leg_y + fh_s * 0.3, fh_s, fh_s * 0.4, COL_HIT)
    d2d.text(_font_small, "HIT %", leg_x1 + fh_s * 1.5, leg_y, COL_HIT)

    d2d.fill_rect(leg_x2, leg_y + fh_s * 0.3, fh_s, fh_s * 0.4, COL_BLK)
    d2d.text(_font_small, "BLOCK %", leg_x2 + fh_s * 1.5, leg_y, COL_BLK)

    -- Footer: averages
    local fy = panel_y + panel_h - footer_h + (footer_h - fh) * 0.5
    local sum_hit, sum_blk = 0, 0
    for _, s in ipairs(_sessions) do
        sum_hit = sum_hit + (tonumber(s.hit_pct) or 0)
        sum_blk = sum_blk + (tonumber(s.blk_pct) or 0)
    end
    local avg_hit = sum_hit / n
    local avg_blk = sum_blk / n

    local hit_str = string.format("HIT AVG: %d%%", math.floor(avg_hit))
    d2d.text(_font, hit_str, panel_x + pad + 1, fy + 1, COL_SHADOW)
    d2d.text(_font, hit_str, panel_x + pad, fy, COL_HIT)

    local blk_str = string.format("BLOCK AVG: %d%%", math.floor(avg_blk))
    local blk_w = #blk_str * fh * 0.6
    local blk_x = panel_x + panel_w - pad - blk_w
    d2d.text(_font, blk_str, blk_x + 1, fy + 1, COL_SHADOW)
    d2d.text(_font, blk_str, blk_x, fy, COL_BLK)
end

-- =========================================================
-- D2D MAIN DRAW
-- =========================================================

local function d2d_init() end

local function d2d_draw()
    if not _visible or #_sessions == 0 then return end

    local sw, sh = d2d.surface_size()

    local fh   = math.floor(sh * 0.016)
    local fh_s = math.floor(sh * 0.013)
    if fh ~= _last_font_h then
        _font = d2d.Font.new("Consolas", fh)
        _last_font_h = fh
    end
    if fh_s ~= _last_font_h_small then
        _font_small = d2d.Font.new("Consolas", fh_s)
        _last_font_h_small = fh_s
    end

    if _mode == "hitconfirm" then
        pcall(draw_chart, sw, sh, fh, fh_s)
    else
        pcall(draw_bars, sw, sh, fh, fh_s)
    end
end

-- Register D2D
if d2d and d2d.register then
    d2d.register(d2d_init, d2d_draw)
end

-- Click detection
re.on_frame(function()
    if not _visible then return end
    pcall(function()
        if imgui.is_mouse_clicked(0) then
            local m = imgui.get_mouse()
            if m then
                local b = _close_btn
                if b.w > 0 and m.x >= b.x and m.x <= b.x + b.w and m.y >= b.y and m.y <= b.y + b.h then
                    M.hide()
                end
            end
        end
    end)
end)

-- Debug
re.on_draw_ui(function()
    if imgui.tree_node("Session Recap Debug") then
        imgui.text("Visible: " .. tostring(_visible))
        imgui.text("Mode: " .. _mode)
        imgui.text("Sessions: " .. #_sessions)
        imgui.text("Debug: " .. _debug_msg)
        for i, s in ipairs(_sessions) do
            local extra = ""
            if s.hit_pct then extra = " | hit:" .. tostring(s.hit_pct) .. "% blk:" .. tostring(s.blk_pct) .. "%" end
            imgui.text("  [" .. i .. "] " .. tostring(s.date) .. " | " .. tostring(s.pct) .. "% | " .. tostring(s.score) .. "/" .. tostring(s.total) .. extra)
        end
        if _visible and imgui.button("Close Recap") then
            M.hide()
        end
        if imgui.button("Test Show (HitConfirm)") then
            M.show("HIT CONFIRM", "HitConfirm_SessionStats.txt", "hitconfirm")
        end
        if imgui.button("Copy Debug to Clipboard") then
            local lines = {}
            lines[#lines + 1] = "Visible: " .. tostring(_visible)
            lines[#lines + 1] = "Mode: " .. _mode
            lines[#lines + 1] = "Sessions: " .. #_sessions
            lines[#lines + 1] = "Debug: " .. _debug_msg
            for i, s in ipairs(_sessions) do
                local extra = ""
                if s.hit_pct then extra = " | hit:" .. tostring(s.hit_pct) .. "% blk:" .. tostring(s.blk_pct) .. "%" end
                lines[#lines + 1] = "  [" .. i .. "] " .. tostring(s.date) .. " | " .. tostring(s.pct) .. "% | " .. tostring(s.score) .. "/" .. tostring(s.total) .. extra
            end
            pcall(imgui.set_clipboard_text, table.concat(lines, "\n"))
            _debug_msg = _debug_msg .. " | Copied!"
        end
        imgui.tree_pop()
    end
end)

return M
