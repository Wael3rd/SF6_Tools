local json = json
local sdk = sdk
local imgui = imgui
local re = re
local draw = draw
local Vector3f = Vector3f
local Vector2f = Vector2f

-- =========================================================
-- [ADVANCED MODE - Distance Logger integration]
-- =========================================================
local ADVANCED_DATA_FILE = "SF6DistanceLogger_Data_Attacks.json"
local advanced_data = {}

local fallback_spacing = { yellow = 2.50, red = 2.00, low = 1.50 }
local spacing_thresholds = {}
local jump_data_store = {}

local ADVANCED_PREFS_FILE = "SF6DistanceViewer_AdvancedPrefs.json"
local advanced_prefs = { [0] = {}, [1] = {} }

local function load_advanced_prefs()
    local f = json.load_file(ADVANCED_PREFS_FILE)
    if f then 
        -- JSON converts integer keys to strings, so we map them back
        advanced_prefs[0] = f["0"] or f[0] or {}
        advanced_prefs[1] = f["1"] or f[1] or {}
    end
    if type(advanced_prefs[0]) ~= "table" then advanced_prefs[0] = {} end
    if type(advanced_prefs[1]) ~= "table" then advanced_prefs[1] = {} end
end
local function save_advanced_prefs() json.dump_file(ADVANCED_PREFS_FILE, advanced_prefs) end
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

local VMODE_FULL = 1
local VMODE_TOP_HALF = 2
local VMODE_BOTTOM_HALF = 3
local VMODE_NONE = 4

