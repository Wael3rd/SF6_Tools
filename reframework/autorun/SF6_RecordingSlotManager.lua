local sdk = sdk
local imgui = imgui
local re = re
local json = json
local fs = fs
local os = os
require("func/SharedHooks") -- error registry (_G.safe_load_json)
local GS = require("func/GameState")

-- =========================================================
-- GLOBAL CONFIGURATION
-- =========================================================
local DATA_FOLDER = "SF6_RecordingSlotManager_data"
local COMBOS_BASE = "TrainingComboTrials_data\\\\CustomCombos"
local CONFIG_FILE = "SF6_RecordingSlotManager_data/config.json"
local status_msg = "Ready."
local force_open_live_slots = false -- Trigger variable to force-open the Live Slots header
local current_p1_id = -1
local current_p2_id = -1
local game_tick_counter = 0
local last_processed_tick = -1
local custom_file_input = ""
local loaded_file_name = ""
local last_saved_state = {}
local is_first_load = true
local cached_file_list = {} 
local filtered_file_list = {}
local filtered_display_list = {}
local dropdown_selected_index = 1
local last_filtered_p2_id = -1
local save_as_input = ""
local loaded_file_cfg = {
    enabled = true,
    x_pct = 0.193,
    y_pct = 0.197,
}
local save_as_open = false
local activate_on_load = false

-- Mass export confirmation
local mass_export_confirm = false
local mass_export_hold_start = nil
local MASS_EXPORT_HOLD_DURATION = 1.0

-- Replay Records dropdown (Live Slots)
local cached_replay_list = {}
local filtered_replay_list = {}
local filtered_replay_display_list = {}
local slot_dropdown_indices = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0, [7]=0 }
local slot_import_msgs = { [0]="", [1]="", [2]="", [3]="", [4]="", [5]="", [6]="", [7]="" }
local last_filtered_replay_p2_id = -1

-- Action queue for async memory allocation
local action_queue = {} 

-- Per-slot filename storage for line-by-line import
local slot_file_inputs = {
    [0]="", [1]="", [2]="", [3]="", [4]="", [5]="", [6]="", [7]=""
}

-- Custom slot names
local slot_names = { [0]="", [1]="", [2]="", [3]="", [4]="", [5]="", [6]="", [7]="" }
local slot_name_bufs = { [0]="", [1]="", [2]="", [3]="", [4]="", [5]="", [6]="", [7]="" }

-- D2D Overlay
local d2d = d2d
local overlay_cfg = {
    font_size_pct = 0.021,
    text_color = 0xFFC9C7C7,
    bg_color = 0x00000000,
    base_x_pct = 0.325,
    base_y_pct = 0.257,
    step_y_pct = 0.0555,
    box_w_pct = 0.155,
    box_h_pct = 0.041,
    text_offset_y = -0.005,
}
local show_slot_overlay = false
local show_reversal_overlay = false
local show_rev_picker_overlay = false
local reversal_slot_map = {}
local gui_has_ui11265 = false
local gui_has_picker = false

local reversal_cfg = {
    base_x_pct = 0.288,
    base_y_pct = 0.201,
    step_y_pct = 0.0555,
    box_w_pct = 0.155,
    box_h_pct = 0.041,
    text_offset_y = -0.005,
}

local rev_picker_cfg = {
    base_x_pct = 0.2,
    base_y_pct = 0.146,
    step_y_pct = 0.0555,
    box_w_pct = 0.155,
    box_h_pct = 0.041,
    text_offset_y = -0.005,
}

-- Input Sequencer
local _td_gBattle = sdk.find_type_definition("gBattle")

local SEQ_NUMPAD_DIR = {
    ["5"] = 0,
    ["8"] = 1, ["2"] = 2, ["4"] = 4, ["6"] = 8,
    ["7"] = 5, ["1"] = 6, ["9"] = 9, ["3"] = 10,
}
local SEQ_BTN = {
    ["LP"] = 16,  ["MP"] = 32,  ["HP"] = 64,
    ["LK"] = 128, ["MK"] = 256, ["HK"] = 512,
    ["P"]  = 16 | 32 | 64,   ["PP"] = 16 | 32 | 64,
    ["K"]  = 128 | 256 | 512, ["KK"] = 128 | 256 | 512,
    ["LPMK"] = 16 | 256, ["DI"] = 16 | 128, ["THROW"] = 16 | 128,
}

local function seq_parse_input(token)
    token = token:upper():gsub("%s", "")
    local dir_mask, btn_mask = 0, 0
    local dir_part, remainder = token:match("^(%d+)(.*)")
    if dir_part then
        dir_mask = SEQ_NUMPAD_DIR[dir_part:sub(-1)] or 0
    else
        remainder = token
    end
    if remainder and remainder ~= "" then
        for b in remainder:gmatch("[^+]+") do
            btn_mask = btn_mask | (SEQ_BTN[b] or 0)
        end
    end
    return dir_mask, btn_mask
end

local seq_state = {
    lines = {},
    is_playing = false,
    current_idx = 0,
    frame_counter = 0,
    sub_idx = 1,
    waiting = false,
    loop = false,
    player_id = 0,
    new_input = "5",
    new_frames = "1",
    _dbg_act_st = "?",
}

local function seq_add_input(input, frames, wait)
    input = input:upper()
    frames = math.max(1, tonumber(frames) or 1)
    local d, b = seq_parse_input(input)
    table.insert(seq_state.lines, { input = input, frames = frames, dir_mask = d, btn_mask = b, wait = wait or false })
end

local _seq_bridge_ts = 0

-- Official SF6 Character IDs
local CHARACTER_NAMES = {
    [1] = "Ryu",        [2] = "Luke",       [3] = "Kimberly",   [4] = "Chun-Li",
    [5] = "Manon",      [6] = "Zangief",    [7] = "JP",         [8] = "Dhalsim",
    [9] = "Cammy",      [10] = "Ken",       [11] = "Dee Jay",   [12] = "Lily",
    [13] = "A.K.I",    [14] = "Rashid",     [15] = "Blanka",    [16] = "Juri",
    [17] = "Marisa",    [18] = "Guile",     [19] = "Ed",        [20] = "E. Honda",
    [21] = "Jamie",     [22] = "Akuma",     [23] = "M. Bison",  [24] = "Terry",
    [25] = "Sagat",     [26] = "M. Bison",
    [27] = "Terry",     [28] = "Mai",       [29] = "Elena",     [30] = "Viper"
}

-- =========================================================
-- UI THEME & HELPERS
-- =========================================================
local SM_THEME = {
    hdr_solo   = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_logger = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
	hdr_liveSlots = { base = 0xFF4E9F5F, hover = 0xFF66B576, active = 0xFF367844 },
    hdr_sequencer = { base = 0xFF5B7FC7, hover = 0xFF7394D6, active = 0xFF4568AF },
    hdr_help = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
}

local function sm_styled_header(label, style)
    imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

local refresh_file_list
local refresh_filtered_list
local refresh_replay_list
local refresh_filtered_replay_list

-- =========================================================
-- UTILS & MEMORY
-- =========================================================
local t_mediator = sdk.find_type_definition("app.FBattleMediator")
if t_mediator then
    local m_update = t_mediator:get_method("UpdateGameInfo")
    if m_update then
        sdk.hook(m_update, function(args)
            game_tick_counter = game_tick_counter + 1

            local mediator = sdk.to_managed_object(args[2])
            if not mediator then return end
            local arr = mediator:get_field("PlayerType")
            if arr then
                local len = arr:call("get_Length")
                if len >= 1 then
                    local p1 = arr:call("GetValue", 0)
                    current_p1_id = (p1 and p1:get_field("value__")) or -1
                end
                if len >= 2 then
                    local p2 = arr:call("GetValue", 1)
                    local new_id = (p2 and p2:get_field("value__")) or -1
                    if new_id ~= current_p2_id then
                        current_p2_id = new_id
                        _G._rsm_p2_id = new_id
                        is_first_load = true
                        for k=0,7 do slot_names[k] = ""; slot_name_bufs[k] = "" end
                        custom_file_input = ""
                        loaded_file_name = ""
                        dropdown_selected_index = 1
                        if refresh_file_list then refresh_file_list() end
                        if refresh_filtered_list then refresh_filtered_list() end
                        if refresh_replay_list then refresh_replay_list() end
                        if refresh_filtered_replay_list then refresh_filtered_replay_list() end
                        status_msg = "Char selected : " .. (CHARACTER_NAMES[new_id] or ("Unknown("..tostring(new_id)..")"))
                    end
                end
            end
        end, function(retval) return retval end)
    end
end

local function get_char_name(id)
    return CHARACTER_NAMES[id] or ("Unknown("..tostring(id)..")")
end

