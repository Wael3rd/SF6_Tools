-- =========================================================
-- TrainingGameplayStats_v1.0.lua
-- Passive gameplay counter: PP, WP, HC, AA for P1 & P2
-- Independent script with D2D overlay
-- =========================================================

local re = re
local sdk = sdk
local imgui = imgui

-- =========================================================
-- CONFIGURATION
-- =========================================================
local cfg = {
    visible = true,
    panel_alpha = 0xCC,     -- transparence du fond (0-255)
    panel_width_pct = 0.13, -- largeur panneau (% ecran)
    panel_margin_pct = 0.02, -- marge depuis le bord
    panel_y_pct = 0.28,     -- position verticale (sous les barres de vie)
}

-- =========================================================
-- COLORS (ABGR)
-- =========================================================
local COL = {
    bg        = 0xCC141414,
    border    = 0xFF555555,
    header_bg = 0x33FFFFFF,
    header_p1 = 0xFFFFAA44, -- bleu/cyan
    header_p2 = 0xFF4444FF, -- rouge
    shadow    = 0xFF000000,
    text      = 0xFFDADADA,
    text_dim  = 0xFF888888,
    separator = 0xFF444444,
    pp        = 0xFFFFFF00, -- cyan
    wp        = 0xFF00A5FF, -- orange
    hc        = 0xFF00DD00, -- vert
    aa        = 0xFF5555FF, -- rouge
    total     = 0xFFFFFFFF, -- blanc
}

-- =========================================================
-- STATE
-- =========================================================
local STATS = { "pp", "wp", "hc", "aa" }
local LABELS = { pp = "PP", wp = "WP", hc = "HC", aa = "AA" }
local STAT_COLORS = { pp = COL.pp, wp = COL.wp, hc = COL.hc, aa = COL.aa }
local FULL_LABELS = { pp = "PERFECT PARRY", wp = "WHIFF PUNISH", hc = "HIT CONFIRM", aa = "ANTI AIR" }

local counters = {
    [0] = { pp = 0, wp = 0, hc = 0, aa = 0 },
    [1] = { pp = 0, wp = 0, hc = 0, aa = 0 },
}

-- Per-player tracking
local track = {
    [0] = { act_st = 0, prev_act_st = 0, pose_st = 0, frame_st = 0, prev_frame_st = 0, hc_pending = false, was_airborne = false, in_combo = false },
    [1] = { act_st = 0, prev_act_st = 0, pose_st = 0, frame_st = 0, prev_frame_st = 0, hc_pending = false, was_airborne = false, in_combo = false },
}

-- Frame state from hooks
local p1_max_frame = 0
local p2_max_frame = 0

-- Fonts
local _font = nil
local _font_small = nil
local _last_fh = 0
local _last_fhs = 0

-- =========================================================
-- GAME STATE READING
-- =========================================================
local function get_player(index)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return nil end
    local player_mgr = gBattle:get_field("Player"):get_data(nil)
    if not player_mgr then return nil end
    return player_mgr:call("getPlayer", index)
end

local function get_act_st(player_index)
    local player = get_player(player_index)
    if not player then return 0 end
    local t = player:get_type_definition()
    if not t then return 0 end
    local field = t:get_field("act_st")
    if not field then return 0 end
    local val = field:get_data(player)
    return tonumber(tostring(val)) or 0
end

local function get_pose_st(player_index)
    local player = get_player(player_index)
    if not player then return 0 end
    local pose = player:get_field("pose_st")
    if pose then return tonumber(tostring(pose)) or 0 end
    return 0
end

-- =========================================================
-- FRAME DATA READING (same approach as HitConfirm matrix)
-- =========================================================
local matrix = {
    p1_list = nil, p2_list = nil,  -- persistent references
    p1_ft = 0, p1_gau = 0, prev_p1_ft = 0, prev_p1_gau = 0,
    p2_ft = 0, p2_gau = 0, prev_p2_ft = 0, prev_p2_gau = 0,
    last_head = -1,
    is_new = false,
    debug_status = "not initialized"
}