local config = { 
    use_attack_lock = false,
    jump_arc_thickness = 50.0,
    
    -- Font Size Base (Master Quality)
    stats_font_size = 80, 
    zone_opacity = 25,

    -- Advanced Mode Data
    p1_advanced_mode = false,
    p2_advanced_mode = false,
    advanced_visibility = {},

    -- ================= P1 SETTINGS =================
    p1_show_all = true,
    p1_opp_zone_show_title = true, p1_opp_zone_show_name = true,
    p1_my_zone_show_title = true, p1_my_zone_show_name = true,
    -- P1 Visuals
    p1_show_horizontal_lines = true, p1_line_height = 0.70,
    p1_end_marker_size = 25.0, p1_end_marker_offset_y = 0.0,
    p1_show_origin_dot = false, p1_origin_dot_size = 8.0,
    p1_show_markers = false, p1_show_vertical_cursor = false, 
    p1_vertical_mode = VMODE_FULL, p1_fill_bg = false,
    p1_show_jump_arc = false,

    -- P1 TEXT: CROSSUP
    p1_crossup_show = true,
    p1_crossup_color_text = true,
    p1_crossup_pos_mode = 1, -- 1=Head, 2=Root, 3=Fixed
    p1_crossup_head_off_x = 0.0, p1_crossup_head_off_y = 100.0,
    p1_crossup_root_off_x = 0.0, p1_crossup_root_off_y = 0.0,
    p1_crossup_fixed_x = 0.25, p1_crossup_fixed_y = 0.10,
    
    -- P1 TEXT: OPPONENT ZONE
    p1_opp_zone_show = true,
    p1_opp_zone_color_text = true,
    p1_opp_zone_pos_mode = 1,
    p1_opp_zone_head_off_x = 0.0, p1_opp_zone_head_off_y = 50.0,
    p1_opp_zone_root_off_x = 0.0, p1_opp_zone_root_off_y = -30.0,
    p1_opp_zone_fixed_x = 0.25, p1_opp_zone_fixed_y = 0.15,
    
    -- P1 TEXT: MY ZONE
    p1_my_zone_show = true,
    p1_my_zone_color_text = true,
    p1_my_zone_pos_mode = 1,
    p1_my_zone_head_off_x = 0.0, p1_my_zone_head_off_y = 0.0,
    p1_my_zone_root_off_x = 0.0, p1_my_zone_root_off_y = -60.0,
    p1_my_zone_fixed_x = 0.25, p1_my_zone_fixed_y = 0.20,
    
    -- ================= P2 SETTINGS =================
	p2_show_all = true,
    p2_opp_zone_show_title = true, p2_opp_zone_show_name = true,
    p2_my_zone_show_title = true, p2_my_zone_show_name = true,
    -- P2 Visuals
    p2_show_horizontal_lines = true, p2_line_height = 0.75,
    p2_end_marker_size = 25.0, p2_end_marker_offset_y = 0.0,
    p2_show_origin_dot = false, p2_origin_dot_size = 8.0,
    p2_show_markers = false, p2_show_vertical_cursor = false,
    p2_vertical_mode = VMODE_FULL, p2_fill_bg = false,
    p2_show_jump_arc = false,

    -- P2 TEXT: CROSSUP
    p2_crossup_show = true,
    p2_crossup_color_text = true,
    p2_crossup_pos_mode = 1,
    p2_crossup_head_off_x = 0.0, p2_crossup_head_off_y = 100.0,
    p2_crossup_root_off_x = 0.0, p2_crossup_root_off_y = 0.0,
    p2_crossup_fixed_x = 0.75, p2_crossup_fixed_y = 0.10,
    
    -- P2 TEXT: OPPONENT ZONE
    p2_opp_zone_show = true,
    p2_opp_zone_color_text = true,
    p2_opp_zone_pos_mode = 1,
    p2_opp_zone_head_off_x = 0.0, p2_opp_zone_head_off_y = 50.0,
    p2_opp_zone_root_off_x = 0.0, p2_opp_zone_root_off_y = -30.0,
    p2_opp_zone_fixed_x = 0.75, p2_opp_zone_fixed_y = 0.15,
    
    -- P2 TEXT: MY ZONE
    p2_my_zone_show = true,
    p2_my_zone_color_text = true,
    p2_my_zone_pos_mode = 1,
    p2_my_zone_head_off_x = 0.0, p2_my_zone_head_off_y = 0.0,
    p2_my_zone_root_off_x = 0.0, p2_my_zone_root_off_y = -60.0,
    p2_my_zone_fixed_x = 0.75, p2_my_zone_fixed_y = 0.20,
    
    -- Global
    marker_thickness = 5.0, marker_origin_shift = 0.0, 
    -- Window State
    show_debug_window = true,
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
    end 
end
load_settings()

local first_draw = true

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
    local f = json.load_file(ADVANCED_DATA_FILE)
    if not f or type(f) ~= "table" then return end
    
    -- Reconstruire les tableaux moves en vrai array Lua (JSON -> clés string)
    for char_name, cdata in pairs(f) do
        if type(cdata) == "table" and cdata.moves then
            local fixed = {}
            for _, v in pairs(cdata.moves) do
                if type(v) == "table" then
                    table.insert(fixed, v)
                end
            end
            table.sort(fixed, function(a, b) return (a.ar or 0) > (b.ar or 0) end)
            cdata.moves = fixed
        end
    end
    advanced_data = f

    -- Remplir spacing_thresholds UNIQUEMENT avec les valeurs de advanced_data
    local count = 0
    for char_name, cdata in pairs(advanced_data) do
        if type(cdata) == "table" and cdata.red and cdata.low then
            local esf_key = real_to_esf[char_name]
            if esf_key then
                if not spacing_thresholds[esf_key] then spacing_thresholds[esf_key] = {} end
                local red_ar = cdata.red.ar / 100.0
                local low_ar = cdata.low.ar / 100.0
                
                -- LECTURE DE LA VARIABLE YELLOW DIRECTEMENT DEPUIS LE PERSO
                local y_off = cdata.yellow_offset or 50
                local max_ar = math.max(red_ar, low_ar)
                local yellow_ar = max_ar + (y_off / 100.0)
                
                spacing_thresholds[esf_key].red    = red_ar
                spacing_thresholds[esf_key].low    = low_ar
                spacing_thresholds[esf_key].yellow = yellow_ar
                spacing_thresholds[esf_key].red_input = cdata.red.input
                spacing_thresholds[esf_key].low_input = cdata.low.input
                count = count + 1
            end
        end
    end
    debug_dist_status = string.format("OK (%d custom chars)", count)
    debug_dist_color = 0xFF00FF00
end

local function save_advanced_data()
    json.dump_file(ADVANCED_DATA_FILE, advanced_data)
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

local colors = { Green=0xFF00FF00, Yellow=0xFF00FFFF, Red=0xFF0000FF, Purple=0xFFFF00FF, White=0xFFFFFFFF, Black=0xFF000000, Cyan=0xFF00FFFF, Grey=0xFFAAAAAA }

local function get_dynamic_color(base_color_abgr)
    local alpha = math.floor((config.zone_opacity / 100.0) * 255)
    return (base_color_abgr & 0x00FFFFFF) | (alpha << 24)
end

local shadow_color = 0x80000000

-- =========================================================
-- [THEMED UI - Same style as Distance Logger]
-- =========================================================
local COL_RED    = 0xFF4444FF
local COL_LOW    = 0xFFCC44BB
local COL_YELLOW = 0xFF00FFFF
local COL_GREEN  = 0xFF00FF00
local COL_CYAN   = 0xFFFFFF00
local COL_GREY   = 0xFF888888
local COL_GOLD   = 0xFF00D5FF

local UI_THEME = {
    hdr_info    = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_session_1 = { base = 0xFFB65900, hover = 0xFFC77000, active = 0xFFA04800 },
    hdr_session_2 = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    hdr_rules   = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
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
            if input then return space .. title .. "\n(" .. input .. ")" else return space .. title end
        elseif show_title and not show_name then
            return space .. title
        elseif not show_title and show_name then
            if input then return space .. input .. " Zone" else return space .. title end
        else
            return ""
        end
    end

    local arr = {
        { name = make_name("Low Range", limits.low_input), dist = limits.low, color = colors.Purple, fill = get_dynamic_color(colors.Purple) },
        { name = make_name("Red Zone", limits.red_input), dist = limits.red, color = colors.Red, fill = get_dynamic_color(colors.Red) },
        { name = make_name("Yellow Zone", nil), dist = limits.yellow, color = colors.Yellow, fill = get_dynamic_color(colors.Yellow) }
    }
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
local res_watcher = { last_w = 0, last_h = 0, cooldown = 0 }

local function try_load_font()
    if not imgui.load_font then custom_font.status = "API Error"; return end
    local sw, sh = get_dynamic_screen_size()
    local scale_factor = sh / 1080.0
    if scale_factor < 0.1 then scale_factor = 1.0 end
    local target_size = math.floor(config.stats_font_size * scale_factor)

    if custom_font.obj and custom_font.loaded_size == target_size then return end

    local font = imgui.load_font(custom_font.filename, target_size)
    if font then 
        custom_font.obj = font
        custom_font.loaded_size = target_size
        custom_font.status = "OK ("..target_size.."px)"
    else
        custom_font.status = "File Not Found"
    end
end

local debug_dist_status = "Not Loaded"
local debug_jump_status = "Not Loaded"
local debug_dist_color = 0xFF0000FF 
local debug_jump_color = 0xFF0000FF

-- 1. INIT DISTANCES (Strictement via Advanced Data maintenant)
spacing_thresholds = {}
debug_dist_status = "Waiting for Data..."
debug_dist_color = 0xFF888888

-- 2. LOAD JUMPS
local jump_data = json.load_file("SF6DistanceLogger_Data_Jumps.json")
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
    if not player_obj then return nil end
    local root_x = 0; local root_y = 0
    if player_obj.pos and player_obj.pos.x and player_obj.pos.y then
        root_x = player_obj.pos.x.v / 6553600.0; root_y = player_obj.pos.y.v / 6553600.0
    else return nil end

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
    if draw and draw.world_to_screen then return draw.world_to_screen(Vector3f.new(root_x, final_y, 0)) end
    return nil
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
        cache_table.head_screen_pos = get_char_top_screen_pos(p)
        cache_table.root_screen_pos = get_char_root_screen_pos(p)
        
        local bit_val = p.BitValue
        if bit_val then 
             cache_table.facing_right = (bitand(bit_val, 128) == 128)
        else cache_table.facing_right = (pi == 0) end
        local detected = detected_infos[pi] or { name="?" }
        cache_table.real_name = detected.name
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

local function get_closest_edge(reference_world_x, target_act_param)
    if not target_act_param or not target_act_param.Collision then return nil, nil end
    local col = target_act_param.Collision
    local best_edge_x = nil; local min_dist = 999999.0
    if col.Infos and col.Infos._items then
        for j, r in pairs(col.Infos._items) do
            if r and (r:get_field("Attr") ~= nil or r:get_field("HitNo") ~= nil) then
                local box_center_x = r.OffsetX.v / 6553600
                local size_x = (r.SizeX.v / 6553600) 
                local left = box_center_x - size_x; local right = box_center_x + size_x
                local d_left = math.abs(reference_world_x - left)
                if d_left < min_dist then min_dist = d_left; best_edge_x = left end
                local d_right = math.abs(reference_world_x - right)
                if d_right < min_dist then min_dist = d_right; best_edge_x = right end
            end
        end
    end
    return best_edge_x, min_dist
end

local function draw_text_safe(text, x, y, color, size) 
    draw.text(text, x + 2, y + 2, shadow_color, size)
    draw.text(text, x, y, color, size) 
end

local function draw_text_above_head_independent(text, pos, color, offset_x, offset_y, scale_factor)
    if text == "" or not pos then return end
    local off_x = offset_x * scale_factor
    local off_y = offset_y * scale_factor

    local lines = {}
    for s in string.gmatch(text, "[^\r\n]+") do table.insert(lines, s) end
    
    local total_height = 0
    for _, line in ipairs(lines) do total_height = total_height + imgui.calc_text_size(line).y end
    
    local current_y = pos.y - off_y - total_height
    
    for _, line in ipairs(lines) do
        local text_width = imgui.calc_text_size(line).x
        local text_height = imgui.calc_text_size(line).y
        local x_pos = pos.x - (text_width / 2) + off_x
        
        imgui.set_cursor_pos(Vector2f.new(x_pos + 2, current_y + 2))
        imgui.text_colored(line, 0xFF000000)
        imgui.set_cursor_pos(Vector2f.new(x_pos, current_y))
        imgui.text_colored(line, color)
        
        current_y = current_y + text_height
    end
end

local function get_crossup_info(cache_data, opponent_data)
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
        if dist_cc <= mv.ar / 100.0 then
            local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
            
            local zone_name = "Zone"
            if prefs.red and prefs.red.input == mv.input then zone_name = "Red Zone"
            elseif prefs.low and prefs.low.input == mv.input then zone_name = "Low Range" end
            
            if show_title and show_name then
                return space .. zone_name .. "\n(" .. mv.input .. ")", col
            elseif show_title and not show_name then
                return space .. zone_name, col
            elseif not show_title and show_name then
                return space .. mv.input .. " Zone", col
            else
                return "", col
            end
        end
    end
    
    if show_title then return space .. "Out Range", colors.White end
    return "", colors.White
end

local function get_opp_zone_info(cache_data, opponent_data)
    if not cache_data.valid or not opponent_data.valid then return "", colors.Grey end
    local _, dist_target = get_closest_edge(cache_data.world_x, opponent_data.act_param)
    if not dist_target then return "No Data", colors.Grey end

   local prefix = "Opp"
    if opponent_data.id == 0 then prefix = "P1"
    elseif opponent_data.id == 1 then prefix = "P2" end

    -- Retrieve specific P1/P2 settings for OPPONENT zone
    local show_t, show_n = true, true
    if cache_data.id == 0 then show_t = config.p1_opp_zone_show_title; show_n = config.p1_opp_zone_show_name
    elseif cache_data.id == 1 then show_t = config.p2_opp_zone_show_title; show_n = config.p2_opp_zone_show_name end

    local is_adv = false
    if cache_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    if is_adv then
        local char_name = get_real_name(opponent_data.real_name)
        local _, dist_opp = get_closest_edge(opponent_data.world_x, cache_data.act_param)
        if dist_opp then
            local txt, col = get_advanced_zone_label(opponent_data.id, char_name, dist_opp, prefix, show_t, show_n)
            if txt then return txt, col end
        end
    end
    
    local _, dist_opp_normal = get_closest_edge(opponent_data.world_x, cache_data.act_param)
    if not dist_opp_normal then return "No Data", colors.Grey end
    
    local limits = spacing_thresholds[opponent_data.real_name] or fallback_spacing
    local sorted = get_sorted_thresholds(limits, show_t, show_n, prefix)
    
    local text_str = ""
    if show_t then text_str = prefix .. " Green Zone" end
    local text_col = colors.Green
    
    for _, zone in ipairs(sorted) do
        if dist_opp_normal <= zone.dist then
            text_str = zone.name
            text_col = zone.color
            break
        end
    end
    return text_str, text_col
end

local function get_my_zone_info(cache_data, opponent_data)
    if not cache_data.valid or not opponent_data.valid then return "", colors.Grey end
    local _, dist_target = get_closest_edge(cache_data.world_x, opponent_data.act_param)
    if not dist_target then return "No Data", colors.Grey end

    local prefix = "My"
    if cache_data.id == 0 then prefix = "P1"
    elseif cache_data.id == 1 then prefix = "P2" end

    -- Retrieve specific P1/P2 settings for MY zone
    local show_t, show_n = true, true
    if cache_data.id == 0 then show_t = config.p1_my_zone_show_title; show_n = config.p1_my_zone_show_name
    elseif cache_data.id == 1 then show_t = config.p2_my_zone_show_title; show_n = config.p2_my_zone_show_name end

    local is_adv = false
    if cache_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    if is_adv then
        local char_name = get_real_name(cache_data.real_name)
        local txt, col = get_advanced_zone_label(cache_data.id, char_name, dist_target, prefix, show_t, show_n)
        if txt then return txt, col end
    end

    local limits = spacing_thresholds[cache_data.real_name] or fallback_spacing
    local sorted = get_sorted_thresholds(limits, show_t, show_n, prefix)
    local text_str = ""
    if show_t then text_str = prefix .. " Green Zone" end
    local text_col = colors.Green
    
    for _, zone in ipairs(sorted) do
        if dist_target <= zone.dist then
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
    local st_limit = frames.cross_up_st or 0; local cr_limit = frames.cross_up_cr or 0
    local arc_col = 0xFFFF0000
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

local function draw_spacing_horizontal(owner_data, target_data, settings, scale_factor)
    if not settings.show_horizontal_lines then return end

    local scaled_thickness = config.marker_thickness * scale_factor
    local scaled_font_size  = config.stats_font_size * scale_factor
    local scaled_marker_size = settings.end_marker_size * scale_factor
    local scaled_marker_offset = settings.end_marker_offset_y * scale_factor
    local scaled_dot_size = (settings.origin_dot_size or 8.0) * scale_factor
    local display_h = select(2, get_dynamic_screen_size())
    local y = display_h * settings.line_height
    
    local edge_target, dist_target = get_closest_edge(owner_data.world_x, target_data.act_param)
    local direction = 1
    if edge_target and edge_target < owner_data.world_x then direction = -1 end

    local function get_x(d)
        local w = world_to_screen_optimized(owner_data.world_x + (d * direction), owner_data.world_y, 0)
        return w and w.x or nil
    end

    local is_adv = false
    if owner_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    if is_adv then
        local char_name = get_real_name(owner_data.real_name)
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
                
                if dist_target <= mv_dist then
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
                local center_y = y + scaled_marker_offset
                local half_size = scaled_marker_size / 2.0
                draw_thick_line(x_end, center_y - half_size, x_end, center_y + half_size, scaled_thickness, cur_col)
                
                local txt = string.format("%.2f", dist_target * 100)
                local mid_x = (x_origin + x_end) / 2
                draw_text_safe(txt, mid_x - scaled_font_size, center_y - half_size - (25 * scale_factor), cur_col, scaled_font_size)
            end
            return
        end
    end

    local limits = spacing_thresholds[owner_data.real_name] or fallback_spacing
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
            local center_y = y + scaled_marker_offset
            local half_size = scaled_marker_size / 2.0
            
            local cur_col = colors.Green
            for _, zone in ipairs(sorted) do
                if dist_target <= zone.dist then cur_col = zone.color; break end
            end
            
            draw_thick_line(x_final, center_y - half_size, x_final, center_y + half_size, scaled_thickness, cur_col)
            local txt = string.format("%.2f", dist_target * 100)
            local mid_x = (x_origin + x_final) / 2
            local ts_x = 30 * scale_factor
            draw_text_safe(txt, mid_x - (ts_x/2), center_y - half_size - (25 * scale_factor), cur_col, scaled_font_size)
        end
    end
end

local function draw_vertical_overlay(owner_data, target_data, settings, scale_factor)
    if settings.vertical_mode == VMODE_NONE then return end
    if not settings.show_markers and not settings.fill_bg and not settings.show_vertical_cursor then return end

    local is_adv = false
    if owner_data.id == 0 then is_adv = config.p1_advanced_mode else is_adv = config.p2_advanced_mode end
    if is_adv then
        local char_name = get_real_name(owner_data.real_name)
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
                    draw.line(lx, y_min, lx, y_max, col, scaled_thickness)
                    if config.adv_show_line_labels then
                        local prefs = get_char_prefs(owner_data.id, char_name)
                        local label = mv.input .. " " .. string.format("%.1f", mv.ar)
                        if prefs.red and prefs.red.input == mv.input then label = "[R] " .. label end
                        if prefs.low and prefs.low.input == mv.input then label = "[L] " .. label end
                        local label_y
                        if label_toggle then label_y = y_min + 5
                        else label_y = y_min + scaled_font_size * 1.5 end
                        label_toggle = not label_toggle
                        draw_text_safe(label, lx + 4, label_y, col, scaled_font_size)
                    end
                end
            end

            if settings.show_vertical_cursor then
                local _, dist_target = get_closest_edge(owner_data.world_x, target_data.act_param)
                if dist_target then
                    local cur_col = colors.White
                    for _, mv in ipairs(sorted) do
                        if dist_target <= mv.ar / 100.0 then
                            cur_col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                            break
                        end
                    end
                    local x = get_screen_x(dist_target)
                    if x then draw_thick_line(x, y_min, x, y_max, scaled_thickness * 2, cur_col) end
                end
            end
            return
        end
    end

    local limits = spacing_thresholds[owner_data.real_name] or fallback_spacing
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
        local _, dist_target = get_closest_edge(owner_data.world_x, target_data.act_param)
        if dist_target then
            local c = colors.Green
            for _, zone in ipairs(sorted) do
                if dist_target <= zone.dist then c = zone.color; break end
            end
            local x = get_screen_x(dist_target)
            if x then draw_thick_line(x, y_min, x, y_max, scaled_thickness, c) end
        end
    end
end

local function draw_debug_values(cache, opponent_cache, p_idx)
    if not cache.valid or not opponent_cache.valid then return end
    local current_dist = math.abs(cache.world_x - opponent_cache.world_x) * 100
    local _, zone_dist = get_closest_edge(cache.world_x, opponent_cache.act_param)
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
    local limits = spacing_thresholds[cache.real_name]
    if limits then
        imgui.text(string.format("L:%.1f | R:%.1f | Y:%.1f", limits.low*100, limits.red*100, limits.yellow*100))
    else imgui.text("Using Fallback Limits") end
    
    imgui.separator()
end

local vmode_names = { "Full Screen", "Top Half", "Bottom Half", "None" }

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
    return has_changed, new_mode
end

local function draw_advanced_moves_menu(pi, rname, cdata)
    local lbl = string.format(">> ADVANCED ZONE CONFIGURATION (%s)##adv%d", rname, pi)
    if styled_tree_node(lbl, COL_YELLOW) then
        if not cdata or not cdata.moves or #cdata.moves == 0 then
            imgui.text_colored("(no moves logged)", COL_GREY)
        else
            local prefs = get_char_prefs(pi, rname)
            local ar_min, ar_max = get_ar_range(pi, rname)
            local max_ar_per_gb = {}
            for _, entry in ipairs(cdata.moves) do
                local gb = entry.guard_bit or 0
                if gb > 0 then
                    if not max_ar_per_gb[gb] or entry.ar > max_ar_per_gb[gb] then
                        max_ar_per_gb[gb] = entry.ar
                    end
                end
            end

            if imgui.button("Show All##"..pi) then
                for _, mv in ipairs(cdata.moves) do set_move_visible(pi, rname, mv.input, true) end
            end
            imgui.same_line()
            if imgui.button("Hide All##"..pi) then
                for _, mv in ipairs(cdata.moves) do set_move_visible(pi, rname, mv.input, false) end
            end
            imgui.same_line()
            if imgui.button("Max Only##"..pi) then
                for _, mv in ipairs(cdata.moves) do
                    local gb_val = mv.guard_bit or 0
                    if gb_val > 0 and mv.ar == max_ar_per_gb[gb_val] then
                        set_move_visible(pi, rname, mv.input, true)
                    else
                        set_move_visible(pi, rname, mv.input, false)
                    end
                end
            end
            imgui.separator()

            if prefs.red then imgui.text_colored(string.format("RED ZONE : [%s]  %.2f", prefs.red.input, prefs.red.ar), COL_RED) end
            if prefs.low then imgui.text_colored(string.format("LOW RANGE: [%s]  %.2f", prefs.low.input, prefs.low.ar), COL_LOW) end
            if prefs.red or prefs.low then imgui.separator() end

            for _, mv in ipairs(cdata.moves) do
                local col = ar_to_color_abgr(mv.ar, ar_min, ar_max)
                local tag = ""
                if prefs.red and prefs.red.input == mv.input then tag = " [R]" end
                if prefs.low and prefs.low.input == mv.input then tag = tag .. " [L]" end

                local gb_val = mv.guard_bit or 0
                local gb_name = get_guard_type_name(gb_val)
                local is_max_for_gb = (gb_val > 0 and mv.ar == max_ar_per_gb[gb_val])

                local visible = is_move_visible(pi, rname, mv.input)
                local chk_changed, chk_new = imgui.checkbox(
                    string.format("%-8s  %.1f%s [%s]##chk_%s_%s_%d", mv.input, mv.ar, tag, gb_name, rname, mv.input, pi),
                    visible)

                if chk_changed then
                    set_move_visible(pi, rname, mv.input, chk_new)
                end

                imgui.same_line()
                imgui.text_colored("[#]", col)

                if is_max_for_gb then
                    imgui.same_line()
                    imgui.text_colored(" * [MAX " .. gb_name .. "]", COL_GOLD)
                end
            end
        end
        imgui.tree_pop()
    end
end

local function draw_config_ui()
    -- ==========================================
    -- 1. GLOBAL SETTINGS (Font, Thickness, Attack Lock)
    -- ==========================================
    if styled_header("--- GLOBAL SETTINGS ---", UI_THEME.hdr_rules) then
        local c_fs, v_fs = safe_input_int("Master Font Quality (Px)", config.stats_font_size)
        if c_fs then config.stats_font_size = v_fs; save_settings(); try_load_font() end

        local changed_lock, new_lock = imgui.checkbox("Auto-Lock on Attack (Freeze during active frames)", config.use_attack_lock)
        if changed_lock then config.use_attack_lock = new_lock; save_settings() end

        local changed_op, new_op = imgui.drag_int("Zone Opacity (%)", config.zone_opacity, 1, 0, 100)
        if changed_op then config.zone_opacity = new_op; save_settings() end
    end

    -- ==========================================
    -- 3. PLAYER 1 SETTINGS
    -- ==========================================
    local changed = false; local c = false
    if styled_header("[ PLAYER 1 SETTINGS ]", UI_THEME.hdr_session_1) then
        c, config.p1_show_all = imgui.checkbox("SHOW ALL P1 OVERLAYS##p1_master", config.p1_show_all); if c then changed = true end
        imgui.separator()
        
        local rname = get_real_name(detected_infos[0] and detected_infos[0].name or "?")
        local cdata = advanced_data[rname]
        if cdata then
            c, config.p1_advanced_mode = imgui.checkbox("Enable Advanced Mode (Distance Logger)##p1", config.p1_advanced_mode); if c then changed = true end
            if not config.p1_advanced_mode then
                if styled_tree_node(">> ZONE CONFIGURATION (" .. rname .. ")##p1", COL_YELLOW) then
                    local prefs = get_char_prefs(0, rname)
                    local move_names = { "None" }
                    local red_idx, low_idx = 1, 1
                    if cdata.moves then
                        for i, mv in ipairs(cdata.moves) do
                            table.insert(move_names, string.format("[%s] %.2f", mv.input, mv.ar))
                            if prefs.red and prefs.red.input == mv.input then red_idx = i + 1 end
                            if prefs.low and prefs.low.input == mv.input then low_idx = i + 1 end
                        end
                    end
                    
                    local chg_r, nv_r = imgui.combo("Red Zone Move##p1", red_idx, move_names)
                    if chg_r then 
                        if nv_r == 1 then prefs.red = nil else prefs.red = { input = cdata.moves[nv_r-1].input, ar = cdata.moves[nv_r-1].ar } end
                        save_advanced_prefs() 
                    end
                    
                    local chg_l, nv_l = imgui.combo("Low Range Move##p1", low_idx, move_names)
                    if chg_l then 
                        if nv_l == 1 then prefs.low = nil else prefs.low = { input = cdata.moves[nv_l-1].input, ar = cdata.moves[nv_l-1].ar } end
                        save_advanced_prefs() 
                    end
                    
                    local y_off = prefs.yellow_offset or 50
                    local chg_y, nv_y = imgui.drag_int("Yellow Offset (cm)##p1", y_off, 1, 0, 300)
                    if chg_y then prefs.yellow_offset = nv_y; save_advanced_prefs() end
                    
                    imgui.tree_pop()
                end
                imgui.separator()
            else
                draw_advanced_moves_menu(0, rname, cdata)
            end
        end
        imgui.separator()

        if styled_tree_node(">> HORIZONTAL LINE##p1", COL_YELLOW) then
            c, config.p1_show_horizontal_lines = imgui.checkbox("Horizontal Line##p1", config.p1_show_horizontal_lines); if c then changed = true end
            c, config.p1_line_height = imgui.drag_float("Horiz Height (0-1)##p1", config.p1_line_height, 0.005, 0.0, 1.0, "%.3f"); if c then changed = true end
            c, config.p1_show_origin_dot = imgui.checkbox("Show Origin Dot##p1", config.p1_show_origin_dot); if c then changed = true end
            if config.p1_show_origin_dot then c, config.p1_origin_dot_size = safe_input_float("Dot Size##p1", config.p1_origin_dot_size); if c then changed = true end end
            c, config.p1_end_marker_size = safe_input_float("Mark Size##p1", config.p1_end_marker_size); if c then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

        if styled_tree_node(">> JUMP ARC##p1", COL_YELLOW) then
            c, config.p1_show_jump_arc = imgui.checkbox("Show Jump Arc##p1", config.p1_show_jump_arc); if c then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

        if styled_tree_node(">> VERTICAL OVERLAY##p1", COL_YELLOW) then
            local res1, index1 = imgui.combo("Vertical Mode##p1", config.p1_vertical_mode, vmode_names)
            if res1 then config.p1_vertical_mode = index1; changed = true end
            c, config.p1_fill_bg = imgui.checkbox("Fill Zones##p1", config.p1_fill_bg); if c then changed = true end
            c, config.p1_show_markers = imgui.checkbox("Show Lines##p1", config.p1_show_markers); if c then changed = true end
            c, config.p1_show_vertical_cursor = imgui.checkbox("Show Cursor##p1", config.p1_show_vertical_cursor); if c then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

		if styled_tree_node(">> TEXT OVERLAYS##p1", COL_YELLOW) then
            local function draw_text_settings(label, prefix)
                if imgui.tree_node(label) then
				    imgui.text("GENERAL")

                    local cp, np = imgui.checkbox("Enable##"..prefix, config[prefix.."_show"]); if cp then config[prefix.."_show"] = np; changed = true end
											imgui.same_line()
                    local ccol, ncol = imgui.checkbox("Color Text##"..prefix.."_col", config[prefix.."_color_text"]); if ccol then config[prefix.."_color_text"] = ncol; changed = true end

    imgui.text("TITLE")

                    -- Injection of Title/Name specifically for zones
                    if string.find(prefix, "zone") then
                        local czt, nzt = imgui.checkbox("Show Zone Title##"..prefix.."_zt", config[prefix.."_show_title"]); if czt then config[prefix.."_show_title"] = nzt; changed = true end
						imgui.same_line()
                        local cmn, nmn = imgui.checkbox("Show Move Name##"..prefix.."_mn", config[prefix.."_show_name"]); if cmn then config[prefix.."_show_name"] = nmn; changed = true end
                    end

                    local rad_changed, new_mode = draw_pos_radios("_"..prefix, config[prefix.."_pos_mode"]); if rad_changed then config[prefix.."_pos_mode"] = new_mode; changed = true end
                    
                    if config[prefix.."_pos_mode"] == 3 then
                        local cx, vx = imgui.drag_float("Fixed X (0-1)##"..prefix.."_x", config[prefix.."_fixed_x"], 0.005, 0.0, 1.0, "%.3f"); if cx then config[prefix.."_fixed_x"] = vx; changed = true end
                        local cy, vy = imgui.drag_float("Fixed Y (0-1)##"..prefix.."_y", config[prefix.."_fixed_y"], 0.005, 0.0, 1.0, "%.3f"); if cy then config[prefix.."_fixed_y"] = vy; changed = true end
                    elseif config[prefix.."_pos_mode"] == 2 then
                        local cx, vx = safe_input_float("Root Offset X##"..prefix.."_rox", config[prefix.."_root_off_x"]); if cx then config[prefix.."_root_off_x"] = vx; changed = true end
                        local cy, vy = safe_input_float("Root Offset Y##"..prefix.."_roy", config[prefix.."_root_off_y"]); if cy then config[prefix.."_root_off_y"] = vy; changed = true end
                    else
                        local cx, vx = safe_input_float("Head Offset X##"..prefix.."_hox", config[prefix.."_head_off_x"]); if cx then config[prefix.."_head_off_x"] = vx; changed = true end
                        local cy, vy = safe_input_float("Head Offset Y##"..prefix.."_hoy", config[prefix.."_head_off_y"]); if cy then config[prefix.."_head_off_y"] = vy; changed = true end
                    end
                    imgui.text_colored("Size is fixed to Master Font Quality", COL_GREY)
                    imgui.tree_pop()
                end
            end

            -- Application aux 3 catégories (P1)
            draw_text_settings("P1 Text: CrossUp", "p1_crossup")
            draw_text_settings("P1 Text: My Zone (Self)", "p1_my_zone")
            draw_text_settings("P1 Text: Opponent Zone (Target)", "p1_opp_zone")
            
            imgui.tree_pop()
        end
	end

    -- ==========================================
    -- 4. PLAYER 2 SETTINGS
    -- ==========================================
    if styled_header("[ PLAYER 2 SETTINGS ]", UI_THEME.hdr_session_2) then
        c, config.p2_show_all = imgui.checkbox("SHOW ALL P2 OVERLAYS##p2_master", config.p2_show_all); if c then changed = true end
        imgui.separator()
        
        local rname = get_real_name(detected_infos[1] and detected_infos[1].name or "?")
        local cdata = advanced_data[rname]
        if cdata then
            c, config.p2_advanced_mode = imgui.checkbox("Enable Advanced Mode (Distance Logger)##p2", config.p2_advanced_mode); if c then changed = true end
            if not config.p2_advanced_mode then
                if styled_tree_node(">> ZONE CONFIGURATION (" .. rname .. ")##p2", COL_YELLOW) then
                    local prefs = get_char_prefs(1, rname)
                    local move_names = { "None" }
                    local red_idx, low_idx = 1, 1
                    if cdata.moves then
                        for i, mv in ipairs(cdata.moves) do
                            table.insert(move_names, string.format("[%s] %.2f", mv.input, mv.ar))
                            if prefs.red and prefs.red.input == mv.input then red_idx = i + 1 end
                            if prefs.low and prefs.low.input == mv.input then low_idx = i + 1 end
                        end
                    end
                    
                    local chg_r, nv_r = imgui.combo("Red Zone Move##p2", red_idx, move_names)
                    if chg_r then 
                        if nv_r == 1 then prefs.red = nil else prefs.red = { input = cdata.moves[nv_r-1].input, ar = cdata.moves[nv_r-1].ar } end
                        save_advanced_prefs() 
                    end
                    
                    local chg_l, nv_l = imgui.combo("Low Range Move##p2", low_idx, move_names)
                    if chg_l then 
                        if nv_l == 1 then prefs.low = nil else prefs.low = { input = cdata.moves[nv_l-1].input, ar = cdata.moves[nv_l-1].ar } end
                        save_advanced_prefs() 
                    end
                    
                    local y_off = prefs.yellow_offset or 50
                    local chg_y, nv_y = imgui.drag_int("Yellow Offset (cm)##p2", y_off, 1, 0, 300)
                    if chg_y then prefs.yellow_offset = nv_y; save_advanced_prefs() end
                    
                    imgui.tree_pop()
                end
                imgui.separator()
            else
                draw_advanced_moves_menu(1, rname, cdata)
            end
        end
imgui.separator()
        if styled_tree_node(">> HORIZONTAL LINE##p2", COL_YELLOW) then
            c, config.p2_show_horizontal_lines = imgui.checkbox("Horizontal Line##p2", config.p2_show_horizontal_lines); if c then changed = true end
            c, config.p2_line_height = imgui.drag_float("Horiz Height (0-1)##p2", config.p2_line_height, 0.005, 0.0, 1.0, "%.3f"); if c then changed = true end
            c, config.p2_show_origin_dot = imgui.checkbox("Show Origin Dot##p2", config.p2_show_origin_dot); if c then changed = true end
            if config.p2_show_origin_dot then c, config.p2_origin_dot_size = safe_input_float("Dot Size##p2", config.p2_origin_dot_size); if c then changed = true end end
            c, config.p2_end_marker_size = safe_input_float("Mark Size##p2", config.p2_end_marker_size); if c then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

        if styled_tree_node(">> JUMP ARC##p2", COL_YELLOW) then
            c, config.p2_show_jump_arc = imgui.checkbox("Show Jump Arc##p2", config.p2_show_jump_arc); if c then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

        if styled_tree_node(">> VERTICAL OVERLAY##p2", COL_YELLOW) then
            local res2, index2 = imgui.combo("Vertical Mode##p2", config.p2_vertical_mode, vmode_names)
            if res2 then config.p2_vertical_mode = index2; changed = true end
            c, config.p2_fill_bg = imgui.checkbox("Fill Zones##p2", config.p2_fill_bg); if c then changed = true end
            c, config.p2_show_markers = imgui.checkbox("Show Lines##p2", config.p2_show_markers); if c then changed = true end
            c, config.p2_show_vertical_cursor = imgui.checkbox("Show Cursor##p2", config.p2_show_vertical_cursor); if c then changed = true end
            imgui.tree_pop()
        end
        imgui.separator()

        if styled_tree_node(">> TEXT OVERLAYS##p2", COL_YELLOW) then
            local function draw_text_settings(label, prefix)
                if imgui.tree_node(label) then
					imgui.text("GENERAL")
                    local cp, np = imgui.checkbox("Enable##"..prefix, config[prefix.."_show"]); if cp then config[prefix.."_show"] = np; changed = true end
                    imgui.same_line()
                    local ccol, ncol = imgui.checkbox("Color Text##"..prefix.."_col", config[prefix.."_color_text"]); if ccol then config[prefix.."_color_text"] = ncol; changed = true end

                    -- Injection of Title/Name specifically for zones
                    if string.find(prefix, "zone") then
					imgui.text("TITLE")

                        local czt, nzt = imgui.checkbox("Show Zone Title##"..prefix.."_zt", config[prefix.."_show_title"]); if czt then config[prefix.."_show_title"] = nzt; changed = true end
                        imgui.same_line()
                        local cmn, nmn = imgui.checkbox("Show Move Name##"..prefix.."_mn", config[prefix.."_show_name"]); if cmn then config[prefix.."_show_name"] = nmn; changed = true end
                    end

                    local rad_changed, new_mode = draw_pos_radios("_"..prefix, config[prefix.."_pos_mode"]); if rad_changed then config[prefix.."_pos_mode"] = new_mode; changed = true end
                    
                    if config[prefix.."_pos_mode"] == 3 then
                        local cx, vx = imgui.drag_float("Fixed X (0-1)##"..prefix.."_x", config[prefix.."_fixed_x"], 0.005, 0.0, 1.0, "%.3f"); if cx then config[prefix.."_fixed_x"] = vx; changed = true end
                        local cy, vy = imgui.drag_float("Fixed Y (0-1)##"..prefix.."_y", config[prefix.."_fixed_y"], 0.005, 0.0, 1.0, "%.3f"); if cy then config[prefix.."_fixed_y"] = vy; changed = true end
                    elseif config[prefix.."_pos_mode"] == 2 then
                        local cx, vx = safe_input_float("Root Offset X##"..prefix.."_rox", config[prefix.."_root_off_x"]); if cx then config[prefix.."_root_off_x"] = vx; changed = true end
                        local cy, vy = safe_input_float("Root Offset Y##"..prefix.."_roy", config[prefix.."_root_off_y"]); if cy then config[prefix.."_root_off_y"] = vy; changed = true end
                    else
                        local cx, vx = safe_input_float("Head Offset X##"..prefix.."_hox", config[prefix.."_head_off_x"]); if cx then config[prefix.."_head_off_x"] = vx; changed = true end
                        local cy, vy = safe_input_float("Head Offset Y##"..prefix.."_hoy", config[prefix.."_head_off_y"]); if cy then config[prefix.."_head_off_y"] = vy; changed = true end
                    end
                    imgui.text_colored("Size is fixed to Master Font Quality", COL_GREY)
                    imgui.tree_pop()
                end
            end

            -- Application aux 3 catégories (P2)
            draw_text_settings("P2 Text: CrossUp", "p2_crossup")
            draw_text_settings("P2 Text: My Zone (Self)", "p2_my_zone")
            draw_text_settings("P2 Text: Opponent Zone (Target)", "p2_opp_zone")
            
            imgui.tree_pop()
        end
	end
    if changed then save_settings() end

    -- ==========================================
    -- 5. DEBUG VALUES (Live)
    -- ==========================================
    if styled_header("--- DEBUG VALUES (Live) ---", UI_THEME.hdr_info) then
        imgui.text_colored("[LOAD STATUS]", COL_GREY)
        imgui.text("Dist Config: "); imgui.same_line(); imgui.text_colored(debug_dist_status, debug_dist_color)
        imgui.text("Jump File: "); imgui.same_line(); imgui.text_colored(debug_jump_status, debug_jump_color)
        imgui.text("Font Status: " .. custom_font.status)
        imgui.separator()

        draw_debug_values(p1_cache, p2_cache, 0)
        draw_debug_values(p2_cache, p1_cache, 1)
    end
end

-- =========================================================
-- [EVENTS]
-- =========================================================

if config.p1_advanced_mode or config.p2_advanced_mode then load_advanced_data() end

re.on_frame(function()
    if gBattle == nil then gBattle = sdk.find_type_definition("gBattle") end; if gBattle == nil then return end

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
        
        if config.use_attack_lock then
            process_attack_lock(0, p1_cache)
            process_attack_lock(1, p2_cache)
        else
            if lock_states[0].active then lock_states[0].active = false end
            if lock_states[1].active then lock_states[1].active = false end
        end
    end
    
    local scale_factor = sh / 1080.0
    local p1_display = nil
    local p2_display = nil

    if p1_cache.valid and p2_cache.valid then
        update_jump_state_logic(0, p1_cache)
        update_jump_state_logic(1, p2_cache)

        p1_display = { id = 0, world_x = p1_cache.world_x, world_y = p1_cache.world_y, real_name = p1_cache.real_name, act_param = p1_cache.act_param, valid = true, facing_right = p1_cache.facing_right, head_screen_pos = p1_cache.head_screen_pos, root_screen_pos = p1_cache.root_screen_pos }
        p2_display = { id = 1, world_x = p2_cache.world_x, world_y = p2_cache.world_y, real_name = p2_cache.real_name, act_param = p2_cache.act_param, valid = true, facing_right = p2_cache.facing_right, head_screen_pos = p2_cache.head_screen_pos, root_screen_pos = p2_cache.root_screen_pos }

        if config.use_attack_lock then
            if lock_states[0].active then
                 p1_display.world_x = lock_states[0].locked_x
                 p1_display.world_y = lock_states[0].locked_y
            end
            if lock_states[1].active then
                 p2_display.world_x = lock_states[1].locked_x
                 p2_display.world_y = lock_states[1].locked_y
            end
        end

        local p1_settings = {
            show_horizontal_lines = config.p1_show_horizontal_lines, end_marker_size = config.p1_end_marker_size,
            end_marker_offset_y = config.p1_end_marker_offset_y, line_height = config.p1_line_height,
            show_origin_dot = config.p1_show_origin_dot, origin_dot_size = config.p1_origin_dot_size
        }
        local p2_settings = {
            show_horizontal_lines = config.p2_show_horizontal_lines, end_marker_size = config.p2_end_marker_size,
            end_marker_offset_y = config.p2_end_marker_offset_y, line_height = config.p2_line_height,
            show_origin_dot = config.p2_show_origin_dot, origin_dot_size = config.p2_origin_dot_size
        }

        if config.p1_show_all then
            draw_spacing_horizontal(p1_display, p2_display, p1_settings, scale_factor)
            draw_jump_arc(0, p1_cache, p2_cache, { show_jump_arc = config.p1_show_jump_arc }, scale_factor)
            draw_vertical_overlay(p1_display, p2_display, {
                show_markers=config.p1_show_markers, fill_bg=config.p1_fill_bg,
                vertical_mode=config.p1_vertical_mode, show_vertical_cursor=config.p1_show_vertical_cursor
            }, scale_factor)
        end

        if config.p2_show_all then
            draw_spacing_horizontal(p2_display, p1_display, p2_settings, scale_factor)
            draw_jump_arc(1, p2_cache, p1_cache, { show_jump_arc = config.p2_show_jump_arc }, scale_factor)
            draw_vertical_overlay(p2_display, p1_display, {
                show_markers=config.p2_show_markers, fill_bg=config.p2_fill_bg,
                vertical_mode=config.p2_vertical_mode, show_vertical_cursor=config.p2_show_vertical_cursor
            }, scale_factor)
        end
    end

    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0)
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    
    local win_flags = 1 | 2 | 4 | 8 | 512 | 786432 | 128

    if imgui.begin_window("CrossUpOverlay", true, win_flags) then
        if custom_font.obj then imgui.push_font(custom_font.obj) end

        if p1_cache.valid and p2_cache.valid then
            local base_size = custom_font.loaded_size
            if base_size > 0 then
                
                local function draw_text_element(cache, opponent, enabled, color_text, pos_mode, txt_func, head_off_x, head_off_y, root_off_x, root_off_y, fix_x, fix_y)
                    if enabled then
                        local txt, col = txt_func(cache, opponent)
                        if txt == "" then return end
                        
                        if not color_text then col = 0xFFFFFFFF end
                        
                        if pos_mode == 3 then
                            -- Screen Fixed Logic
                            local lines = {}
                            for s in string.gmatch(txt, "[^\r\n]+") do table.insert(lines, s) end
                            
                            local total_height = 0
                            for _, line in ipairs(lines) do total_height = total_height + imgui.calc_text_size(line).y end
                            
                            local current_y = (sh * fix_y) - (total_height / 2)
                            
                            for _, line in ipairs(lines) do
                                local text_width = imgui.calc_text_size(line).x
                                local text_height = imgui.calc_text_size(line).y
                                local x_pos = (sw * fix_x) - (text_width / 2)
                                
                                imgui.set_cursor_pos(Vector2f.new(x_pos + 2, current_y + 2))
                                imgui.text_colored(line, 0xFF000000)
                                imgui.set_cursor_pos(Vector2f.new(x_pos, current_y))
                                imgui.text_colored(line, col)
                                
                                current_y = current_y + text_height
                            end
                        else
                            -- Dynamic Logic (1 = Head, 2 = Root)
                            local target_pos = (pos_mode == 1) and cache.head_screen_pos or cache.root_screen_pos
                            local active_off_x = (pos_mode == 1) and head_off_x or root_off_x
                            local active_off_y = (pos_mode == 1) and head_off_y or root_off_y
                            
                            if target_pos then
                                local directed_off_x = cache.facing_right and active_off_x or -active_off_x
                                draw_text_above_head_independent(txt, target_pos, col, directed_off_x, active_off_y, scale_factor)
                            end
                        end
                    end
                end
				
                if p1_display and p2_display then
                    -- ====== P1 TEXTS ======
                    if config.p1_show_all then
                        draw_text_element(p1_display, p2_display, config.p1_crossup_show, config.p1_crossup_color_text, config.p1_crossup_pos_mode, get_crossup_info, config.p1_crossup_head_off_x, config.p1_crossup_head_off_y, config.p1_crossup_root_off_x, config.p1_crossup_root_off_y, config.p1_crossup_fixed_x, config.p1_crossup_fixed_y)
                        draw_text_element(p1_display, p2_display, config.p1_my_zone_show, config.p1_my_zone_color_text, config.p1_my_zone_pos_mode, get_my_zone_info, config.p1_my_zone_head_off_x, config.p1_my_zone_head_off_y, config.p1_my_zone_root_off_x, config.p1_my_zone_root_off_y, config.p1_my_zone_fixed_x, config.p1_my_zone_fixed_y)
                        draw_text_element(p1_display, p2_display, config.p1_opp_zone_show, config.p1_opp_zone_color_text, config.p1_opp_zone_pos_mode, get_opp_zone_info, config.p1_opp_zone_head_off_x, config.p1_opp_zone_head_off_y, config.p1_opp_zone_root_off_x, config.p1_opp_zone_root_off_y, config.p1_opp_zone_fixed_x, config.p1_opp_zone_fixed_y)
                    end

                    -- ====== P2 TEXTS ======
                    if config.p2_show_all then
                        draw_text_element(p2_display, p1_display, config.p2_crossup_show, config.p2_crossup_color_text, config.p2_crossup_pos_mode, get_crossup_info, config.p2_crossup_head_off_x, config.p2_crossup_head_off_y, config.p2_crossup_root_off_x, config.p2_crossup_root_off_y, config.p2_crossup_fixed_x, config.p2_crossup_fixed_y)
                        draw_text_element(p2_display, p1_display, config.p2_my_zone_show, config.p2_my_zone_color_text, config.p2_my_zone_pos_mode, get_my_zone_info, config.p2_my_zone_head_off_x, config.p2_my_zone_head_off_y, config.p2_my_zone_root_off_x, config.p2_my_zone_root_off_y, config.p2_my_zone_fixed_x, config.p2_my_zone_fixed_y)
                        draw_text_element(p2_display, p1_display, config.p2_opp_zone_show, config.p2_opp_zone_color_text, config.p2_opp_zone_pos_mode, get_opp_zone_info, config.p2_opp_zone_head_off_x, config.p2_opp_zone_head_off_y, config.p2_opp_zone_root_off_x, config.p2_opp_zone_root_off_y, config.p2_opp_zone_fixed_x, config.p2_opp_zone_fixed_y)
                    end
                end
                
            end
        end

        if custom_font.obj then imgui.pop_font() end
        imgui.end_window()
    end
    imgui.pop_style_color(1); imgui.pop_style_var(2)

    if config.show_debug_window then
        if first_draw then
            imgui.set_next_window_pos(Vector2f.new(config.window_pos_x, config.window_pos_y), 1 << 3)
            first_draw = false
        end

        if imgui.begin_window("SF6 Distance Viewer Config", true, 0) then
            -- Checkbox to hide the floating window from within itself
            local chg_ov, new_ov = imgui.checkbox("Afficher Fenêtre Flottante", config.show_debug_window)
					imgui.same_line()
        if imgui.button("Reload Data") then load_advanced_data() end
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
            imgui.end_window()
        end
    end
    collectgarbage("step", 1)
end)

re.on_draw_ui(function()
    if imgui.tree_node("SF6 DISTANCE VIEWER") then
        local changed_ov, new_ov = imgui.checkbox("Afficher Fenêtre Flottante", config.show_debug_window)
        if changed_ov then
            config.show_debug_window = new_ov
            first_draw = true
            save_settings()
        end
							imgui.same_line()
        if imgui.button("Reload Data") then load_advanced_data() end


        if not config.show_debug_window then
            imgui.separator()
            imgui.text_colored("MODE MENU REFRAMEWORK (Fenêtre Masquée)", COL_CYAN)
            draw_config_ui()
        end

        imgui.tree_pop()
    end
end)