local function get_slots_access(target_id)
    local use_id = target_id or current_p2_id
    if use_id == -1 then return nil, "Unknown Character ID" end

    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return nil, "No TrainingManager" end
    local rec_func = mgr:call("get_RecordFunc")
    if not rec_func then return nil, "No RecFunc" end
    
    local fighter_list = rec_func:get_field("_tData"):get_field("RecordSetting"):get_field("FighterDataList")
    if not fighter_list then return nil, "No Fighter List" end

    local dummy_data = fighter_list:call("get_Item", use_id)
    if not dummy_data then return nil, "Data not found for ID " .. use_id end

    return dummy_data:get_field("RecordSlots"), "OK"
end

-- =========================================================
-- FILE SYSTEM
-- =========================================================
local function normalize_name(s)
    return s:lower():gsub("[%.%s%-]", "")
end

local function get_char_folder(char_name)
    return DATA_FOLDER .. "/" .. char_name
end

local function migrate_legacy_files()
    local cfg = _G.safe_load_json(CONFIG_FILE) or {}
    if cfg.migration_done then return end
    local all_char_names = {}
    for _, name in pairs(CHARACTER_NAMES) do all_char_names[name] = true end
    local files = fs.glob(DATA_FOLDER .. "\\\\.*json")
    if not files then return end
    local count = 0
    for _, filepath in ipairs(files) do
        local filename = filepath:match("^.+\\(.+)$") or filepath
        if filename == "overlay_config.json" or filename == "settings.json" or filename == "migration_done.json" then goto continue end
        local matched_char = nil
        for char_name, _ in pairs(all_char_names) do
            local norm_char = normalize_name(char_name)
            local norm_file = normalize_name(filename)
            if norm_file:find(norm_char, 1, true) then
                matched_char = char_name
                break
            end
        end
        if matched_char then
            local src = DATA_FOLDER .. "/" .. filename
            local dst_folder = get_char_folder(matched_char)
            local dst_name = filename
            if normalize_name(filename) == normalize_name(matched_char .. ".json") then
                dst_name = matched_char .. "_Base.json"
            end
            local data = json.load_file(src)
            if data then
                json.dump_file(dst_folder .. "/" .. dst_name, data)
                count = count + 1
            end
        end
        ::continue::
    end
    cfg.migration_done = true
    cfg.migrated_count = count
    json.dump_file(CONFIG_FILE, cfg)
end

refresh_file_list = function()
    cached_file_list = {}
    if current_p2_id == -1 then return end
    local char_name = get_char_name(current_p2_id)
    local folder = DATA_FOLDER .. "\\\\" .. char_name .. "\\\\.*json"
    local files = fs.glob(folder)
    if files then
        for _, filepath in ipairs(files) do
            local filename = filepath:match("^.+\\(.+)$") or filepath
            table.insert(cached_file_list, filename)
        end
    end
    table.sort(cached_file_list)
end

local function get_display_name(filename)
    local name = filename:gsub("%.json$", "")
    return name
end

refresh_filtered_list = function()
    local previous_selection = custom_file_input
    filtered_file_list = {}
    filtered_display_list = { "-- Select File --" }
    dropdown_selected_index = 1
    custom_file_input = ""
    for _, f in ipairs(cached_file_list) do
        table.insert(filtered_file_list, f)
        table.insert(filtered_display_list, get_display_name(f))
    end
    if previous_selection and previous_selection ~= "" then
        for i, f in ipairs(filtered_file_list) do
            if f == previous_selection then
                dropdown_selected_index = i + 1
                custom_file_input = previous_selection
                break
            end
        end
    end
end

refresh_replay_list = function()
    cached_replay_list = {}
    if current_p2_id == -1 then return end
    local char_name = get_char_name(current_p2_id)
    local folder = COMBOS_BASE .. "\\\\" .. char_name .. "\\\\.*json"
    local files = fs.glob(folder)
    if files then
        for _, filepath in ipairs(files) do
            local filename = filepath:match("^.+\\(.+)$") or filepath
            table.insert(cached_replay_list, filename)
        end
    end
    table.sort(cached_replay_list)
end

refresh_filtered_replay_list = function()
    filtered_replay_list = {}
    filtered_replay_display_list = { "" }
    for _, f in ipairs(cached_replay_list) do
        table.insert(filtered_replay_list, f)
        table.insert(filtered_replay_display_list, (f:gsub("%.json$", "")))
    end
end

-- Migrate legacy files into per-character subfolders
migrate_legacy_files()

-- Populate lists on load
refresh_file_list()
refresh_filtered_list()
refresh_replay_list()
refresh_filtered_replay_list()

-- =========================================================
-- SETTINGS PERSISTENCE
-- =========================================================
local function save_settings()
    local cfg = json.load_file(CONFIG_FILE) or {}
    cfg.activate_on_load = activate_on_load
    json.dump_file(CONFIG_FILE, cfg)
end

local function load_settings()
    local s = _G.safe_load_json(CONFIG_FILE)
    if s then
        if s.activate_on_load ~= nil then activate_on_load = s.activate_on_load end
    end
end

load_settings()

-- =========================================================
-- DIRTY STATE LOGIC
-- =========================================================
local function capture_current_slots_state()
    local slots, _ = get_slots_access(current_p2_id)
    if not slots then return {} end
    local state = {}
    for i=0, 7 do
        local s = slots:call("get_Item", i)
        local raw_act = s:get_field("IsActive")
        local act_bool = (raw_act == true) or (raw_act == 1)
        table.insert(state, {
            f = math.floor(s:get_field("Frame") or 0),
            w = math.floor(s:get_field("Weight") or 0),
            a = act_bool,
            n = slot_names[i] or ""
        })
    end
    return state
end

local function update_saved_state_reference()
    last_saved_state = capture_current_slots_state()
end

local _rsm_force_dirty = false
local function check_is_dirty()
    if _rsm_force_dirty then return true end
    if is_first_load then
        update_saved_state_reference()
        is_first_load = false
        return false
    end
    if #last_saved_state == 0 then return false end
    local current = capture_current_slots_state()
    if #current ~= #last_saved_state then return true end
    for i=1, 8 do
        if current[i].f ~= last_saved_state[i].f then return true end
        if current[i].w ~= last_saved_state[i].w then return true end
        if current[i].a ~= last_saved_state[i].a then return true end
        if current[i].n ~= last_saved_state[i].n then return true end
    end
    return false
end

-- =========================================================
-- NUMPAD LOGIC
-- =========================================================
local MASKS = { UP=1, DOWN=2, RIGHT=4, LEFT=8, LP=16, MP=32, HP=64, LK=128, MK=256, HK=512 }

local function decode_to_numpad(val)
    local parts = {}
    local u, d, l, r = (val & MASKS.UP)~=0, (val & MASKS.DOWN)~=0, (val & MASKS.LEFT)~=0, (val & MASKS.RIGHT)~=0
    local num = 5
    if u then if l then num=7 elseif r then num=9 else num=8 end
    elseif d then if l then num=1 elseif r then num=3 else num=2 end
    else if l then num=4 elseif r then num=6 else num=5 end end
    table.insert(parts, tostring(num))
    if (val & MASKS.LP)~=0 then table.insert(parts, "LP") end
    if (val & MASKS.MP)~=0 then table.insert(parts, "MP") end
    if (val & MASKS.HP)~=0 then table.insert(parts, "HP") end
    if (val & MASKS.LK)~=0 then table.insert(parts, "LK") end
    if (val & MASKS.MK)~=0 then table.insert(parts, "MK") end
    if (val & MASKS.HK)~=0 then table.insert(parts, "HK") end
    return table.concat(parts, " + ")
end

local function encode_from_numpad(str)
    if not str then return 0 end
    local total = 0
    local dir_map = { ["1"]=MASKS.DOWN|MASKS.LEFT, ["2"]=MASKS.DOWN, ["3"]=MASKS.DOWN|MASKS.RIGHT, ["4"]=MASKS.LEFT, ["5"]=0, ["6"]=MASKS.RIGHT, ["7"]=MASKS.UP|MASKS.LEFT, ["8"]=MASKS.UP, ["9"]=MASKS.UP|MASKS.RIGHT }
    for token in string.gmatch(str, "[^%s+]+") do
        local key = token:match("^%s*(.-)%s*$")
        if dir_map[key] then total = total | dir_map[key]
        elseif MASKS[key] then total = total | MASKS[key] end
    end
    return total
end