local function read_frame_data()
    -- Acquire lists once (same as HitConfirm detection.p1_list / detection.p2_list)
    if not matrix.p1_list or not matrix.p2_list then
        local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
        if not mgr then matrix.debug_status = "no TrainingManager"; return false end
        local dict = mgr:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")
        if not entries then matrix.debug_status = "no entries"; return false end

        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry:get_field("key") == 5 then
                local widget = entry:get_field("value"):call("get_Item", 0)
                local ss = widget:call("get_SSData")
                local m_datas = ss:get_field("MeterDatas")
                if m_datas and m_datas:call("get_Count") >= 2 then
                    local item_p1 = m_datas:call("get_Item", 0)
                    local item_p2 = m_datas:call("get_Item", 1)
                    if item_p1 then matrix.p1_list = item_p1:get_field("FrameNumDatas") end
                    if item_p2 then matrix.p2_list = item_p2:get_field("FrameNumDatas") end
                end
                break
            end
        end
        if not matrix.p1_list or not matrix.p2_list then
            matrix.debug_status = "no FrameNumDatas"
            return false
        end
        matrix.debug_status = "lists acquired"
    end

    -- Read from persistent lists (exact same logic as HitConfirm)
    local buffer_count = matrix.p1_list:call("get_Count")
    if buffer_count <= 0 then matrix.debug_status = "buffer empty"; return false end

    local function check_active(idx)
        if idx < 0 or idx >= buffer_count then return false end
        local item1 = matrix.p1_list:call("get_Item", idx)
        local item2 = matrix.p2_list:call("get_Item", idx)
        if not item1 or not item2 then return false end
        local ft1 = tonumber(tostring(item1:get_field("FrameType"))) or 0
        local ft2 = tonumber(tostring(item2:get_field("FrameType"))) or 0
        return (ft1 ~= 0 or ft2 ~= 0)
    end

    local active_head = -1
    local next_idx = (matrix.last_head + 1) % buffer_count
    matrix.is_new = false

    if check_active(next_idx) then
        active_head = next_idx
        matrix.is_new = true
    elseif check_active(matrix.last_head) then
        active_head = matrix.last_head
    else
        -- Fallback: scan backwards for last active slot
        for i = buffer_count - 1, 0, -1 do
            if check_active(i) then active_head = i; break end
        end
    end

    if active_head == -1 then matrix.debug_status = "no active head"; return false end
    matrix.last_head = active_head

    if not matrix.is_new then return false end -- no new frame data

    local it1 = matrix.p1_list:call("get_Item", active_head)
    local it2 = matrix.p2_list:call("get_Item", active_head)
    if not it1 or not it2 then return false end

    -- Save previous
    matrix.prev_p1_ft  = matrix.p1_ft
    matrix.prev_p1_gau = matrix.p1_gau
    matrix.prev_p1_dmg = matrix.p1_dmg
    matrix.prev_p1_hs  = matrix.p1_hs
    matrix.prev_p2_ft  = matrix.p2_ft
    matrix.prev_p2_gau = matrix.p2_gau
    matrix.prev_p2_dmg = matrix.p2_dmg
    matrix.prev_p2_hs  = matrix.p2_hs

    -- Read ALL fields from both items for debug mapping
    matrix.p1_ft  = tonumber(tostring(it1:get_field("FrameType")))  or 0
    matrix.p1_type = tonumber(tostring(it1:get_field("Type")))  or 0
    matrix.p1_frame = tonumber(tostring(it1:get_field("Frame")))  or 0
    matrix.p1_sf  = tonumber(tostring(it1:get_field("StartFrame")))  or 0
    matrix.p1_ef  = tonumber(tostring(it1:get_field("EndFrame")))  or 0
    matrix.p1_gau = tonumber(tostring(it1:get_field("MainGauge"))) or 0

    matrix.p2_ft  = tonumber(tostring(it2:get_field("FrameType")))  or 0
    matrix.p2_type = tonumber(tostring(it2:get_field("Type")))  or 0
    matrix.p2_frame = tonumber(tostring(it2:get_field("Frame")))  or 0
    matrix.p2_sf  = tonumber(tostring(it2:get_field("StartFrame")))  or 0
    matrix.p2_ef  = tonumber(tostring(it2:get_field("EndFrame")))  or 0
    matrix.p2_gau = tonumber(tostring(it2:get_field("MainGauge"))) or 0

    -- Read DMG, HS, COMBO, TRADE_DM from player objects
    matrix.prev_p1_combo = matrix.p1_combo or 0
    matrix.prev_p2_combo = matrix.p2_combo or 0
    matrix.p1_dmg = 0; matrix.p1_hs = 0; matrix.p1_combo = 0
    matrix.p2_dmg = 0; matrix.p2_hs = 0; matrix.p2_combo = 0
    matrix.p1_trade_dm = false; matrix.p2_trade_dm = false
    pcall(function()
        local gBattle = sdk.find_type_definition("gBattle")
        if not gBattle then return end
        local pmgr = gBattle:get_field("Player"):get_data(nil)
        if not pmgr then return end
        local p1_obj = pmgr:call("getPlayer", 0)
        local p2_obj = pmgr:call("getPlayer", 1)
        if p1_obj then
            local dt = p1_obj:get_field("damage_type"); if dt then matrix.p1_dmg = tonumber(tostring(dt)) or 0 end
            local hs = p1_obj:get_field("hit_stop"); if hs then matrix.p1_hs = tonumber(tostring(hs)) or 0 end
            local cc = p1_obj:get_field("combo_cnt"); if cc then matrix.p1_combo = tonumber(tostring(cc)) or 0 end
            local td = p1_obj:get_field("trade_dm_flag"); if td then matrix.p1_trade_dm = (tostring(td) == "true") end
        end
        if p2_obj then
            local dt = p2_obj:get_field("damage_type"); if dt then matrix.p2_dmg = tonumber(tostring(dt)) or 0 end
            local hs = p2_obj:get_field("hit_stop"); if hs then matrix.p2_hs = tonumber(tostring(hs)) or 0 end
            local cc = p2_obj:get_field("combo_cnt"); if cc then matrix.p2_combo = tonumber(tostring(cc)) or 0 end
            local td = p2_obj:get_field("trade_dm_flag"); if td then matrix.p2_trade_dm = (tostring(td) == "true") end
        end
    end)

    matrix.debug_status = string.format("OK head=%d", active_head)
    return true
