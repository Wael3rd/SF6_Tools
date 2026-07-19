local sdk = sdk
local imgui = imgui
local re = re
local json = json
require("func/SharedHooks")
local GS = require("func/GameState")
-- Validation architecture shared with SF6_TOOLS_CC (cdjay)
local ComboTrialsModules = {
    DebugTrace = require("func/ComboTrials/DebugTrace"),
    ActionMatcher = require("func/ComboTrials/ActionMatcher"),
    CharacterRules = require("func/ComboTrials/CharacterRules"),
    Validator = require("func/ComboTrials/Validator"),
    PendingAbsorb = require("func/ComboTrials/PendingAbsorb"),
    BcmCatalog = require("func/ComboTrials/BcmCatalog")
}
local CharacterRules = ComboTrialsModules.CharacterRules
local Validator = ComboTrialsModules.Validator
local ActionMatcher = ComboTrialsModules.ActionMatcher
local BcmCatalog = ComboTrialsModules.BcmCatalog

pcall(function()
    if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end
end)

local _td_gBattle = sdk.find_type_definition("gBattle")
local _td_sfix = sdk.find_type_definition("via.sfix")
local _td_gamepad = sdk.find_type_definition("via.hid.GamePad")


local ui_state = { viewed_player = 0 }

-- EXACT FRAME COUNTER (Lag-independent, synced to engine)
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

