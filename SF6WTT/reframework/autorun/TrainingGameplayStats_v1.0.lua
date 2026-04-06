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
    pp_postguard_mode = false, -- true = PostGuard detection (trade_dm only), false = custom (trade_dm + dmg=34 + hs!=0)
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
-- HC ENGINE: CONFIG + HELPERS (same as HitConfirm training)
-- =========================================================
local hc_config_file = "TrainingHitConfirm_Config.json"

local function parse_list(str)
    local t = {}
    if not str then return t end
    for s in string.gmatch(str, "([^,]+)") do local n = tonumber(s); if n then table.insert(t, n) end end
    return t
end

local function is_in(tbl, val)
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

-- Load HC config from shared config file, with defaults
local hc_cfg = {
    str_trigger_list = "13",
    str_success_list = "13",
    str_break_list = "7,2,1",
    str_dmg_hit_list = "3",
    str_dmg_block_list = "30",
    str_light_btn_list = "16,128",
    dont_count_blocked = true,
}
pcall(function()
    local f = io.open("reframework/data/" .. hc_config_file, "r")
    if not f then return end
    local raw = f:read("*a"); f:close()
    local data = json.load_string(raw)
    if data and data.user then
        local u = data.user
        if u.str_trigger_list then hc_cfg.str_trigger_list = u.str_trigger_list end
        if u.str_success_list then hc_cfg.str_success_list = u.str_success_list end
        if u.str_break_list then hc_cfg.str_break_list = u.str_break_list end
        if u.str_dmg_hit_list then hc_cfg.str_dmg_hit_list = u.str_dmg_hit_list end
        if u.str_dmg_block_list then hc_cfg.str_dmg_block_list = u.str_dmg_block_list end
        if u.str_light_btn_list then hc_cfg.str_light_btn_list = u.str_light_btn_list end
        if u.dont_count_blocked ~= nil then hc_cfg.dont_count_blocked = u.dont_count_blocked end
    end
end)

-- Work tables (parsed from config)
local hc_work = {
    trigger    = parse_list(hc_cfg.str_trigger_list),
    success    = parse_list(hc_cfg.str_success_list),
    break_list = parse_list(hc_cfg.str_break_list),
    dmg_hit    = parse_list(hc_cfg.str_dmg_hit_list),
    dmg_block  = parse_list(hc_cfg.str_dmg_block_list),
    light_btns = parse_list(hc_cfg.str_light_btn_list),
}

local MASK_LIGHT  = 144  -- LP(16) + LK(128)
local MASK_MEDIUM = 288
local MASK_HEAVY  = 576

-- HC detection state per player
local hc_state = {
    [0] = {
        monitor = { active = false, type = nil, has_reset_hs = false, target_combo = 0, is_medium = false },
        lockout = false,
        last_light_time = 0, last_medium_time = 0, last_heavy_time = 0,
    },
    [1] = {
        monitor = { active = false, type = nil, has_reset_hs = false, target_combo = 0, is_medium = false },
        lockout = false,
        last_light_time = 0, last_medium_time = 0, last_heavy_time = 0,
    },
}

-- =========================================================
-- STATE
-- =========================================================
local STATS = { "pp", "wp", "hc", "aa" }
local LABELS = { pp = "PP", wp = "WP", hc = "HC", aa = "AA" }
local STAT_COLORS = { pp = COL.pp, wp = COL.wp, hc = COL.hc, aa = COL.aa }
local FULL_LABELS = { pp = "PERFECT PARRY", wp = "WHIFF PUNISH", hc = "HIT CONFIRM", aa = "ANTI AIR" }

local counters = {
    [0] = { pp = 0, wp = 0, wp_ok = 0, wp_opp = 0, hc = 0, hc_ok = 0, hc_opp = 0, aa = 0, aa_ok = 0, aa_opp = 0 },
    [1] = { pp = 0, wp = 0, wp_ok = 0, wp_opp = 0, hc = 0, hc_ok = 0, hc_opp = 0, aa = 0, aa_ok = 0, aa_opp = 0 },
}