-- =========================================================
-- SHARED IMPORT / EXPORT FUNCTION
-- =========================================================
local function apply_data_to_character(target_id, data_table, source_name, live_slot_idx)
    local use_id = target_id or current_p2_id
    local slots, err = get_slots_access(use_id)
    if not slots then return "Error: " .. tostring(err) end
    
    local missing_memory_slots = {}
    
    -- 1. VERIFY MEMORY FOR ALL SLOTS
    for _, s_data in ipairs(data_table) do
        if not s_data.empty then
            local slot = slots:call("get_Item", s_data.id - 1)
            local buffer = slot:get_field("InputData"):get_field("buff")
            
            local needed = 0
            if s_data.timeline then
                 for _, e in ipairs(s_data.timeline) do
                    local d = string.match(e, "(%d+)f")
                    if d then needed = needed + tonumber(d) end
                 end
            else needed = #s_data.inputs end
            
            local cap = buffer and buffer:call("get_Length") or 0
            
            -- If capacity is too low (or zero), we need to allocate
            if cap < needed then
                table.insert(missing_memory_slots, s_data.id - 1)
            end
        end
    end
    
    -- 2. IF MEMORY MISSING -> TRIGGER AUTO-ALLOCATION
    if #missing_memory_slots > 0 then
        -- Clear the current queue to prioritize this operation
        action_queue = {}
        
        -- Add an allocation action for each empty slot
        for _, slot_idx in ipairs(missing_memory_slots) do
            table.insert(action_queue, {
                type = "ALLOC",
                slot = slot_idx,
                step = "INIT"
            })
        end
        
        -- At the very end, add an action to RE-EXECUTE the data write
        table.insert(action_queue, {
            type = "WRITE_DATA",
            target_id = use_id,
            data = data_table,
            name = source_name,
            live_slot_idx = live_slot_idx
        })
        
        return "Auto-Allocating " .. #missing_memory_slots .. " slots... Please wait."
    end

    -- 3. WRITE DATA (if memory OK)
    local count = 0
    for _, s_data in ipairs(data_table) do
        local slot = slots:call("get_Item", s_data.id - 1)
        if s_data.weight then slot:set_field("Weight", s_data.weight) end
        
        if s_data.empty then
            slot:set_field("IsValid", false)
            slot:set_field("Frame", 0)
            slot:set_field("IsActive", false)
            slot:get_field("InputData"):set_field("Num", 0)
        else
            local input_data = slot:get_field("InputData")
            local buffer = input_data:get_field("buff")
            
            -- Recalculate needed to be safe
            local needed = 0
            if s_data.timeline then
                 for _, e in ipairs(s_data.timeline) do
                    local d = string.match(e, "(%d+)f")
                    if d then needed = needed + tonumber(d) end
                 end
            else needed = #s_data.inputs end
            
            local head = 0
            if s_data.timeline then
                for _, e in ipairs(s_data.timeline) do
                    local d_str, i_str = string.match(e, "(%d+)f : (.+)")
                    local dur = tonumber(d_str)
                    local val = sdk.create_uint16(encode_from_numpad(i_str))
                    for k=1, dur do buffer:call("SetValue", val, head); head = head + 1 end
                end
            else
                for f=1, needed do
                        local v = s_data.inputs[f]
                        local n = (type(v)=="string") and encode_from_numpad(v) or v
                        buffer:call("SetValue", sdk.create_uint16(n), f-1)
                end
            end
            
            slot:set_field("IsValid", true)
            slot:set_field("Frame", needed)
            slot:set_field("IsActive", false)
            input_data:set_field("Num", needed)
            count = count + 1
        end
    end
    
    for _, s_data in ipairs(data_table) do
        local idx = s_data.id - 1
        slot_names[idx] = s_data.name or ""
        slot_name_bufs[idx] = slot_names[idx]
    end


    update_saved_state_reference()

    -- If "Activate on Load" is enabled, activate all valid slots
    if activate_on_load then
        for i=0, 7 do
            local s = slots:call("get_Item", i)
            if s and s:get_field("IsValid") then
                s:set_field("IsActive", true)
            end
        end
        update_saved_state_reference()
    end

    local msg = "Loaded: "..source_name
    local ticker_name = source_name:match("[/\\]?([^/\\]+)$") or source_name
    ticker_name = ticker_name:gsub("%.json$", "")
    if _G.show_custom_ticker then _G.show_custom_ticker(ticker_name .. " File Loaded", 3) end
    return msg
end

-- =========================================================
-- PUBLIC API (consumed by Training Drills via _G._rsm_api)
-- =========================================================
_G._rsm_api = {
    get_file_list = function()
        if current_p2_id == -1 then return { "-- Select File --" }, {} end
        local char_name = get_char_name(current_p2_id)
        local folder = DATA_FOLDER .. "\\\\" .. char_name .. "\\\\.*json"
        local files = fs.glob(folder)
        local raw = {}
        local display = { "-- Select File --" }
        if files then
            for _, fp in ipairs(files) do
                local fn = fp:match("^.+\\(.+)$") or fp
                table.insert(raw, fn)
            end
            table.sort(raw)
            for _, fn in ipairs(raw) do
                local name = fn:gsub("%.json$", "")
                table.insert(display, name)
            end
        end
        return display, raw
    end,
    import_and_activate = function(filename)
        if current_p2_id == -1 then return "No character" end
        if not filename or filename == "" then return "No file" end
        if not filename:match("%.json$") then filename = filename .. ".json" end
        local char_name = get_char_name(current_p2_id)
        local full_path = get_char_folder(char_name) .. "/" .. filename
        local data = json.load_file(full_path)
        if not data then return "Load Failed: " .. filename end
        activate_on_load = true
        local result = apply_data_to_character(current_p2_id, data, filename)
        if result:find("^Loaded:") then
            loaded_file_name = filename:gsub("%.json$", "")
        end
        return result
    end,
    get_loaded_name = function() return loaded_file_name end,
}

-- =========================================================
-- IMPORT SINGLE REPLAY (LINE BY LINE)
-- =========================================================
local function import_single_replay_slot(slot_idx, filename)
    if not filename or filename == "" then return "No filename" end
    if not filename:match("%.json$") then filename = filename .. ".json" end

    local char_name = get_char_name(current_p2_id)
    local fullpath = "TrainingComboTrials_data/CustomCombos/" .. char_name .. "/" .. filename
    local data = json.load_file(fullpath)
    if not data then return "Load Fail: " .. filename end

    local timeline = nil
    if type(data) == "table" and data[1] and data[1].timeline then
        timeline = data[1].timeline
    elseif type(data) == "table" and data.timeline then
        timeline = data.timeline
    end
    if not timeline then return "No timeline in " .. filename end

    local display_name = filename:gsub("%.json$", "")
    local single_slot_data = {
        { id = slot_idx + 1, timeline = timeline, weight = 1, empty = false, name = display_name }
    }
    local result = apply_data_to_character(current_p2_id, single_slot_data, filename, slot_idx)
    _rsm_force_dirty = true
    return result
end

-- =========================================================
-- AUTO-ALLOCATION SYSTEM (ACTION QUEUE - THE BRAIN)
-- =========================================================
re.on_frame(function()
    if #action_queue > 0 then
        local action = action_queue[1]
        
        -- === TYPE: MEMORY ALLOCATION (Recorder.lua method confirmed) ===
        if action.type == "ALLOC" then
            
            -- STEP 1: INIT (Start a real recording on the empty slot)
            if action.step == "INIT" then
                local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
                local rec_func = mgr and mgr:call("get_RecordFunc")
                
                if rec_func then
                    rec_func:call("ChangeRecordStartSetting", 0)
                    rec_func:call("SetStartRecord", 16, action.slot)
                    rec_func:call("ReleaseDummyData")
                    rec_func:call("CopyDummyData")
                    mgr:call("ChangeState", 3)
                    rec_func:call("ForceApply")
                    
                    action.timer = 0
                    action.step = "WAITING"
                    status_msg = "Allocating Slot " .. (action.slot + 1) .. "..."
                else
                    table.remove(action_queue, 1)
                end

            -- STEP 2: WAITING (Let the game record a few frames)
            elseif action.step == "WAITING" then
                action.timer = action.timer + 1
                if action.timer > 10 then
                    action.step = "STOP_PHASE1"
                end

            -- STEP 3: STOP_PHASE1 (Switch back to normal mode)
            elseif action.step == "STOP_PHASE1" then
                local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
                if mgr then
                    mgr:call("ChangeState", 4)
                end
                action.step = "STOP_PHASE2"

            -- STEP 4: STOP_PHASE2 (Stop recording, next frame)
            elseif action.step == "STOP_PHASE2" then
                local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
                local rec_func = mgr and mgr:call("get_RecordFunc")
                
                if rec_func then
                    rec_func:call("StopRecord")
                    rec_func:call("ChangeRecordStartSetting", 1)
                    rec_func:call("ForceApply")
                end
                table.remove(action_queue, 1)
            end
            
        -- === TYPE: FINAL DATA WRITE ===
        elseif action.type == "WRITE_DATA" then
            local res
            if action.already_retried then
                -- Allocation already attempted and still insufficient: abort to avoid infinite loop
                res = "Alloc Failed: memory still insufficient after retry"
            else
                res = apply_data_to_character(action.target_id, action.data, action.name, action.live_slot_idx)
                -- If apply_data re-queued a WRITE_DATA (memory still missing), flag it as retry
                for _, queued in ipairs(action_queue) do
                    if queued.type == "WRITE_DATA" and queued.target_id == action.target_id then
                        queued.already_retried = true
                    end
                end
            end
            status_msg = res
            if action.live_slot_idx then
                slot_import_msgs[action.live_slot_idx] = res
            end
            table.remove(action_queue, 1)
        end
    end
end)