-- Unique character resources (drinks, stocks, install timers) — registry and
-- capture/apply/restore system shared with SF6_TOOLS_CC (cdjay) for combo
-- file compatibility (scene_state schema xt.combo_trial.scene.v1)
local unique_resources = {
    by_fighter_id = {
        [1] = {
        name = "Ryu",
        resources = {
            { id = "timer_0_001", kind = "timer", min = 0, max = 2 }
        }
    },
    [3] = {
        name = "Kimberly",
        resources = {
            { id = "stock_0_003", kind = "stock", min = 0, max = 2, allow_infinite = true }
        }
    },
    [5] = {
        name = "Manon",
        resources = {
            { id = "stock_0_005", kind = "stock", min = 0, max = 4 }
        }
    },
    [12] = {
        name = "Lily",
        resources = {
            { id = "stock_0_012", kind = "stock", min = 0, max = 3, allow_infinite = true }
        }
    },
    [15] = {
        name = "Blanka",
        resources = {
            { id = "timer_0_015", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_015", kind = "stock", min = 0, max = 3, allow_infinite = true }
        }
    },
    [16] = {
        name = "Juri",
        resources = {
            { id = "timer_0_016", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_016", kind = "stock", min = 0, max = 3, allow_infinite = true }
        }
    },
    [18] = {
        name = "Guile",
        resources = {
            { id = "timer_0_018", kind = "timer", min = 0, max = 2 }
        }
    },
    [20] = {
        name = "EHonda",
        resources = {
            { id = "stock_0_020", kind = "stock", min = 0, max = 1, allow_infinite = true }
        }
    },
    [21] = {
        name = "Jamie",
        resources = {
            { id = "timer_0_021", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_021", kind = "stock", min = 0, max = 4 }
        }
    },
    [28] = {
        name = "Mai",
        resources = {
            { id = "stock_0_028", kind = "stock", min = 0, max = 5, reject_infinite = true, setter = "SetUnique028_stock_0" }
        }
    },
    [30] = {
        name = "CViper",
        resources = {
            { id = "timer_0_030", kind = "timer", min = 0, max = 2 }
        }
    },
    [32] = {
        name = "Ingrid",
        resources = {
            { id = "stock_0_032", kind = "stock", min = 0, max = 4, allow_infinite = true }
        }
    }
    },
    by_id = nil
}

function unique_resources.resource_by_id(resource_id)
    if not unique_resources.by_id then
        local by_id = {}
        for _, char_data in pairs(unique_resources.by_fighter_id) do
            for _, resource in ipairs(char_data.resources or {}) do
                by_id[resource.id] = resource
            end
        end
        unique_resources.by_id = by_id
    end
    return unique_resources.by_id[resource_id]
end

function unique_resources.fighter_id_for_resource(resource_id)
    for fighter_id, char_data in pairs(unique_resources.by_fighter_id) do
        for _, resource in ipairs(char_data.resources or {}) do
            if resource.id == resource_id then return fighter_id end
        end
    end
    return nil
end

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
    ["ESF_031"] = "Alex",
	["ESF_032"]="Ingrid" 
}


local common_exceptions = CharacterRules.load_common()

local XT_SETTINGS_FILE = "TrainingComboTrials_data/XT_Settings.json"
local xt_settings = { default_author = "Anonymous" }
pcall(function()
    local loaded = _G.safe_load_json and _G.safe_load_json(XT_SETTINGS_FILE)
    if type(loaded) == "table" and type(loaded.default_author) == "string" and loaded.default_author ~= "" then
        xt_settings.default_author = loaded.default_author
    end
end)

-- xt.combo_trial format v2 (joint spec with SF6_TOOLS_CC — docs/COMBO_JSON_SPEC.md)
local XT_RECORDER_VERSION = "2.9.0"

local function iso8601_now()
    local t = os.date("%Y-%m-%dT%H:%M:%S")
    local tz = os.date("%z") or ""
    if #tz == 5 then tz = tz:sub(1, 3) .. ":" .. tz:sub(4) end
    return t .. tz
end

-- Reads P1's control type from the select menu (0 = classic, 1 = modern)
local function read_control_mode()
    local mode = "classic"
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local sm = tm:get_field("_tData"):get_field("SelectMenu")
        local pd = sm and sm.PlayerDatas and sm.PlayerDatas[0]
        local v = pd and tonumber(pd.InputType)
        if v == 1 then mode = "modern" end
    end)
    return mode
end

local function build_auto_xt_meta(sequence)
    local now = iso8601_now()
    local step_notes = {}
    for i = 1, (sequence and #sequence or 0) do step_notes[i] = "" end
    return {
        title = "",
        note = "",
        author = xt_settings.default_author or "Anonymous",
        tags = {},
        step_notes = step_notes,
        language = xt_settings.language or "en",
        control_mode = read_control_mode(),
        created_at = now,
        updated_at = now,
        versions = {
            game = { id = "sf6" },
            recorder = { id = "wtt", version = XT_RECORDER_VERSION },
            json = { id = "xt.combo_trial", version = "2.0.0" }
        },
        schema = 2
    }
end

local function trim_string(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$") or "")
end

local function sanitize_ascii_filename_part(value, max_chars)
    local s = trim_string(value)
    if max_chars then s = s:sub(1, max_chars) end
    s = s:gsub("[^%w%+%-_%.]", "_")
    s = s:gsub("_+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    return s
end

local function get_safe_filename_motion(sequence)
    local motion = sequence and sequence[1] and sequence[1].motion or ""
    motion = tostring(motion):match("^%s*(.-)%s*$") or ""
    if motion == "" then return "UNKNOWN" end
    motion = motion:gsub("^>%s*", "")
    motion = motion:gsub("%s+", "")
    motion = motion:gsub("[<>:\"/\\|%?%*]", "_")
    motion = motion:gsub("[%c]", "")
    motion = motion:gsub("_+", "_")
    motion = motion:gsub("^_+", ""):gsub("_+$", "")
    if motion == "" then motion = "UNKNOWN" end
    return motion
end

local DR_IDS = { [500]=true, [501]=true, [502]=true, [504]=true, [730]=true, [731]=true, [739]=true, [740]=true, [741]=true, [760]=true, [761]=true }

local function is_drive_rush_id(act_id)
    return DR_IDS[act_id] == true
end

local function is_drive_rush_motion(motion)
    if not motion then return false end
    local m = motion:upper()
    return m == "DRIVE RUSH" or m == "DRC" or m == "RAW DR"
end

local function is_parry_action(motion_str, real_input_str, act_name)
    return (motion_str and motion_str:upper():match("PARRY") ~= nil) or
           (real_input_str and real_input_str:upper():match("PARRY") ~= nil) or
           (act_name and act_name:upper():match("PARRY") ~= nil)
end

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

-- GLOBAL COMBO TRIAL STATE
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
    flip_inputs = false,   -- Whether to visually flip the input display
    _rec_gauges = nil,     -- Gauge snapshot at recording start
    _rec_hit_type = nil,   -- CH/PC detected on first hit
    _saved_vital_p1 = nil,
    _saved_vital_p2 = nil,
    _saved_gauge_atk = nil,
    _saved_dummy_action = nil,
    _saved_unique_resources = nil,
    _rec_scene_state = nil,
    _pending_victim_hp = nil,
    _pending_attacker_hp = nil,
    _pending_attacker_drive = nil,
    _pending_attacker_super = nil,
    _rec_pending_snapshot = 0,
    _was_playing = false,   -- Previous state for detecting transitions
    _step1_wrong_pending = false,
    _demo_backup_slot = nil
}

-- =========================================================
-- DEMO ENGINE STATE
-- =========================================================
local demo_state = {
    is_playing = false,
    current_frame = 0,
    current_step = 1,
    sequence = {},
    p1_mask = 0,
    raw_buffer = nil,
    play_index = 1,
    countdown = 0,
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
    local full_path = "TrainingComboTrials_data/ReplayRecords/" .. short_filename
    
    if fs.create_dir then fs.create_dir("TrainingComboTrials_data/ReplayRecords") end
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

    local player_mgr = GS.sP
    if not player_mgr then return end

    local is_paused = GS.in_pause_menu

    local function process_player(index, rec_struct)
        local p = (index == 0) and GS.p1 or GS.p2
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
            
            -- Wait for the first real action (direction or button) to start the timeline
            if not rec_struct.has_started then
                if d == 0 and b == 0 then
                    return -- Ignore all initial neutral frames until an action
                else
                    rec_struct.has_started = true -- Let's go!
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
-- D2D VISUALIZER CONFIGURATION
-- =========================================================
local D2D_CONFIG_FILE = "TrainingComboTrials_data/CommandLogger_Visualizer.json"
local d2d_cfg = {
    enabled = true,
    auto_load = true,
    use_bcm_catalog = false,   -- opt-in: use cdjay's BCM catalog instead of manual exception files
    auto_next_trial = true,    -- after a manual success: auto-load the next combo in the list
    auto_retry_on_fail = true, -- after the fail banner ends: auto-reset the trial
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
    pos_trial_p1 = { x = 0.050, y = 0.177 },
    pos_trial_p2 = { x = 0.850, y = 0.015 },
    pos_trial = { x = 0.400, y = 0.150 },
    cartouche_width = 0.260,
    cartouche_height = 1.730,
    cartouche_offset_x = -0.027,
    cartouche_offset_y = 0.001,
    bar_img_offset_x = -0.014,
    bar_img_offset_y = -0.019,
    done_bar_height = 1.0,
    done_bar_offset_x = -0.014,
    done_bar_offset_y = -0.019,
    overlay_height = 0.950,
    overlay_offset_y = -0.002,
    bar_width_pct = 0.95,
    icon_size = 0.035,
    font_size = 0.028,
    spacing_y = 0.045,
    spacing_x = 0.005,
    text_y_offset = 0.000,
    max_history = 10,
    special_icon_scale = 1.0,
    trial_visible_steps = 13,
    ignore_auto = true,

    -- Separate config for IDLE mode (no active record/trial)
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

    -- HUD Overlay (text on native lines, same positions as HitConfirm)
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
    local loaded = _G.safe_load_json(D2D_CONFIG_FILE)
    if loaded then
        for k, v in pairs(loaded) do
            if type(v) == "table" and type(d2d_cfg[k]) == "table" then
                for k2, v2 in pairs(v) do d2d_cfg[k][k2] = v2 end
            else
                d2d_cfg[k] = v
            end
        end
    end
    _G.ComboTrials_UseBcmCatalog = (d2d_cfg.use_bcm_catalog == true)
end

local function save_d2d_config()
    json.dump_file(D2D_CONFIG_FILE, d2d_cfg)
    _G.ComboTrials_UseBcmCatalog = (d2d_cfg.use_bcm_catalog == true)
end
load_d2d_config()


-- =========================================================
-- SHARED CONTEXT & D2D MODULE
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
-- ORIGINAL COMMAND LOGGER (CONTINUED)
-- =========================================================

-- Player info from shared hook (0_SharedHooks.lua)
re.on_frame(function()
    if _G._shared_player_info then
        for i = 0, 1 do
            local info = _G._shared_player_info[i]
            if info and info.key then
                players[i].profile_name = esf_names_map[info.key] or "Unknown"
            end
        end
    end
end)

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
    return CharacterRules.get_exception_filename(name)
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
    local gBattle = _td_gBattle
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
    if visited[ptr_str] then return "<Already explored>" end
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
            if #elements > 25 then table.insert(arr, "<... and " .. tostring(#elements - 25) .. " more>") end
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

-- Hoisted hot-path helper (no per-call closure). Scratch table preserves
-- partial-write semantics if an SDK call errors mid-body.
local _ct_action_scratch = { act_id = -1, frame = 0, state_flags = -1, action_code = 0, direct_input = 0, branch_type = 0 }
local function _ct_read_action_data(p_obj)
    local r = _ct_action_scratch
    local p_def = p_obj:get_type_definition()
    local d = (p_def:get_field("pl_input_new"):get_data(p_obj)) or 0
    local b = (p_def:get_field("pl_sw_new"):get_data(p_obj)) or 0
    r.direct_input = d | b

    local act_param = p_obj:get_field("mpActParam")
    if not act_param then return end
    local action_part = act_param:get_field("ActionPart")
    if action_part then
        local engine = action_part:get_field("_Engine")
        if engine then
            r.act_id = engine:call("get_ActionID") or -1
            local sf = engine:call("get_ActionFrame")
            if sf then r.frame = tonumber(sf:call("ToString()")) or 0 end
            local m_param = engine:get_field("mParam")
            if m_param then
                local sf_field = m_param:get_type_definition():get_field("state_flags")
                if sf_field then r.state_flags = tonumber(sf_field:get_data(m_param)) or -1 end
            end
        end
    end
    local ki_field = act_param:get_type_definition():get_field("KeyInput")
    if ki_field then
        local ki_data = ki_field:get_data(act_param)
        if ki_data then
            local a_field = ki_data:get_type_definition():get_field("Action")
            if a_field then r.action_code = tonumber(a_field:get_data(ki_data)) or 0 end
        end
    end
    local branch = act_param:get_field("Branch")
    if branch then
        local bt_field = branch:get_type_definition():get_field("BranchType")
        if bt_field then r.branch_type = tonumber(bt_field:get_data(branch)) or 0 end
    end
end

local function get_action_data(p_obj)
    if not p_obj then return -1, 0, -1, 0, 0, 0 end
    local r = _ct_action_scratch
    r.act_id, r.frame, r.state_flags, r.action_code, r.direct_input, r.branch_type = -1, 0, -1, 0, 0, 0
    pcall(_ct_read_action_data, p_obj)
    return r.act_id, r.frame, r.state_flags, r.action_code, r.direct_input, r.branch_type
end

local function get_damage_type_safe(p_char)
    if not p_char then return 0 end

    local result = 0
    pcall(function()
        -- Direct syntax via REFramework's syntactic sugar
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
        if f_hs then attacker_hs = f_hs:get_data(attacker_obj) or 0 end
    end)
    return (attacker_hs == 0)
end

local function _ct_read_combo_cnt(p_obj)
    return p_obj:get_type_definition():get_field("combo_cnt"):get_data(p_obj) or 0
end
local function get_combo_count(p_obj)
    if not p_obj then return 0 end
    local s, res = pcall(_ct_read_combo_cnt, p_obj)
    return s and res or 0
end

-- Gauge snapshot (same pattern as SheldonsBoxes)
-- attacker_idx = 0 or 1 (the player performing the combo)
local function snapshot_gauges(attacker_idx)
    local result = nil
    pcall(function()
        local victim_idx = 1 - attacker_idx
        local victim = (victim_idx == 0) and GS.p1 or GS.p2
        local attacker = (attacker_idx == 0) and GS.p1 or GS.p2
        if not victim or not attacker then return end
        local gB = _td_gBattle
        if not gB then return end
        local BT = gB:get_field("Team"):get_data(nil)
        if not BT or not BT.mcTeam then return end

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
            -- Min trackers (updated each frame in on_frame)
            min_victim_hp = v_hp,
            min_atk_drive = a_dr,
            min_atk_super = a_sa
        }
    end)
    return result
end

-- Force exact HP injection on a player
local function _ct_do_inject_vital(player_idx, hp)
    local p = (player_idx == 0) and GS.p1 or GS.p2
    if not p then return end
    p.vital_new = hp
    p.vital_old = hp
    p.heal_new = hp
end
local function inject_player_vital(player_idx, hp)
    pcall(_ct_do_inject_vital, player_idx, hp)
end

local function _ct_do_inject_gauges(player_idx, drive, super)
    local p = (player_idx == 0) and GS.p1 or GS.p2
    if not p then return end
    if drive ~= nil then p.focus_new = drive end
    if super ~= nil then
        local BT = _td_gBattle:get_field("Team"):get_data(nil)
        if BT and BT.mcTeam then BT.mcTeam[player_idx].mSuperGauge = super end
    end
end
local function inject_player_gauges(player_idx, drive, super)
    pcall(_ct_do_inject_gauges, player_idx, drive, super)
end

-- Apply health (Victim = combo damage, Attacker = HP recorded at step 1)
local function apply_trial_vital()
    if not trial_state.sequence[1] then return end
    
    local expected_attacker_hp = trial_state.sequence[1].expected_hp
    if expected_attacker_hp then
        trial_state._pending_attacker_hp = expected_attacker_hp
    end
    
    local cs = trial_state.sequence[1].combo_stats
    if cs and cs.damage and cs.damage > 0 then
        local hp = cs.damage
        local seq = trial_state.sequence
        if #seq >= 2 then
            local last_dmg = seq[#seq].damage_at_step
            local prev_dmg = seq[#seq - 1].damage_at_step
            if last_dmg and prev_dmg and last_dmg == prev_dmg and not seq[#seq].has_hit then
                hp = hp + 1
            end
        end
        trial_state._pending_victim_hp = hp
    end

    if cs and (cs.drive_used ~= nil or cs.super_used ~= nil) then
        -- WTT trial UX: start with exactly the gauge the combo consumes
        trial_state._pending_attacker_drive = cs.drive_used or 0
        trial_state._pending_attacker_super = cs.super_used or 0
    else
        -- Interop fallback (spec v2): recorded starting resources (1:1)
        local s1 = trial_state.sequence[1]
        local sc = s1 and s1.scene_state
        local atk_side = (s1 and s1.recorded_by == 1) and "p2" or "p1"
        local res = sc and sc.players and sc.players[atk_side] and sc.players[atk_side].resources
        if res then
            trial_state._pending_attacker_drive = res.drive or 0
            trial_state._pending_attacker_super = res.super or 0
        end
    end

    -- Victim (dummy) recorded drive / super / burnout (spec v2 scene_state) so a
    -- combo recorded against a burnt-out opponent replays with that state.
    do
        local s1 = trial_state.sequence[1]
        local sc = s1 and s1.scene_state
        local atk_side = (s1 and s1.recorded_by == 1) and "p2" or "p1"
        local vic_side = (atk_side == "p1") and "p2" or "p1"
        local vp = sc and sc.players and sc.players[vic_side]
        if vp then
            if vp.resources then
                trial_state._pending_victim_drive = vp.resources.drive
                trial_state._pending_victim_super = vp.resources.super
            end
            trial_state._pending_victim_burnout = (vp.status and vp.status.burnout == true) or false
        end
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

        if trial_state._pending_attacker_drive ~= nil or trial_state._pending_attacker_super ~= nil then
            local ad = ps.PlayerDatas[attacker_idx]
            if not trial_state._saved_gauge_atk then
                trial_state._saved_gauge_atk = {
                    DG_Type = ad.DG_Type, DG_Stock = ad.DG_Stock, DG_Point = ad.DG_Point,
                    Is_DG_Recovery_Timer = ad.Is_DG_Recovery_Timer, Is_DG_Infinity = ad.Is_DG_Infinity,
                    Is_DG_Point_Lock = ad.Is_DG_Point_Lock, Is_DG_Break = ad.Is_DG_Break,
                    SA_Type = ad.SA_Type, SA_Stock = ad.SA_Stock, SA_Point = ad.SA_Point,
                    Is_SA_Recovery_Timer = ad.Is_SA_Recovery_Timer, Is_SA_Infinity = ad.Is_SA_Infinity,
                    Is_SA_No_Recovery = ad.Is_SA_No_Recovery, Is_SA_Point_Lock = ad.Is_SA_Point_Lock,
                }
            end
            ad.DG_Type = 0
            ad.Is_DG_Infinity = false
            ad.Is_DG_Recovery_Timer = false
            ad.SA_Type = 0
            ad.Is_SA_Infinity = false
            ad.Is_SA_Recovery_Timer = false
            ad.Is_SA_No_Recovery = true
        end

        -- Victim (dummy) drive gauge / burnout state
        if trial_state._pending_victim_burnout ~= nil or trial_state._pending_victim_drive ~= nil then
            local vd = ps.PlayerDatas[victim_idx]
            if not trial_state._saved_gauge_vic then
                trial_state._saved_gauge_vic = {
                    DG_Type = vd.DG_Type, Is_DG_Recovery_Timer = vd.Is_DG_Recovery_Timer,
                    Is_DG_Infinity = vd.Is_DG_Infinity, Is_DG_Break = vd.Is_DG_Break,
                }
            end
            vd.DG_Type = 0
            vd.Is_DG_Infinity = false
            vd.Is_DG_Recovery_Timer = false
            vd.Is_DG_Break = (trial_state._pending_victim_burnout == true)
        end

    end)
end

-- Re-inject HP (after a fail / reset)
local function reinject_trial_vital()
    local attacker_idx = trial_state.playing_player
    local victim_idx = 1 - attacker_idx
    if trial_state._pending_victim_hp and trial_state._pending_victim_hp > 0 then
        inject_player_vital(victim_idx, trial_state._pending_victim_hp)
    end
    if trial_state._pending_attacker_hp and trial_state._pending_attacker_hp > 0 then
        inject_player_vital(attacker_idx, trial_state._pending_attacker_hp)
    end
    if trial_state._pending_attacker_drive or trial_state._pending_attacker_super then
        inject_player_gauges(attacker_idx, trial_state._pending_attacker_drive, trial_state._pending_attacker_super)
    end
    if trial_state._pending_victim_drive ~= nil or trial_state._pending_victim_burnout then
        local vdrive = trial_state._pending_victim_burnout and 0 or trial_state._pending_victim_drive
        inject_player_gauges(victim_idx, vdrive, trial_state._pending_victim_super)
    end
end

-- Restore vital settings to original values
local function restore_trial_vital()
    trial_state._pending_victim_hp = nil
    trial_state._pending_attacker_hp = nil
    trial_state._pending_attacker_drive = nil
    trial_state._pending_attacker_super = nil
    trial_state._pending_victim_drive = nil
    trial_state._pending_victim_super = nil
    trial_state._pending_victim_burnout = nil
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

        if trial_state._saved_gauge_atk then
            local atk_idx = trial_state.playing_player or 0
            local ad = ps.PlayerDatas[atk_idx]
            local sg = trial_state._saved_gauge_atk
            ad.DG_Type = sg.DG_Type; ad.DG_Stock = sg.DG_Stock; ad.DG_Point = sg.DG_Point
            ad.Is_DG_Recovery_Timer = sg.Is_DG_Recovery_Timer; ad.Is_DG_Infinity = sg.Is_DG_Infinity
            ad.Is_DG_Point_Lock = sg.Is_DG_Point_Lock; ad.Is_DG_Break = sg.Is_DG_Break
            ad.SA_Type = sg.SA_Type; ad.SA_Stock = sg.SA_Stock; ad.SA_Point = sg.SA_Point
            ad.Is_SA_Recovery_Timer = sg.Is_SA_Recovery_Timer; ad.Is_SA_Infinity = sg.Is_SA_Infinity
            ad.Is_SA_No_Recovery = sg.Is_SA_No_Recovery; ad.Is_SA_Point_Lock = sg.Is_SA_Point_Lock
            trial_state._saved_gauge_atk = nil
        end

        if trial_state._saved_gauge_vic then
            local vic_idx = 1 - (trial_state.playing_player or 0)
            local vd = ps.PlayerDatas[vic_idx]
            local sv = trial_state._saved_gauge_vic
            vd.DG_Type = sv.DG_Type; vd.Is_DG_Recovery_Timer = sv.Is_DG_Recovery_Timer
            vd.Is_DG_Infinity = sv.Is_DG_Infinity; vd.Is_DG_Break = sv.Is_DG_Break
            trial_state._saved_gauge_vic = nil
        end

    end)
end

-- =========================================================
-- UNIQUE RESOURCES capture/apply/restore (SF6_TOOLS_CC-compatible)
-- Same scene_state schema (xt.combo_trial.scene.v1) as cdjay's fork so
-- combo files stay interchangeable between the two projects.
-- =========================================================

function unique_resources.request_training_refresh()
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm then tm._IsReqRefresh = true end
    end)
end

function unique_resources.trace_restore(event)
    if type(event) ~= "table" then return end
    trial_state._unique_restore_debug = event
end

function unique_resources.get_training_data_objects()
    local result = {}
    pcall(function()
        result.training_manager = sdk.get_managed_singleton("app.training.TrainingManager")
        if not result.training_manager then return end
        result.training_data = result.training_manager:get_field("_tData")
        if not result.training_data then return end
        result.parameter_setting = result.training_data:get_field("ParameterSetting")
        result.select_menu = result.training_data:get_field("SelectMenu")
    end)
    if result.parameter_setting then
        pcall(function() result.unique_data = result.parameter_setting:get_field("UniqueData") end)
        if not result.unique_data then
            pcall(function() result.unique_data = result.parameter_setting.UniqueData end)
        end
        pcall(function() result.param_func = result.parameter_setting:get_field("ParamFunc") end)
        if not result.param_func then
            pcall(function() result.param_func = result.parameter_setting.ParamFunc end)
        end
    end
    if not result.param_func and result.training_data then
        pcall(function() result.param_func = result.training_data:get_field("ParamFunc") end)
        if not result.param_func then
            pcall(function() result.param_func = result.training_data.ParamFunc end)
        end
    end
    return result
end

function unique_resources.read_training_fighter_id(player_idx)
    local fighter_id = nil
    pcall(function()
        local data = unique_resources.get_training_data_objects()
        local sm = data.select_menu
        if not sm or not sm.PlayerDatas then return end
        local player_data = sm.PlayerDatas[player_idx]
        if not player_data then return end
        fighter_id = tonumber(player_data.FighterID)
    end)
    return fighter_id
end

function unique_resources.read_value(unique_data, resource_id)
    if not unique_data or not resource_id then return nil end

    local ok, value = pcall(function() return unique_data[resource_id] end)
    if ok and value ~= nil then return tonumber(value) end

    ok, value = pcall(function() return unique_data:get_field(resource_id) end)
    if ok and value ~= nil then return tonumber(value) end

    return nil
end

function unique_resources.call_setter(data, resource, value)
    if not data or not resource or not resource.setter then return false, "setter_missing" end

    local param_func = data.param_func
    if not param_func then return false, "setter_missing" end

    local ok = pcall(function()
        param_func:call(resource.setter, value)
    end)
    if ok then return true, resource.setter end

    ok = pcall(function()
        param_func[resource.setter](param_func, value)
    end)
    if ok then return true, resource.setter end

    ok = pcall(function()
        param_func[resource.setter](value)
    end)
    if ok then return true, resource.setter end

    return false, "setter_missing"
end

function unique_resources.write_value(unique_data, resource_id, value, data)
    if not unique_data or not resource_id or value == nil then return false end

    local resource = unique_resources.resource_by_id(resource_id)
    if resource and resource.setter and data then
        local setter_ok, setter_method = unique_resources.call_setter(data, resource, value)
        if setter_ok then return true, setter_method end
    end

    local ok = pcall(function()
        unique_data[resource_id] = value
    end)
    if ok then return true, "existing_unique_setter" end

    ok = pcall(function()
        unique_data:set_field(resource_id, value)
    end)
    if ok then return true, "existing_unique_setter" end

    return false, resource and resource.setter and "setter_missing" or "write_failed"
end

function unique_resources.normalize_value(resource, value)
    if not resource then return nil end
    local n = tonumber(value)
    if n == nil then return nil end
    n = math.floor(n + 0.5)

    if n == 7 then
        if resource.allow_infinite then
            return 7
        end
        if resource.reject_infinite then
            return nil, "invalid_value"
        end
    end

    local min_value = resource.min or 0
    local max_value = resource.max or min_value
    if n < min_value then n = min_value end
    if n > max_value then n = max_value end
    return n
end

function unique_resources.capture_for_fighter(fighter_id, unique_data, side_key)
    local char_data = unique_resources.by_fighter_id[tonumber(fighter_id)]
    if not char_data or not unique_data then return nil end

    local unique = {}
    for _, resource in ipairs(char_data.resources or {}) do
        local raw_value = unique_resources.read_value(unique_data, resource.id)
        local value = unique_resources.normalize_value(resource, raw_value)
        if value ~= nil then
            unique[resource.id] = value
        end

        -- LOCAL EXTENSION: resources gained IN-GAME (e.g. Jamie drinking via
        -- 22P) live in cPlayer.mStyleNo, not in the training menu settings.
        -- Prefer the live value for stock resources when it is higher.
        if resource.kind == "stock" then
            pcall(function()
                local p = (side_key == "p2") and GS.p2 or GS.p1
                local live = p and p:get_field("mStyleNo")
                if live and live > 0 and live < 100 then
                    local lv = unique_resources.normalize_value(resource, live)
                    if lv ~= nil and (unique[resource.id] == nil or lv > unique[resource.id]) then
                        unique[resource.id] = lv
                    end
                end
            end)
        end

        -- LOCAL EXTENSION: install timers activated IN-GAME (Denjin Charge,
        -- Feng Shui Engine, etc.) show a live cPlayer.style_timer > 0 while the
        -- menu setting is still 0 (Standard). Record the install as active
        -- (setting value 1 = Activated/Maximum) so the trial re-applies it.
        if resource.kind == "timer" then
            pcall(function()
                local p = (side_key == "p2") and GS.p2 or GS.p1
                local st = p and tonumber(tostring(p:get_field("style_timer")))
                if st and st > 0 then
                    local menu_val = unique[resource.id] or 0
                    if menu_val == 0 then
                        unique[resource.id] = 1
                    end
                end
            end)
        end
    end

    if next(unique) == nil then return nil end
    return unique
end

function unique_resources.capture_by_side()
    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if not unique_data then return nil end

    local players_state = {}
    local has_unique = false

    for player_idx = 0, 1 do
        local fighter_id = unique_resources.read_training_fighter_id(player_idx)
        local side_key = player_idx == 0 and "p1" or "p2"
        local side_state = nil

        if fighter_id ~= nil then
            local unique = unique_resources.capture_for_fighter(fighter_id, unique_data, side_key)
            if unique then
                side_state = {
                    fighter_id = fighter_id,
                    unique = unique
                }
                has_unique = true
            end
        end

        if side_state then
            players_state[side_key] = side_state
        end
    end

    if not has_unique then return nil end
    return players_state
end

function unique_resources.capture_scene_state(recorded_by)
    -- v2 (joint spec): always captured — resources + status are playback
    -- preconditions for every combo, unique data only for install chars
    local players_state = unique_resources.capture_by_side() or {}

    for player_idx = 0, 1 do
        local side_key = player_idx == 0 and "p1" or "p2"
        local side = players_state[side_key] or {}
        if side.fighter_id == nil then
            side.fighter_id = unique_resources.read_training_fighter_id(player_idx)
        end
        pcall(function()
            local p = (player_idx == 0) and GS.p1 or GS.p2
            if not p then return end

            local super = 0
            pcall(function()
                local BT = _td_gBattle:get_field("Team"):get_data(nil)
                if BT and BT.mcTeam and BT.mcTeam[player_idx] then
                    super = BT.mcTeam[player_idx].mSuperGauge or 0
                end
            end)
            side.resources = {
                hp = p.vital_new,
                drive = p.focus_new,
                super = super
            }

            local pose = tonumber(tostring(p:get_field("pose_st"))) or 0
            local stance = "standing"
            if pose == 1 then stance = "crouching"
            elseif pose == 2 then stance = "airborne" end

            local stunned = false
            pcall(function()
                local eng = p.mpActParam.ActionPart._Engine
                if eng then
                    local aid = eng:get_ActionID()
                    stunned = (aid == 293 or aid == 294)
                end
            end)

            local burnout = false
            pcall(function()
                local tm2 = sdk.get_managed_singleton("app.training.TrainingManager")
                local ps2 = tm2:get_field("_tData"):get_field("ParameterSetting")
                local pdd = ps2 and ps2.PlayerDatas and ps2.PlayerDatas[player_idx]
                if pdd then
                    burnout = (pdd.Is_DG_Break == true or pdd.Is_DG_Break == 1)
                end
            end)

            side.status = { burnout = burnout, stunned = stunned, stance = stance }
        end)
        players_state[side_key] = side
    end

    return {
        schema = "xt.combo_trial.scene.v2",
        capture_mode = "portable",
        recorded_by = recorded_by,
        players = players_state
    }
end

function unique_resources.add_recorded_entries(entries, unique_table, side_key, fighter_id, source)
    if type(unique_table) ~= "table" then return end

    for resource_id, value in pairs(unique_table) do
        local resource = unique_resources.resource_by_id(resource_id)
        local normalized = unique_resources.normalize_value(resource, value)
        if normalized ~= nil then
            table.insert(entries, {
                resource_id = resource_id,
                value = normalized,
                resource = resource,
                side_key = side_key,
                fighter_id = fighter_id,
                source = source
            })
        end
    end
end

function unique_resources.collect_recorded_entries()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil end

    local entries = {}
    local scene_state = type(first.scene_state) == "table" and first.scene_state or nil
    local meta = type(first._xt_meta) == "table" and first._xt_meta or nil

    if not scene_state and meta and type(meta.scene_state) == "table" then
        scene_state = meta.scene_state
    end

    if scene_state and type(scene_state.players) == "table" then
        local recorded_by = tonumber(first.recorded_by or scene_state.recorded_by or 0) or 0
        local first_side = recorded_by == 1 and "p2" or "p1"
        local second_side = recorded_by == 1 and "p1" or "p2"

        local function add_side(side_key)
            local side = scene_state.players[side_key]
            if type(side) == "table" then
                unique_resources.add_recorded_entries(entries, side.unique, side_key, side.fighter_id, "scene_state")
            end
        end

        add_side(second_side)
        add_side(first_side)
    end

    if meta and type(meta.environment) == "table" then
        local env = meta.environment
        if type(env.unique) == "table" then
            unique_resources.add_recorded_entries(entries, env.unique, nil, nil, "meta.environment.unique")
            if type(env.unique.p1) == "table" then
                unique_resources.add_recorded_entries(entries, env.unique.p1.unique, "p1", env.unique.p1.fighter_id, "meta.environment.unique.p1")
            end
            if type(env.unique.p2) == "table" then
                unique_resources.add_recorded_entries(entries, env.unique.p2.unique, "p2", env.unique.p2.fighter_id, "meta.environment.unique.p2")
            end
        end
        if type(env.players) == "table" then
            if type(env.players.p1) == "table" then
                unique_resources.add_recorded_entries(entries, env.players.p1.unique, "p1", env.players.p1.fighter_id, "meta.environment.players.p1")
            end
            if type(env.players.p2) == "table" then
                unique_resources.add_recorded_entries(entries, env.players.p2.unique, "p2", env.players.p2.fighter_id, "meta.environment.players.p2")
            end
        end
    end

    -- LOCAL EXTENSION: legacy bridge for combos recorded with the transitional
    -- combo_stats.style_stock format (v2.9)
    if #entries == 0 then
        local cs = type(first.combo_stats) == "table" and first.combo_stats or nil
        local char_id = cs and tonumber(cs.style_char_id)
        local stock = cs and tonumber(cs.style_stock)
        if char_id and stock and stock > 0 then
            local rid = string.format("stock_0_%03d", char_id)
            local resource = unique_resources.resource_by_id(rid)
            local normalized = unique_resources.normalize_value(resource, stock)
            if normalized ~= nil then
                table.insert(entries, {
                    resource_id = rid,
                    value = normalized,
                    resource = resource,
                    side_key = nil,
                    fighter_id = char_id,
                    source = "combo_stats.style_stock"
                })
            end
        end
    end

    if #entries == 0 then return nil end
    return entries
end

function unique_resources.side_to_player_idx(side_key)
    if side_key == "p1" then return 0 end
    if side_key == "p2" then return 1 end
    return nil
end

function unique_resources.any_current_fighter_is(fighter_id)
    for player_idx = 0, 1 do
        if tonumber(unique_resources.read_training_fighter_id(player_idx)) == tonumber(fighter_id) then
            return true
        end
    end
    return false
end

function unique_resources.should_apply_entry(entry)
    if type(entry) ~= "table" then return false, "invalid_entry" end
    local owner_fighter_id = unique_resources.fighter_id_for_resource(entry.resource_id)
    if not owner_fighter_id then return false, "unknown_resource" end

    if entry.fighter_id ~= nil and tonumber(entry.fighter_id) ~= tonumber(owner_fighter_id) then
        return false, "wrong_resource_owner"
    end

    local player_idx = unique_resources.side_to_player_idx(entry.side_key)
    if player_idx ~= nil then
        if tonumber(unique_resources.read_training_fighter_id(player_idx)) ~= tonumber(owner_fighter_id) then
            return false, "current_side_character_mismatch"
        end
        return true
    end

    if unique_resources.any_current_fighter_is(owner_fighter_id) then return true end
    return false, "current_character_mismatch"
end

function unique_resources.save_current()
    if trial_state._saved_unique_resources then return end

    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if not unique_data then return end

    local saved = {}
    unique_resources.resource_by_id("")
    for resource_id, resource in pairs(unique_resources.by_id or {}) do
        local owner_fighter_id = unique_resources.fighter_id_for_resource(resource_id)
        if owner_fighter_id and unique_resources.any_current_fighter_is(owner_fighter_id) then
            local value = unique_resources.normalize_value(resource, unique_resources.read_value(unique_data, resource_id))
            if value ~= nil then saved[resource_id] = value end
        end
    end

    if next(saved) ~= nil then
        trial_state._saved_unique_resources = saved
    end
end

function unique_resources.restore()
    local saved = trial_state._saved_unique_resources
    if type(saved) ~= "table" then return end

    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if unique_data then
        local changed = false
        for resource_id, value in pairs(saved) do
            local owner_fighter_id = unique_resources.fighter_id_for_resource(resource_id)
            if owner_fighter_id and unique_resources.any_current_fighter_is(owner_fighter_id) then
                if unique_resources.write_value(unique_data, resource_id, value, data) then
                    changed = true
                end
            end
        end
        if changed then unique_resources.request_training_refresh() end
    end

    trial_state._saved_unique_resources = nil
end

function unique_resources.apply_recorded()
    local entries = unique_resources.collect_recorded_entries()
    if type(entries) ~= "table" then return false end

    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if not unique_data then return false end

    unique_resources.save_current()

    local changed = false
    for _, entry in ipairs(entries) do
        local should_apply = unique_resources.should_apply_entry(entry)
        if should_apply then
            local ok = unique_resources.write_value(unique_data, entry.resource_id, entry.value, data)
            if ok then
                changed = true
            end
        end
    end

    if changed then unique_resources.request_training_refresh() end
    return changed
end

-- Sets the Dummy Counter state (0=Normal, 1=Counter, 2=Punish Counter)
-- Cache tf_CounterSetting from _tfFuncs
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

-- 0=Normal, 1=CH, 2=PC (via DummyData + bApply, instant without refresh)
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

-- Read the current counter state
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

-- Cache tf_GuardSetting from _tfFuncs
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

local function set_dummy_action_type(val, jump_type)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dd = tm:get_field("_tData"):get_field("DummyStatus"):get_field("DummyData")
        dd.DummyActionType = val
        if jump_type ~= nil then dd.JumpType = jump_type end
    end)
end

-- Returns configured dummy behavior (action type, jump type) — the training
-- menu INTENT, as opposed to the live victim pose (SF6_TOOLS_CC environment)
local function read_dummy_action_type()
    local result, jump = 0, 0
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dd = tm:get_field("_tData"):get_field("DummyStatus"):get_field("DummyData")
        result = dd.DummyActionType or 0
        jump = dd.JumpType or 0
    end)
    return result, jump
end

local function save_dummy_action_type()
    trial_state._saved_dummy_action, trial_state._saved_dummy_jump = read_dummy_action_type()
end

local function restore_dummy_action_type()
    if trial_state._saved_dummy_action ~= nil then
        set_dummy_action_type(trial_state._saved_dummy_action, trial_state._saved_dummy_jump)
        trial_state._saved_dummy_action = nil
        trial_state._saved_dummy_jump = nil
    end
end

local function capture_current_positions()
    local p1_pos, p2_pos, p1_raw, p2_raw = nil, nil, nil, nil
    local p1 = GS.p1
    local p2 = GS.p2

    -- UNIVERSAL FORMULA: Raw value / 65536 = Meters (e.g. 1.31)
    if p1 and p1.pos and p1.pos.x and p1.pos.x.v then
        p1_raw = p1.pos.x.v
        p1_pos = p1_raw / 6553600.0
    end
    if p2 and p2.pos and p2.pos.x and p2.pos.x.v then
        p2_raw = p2.pos.x.v
        p2_pos = p2_raw / 6553600.0
    end
    return p1_pos, p2_pos, p1_raw, p2_raw
end

-- Calculate the facing direction of the active player at trial start
local function update_trial_flip_state(skip_mirror)
    local r1, r2

    if d2d_cfg.forced_position_idx == 1 then
        -- 1. FORCED POS OFF: destination positions (live_start if playing, else live)
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
        -- 2. FORCED POS ON or MIRRORED: Read saved position (game will teleport us there)
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

        -- Swap if the playing player is not the one who recorded
        if trial_state.is_playing and trial_state.playing_player ~= recorded_by then
            local temp = r1
            r1 = r2
            r2 = temp
        end

        -- Automatic mathematical inversion if MIRRORED is selected
        if d2d_cfg.forced_position_idx == 3 and not skip_mirror then
            r1 = -r1
            r2 = -r2
        end
    end

    -- Determine final facing direction (P1 or P2)
    if trial_state.playing_player == 0 then
        -- P1 faces left if physically to the right of P2
        trial_state.flip_inputs = (r1 > r2)
    else
        -- P2 faces left if physically to the right of P1
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
    -- Store exact sfix values for post-refresh correction
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

        -- Juri: the hit after 1218 is not a real follow-up, break the group
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

-- File handling extracted to func/ComboTrials_Files.lua (init below,
-- after its dependencies are defined)
local ComboTrials_Files = require("func/ComboTrials_Files")

local function load_combo_from_file(path)
    return ComboTrials_Files.load_combo_from_file(path)
end

local function reset_visual_state()
    if ComboTrials_D2D then
        pcall(ComboTrials_D2D.reset_anim)
        pcall(ComboTrials_D2D.reset_raw)
    end
    for i = 0, 1 do
        if players[i] then
            players[i].log = {}
            players[i].input_history_queue = {}
        end
    end
end

local function reset_trial_flags()
    trial_state.is_playing = false
    trial_state.is_recording = false
    trial_state._was_playing = false
    trial_state.current_step = 1
    trial_state.ui_visual_step = 1
    trial_state.floating_info = nil
    trial_state._step1_wrong_pending = false
    trial_state._first_hit_landed = false
    trial_state._reset_grace = 0
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state._rec_gauges = nil
    trial_state._rec_scene_state = nil
    trial_state._rec_dummy_action = nil
    trial_state._rec_dummy_jump = nil
    trial_state._rec_hit_type = nil
    trial_state._raw_rec_active = false
    trial_state._attempt_had_demo = false
    trial_state._pending_current_absorb = nil
    if demo_state then demo_state.is_playing = false end
end

ComboTrials_Files.init({
    trial_state = trial_state,
    file_system = file_system,
    players = players,
    assign_groups = assign_groups,
    reset_trial_flags = reset_trial_flags,
    reset_visual_state = reset_visual_state,
})

local function clear_combo_state()
    return ComboTrials_Files.clear_combo_state()
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

    -- Capture live position and refresh (same behavior as start_trial)
    trial_state.start_pos_p1, trial_state.start_pos_p2, trial_state.start_pos_p1_raw, trial_state.start_pos_p2_raw =
        capture_current_positions()
    apply_forced_position(true) -- skip_mirror: record in normal position

    trial_state._rec_gauges = nil
    trial_state._rec_dummy_action, trial_state._rec_dummy_jump = read_dummy_action_type()
    trial_state._rec_pending_snapshot = 8
    trial_state._rec_hit_type = nil
    trial_state._piyo_detected = false
    trial_state._piyo_frame = nil
    trial_state._di_frame = nil
    trial_state._rec_frame_count = 0
    trial_state._raw_rec_buffer = {}
    trial_state._raw_rec_active = true
end

local function start_trial(player_idx)
    restore_trial_vital()
    unique_resources.restore()
    reset_trial_flags()
    trial_state.is_playing = true
    trial_state.playing_player = player_idx
    trial_state._reset_grace = 15

    trial_state.live_start_pos_p1, trial_state.live_start_pos_p2, trial_state.live_start_pos_p1_raw, trial_state.live_start_pos_p2_raw = capture_current_positions()

    reset_visual_state()

    save_dummy_counter_type()
    save_dummy_guard_type()
    save_dummy_action_type()

    -- INJECT COUNTER STATE for the first step
    local first_ct = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].counter_type or 0
    set_dummy_counter_type(first_ct)

    -- INJECT DUMMY BEHAVIOR from step 1: configured menu intent when recorded
    -- (handles jump/crouch configs), else live victim_pose fallback (replays)
    local s1 = trial_state.sequence and trial_state.sequence[1]
    if s1 and s1.dummy_action_type ~= nil then
        set_dummy_action_type(s1.dummy_action_type, s1.dummy_jump_type)
    elseif s1 and s1.victim_pose == 1 then
        set_dummy_action_type(1)
    else
        set_dummy_action_type(0)
    end

    -- APPLY UNIQUE RESOURCES recorded with the combo (Jamie drinks etc.)
    unique_resources.apply_recorded()

    -- Control mode check (spec v2): recorded inputs are not portable across modes
    pcall(function()
        local meta = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1]._xt_meta
        local file_mode = meta and meta.control_mode
        if file_mode and file_mode ~= read_control_mode() then
            if _G.show_custom_ticker then
                _G.show_custom_ticker("WARNING: COMBO RECORDED IN " .. tostring(file_mode):upper() .. " CONTROLS", 0.3)
            end
        end
    end)

    -- Guard: After 1st Hit (2) at trial start
    set_dummy_guard_type(2)
    if _G.p2_vital_mode and type(set_vital_recovery) == "function" then
        set_vital_recovery(1, _G.p2_vital_mode)
    end
    update_trial_flip_state()
    apply_forced_position()
