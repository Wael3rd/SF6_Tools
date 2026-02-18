local sdk = sdk
local imgui = imgui
local re = re
local json = json
local fs = fs
local os = os

-- =========================================================
-- CONFIGURATION GLOBALE
-- =========================================================
local DATA_FOLDER = "SlotManager_Data"
local REPLAY_FOLDER = "ReplayRecords" -- Dossier cible pour les Replays
local SETTINGS_FILE = "SlotManager_Data/settings.json"
local status_msg = "Ready."
local force_open_live_slots = false -- La variable qui servira de déclencheur
local current_p1_id = -1
local current_p2_id = -1
local game_tick_counter = 0
local last_processed_tick = -1
local custom_file_input = "" 
local last_saved_state = {} 
local is_first_load = true
local cached_file_list = {} 
local filtered_file_list = {}
local filtered_display_list = {}
local dropdown_selected_index = 0
local last_filtered_p2_id = -1
local save_as_input = ""
local save_as_open = false
local activate_on_load = false

-- Replay Records dropdown (Live Slots)
local cached_replay_list = {}
local filtered_replay_list = {}
local filtered_replay_display_list = {}
local slot_dropdown_indices = { [0]=0, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0, [6]=0, [7]=0 }
local slot_import_msgs = { [0]="", [1]="", [2]="", [3]="", [4]="", [5]="", [6]="", [7]="" }
local last_filtered_replay_p2_id = -1

-- Queue d'actions pour l'allocation mémoire asynchrone
local action_queue = {} 

-- Stockage des noms de fichiers pour l'import ligne par ligne
local slot_file_inputs = {
    [0]="", [1]="", [2]="", [3]="", [4]="", [5]="", [6]="", [7]=""
}

-- IDs Officiels SF6
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
    hdr_mass   = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
    hdr_logger = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
	hdr_liveSlots = { base = 0xFF4E9F5F, hover = 0xFF66B576, active = 0xFF367844 },
}

local function sm_styled_header(label, style)
    imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

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
                        is_first_load = true
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
local function refresh_file_list()
    cached_file_list = {}
    local files = fs.glob(DATA_FOLDER .. "\\\\.*json")
    if files then
        for _, filepath in ipairs(files) do
            local filename = filepath:match("^.+\\(.+)$") or filepath
            table.insert(cached_file_list, filename)
        end
    end
    table.sort(cached_file_list)
end

local function normalize_name(s)
    return s:lower():gsub("[%.%s%-]", "")
end

local function refresh_filtered_list()
    local previous_selection = custom_file_input
    filtered_file_list = {}
    filtered_display_list = {}
    dropdown_selected_index = 0
    custom_file_input = ""
    if current_p2_id == -1 then
        for _, f in ipairs(cached_file_list) do
            table.insert(filtered_file_list, f)
            table.insert(filtered_display_list, (f:gsub("%.json$", "")))
        end
    else
        local char_name = get_char_name(current_p2_id)
        local norm_char = normalize_name(char_name)
        for _, filename in ipairs(cached_file_list) do
            local norm_file = normalize_name(filename)
            if norm_file:find(norm_char, 1, true) then
                table.insert(filtered_file_list, filename)
                table.insert(filtered_display_list, (filename:gsub("%.json$", "")))
            end
        end
    end
    -- Retrouver l'index de la sélection précédente
    if previous_selection and previous_selection ~= "" then
        for i, f in ipairs(filtered_file_list) do
            if f == previous_selection then
                dropdown_selected_index = i
                custom_file_input = previous_selection
                break
            end
        end
    end
end

local function refresh_replay_list()
    cached_replay_list = {}
    local files = fs.glob(REPLAY_FOLDER .. "\\\\.*json")
    if files then
        for _, filepath in ipairs(files) do
            local filename = filepath:match("^.+\\(.+)$") or filepath
            table.insert(cached_replay_list, filename)
        end
    end
    table.sort(cached_replay_list, function(a, b) return a > b end)
end

local function refresh_filtered_replay_list()
    filtered_replay_list = {}
    filtered_replay_display_list = { "" } -- index 1 = vide (rien sélectionné)
    if current_p2_id == -1 then
        for _, f in ipairs(cached_replay_list) do
            table.insert(filtered_replay_list, f)
            table.insert(filtered_replay_display_list, (f:gsub("%.json$", "")))
        end
    else
        local char_name = get_char_name(current_p2_id)
        local norm_char = normalize_name(char_name)
        for _, filename in ipairs(cached_replay_list) do
            local norm_file = normalize_name(filename)
            if norm_file:find(norm_char, 1, true) then
                table.insert(filtered_replay_list, filename)
                table.insert(filtered_replay_display_list, (filename:gsub("%.json$", "")))
            end
        end
    end