end

-- =========================================================
-- FRAME METER HOOKS (for WP, HC, AA detection)
-- =========================================================
local function setup_hooks()
    local t_fm = sdk.find_type_definition("app.training.UIWidget_TMFrameMeter")
    if not t_fm then return end

    local m_up = t_fm:get_method("SetUpFrame")
    if m_up then
        sdk.hook(m_up, function(args)
            local s = tonumber(tostring(sdk.to_int64(args[4])))
            if s and s > p1_max_frame then p1_max_frame = s end
        end, function(r) return r end)
    end

    local m_down = t_fm:get_method("SetDownFrame")
    if m_down then
        sdk.hook(m_down, function(args)
            local s = tonumber(tostring(sdk.to_int64(args[4])))
            if s and s > p2_max_frame then p2_max_frame = s end
        end, function(r) return r end)
    end
end

pcall(setup_hooks)

-- =========================================================
-- INPUT READING (for light button detection)
-- =========================================================
local MASK_LIGHT = 144  -- LP(16) + LK(128)

local function read_game_input(player_index)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return 0 end
    local pmgr = gBattle:get_field("Player"):get_data(nil)
    if not pmgr then return 0 end
    local p = pmgr:call("getPlayer", player_index)
    if not p then return 0 end
    local f_sw = p:get_type_definition():get_field("pl_sw_new")
    if not f_sw then return 0 end
    return f_sw:get_data(p) or 0
end

