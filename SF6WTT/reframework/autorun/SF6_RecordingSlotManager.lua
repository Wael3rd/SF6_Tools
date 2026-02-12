local sdk = sdk
local imgui = imgui
local re = re
local json = json
local fs = fs

-- =========================================================
-- CONFIGURATION GLOBALE
-- =========================================================
local DATA_FOLDER = "SlotManager_Data"
local status_msg = "Ready."
local current_p2_id = -1
local custom_file_input = "FileName.json" 
local last_saved_state = {} 
local is_first_load = true
local cached_file_list = {} 

-- IDs Officiels SF6
local CHARACTER_NAMES = {
    [1] = "Ryu",        [2] = "Luke",       [3] = "Kimberly",   [4] = "Chun-Li",
    [5] = "Manon",      [6] = "Zangief",    [7] = "JP",         [8] = "Dhalsim",
    [9] = "Cammy",      [10] = "Ken",       [11] = "Dee Jay",   [12] = "Lily",
    [13] = "A.K.I.",    [14] = "Rashid",    [15] = "Blanka",    [16] = "Juri",
    [17] = "Marisa",    [18] = "Guile",     [19] = "Ed",        [20] = "E. Honda",
    [21] = "Jamie",     [22] = "Akuma",     
    [23] = "M. Bison",  [24] = "Terry",     
    [25] = "Sagat",     [26] = "M. Bison",  [27] = "Terry",     [28] = "Mai",
    [29] = "Elena",     [30] = "Viper"
}

