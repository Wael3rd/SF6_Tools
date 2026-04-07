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
local _font_title = nil
local _last_font_h = 0
local _last_font_h_small = 0
local _last_font_h_title = 0
local _debug_msg = ""

-- Colors (ABGR : 0xAABBGGRR)
local COL_BG        = 0xF00D0D12
local COL_BORDER    = 0xFF3A3A4A
local COL_HEADER_BG = 0xFF1A1A28
local COL_HEADER    = 0xFFFFAA44  -- warm orange title
local COL_TEXT      = 0xFFE0E0E0
local COL_TEXT_DIM  = 0xFF6A6A7A
local COL_BAR_BG    = 0xFF1E1E2E
local COL_BAR_RED   = 0xFF4444FF
local COL_BAR_ORG   = 0xFF00A5FF
local COL_BAR_YEL   = 0xFF00FFFF
local COL_BAR_GRN   = 0xFF00DD00
local COL_SHADOW    = 0xFF000000
local COL_CLOSE_BG  = 0x33FFFFFF
local COL_CLOSE_HOV = 0x664444FF
local COL_CLOSE_TXT = 0xFFDADADA
local COL_HIT       = 0xFFF5C832  -- warm gold (hit confirm)
local COL_BLK       = 0xFFEE6644  -- coral/salmon (block confirm)
local COL_GRID      = 0xFF1E2233
local COL_CHART_BG  = 0xFF0A0A14
local COL_ACCENT    = 0xFF3A3A5A

-- Layout config (all values in % of screen, saved to JSON)
local LAYOUT_FILE = "SessionRecap_Layout.json"
local layout = {
    panel_w  = 0.48,
    panel_cy = 0.50,
    header_h = 0.034,
    chart_h  = 0.30,
    axis_h   = 0.042,
    legend_h = 0.022,
    footer_h = 0.038,
    pad      = 0.014,
    margin_l = 0.040,
    margin_r = 0.012,
    title_y  = 0.485,
    btn_inset = 0.010,
    btn_size = 0.019,
    title_ox = 0.025, title_oy = 0.0,
    btn_ox = 0.006, btn_oy = 0.0,
    ylabels_ox = 0.0, ylabels_oy = 0.0,
    chart_ox = 0.0, chart_oy = 0.0,
    xlabels_ox = 0.0, xlabels_oy = 0.0,
    legend_ox = 0.0, legend_oy = 0.030,
    legdot_ox = -0.002, legdot_oy = 0.008,
    closex_ox = 0.0, closex_oy = -0.010,
    footer_ox = 0.0, footer_oy = -0.009,
    hitavg_ox = 0.002, hitavg_oy = -0.008,
    blkavg_ox = 0.005, blkavg_oy = -0.007,
}

pcall(function()
    local data = json.load_file(LAYOUT_FILE)
    if data then for k, v in pairs(data) do layout[k] = v end end
end)

local function save_layout()
    json.dump_file(LAYOUT_FILE, layout)