-- =========================================================
-- DETECTION LOGIC
-- =========================================================
-- Matrix FT values: 7=startup, 8=recovery, 9=hurt/block, 13/14=active
-- Matrix GAU values: 34=perfect parry
local STATE_NEUTRAL  = 0
local STATE_RECOVER  = 8
local STATE_HURT     = 9
local FT_ACTIVE_1    = 13
local FT_ACTIVE_2    = 14
local GAU_PARRY      = 34

local function is_active(ft)
    return ft == FT_ACTIVE_1 or ft == FT_ACTIVE_2
end

local function detect_events()
    -- Read hook-based states (for WP, HC, AA)
    for p = 0, 1 do
        track[p].prev_act_st = track[p].act_st
        track[p].prev_frame_st = track[p].frame_st
        track[p].act_st = get_act_st(p)
        track[p].pose_st = get_pose_st(p)
    end
    track[0].frame_st = p1_max_frame
    track[1].frame_st = p2_max_frame
    p1_max_frame = 0
    p2_max_frame = 0

    -- Read matrix data (for PP detection)
    local has_matrix = pcall(read_frame_data)

    -- =====================
    -- PERFECT PARRY (from player data)
    -- trade_dm_flag == true (distinguishes perfect parry from normal parry)
    -- + dmg=34 AND hitstop!=0 as confirmation
    -- Lock until hitstop returns to 0
    -- =====================
    if has_matrix then
        -- P1 perfect parry
        if (matrix.p1_hs or 0) == 0 then track[0]._pp_locked = false end
        if not track[0]._pp_locked and matrix.p1_trade_dm and (matrix.p1_dmg or 0) == 34 and (matrix.p1_hs or 0) ~= 0 then
            counters[0].pp = counters[0].pp + 1
            track[0]._pp_locked = true
        end
        -- P2 perfect parry
        if (matrix.p2_hs or 0) == 0 then track[1]._pp_locked = false end
        if not track[1]._pp_locked and matrix.p2_trade_dm and (matrix.p2_dmg or 0) == 34 and (matrix.p2_hs or 0) ~= 0 then
            counters[1].pp = counters[1].pp + 1
            track[1]._pp_locked = true
        end
    end

    for p = 0, 1 do
        local opp = 1 - p
        local t_p = track[p]
        local t_o = track[opp]

        -- =====================
        -- WHIFF PUNISH : opponent was in recovery (8) and gets hurt (9)
        -- =====================
        if t_o.prev_frame_st == STATE_RECOVER and t_o.frame_st == STATE_HURT then
            counters[p].wp = counters[p].wp + 1
        end

        -- =====================
        -- ANTI AIR : opponent was airborne (pose_st >= 2) and gets hurt
        -- =====================
        if t_o.pose_st >= 2 then
            t_o.was_airborne = true
        end
        if t_o.was_airborne and t_o.frame_st == STATE_HURT and t_o.prev_frame_st ~= STATE_HURT then
            counters[p].aa = counters[p].aa + 1
            t_o.was_airborne = false
        end
        if t_o.frame_st == STATE_NEUTRAL then
            t_o.was_airborne = false
        end

        -- =====================
        -- HIT CONFIRM SCORE (same logic as HitConfirm training)
        -- +1 = confirmed hit into combo (success)
        -- -1 = dropped combo or didn't confirm (fail)
        -- Light threshold: combo 2→3+, Non-light: combo 1→2+
        -- =====================
        local my_combo = (p == 0) and matrix.p1_combo or matrix.p2_combo

        -- Track light button press for this player
        pcall(function()
            local input = read_game_input(p)
            if (input & MASK_LIGHT) ~= 0 then
                t_p._last_light_time = os.clock()
            end
        end)
        local is_light = (t_p._last_light_time and (os.clock() - t_p._last_light_time) < 0.25)

        -- Combo starts: lock and determine threshold
        if my_combo >= 1 and not t_p._hc_active then
            t_p._hc_active = true
            t_p._hc_is_light = is_light
            t_p._hc_scored = false
            t_p._hc_target = is_light and 3 or 2  -- light needs combo 3+, other needs 2+
        end

        -- Combo reaches target = SUCCESS (+1)
        if t_p._hc_active and not t_p._hc_scored and my_combo >= (t_p._hc_target or 2) then
            counters[p].hc = counters[p].hc + 1
            t_p._hc_scored = true
        end

        -- Combo drops to 0 = evaluate
        if my_combo == 0 and t_p._hc_active then
            if not t_p._hc_scored then
                -- Had a hit but didn't confirm = FAIL (-1)
                counters[p].hc = counters[p].hc - 1
            end
            t_p._hc_active = false
        end
    end