-- =========================================================
-- IMPORT / EXPORT STANDARDS
-- =========================================================
local function export_json_compressed(target_id)
    local use_id = target_id or current_p2_id
    local slots, err = get_slots_access(use_id)
    if not slots then return "Error: " .. tostring(err) end

    local export_data = {}
    local p2_name = get_char_name(use_id)

    for i=0, 7 do
        local slot = slots:call("get_Item", i)
        local frames = slot:get_field("Frame")
        local weight = slot:get_field("Weight") or 0
        local is_valid = slot:get_field("IsValid")

        local slot_entry = { id = i+1, weight = weight }
        if slot_names[i] ~= "" then slot_entry.name = slot_names[i] end
        if is_valid and frames > 0 then
            local buffer = slot:get_field("InputData"):get_field("buff")
            local sequence = {}
            local current_val = -1
            local run_length = 0
            for f=0, frames-1 do
                local val = buffer:call("GetValue", f):get_field("mValue")
                if f == 0 then current_val = val; run_length = 1
                else
                    if val == current_val then run_length = run_length + 1
                    else
                        table.insert(sequence, string.format("%df : %s", run_length, decode_to_numpad(current_val)))
                        current_val = val; run_length = 1
                    end
                end
            end
            table.insert(sequence, string.format("%df : %s", run_length, decode_to_numpad(current_val)))
            slot_entry.timeline = sequence
            slot_entry.empty = false
        else
            slot_entry.empty = true
            slot_entry.timeline = {}
        end
        table.insert(export_data, slot_entry)
    end
    local save_path = get_char_folder(p2_name) .. "/" .. p2_name .. "_Base.json"
    json.dump_file(save_path, export_data)
    update_saved_state_reference()
    _rsm_force_dirty = false
    refresh_file_list()
    refresh_filtered_list()
    local msg = "Saved: " .. p2_name .. "_Base.json"
    if _G.show_custom_ticker then _G.show_custom_ticker(p2_name .. "_Base File Saved", 3) end
    return msg
end

local function import_json_compressed(target_id)
    local use_id = target_id or current_p2_id
    local p2_name = get_char_name(use_id)
    local filename = get_char_folder(p2_name) .. "/" .. p2_name .. "_Base.json"
    local data = json.load_file(filename)
    if not data then return "File not found: " .. p2_name .. "_Base.json" end
    return apply_data_to_character(use_id, data, p2_name .. "_Base.json")
end

local function save_custom_file_text()
    local filepath = custom_file_input
    if not filepath or filepath == "" then return "Empty Path" end
    if not filepath:match("%.json$") then filepath = filepath .. ".json" end
    local char_name = get_char_name(current_p2_id)
    local norm = normalize_name(filepath)
    if not norm:find(normalize_name(char_name), 1, true) then
        filepath = char_name .. "_" .. filepath
    end

    local use_id = current_p2_id
    local slots, err = get_slots_access(use_id)
    if not slots then return "Error: " .. tostring(err) end

    local export_data = {}
    
    for i=0, 7 do
        local slot = slots:call("get_Item", i)
        local frames = slot:get_field("Frame")
        local weight = slot:get_field("Weight") or 0
        local is_valid = slot:get_field("IsValid")
        
        local slot_entry = { id = i+1, weight = weight }
        if slot_names[i] ~= "" then slot_entry.name = slot_names[i] end
        if is_valid and frames > 0 then
            local buffer = slot:get_field("InputData"):get_field("buff")
            local sequence = {}
            local current_val = -1
            local run_length = 0
            for f=0, frames-1 do
                local val = buffer:call("GetValue", f):get_field("mValue")
                if f == 0 then current_val = val; run_length = 1
                else
                    if val == current_val then run_length = run_length + 1
                    else
                        table.insert(sequence, string.format("%df : %s", run_length, decode_to_numpad(current_val)))
                        current_val = val; run_length = 1
                    end
                end
            end
            table.insert(sequence, string.format("%df : %s", run_length, decode_to_numpad(current_val)))
            slot_entry.timeline = sequence
            slot_entry.empty = false
        else
            slot_entry.empty = true
            slot_entry.timeline = {}
        end
        table.insert(export_data, slot_entry)
    end

    local char_folder = get_char_folder(get_char_name(current_p2_id))
    json.dump_file(char_folder .. "/" .. filepath, export_data)
    custom_file_input = filepath
    update_saved_state_reference()
    _rsm_force_dirty = false
    refresh_file_list()
    refresh_filtered_list()
    local msg = "Custom Saved: " .. filepath
    local ticker_name = filepath:gsub("%.json$", "")
    if _G.show_custom_ticker then _G.show_custom_ticker(ticker_name .. " File Saved", 3) end
    return msg
end

local function import_custom_file_text()
    local filepath = custom_file_input
    if not filepath or filepath == "" then return "Empty Path" end
    if not filepath:match("%.json$") then filepath = filepath .. ".json" end
    local char_name = get_char_name(current_p2_id)
    local full_path = get_char_folder(char_name) .. "/" .. filepath
    local data = json.load_file(full_path)
    if not data then return "Load Failed: " .. filepath end
    local result = apply_data_to_character(current_p2_id, data, filepath)
    if result:find("^Loaded:") then loaded_file_name = custom_file_input end
    return result
end

local function export_all_characters()
    local count_ok = 0
    for id, name in pairs(CHARACTER_NAMES) do
        local res = export_json_compressed(id)
        if string.find(res, "Saved") then count_ok = count_ok + 1 end
    end
    local msg = "Mass Export Done ("..count_ok..")"
    if _G.show_custom_ticker then _G.show_custom_ticker("Mass Export Done", 3) end
    return msg
end