end

local function cancel_recording()
    clear_combo_state()
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

    -- MERGE LOGGER TIMELINE IN MEMORY (no intermediate file)
    local rec = saved_player == 0 and logger_state.rec_p1 or logger_state.rec_p2
    if rec.has_started and #rec.data > 0 and trial_state.sequence and #trial_state.sequence > 0 then
        local timeline = {}
        for _, entry in ipairs(rec.data) do
            local frame_str = tostring(entry.frames) .. "f"
            local dir_str = logger_get_numpad_notation(entry.dir)
            local btn_str = logger_get_btn_string(entry.btn)
            table.insert(timeline, string.format("%s : %s%s", frame_str, dir_str, btn_str))
        end
        trial_state.sequence[1].timeline = timeline
    end
    rec.active = false
    rec.has_started = false
    rec.data = {}

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
    trial_state.ui_visual_step = 1
    trial_state._attempt_had_demo = false
    trial_state._pending_current_absorb = nil
    trial_state.floating_info = nil
    trial_state._step1_wrong_pending = false
    trial_state._first_hit_landed = false
    trial_state._reset_grace = 15
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    for _, item in ipairs(trial_state.sequence) do
        item.actual_combo = 0
        item.has_hit = false
        item.last_frame_diff = nil
    end
    reinject_trial_vital()
    apply_forced_position()
    trial_state._pending_reinject_settings = true
    pcall(collectgarbage, "step", 16)