end

-- =========================================================
-- GAME LOOP
-- =========================================================
re.on_frame(function()
    if not cfg.visible then return end
    pcall(detect_events)
end)

-- =========================================================
-- IMGUI MENU
-- =========================================================
re.on_draw_ui(function()
    if imgui.tree_node("Gameplay Stats Counter") then
        local changed, val = imgui.checkbox("Show Overlay", cfg.visible)
        if changed then cfg.visible = val end

        if imgui.button("RESET ALL") then
            for p = 0, 1 do
                for _, k in ipairs(STATS) do counters[p][k] = 0 end
            end
        end

        -- Show current counts
        for p = 0, 1 do
            imgui.text("--- P" .. (p+1) .. " ---")
            for _, k in ipairs(STATS) do
                imgui.text("  " .. FULL_LABELS[k] .. ": " .. counters[p][k])
            end
        end

        -- Live matrix debug - ALL fields
        imgui.spacing()
        imgui.text("--- MATRIX LIVE ---")
        imgui.text("Status: " .. matrix.debug_status)
        imgui.text(string.format("Head IDX: %d  |  Lists: %s", matrix.last_head, (matrix.p1_list and matrix.p2_list) and "OK" or "nil"))
        imgui.spacing()
        imgui.text("P1 item fields:")
        imgui.text(string.format("  FrameType=%d  Type=%d  Frame=%d  SF=%d  EF=%d  MainGauge=%d",
            matrix.p1_ft, matrix.p1_type or 0, matrix.p1_frame or 0, matrix.p1_sf or 0, matrix.p1_ef or 0, matrix.p1_gau))
        imgui.text(string.format("  dmg=%d  hs=%d  combo=%d  trade_dm=%s", matrix.p1_dmg or 0, matrix.p1_hs or 0, matrix.p1_combo or 0, tostring(matrix.p1_trade_dm)))
        imgui.text("P2 item fields:")
        imgui.text(string.format("  FrameType=%d  Type=%d  Frame=%d  SF=%d  EF=%d  MainGauge=%d",
            matrix.p2_ft, matrix.p2_type or 0, matrix.p2_frame or 0, matrix.p2_sf or 0, matrix.p2_ef or 0, matrix.p2_gau))
        imgui.text(string.format("  dmg=%d  hs=%d  combo=%d  trade_dm=%s", matrix.p2_dmg or 0, matrix.p2_hs or 0, matrix.p2_combo or 0, tostring(matrix.p2_trade_dm)))

        imgui.tree_pop()
    end
end)

-- =========================================================
-- D2D DRAWING
-- =========================================================
local function d2d_init() end

