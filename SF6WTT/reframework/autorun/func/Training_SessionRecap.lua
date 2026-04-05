-- =========================================================
-- Training_SessionRecap.lua
-- D2D overlay : barres horizontales des 7 dernieres sessions
-- =========================================================

local M = {}

-- State
local _visible = false
local _sessions = {}
local _title = ""
local _font = nil
local _font_small = nil
local _last_font_h = 0
local _last_font_h_small = 0
local _debug_msg = ""  -- debug pour diagnostiquer les problèmes de parsing

-- Colors (ABGR : 0xAABBGGRR)
local COL_BG        = 0xF0181818
local COL_BORDER    = 0xFFAAAAAA
local COL_HEADER_BG = 0x44FFFFFF
local COL_HEADER    = 0xFF00DDFF   -- jaune/or
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

-- Close button hit zone (updated each d2d frame)
local _close_btn = { x = 0, y = 0, w = 0, h = 0 }

local function bar_color(pct)
    if pct < 40 then return COL_BAR_RED
    elseif pct < 60 then return COL_BAR_ORG
    elseif pct < 75 then return COL_BAR_YEL
    else return COL_BAR_GRN end
end

-- =========================================================
-- PARSERS (un par type de fichier stats)
-- =========================================================

local function tail_7(results)
    local n = #results
    local start = math.max(1, n - 6)
    local out = {}
    for i = start, n do out[#out + 1] = results[i] end
    return out
end

local function extract_date(raw)
    -- Essaie d'extraire date + heure pour distinguer les sessions du meme jour
    local y, mo, da, hh, mm = raw:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+)")
    if da and hh then
        return (da or "??") .. "/" .. (mo or "??") .. " " .. hh .. ":" .. mm
    end
    local y2, mo2, da2 = raw:match("(%d+)-(%d+)-(%d+)")
    return (da2 or "??") .. "/" .. (mo2 or "??")
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
    return tail_7(results)
end