-- =========================================================
-- UI DRAW (UNIFIED)
-- =========================================================
re.on_draw_ui(function()


    if imgui.tree_node("RECORDING SLOT MANAGER") then  
        
        local real_name = get_char_name(current_p2_id)
        local is_ready = (current_p2_id ~= -1)
        
        if is_ready then
            local is_dirty = check_is_dirty()

            imgui.text_colored("Character: " .. real_name, 0xFF00FFFF)

            -- ================= SOLO OPERATIONS =================
            if sm_styled_header("--- SOLO OPERATIONS ---", SM_THEME.hdr_solo) then

                -- Auto-refresh filter if the character changes
                if current_p2_id ~= last_filtered_p2_id then
                    refresh_filtered_list()
                    last_filtered_p2_id = current_p2_id
                end

                if imgui.button("Refresh") then
                    refresh_file_list()
                    refresh_filtered_list()
                end

                imgui.same_line()

                -- Dropdown of files filtered by character (without .json)
                imgui.push_item_width(250)
                local combo_changed, combo_idx = imgui.combo("##file_picker", dropdown_selected_index, filtered_display_list)
                if combo_changed then
                    dropdown_selected_index = combo_idx
                    local file_idx = combo_idx - 1
                    if file_idx >= 1 and filtered_file_list[file_idx] then
                        custom_file_input = filtered_file_list[file_idx]
                    else
                        custom_file_input = ""
                    end
                end
                imgui.pop_item_width()

                imgui.same_line()

                if imgui.button("IMPORT") then
                    if custom_file_input == "" then
                        custom_file_input = get_char_name(current_p2_id) .. ".json"
                    end
                    local ok, res = pcall(import_custom_file_text)
                    status_msg = ok and res or ("Crash: "..tostring(res))
                end

                imgui.same_line()

                if is_dirty then 
                    imgui.push_style_color(21, 0xFF00A5FF)
                    imgui.push_style_color(22, 0xFF00C0FF)
                    imgui.push_style_color(23, 0xFF0080FF)
                end

                if imgui.button("EXPORT") then
                    if custom_file_input == "" then
                        custom_file_input = get_char_name(current_p2_id) .. ".json"
                    end
                    local ok, res = pcall(save_custom_file_text)
                    status_msg = ok and res or ("Crash: "..tostring(res))
                end

                if is_dirty then 
                    imgui.pop_style_color(3)
                    if imgui.is_item_hovered() then
                        imgui.set_tooltip("Modifications not saved !")
                    end
                end

                imgui.same_line()

                if imgui.button("SAVE AS") then
                    save_as_input = get_char_name(current_p2_id)
                    save_as_open = true
                    imgui.open_popup("##save_as_popup")
                end

                if imgui.begin_popup("##save_as_popup") then
                    imgui.text("Save as:")
                    imgui.push_item_width(250)
                    local sa_changed, sa_val = imgui.input_text("##save_as_field", save_as_input)
                    if sa_changed then save_as_input = sa_val end
                    imgui.pop_item_width()

                    if imgui.button("OK") then
                        custom_file_input = save_as_input
                        if not custom_file_input:match("%.json$") then
                            custom_file_input = custom_file_input .. ".json"
                        end
                        local ok, res = pcall(save_custom_file_text)
                        status_msg = ok and res or ("Crash: "..tostring(res))
                        save_as_open = false
                        imgui.close_current_popup()
                    end
                    imgui.same_line()
                    if imgui.button("Cancel") then
                        save_as_open = false
                        imgui.close_current_popup()
                    end
                    imgui.end_popup()
                end

                imgui.same_line()

                -- EXPORT ALL CHARS (with hold confirmation)
                if not mass_export_confirm then
                    if imgui.button("EXPORT ALL CHARS") then
                        mass_export_confirm = true
                        mass_export_hold_start = nil
                    end
                else
                    imgui.text_colored("Are you sure? This will overwrite existing files.", 0xFF00FFFF)

                    -- NO button
                    imgui.push_style_color(21, 0xFF1B1BAA)
                    imgui.push_style_color(22, 0xFF3030CC)
                    imgui.push_style_color(23, 0xFF101080)
                    if imgui.button("  NO  ") then
                        mass_export_confirm = false
                        mass_export_hold_start = nil
                    end
                    imgui.pop_style_color(3)

                    imgui.same_line()

                    -- YES button (hold 1 second)
                    imgui.push_style_color(21, 0xFF1B6E1B)
                    imgui.push_style_color(22, 0xFF2A9E2A)
                    imgui.push_style_color(23, 0xFF104E10)
                    imgui.button("  YES (hold 1s)  ")
                    imgui.pop_style_color(3)

                    local is_held = imgui.is_item_active()
                    if is_held then
                        if not mass_export_hold_start then
                            mass_export_hold_start = os.clock()
                        end
                        local elapsed = os.clock() - mass_export_hold_start
                        local progress = math.min(elapsed / MASS_EXPORT_HOLD_DURATION, 1.0)

                        imgui.push_style_color(28, 0xFF2A9E2A)
                        imgui.progress_bar(progress, Vector2f.new(120, 12), "")
                        imgui.pop_style_color(1)

                        if progress >= 1.0 then
                            local ok, res = pcall(export_all_characters)
                            status_msg = ok and res or ("Crash: "..tostring(res))
                            mass_export_confirm = false
                            mass_export_hold_start = nil
                        end
                    else
                        if mass_export_hold_start then
                            mass_export_hold_start = nil
                        end
                        imgui.push_style_color(28, 0xFF444444)
                        imgui.progress_bar(0.0, Vector2f.new(120, 12), "")
                        imgui.pop_style_color(1)
                    end
                end
            end


            -- ================= LIVE SLOTS (always visible) =================
			-- If the logger requested opening, force the next header to open
            if force_open_live_slots then
                imgui.set_next_item_open(true, 1) -- 1 = Condition "Appearing" or force immediate
                force_open_live_slots = false     -- Reset to false so it doesn't stay forced open
            end
            if sm_styled_header("--- LIVE SLOTS ---", SM_THEME.hdr_liveSlots) then
            local slots, msg = get_slots_access()
            if slots then

                -- Auto-refresh replay filter if the character changes
                if current_p2_id ~= last_filtered_replay_p2_id then
                    refresh_replay_list()
                    refresh_filtered_replay_list()
                    last_filtered_replay_p2_id = current_p2_id
                end
			
			-- [STEP 1] Analyze current state: are all slots active?
                    local all_active = true
                    local has_valid_slots = false

                    for i=0, 7 do
                        local s = slots:call("get_Item", i)
                        if s and s:get_field("IsValid") then
                            has_valid_slots = true
                            local raw_act = s:get_field("IsActive")
                            local is_act = (raw_act == true) or (raw_act == 1)
                            
                            if not is_act then
                                all_active = false
                                break
                            end
                        end
                    end

                    -- [STEP 2] Display the single button based on the result
                    if has_valid_slots then
                        if all_active then
                            imgui.push_style_color(21, 0xFF4A4A99)
                            imgui.push_style_color(22, 0xFF6666CC)
                            imgui.push_style_color(23, 0xFF333366)
                            
                            if imgui.button("DEACTIVATE ALL") then
                                for i=0, 7 do
                                    local s = slots:call("get_Item", i)
                                    if s then s:set_field("IsActive", false) end
                                end
                            end
                            imgui.pop_style_color(3)
                        else
                            imgui.push_style_color(21, 0xFF4E9F5F)
                            imgui.push_style_color(22, 0xFF66B576)
                            imgui.push_style_color(23, 0xFF367844)
                            
                            if imgui.button("ACTIVATE ALL") then
                                for i=0, 7 do
                                    local s = slots:call("get_Item", i)
                                    if s and s:get_field("IsValid") then 
                                        s:set_field("IsActive", true) 
                                    end
                                end
                            end
                            imgui.pop_style_color(3)
                        end
                    else
                        imgui.text_colored("No valid slots loaded.", 0xFF888888)
                    end

                    imgui.same_line()
                    -- Toggle button "ACTIVATE ON LOAD"
                    if activate_on_load then
                        imgui.push_style_color(21, 0xFF4E9F5F)
                        imgui.push_style_color(22, 0xFF66B576)
                        imgui.push_style_color(23, 0xFF367844)
                    else
                        imgui.push_style_color(21, 0xFF444444)
                        imgui.push_style_color(22, 0xFF666666)
                        imgui.push_style_color(23, 0xFF222222)
                    end
                    if imgui.button(activate_on_load and "ACTIVATE ON LOAD [ON]" or "ACTIVATE ON LOAD [OFF]") then
                        activate_on_load = not activate_on_load
                        save_settings()
                    end
                    imgui.pop_style_color(3)

                    imgui.same_line()
                    if imgui.button("Refresh All") then
                        refresh_replay_list()
                        refresh_filtered_replay_list()
                    end


                    -- [END OF BUTTONS]
                if imgui.begin_table("SlotTbl", 7, 1 << 0) then

                    imgui.table_setup_column("ID", 0, 10)
                    imgui.table_setup_column("Name", 0, 60)
                    imgui.table_setup_column("Active", 0, 10)
                    imgui.table_setup_column("Weight", 0, 10)
                    imgui.table_setup_column("Frames", 0, 10)
                    imgui.table_setup_column("IMPORT COMBO DATA", 0, 180)
                    imgui.table_setup_column("Status", 0, 80)
                    imgui.table_headers_row()

                    for i=0, 7 do
                        local s = slots:call("get_Item", i)
                        
                        local f = math.floor(s:get_field("Frame") or 0)
                        local raw_act = s:get_field("IsActive")
                        local active = (raw_act == true) or (raw_act == 1)
                        local weight = math.floor(s:get_field("Weight") or 0)

                        imgui.table_next_row()
                        imgui.push_id(i) 
                        
                        -- ID
                        imgui.table_next_column()
                        imgui.text(tostring(i+1))

                        -- Name
                        imgui.table_next_column()
                        imgui.push_item_width(-1)
                        local n_changed, n_val = imgui.input_text("##name", slot_name_bufs[i], 32)
                        if n_changed then
                            slot_name_bufs[i] = n_val
                            slot_names[i] = n_val
                        
                        end
                        imgui.pop_item_width()

                        -- Active
                        imgui.table_next_column()
                        local c_change, c_val = imgui.checkbox("##act", active)
                        if c_change then s:set_field("IsActive", c_val) end

                        -- Weight
                        imgui.table_next_column()
                        imgui.push_item_width(60)
                        local w_change, w_val = imgui.input_text ("##w", weight)
                        if w_change then s:set_field("Weight", w_val) end
                        imgui.pop_item_width()

                        -- Frames
                        imgui.table_next_column()
                        if f > 0 then
                            imgui.text_colored(string.format("%d f", f), 0xFF00FF00)
                        else
                            imgui.text_colored("-", 0xFF666666)
                        end

                        -- REPLAY IMPORT COLUMN (dropdown + button)
                        imgui.table_next_column()
                        imgui.push_item_width(-70)
                        local rd_changed, rd_idx = imgui.combo("##rep_pick", slot_dropdown_indices[i] or 1, filtered_replay_display_list)
                        if rd_changed then
                            slot_dropdown_indices[i] = rd_idx
                        end
                        imgui.pop_item_width()
                        
                        imgui.same_line()
                        if imgui.button("IMPORT") then
                            local sel_idx = slot_dropdown_indices[i] or 1
                            if sel_idx > 1 and filtered_replay_list[sel_idx - 1] then
                                local filename = filtered_replay_list[sel_idx - 1]
                                local res = import_single_replay_slot(i, filename)
                                if string.find(res, "Loaded") or string.find(res, "Allocating") then
                                    slot_import_msgs[i] = res
                                    slot_dropdown_indices[i] = 1 -- reset to empty
                                else
                                    slot_import_msgs[i] = res
                                end
                            else
                                slot_import_msgs[i] = "No file selected"
                            end
                            status_msg = slot_import_msgs[i]
                        end

                        -- Status column (per-slot msg)
                        imgui.table_next_column()
                        if slot_import_msgs[i] ~= "" then
                            local mcol = 0xFFFFFFFF
                            if string.find(slot_import_msgs[i], "Loaded") then mcol = 0xFF00FF00 end
                            if string.find(slot_import_msgs[i], "Allocating") then mcol = 0xFFFFAA00 end
                            if string.find(slot_import_msgs[i], "Fail") or string.find(slot_import_msgs[i], "No file") then mcol = 0xFF0000FF end
                            imgui.text_colored(slot_import_msgs[i], mcol)
                        end
                        
                        imgui.pop_id()
                    end
                    imgui.end_table()
                end


            else
                imgui.text_colored("Error: "..msg, 0xFF0000FF)
            end
			end
        else
            imgui.text("Waiting for battle...")
        end



        -- ================= INPUT SEQUENCER =================
        if sm_styled_header("--- INPUT SEQUENCER ---", SM_THEME.hdr_sequencer) then
            local is_p1 = seq_state.player_id == 0
            local c1, v1 = imgui.checkbox("P1##seq_p", is_p1)
            if c1 then seq_state.player_id = v1 and 0 or 1 end
            imgui.same_line()
            local c2, v2 = imgui.checkbox("P2##seq_p2", not is_p1)
            if c2 then seq_state.player_id = v2 and 1 or 0 end
            imgui.same_line()
            local cl, vl = imgui.checkbox("Loop##seq_loop", seq_state.loop)
            if cl then seq_state.loop = vl end

            imgui.separator()

            local to_delete, to_move_up, to_move_down = nil, nil, nil
            for i, line in ipairs(seq_state.lines) do
                local highlight = seq_state.is_playing and i == seq_state.current_idx
                if highlight then imgui.text_colored("> ", 0xFF00FF00); imgui.same_line() end

                imgui.push_item_width(100)
                local ci, ni = imgui.input_text("##seq_inp_" .. i, line.input)
                if ci then
                    line.input = ni
                    line.dir_mask, line.btn_mask = seq_parse_input(ni)
                end
                imgui.pop_item_width()

                imgui.same_line()
                imgui.push_item_width(50)
                local cf, nf = imgui.input_text("f##seq_fr_" .. i, tostring(line.frames))
                if cf then line.frames = math.max(1, tonumber(nf) or 1) end
                imgui.pop_item_width()

                imgui.same_line()
                local cw, nw = imgui.checkbox("W##seq_w_" .. i, line.wait or false)
                if cw then line.wait = nw end
                imgui.same_line()
                if imgui.button("X##seq_del_" .. i) then to_delete = i end
                imgui.same_line()
                if imgui.button("^##seq_up_" .. i) then to_move_up = i end
                imgui.same_line()
                if imgui.button("v##seq_dn_" .. i) then to_move_down = i end
            end

            if to_delete then table.remove(seq_state.lines, to_delete) end
            if to_move_up and to_move_up > 1 then
                seq_state.lines[to_move_up], seq_state.lines[to_move_up - 1] = seq_state.lines[to_move_up - 1], seq_state.lines[to_move_up]
            end
            if to_move_down and to_move_down < #seq_state.lines then
                seq_state.lines[to_move_down], seq_state.lines[to_move_down + 1] = seq_state.lines[to_move_down + 1], seq_state.lines[to_move_down]
            end

            imgui.separator()

            imgui.push_item_width(100)
            local ca, na = imgui.input_text("Input##seq_new_inp", seq_state.new_input)
            if ca then seq_state.new_input = na end
            imgui.pop_item_width()
            imgui.same_line()
            imgui.push_item_width(50)
            local cb, nb = imgui.input_text("Frames##seq_new_fr", seq_state.new_frames)
            if cb then seq_state.new_frames = nb end
            imgui.pop_item_width()
            imgui.same_line()
            if imgui.button("ADD##seq_add") then
                seq_add_input(seq_state.new_input, seq_state.new_frames)
            end

            imgui.separator()

            if not seq_state.is_playing then
                if imgui.button("START##seq_start") then
                    if #seq_state.lines > 0 then
                        seq_state.is_playing = true
                        seq_state.current_idx = 1
                        seq_state.frame_counter = 0
                        seq_state.sub_idx = 1
                        seq_state.waiting = false
                    end
                end
            else
                if imgui.button("STOP##seq_stop") then
                    seq_state.is_playing = false
                    seq_state.current_idx = 0
                    seq_state.frame_counter = 0
                    seq_state.sub_idx = 1
                    seq_state.waiting = false
                end
                imgui.same_line()
                local status = "Step " .. seq_state.current_idx .. "/" .. #seq_state.lines ..
                    "  Frame " .. seq_state.frame_counter .. "/" ..
                    (seq_state.lines[seq_state.current_idx] and seq_state.lines[seq_state.current_idx].frames or 0) ..
                    "  Sub " .. seq_state.sub_idx
                if seq_state.waiting then status = status .. "  [WAITING act_st=" .. (seq_state._dbg_act_st or "?") .. "]" end
                imgui.text(status)
            end
        end

        if sm_styled_header("--- HELP ---", SM_THEME.hdr_help) then
            imgui.text_colored("SOLO OPERATIONS", 0xFF00FFFF)
            imgui.text("  IMPORT: Load slot data from a per-character JSON file.")
            imgui.text("  EXPORT: Save current slots to the default character file.")
            imgui.text("  SAVE AS: Save with a custom filename.")
            imgui.text("  EXPORT ALL CHARS: Hold 1s to mass-export all characters.")
            imgui.spacing()

            imgui.text_colored("LIVE SLOTS", 0xFF00FFFF)
            imgui.text("  Active: Enable/disable a slot for dummy playback.")
            imgui.text("  Weight: Higher = picked more often in random playback.")
            imgui.text("  Import Combo Data: Load a CustomCombo file into a slot.")
            imgui.spacing()

            imgui.text_colored("INPUT SEQUENCER", 0xFF00FFFF)
            imgui.text("  Program input sequences line by line (direction + buttons).")
            imgui.text("  Supported motions: QCF, QCB, HCF, HCB, 360, SRK.")
            imgui.text("  Frames: How many frames to hold the input.")
            imgui.text("  W (WAIT): Pause until the current action completes.")
            imgui.text("  Loop: Repeat the sequence continuously.")
        end

        imgui.separator()
        local col = 0xFFFFFFFF
        if string.find(status_msg, "Saved") or string.find(status_msg, "Loaded") or string.find(status_msg, "Valid") then col = 0xFF00FF00 end
        if string.find(status_msg, "Crash") or string.find(status_msg, "Fail") or string.find(status_msg, "Error") then col = 0xFF0000FF end
        if string.find(status_msg, "Allocating") then col = 0xFFFFAA00 end

        imgui.text("Msg: ")
        imgui.same_line()
        imgui.text_colored(status_msg, col)

        imgui.tree_pop()
    end
end)

