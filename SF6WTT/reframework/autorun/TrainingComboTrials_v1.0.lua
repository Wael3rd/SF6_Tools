local sdk = sdk
local imgui = imgui
local re = re
local json = json
local d2d = d2d

pcall(function()
    -- CORRECTION CRITIQUE DU CHEMIN (REFramework ajoute déjà reframework/data/)
    if fs and fs.create_dir then fs.create_dir("exceptions") end
end)


local ui_state = { viewed_player = 0 }

-- COMPTEUR DE FRAMES EXACT (Insensible au lag, calé sur le moteur)
local engine_frame_count = 0

local DIR_MAP = {
    [0] = "5",
    [1] = "8",
    [2] = "2",
    [4] = "4",
    [8] = "6",
    [5] = "7",
    [6] = "1",
    [9] = "9",
    [10] = "3",
    [15] = "*"
}
local BTN_MASKS = { [16] = "LP", [32] = "MP", [64] = "HP", [128] = "LK", [256] = "MK", [512] = "HK" }

local esf_names_map = {
    ["ESF_001"] = "Ryu",
    ["ESF_002"] = "Luke",
    ["ESF_003"] = "Kimberly",
    ["ESF_004"] = "ChunLi",
    ["ESF_005"] = "Manon",
    ["ESF_006"] = "Zangief",
    ["ESF_007"] = "JP",
    ["ESF_008"] = "Dhalsim",
    ["ESF_009"] = "Cammy",
    ["ESF_010"] = "Ken",
    ["ESF_011"] = "DeeJay",
    ["ESF_012"] = "Lily",
    ["ESF_013"] = "AKI",
    ["ESF_014"] = "Rashid",
    ["ESF_015"] = "Blanka",
    ["ESF_016"] = "Juri",
    ["ESF_017"] = "Marisa",
    ["ESF_018"] = "Guile",
    ["ESF_019"] = "Ed",
    ["ESF_020"] = "EHonda",
    ["ESF_021"] = "Jamie",
    ["ESF_022"] = "Akuma",
    ["ESF_025"] = "Sagat",
    ["ESF_026"] = "MBison",
    ["ESF_027"] = "Terry",
    ["ESF_028"] = "Mai",
    ["ESF_029"] = "Elena",
    ["ESF_030"] = "CViper",
    ["ESF_031"] = "Alex"
}


local common_exceptions = {}
pcall(function()
    local loaded = json.load_file("exceptions/Common.json")
    if loaded then common_exceptions = loaded end
end)

local players = {
    [0] = {
        log = {}, prev_act_id = -1, prev_act_frame = -1, last_combo_count = 0,
        bcm_cache = {}, trigger_mask_cache = {}, cache_built = false,
        last_bcm_ptr = "", last_direct_input = 0, input_history_queue = {},
        profile_name = "Unknown", last_profile_name = "", exceptions = {},
        editing_id = -1, edit_ignore = false, edit_force = false, edit_text = "",
		edit_is_common = false, edit_holdable = false, edit_absorb_ids = "",
        edit_charge_min = "", edit_charge_max = "", enable_deep_logging = false,
        edit_ignore_prev_id = "", edit_ignore_prev_frames = "5"
    },
    [1] = {
        log = {}, prev_act_id = -1, prev_act_frame = -1, last_combo_count = 0,
        bcm_cache = {}, trigger_mask_cache = {}, cache_built = false,
        last_bcm_ptr = "", last_direct_input = 0, input_history_queue = {},
        profile_name = "Unknown", last_profile_name = "", exceptions = {},
        editing_id = -1, edit_ignore = false, edit_force = false, edit_text = "",
		edit_is_common = false, edit_holdable = false, edit_absorb_ids = "",
        edit_charge_min = "", edit_charge_max = "", enable_deep_logging = false,
        edit_ignore_prev_id = "", edit_ignore_prev_frames = "5"
    }
}

-- ÉTAT DU COMBO TRIAL GLOBAL
local trial_state = {
    is_recording = false,
    recording_player = 0,
    is_playing = false,
    playing_player = 0,
    sequence = {},
    current_step = 1,
    success_timer = 0,
    fail_timer = 0,
    fail_reason = nil,
    last_recorded_frame = 0,
    last_played_frame = 0,
    start_pos_p1 = nil,
    start_pos_p2 = nil,
    start_pos_p1_raw = nil,
    start_pos_p2_raw = nil,
    pending_exact_pos = 0,
    saved_start_location = nil,
    flip_inputs = false,   -- Définit si on doit inverser visuellement le cartouche
    _rec_gauges = nil,     -- Snapshot jauges au début du recording
    _rec_hit_type = nil,   -- CH/PC détecté au premier hit
    _saved_vital_p1 = nil,
    _saved_vital_p2 = nil,
    _pending_victim_hp = nil,
    _pending_attacker_hp = nil,
    _rec_pending_snapshot = 0,
    _was_playing = false,   -- État précédent pour détecter les transitions
    _step1_wrong_pending = false, -- Première action : fail seulement si le coup touche
    _demo_backup_slot = nil,       -- Sandbox slot backup for demo
	_step1_wrong_pending = false, -- Première action : fail seulement si le coup touche
    _demo_backup_slot = nil       -- Sandbox slot backup for demo
}

-- =========================================================
-- DEMO ENGINE STATE
-- =========================================================
local demo_state = {
    is_playing = false,
    current_frame = 0,
    current_step = 1,
    sequence = {},
    p1_mask = 0
}
local p_id_stack = {}
local tick_done_this_frame = false



-- =========================================================
-- INPUT LOGGER (JSON EXPORT)
-- =========================================================
local logger_state = {
    rec_p1 = { active = false, has_started = false, data = {}, facing_right = false, char_name = "P1_Waiting" },
    rec_p2 = { active = false, has_started = false, data = {}, facing_right = false, char_name = "P2_Waiting" },
    dual_active = false,
    window_open = false,
    last_export_name = nil,
    last_export_name_2 = nil
}

local function logger_update_char_names()
    if players[0].profile_name ~= "Unknown" then
        logger_state.rec_p1.char_name = players[0].profile_name
    end
    if players[1].profile_name ~= "Unknown" then
        logger_state.rec_p2.char_name = players[1].profile_name
    end
end

local function logger_get_numpad_notation(dir_val)
    local u = (dir_val & 1) ~= 0
    local d = (dir_val & 2) ~= 0
    local r = (dir_val & 4) ~= 0
    local l = (dir_val & 8) ~= 0

    if u and l then return "7"
    elseif u and r then return "9"
    elseif d and l then return "1"
    elseif d and r then return "3"
    elseif u then return "8"
    elseif d then return "2"
    elseif l then return "4"
    elseif r then return "6"
    end
    return "5"
end

local function logger_get_btn_string(val)
    local str = ""
    if (val & 16) ~= 0  then str = str .. "+LP" end
    if (val & 128) ~= 0 then str = str .. "+LK" end
    if (val & 32) ~= 0  then str = str .. "+MP" end
    if (val & 256) ~= 0 then str = str .. "+MK" end
    if (val & 64) ~= 0  then str = str .. "+HP" end
    if (val & 512) ~= 0 then str = str .. "+HK" end
    return str
end

local function logger_export(rec_struct, suffix)
    local output = { 
        ReplayInputRecord = true, 
        timeline = {} 
    }
    
    for i, entry in ipairs(rec_struct.data) do
        local frame_str = tostring(entry.frames) .. "f"
        local dir_str = logger_get_numpad_notation(entry.dir)
        local btn_str = logger_get_btn_string(entry.btn)
        local line = string.format("%s : %s%s", frame_str, dir_str, btn_str)
        table.insert(output.timeline, line)
    end
    
    local timestamp = os.date("%Y%m%d%H%M%S")
    local name = rec_struct.char_name or "Unknown"
    local safe_name = name:gsub("%s+", "")
    if suffix then safe_name = safe_name .. suffix end
    
    local short_filename = "ReplayInputRecord_" .. safe_name .. "_" .. timestamp .. ".json"
    local full_path = "ReplayRecords/" .. short_filename
    
    if fs.create_dir then fs.create_dir("ReplayRecords") end
    json.dump_file(full_path, output)

    return short_filename
end