end

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
                    time  = extract_short_time(parts[1]),
                    mode  = parts[3] or "",
                    pct   = (score / total) * 100,
                    score = score,
                    total = total
                }
            end
        end
    end
    f:close()
    return tail_n(results, 10)
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
                        mode    = parts[3] or "",
                        pct     = pct or 0,
                        hit_pct = hit_pct,
                        blk_pct = blk_pct,
                        hit_tot = tonumber(parts[9]) or 0,
                        hit_ok  = tonumber(parts[10]) or 0,
                        blk_tot = tonumber(parts[12]) or 0,
                        blk_ok  = tonumber(parts[13]) or 0,
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
                    local success = math.floor(pct * total / 100 + 0.5)
                    results[#results + 1] = {
                        date  = extract_date(parts[1]),
                        time  = extract_short_time(parts[1]),
                        mode  = "",
                        pct   = pct,
                        score = success,
                        total = total
                    }
                end
            end
        end
    end
    f:close()
    return tail_n(results, 10)
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
    -- Header background
    d2d.fill_rect(panel_x, panel_y, panel_w, header_h, COL_HEADER_BG)
    -- Accent separator at bottom of header
    d2d.fill_rect(panel_x, panel_y + header_h - 2, panel_w, 2, COL_ACCENT)

    -- Title — centered horizontally, adjustable vertical bias
    local title_font = _font_title or _font
    local fh_title = _last_font_h_title or fh
    local title_w = #_title * fh_title * 0.52
    local sw_local, sh_local = d2d.surface_size()
    local tx = panel_x + (panel_w - title_w) * 0.5 + sw_local * (layout.title_ox or 0)
    local ty = panel_y + (header_h - fh_title) * (layout.title_y or 0.48) + sh_local * (layout.title_oy or 0)
    d2d.text(title_font, _title, tx + 1, ty + 1, COL_SHADOW)
    d2d.text(title_font, _title, tx, ty, COL_HEADER)

    -- Close button
    local btn_size = sh_local * (layout.btn_size or 0.016)
    local btn_inset = sw_local * (layout.btn_inset or 0.010)
    local btn_x = panel_x + panel_w - btn_inset - btn_size + sw_local * (layout.btn_ox or 0)
    local btn_y = panel_y + (header_h - btn_size) * 0.5 + sh_local * (layout.btn_oy or 0)
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
    d2d.outline_rect(btn_x, btn_y, btn_size, btn_size, 1, COL_ACCENT)
    -- "X" centered in button + offset
    local x_char_w = fh * 0.55
    local x_tx = btn_x + (btn_size - x_char_w) * 0.5 + sw_local * (layout.closex_ox or 0)
    local x_ty = btn_y + (btn_size - fh) * 0.5 + sh_local * (layout.closex_oy or 0)
    d2d.text(_font, "X", x_tx + 1, x_ty + 1, COL_SHADOW)
    d2d.text(_font, "X", x_tx, x_ty, is_hovered and 0xFFFFFFFF or COL_CLOSE_TXT)
end

-- =========================================================
-- D2D: BAR CHART (Reactions / PostGuard)
-- =========================================================

local function draw_bars(sw, sh, fh, fh_s)
    local n        = #_sessions
    local L        = layout
    local pad      = sh * L.pad
    local header_h = sh * L.header_h
    local row_h    = fh_s * 2.6
    local footer_h = sh * L.footer_h
    local content_h = n * row_h
    local panel_w  = sw * L.panel_w * 0.75
    local panel_h  = header_h + pad + content_h + pad + footer_h + pad
    local panel_x  = (sw - panel_w) * 0.5
    local panel_y  = sh * L.panel_cy - panel_h * 0.5

    -- Panel background with shadow
    d2d.fill_rect(panel_x - 1, panel_y - 1, panel_w + 2, panel_h + 2, COL_SHADOW)
    d2d.fill_rect(panel_x, panel_y, panel_w, panel_h, COL_BG)
    d2d.outline_rect(panel_x, panel_y, panel_w, panel_h, 1, COL_BORDER)
    draw_header(panel_x, panel_y, panel_w, header_h, fh, pad)

    -- Column positions
    local content_x = panel_x + pad * 1.5
    local content_y = panel_y + header_h + pad
    local date_w    = panel_w * 0.18
    local bar_x     = content_x + date_w + pad
    local bar_max_w = panel_w * 0.38
    local pct_x     = bar_x + bar_max_w + pad * 1.5
    local score_x   = pct_x + panel_w * 0.12
    local bar_h     = row_h * 0.45
    local sum_pct   = 0

    for i, s in ipairs(_sessions) do
        pcall(function()
            local ry  = content_y + (i - 1) * row_h
            local by  = ry + (row_h - bar_h) * 0.5
            local tty = ry + (row_h - fh_s) * 0.5

            -- Alternating row bg
            if i % 2 == 0 then
                d2d.fill_rect(panel_x + 1, ry, panel_w - 2, row_h, 0x0CFFFFFF)
            end

            -- Date
            d2d.text(_font_small, tostring(s.date or "?"), content_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, tostring(s.date or "?"), content_x, tty, COL_TEXT_DIM)

            -- Bar
            d2d.fill_rect(bar_x, by, bar_max_w, bar_h, COL_BAR_BG)
            local pct_safe = tonumber(s.pct) or 0
            local fill_w = bar_max_w * math.min(pct_safe, 100) / 100
            local col = bar_color(pct_safe)
            d2d.fill_rect(bar_x, by, fill_w, bar_h, col)
            d2d.outline_rect(bar_x, by, bar_max_w, bar_h, 1, COL_ACCENT)

            -- Percentage
            local pct_str = string.format("%d%%", math.floor(pct_safe))
            d2d.text(_font_small, pct_str, pct_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, pct_str, pct_x, tty, col)

            -- Score
            local sc_str = string.format("%d/%d", tonumber(s.score) or 0, tonumber(s.total) or 0)
            d2d.text(_font_small, sc_str, score_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, sc_str, score_x, tty, COL_TEXT)

            sum_pct = sum_pct + pct_safe
        end)
    end

    -- Footer separator + content
    local fy_sep = content_y + content_h + pad * 0.5
    d2d.fill_rect(panel_x + pad * 1.5, fy_sep, panel_w - pad * 3, 1, COL_ACCENT)
    local fy = fy_sep + (footer_h - fh) * 0.5

    local avg = sum_pct / n

    if n >= 2 then
        local trend = _sessions[n].pct - _sessions[1].pct
        local trend_str = trend >= 0
            and string.format("TREND: +%d%%", math.floor(trend))
            or  string.format("TREND: %d%%", math.floor(trend))
        local trend_col = trend >= 0 and COL_BAR_GRN or COL_BAR_RED
        d2d.text(_font, trend_str, panel_x + pad * 1.5 + 1, fy + 1, COL_SHADOW)
        d2d.text(_font, trend_str, panel_x + pad * 1.5, fy, trend_col)
    end

    local avg_str = string.format("AVG: %d%%", math.floor(avg))
    local avg_w = #avg_str * fh * 0.6
    d2d.text(_font, avg_str, panel_x + panel_w - pad * 1.5 - avg_w + 1, fy + 1, COL_SHADOW)
    d2d.text(_font, avg_str, panel_x + panel_w - pad * 1.5 - avg_w, fy, bar_color(avg))