end

local function refresh_combo_list(recent_saved_player)
    return ComboTrials_Files.refresh_combo_list(recent_saved_player)
end

-- =========================================================
-- HOTKEYS: shared multi-device framework (Training_Hotkeys). Combo trials
-- registers a scope; bindings/menu are owned by Training_Hotkeys.
-- =========================================================
local ComboTrials_Hotkeys = require("func/ComboTrials_Hotkeys")
local TrainingHotkeys = require("func/Training_Hotkeys")

local POS_TICKER_NAMES = { "ANY POSITION", "EXACT POSITION", "MIRROR POSITION" }
local function ct_ticker(msg)
    if _G.show_custom_ticker then _G.show_custom_ticker(msg, 0.3) end
end

local function cycle_position_mode()
    d2d_cfg.forced_position_idx = (d2d_cfg.forced_position_idx or 1) + 1
    if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
    save_d2d_config()
    apply_forced_position()
    ct_ticker("POSITION: " .. (POS_TICKER_NAMES[d2d_cfg.forced_position_idx] or ""))
end

-- =========================================================
-- TRIAL PROGRESSION (SF6_TOOLS_CC feature): auto-advance to next combo
-- =========================================================
ctx.advance_to_next_trial = function()
    local p_idx = trial_state.playing_player or 0
    local paths = (p_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (p_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    if type(paths) ~= "table" or #paths == 0 then return false end
    if idx >= #paths then
        ct_ticker("LAST COMBO IN LIST")
        return false
    end

    if p_idx == 0 then
        file_system.selected_file_idx_p1 = idx + 1
    else
        file_system.selected_file_idx_p2 = idx + 1
    end
    load_and_start_trial(p_idx)
    ct_ticker(string.format("NEXT COMBO (%d/%d)", idx + 1, #paths))
    return true
end

-- =========================================================
-- UNIVERSAL CHARGE STATE MACHINE
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
-- SKIP K.O. & ROUND END ANIMATIONS (Ported from ReplayLabs)
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
        -- Force automatic reset (reposition) as soon as K.O. is detected
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

-- =========================================================
-- HOISTED HOT-PATH HELPERS (no per-frame closure allocations)
-- =========================================================
local function _ct_track_live_combo()
    local p1 = GS.p1
    if not p1 then return end
    local cc = p1:get_type_definition():get_field("combo_cnt"):get_data(p1) or 0

    if not trial_state._onframe_last_cc then trial_state._onframe_last_cc = 0 end

    if trial_state._pending_hit_delay and trial_state._pending_hit_delay > 0 then
        trial_state._pending_hit_delay = trial_state._pending_hit_delay - 1
        if trial_state._pending_hit_delay == 0 and trial_state.is_recording and #trial_state.sequence > 0 then
            local last = trial_state.sequence[#trial_state.sequence]
            last.has_hit = true
            last.expected_combo = trial_state._pending_hit_cc
            trial_state._pending_hit_cc = nil
        end
    end

    if cc > trial_state._onframe_last_cc then
        trial_state._hit_grace = 5
        if trial_state.is_recording and #trial_state.sequence > 0 then
            trial_state._pending_hit_cc = cc
            trial_state._pending_hit_delay = 2
        end
    end

    if trial_state._hit_grace and trial_state._hit_grace > 0 then
        trial_state._hit_grace = trial_state._hit_grace - 1
    end

    trial_state._onframe_last_cc = cc
end

local function _ct_update_flip_live()
    local p1 = GS.p1
    local p2 = GS.p2
    if not p1 or not p2 then return end
    local r1 = p1.pos.x.v
    local r2 = p2.pos.x.v
    local facing_left = false
    if trial_state.playing_player == 0 then
        facing_left = (r1 > r2)
    else
        facing_left = (r2 > r1)
    end
    trial_state.flip_inputs = facing_left
end

local function _ct_replay_bridge_poll()
    local f = io.open("SF6_TrainingRemoteControl_data/Replay_WebBridge.json", "r")
    if not f then return end
    local raw = f:read("*a"); f:close()
    if not raw or #raw < 5 then return end
    local ts = tonumber(raw:match('"_web_timestamp":(%d+)'))
    if not ts then return end
    if not _G._replay_bridge_ts then _G._replay_bridge_ts = 0 end
    if ts <= _G._replay_bridge_ts then return end
    _G._replay_bridge_ts = ts
    local cmd = raw:match('"cmd":"([^"]*)"')
    if not cmd or cmd == "" then return end
    if cmd == "record_p1" then _G.ComboTrials_ReplaySavePlayer = 0; start_recording(0) end
    if cmd == "record_p2" then _G.ComboTrials_ReplaySavePlayer = 1; start_recording(1) end
    if cmd == "stop_save" then _G.ComboTrials_ReplaySavePlayer = trial_state.recording_player; stop_recording_and_save() end
    if cmd == "cancel" then
        local cp = trial_state.recording_player
        cancel_recording()
        _G.ComboTrials_ReplayCanceled = cp
    end
    if cmd == "hide_ui" then _G._tsm_hide_ui = not _G._tsm_hide_ui end
end

local function _ct_detect_piyo()
    local p2 = GS.p2
    if not p2 then return end
    local eng = p2.mpActParam.ActionPart._Engine
    if eng and (eng:get_ActionID() == 293 or eng:get_ActionID() == 294) then
        trial_state._piyo_detected = true
        trial_state._piyo_frame = trial_state._rec_frame_count
    end
end

local function _ct_check_first_hit()
    local attacker_char = (trial_state.playing_player == 0) and GS.p1 or GS.p2
    if attacker_char and get_combo_count(attacker_char) > 0 then
        trial_state._first_hit_landed = true
    end
end

local function _ct_get_player(player_obj, idx)
    return player_obj:call("getPlayer", idx)
end

local function _ct_track_rec_gauges(victim, p_char, p_idx)
    local BT = _td_gBattle:get_field("Team"):get_data(nil)
    if victim and BT and BT.mcTeam then
        local v_hp = victim.vital_new
        local a_dr = p_char.focus_new
        local a_sa = BT.mcTeam[p_idx].mSuperGauge

        local rg = trial_state._rec_gauges
        if v_hp and rg.min_victim_hp then rg.min_victim_hp = math.min(rg.min_victim_hp, v_hp) end
        if a_dr and rg.min_atk_drive then rg.min_atk_drive = math.min(rg.min_atk_drive, a_dr) end
        if a_sa and rg.min_atk_super then rg.min_atk_super = math.min(rg.min_atk_super, a_sa) end
    end
end

local function _ct_capture_rec_hit_type(victim_obj)
    if victim_obj then
        local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
        local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
        if pc == true then
            trial_state._rec_hit_type = "PC"
        elseif ch == true and trial_state._rec_hit_type ~= "PC" then
            trial_state._rec_hit_type = "CH"
        end
    end
end

local function _ct_check_knockdown(victim_obj)
    if not victim_obj then return false end
    local pose_st = victim_obj:get_type_definition():get_field("pose_st"):get_data(victim_obj)
    return (pose_st or 0) == 3
end


-- =========================================================
-- PER-FRAME PLAYER CONTEXT (reused each player-loop iteration)
-- =========================================================
local _pf = {}

-- =========================================================
-- PENDING ABSORB support (SF6_TOOLS_CC validation semantics)
-- =========================================================
local DebugTrace = ComboTrialsModules.DebugTrace

local function is_pressure_tail_step(step)
    return Validator.is_pressure_tail_step(step)
end

local function is_post_hit_setup_step(step_idx)
    if not trial_state.sequence or not step_idx or step_idx < 1 then return false end
    local step = trial_state.sequence[step_idx]
    if not step or step.expected_combo ~= 0 then return false end
    if is_pressure_tail_step(step) then return false end
    if step.has_hit == true then return false end
    local step_damage = tonumber(step.damage_at_step) or 0
    local prev = step_idx > 1 and trial_state.sequence[step_idx - 1] or nil
    local prev_damage = prev and (tonumber(prev.damage_at_step) or 0) or 0
    if step_damage > prev_damage then return false end
    for i = 1, step_idx - 1 do
        local earlier = trial_state.sequence[i]
        if earlier and (earlier.expected_combo or 0) > 0 then
            return true
        end
    end
    return false
end

local function build_absorb_ctx(p_idx, p_state)
    return {
        state = trial_state,
        p_idx = p_idx,
        p_state = p_state,
        frame = engine_frame_count,
        pf = _pf,
        Validator = Validator,
        DebugTrace = DebugTrace,
        is_post_hit_setup_step = is_post_hit_setup_step,
        set_dummy_counter_type = set_dummy_counter_type,
        d2d_cfg = d2d_cfg,
        file_system = file_system,
        act_id_reverse_enum = act_id_reverse_enum
    }
end
local _replay_cleaned = false

-- =========================================================
-- EXTRACTED ON_FRAME SUBSYSTEMS
-- =========================================================

local function ct_handle_web_commands()
    if _G.CurrentTrainerMode == 4 and _G._tsm_web_cmd then
        local cmd = _G._tsm_web_cmd; _G._tsm_web_cmd = nil
        if cmd == "record" then start_recording(0); ct_ticker("RECORDING") end
        if cmd == "start_trial" then load_and_start_trial(0); ct_ticker("TRIAL STARTED") end
        if cmd == "stop_trial" then
            trial_state.is_playing = false; ct_ticker("TRIAL STOPPED")
        end
        if cmd == "toggle_position" then
            d2d_cfg.forced_position_idx = (d2d_cfg.forced_position_idx or 1) + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            apply_forced_position()
            ct_ticker("POSITION: " .. (POS_TICKER_NAMES[d2d_cfg.forced_position_idx] or ""))
        end
        if cmd == "cancel_record" then
            _G.ComboTrials_ReplayCancelPlayer = trial_state.recording_player or 0
            cancel_recording(); ct_ticker("RECORDING CANCELLED")
        end
        if cmd == "stop_record" then stop_recording_and_save(); ct_ticker("RECORDING SAVED") end
        if cmd == "reset_trial" then
            local ok, err = pcall(function()
                if not trial_state.is_playing then return end
                local curr_player = trial_state.playing_player
                local paths = (curr_player == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
                local idx = (curr_player == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
                if #paths > 0 then
                    local loaded = json.load_file(paths[idx])
                    if loaded then trial_state.sequence = loaded; assign_groups(trial_state.sequence) end
                end
                trial_state.current_step = 1; trial_state.success_timer = 0; trial_state.fail_timer = 0
                trial_state.fail_reason = nil; trial_state._step1_wrong_pending = false
                trial_state.active_universal_hold = nil
                for _, item in ipairs(trial_state.sequence) do
                    item.actual_combo = 0; item.has_hit = false; item.last_frame_diff = nil
                end
                trial_state._first_hit_landed = false
                trial_state._reset_grace = 15
                reinject_trial_vital()
                apply_forced_position()
                trial_state._pending_reinject_settings = true
            end)
        end
        if cmd == "demo" then
            pcall(function()
                if not trial_state.is_playing then return end
                if ctx.start_demo then ctx.start_demo() end
            end)
        end
        if cmd == "restart_demo" then
            pcall(function()
                if ctx.start_demo then ctx.start_demo() end
            end)
        end
        if cmd == "quit_demo" then
            pcall(function()
                if ctx.stop_demo then ctx.stop_demo() end
            end)
        end
        if cmd == "mirror" and trial_state.is_playing then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx == 3 and 2 or 3
            if apply_forced_position then apply_forced_position() end
        end
        if cmd == "refresh_combos" then
            pcall(function()
                ComboTrials_Files.refresh_combo_list_preserve_selection()
                ct_ticker("COMBO LIST REFRESHED")
            end)
        end
        if type(cmd) == "string" and cmd:match("^select_file:") then
            local idx = tonumber(cmd:match("^select_file:(%d+)"))
            if idx then
                local p = trial_state.playing_player or 0
                if p == 0 then file_system.selected_file_idx_p1 = idx
                else file_system.selected_file_idx_p2 = idx end
                if trial_state.is_playing then
                    load_and_start_trial(p)
                end
            end
        end
    end
end

local function ct_handle_replay_cleanup(_in_replay)
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
end

local function ct_handle_mode_exit()
    if _G.CurrentTrainerMode ~= 4 then
        if trial_state.is_playing or trial_state.is_recording or (demo_state and demo_state.is_playing) then
            reset_trial_flags()
            reset_visual_state()
            restore_trial_vital()
            unique_resources.restore()
            restore_dummy_counter_type()
            restore_dummy_guard_type()
            restore_dummy_action_type()
            apply_current_position_refresh()
            pcall(collectgarbage, "step", 16)
        end
        trial_state._vital_initialized = false
        return
    end
end

local function ct_handle_first_frame_init()
    if not trial_state._vital_initialized then
        trial_state._vital_initialized = true

        -- Force stop everything lingering from a previous session
        if trial_state.is_playing then
            trial_state.is_playing = false
            trial_state._was_playing = false
        end
        if demo_state and demo_state.is_playing then demo_state.is_playing = false end
        if trial_state.is_recording then cancel_recording() end
        trial_state.flip_inputs = false
        trial_state.floating_info = nil
        _G.ComboTrials_HideNativeHUD = false

        -- Only touch TrainingManager if NOT in replay
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

end

local function ct_handle_pause_positions(is_game_paused, _in_replay)
    -- Entering pause → capture live positions
    if is_game_paused and not trial_state._was_game_paused then
        pcall(function()
            local p1 = GS.p1
            local p2 = GS.p2
            if not p1 or not p2 then return end
            trial_state._pause_live_r1 = p1.pos.x.v
            trial_state._pause_live_r2 = p2.pos.x.v
        end)
    end

    -- Leaving pause → inject captured live positions
    if not is_game_paused and trial_state._was_game_paused then
        if trial_state._pause_live_r1 and trial_state._pause_live_r2 then
            trial_state._unpause_delay = 5
        end
    end
    trial_state._was_game_paused = is_game_paused

    -- Delayed inject after unpause (skip in replay)
    if not _in_replay and trial_state._unpause_delay and trial_state._unpause_delay > 0 then
        trial_state._unpause_delay = trial_state._unpause_delay - 1
        if trial_state._unpause_delay == 0 and trial_state._pause_live_r1 and trial_state._pause_live_r2 then
            pcall(function()
                local p1 = GS.p1
                local p2 = GS.p2
                if not p1 or not p2 then return end
                local sfix_type = _td_sfix
                if not sfix_type then return end
                local sfix_from = sfix_type:get_method("From(System.Double)")
                if not sfix_from then return end
                if p1.POS_SETx then p1:POS_SETx(sfix_from:call(nil, trial_state._pause_live_r1 / 65536.0)) end
                if p2.POS_SETx then p2:POS_SETx(sfix_from:call(nil, trial_state._pause_live_r2 / 65536.0)) end
            end)
            trial_state._pause_live_r1 = nil
            trial_state._pause_live_r2 = nil
        end
    end

end

local function ct_handle_playing_transition()
    -- Detect is_playing transitions for P2 health
    local now_playing = trial_state.is_playing
    if now_playing and not trial_state._was_playing then
        -- Transition OFF -> ON: Apply P2 health = combo damage
        apply_trial_vital()
    elseif not now_playing and trial_state._was_playing then
        -- Transition ON -> OFF: Restore P2 health and reset positions to default
        restore_trial_vital()
        unique_resources.restore()
        trial_state._pending_reinject_settings = false
        set_dummy_counter_type(0)
        set_dummy_guard_type(0)
        trial_state._saved_counter_type = nil
        trial_state._saved_guard_type = nil
        reset_positions_to_default()
    end
    trial_state._was_playing = now_playing
end

local function ct_handle_position_correction(_in_replay)
    -- POST-REFRESH EXACT POSITION CORRECTION (skip in replay)
    if not _in_replay and trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then
        local tm_check = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm_check and tm_check:get_field("_IsReqRefresh") == false then
            trial_state.pending_exact_pos = trial_state.pending_exact_pos - 1
            if trial_state.pending_exact_pos == 0 then
                pcall(function()
                    local r1 = trial_state.exact_inject_r1
                    local r2 = trial_state.exact_inject_r2
                    if not r1 or not r2 then return end

                    local p1 = GS.p1
                    local p2 = GS.p2
                    if not p1 or not p2 then return end

                    local sfix_type = _td_sfix
                    if not sfix_type then return end
                    local sfix_from = sfix_type:get_method("From(System.Double)")
                    if not sfix_from then return end

                    -- r1/r2 are raw sfix values (pos.x.v). In cm: raw / 65536.0
                    if p1.POS_SETx then p1:POS_SETx(sfix_from:call(nil, r1 / 65536.0)) end
                    if p2.POS_SETx then p2:POS_SETx(sfix_from:call(nil, r2 / 65536.0)) end
                end)
            end
        end
    end

    if trial_state._pending_reinject_settings and trial_state.is_playing then
        local tm_s = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm_s and tm_s:get_field("_IsReqRefresh") == false then
            trial_state._pending_reinject_settings = false
            local first_ct = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].counter_type or 0
            set_dummy_counter_type(first_ct)
            set_dummy_guard_type(2)
        end
    end
end

local function ct_handle_hp_injection()
    -- INJECTION HP EXACT VIA PLAYER OBJECT
    -- Inject continuously while the trial waits for the first hit (current_step == 1)
    -- Stop permanently once the victim takes a hit (combo_cnt > 0)
    -- After a refresh (forced pos), wait for the refresh to finish first
    if trial_state.is_playing and trial_state.current_step == 1 then
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local is_refreshing = tm and tm:get_field("_IsReqRefresh")
        -- Detect first hit and latch it (check combo_cnt on ATTACKER)
        -- Skip for a few frames after reset (combo_cnt may still be stale)
        if trial_state._reset_grace and trial_state._reset_grace > 0 then
            trial_state._reset_grace = trial_state._reset_grace - 1
        elseif not trial_state._first_hit_landed and not is_refreshing then
            pcall(_ct_check_first_hit)
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
                if trial_state._pending_attacker_drive or trial_state._pending_attacker_super then
                    inject_player_gauges(attacker_idx, trial_state._pending_attacker_drive, trial_state._pending_attacker_super)
                end
                if trial_state._pending_victim_drive ~= nil or trial_state._pending_victim_burnout then
                    local vdrive = trial_state._pending_victim_burnout and 0 or trial_state._pending_victim_drive
                    inject_player_gauges(victim_idx, vdrive, trial_state._pending_victim_super)
                end
            end
        end
    end

end

local function ct_player_init(p_idx, p_state)
    --- Global Trial Timers (Success & Fail animations)
    if p_idx == trial_state.playing_player then
        if trial_state.success_timer > 0 then
            trial_state.success_timer = trial_state.success_timer - 1
            if trial_state.success_timer <= 0 then
                -- Completion tracking + auto-advance (SF6_TOOLS_CC feature):
                -- demo-driven finishes are tainted and never count
                local advanced = false
                if not trial_state._attempt_had_demo then
                    local sp_idx = trial_state.playing_player or 0
                    local spaths = (sp_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
                    local sidx = (sp_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
                    local spath = spaths and spaths[sidx]
                    if spath and file_system.mark_trial_completed then
                        file_system.mark_trial_completed(spath)
                    end
                    if d2d_cfg.auto_next_trial ~= false then
                        advanced = ctx.advance_to_next_trial()
                    end
                end
                trial_state._attempt_had_demo = false
                if not advanced then
                    reset_trial_steps()
                end
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
                if d2d_cfg.auto_retry_on_fail ~= false then
                    reset_trial_steps()
                else
                    -- Manual mode: leave the trial; restart via shortcut/UI
                    trial_state.is_playing = false
                end
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

        -- RESET TRIAL on character change
        -- The trial depends on both characters, reset if either changes
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
            p_state.exceptions = CharacterRules.load_for_character(p_state.profile_name)
        end
    end

end

local function ct_player_tracking(p_idx, p_state)
    -- LILY STRICT: Track physical button held on controller
    if p_state.profile_name == "Lily" and #p_state.log > 0 and p_state.log[1].trigger_mask then
        p_state.log[1].is_physically_holding = ((direct_input & p_state.log[1].trigger_mask) ~= 0)
    end

    -- ========================================================
    -- SIMPLIFIED COMBO COUNTER HANDLING
    -- ========================================================
    -- Update combo count in the log (for display)
    if (_pf.current_combo or 0) > 0 then
        if #p_state.log > 0 then
            p_state.log[1].combo_count = math.max(p_state.log[1].combo_count or 0,
                _pf.current_combo)
        end
        for i = 1, math.min(15, #p_state.log) do
            if p_state.log[i].intentional then
                p_state.log[i].combo_count = math.max(p_state.log[i].combo_count or 0, _pf.current_combo); break
            end
        end
    end

    -- ========================================================
    -- CONTINUOUS GAUGE TRACKING DURING RECORDING
    -- ========================================================
    		-- DELAYED SNAPSHOT: wait for P2 refresh (100% health) to be applied by the engine
    if trial_state.is_recording and p_idx == trial_state.recording_player
    and trial_state._rec_pending_snapshot and trial_state._rec_pending_snapshot > 0 then
    trial_state._rec_pending_snapshot = trial_state._rec_pending_snapshot - 1
    if trial_state._rec_pending_snapshot == 0 then
    trial_state._rec_gauges = snapshot_gauges(p_idx)
    trial_state._rec_scene_state = unique_resources.capture_scene_state(p_idx)
    -- At this point vital_new = character's real max_hp, so damage is calculated from 100%
    end
    end
    -- Fetch victim once for all checks below
    _pf.victim_idx = 1 - p_idx
    _pf.victim_obj = (_pf.victim_idx == 0) and GS.p1 or GS.p2

    if trial_state.is_recording and p_idx == trial_state.recording_player and trial_state._rec_gauges then
        pcall(_ct_track_rec_gauges, _pf.victim_obj, _pf.p_char, p_idx)
    end

    -- Hit detection for visual display (has_hit + actual_combo + projectile)
    if (_pf.current_combo or 0) > (p_state.last_combo_count or 0) then
        -- Verify hit source: projectile or direct player hit
        local hit_is_projectile = false
        pcall(function()
            hit_is_projectile = check_is_projectile(p_idx, _pf.p_char, _td_gBattle)
        end)

        if trial_state.is_recording and p_idx == trial_state.recording_player then
            if #trial_state.sequence > 0 then
                local step = trial_state.sequence[#trial_state.sequence]
                -- has_hit is now handled by on_frame delayed combo tracking
                -- Track if there was AT LEAST one projectile hit during the action
                step.is_projectile_hit = step.is_projectile_hit or hit_is_projectile
                -- Capture CH/PC at the moment of the hit
                if step.counter_type == 0 then
                    pcall(function()
                        local victim_obj = _pf.victim_obj
                        if victim_obj then
                            local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
                            local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
                            if pc == true then step.counter_type = 2
                            elseif ch == true then step.counter_type = 1 end
                        end
                    end)
                end
            end
        elseif trial_state.is_playing and p_idx == trial_state.playing_player
            and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
            -- Step 1 tolerance: fail if the wrong hit LANDS on the dummy
            if trial_state._step1_wrong_pending and trial_state.current_step == 1 then
                trial_state._step1_wrong_pending = false
                trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                trial_state.fail_reason = "WRONG MOVE"
            end
            local target_step_idx = math.max(1, trial_state.current_step - 1)
            if trial_state._hit_grace and trial_state._hit_grace > 0 then
                target_step_idx = math.min(#trial_state.sequence, trial_state.current_step)
            end
            local prev_step = trial_state.sequence[target_step_idx]
            if prev_step then
                prev_step.actual_combo = _pf.current_combo
                prev_step.has_hit = true
                if hit_is_projectile then prev_step.is_projectile_hit = true end

                -- Hit confirmed: apply the counter_type of the next step
                local next_step = trial_state.sequence[trial_state.current_step]
                if next_step and next_step.counter_type then
                    set_dummy_counter_type(next_step.counter_type)
                else
                    set_dummy_counter_type(0)
                end

                -- Advance ONLY the [ACTION X / Y] counter on impact
                trial_state.ui_visual_step = trial_state.current_step
                trial_state.floating_info = nil -- <-- Clear text while waiting for the next input
            end

        end
    			end

    -- Capture CH/PC continuously during recording (independent of combo count for DI etc.)
    if not trial_state._rec_hit_type and trial_state.is_recording and p_idx == trial_state.recording_player then
        pcall(_ct_capture_rec_hit_type, _pf.victim_obj)
    end

    -- Opponent knockdown detection (pose_st == 3)
    _pf.opponent_knocked_down = false
    local _ok_kd, _kd = pcall(_ct_check_knockdown, _pf.victim_obj)
    if _ok_kd and _kd then _pf.opponent_knocked_down = true end
    -- Guard off as soon as the opponent falls (for okis)
    if trial_state.is_playing and _pf.opponent_knocked_down and not trial_state._guard_off_on_kd then
        set_dummy_guard_type(0)
        trial_state._guard_off_on_kd = true
    elseif trial_state.is_playing and not _pf.opponent_knocked_down and trial_state._guard_off_on_kd then
        trial_state._guard_off_on_kd = false
    end

    -- ========================================================
end

local function ct_player_validation(p_idx, p_state)
    -- Pending absorb confirmation (delayed absorbs, e.g. Honda)
    if trial_state.is_playing and p_idx == trial_state.playing_player then
        ComboTrialsModules.PendingAbsorb.check(build_absorb_ctx(p_idx, p_state), "pending_current_absorb_validation")
    end
    -- SUCCESS VERIFICATION + DROP DETECTION (Trial)
    -- ========================================================
    local is_demo_playing = (demo_state and demo_state.is_playing)
    if trial_state.is_playing and p_idx == trial_state.playing_player and not is_demo_playing then
        local is_hold_pending = (trial_state.active_universal_hold ~= nil)

        if #trial_state.sequence > 0 and trial_state.current_step > #trial_state.sequence then
            local last_step = trial_state.sequence[#trial_state.sequence]
            local observed_combo = math.max(_pf.current_combo or 0, p_state.last_combo_count or 0, last_step.actual_combo or 0)
            if trial_state.success_timer == 0 and not is_hold_pending and not (trial_state.fail_timer and trial_state.fail_timer > 0) and (not last_step.expected_combo or last_step.expected_combo == 0 or observed_combo >= last_step.expected_combo) then
                trial_state.success_timer = d2d_cfg.fail_display_frames or 120
            end
        end

        -- CONTINUOUS COMBO DROP DETECTION:
        if (_pf.current_combo or 0) == 0 and (p_state.last_combo_count or 0) > 0 and not trial_state._pending_hit_cc and not (trial_state._hit_grace and trial_state._hit_grace > 0) then
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
                        elseif not _pf.opponent_knocked_down and not is_reset_expected
                            and not (last_validated.expected_combo == (trial_state.current_step >= 3 and trial_state.sequence[trial_state.current_step - 2].expected_combo or 0)) then
                            ComboTrialsModules.PendingAbsorb.clear(trial_state, "combo_dropped")
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

                    if expected.expected_hp ~= nil and _pf.p_char.vital_new ~= expected.expected_hp then
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
end

local function ct_player_hold_charge(p_state)
    -- CONTINUOUS CHARGE HANDLING
    if #p_state.log > 0 then
        local current_log = p_state.log[1]
        if current_log.is_holdable and current_log.is_holding then
            if current_log.hold_mask > 0 and (_pf.direct_input & current_log.hold_mask) ~= 0 then
                current_log.hold_frames = current_log.hold_frames + 1
            else
                -- PLAYER RELEASED THE BUTTON
                current_log.is_holding = false

                -- Auto-detect max frame for JP/Lily if not configured
                if (p_state.profile_name == "JP" or p_state.profile_name == "Lily") and (current_log.charge_max == nil or current_log.charge_max == "") then
                    current_log.charge_max = current_log.hold_frames
                    local id_s = tostring(current_log.id)
                    local exc_to_update = CharacterRules.get_exception(p_state.exceptions, common_exceptions, id_s)
                    if exc_to_update then
                        exc_to_update.charge_max = current_log.hold_frames
                        if CharacterRules.has_character_exception(p_state.exceptions, id_s) then json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                        else json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions) end
                    end
                end
            end

            current_log.charge_status = evaluate_charge_status(
                p_state.profile_name, current_log.hold_frames,
                current_log.charge_min, current_log.charge_max,
                current_log.luke_perfect_min, current_log.luke_perfect_max
            )

            -- REAL-TIME HOLD SYNCHRONIZATION FOR THE TRIAL
            if trial_state.is_recording and current_log.trial_step_idx and trial_state.sequence[current_log.trial_step_idx] then
                trial_state.sequence[current_log.trial_step_idx].hold_frames = current_log.hold_frames
                trial_state.sequence[current_log.trial_step_idx].charge_status = current_log.charge_status
                trial_state.sequence[current_log.trial_step_idx].charge_max = current_log.charge_max
            end
        end
    end			
end

local function ct_player_input_buffer(p_state)
    local newly_pressed = (_pf.direct_input ~ p_state.last_direct_input) & _pf.direct_input
    local current_dir_val = _pf.direct_input & 0xF
    local current_dir = DIR_MAP[current_dir_val] or "5"
    if current_dir == "5" then current_dir = "" end

    if newly_pressed > 0 then
        table.insert(p_state.input_history_queue,
            { frame_tick = engine_frame_count, mask = newly_pressed, dir = current_dir })
    end
    p_state.last_direct_input = _pf.direct_input

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

    local actions_to_process = p_state._act_queue
    if not actions_to_process then actions_to_process = {}; p_state._act_queue = actions_to_process end
    for i = 1, #actions_to_process do actions_to_process[i] = nil end
    local started_new_action = false
    if _pf.act_id ~= p_state.buffer_act_id or (_pf.act_frame < p_state.buffer_act_frame and _pf.act_frame < 2) then
        started_new_action = true
    end
    p_state.buffer_act_frame = _pf.act_frame

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
                if _pf.flags == 0 then
                    new_is_intentional = true
                elseif _pf.flags == 16 then
                    if _pf.action_code > 0 and _pf.b_type ~= 0 then
                        new_is_intentional = true
                    elseif _pf.b_type == 536870932 and (_pf.direct_input & 0xFFFF) > 0 then
                        new_is_intentional = true
                    end
                end
                if _pf.act_id == 36 or _pf.act_id == 37 or _pf.act_id == 38 then new_is_intentional = true end

                local exc_new = CharacterRules.get_exception(p_state.exceptions, common_exceptions, _pf.act_id)
                if ActionMatcher.is_force_enabled(exc_new) then new_is_intentional = true end

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
        p_state.buffer_act_id = _pf.act_id
        p_state.buffer_start_frame = engine_frame_count
        p_state.buffer_is_committed = false
        p_state.buffer_flags = _pf.flags
        p_state.buffer_action_code = _pf.action_code
        p_state.buffer_direct_input = _pf.direct_input
        p_state.buffer_b_type = _pf.b_type
        p_state.buffer_hold_frames = 0
        p_state.buffer_current_hp = _pf.p_char.vital_new
        -- Immediate position snapshot at the exact frame of the input
        local _p1, _p2, _r1, _r2 = capture_current_positions()
        p_state.buffer_p1 = _p1; p_state.buffer_p2 = _p2
        p_state.buffer_r1 = _r1; p_state.buffer_r2 = _r2
    end

    -- REAL-TIME HOLD TRACKING DURING BUFFER
    if not p_state.buffer_is_committed and p_state.buffer_act_id ~= -1 then
        local buf_btn = p_state.buffer_direct_input & 0xFFF0
        if buf_btn > 0 and (_pf.direct_input & buf_btn) ~= 0 then
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
    return actions_to_process
end

local function ct_player_process_actions(p_idx, p_state, actions_to_process)
    for _, process_act in ipairs(actions_to_process) do
        local act_id = process_act.id
        local flags = process_act.flags
        local action_code = process_act.action_code
        local direct_input = process_act.direct_input
        local b_type = process_act.b_type
        local engine_frame_count = process_act.engine_frame
        local act_name = act_id_reverse_enum[act_id] or "Unknown"

        -- 1. EARLY EXCEPTION RESOLUTION (For Hold Link)
        local exc, exc_char, exc_com = CharacterRules.get_exception(p_state.exceptions, common_exceptions, act_id)

        -- BCM Catalog (opt-in toggle): when enabled, cdjay's compiled catalog
        -- handles AC install aliases + classic display in place of the manual
        -- exception files. Cached per character; data exists for a few chars only
        -- (falls back to exceptions when there is no catalog for this character).
        local bcm_catalog = nil
        if _G.ComboTrials_UseBcmCatalog then
            bcm_catalog = BcmCatalog.load_for_character(p_state.profile_name)
        end

        if p_state.editing_id == act_id then
            exc = ActionMatcher.build_edit_exception(p_state)
        end

        -- Character-specific runtime overrides (Cammy TC followups etc.)
        exc = CharacterRules.apply_runtime_overrides(p_state.profile_name, act_id, exc, p_state.log)

        -- ABSORPTION CHECK (Does the active parent action want to absorb this new ID?)
        local is_continuation = false
        if #p_state.log > 0 then
            local parent_id = p_state.log[1].id
            local parent_exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, parent_id)

            -- Real-time update if we are editing the parent action
            if p_state.editing_id == parent_id then
                parent_exc = { absorb_ids = p_state.edit_absorb_ids }
            end

            if bcm_catalog then
                is_continuation = BcmCatalog.is_alias_for(bcm_catalog, act_id, parent_id)
            else
                is_continuation = ActionMatcher.matches_absorb_id(parent_exc, act_id)
            end
        end

        -- 2. CLOSING THE PREVIOUS ACTION
        if #p_state.log > 0 then
            local last_log = p_state.log[1]

            if not is_continuation then
                last_log.is_finished = true
                last_log.transition_id = act_id

                -- Safety stop if the action is abruptly interrupted
                if last_log.is_holdable and last_log.is_holding then
                    last_log.is_holding = false
                end
            else
                -- CONTINUATION: Keep the log active
                p_state.prev_act_id = act_id
            end
        end

        if not is_continuation then
        local is_trackable = false
            local is_ignored = false
            local ignore_reason = ""

            -- SAFETY: Global variable declarations to avoid "nil" values in the log
            local motion_str = act_name
            local real_input_str = "None"
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
                if not is_ignored and get_damage_type_safe(_pf.p_char) ~= 0 then
                    is_ignored = true
                    ignore_reason = "[System: Taking Damage]"
                end
            end

            if is_trackable then
                if ActionMatcher.is_exception_ignored(exc) then
                    is_ignored = true
                    ignore_reason = "[Exception: IGNORE]"
                end

                -- Check ignore_prev_id condition (supports single number or table of numbers)
                -- Decision via ActionMatcher; reason string kept local (per-language display)
                if not is_ignored and exc and exc.ignore_prev_id then
                    local prev_eval = ActionMatcher.evaluate_ignore_prev(exc, p_state.log, engine_frame_count)
                    if prev_eval.ignored then
                        is_ignored = true
                        local id_disp = type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id)
                        ignore_reason = "[Exception: Ignored after ID " .. id_disp .. "]"
                    end
                end

                if p_state.enable_deep_logging then deep_data = capture_deep_action_data(_pf.p_char) end

                if flags == 0 then
                    is_intentional = true
                elseif flags == 16 then
                    if action_code > 0 and b_type ~= 0 then
                        is_intentional = true
                    elseif b_type == 536870932 and (direct_input & 0xFFFF) > 0 then
                        is_intentional = true
                    end
                end

                if ActionMatcher.is_force_enabled(exc) then is_intentional = true end
                if act_id == 36 or act_id == 37 or act_id == 38 then is_intentional = true end

                -- Neutralize intentionality if the action is ignored
                if is_ignored then is_intentional = false end

                -- CALCULATE FACING DIRECTION AT THIS FRAME (outside is_intentional block so log has access)
                pcall(function()
                    local gs_p1 = GS.p1
                    local gs_p2 = GS.p2
                    if not gs_p1 or not gs_p2 then return end
                    local p1_x = gs_p1.pos.x.v
                    local p2_x = gs_p2.pos.x.v
                    if p_idx == 0 then
                        is_facing_left = (p1_x > p2_x)
                    else
                        is_facing_left = (p2_x > p1_x)
                    end
                end)

                if is_intentional then
                -- 1. Calculate charge properties
                if exc and exc.is_holdable then
                    is_holdable = true
                    if p_state.profile_name == "Luke" then
                        local w = get_luke_charge_windows(_pf.p_char)
                        luke_perfect_min = exc.perfect_min or w.perfect_min
                        luke_perfect_max = exc.perfect_max or w.perfect_max
                    end

                    charge_min = exc.charge_min
                    charge_max = exc.charge_max
                    dual_threshold = (p_state.profile_name == "Lily")
                    if charge_min == nil or charge_min == "" then
                        local detected_min = auto_detect_charge_min(_pf.p_char)
                        if detected_min then
                            charge_min = detected_min
                            local id_s = tostring(act_id)
                            local exc_to_update = CharacterRules.get_exception(p_state.exceptions, common_exceptions, id_s)
                            if exc_to_update then
                                exc_to_update.charge_min = detected_min
                                if CharacterRules.has_character_exception(p_state.exceptions, id_s) then
                                    json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                                else
                                    json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions)
                                end
                            end
                        end
                    end
                end

                -- 2. Final motion_str determination
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
                        frame_diff_str = "Instant"
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
                    real_input_str = "None"
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

                if is_drive_rush_id(act_id) then
                    if not is_drive_rush_motion(motion_str) then motion_str = "DRIVE RUSH" end
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

                if bcm_catalog then
                    local cat_disp = BcmCatalog.get_classic_display(bcm_catalog, act_id)
                    if cat_disp then motion_str = cat_disp
                    else motion_str = ActionMatcher.apply_override_name(motion_str, exc) end
                else
                    motion_str = ActionMatcher.apply_override_name(motion_str, exc)
                end

                -- 3. COMBO TRIAL HANDLING (Now that motion_str is finalized!)
                if trial_state.is_recording and p_idx == trial_state.recording_player then
                    -- Capture exact position at the frame when input was detected
                    if #trial_state.sequence == 0 then
                        trial_state.start_pos_p1 = process_act.p1
                        trial_state.start_pos_p2 = process_act.p2
                        trial_state.start_pos_p1_raw = process_act.r1
                        trial_state.start_pos_p2_raw = process_act.r2
                    end

                    if #trial_state.sequence > 0 then
                        local prev_step = trial_state.sequence[#trial_state.sequence]
                        if not trial_state._pending_hit_cc then
                            prev_step.expected_combo = _pf.current_combo
                        end

                        -- WHIFF DETECTION: Dynamically tag the previous hit if it didn't connect
                        -- Also check _pf.current_combo > 0 because during a cancel, the hit can be
                        -- counted on the same frame as the action change (race condition)
                        if not prev_step.has_hit and (_pf.current_combo or 0) == 0 then
                            local p_id = prev_step.id or 0
                            local is_mov = (p_id == 17 or p_id == 18 or p_id == 36 or p_id == 37 or p_id == 38) or is_drive_rush_id(p_id)
                            local m_str = prev_step.motion and prev_step.motion:upper() or ""
                            local is_parry = m_str:match("PARRY")
                            local is_dash = m_str:match("DASH") or m_str:match("66") or m_str:match("44") or is_drive_rush_motion(prev_step.motion)

                            if not is_mov and not is_parry and not is_dash and not m_str:match("WHIFF") then
                                prev_step.motion = prev_step.motion .. " (WHIFF)"
                                -- Update the Live Log for real-time display
                                if p_state.log and #p_state.log > 0 then
                                    local log_to_update = p_state.log[1]
                                    if log_to_update and log_to_update.id == prev_step.id then
                                        log_to_update.motion = log_to_update.motion .. " (WHIFF)"
                                    end
                                end
                            end
                        elseif (_pf.current_combo or 0) > 0 then
                            prev_step.has_hit = true
                            -- Capture CH/PC at the moment of the hit
                            if trial_state.is_recording and prev_step.counter_type == 0 then
                                pcall(function()
                                    local v_obj = _pf.victim_obj
                                    if v_obj then
                                        local pc = v_obj:get_type_definition():get_field("counter_fw_flag"):get_data(v_obj)
                                        local ch = v_obj:get_type_definition():get_field("counter_dm_flag"):get_data(v_obj)
                                        if pc == true then prev_step.counter_type = 2
                                        elseif ch == true then prev_step.counter_type = 1 end
                                    end
                                end)
                            end
                        end
    						end

                    local last_rec = trial_state.last_recorded_frame or engine_frame_count
                    local delay = 0
                    if #trial_state.sequence > 0 then delay = engine_frame_count - last_rec end
                    trial_state.last_recorded_frame = engine_frame_count

                    -- Snapshot damage for the PREVIOUS step (damage done up to now)
                    if #trial_state.sequence > 0 and trial_state._rec_gauges then
                        local rg = trial_state._rec_gauges
                        local v_hp_now = rg.min_victim_hp or rg.victim_hp
                        trial_state.sequence[#trial_state.sequence].damage_at_step = math.max(0, rg.victim_hp - v_hp_now)
                    end

                    local victim_pose = 0
                    pcall(function()
                        local v = (trial_state.recording_player == 0) and GS.p2 or GS.p1
                        if v then victim_pose = tonumber(tostring(v:get_field("pose_st"))) or 0 end
                    end)

                    table.insert(trial_state.sequence, {
                        id = act_id,
                        motion = motion_str,
                        expected_hp = process_act.current_hp,
                        is_holdable = is_holdable,
                        dual_threshold = dual_threshold,
                        charge_min = charge_min,
                        charge_max = charge_max,
                        hold_frames = 0,
                        hold_partial_check = ActionMatcher.hold_partial_check_enabled(exc),
                        expected_combo = 0,
                        actual_combo = 0,
                        has_hit = false,
                        delay_from_prev = delay,
                        facing_left = is_facing_left,
                        counter_type = 0,
                        next_auto_id = nil,
                        victim_pose = victim_pose
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
                            -- Step match by id OR normalized motion (SF6_TOOLS_CC semantics:
                            -- tolerates act_id drift between record and replay contexts)
                            local step_match = ActionMatcher.match_expected_action(expected, act_id, motion_str, real_input_str)
                            if expected and step_match.matched then
                                trial_state._step1_wrong_pending = false
                                local actual_delay = 0
                                local last_played = trial_state.last_played_frame or engine_frame_count
                                if trial_state.current_step > 1 then
                                    actual_delay = engine_frame_count -
                                        last_played
                                end
                                trial_state.last_played_frame = engine_frame_count
                                local frame_diff = actual_delay - (expected.delay_from_prev or 0)

                                -- IMMEDIATE timing display at the input frame
                                if frame_diff < 0 then
                                    trial_state.floating_info = string.format("%d frames too early", math.abs(frame_diff))
                                    trial_state.floating_color = 0xFF00FFAD -- Green-Yellow (ABGR)
                                elseif frame_diff > 0 then
                                    trial_state.floating_info = string.format("%d frames too late", frame_diff)
                                    trial_state.floating_color = 0xFF00A5FF -- Light Orange (ABGR)
                                else
                                    trial_state.floating_info = "Perfect timing"
                                    trial_state.floating_color = 0xFF00FFFF -- Pure Yellow (ABGR)
                                end

                                -- If it's a setup with no expected hit, validate the visual step immediately
                                if expected.expected_combo == 0 then
                                    trial_state.ui_visual_step = trial_state.current_step + 1
                                end

                                local prev_step_v = trial_state.current_step > 1 and trial_state.sequence[trial_state.current_step - 1] or nil
                                local combo_ok = Validator.check_combo({
                                    expected = expected,
                                    prev_step = prev_step_v,
                                    current_combo = _pf.current_combo or 0,
                                    opponent_knocked_down = _pf.opponent_knocked_down,
                                })
                                local hp_ok = Validator.check_hp(
                                    expected.expected_hp,
                                    process_act.current_hp,
                                    (prev_step_v and prev_step_v.expected_combo == 0),
                                    expected
                                )

                                if combo_ok and hp_ok then
                                    trial_step_idx = trial_state.current_step
                                    trial_state.sequence[trial_step_idx].has_hit = false
                                    trial_state.sequence[trial_step_idx].last_frame_diff = frame_diff
                                    if demo_state and demo_state.is_playing and demo_state._di_triggered
                                        and demo_state._di_step_idx and trial_step_idx == demo_state._di_step_idx + 1
                                        and (_G._demo_post_di_delay_ms or 0) == 0 then
                                        _G._demo_post_di_delay_ms = math.floor(-frame_diff * 16.67 + 0.5)
                                    end
                                    trial_state.current_step = trial_state.current_step + 1

                                    -- Apply the counter of the next step to execute
                                    -- Unless the step we just validated still needs to land as CH/PC
                                    local just_validated = trial_state.sequence[trial_state.current_step - 1]
                                    if not just_validated or just_validated.counter_type == 0 then
                                        local next_step = trial_state.sequence[trial_state.current_step]
                                        if next_step and next_step.counter_type then
                                            set_dummy_counter_type(next_step.counter_type)
                                        end
                                    end

                                    -- INIT UNIVERSAL HOLD: memorize the expected level
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
                                    elseif trial_state._hit_grace and trial_state._hit_grace > 0 then
                                        trial_state.fail_timer = 0
                                    else
                                        trial_state.fail_reason = "COMBO DROPPED"
                                    end
                                end
                            else
                                local is_parry = is_parry_action(motion_str, real_input_str, act_name)
                                local is_current_dr = is_drive_rush_id(act_id) or is_drive_rush_motion(motion_str)
                                local expecting_dr = expected and (is_drive_rush_id(expected.id) or is_drive_rush_motion(expected.motion))
                                local expecting_parry = expected and expected.motion and expected.motion:upper():match("PARRY") ~= nil
                                local is_first_step_dr = is_drive_rush_id(trial_state.sequence[1].id) or is_drive_rush_motion(trial_state.sequence[1].motion)
                                local is_first_step_parry = trial_state.sequence[1].motion and trial_state.sequence[1].motion:upper():match("PARRY") ~= nil

                                if expecting_dr and is_parry then
                                    -- Tolerance: Expecting DR, got Parry → ignore, wait for DR
                                elseif expecting_parry and is_current_dr then
                                    -- Tolerance: Expecting Parry, got DR directly → skip Parry step, validate DR on next
                                    ComboTrialsModules.PendingAbsorb.clear(trial_state, "parry_dr_skip")
                                    trial_state._step1_wrong_pending = false
                                    trial_state.last_played_frame = engine_frame_count
                                    trial_state.current_step = trial_state.current_step + 1
                                    local next_expected = trial_state.sequence[trial_state.current_step]
                                    if next_expected and (is_drive_rush_id(next_expected.id) or is_drive_rush_motion(next_expected.motion)) then
                                        trial_state.current_step = trial_state.current_step + 1
                                    end
                                elseif expecting_dr and is_current_dr then
                                    -- Tolerance: DR id mismatch (739 vs 740 vs char-specific) → validate
                                    ComboTrialsModules.PendingAbsorb.clear(trial_state, "drive_rush_tolerance")
                                    trial_state._step1_wrong_pending = false
                                    trial_state.last_played_frame = engine_frame_count
                                    trial_state.current_step = trial_state.current_step + 1
                                elseif act_id == trial_state.sequence[1].id then
                                    trial_state.fail_timer = 0
                                    trial_state.fail_reason = nil
                                    reset_trial_steps()
                                    trial_step_idx = 1
                                    trial_state.sequence[1].has_hit = false
                                    trial_state.current_step = 2
                                    trial_state.last_played_frame = engine_frame_count
                                elseif (is_first_step_dr and is_parry) or (is_first_step_parry and is_current_dr) then
                                    trial_state.fail_timer = 0
                                    trial_state.fail_reason = nil
                                    reset_trial_steps()
                                    trial_step_idx = nil
                                elseif is_current_dr then
                                    -- DR arrived early: look ahead for the DRC step and skip to after it
                                    local found_dr_step = false
                                    for look = trial_state.current_step, math.min(trial_state.current_step + 2, #trial_state.sequence) do
                                        local ls = trial_state.sequence[look]
                                        if ls and (is_drive_rush_id(ls.id) or is_drive_rush_motion(ls.motion)) then
                                            trial_state._step1_wrong_pending = false
                                            trial_state.last_played_frame = engine_frame_count
                                            trial_state.current_step = look + 1
                                            found_dr_step = true
                                            break
                                        end
                                    end
                                    if not found_dr_step then
                                        ComboTrialsModules.PendingAbsorb.clear(trial_state, "wrong_move")
                                        trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                        trial_state.fail_reason = "WRONG MOVE"
                                    end
                                else
                                    -- DELAYED/CHAINED ABSORB (SF6_TOOLS_CC): before failing,
                                    -- check absorb confirmations (e.g. Honda absorbed hits)
                                    local absorb_handled = false
                                    if expected and trial_state.current_step > 1 then
                                        local actx = build_absorb_ctx(p_idx, p_state)
                                        local frames_since_prev = engine_frame_count - (trial_state.last_played_frame or engine_frame_count)
                                        local abs_frame_diff = Validator.calculate_frame_diff(frames_since_prev, expected.delay_from_prev or 0)
                                        local recent = CharacterRules.find_recent_absorb_confirmation(
                                            p_state.exceptions, common_exceptions, expected, p_state.log, p_state.profile_name)
                                        if recent.matched then
                                            absorb_handled = ComboTrialsModules.PendingAbsorb.apply_matched_step(actx, {
                                                expected = expected,
                                                actual_action_id = recent.actual_action_id,
                                                actual_motion = recent.motion or "Unknown",
                                                actual_input = recent.real_input or "None",
                                                frame = recent.start_frame or engine_frame_count,
                                                combo_count = recent.combo_count or (_pf.current_combo or 0),
                                                actual_hp = process_act.current_hp,
                                                match_reason = recent.match_reason,
                                                match_details = recent
                                            }) and true or false
                                        else
                                            local current_absorb = CharacterRules.match_current_absorb_confirmation(
                                                p_state.exceptions, common_exceptions, expected, act_id, _pf.current_combo or 0, p_state.profile_name)
                                            if current_absorb.matched then
                                                absorb_handled = ComboTrialsModules.PendingAbsorb.apply_matched_step(actx, {
                                                    expected = expected,
                                                    actual_action_id = current_absorb.actual_action_id,
                                                    actual_motion = motion_str,
                                                    actual_input = real_input_str,
                                                    frame = engine_frame_count,
                                                    combo_count = current_absorb.combo_count or 0,
                                                    actual_hp = process_act.current_hp,
                                                    match_reason = current_absorb.match_reason,
                                                    match_details = current_absorb
                                                }) and true or false
                                            elseif current_absorb.block_reason == "combo_not_reached" then
                                                local match_probe = {
                                                    step = trial_state.current_step,
                                                    frame = engine_frame_count,
                                                    frames_since_prev_step = frames_since_prev,
                                                    expected_delay = expected.delay_from_prev,
                                                    frame_diff = abs_frame_diff,
                                                    actual_motion = motion_str,
                                                    actual_input = real_input_str,
                                                    current_combo = _pf.current_combo or 0
                                                }
                                                absorb_handled = ComboTrialsModules.PendingAbsorb.store(
                                                    actx, expected, current_absorb, match_probe, process_act.current_hp) == true
                                            end
                                        end
                                    end

                                    if not absorb_handled then
                                        if trial_state.current_step == 1 then
                                            trial_state._step1_wrong_pending = true
                                        else
                                            ComboTrialsModules.PendingAbsorb.clear(trial_state, "wrong_move")
                                            trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                            trial_state.fail_reason = "WRONG MOVE"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- CODE OK 							

            -- AUTOMATIC ACTION HANDLING AFTER A HOLD (outside is_intentional block)
            -- This must be OUTSIDE the is_intentional block because auto actions are not intentional

            -- DURING RECORDING: capture the automatic action following a holdable step
            if trial_state.is_recording and p_idx == trial_state.recording_player
                and not is_intentional and #trial_state.sequence > 0 then
                local prev_step = trial_state.sequence[#trial_state.sequence]
                if prev_step.is_holdable and prev_step.next_auto_id == nil then
                    prev_step.next_auto_id = act_id
                end
            end

            -- DURING PLAYBACK: verify the exact automatic action
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
            -- Raw input fallback for UNKNOWN automatic actions: show what was
            -- actually pressed so unmapped install-variant IDs (Sumo Spirit
            -- normals etc.) are easy to identify and except. Uses the same
            -- input-history search as intentional actions (facing-corrected
            -- direction, survives diagonals dropped at spawn frame).
            if not is_intentional and real_input_str == "None" and act_name == "Unknown" then
                local raw_match = nil
                for i = #p_state.input_history_queue, 1, -1 do
                    local entry = p_state.input_history_queue[i]
                    if (engine_frame_count - entry.frame_tick) <= 15 and (entry.mask & 0xFFF0) > 0 then
                        raw_match = entry
                        break
                    end
                end
                if raw_match then
                    local raw_btn = decode_button_mask(raw_match.mask)
                    local raw = raw_match.dir or ""
                    if raw_btn ~= "" then
                        raw = raw .. (raw ~= "" and "+" or "") .. raw_btn
                    end
                    if raw ~= "" then real_input_str = raw end
                end
            end

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
        end -- END OF "if not is_continuation" block
    end -- END OF for _, process_act
    p_state.prev_act_id = _pf.act_id
end

local function ct_player_universal_hold(p_idx, p_state)
    -- UNIVERSAL HOLD EVALUATION (EVALUATE ONLY UPON FULL BUTTON RELEASE)
    -- ========================================================
    if trial_state.is_playing and p_idx == trial_state.playing_player and trial_state.active_universal_hold then
        local uh = trial_state.active_universal_hold
        if uh.hold_mask > 0 and (_pf.direct_input & uh.hold_mask) ~= 0 then
            uh.frames = uh.frames + 1
        else
            -- Optional retrieval of perfect windows (e.g. Luke)
            local p_min, p_max = nil, nil
            local act_id_str = tostring(p_state.prev_act_id)
            local exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, act_id_str)
            if exc then p_min = exc.perfect_min; p_max = exc.perfect_max end

            local final_status = evaluate_charge_status(
                uh.profile_name, uh.frames,
                uh.charge_min, uh.charge_max,
                p_min, p_max
            )

            local hold_failed = false
            if final_status ~= uh.expected_status then
                -- If hold_partial_check == false, tolerate mismatches between intermediate levels
                -- (Instant, Partial, Charging, Lv1, Lv2...) but ALWAYS require Maxed/PERFECT/FAKE/LATE
                local hard_statuses = { Maxed = true, ["PERFECT!"] = true, FAKE = true, LATE = true }
                if uh.hold_partial_check == false
                    and not hard_statuses[final_status]
                    and not hard_statuses[uh.expected_status] then
                    -- Partial mismatch tolerated
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
end

-- =========================================================
-- MAIN ON_FRAME — ORCHESTRATOR
-- =========================================================
re.on_frame(function()
    pcall(_ct_track_live_combo)
    ct_handle_web_commands()

    -- External combo file detection (mobile imports): signature check every
    -- 300 frames, only with the remote loaded and no trial/recording active
    if _G._remote_control_loaded and _G.CurrentTrainerMode == 4
        and engine_frame_count % 300 == 87
        and not trial_state.is_playing and not trial_state.is_recording
        and not (demo_state and demo_state.is_playing) then
        pcall(function()
            if ComboTrials_Files.check_external_changes() then
                ct_ticker("COMBO LIST UPDATED (EXTERNAL)")
            end
        end)
    end

    -- Export globals for web bridge
    local _p_idx = trial_state.playing_player or 0
    local _paths = (_p_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local _display = (_p_idx == 0) and file_system.saved_combos_display_p1 or file_system.saved_combos_display_p2
    local _fidx = (_p_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    local _fname = _paths and _paths[_fidx] or ""
    _G.ComboTrials_CurrentFile = _fname:match("([^/\\]+)$") or _fname
    _G.ComboTrials_CurrentPath = _fname
    _G.ComboTrials_CurrentStep = trial_state.current_step or 0
    _G.ComboTrials_TotalSteps = trial_state.sequence and #trial_state.sequence or 0
    _G.ComboTrials_IsPlaying = trial_state.is_playing or false
    _G.ComboTrials_IsRecording = trial_state.is_recording or false
    _G.ComboTrials_IsDemo = (demo_state and demo_state.is_playing) or false
    _G.ComboTrials_FileList = _display or {}
    _G.ComboTrials_FileIdx = _fidx
    _G.ComboTrials_PositionIdx = d2d_cfg.forced_position_idx or 1

    -- BATTLE HUB SPECTATE: script disabled

    if _G.IsInBattleHub then return end

    local _in_replay = (_G.FlowMapID == 10 or _G.IsInReplay)
    ct_handle_replay_cleanup(_in_replay)

    -- Live update of flip_inputs (only before the first hit of the sequence)
    if trial_state.is_playing and trial_state.current_step == 1 then
        pcall(_ct_update_flip_live)
    end

    if _G._remote_control_loaded then
        local wf = _G._web_frame or 0
        if wf % 60 == 40 then
            pcall(function()
                local f = io.open("SF6_TrainingRemoteControl_data/Replay_WebState.json", "w")
                if not f then return end
                f:write('{"in_replay":' .. tostring(_in_replay))
                f:write(',"is_recording":' .. tostring(_in_replay and trial_state.is_recording or false))
                f:write(',"recording_player":' .. (_in_replay and trial_state.recording_player or -1))
                f:write(',"hide_ui":' .. tostring(_G._tsm_hide_ui or false) .. '}')
                f:close()
            end)
        end
        if _in_replay and wf % 60 == 45 then
            pcall(_ct_replay_bridge_poll)
        end
    end


    if _G.CurrentTrainerMode ~= 4 then ct_handle_mode_exit(); return end

    ct_handle_first_frame_init()
    _G.ComboTrials_HideNativeHUD = (trial_state.is_recording or trial_state.is_playing)

    local is_game_paused = GS.in_pause_menu
    ct_handle_pause_positions(is_game_paused, _in_replay)
    if is_game_paused then return end

    engine_frame_count = engine_frame_count + 1
    logger_process_game_state()

    if trial_state.is_recording then
        if not trial_state._rec_frame_count then trial_state._rec_frame_count = 0 end
        trial_state._rec_frame_count = trial_state._rec_frame_count + 1
        if not trial_state._piyo_detected then
            pcall(_ct_detect_piyo)
        end
        if not trial_state._di_frame and GS.p1_act_st == 11 then
            trial_state._di_frame = trial_state._rec_frame_count
        end
    end


    ct_handle_playing_transition()
    ct_handle_position_correction(_in_replay)

    local gBattle = _td_gBattle
    if not gBattle then return end
    _pf.cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not _pf.cmd_obj then return end
    if not GS.sP then return end

    ct_handle_hp_injection()

    for p_idx = 0, 1 do
        local p_state = players[p_idx]
        ct_player_init(p_idx, p_state)

        _pf.p_char = (p_idx == 0) and GS.p1 or GS.p2
        if not _pf.p_char then p_state.last_combo_count = 0; goto ct_next_player end

        local bcm_resource = _pf.cmd_obj:get_field("mpBCMResource")
        if bcm_resource then
            local p_bcm = bcm_resource[p_idx]
            local current_bcm_ptr = tostring(p_bcm)
            if current_bcm_ptr ~= p_state.last_bcm_ptr then
                p_state.last_bcm_ptr = current_bcm_ptr
                p_state.cache_built = false
            end
        end
        if not p_state.cache_built then build_bcm_cache(p_idx) end

        _pf.act_id, _pf.act_frame, _pf.flags, _pf.action_code, _pf.direct_input, _pf.b_type = get_action_data(_pf.p_char)
        _pf.current_combo = get_combo_count(_pf.p_char)
        _pf.victim_idx = 1 - p_idx
        _pf.victim_obj = (_pf.victim_idx == 0) and GS.p1 or GS.p2

        ct_player_tracking(p_idx, p_state)
        ct_player_validation(p_idx, p_state)
        ct_player_hold_charge(p_state)
        local actions_to_process = ct_player_input_buffer(p_state)
        ct_player_process_actions(p_idx, p_state, actions_to_process)
        ct_player_universal_hold(p_idx, p_state)

        p_state.last_combo_count = _pf.current_combo
        ::ct_next_player::
    end
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

                -- FINAL WHIFF DETECTION: Apply the tag on the very last recorded hit
                -- Also consider expected_combo > 0 as proof of hit (cancel/last hit)
                if not last_step.has_hit and (last_step.expected_combo or 0) == 0 then
                    local p_id = last_step.id or 0
                    local is_mov = (p_id == 17 or p_id == 18 or p_id == 36 or p_id == 37 or p_id == 38) or is_drive_rush_id(p_id)
                    local m_str = last_step.motion and last_step.motion:upper() or ""
                    local is_parry = m_str:match("PARRY")
                    local is_dash = m_str:match("DASH") or m_str:match("66") or m_str:match("44") or is_drive_rush_motion(last_step.motion)

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
            if trial_state._piyo_detected then
                trial_state.sequence[1].has_piyo = true
                trial_state.sequence[1].piyo_frame = trial_state._piyo_frame
                trial_state.sequence[1].di_frame = trial_state._di_frame
            end
        end

        -- Snapshot damage for the LAST step
        if #trial_state.sequence > 0 and trial_state._rec_gauges then
            local rg = trial_state._rec_gauges
            local v_hp_now = rg.min_victim_hp or rg.victim_hp
            trial_state.sequence[#trial_state.sequence].damage_at_step = math.max(0, rg.victim_hp - v_hp_now)
        end

        -- Calculate combo stats (damage, drive, super, hit type)
        -- Uses MIN values tracked frame-by-frame (training refills gauges)
        local init = trial_state._rec_gauges
        local stats = { hit_type = trial_state._rec_hit_type }
        if init then
            stats.damage     = math.max(0, init.victim_hp - (init.min_victim_hp or init.victim_hp))
            stats.drive_used = math.max(0, init.attacker_drive - (init.min_atk_drive or init.attacker_drive))
            stats.super_used = math.max(0, init.attacker_super - (init.min_atk_super or init.attacker_super))
        end
        trial_state.sequence[1].combo_stats = stats
        if (trial_state.sequence[1].counter_type == nil or trial_state.sequence[1].counter_type == 0) and stats.hit_type then
            local ct = 0
            if stats.hit_type == "PC" then ct = 2 elseif stats.hit_type == "CH" then ct = 1 end
            if ct ~= 0 then trial_state.sequence[1].counter_type = ct end
        end
        if logger_state.last_export_name then
            trial_state.sequence[1].raw_input_file = logger_state.last_export_name
        end
        trial_state._rec_gauges = nil
        trial_state._rec_hit_type = nil
    end

    local meta = build_auto_xt_meta(trial_state.sequence)
    if type(trial_state.sequence[1]) == "table" then
        trial_state.sequence[1]._xt_meta = meta
        if trial_state._raw_rec_buffer and #trial_state._raw_rec_buffer > 0 then
            trial_state.sequence[1].raw_inputs = trial_state._raw_rec_buffer
        end
        -- Unique resources snapshot (SF6_TOOLS_CC-compatible scene_state)
        local scene_state = trial_state._rec_scene_state
        if scene_state then
            trial_state.sequence[1].scene_state = scene_state
        end
        trial_state._rec_scene_state = nil
        -- Configured dummy behavior (menu intent; victim_pose stays as live fallback)
        if trial_state._rec_dummy_action ~= nil then
            trial_state.sequence[1].dummy_action_type = trial_state._rec_dummy_action
            trial_state.sequence[1].dummy_jump_type = trial_state._rec_dummy_jump or 0
        end
        trial_state._rec_dummy_action = nil
        trial_state._rec_dummy_jump = nil
    end
    trial_state._raw_rec_active = false
    trial_state._raw_rec_buffer = {}

    if fs.create_dir then
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos"); pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/" .. char_name)
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
    -- Ignore DRC steps (motion contains "DRC"/"DR"/"DRIVE RUSH") which temporarily drop combo count
    local has_oki = false
    local saw_combo = false
    local combo_dropped = false
    for _, step in ipairs(trial_state.sequence) do
        local ec = step.expected_combo or 0
        if ec > 0 then
            saw_combo = true
            combo_dropped = false
        end
        if saw_combo and ec == 0 and not is_drive_rush_motion(step.motion) then
            combo_dropped = true
        end
        if combo_dropped and step.has_hit then has_oki = true; break end
    end

    local has_stun = trial_state.sequence[1] and trial_state.sequence[1].has_piyo
    local type_tag = has_stun and "_STUN" or (has_oki and "_OKI" or "_COMBO")
    local starter_motion = get_safe_filename_motion(trial_state.sequence)
    local title_suffix = ""
    local meta_title = type(meta) == "table" and meta.title or nil
    if trim_string(meta_title) ~= "" then
        local safe_title = sanitize_ascii_filename_part(meta_title, 32)
        if safe_title ~= "" then title_suffix = "_" .. safe_title end
    end
    local base_name = char_name .. type_tag .. "_" .. starter_motion .. "_" .. dmg .. "_D" .. drive_bars .. "_SA" .. sa_bars .. title_suffix
    local fname = base_name .. ".json"
    local path = "TrainingComboTrials_data/CustomCombos/" .. char_name .. "/" .. fname

    -- Avoid overwriting: append timestamp if file exists
    local existing = json.load_file(path)
    if existing then
        local ts = os.date("%Y%m%d_%H%M%S")
        fname = base_name .. "_" .. ts .. ".json"
        path = "TrainingComboTrials_data/CustomCombos/" .. char_name .. "/" .. fname
    end

    assign_groups(trial_state.sequence)
    json.dump_file(path, trial_state.sequence)
    file_system._pending_select_path = path
    refresh_combo_list(rec_p)

    local paths = rec_p == 0 and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local saved_fname = fname
    for idx, combo_path in ipairs(paths) do
        local list_fname = combo_path:match("([^/\\]+)$") or combo_path
        if list_fname == saved_fname then
            if rec_p == 0 then
                file_system.selected_file_idx_p1 = idx
            else
                file_system.selected_file_idx_p2 = idx
            end
            break
        end
    end
    file_system._pending_select_path = nil
    load_combo_from_file(path, true)

    _G.ComboTrials_LastSavedFilename = fname
    return path
end

-- =========================================================
-- MODULE UI (extracted to func/ComboTrials_UI.lua)
-- =========================================================
-- Add references to shared context for the UI module
ctx.file_system = file_system
ctx.common_exceptions = common_exceptions
ctx.load_and_start_trial = load_and_start_trial
ctx.start_recording = start_recording
ctx.stop_recording_and_save = stop_recording_and_save
ctx.cancel_recording = cancel_recording
ctx.refresh_combo_list = refresh_combo_list
ctx.restore_trial_vital = restore_trial_vital
ctx.save_d2d_config = save_d2d_config
ctx.xt_settings = xt_settings
ctx.save_xt_settings = function(author)
    if type(author) == "string" and trim_string(author) ~= "" then
        xt_settings.default_author = trim_string(author)
    end
    if fs and fs.create_dir then pcall(fs.create_dir, "TrainingComboTrials_data") end
    json.dump_file(XT_SETTINGS_FILE, xt_settings)
end
ctx.get_exc_filename = get_exc_filename
ctx.ui_state = ui_state
ctx.apply_forced_position = apply_forced_position
ctx.dump_last_fail = function()
    if not trial_state.last_fail_dump then return nil end
    local char_name = players[trial_state.playing_player].profile_name or "Unknown"
    local ts = os.date("%Y%m%d_%H%M%S")
    local fname = char_name .. "_FAIL_" .. ts .. ".json"
    
    if fs.create_dir then 
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos")
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/Fails") 
    end
    
    local path = "TrainingComboTrials_data/CustomCombos/Fails/" .. fname
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
        
        -- Memory purge so non-raw display truly disappears
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
    local has_raw = trial_state.sequence[1] and trial_state.sequence[1].raw_inputs
    if trial_state.sequence[1] and trial_state.sequence[1].has_piyo and not has_raw then return end

    -- Demo drives the same validation pipeline: taint the attempt so a
    -- demo-driven finish never counts as a completed trial
    trial_state._attempt_had_demo = true

    -- RAW INPUTS (native-like playback) — preferred
    local raw_inputs = trial_state.sequence[1].raw_inputs

    -- LEGACY FALLBACK: parse timeline if no raw_inputs
    if not raw_inputs then
        local timeline = trial_state.sequence[1].timeline
        if not timeline then
            local raw_file = trial_state.sequence[1].raw_input_file
            if not raw_file then print("[ComboTrials] No raw_inputs, timeline or raw_input_file!"); return end
            local loaded = json.load_file("TrainingComboTrials_data/ReplayRecords/" .. raw_file)
            if not loaded or not loaded.timeline then print("[ComboTrials] Failed to load ReplayRecord"); return end
            timeline = loaded.timeline
        end
        demo_state.sequence = {}
        for _, line in ipairs(timeline) do
            local parsed = parse_timeline_line(line)
            if parsed then table.insert(demo_state.sequence, parsed) end
        end
        if #demo_state.sequence == 0 then return end
        demo_state.raw_buffer = nil
    else
        demo_state.raw_buffer = raw_inputs
        demo_state.sequence = {}
    end

    -- Force Trial mode to stay active on P1
    trial_state.is_recording = false
    trial_state.is_playing = true
    trial_state.playing_player = 0

    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state.active_universal_hold = nil

    reset_visual_state()
    update_trial_flip_state()
    reset_trial_steps()

    demo_state.is_playing = true
    demo_state.countdown = 10
    demo_state.current_frame = 0
    demo_state.current_step = 1
    demo_state.p1_mask = 0
    demo_state.play_index = 1
    demo_state._total_frames = 0
    demo_state._di_delay_remaining = 0
    demo_state._di_step_idx = nil
    demo_state._di_triggered = false

    if trial_state.sequence then
        for si, step in ipairs(trial_state.sequence) do
            if step.motion then
                local m = step.motion:upper()
                if m == "DI" or m:find("HPHK") then
                    demo_state._di_step_idx = si
                    break
                end
            end
        end
    end

    print("[ComboTrials] DEMO Started" .. (raw_inputs and " (RAW native)" or " (LEGACY timeline)"))
end

ctx.demo_state = demo_state
ctx.stop_demo = function() demo_state.is_playing = false; _G._demo_post_di_delay_ms = 0 end
ctx.start_demo = start_demo

-- (Keep sf6_menu_state below this as before)
sf6_menu_state = { active = false, x = 0, y = 0, w = 0, h = 0 }
ctx.sf6_menu_state = sf6_menu_state


-- Command surface bound by the hotkey scope (mirrors SF6_TOOLS_CC)
local function ct_is_replay_ctx()
    return _G.IsInReplay == true or _G.IsInBattleHub == true or _G.FlowMapID == 10
end
ctx.commands = {
    record_p1 = function()
        if ct_is_replay_ctx() then _G.ComboTrials_ReplaySavePlayer = 0 end
        start_recording(0); ct_ticker("RECORDING")
    end,
    record_p2 = function()
        if ct_is_replay_ctx() then _G.ComboTrials_ReplaySavePlayer = 1 end
        start_recording(1); ct_ticker("RECORDING")
    end,
    save_recording = function()
        if not trial_state.is_recording then return end
        _G.ComboTrials_ReplaySavePlayer = trial_state.recording_player
        stop_recording_and_save(); ct_ticker("RECORDING SAVED")
    end,
    cancel_recording = function()
        if not trial_state.is_recording then return end
        _G.ComboTrials_ReplayCancelPlayer = trial_state.recording_player
        cancel_recording(); ct_ticker("RECORDING CANCELLED")
    end,
    start_trial = function()
        load_and_start_trial(0); ct_ticker("TRIAL STARTED")
    end,
    reset_trial = function()
        if demo_state and demo_state.is_playing then
            if ctx.start_demo then ctx.start_demo() end
        elseif trial_state.is_playing then
            local pi = trial_state.playing_player or 0
            local paths = (pi == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
            local idx = (pi == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
            if paths and paths[idx] then
                local loaded = json.load_file(paths[idx])
                if loaded then trial_state.sequence = loaded; assign_groups(trial_state.sequence) end
            end
            reset_trial_steps()
        end
    end,
    stop_trial = function()
        if not trial_state.is_playing and not (demo_state and demo_state.is_playing) then return end
        if demo_state then demo_state.is_playing = false end
        trial_state.is_playing = false; ct_ticker("TRIAL STOPPED")
    end,
    start_demo = function()
        if trial_state.is_recording then return end
        if ctx.start_demo then ctx.start_demo() end
    end,
    restart_demo = function()
        if not (demo_state and demo_state.is_playing) then return end
        if ctx.start_demo then ctx.start_demo() end
    end,
    quit_demo = function()
        if not (demo_state and demo_state.is_playing) then return end
        if ctx.stop_demo then ctx.stop_demo() end
    end,
    switch_position = function()
        if trial_state.is_recording then return end
        cycle_position_mode()
    end,
    open_combo_dropdown = function()
        if trial_state.is_recording then return end
        _G.ComboTrials_OpenDropdown = true
    end,
}

-- Expose live combo/trial state to the hotkey layer. All hotkey slot dispatch
-- lives in ComboTrials_Hotkeys.lua; this module only exposes state + commands.
ctx.trial_state = trial_state

ComboTrials_Hotkeys.init(ctx, TrainingHotkeys)

local ComboTrials_UI = require("func/ComboTrials_UI")
ComboTrials_UI.init(ctx)


-- ============================================================
-- SAVE STATE / LOAD STATE: sync with active trial
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


if not _G._demo_post_di_delay_ms then _G._demo_post_di_delay_ms = 0 end

local function _ct_get_field(obj, name)
    return obj:get_field(name)
end

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

    -- If Save fired and no Load followed within 5 frames -> real Save
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

    -- STOP TRIAL -> clear
    if not trial_state.is_playing and _trial_snapshot then
        clear_trial_snapshot()
    end

    -- GUARD: cancel the refresh triggered by save shortcuts when trial is active with forced position
    if trial_state.is_playing and d2d_cfg.forced_position_idx ~= 1 then
        local tm2 = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm2 then
            local ok, ts = pcall(_ct_get_field, tm2, "_TrainingState")
            local ok2, rf = pcall(_ct_get_field, tm2, "_IsReqRefresh")
            if ok and ok2 and ts == 2 and rf == true then
                pcall(function()
                    tm2:set_field("_IsReqRefresh", false)
                    tm2:set_field("_TrainingState", 1)
                end)
            end
        end
    end

   -- Delayed restore
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

-- Register with shared pl_input_sub hook (0_SharedHooks.lua)
if _G._shared_input_pre then
table.insert(_G._shared_input_pre, function(p_id, args)
    if not tick_done_this_frame and demo_state.is_playing and not demo_state.raw_buffer then
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
            local is_refreshing = false
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            if tm and tm:get_field("_IsReqRefresh") == true then is_refreshing = true end
            if trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then is_refreshing = true end

            if not is_paused and not is_refreshing then
                if demo_state.countdown and demo_state.countdown > 0 then
                    demo_state.countdown = demo_state.countdown - 1
                    demo_state.p1_mask = 0
                else
                    if demo_state._di_delay_remaining and demo_state._di_delay_remaining > 0 then
                        demo_state._di_delay_remaining = demo_state._di_delay_remaining - 1
                        demo_state.p1_mask = 0
                    else
                    local step = demo_state.sequence[demo_state.current_step]
                    if step then
                        demo_state.p1_mask = step.mask
                        demo_state.current_frame = demo_state.current_frame + 1
                        if demo_state.current_frame >= step.frames then
                            demo_state.current_step = demo_state.current_step + 1
                            demo_state.current_frame = 0
                        end
                        local _di_victim = (trial_state.playing_player == 0) and GS.p2 or GS.p1
                        local _di_victim_act = nil
                        if _di_victim and _di_victim.mpActParam and _di_victim.mpActParam.ActionPart then
                            local eng = _di_victim.mpActParam.ActionPart._Engine
                            if eng then _di_victim_act = eng:get_ActionID() end
                        end
                        if demo_state._di_step_idx and not demo_state._di_triggered
                            and trial_state.current_step > demo_state._di_step_idx
                            and _di_victim_act and (_di_victim_act == 293 or _di_victim_act == 294) then
                            demo_state._di_triggered = true
                            local delay_ms = _G._demo_post_di_delay_ms or 0
                            if delay_ms > 0 then
                                demo_state._di_delay_remaining = math.floor(delay_ms / 16.67 + 0.5)
                            elseif delay_ms < 0 then
                                local skip = math.floor(-delay_ms / 16.67 + 0.5)
                                local before_step = demo_state.current_step
                                local before_frame = demo_state.current_frame
                                for _ = 1, skip do
                                    local s = demo_state.sequence[demo_state.current_step]
                                    if not s then break end
                                    demo_state.current_frame = demo_state.current_frame + 1
                                    if demo_state.current_frame >= s.frames then
                                        demo_state.current_step = demo_state.current_step + 1
                                        demo_state.current_frame = 0
                                    end
                                end
                                _G._di_skip_debug = string.format("SKIPPED %d frames (step %d/%d -> %d/%d)", skip, before_step, before_frame, demo_state.current_step, demo_state.current_frame)
                            end
                        end
                    else
                        demo_state.current_step = 1
                        demo_state.current_frame = 0
                        demo_state.countdown = 10
                        demo_state.p1_mask = 0
                        demo_state._di_triggered = false
                        reset_trial_steps()
                    end
                    end -- di_delay
                end
            else
                demo_state.p1_mask = 0
            end
        end
        tick_done_this_frame = true
    end
end)

end
local function _ct_clear_inputs(idx)
    local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[idx]
    if p1 then p1:set_field("pl_input_new", 0); p1:set_field("pl_sw_new", 0) end
end

local function _ct_demo_inject_mask()
    local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[0]
    local final_mask = demo_state.p1_mask
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
end

if _G._shared_input_post then
table.insert(_G._shared_input_post, function(p_id, retval)
    if p_id == 0 and trial_state.is_playing and trial_state.fail_timer and trial_state.fail_timer > 0 then
        pcall(_ct_clear_inputs, trial_state.playing_player)
    end
    if p_id == 0 and _G.TrainingFuncHeld then
        pcall(_ct_clear_inputs, 0)
    end
    -- RAW RECORDING: capture P1 pl_input_new every hook call
    if p_id == trial_state.recording_player and trial_state._raw_rec_active then
        pcall(function()
            local p = (p_id == 0) and GS.p1 or GS.p2
            if p then
                local inp = p:get_field("pl_input_new")
                trial_state._raw_rec_buffer[#trial_state._raw_rec_buffer + 1] = (inp and tonumber(tostring(inp))) or 0
            end
        end)
    end
    -- RAW DEMO PLAYBACK
    if p_id == 0 and demo_state.is_playing and demo_state.raw_buffer then
        pcall(function()
            if demo_state.countdown and demo_state.countdown > 0 then
                demo_state.countdown = demo_state.countdown - 1
                return
            end
            local pm = sdk.get_managed_singleton("app.PauseManager")
            if pm then
                local b = pm:get_field("_CurrentPauseTypeBit")
                if b ~= 64 and b ~= 2112 then return end
            end
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            if tm and tm:get_field("_IsReqRefresh") == true then return end

            local idx = demo_state.play_index
            if idx > #demo_state.raw_buffer then
                demo_state.play_index = 1
                demo_state.countdown = 30
                trial_state.current_step = 1
                trial_state.ui_visual_step = 1
                trial_state._step1_wrong_pending = false
                trial_state._first_hit_landed = false
                trial_state._reset_grace = 15
                for _, item in ipairs(trial_state.sequence) do
                    item.actual_combo = 0; item.has_hit = false; item.last_frame_diff = nil
                end
                reinject_trial_vital()
                return
            end
            local p1 = GS.p1
            if not p1 then return end
            local mask = demo_state.raw_buffer[idx]
            p1:set_field("pl_input_new", mask)
            p1:set_field("pl_sw_new", mask)
            demo_state.play_index = idx + 1
        end)
    -- LEGACY DEMO FALLBACK (timeline-based, for old combos without raw_inputs)
    elseif p_id == 0 and demo_state.is_playing and demo_state.p1_mask > 0 and not demo_state.raw_buffer then
        pcall(_ct_demo_inject_mask)
    end
end)
end