local function _rsm_detect_overlays()
        if not GS.in_pause_menu then return end
        local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
        if not mgr then return end
        local cpd = mgr:call("get_CurrentParentData")
        if not cpd then return end
        local func_type = cpd:get_field("_FuncType")
        if func_type == 4 then show_slot_overlay = true end
        if func_type == 5 and current_p2_id >= 0 then
            if gui_has_picker then
                if gui_has_ui11265 then
                    show_rev_picker_overlay = true
                end
            else
                local rev_func = mgr:call("get_ReversalFunc")
                if not rev_func then return end
                local tdata = rev_func:get_field("_tData")
                local rev_setting = tdata:get_field("ReversalSetting")
                local rev_type = rev_setting:get_field("ReversalType")
                local fighter_list = rev_setting:get_field("FighterDataList")
                local fighter_data = fighter_list:call("get_Item", current_p2_id)
                local array_name = rev_type == 0 and "DownReversalDatas" or (rev_type == 1 and "GuardReversalDatas" or "DamageReversalDatas")
                local rev_datas = fighter_data:get_field(array_name)
                local has_any = false
                for i = 0, 9 do
                    local entry = rev_datas:call("GetValue", i)
                    if entry:get_field("Type") == 4 then
                        local skill_idx = entry:get_field("SkillIndex")
                        if skill_idx >= 0 and skill_idx <= 7 then
                            local name = slot_names[skill_idx]
                            if name and name ~= "" then
                                reversal_slot_map[i] = name
                                has_any = true
                            end
                        end
                    end
                end
                if has_any then show_reversal_overlay = true end
            end
        end