end

-- =========================================================
-- D2D: LINE CHART (HitConfirm - hit% & block% courbes)
-- =========================================================

local COL_SINGLE    = 0xFF44DDFF  -- bright cyan for single-curve mode

local function draw_chart(sw, sh, fh, fh_s)
    local n        = #_sessions
    local L = layout
    -- Dual mode (hit+blk) or single mode (pct only)
    local dual_mode = (_sessions[1].hit_pct ~= nil)
    local pad      = sh * L.pad
    local header_h = sh * L.header_h
    local chart_h  = sh * L.chart_h
    local axis_h   = sh * L.axis_h
    local legend_h = sh * L.legend_h
    local footer_h = sh * L.footer_h
    local panel_w  = sw * L.panel_w
    local panel_h  = header_h + pad + chart_h + axis_h + legend_h + footer_h + pad
    local panel_x  = (sw - panel_w) * 0.5
    local panel_y  = sh * L.panel_cy - panel_h * 0.5

    -- Panel background with subtle inner shadow
    d2d.fill_rect(panel_x - 1, panel_y - 1, panel_w + 2, panel_h + 2, COL_SHADOW)
    d2d.fill_rect(panel_x, panel_y, panel_w, panel_h, COL_BG)
    d2d.outline_rect(panel_x, panel_y, panel_w, panel_h, 1, COL_BORDER)

    draw_header(panel_x, panel_y, panel_w, header_h, fh, pad)

    -- Chart area with inset look
    local margin_l = sw * L.margin_l
    local margin_r = sw * L.margin_r
    local cx = panel_x + margin_l + sw * (L.chart_ox or 0)
    local cy = panel_y + header_h + pad * 1.5 + sh * (L.chart_oy or 0)
    local cw = panel_w - margin_l - margin_r
    local ch = chart_h

    d2d.fill_rect(cx, cy, cw, ch, COL_CHART_BG)
    d2d.outline_rect(cx, cy, cw, ch, 1, COL_ACCENT)

    -- Y axis grid + labels (right-aligned to chart left edge)
    for _, pct in ipairs({0, 25, 50, 75, 100}) do
        local gy = cy + ch - (ch * pct / 100)
        if pct > 0 and pct < 100 then
            for gx = cx, cx + cw - 4, 8 do
                d2d.fill_rect(gx, gy, 4, 1, COL_GRID)
            end
        else
            d2d.fill_rect(cx, gy, cw, 1, COL_ACCENT)
        end
        local label = tostring(pct) .. "%"
        local lw = #label * fh_s * 0.55
        local lx = cx - lw - pad * 0.5 + sw * (L.ylabels_ox or 0)
        d2d.text(_font_small, label, lx, gy - fh_s * 0.45 + sh * (L.ylabels_oy or 0), COL_TEXT_DIM)
    end

    -- Helpers
    local function sx(i)
        if n == 1 then return cx + cw * 0.5 end
        return cx + pad + (i - 1) * (cw - pad * 2) / (n - 1)
    end
    local function sy(pct)
        return cy + ch - (ch * math.min(math.max(pct, 0), 100) / 100)
    end

    -- Vertical grid lines per session (subtle)
    for i = 1, n do
        local gx = sx(i)
        for gy = cy + 2, cy + ch - 2, 6 do
            d2d.fill_rect(gx, gy, 1, 3, 0x18FFFFFF)
        end
    end

    -- Curves
    local dot_r = math.max(3, fh * 0.22)
    local hover_r = dot_r * 3
    local tooltip = nil

    local mx, my = 0, 0
    pcall(function()
        local m = imgui.get_mouse()
        if m then mx, my = m.x, m.y end
    end)

    -- Define curve data: dual mode (hit+blk) or single mode (pct)
    local curves = {}
    if dual_mode then
        curves[#curves + 1] = { key = "hit_pct", ok_key = "hit_ok", tot_key = "hit_tot", label = "HIT", color = COL_HIT, fill = 0x0CF5C832 }
        curves[#curves + 1] = { key = "blk_pct", ok_key = "blk_ok", tot_key = "blk_tot", label = "BLK", color = COL_BLK, fill = 0x0CEE6644 }
    else
        curves[#curves + 1] = { key = "pct", ok_key = "score", tot_key = "total", label = "SUCCESS", color = COL_SINGLE, fill = 0x0C44DDFF }
    end

    -- Area fill under curves
    for _, c in ipairs(curves) do
        for i = 2, n do
            pcall(function()
                local v = tonumber(_sessions[i][c.key]) or 0
                local vp = tonumber(_sessions[i-1][c.key]) or 0
                local x1, x2 = sx(i-1), sx(i)
                local y1, y2 = sy(vp), sy(v)
                local base = cy + ch
                local steps = math.max(1, math.floor(x2 - x1))
                for s = 0, steps do
                    local t = s / steps
                    local lx = x1 + (x2 - x1) * t
                    local ly = y1 + (y2 - y1) * t
                    d2d.fill_rect(lx, ly, 1, base - ly, c.fill)
                end
            end)
        end
    end

    -- Lines + dots
    for ci, c in ipairs(curves) do
        for i = 1, n do
            pcall(function()
                local v = tonumber(_sessions[i][c.key]) or 0
                if i > 1 then
                    local vp = tonumber(_sessions[i-1][c.key]) or 0
                    draw_line(sx(i-1), sy(vp), sx(i), sy(v), 2, c.color)
                end
                local px, py = sx(i), sy(v)
                local is_hov = math.abs(mx - px) < hover_r and math.abs(my - py) < hover_r
                local size = is_hov and dot_r * 1.8 or dot_r
                d2d.fill_rect(px - size - 1, py - size - 1, size * 2 + 2, size * 2 + 2, COL_CHART_BG)
                d2d.fill_rect(px - size, py - size, size * 2, size * 2, c.color)
                if is_hov and not tooltip then
                    local s = _sessions[i]
                    tooltip = { x = px, y = py, text = string.format("%s: %.1f%%", c.label, v), text2 = string.format("%d / %d", tonumber(s[c.ok_key]) or 0, tonumber(s[c.tot_key]) or 0), color = c.color }
                end
            end)
        end
    end

    -- Tooltip
    if tooltip then
        local tt = tooltip
        local max_len = math.max(#tt.text, #(tt.text2 or ""))
        local tt_w = max_len * fh_s * 0.62 + pad * 3
        local tt_h = fh_s * 2.2 + pad * 1.5
        local tt_x = tt.x - tt_w * 0.5
        local tt_y = tt.y - tt_h - dot_r * 3
        -- Clamp inside chart
        if tt_x < cx then tt_x = cx end
        if tt_x + tt_w > cx + cw then tt_x = cx + cw - tt_w end
        if tt_y < cy then tt_y = tt.y + dot_r * 3 end
        -- Shadow + bg
        d2d.fill_rect(tt_x + 2, tt_y + 2, tt_w, tt_h, 0x88000000)
        d2d.fill_rect(tt_x, tt_y, tt_w, tt_h, 0xF0141420)
        d2d.outline_rect(tt_x, tt_y, tt_w, tt_h, 1, tt.color)
        -- Accent line on top
        d2d.fill_rect(tt_x, tt_y, tt_w, 2, tt.color)
        d2d.text(_font_small, tt.text, tt_x + pad, tt_y + pad * 0.6, tt.color)
        if tt.text2 then
            d2d.text(_font_small, tt.text2, tt_x + pad, tt_y + pad * 0.6 + fh_s * 1.1, COL_TEXT)
        end
    end

    -- X axis labels (date + time + mode) — centered under each point
    local cw_char = fh_s * 0.55
    local xl_ox = sw * (L.xlabels_ox or 0)
    local xl_oy = sh * (L.xlabels_oy or 0)
    for i = 1, n do
        pcall(function()
            local s = _sessions[i]
            local date_lbl = s.date or ""
            local time_lbl = s.time or tostring(i)
            local base_y = cy + ch + pad * 0.8 + xl_oy
            local xi = sx(i) + xl_ox

            -- Tick mark
            d2d.fill_rect(xi, cy + ch, 1, pad * 0.5, COL_ACCENT)

            -- Date
            d2d.text(_font_small, date_lbl, xi - #date_lbl * cw_char * 0.5, base_y, COL_TEXT_DIM)

            -- Time
            d2d.text(_font_small, time_lbl, xi - #time_lbl * cw_char * 0.5, base_y + fh_s * 1.15, COL_TEXT)

            -- Mode tag
            local mode_raw = s.mode or ""
            local mode_tag = ""
            local t_count = mode_raw:match("TRIALS_(%d+)")
            local t_min = mode_raw:match("TIMED_(%d+M)")
            if t_count then mode_tag = "T" .. t_count
            elseif t_min then mode_tag = t_min end
            if mode_tag ~= "" then
                d2d.text(_font_small, mode_tag, xi - #mode_tag * cw_char * 0.5, base_y + fh_s * 2.3, COL_TEXT_DIM)
            end
        end)
    end

    -- Legend — centered symmetrically, adapts to number of curves
    local leg_y = cy + ch + axis_h + pad * 0.3 + sh * (L.legend_oy or 0)
    local leg_cx = cx + cw * 0.5 + sw * (L.legend_ox or 0)
    local dot_sz = fh_s * 0.6
    local ldot_ox = sw * (L.legdot_ox or 0)
    local ldot_oy = sh * (L.legdot_oy or 0)
    local leg_gap = cw * 0.08

    local leg_labels = {}
    for _, c in ipairs(curves) do
        leg_labels[#leg_labels + 1] = { text = c.label .. " %", color = c.color }
    end
    -- Measure total width
    local leg_items_w = {}
    local total_leg = 0
    for i, ll in ipairs(leg_labels) do
        local w = dot_sz + fh_s * 0.5 + #ll.text * cw_char
        leg_items_w[i] = w
        total_leg = total_leg + w
        if i < #leg_labels then total_leg = total_leg + leg_gap end
    end
    local leg_x = leg_cx - total_leg * 0.5
    for i, ll in ipairs(leg_labels) do
        d2d.fill_rect(leg_x + ldot_ox, leg_y + (fh_s - dot_sz) * 0.5 + ldot_oy, dot_sz, dot_sz, ll.color)
        d2d.text(_font_small, ll.text, leg_x + dot_sz + fh_s * 0.4, leg_y, ll.color)
        leg_x = leg_x + leg_items_w[i] + leg_gap
    end

    -- Footer: averages with accent separator
    local ft_ox = sw * (L.footer_ox or 0)
    local ft_oy = sh * (L.footer_oy or 0)
    local fy_sep = panel_y + panel_h - footer_h + ft_oy
    d2d.fill_rect(panel_x + pad * 1.5, fy_sep, panel_w - pad * 3, 1, COL_ACCENT)
    local fy = fy_sep + (footer_h - fh) * 0.5

    if dual_mode then
        local sum_hit, sum_blk = 0, 0
        for _, s in ipairs(_sessions) do
            sum_hit = sum_hit + (tonumber(s.hit_pct) or 0)
            sum_blk = sum_blk + (tonumber(s.blk_pct) or 0)
        end
        local avg_hit = sum_hit / n
        local avg_blk = sum_blk / n

        local hit_str = string.format("HIT AVG: %d%%", math.floor(avg_hit))
        local ha_x = panel_x + pad * 1.5 + ft_ox + sw * (L.hitavg_ox or 0)
        local ha_y = fy + sh * (L.hitavg_oy or 0)
        d2d.text(_font, hit_str, ha_x + 1, ha_y + 1, COL_SHADOW)
        d2d.text(_font, hit_str, ha_x, ha_y, COL_HIT)

        local blk_str = string.format("BLOCK AVG: %d%%", math.floor(avg_blk))
        local blk_w = #blk_str * fh * 0.6
        local ba_x = panel_x + panel_w - pad * 1.5 - blk_w + ft_ox + sw * (L.blkavg_ox or 0)
        local ba_y = fy + sh * (L.blkavg_oy or 0)
        d2d.text(_font, blk_str, ba_x + 1, ba_y + 1, COL_SHADOW)
        d2d.text(_font, blk_str, ba_x, ba_y, COL_BLK)
    else
        -- Single mode: trend left, avg right
        local sum_pct = 0
        for _, s in ipairs(_sessions) do sum_pct = sum_pct + (tonumber(s.pct) or 0) end
        local avg_pct = sum_pct / n

        if n >= 2 then
            local trend = (tonumber(_sessions[n].pct) or 0) - (tonumber(_sessions[1].pct) or 0)
            local trend_str = trend >= 0
                and string.format("TREND: +%d%%", math.floor(trend))
                or  string.format("TREND: %d%%", math.floor(trend))
            local trend_col = trend >= 0 and COL_BAR_GRN or COL_BAR_RED
            d2d.text(_font, trend_str, panel_x + pad * 1.5 + ft_ox + 1, fy + 1, COL_SHADOW)
            d2d.text(_font, trend_str, panel_x + pad * 1.5 + ft_ox, fy, trend_col)
        end

        local avg_str = string.format("AVG: %d%%", math.floor(avg_pct))
        local avg_w = #avg_str * fh * 0.6
        d2d.text(_font, avg_str, panel_x + panel_w - pad * 1.5 - avg_w + ft_ox + 1, fy + 1, COL_SHADOW)
        d2d.text(_font, avg_str, panel_x + panel_w - pad * 1.5 - avg_w + ft_ox, fy, COL_SINGLE)
    end
end

-- =========================================================
-- D2D MAIN DRAW
-- =========================================================

local function d2d_init() end

local function d2d_draw()
    _G.SessionRecapVisible = _visible and #_sessions > 0
    if not _visible or #_sessions == 0 then return end

    local sw, sh = d2d.surface_size()

    local fh   = math.floor(sh * 0.015)
    local fh_s = math.floor(sh * 0.012)
    local fh_t = math.floor(sh * 0.020)
    if fh ~= _last_font_h then
        _font = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", fh)
        _last_font_h = fh
    end
    if fh_s ~= _last_font_h_small then
        _font_small = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", fh_s)
        _last_font_h_small = fh_s
    end
    if fh_t ~= _last_font_h_title then
        _font_title = d2d.Font.new("SF6_college.ttf", fh_t)
        _last_font_h_title = fh_t
    end

    pcall(draw_chart, sw, sh, fh, fh_s)
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
    if imgui.tree_node("Session Recap") then
        -- Layout editor

        -- Debug
        if imgui.tree_node("Debug") then
            imgui.text("Visible: " .. tostring(_visible))
            imgui.text("Mode: " .. _mode)
            imgui.text("Sessions: " .. #_sessions)
            imgui.text("Debug: " .. _debug_msg)
            for i, s in ipairs(_sessions) do
                local extra = ""
                if s.hit_pct then extra = " | hit:" .. tostring(s.hit_pct) .. "% blk:" .. tostring(s.blk_pct) .. "%" end
                imgui.text("  [" .. i .. "] " .. tostring(s.date) .. " | " .. tostring(s.pct) .. "% | " .. tostring(s.score) .. "/" .. tostring(s.total) .. extra)
            end
            imgui.tree_pop()
        end

        if _visible and imgui.button("Close Recap") then M.hide() end
        if imgui.button("Test Show (HitConfirm)") then
            M.show("HIT CONFIRM", "HitConfirm_SessionStats.txt", "hitconfirm")
        end
        imgui.tree_pop()
    end
end)

return M
