local json = json
local sdk = sdk
local imgui = imgui
local re = re
local draw = draw
local Vector3f = Vector3f
local Vector2f = Vector2f

-- Conversion numpad → flèches Unicode
local _numpad_arrows = { ["1"]="↙", ["2"]="↓", ["3"]="↘", ["4"]="←", ["6"]="→", ["7"]="↖", ["8"]="↑", ["9"]="↗" }
local function input_to_arrows(str)
    if not str then return str end
    return str:gsub("^(%d+)", function(digits)
        local out = ""
        for i = 1, #digits do
            local c = digits:sub(i, i)
            out = out .. (_numpad_arrows[c] or (c == "5" and "" or c))
        end
        return out
    end)
end

-- Couleur par force du coup
local COL_HEAVY = 0xFF5555FF   -- Rouge
local COL_MEDIUM = 0xFF00FFFF  -- Jaune
local COL_LIGHT = 0xFFFFBB55   -- Bleu clair
local function get_strength_color(input)
    if not input then return nil end
    local upper = input:upper()
    if upper:find("HP") or upper:find("HK") then return COL_HEAVY end
    if upper:find("MP") or upper:find("MK") then return COL_MEDIUM end
    if upper:find("LP") or upper:find("LK") then return COL_LIGHT end
    return nil
end