end

re.on_frame(function()

    -- Overlay detection: pause + Recording/Reversal Settings tab
    show_slot_overlay = false
    show_reversal_overlay = false
    show_rev_picker_overlay = false
    reversal_slot_map = {}
    pcall(_rsm_detect_overlays)
    gui_has_ui11265 = false
    gui_has_picker = false

end)

local picker_elements = { ui11261=true, ui11262=true, ui11263=true, ui11264=true, ui11265=true, ui11266=true }

local function _rsm_scan_gui_element(element)
    local go = element:call("get_GameObject")
    if go then
        local name = go:call("get_Name")
        if name == "ui11265" then
            gui_has_ui11265 = true
            gui_has_picker = true
        elseif picker_elements[name] then
            gui_has_picker = true
        end
    end
end

re.on_pre_gui_draw_element(function(element, context)
    if gui_has_ui11265 and gui_has_picker then return true end
    pcall(_rsm_scan_gui_element, element)
    return true
end)

-- =========================================================
-- D2D SLOT NAME OVERLAY
-- =========================================================
if d2d then
    local ov_font = nil
    local ov_last_px = 0
    local ov_shrink = {}

    local function ov_d2d_init()
        ov_font = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", 20)
        ov_last_px = 20
    end

    local function ov_draw_names(cfg, names_source, count)
        local sw, sh = d2d.surface_size()
        if not sw or sw == 0 then return end

        local px = math.floor(overlay_cfg.font_size_pct * sh)
        if px < 8 then px = 8 end
        if math.abs(px - ov_last_px) > 1 or not ov_font then
            ov_font = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", px)
            ov_last_px = px
        end
        if not ov_font then return end

        local bx = sw * cfg.base_x_pct
        local by = sh * cfg.base_y_pct
        local bw = sw * cfg.box_w_pct
        local bh = sh * cfg.box_h_pct
        local step = sh * cfg.step_y_pct

        for i = 0, count - 1 do
            local name = type(names_source) == "table" and names_source[i] or nil
            if name and name ~= "" then
                local y = by + i * step
                d2d.fill_rect(bx, y, bw, bh, overlay_cfg.bg_color)
                local tw, th = ov_font:measure(name)
                local draw_font = ov_font
                if tw > bw - 8 then
                    local ratio = (bw - 8) / tw
                    local smaller = math.floor(px * ratio)
                    if smaller < 8 then smaller = 8 end
                    if not ov_shrink[smaller] then
                        ov_shrink[smaller] = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", smaller)
                    end
                    draw_font = ov_shrink[smaller]
                    _, th = draw_font:measure(name)
                end
                local text_y = y + (bh - th) / 2 + sh * cfg.text_offset_y
                d2d.text(draw_font, name, bx + 4, text_y, overlay_cfg.text_color)
            end
        end
    end

    local function ov_d2d_draw()
        if show_slot_overlay then
            ov_draw_names(overlay_cfg, slot_names, 8)
        end
        if show_reversal_overlay then
            ov_draw_names(reversal_cfg, reversal_slot_map, 10)
        end
        if show_rev_picker_overlay then
            ov_draw_names(rev_picker_cfg, slot_names, 8)
        end
        if show_slot_overlay and loaded_file_name and loaded_file_name ~= "" then
            local sw, sh = d2d.surface_size()
            if sw and sw > 0 then
                local px = math.floor(overlay_cfg.font_size_pct * sh)
                if px < 8 then px = 8 end
                if math.abs(px - ov_last_px) > 1 or not ov_font then
                    ov_font = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", px)
                    ov_last_px = px
                end
                if ov_font then
                    local txt = loaded_file_name:gsub("%.json$", "")
                    local x = sw * loaded_file_cfg.x_pct
                    local y = sh * loaded_file_cfg.y_pct
                    d2d.text(ov_font, txt, x, y, overlay_cfg.text_color)
                end
            end
        end
    end

    d2d.register(ov_d2d_init, ov_d2d_draw)
end

-- =========================================================
-- WEB BRIDGE (Mobile App Integration)
-- =========================================================
local _rsm_web_counter = 0
local _rsm_bridge_ts = 0

pcall(function()
    local b = json.load_file("SF6_TrainingRemoteControl_data/RSM_WebBridge.json")
    if b and b._web_timestamp then _rsm_bridge_ts = b._web_timestamp end
end)

local function _rsm_collect_slot_list(slot_list)
    local slots, _ = get_slots_access(current_p2_id)
    if slots then
        for i = 0, 7 do
            local s = slots:call("get_Item", i)
            local raw_act = s:get_field("IsActive")
            table.insert(slot_list, {
                name = slot_names[i] or "",
                weight = math.floor(s:get_field("Weight") or 0),
                frames = math.floor(s:get_field("Frame") or 0),
                active = (raw_act == true) or (raw_act == 1),
                valid = s:get_field("IsValid") == true,
            })
        end
    end
end

local function _rsm_write_web_state()
        local char_name = ""
        if current_p2_id ~= -1 then char_name = get_char_name(current_p2_id) end

        local slot_list = {}
        pcall(_rsm_collect_slot_list, slot_list)

        local file_list = {}
        for _, f in ipairs(filtered_file_list or {}) do
            table.insert(file_list, f)
        end

        local combo_list = {}
        for _, f in ipairs(filtered_replay_list or {}) do
            table.insert(combo_list, f)
        end

        json.dump_file("SF6_TrainingRemoteControl_data/RSM_WebState.json", {
            char_name = char_name,
            slots = slot_list,
            files = file_list,
            combo_files = combo_list,
            selected_file = custom_file_input or "",
            status_msg = status_msg or "",
            activate_on_load = activate_on_load or false,
        })
end

local function _rsm_read_web_bridge()
        local b = json.load_file("SF6_TrainingRemoteControl_data/RSM_WebBridge.json")
        if not b then return end
        local ts = b._web_timestamp or 0
        if ts <= _rsm_bridge_ts then return end
        _rsm_bridge_ts = ts

        if b.cmd == "select_file" and b.file then
            custom_file_input = b.file
            for i, f in ipairs(filtered_file_list or {}) do
                if f == b.file then dropdown_selected_index = i + 1; break end
            end
        elseif b.cmd == "import" then
            if b.file and b.file ~= "" then
                custom_file_input = b.file
                for i, f in ipairs(filtered_file_list or {}) do
                    if f == b.file then dropdown_selected_index = i + 1; break end
                end
                status_msg = import_custom_file_text()
            else
                status_msg = import_json_compressed()
            end
        elseif b.cmd == "export" then
            if custom_file_input == "" then
                custom_file_input = get_char_name(current_p2_id) .. ".json"
            end
            status_msg = save_custom_file_text()
        elseif b.cmd == "save_as" and b.file then
            custom_file_input = b.file
            status_msg = save_custom_file_text()
        elseif b.cmd == "import_combo" and b.file and b.slot ~= nil then
            status_msg = import_single_replay_slot(b.slot, b.file)
        elseif b.cmd == "activate_all" then
            pcall(function()
                local slots, _ = get_slots_access(current_p2_id)
                if slots then
                    for i = 0, 7 do
                        local s = slots:call("get_Item", i)
                        if s:get_field("IsValid") then s:set_field("IsActive", true) end
                    end
                end
            end)
            status_msg = "All valid slots activated"
        elseif b.cmd == "deactivate_all" then
            pcall(function()
                local slots, _ = get_slots_access(current_p2_id)
                if slots then
                    for i = 0, 7 do
                        local s = slots:call("get_Item", i)
                        s:set_field("IsActive", false)
                    end
                end
            end)
            status_msg = "All slots deactivated"
        elseif b.cmd == "toggle_aol" then
            activate_on_load = not activate_on_load
            save_settings()
        elseif b.cmd == "refresh" then
            refresh_file_list()
            refresh_filtered_list()
            status_msg = "Refreshed"
        end

        if b.slot_name then
            local idx = b.slot_name.idx
            local name = b.slot_name.name or ""
            if idx >= 0 and idx <= 7 then
                slot_names[idx] = name
                slot_name_bufs[idx] = name
            end
        end

        if b.slot_weight then
            local idx = b.slot_weight.idx
            local w = b.slot_weight.weight or 1
            if idx >= 0 and idx <= 7 then
                pcall(function()
                    local slots, _ = get_slots_access(current_p2_id)
                    if slots then
                        local s = slots:call("get_Item", idx)
                        s:set_field("Weight", w)
                    end
                end)
            end
        end

        if b.slot_active then
            local idx = b.slot_active.idx
            if idx >= 0 and idx <= 7 then
                pcall(function()
                    local slots, _ = get_slots_access(current_p2_id)
                    if slots then
                        local s = slots:call("get_Item", idx)
                        local cur = s:get_field("IsActive")
                        s:set_field("IsActive", not ((cur == true) or (cur == 1)))
                    end
                end)
            end
        end