local function logger_update_recording(rec_table, current_dir, current_btn)
    local buffer = rec_table.data
    local last_entry = buffer[#buffer] 
    local is_same = false
    
    if last_entry and last_entry.dir == current_dir and last_entry.btn == current_btn then 
        is_same = true 
    end
    
    if is_same then
        last_entry.frames = last_entry.frames + 1
    else
        table.insert(buffer, { dir=current_dir, btn=current_btn, frames=1 })
    end
end

local function logger_process_game_state()
    logger_update_char_names()

    local gBattle = sdk.find_type_definition("gBattle")
    local player_mgr = nil
    
    if gBattle then
        local f_player = gBattle:get_field("Player")
        if f_player then
            player_mgr = f_player:get_data(nil)
        end
    end
    
    if not player_mgr then return end

    local is_paused = false
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pause_bit = pm:get_field("_CurrentPauseTypeBit")
        if pause_bit > 64 then is_paused = true end
    end

    local function process_player(index, rec_struct)
        local p = player_mgr:call("getPlayer", index)
        if not p then return end
        
        local is_facing_right = p:get_field("rl_dir")
        rec_struct.facing_right = is_facing_right

        if rec_struct.active and not is_paused then
            local f_input = p:get_type_definition():get_field("pl_input_new")
            local f_sw = p:get_type_definition():get_field("pl_sw_new")
            
            local d = (f_input and f_input:get_data(p)) or 0
            local b = (f_sw and f_sw:get_data(p)) or 0
            
            if not is_facing_right then
                local has_right = (d & 4) ~= 0 
                local has_left  = (d & 8) ~= 0 
                d = d & ~4 
                d = d & ~8 
                if has_right then d = d | 8 end 
                if has_left  then d = d | 4 end 
            end
            
            -- On attend la première vraie action (direction ou bouton) pour démarrer la timeline
            if not rec_struct.has_started then
                if d == 0 and b == 0 then
                    return -- On ignore tous les neutres initiaux en attendant l'action
                else
                    rec_struct.has_started = true -- C'est parti !
                end
            end
            
            logger_update_recording(rec_struct, d, b)
        end
    end

    process_player(0, logger_state.rec_p1)
    process_player(1, logger_state.rec_p2)
end

local file_system = {
    saved_combos_display_p1 = {},
    saved_combos_paths_p1 = {},
    selected_file_idx_p1 = 1,

    saved_combos_display_p2 = {},
    saved_combos_paths_p2 = {},
    selected_file_idx_p2 = 1,

    last_p1_id = -1,
    auto_load = true,
    forced_position_options = { "OFF", "FORCED", "MIRROR" }
}

-- =========================================================
-- CONFIGURATION D2D VISUALISER
-- =========================================================
local D2D_CONFIG_FILE = "CommandLogger_Visualizer.json"
local d2d_cfg = {
    enabled = true,
    auto_load = true,
    forced_position_idx = 1,
    show_p1 = true,
    show_p2 = true,
    raw_p1 = false,
    raw_p2 = false,
    mirror_p1 = false,
    mirror_p2 = false,
    show_combo_count = true,
    pos_p1 = { x = 0.050, y = 0.350 },
    pos_p2 = { x = 0.850, y = 0.350 },
    raw_pos_p1 = { x = 0.050, y = 0.350 },
    raw_pos_p2 = { x = 0.850, y = 0.350 },
    pos_trial_p1 = { x = 0.050, y = 0.350 },
    pos_trial_p2 = { x = 0.850, y = 0.350 },
    pos_trial = { x = 0.400, y = 0.150 },
    cartouche_width = 0.220,
    cartouche_height = 0.5,
    cartouche_offset_x = 0.000,
    cartouche_offset_y = 0.000,
    icon_size = 0.035,
    font_size = 0.028,
    spacing_y = 0.045,
    spacing_x = 0.005,
    text_y_offset = 0.000,
    max_history = 10,
    special_icon_scale = 1.0,
    trial_visible_steps = 7,
    ignore_auto = true,

    -- Config séparée pour le mode IDLE (pas de record/trial actif)
    idle_show_p1 = true,
    idle_show_p2 = true,
    idle_raw_p1 = false,
    idle_raw_p2 = false,
    idle_mirror_p1 = false,
    idle_mirror_p2 = false,
    idle_pos_p1 = { x = 0.050, y = 0.350 },
    idle_pos_p2 = { x = 0.850, y = 0.350 },
    idle_max_history = 10,
    raw_max_history = 19,
    idle_raw_max_history = 19,

    -- Raw Input display settings (shared across all modes)
    raw = {
        icon_size     = 0.030,
        font_size     = 0.028,
        spacing_y     = 0.040,
        text_y_offset = 0.002,
        col_frame     = 0.000,
        col_dir       = 0.050,
        slot1         = 0.100,
        slot2         = 0.140,
        slot3         = 0.180,
        slot4         = 0.220,
        slot5         = 0.260,
        slot6         = 0.300,
    },

    show_live_single_p1 = true,
    show_live_single_p2 = true,
    pos_live_single_p1 = { x = 0.050, y = 0.800 },
    pos_live_single_p2 = { x = 0.850, y = 0.800 },

    pos_trial_header = { x = 0.500, y = 0.050 },
    pos_combo_stats = { x = 0.500, y = 0.085 },
    fail_display_frames = 120,

    -- HUD Overlay (texte sur les lignes natives, même positions que HitConfirm)
    hud_global_y = -0.337,
    hud_spacing_y = 0.028,
    hud_show = true,
    hud_font_size = 20,

    colors = {
        shadow             = 0xFF000000,
        text_live          = 0xFF00FFFF,
        text_normal        = 0xFFFFFFFF,
        text_cond          = 0xFFFFCC00,
        text_dark          = 0xFF888888,
        text_dr            = 0xFF00FF00,
        bg_active          = 0xA0601070,
        bg_active_line     = 0xFFD030F0,
        bg_success         = 0x25A03080,
        bg_success_line    = 0xFFD050B0,
        bg_fail            = 0x90600000,
        bg_fail_line       = 0xFFB00000,
        bg_overlay         = 0x85000000, -- Dark shadow for fails
        bg_overlay_success = 0x40D050B0  -- NEW: Light pink tint for completed steps
    }
}

local function load_d2d_config()
    local loaded = json.load_file(D2D_CONFIG_FILE)
    if loaded then
        for k, v in pairs(loaded) do
            if type(v) == "table" and type(d2d_cfg[k]) == "table" then
                for k2, v2 in pairs(v) do d2d_cfg[k][k2] = v2 end
            else
                d2d_cfg[k] = v
            end
        end
    end
end

local function save_d2d_config()
    json.dump_file(D2D_CONFIG_FILE, d2d_cfg)
end
load_d2d_config()


-- =========================================================
-- CONTEXTE PARTAGÉ & MODULE D2D
-- =========================================================
local ctx = {
    d2d_cfg = d2d_cfg,
    trial_state = trial_state,
    players = players,
    sf6_menu_state = nil, -- set later when sf6_menu_state is created
    cached_sw = 1920,
    cached_sh = 1080,
}

local ComboTrials_D2D = require("func/ComboTrials_D2D")
ComboTrials_D2D.init(ctx)

-- (D2D rendering code is now in ComboTrials_D2D.lua)

-- =========================================================
-- SUITE DU COMMAND LOGGER D'ORIGINE
-- =========================================================

local t_med = sdk.find_type_definition("app.FBattleMediator")
if t_med then
    local m = t_med:get_method("UpdateGameInfo")
    if m then
        sdk.hook(m, function(args)
            local mgr = sdk.to_managed_object(args[2])
            if mgr then
                local pt = t_med:get_field("PlayerType"):get_data(mgr)
                if pt and pt:call("get_Length") >= 2 then
                    for i = 0, 1 do
                        local p = pt:call("GetValue", i)
                        if p then
                            local pid = p:get_type_definition():get_field("value__"):get_data(p)
                            if pid then
                                local k = string.format("ESF_%03d", pid)
                                players[i].profile_name = esf_names_map[k] or "Unknown"
                            end
                        end
                    end
                end
            end
        end, function(retval) return retval end)
    end
end

local act_id_reverse_enum = {}
do
    local td = sdk.find_type_definition("nBattle.ACT_ID")
    if td then
        for _, field in ipairs(td:get_fields()) do
            if field:is_static() and field:get_data() ~= nil then act_id_reverse_enum[field:get_data()] = field:get_name() end
        end
    end
end

local function get_exc_filename(name)
    return "exceptions/" .. name:gsub("[^%w_]", "") .. ".json"
end

local function format_charge_motion(notation)
    local opposite = { ["6"] = "4", ["8"] = "2", ["4"] = "6", ["2"] = "8", ["9"] = "1", ["3"] = "7" }
    if #notation == 2 then
        local release = notation:sub(1, 1); local press = notation:sub(2, 2); local hold = opposite[press]
        if hold then return "[" .. hold .. "]" .. press end
    end
    return notation
end

local function decode_button_mask(mask)
    local parts = {}
    if (mask & 16) ~= 0 then table.insert(parts, "LP") end
    if (mask & 32) ~= 0 then table.insert(parts, "MP") end
    if (mask & 64) ~= 0 then table.insert(parts, "HP") end
    if (mask & 128) ~= 0 then table.insert(parts, "LK") end
    if (mask & 256) ~= 0 then table.insert(parts, "MK") end
    if (mask & 512) ~= 0 then table.insert(parts, "HK") end
    return table.concat(parts, "+")
end

local function decode_ok_key(ok_key, ok_key_cond)
    local btn_count = ((ok_key_cond >> 6) & 3) + 1
    if ok_key == 144 then return "Throw" end
    if ok_key == 288 then return "Parry" end
    if ok_key == 576 then return "DI" end

    local base_btn = ""
    if ok_key == 112 then
        if btn_count == 3 then base_btn = "PPP" elseif btn_count == 2 then base_btn = "PP" else base_btn = "P" end
    elseif ok_key == 896 then
        if btn_count == 3 then base_btn = "KKK" elseif btn_count == 2 then base_btn = "KK" else base_btn = "K" end
    else
        base_btn = decode_button_mask(ok_key)
    end
    return base_btn
end

local function build_bcm_cache(player_idx)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return false end
    local cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not cmd_obj then return false end

    local cmd_data = {}
    pcall(function()
        local pCommand = cmd_obj:get_field("mpBCMResource")[player_idx]:get_field("pCommand")
        for i, entry in pairs(pCommand._entries) do
            if entry and entry.value then
                local cmds = entry.value:get_elements()
                for ci = 1, #cmds do
                    local c = cmds[ci]
                    if c then
                        local inum = c:get_field("input_num")
                        local charge_bit = c:get_field("charge_bit")
                        if inum and inum > 0 then
                            local dirs, has_charge, elems = {}, false, c:get_field("inputs"):get_elements()
                            for j = 1, math.min(#elems, inum) do
                                pcall(function()
                                    table.insert(dirs,
                                        DIR_MAP[elems[j]:get_field("normal"):get_field("ok_key_flags") & 0xF] or "5")
                                    if elems[j]:get_field("charge"):get_field("id") > 0 then has_charge = true end
                                end)
                            end
                            local raw_motion = table.concat(dirs, "")
                            raw_motion = raw_motion:gsub("23626", "236236"):gsub("21424", "214214"):gsub("626", "623")
                                :gsub("424", "421"):gsub("6314", "63214"):gsub("4136", "41236")
                            if has_charge or (charge_bit and charge_bit ~= 0) then
                                raw_motion = format_charge_motion(
                                    raw_motion)
                            end
                            if not cmd_data[entry.key] then cmd_data[entry.key] = raw_motion end
                        end
                    end
                end
            end
        end
    end)

    local cache = {}
    local mask_cache = {}
    local trigger_count = 0
    pcall(function()
        local trigs = cmd_obj:call("get_mUserEngine")[player_idx]:call("GetTrigger()"):get_elements()
        for i = 1, #trigs do
            local t = trigs[i]
            if t then
                local aid = t.action_id
                if aid > 0 then
                    local norm_ng = false
                    pcall(function() norm_ng = t:get_field("norm_NG") == true end)

                    local cmd_src = nil
                    if not norm_ng then
                        pcall(function() cmd_src = t:get_field("norm") end)
                    else
                        local use_sprt, sprt_ng = false, true
                        pcall(function() use_sprt = t:get_field("use_sprt") == true end)
                        pcall(function() sprt_ng = t:get_field("sprt_NG") == true end)
                        if use_sprt and not sprt_ng then pcall(function() cmd_src = t:get_field("sprt") end) end
                    end

                    if cmd_src then
                        local ok_key = cmd_src:get_field("ok_key_flags") or 0
                        local cmd_no = cmd_src:get_field("command_no") or -1
                        local ok_key_cond = cmd_src:get_field("ok_key_cond_flags") or 0
                        local dc_exc = cmd_src:get_field("dc_exc_flags") or 0

                        local btn = decode_ok_key(ok_key, ok_key_cond)


                        local owner_state = t:get_field("cond_owner_state_flags") or 0
                        local cat_flags = t:get_field("category_flags") or 0
                        local is_air = (owner_state == 4) or ((cat_flags & 0x40000000) ~= 0)
                        local air_prefix = is_air and "j." or ""

                        local new_str = ""
                        if cmd_no >= 0 and cmd_data[cmd_no] then
                            new_str = air_prefix .. cmd_data[cmd_no] .. (btn ~= "" and "+" .. btn or "")
                        else
                            local req_dir = ""
                            local exc_dir_bit = dc_exc & 0xF
                            if exc_dir_bit ~= 0 and exc_dir_bit ~= 5 then
                                req_dir = DIR_MAP[exc_dir_bit] or ""
                            else
                                local ok_dir_bit = ok_key & 0xF
                                if ok_dir_bit ~= 0 and ok_dir_bit ~= 15 and ok_dir_bit ~= 5 then
                                    req_dir = DIR_MAP
                                        [ok_dir_bit] or ""
                                end
                            end
                            new_str = air_prefix .. req_dir .. (btn ~= "" and btn or "Normal")
                        end

                        if not cache[aid] then
                            cache[aid] = new_str
                        end
                        mask_cache[aid] = (mask_cache[aid] or 0) | ok_key
                        trigger_count = trigger_count + 1
                    end
                end
            end
        end
    end)

    if trigger_count < 10 then return false end
    players[player_idx].bcm_cache = cache
    players[player_idx].trigger_mask_cache = mask_cache
    players[player_idx].cache_built = true
    return true
end

local skip_fields = {
    ["Owner"] = true,
    ["OwnerAdrs"] = true,
    ["mpOwner"] = true,
    ["ActionPart"] = true,
    ["_Engine"] = true,
    ["_EngineAdrs"] = true,
    ["pPlayer"] = true,
    ["Battle"] = true,
    ["Collision"] = true,
    ["Place"] = true,
    ["PartsParam"] = true,
    ["VFXSpawnID"] = true
}

local function dump_object(obj, depth, max_depth, visited)
    if not obj then return "null" end
    if type(obj) ~= "userdata" then return tostring(obj) end
    if depth > max_depth then return "<Max Depth Reached>" end

    pcall(function() obj = sdk.to_managed_object(obj) or obj end)

    local ptr_str = tostring(obj)
    if visited[ptr_str] then return "<Déjà exploré>" end
    visited[ptr_str] = true

    local tdef = obj:get_type_definition()
    if not tdef then return tostring(obj) end

    local tname = tdef:get_name()
    if tname == "sfix" or tname == "Sfix" then
        local val = "unknown"
        pcall(function() val = tostring(tdef:get_field("v"):get_data(obj)) end)
        return "sfix(" .. val .. ")"
    end

    local data = {}
    data["_type"] = tname

    local is_array = false
    pcall(function() if obj.get_elements then is_array = true end end)

    if is_array then
        local s, elements = pcall(function() return obj:get_elements() end)
        if s and elements then
            local arr = {}
            for i = 1, math.min(#elements, 25) do
                if elements[i] ~= nil then
                    table.insert(arr, dump_object(elements[i], depth + 1, max_depth, visited))
                end
            end
            if #elements > 25 then table.insert(arr, "<... et " .. tostring(#elements - 25) .. " autres>") end
            data["_elements"] = arr
            return data
        end
    end

    while tdef do
        for _, f in ipairs(tdef:get_fields()) do
            local fname = f:get_name()
            if not skip_fields[fname] and not data[fname] then
                local s, v = pcall(function() return f:get_data(obj) end)
                if s and v ~= nil then
                    data[fname] = dump_object(v, depth + 1, max_depth, visited)
                end
            end
        end
        tdef = tdef:get_parent_type()
    end

    return data
end

local function capture_deep_action_data(p_char)
    local dump = {}
    pcall(function()
        local visited = {}
        local act_param = p_char:get_field("mpActParam")
        if act_param then
            local branch = act_param:get_field("Branch")
            if branch then dump.ActParam_Branch = dump_object(branch, 0, 5, visited) end

            local trigger = act_param:get_field("Trigger")
            if trigger then dump.ActParam_Trigger = dump_object(trigger, 0, 5, visited) end

            local action_part = act_param:get_field("ActionPart")
            if action_part then
                local engine = action_part:get_field("_Engine")
                if engine then
                    local mParam = engine:get_field("mParam")
                    if mParam then
                        local action_obj = mParam:get_field("action")
                        if action_obj then
                            local keys = action_obj:get_field("Keys")
                            if keys then dump.Engine_Keys = dump_object(keys, 0, 5, visited) end
                        end
                    end
                end
            end
        end
    end)
    return dump
end

local function get_elements_safe(obj)
    if not obj then return nil end
    local s, arr = pcall(function() return obj:get_elements() end)
    if s and arr then return arr end
    pcall(function()
        local items = obj:get_field("_items")
        if items then arr = items:get_elements() end
    end)
    return arr
end

local function auto_detect_charge_min(p_char)
    local min_frame = nil
    pcall(function()
        local engine = p_char:get_field("mpActParam"):get_field("ActionPart"):get_field("_Engine")
        local keys_obj = engine:get_field("mParam"):get_field("action"):get_field("Keys")

        local groups = get_elements_safe(keys_obj)
        if groups then
            for _, group in ipairs(groups) do
                local keys = get_elements_safe(group)
                if keys then
                    for _, key in ipairs(keys) do
                        local tdef = key:get_type_definition()
                        if tdef and tdef:get_name() == "BranchKey" then
                            local type_val = key:get_field("Type")
                            if type_val and tonumber(type_val) == 100 then
                                local p00_val = key:get_field("Param00") or 0
                                if tonumber(p00_val) == 0 then
                                    local af_val = key:get_field("ActionFrame")
                                    if af_val then
                                        min_frame = tonumber(af_val)
                                        return min_frame
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    return min_frame
end

local function get_luke_charge_windows(p_char)
    local windows = { perfect_min = nil, perfect_max = nil }
    pcall(function()
        local engine = p_char:get_field("mpActParam"):get_field("ActionPart"):get_field("_Engine")
        local keys_obj = engine:get_field("mParam"):get_field("action"):get_field("Keys")

        local groups = get_elements_safe(keys_obj)
        if groups then
            local frames_by_act = {}
            for _, group in ipairs(groups) do
                local keys = get_elements_safe(group)
                if keys then
                    for _, key in ipairs(keys) do
                        local tdef = key:get_type_definition()
                        if tdef and tdef:get_name() == "BranchKey" then
                            local type_val = key:get_field("Type")
                            if type_val and tonumber(type_val) == 100 then
                                local act = tonumber(key:get_field("Action"))
                                local frm = tonumber(key:get_field("ActionFrame"))
                                if act and frm then
                                    if not frames_by_act[act] then frames_by_act[act] = {} end
                                    frames_by_act[act][frm] = true
                                end
                            end
                        end
                    end
                end
            end

            for act, frames in pairs(frames_by_act) do
                local min_f, max_f = 9999, -1
                local count = 0
                for f, _ in pairs(frames) do
                    if f < min_f then min_f = f end
                    if f > max_f then max_f = f end
                    count = count + 1
                end
                if count >= 2 then
                    windows.perfect_min = min_f
                    windows.perfect_max = max_f
                end
            end
        end
    end)
    return windows
end

local function get_action_data(p_obj)
    if not p_obj then return -1, 0, -1, 0, 0, 0 end
    local act_id, frame, state_flags, action_code, direct_input, branch_type = -1, 0, -1, 0, 0, 0
    pcall(function()
        local p_def = p_obj:get_type_definition()
        local d = (p_def:get_field("pl_input_new"):get_data(p_obj)) or 0
        local b = (p_def:get_field("pl_sw_new"):get_data(p_obj)) or 0
        direct_input = d | b

        local act_param = p_obj:get_field("mpActParam")
        if not act_param then return end
        local action_part = act_param:get_field("ActionPart")
        if action_part then
            local engine = action_part:get_field("_Engine")
            if engine then
                act_id = engine:call("get_ActionID") or -1
                local sf = engine:call("get_ActionFrame")
                if sf then frame = tonumber(sf:call("ToString()")) or 0 end
                local m_param = engine:get_field("mParam")
                if m_param then
                    local sf_field = m_param:get_type_definition():get_field("state_flags")
                    if sf_field then state_flags = tonumber(sf_field:get_data(m_param)) or -1 end
                end
            end
        end
        local ki_field = act_param:get_type_definition():get_field("KeyInput")
        if ki_field then
            local ki_data = ki_field:get_data(act_param)
            if ki_data then
                local a_field = ki_data:get_type_definition():get_field("Action")
                if a_field then action_code = tonumber(a_field:get_data(ki_data)) or 0 end
            end
        end
        local branch = act_param:get_field("Branch")
        if branch then
            local bt_field = branch:get_type_definition():get_field("BranchType")
            if bt_field then branch_type = tonumber(bt_field:get_data(branch)) or 0 end
        end
    end)
    return act_id, frame, state_flags, action_code, direct_input, branch_type
end

local function get_damage_type_safe(p_char)
    if not p_char then return 0 end

    local result = 0
    pcall(function()
        -- Ta syntaxe directe via le sucre syntaxique de REFramework
        local act_val = tonumber(p_char.act_st)

        if act_val == 27 or act_val == 32 or act_val == 35 or act_val == 38 then
            result = 1
        end
    end)

    return result
end

local function check_is_projectile(attacker_idx, attacker_obj, gBattle)
    local attacker_hs = 0
    pcall(function()
        local f_hs = attacker_obj:get_type_definition():get_field("hit_stop")
        if f_hs then attacker_hs = tonumber(tostring(f_hs:get_data(attacker_obj))) or 0 end
    end)
    return (attacker_hs == 0)
end

local function get_combo_count(p_obj)
    if not p_obj then return 0 end
    local s, res = pcall(function()
        return tonumber(tostring(p_obj:get_type_definition():get_field("combo_cnt"):get_data(p_obj))) or 0
    end)
    return s and res or 0
end

-- Snapshot des jauges (pattern identique à SheldonsBoxes)
-- attacker_idx = 0 ou 1 (le joueur qui fait le combo)
local function snapshot_gauges(attacker_idx)
    local result = nil
    pcall(function()
        local gB = sdk.find_type_definition("gBattle")
        if not gB then return end
        local sP = gB:get_field("Player"):get_data(nil)
        if not sP or not sP.mcPlayer then return end
        local BT = gB:get_field("Team"):get_data(nil)
        if not BT or not BT.mcTeam then return end

        local victim_idx = 1 - attacker_idx
        local victim = sP.mcPlayer[victim_idx]
        local attacker = sP.mcPlayer[attacker_idx]
        local atk_team = BT.mcTeam[attacker_idx]

        if not victim or not attacker or not atk_team then return end

        local v_hp = victim.vital_new
        local a_dr = attacker.focus_new
        local a_sa = atk_team.mSuperGauge

        if v_hp == nil or a_dr == nil or a_sa == nil then return end

        result = {
            victim_hp = v_hp,
            attacker_drive = a_dr,
            attacker_super = a_sa,
            -- Min trackers (mis à jour chaque frame dans on_frame)
            min_victim_hp = v_hp,
            min_atk_drive = a_dr,
            min_atk_super = a_sa
        }
    end)
    return result
end

-- Force l'injection des HP exacts sur un joueur
local function inject_player_vital(player_idx, hp)
    pcall(function()
        local gBattle = sdk.find_type_definition("gBattle")
        if not gBattle then return end
        local sP = gBattle:get_field("Player"):get_data(nil)
        if not sP then return end
        local p = sP:call("getPlayer", player_idx)
        if not p then return end
        p.vital_new = hp
        p.vital_old = hp
        p.heal_new = hp
    end)
end

-- Applique la vie (Victime = damage du combo, Attaquant = HP enregistré à l'étape 1)
local function apply_trial_vital()
    if not trial_state.sequence[1] then return end
    
    local expected_attacker_hp = trial_state.sequence[1].expected_hp
    if expected_attacker_hp then
        trial_state._pending_attacker_hp = expected_attacker_hp
    end
    
    local cs = trial_state.sequence[1].combo_stats
    if cs and cs.damage and cs.damage > 0 then
        trial_state._pending_victim_hp = cs.damage
    end

    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local ps = tm:get_field("_tData"):get_field("ParameterSetting")
        if not ps or not ps.PlayerDatas then return end
        
        -- Backup P1 (Index 0 in Training Menu)
        local p1d = ps.PlayerDatas[0]
        if not trial_state._saved_vital_p1 then
            trial_state._saved_vital_p1 = {
                Vital_Type = p1d.Vital_Type, Is_Vital_Infinity = p1d.Is_Vital_Infinity,
                Is_Vital_No_Recovery = p1d.Is_Vital_No_Recovery, Is_Vital_Recovery_Timer = p1d.Is_Vital_Recovery_Timer,
                Is_KO = p1d.Is_KO, Is_Point_Lock = p1d.Is_Point_Lock
            }
        end

        -- Backup P2 (Index 1 in Training Menu)
        local p2d = ps.PlayerDatas[1]
        if not trial_state._saved_vital_p2 then
            trial_state._saved_vital_p2 = {
                Vital_Type = p2d.Vital_Type, Is_Vital_Infinity = p2d.Is_Vital_Infinity,
                Is_Vital_No_Recovery = p2d.Is_Vital_No_Recovery, Is_Vital_Recovery_Timer = p2d.Is_Vital_Recovery_Timer,
                Is_KO = p2d.Is_KO, Is_Point_Lock = p2d.Is_Point_Lock
            }
        end

        local attacker_idx = trial_state.playing_player
        local victim_idx = 1 - attacker_idx

        if trial_state._pending_attacker_hp then
            local ad = ps.PlayerDatas[attacker_idx]
            ad.Vital_Type = 2
            ad.Is_Vital_Recovery_Timer = false
            ad.Is_Vital_Infinity = false
            ad.Is_Vital_No_Recovery = true
        end

        if trial_state._pending_victim_hp then
            local vd = ps.PlayerDatas[victim_idx]
            vd.Vital_Type = 2
            vd.Is_Vital_Recovery_Timer = false
            vd.Is_Vital_Infinity = false
            vd.Is_Vital_No_Recovery = true
            vd.Is_KO = true
            vd.Is_Point_Lock = true
        end
    end)
end

-- Relance l'injection HP (après un fail / reset)
local function reinject_trial_vital()
    local attacker_idx = trial_state.playing_player
    local victim_idx = 1 - attacker_idx
    if trial_state._pending_victim_hp and trial_state._pending_victim_hp > 0 then
        inject_player_vital(victim_idx, trial_state._pending_victim_hp)
    end
    if trial_state._pending_attacker_hp and trial_state._pending_attacker_hp > 0 then
        inject_player_vital(attacker_idx, trial_state._pending_attacker_hp)
    end
end

-- Restaure les settings vitaux aux valeurs d'origine
local function restore_trial_vital()
    trial_state._pending_victim_hp = nil
    trial_state._pending_attacker_hp = nil
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end

        local ps = tm:get_field("_tData"):get_field("ParameterSetting")
        if not ps or not ps.PlayerDatas then return end
        
        if trial_state._saved_vital_p1 then
            local p1d = ps.PlayerDatas[0]
            p1d.Vital_Type = trial_state._saved_vital_p1.Vital_Type
            p1d.Is_Vital_Infinity = trial_state._saved_vital_p1.Is_Vital_Infinity
            p1d.Is_Vital_No_Recovery = trial_state._saved_vital_p1.Is_Vital_No_Recovery
            p1d.Is_Vital_Recovery_Timer = trial_state._saved_vital_p1.Is_Vital_Recovery_Timer
            p1d.Is_KO = trial_state._saved_vital_p1.Is_KO
            p1d.Is_Point_Lock = trial_state._saved_vital_p1.Is_Point_Lock
            trial_state._saved_vital_p1 = nil
        end

        if trial_state._saved_vital_p2 then
            local p2d = ps.PlayerDatas[1]
            p2d.Vital_Type = trial_state._saved_vital_p2.Vital_Type
            p2d.Is_Vital_Infinity = trial_state._saved_vital_p2.Is_Vital_Infinity
            p2d.Is_Vital_No_Recovery = trial_state._saved_vital_p2.Is_Vital_No_Recovery
            p2d.Is_Vital_Recovery_Timer = trial_state._saved_vital_p2.Is_Vital_Recovery_Timer
            p2d.Is_KO = trial_state._saved_vital_p2.Is_KO
            p2d.Is_Point_Lock = trial_state._saved_vital_p2.Is_Point_Lock
            trial_state._saved_vital_p2 = nil
        end
    end)
end

-- Sets the Dummy Counter state (0=Normal, 1=Counter, 2=Punish Counter)
-- Cache tf_CounterSetting depuis _tfFuncs
local _tf_counter_cache = nil
local function get_tf_counter()
    if _tf_counter_cache then return _tf_counter_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val then
                    local td = val:get_type_definition()
                    if td:get_full_name():find("tf_CounterSetting") then
                        _tf_counter_cache = val
                        return
                    end
                end
            end
        end
    end)
    return _tf_counter_cache
end

-- 0=Normal, 1=CH, 2=PC (via DummyData + bApply, instantané sans refresh)
local function set_dummy_counter_type(counter_val)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local cs = tData:get_field("CounterSetting")
        if not cs then return end
        local dd = cs:get_field("DummyData")
        if not dd then return end
        if counter_val == 2 then
            dd.NC_TYPE = 0; dd.PC_TYPE = 1
        elseif counter_val == 1 then
            dd.NC_TYPE = 1; dd.PC_TYPE = 0
        else
            dd.NC_TYPE = 0; dd.PC_TYPE = 0
        end
    end)
    local tc = get_tf_counter()
    if tc then pcall(function() tc:call("bApply") end) end
end

-- Lire l'état actuel du counter
local function read_dummy_counter_type()
    local result = 0
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local cs = tData:get_field("CounterSetting")
        if not cs then return end
        local dd = cs:get_field("DummyData")
        if not dd then return end
        if dd.PC_TYPE == 1 then result = 2
        elseif dd.NC_TYPE == 1 then result = 1 end
    end)
    return result