end

-- Peupler les listes au chargement
refresh_file_list()
refresh_filtered_list()
refresh_replay_list()
refresh_filtered_replay_list()

-- =========================================================
-- SETTINGS PERSISTENCE
-- =========================================================
local function save_settings()
    json.dump_file(SETTINGS_FILE, { activate_on_load = activate_on_load })
end

local function load_settings()
    local s = json.load_file(SETTINGS_FILE)
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
            a = act_bool
        })
    end
    return state
end

local function update_saved_state_reference()
    last_saved_state = capture_current_slots_state()
end

local function check_is_dirty()
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
-- FONCTION D'IMPORT / EXPORT COMMUNE
-- =========================================================
local function apply_data_to_character(target_id, data_table, source_name, live_slot_idx)
    local use_id = target_id or current_p2_id
    local slots, err = get_slots_access(use_id)
    if not slots then return "Error: " .. tostring(err) end
    
    local missing_memory_slots = {}
    
    -- 1. VERIFICATION DE LA MEMOIRE POUR TOUS LES SLOTS
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
            
            -- Si la capacité est trop faible (ou nulle), on doit allouer
            if cap < needed then
                table.insert(missing_memory_slots, s_data.id - 1)
            end
        end
    end
    
    -- 2. SI MEMOIRE MANQUANTE -> DECLENCHER L'AUTO-ALLOCATION
    if #missing_memory_slots > 0 then
        -- On vide la queue actuelle pour prioriser cette opération
        action_queue = {}
        
        -- On ajoute une action d'allocation pour chaque slot vide
        for _, slot_idx in ipairs(missing_memory_slots) do
            table.insert(action_queue, {
                type = "ALLOC",
                slot = slot_idx,
                step = "INIT"
            })
        end
        
        -- A la toute fin, on ajoute une action pour RE-EXECUTER l'écriture des données
        table.insert(action_queue, {
            type = "WRITE_DATA",
            target_id = use_id,
            data = data_table,
            name = source_name,
            live_slot_idx = live_slot_idx
        })
        
        return "Auto-Allocating " .. #missing_memory_slots .. " slots... Please wait."
    end

    -- 3. ECRITURE DES DONNEES (Si mémoire OK)
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
            
            -- Recalcul du needed pour être sûr
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
    
    update_saved_state_reference()

    -- Si "Activate on Load" est activé, on active tous les slots valides
    if activate_on_load then
        for i=0, 7 do
            local s = slots:call("get_Item", i)
            if s and s:get_field("IsValid") then
                s:set_field("IsActive", true)
            end
        end
        update_saved_state_reference()
    end

    return "Loaded: "..source_name
end

-- =========================================================
-- IMPORT REPLAY SINGLE (LIGNE PAR LIGNE)
-- =========================================================
local function import_single_replay_slot(slot_idx, filename)
    if not filename or filename == "" then return "No filename" end
    if not filename:match("%.json$") then filename = filename .. ".json" end
    
    local fullpath = REPLAY_FOLDER .. "/" .. filename
    local data = json.load_file(fullpath)
    
    if not data then return "Load Fail: " .. fullpath end
    
    local single_slot_data = {
        {
            id = slot_idx + 1,
            timeline = data.timeline,
            weight = 1, -- Valeur par défaut
            empty = false
        }
    }
    
    return apply_data_to_character(current_p2_id, single_slot_data, filename, slot_idx)
end