-- HitConfirm : header optionnel, puis date\ttime\tmode\tduration\ttotal\tsuccess\tpct%\tscore\t...
local function parse_hitconfirm(filepath)
    local results = {}
    local f = io.open(filepath, "r")
    if not f then return results end
    for line in f:lines() do
        if not line:match("^DATE") then
            local parts = {}
            for p in line:gmatch("[^\t]+") do parts[#parts + 1] = p end
            if #parts >= 7 then
                local total   = tonumber(parts[5])
                local success = tonumber(parts[6])
                local pct     = tonumber((parts[7]:gsub("%%", "")))
                if pct and total and total > 0 then
                    results[#results + 1] = {
                        date  = extract_date(parts[1]),
                        pct   = pct,
                        score = success or 0,
                        total = total
                    }
                end
            end
        end
    end
    f:close()
    return tail_7(results)
end

-- PostGuard : header optionnel, puis date\tduration\tscore\tpct%\ttotal\tdetails
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
    return tail_7(results)
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

    -- Test si le fichier existe
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
    local n = #_sessions
    _debug_msg = _debug_msg .. " -> parsed " .. n .. " sessions"
    if n == 0 then return end
    _title = mode_name .. "  -  LAST " .. n .. " SESSION" .. (n > 1 and "S" or "")
    _visible = true
end

function M.hide()
    _visible = false
    _sessions = {}
end

function M.is_visible()
    return _visible
end

-- =========================================================
-- D2D DRAWING
-- =========================================================

local function d2d_init() end

local function d2d_draw()
    if not _visible or #_sessions == 0 then return end

    local sw, sh = d2d.surface_size()

    -- Fonts (recrees si la taille change)
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

    -- Layout
    local n        = #_sessions
    local row_h    = fh * 2.2
    local header_h = fh * 2.8
    local footer_h = fh * 2.5
    local pad      = sh * 0.012
    local panel_w  = sw * 0.34
    local panel_h  = header_h + (n * row_h) + footer_h + pad
    local panel_x  = (sw - panel_w) * 0.5
    local panel_y  = (sh - panel_h) * 0.5

    -- Background + border
    d2d.fill_rect(panel_x, panel_y, panel_w, panel_h, COL_BG)
    d2d.outline_rect(panel_x, panel_y, panel_w, panel_h, 2, COL_BORDER)

    -- Header
    d2d.fill_rect(panel_x, panel_y, panel_w, header_h, COL_HEADER_BG)
    local tx = panel_x + pad
    local ty = panel_y + (header_h - fh) * 0.5
    d2d.text(_font, _title, tx + 1, ty + 1, COL_SHADOW)
    d2d.text(_font, _title, tx, ty, COL_HEADER)

    -- Close button [X] en haut a droite
    local btn_size = header_h * 0.65
    local btn_x = panel_x + panel_w - pad - btn_size
    local btn_y = panel_y + (header_h - btn_size) * 0.5
    _close_btn.x = btn_x
    _close_btn.y = btn_y
    _close_btn.w = btn_size
    _close_btn.h = btn_size

    -- Hover detection (check mouse pos)
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
    local x_label = "\xc3\x97" -- multiplication sign (x)
    local x_tx = btn_x + btn_size * 0.25
    local x_ty = btn_y + (btn_size - fh) * 0.5
    d2d.text(_font, "X", x_tx + 1, x_ty + 1, COL_SHADOW)
    d2d.text(_font, "X", x_tx, x_ty, COL_CLOSE_TXT)

    -- Colonnes
    local date_x    = panel_x + pad
    local bar_x     = panel_x + panel_w * 0.17
    local bar_max_w = panel_w * 0.46
    local pct_x     = bar_x + bar_max_w + pad
    local score_x   = pct_x + panel_w * 0.11
    local bar_h     = row_h * 0.50

    local sum_pct = 0

    for i, s in ipairs(_sessions) do
        local ok, err = pcall(function()
            local ry  = panel_y + header_h + (i - 1) * row_h
            local by  = ry + (row_h - bar_h) * 0.5
            local tty = ry + (row_h - fh_s) * 0.5

            -- Alternance fond de ligne
            if i % 2 == 0 then
                d2d.fill_rect(panel_x, ry, panel_w, row_h, 0x11FFFFFF)
            end

            -- Date
            local date_str = tostring(s.date or "?")
            d2d.text(_font_small, date_str, date_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, date_str, date_x, tty, COL_TEXT_DIM)

            -- Barre fond
            d2d.fill_rect(bar_x, by, bar_max_w, bar_h, COL_BAR_BG)

            -- Barre remplie
            local pct_safe = tonumber(s.pct) or 0
            local fill_w = bar_max_w * math.min(pct_safe, 100) / 100
            local col = bar_color(pct_safe)
            d2d.fill_rect(bar_x, by, fill_w, bar_h, col)
            d2d.outline_rect(bar_x, by, bar_max_w, bar_h, 1, 0x44FFFFFF)

            -- Pourcentage
            local pct_str = string.format("%d%%", pct_safe)
            d2d.text(_font_small, pct_str, pct_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, pct_str, pct_x, tty, col)

            -- Score / Total
            local sc_str = string.format("%d/%d", tonumber(s.score) or 0, tonumber(s.total) or 0)
            d2d.text(_font_small, sc_str, score_x + 1, tty + 1, COL_SHADOW)
            d2d.text(_font_small, sc_str, score_x, tty, COL_TEXT)

            sum_pct = sum_pct + pct_safe
        end)
        if not ok then
            _debug_msg = "DRAW ERROR row " .. i .. ": " .. tostring(err)
        end
    end

    -- Footer
    local avg = sum_pct / n
    local fy = panel_y + header_h + n * row_h + (footer_h - fh) * 0.5

    -- Trend (derniere vs premiere)
    if n >= 2 then
        local trend = _sessions[n].pct - _sessions[1].pct
        local trend_str, trend_col
        if trend >= 0 then
            trend_str = string.format("+%d%%", trend)
            trend_col = COL_BAR_GRN
        else
            trend_str = string.format("%d%%", trend)
            trend_col = COL_BAR_RED
        end
        d2d.text(_font, trend_str, panel_x + pad + 1, fy + 1, COL_SHADOW)
        d2d.text(_font, trend_str, panel_x + pad, fy, trend_col)
    end

    -- Moyenne
    local avg_str = string.format("AVG: %d%%", avg)
    local avg_w = #avg_str * fh * 0.6
    local avg_x = panel_x + panel_w - pad - avg_w
    d2d.text(_font, avg_str, avg_x + 1, fy + 1, COL_SHADOW)
    d2d.text(_font, avg_str, avg_x, fy, bar_color(avg))
end

-- Register D2D (guard si d2d pas disponible)
if d2d and d2d.register then
    d2d.register(d2d_init, d2d_draw)
end

-- Click detection pour le bouton close (via re.on_frame, pas re.on_draw_ui)
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

-- Debug info dans le menu REFramework
re.on_draw_ui(function()
    if imgui.tree_node("Session Recap Debug") then
        imgui.text("Visible: " .. tostring(_visible))
        imgui.text("Sessions: " .. #_sessions)
        imgui.text("Debug: " .. _debug_msg)
        -- Detail de chaque session parsee
        for i, s in ipairs(_sessions) do
            imgui.text("  [" .. i .. "] " .. tostring(s.date) .. " | " .. tostring(s.pct) .. "% | " .. tostring(s.score) .. "/" .. tostring(s.total))
        end
        if _visible and imgui.button("Close Recap") then
            M.hide()
        end
        if imgui.button("Test Show (HitConfirm)") then
            M.show("HIT CONFIRM", "HitConfirm_SessionStats.txt", "hitconfirm")
        end
        if imgui.button("Copy Debug to File") then
            local f = io.open("SessionRecap_Debug.txt", "w")
            if f then
                f:write("Visible: " .. tostring(_visible) .. "\n")
                f:write("Sessions: " .. #_sessions .. "\n")
                f:write("Debug: " .. _debug_msg .. "\n")
                for i, s in ipairs(_sessions) do
                    f:write("  [" .. i .. "] " .. tostring(s.date) .. " | " .. tostring(s.pct) .. "% | " .. tostring(s.score) .. "/" .. tostring(s.total) .. "\n")
                end
                f:close()
                _debug_msg = _debug_msg .. " | Copied to SessionRecap_Debug.txt"
            end
        end
        imgui.tree_pop()
    end
end)

return M