end

local function save_dummy_counter_type()
    trial_state._saved_counter_type = read_dummy_counter_type()
end

local function restore_dummy_counter_type()
    if trial_state._saved_counter_type ~= nil then
        set_dummy_counter_type(trial_state._saved_counter_type)
        trial_state._saved_counter_type = nil
    end
end

-- Cache tf_GuardSetting depuis _tfFuncs
local _tf_guard_cache = nil
local function get_tf_guard()
    if _tf_guard_cache then return _tf_guard_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val and val:get_type_definition():get_full_name():find("tf_GuardSetting") then
                    _tf_guard_cache = val
                    return
                end
            end
        end
    end)
    return _tf_guard_cache
end

local function set_dummy_guard_type(guard_val)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        local gs = tData:get_field("GuardSetting")
        local dd = gs:get_field("DummyData")
        dd.GuardType = guard_val
    end)
    local tg = get_tf_guard()
    if tg then pcall(function() tg:call("bApply") end) end
end

local function read_dummy_guard_type()
    local result = 0
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        local gs = tData:get_field("GuardSetting")
        local dd = gs:get_field("DummyData")
        result = dd.GuardType or 0
    end)
    return result
end

local function save_dummy_guard_type()
    trial_state._saved_guard_type = read_dummy_guard_type()
end

local function restore_dummy_guard_type()
    if trial_state._saved_guard_type ~= nil then
        set_dummy_guard_type(trial_state._saved_guard_type)
        trial_state._saved_guard_type = nil
    end
end

local function capture_current_positions()
    local p1_pos, p2_pos, p1_raw, p2_raw = nil, nil, nil, nil
    local gBattle = sdk.find_type_definition("gBattle")
    if gBattle then
        local sP = gBattle:get_field("Player"):get_data(nil)
        if sP and sP.mcPlayer then
            local p1 = sP.mcPlayer[0]
            local p2 = sP.mcPlayer[1]

            -- VRAIE FORMULE UNIVERSELLE : Valeur brute / 65536 = Mètres (ex: 1.31)
            if p1 and p1.pos and p1.pos.x and p1.pos.x.v then
                p1_raw = p1.pos.x.v
                p1_pos = p1_raw / 6553600.0
            end
            if p2 and p2.pos and p2.pos.x and p2.pos.x.v then
                p2_raw = p2.pos.x.v
                p2_pos = p2_raw / 6553600.0
            end
        end
    end
    return p1_pos, p2_pos, p1_raw, p2_raw
end

-- Calcule la direction vers laquelle regarde le joueur actif au début du trial
local function update_trial_flip_state(skip_mirror)
    local r1, r2

    if d2d_cfg.forced_position_idx == 1 then
        -- 1. FORCED POS OFF : positions de destination (live_start si playing, sinon live)
        if trial_state.is_playing and trial_state.live_start_pos_p1_raw and trial_state.live_start_pos_p2_raw then
            r1 = trial_state.live_start_pos_p1_raw
            r2 = trial_state.live_start_pos_p2_raw
        else
            local _, _, live_p1, live_p2 = capture_current_positions()
            if not live_p1 or not live_p2 then
                trial_state.flip_inputs = false
                return
            end
            r1 = live_p1
            r2 = live_p2
        end
    else
        -- 2. FORCED POS ON ou MIRRORED : On lit la position sauvegardée (car le jeu va nous y téléporter)
        if not trial_state.start_pos_p1_raw or not trial_state.start_pos_p2_raw then
            trial_state.flip_inputs = false
            return
        end
        
        local recorded_by = 0
        if trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].recorded_by then
            recorded_by = trial_state.sequence[1].recorded_by
        end

        r1 = trial_state.start_pos_p1_raw
        r2 = trial_state.start_pos_p2_raw

        -- Swap si le joueur qui joue n'est pas celui qui a enregistré
        if trial_state.is_playing and trial_state.playing_player ~= recorded_by then
            local temp = r1
            r1 = r2
            r2 = temp
        end

        -- Inversion mathématique automatique si on a choisi MIRRORED
        if d2d_cfg.forced_position_idx == 3 and not skip_mirror then
            r1 = -r1
            r2 = -r2
        end
    end

    -- Détermination de l'orientation finale (P1 ou P2)
    if trial_state.playing_player == 0 then
        -- P1 regarde à gauche s'il est physiquement à droite de P2
        trial_state.flip_inputs = (r1 > r2)
    else
        -- P2 regarde à gauche s'il est physiquement à droite de P1
        trial_state.flip_inputs = (r2 > r1)
    end
end


local function apply_forced_position(skip_mirror)
    if _G.IsInBattleHub or _G.IsInReplay then return end

    -- SYNCHRONIZATION: Always update visual flip state before injecting position
    update_trial_flip_state(skip_mirror)

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return end

    local tData = tm:get_field("_tData")
    if not tData then return end

    local sm = tData:get_field("SelectMenu")
    if not sm then return end

    local pos1, pos2, raw1, raw2

    if d2d_cfg.forced_position_idx == 1 then
        if trial_state.is_playing and trial_state.live_start_pos_p1 then
            pos1 = trial_state.live_start_pos_p1
            pos2 = trial_state.live_start_pos_p2
            raw1 = trial_state.live_start_pos_p1_raw
            raw2 = trial_state.live_start_pos_p2_raw
        else
            local p1, p2, r1, r2 = capture_current_positions()
            if not r1 or not r2 then return end
            pos1, pos2, raw1, raw2 = p1, p2, r1, r2
            trial_state.start_pos_p1 = p1
            trial_state.start_pos_p2 = p2
            trial_state.start_pos_p1_raw = r1
            trial_state.start_pos_p2_raw = r2
        end
    else
        if not trial_state.start_pos_p1 or not trial_state.start_pos_p2 then return end

        local recorded_by = 0
        if trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].recorded_by then
            recorded_by = trial_state.sequence[1].recorded_by
        end

        local p1_pos = trial_state.start_pos_p1
        local p2_pos = trial_state.start_pos_p2
        local p1_raw = trial_state.start_pos_p1_raw
        local p2_raw = trial_state.start_pos_p2_raw

        if trial_state.is_playing and trial_state.playing_player ~= recorded_by then
            p1_pos = trial_state.start_pos_p2
            p2_pos = trial_state.start_pos_p1
            p1_raw = trial_state.start_pos_p2_raw
            p2_raw = trial_state.start_pos_p1_raw
        end

        pos1 = p1_pos
        pos2 = p2_pos
        raw1 = p1_raw
        raw2 = p2_raw

        if d2d_cfg.forced_position_idx == 3 and not skip_mirror then
            pos1 = -pos1
            pos2 = -pos2
            raw1 = -raw1
            raw2 = -raw2
        end
    end

    sm.StartLocation = 3
    sm.PlayerDatas[0].ManualPosX = math.floor((pos1 * 100) + 0.5)
    sm.PlayerDatas[1].ManualPosX = math.floor((pos2 * 100) + 0.5)

    tm._IsReqRefresh = true
    -- Stocker les valeurs sfix exactes pour correction post-refresh
    trial_state.exact_inject_r1 = raw1
    trial_state.exact_inject_r2 = raw2
    trial_state.pending_exact_pos = 10
end
-- =========================================================
-- HELPER FUNCTIONS (Shared by UI buttons and pad shortcuts)
-- =========================================================

local function reset_positions_to_default()
    if _G.IsInReplay or _G.FlowMapID == 10 then return end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local sm = tData:get_field("SelectMenu")
        if not sm then return end
        sm.StartLocation = 3
        sm.PlayerDatas[0].ManualPosX = -150
        sm.PlayerDatas[1].ManualPosX = 150
        tm._IsReqRefresh = true
    end)
end

local function apply_current_position_refresh()
    if _G.IsInReplay or _G.FlowMapID == 10 then return end
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return end
    local tData = tm:get_field("_tData")
    if not tData then return end
    local sm = tData:get_field("SelectMenu")
    if not sm then return end

    local p1, p2, r1, r2 = capture_current_positions()
    if not r1 or not r2 then return end

    trial_state.override_inject_r1 = r1
    trial_state.override_inject_r2 = r2
    trial_state.exact_inject_r1 = r1
    trial_state.exact_inject_r2 = r2

    sm.StartLocation = 3
    sm.PlayerDatas[0].ManualPosX = math.floor((p1 * 100) + 0.5)
    sm.PlayerDatas[1].ManualPosX = math.floor((p2 * 100) + 0.5)

    tm._IsReqRefresh = true
    trial_state.pending_exact_pos = 10
end


local function assign_groups(sequence)
    local gid = 0
    for i, step in ipairs(sequence) do
        local motion = (step.motion or ""):match("^%s*(.-)%s*$") or ""
        local is_followup = motion:sub(1, 1) == ">"

        -- Juri : le coup après 1218 n'est pas un vrai follow-up, on casse le groupe
        if is_followup and i > 1 and sequence[i - 1].id == 1218 then
            is_followup = false
            step.motion = motion:gsub("^>%s*", "")
        end

        if is_followup and i > 1 then
            step.group_id = sequence[i - 1].group_id
        else
            gid = gid + 1
            step.group_id = gid
        end
    end
end

local function load_combo_from_file(path)
    if not path then return false end
    local loaded = json.load_file(path)
    if not loaded then return false end
    trial_state.sequence = loaded
	assign_groups(trial_state.sequence) 
    trial_state.current_step = 1
    trial_state.is_playing = false
    if loaded[1] then
        trial_state.start_pos_p1 = loaded[1].start_pos_p1
        trial_state.start_pos_p2 = loaded[1].start_pos_p2
        trial_state.start_pos_p1_raw = loaded[1].start_pos_p1_raw
        trial_state.start_pos_p2_raw = loaded[1].start_pos_p2_raw
    end
    return true
end

local function clear_combo_state()
    trial_state.sequence = {}
    trial_state.current_step = 1
    trial_state.is_playing = false
    trial_state.start_pos_p1 = nil
    trial_state.start_pos_p2 = nil
    trial_state.start_pos_p1_raw = nil
    trial_state.start_pos_p2_raw = nil
    trial_state.live_start_pos_p1 = nil
    trial_state.live_start_pos_p2 = nil
    trial_state.live_start_pos_p1_raw = nil
    trial_state.live_start_pos_p2_raw = nil
end

-- =========================================================
-- END DEMO PLAYBACK AREA
-- =========================================================


local function start_recording(player_idx)
    trial_state.is_recording = true
    trial_state.recording_player = player_idx
    trial_state.sequence = {}

    -- LOGGER EXPORT RECORDING INIT
    if player_idx == 0 then
        logger_state.rec_p1.data = {}
        logger_state.rec_p1.has_started = false
        logger_state.rec_p1.wait_neutral = true
        logger_state.rec_p1.active = true
    else
        logger_state.rec_p2.data = {}
        logger_state.rec_p2.has_started = false
        logger_state.rec_p2.wait_neutral = true
        logger_state.rec_p2.active = true
    end

    -- Capturer la position live et refresh (même comportement que start_trial)
    trial_state.start_pos_p1, trial_state.start_pos_p2, trial_state.start_pos_p1_raw, trial_state.start_pos_p2_raw =
        capture_current_positions()
    apply_forced_position(true) -- skip_mirror : on enregistre en position normale

    trial_state._rec_gauges = nil
    trial_state._rec_pending_snapshot = 8
    trial_state._rec_hit_type = nil
end

local function start_trial(player_idx)
    restore_trial_vital()
    trial_state.is_recording = false
    trial_state._rec_gauges = nil
    trial_state._rec_hit_type = nil
    trial_state.is_playing = true
    trial_state.playing_player = player_idx
    trial_state.current_step = 1
    trial_state._was_playing = false

    trial_state.live_start_pos_p1, trial_state.live_start_pos_p2, trial_state.live_start_pos_p1_raw, trial_state.live_start_pos_p2_raw = capture_current_positions()

    -- NOUVEAU : Reset total de l'affichage (Log texte + D2D Raw et Animé)
    players[player_idx].log = {}
    players[player_idx].input_history_queue = {}
    if ComboTrials_D2D then
        pcall(function() ComboTrials_D2D.reset_anim() end)
        pcall(function() ComboTrials_D2D.reset_raw() end)
    end

    save_dummy_counter_type()
    save_dummy_guard_type()

    -- INJECT COUNTER STATE pour le premier step
    local first_ct = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].counter_type or 0
    set_dummy_counter_type(first_ct)

    -- Guard: After 1st Hit (2) au start trial
    set_dummy_guard_type(2)
    if _G.p2_vital_mode and type(set_vital_recovery) == "function" then
        set_vital_recovery(1, _G.p2_vital_mode)
    end
    update_trial_flip_state()
    apply_forced_position()
end

local function cancel_recording()
    trial_state.is_recording = false
    trial_state.is_playing = false
    trial_state.sequence = {}
    trial_state.current_step = 1
    -- Flush displayed input history
    pcall(function() ComboTrials_D2D.reset_raw() end)
end

local function stop_recording_and_save()
    -- Check if logger has data (for replay/BH mode where sequence stays empty)
    local logger_has_data = false
    if trial_state.recording_player == 0 then
        logger_has_data = logger_state.rec_p1.has_started and #logger_state.rec_p1.data > 0
    else
        logger_has_data = logger_state.rec_p2.has_started and #logger_state.rec_p2.data > 0
    end

    -- If nothing was recorded anywhere, act exactly like Cancel
    if #trial_state.sequence == 0 and not logger_has_data then
        cancel_recording()

        if trial_state.recording_player == 0 then
            logger_state.rec_p1.active = false
            logger_state.rec_p1.has_started = false
            logger_state.rec_p1.data = {}
        else
            logger_state.rec_p2.active = false
            logger_state.rec_p2.has_started = false
            logger_state.rec_p2.data = {}
        end

        return
    end

    local saved_player = trial_state.recording_player
    trial_state.is_recording = false

    -- EXPORT LOGGER
    if saved_player == 0 then
        if logger_state.rec_p1.has_started then
            logger_state.last_export_name = logger_export(logger_state.rec_p1)
            logger_state.last_export_name_2 = nil
        end
        logger_state.rec_p1.active = false
        logger_state.rec_p1.has_started = false
        logger_state.rec_p1.data = {}
    else
        if logger_state.rec_p2.has_started then
            logger_state.last_export_name = logger_export(logger_state.rec_p2)
            logger_state.last_export_name_2 = nil
        end
        logger_state.rec_p2.active = false
        logger_state.rec_p2.has_started = false
        logger_state.rec_p2.data = {}
    end

    -- ==========================================
    -- MERGING FILES : Injection avant sauvegarde
    -- ==========================================
    if trial_state.sequence and #trial_state.sequence > 0 then
        local raw_file = logger_state.last_export_name
        if raw_file then
            local loaded_raw = json.load_file("ReplayRecords/" .. raw_file)
            if loaded_raw and loaded_raw.timeline then
                trial_state.sequence[1].timeline = loaded_raw.timeline
            end
        end
    end

    save_trial_sequence()
end



local function load_and_start_trial(player_idx)
    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    if #paths > 0 then
        load_combo_from_file(paths[idx])
    end
    start_trial(player_idx)
end

local function reset_trial_steps()
    trial_state.current_step = 1
	trial_state.ui_visual_step = 1     --- NOUVEAU
    trial_state.floating_info = nil    --- NOUVEAU
    trial_state._step1_wrong_pending = false
    trial_state._first_hit_landed = false
    for _, item in ipairs(trial_state.sequence) do
        item.actual_combo = 0
        item.has_hit = false
        item.last_frame_diff = nil
    end
    -- Remettre la vie P2 au niveau exact du combo pour la prochaine tentative
    reinject_trial_vital()
    -- Remettre les positions si forced pos / mirror est actif
    apply_forced_position()
end

local function refresh_combo_list(recent_saved_player)
    file_system.saved_combos_display_p1, file_system.saved_combos_paths_p1 = {}, {}
    file_system.saved_combos_display_p2, file_system.saved_combos_paths_p2 = {}, {}

    local function load_files(player_idx, display_list, path_list)
        if not players[player_idx] then return end
        local char_name = players[player_idx].profile_name
        if char_name == "Unknown" then return end

        if fs.create_dir then
            pcall(fs.create_dir, "CustomCombos"); pcall(fs.create_dir, "CustomCombos/" .. char_name)
        end

        local files = fs.glob("CustomCombos\\\\" .. char_name .. "\\\\.*json")
        if files then
            -- Parse filename to extract sort keys: type (COMBO/OKI), damage, drive, SA
            local function parse_sort_keys(filepath)
                local fname = filepath:match("([^/\\]+)$") or ""
                local is_oki = fname:find("_OKI_") and 1 or 0
                local dmg = tonumber(fname:match("_(%d+)_D")) or 0
                local drive = tonumber(fname:match("_D([%d%.]+)_SA")) or 0
                local sa = tonumber(fname:match("_SA([%d%.]+)")) or 0
                return is_oki, dmg, drive, sa
            end
            -- Sort: COMBO first, then by damage desc, drive desc, SA desc
            table.sort(files, function(a, b)
                local a_oki, a_dmg, a_dr, a_sa = parse_sort_keys(a)
                local b_oki, b_dmg, b_dr, b_sa = parse_sort_keys(b)
                if a_oki ~= b_oki then return a_oki < b_oki end
                if a_dmg ~= b_dmg then return a_dmg > b_dmg end
                if a_dr ~= b_dr then return a_dr > b_dr end
                if a_sa ~= b_sa then return a_sa > b_sa end
                return a < b
            end)
            for _, filepath in ipairs(files) do
                table.insert(path_list, filepath)
                table.insert(display_list, filepath:match("([^/\\]+)$") or filepath)
            end
        end
    end

    load_files(0, file_system.saved_combos_display_p1, file_system.saved_combos_paths_p1)
    load_files(1, file_system.saved_combos_display_p2, file_system.saved_combos_paths_p2)

    local target_player = recent_saved_player or 0
    if target_player == 1 and #file_system.saved_combos_paths_p2 == 0 then target_player = 0 end
    if target_player == 0 and #file_system.saved_combos_paths_p1 == 0 then target_player = 1 end

    local path_to_load = nil
    if target_player == 0 and #file_system.saved_combos_paths_p1 > 0 then
        file_system.selected_file_idx_p1 = 1
        path_to_load = file_system.saved_combos_paths_p1[1]
    elseif target_player == 1 and #file_system.saved_combos_paths_p2 > 0 then
        file_system.selected_file_idx_p2 = 1
        path_to_load = file_system.saved_combos_paths_p2[1]
    end

    if not load_combo_from_file(path_to_load) then
        clear_combo_state()
    end