-- =========================================================
-- UTILS & MEMORY
-- =========================================================
local t_mediator = sdk.find_type_definition("app.FBattleMediator")
if t_mediator then
    local m_update = t_mediator:get_method("UpdateGameInfo")
    if m_update then
        sdk.hook(m_update, function(args)
            local mediator = sdk.to_managed_object(args[2])
            if not mediator then return end
            local arr = mediator:get_field("PlayerType")
            if arr and arr:call("get_Length") >= 2 then
                local p2 = arr:call("GetValue", 1)
                local new_id = (p2 and p2:get_field("value__")) or -1
                if new_id ~= current_p2_id then
                    current_p2_id = new_id
                    is_first_load = true 
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
    if not mgr then return nil, "No Manager" end
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
    local files = fs.glob(DATA_FOLDER .. "\\*.json")
    if files then
        for _, filepath in ipairs(files) do
            local filename = filepath:match("^.+\\(.+)$") or filepath
            table.insert(cached_file_list, filename)
        end
    end
    table.sort(cached_file_list)
end

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
-- IMPORT / EXPORT (AVEC GESTION MEMOIRE)
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
        end
        table.insert(export_data, slot_entry)
    end
    json.dump_file(DATA_FOLDER.."/"..p2_name..".json", export_data)
    update_saved_state_reference()
    refresh_file_list()
    return "Saved: "..p2_name..".json"
end

local function apply_data_to_character(target_id, data_table, source_name)
    local use_id = target_id or current_p2_id
    local slots, err = get_slots_access(use_id)
    if not slots then return "Error accessing memory: " .. tostring(err) end
    local count = 0
    local log = ""

    for _, s_data in ipairs(data_table) do
        local slot = slots:call("get_Item", s_data.id - 1)
        if s_data.weight then slot:set_field("Weight", s_data.weight) end
        
        if s_data.empty then
            slot:set_field("IsValid", false)
            slot:set_field("Frame", 0)
            slot:set_field("IsActive", false)
            slot:get_field("InputData"):set_field("Num", 0)
        else
            -- === MEMORY CHECK ===
            local input_data = slot:get_field("InputData")
            local buffer = input_data:get_field("buff")
            
            local needed = 0
            if s_data.timeline then
                 for _, e in ipairs(s_data.timeline) do
                    local d = string.match(e, "(%d+)f")
                    if d then needed = needed + tonumber(d) end
                 end
            else needed = #s_data.inputs end

            local cap = buffer and buffer:call("get_Length") or 0
            
            if cap >= needed then
                -- WRITE DATA
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
                slot:set_field("IsActive", true)
                input_data:set_field("Num", needed)
                count = count + 1
            else
                -- FAIL GRACEFULLY
                log = log .. "\nSlot " .. s_data.id .. ": Mem Low ("..cap.."<"..needed.."). Record something in this slot first!"
            end
        end
    end
    
    update_saved_state_reference()
    if log ~= "" then return "Partial Load ("..count..")."..log else return "Loaded: "..source_name end
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
    -- Ajout extension .json si absente
    if not filepath:match("%.json$") then filepath = filepath .. ".json" end
    
    local use_id = current_p2_id
    local slots, err = get_slots_access(use_id)
    if not slots then return "Error: " .. tostring(err) end

    local export_data = {}
    
    -- Récupération des données (Copie de la logique d'export standard)
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
        end
        table.insert(export_data, slot_entry)
    end

    -- Sauvegarde brute (écrase si existe)
    json.dump_file(DATA_FOLDER.."/"..filepath, export_data)
    update_saved_state_reference()
    refresh_file_list()
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

local function import_specific_file(filename)
    local filepath = DATA_FOLDER.."/"..filename
    local data = json.load_file(filepath)
    if not data then return "Load Failed: " .. filename end
    return apply_data_to_character(current_p2_id, data, filename)
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
-- UI DRAW
-- =========================================================
re.on_draw_ui(function()
    if imgui.tree_node("Recording Slot Manager") then  
        
        local real_name = get_char_name(current_p2_id)
        local is_ready = (current_p2_id ~= -1)
        
        if is_ready then
            local is_dirty = check_is_dirty()
            
            -- ================= HEADER =================
            imgui.text_colored("Character: " .. real_name, 0xFF00FFFF)
			local upper_name = string.upper(real_name)
            
            -- ORANGE DOUX (ABGR: Alpha=FF, Blue=00, Green=A5, Red=FF)
            if is_dirty then 
                imgui.push_style_color(21, 0xFF00A5FF) -- Button Normal (Orange)
                imgui.push_style_color(22, 0xFF00C0FF) -- Hovered (Lighter)
                imgui.push_style_color(23, 0xFF0080FF) -- Active (Darker)
            end
            
		-- BOUTON DYNAMIQUE : SAVE [Nom] SLOTS
            if imgui.button("EXPORT " .. upper_name .. " SLOTS") then
                local ok, res = pcall(export_json_compressed, nil)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end
            
            if is_dirty then 
                imgui.pop_style_color(3)
                if imgui.is_item_hovered() then
                    imgui.set_tooltip("Modifications not saved !")
                end
            end

            imgui.same_line()
		-- BOUTON DYNAMIQUE : LOAD [Nom] SLOTS
            if imgui.button("IMPORT " .. upper_name .. " SLOTS") then
                local ok, res = pcall(import_json_compressed, nil)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end

            
-- SAVE CUSTOM (NOUVEAU BOUTON)
            if imgui.button("EXPORT CUSTOM SLOTS") then
                local ok, res = pcall(save_custom_file_text)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end

            imgui.same_line()

            -- CUSTOM LOAD
            if imgui.button("IMPORT CUSTOM SLOTS") then
                local ok, res = pcall(import_custom_file_text)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end

            imgui.same_line()

            imgui.push_item_width(480)
            local changed, new_val = imgui.input_text("##custom", custom_file_input)
            if changed then custom_file_input = new_val end
            imgui.pop_item_width()
            

            -- ================= MASS LOAD =================
                if imgui.button("EXPORT ALL CHARS") then
                    local ok, res = pcall(export_all_characters)
                    status_msg = ok and res or ("Crash: "..tostring(res))
                end
                imgui.same_line()
                if imgui.button("IMPORT ALL CHARS") then
                    local ok, res = pcall(import_all_characters)
                    status_msg = ok and res or ("Crash: "..tostring(res))
                end
                imgui.tree_pop()

            imgui.separator()

            -- ================= SLOTS TABLE =================
            if imgui.tree_node("Live Slots") then
                local slots, msg = get_slots_access()
                if slots then
                    if imgui.begin_table("SlotTbl", 4, 1 << 0) then 
                        
                        imgui.table_setup_column("ID", 0, 10)
                        imgui.table_setup_column("Active", 0, 10)
                        imgui.table_setup_column("Weight", 0, 10)
                        imgui.table_setup_column("Frames", 0, 10)
                        imgui.table_headers_row()

                        for i=0, 7 do
                            local s = slots:call("get_Item", i)
                            
                            local f = math.floor(s:get_field("Frame") or 0)
                            local raw_act = s:get_field("IsActive")
                            local active = (raw_act == true) or (raw_act == 1)
                            local weight = math.floor(s:get_field("Weight") or 0)

                            imgui.table_next_row()
                            
                            -- ID
                            imgui.table_next_column()
                            imgui.text(tostring(i+1))
                            
                            -- Active
                            imgui.table_next_column()
                            local c_change, c_val = imgui.checkbox("##act"..i, active)
                            if c_change then s:set_field("IsActive", c_val) end

                            -- Weight
                            imgui.table_next_column()
                            imgui.push_item_width(-1)
                            local w_change, w_val = imgui.input_text ("##w"..i, weight)
                            if w_change then s:set_field("Weight", w_val) end
                            imgui.pop_item_width()

                            -- Frames
                            imgui.table_next_column()
                            if f > 0 then
                                imgui.text_colored(string.format("%d f", f), 0xFF00FF00)
                            else
                                imgui.text_colored("-", 0xFF666666)
                            end
                        end
                        imgui.end_table()
                    end
                else
                    imgui.text_colored("Error: "..msg, 0xFF0000FF)
                end
                imgui.tree_pop()
            end
        else
            imgui.text("Waiting for battle...")
        end

        imgui.separator()
        local col = 0xFFFFFFFF
        if string.find(status_msg, "Saved") or string.find(status_msg, "Loaded") then col = 0xFF00FF00 end
        if string.find(status_msg, "Crash") or string.find(status_msg, "Fail") or string.find(status_msg, "Low") then col = 0xFF0000FF end
        imgui.text("Msg: ")
        imgui.same_line()
        imgui.text_colored(status_msg, col)

        imgui.tree_pop()
    end
end)