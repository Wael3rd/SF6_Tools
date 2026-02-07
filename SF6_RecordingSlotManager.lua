local sdk = sdk
local imgui = imgui
local re = re
local json = json

-- =========================================================
-- CONFIGURATION
-- =========================================================
local DATA_FOLDER = "SlotManager_Data"
local status_msg = "Ready."
local current_p2_id = -1          

-- Official SF6 IDs
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
-- 1. IDENTITY DETECTOR
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
                current_p2_id = (p2 and p2:get_field("value__")) or -1
            end
        end, function(retval) return retval end)
    end
end

local function get_char_name(id)
    return CHARACTER_NAMES[id] or ("Unknown("..tostring(id)..")")
end

-- =========================================================
-- 2. MEMORY ACCESS
-- =========================================================
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
-- 3. NUMPAD LOGIC
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
-- 4. EXPORT (FULL 8 SLOTS + WEIGHT)
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
        local weight = slot:get_field("Weight") or 0 -- SELECTION RATE
        local is_valid = slot:get_field("IsValid")
        
        local slot_entry = { 
            id = i+1,
            weight = weight 
        }

        if is_valid and frames > 0 then
            -- Filled Slot
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
            -- Empty Slot (exported anyway to overwrite on import)
            slot_entry.empty = true
        end

        table.insert(export_data, slot_entry)
    end

    json.dump_file(DATA_FOLDER.."/"..p2_name..".json", export_data)
    return "Saved Full Backup: "..p2_name..".json"
end

local function export_all_characters()
    local count_ok = 0
    local log = ""
    
    -- Iterate through all valid IDs in CHARACTER_NAMES (which are indices 1 to 30 roughly)
    -- We can iterate the table pairs or a fixed range. CHARACTER_NAMES keys are integers.
    for id, name in pairs(CHARACTER_NAMES) do
        local res = export_json_compressed(id)
        if string.find(res, "Saved") then
            count_ok = count_ok + 1
        else
            log = log .. "\n" .. name .. ": " .. res
        end
    end
    
    if log ~= "" then return "Done ("..count_ok.."). Errors:"..log
    else return "All Characters Exported ("..count_ok..")" end
end

-- =========================================================
-- 5. IMPORT (CLEANER + WEIGHT)
-- =========================================================
local function import_json_compressed(target_id)
    local use_id = target_id or current_p2_id
    local p2_name = get_char_name(use_id)
    local data = json.load_file(DATA_FOLDER.."/"..p2_name..".json")
    if not data then return "File not found: "..p2_name..".json" end

    local slots, err = get_slots_access(use_id)
    if not slots then return "Error: " .. tostring(err) end

    local count = 0
    local log = ""

    for _, s_data in ipairs(data) do
        local slot = slots:call("get_Item", s_data.id - 1)
        
        -- 1. WEIGHT MANAGEMENT (RATE)
        if s_data.weight then
            slot:set_field("Weight", s_data.weight)
        end

        -- 2. CONTENT MANAGEMENT
        if s_data.empty then
            -- COMPLETE SLOT CLEANING
            slot:set_field("IsValid", false)
            slot:set_field("Frame", 0)
            slot:set_field("IsActive", false)
            slot:get_field("InputData"):set_field("Num", 0)
            -- This doesn't count as a "successful load" but as a "reset"
        else
            -- STANDARD LOADING
            local buffer = slot:get_field("InputData"):get_field("buff")
            local needed = 0
            if s_data.timeline then
                 for _, e in ipairs(s_data.timeline) do
                    local d = string.match(e, "(%d+)f")
                    if d then needed = needed + tonumber(d) end
                 end
            else needed = #s_data.inputs end -- Legacy

            local cap = buffer and buffer:call("get_Length") or 0
            
            if cap >= needed then
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
                slot:get_field("InputData"):set_field("Num", needed)
                count = count + 1
            else
                log = log .. "\nS"..s_data.id..": Mem Low ("..cap.." vs "..needed..")"
            end
        end
    end
    
    if log ~= "" then return "Partial ("..count..")."..log else return "Loaded: "..p2_name..".json" end
end

local function import_all_characters()
    local count_ok = 0
    local log = ""

    for id, name in pairs(CHARACTER_NAMES) do
        -- Check if file exists by trying to load it (or just relying on import_json_compressed check)
        -- Optimization: We could check file existence first if json.load_file is heavy, 
        -- but import_json_compressed returns specific string on missing file.
        
        local res = import_json_compressed(id)
        -- We only care if it successfully loaded or if it failed for a reason OTHER than "File not found"
        -- Actually user wants to import "ALL the folder", so if a file exists it should be imported.
        
        if string.find(res, "Loaded") then
            count_ok = count_ok + 1
        elseif string.find(res, "File not found") then
            -- Silent skip
        else
            log = log .. "\n" .. name .. ": " .. res
        end
    end

    if log ~= "" then return "Done ("..count_ok.."). Errors:"..log
    else return "All Available Files Imported ("..count_ok..")" end
end

-- =========================================================
-- UI DRAW
-- =========================================================
re.on_draw_ui(function()
    if imgui.begin_window("Slot Manager (V15 Full Control)", true, 0) then
        
        local real_name = get_char_name(current_p2_id)
        local display_header = "Target: " .. real_name
        if current_p2_id == -1 then display_header = "Target: Unknown (Go to Battle)" end
        
        imgui.text_colored(display_header, 0xFF00FFFF)
        imgui.separator()

        if current_p2_id ~= -1 then
            if imgui.button("EXPORT " .. real_name .. ".json") then
                local ok, res = pcall(export_json_compressed, nil)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end
            
            imgui.same_line()
            
            if imgui.button("IMPORT " .. real_name .. ".json") then
                local ok, res = pcall(import_json_compressed, nil)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end

            imgui.separator()
            if imgui.button("EXPORT ALL (Bulk)") then
                local ok, res = pcall(export_all_characters)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end
            imgui.same_line()
            if imgui.button("IMPORT ALL (Bulk)") then
                 local ok, res = pcall(import_all_characters)
                status_msg = ok and res or ("Crash: "..tostring(res))
            end
        else
            imgui.text_colored("Waiting for Character ID...", 0xFF888888)
        end
        
        imgui.separator()

        if imgui.tree_node("Live Slots (ID: "..current_p2_id..")") then
            if current_p2_id ~= -1 then
                local slots, msg = get_slots_access()
                if slots then
                    for i=0, 7 do
                        local s = slots:call("get_Item", i)
                        local f = s:get_field("Frame")
                        local a = s:get_field("IsActive")
                        local w = s:get_field("Weight") or 0 -- Weight Display
                        
                        local line = string.format("Slot %d: %4d frames [Rate: %d] [%s]", i+1, f, w, a and "ON" or "OFF")
                        local col = (f > 0) and 0xFF00FF00 or 0xFF888888
                        imgui.text_colored(line, col)
                    end
                else
                    imgui.text_colored("Error: "..msg, 0xFF0000FF)
                end
            else
                 imgui.text("Enter training to see slots.")
            end
            imgui.tree_pop()
        end

        imgui.separator()
        local col = 0xFFFFFFFF
        if string.find(status_msg, "Saved") or string.find(status_msg, "Loaded") then col = 0xFF00FF00 end
        if string.find(status_msg, "Error") or string.find(status_msg, "Crash") then col = 0xFF0000FF end
        imgui.text_colored(status_msg, col)

        imgui.end_window()
    end
end)