end

-- =========================================================
-- PAD SHORTCUTS SYSTEM (FUNC + D-PAD)
-- =========================================================
local BTN_UP          = 1
local BTN_DOWN        = 2
local BTN_LEFT        = 4
local BTN_RIGHT       = 8
local BTN_CROSS       = 32  -- Cross (PS) / A (Xbox)  [RDown in via.hid.GamePad]
local last_input_mask = 0
local last_kb_state = { [0x31]=false, [0x32]=false, [0x33]=false, [0x34]=false, [0x38]=false, [0x26]=false, [0x28]=false, [0x0D]=false }

-- VK codes pour les touches 1,2,3,4,8 (haut du clavier) + flèches
local KB_1 = 0x31  -- Position 1 : LEFT
local KB_2 = 0x32  -- Position 2 : UP (4-btn) ou RIGHT (2-btn)
local KB_3 = 0x33  -- Position 3 : RIGHT (4-btn only)
local KB_4 = 0x34  -- Position 4 : DOWN (4-btn only)
local KB_8 = 0x38  -- A (OPEN/CLOSE COMBO DROPDOWN)
local KB_ARROW_UP   = 0x26  -- Flèche haut (navigation dropdown)
local KB_ARROW_DOWN = 0x28  -- Flèche bas (navigation dropdown)
local KB_ENTER      = 0x0D  -- Entrée (valider sélection dropdown)

-- Détection du dernier périphérique utilisé (partagé via _G)
if _G.ComboTrials_InputDevice == nil then _G.ComboTrials_InputDevice = "pad" end

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

-- Lecture clavier via reframework API (avec fallback sécurisé)
local function is_kb_down(vk)
    local ok, result = pcall(function() return reframework:is_key_down(vk) end)
    return ok and result
end