-- Per-player tracking
local track = {
    [0] = { act_st = 0, prev_act_st = 0, pose_st = 0, frame_st = 0, prev_frame_st = 0, was_airborne = false },
    [1] = { act_st = 0, prev_act_st = 0, pose_st = 0, frame_st = 0, prev_frame_st = 0, was_airborne = false },
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
    -- Read player data EVERY frame (combo, dmg, hs, trade_dm)
    -- Same as HitConfirm which reads these at the top of update_detection()
    matrix.prev_p1_combo = matrix.p1_combo or 0
    matrix.prev_p2_combo = matrix.p2_combo or 0
    matrix.p1_dmg = 0; matrix.p1_hs = 0; matrix.p1_combo = 0
    matrix.p2_dmg = 0; matrix.p2_hs = 0; matrix.p2_combo = 0
    matrix.p1_trade_dm = false; matrix.p2_trade_dm = false
    matrix.p1_pose_st = 0; matrix.p2_pose_st = 0
    matrix.p1_suki = false; matrix.p2_suki = false
    matrix.p1_parry_combo = 0; matrix.p2_parry_combo = 0
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
            local ps = p1_obj:get_field("pose_st"); if ps then matrix.p1_pose_st = tonumber(tostring(ps)) or 0 end
            local sk = p1_obj:get_field("land_suki_flag"); if sk then matrix.p1_suki = (tostring(sk) == "true") end
            local pc = p1_obj:get_field("parry_combo_cnt"); if pc then matrix.p1_parry_combo = tonumber(tostring(pc)) or 0 end
        end
        if p2_obj then
            local dt = p2_obj:get_field("damage_type"); if dt then matrix.p2_dmg = tonumber(tostring(dt)) or 0 end
            local hs = p2_obj:get_field("hit_stop"); if hs then matrix.p2_hs = tonumber(tostring(hs)) or 0 end
            local cc = p2_obj:get_field("combo_cnt"); if cc then matrix.p2_combo = tonumber(tostring(cc)) or 0 end
            local td = p2_obj:get_field("trade_dm_flag"); if td then matrix.p2_trade_dm = (tostring(td) == "true") end
            local ps = p2_obj:get_field("pose_st"); if ps then matrix.p2_pose_st = tonumber(tostring(ps)) or 0 end
            local sk = p2_obj:get_field("land_suki_flag"); if sk then matrix.p2_suki = (tostring(sk) == "true") end
            local pc = p2_obj:get_field("parry_combo_cnt"); if pc then matrix.p2_parry_combo = tonumber(tostring(pc)) or 0 end
        end
    end)

    -- Acquire matrix lists once
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
-- INPUT READING (for button detection)
-- =========================================================
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
    -- PERFECT PARRY
    -- PostGuard mode: trade_dm_flag only (unlock when trade_dm goes false)
    -- Custom mode: trade_dm + dmg=34 + hs!=0 (unlock when hs returns to 0)
    -- =====================
    if has_matrix then
        for pp_p = 0, 1 do
            local dm  = (pp_p == 0) and matrix.p1_trade_dm or matrix.p2_trade_dm
            local dmg = (pp_p == 0) and (matrix.p1_dmg or 0) or (matrix.p2_dmg or 0)
            local hs  = (pp_p == 0) and (matrix.p1_hs or 0) or (matrix.p2_hs or 0)
            local pcc = (pp_p == 0) and (matrix.p1_parry_combo or 0) or (matrix.p2_parry_combo or 0)
            -- parry_combo_cnt > 0 = normal parry (held parry), must be 0 for perfect parry
            local not_normal_parry = (pcc == 0)

            if cfg.pp_postguard_mode then
                -- PostGuard: trade_dm_flag + not normal parry, unlock when dm goes false
                if not dm then track[pp_p]._pp_locked = false end
                if not track[pp_p]._pp_locked and dm and not_normal_parry then
                    counters[pp_p].pp = counters[pp_p].pp + 1
                    track[pp_p]._pp_locked = true
                end
            else
                -- Custom: trade_dm + dmg=34 + hs!=0 + not normal parry, unlock when hs=0
                if hs == 0 then track[pp_p]._pp_locked = false end
                if not track[pp_p]._pp_locked and dm and not_normal_parry and dmg == 34 and hs ~= 0 then
                    counters[pp_p].pp = counters[pp_p].pp + 1
                    track[pp_p]._pp_locked = true
                end
            end
        end
    end

    for p = 0, 1 do
        local opp = 1 - p
        local t_p = track[p]
        local t_o = track[opp]

        -- =====================
        -- WHIFF PUNISH (only tracks opponent moves that WHIFF, not moves that connect)
        -- Score: +1 if P punishes whiffed move, -1 if missed opportunity
        -- Cancel tracking if opponent's attack actually hits player (not a whiff)
        -- =====================
        local opp_state = (opp == 0) and track[0].frame_st or track[1].frame_st
        local opp_pose  = (opp == 0) and (matrix.p1_pose_st or 0) or (matrix.p2_pose_st or 0)
        local my_state  = (p == 0) and track[0].frame_st or track[1].frame_st

        -- Check if opponent is in player's orange zone (from DistanceViewer)
        local my_zone = ""
        pcall(function()
            local sc = _G.SF6_SharedCombat
            if sc then my_zone = (p == 0) and (sc.p1_zone_name or "") or (sc.p2_zone_name or "") end
        end)
        local in_punish_range = my_zone:find("Orange Zone") or my_zone:find("Red Zone")

        -- Opponent is grounded and attacking — only track if in punish range
        if opp_pose < 2 and not t_p._wp_tracking and not t_p._wp_cooldown and in_punish_range then
            if opp_state == 7 or opp_state == 13 or opp_state == 14 or opp_state == STATE_RECOVER then
                t_p._wp_tracking = true
                t_p._wp_counted = false
                -- Check if opponent used a light button
                t_p._wp_is_light = false
                pcall(function()
                    local opp_input = read_game_input(opp)
                    if (opp_input & MASK_LIGHT) ~= 0 then t_p._wp_is_light = true end
                end)
            end
        end

        -- Cooldown resets when opponent returns to neutral
        if t_p._wp_cooldown and (opp_state == STATE_NEUTRAL or opp_state == 0) then
            t_p._wp_cooldown = false
        end

        if t_p._wp_tracking then
            -- If PLAYER got hit or blocked, opponent's move connected = NOT a whiff, cancel
            if my_state == STATE_HURT or my_state == 10 then
                t_p._wp_tracking = false
                t_p._wp_counted = false
                t_p._wp_cooldown = true
            elseif opp_state == STATE_HURT then
                -- Player punished the opponent = SUCCESS (+1 always, even lights)
                if not t_p._wp_counted then
                    counters[p].wp = counters[p].wp + 1
                    counters[p].wp_ok = counters[p].wp_ok + 1
                    counters[p].wp_opp = counters[p].wp_opp + 1
                    t_p._wp_counted = true
                end
                t_p._wp_tracking = false
                t_p._wp_cooldown = true
            elseif opp_state == STATE_NEUTRAL or opp_state == 0 then
                -- Opponent returned to neutral unpunished
                if not t_p._wp_counted then
                    if t_p._wp_is_light then
                        -- Light whiff missed: no penalty, just count opportunity
                        counters[p].wp_opp = counters[p].wp_opp + 1
                    else
                        -- Non-light whiff missed: -1
                        counters[p].wp = counters[p].wp - 1
                        counters[p].wp_opp = counters[p].wp_opp + 1
                    end
                end
                t_p._wp_tracking = false
                t_p._wp_counted = false
            end
        end

        -- =====================
        -- ANTI AIR (PostGuard logic)
        -- Only tracks when OPPONENT is airborne AND attacking (suki_flag)
        -- +1 if opponent hit while airborne attacking, -1 if lands safely
        -- =====================
        local opp_suki = (opp == 0) and matrix.p1_suki or matrix.p2_suki
        local my_pose = (p == 0) and (matrix.p1_pose_st or 0) or (matrix.p2_pose_st or 0)

        if opp_pose >= 2 then
            t_p._aa_opp_in_air = true
            if opp_suki then t_p._aa_opp_attacking = true end
        end

        if t_p._aa_opp_in_air then
            -- Only count if opponent was ATTACKING in air (suki_flag) and player is GROUNDED
            if t_p._aa_opp_attacking and opp_state == STATE_HURT and my_pose < 2 then
                if not t_p._aa_counted then
                    counters[p].aa = counters[p].aa + 1
                    counters[p].aa_ok = counters[p].aa_ok + 1
                    counters[p].aa_opp = counters[p].aa_opp + 1
                    t_p._aa_counted = true
                end
            end
            -- Opponent landed (back on ground + neutral)
            if opp_pose < 2 and (opp_state == STATE_NEUTRAL or opp_state == 0) then
                if t_p._aa_opp_attacking and not t_p._aa_counted then
                    counters[p].aa = counters[p].aa - 1
                    counters[p].aa_opp = counters[p].aa_opp + 1
                end
                t_p._aa_opp_in_air = false
                t_p._aa_opp_attacking = false
                t_p._aa_counted = false
            end
        end

        -- =====================
        -- HIT CONFIRM (full HitConfirm engine logic)
        -- =====================
        local hs = hc_state[p]
        local mon = hs.monitor

        -- Get matrix data for attacker (p) and opponent (opp)
        local p_ft  = (p == 0) and matrix.p1_ft  or matrix.p2_ft
        local p_gau = (p == 0) and matrix.p1_gau or matrix.p2_gau
        local opp_ft  = (p == 0) and matrix.p2_ft  or matrix.p1_ft
        local opp_gau = (p == 0) and matrix.p2_gau or matrix.p1_gau
        local live_dmg   = (opp == 0) and matrix.p1_dmg   or matrix.p2_dmg
        local live_hs    = (opp == 0) and matrix.p1_hs    or matrix.p2_hs
        local live_combo = (p == 0)   and matrix.p1_combo or matrix.p2_combo

        -- Track button presses for this player
        pcall(function()
            local input = read_game_input(p)
            if (input & MASK_LIGHT) ~= 0 then hs.last_light_time = os.clock() end
            if (input & MASK_MEDIUM) ~= 0 then hs.last_medium_time = os.clock() end
            if (input & MASK_HEAVY) ~= 0 then hs.last_heavy_time = os.clock() end
        end)

        local is_light_buffered  = (os.clock() - hs.last_light_time) < 0.25
        local is_medium_buffered = (os.clock() - hs.last_medium_time) < 0.5
        local required_combo_start = is_light_buffered and 2 or 1

        -- 1) LOCKOUT RESET
        if hs.lockout then
            if not is_in(hc_work.trigger, p_ft) and not is_in(hc_work.break_list, p_ft) then
                hs.lockout = false
            end
        end

        -- 2) TRIGGER CONDITIONS
        local is_ft_trig   = is_in(hc_work.trigger, p_ft)
        local is_dmg_hit   = is_in(hc_work.dmg_hit, live_dmg)
        local is_dmg_blk   = is_in(hc_work.dmg_block, live_dmg)
        local trig_hit = (is_ft_trig and live_combo == required_combo_start and is_dmg_hit)
        local trig_blk = (is_ft_trig and opp_gau > 0 and is_dmg_blk)

        -- 3) HIT TRIGGER
        if trig_hit and not hs.lockout then
            if not mon.active or mon.type ~= "HIT" then
                mon.active = true; mon.type = "HIT"; mon.has_reset_hs = false
                mon.target_combo = required_combo_start + 1
            end
        -- 4) BLOCK TRIGGER
        elseif trig_blk and not hs.lockout then
            if not mon.active or mon.type ~= "BLOCK" then
                mon.active = true; mon.type = "BLOCK"; mon.has_reset_hs = false
                mon.is_medium = is_medium_buffered
            end
        end

        -- 5) STANDARD MONITOR (exact same logic as HitConfirm)
        if mon.active and not hs.lockout then
            if live_hs == 0 then mon.has_reset_hs = true end
            if mon.has_reset_hs then
                if mon.type == "HIT" then
                    if live_combo >= mon.target_combo then
                        -- SUCCESS: confirmed hit into combo
                        counters[p].hc = counters[p].hc + 1
                        counters[p].hc_ok = counters[p].hc_ok + 1
                        counters[p].hc_opp = counters[p].hc_opp + 1
                        mon.active = false; hs.lockout = true
                    elseif live_combo == 0 then
                        -- FAIL: dropped combo
                        counters[p].hc = counters[p].hc - 1
                        counters[p].hc_opp = counters[p].hc_opp + 1
                        mon.active = false; hs.lockout = true
                    end
                elseif mon.type == "BLOCK" then
                    if is_in(hc_work.break_list, p_ft) then
                        -- FAIL: unsafe on block
                        counters[p].hc = counters[p].hc - 1
                        counters[p].hc_opp = counters[p].hc_opp + 1
                        mon.active = false; hs.lockout = true
                    elseif is_in(hc_work.success, p_ft) and not is_in(hc_work.trigger, p_ft) and live_hs > 0 then
                        -- FAIL: autopilot (kept pressing buttons)
                        counters[p].hc = counters[p].hc - 1
                        counters[p].hc_opp = counters[p].hc_opp + 1
                        mon.active = false; hs.lockout = true
                    elseif not is_in(hc_work.dmg_block, live_dmg) then
                        -- Block resolved: stopped pressing
                        counters[p].hc_opp = counters[p].hc_opp + 1
                        if not hc_cfg.dont_count_blocked then
                            counters[p].hc = counters[p].hc + 1
                            counters[p].hc_ok = counters[p].hc_ok + 1
                        end
                        mon.active = false; hs.lockout = true
                    end
                end
            end
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

        local pp_chg, pp_val = imgui.checkbox("PP: PostGuard mode (trade_dm only)", cfg.pp_postguard_mode)
        if pp_chg then cfg.pp_postguard_mode = pp_val end

        if imgui.button("RESET ALL") then
            for p = 0, 1 do
                for _, k in ipairs(STATS) do counters[p][k] = 0 end
                counters[p].wp_ok = 0; counters[p].wp_opp = 0
                counters[p].hc_ok = 0; counters[p].hc_opp = 0
                counters[p].aa_ok = 0; counters[p].aa_opp = 0
                hc_state[p].monitor.active = false; hc_state[p].monitor.type = nil
                hc_state[p].monitor.has_reset_hs = false; hc_state[p].monitor.target_combo = 0
                hc_state[p].lockout = false
                track[p]._wp_tracking = false; track[p]._aa_opp_in_air = false
                track[p]._aa_opp_attacking = false; track[p]._aa_counted = false
            end
        end

        -- Show current counts
        for p = 0, 1 do
            imgui.text("--- P" .. (p+1) .. " ---")
            for _, k in ipairs(STATS) do
                imgui.text("  " .. FULL_LABELS[k] .. ": " .. counters[p][k])
            end
        end

        -- Zone info from DistanceViewer
        imgui.spacing()
        imgui.text("--- ZONES (from DistanceViewer) ---")
        pcall(function()
            local sc = _G.SF6_SharedCombat
            if sc then
                imgui.text("P1 zone: " .. (sc.p1_zone_name or "N/A"))
                imgui.text("P2 zone: " .. (sc.p2_zone_name or "N/A"))
            else
                imgui.text("DistanceViewer not loaded")
            end
        end)

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

        -- PP detection formula debug
        imgui.spacing()
        local mode_label = cfg.pp_postguard_mode and "PostGuard" or "Custom"
        imgui.text("--- PP DETECTION [" .. mode_label .. "] ---")
        for p = 0, 1 do
            local dm   = (p == 0) and matrix.p1_trade_dm or matrix.p2_trade_dm
            local dmg  = (p == 0) and (matrix.p1_dmg or 0) or (matrix.p2_dmg or 0)
            local hs   = (p == 0) and (matrix.p1_hs or 0) or (matrix.p2_hs or 0)
            local pcc  = (p == 0) and (matrix.p1_parry_combo or 0) or (matrix.p2_parry_combo or 0)
            local lock = track[p]._pp_locked and "LOCKED" or "READY"
            local not_normal = (pcc == 0)
            local result
            if cfg.pp_postguard_mode then
                result = (dm and not_normal) and ">>> PP!" or "no"
                imgui.text(string.format("P%d: trade_dm=%s  parry_combo=%d==0?  [%s] => %s",
                    p + 1, tostring(dm), pcc, lock, result))
            else
                result = (dm and not_normal and dmg == 34 and hs ~= 0) and ">>> PP!" or "no"
                imgui.text(string.format("P%d: trade_dm=%s  parry_combo=%d==0?  dmg=%d==34?  hs=%d!=0?  [%s] => %s",
                    p + 1, tostring(dm), pcc, dmg, hs, lock, result))
            end
        end

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
    local ph = header_h + sep_h + (#STATS * row_h) + pad

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
            -- WP/HC/AA show score + ratio, PP just count
            local val_str
            local ok_key = k .. "_ok"
            local opp_key = k .. "_opp"
            if counters[p][ok_key] and counters[p][opp_key] then
                local score = val
                local score_prefix = score >= 0 and "+" or ""
                val_str = score_prefix .. tostring(score) .. " (" .. tostring(counters[p][ok_key]) .. "/" .. tostring(counters[p][opp_key]) .. ")"
            else
                val_str = tostring(val)
            end
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
    end
end

if d2d and d2d.register then
    d2d.register(d2d_init, d2d_draw)
end