end

re.on_frame(function()
    _rsm_web_counter = _rsm_web_counter + 1
    if _rsm_web_counter < 10 then return end
    _rsm_web_counter = 0

    if current_p2_id ~= last_filtered_p2_id then
        refresh_file_list()
        refresh_filtered_list()
        refresh_replay_list()
        refresh_filtered_replay_list()
        last_filtered_p2_id = current_p2_id
    end

    pcall(_rsm_write_web_state)
    pcall(_rsm_read_web_bridge)
end)

-- =========================================================
-- INPUT SEQUENCER: WebState + WebBridge (on_frame)
-- =========================================================
local function _rsm_write_seq_state()
        local seq_lines_out = {}
        for _, l in ipairs(seq_state.lines) do
            table.insert(seq_lines_out, { input = l.input, frames = l.frames, wait = l.wait or false })
        end
        json.dump_file("SF6_TrainingRemoteControl_data/Sequencer_WebState.json", {
            seq_lines = seq_lines_out,
            seq_playing = seq_state.is_playing,
            seq_current_idx = seq_state.current_idx,
            seq_loop = seq_state.loop,
            seq_player = seq_state.player_id,
        })
end

local function _rsm_read_seq_bridge()
        local b = json.load_file("SF6_TrainingRemoteControl_data/Sequencer_WebBridge.json")
        if not b then return end
        local ts = b._web_timestamp or 0
        if ts <= _seq_bridge_ts then return end
        _seq_bridge_ts = ts

        if b.cmd == "seq_add" and b.input then
            seq_add_input(b.input, b.frames or 1)
        elseif b.cmd == "seq_delete" and b.idx ~= nil then
            local idx = b.idx + 1
            if idx >= 1 and idx <= #seq_state.lines then table.remove(seq_state.lines, idx) end
        elseif b.cmd == "seq_move" and b.idx ~= nil and b.dir then
            local idx = b.idx + 1
            if b.dir == "up" and idx > 1 then
                seq_state.lines[idx], seq_state.lines[idx - 1] = seq_state.lines[idx - 1], seq_state.lines[idx]
            elseif b.dir == "down" and idx < #seq_state.lines then
                seq_state.lines[idx], seq_state.lines[idx + 1] = seq_state.lines[idx + 1], seq_state.lines[idx]
            end
        elseif b.cmd == "seq_edit" and b.idx ~= nil then
            local idx = b.idx + 1
            if idx >= 1 and idx <= #seq_state.lines then
                if b.input then
                    seq_state.lines[idx].input = b.input:upper()
                    seq_state.lines[idx].dir_mask, seq_state.lines[idx].btn_mask = seq_parse_input(b.input)
                end
                if b.frames then seq_state.lines[idx].frames = math.max(1, tonumber(b.frames) or 1) end
                if b.wait ~= nil then seq_state.lines[idx].wait = b.wait end
            end
        elseif b.cmd == "seq_start" then
            if #seq_state.lines > 0 then
                seq_state.is_playing = true
                seq_state.current_idx = 1
                seq_state.frame_counter = 0
                seq_state.sub_idx = 1
                seq_state.waiting = false
            end
        elseif b.cmd == "seq_stop" then
            seq_state.is_playing = false
            seq_state.current_idx = 0
            seq_state.frame_counter = 0
            seq_state.sub_idx = 1
            seq_state.waiting = false
        elseif b.cmd == "seq_loop" then
            seq_state.loop = not seq_state.loop
        elseif b.cmd == "seq_player" and b.player ~= nil then
            seq_state.player_id = (b.player == 1) and 1 or 0
        elseif b.cmd == "seq_clear" then
            seq_state.lines = {}
            seq_state.is_playing = false
            seq_state.current_idx = 0
            seq_state.frame_counter = 0
            seq_state.sub_idx = 1
            seq_state.waiting = false
        end
end

local _seq_web_tick = 0
re.on_frame(function()
    _seq_web_tick = _seq_web_tick + 1
    if _seq_web_tick % 10 ~= 0 then return end

    pcall(_rsm_write_seq_state)
    pcall(_rsm_read_seq_bridge)
end)

-- =========================================================
-- INPUT SEQUENCER: injection via shared hook
-- =========================================================
local function _rsm_seq_wait_check()
    local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[seq_state.player_id]
    if not p1 then return end
    local act_st = tonumber(tostring(p1:get_type_definition():get_field("act_st"):get_data(p1))) or -1
    seq_state._dbg_act_st = act_st
    if act_st == 0 then
        seq_state.waiting = false
        seq_state.sub_idx = 1
        seq_state.current_idx = seq_state.current_idx + 1
        if seq_state.current_idx > #seq_state.lines then
            if seq_state.loop then
                seq_state.current_idx = 1
                seq_state.sub_idx = 1
            else
                seq_state.is_playing = false
                seq_state.current_idx = 0
            end
        end
    end
end

local function _rsm_seq_inject(line, dir_part, btn_part)
    local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[seq_state.player_id]
    if not p1 then return end

    local final_dir, final_btn = 0, 0
    if dir_part and #dir_part > 1 then
        local digit = dir_part:sub(seq_state.sub_idx, seq_state.sub_idx)
        final_dir = SEQ_NUMPAD_DIR[digit] or 0
        if seq_state.sub_idx == #dir_part and btn_part and btn_part ~= "" then
            for bp in btn_part:gmatch("[^+]+") do final_btn = final_btn | (SEQ_BTN[bp] or 0) end
        end
    else
        final_dir = line.dir_mask
        final_btn = line.btn_mask
    end

    if not p1:get_field("rl_dir") then
        local has_right = (final_dir & 4) ~= 0
        local has_left  = (final_dir & 8) ~= 0
        final_dir = final_dir & ~12
        if has_right then final_dir = final_dir | 8 end
        if has_left  then final_dir = final_dir | 4 end
    end

    local combined = final_dir | final_btn
    local orig_in = p1:get_field("pl_input_new") or 0
    local orig_sw = p1:get_field("pl_sw_new") or 0
    p1:set_field("pl_input_new", orig_in | combined)
    p1:set_field("pl_sw_new", orig_sw | combined)
end

if _G._shared_input_post then
    table.insert(_G._shared_input_post, function(p_id, retval)
        if not seq_state.is_playing then return end
        if p_id ~= seq_state.player_id then return end
        if seq_state.current_idx < 1 or seq_state.current_idx > #seq_state.lines then
            seq_state.is_playing = false
            seq_state.current_idx = 0
            seq_state.frame_counter = 0
            seq_state.sub_idx = 1
            seq_state.waiting = false
            return
        end

        local line = seq_state.lines[seq_state.current_idx]

        if seq_state.waiting then
            pcall(_rsm_seq_wait_check)
            return
        end

        seq_state.frame_counter = seq_state.frame_counter + 1

        local input = line.input:upper()
        local dir_part, btn_part = input:match("^(%d+)(.*)")
        local num_subs = (dir_part and #dir_part > 1) and #dir_part or 1
        if seq_state.sub_idx < 1 then seq_state.sub_idx = 1 end

        pcall(_rsm_seq_inject, line, dir_part, btn_part)

        if seq_state.frame_counter >= line.frames then
            seq_state.frame_counter = 0
            seq_state.sub_idx = seq_state.sub_idx + 1
            if seq_state.sub_idx > num_subs then
                if line.wait then
                    seq_state.waiting = true
                else
                    seq_state.sub_idx = 1
                    seq_state.current_idx = seq_state.current_idx + 1
                    if seq_state.current_idx > #seq_state.lines then
                        if seq_state.loop then
                            seq_state.current_idx = 1
                            seq_state.sub_idx = 1
                        else
                            seq_state.is_playing = false
                            seq_state.current_idx = 0
                        end
                    end
                end
            end
        end
    end)
end