local function handle_combo_shortcuts()
    if _G.FlowMapID ~= 10 and not _G.IsInReplay and _G.CurrentTrainerMode ~= 4 then return end

    local active_buttons = get_hardware_pad_mask()
    local func_btn = _G.TrainingFuncButton or 16384
    local is_func_held = ((active_buttons & func_btn) == func_btn)

    local function is_pressed(target_mask)
        if not is_func_held then return false end
        return ((active_buttons & target_mask) == target_mask) and not ((last_input_mask & target_mask) == target_mask)
    end

    -- Lecture clavier : touches 1,2,3,4,8 + flèches (front-edge)
    local kb_now = {
        [KB_1] = is_kb_down(KB_1),
        [KB_2] = is_kb_down(KB_2),
        [KB_3] = is_kb_down(KB_3),
        [KB_4] = is_kb_down(KB_4),
        [KB_8] = is_kb_down(KB_8),
        [KB_ARROW_UP] = is_kb_down(KB_ARROW_UP),
        [KB_ARROW_DOWN] = is_kb_down(KB_ARROW_DOWN),
        [KB_ENTER] = is_kb_down(KB_ENTER)
    }
    local function kb_pressed(vk)
        return kb_now[vk] and not last_kb_state[vk]
    end

    -- Détection du périphérique actif
    if is_func_held and active_buttons > func_btn then
        _G.ComboTrials_InputDevice = "pad"
    end
    for _, vk in ipairs({KB_1, KB_2, KB_3, KB_4, KB_8}) do
        if kb_now[vk] then _G.ComboTrials_InputDevice = "kb" end
    end
    if kb_now[KB_ARROW_UP] or kb_now[KB_ARROW_DOWN] then
        _G.ComboTrials_InputDevice = "kb"
    end

    -- =============================================
    -- DROPDOWN NAVIGATION MODE : bloque tous les autres raccourcis
    -- =============================================
    if _G.ComboTrials_DropdownOpen then
        if is_pressed(BTN_UP) or kb_pressed(KB_ARROW_UP) then
            _G.ComboTrials_DropdownNavUp = true
        end
        if is_pressed(BTN_DOWN) or kb_pressed(KB_ARROW_DOWN) then
            _G.ComboTrials_DropdownNavDown = true
        end
        if is_pressed(BTN_CROSS) or kb_pressed(KB_8) or kb_pressed(KB_ENTER) then
            _G.ComboTrials_DropdownSelect = true
        end
        last_input_mask = active_buttons
        last_kb_state = kb_now
        return
    end

    local is_demo_active = (demo_state and demo_state.is_playing)

    -- =============================================
    -- Raccourcis positionnels (gauche → droite) :
    --   4 boutons : LEFT/1, UP/2, RIGHT/3, DOWN/4
    --   2 boutons : LEFT/1, RIGHT/2
    -- =============================================

    if is_demo_active then
        -- ===== DEMO : 2 boutons (LEFT/1 = restart, RIGHT/2 = quit) =====
        if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
            if ctx.start_demo then ctx.start_demo() end
        end
        if is_pressed(BTN_RIGHT) or kb_pressed(KB_2) then
            if ctx.stop_demo then ctx.stop_demo() end
            -- trial_state.is_playing stays true so we return to the trial
        end

    elseif trial_state.is_recording then
        -- ===== RECORDING : 2 boutons (LEFT/1 = save, RIGHT/2 = cancel) =====
        if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
            stop_recording_and_save()
        end
        if is_pressed(BTN_RIGHT) or kb_pressed(KB_2) then
            cancel_recording()
        end

    elseif trial_state.is_playing then
        -- ===== PLAYING : 4 boutons (LEFT/1=reset, UP/2=stop, RIGHT/3=demo, DOWN/4=switch pos) =====
        if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
            -- RESET : recharge la séquence sans quitter le trial
            local curr_player = trial_state.playing_player
            local paths = (curr_player == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
            local idx = (curr_player == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
            if #paths > 0 then
                local loaded = json.load_file(paths[idx])
                if loaded then
                    trial_state.sequence = loaded
                    assign_groups(trial_state.sequence)
                end
            end
            trial_state.is_playing = true
            trial_state.current_step = 1
            trial_state._step1_wrong_pending = false
            trial_state.success_timer = 0
            trial_state.fail_timer = 0
            trial_state.fail_reason = nil
            trial_state.active_universal_hold = nil
            for _, item in ipairs(trial_state.sequence) do
                item.actual_combo = 0
                item.has_hit = false
                item.last_frame_diff = nil
            end

            players[curr_player].log = {}
            players[curr_player].input_history_queue = {}

            apply_forced_position()
            ComboTrials_D2D.reset_anim()
            ComboTrials_D2D.reset_raw()
        end
        if is_pressed(BTN_UP) or kb_pressed(KB_2) then
            trial_state.is_playing = false
        end
        if is_pressed(BTN_RIGHT) or kb_pressed(KB_3) then
            if ctx.start_demo then ctx.start_demo() end
        end
        if is_pressed(BTN_DOWN) or kb_pressed(KB_4) then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            save_d2d_config()
            apply_forced_position()
            -- Mini-reset pour replacer proprement après le switch pos
            trial_state.current_step = 1
            trial_state._step1_wrong_pending = false
            trial_state.success_timer = 0
            trial_state.fail_timer = 0
            trial_state.fail_reason = nil
            trial_state.active_universal_hold = nil
            for _, item in ipairs(trial_state.sequence) do
                item.actual_combo = 0
                item.has_hit = false
                item.last_frame_diff = nil
            end
            if ctx.reset_visuals then ctx.reset_visuals() end
        end

    else
        if _G.IsInReplay or _G.IsInBattleHub then
            -- ===== REPLAY/SPECTATE IDLE : 2 boutons (LEFT/1=rec P1, RIGHT/2=rec P2) =====
            if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
                start_recording(0)
            end
            if is_pressed(BTN_RIGHT) or kb_pressed(KB_2) then
                start_recording(1)
            end
        else
            -- ===== IDLE : 3 boutons (LEFT/1=record, UP/2=start trial, RIGHT/3=switch pos) =====
            if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
                start_recording(0)
            end
            if is_pressed(BTN_UP) or kb_pressed(KB_2) then
                load_and_start_trial(0)
            end
            if is_pressed(BTN_RIGHT) or kb_pressed(KB_3) then
                d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
                if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
                save_d2d_config()
            end
        end
    end

    -- FUNC + CROSS (A) / Touche 8 : OUVRIR LE DROPDOWN COMBO FILES
    if is_pressed(BTN_CROSS) or kb_pressed(KB_8) then
        if not trial_state.is_recording then
            _G.ComboTrials_OpenDropdown = true
        end
    end

    last_input_mask = active_buttons
    last_kb_state = kb_now
end

-- =========================================================
-- MACHINE A ETAT UNIVERSELLE DES CHARGES
-- =========================================================
local function evaluate_charge_status(char_name, frames, c_min, c_max, p_min, p_max)
    if char_name == "Luke" and p_min then
        local insta_threshold = c_min or (p_min - 5)
        if frames <= insta_threshold then return "Instant" end
        if frames >= p_min and frames <= (p_max or p_min+2) then return "PERFECT!" end
        if frames < p_min then return "Partial" end
        return "LATE"
    elseif char_name == "JP" then
        if c_min and frames <= c_min then return "Instant" end
        if c_max and frames >= c_max then return "FAKE" end
        return "Partial"
    elseif char_name == "Lily" then
        if c_min and frames <= c_min then return "Lv1" end
        if c_max and frames >= c_max then return "Lv3" end
        return "Lv2"
    else
        if c_min and frames <= c_min then return "Instant" end
        if c_max and frames >= c_max then return "Maxed" end
        if frames > 0 then return "Partial" end
        return "Instant"
    end
end

-- =========================================================
-- SKIP K.O. & ROUND END ANIMATIONS (Porté de ReplayLabs)
-- =========================================================
local function setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then
            pcall(function() sdk.hook(method, pre_func, post_func) end)
        end
    end
end

setup_hook("app.battle.bBattleFlow", "updateKO", nil, function(retval)
    if trial_state.is_playing or trial_state.is_recording or (demo_state and demo_state.is_playing) then
        -- Force le reset automatique (remise en position) dès que le K.O. est détecté
        if trial_state.is_playing and trial_state.success_timer == 0 then
            trial_state.success_timer = 1 
        end
        return sdk.to_ptr(2) -- 2 = Skip animation
    end
    return retval
end)

setup_hook("app.battle.bBattleFlow", "updateRoundResult", nil, function(retval)
    if trial_state.is_playing or trial_state.is_recording or (demo_state and demo_state.is_playing) then
        return sdk.to_ptr(2)
    end
    return retval
end)

local function build_fail_dump()
    local dump = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        fail_reason_ui = trial_state.fail_reason,
        failed_at_step = trial_state.current_step,
        expected_sequence = {},
        player_recent_inputs = {}
    }
    
    -- 1. Capture of the expected sequence up to the fail
    for i, step in ipairs(trial_state.sequence) do
        local s = {
            step = i,
            id = step.id,
            motion = step.motion,
            expected_combo = step.expected_combo,
            is_holdable = step.is_holdable,
            delay_from_prev = step.delay_from_prev
        }
        if i == trial_state.current_step then
            s.STATUS = "<-- FAILED HERE"
            if trial_state.active_universal_hold then
                s.hold_error_details = {
                    expected_status = trial_state.active_universal_hold.expected_status,
                    expected_frames = trial_state.active_universal_hold.expected_frames,
                    actual_frames = trial_state.active_universal_hold.frames,
                    charge_min = trial_state.active_universal_hold.charge_min,
                    charge_max = trial_state.active_universal_hold.charge_max
                }
            end
        end
        table.insert(dump.expected_sequence, s)
    end
    
    -- 2. Capture of the player's last 15 actions
    local p_state = players[trial_state.playing_player]
    if p_state and p_state.log then
        for i = 1, math.min(15, #p_state.log) do
            local l = p_state.log[i]
            table.insert(dump.player_recent_inputs, {
                log_index = i,
                id = l.id,
                name = l.name,
                motion = l.motion,
                real_input = l.real_input,
                frame_diff = l.frame_diff,
                intentional = l.intentional,
                hold_frames = l.hold_frames,
                charge_status = l.charge_status,
                combo_count = l.combo_count,
                is_ignored = l.is_ignored,
                ignore_reason = l.ignore_reason
            })
        end
    end
    
    return dump
end

local _replay_cleaned = false
re.on_frame(function()
    -- BATTLE HUB SPECTATE : script désactivé
    if _G.IsInBattleHub then return end

    -- Replay : clean une seule fois à l'entrée (stop trial/demo, reset state)
    local _in_replay = (_G.FlowMapID == 10 or _G.IsInReplay)
    if _in_replay and not _replay_cleaned then
        _replay_cleaned = true
        if trial_state.is_playing then
            trial_state.is_playing = false
            trial_state._was_playing = false
        end
        if demo_state and demo_state.is_playing then demo_state.is_playing = false end
        trial_state.flip_inputs = false
        trial_state.floating_info = nil
        trial_state._vital_initialized = false
        trial_state._pause_live_r1 = nil
        trial_state._pause_live_r2 = nil
        trial_state._unpause_delay = nil
        trial_state.pending_exact_pos = nil
        _G.ComboTrials_HideNativeHUD = false
    elseif not _in_replay then
        _replay_cleaned = false
    end

    -- Mise à jour live de flip_inputs (seulement avant le premier coup de la séquence)
    if trial_state.is_playing and trial_state.current_step == 1 then
        pcall(function()
            local gB = sdk.find_type_definition("gBattle")
            if not gB then return end
            local sP = gB:get_field("Player"):get_data(nil)
            if not sP or not sP.mcPlayer or not sP.mcPlayer[0] or not sP.mcPlayer[1] then return end
            local r1 = sP.mcPlayer[0].pos.x.v
            local r2 = sP.mcPlayer[1].pos.x.v
            local facing_left = false
            if trial_state.playing_player == 0 then
                facing_left = (r1 > r2)
            else
                facing_left = (r2 > r1)
            end
            trial_state.flip_inputs = facing_left
        end)
    end

    if _G.CurrentTrainerMode ~= 4 then
        -- Clean shutdown if switching scripts during an active Trial/Demo
        if trial_state.is_playing or (demo_state and demo_state.is_playing) then
            trial_state.is_playing = false
            trial_state._was_playing = false
            if demo_state then demo_state.is_playing = false end

            restore_trial_vital()
            restore_dummy_counter_type()
            restore_dummy_guard_type()
            apply_current_position_refresh()
        elseif trial_state.is_recording then
            cancel_recording()
        end
        trial_state._vital_initialized = false
        return
    end

    -- On first frame of Combo Trials mode: clean slate (skip en replay)
    if not trial_state._vital_initialized then
        trial_state._vital_initialized = true

        -- Force stop tout ce qui traîne d'une session précédente
        if trial_state.is_playing then
            trial_state.is_playing = false
            trial_state._was_playing = false
        end
        if demo_state and demo_state.is_playing then demo_state.is_playing = false end
        if trial_state.is_recording then cancel_recording() end
        trial_state.flip_inputs = false
        trial_state.floating_info = nil
        _G.ComboTrials_HideNativeHUD = false

        -- Ne toucher au TrainingManager que si on n'est PAS en replay
        if not _G.IsInReplay and _G.FlowMapID ~= 10 then
            pcall(function()
                local tm = sdk.get_managed_singleton("app.training.TrainingManager")
                if not tm then return end
                local ps = tm:get_field("_tData"):get_field("ParameterSetting")
                if not ps or not ps.PlayerDatas then return end
                for i = 0, 1 do
                    local pd = ps.PlayerDatas[i]
                    pd.Is_Vital_Recovery_Timer = true
                    pd.Is_Vital_Infinity = false
                    pd.Is_Vital_No_Recovery = false
                    pd.Is_KO = false
                    pd.Is_Point_Lock = true
                end
            end)
        end
    end

    -- DYNAMIC NATIVE HUD: Hide base game info ONLY during active record or playback
    _G.ComboTrials_HideNativeHUD = (trial_state.is_recording or trial_state.is_playing)

    -- HOOK DES RACCOURCIS MANETTE
    handle_combo_shortcuts()
    local pm = sdk.get_managed_singleton("app.PauseManager")
    local is_game_paused = false
    if pm then
        local b = pm:get_field("_CurrentPauseTypeBit")
        if b ~= 64 and b ~= 2112 then is_game_paused = true end
    end

    -- Entering pause → capture live positions
    if is_game_paused and not trial_state._was_game_paused then
        pcall(function()
            local gB = sdk.find_type_definition("gBattle")
            if not gB then return end
            local sP = gB:get_field("Player"):get_data(nil)
            if not sP or not sP.mcPlayer then return end
            trial_state._pause_live_r1 = sP.mcPlayer[0].pos.x.v
            trial_state._pause_live_r2 = sP.mcPlayer[1].pos.x.v
        end)
    end

    -- Leaving pause → inject captured live positions
    if not is_game_paused and trial_state._was_game_paused then
        if trial_state._pause_live_r1 and trial_state._pause_live_r2 then
            trial_state._unpause_delay = 5
        end
    end
    trial_state._was_game_paused = is_game_paused

    -- Delayed inject after unpause (skip en replay)
    if not _in_replay and trial_state._unpause_delay and trial_state._unpause_delay > 0 then
        trial_state._unpause_delay = trial_state._unpause_delay - 1
        if trial_state._unpause_delay == 0 and trial_state._pause_live_r1 and trial_state._pause_live_r2 then
            pcall(function()
                local gB = sdk.find_type_definition("gBattle")
                if not gB then return end
                local sP = gB:get_field("Player"):get_data(nil)
                if not sP or not sP.mcPlayer then return end
                local sfix_type = sdk.find_type_definition("via.sfix")
                if not sfix_type then return end
                local sfix_from = sfix_type:get_method("From(System.Double)")
                if not sfix_from then return end
                local p1 = sP.mcPlayer[0]
                local p2 = sP.mcPlayer[1]
                if p1 and p1.POS_SETx then p1:POS_SETx(sfix_from:call(nil, trial_state._pause_live_r1 / 65536.0)) end
                if p2 and p2.POS_SETx then p2:POS_SETx(sfix_from:call(nil, trial_state._pause_live_r2 / 65536.0)) end
            end)
            trial_state._pause_live_r1 = nil
            trial_state._pause_live_r2 = nil
        end
    end

    if is_game_paused then return end

    engine_frame_count = engine_frame_count + 1

    -- Process the input logger to record real inputs
    logger_process_game_state()

    -- Détection des transitions is_playing pour la vie P2
    local now_playing = trial_state.is_playing
    if now_playing and not trial_state._was_playing then
        -- Transition OFF → ON : Appliquer la vie P2 = damage du combo
        apply_trial_vital()
    elseif not now_playing and trial_state._was_playing then
        -- Transition ON → OFF : Restaurer la vie P2 et remettre les positions par défaut
        restore_trial_vital()
        restore_dummy_counter_type()
        restore_dummy_guard_type()
        reset_positions_to_default()
    end
    trial_state._was_playing = now_playing

    -- POST-REFRESH EXACT POSITION CORRECTION (skip en replay)
    if not _in_replay and trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then
        local tm_check = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm_check and tm_check:get_field("_IsReqRefresh") == false then
            trial_state.pending_exact_pos = trial_state.pending_exact_pos - 1
            if trial_state.pending_exact_pos == 0 then
                pcall(function()
                    local r1 = trial_state.exact_inject_r1
                    local r2 = trial_state.exact_inject_r2
                    if not r1 or not r2 then return end

                    local gBt = sdk.find_type_definition("gBattle")
                    if not gBt then return end
                    local sP = gBt:get_field("Player"):get_data(nil)
                    if not sP or not sP.mcPlayer then return end
                    local p1 = sP.mcPlayer[0]
                    local p2 = sP.mcPlayer[1]
                    if not p1 or not p2 then return end

                    local sfix_type = sdk.find_type_definition("via.sfix")
                    if not sfix_type then return end
                    local sfix_from = sfix_type:get_method("From(System.Double)")
                    if not sfix_from then return end

                    -- r1/r2 sont des valeurs sfix brutes (pos.x.v). En cm : raw / 65536.0
                    if p1.POS_SETx then p1:POS_SETx(sfix_from:call(nil, r1 / 65536.0)) end
                    if p2.POS_SETx then p2:POS_SETx(sfix_from:call(nil, r2 / 65536.0)) end
                end)
            end
        end
    end


    -- INJECTION HP EXACT VIA PLAYER OBJECT
    -- Injecte en continu tant que le trial attend le premier coup (current_step == 1)
    -- Après un refresh (forced pos), attend que le refresh finisse d'abord
    if trial_state.is_playing and trial_state._pending_vital_hp and trial_state.current_step == 1 then
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm and tm:get_field("_IsReqRefresh") == false then
            inject_p2_vital(trial_state._pending_vital_hp)
        end
    end

    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return end
    local cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not cmd_obj then return end
    local player_obj = gBattle:get_field("Player"):get_data(nil)
    if not player_obj then return end


    -- INJECTION HP EXACT VIA PLAYER OBJECT
    -- Injecte en continu tant que le trial attend le premier coup (current_step == 1)
    -- Stoppe définitivement dès que la victime prend un hit (combo_cnt > 0)
    -- Après un refresh (forced pos), attend que le refresh finisse d'abord
    if trial_state.is_playing and trial_state.current_step == 1 then
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local is_refreshing = tm and tm:get_field("_IsReqRefresh")
        -- Detect first hit and latch it (check combo_cnt on ATTACKER)
        -- Only check when not refreshing (after KO/reset, combo_cnt may still be stale)
        if not trial_state._first_hit_landed and not is_refreshing then
            pcall(function()
                local attacker_char = player_obj:call("getPlayer", trial_state.playing_player)
                if attacker_char and get_combo_count(attacker_char) > 0 then
                    trial_state._first_hit_landed = true
                end
            end)
        end
        local attacker_idx = trial_state.playing_player
        local victim_idx = 1 - attacker_idx
        if not trial_state._first_hit_landed then
            if tm and not is_refreshing then
                if trial_state._pending_victim_hp then
                    inject_player_vital(victim_idx, trial_state._pending_victim_hp)
                end
                if trial_state._pending_attacker_hp then
                    inject_player_vital(attacker_idx, trial_state._pending_attacker_hp)
                end
            end
        end
    end

    for p_idx = 0, 1 do
        local p_state = players[p_idx]

        --- Global Trial Timers (Success & Fail animations)
        if p_idx == trial_state.playing_player then
            if trial_state.success_timer > 0 then
                trial_state.success_timer = trial_state.success_timer - 1
                if trial_state.success_timer <= 0 then
                    reset_trial_steps()
                end
            end

            if trial_state.fail_timer and trial_state.fail_timer > 0 then
                -- CAPTURE: Take a snapshot on the very first frame of the fail state
                -- if not trial_state._fail_captured then
                --     trial_state.last_fail_dump = build_fail_dump()
                --     trial_state._fail_captured = true
                -- end

                trial_state.fail_timer = trial_state.fail_timer - 1
                if trial_state.fail_timer <= 0 then
                    trial_state.fail_reason = nil
                    trial_state._fail_captured = false
                    reset_trial_steps()
                end
            end
		end

        if p_state.profile_name ~= p_state.last_profile_name then
            p_state.last_profile_name = p_state.profile_name
            p_state.log = {}
            p_state.input_history_queue = {}
            p_state.bcm_cache = {}
            p_state.trigger_mask_cache = {}
            p_state.cache_built = false
            p_state.last_bcm_ptr = ""

            -- RESET DU TRIAL au changement de personnage
            -- Le trial dépend des deux persos, on reset si l'un des deux change
            if trial_state.is_recording then
                trial_state.is_recording = false
            end
            if trial_state.is_playing then
                trial_state.is_playing = false
            end
            trial_state.sequence = {}
            trial_state.current_step = 1
            trial_state.success_timer = 0
            trial_state.fail_timer = 0
            trial_state.fail_reason = nil

            -- Refresh the list only if it's the character we are currently viewing
            if p_idx == ui_state.viewed_player then
                refresh_combo_list()
            end
            if p_state.profile_name ~= "Unknown" then
                local filename = get_exc_filename(p_state.profile_name)
                local loaded = json.load_file(filename)
                if loaded then
                    p_state.exceptions = loaded
                else
                    p_state.exceptions = {}
                end
            end
        end

        local p_char = player_obj:call("getPlayer", p_idx)
        if p_char then
            local bcm_resource = cmd_obj:get_field("mpBCMResource")
            if bcm_resource then
                local p_bcm = bcm_resource[p_idx]
                local current_bcm_ptr = tostring(p_bcm)
                if current_bcm_ptr ~= p_state.last_bcm_ptr then
                    p_state.last_bcm_ptr = current_bcm_ptr
                    p_state.cache_built = false
                end
            end

            if not p_state.cache_built then build_bcm_cache(p_idx) end

            local act_id, act_frame, flags, action_code, direct_input, b_type = get_action_data(p_char)
            local current_combo = get_combo_count(p_char)

            -- LILY STRICT : Tracking du bouton physique enfoncé sur la manette
            if p_state.profile_name == "Lily" and #p_state.log > 0 and p_state.log[1].trigger_mask then
                p_state.log[1].is_physically_holding = ((direct_input & p_state.log[1].trigger_mask) ~= 0)
            end

            -- ========================================================
            -- GESTION SIMPLIFIÉE DU COMBO COUNTER
            -- ========================================================
            -- Mise à jour du combo count dans le log (pour affichage)
            if (current_combo or 0) > 0 then
                if #p_state.log > 0 then
                    p_state.log[1].combo_count = math.max(p_state.log[1].combo_count or 0,
                        current_combo)
                end
                for i = 1, math.min(15, #p_state.log) do
                    if p_state.log[i].intentional then
                        p_state.log[i].combo_count = math.max(p_state.log[i].combo_count or 0, current_combo); break
                    end
                end
            end

            -- ========================================================
            -- TRACKING CONTINU DES JAUGES PENDANT LE RECORDING
            -- ========================================================
			-- SNAPSHOT DIFFÉRÉ : attend que le refresh P2 (100% vie) soit appliqué par le moteur
if trial_state.is_recording and p_idx == trial_state.recording_player
    and trial_state._rec_pending_snapshot and trial_state._rec_pending_snapshot > 0 then
    trial_state._rec_pending_snapshot = trial_state._rec_pending_snapshot - 1
    if trial_state._rec_pending_snapshot == 0 then
        trial_state._rec_gauges = snapshot_gauges(p_idx)
        -- À ce moment vital_new = max_hp réel du perso → dégâts calculés depuis 100%
    end
end
            if trial_state.is_recording and p_idx == trial_state.recording_player and trial_state._rec_gauges then
                pcall(function()
                    local victim_idx = 1 - p_idx
                    local victim = player_obj:call("getPlayer", victim_idx)
                    local BT = gBattle:get_field("Team"):get_data(nil)
                    if victim and BT and BT.mcTeam then
                        local v_hp = victim.vital_new
                        local a_dr = p_char.focus_new
                        local a_sa = BT.mcTeam[p_idx].mSuperGauge

                        local rg = trial_state._rec_gauges
                        if v_hp and rg.min_victim_hp then rg.min_victim_hp = math.min(rg.min_victim_hp, v_hp) end
                        if a_dr and rg.min_atk_drive then rg.min_atk_drive = math.min(rg.min_atk_drive, a_dr) end
                        if a_sa and rg.min_atk_super then rg.min_atk_super = math.min(rg.min_atk_super, a_sa) end
                    end
                end)
            end

            -- Détection du hit pour le visuel (has_hit + actual_combo + projectile)
            if (current_combo or 0) > (p_state.last_combo_count or 0) then
                -- Vérification de la source du hit : projectile ou joueur direct
                local hit_is_projectile = false
                pcall(function()
                    hit_is_projectile = check_is_projectile(p_idx, p_char, gBattle)
                end)

                if trial_state.is_recording and p_idx == trial_state.recording_player then
                    if #trial_state.sequence > 0 then
                        local step = trial_state.sequence[#trial_state.sequence]
                        step.has_hit = true
                        -- Mémorise s'il y a eu AU MOINS un hit de projectile pendant l'action
                        step.is_projectile_hit = step.is_projectile_hit or hit_is_projectile
                        -- Capturer CH/PC au moment du hit
                        if step.counter_type == 0 then
                            pcall(function()
                                local victim_idx = 1 - p_idx
                                local victim_obj = player_obj:call("getPlayer", victim_idx)
                                if victim_obj then
                                    local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
                                    local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
                                    if tostring(pc) == "true" then step.counter_type = 2
                                    elseif tostring(ch) == "true" then step.counter_type = 1 end
                                end
                            end)
                        end
                    end
                elseif trial_state.is_playing and p_idx == trial_state.playing_player
                    and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                    -- Step 1 tolerance : fail si le mauvais coup TOUCHE le dummy
                    if trial_state._step1_wrong_pending and trial_state.current_step == 1 then
                        trial_state._step1_wrong_pending = false
                        trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                        trial_state.fail_reason = "WRONG MOVE"
                    end
                    local prev_step_idx = math.max(1, trial_state.current_step - 1)
                    local prev_step = trial_state.sequence[prev_step_idx]
                    if prev_step then
                        prev_step.actual_combo = current_combo
                        prev_step.has_hit = true
                        if hit_is_projectile then prev_step.is_projectile_hit = true end

                        -- Le hit est confirmé : appliquer le counter_type du prochain step
                        local next_step = trial_state.sequence[trial_state.current_step]
                        if next_step and next_step.counter_type then
                            set_dummy_counter_type(next_step.counter_type)
                        else
                            set_dummy_counter_type(0)
                        end

                        -- Fait avancer UNIQUEMENT le compteur [ACTION X / Y] à l'impact
                        trial_state.ui_visual_step = trial_state.current_step
                        trial_state.floating_info = nil -- <-- Vide le texte en attendant le prochain input
                    end

                end
				end

            -- Capture CH/PC en continu pendant le recording (indépendant du combo count pour DI etc.)
            if not trial_state._rec_hit_type and trial_state.is_recording and p_idx == trial_state.recording_player then
                pcall(function()
                    local victim_idx = 1 - p_idx
                    local victim_obj = player_obj:call("getPlayer", victim_idx)
                    if victim_obj then
                        local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
                        local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
                        if tostring(pc) == "true" then
                            trial_state._rec_hit_type = "PC"
                        elseif tostring(ch) == "true" and trial_state._rec_hit_type ~= "PC" then
                            trial_state._rec_hit_type = "CH"
                        end
                    end
                end)
            end

            -- Détection du knockdown adverse (pose_st == 3)
            local opponent_knocked_down = false
            pcall(function()
                local victim_idx = 1 - p_idx
                local victim_obj = player_obj:call("getPlayer", victim_idx)
                if victim_obj then
                    local pose_st = victim_obj:get_type_definition():get_field("pose_st"):get_data(victim_obj)
                    if tonumber(tostring(pose_st)) == 3 then opponent_knocked_down = true end
                end
            end)
            -- Guard off dès que l'adversaire tombe (pour les okis)
            if trial_state.is_playing and opponent_knocked_down and not trial_state._guard_off_on_kd then
                set_dummy_guard_type(0)
                trial_state._guard_off_on_kd = true
            elseif trial_state.is_playing and not opponent_knocked_down and trial_state._guard_off_on_kd then
                trial_state._guard_off_on_kd = false
            end

            -- ========================================================
            -- VÉRIFICATION DU SUCCÈS + DÉTECTION DROP (Trial)
            -- ========================================================
            local is_demo_playing = (demo_state and demo_state.is_playing)
            if trial_state.is_playing and p_idx == trial_state.playing_player and not is_demo_playing then
                local is_hold_pending = (trial_state.active_universal_hold ~= nil)

                if #trial_state.sequence > 0 and trial_state.current_step > #trial_state.sequence then
                    local last_step = trial_state.sequence[#trial_state.sequence]
                    if trial_state.success_timer == 0 and not is_hold_pending and not (trial_state.fail_timer and trial_state.fail_timer > 0) and (not last_step.expected_combo or last_step.expected_combo == 0 or (current_combo or 0) >= last_step.expected_combo) then
                        trial_state.success_timer = d2d_cfg.fail_display_frames or 120
                    end
                end

                -- DÉTECTION CONTINUE DU COMBO DROP :
                if (current_combo or 0) == 0 and (p_state.last_combo_count or 0) > 0 then
                    if trial_state.success_timer == 0 and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                        local last_validated_idx = trial_state.current_step - 1
                        if last_validated_idx >= 1 then
                            local last_validated = trial_state.sequence[last_validated_idx]
                            
                            local current_expected = trial_state.sequence[trial_state.current_step]
                            local is_reset_expected = current_expected and current_expected.expected_combo == 0
                            
                            if last_validated and last_validated.expected_combo and last_validated.expected_combo > 0 then
                                if is_hold_pending then
                                    trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                    local frames_since = engine_frame_count - (trial_state.last_played_frame or engine_frame_count)
                                    if frames_since < 15 then
                                        trial_state.fail_reason = "TOO LATE (Combo Drop)"
                                    else
                                        local diff_str = ""
                                        if trial_state.active_universal_hold and trial_state.active_universal_hold.expected_frames then
                                            local diff = trial_state.active_universal_hold.frames - trial_state.active_universal_hold.expected_frames
                                            local sign = diff > 0 and "+" or ""
                                            diff_str = string.format(" [%s%df]", sign, diff)
                                        end
                                        trial_state.fail_reason = "HOLD TIMING" .. diff_str .. " (Combo Drop)"
                                    end
                                    trial_state.active_universal_hold = nil
                                elseif not opponent_knocked_down and not is_reset_expected
                                    and not (last_validated.expected_combo == (trial_state.current_step >= 3 and trial_state.sequence[trial_state.current_step - 2].expected_combo or 0)) then
                                    trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                    if last_validated.last_frame_diff and last_validated.last_frame_diff < -2 then
                                        trial_state.fail_reason = string.format("TOO EARLY (%df)", math.abs(last_validated.last_frame_diff))
                                    elseif last_validated.last_frame_diff and last_validated.last_frame_diff > 2 then
                                        trial_state.fail_reason = string.format("TOO LATE (%df)", last_validated.last_frame_diff)
                                    else
                                        local expected = trial_state.sequence[trial_state.current_step]
                                        if expected then
                                            local last_played = trial_state.last_played_frame or engine_frame_count
                                            local diff = (engine_frame_count - last_played) - (expected.delay_from_prev or 0)
                                            if diff > 2 then trial_state.fail_reason = string.format("TOO LATE (%df)", diff)
                                            else trial_state.fail_reason = "COMBO DROPPED" end
                                        else
                                            trial_state.fail_reason = "COMBO DROPPED"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- TIMEOUT CONTINUOUS DETECTION (Triggers if player does nothing or gets hit)
                if trial_state.success_timer == 0 and not is_hold_pending and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                    local expected = trial_state.sequence[trial_state.current_step]
                    if expected and trial_state.current_step > 1 then
                        local last_played = trial_state.last_played_frame or engine_frame_count
                        local frames_since = engine_frame_count - last_played
                        local delay = expected.delay_from_prev or 0
                        
                        -- 60 frames (~1 sec) tolerance after the ideal timing
                        if frames_since > (delay + 60) then
                            trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                            
                            if expected.expected_hp ~= nil and p_char.vital_new ~= expected.expected_hp then
                                if expected.expected_combo == 0 then
                                    trial_state.fail_reason = "SETUP INTERRUPTED (Got hit)"
                                else
                                    local prev_step = trial_state.sequence[trial_state.current_step - 1]
                                    if prev_step and prev_step.expected_combo == 0 then
                                        trial_state.fail_reason = "MEATY INTERRUPTED (Got hit)"
                                    else
                                        trial_state.fail_reason = "INTERRUPTED (Got hit)"
                                    end
                                end
                            else
                                local prev_step = trial_state.sequence[trial_state.current_step - 1]
                                if prev_step and prev_step.expected_combo == 0 then
                                    trial_state.fail_reason = "MEATY TOO LATE (Missed Input)"
                                else
                                    trial_state.fail_reason = "TOO LATE (Missed Input)"
                                end
                            end
                        end
                    end
                end
			end

            -- GESTION CONTINUE DE LA CHARGE
            if #p_state.log > 0 then
                local current_log = p_state.log[1]
                if current_log.is_holdable and current_log.is_holding then
                    if current_log.hold_mask > 0 and (direct_input & current_log.hold_mask) ~= 0 then
                        current_log.hold_frames = current_log.hold_frames + 1
                    else
                        -- LE JOUEUR RELÂCHE LE BOUTON
                        current_log.is_holding = false
                        
                        -- Auto-détection de la frame max pour JP/Lily si non configuré
                        if (p_state.profile_name == "JP" or p_state.profile_name == "Lily") and (current_log.charge_max == nil or current_log.charge_max == "") then
                            current_log.charge_max = current_log.hold_frames
                            local id_s = tostring(current_log.id)
                            local exc_to_update = p_state.exceptions[id_s] or common_exceptions[id_s]
                            if exc_to_update then
                                exc_to_update.charge_max = current_log.hold_frames
                                if p_state.exceptions[id_s] then json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                                else json.dump_file("exceptions/Common.json", common_exceptions) end
                            end
                        end
                    end

                    current_log.charge_status = evaluate_charge_status(
                        p_state.profile_name, current_log.hold_frames,
                        current_log.charge_min, current_log.charge_max,
                        current_log.luke_perfect_min, current_log.luke_perfect_max
                    )

                    -- SYNCHRONISATION EN TEMPS RÉEL DU HOLD POUR LE TRIAL
                    if trial_state.is_recording and current_log.trial_step_idx and trial_state.sequence[current_log.trial_step_idx] then
                        trial_state.sequence[current_log.trial_step_idx].hold_frames = current_log.hold_frames
                        trial_state.sequence[current_log.trial_step_idx].charge_status = current_log.charge_status
                        trial_state.sequence[current_log.trial_step_idx].charge_max = current_log.charge_max
                    end
                end
            end			
            local newly_pressed = (direct_input ~ p_state.last_direct_input) & direct_input
            local current_dir_val = direct_input & 0xF
            local current_dir = DIR_MAP[current_dir_val] or "5"
            if current_dir == "5" then current_dir = "" end

            if newly_pressed > 0 then
                table.insert(p_state.input_history_queue,
                    { frame_tick = engine_frame_count, mask = newly_pressed, dir = current_dir })
            end
            p_state.last_direct_input = direct_input

            while #p_state.input_history_queue > 0 and (engine_frame_count - p_state.input_history_queue[1].frame_tick) > 60 do
                table.remove(p_state.input_history_queue, 1)
            end

            -- ANTI-GHOSTING DEBOUNCE LOGIC
            local ghost_wait = ctx.d2d_cfg.ghost_filter_frames or 4

            p_state.buffer_act_id = p_state.buffer_act_id or -1
            p_state.buffer_act_frame = p_state.buffer_act_frame or -1
            p_state.buffer_start_frame = p_state.buffer_start_frame or -1
            p_state.buffer_flags = p_state.buffer_flags or 0
            p_state.buffer_action_code = p_state.buffer_action_code or 0
            p_state.buffer_direct_input = p_state.buffer_direct_input or 0
            p_state.buffer_b_type = p_state.buffer_b_type or 0
            p_state.buffer_hold_frames = p_state.buffer_hold_frames or 0
            if p_state.buffer_is_committed == nil then p_state.buffer_is_committed = true end

            local actions_to_process = {}
            local started_new_action = false
            if act_id ~= p_state.buffer_act_id or (act_frame < p_state.buffer_act_frame and act_frame < 2) then
                started_new_action = true
            end
            p_state.buffer_act_frame = act_frame

            if started_new_action then
                if p_state.buffer_act_id ~= -1 and not p_state.buffer_is_committed then
                    local duration = engine_frame_count - p_state.buffer_start_frame
                    local is_ghost = false
                    
                    -- Bypass ghost filtering for Alex's action 976
                    local is_alex_exempt = (p_state.profile_name == "Alex" and p_state.buffer_act_id == 976)

                    if duration > 0 and duration < ghost_wait and p_state.buffer_act_id > 50 and not is_alex_exempt then
                        -- EXACT EVALUATION OF THE NEW ACTION
                        -- We must know if the game triggered it automatically or if the player pressed a button
                        local new_is_intentional = false
                        if flags == 0 then
                            new_is_intentional = true
                        elseif flags == 16 then
                            if action_code > 0 and b_type ~= 0 then
                                new_is_intentional = true
                            elseif b_type == 536870932 and (direct_input & 0xFFFF) > 0 then
                                new_is_intentional = true
                            end
                        end
                        if act_id == 36 or act_id == 37 or act_id == 38 then new_is_intentional = true end
                        
                        local exc_new = p_state.exceptions[tostring(act_id)] or common_exceptions[tostring(act_id)]
                        if exc_new and exc_new.force then new_is_intentional = true end

                        -- If the NEW action is truly intentional (e.g. player hit P, then PP 2 frames later),
                        -- THEN the buffered action is a ghost.
                        -- But if the NEW action is automatic (e.g. Kimberly auto-sprint after EX move),
                        -- the buffered action IS NOT a ghost, it is valid and must be committed.
                        if new_is_intentional then
                            is_ghost = true
                        end
                    end

                    if is_ghost then
                        local g_name = act_id_reverse_enum[p_state.buffer_act_id] or "Unknown"
                        table.insert(p_state.log, 1, {
                            id = p_state.buffer_act_id,
                            name = g_name,
                            motion = p_state.bcm_cache[p_state.buffer_act_id] or g_name,
                            real_input = "Ghost",
                            frame_diff = "0f",
                            intentional = false,
                            is_holdable = false,
                            is_ignored = true,
                            ignore_reason = "[Ghost Input: " .. tostring(duration) .. "f]",
                            facing_left = false,
                            start_frame = p_state.buffer_start_frame
                        })
                        if #p_state.log > 100 then table.remove(p_state.log) end
                    else
                        -- Not a ghost (survived or interrupted by system). Force commit it immediately!
                        table.insert(actions_to_process, {
                            id = p_state.buffer_act_id,
                            flags = p_state.buffer_flags,
                            action_code = p_state.buffer_action_code,
                            direct_input = p_state.buffer_direct_input,
                            b_type = p_state.buffer_b_type,
                            engine_frame = p_state.buffer_start_frame,
                            buffer_hold_frames = p_state.buffer_hold_frames,
                            p1 = p_state.buffer_p1, p2 = p_state.buffer_p2,
                            r1 = p_state.buffer_r1, r2 = p_state.buffer_r2,
                            current_hp = p_state.buffer_current_hp
                        })
                    end
                end
                p_state.buffer_act_id = act_id
                p_state.buffer_start_frame = engine_frame_count
                p_state.buffer_is_committed = false
                p_state.buffer_flags = flags
                p_state.buffer_action_code = action_code
                p_state.buffer_direct_input = direct_input
                p_state.buffer_b_type = b_type
                p_state.buffer_hold_frames = 0
                p_state.buffer_current_hp = p_char.vital_new
                -- Snapshot immédiat des positions à la frame exacte de l'input
                local _p1, _p2, _r1, _r2 = capture_current_positions()
                p_state.buffer_p1 = _p1; p_state.buffer_p2 = _p2
                p_state.buffer_r1 = _r1; p_state.buffer_r2 = _r2
            end

            -- TRACKING TEMPS RÉEL DU HOLD PENDANT LE BUFFER
            if not p_state.buffer_is_committed and p_state.buffer_act_id ~= -1 then
                local buf_btn = p_state.buffer_direct_input & 0xFFF0
                if buf_btn > 0 and (direct_input & buf_btn) ~= 0 then
                    p_state.buffer_hold_frames = p_state.buffer_hold_frames + 1
                end
            end

            if not p_state.buffer_is_committed and (engine_frame_count - p_state.buffer_start_frame) >= ghost_wait then
                p_state.buffer_is_committed = true
                table.insert(actions_to_process, {
                    id = p_state.buffer_act_id,
                    flags = p_state.buffer_flags,
                    action_code = p_state.buffer_action_code,
                    direct_input = p_state.buffer_direct_input,
                    b_type = p_state.buffer_b_type,
                    engine_frame = p_state.buffer_start_frame,
                    buffer_hold_frames = p_state.buffer_hold_frames,
                    p1 = p_state.buffer_p1, p2 = p_state.buffer_p2,
                    r1 = p_state.buffer_r1, r2 = p_state.buffer_r2,
                    current_hp = p_state.buffer_current_hp
                })
            end

            for _, process_act in ipairs(actions_to_process) do
                local act_id = process_act.id
                local flags = process_act.flags
                local action_code = process_act.action_code
                local direct_input = process_act.direct_input
                local b_type = process_act.b_type
                local engine_frame_count = process_act.engine_frame
                local act_name = act_id_reverse_enum[act_id] or "Unknown"

                -- 1. RESOLUTION ANTICIPEE DES EXCEPTIONS (Pour le Hold Link)
                local exc_char = p_state.exceptions[tostring(act_id)]
                local exc_com = common_exceptions[tostring(act_id)]
                local exc = exc_char or exc_com

                if p_state.editing_id == act_id then
                    exc = {
                        ignore = p_state.edit_ignore,
                        force = p_state.edit_force,
                        is_holdable = p_state.edit_holdable,
                        hold_partial_check = p_state.edit_hold_partial_check,
                        absorb_ids = p_state.edit_absorb_ids,
                        charge_min = tonumber(p_state.edit_charge_min),
                        charge_max = tonumber(p_state.edit_charge_max),
                        override_name = (p_state.edit_text ~= "") and p_state.edit_text or nil,
                        ignore_prev_id = tonumber(p_state.edit_ignore_prev_id),
                        ignore_prev_frames = tonumber(p_state.edit_ignore_prev_frames) or 5
                    }
                end

                -- CAMMY SPECIFIC: Force display and rename Spin Knuckle / Cannon Spike after Target Combo
                if p_state.profile_name == "Cammy" and (act_id == 908 or act_id == 922) then
                    if #p_state.log > 0 and (p_state.log[1].id == 652 or p_state.log[1].id == 653 or p_state.log[1].id == 926) then
                        if not exc then exc = {} end
                        exc.force = true
                        if act_id == 908 then
                            exc.override_name = "236+HK"
                        elseif act_id == 922 then
                            exc.override_name = "623+HK"
                        end
                    end
                end

                -- VERIFICATION ABSORPTION (L'action mère active demande-t-elle d'absorber ce nouvel ID ?)
                local is_continuation = false
                if #p_state.log > 0 then
                    local parent_id = p_state.log[1].id
                    local parent_exc = p_state.exceptions[tostring(parent_id)] or common_exceptions[tostring(parent_id)]
                    
                    -- Update en temps réel si on est en train d'éditer l'action mère
                    if p_state.editing_id == parent_id then
                        parent_exc = { absorb_ids = p_state.edit_absorb_ids }
                    end

                    if parent_exc and parent_exc.absorb_ids and type(parent_exc.absorb_ids) == "string" and parent_exc.absorb_ids ~= "" then
                        for absorb_str in string.gmatch(parent_exc.absorb_ids, "([^,]+)") do
                            local absorb_num = tonumber(absorb_str:match("^%s*(.-)%s*$"))
                            if absorb_num and absorb_num == act_id then
                                is_continuation = true
                                break
                            end
                        end
                    end
                end

                -- 2. CLÔTURE DE L'ACTION PRÉCÉDENTE
                if #p_state.log > 0 then
                    local last_log = p_state.log[1]
                    
                    if not is_continuation then
                        last_log.is_finished = true
                        last_log.transition_id = act_id

                        -- Arrêt de sécurité si l'action est coupée brutalement
                        if last_log.is_holdable and last_log.is_holding then
                            last_log.is_holding = false
                        end
                    else
                        -- CONTINUATION : On maintient le log actif
                        p_state.prev_act_id = act_id
                    end
                end

                if not is_continuation then
                local is_trackable = false
				local is_trackable = false
                    local is_ignored = false
                    local ignore_reason = ""

                    -- SÉCURITÉ : Déclaration globale des variables pour éviter les valeurs "nil" dans le log
                    local motion_str = act_name
                    local real_input_str = "Aucun"
                    local frame_diff_str = "0f"
                    local is_holdable = false
                    local is_holding = false
                    local hold_frames = 0
                    local hold_mask = 0
                    local charge_min = nil
                    local charge_max = nil
                    local charge_status = "Charging"
                    local luke_perfect_min = nil
                    local luke_perfect_max = nil
                    local dual_threshold = false
                    local trial_step_idx = nil
                    local is_intentional = false
                    local deep_data = nil
                    local best_match = nil
                    local is_facing_left = false

                    if act_id > 50 or act_id == 17 or act_id == 18 or act_id == 36 or act_id == 37 or act_id == 38 then
                        is_trackable = true
                        if string.find(act_name, "DMG_") or string.find(act_name, "GRD_") or string.find(act_name, "DOWN") or string.find(act_name, "PIYO") then
                            is_ignored = true
                            ignore_reason = "[System: Guard/Down/Stun]"
                        end
                        if not is_ignored and get_damage_type_safe(p_char) ~= 0 then
                            is_ignored = true
                            ignore_reason = "[System: Taking Damage]"
                        end
                    end

                    if is_trackable then
                        if exc and exc.ignore then
                            is_ignored = true
                            ignore_reason = "[Exception: IGNORE]"
                        end

                        -- Check ignore_prev_id condition
                        if not is_ignored and exc and exc.ignore_prev_id then
                            for i = 1, math.min(10, #p_state.log) do
                                local prev_log = p_state.log[i]
                                if prev_log.id == exc.ignore_prev_id then
                                    local frames_since = engine_frame_count - (prev_log.start_frame or engine_frame_count)
                                    if frames_since <= (exc.ignore_prev_frames or 5) then
                                        is_ignored = true
                                        ignore_reason = "[Exception: Ignored after ID " .. exc.ignore_prev_id .. "]"
                                        break
                                    end
                                end
                            end
                        end
                    
                        if p_state.enable_deep_logging then deep_data = capture_deep_action_data(p_char) end

                        if flags == 0 then
                            is_intentional = true
                        elseif flags == 16 then
                            if action_code > 0 and b_type ~= 0 then
                                is_intentional = true
                            elseif b_type == 536870932 and (direct_input & 0xFFFF) > 0 then
                                is_intentional = true
                            end
                        end

                        if exc and exc.force then is_intentional = true end
                        if act_id == 36 or act_id == 37 or act_id == 38 then is_intentional = true end

                        -- Neutralize intentionality if the action is ignored
                        if is_ignored then is_intentional = false end

                        -- CALCUL DE L'ORIENTATION À L'INSTANT T (hors du bloc is_intentional pour que le log y ait accès)
                        pcall(function()
                            local sP = gBattle:get_field("Player"):get_data(nil)
                            local p1_x = sP.mcPlayer[0].pos.x.v
                            local p2_x = sP.mcPlayer[1].pos.x.v
                            if p_idx == 0 then
                                is_facing_left = (p1_x > p2_x)
                            else
                                is_facing_left = (p2_x > p1_x)
                            end
                        end)

                        if is_intentional then
                        -- 1. Calcul des propriétés de charge
                        if exc and exc.is_holdable then
                            is_holdable = true
                            if p_state.profile_name == "Luke" then
                                local w = get_luke_charge_windows(p_char)
                                luke_perfect_min = exc.perfect_min or w.perfect_min
                                luke_perfect_max = exc.perfect_max or w.perfect_max
                            end

                            charge_min = exc.charge_min
                            charge_max = exc.charge_max
                            dual_threshold = (p_state.profile_name == "Lily")
                            if charge_min == nil or charge_min == "" then
                                local detected_min = auto_detect_charge_min(p_char)
                                if detected_min then
                                    charge_min = detected_min
                                    local id_s = tostring(act_id)
                                    local exc_to_update = p_state.exceptions[id_s] or common_exceptions[id_s]
                                    if exc_to_update then
                                        exc_to_update.charge_min = detected_min
                                        if p_state.exceptions[id_s] then
                                            json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                                        else
                                            json.dump_file("exceptions/Common.json", common_exceptions)
                                        end
                                    end
                                end
                            end
                        end

                        -- 2. Détermination finale du motion_str
                        motion_str = p_state.bcm_cache[act_id]
                        local required_mask = p_state.trigger_mask_cache[act_id] or 0
                        local best_match = nil

                        if required_mask > 0 then
                            for i = #p_state.input_history_queue, 1, -1 do
                                local entry = p_state.input_history_queue[i]
                                if (engine_frame_count - entry.frame_tick) <= 15 and (entry.mask & required_mask) ~= 0 then
                                    best_match = entry
                                    break
                                end
                            end
                        end

                        if not best_match then
                            for i = #p_state.input_history_queue, 1, -1 do
                                local entry = p_state.input_history_queue[i]
                                if (engine_frame_count - entry.frame_tick) <= 15 and (entry.mask & 0xFFF0) > 0 then
                                    best_match = entry
                                    break
                                end
                            end
                        end

                        if best_match then
                            local real_btn = decode_button_mask(best_match.mask)
                            real_input_str = best_match.dir
                            if real_btn ~= "" then
                                real_input_str = real_input_str ..
                                    (real_input_str ~= "" and "+" or "") .. real_btn
                            end

                            local diff = engine_frame_count - best_match.frame_tick
                            if diff == 0 then
                                frame_diff_str = "Instantané"
                            else
                                frame_diff_str = "Buffer: " .. tostring(diff) .. "f"
                            end

                            if is_holdable then
                                hold_mask = best_match.mask & 0xFFF0
                                if hold_mask > 0 then
                                    is_holding = true
                                    hold_frames = process_act.buffer_hold_frames or 1
                                end
                            end
                        else
                            real_input_str = "Aucun"
                            frame_diff_str = "?"
                            if is_holdable and p_state.profile_name == "Lily" then
                                hold_mask = direct_input & 0xFFF0
                                if hold_mask > 0 then
                                    is_holding = true
                                    hold_frames = process_act.buffer_hold_frames or 1
                                end
                            end
                        end

                        if not motion_str then
                            if best_match then
                                motion_str = "Follow-up (" .. decode_button_mask(best_match.mask) .. ")"
                            else
                                motion_str = act_name
                            end
                        end

                        if act_id == 739 or act_id == 740 then
                            motion_str = "DRIVE RUSH"
                            if trial_state.is_recording and p_idx == trial_state.recording_player and #trial_state.sequence > 0 then
                                local prev_step = trial_state.sequence[#trial_state.sequence]
                                if prev_step.motion and prev_step.motion:upper():match("PARRY") then
                                    motion_str = "PARRY > RAW DR"
                                    table.remove(trial_state.sequence, #trial_state.sequence)
                                end
                            end
                        end
                        if act_id == 17 then motion_str = "66" end
                        if act_id == 18 then motion_str = "44" end
                        if act_id == 36 then
                            motion_str = "8"; real_input_str = "8"; frame_diff_str = "Mouvement"
                        end
                        if act_id == 37 then
                            motion_str = "9"; real_input_str = "9"; frame_diff_str = "Mouvement"
                        end
                        if act_id == 38 then
                            motion_str = "7"; real_input_str = "7"; frame_diff_str = "Mouvement"
                        end

                        if exc and exc.override_name and exc.override_name ~= "" then
                            motion_str = exc.override_name
                        end

                        -- 3. GESTION DU COMBO TRIAL (Maintenant que motion_str est finalisé !)
                        if trial_state.is_recording and p_idx == trial_state.recording_player then
                            -- Capturer la position exacte à la frame où l'input a été détecté
                            if #trial_state.sequence == 0 then
                                trial_state.start_pos_p1 = process_act.p1
                                trial_state.start_pos_p2 = process_act.p2
                                trial_state.start_pos_p1_raw = process_act.r1
                                trial_state.start_pos_p2_raw = process_act.r2
                            end

                            if #trial_state.sequence > 0 then
                                local prev_step = trial_state.sequence[#trial_state.sequence]
                                prev_step.expected_combo = current_combo
                                
                                -- WHIFF DETECTION : Tagge dynamiquement le coup précédent s'il n'a pas touché
                                -- On vérifie aussi current_combo > 0 car lors d'un cancel, le hit peut être
                                -- comptabilisé la même frame que le changement d'action (race condition)
                                if not prev_step.has_hit and (current_combo or 0) == 0 then
                                    local p_id = prev_step.id or 0
                                    local is_mov = (p_id == 17 or p_id == 18 or p_id == 36 or p_id == 37 or p_id == 38 or p_id == 739 or p_id == 740)
                                    local m_str = prev_step.motion and prev_step.motion:upper() or ""
                                    local is_parry = m_str:match("PARRY")
                                    local is_dash = m_str:match("DASH") or m_str:match("66") or m_str:match("44") or m_str:match("DRIVE RUSH") or m_str:match("DRC")

                                    if not is_mov and not is_parry and not is_dash and not m_str:match("WHIFF") then
                                        prev_step.motion = prev_step.motion .. " (WHIFF)"
                                        -- Met à jour le Live Log pour l'affichage en temps réel
                                        if p_state.log and #p_state.log > 0 then
                                            local log_to_update = p_state.log[1]
                                            if log_to_update and log_to_update.id == prev_step.id then
                                                log_to_update.motion = log_to_update.motion .. " (WHIFF)"
                                            end
                                        end
                                    end
                                elseif (current_combo or 0) > 0 then
                                    prev_step.has_hit = true
                                    -- Capturer CH/PC au moment du hit
                                    if trial_state.is_recording and prev_step.counter_type == 0 then
                                        pcall(function()
                                            local victim_idx = 1 - p_idx
                                            local victim_obj = player_obj:call("getPlayer", victim_idx)
                                            if victim_obj then
                                                local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
                                                local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
                                                if tostring(pc) == "true" then prev_step.counter_type = 2
                                                elseif tostring(ch) == "true" then prev_step.counter_type = 1 end
                                            end
                                        end)
                                    end
                                end
							end

                            local last_rec = trial_state.last_recorded_frame or engine_frame_count
                            local delay = 0
                            if #trial_state.sequence > 0 then delay = engine_frame_count - last_rec end
                            trial_state.last_recorded_frame = engine_frame_count

                            table.insert(trial_state.sequence, {
                                id = act_id,
                                motion = motion_str,
                                expected_hp = process_act.current_hp,
                                is_holdable = is_holdable,
                                dual_threshold = dual_threshold,
                                charge_min = charge_min,
                                charge_max = charge_max,
                                hold_frames = 0,
                                hold_partial_check = (exc and exc.hold_partial_check ~= false) and true or false,
                                expected_combo = 0,
                                actual_combo = 0,
                                has_hit = false,
                                delay_from_prev = delay,
                                facing_left = is_facing_left,
                                counter_type = 0, -- sera mis à jour au moment du hit (CH/PC détecté via flags)
                                next_auto_id = nil -- Sera rempli si l'action suivante est automatique
                            })
                            trial_step_idx = #trial_state.sequence
                        elseif trial_state.is_playing and p_idx == trial_state.playing_player and #trial_state.sequence > 0 then

                            if trial_state.success_timer == 0 and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                                local allow_input = true
                                local expected = trial_state.sequence[trial_state.current_step]

                                if trial_state.fail_timer and trial_state.fail_timer > 0 then
                                    -- Block ALL inputs during fail/reload period
                                    allow_input = false
                                end

                                if allow_input then
                                    if expected and act_id == expected.id then
                                        trial_state._step1_wrong_pending = false
                                        local actual_delay = 0
                                        local last_played = trial_state.last_played_frame or engine_frame_count
                                        if trial_state.current_step > 1 then
                                            actual_delay = engine_frame_count -
                                                last_played
                                        end
                                        trial_state.last_played_frame = engine_frame_count
                                        local frame_diff = actual_delay - (expected.delay_from_prev or 0)

                                        -- Affichage IMMÉDIAT du timing à la frame d'input
                                        if frame_diff < 0 then
                                            trial_state.floating_info = string.format("%d frames too early", math.abs(frame_diff))
                                            trial_state.floating_color = 0xFF00FFAD -- Vert-Jaune (ABGR)
                                        elseif frame_diff > 0 then
                                            trial_state.floating_info = string.format("%d frames too late", frame_diff)
                                            trial_state.floating_color = 0xFF00A5FF -- Orange clair (ABGR)
                                        else
                                            trial_state.floating_info = "Perfect timing"
                                            trial_state.floating_color = 0xFF00FFFF -- Jaune pur (ABGR)
                                        end

                                        -- Si c'est un setup sans hit attendu, on valide l'étape visuelle tout de suite
                                        if expected.expected_combo == 0 then
                                            trial_state.ui_visual_step = trial_state.current_step + 1
                                        end

                                        local combo_ok = true
                                        if trial_state.current_step > 1 then
                                            local prev_step = trial_state.sequence[trial_state.current_step - 1]
                                            if prev_step and prev_step.expected_combo ~= nil then
                                                local skip_strict_check = (prev_step.is_projectile_hit == true)
                                                if not skip_strict_check and (current_combo or 0) ~= prev_step.expected_combo then
                                                    if opponent_knocked_down and (current_combo or 0) == 0 and prev_step.expected_combo == 0 then
                                                        combo_ok = true
                                                    elseif prev_step.expected_combo == 0 and (current_combo or 0) > 0 then
                                                        combo_ok = true
                                                    elseif (current_combo or 0) == 0 and prev_step.expected_combo > 0 then
                                                        -- Oki / cross-up setup : combo dropped naturellement (adversaire relevé)
                                                        combo_ok = true
                                                    elseif expected and expected.expected_combo == 0 then
                                                        -- RESET TOLERANCE 2.0 (Standing Reset / Oki):
                                                        -- The sequence intends for the combo to drop to 0 after this move.
                                                        -- So it doesn't matter if the combo counter is still running (early input) 
                                                        -- or has just naturally dropped to 0. Both states are valid.
                                                        combo_ok = true
                                                    else
                                                        combo_ok = false
                                                    end
                                                end
                                            end
                                        end

                                        local hp_ok = true
                                        if expected.expected_hp ~= nil and process_act.current_hp ~= nil then
                                            -- Validation HP : strict pour oki (expected_combo == 0), tolérant pour combos
                                            local prev_step = trial_state.current_step > 1 and trial_state.sequence[trial_state.current_step - 1] or nil
                                            local is_oki = (prev_step and prev_step.expected_combo == 0)
                                            if is_oki then
                                                if process_act.current_hp ~= expected.expected_hp then
                                                    hp_ok = false
                                                end
                                            end
                                        end

                                        if combo_ok and hp_ok then
                                            trial_step_idx = trial_state.current_step
                                            trial_state.sequence[trial_step_idx].has_hit = false
                                            trial_state.sequence[trial_step_idx].last_frame_diff = frame_diff
                                            trial_state.current_step = trial_state.current_step + 1

                                            -- Appliquer le counter du prochain step à faire
                                            -- Sauf si le step qu'on vient de valider doit encore toucher en CH/PC
                                            local just_validated = trial_state.sequence[trial_state.current_step - 1]
                                            if not just_validated or just_validated.counter_type == 0 then
                                                local next_step = trial_state.sequence[trial_state.current_step]
                                                if next_step and next_step.counter_type then
                                                    set_dummy_counter_type(next_step.counter_type)
                                                end
                                            end

                                            -- INIT UNIVERSAL HOLD : mémoriser le niveau attendu
                                            if expected.is_holdable and expected.charge_status then
                                                local safe_mask = hold_mask
                                                if not safe_mask or safe_mask == 0 then safe_mask = direct_input & 0xFFF0 end
                                                trial_state.active_universal_hold = {
                                                    expected_status = expected.charge_status,
                                                    hold_mask = safe_mask,
                                                    frames = hold_frames or 0,
                                                    charge_min = expected.charge_min,
                                                    charge_max = expected.charge_max,
                                                    profile_name = p_state.profile_name,
                                                    linked_transition_id = expected.linked_transition_id,
                                                    expected_frames = expected.hold_frames,
                                                    hold_partial_check = expected.hold_partial_check
                                                }
                                            end
                                        else
                                            trial_state.fail_timer = d2d_cfg.fail_display_frames or 20
                                            if not hp_ok then
                                                local custom_reason = "WRONG HP (Setup Dropped)"
                                                local prev_step = trial_state.sequence[trial_state.current_step - 1]
                                                if prev_step and prev_step.expected_combo == 0 and prev_step.last_frame_diff then
                                                    if prev_step.last_frame_diff > 2 then
                                                        custom_reason = string.format("SETUP TOO LATE (%df)", prev_step.last_frame_diff)
                                                    elseif prev_step.last_frame_diff < -2 then
                                                        custom_reason = string.format("SETUP TOO EARLY (%df)", math.abs(prev_step.last_frame_diff))
                                                    else
                                                        custom_reason = "MEATY TIMING FAILED"
                                                    end
                                                end
                                                trial_state.fail_reason = custom_reason
                                            elseif frame_diff < -2 then
                                                trial_state.fail_reason = string.format("TOO EARLY (%df)", math.abs(frame_diff))
                                            elseif frame_diff > 2 then
                                                trial_state.fail_reason = string.format("TOO LATE (%df)", frame_diff)
                                            else
                                                trial_state.fail_reason = "COMBO DROPPED"
                                            end
                                        end
                                    else
                                        local is_parry = (motion_str and motion_str:upper():match("PARRY")) or
                                            (real_input_str and real_input_str:upper():match("PARRY")) or
                                            (act_name and act_name:upper():match("PARRY"))
                                        local is_first_step_raw_dr = (trial_state.sequence[1].id == 739 or trial_state.sequence[1].id == 740) and
                                            trial_state.sequence[1].motion and
                                            trial_state.sequence[1].motion:upper():match("RAW DR")
                                        local expecting_raw_dr = expected and (expected.id == 739 or expected.id == 740) and
                                            expected.motion and expected.motion:upper():match("RAW DR")

                                        if expecting_raw_dr and is_parry then
                                            -- Tolerance: Waiting for RAW DR, ignoring the preparatory Parry input
                                        elseif act_id == trial_state.sequence[1].id then
                                            trial_state.fail_timer = 0
                                            trial_state.fail_reason = nil
                                            reset_trial_steps()
                                            trial_step_idx = 1
                                            trial_state.sequence[1].has_hit = false
                                            trial_state.current_step = 2
                                            trial_state.last_played_frame = engine_frame_count
                                        elseif is_first_step_raw_dr and is_parry then
                                            trial_state.fail_timer = 0
                                            trial_state.fail_reason = nil
                                            reset_trial_steps()
                                            trial_step_idx = nil
                                        else
                                            if trial_state.current_step == 1 then
                                                trial_state._step1_wrong_pending = true
                                            else
                                                trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                                trial_state.fail_reason = "WRONG MOVE"
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    -- CODE OK 							

                    -- GESTION DES ACTIONS AUTOMATIQUES APRÈS UN HOLD (hors bloc is_intentional)
                    -- Ceci doit être HORS du bloc is_intentional car les actions auto ne sont pas intentionnelles

                    -- PENDANT LE RECORDING : capture de l'action automatique suivant un step holdable
                    if trial_state.is_recording and p_idx == trial_state.recording_player
                        and not is_intentional and #trial_state.sequence > 0 then
                        local prev_step = trial_state.sequence[#trial_state.sequence]
                        if prev_step.is_holdable and prev_step.next_auto_id == nil then
                            prev_step.next_auto_id = act_id
                        end
                    end

                    -- PENDANT LE PLAYBACK : vérification de l'action automatique exacte
                    if trial_state.is_playing and p_idx == trial_state.playing_player
                        and not is_intentional and trial_state.pending_auto_check then
                        local pac = trial_state.pending_auto_check
                        if act_id ~= pac.expected_id then
                            trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                            trial_state.fail_reason = "WRONG HOLD TIMING"
                        end
                        trial_state.pending_auto_check = nil
                    end
					end

                    ::continue_to_log::
                    table.insert(p_state.log, 1, {
                        dual_threshold = dual_threshold,
                        id = act_id,
                        name = act_name,
                        motion = motion_str,
                        real_input = real_input_str,
                        frame_diff = frame_diff_str,
                        intentional = is_intentional,
                        is_holdable = is_holdable,
                        is_holding = is_holding,
                        hold_frames = hold_frames,
                        hold_mask = hold_mask,
                        trigger_mask = best_match and (best_match.mask & 0xFFF0) or (direct_input & 0xFFF0),
                        is_physically_holding = false,
                        charge_min = charge_min,
                        charge_max = charge_max,
                        charge_status = charge_status,
                        luke_perfect_min = luke_perfect_min,
                        luke_perfect_max = luke_perfect_max,
                        transition_id = nil,
                        deep_data = deep_data,
                        combo_count = 0,
                        is_finished = false,
                        trial_step_idx = trial_step_idx,
                        start_frame = engine_frame_count,
                        facing_left = is_facing_left,
                        is_ignored = is_ignored,
                        ignore_reason = ignore_reason
                    })

                    if #p_state.log > 100 then table.remove(p_state.log) end
                end -- FIN DU BLOC "if not is_continuation"
            end -- FIN DU for _, process_act

            p_state.prev_act_id = act_id
       

        -- ========================================================
        -- UNIVERSAL HOLD EVALUATION (EVALUATE ONLY UPON FULL BUTTON RELEASE)
        -- ========================================================
        if trial_state.is_playing and p_idx == trial_state.playing_player and trial_state.active_universal_hold then
            local uh = trial_state.active_universal_hold
            if uh.hold_mask > 0 and (direct_input & uh.hold_mask) ~= 0 then
                uh.frames = uh.frames + 1
            else
                -- Récupération optionnelle des fenêtres de perfect (ex: Luke)
                local p_min, p_max = nil, nil
                local act_id_str = tostring(p_state.prev_act_id)
                local exc = p_state.exceptions[act_id_str] or common_exceptions[act_id_str]
                if exc then p_min = exc.perfect_min; p_max = exc.perfect_max end

                local final_status = evaluate_charge_status(
                    uh.profile_name, uh.frames,
                    uh.charge_min, uh.charge_max,
                    p_min, p_max
                )
                
                local hold_failed = false
                if final_status ~= uh.expected_status then
                    -- Si hold_partial_check == false, tolérer les mismatches entre niveaux intermédiaires
                    -- (Instant, Partial, Charging, Lv1, Lv2...) mais TOUJOURS exiger Maxed/PERFECT/FAKE/LATE
                    local hard_statuses = { Maxed = true, ["PERFECT!"] = true, FAKE = true, LATE = true }
                    if uh.hold_partial_check == false
                        and not hard_statuses[final_status]
                        and not hard_statuses[uh.expected_status] then
                        -- Mismatch partiel toléré
                    else
                        hold_failed = true
                    end
                end

                if hold_failed then
                trial_state.success_timer = 0
                trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                
                local diff_str = ""
                if uh.expected_frames then
                    local diff = uh.frames - uh.expected_frames
                    local sign = diff > 0 and "+" or ""
                    diff_str = string.format(" [%s%df]", sign, diff)
                end
                
                trial_state.fail_reason = string.format("WRONG HOLD (Got: %s, Exp: %s)%s", final_status, uh.expected_status, diff_str)
                trial_state.current_step = math.max(1, trial_state.current_step - 1)
            end
                trial_state.active_universal_hold = nil
            end
        end

        p_state.last_combo_count = current_combo
		end -- FIN DU if p_char then
    end -- FIN DU for p_idx = 0, 1 do
end)



function save_trial_sequence()
    if #trial_state.sequence == 0 then return end
    local rec_p = trial_state.recording_player
    local char_name = players[rec_p].profile_name

    local p_state = players[rec_p]
    if #trial_state.sequence > 0 and #p_state.log > 0 then
        local last_step = trial_state.sequence[#trial_state.sequence]
        for _, log_entry in ipairs(p_state.log) do
                    if log_entry.trial_step_idx == #trial_state.sequence then
                        last_step.expected_combo = log_entry.combo_count or 0
                        break
                    end
                end

                -- FINAL WHIFF DETECTION : Applique le tag sur le tout dernier coup enregistré
                -- On considère aussi le expected_combo > 0 comme preuve de hit (cancel/dernier coup)
                if not last_step.has_hit and (last_step.expected_combo or 0) == 0 then
                    local p_id = last_step.id or 0
                    local is_mov = (p_id == 17 or p_id == 18 or p_id == 36 or p_id == 37 or p_id == 38 or p_id == 739 or p_id == 740)
                    local m_str = last_step.motion and last_step.motion:upper() or ""
                    local is_parry = m_str:match("PARRY")
                    local is_dash = m_str:match("DASH") or m_str:match("66") or m_str:match("44") or m_str:match("DRIVE RUSH") or m_str:match("DRC")

                    if not is_mov and not is_parry and not is_dash and not m_str:match("WHIFF") then
                        last_step.motion = last_step.motion .. " (WHIFF)"
                    end
                end

                if trial_state.start_pos_p1 and trial_state.start_pos_p2 then
            trial_state.sequence[1].start_pos_p1 = trial_state.start_pos_p1
            trial_state.sequence[1].start_pos_p2 = trial_state.start_pos_p2
            trial_state.sequence[1].start_pos_p1_raw = trial_state.start_pos_p1_raw
            trial_state.sequence[1].start_pos_p2_raw = trial_state.start_pos_p2_raw
            trial_state.sequence[1].recorded_by = rec_p
        end

        -- Calcul des stats du combo (dégâts, drive, super, hit type)
        -- Utilise les valeurs MIN trackées frame par frame (le training refill les jauges)
        local init = trial_state._rec_gauges
        local stats = { hit_type = trial_state._rec_hit_type }
        if init then
            stats.damage     = math.max(0, init.victim_hp - (init.min_victim_hp or init.victim_hp))
            stats.drive_used = math.max(0, init.attacker_drive - (init.min_atk_drive or init.attacker_drive))
            stats.super_used = math.max(0, init.attacker_super - (init.min_atk_super or init.attacker_super))
        end
        trial_state.sequence[1].combo_stats = stats
        if logger_state.last_export_name then
            trial_state.sequence[1].raw_input_file = logger_state.last_export_name
        end
        trial_state._rec_gauges = nil
        trial_state._rec_hit_type = nil
    end

    if fs.create_dir then
        pcall(fs.create_dir, "CustomCombos"); pcall(fs.create_dir, "CustomCombos/" .. char_name)
    end

    -- Filename: CharName_Damage_DriveBarSpent_SABarSpent[_OKI].json
    local cs = trial_state.sequence[1] and trial_state.sequence[1].combo_stats
    local dmg = (cs and cs.damage) or 0
    local drive_spent = (cs and cs.drive_used) or 0
    local sa_spent = (cs and cs.super_used) or 0
    local drive_bars = string.format("%.1f", drive_spent / 10000)
    local sa_bars = string.format("%.1f", sa_spent / 10000)
    drive_bars = drive_bars:gsub("%.0$", "")
    sa_bars = sa_bars:gsub("%.0$", "")

    -- Detect OKI: combo was active (>0), drops to 0, then a later step hits
    local has_oki = false
    local saw_combo = false
    local combo_dropped = false
    for _, step in ipairs(trial_state.sequence) do
        if (step.expected_combo or 0) > 0 then saw_combo = true end
        if saw_combo and (step.expected_combo or 0) == 0 then combo_dropped = true end
        if combo_dropped and step.has_hit then has_oki = true; break end
    end

    local type_tag = has_oki and "_OKI" or "_COMBO"
    local fname = char_name .. type_tag .. "_" .. dmg .. "_D" .. drive_bars .. "_SA" .. sa_bars .. ".json"
    local path = "CustomCombos/" .. char_name .. "/" .. fname

    -- Avoid overwriting: append timestamp if file exists
    local existing = json.load_file(path)
    if existing then
        local ts = os.date("%Y%m%d_%H%M%S")
        fname = char_name .. type_tag .. "_" .. dmg .. "_D" .. drive_bars .. "_SA" .. sa_bars .. "_" .. ts .. ".json"
        path = "CustomCombos/" .. char_name .. "/" .. fname
    end

    assign_groups(trial_state.sequence)
    json.dump_file(path, trial_state.sequence)
    refresh_combo_list(rec_p) -- Injecte l'ID du joueur qui vient de sauvegarder

    return path
end

-- =========================================================
-- MODULE UI (extrait dans func/ComboTrials_UI.lua)
-- =========================================================
-- Ajout des references au contexte partage pour le module UI
ctx.file_system = file_system
ctx.common_exceptions = common_exceptions
ctx.load_and_start_trial = load_and_start_trial
ctx.start_recording = start_recording
ctx.stop_recording_and_save = stop_recording_and_save
ctx.cancel_recording = cancel_recording
ctx.refresh_combo_list = refresh_combo_list
ctx.restore_trial_vital = restore_trial_vital
ctx.save_d2d_config = save_d2d_config
ctx.get_exc_filename = get_exc_filename
ctx.ui_state = ui_state
ctx.apply_forced_position = apply_forced_position
ctx.dump_last_fail = function()
    if not trial_state.last_fail_dump then return nil end
    local char_name = players[trial_state.playing_player].profile_name or "Unknown"
    local ts = os.date("%Y%m%d_%H%M%S")
    local fname = char_name .. "_FAIL_" .. ts .. ".json"
    
    if fs.create_dir then 
        pcall(fs.create_dir, "CustomCombos")
        pcall(fs.create_dir, "CustomCombos/Fails") 
    end
    
    local path = "CustomCombos/Fails/" .. fname
    json.dump_file(path, trial_state.last_fail_dump)
    return path
end
ctx.reset_visuals = function()
    ComboTrials_D2D.reset_anim()
    ComboTrials_D2D.reset_raw()
end
ctx.reset_trial_steps_and_load = function(player_idx)
    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    if #paths > 0 then
        local loaded = json.load_file(paths[idx])
        if loaded then
            trial_state.sequence = loaded
            assign_groups(trial_state.sequence)
        end
    end
    trial_state.is_playing = true
    trial_state.current_step = 1
    trial_state._step1_wrong_pending = false
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state.active_universal_hold = nil
    for _, item in ipairs(trial_state.sequence) do
            item.actual_combo = 0
            item.has_hit = false
            item.last_frame_diff = nil
        end
        
        -- NOUVEAU : Purge mémoire pour que le non-raw disparaisse vraiment
        players[player_idx].log = {}
        players[player_idx].input_history_queue = {}

        ComboTrials_D2D.reset_anim()
        ComboTrials_D2D.reset_raw()
    end
-- =========================================================
-- DEMO ENGINE LOGIC & EXPORTS
-- =========================================================
local function parse_timeline_line(line)
    local frames_str, rest = line:match("^(%d+)f%s*:%s*(.*)")
    if not frames_str then return nil end
    local frames = tonumber(frames_str)
    
    local parts = {}
    for p in rest:gmatch("[^+]+") do table.insert(parts, p:match("^%s*(.-)%s*$")) end
    
    local dir_to_mask = { ["7"]=9, ["8"]=1, ["9"]=5, ["4"]=8, ["5"]=0, ["6"]=4, ["1"]=10, ["2"]=2, ["3"]=6 }
    local btn_to_mask = { ["LP"]=16, ["MP"]=32, ["HP"]=64, ["LK"]=128, ["MK"]=256, ["HK"]=512 }
    
    local mask = dir_to_mask[parts[1]] or 0
    for i = 2, #parts do if btn_to_mask[parts[i]] then mask = mask | btn_to_mask[parts[i]] end end
    return { frames = frames, mask = mask }
end

local function start_demo()
    if not trial_state.sequence or #trial_state.sequence == 0 then return end
    
    -- 1. Check for embedded timeline directly in the file (Merged files)
    local timeline = trial_state.sequence[1].timeline
    
    -- 2. Backward compatibility fallback (Old 2-part files)
    if not timeline then
        local raw_file = trial_state.sequence[1].raw_input_file
        if not raw_file then print("[ComboTrials] No timeline or raw input file!"); return end
        
        local loaded = json.load_file("ReplayRecords/" .. raw_file)
        if not loaded or not loaded.timeline then print("[ComboTrials] Failed to load ReplayRecord"); return end
        timeline = loaded.timeline
    end
    
    demo_state.sequence = {}
    for _, line in ipairs(timeline) do
        local parsed = parse_timeline_line(line)
        if parsed then table.insert(demo_state.sequence, parsed) end
    end
    if #demo_state.sequence == 0 then return end

    -- Force Trial mode to stay active on P1
    trial_state.is_recording = false
    trial_state.is_playing = true
    trial_state.playing_player = 0
    
    -- CLEANUP TIMERS
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state.active_universal_hold = nil
    
    -- NOUVEAU : Purge totale de l'historique au lancement de la Démo
    players[0].log = {}
    players[0].input_history_queue = {}
    if ComboTrials_D2D then
        pcall(function() ComboTrials_D2D.reset_anim() end)
        pcall(function() ComboTrials_D2D.reset_raw() end)
    end
    
    update_trial_flip_state()
    reset_trial_steps()

    demo_state.is_playing = true
    demo_state.countdown = 10
    demo_state.current_frame = 0
    demo_state.current_step = 1
    demo_state.p1_mask = 0
    
	save_dummy_counter_type()

    -- Appliquer le counter_type du premier step
    local first_ct = trial_state.sequence[1] and trial_state.sequence[1].counter_type or 0
    set_dummy_counter_type(first_ct)
    
    print("[ComboTrials] DEMO Started for P1")
end

ctx.demo_state = demo_state
ctx.stop_demo = function() demo_state.is_playing = false end
ctx.start_demo = start_demo

-- (Garde sf6_menu_state en dessous de ça comme avant)
sf6_menu_state = { active = false, x = 0, y = 0, w = 0, h = 0 }
ctx.sf6_menu_state = sf6_menu_state


local ComboTrials_UI = require("func/ComboTrials_UI")
ComboTrials_UI.init(ctx)


-- ============================================================
-- SAVE STATE / LOAD STATE : synchro avec trial en cours
-- ============================================================
local _trial_snapshot    = nil
local _pending_restore   = 0
local _save_pending      = false
local _real_frame        = 0
local _save_fired_at     = 0
local _save_step_at_fire = 1

local function apply_restore()
    if not _trial_snapshot then return end
    if not trial_state.is_playing then return end
    trial_state.current_step      = _trial_snapshot.step or 1
    trial_state.success_timer     = 0
    trial_state.fail_timer        = 0
    trial_state.fail_reason       = nil
    local frames_since            = _trial_snapshot.frames_since_step or 0
    trial_state.last_played_frame = engine_frame_count - frames_since
    if _trial_snapshot.flip_inputs ~= nil then
        trial_state.flip_inputs = _trial_snapshot.flip_inputs
    end
    if _trial_snapshot.sequence then
        for i, saved in ipairs(_trial_snapshot.sequence) do
            if trial_state.sequence[i] then
                trial_state.sequence[i].has_hit      = saved.has_hit
                trial_state.sequence[i].actual_combo = saved.actual_combo
            end
        end
    else
        for _, item in ipairs(trial_state.sequence) do
            item.has_hit      = false
            item.actual_combo = 0
        end
    end
    ComboTrials_D2D.reset_anim()
end

local function clear_trial_snapshot()
    _trial_snapshot  = nil
    _pending_restore = 0
    _save_pending    = false
end

-- Debug log
local _dbg_log = {}
local function dbg(s)
    table.insert(_dbg_log, 1, string.format("[%d] %s", _real_frame, s))
    if #_dbg_log > 20 then table.remove(_dbg_log) end
end

local _save_display = "jamais"
local _save_count   = 0
local _load_display = "jamais"
local _load_count   = 0

-- re.on_draw_ui(function()
-- imgui.begin_window("TrialSaveState DEBUG", true, 0)
-- imgui.text_colored("SAVE: " .. _save_count .. "x  " .. _save_display, 0xFF88FF88)
-- imgui.text_colored("LOAD: " .. _load_count .. "x  " .. _load_display, 0xFF8888FF)
-- imgui.separator()
-- for _, l in ipairs(_dbg_log) do imgui.text(l) end
-- imgui.end_window()
-- end)


local _ss_hooked = false
re.on_frame(function()
    if not _ss_hooked then
        _ss_hooked = true
        local td = sdk.find_type_definition("app.training.TrainingManager")
        if td then
            local save_methods = { "requestSaveState", "SaveKeyData" }
            local load_methods = { "requestLoadState" }
            
            for _, name in ipairs(save_methods) do
                local m = td:get_method(name)
                if m then
                    pcall(function()
                        sdk.hook(m, function(args)
                            if _pending_restore > 0 then return end
                            _save_pending      = true
                            _save_fired_at     = _real_frame
                            _save_step_at_fire = trial_state.current_step
                            dbg("Save() " .. name .. " step=" .. tostring(trial_state.current_step))
                        end, function(retval) return retval end)
                    end)
                end
            end

            for _, name in ipairs(load_methods) do
                local m = td:get_method(name)
                if m then
                    pcall(function()
                        sdk.hook(m, function(args)
                            _load_count   = _load_count + 1
                            _save_pending = false
                            if _trial_snapshot and trial_state.is_playing then
                                _pending_restore = 8
                            end
                        end, function(retval) return retval end)
                    end)
                end
            end
        end
    end

    -- Si Save a firé et qu'aucun Load n'a suivi dans les 5 frames -> vrai Save
    if _save_pending and (_real_frame - _save_fired_at) >= 5 then
        _save_pending = false
        if trial_state.is_playing then
            local snap_sequence = {}
            for i, item in ipairs(trial_state.sequence) do
                snap_sequence[i] = { has_hit = item.has_hit, actual_combo = item.actual_combo }
            end
            _trial_snapshot = {
                step              = _save_step_at_fire,
                frames_since_step = engine_frame_count - (trial_state.last_played_frame or engine_frame_count),
                sequence          = snap_sequence,
                flip_inputs       = trial_state.flip_inputs,
            }
            _save_count     = _save_count + 1
            _save_display   = os.date("%H:%M:%S") .. " [SnapShoted] step=" .. tostring(_save_step_at_fire)
            dbg("-> snapshot saved step=" ..
                tostring(_trial_snapshot.step) .. " frames_since=" .. tostring(_trial_snapshot.frames_since_step))
        end
    end

    -- STOP TRIAL -> effacer
    if not trial_state.is_playing and _trial_snapshot then
        clear_trial_snapshot()
    end

    -- GUARD : annuler le refresh déclenché par save raccourcis quand trial actif avec position forcée
    if trial_state.is_playing and d2d_cfg.forced_position_idx ~= 1 then
        local tm2 = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm2 then
            local ok, ts = pcall(function() return tm2:get_field("_TrainingState") end)
            local ok2, rf = pcall(function() return tm2:get_field("_IsReqRefresh") end)
            if ok and ok2 and ts == 2 and rf == true then
                pcall(function()
                    tm2:set_field("_IsReqRefresh", false)
                    tm2:set_field("_TrainingState", 1)
                end)
            end
        end
    end

   -- Restore différé
    if _pending_restore > 0 then
        _pending_restore = _pending_restore - 1
        if _pending_restore == 0 then
            dbg("apply_restore step=" .. tostring(_trial_snapshot and _trial_snapshot.step or "nil"))
            apply_restore()
        end
    end
end)

-- =========================================================
-- DEMO ENGINE INJECTION HOOKS (Stack-based Player ID tracking)
-- =========================================================
local bf_type = sdk.find_type_definition("app.BattleFlow")
if bf_type then
    local method = bf_type:get_method("UpdateFrameMain")
    if method then
        sdk.hook(method, function(args)
            tick_done_this_frame = false
            p_id_stack = {}
        end, function(retval) return retval end)
    end
end

local cplayer_type = sdk.find_type_definition("nBattle.cPlayer")
if cplayer_type then
    local method = cplayer_type:get_method("pl_input_sub")
    if method then
        sdk.hook(method,
            function(args)
                local hook_addr = sdk.to_int64(args[2])
                local p_id = -1
                
                pcall(function()
                    local gBattle = sdk.find_type_definition("gBattle")
                    if gBattle then
                        local p1 = gBattle:get_field("Player"):get_data(nil).mcPlayer[0]
                        if p1 and p1:get_address() == hook_addr then p_id = 0 end
                    end
                end)
                
                table.insert(p_id_stack, p_id)

                if not tick_done_this_frame and demo_state.is_playing then
                    -- SÉCURITÉ ABSOLUE : Coupe instantanément l'injection si le Trial est annulé/stoppé
                    if not trial_state.is_playing then
                        demo_state.is_playing = false
                        demo_state.p1_mask = 0
                    else
                        local pm = sdk.get_managed_singleton("app.PauseManager")
                        local is_paused = false
                        if pm then
                            local b = pm:get_field("_CurrentPauseTypeBit")
                            if b ~= 64 and b ~= 2112 then is_paused = true end
                        end

                        -- AJOUT : Détection du Refresh Moteur (Ecran Noir)
                        local is_refreshing = false
                        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
                        if tm and tm:get_field("_IsReqRefresh") == true then
                            is_refreshing = true
                        end
                        if trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then
                            is_refreshing = true
                        end

                        -- Ne faire avancer la lecture que si on n'est ni en pause, ni en chargement
                        if not is_paused and not is_refreshing then
                            if demo_state.countdown and demo_state.countdown > 0 then
                                -- PHASE 1 : Décompte des 3 secondes
                                demo_state.countdown = demo_state.countdown - 1
                                demo_state.p1_mask = 0
                            else
                                -- PHASE 2 : Lecture du combo
                                local step = demo_state.sequence[demo_state.current_step]
                                if step then
                                    demo_state.p1_mask = step.mask
                                    demo_state.current_frame = demo_state.current_frame + 1
                                    if demo_state.current_frame >= step.frames then
                                        demo_state.current_step = demo_state.current_step + 1
                                        demo_state.current_frame = 0
                                    end
                                else
                                    -- Demo sequence finished → soft restart (just rewind, no reload)
                                    demo_state.current_step = 1
                                    demo_state.current_frame = 0
                                    demo_state.countdown = 10
                                    demo_state.p1_mask = 0
                                    reset_trial_steps()
                                end
                            end
                        else
                            -- Mettre le masque à 0 pendant le chargement pour ne rien injecter
                            demo_state.p1_mask = 0
                        end
                    end
                    tick_done_this_frame = true
                end
            end,
            function(retval)
                local p_id = table.remove(p_id_stack) or -1

                -- BLOCK P1 INPUTS during fail state (freeze player completely)
                if p_id == 0 and trial_state.is_playing and trial_state.fail_timer and trial_state.fail_timer > 0 then
                    pcall(function()
                        local p1 = sdk.find_type_definition("gBattle"):get_field("Player"):get_data(nil).mcPlayer[trial_state.playing_player]
                        if p1 then
                            p1:set_field("pl_input_new", 0)
                            p1:set_field("pl_sw_new", 0)
                        end
                    end)
                end

                -- BLOCK P1 INPUTS when FUNC button is held (suppress game actions during shortcuts)
                if p_id == 0 and _G.TrainingFuncHeld then
                    pcall(function()
                        local p1 = sdk.find_type_definition("gBattle"):get_field("Player"):get_data(nil).mcPlayer[0]
                        if p1 then
                            p1:set_field("pl_input_new", 0)
                            p1:set_field("pl_sw_new", 0)
                        end
                    end)
                end

                if p_id == 0 and demo_state.is_playing and demo_state.p1_mask > 0 then
                    pcall(function()
                        local p1 = sdk.find_type_definition("gBattle"):get_field("Player"):get_data(nil).mcPlayer[0]
                        local final_mask = demo_state.p1_mask
                        
                        -- Inversion des inputs gauche/droite si P1 regarde à gauche
                        if not p1:get_field("rl_dir") then
                            local has_right = (final_mask & 4) ~= 0 
                            local has_left  = (final_mask & 8) ~= 0 
                            final_mask = final_mask & ~12
                            if has_right then final_mask = final_mask | 8 end 
                            if has_left  then final_mask = final_mask | 4 end 
                        end

                        local orig_in = p1:get_field("pl_input_new") or 0
                        local orig_sw = p1:get_field("pl_sw_new") or 0
                        p1:set_field("pl_input_new", orig_in | final_mask)
                        p1:set_field("pl_sw_new", orig_sw | final_mask)
                    end)
                end
                return retval
            end
        )
    end
end