-- =========================================================
-- SYSTEME D'AUTO-ALLOCATION (ACTION QUEUE - LE CERVEAU)
-- =========================================================
re.on_frame(function()
    if #action_queue > 0 then
        local action = action_queue[1]
        
        -- === TYPE: ALLOCATION DE MEMOIRE (Méthode Recorder.lua confirmée) ===
        if action.type == "ALLOC" then
            
            -- ETAPE 1: INIT (Lancer un vrai record sur le slot vide)
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

            -- ETAPE 2: WAITING (Laisser le jeu enregistrer quelques frames)
            elseif action.step == "WAITING" then
                action.timer = action.timer + 1
                if action.timer > 10 then
                    action.step = "STOP_PHASE1"
                end

            -- ETAPE 3: STOP_PHASE1 (Repasser en mode normal)
            elseif action.step == "STOP_PHASE1" then
                local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
                if mgr then
                    mgr:call("ChangeState", 4)
                end
                action.step = "STOP_PHASE2"

            -- ETAPE 4: STOP_PHASE2 (Arrêter le record, frame suivante)
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
            
        -- === TYPE: ECRITURE FINALE DES DONNEES ===
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
    json.dump_file(DATA_FOLDER.."/"..p2_name..".json", export_data)
    update_saved_state_reference()
    refresh_file_list()
    refresh_filtered_list()
    return "Saved: "..p2_name..".json"
end

local function import_json_compressed(target_id)
    local use_id = target_id or current_p2_id
    local p2_name = get_char_name(use_id)
    local filename = DATA_FOLDER.."/"..p2_name..".json"
    local data = json.load_file(filename)
    if not data then return "File not found: "..p2_name..".json" end
    return apply_data_to_character(use_id, data, p2_name..".json")
end

local function save_custom_file_text()
    local filepath = custom_file_input
    if not filepath or filepath == "" then return "Empty Path" end
    if not filepath:match("%.json$") then filepath = filepath .. ".json" end
    
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

    json.dump_file(DATA_FOLDER.."/"..filepath, export_data)
    update_saved_state_reference()
    refresh_file_list()
    refresh_filtered_list()
    return "Custom Saved: "..filepath
end

local function import_custom_file_text()
    local filepath = custom_file_input
    if not filepath or filepath == "" then return "Empty Path" end
    if not filepath:match("%.json$") then filepath = filepath .. ".json" end
    if not filepath:match("/") and not filepath:match("\\") then filepath = DATA_FOLDER.."/"..filepath end
    local data = json.load_file(filepath)
    if not data then return "Load Failed: " .. filepath end
    return apply_data_to_character(current_p2_id, data, filepath)
end

local function export_all_characters()
    local count_ok = 0
    for id, name in pairs(CHARACTER_NAMES) do
        local res = export_json_compressed(id)
        if string.find(res, "Saved") then count_ok = count_ok + 1 end
    end
    return "Mass Export Done ("..count_ok..")"
end

local function import_all_characters()
    local count_ok = 0
    for id, name in pairs(CHARACTER_NAMES) do
        local res = import_json_compressed(id)
        if string.find(res, "Loaded") then count_ok = count_ok + 1 end
    end
    return "Mass Import Done ("..count_ok..")"
end

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
    if current_p1_id ~= -1 then
        logger_state.rec_p1.char_name = CHARACTER_NAMES[current_p1_id] or ("ID_" .. tostring(current_p1_id))
    end
    if current_p2_id ~= -1 then
        logger_state.rec_p2.char_name = CHARACTER_NAMES[current_p2_id] or ("ID_" .. tostring(current_p2_id))
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
    
    json.dump_file(full_path, output)
    print("[InputLogger] Saved to " .. full_path)

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
    if game_tick_counter == last_processed_tick then
        return
    end
    last_processed_tick = game_tick_counter

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
            
            if not rec_struct.has_started then
                if d == 0 and b == 0 then
                    return 
                else
                    rec_struct.has_started = true
                end
            end
            
            logger_update_recording(rec_struct, d, b)
        end
    end

    process_player(0, logger_state.rec_p1)
    process_player(1, logger_state.rec_p2)
end

local function draw_logger_content()
        local function get_facing_text(val) return tostring(val) end

    -- === DUAL MODE (les deux enregistrent en même temps) ===
    if logger_state.dual_active then
        imgui.push_id(3)
        
        local any_started = logger_state.rec_p1.has_started or logger_state.rec_p2.has_started
        local dual_stop_label = any_started 
            and ("STOP & EXPORT " .. logger_state.rec_p1.char_name .. " (P1) & " .. logger_state.rec_p2.char_name .. " (P2)")
            or ("STOP " .. logger_state.rec_p1.char_name .. " (P1) & " .. logger_state.rec_p2.char_name .. " (P2)")
        
        if imgui.button(dual_stop_label) then
            if any_started then
                local same_char = (logger_state.rec_p1.char_name == logger_state.rec_p2.char_name)
                
                logger_state.last_export_name = nil
                logger_state.last_export_name_2 = nil
                
                if logger_state.rec_p1.has_started then
                    logger_state.last_export_name = logger_export(logger_state.rec_p1, same_char and "_P1" or nil)
                end
                if logger_state.rec_p2.has_started then
                    logger_state.last_export_name_2 = logger_export(logger_state.rec_p2, same_char and "_P2" or nil)
                end
                
                force_open_live_slots = true
            end
            
            logger_state.rec_p1.active = false
            logger_state.rec_p1.has_started = false
            logger_state.rec_p1.data = {}
            logger_state.rec_p2.active = false
            logger_state.rec_p2.has_started = false
            logger_state.rec_p2.data = {}
            logger_state.dual_active = false
        end
        
        -- Status P1
        if not logger_state.rec_p1.has_started then
            imgui.text_colored("  P1: WAITING INPUT...", 0xFF00A5FF)
        else
            local count = 0
            for _, v in ipairs(logger_state.rec_p1.data) do count = count + v.frames end
            imgui.text_colored("  P1: RECORDING... (" .. #logger_state.rec_p1.data .. " lines / " .. count .. " frames)", 0xFF0000FF)
        end
        -- Status P2
        if not logger_state.rec_p2.has_started then
            imgui.text_colored("  P2: WAITING INPUT...", 0xFF00A5FF)
        else
            local count = 0
            for _, v in ipairs(logger_state.rec_p2.data) do count = count + v.frames end
            imgui.text_colored("  P2: RECORDING... (" .. #logger_state.rec_p2.data .. " lines / " .. count .. " frames)", 0xFF0000FF)
        end
        
        imgui.pop_id()
    else
    -- === P1 UI ===
    imgui.push_id(1) 
    
    if logger_state.rec_p1.active then
        local p1_btn_label = logger_state.rec_p1.has_started 
            and ("STOP & EXPORT " .. logger_state.rec_p1.char_name) 
            or ("STOP " .. logger_state.rec_p1.char_name)
        if imgui.button(p1_btn_label) then
            if logger_state.rec_p1.has_started then
                logger_state.last_export_name = logger_export(logger_state.rec_p1)
                logger_state.last_export_name_2 = nil
                force_open_live_slots = true
            end
            logger_state.rec_p1.active = false
            logger_state.rec_p1.has_started = false
            logger_state.rec_p1.data = {}
        end
        imgui.same_line()
        
        if not logger_state.rec_p1.has_started then
            imgui.text_colored("WAITING INPUT...", 0xFF00A5FF) 
        else
            local count = 0
            for _, v in ipairs(logger_state.rec_p1.data) do count = count + v.frames end
            imgui.text_colored("RECORDING... (" .. #logger_state.rec_p1.data .. " lines / " .. count .. " frames)", 0xFF0000FF)
        end
    else
        if imgui.button("RECORD " .. logger_state.rec_p1.char_name .. " (P1)") then
            logger_state.rec_p1.data = {}
            logger_state.rec_p1.has_started = false 
            logger_state.rec_p1.active = true
        end
    end
    imgui.pop_id()

    imgui.separator()

    -- === P2 UI ===
    imgui.push_id(2)

    if logger_state.rec_p2.active then
        local p2_btn_label = logger_state.rec_p2.has_started 
            and ("STOP & EXPORT " .. logger_state.rec_p2.char_name) 
            or ("STOP " .. logger_state.rec_p2.char_name)
        if imgui.button(p2_btn_label) then
            if logger_state.rec_p2.has_started then
                logger_state.last_export_name = logger_export(logger_state.rec_p2)
                logger_state.last_export_name_2 = nil
                force_open_live_slots = true
            end
            logger_state.rec_p2.active = false
            logger_state.rec_p2.has_started = false
            logger_state.rec_p2.data = {}
        end
        imgui.same_line()
        
        if not logger_state.rec_p2.has_started then
            imgui.text_colored("WAITING INPUT...", 0xFF00A5FF)
        else
            local count = 0
            for _, v in ipairs(logger_state.rec_p2.data) do count = count + v.frames end
            imgui.text_colored("RECORDING... (" .. #logger_state.rec_p2.data .. " lines / " .. count .. " frames)", 0xFF0000FF)
        end
    else
        if imgui.button("RECORD " .. logger_state.rec_p2.char_name .. " (P2)") then
            logger_state.rec_p2.data = {}
            logger_state.rec_p2.has_started = false
            logger_state.rec_p2.active = true
        end
    end
    imgui.pop_id()

    imgui.separator()

    -- === DUAL RECORD BUTTON ===
    if not logger_state.rec_p1.active and not logger_state.rec_p2.active then
        imgui.push_id(3)
        if imgui.button("RECORD " .. logger_state.rec_p1.char_name .. " (P1) & " .. logger_state.rec_p2.char_name .. " (P2)") then
            logger_state.rec_p1.data = {}
            logger_state.rec_p1.has_started = false
            logger_state.rec_p1.active = true
            logger_state.rec_p2.data = {}
            logger_state.rec_p2.has_started = false
            logger_state.rec_p2.active = true
            logger_state.dual_active = true
            logger_state.last_export_name = nil
            logger_state.last_export_name_2 = nil
        end
        imgui.pop_id()
    end
    end -- fin du else (not dual_active)

    if logger_state.last_export_name then
        imgui.separator()
        imgui.text_colored("Last Saved File (Select & Ctrl+C):", 0xFF00FF00)
        imgui.push_item_width(350)
        imgui.input_text("##last_export_box", logger_state.last_export_name)
        imgui.pop_item_width()
        if logger_state.last_export_name_2 then
            imgui.push_item_width(350)
            imgui.input_text("##last_export_box_2", logger_state.last_export_name_2)
            imgui.pop_item_width()
        end
    end
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

                -- Auto-refresh du filtre si le perso change
                if current_p2_id ~= last_filtered_p2_id then
                    refresh_filtered_list()
                    last_filtered_p2_id = current_p2_id
                end

                if imgui.button("Refresh") then
                    refresh_file_list()
                    refresh_filtered_list()
                end

                imgui.same_line()

                -- Dropdown des fichiers filtrés par personnage (sans .json)
                imgui.push_item_width(250)
                local combo_changed, combo_idx = imgui.combo("##file_picker", dropdown_selected_index, filtered_display_list)
                if combo_changed then
                    dropdown_selected_index = combo_idx
                    if filtered_file_list[combo_idx] then
                        custom_file_input = filtered_file_list[combo_idx]
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
                    imgui.same_line()
                    imgui.text(".json")

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
            end

            -- ================= MASS OPERATIONS =================
            if sm_styled_header("--- MASS OPERATIONS ---", SM_THEME.hdr_mass) then
                if imgui.button("EXPORT ALL CHARS") then
                    local ok, res = pcall(export_all_characters)
                    status_msg = ok and res or ("Crash: "..tostring(res))
                end
                imgui.same_line()
                if imgui.button("IMPORT ALL CHARS") then
                    local ok, res = pcall(import_all_characters)
                    status_msg = ok and res or ("Crash: "..tostring(res))
                end
            end

            -- ================= INPUT LOGGER =================
            if sm_styled_header("--- REPLAY INPUT LOGGER ---", SM_THEME.hdr_logger) then
                if not logger_state.window_open then
                    if imgui.button("Open in Separate Window >>") then
                        logger_state.window_open = true
                    end
                    imgui.separator()
                    draw_logger_content()
                else
                    imgui.text_colored("Content is currently in independent window.", 0xFFFFFF00)
                    if imgui.button("Bring back here") then
                        logger_state.window_open = false
                    end
                end
            end

            -- ================= LIVE SLOTS (toujours visible) =================
			-- Si le logger a demandé l'ouverture, on force le prochain header à s'ouvrir
            if force_open_live_slots then
                imgui.set_next_item_open(true, 1) -- 1 = Condition "Appearing" ou force immediate
                force_open_live_slots = false     -- On remet à faux pour ne pas le bloquer ouvert tout le temps
            end
            if sm_styled_header("--- LIVE SLOTS ---", SM_THEME.hdr_liveSlots) then
            local slots, msg = get_slots_access()
            if slots then

                -- Auto-refresh du filtre replay si le perso change
                if current_p2_id ~= last_filtered_replay_p2_id then
                    refresh_filtered_replay_list()
                    last_filtered_replay_p2_id = current_p2_id
                end
			
			-- [ETAPE 1] On analyse l'état actuel : Est-ce que tout est activé ?
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

                    -- [ETAPE 2] On affiche LE bouton unique en fonction du résultat
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
                    -- Bouton toggle "ACTIVATE ON LOAD"
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
                    
                    -- [FIN DES BOUTONS]
                if imgui.begin_table("SlotTbl", 6, 1 << 0) then 
                    
                    imgui.table_setup_column("ID", 0, 10)
                    imgui.table_setup_column("Active", 0, 10)
                    imgui.table_setup_column("Weight", 0, 10)
                    imgui.table_setup_column("Frames", 0, 10)
                    imgui.table_setup_column("IMPORT REPLAY DATA (Folder: ReplayRecords)", 0, 180)
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

                        -- REPLAY IMPORT COLUMN (dropdown + bouton)
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
                                    slot_dropdown_indices[i] = 1 -- reset à vide
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

re.on_frame(function()
    -- Standalone Logger Window (always checked, independent of tree)
    if logger_state.window_open then
        local should_draw = imgui.begin_window("Input Logger Standalone", true, 0)
        if should_draw then
            if imgui.button("<< Re-Attach to REFramework") then
                logger_state.window_open = false
            end
            imgui.separator()
            draw_logger_content()
            imgui.end_window()
        else
            logger_state.window_open = false
        end
    end
    logger_process_game_state()
end)