local function d2d_draw()
    if not cfg.visible then return end

    local sw, sh = d2d.surface_size()

    -- Font sizing
    local fh = math.floor(sh * 0.016)
    local fhs = math.floor(sh * 0.013)
    if fh ~= _last_fh then
        _font = d2d.Font.new("Consolas", fh)
        _last_fh = fh
    end
    if fhs ~= _last_fhs then
        _font_small = d2d.Font.new("Consolas", fhs)
        _last_fhs = fhs
    end

    -- Layout
    local pw = sw * cfg.panel_width_pct
    local mx = sw * cfg.panel_margin_pct
    local py = sh * cfg.panel_y_pct
    local pad = sh * 0.008
    local row_h = fhs * 2.2
    local header_h = fh * 2.2
    local sep_h = 1
    local footer_h = fhs * 2.2
    local ph = header_h + sep_h + (#STATS * row_h) + sep_h + footer_h + pad

    for p = 0, 1 do
        -- Panel X position
        local px
        if p == 0 then
            px = mx  -- P1 left
        else
            px = sw - mx - pw  -- P2 right
        end

        -- Background
        d2d.fill_rect(px, py, pw, ph, COL.bg)
        d2d.outline_rect(px, py, pw, ph, 1, COL.border)

        -- Header
        d2d.fill_rect(px, py, pw, header_h, COL.header_bg)
        local header_col = p == 0 and COL.header_p1 or COL.header_p2
        local header_txt
        if p == 0 then
            header_txt = "  \xe2\x96\xb8 P1 STATS"
        else
            header_txt = "     P2 STATS \xe2\x97\x82"
        end

        local hx
        if p == 0 then
            hx = px + pad
        else
            -- Right-align header text for P2
            local approx_w = #"     P2 STATS .." * fh * 0.55
            hx = px + pw - pad - approx_w
        end
        local hy = py + (header_h - fh) * 0.5
        d2d.text(_font, header_txt, hx + 1, hy + 1, COL.shadow)
        d2d.text(_font, header_txt, hx, hy, header_col)

        -- Separator
        local sep_y = py + header_h
        d2d.fill_rect(px, sep_y, pw, sep_h, COL.separator)

        -- Stat rows
        local total = 0
        for i, k in ipairs(STATS) do
            local ry = sep_y + sep_h + (i - 1) * row_h
            local ty = ry + (row_h - fhs) * 0.5
            local val = counters[p][k]
            total = total + val

            local label = LABELS[k]
            local val_str = tostring(val)
            local col = STAT_COLORS[k]

            if p == 0 then
                -- P1: label left, number right
                d2d.text(_font_small, label, px + pad + 1, ty + 1, COL.shadow)
                d2d.text(_font_small, label, px + pad, ty, col)

                local vx = px + pw - pad - #val_str * fhs * 0.62
                d2d.text(_font_small, val_str, vx + 1, ty + 1, COL.shadow)
                d2d.text(_font_small, val_str, vx, ty, COL.text)
            else
                -- P2: number left, label right (mirrored)
                d2d.text(_font_small, val_str, px + pad + 1, ty + 1, COL.shadow)
                d2d.text(_font_small, val_str, px + pad, ty, COL.text)

                local lx = px + pw - pad - #label * fhs * 0.62
                d2d.text(_font_small, label, lx + 1, ty + 1, COL.shadow)
                d2d.text(_font_small, label, lx, ty, col)
            end
        end

        -- Separator before footer
        local sep2_y = sep_y + sep_h + #STATS * row_h
        d2d.fill_rect(px, sep2_y, pw, sep_h, COL.separator)

        -- Footer: TOTAL
        local fy = sep2_y + sep_h + (footer_h - fhs) * 0.5
        local total_str = tostring(total)

        if p == 0 then
            d2d.text(_font_small, "TOTAL", px + pad + 1, fy + 1, COL.shadow)
            d2d.text(_font_small, "TOTAL", px + pad, fy, COL.text_dim)
            local tx = px + pw - pad - #total_str * fhs * 0.62
            d2d.text(_font_small, total_str, tx + 1, fy + 1, COL.shadow)
            d2d.text(_font_small, total_str, tx, fy, COL.total)
        else
            d2d.text(_font_small, total_str, px + pad + 1, fy + 1, COL.shadow)
            d2d.text(_font_small, total_str, px + pad, fy, COL.total)
            local lx = px + pw - pad - #"TOTAL" * fhs * 0.62
            d2d.text(_font_small, "TOTAL", lx + 1, fy + 1, COL.shadow)
            d2d.text(_font_small, "TOTAL", lx, fy, COL.text_dim)
        end
    end
end

if d2d and d2d.register then
    d2d.register(d2d_init, d2d_draw)
end