-- Dropdown de moves (imgui.combo natif)
local function colored_move_dropdown(label, selected_idx, moves, width)
    local move_names = { "None" }
    for _, mv in ipairs(moves) do
        move_names[#move_names + 1] = input_to_arrows(mv.input)
    end
    imgui.push_item_width(width)
    local changed, new_idx = imgui.combo(label, selected_idx, move_names)
    imgui.pop_item_width()
    return changed, new_idx
end

-- =========================================================
-- [ADVANCED MODE - Distance Logger integration]
-- =========================================================
local UNIFIED_FILE = "SF6Distance_Data_Attacks.json"
local advanced_data = {}

local fallback_spacing = { yellow = 2.50, red = 2.00, low = 1.50 }
local spacing_thresholds = {}
local jump_data_store = {}

local advanced_prefs = { [0] = {}, [1] = {} }

local function load_advanced_prefs()
    local f = json.load_file(UNIFIED_FILE)
    local pp = f and f.player_prefs
    if not pp then
        -- Migration: try old file
        pp = json.load_file("SF6DistanceViewer_AdvancedPrefs.json")
    end
    if pp then
        advanced_prefs[0] = pp["0"] or pp[0] or {}
        advanced_prefs[1] = pp["1"] or pp[1] or {}
    end
    if type(advanced_prefs[0]) ~= "table" then advanced_prefs[0] = {} end
    if type(advanced_prefs[1]) ~= "table" then advanced_prefs[1] = {} end
end
local function save_advanced_prefs()
    local current = json.load_file(UNIFIED_FILE) or {}
    current.player_prefs = advanced_prefs
    if not current.attacks then current.attacks = {} end
    if not current.jumps then current.jumps = {} end
    json.dump_file(UNIFIED_FILE, current)
    _G.DV_AdvancedPrefs = advanced_prefs
end
_G.DV_AdvancedPrefs = advanced_prefs
local function get_char_prefs(pi, char_name)
    if not advanced_prefs[pi][char_name] then 
        advanced_prefs[pi][char_name] = { visibility = {}, yellow_offset = 50, red = nil, low = nil } 
    end
    -- Ensure visibility table exists for legacy saves
    if not advanced_prefs[pi][char_name].visibility then
        advanced_prefs[pi][char_name].visibility = {}
    end
    return advanced_prefs[pi][char_name]
end
load_advanced_prefs()

local VMODE_NONE = 1
local VMODE_TOP_HALF = 2
local VMODE_BOTTOM_HALF = 3
local VMODE_FULL = 4

local config = {
    -- Box filters for distance calculation
    box_use_hurtbox = true,
    box_use_hurtbox_invuln = false,
    box_use_pushbox = true,
    box_use_hitbox = false,
    box_use_throwbox = false,
    box_use_clash = false,
    box_use_proximity = false,
    use_attack_lock = false,
    jump_arc_thickness = 50.0,
    -- TELEPORT VARIABLES
    teleport_target_dist = 300.0,
    tp_p1_border = false,
    tp_p2_border = true,
	
    -- Font Size Base (Master Quality)
    stats_font_size = 40, 
    number_font_size = 20,
    zone_opacity = 15,
	ui_scale = 1.25,
	icon_scale = 1.0,
    icon_offset_y = 0.0,

    -- Advanced Mode Data
    p1_advanced_mode = false,
    p2_advanced_mode = false,
    advanced_visibility = {},

    -- ================= P1 SETTINGS =================
    p1_show_all = true,
    p1_opp_zone_show_title = false, p1_opp_zone_show_name = true,
    p1_my_zone_show_title = false, p1_my_zone_show_name = true,
    -- P1 Visuals
    p1_show_horizontal_lines = true, p1_line_height_1 = 0.45, p1_line_height_2 = 0.90, p1_line_height_3 = 0.10, p1_line_height_4 = 0.45,
    p1_end_marker_size = 100.0, p1_end_marker_offset_y = 0.0,
    p1_show_origin_dot = true, p1_origin_dot_size = 8.0,
    pp1_show_markers = true, p1_show_vertical_cursor = true, p1_show_numbers = true,
    p1_number_off_y_1 = -25.0, p1_number_off_y_2 = -25.0, p1_number_off_y_3 = 25.0, p1_number_off_y_4 = -25.0,
    p1_vertical_mode = VMODE_NONE, p1_fill_bg = true,
    p1_show_jump_arc = false,
    p1_has_custom = false, p1_custom_base_mode = 1, p1_custom_fill_bg = false, p1_custom_show_markers = false, p1_custom_show_cursor = false, p1_custom_show_hz = false, p1_custom_show_numbers = false, p1_custom_show_text = false,

    -- P1 TEXT: CROSSUP
    p1_crossup_show = true,
    p1_crossup_color_text = false,
    p1_crossup_pos_mode = 1,
    p1_crossup_head_off_x = 0.0, p1_crossup_head_off_y = 0.0,
    p1_crossup_root_off_x = 0.0, p1_crossup_root_off_y = 0.0,
    p1_crossup_fixed_x = 0.0, p1_crossup_fixed_y = 0.0,
    
    -- P1 TEXT: OPPONENT ZONE
    p1_opp_zone_show = true,
    p1_opp_zone_color_text = true,
    p1_opp_zone_pos_mode = 4,
    p1_opp_zone_head_off_x = 0.0, p1_opp_zone_head_off_y = 0.0,
    p1_opp_zone_root_off_x = 150.0, p1_opp_zone_root_off_y = 200.0,
    p1_opp_zone_fixed_x = 0.0, p1_opp_zone_fixed_y = 0.0,
    p1_opp_zone_cursor_off_x = 15.0,
    -- =======================================================
    -- [TWEAKS MANUELS P1] (Valeurs de 0.0 à 1.0 = Hauteur écran)
    -- h_1 = Mode Distance Only (1)
    -- Le texte se dessine "vers le haut" depuis cette coordonnée.
    -- =======================================================
    p1_opp_zone_cursor_h_1 = 0.48, p1_opp_zone_cursor_h_2 = 0.85, p1_opp_zone_cursor_h_3 = 0.16, p1_opp_zone_cursor_h_4 = 0.45,
    p1_opp_zone_cursor_input_h_1 = 0.80, p1_opp_zone_cursor_input_h_2 = 0.90, p1_opp_zone_cursor_input_h_3 = 0.20, p1_opp_zone_cursor_input_h_4 = 0.49,
    
    -- P1 TEXT: MY ZONE
    p1_my_zone_show = false,
    p1_my_zone_color_text = true,
    p1_my_zone_pos_mode = 2,
    p1_my_zone_head_off_x = 0.0, p1_my_zone_head_off_y = 0.0,
    p1_my_zone_root_off_x = 160.0, p1_my_zone_root_off_y = 400.0,
    p1_my_zone_fixed_x = 0.0, p1_my_zone_fixed_y = 0.0,
    
    -- ================= P2 SETTINGS =================
	p2_show_all = true,
    p2_opp_zone_show_title = false, p2_opp_zone_show_name = true,
    p2_my_zone_show_title = true, p2_my_zone_show_name = true,
    -- P2 Visuals
    p2_show_horizontal_lines = true, p2_line_height_1 = 0.55, p2_line_height_2 = 0.90, p2_line_height_3 = 0.10, p2_line_height_4 = 0.55,
    p2_end_marker_size = 100.0, p2_end_marker_offset_y = 0.0,
    p2_show_origin_dot = true, p2_origin_dot_size = 8.0,
    p2_show_markers = true, p2_show_vertical_cursor = true, p2_show_numbers = true,
    p2_number_off_y_1 = 25.0, p2_number_off_y_2 = -25.0, p2_number_off_y_3 = 25.0, p2_number_off_y_4 = 25.0,
    p2_vertical_mode = VMODE_BOTTOM_HALF, p2_fill_bg = true,
    p2_show_jump_arc = false,
    p2_has_custom = false, p2_custom_base_mode = 1, p2_custom_fill_bg = false, p2_custom_show_markers = false, p2_custom_show_cursor = false, p2_custom_show_hz = false, p2_custom_show_numbers = false, p2_custom_show_text = false,

    -- P2 TEXT: CROSSUP
    p2_crossup_show = true,
    p2_crossup_color_text = true,
    p2_crossup_pos_mode = 1,
    p2_crossup_head_off_x = 0.0, p2_crossup_head_off_y = 0.0,
    p2_crossup_root_off_x = 0.0, p2_crossup_root_off_y = 0.0,
    p2_crossup_fixed_x = 0.0, p2_crossup_fixed_y = 0.0,
    
    -- P2 TEXT: OPPONENT ZONE
    p2_opp_zone_show = true,
    p2_opp_zone_color_text = true,
    p2_opp_zone_pos_mode = 4,
    p2_opp_zone_head_off_x = 0.0, p2_opp_zone_head_off_y = -50.0,
    p2_opp_zone_root_off_x = 160.0, p2_opp_zone_root_off_y = 600.0,
    p2_opp_zone_fixed_x = 0.42, p2_opp_zone_fixed_y = 0.145,
    p2_opp_zone_cursor_off_x = 15.0,
	-- =======================================================
    -- [TWEAKS MANUELS P2] (Valeurs de 0.0 à 1.0 = Hauteur écran)
    -- =======================================================
    p2_opp_zone_cursor_h_1 = 0.51, p2_opp_zone_cursor_h_2 = 0.85, p2_opp_zone_cursor_h_3 = 0.16, p2_opp_zone_cursor_h_4 = 0.51,
    p2_opp_zone_cursor_input_h_1 = 0.55, p2_opp_zone_cursor_input_h_2 = 0.90, p2_opp_zone_cursor_input_h_3 = 0.20, p2_opp_zone_cursor_input_h_4 = 0.55,
    
    -- P2 TEXT: MY ZONE
    p2_my_zone_show = false,
    p2_my_zone_color_text = true,
    p2_my_zone_pos_mode = 1,
    p2_my_zone_head_off_x = 0.0, p2_my_zone_head_off_y = -20.0,
    p2_my_zone_root_off_x = 0.0, p2_my_zone_root_off_y = -20.0,
    p2_my_zone_fixed_x = 0.75, p2_my_zone_fixed_y = 0.20,
    
    -- Global
    marker_thickness = 5.0, marker_origin_shift = 0.0,
	func_button = nil,
    -- Window State
    show_debug_window = true,
	expert_mode_enabled = false,
    window_pos_x = 20.0, window_pos_y = 20.0,
    p1_tree_open = false, p2_tree_open = false,
    adv_show_line_labels = true
}

local settings_file = "SF6DistanceViewer_Config.json"
local function save_settings() local d={config=config}; json.dump_file(settings_file, d) end
local function load_settings() 
    local d=json.load_file(settings_file)
    if d and d.config then 
        for k,v in pairs(d.config) do 
            if config[k]~=nil then config[k]=v end 
        end
        -- Migration
		if d.config.advanced_mode ~= nil then config.p1_advanced_mode = d.config.advanced_mode; config.p2_advanced_mode = d.config.advanced_mode; d.config.advanced_mode = nil end
        if d.config.p1_crossup_dynamic ~= nil then config.p1_crossup_pos_mode = d.config.p1_crossup_dynamic and 1 or 2 end
        if d.config.p1_opp_zone_dynamic ~= nil then config.p1_opp_zone_pos_mode = d.config.p1_opp_zone_dynamic and 1 or 2 end
        if d.config.p1_my_zone_dynamic ~= nil then config.p1_my_zone_pos_mode = d.config.p1_my_zone_dynamic and 1 or 2 end
        if d.config.p2_crossup_dynamic ~= nil then config.p2_crossup_pos_mode = d.config.p2_crossup_dynamic and 1 or 2 end
        if d.config.p2_opp_zone_dynamic ~= nil then config.p2_opp_zone_pos_mode = d.config.p2_opp_zone_dynamic and 1 or 2 end
        if d.config.p2_my_zone_dynamic ~= nil then config.p2_my_zone_pos_mode = d.config.p2_my_zone_dynamic and 1 or 2 end
        
        local function migrate_offsets(prefix)
            if d.config[prefix .. "_off_x"] ~= nil then
                config[prefix .. "_head_off_x"] = d.config[prefix .. "_off_x"]
                config[prefix .. "_root_off_x"] = d.config[prefix .. "_off_x"]
                config[prefix .. "_head_off_y"] = d.config[prefix .. "_off_y"]
                config[prefix .. "_root_off_y"] = d.config[prefix .. "_off_y"]
            end
        end
       migrate_offsets("p1_crossup"); migrate_offsets("p1_opp_zone"); migrate_offsets("p1_my_zone")
        migrate_offsets("p2_crossup"); migrate_offsets("p2_opp_zone"); migrate_offsets("p2_my_zone")

        -- Migrate legacy single line height to per-mode line heights
        if d.config.p1_line_height ~= nil then
            for i=1,4 do config["p1_line_height_"..i] = d.config.p1_line_height end
            d.config.p1_line_height = nil
        end
        if d.config.p2_line_height ~= nil then
            for i=1,4 do config["p2_line_height_"..i] = d.config.p2_line_height end
            d.config.p2_line_height = nil
        end
        
        -- Migrate legacy cursor_off_y
        if d.config.p1_opp_zone_cursor_off_y ~= nil then
            for i=1,4 do config["p1_opp_zone_cursor_h_"..i] = 0.5 end
            d.config.p1_opp_zone_cursor_off_y = nil
        end
        if d.config.p2_opp_zone_cursor_off_y ~= nil then
            for i=1,4 do config["p2_opp_zone_cursor_h_"..i] = 0.5 end
            d.config.p2_opp_zone_cursor_off_y = nil
        end
    end 
end
load_settings()

-- =========================================================
-- [TELEPORT SYSTEM]
-- =========================================================
local pending_tp = { active = false, attacker_id = 0, distance = 0.0, attempts = 0, expected_c2c = 0.0 }
local shared_combat = { p1_front_offset = 0.0, p2_front_offset = 0.0, p1_edge_x = nil, p1_dist = nil, p2_edge_x = nil, p2_dist = nil }

local function apply_teleport_exact(attacker_id, distance, is_retry)
    local gb = sdk.find_type_definition("gBattle")
    if not gb then return end

    local sP = gb:get_field("Player"):get_data(nil)
    if not sP or not sP.mcPlayer then return end

    local p1 = sP.mcPlayer[0]
    local p2 = sP.mcPlayer[1]
    if not p1 or not p2 then return end

    local px1_raw = p1.pos.x.v
    local px2_raw = p2.pos.x.v
    local p1_is_left = px1_raw < px2_raw

    -- LECTURE DIRECTE DU CACHE GLOBAL
    local p1_offset = (attacker_id == 1) and shared_combat.p1_front_offset or 0.0
    local p2_offset = (attacker_id == 0) and shared_combat.p2_front_offset or 0.0

    local total_center_dist = distance + p1_offset + p2_offset

    local raw_total_dist = math.floor((total_center_dist * 65536.0) + 0.5)
    local current_mid_raw = math.floor((px1_raw + px2_raw) / 2.0)
    local half_raw = math.floor(raw_total_dist / 2.0)

    local p1_target_raw, p2_target_raw
    if p1_is_left then
        p1_target_raw = current_mid_raw - half_raw
        p2_target_raw = p1_target_raw + raw_total_dist 
    else
        p2_target_raw = current_mid_raw - half_raw
        p1_target_raw = p2_target_raw + raw_total_dist 
    end

    local max_bound_raw = 47841280
    local left_edge_raw = math.min(p1_target_raw, p2_target_raw)
    local right_edge_raw = math.max(p1_target_raw, p2_target_raw)
    
    if left_edge_raw < -max_bound_raw then
        local shift = -max_bound_raw - left_edge_raw
        p1_target_raw = p1_target_raw + shift
        p2_target_raw = p2_target_raw + shift
    elseif right_edge_raw > max_bound_raw then
        local shift = right_edge_raw - max_bound_raw
        p1_target_raw = p1_target_raw - shift
        p2_target_raw = p2_target_raw - shift
    end

    local p1_pos_double = p1_target_raw / 65536.0
    local p2_pos_double = p2_target_raw / 65536.0

    local sfix_type = sdk.find_type_definition("via.sfix")
    if sfix_type then
        local sfix_from_double = sfix_type:get_method("From(System.Double)")
        if p1 and p1.POS_SETx then p1:POS_SETx(sfix_from_double:call(nil, p1_pos_double)) end
        if p2 and p2.POS_SETx then p2:POS_SETx(sfix_from_double:call(nil, p2_pos_double)) end
    end
    
    if not is_retry then
        pending_tp.active = true
        pending_tp.attacker_id = attacker_id
        pending_tp.distance = distance
        pending_tp.expected_c2c = total_center_dist
        pending_tp.attempts = 0
    end
end

local first_draw = true

local first_draw = true
local is_binding_mode = false
local text_pos_modes = { "Follow Head", "Follow Root", "Fixed Screen" }

-- Functions utilizing the loaded config for visibility
local function is_move_visible(pi, char_name, input)
    local prefs = get_char_prefs(pi, char_name)
    if prefs.visibility[input] == nil then return true end
    return prefs.visibility[input]
end

local function set_move_visible(pi, char_name, input, val)
    local prefs = get_char_prefs(pi, char_name)
    prefs.visibility[input] = val
    save_advanced_prefs()
end

local esf_names_map = {
    ["ESF_001"]="Ryu",     ["ESF_002"]="Luke",    ["ESF_003"]="Kimberly", ["ESF_004"]="Chun-Li",
    ["ESF_005"]="Manon",   ["ESF_006"]="Zangief", ["ESF_007"]="JP",       ["ESF_008"]="Dhalsim",
    ["ESF_009"]="Cammy",   ["ESF_010"]="Ken",     ["ESF_011"]="Dee Jay",  ["ESF_012"]="Lily",
    ["ESF_013"]="A.K.I.",  ["ESF_014"]="Rashid",  ["ESF_015"]="Blanka",   ["ESF_016"]="Juri",
    ["ESF_017"]="Marisa",  ["ESF_018"]="Guile",   ["ESF_019"]="Ed",
    ["ESF_020"]="E. Honda",["ESF_021"]="Jamie",   ["ESF_022"]="Akuma",
    ["ESF_025"]="Sagat",   ["ESF_026"]="M.Bison", ["ESF_027"]="Terry",
    ["ESF_028"]="Maï",     ["ESF_029"]="Elena",   ["ESF_030"]="Viper",["ESF_031"]="Alex"
}

local function get_real_name(esf_key)
    return esf_names_map[esf_key] or esf_key
end

-- Map inverse : nom réel -> clé ESF (pour patcher spacing_thresholds)
local real_to_esf = {}
for esf_key, real_name in pairs(esf_names_map) do
    real_to_esf[real_name] = esf_key
end

local function load_advanced_data()
    local f = json.load_file(UNIFIED_FILE)
    local atk = f and f.attacks
    if not atk then
        -- Migration: try old file (flat format)
        atk = json.load_file("SF6DistanceLogger_Data_Attacks.json")
    end
    if not atk or type(atk) ~= "table" then return end

    for char_name, cdata in pairs(atk) do
        if type(cdata) == "table" and cdata.moves then
            local fixed = {}
            for _, v in pairs(cdata.moves) do
                if type(v) == "table" then table.insert(fixed, v) end
            end
            table.sort(fixed, function(a, b) return (a.ar or 0) > (b.ar or 0) end)
            cdata.moves = fixed
        end
    end
    advanced_data = atk

    local count = 0
    for _, _ in pairs(advanced_data) do count = count + 1 end
    debug_dist_status = string.format("OK (%d custom chars)", count)
    debug_dist_color = 0xFF00FF00
end

local function get_player_limits(pi, p_data)
    local char_name = p_data.adv_name or get_real_name(p_data.real_name)
    local cdata = advanced_data[char_name]
    if not cdata then return fallback_spacing end

    -- Get prefs for current stance/variant (no fallback to attacks data)
    local prefs = advanced_prefs[pi] and advanced_prefs[pi][char_name] or {}
    local p_red = (prefs.red and prefs.red ~= false) and prefs.red or nil
    local p_low = (prefs.low and prefs.low ~= false) and prefs.low or nil
    local p_yoff = prefs.yellow_offset or 50

    local red_ar = p_red and (p_red.ar / 100.0) or nil
    local low_ar = p_low and (p_low.ar / 100.0) or nil

    -- Yellow = max(red, low) + offset. Si aucun des deux, yellow = offset seul
    local base_ar = nil
    if red_ar and low_ar then base_ar = math.max(red_ar, low_ar)
    elseif red_ar then base_ar = red_ar
    elseif low_ar then base_ar = low_ar end

    local yellow = base_ar and (base_ar + (p_yoff / 100.0)) or (p_yoff > 0 and (p_yoff / 100.0) or nil)

    return {
        red = red_ar, low = low_ar, yellow = yellow,
        red_input = p_red and p_red.input or nil,
        low_input = p_low and p_low.input or nil
    }
end

local function save_advanced_data()
    local current = json.load_file(UNIFIED_FILE) or {}
    current.attacks = advanced_data
    if not current.jumps then current.jumps = {} end
    if not current.player_prefs then current.player_prefs = advanced_prefs end
    json.dump_file(UNIFIED_FILE, current)
    load_advanced_data()
end

local function get_guard_type_name(gb)
    if not gb or gb == 0 then return "---" end
    if gb == 7 then return "Mid" end
    if gb == 6 then return "Low" end
    if gb == 5 then return "Overhead" end
    if gb == 3 then return "Grd.Mid" end
    if gb == 1 then return "High" end
    if gb == 2 then return "Crouch" end
    if gb == 4 then return "Air" end
    return tostring(gb)
end

-- Gradient hot (red) -> cold (blue), format ABGR
local function ar_to_color_abgr(ar, ar_min, ar_max)
    local t = 0.5
    if ar_max > ar_min then t = (ar - ar_min) / (ar_max - ar_min) end
    t = math.max(0, math.min(1, t))
    
    -- Invert the gradient: t=1 is now close (red), t=0 is far (blue)
    t = 1.0 - t
    
    local r, g, b
    if t < 0.25 then
        local s = t / 0.25; r = 0; g = math.floor(s * 255); b = 255
    elseif t < 0.5 then
        local s = (t - 0.25) / 0.25; r = 0; g = 255; b = math.floor((1 - s) * 255)
    elseif t < 0.75 then
        local s = (t - 0.5) / 0.25; r = math.floor(s * 255); g = 255; b = 0
    else
        local s = (t - 0.75) / 0.25; r = 255; g = math.floor((1 - s) * 255); b = 0
    end
    return 0xFF000000 | (b << 16) | (g << 8) | r
end



local function get_ar_range(pi, char_name)
    local cdata = advanced_data[char_name]
    if not cdata or not cdata.moves or #cdata.moves == 0 then return 0, 1 end
    local mn, mx = math.huge, -math.huge
    local has_visible = false
    for _, m in ipairs(cdata.moves) do
        if is_move_visible(pi, char_name, m.input) then
            if m.ar < mn then mn = m.ar end
            if m.ar > mx then mx = m.ar end
            has_visible = true
        end
    end
    if not has_visible then return 0, 1 end
    -- Évite la division par zéro si un seul coup est sélectionné
    if mn == mx then return mn, mx + 0.1 end 
    return mn, mx
end

-- =========================================================
-- [GLOBAL CACHE & OPTIMIZATION]
-- =========================================================
local temp_world_vec = Vector3f.new(0, 0, 0)
local p1_cache = { id = 0, world_x = 0, world_y = 0, real_name = "", act_param = nil, valid = false, facing_right = true, head_screen_pos = nil, root_screen_pos = nil, obj = nil }
local p2_cache = { id = 1, world_x = 0, world_y = 0, real_name = "", act_param = nil, valid = false, facing_right = false, head_screen_pos = nil, root_screen_pos = nil, obj = nil }

local frozen_frames = 0
local last_stage_timer = -1

local ATTACK_MASK = 16 | 32 | 64 | 128 | 256 | 512

local lock_states = {
    [0] = { active = false, duration = 0, pending = false, capture_timer = 0, locked_x = 0, locked_y = 0, last_input = 0, current_reach = 0, tracked_id = -1 },
    [1] = { active = false, duration = 0, pending = false, capture_timer = 0, locked_x = 0, locked_y = 0, last_input = 0, current_reach = 0, tracked_id = -1 }
}

local function read_sfix(sfix_obj)
    if not sfix_obj then return 0 end
    local str_val = sfix_obj:call("ToString()")
    return tonumber(str_val) or 0
end

local function bitand(a, b)
    local r = 0; local B = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + B end
        B = B * 2; a = math.floor(a / 2); b = math.floor(b / 2)
    end
    return r
end

local colors = { Green=0xFF00FF00, Yellow=0xFF00FFFF, Orange=0xFF00A5FF, Red=0xFF0000FF, Purple=0xFFFF00FF, White=0xFFFFFFFF, Black=0xFF000000, Cyan=0xFF00FFFF, Grey=0xFFAAAAAA }

local function get_dynamic_color(base_color_abgr)
    local alpha = math.floor((config.zone_opacity / 100.0) * 255)
    return (base_color_abgr & 0x00FFFFFF) | (alpha << 24)
end

local shadow_color = 0x80000000

-- =========================================================
-- [THEMED UI - Same style as Distance Logger]
-- =========================================================
local COL_RED    = 0xFF4444FF
local COL_ORANGE = 0xFF00A5FF
local COL_YELLOW = 0xFF00FFFF
local COL_GREEN  = 0xFF00FF00
local COL_CYAN   = 0xFFFFFF00
local COL_GREY   = 0xFF888888
local COL_GOLD   = 0xFF00D5FF

local UI_THEME = {
    hdr_info      = { base = 0xFF32C8F5, hover = 0xFF50D7FF, active = 0xFF1EAAEE }, -- Jaune soutenu
    hdr_rules     = { base = 0xFF2882F0, hover = 0xFF3C96FF, active = 0xFF1464D2 }, -- Orange vibrant
    hdr_session_1 = { base = 0xFF4B4BE1, hover = 0xFF5F5FF5, active = 0xFF3232C3 }, -- Rouge doux mais franc
    hdr_session_2 = { base = 0xFFE69646, hover = 0xFFFAAA5A, active = 0xFFC87832 }, -- Bleu océan
    hdr_debug     = { base = 0xFF5AC850, hover = 0xFF6EDC64, active = 0xFF46AA3C }, -- Vert prairie
}

local function styled_header(label, style)
    imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

local function styled_tree_node(label, color)
    imgui.push_style_color(0, color)
    local is_open = imgui.tree_node(label)
    imgui.pop_style_color(1)
    return is_open
end

local jump_states = {
    [0] = { locked = false, origin_x = 0, last_grounded_x = 0, facing_at_lock = true },
    [1] = { locked = false, origin_x = 0, last_grounded_x = 0, facing_at_lock = false }
}

local function get_sorted_thresholds(limits, show_title, show_name, prefix)
    if show_title == nil then show_title = true end
    if show_name == nil then show_name = true end
    local space = (prefix and prefix ~= "") and (prefix .. " ") or ""
    
    local function make_name(title, input)
            if show_title and show_name then
                if input then return space .. title .. "\n{" .. input .. "}" else return space .. title end
            elseif show_title and not show_name then
                return space .. title
            elseif not show_title and show_name then
                if input then return space .. "{" .. input .. "}" else return space .. title end
            else
                return ""
            end
        end

    local arr = {}
    if limits.low then arr[#arr+1] = { name = make_name("Red Zone", limits.low_input), dist = limits.low, color = colors.Red, fill = get_dynamic_color(colors.Red) } end
    if limits.red then arr[#arr+1] = { name = make_name("Orange Zone", limits.red_input), dist = limits.red, color = colors.Orange, fill = get_dynamic_color(colors.Orange) } end
    if limits.yellow then arr[#arr+1] = { name = make_name("Yellow Zone", nil), dist = limits.yellow, color = colors.Yellow, fill = get_dynamic_color(colors.Yellow) } end
    table.sort(arr, function(a, b) return a.dist < b.dist end)
    return arr
end

local function get_dynamic_screen_size()
    local w, h = 1920, 1080 
    if imgui.get_display_size then
        local result = imgui.get_display_size()
        if type(result) == "userdata" then
            local ok, x = pcall(function() return result.x end)
            local ok2, y = pcall(function() return result.y end)
            if ok and ok2 then w = x; h = y 
            elseif result.w and result.h then w = result.w; h = result.h end
        elseif type(result) == "number" then
            local w_val, h_val = imgui.get_display_size()
            w, h = w_val, h_val
        end
    end
    if w == nil or w <= 0 then w = 1920 end
    if h == nil or h <= 0 then h = 1080 end
    return w, h
end

local custom_font = { obj = nil, filename = "SF6_college.ttf", loaded_size = 0, status = "Init..." }
local custom_font_num = { obj = nil, filename = "SF6_college.ttf", loaded_size = 0, status = "Init..." }
local ui_font = { obj = nil, filename = "SF6_college.ttf", loaded_size = 0, status = "Init..." }
local res_watcher = { last_w = 0, last_h = 0, cooldown = 0 }

local function try_load_font()
    if not imgui.load_font then custom_font.status = "API Error"; custom_font_num.status = "API Error"; return end
    local sw, sh = get_dynamic_screen_size()
    local scale_factor = sh / 1080.0
    if scale_factor < 0.1 then scale_factor = 1.0 end
    
    local target_size = math.floor(config.stats_font_size * scale_factor)
    if custom_font.obj == nil or custom_font.loaded_size ~= target_size then
        local font = imgui.load_font(custom_font.filename, target_size)
        if font then 
            custom_font.obj = font; custom_font.loaded_size = target_size; custom_font.status = "OK ("..target_size.."px)"
        else custom_font.status = "File Not Found" end
    end

    local target_size_num = math.floor((config.number_font_size or 60) * scale_factor)
    if custom_font_num.obj == nil or custom_font_num.loaded_size ~= target_size_num then
        local font_num = imgui.load_font(custom_font_num.filename, target_size_num)
        if font_num then 
            custom_font_num.obj = font_num; custom_font_num.loaded_size = target_size_num; custom_font_num.status = "OK ("..target_size_num.."px)"
        else custom_font_num.status = "File Not Found" end
    end

    local target_size_ui = math.floor(18 * (config.ui_scale or 1.25) * scale_factor)
    if ui_font.obj == nil or ui_font.loaded_size ~= target_size_ui then
        local font_ui = imgui.load_font(ui_font.filename, target_size_ui)
        if font_ui then 
            ui_font.obj = font_ui; ui_font.loaded_size = target_size_ui; ui_font.status = "OK ("..target_size_ui.."px)"
        else ui_font.status = "File Not Found" end
    end

end

-- =========================================================
-- [INPUT ICONS CACHE & D2D QUEUE]
-- =========================================================
local d2d_icons = {}
local d2d_queue = {}
local icons_to_draw = {} -- Déclaré en global ici !
local d2d_initialized = false



local function init_d2d_icons()
    local folder = "buttonsAndArrows/"
    local keys = {"1","2","3","4","5","6","7","8","9","lp","mp","hp","lk","mk","hk","HOLD","THROW"}
    for _, k in ipairs(keys) do d2d_icons[k] = d2d.Image.new(folder .. k .. ".png") end
    d2d_initialized = true
end

local function draw_d2d_icons()
    if not d2d_initialized then init_d2d_icons() end
    for _, item in ipairs(d2d_queue) do
        local img = d2d_icons[item.key]
        if img then d2d.image(img, item.x, item.y, item.size, item.size) end
    end
    d2d_queue = {} -- CRITICAL: Clear queue ONLY after drawing to sync D2D/ImGui
end
d2d.register(init_d2d_icons, draw_d2d_icons)

local function flip_numpad(dir_str, facing_right)
    -- In SF6, the "facing_right" boolean based on BitValue 128 is actually true when facing LEFT.
    -- We invert the inputs ONLY when facing left (facing_right == true).
    if not facing_right then return dir_str end
    
    local map = { ["1"]="3", ["3"]="1", ["4"]="6", ["6"]="4", ["7"]="9", ["9"]="7" }
    return map[dir_str] or dir_str
end

local function parse_input_string(input_str, facing_right)
    local icons = {}
    local strength = ""
    
    -- 1. HOLD specific catch
    if string.upper(input_str):find("HOLD") or input_str:find("%[") then
        table.insert(icons, "HOLD")
    end

    
    -- 2. Direction logic (Ignore neutral "5", flip if facing left)
    local dir = input_str:match("%d+")
    if dir and dir ~= "5" then
        dir = flip_numpad(dir, facing_right)
        table.insert(icons, dir)
    end
    
    -- 3. Strict button extraction (lp, mp, hp, lk, mk, hk)
    local btn = string.lower(input_str):match("[lmh][pk]")
    if btn then 
        table.insert(icons, btn)
        strength = string.upper(string.sub(btn, 1, 1))
    end

    -- 4. THROW specific catch
    if string.upper(input_str):find("THROW") or input_str:find("%[") then
        table.insert(icons, "THROW")
    end

    
    return icons, strength
end

local debug_dist_status = "Not Loaded"
local debug_jump_status = "Not Loaded"
local debug_dist_color = 0xFF0000FF 
local debug_jump_color = 0xFF0000FF

-- 1. INIT DISTANCES (Strictement via Advanced Data maintenant)
spacing_thresholds = {}
debug_dist_status = "Waiting for Data..."
debug_dist_color = 0xFF888888

-- 2. LOAD JUMPS (from unified file, fallback to old file)
local _uf = json.load_file(UNIFIED_FILE)
local jump_data = _uf and _uf.jumps
if not jump_data then jump_data = json.load_file("SF6DistanceLogger_Data_Jumps.json") end
if jump_data then
    jump_data_store = jump_data
    local count = 0
    for k, v in pairs(jump_data_store) do count = count + 1 end
    debug_jump_status = string.format("OK (%d chars)", count)
    debug_jump_color = 0xFF00FF00
else
    debug_jump_status = "ERROR: JSON not found"
    jump_data_store = {}
end
_uf = nil
load_advanced_data()

local detected_infos = { [0] = { name = "Waiting...", id = -1 }, [1] = { name = "Waiting...", id = -1 } }
local t_med = sdk.find_type_definition("app.FBattleMediator")
if t_med then
    local method = t_med:get_method("UpdateGameInfo")
    if method then
        sdk.hook(method, function(args)
            local managed_obj = sdk.to_managed_object(args[2])
            if managed_obj then
                local f_pt = t_med:get_field("PlayerType")
                if f_pt then
                    local array = f_pt:get_data(managed_obj)
                    if array and array:call("get_Length") >= 2 then
                        for i=0,1 do
                            local obj = array:call("GetValue", i)
                            if obj then 
                                local pid = obj:get_type_definition():get_field("value__"):get_data(obj)
                                detected_infos[i].name = string.format("ESF_%03d", pid)
                            end
                        end
                    end
                end
            end
        end, function(retval) return retval end)
    end
end

local function get_char_top_screen_pos(player_obj)
    if not player_obj then return nil, 0 end
    local root_x = 0; local root_y = 0
    if player_obj.pos and player_obj.pos.x and player_obj.pos.y then
        root_x = player_obj.pos.x.v / 6553600.0; root_y = player_obj.pos.y.v / 6553600.0
    else return nil, 0 end

    local highest_y = -999.0; local found_dynamic_box = false
    local act_param = player_obj.mpActParam
    if act_param and act_param.Collision and act_param.Collision.Infos and act_param.Collision.Infos._items then
        for i, r in pairs(act_param.Collision.Infos._items) do
            if r and r.OffsetY and r.OffsetY.v and r.SizeY and r.SizeY.v then
                local pY = r.OffsetY.v / 6553600.0; local sY = (r.SizeY.v / 6553600.0) * 2 
                local top_edge = pY + (sY / 2)
                if top_edge > (root_y + 0.8) then
                    if top_edge > highest_y then highest_y = top_edge; found_dynamic_box = true end
                end
            end
        end
    end

    local final_y = 0
    if found_dynamic_box then final_y = highest_y + 0.1 else final_y = root_y + 2.0 end
    if draw and draw.world_to_screen then return draw.world_to_screen(Vector3f.new(root_x, final_y, 0)), final_y end
    return nil, final_y
end

local function get_char_root_screen_pos(player_obj)
    if not player_obj then return nil end
    if player_obj.pos and player_obj.pos.x and player_obj.pos.y then
        local root_x = player_obj.pos.x.v / 6553600.0; local root_y = player_obj.pos.y.v / 6553600.0
        if draw and draw.world_to_screen then return draw.world_to_screen(Vector3f.new(root_x, root_y, 0)) end
    end
    return nil
end

local gBattle = nil
local function update_player_cache(pi, cache_table)
    if gBattle==nil then gBattle=sdk.find_type_definition("gBattle") end; if gBattle==nil then cache_table.valid = false; return end
    local sP=gBattle:get_field("Player"):get_data(nil); if sP==nil then cache_table.valid = false; return end
    local cP=sP.mcPlayer; if cP==nil or cP[pi]==nil then cache_table.valid = false; return end
    local p=cP[pi]; 
    
    cache_table.obj = p
    if p.pos and p.pos.x and p.pos.x.v and p.pos.y and p.pos.y.v then 
        cache_table.world_x = p.pos.x.v/6553600.0; cache_table.world_y = p.pos.y.v/6553600.0; cache_table.act_param = p.mpActParam
        cache_table.head_screen_pos, cache_table.head_world_y = get_char_top_screen_pos(p)
        cache_table.root_screen_pos = get_char_root_screen_pos(p)
        
        local bit_val = p.BitValue
        if bit_val then 
             cache_table.facing_right = (bitand(bit_val, 128) == 128)
        else cache_table.facing_right = (pi == 0) end
        local detected = detected_infos[pi] or { name="?" }
        cache_table.real_name = detected.name
        
        local char_name = esf_names_map[detected.name] or detected.name
        cache_table.adv_name = char_name
        
        if char_name == "Alex" and p.mpActParam ~= nil and p.mpActParam.ActionPart ~= nil then
            local eng = p.mpActParam.ActionPart._Engine
            if eng ~= nil then
                local a_id = eng:get_ActionID()
                if a_id == 957 
				or a_id == 960 
				or a_id == 970 
				or a_id == 964 
				or a_id == 962 
				or a_id == 973 
				or a_id == 976 
				or a_id == 977 
				or a_id == 980 
				or a_id == 982 
				or a_id == 967 
				or a_id == 968 
				or a_id == 969 
				or a_id == 971 
				or a_id == 972 
				or a_id == 978 
				or a_id == 993 
				then cache_table.adv_name = "Alex_Prowler" end
            end
        end
        if char_name == "Chun-Li" and p.mpActParam ~= nil and p.mpActParam.ActionPart ~= nil then
            local eng = p.mpActParam.ActionPart._Engine
            if eng ~= nil then
                local a_id = eng:get_ActionID()
                if a_id == 658
                or a_id == 659
                or a_id == 660
                or a_id == 663
                or a_id == 664
                or a_id == 666
                or a_id == 667
                or a_id == 668
                or a_id == 669
                or a_id == 670
                or a_id == 680
                or a_id == 681
                or a_id == 684
                or a_id == 686
                or a_id == 688
                then cache_table.adv_name = "ChunLi_Serenity" end
            end
        end
        cache_table.valid = true
    else cache_table.valid = false end
end

local function update_jump_state_logic(pi, cache_data)
    local state = jump_states[pi]
    if cache_data.world_y > 0.05 then
        if not state.locked then state.locked = true; state.origin_x = state.last_grounded_x; state.facing_at_lock = cache_data.facing_right end
    else
        state.locked = false; state.origin_x = cache_data.world_x; state.facing_at_lock = cache_data.facing_right; state.last_grounded_x = cache_data.world_x
    end
end

local function get_current_max_reach(player_obj, locked_origin_x)
    if not player_obj then return 0 end
    local act_param = player_obj.mpActParam
    if not act_param then return 0 end

    local col = act_param.Collision
    if not col then return 0 end
    
    local max_dist = 0.0
    if col.Infos and col.Infos._items then
        for i, rect in pairs(col.Infos._items) do
            if rect then
                local is_attack = false
                if rect.TypeFlag and rect.TypeFlag > 0 then is_attack = true 
                elseif rect.TypeFlag == 0 and rect.PoseBit and rect.PoseBit > 0 then is_attack = true end

                if is_attack and rect.OffsetX and rect.SizeX then
                    local posX = rect.OffsetX.v / 6553600.0
                    local sclX = (rect.SizeX.v / 6553600.0) * 2
                    local edge_left = posX - (sclX / 2)
                    local edge_right = posX + (sclX / 2)
                    local d1 = math.abs(edge_left - locked_origin_x)
                    local d2 = math.abs(edge_right - locked_origin_x)
                    if d1 > max_dist then max_dist = d1 end
                    if d2 > max_dist then max_dist = d2 end
                end
            end
        end
    end
    return max_dist
end

local function process_attack_lock(pi, cache_data)
    if not cache_data.valid or not cache_data.obj then return end
    local state = lock_states[pi]
    
    local f_sw = cache_data.obj:get_type_definition():get_field("pl_sw_new")
    local raw_input = f_sw and f_sw:get_data(cache_data.obj) or 0
    local attack_input = raw_input & ATTACK_MASK
    
    local just_pressed = attack_input & ~state.last_input
    state.last_input = attack_input
    
    if just_pressed > 0 then
        state.pending = true
        state.capture_timer = 0
    end

    if state.pending then
        state.capture_timer = state.capture_timer + 1
        if state.capture_timer >= 1 then
            local act_param = cache_data.act_param
            local engine = act_param and act_param:get_field("ActionPart"):get_field("_Engine")
            
            if engine then
                local margin_obj = engine:call("get_MarginFrame")
                local margin_val = math.floor(read_sfix(margin_obj))
                local current_action_id = engine:call("get_ActionID")

                if margin_val > 0 then
                    state.duration = margin_val
                    state.active = true
                    state.tracked_id = current_action_id
                    state.locked_x = cache_data.world_x
                    state.locked_y = cache_data.world_y
                    state.current_reach = 0 
                end
            end
            state.pending = false
        end
        return 
    end

    if state.active then
        local act_param = cache_data.act_param
        local engine = act_param and act_param:get_field("ActionPart"):get_field("_Engine")
        if engine then
            local current_id = engine:call("get_ActionID")
            local current_frame_obj = engine:call("get_ActionFrame")
            local current_frame = math.floor(read_sfix(current_frame_obj))
            
            if current_id ~= state.tracked_id then
                state.active = false
                state.duration = 0
                state.tracked_id = -1
                return
            end

            if current_frame >= state.duration then
                state.active = false
                state.duration = 0
                state.tracked_id = -1
                return
            end
            
            state.current_reach = get_current_max_reach(cache_data.obj, state.locked_x)
        end
    end
end

local function safe_input_float(label, val)
    if imgui.input_float then return imgui.input_float(label, val) end
    local changed, str = imgui.input_text(label, tostring(val))
    if changed then local n = tonumber(str); if n then return true, n end end; return false, val
end

local function safe_input_int(label, val)
    if imgui.input_int then return imgui.input_int(label, val) end
    local changed, str = imgui.input_text(label, tostring(val))
    if changed then local n = tonumber(str); if n then return true, math.floor(n) end end; return false, val
end

local function draw_thick_line(x1, y1, x2, y2, th, col) 
    local dx=x2-x1; local dy=y2-y1; 
    if (dx*dx + dy*dy) < 0.1 then return end 
    local len=math.sqrt(dx*dx+dy*dy)
    local nx=-dy/len; local ny=dx/len; local half=th/2.0; 
    draw.filled_quad(x1+nx*half, y1+ny*half, x2+nx*half, y2+ny*half, x2-nx*half, y2-ny*half, x1-nx*half, y1-ny*half, col) 
end

local function world_to_screen_optimized(wx, wy, wz)
    temp_world_vec.x = wx; temp_world_vec.y = wy; temp_world_vec.z = wz
    return draw.world_to_screen(temp_world_vec)
end

-- =========================================================
-- [MASTER COLLISION CACHE] - Single Detection Engine
-- =========================================================

local function update_combat_distances()
    if not p1_cache.valid or not p2_cache.valid then return end
    
    local function analyze_boxes(player_obj, is_on_left, ref_x)
        local front_offset = 0.0
        local closest_edge = nil
        local min_dist = 999999.0
        
        if not player_obj or not player_obj.mpActParam or not player_obj.mpActParam.Collision then return 0.0, nil, nil end
        local col = player_obj.mpActParam.Collision
        local px = player_obj.pos.x.v / 6553600.0
        
        if col.Infos and col.Infos._items then
            for _, r in pairs(col.Infos._items) do
                local dominated = false
                if r then
                    local has_HitPos = r:get_field("HitPos") ~= nil
                    local has_Attr = r:get_field("Attr") ~= nil
                    local has_HitNo = r:get_field("HitNo") ~= nil
                    if has_HitPos then
                        local tf = r.TypeFlag or 0
                        local pb = r.PoseBit or 0
                        local cf = r.CondFlag or 0
                        local gb = r.GuardBit or 0
                        if tf > 0 then dominated = config.box_use_hitbox
                        elseif (tf == 0 and pb > 0) or cf == 0x2C0 then dominated = config.box_use_throwbox
                        elseif gb == 0 then dominated = config.box_use_clash
                        else dominated = config.box_use_proximity end
                    elseif has_Attr then
                        dominated = config.box_use_pushbox
                    elseif has_HitNo then
                        local tp = r.Type or 0
                        if tp == 1 or tp == 2 then dominated = config.box_use_hurtbox_invuln
                        else dominated = config.box_use_hurtbox end
                    end
                end
                if r and dominated then
                    local box_x = (r.OffsetX and r.OffsetX.v) and (r.OffsetX.v / 6553600.0) or 0.0
                    local size_x = (r.SizeX and r.SizeX.v) and (r.SizeX.v / 6553600.0) or 0.0
                    
                    local right_edge = box_x + size_x
                    local left_edge = box_x - size_x
                    
                    -- Front offset for Teleport calculation
                    local off = is_on_left and (right_edge - px) or (px - left_edge)
                    if off > front_offset then front_offset = off end
                    
                    -- Distance to opponent center for UI drawing
                    local d_left = math.abs(ref_x - left_edge)
                    local d_right = math.abs(ref_x - right_edge)
                    if d_left < min_dist then min_dist = d_left; closest_edge = left_edge end
                    if d_right < min_dist then min_dist = d_right; closest_edge = right_edge end
                end
            end
        end
        return front_offset * 100.0, closest_edge, min_dist
    end

    local p1_is_left = p1_cache.world_x < p2_cache.world_x
    
    -- [CRITICAL FIX] : Prise en compte du Lock pour calculer la distance depuis l'origine gelée
    local p1_ref_x = p1_cache.world_x
    local p2_ref_x = p2_cache.world_x
    if config.use_attack_lock then
        if lock_states[0].active then p1_ref_x = lock_states[0].locked_x end
        if lock_states[1].active then p2_ref_x = lock_states[1].locked_x end
    end
    
    -- Analyze once for P1, once for P2
    local p1_off, edge_for_p2, dist_for_p2 = analyze_boxes(p1_cache.obj, p1_is_left, p2_ref_x)
    shared_combat.p1_front_offset = p1_off
    shared_combat.p2_edge_x = edge_for_p2
    shared_combat.p2_dist = dist_for_p2
    
    local p2_off, edge_for_p1, dist_for_p1 = analyze_boxes(p2_cache.obj, not p1_is_left, p1_ref_x)
    shared_combat.p2_front_offset = p2_off
    shared_combat.p1_edge_x = edge_for_p1
    shared_combat.p1_dist = dist_for_p1
end

local function get_closest_edge(player_id)
    if player_id == 0 then
        return shared_combat.p1_edge_x, shared_combat.p1_dist
    else
        return shared_combat.p2_edge_x, shared_combat.p2_dist
    end
end


local function evaluate_player_zone(pi, cache_data, opponent_data)
    local _, dist_target = get_closest_edge(cache_data.id)
    if not dist_target then return { name = "Out Range", color = colors.Grey } end

    local is_adv = (pi == 0) and config.p1_advanced_mode or config.p2_advanced_mode
    local char_name = cache_data.adv_name or get_real_name(cache_data.real_name)
    
    -- La Source de Vérité absorbe l'erreur de 1 millimètre du moteur 3D ici.
    local epsilon = 0.001 
    
    if is_adv then
        local cdata = advanced_data[char_name]
        if cdata and cdata.moves then
            local prefs = get_char_prefs(pi, char_name)
            local ar_min, ar_max = get_ar_range(pi, char_name)
            local sorted = {}
            for _, m in ipairs(cdata.moves) do
                if is_move_visible(pi, char_name, m.input) then table.insert(sorted, m) end
            end
            table.sort(sorted, function(a, b) return a.ar < b.ar end)
            
            for _, mv in ipairs(sorted) do
                if dist_target <= (mv.ar / 100.0) + epsilon then
                    local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                    local zone_name = "{" .. mv.input .. "}"
                    local prefix = (pi == 0) and "P1" or "P2"
                    if prefs.red and prefs.red.input == mv.input then zone_name = prefix .. " Orange Zone\n" .. zone_name
                    elseif prefs.low and prefs.low.input == mv.input then zone_name = prefix .. " Red Zone\n" .. zone_name end
                    return { name = zone_name, color = col }
                end
            end
        end
    else
        local limits = get_player_limits(pi, cache_data)
        if limits then
            local sorted = get_sorted_thresholds(limits, true, true, (pi == 0) and "P1" or "P2")
            for _, zone in ipairs(sorted) do
                if dist_target <= zone.dist + 0.001 then
                    return { name = zone.name, color = zone.color }
                end
            end
        end
    end
    return { name = ((pi == 0) and "P1" or "P2") .. " Green Zone", color = colors.Green }
end

local function draw_text_safe(text, x, y, color, size) 
    draw.text(text, x + 2, y + 2, shadow_color, size)
    draw.text(text, x, y, color, size) 
end

local function draw_text_above_head_independent(text, pos, color, offset_x, offset_y, scale_factor, align, facing_right)
    if text == "" or not pos then return end
    
    local off_x = offset_x * scale_factor
    local off_y = offset_y * scale_factor

    local lines = {}
    for s in string.gmatch(text, "[^\r\n]+") do table.insert(lines, s) end
    
    local total_height = 0
    for _, line in ipairs(lines) do total_height = total_height + imgui.calc_text_size(line).y end
    
    -- Absolute Y coordinate with nearest-pixel rounding
    local current_y = math.floor(pos.y - off_y - total_height + 0.5)
    
    for _, line in ipairs(lines) do
        local text_height = imgui.calc_text_size(line).y
        local icon_size = math.floor(text_height * (config.icon_scale or 1.0) + 0.5)
        
        -- CALCULATE TRUE WIDTH ACCOUNTING FOR ICON SIZE
        local true_width = 0
        local before_txt, input_core, after_txt = string.match(line, "^(.-){(.-)}(.*)$")
        local parsed_icons, parsed_strength
        
        if input_core then
            parsed_icons, parsed_strength = parse_input_string(input_core, facing_right)
            local icon_letter_gap = 4 -- <<< CHANGE THIS VALUE FOR SPACING
            
            if before_txt and before_txt ~= "" then true_width = true_width + imgui.calc_text_size(before_txt).x end
            true_width = true_width + (#parsed_icons * icon_size)
            if #parsed_icons > 0 and parsed_strength ~= "" then true_width = true_width + icon_letter_gap end
            if parsed_strength ~= "" then true_width = true_width + imgui.calc_text_size(parsed_strength).x + 5 end
            if after_txt and after_txt ~= "" then true_width = true_width + imgui.calc_text_size(after_txt).x end
        else
            true_width = imgui.calc_text_size(line).x
        end
        
        -- Absolute X coordinate with nearest-pixel rounding
        local x_pos
        if align == "left" then x_pos = math.floor(pos.x + off_x + 0.5)
        elseif align == "right" then x_pos = math.floor(pos.x - true_width + off_x + 0.5)
        else x_pos = math.floor(pos.x - (true_width / 2.0) + off_x + 0.5) end
        
        if input_core then
            local current_x = x_pos
            if before_txt and before_txt ~= "" then
                local b_w = math.floor(imgui.calc_text_size(before_txt).x + 0.5)
                imgui.set_cursor_pos(Vector2f.new(current_x + 2, current_y + 2)); imgui.text_colored(before_txt, 0xFF000000)
                imgui.set_cursor_pos(Vector2f.new(current_x, current_y)); imgui.text_colored(before_txt, color)
                current_x = current_x + b_w
            end
            
            local y_with_offset = math.floor(current_y + ((config.icon_offset_y or 0.0) * scale_factor) + 0.5)
            
            for _, icon_key in ipairs(parsed_icons) do
                table.insert(d2d_queue, { key = icon_key, x = current_x, y = y_with_offset, size = icon_size })
                current_x = current_x + icon_size
            end
            
            local icon_letter_gap = 8 -- <<< SAME VALUE HERE
            if #parsed_icons > 0 and parsed_strength ~= "" then current_x = current_x + icon_letter_gap end
            
            if parsed_strength ~= "" then
                local s_w = math.floor(imgui.calc_text_size(parsed_strength).x + 0.5)
                imgui.set_cursor_pos(Vector2f.new(current_x + 2, current_y + 2)); imgui.text_colored(parsed_strength, 0xFF000000)
                imgui.set_cursor_pos(Vector2f.new(current_x, current_y)); imgui.text_colored(parsed_strength, color)
                current_x = current_x + s_w + 5
            end
            
            if after_txt and after_txt ~= "" then
                imgui.set_cursor_pos(Vector2f.new(current_x + 2, current_y + 2)); imgui.text_colored(after_txt, 0xFF000000)
                imgui.set_cursor_pos(Vector2f.new(current_x, current_y)); imgui.text_colored(after_txt, color)
            end
        else
            imgui.set_cursor_pos(Vector2f.new(x_pos + 2, current_y + 2)); imgui.text_colored(line, 0xFF000000)
            imgui.set_cursor_pos(Vector2f.new(x_pos, current_y)); imgui.text_colored(line, color)
        end
        current_y = current_y + math.floor(text_height + 0.5)
    end
end

local function get_crossup_info(cache_data, opponent_data)
    if not cache_data.valid or not opponent_data.valid then return "", colors.Grey end
    if not cache_data.valid or not opponent_data.valid then return "", colors.Grey end
    local real_distance = math.abs(cache_data.world_x - opponent_data.world_x) * 100
    local frames = jump_data_store[cache_data.real_name]
    local text_str = "No Data"; local text_col = colors.Grey
    if frames then
        local st_limit = frames.cross_up_st or 9999.0; local cr_limit = frames.cross_up_cr or 9999.0
        if real_distance < st_limit then text_str = "CrossUpSt"; text_col = colors.Red
        elseif real_distance < cr_limit then text_str = "CrossUpCr"; text_col = colors.Yellow
        else text_str = "No Cross"; text_col = colors.Grey end
    end
    return text_str, text_col
end

local function get_advanced_zone_label(pi, char_name, dist_cc, prefix, show_title, show_name)
    local cdata = advanced_data[char_name]
    if not cdata or not cdata.moves then return nil, nil end
    local prefs = get_char_prefs(pi, char_name)
        local ar_min, ar_max = get_ar_range(pi, char_name)
        local sorted = {}
    for _, m in ipairs(cdata.moves) do
        if is_move_visible(pi, char_name, m.input) then table.insert(sorted, m) end
    end
    if #sorted == 0 then return nil, nil end
    table.sort(sorted, function(a, b) return a.ar < b.ar end)
    
    if show_title == nil then show_title = true end
    if show_name == nil then show_name = true end
    local space = (prefix and prefix ~= "") and (prefix .. " ") or ""
    
    for _, mv in ipairs(sorted) do
        if dist_cc <= (mv.ar / 100.0) + 0.0000001 then
            local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
            
            if show_title and show_name then
                return space .. "\n{" .. mv.input .. "}", col
            elseif show_title and not show_name then
                return space, col
            elseif not show_title and show_name then
                return space .. "{" .. mv.input .. "}", col
            else
                return "", col
            end
        end
    end
    
    if show_title or show_name then return space .. "Out Range", colors.White end
        return "", colors.White
end

local function get_opp_zone_info(cache_data, opponent_data)
    if not cache_data.valid or not opponent_data.valid then return "", colors.Grey end
    
    -- MY ZONE LOGIC: On évalue sa propre position par rapport à la zone de l'adversaire
    local _, dist_target = get_closest_edge(cache_data.id)
    if not dist_target then return "No Data", colors.Grey end

    local prefix = "My"
    if cache_data.id == 0 then prefix = "P1"
    elseif cache_data.id == 1 then prefix = "P2" end

    local show_t, show_n = true, true -- Forcé à TRUE pour toujours avoir Titre + Coup

    local is_adv = false
    if cache_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    
    if is_adv then
        local char_name = cache_data.adv_name or get_real_name(cache_data.real_name)
        local txt, col = get_advanced_zone_label(cache_data.id, char_name, dist_target, prefix, show_t, show_n)
        if txt then return txt, col end
        return "", colors.Grey  -- no fallback to Red/Orange Zone labels in advanced mode
    end

    local limits = get_player_limits(cache_data.id, cache_data)
    local sorted = get_sorted_thresholds(limits, show_t, show_n, prefix)
    
    local text_str = ""
    if show_t or show_n then 
        local space = (prefix and prefix ~= "") and (prefix .. " ") or ""
        text_str = space .. "Green Zone" 
    end
    local text_col = colors.Green
    
    for _, zone in ipairs(sorted) do
        if dist_target <= zone.dist + 0.0000001 then
            text_str = zone.name
            text_col = zone.color
            break
        end
    end
    return text_str, text_col
end


local function draw_jump_arc(pi, cache_data, opponent_data, settings, scale_factor)
    if not settings.show_jump_arc or not cache_data.valid or not opponent_data.valid then return end
    local c_data = jump_data_store[cache_data.real_name]
    if not c_data or not c_data.points or #c_data.points < 2 then return end
    local frames = c_data.points
    local current_dist = math.abs(cache_data.world_x - opponent_data.world_x) * 100.0
    
    -- Sync limits with the text logic (using c_data, not frames)
    local st_limit = c_data.cross_up_st or 9999.0
    local cr_limit = c_data.cross_up_cr or 9999.0
    
    -- Dynamic color evaluation based on reach
    local arc_col = colors.Grey
    if current_dist < st_limit then arc_col = colors.Red
    elseif current_dist < cr_limit then arc_col = colors.Yellow end
    
    local state = jump_states[pi]
    local origin_x = state.origin_x
    local facing_right = state.facing_at_lock
    local dir = facing_right and 1.0 or -1.0
    local thickness = (config.jump_arc_thickness or 10.0) * scale_factor
    
    for i = 1, #frames - 1 do
        local pA = frames[i]; local pB = frames[i+1]
        local wX1 = origin_x + (pA.x * dir); local wY1 = pA.y
        local wX2 = origin_x + (pB.x * dir); local wY2 = pB.y
        local s1 = world_to_screen_optimized(wX1, wY1, 0); local s2 = world_to_screen_optimized(wX2, wY2, 0)
        if s1 and s2 then draw_thick_line(s1.x, s1.y, s2.x, s2.y, thickness, arc_col) end
    end
end

local function draw_spacing_horizontal(owner_data, target_data, settings, scale_factor, numbers_to_draw)
    if not settings.show_horizontal_lines then return end

    local scaled_thickness = config.marker_thickness * scale_factor
    local scaled_dot_size = (settings.origin_dot_size or 8.0) * scale_factor
    
    local _, screen_h = get_dynamic_screen_size()
    local y_min, y_max = 0, screen_h
    if settings.vertical_mode == 2 then y_max = screen_h / 2
    elseif settings.vertical_mode == 3 then y_min = screen_h / 2 end
    local y = y_min + ((y_max - y_min) * settings.line_height)
    
    local edge_target, dist_target = get_closest_edge(owner_data.id)
    local direction = 1
    if edge_target and edge_target < owner_data.world_x then direction = -1 end

    local function get_x(d)
        local w = world_to_screen_optimized(owner_data.world_x + (d * direction), owner_data.world_y, 0)
        return w and w.x or nil
    end

    local is_adv = false
    if owner_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    if is_adv then
        local char_name = owner_data.adv_name or get_real_name(owner_data.real_name)
        local cdata = advanced_data[char_name]
        
        if cdata and cdata.moves and #cdata.moves > 0 and dist_target then
            local ar_min, ar_max = get_ar_range(owner_data.id, char_name)
            
            local sorted = {}
            for _, m in ipairs(cdata.moves) do
                if is_move_visible(owner_data.id, char_name, m.input) then table.insert(sorted, m) end
            end
            table.sort(sorted, function(a, b) return a.ar < b.ar end)
            if #sorted == 0 then return end
            
            local prev_dist = 0
            local x_origin = get_x(0)
            local cur_col = colors.White
            local out_of_range = true
            
            for _, mv in ipairs(sorted) do
                local mv_dist = mv.ar / 100.0
                local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                
                if dist_target > prev_dist then
                    local d_start = prev_dist
                    local d_end = math.min(dist_target, mv_dist)
                    local x_start = get_x(d_start)
                    local x_end_seg = get_x(d_end)
                    if x_start and x_end_seg then
                        draw_thick_line(x_start, y, x_end_seg, y, scaled_thickness, col)
                    end
                end
                
                if dist_target <= mv_dist + 0.0000001 then
                    cur_col = col
                    out_of_range = false
                    break
                end
                prev_dist = mv_dist
            end
            
            if out_of_range and dist_target > prev_dist then
                local x_start = get_x(prev_dist)
                local x_end_seg = get_x(dist_target)
                if x_start and x_end_seg then
                    draw_thick_line(x_start, y, x_end_seg, y, scaled_thickness, colors.White)
                end
            end

            if settings.show_origin_dot and x_origin then 
                draw.filled_circle(x_origin, y, scaled_dot_size, colors.White, 16) 
            end

            local x_end = get_x(dist_target)
            if x_end and x_origin then
                if settings.vertical_mode == 1 then
                local center_y = y + (settings.end_marker_offset_y * scale_factor)
                local half_size = (settings.end_marker_size * scale_factor) / 2.0
                draw_thick_line(x_end, center_y - half_size, x_end, center_y + half_size, scaled_thickness, cur_col)
            end
                
                if settings.show_numbers then
                    local txt = string.format("%.5f", dist_target * 100)
                    local mid_x = (x_origin + x_end) / 2
                    local final_col = settings.color_text and cur_col or colors.White
                    table.insert(numbers_to_draw, { txt = txt, x = mid_x, y = y, col = final_col, off_y = settings.number_off_y })
                end
            end
            return
        end
    end

    local limits = get_player_limits(owner_data.id, owner_data)
    if edge_target and dist_target and limits then
        local sorted = get_sorted_thresholds(limits)
        local prev_dist = 0
        
        for i, zone in ipairs(sorted) do
            if dist_target > prev_dist then
                local d_start = prev_dist
                local d_end = math.min(dist_target, zone.dist)
                local x_start = get_x(d_start)
                local x_end = get_x(d_end)
                if x_start and x_end then draw_thick_line(x_start, y, x_end, y, scaled_thickness, zone.color) end
            end
            if dist_target <= zone.dist + 0.0000001 then 
                prev_dist = dist_target -- Empêche la ligne verte de s'écrire par dessus
                break 
            end
            prev_dist = zone.dist
        end
        
        if dist_target > prev_dist then
            local x_start = get_x(prev_dist)
            local x_end = get_x(dist_target)
            if x_start and x_end then draw_thick_line(x_start, y, x_end, y, scaled_thickness, colors.Green) end
        end
        
        local x_origin = get_x(0)
        if settings.show_origin_dot and x_origin then draw.filled_circle(x_origin, y, scaled_dot_size, colors.White, 16) end
        
        local x_final = get_x(dist_target)
        if x_final and x_origin then
            local cur_col = colors.Green
            for _, zone in ipairs(sorted) do
                if dist_target <= zone.dist + 0.0000001 then cur_col = zone.color; break end
            end
            
            if settings.vertical_mode == 1 then
                local center_y = y + (settings.end_marker_offset_y * scale_factor)
                local half_size = (settings.end_marker_size * scale_factor) / 2.0
                draw_thick_line(x_final, center_y - half_size, x_final, center_y + half_size, scaled_thickness, cur_col)
            end
            
            if settings.show_numbers then
                local txt = string.format("%.5f", dist_target * 100)
                local mid_x = (x_origin + x_final) / 2
                local final_col = settings.color_text and cur_col or colors.White
                table.insert(numbers_to_draw, { txt = txt, x = mid_x, y = y, col = final_col, off_y = settings.number_off_y })
            end
        end
    end
end
local function draw_vertical_overlay(owner_data, target_data, settings, scale_factor)
    if settings.vertical_mode == VMODE_NONE then return end
    if not settings.show_markers and not settings.fill_bg and not settings.show_vertical_cursor then return end

    local is_adv = false
    if owner_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    if is_adv then
        local char_name = owner_data.adv_name or get_real_name(owner_data.real_name)
        local cdata = advanced_data[char_name]
        if cdata and cdata.moves and #cdata.moves > 0 then
            local _, screen_h = get_dynamic_screen_size()
            local y_min, y_max = 0, screen_h
            if settings.vertical_mode == VMODE_TOP_HALF then y_max = screen_h / 2
            elseif settings.vertical_mode == VMODE_BOTTOM_HALF then y_min = screen_h / 2 end
            local dir = 1; if target_data.world_x < owner_data.world_x then dir = -1 end
            local origin_x = owner_data.world_x + (config.marker_origin_shift * dir)
            local scaled_thickness = config.marker_thickness * scale_factor
            local scaled_font_size  = config.stats_font_size * scale_factor
            local function get_screen_x(dist_val)
                local s = world_to_screen_optimized(origin_x + (dist_val * dir), 1.0, 0)
                return s and s.x or nil
            end
            local ar_min, ar_max = get_ar_range(owner_data.id, char_name)
            local sorted = {}
            for _, m in ipairs(cdata.moves) do
                if is_move_visible(owner_data.id, char_name, m.input) then table.insert(sorted, m) end
            end
            table.sort(sorted, function(a, b) return a.ar < b.ar end)
            if #sorted == 0 then return end

            if settings.fill_bg then
                local x_prev = get_screen_x(0)
                for _, mv in ipairs(sorted) do
                    local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                    local fill_col = get_dynamic_color(col)
                    local x_cur = get_screen_x(mv.ar / 100.0)
                    if x_prev and x_cur then
                        draw.filled_quad(x_prev, y_min, x_cur, y_min, x_cur, y_max, x_prev, y_max, fill_col)
                    end
                    x_prev = x_cur
                end
            end

            local label_toggle = true
            for _, mv in ipairs(sorted) do
                local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                local lx = get_screen_x(mv.ar / 100.0)
                if lx then
                    if settings.show_markers then
                        draw.line(lx, y_min, lx, y_max, col, scaled_thickness)
                        if config.adv_show_line_labels then
                            local prefs = get_char_prefs(owner_data.id, char_name)
                            local tag = ""
                            if prefs.red and prefs.red.input == mv.input then tag = "[R] " end
                            if prefs.low and prefs.low.input == mv.input then tag = "[L] " end

                            local label_y
                            if label_toggle then label_y = y_min + 5
                            else label_y = y_min + scaled_font_size * 1.5 end
                            label_toggle = not label_toggle

                            -- Store separated data for ImGui rendering instead of draw_text_safe
                            table.insert(icons_to_draw, {
                                raw_input = mv.input,
                                dist_text = string.format("%.5f", mv.ar),
                                tag = tag,
                                x = lx + 4,
                                y = label_y,
                                size = scaled_font_size,
                                color = col,
                                facing_right = owner_data.facing_right -- Stockage de la direction
                            })
                        end
                    end
                end
            end

            if settings.show_vertical_cursor then
                local _, dist_target = get_closest_edge(owner_data.id)
                if dist_target then
                    local c = colors.White
                    for _, mv in ipairs(sorted) do
                        if dist_target <= (mv.ar / 100.0) + 0.0000001 then 
                            c = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                            break 
                        end
                    end
                    local x = get_screen_x(dist_target)
                    if x then draw_thick_line(x, y_min, x, y_max, scaled_thickness, c) end
                end
            end
            return
        end
    end

    local limits = get_player_limits(owner_data.id, owner_data)
    if not limits then return end
    local sorted = get_sorted_thresholds(limits)
    
    local _, screen_h = get_dynamic_screen_size()
    local y_min, y_max = 0, screen_h
    if settings.vertical_mode == VMODE_TOP_HALF then y_max = screen_h / 2
    elseif settings.vertical_mode == VMODE_BOTTOM_HALF then y_min = screen_h / 2 end
    
    local dir = 1; if target_data.world_x < owner_data.world_x then dir = -1 end
    local origin_x = owner_data.world_x + (config.marker_origin_shift * dir)
    local scaled_thickness = config.marker_thickness * scale_factor
    local function get_screen_x(dist_val)
        local s = world_to_screen_optimized(origin_x + (dist_val * dir), 1.0, 0)
        return s and s.x or nil
    end

    if settings.fill_bg then
        local prev_x = get_screen_x(0)
        for _, zone in ipairs(sorted) do
            local cur_x = get_screen_x(zone.dist)
            if prev_x and cur_x then draw.filled_quad(prev_x, y_min, cur_x, y_min, cur_x, y_max, prev_x, y_max, zone.fill) end
            prev_x = cur_x
        end
        local xEnd = get_screen_x(sorted[#sorted].dist + 50.0)
        if prev_x and xEnd then draw.filled_quad(prev_x, y_min, xEnd, y_min, xEnd, y_max, prev_x, y_max, get_dynamic_color(colors.Green)) end
    end
    
    if settings.show_markers then
        for _, zone in ipairs(sorted) do
            local x = get_screen_x(zone.dist)
            if x then draw.line(x, y_min, x, y_max, zone.color, scaled_thickness) end
        end
    end
    
    if settings.show_vertical_cursor then
        local _, dist_target = get_closest_edge(owner_data.id)
        if dist_target then
            local c = colors.Green
            for _, zone in ipairs(sorted) do
                if dist_target <= zone.dist + 0.0000001 then c = zone.color; break end
            end
            local x = get_screen_x(dist_target)
            if x then draw_thick_line(x, y_min, x, y_max, scaled_thickness, c) end
        end
    end
end
local function draw_debug_values(cache, opponent_cache, p_idx)
    if not cache.valid or not opponent_cache.valid then return end
    local current_dist = math.abs(cache.world_x - opponent_cache.world_x) * 100
    local _, zone_dist = get_closest_edge(cache.id)
    local z_dist_val = (zone_dist or 0) * 100
    
    local frames = jump_data_store[cache.real_name]
    local lock = lock_states[p_idx]

    imgui.text_colored(string.format("DEBUG %s (ID:%d):", cache.real_name, p_idx), COL_CYAN)
    
    if lock then
        local status_color = lock.active and COL_GREEN or COL_GREY
        imgui.text_colored(string.format("Lock Active: %s", tostring(lock.active)), status_color)
        imgui.text_colored(string.format("Live Abs Range: %.4f", lock.current_reach * 100), COL_CYAN) 
    end
    
    imgui.separator()
    imgui.text("-- CROSSUP DATA --")
    imgui.text(string.format("Center Dist: %.4f", current_dist))
    if frames then
        local st = frames.cross_up_st or 0; local cr = frames.cross_up_cr or 0
        imgui.text(string.format("vs ST: %.4f | vs CR: %.4f", st, cr))
    else imgui.text("No Jump Data") end

    imgui.separator()
    imgui.text("-- ZONE DATA --")
    imgui.text(string.format("Edge Dist: %.4f", z_dist_val))
    local limits = get_player_limits(p_idx, cache)
    if limits then
        imgui.text(string.format("R:%.1f | O:%.1f | Y:%.1f", limits.low*100, limits.red*100, limits.yellow*100))
    else imgui.text("Using Fallback Limits") end
    
    imgui.separator()
end

local vmode_names = { "Distance Only", "Top Half", "Bottom Half", "Full Screen", "On Head", "On Root", "OFF", "CUSTOM" }

local p1_transient_timer, p2_transient_timer = 0, 0
local p1_transient_text, p2_transient_text = "", ""

local function trigger_transient(pi, vmode, adv)
    local text = ""
    
    -- 0. OFF
    if vmode == 7 then 
        text = "0. OFF"
    -- 13. CUSTOM
    elseif vmode == 8 then 
        text = "13. CUSTOM " .. (adv and "(ADVANCED)" or "(NORMAL)")
    -- 1-6 NORMAL / 7-12 ADVANCED
    else
        local num = vmode
        if adv then num = num + 6 end
        
        local prefix = adv and "ADVANCED " or "NORMAL "
        local m_name = vmode_names[vmode] and string.upper(vmode_names[vmode]) or "UNKNOWN"
        
        text = tostring(num) .. ". " .. prefix .. m_name
    end

    if pi == 0 then 
        p1_transient_text = text; p1_transient_timer = 60
    else 
        p2_transient_text = text; p2_transient_timer = 60 
    end
end

local function draw_pos_radios(id_suffix, current_mode)
    local new_mode = current_mode
    local has_changed = false
    imgui.text("POSITION")
    local c1, v1 = imgui.checkbox("Head##h" .. id_suffix, current_mode == 1)
    if c1 and v1 then new_mode = 1; has_changed = true end
    imgui.same_line()
    local c2, v2 = imgui.checkbox("Root##r" .. id_suffix, current_mode == 2)
    if c2 and v2 then new_mode = 2; has_changed = true end
    imgui.same_line()
    local c3, v3 = imgui.checkbox("Fixed##f" .. id_suffix, current_mode == 3)
    if c3 and v3 then new_mode = 3; has_changed = true end
    imgui.same_line()
    local c4, v4 = imgui.checkbox("Cursor##c" .. id_suffix, current_mode == 4)
    if c4 and v4 then new_mode = 4; has_changed = true end
    return has_changed, new_mode
end

local function draw_advanced_moves_menu(pi, rname, cdata)
    local lbl = string.format("-- DISPLAYED MOVES ##adv%d", pi)
    if styled_tree_node(lbl, COL_YELLOW) then
        -- Build merged move list (base + variants)
        local all_sets = {}
        if cdata and cdata.moves and #cdata.moves > 0 then
            all_sets[#all_sets + 1] = { name = rname, moves = cdata.moves }
        end
        local clean = rname:gsub("%-", "")
        for key, vdata in pairs(advanced_data) do
            if key ~= rname and key:sub(1, #clean + 1) == clean .. "_" and vdata.moves and #vdata.moves > 0 then
                all_sets[#all_sets + 1] = { name = key, moves = vdata.moves }
            end
        end

        if #all_sets == 0 then
            imgui.text_colored("(no moves logged)", COL_GREY)
        else
            local prefs = get_char_prefs(pi, rname)
            local ar_min, ar_max = get_ar_range(pi, rname)
            local max_ar_per_gb_per_set = {}
            for si, s in ipairs(all_sets) do
                max_ar_per_gb_per_set[si] = {}
                for _, entry in ipairs(s.moves) do
                    local gb = entry.guard_bit or 0
                    if gb > 0 then
                        if not max_ar_per_gb_per_set[si][gb] or entry.ar > max_ar_per_gb_per_set[si][gb] then
                            max_ar_per_gb_per_set[si][gb] = entry.ar
                        end
                    end
                end
            end

            if imgui.button("Show All##"..pi) then
                for _, s in ipairs(all_sets) do
                    for _, mv in ipairs(s.moves) do set_move_visible(pi, s.name, mv.input, true) end
                end
            end
            imgui.same_line()
            if imgui.button("Hide All##"..pi) then
                for _, s in ipairs(all_sets) do
                    for _, mv in ipairs(s.moves) do set_move_visible(pi, s.name, mv.input, false) end
                end
            end
            imgui.same_line()
            if imgui.button("Max Only##"..pi) then
                for si, s in ipairs(all_sets) do
                    local set_max = max_ar_per_gb_per_set[si]
                    for _, mv in ipairs(s.moves) do
                        local gb_val = mv.guard_bit or 0
                        if gb_val > 0 and mv.ar == set_max[gb_val] then
                            set_move_visible(pi, s.name, mv.input, true)
                        else
                            set_move_visible(pi, s.name, mv.input, false)
                        end
                    end
                end
            end
            imgui.separator()

            imgui.separator()

            for si, s in ipairs(all_sets) do
                local set_max = max_ar_per_gb_per_set[si]
                if #all_sets > 1 then
                    imgui.spacing()
                    imgui.text_colored("-- " .. s.name .. " --", COL_CYAN)
                end
                for _, mv in ipairs(s.moves) do
                    local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                    local tag = ""
                    if prefs.red and prefs.red.input == mv.input then tag = " [O]" end
                    if prefs.low and prefs.low.input == mv.input then tag = tag .. " [R]" end

                    local gb_val = mv.guard_bit or 0
                    local gb_name = get_guard_type_name(gb_val)
                    local is_max_for_gb = (gb_val > 0 and mv.ar == set_max[gb_val])

                    local visible = is_move_visible(pi, s.name, mv.input)
                    local chk_changed, chk_new = imgui.checkbox(
                        string.format("%-8s %.5f %s [%s]##chk_%s_%s_%d", input_to_arrows(mv.input), mv.ar, tag, gb_name, s.name, mv.input, pi),
                        visible)

                    if chk_changed then
                        set_move_visible(pi, s.name, mv.input, chk_new)
                    end

                    imgui.same_line()
                    imgui.text_colored("[#]", visible and col or 0xFF444444)

                    imgui.same_line()
                    imgui.push_style_color(21, 0xFF994400) -- Button
                    imgui.push_style_color(22, 0xFFBB6600) -- Hovered
                    imgui.push_style_color(23, 0xFFDD8800) -- Active
                    if imgui.button("Teleport##tp_adv_" .. pi .. "_" .. s.name .. "_" .. mv.input) then apply_teleport_exact(pi, mv.ar) end
                    imgui.pop_style_color(3)
                    if is_max_for_gb then
                        imgui.same_line()
                        imgui.text_colored("MAX " .. gb_name, COL_GOLD)
                    end
                end
            end
        end
        imgui.tree_pop()
    end
end



-- Store last mouse click coordinates
local debug_mouse_x, debug_mouse_y = 0.0, 0.0

local function get_p_cycle(has_custom)
    local c = {}
    for i=1,6 do table.insert(c, {v=i, a=false}) end
    if has_custom then table.insert(c, {v=8, a=false}) end
    for i=1,6 do table.insert(c, {v=i, a=true}) end
    if has_custom then table.insert(c, {v=8, a=true}) end
    table.insert(c, {v=7, a=false})
    return c
end

local function get_next_cycle(vmode, adv, has_custom)
    local c = get_p_cycle(has_custom)
    local cur = #c
    if vmode == 7 then cur = #c else
        for i=1,#c-1 do
            if c[i].v == vmode and c[i].a == adv then cur = i; break end
        end
    end
    local nxt = cur + 1; if nxt > #c then nxt = 1 end
    return c[nxt].v, c[nxt].a
end

-- Apply display flags for a given vertical mode
local function apply_mode_flags(p, v)
    if v == 1 then
        config[p.."_fill_bg"] = false; config[p.."_show_markers"] = false; config[p.."_show_vertical_cursor"] = false
        config[p.."_show_horizontal_lines"] = true; config[p.."_show_numbers"] = true
        config[p.."_opp_zone_show"] = true; config[p.."_crossup_show"] = true
    elseif v == 5 or v == 6 then
        config[p.."_fill_bg"] = false; config[p.."_show_markers"] = false; config[p.."_show_vertical_cursor"] = false
        config[p.."_show_horizontal_lines"] = false; config[p.."_show_numbers"] = false
    elseif v == 7 then
        config[p.."_fill_bg"] = false; config[p.."_show_markers"] = false; config[p.."_show_vertical_cursor"] = false
        config[p.."_show_horizontal_lines"] = false; config[p.."_show_numbers"] = false
        config[p.."_opp_zone_show"] = false; config[p.."_crossup_show"] = false
    elseif v == 8 then
        config[p.."_fill_bg"] = config[p.."_custom_fill_bg"]; config[p.."_show_markers"] = config[p.."_custom_show_markers"]
        config[p.."_show_vertical_cursor"] = config[p.."_custom_show_cursor"]
        config[p.."_show_horizontal_lines"] = config[p.."_custom_show_hz"]; config[p.."_show_numbers"] = config[p.."_custom_show_numbers"]
        config[p.."_opp_zone_show"] = config[p.."_custom_show_text"]; config[p.."_crossup_show"] = config[p.."_custom_show_text"]
    elseif v >= 2 and v <= 4 then
        config[p.."_fill_bg"] = true; config[p.."_show_markers"] = true; config[p.."_show_vertical_cursor"] = true
        config[p.."_show_horizontal_lines"] = true; config[p.."_show_numbers"] = true
        config[p.."_opp_zone_show"] = true; config[p.."_crossup_show"] = true
    end
    config[p.."_show_all"] = (v ~= 7)
end

local function cycle_player_display(p)
    local cur_v = config[p.."_vertical_mode"]
    local next_v, next_a
    if not config.expert_mode_enabled then
        -- Normal: NORMAL(1) ↔ OFF(7)
        next_v = (cur_v == 1) and 7 or 1
        next_a = false
    else
        -- Expert: toggle between Distance Only(1) and OFF(7)
        if cur_v == 7 then
            next_v = 1; next_a = true
        else
            next_v = 7; next_a = false
        end
    end
    config[p.."_vertical_mode"] = next_v; config[p.."_advanced_mode"] = next_a
    if config.expert_mode_enabled then
        -- Expert: don't reset flags, just toggle show_all
        config[p.."_show_all"] = (next_v ~= 7)
    else
        apply_mode_flags(p, next_v)
    end

    local pi = (p == "p1") and 0 or 1
    save_settings()
end

local function draw_config_ui()
    -- ==========================================
    -- 0. HELP & INFO
    -- ==========================================
    if styled_header("--- HELP & INFO ---", UI_THEME.hdr_info) then
        imgui.text("SHORTCUTS (Keyboard / Gamepad):")
        
        if not config.expert_mode_enabled then
            imgui.text("- [5] or (Func) + LB/L1 : Toggle P1 (Normal / OFF)")
            imgui.text("- [6] or (Func) + RB/R1 : Toggle P2 (Normal / OFF)")
        else
            imgui.text("- [5] or (Func) + LB/L1 : Toggle P1 (ON / OFF)")
            imgui.text("- [6] or (Func) + RB/R1 : Toggle P2 (ON / OFF)")
        end
        
        imgui.text("- [7] or (Func) + Triangle/Y : Toggle UI Window")
        
        if _G.TrainingFuncButton ~= nil then
            imgui.text_colored("* (Func) button is defined in Training Script Manager (Default: Select)", COL_GREY)
        else
            imgui.separator()
            if is_binding_mode then
                imgui.text_colored("-- PRESS ANY GAMEPAD BUTTON TO BIND FUNC --", 0xFF00FFFF)
            else
                local btn_name = "NOT SET"
                if config.func_button then
                    btn_name = "ID: " .. tostring(config.func_button)
                    if config.func_button == 16384 then btn_name = "SELECT / BACK" end
                    if config.func_button == 8192 then btn_name = "R3 / RS" end
                    if config.func_button == 4096 then btn_name = "L3 / LS" end
                end
                
                imgui.text("Current Func Button: " .. btn_name)
                imgui.same_line()
                if imgui.button("CHANGE FUNC BUTTON") then
                    is_binding_mode = true
                    last_input_mask = 0 
                end
            end
        end
        imgui.spacing()
    end -- Fin du bloc "HELP & INFO"

        -- ==========================================
        -- PLAYER OPTIONS (Normal Mode)
        -- ==========================================
        if not config.expert_mode_enabled then
            local function draw_player_options_normal(pi, cache, p_prefix, hdr_color)
                local rname = cache.valid and cache.adv_name or get_real_name(detected_infos[pi] and detected_infos[pi].name or "?")
                -- Always use base character name for menu (not stance variant)
                local base_display = cache.valid and (esf_names_map[cache.real_name] or cache.real_name) or get_real_name(detected_infos[pi] and detected_infos[pi].name or "?")
                local header_label = string.format("--- %s (P%d) OPTIONS ---", base_display, pi + 1)
                if styled_header(header_label, hdr_color) then
                    -- Display toggle
                    local is_on = config[p_prefix .. "_vertical_mode"] ~= 7
                    local c_disp, v_disp = imgui.checkbox("Display P" .. (pi+1) .. " Distance##disp_" .. p_prefix, is_on)
                    if c_disp then cycle_player_display(p_prefix) end

                    -- Build list of move sets: base + variants
                    local base_name = base_display
                    local move_sets = {}
                    local base_cdata = advanced_data[base_name]
                    if base_cdata and base_cdata.moves and #base_cdata.moves > 0 then
                        move_sets[#move_sets + 1] = { name = base_name, label = base_name, cdata = base_cdata }
                    end
                    local clean_base = base_name:gsub("%-", "")
                    for key, vdata in pairs(advanced_data) do
                        if key ~= base_name and key:sub(1, #clean_base + 1) == clean_base .. "_" and vdata.moves and #vdata.moves > 0 then
                            local short = key:match("_(.+)$") or key
                            move_sets[#move_sets + 1] = { name = key, label = short, cdata = vdata }
                        end
                    end

                    if #move_sets > 0 then
                        -- Draw 3 lines (red/orange/yellow) per set
                        for si, ms in ipairs(move_sets) do
                            local prefs = get_char_prefs(pi, ms.name)
                            local cd = ms.cdata
                            local suffix = #move_sets > 1 and (" " .. ms.label) or ""
                            local uid = p_prefix .. "_" .. ms.name

                            local red_idx, low_idx = 1, 1
                            local active_red = (prefs.red and prefs.red ~= false) and prefs.red or nil
                            local active_low = (prefs.low and prefs.low ~= false) and prefs.low or nil
                            for i, mv in ipairs(cd.moves) do
                                if active_red and active_red.input == mv.input and red_idx == 1 then red_idx = i + 1 end
                                if active_low and active_low.input == mv.input and low_idx == 1 then low_idx = i + 1 end
                            end

                            if #move_sets > 1 then
                                imgui.spacing()
                                imgui.text_colored("-- " .. ms.label .. " --", COL_CYAN)
                            else
                                imgui.spacing()
                            end

                            -- Red Zone
                            local chg_l, nv_l = colored_move_dropdown("##" .. uid .. "_red", low_idx, cd.moves, 200)
                            imgui.same_line(); imgui.text_colored("Red Zone" .. suffix, COL_RED)
                            imgui.same_line()
                            if imgui.button("TELEPORT##tp_red_" .. uid) then
                                if low_idx > 1 then apply_teleport_exact(pi, cd.moves[low_idx-1].ar) end
                            end
                            if chg_l then
                                if nv_l == 1 then prefs.low = false else prefs.low = { input = cd.moves[nv_l-1].input, ar = cd.moves[nv_l-1].ar } end
                                save_advanced_prefs(); load_advanced_data()
                            end

                            -- Orange Zone
                            local chg_r, nv_r = colored_move_dropdown("##" .. uid .. "_org", red_idx, cd.moves, 200)
                            imgui.same_line(); imgui.text_colored("Orange Zone" .. suffix, COL_ORANGE)
                            imgui.same_line()
                            if imgui.button("TELEPORT##tp_org_" .. uid) then
                                if red_idx > 1 then apply_teleport_exact(pi, cd.moves[red_idx-1].ar) end
                            end
                            if chg_r then
                                if nv_r == 1 then prefs.red = false else prefs.red = { input = cd.moves[nv_r-1].input, ar = cd.moves[nv_r-1].ar } end
                                save_advanced_prefs(); load_advanced_data()
                            end

                            -- Yellow Offset
                            local y_off = prefs.yellow_offset or 50
                            imgui.push_item_width(150)
                            local chg_y, nv_y = imgui.drag_int("##" .. uid .. "_yel", y_off, 1, 0, 300)
                            imgui.pop_item_width()
                            imgui.same_line(); imgui.text_colored("Yellow Offset" .. suffix, COL_YELLOW)
                            imgui.same_line()
                            if imgui.button("TELEPORT##tp_yel_" .. uid) then
                                local limits = get_player_limits(pi, cache)
                                if limits and limits.yellow then apply_teleport_exact(pi, limits.yellow * 100.0) end
                            end
                            if chg_y then
                                prefs.yellow_offset = nv_y
                                save_advanced_prefs(); load_advanced_data()
                            end
                        end
                    else
                        imgui.text_colored("No attack data for " .. rname, COL_GREY)
                    end
                end
            end

            draw_player_options_normal(0, p1_cache, "p1", UI_THEME.hdr_session_1)
            draw_player_options_normal(1, p2_cache, "p2", UI_THEME.hdr_session_2)
        end

        if config.expert_mode_enabled then
        -- ==========================================
        -- 1. GLOBAL SETTINGS (Font, Thickness, Attack Lock)
        -- ==========================================
        if styled_header("--- GLOBAL SETTINGS ---", UI_THEME.hdr_rules) then
        local c_fs, v_fs = safe_input_int("Master Font Quality (Px)", config.stats_font_size)
        if c_fs then config.stats_font_size = v_fs; save_settings(); try_load_font() end

        local c_fns, v_fns = safe_input_int("Numbers Font Size (Px)", config.number_font_size or 60)
        if c_fns then config.number_font_size = v_fns; save_settings(); try_load_font() end

        local c_us, v_us = imgui.drag_float("Floating UI Scale", config.ui_scale or 1.25, 0.05, 0.5, 4.0)
        if c_us then config.ui_scale = v_us; save_settings(); try_load_font() end

        local changed_lock, new_lock = imgui.checkbox("Auto-Lock on Attack (Freeze during active frames)", config.use_attack_lock)
        if changed_lock then config.use_attack_lock = new_lock; save_settings() end

        local changed_op, new_op = imgui.drag_int("Zone Opacity (%)", config.zone_opacity, 1, 0, 100)
        if changed_op then config.zone_opacity = new_op; save_settings() end
		
		local c_is, v_is = imgui.drag_float("Icon Scale", config.icon_scale or 1.0, 0.05, 0.5, 3.0)
        if c_is then config.icon_scale = v_is; save_settings() end

        local c_ioy, v_ioy = imgui.drag_float("Icon Y Offset", config.icon_offset_y or 0.0, 1.0, -100.0, 100.0)
        if c_ioy then config.icon_offset_y = v_ioy; save_settings() end
    end

	
    -- ==========================================
    -- 3. PLAYER 1 SETTINGS
    -- ==========================================
    local changed = false; local c = false
    local p1_rname_expert = p1_cache.valid and (esf_names_map[p1_cache.real_name] or p1_cache.real_name) or "P1"
    if styled_header(string.format("--- %s (P1) OPTIONS ---", p1_rname_expert), UI_THEME.hdr_session_1) then
--        c, config.p1_show_all = imgui.checkbox("SHOW ALL P1 OVERLAYS##p1_master", config.p1_show_all); if c then changed = true end
--        imgui.separator()
        
        config.p1_advanced_mode = true
        local rname_p1 = p1_rname_expert
        local cdata_p1 = advanced_data[rname_p1]
        if cdata_p1 then
            draw_advanced_moves_menu(0, rname_p1, cdata_p1)
        end


        if styled_tree_node("-- CUSTOMIZE OVERLAY##p1", COL_YELLOW) then
            local changed_any = false
            c, config.p1_fill_bg = imgui.checkbox("Zones##p1", config.p1_fill_bg); if c then changed_any = true end; imgui.same_line()
            c, config.p1_show_markers = imgui.checkbox("Lines##p1", config.p1_show_markers); if c then changed_any = true end; imgui.same_line()
            c, config.p1_show_vertical_cursor = imgui.checkbox("Cursor##p1", config.p1_show_vertical_cursor); if c then changed_any = true end; imgui.same_line()
            c, config.p1_show_horizontal_lines = imgui.checkbox("Distance##p1", config.p1_show_horizontal_lines); if c then changed_any = true end; imgui.same_line()
            local c_num1, v_num1 = imgui.checkbox("Numbers##p1", config.p1_show_numbers); if c_num1 then config.p1_show_numbers = v_num1; changed_any = true end; imgui.same_line()
            local c_txt1, v_txt1 = imgui.checkbox("Text ##p1", config.p1_opp_zone_show)
            if c_txt1 then config.p1_opp_zone_show = v_txt1; changed_any = true end
            
            -- Options indépendantes du Custom
            local c_col1, v_col1 = imgui.checkbox("Color Text##p1", config.p1_opp_zone_color_text)
            if c_col1 then config.p1_opp_zone_color_text = v_col1; config.p1_crossup_color_text = v_col1; changed = true end
            imgui.same_line()
            local c_cu1, v_cu1 = imgui.checkbox("CrossUp Text##p1", config.p1_crossup_show)
            if c_cu1 then config.p1_crossup_show = v_cu1; changed = true end
            imgui.same_line()
            local c_arc1, v_arc1 = imgui.checkbox("CrossUp Arch##p1", config.p1_show_jump_arc)
            if c_arc1 then config.p1_show_jump_arc = v_arc1; changed = true end

            if changed_any then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()
	end

    -- ==========================================
    -- 4. PLAYER 2 SETTINGS
    -- ==========================================
    local p2_rname_expert = p2_cache.valid and (esf_names_map[p2_cache.real_name] or p2_cache.real_name) or "P2"
    if styled_header(string.format("--- %s (P2) OPTIONS ---", p2_rname_expert), UI_THEME.hdr_session_2) then
        config.p2_advanced_mode = true
        local rname_p2 = p2_rname_expert
        local cdata_p2 = advanced_data[rname_p2]
        if cdata_p2 then
            draw_advanced_moves_menu(1, rname_p2, cdata_p2)
        end

        if styled_tree_node("-- CUSTOMIZE OVERLAY##p2", COL_YELLOW) then
            local changed_any = false
            c, config.p2_fill_bg = imgui.checkbox("Zones##p2", config.p2_fill_bg); if c then changed_any = true end; imgui.same_line()
            c, config.p2_show_markers = imgui.checkbox("Lines##p2", config.p2_show_markers); if c then changed_any = true end; imgui.same_line()
            c, config.p2_show_vertical_cursor = imgui.checkbox("Cursor##p2", config.p2_show_vertical_cursor); if c then changed_any = true end; imgui.same_line()
            c, config.p2_show_horizontal_lines = imgui.checkbox("Distance##p2", config.p2_show_horizontal_lines); if c then changed_any = true end; imgui.same_line()
            local c_num2, v_num2 = imgui.checkbox("Numbers##p2", config.p2_show_numbers); if c_num2 then config.p2_show_numbers = v_num2; changed_any = true end; imgui.same_line()
            local c_txt2, v_txt2 = imgui.checkbox("Text ##p2", config.p2_opp_zone_show)
            if c_txt2 then config.p2_opp_zone_show = v_txt2; changed_any = true end
            
            -- Options indépendantes du Custom
            local c_col2, v_col2 = imgui.checkbox("Color Text##p2", config.p2_opp_zone_color_text)
            if c_col2 then config.p2_opp_zone_color_text = v_col2; config.p2_crossup_color_text = v_col2; changed = true end
            imgui.same_line()
            local c_cu2, v_cu2 = imgui.checkbox("CrossUp Text##p2", config.p2_crossup_show)
            if c_cu2 then config.p2_crossup_show = v_cu2; changed = true end
            imgui.same_line()
            local c_arc2, v_arc2 = imgui.checkbox("CrossUp Arch##p2", config.p2_show_jump_arc)
            if c_arc2 then config.p2_show_jump_arc = v_arc2; changed = true end

            local act_v2 = config.p2_vertical_mode
            if act_v2 == 8 then act_v2 = config.p2_custom_base_mode or 1 end
            -- if act_v2 >= 1 and act_v2 <= 4 and config.p2_show_numbers then
                -- local c_ny2, v_ny2 = safe_input_float("Numbers Y Offset (Mode "..act_v2..")##p2", config["p2_number_off_y_"..act_v2] or 25.0)
                -- if c_ny2 then config["p2_number_off_y_"..act_v2] = v_ny2; changed = true end
            -- end

            if changed_any then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

	end
    if changed then save_settings() end

    -- ==========================================
    -- 5. DEBUG VALUES (Live)
    -- ==========================================
    if styled_header("--- DEBUG VALUES (Live) ---", UI_THEME.hdr_debug) then
        -- Capture left mouse click (0) and update coordinates
        if imgui.is_mouse_clicked(0) then
            local mouse_pos = imgui.get_mouse()
            debug_mouse_x = mouse_pos.x
            debug_mouse_y = mouse_pos.y
        end
        
        imgui.text_colored(string.format("Last Click Pos: X: %.1f | Y: %.1f", debug_mouse_x, debug_mouse_y), COL_CYAN)
        imgui.separator()

        imgui.text_colored("[LOAD STATUS]", COL_GREY)
        imgui.text("Dist Config: "); imgui.same_line(); imgui.text_colored(debug_dist_status, debug_dist_color)
        imgui.text("Jump File: "); imgui.same_line(); imgui.text_colored(debug_jump_status, debug_jump_color)
        imgui.text("Font Status: " .. custom_font.status)
        imgui.separator()

        draw_debug_values(p1_cache, p2_cache, 0)
        draw_debug_values(p2_cache, p1_cache, 1)

        imgui.separator()
        imgui.text_colored("[BOX FILTERS — Distance Calculation]", COL_YELLOW)
        local bc = false
        local c1, v1 = imgui.checkbox("Hurtbox", config.box_use_hurtbox); if c1 then config.box_use_hurtbox = v1; bc = true end
        imgui.same_line()
        local c2, v2 = imgui.checkbox("Hurtbox Invuln", config.box_use_hurtbox_invuln); if c2 then config.box_use_hurtbox_invuln = v2; bc = true end
        local c3, v3 = imgui.checkbox("Pushbox", config.box_use_pushbox); if c3 then config.box_use_pushbox = v3; bc = true end
        imgui.same_line()
        local c4, v4 = imgui.checkbox("Hitbox", config.box_use_hitbox); if c4 then config.box_use_hitbox = v4; bc = true end
        local c5, v5 = imgui.checkbox("Throwbox", config.box_use_throwbox); if c5 then config.box_use_throwbox = v5; bc = true end
        imgui.same_line()
        local c6, v6 = imgui.checkbox("Clash", config.box_use_clash); if c6 then config.box_use_clash = v6; bc = true end
        local c7, v7 = imgui.checkbox("Proximity", config.box_use_proximity); if c7 then config.box_use_proximity = v7; bc = true end
        if bc then save_settings() end

        imgui.separator()
        imgui.text_colored("[LIVE BOX DUMP — P1]", COL_CYAN)
        pcall(function()
            local gB = sdk.find_type_definition("gBattle")
            if not gB then return end
            local sP = gB:get_field("Player"):get_data(nil)
            if not sP or not sP.mcPlayer or not sP.mcPlayer[0] then return end
            local p = sP.mcPlayer[0]
            if not p.mpActParam or not p.mpActParam.Collision then return end
            local col = p.mpActParam.Collision
            if col.Infos and col.Infos._items then
                for j, r in pairs(col.Infos._items) do
                    if r and r.OffsetX and r.OffsetX.v then
                        local has_HitPos = r:get_field("HitPos") ~= nil
                        local has_Attr = r:get_field("Attr") ~= nil
                        local has_HitNo = r:get_field("HitNo") ~= nil
                        local label = "?"
                        if has_HitPos then
                            local tf = r.TypeFlag or 0
                            local pb = r.PoseBit or 0
                            local cf = r.CondFlag or 0
                            local gb = r.GuardBit or 0
                            if tf > 0 then label = "HITBOX"
                            elseif (tf == 0 and pb > 0) or cf == 0x2C0 then label = "THROWBOX"
                            elseif gb == 0 then label = "CLASH"
                            else label = "PROXIMITY" end
                        elseif has_Attr then label = "PUSHBOX"
                        elseif has_HitNo then
                            local tp = r.Type or 0
                            if tp == 1 or tp == 2 then label = "HURTBOX_INV" else label = "HURTBOX" end
                        end
                        local ox = r.OffsetX.v / 6553600.0
                        local sx = r.SizeX.v / 6553600.0
                        imgui.text(string.format("  [%d] %-12s X:%.3f SX:%.3f", j, label, ox, sx))
                    end
                end
            end
        end)
    end
    
    end -- FIN DU BLOC "if not config.simple_mode_enabled"
end

-- =========================================================
-- [EVENTS]
-- =========================================================

if config.p1_advanced_mode or config.p2_advanced_mode then load_advanced_data() end

-- =========================================================
-- [SHORTCUTS SYSTEM]
-- =========================================================
local last_input_mask = 0
local KB_5 = 0x35
local KB_6 = 0x36
local KB_7 = 0x37
local last_kb_state = { [KB_5] = false, [KB_6] = false, [KB_7] = false }
local PAD_LB = 256
local PAD_RB = 1024
local PAD_TRIANGLE = 16

local function get_hardware_pad_mask()
    local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
    local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
    if not gamepad_manager then return 0 end
    local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
    if not devices then return 0 end
    local count = devices:call("get_Count") or 0
    for i = 0, count - 1 do
        local pad = devices:call("get_Item", i)
        if pad then
            local b = pad:call("get_Button") or 0; if b > 0 then return b end
        end
    end
    return 0
end

local function is_kb_down(vk)
    local ok, result = pcall(function() return reframework:is_key_down(vk) end)
    return ok and result
end

local function handle_viewer_shortcuts()
    local active_buttons = get_hardware_pad_mask()
    local kb_now = { [KB_5] = is_kb_down(KB_5), [KB_6] = is_kb_down(KB_6), [KB_7] = is_kb_down(KB_7) }
    local function kb_pressed(vk) return kb_now[vk] and not last_kb_state[vk] end

    if is_binding_mode then
        if active_buttons ~= 0 and last_input_mask == 0 then
            config.func_button = active_buttons
            save_settings()
            is_binding_mode = false
        end
        last_input_mask = active_buttons
        last_kb_state = kb_now
        return
    end

    local func_btn = _G.TrainingFuncButton or config.func_button
    local is_func_held = false
    if func_btn and func_btn > 0 then
        is_func_held = ((active_buttons & func_btn) == func_btn)
    end

    local function is_pressed(target_mask)
        if not is_func_held then return false end
        return ((active_buttons & target_mask) == target_mask) and not ((last_input_mask & target_mask) == target_mask)
    end

    local changed = false

    -- Cycle P1 Modes
    if is_pressed(PAD_LB) or kb_pressed(KB_5) then
        cycle_player_display("p1"); changed = true
    end

    -- Cycle P2 Modes
    if is_pressed(PAD_RB) or kb_pressed(KB_6) then
        cycle_player_display("p2"); changed = true
    end

    if changed then save_settings() end
    last_input_mask = active_buttons; last_kb_state = kb_now
end

local _dv_last_window_rect = nil -- saved from on_draw_ui, used next frame

re.on_frame(function()
    handle_viewer_shortcuts()

    -- Build local rect list from all sources (independent of frame ordering)
    local all_rects = {}
    -- From SharedUI floating bars
    if _G.FloatingRects then for _, r in ipairs(_G.FloatingRects) do all_rects[#all_rects + 1] = r end end
    -- From DV settings window (last frame)
    if _dv_last_window_rect then all_rects[#all_rects + 1] = _dv_last_window_rect end
    -- From REF menu (last frame)
    local ref_open = false
    pcall(function() ref_open = reframework:is_drawing_ui() end)
    if not ref_open then _G._ref_menu_rect = nil end
    if _G._ref_menu_rect then all_rects[#all_rects + 1] = _G._ref_menu_rect end

    -- Check if a point overlaps any rect
    local function point_in_any_rect(px, py)
        for _, r in ipairs(all_rects) do
            if px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h then
                return true
            end
        end
        return false
    end

    local function is_overlapping_floating(display)
        if not display or not display.root_screen_pos then return false end
        return point_in_any_rect(display.root_screen_pos.x, display.root_screen_pos.y)
    end

    if gBattle == nil then gBattle = sdk.find_type_definition("gBattle") end; if gBattle == nil then return end

    -- Hide everything when session recap is displayed
    if _G.SessionRecapVisible then return end

    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pause_bit = pm:get_field("_CurrentPauseTypeBit")
		  if pause_bit ~= 64 and pause_bit ~= 2112 then return end
    end

    local should_update = true
    local sGame = gBattle:get_field("Game"):get_data(nil)
    if sGame then
        local success, current_timer = pcall(function() return sGame.stage_timer end)
        if success and current_timer ~= nil then
            if current_timer == last_stage_timer then
                frozen_frames = frozen_frames + 1
            else
                last_stage_timer = current_timer; frozen_frames = 0
            end
            if frozen_frames > 5 then should_update = false end
        end
    end

    local sw, sh = get_dynamic_screen_size()
    if res_watcher.last_w == 0 then res_watcher.last_w = sw; res_watcher.last_h = sh; try_load_font() end
    if sw ~= res_watcher.last_w or sh ~= res_watcher.last_h then 
        res_watcher.cooldown = 30; res_watcher.last_w = sw; res_watcher.last_h = sh 
    end
    if res_watcher.cooldown > 0 then 
        res_watcher.cooldown = res_watcher.cooldown - 1
        if res_watcher.cooldown == 0 then try_load_font() end 
    end

    if should_update then
        update_player_cache(0, p1_cache)
        update_player_cache(1, p2_cache)
        _G.DV_PlayerAdvName = { [0] = p1_cache.adv_name, [1] = p2_cache.adv_name }
        update_combat_distances() -- <<< NOTRE DÉTECTION UNIQUE

		-- [SSOT] Détection unique des zones stockée dans le cache
        if p1_cache.valid and p2_cache.valid then
            p1_cache.active_zone = evaluate_player_zone(0, p1_cache, p2_cache)
            p2_cache.active_zone = evaluate_player_zone(1, p2_cache, p1_cache)
        end

        -- [TELEPORT RETRY LOGIC] Ensures strict adherence to target distance
        if pending_tp.active and p1_cache.valid and p2_cache.valid then
            local current_c2c = math.abs(p1_cache.world_x - p2_cache.world_x) * 100.0
            if math.abs(current_c2c - pending_tp.expected_c2c) > 0.5 then -- > 0.5 cm error tolerance
                pending_tp.attempts = pending_tp.attempts + 1
                if pending_tp.attempts < 15 then -- Max 15 frames retry (0.25s)
                    apply_teleport_exact(pending_tp.attacker_id, pending_tp.distance, true)
                else
                    pending_tp.active = false -- Abort to prevent hard soft-lock
                end
            else
                pending_tp.active = false -- Perfect distance reached
            end
        end

        if config.use_attack_lock then
            process_attack_lock(0, p1_cache)
            process_attack_lock(1, p2_cache)
        else
            if lock_states[0].active then lock_states[0].active = false end
            if lock_states[1].active then lock_states[1].active = false end
        end
    end
    
    local scale_factor = sh / 1080.0
    
    -- Helper: check if point is inside a character's bounding box
    local function check_char_click(mx, my, cache)
        if not cache.valid or not cache.head_screen_pos or not cache.root_screen_pos then return false end
        local top = cache.head_screen_pos.y
        local bot = cache.root_screen_pos.y
        local cx = cache.root_screen_pos.x
        local h = bot - top
        local w = math.abs(h * 0.55) -- Largeur estimée à 55% de la hauteur
        return mx >= (cx - w/2) and mx <= (cx + w/2) and my >= top and my <= bot
    end

    -- [LEFT-CLICK: CYCLE DISPLAY ON CHARACTER] (bloqué quand menu REF ouvert)
    if not ref_open and imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m and not point_in_any_rect(m.x, m.y) then
            if check_char_click(m.x, m.y, p1_cache) then
                cycle_player_display("p1")
            end
            if check_char_click(m.x, m.y, p2_cache) then
                cycle_player_display("p2")
            end
        end
    end

    -- [RIGHT-CLICK ON P1/P2: TOGGLE DEBUG WINDOW] (bloqué quand menu REF ouvert)
    if not ref_open and imgui.is_mouse_clicked(1) then
        local m = imgui.get_mouse()
        if m and not point_in_any_rect(m.x, m.y) then
            if check_char_click(m.x, m.y, p1_cache) or check_char_click(m.x, m.y, p2_cache) then
                config.show_debug_window = not config.show_debug_window
                save_settings()
            end
        end
    end

    local p1_display = nil
    local p2_display = nil
    local numbers_to_draw = {}
    local numbers_to_draw = {}
	
    if p1_cache.valid and p2_cache.valid then
        update_jump_state_logic(0, p1_cache)
        update_jump_state_logic(1, p2_cache)

		p1_display = { id = 0, world_x = p1_cache.world_x, world_y = p1_cache.world_y, real_name = p1_cache.real_name, adv_name = p1_cache.adv_name, act_param = p1_cache.act_param, valid = true, facing_right = p1_cache.facing_right, head_screen_pos = p1_cache.head_screen_pos, root_screen_pos = p1_cache.root_screen_pos }
        p2_display = { id = 1, world_x = p2_cache.world_x, world_y = p2_cache.world_y, real_name = p2_cache.real_name, adv_name = p2_cache.adv_name, act_param = p2_cache.act_param, valid = true, facing_right = p2_cache.facing_right, head_screen_pos = p2_cache.head_screen_pos, root_screen_pos = p2_cache.root_screen_pos }
        
        if config.use_attack_lock then
            if lock_states[0].active then
                 p1_display.world_x = lock_states[0].locked_x
                 p1_display.world_y = lock_states[0].locked_y
                 -- On recalcule la position 2D du texte basée sur la coordonnée gelée
                 p1_display.root_screen_pos = world_to_screen_optimized(lock_states[0].locked_x, lock_states[0].locked_y, 0)
                 if p1_cache.head_world_y then
                     p1_display.head_screen_pos = world_to_screen_optimized(lock_states[0].locked_x, p1_cache.head_world_y, 0)
                 end
            end
            if lock_states[1].active then
                 p2_display.world_x = lock_states[1].locked_x
                 p2_display.world_y = lock_states[1].locked_y
                 -- On recalcule la position 2D du texte basée sur la coordonnée gelée
                 p2_display.root_screen_pos = world_to_screen_optimized(lock_states[1].locked_x, lock_states[1].locked_y, 0)
                 if p2_cache.head_world_y then
                     p2_display.head_screen_pos = world_to_screen_optimized(lock_states[1].locked_x, p2_cache.head_world_y, 0)
                 end
            end
        end
        
        local draw_v_p1 = config.p1_vertical_mode
        if draw_v_p1 == 8 then draw_v_p1 = config.p1_custom_base_mode or 1 end
        if draw_v_p1 > 4 then draw_v_p1 = 4 end
        if config.expert_mode_enabled and draw_v_p1 ~= 7 then draw_v_p1 = 2 end

        local p1_settings = {
            show_horizontal_lines = config.p1_show_horizontal_lines, 
            show_numbers = config.p1_show_numbers,
            color_text = config.p1_opp_zone_color_text,
            number_off_y = config["p1_number_off_y_" .. draw_v_p1] or 25.0,
            line_height = config["p1_line_height_" .. draw_v_p1] or 0.5,
            show_origin_dot = config.p1_show_origin_dot, origin_dot_size = config.p1_origin_dot_size,
            end_marker_size = config.p1_end_marker_size, end_marker_offset_y = config.p1_end_marker_offset_y,
            vertical_mode = draw_v_p1
        }
        
        local draw_v_p2 = config.p2_vertical_mode
        if draw_v_p2 == 8 then draw_v_p2 = config.p2_custom_base_mode or 1 end
        if draw_v_p2 > 4 then draw_v_p2 = 4 end
        if config.expert_mode_enabled and draw_v_p2 ~= 7 then draw_v_p2 = 3 end

        local p2_settings = {
            show_horizontal_lines = config.p2_show_horizontal_lines, 
            show_numbers = config.p2_show_numbers,
            color_text = config.p2_opp_zone_color_text,
            number_off_y = config["p2_number_off_y_" .. draw_v_p2] or 25.0,
            line_height = config["p2_line_height_" .. draw_v_p2] or 0.5,
            show_origin_dot = config.p2_show_origin_dot, origin_dot_size = config.p2_origin_dot_size,
            end_marker_size = config.p2_end_marker_size, end_marker_offset_y = config.p2_end_marker_offset_y,
            vertical_mode = draw_v_p2
        }

        if config.p1_show_all and not is_overlapping_floating(p1_display) then
            draw_spacing_horizontal(p1_display, p2_display, p1_settings, scale_factor, numbers_to_draw)
            draw_jump_arc(0, p1_cache, p2_cache, { show_jump_arc = config.p1_show_jump_arc }, scale_factor)
            draw_vertical_overlay(p1_display, p2_display, {
                show_markers=config.p1_show_markers, fill_bg=config.p1_fill_bg,
                vertical_mode=draw_v_p1, show_vertical_cursor=config.p1_show_vertical_cursor
            }, scale_factor)
        end

        if config.p2_show_all and not is_overlapping_floating(p2_display) then
            draw_spacing_horizontal(p2_display, p1_display, p2_settings, scale_factor, numbers_to_draw)
            draw_jump_arc(1, p2_cache, p1_cache, { show_jump_arc = config.p2_show_jump_arc }, scale_factor)
            draw_vertical_overlay(p2_display, p1_display, {
                show_markers=config.p2_show_markers, fill_bg=config.p2_fill_bg,
                vertical_mode=draw_v_p2, show_vertical_cursor=config.p2_show_vertical_cursor
            }, scale_factor)
        end
    end

    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0)
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    
    local win_flags = 1 | 2 | 4 | 8 | 512 | 786432 | 128

    if imgui.begin_window("CrossUpOverlay", true, win_flags) then
	-- Render vertically stored labels/icons
        if #icons_to_draw > 0 then
            for _, item in ipairs(icons_to_draw) do
                local current_x = item.x
                
                if item.tag and item.tag ~= "" then
                    imgui.set_cursor_pos(Vector2f.new(current_x + 2, item.y + 2))
                    imgui.text_colored(item.tag, 0xFF000000)
                    imgui.set_cursor_pos(Vector2f.new(current_x, item.y))
                    imgui.text_colored(item.tag, item.color)
                    current_x = current_x + imgui.calc_text_size(item.tag).x + 5
                end
                
                if item.raw_input then
                    local icons, strength = parse_input_string(item.raw_input, item.facing_right)
                    
                    local icon_size = math.floor(item.size * (config.icon_scale or 1.0) + 0.5)
                    local y_with_offset = math.floor(item.y + ((config.icon_offset_y or 0.0) * scale_factor) + 0.5)
                    local current_x = math.floor(current_x + 0.5)
                    
                    for _, icon_key in ipairs(icons) do
                        table.insert(d2d_queue, { key = icon_key, x = current_x, y = y_with_offset, size = icon_size })
                        current_x = current_x + icon_size
                    end
                    
                    local icon_letter_gap = 4 -- <<< CHANGE THIS VALUE FOR SPACING (Vertical mode)
                    if #icons > 0 and strength ~= "" then current_x = current_x + icon_letter_gap end
                    
                    if strength ~= "" then
                        local final_y = math.floor(item.y + 0.5)
                        imgui.set_cursor_pos(Vector2f.new(current_x + 2, final_y + 2))
                        imgui.text_colored(strength, 0xFF000000)
                        imgui.set_cursor_pos(Vector2f.new(current_x, final_y))
                        imgui.text_colored(strength, item.color)
                        current_x = current_x + math.floor(imgui.calc_text_size(strength).x + 0.5) + 5
                    end
                end
                
                if item.dist_text then
                    imgui.set_cursor_pos(Vector2f.new(current_x + 5, item.y + 2))
                    imgui.text_colored(item.dist_text, 0xFF000000)
                    imgui.set_cursor_pos(Vector2f.new(current_x + 5, item.y))
                    imgui.text_colored(item.dist_text, item.color)
                end
            end
            icons_to_draw = {}
        end
        if custom_font.obj then imgui.push_font(custom_font.obj) end

        if p1_cache.valid and p2_cache.valid then
            local base_size = custom_font.loaded_size
            if base_size > 0 then
                
                local function draw_text_element(cache, opponent, enabled, color_text, pos_mode, txt_func, head_off_x, head_off_y, root_off_x, root_off_y, fix_x, fix_y, cursor_off_x, cursor_off_y, cursor_input_off_y, v_mode_self, v_mode_opp, is_opp_zone)
                    if enabled then
                        local txt, col = txt_func(cache, opponent)
                        if txt == "" then return end
                        
                        if not color_text then col = 0xFFFFFFFF end
                        
                        local cursor_owner = is_opp_zone and opponent or cache
                        local cursor_target = is_opp_zone and cache or opponent
                        
                        local active_v_mode = v_mode_self
                        local active_pos_mode = pos_mode
                        
                        local align = "center"
                        if active_pos_mode == 3 then
                            if cache.id == 0 then align = "right" elseif cache.id == 1 then align = "left" end
                        elseif active_pos_mode == 4 then
                            if cache.facing_right then align = "right" else align = "left" end
                        end
                        
                        if active_pos_mode == 3 then
                            local lines = {}
                            for s in string.gmatch(txt, "[^\r\n]+") do table.insert(lines, s) end
                            local total_height = 0
                            for _, line in ipairs(lines) do total_height = total_height + imgui.calc_text_size(line).y end
                            
                            local current_y = (sh * fix_y) - (total_height / 2)
                            for _, line in ipairs(lines) do
                                local text_width = imgui.calc_text_size(line).x
                                local x_pos
                                if align == "left" then x_pos = (sw * fix_x)
                                elseif align == "right" then x_pos = (sw * fix_x) - text_width
                                else x_pos = (sw * fix_x) - (text_width / 2) end
                                
                                imgui.set_cursor_pos(Vector2f.new(x_pos + 2, current_y + 2)); imgui.text_colored(line, 0xFF000000)
                                imgui.set_cursor_pos(Vector2f.new(x_pos, current_y)); imgui.text_colored(line, col)
                                current_y = current_y + imgui.calc_text_size(line).y
                            end
                        elseif active_pos_mode == 4 then
                            local _, screen_h = get_dynamic_screen_size()
                            local y_min, y_max = 0, screen_h
                            if active_v_mode == 2 then y_max = screen_h / 2 elseif active_v_mode == 3 then y_min = screen_h / 2 end
                            
                            -- ==========================================
                            -- [HARDCODED TWEAKS] 
                            -- Bypasses JSON entirely. (0.0 to 1.0 = Screen Height)
                            -- P1 Line is at 0.45 | P2 Line is at 0.55
                            -- ==========================================
                            local title_offset = 0.5
                            local input_offset = 0.5
                            if cursor_owner.id == 0 then
                                title_offset = 0.445  -- <<< P1 TITLE (e.g. "RED ZONE")
                                input_offset = 0.495  -- <<< P1 INPUT ICONS
                            else
                                title_offset = 0.545  -- <<< P2 TITLE (e.g. "RED ZONE")
                                input_offset = 0.595  -- <<< P2 INPUT ICONS
                            end
                            -- ==========================================
                            
                            local target_y = y_min + ((y_max - y_min) * title_offset)
                            
                            local _, dist_target = get_closest_edge(cursor_owner.id)
                            if dist_target then
                                local dir = 1; if cursor_target.world_x < cursor_owner.world_x then dir = -1 end
                                local origin_x = cursor_owner.world_x + ((config.marker_origin_shift or 0.0) * dir)
                                local s = world_to_screen_optimized(origin_x + (dist_target * dir), 1.0, 0)
                                if s then
                                    local directed_off_x = cursor_off_x or 0.0
                                    directed_off_x = cache.facing_right and -directed_off_x or directed_off_x
                                    
                                    if string.find(txt, "\n") then
                                        local title_part, input_part = string.match(txt, "^(.-)\n(.*)$")
                                        if title_part and input_part then
                                            -- 1. TITLE
                                            local pos1 = { x = s.x, y = target_y }
                                            draw_text_above_head_independent(title_part, pos1, col, directed_off_x, 0.0, scale_factor, align, cursor_target.facing_right)
                                            
                                            -- 2. INPUT ICONS
                                            local target_y_input = y_min + ((y_max - y_min) * input_offset)
                                            local pos2 = { x = s.x, y = target_y_input }
                                            draw_text_above_head_independent(input_part, pos2, col, directed_off_x, 0.0, scale_factor, align, cursor_target.facing_right)
                                        else
                                            local pos_single = { x = s.x, y = target_y }
                                            draw_text_above_head_independent(txt, pos_single, col, directed_off_x, 0.0, scale_factor, align, cursor_target.facing_right)
                                        end
                                    else
                                        local pos_single = { x = s.x, y = target_y }
                                        draw_text_above_head_independent(txt, pos_single, col, directed_off_x, 0.0, scale_factor, align, cursor_target.facing_right)
                                    end
                                end
                            end
                        else
                            local target_pos = (active_pos_mode == 1) and cache.head_screen_pos or cache.root_screen_pos
                            local active_off_x = (active_pos_mode == 1) and head_off_x or root_off_x
                            local active_off_y = (active_pos_mode == 1) and head_off_y or root_off_y
                            if target_pos then
                                local directed_off_x = active_off_x or 0.0
                                if align == "center" then
                                    directed_off_x = cache.facing_right and directed_off_x or -directed_off_x
                                end
                                draw_text_above_head_independent(txt, target_pos, col, directed_off_x, active_off_y, scale_factor, align, cursor_target.facing_right)
                            end
                        end
                    end
                end
                
                if p1_display and p2_display then
                    local function draw_crossup(cache, opponent, opp_pos_mode, show_opp_zone, opp_off_x, opp_off_y, enabled, opp_zone_off_y, color_text)
                        if not enabled then return 0 end
                        local txt, col = get_crossup_info(cache, opponent)
                        local target_pos = (opp_pos_mode == 2) and cache.root_screen_pos or cache.head_screen_pos
                        if txt == "" or not target_pos then return 0 end
                        
                        -- Apply the user's color preference for the text
                        if not color_text then col = colors.White end
                        
                        local align = "center"; local extra_y_unscaled = 0
                        if (opp_pos_mode == 1 or opp_pos_mode == 2) and show_opp_zone then
                            local opp_txt, _ = get_opp_zone_info(cache, opponent)
                            if opp_txt ~= "" then
                                local total_height = 0
                                for s in string.gmatch(opp_txt, "[^\r\n]+") do total_height = total_height + imgui.calc_text_size(s).y end
                                extra_y_unscaled = (total_height / scale_factor)
                            end
                        end
                        
                        local off_y = (opp_off_y or 0.0) + extra_y_unscaled
                        if (opp_pos_mode == 1 or opp_pos_mode == 2) and show_opp_zone then off_y = off_y + (opp_zone_off_y or 0.0) end
                        local off_x = opp_off_x or 0.0
                        local directed_off_x = cache.facing_right and off_x or -off_x
                        
                        draw_text_above_head_independent(txt, target_pos, col, directed_off_x, off_y, scale_factor, align, cache.facing_right)
                        
                        local total_cross_h = 0
                        for s in string.gmatch(txt, "[^\r\n]+") do total_cross_h = total_cross_h + imgui.calc_text_size(s).y end
                        return off_y + (total_cross_h / scale_factor)
                    end

                    -- ====== P1 TEXTS ======
                    if config.p1_show_all and not is_overlapping_floating(p1_display) then
                        local draw_v_p1 = config.p1_vertical_mode
                        if draw_v_p1 == 8 then draw_v_p1 = config.p1_custom_base_mode or 1 end
                        if draw_v_p1 > 4 then draw_v_p1 = 4 end
                        
                        local draw_v_p2 = config.p2_vertical_mode
                        if draw_v_p2 == 8 then draw_v_p2 = config.p2_custom_base_mode or 1 end
                        if draw_v_p2 > 4 then draw_v_p2 = 4 end
                        
                        local active_pos_p1 = config.p1_opp_zone_pos_mode
                        if active_pos_p1 == 4 and not config.p1_show_vertical_cursor and not config.p1_show_horizontal_lines then 
                            active_pos_p1 = (config.p1_vertical_mode == 6) and 2 or 1 
                        end
                        
                        local p1_head_x, p1_head_y, p1_root_x, p1_root_y = 0.0, 0.0, 0.0, 0.0
                        local p1_zone_off_y = (active_pos_p1 == 2) and p1_root_y or p1_head_y
                        
                        local p1_cross_top = draw_crossup(p1_display, p2_display, active_pos_p1, config.p1_opp_zone_show, p1_head_x, p1_head_y, config.p1_crossup_show, p1_zone_off_y, config.p1_crossup_color_text)
                        
                        if p1_transient_timer > 0 then
                            p1_transient_timer = p1_transient_timer - 1
                            local trans_y = p1_cross_top
                            if trans_y == 0 then
                                trans_y = p1_zone_off_y
                                if (active_pos_p1 == 1 or active_pos_p1 == 2) and config.p1_opp_zone_show then
                                    local opp_txt = get_opp_zone_info(p1_display, p2_display)
                                    if opp_txt ~= "" then
                                        local h = 0; for s in string.gmatch(opp_txt, "[^\r\n]+") do h = h + imgui.calc_text_size(s).y end
                                        trans_y = trans_y + (h / scale_factor)
                                    end
                                end
                            end
                            local target_pos = (active_pos_p1 == 2) and p1_display.root_screen_pos or p1_display.head_screen_pos
                            if target_pos then draw_text_above_head_independent(p1_transient_text, target_pos, colors.White, 0.0, trans_y, scale_factor, "center", p1_display.facing_right) end
                        end
                        
						local p1_opp_h = config["p1_opp_zone_cursor_h_" .. draw_v_p1] or 0.5
                        local p1_opp_input_h = config["p1_opp_zone_cursor_input_h_" .. draw_v_p1] or 0.475
                        draw_text_element(p1_display, p2_display, config.p1_opp_zone_show, config.p1_opp_zone_color_text, active_pos_p1, get_opp_zone_info, p1_head_x, p1_head_y, p1_root_x, p1_root_y, config.p1_opp_zone_fixed_x, config.p1_opp_zone_fixed_y, config.p1_opp_zone_cursor_off_x, p1_opp_h, p1_opp_input_h, draw_v_p1, draw_v_p2, false)
						end

                    -- ====== P2 TEXTS ======
                    if config.p2_show_all and not is_overlapping_floating(p2_display) then
                        local draw_v_p1 = config.p1_vertical_mode
                        if draw_v_p1 == 8 then draw_v_p1 = config.p1_custom_base_mode or 1 end
                        if draw_v_p1 > 4 then draw_v_p1 = 4 end
                        
                        local draw_v_p2 = config.p2_vertical_mode
                        if draw_v_p2 == 8 then draw_v_p2 = config.p2_custom_base_mode or 1 end
                        if draw_v_p2 > 4 then draw_v_p2 = 4 end
                        
                        local active_pos_p2 = config.p2_opp_zone_pos_mode
                        if active_pos_p2 == 4 and not config.p2_show_vertical_cursor and not config.p2_show_horizontal_lines then 
                            active_pos_p2 = (config.p2_vertical_mode == 6) and 2 or 1 
                        end
                        
                        local p2_head_x, p2_head_y, p2_root_x, p2_root_y = 0.0, 0.0, 0.0, 0.0
                        local p2_zone_off_y = (active_pos_p2 == 2) and p2_root_y or p2_head_y
                        
                        local p2_cross_top = draw_crossup(p2_display, p1_display, active_pos_p2, config.p2_opp_zone_show, p2_head_x, p2_head_y, config.p2_crossup_show, p2_zone_off_y, config.p2_crossup_color_text)
                        
                        if p2_transient_timer > 0 then
                            p2_transient_timer = p2_transient_timer - 1
                            local trans_y = p2_cross_top
                            if trans_y == 0 then
                                trans_y = p2_zone_off_y
                                if (active_pos_p2 == 1 or active_pos_p2 == 2) and config.p2_opp_zone_show then
                                    local opp_txt = get_opp_zone_info(p2_display, p1_display)
                                    if opp_txt ~= "" then
                                        local h = 0; for s in string.gmatch(opp_txt, "[^\r\n]+") do h = h + imgui.calc_text_size(s).y end
                                        trans_y = trans_y + (h / scale_factor)
                                    end
                                end
                            end
                            local target_pos = (active_pos_p2 == 2) and p2_display.root_screen_pos or p2_display.head_screen_pos
                            if target_pos then draw_text_above_head_independent(p2_transient_text, target_pos, colors.White, 0.0, trans_y, scale_factor, "center", p2_display.facing_right) end
                        end
                        
						local p2_opp_h = config["p2_opp_zone_cursor_h_" .. draw_v_p2] or 0.5
                        local p2_opp_input_h = config["p2_opp_zone_cursor_input_h_" .. draw_v_p2] or 0.52
                        draw_text_element(p2_display, p1_display, config.p2_opp_zone_show, config.p2_opp_zone_color_text, active_pos_p2, get_opp_zone_info, p2_head_x, p2_head_y, p2_root_x, p2_root_y, config.p2_opp_zone_fixed_x, config.p2_opp_zone_fixed_y, config.p2_opp_zone_cursor_off_x, p2_opp_h, p2_opp_input_h, draw_v_p2, draw_v_p1, false)						
                    end
                end
                
            end
        end

        if custom_font.obj then imgui.pop_font() end

        -- Rendu des nombres de distance avec leur propre police
        if #numbers_to_draw > 0 then
            if custom_font_num.obj then imgui.push_font(custom_font_num.obj) end
            for _, nd in ipairs(numbers_to_draw) do
                local txt_sz = imgui.calc_text_size(nd.txt)
                local txt_x = nd.x - (txt_sz.x / 2.0)
                local txt_y = nd.y - ((nd.off_y or 25.0) * scale_factor) - (txt_sz.y / 2.0)
                imgui.set_cursor_pos(Vector2f.new(txt_x + 2, txt_y + 2)); imgui.text_colored(nd.txt, 0xFF000000)
                imgui.set_cursor_pos(Vector2f.new(txt_x, txt_y)); imgui.text_colored(nd.txt, nd.col)
            end
            if custom_font_num.obj then imgui.pop_font() end
        end

        imgui.end_window()
    end
    imgui.pop_style_color(1); imgui.pop_style_var(2)

    if not config.show_debug_window or _G.SessionRecapVisible then _dv_last_window_rect = nil end
    if config.show_debug_window and not _G.SessionRecapVisible then
        if first_draw then
            imgui.set_next_window_pos(Vector2f.new(config.window_pos_x, config.window_pos_y), 1 << 3)
            first_draw = false
        end

        -- Flag 64 = ImGuiWindowFlags_AlwaysAutoResize (Forces window to wrap content tightly)
        local window_flags = 64
        if not config.expert_mode_enabled then
            window_flags = 64
        end

        if imgui.begin_window("SF6 DISTANCE VIEWER", true, window_flags) then
            -- Save rect for next frame's click detection (on_draw_ui runs after on_frame)
            pcall(function()
                local wpos = imgui.get_window_pos()
                local wsz = imgui.get_window_size()
                _dv_last_window_rect = { x = wpos.x, y = wpos.y, w = wsz.x, h = wsz.y }
            end)
            if ui_font.obj then imgui.push_font(ui_font.obj) end
            
            -- Checkbox to hide the floating window from within itself
            local chg_ov, new_ov = imgui.checkbox("Floating Window", config.show_debug_window)
            imgui.same_line()
            if imgui.button("Reload Data") then load_advanced_data() end
            imgui.same_line()
            local chg_em, new_em = imgui.checkbox("EXPERT MODE ", config.expert_mode_enabled)
            if chg_em then
                config.expert_mode_enabled = new_em
                for _, p in ipairs({"p1", "p2"}) do
                    if not new_em then
                        -- Expert → Normal: save expert flags, reset to normal mode 1
                        config[p.."_expert_fill_bg"] = config[p.."_fill_bg"]
                        config[p.."_expert_markers"] = config[p.."_show_markers"]
                        config[p.."_expert_cursor"] = config[p.."_show_vertical_cursor"]
                        config[p.."_expert_hlines"] = config[p.."_show_horizontal_lines"]
                        config[p.."_expert_numbers"] = config[p.."_show_numbers"]
                        config[p.."_expert_zone"] = config[p.."_opp_zone_show"]
                        config[p.."_expert_crossup"] = config[p.."_crossup_show"]
                        config[p.."_expert_color_text"] = config[p.."_opp_zone_color_text"]
                        config[p.."_expert_crossup_color"] = config[p.."_crossup_color_text"]
                        config[p.."_expert_jump_arc"] = config[p.."_show_jump_arc"]
                        config[p.."_vertical_mode"] = 1; config[p.."_advanced_mode"] = false
                        apply_mode_flags(p, 1)
                        config[p.."_show_jump_arc"] = false
                    else
                        -- Normal → Expert: restore expert flags
                        config[p.."_vertical_mode"] = 1
                        config[p.."_advanced_mode"] = true
                        apply_mode_flags(p, 1)
                        -- Restore saved expert settings (or defaults)
                        config[p.."_fill_bg"] = config[p.."_expert_fill_bg"] or false
                        config[p.."_show_markers"] = config[p.."_expert_markers"] or false
                        config[p.."_show_vertical_cursor"] = config[p.."_expert_cursor"] ~= false and true or false
                        config[p.."_show_horizontal_lines"] = config[p.."_expert_hlines"] ~= false and true or false
                        config[p.."_show_numbers"] = config[p.."_expert_numbers"] ~= false and true or false
                        config[p.."_opp_zone_show"] = config[p.."_expert_zone"] ~= false and true or false
                        config[p.."_crossup_show"] = config[p.."_expert_crossup"] ~= false and true or false
                        if config[p.."_expert_color_text"] ~= nil then config[p.."_opp_zone_color_text"] = config[p.."_expert_color_text"] end
                        if config[p.."_expert_crossup_color"] ~= nil then config[p.."_crossup_color_text"] = config[p.."_expert_crossup_color"] end
                        if config[p.."_expert_jump_arc"] ~= nil then config[p.."_show_jump_arc"] = config[p.."_expert_jump_arc"] end
                    end
                end
                save_settings()
            end

            if chg_ov then
                config.show_debug_window = new_ov
                save_settings()
            end

            imgui.separator()

            draw_config_ui()

            local pos = imgui.get_window_pos()
            if math.abs(pos.x - config.window_pos_x) > 1.0 or math.abs(pos.y - config.window_pos_y) > 1.0 then
                config.window_pos_x = pos.x; config.window_pos_y = pos.y
                if not imgui.is_mouse_down(0) then save_settings() end
            end
            
            if ui_font.obj then imgui.pop_font() end
            imgui.end_window()
        end
    end
    collectgarbage("step", 1)
end)

local function draw_distance_viewer_menu_ui()
    if imgui.tree_node("SF6 DISTANCE VIEWER") then
        local changed_ov, new_ov = imgui.checkbox("FLOATING WINDOW", config.show_debug_window)
        if changed_ov then
            config.show_debug_window = new_ov
            first_draw = true
            save_settings()
        end
        imgui.same_line()
        if imgui.button("Reload Data") then load_advanced_data() end
        imgui.same_line()
        local chg_em, new_em = imgui.checkbox("EXPERT MODE ", config.expert_mode_enabled)
        if chg_em then
            config.expert_mode_enabled = new_em
            for _, p in ipairs({"p1", "p2"}) do
                if not new_em then
                    config[p.."_expert_fill_bg"] = config[p.."_fill_bg"]
                    config[p.."_expert_markers"] = config[p.."_show_markers"]
                    config[p.."_expert_cursor"] = config[p.."_show_vertical_cursor"]
                    config[p.."_expert_hlines"] = config[p.."_show_horizontal_lines"]
                    config[p.."_expert_numbers"] = config[p.."_show_numbers"]
                    config[p.."_expert_zone"] = config[p.."_opp_zone_show"]
                    config[p.."_expert_crossup"] = config[p.."_crossup_show"]
                    config[p.."_expert_color_text"] = config[p.."_opp_zone_color_text"]
                    config[p.."_expert_crossup_color"] = config[p.."_crossup_color_text"]
                    config[p.."_expert_jump_arc"] = config[p.."_show_jump_arc"]
                    config[p.."_vertical_mode"] = 1; config[p.."_advanced_mode"] = false
                    apply_mode_flags(p, 1)
                else
                    config[p.."_vertical_mode"] = 1
                    config[p.."_advanced_mode"] = true
                    apply_mode_flags(p, 1)
                    config[p.."_fill_bg"] = config[p.."_expert_fill_bg"] or false
                    config[p.."_show_markers"] = config[p.."_expert_markers"] or false
                    config[p.."_show_vertical_cursor"] = config[p.."_expert_cursor"] ~= false and true or false
                    config[p.."_show_horizontal_lines"] = config[p.."_expert_hlines"] ~= false and true or false
                    config[p.."_show_numbers"] = config[p.."_expert_numbers"] ~= false and true or false
                    config[p.."_opp_zone_show"] = config[p.."_expert_zone"] ~= false and true or false
                    config[p.."_crossup_show"] = config[p.."_expert_crossup"] ~= false and true or false
                    if config[p.."_expert_color_text"] ~= nil then config[p.."_opp_zone_color_text"] = config[p.."_expert_color_text"] end
                    if config[p.."_expert_crossup_color"] ~= nil then config[p.."_crossup_color_text"] = config[p.."_expert_crossup_color"] end
                    if config[p.."_expert_jump_arc"] ~= nil then config[p.."_show_jump_arc"] = config[p.."_expert_jump_arc"] end
                end
            end
            save_settings()
        end

        if not config.show_debug_window then
            imgui.separator()
            imgui.text_colored("MODE MENU REFRAMEWORK (Fenêtre Masquée)", COL_CYAN)
            draw_config_ui()
        end

        imgui.tree_pop()
    end
end

re.on_draw_ui(draw_distance_viewer_menu_ui)