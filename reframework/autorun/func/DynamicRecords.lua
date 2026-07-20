-- DynamicRecords.lua
-- Import/export helpers for SF6 training dynamic record slots and reversal settings.

local sdk = sdk
local json = json
local fs = fs
local os = os

local M = {}
local JSON_NULL = json and (json.null or json.NULL) or nil

M.LEGACY_SCHEMA = "sf6cc.dynamic_records.v1"
M.SCHEMA = "sf6cc.training_setup.v2"
M.DATA_DIR = "SF6CC_TrainingConfigs"
M.CONFIG_DIR = M.DATA_DIR .. "/configs"
M.BACKUP_DIR = M.DATA_DIR .. "/backups"
M.EXPORT_PATH = M.CONFIG_DIR .. "/export_current.json"
M.IMPORT_PATH = M.EXPORT_PATH
M.CONFIG_INDEX_PATH = M.DATA_DIR .. "/config_index.json"
M.LATEST_BACKUP_PATH = M.DATA_DIR .. "/latest_backup.json"
M.EDITOR_PATH = M.DATA_DIR .. "/editor/SF6CC_TrainingConfigEditor.html"
M.LEGACY_DATA_DIR = "SF6CC_DynamicRecords"
M.LEGACY_EXPORT_PATH = M.LEGACY_DATA_DIR .. "/export_current.json"
M._last_backup_path = nil

-- Native training recordings and reversal settings belong to the dummy side.
-- Keep this feature fixed to P2; do not infer the side from the active recorder.
local SOURCE_PLAYER = "P2"
local SOURCE_PLAYER_INDEX = 1
local SLOT_COUNT = 8
local REVERSAL_SLOT_COUNT = 10
local write_latest_backup_marker

local REVERSAL_GROUPS = {
    { key = "down", field = "DownReversalDatas", type = 0 },
    { key = "guard", field = "GuardReversalDatas", type = 1 },
    { key = "damage", field = "DamageReversalDatas", type = 2 },
}

local function empty_annotations()
    local out = {
        version = 1,
        record_slots = {},
        reversals = { down = {}, guard = {}, damage = {} },
    }
    for slot = 1, SLOT_COUNT do
        out.record_slots[slot] = { slot = slot, text = "" }
    end
    for _, group in ipairs(REVERSAL_GROUPS) do
        for slot = 1, REVERSAL_SLOT_COUNT do
            out.reversals[group.key][slot] = { slot = slot, text = "" }
        end
    end
    return out
end

M._annotations = empty_annotations()

local REVERSAL_FIELDS = {
    active = { "IsActive", "Active", "Enable", "IsEnable" },
    type = { "Type", "type" },
    skill_index = { "SkillIndex", "skillIndex", "SkillID", "SkillId" },
    delay_frame = { "DelayFrame", "Delay" },
    count = { "Count", "ReversalCount" },
    meaty_frame = { "MeatyFrame", "Meaty" },
}

local CHARACTER_NAMES = {
    [1] = "Ryu",        [2] = "Luke",       [3] = "Kimberly",   [4] = "Chun-Li",
    [5] = "Manon",      [6] = "Zangief",    [7] = "JP",         [8] = "Dhalsim",
    [9] = "Cammy",      [10] = "Ken",       [11] = "Dee Jay",   [12] = "Lily",
    [13] = "A.K.I",     [14] = "Rashid",    [15] = "Blanka",    [16] = "Juri",
    [17] = "Marisa",    [18] = "Guile",     [19] = "Ed",        [20] = "E. Honda",
    [21] = "Jamie",     [22] = "Akuma",     [23] = "M. Bison",  [24] = "Terry",
    [25] = "Sagat",     [26] = "M. Bison",  [27] = "Terry",     [28] = "Mai",
    [29] = "Elena",     [30] = "Viper",      [32] = "Ingrid",
}

local cached_context = {
    fighter_id = nil,
    fighter_name = "",
    source_player = SOURCE_PLAYER,
}

local function ensure_dirs()
    if fs and fs.create_dir then
        pcall(fs.create_dir, M.DATA_DIR)
        pcall(fs.create_dir, M.CONFIG_DIR)
        pcall(fs.create_dir, M.BACKUP_DIR)
    end
end

local function now_display()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function now_stamp()
    return os.date("%Y%m%d_%H%M%S")
end

local function as_int(value, default)
    local n = tonumber(value)
    if n == nil then return default end
    return math.floor(n)
end

local function get_char_name(fighter_id)
    return CHARACTER_NAMES[fighter_id] or ("Unknown(" .. tostring(fighter_id) .. ")")
end

local function sanitize_filename_component(value, fallback)
    local s = tostring(value or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("[%c]", "")
    s = s:gsub("%s+", "_")
    s = s:gsub("[<>:\"/\\|%?%*%.]", "_")

    local out = {}
    for index = 1, #s do
        local byte = s:byte(index)
        if (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 45 or byte == 95 then
            out[#out + 1] = s:sub(index, index)
        elseif byte < 128 then
            out[#out + 1] = "_"
        end
    end

    s = table.concat(out):gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if s == "" then return fallback or "P2" end
    return s
end

local function get_collection_item(collection, index)
    if not collection then return nil end

    local ok, item = pcall(function() return collection:call("get_Item", index) end)
    if ok and item then return item end

    ok, item = pcall(function() return collection:call("GetValue", index) end)
    if ok and item then return item end

    ok, item = pcall(function() return collection[index] end)
    if ok then return item end

    return nil
end

local function set_collection_item(collection, index, value)
    if not collection then return false, "collection is nil" end

    local ok, err = pcall(function() collection:call("set_Item", index, value) end)
    if ok then return true, nil end

    ok, err = pcall(function() collection:call("Set", index, value) end)
    if ok then return true, nil end

    ok, err = pcall(function() collection:call("SetValue", value, index) end)
    if ok then return true, nil end

    return false, tostring(err)
end

local function safe_get_field(obj, name)
    if not obj then return nil end
    local ok, value = pcall(function() return obj:get_field(name) end)
    if ok then return value end
    return nil
end

local function safe_set_field(obj, name, value)
    if not obj then return false, "object is nil" end
    local td = nil
    local ok = pcall(function() td = obj:get_type_definition() end)
    if ok and td then
        local field = nil
        pcall(function() field = td:get_field(name) end)
        if not field then return false, "field not found: " .. tostring(name) end
    end

    local err
    ok, err = pcall(function() obj:set_field(name, value) end)
    if ok then return true, nil end
    return false, tostring(err)
end

local function read_first_field(obj, names)
    for _, name in ipairs(names or {}) do
        local value = safe_get_field(obj, name)
        if value ~= nil then return value, name end
    end
    return nil, nil
end

local function json_scalar(value)
    if value == nil then return JSON_NULL end
    local value_type = type(value)
    if value_type == "number" or value_type == "string" or value_type == "boolean" then
        return value
    end
    local n = tonumber(value) or tonumber(tostring(value))
    if n ~= nil then return n end
    return JSON_NULL
end

local function read_selected_fighter_id()
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return nil, "No TrainingManager" end

    local t_data = mgr:get_field("_tData")
    if not t_data then return nil, "No TrainingManager._tData" end

    local select_menu = t_data:get_field("SelectMenu")
    if not select_menu then return nil, "No SelectMenu" end

    local player_datas = select_menu:get_field("PlayerDatas")
    if not player_datas then return nil, "No SelectMenu.PlayerDatas" end

    local player_data = get_collection_item(player_datas, SOURCE_PLAYER_INDEX)
    if not player_data then return nil, "No P2 PlayerData" end

    local fighter_id = as_int(player_data:get_field("FighterID"), nil)
    if fighter_id == nil then return nil, "No P2 FighterID" end

    return fighter_id, nil
end

function M.get_context()
    local fighter_id, err = read_selected_fighter_id()
    if fighter_id ~= nil then
        cached_context.fighter_id = fighter_id
        cached_context.fighter_name = get_char_name(fighter_id)
        cached_context.source_player = SOURCE_PLAYER
        return cached_context
    end

    return {
        fighter_id = cached_context.fighter_id,
        fighter_name = cached_context.fighter_name,
        source_player = SOURCE_PLAYER,
        error = err,
    }
end

local function get_record_func()
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return nil, "No TrainingManager" end

    local rec_func = mgr:call("get_RecordFunc")
    if not rec_func then return nil, "No RecordFunc" end

    return rec_func, nil
end

local function get_slots_for_fighter(fighter_id)
    if fighter_id == nil then return nil, "No fighter_id" end

    local rec_func, rec_err = get_record_func()
    if not rec_func then return nil, rec_err end

    local t_data = rec_func:get_field("_tData")
    if not t_data then return nil, "No RecordFunc._tData" end

    local record_setting = t_data:get_field("RecordSetting")
    if not record_setting then return nil, "No RecordSetting" end

    local fighter_list = record_setting:get_field("FighterDataList")
    if not fighter_list then return nil, "No FighterDataList" end

    local fighter_data = get_collection_item(fighter_list, fighter_id)
    if not fighter_data then return nil, "No FighterData for id " .. tostring(fighter_id) end

    local slots = fighter_data:get_field("RecordSlots")
    if not slots then return nil, "No RecordSlots" end

    return slots, nil, rec_func, {
        record_setting = record_setting,
        fighter_data = fighter_data,
    }
end

local function get_current_slots()
    local ctx = M.get_context()
    if ctx.error then return nil, ctx.error, ctx end

    local slots, err, rec_func, record_ctx = get_slots_for_fighter(ctx.fighter_id)
    if not slots then return nil, err, ctx end

    return slots, nil, ctx, rec_func, record_ctx
end

local function get_reversal_context(fighter_id)
    if fighter_id == nil then return nil, "No fighter_id" end

    local manager = sdk.get_managed_singleton("app.training.TrainingManager")
    if not manager then return nil, "No TrainingManager" end

    local reversal_func = manager:call("get_ReversalFunc")
    if not reversal_func then return nil, "No ReversalFunc" end

    local t_data = reversal_func:get_field("_tData")
    if not t_data then return nil, "No ReversalFunc._tData" end

    local reversal_setting = t_data:get_field("ReversalSetting")
    if not reversal_setting then return nil, "No ReversalSetting" end

    local fighter_list = reversal_setting:get_field("FighterDataList")
    if not fighter_list then return nil, "No ReversalSetting.FighterDataList" end

    local fighter_data = get_collection_item(fighter_list, fighter_id)
    if not fighter_data then
        return nil, "No reversal FighterData for id " .. tostring(fighter_id)
    end

    local groups = {}
    for _, definition in ipairs(REVERSAL_GROUPS) do
        local entries = fighter_data:get_field(definition.field)
        if not entries then return nil, "No " .. definition.field end
        groups[definition.key] = entries
    end

    return {
        manager = manager,
        reversal_func = reversal_func,
        reversal_setting = reversal_setting,
        fighter_data = fighter_data,
        fighter_id = fighter_id,
        groups = groups,
        original_type = as_int(safe_get_field(reversal_setting, "ReversalType"), nil),
    }, nil
end

local function get_bool_field(obj, name)
    local raw = obj:get_field(name)
    return raw == true or raw == 1
end

local function get_buffer(input_data)
    if not input_data then return nil end
    return input_data:get_field("buff")
end

local function get_buffer_length(buffer)
    if not buffer then return 0 end
    local ok, len = pcall(function() return buffer:call("get_Length") end)
    if ok and len then return as_int(len, 0) end
    return 0
end

local function read_buffer_values(buffer, frames)
    local values = {}
    local length = get_buffer_length(buffer)
    local read_count = math.min(math.max(as_int(frames, 0) or 0, 0), length)

    for index = 0, read_count - 1 do
        local ok, raw = pcall(function() return buffer:call("GetValue", index) end)
        local value = 0
        if ok and raw then
            value = as_int(raw:get_field("mValue"), 0)
        end
        values[#values + 1] = value
    end

    return values, length
end

local collect_scalar_fields

local function collect_slot(slot_obj, slot_number, include_buff)
    local frame = as_int(slot_obj:get_field("Frame"), 0) or 0
    local weight = as_int(slot_obj:get_field("Weight"), 0) or 0
    local input_data = slot_obj:get_field("InputData")
    local input_num = input_data and as_int(input_data:get_field("Num"), frame) or frame
    local buffer = get_buffer(input_data)
    local input_buff = {}
    local capacity = get_buffer_length(buffer)

    if include_buff and buffer then
        input_buff, capacity = read_buffer_values(buffer, frame)
    end

    return {
        slot = slot_number,
        name = "slot" .. tostring(slot_number),
        is_valid = get_bool_field(slot_obj, "IsValid"),
        is_active = get_bool_field(slot_obj, "IsActive"),
        frame = frame,
        weight = weight,
        input_num = input_num or frame,
        input_buff = include_buff and input_buff or nil,
        capacity = capacity,
        fields = collect_scalar_fields(slot_obj),
        input_fields = collect_scalar_fields(input_data),
    }
end

collect_scalar_fields = function(obj)
    local out = {}
    if not obj then return out end

    local td = nil
    local ok = pcall(function() td = obj:get_type_definition() end)
    if not ok or not td then return out end

    local fields = nil
    ok = pcall(function() fields = td:get_fields() end)
    if not ok or not fields then return out end

    for _, field in ipairs(fields) do
        local name = nil
        pcall(function() name = field:get_name() end)
        if name then
            local value = safe_get_field(obj, name)
            local serialized = json_scalar(value)
            if serialized ~= JSON_NULL then out[name] = serialized end
        end
    end

    return out
end

local function collect_reversal_entry(entry, slot_number)
    local function read_canonical(key)
        local value = read_first_field(entry, REVERSAL_FIELDS[key])
        return json_scalar(value)
    end

    return {
        slot = slot_number,
        active = read_canonical("active"),
        type = read_canonical("type"),
        skill_index = read_canonical("skill_index"),
        delay_frame = read_canonical("delay_frame"),
        count = read_canonical("count"),
        meaty_frame = read_canonical("meaty_frame"),
        fields = collect_scalar_fields(entry),
    }
end

local function collect_reversals(ctx)
    local reversal_ctx, err = get_reversal_context(ctx.fighter_id)
    if not reversal_ctx then return nil, err end

    local out = {}
    for _, definition in ipairs(REVERSAL_GROUPS) do
        local entries = reversal_ctx.groups[definition.key]
        local group_out = {}
        for index = 0, REVERSAL_SLOT_COUNT - 1 do
            local entry = get_collection_item(entries, index)
            if not entry then
                return nil, "Missing " .. definition.key .. " reversal slot " .. tostring(index + 1)
            end
            group_out[#group_out + 1] = collect_reversal_entry(entry, index + 1)
        end
        out[definition.key] = group_out
    end

    return out, nil
end

local function copy_binding(binding)
    if type(binding) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(binding) do
        local value_type = type(value)
        if type(key) == "string"
            and (value_type == "string" or value_type == "number" or value_type == "boolean") then
            out[key] = value
        end
    end
    return next(out) and out or nil
end

local function normalize_annotation_entry(source, slot)
    if type(source) == "string" then
        return { slot = slot, text = source }
    end
    if type(source) ~= "table" then
        return { slot = slot, text = "" }
    end
    return {
        slot = slot,
        text = type(source.text) == "string" and source.text or "",
        binding = copy_binding(source.binding),
    }
end

local function normalize_annotations(source)
    local out = empty_annotations()
    if type(source) ~= "table" then return out end

    out.version = as_int(source.version, 1) or 1
    if type(source.record_slots) == "table" then
        for index, entry in ipairs(source.record_slots) do
            local slot = type(entry) == "table" and as_int(entry.slot, index) or index
            if slot and slot >= 1 and slot <= SLOT_COUNT then
                out.record_slots[slot] = normalize_annotation_entry(entry, slot)
            end
        end
    end

    if type(source.reversals) == "table" then
        for _, group in ipairs(REVERSAL_GROUPS) do
            local source_group = source.reversals[group.key]
            if type(source_group) == "table" then
                for index, entry in ipairs(source_group) do
                    local slot = type(entry) == "table" and as_int(entry.slot, index) or index
                    if slot and slot >= 1 and slot <= REVERSAL_SLOT_COUNT then
                        out.reversals[group.key][slot] = normalize_annotation_entry(entry, slot)
                    end
                end
            end
        end
    end
    return out
end

local function clone_annotations(source)
    return normalize_annotations(source)
end

local function record_signature(slot_data)
    if type(slot_data) ~= "table" then return nil end
    if slot_data.is_valid ~= true or (as_int(slot_data.frame, 0) or 0) <= 0 then
        return "record-v1:empty"
    end
    if type(slot_data.input_buff) ~= "table" then return nil end

    local hash = 17
    for index, value in ipairs(slot_data.input_buff) do
        hash = (hash * 131 + (as_int(value, 0) or 0) + index) % 2147483647
    end
    return "record-v1:" .. tostring(as_int(slot_data.frame, 0) or 0)
        .. ":" .. tostring(as_int(slot_data.input_num, 0) or 0)
        .. ":" .. tostring(hash)
end

local function reversal_binding(entry)
    if type(entry) ~= "table" then return nil end
    local type_value = as_int(entry.type, -1) or -1
    local skill_index = as_int(entry.skill_index, -1) or -1
    local fields = type(entry.fields) == "table" and entry.fields or {}
    local level = as_int(fields.Level, 0) or 0
    return {
        type = type_value,
        skill_index = skill_index,
        level = level,
        signature = "reversal-v1:" .. tostring(type_value)
            .. ":" .. tostring(skill_index) .. ":" .. tostring(level),
    }
end

local function binding_matches_record(binding, signature)
    if type(binding) ~= "table" or type(binding.signature) ~= "string" then return true end
    return binding.signature == signature
end

local function binding_matches_reversal(binding, current)
    if type(binding) ~= "table" then return true end
    if type(binding.signature) == "string" then
        return current and binding.signature == current.signature
    end
    return current
        and as_int(binding.type, -1) == current.type
        and as_int(binding.skill_index, -1) == current.skill_index
        and as_int(binding.level, 0) == current.level
end

local function collect_snapshot(include_buff, metadata)
    local slots, err, ctx, _, record_ctx = get_current_slots()
    if not slots then return nil, err end

    local out_slots = {}
    for index = 0, SLOT_COUNT - 1 do
        local slot_obj = get_collection_item(slots, index)
        if not slot_obj then return nil, "Missing slot " .. tostring(index + 1) end
        out_slots[#out_slots + 1] = collect_slot(slot_obj, index + 1, include_buff)
    end

    local reversals, reversal_err = collect_reversals(ctx)
    if not reversals then return nil, reversal_err end

    return {
        schema = M.SCHEMA,
        created_at = now_display(),
        title = type(metadata) == "table" and tostring(metadata.title or "") ~= ""
            and tostring(metadata.title) or (tostring(ctx.fighter_name or "P2") .. " 训练配置"),
        description = type(metadata) == "table" and tostring(metadata.description or "") or "",
        fighter_id = ctx.fighter_id,
        fighter_name = ctx.fighter_name,
        source_player = ctx.source_player,
        slots = out_slots,
        reversals = reversals,
        annotations = clone_annotations(M._annotations),
        settings = {
            record = {
                record_setting_fields = collect_scalar_fields(record_ctx and record_ctx.record_setting),
                fighter_fields = collect_scalar_fields(record_ctx and record_ctx.fighter_data),
            },
        },
    }, nil
end

function M.get_overlay_state()
    local slots, slots_err, ctx = get_current_slots()
    if not slots then return nil, slots_err end

    local reversal_ctx, reversal_err = get_reversal_context(ctx.fighter_id)
    if not reversal_ctx then return nil, reversal_err end

    local state = {
        record_slots = {},
        reversals = { down = {}, guard = {}, damage = {} },
        reversal_type = reversal_ctx.original_type,
    }

    for index = 0, SLOT_COUNT - 1 do
        local annotation = M._annotations.record_slots[index + 1]
        local text = annotation and tostring(annotation.text or "") or ""
        if text ~= "" then
            local slot_obj = get_collection_item(slots, index)
            local current = slot_obj and collect_slot(slot_obj, index + 1, true) or nil
            local signature = record_signature(current)
            if not binding_matches_record(annotation.binding, signature) then text = "" end
        end
        state.record_slots[index + 1] = text
    end

    for _, group in ipairs(REVERSAL_GROUPS) do
        local collection = reversal_ctx.groups[group.key]
        for index = 0, REVERSAL_SLOT_COUNT - 1 do
            local target = get_collection_item(collection, index)
            local entry = target and collect_reversal_entry(target, index + 1) or nil
            local current_binding = reversal_binding(entry)
            local annotation = M._annotations.reversals[group.key][index + 1]
            local text = annotation and tostring(annotation.text or "") or ""
            if text ~= "" and not binding_matches_reversal(annotation.binding, current_binding) then
                text = ""
            end
            if text == "" and current_binding and current_binding.type == 4
                and current_binding.skill_index >= 0 and current_binding.skill_index < SLOT_COUNT then
                text = state.record_slots[current_binding.skill_index + 1] or ""
            end
            state.reversals[group.key][index + 1] = text
        end
    end

    return state, nil
end

function M.get_slot_summaries()
    local snapshot, err = collect_snapshot(false)
    if not snapshot then return nil, err end
    return snapshot.slots, nil, snapshot
end

local function dump_snapshot(path, include_buff, metadata)
    ensure_dirs()
    local snapshot, err = collect_snapshot(include_buff, metadata)
    if not snapshot then return nil, err end

    local ok, write_result = pcall(json.dump_file, path, snapshot)
    if not ok then return nil, tostring(write_result) end
    if write_result == false then return nil, "json.dump_file returned false" end

    return snapshot, nil
end

function M.export_current(path, metadata)
    local out_path = path or M.EXPORT_PATH
    local snapshot, err = dump_snapshot(out_path, true, metadata)
    if not snapshot then return false, err end
    return true, "Exported: data/" .. out_path, out_path, snapshot
end

local function data_path_exists(path)
    if not fs or not fs.glob or type(path) ~= "string" then return false end
    local matches = fs.glob(path)
    return type(matches) == "table" and #matches > 0
end

local function glob_data_directory(directory, filename_regex)
    if not fs or not fs.glob then return {}, {} end

    local windows_regex_dir = tostring(directory or ""):gsub("/", "\\\\")
    local patterns = {
        windows_regex_dir .. "\\\\" .. tostring(filename_regex or ".*"),
        tostring(directory or "") .. "/" .. tostring(filename_regex or ".*"),
    }
    local matches = {}
    local seen = {}
    for _, pattern in ipairs(patterns) do
        local ok, result = pcall(fs.glob, pattern)
        if ok and type(result) == "table" then
            for _, path in ipairs(result) do
                if not seen[path] then
                    seen[path] = true
                    matches[#matches + 1] = path
                end
            end
        end
    end
    return matches, patterns
end

local function normalize_config_path(path)
    if type(path) ~= "string" then return nil end
    local normalized = path:gsub("\\", "/")
    local data_prefix = "/data/"
    local prefix_pos = normalized:find(data_prefix, 1, true)
    if prefix_pos then normalized = normalized:sub(prefix_pos + #data_prefix) end
    return normalized:gsub("^data/", "")
end

local function read_config_index_paths()
    if not fs or not fs.read then return {} end
    local ok, content = pcall(fs.read, M.CONFIG_INDEX_PATH)
    if not ok or type(content) ~= "string" or content == "" then return {} end
    local parsed = json and json.load_string and json.load_string(content) or nil
    local source = type(parsed) == "table" and parsed.configs or nil
    local paths = {}
    if type(source) == "table" then
        for _, path in ipairs(source) do
            local normalized = normalize_config_path(path)
            if normalized then paths[#paths + 1] = normalized end
        end
    end
    return paths
end

local function write_config_index_paths(paths)
    ensure_dirs()
    local unique = {}
    local out = {}
    for _, path in ipairs(paths or {}) do
        local normalized = normalize_config_path(path)
        if normalized and not unique[normalized] then
            unique[normalized] = true
            out[#out + 1] = normalized
        end
    end
    table.sort(out, function(left, right) return tostring(left) > tostring(right) end)
    local ok, result = pcall(json.dump_file, M.CONFIG_INDEX_PATH, {
        schema = "sf6cc.training_config_index.v1",
        configs = out,
    })
    return ok and result ~= false
end

local function register_config_path(path)
    local paths = read_config_index_paths()
    paths[#paths + 1] = path
    return write_config_index_paths(paths)
end

local function config_path_is_loadable(path)
    if type(path) ~= "string" or path == "" then return false end
    local ok, data = pcall(json.load_file, path)
    return ok and type(data) == "table"
end

function M.list_configs()
    ensure_dirs()
    local entries = {}
    local seen = {}
    local matches, patterns = glob_data_directory(M.CONFIG_DIR, ".*json")
    M._last_config_glob_patterns = patterns
    M._last_config_glob_count = #matches

    for _, indexed_path in ipairs(read_config_index_paths()) do
        if config_path_is_loadable(indexed_path) then
            matches[#matches + 1] = indexed_path
        end
    end

    for _, raw_path in ipairs(matches) do
        local path = normalize_config_path(raw_path)
        local filename = path and path:match("([^/]+)$") or nil
        if path and filename and not seen[path] and config_path_is_loadable(path) then
            seen[path] = true
            entries[#entries + 1] = {
                filename = filename,
                path = path,
                legacy = false,
            }
        end
    end

    table.sort(entries, function(left, right)
        if left.legacy ~= right.legacy then return left.legacy == false end
        return tostring(left.filename) > tostring(right.filename)
    end)
    local indexed_paths = {}
    for _, entry in ipairs(entries) do
        if not entry.legacy then indexed_paths[#indexed_paths + 1] = entry.path end
    end
    write_config_index_paths(indexed_paths)
    return entries
end

function M.read_config_metadata(path)
    if type(path) ~= "string" or path == "" then return nil, "empty config path" end
    local data = json.load_file(path)
    if type(data) ~= "table" then return nil, "config JSON could not be loaded" end
    return {
        schema = data.schema,
        title = type(data.title) == "string" and data.title or "",
        description = type(data.description) == "string" and data.description or "",
        fighter_id = data.fighter_id,
        fighter_name = data.fighter_name,
        source_player = data.source_player,
    }, nil
end

function M.export_new(metadata)
    ensure_dirs()
    local ctx = M.get_context()
    if ctx.error then return false, "Export failed: " .. tostring(ctx.error) end

    local character = sanitize_filename_component(ctx.fighter_name, "P2")
    local stamp = now_stamp()
    local base_name = character .. "_" .. stamp
    local path = M.CONFIG_DIR .. "/" .. base_name .. ".json"
    local suffix = 1
    while data_path_exists(path) do
        path = M.CONFIG_DIR .. "/" .. base_name .. "_" .. string.format("%03d", suffix) .. ".json"
        suffix = suffix + 1
    end

    local snapshot, err = dump_snapshot(path, true, metadata)
    if not snapshot then return false, err end
    if not register_config_path(path) then
        return false, "配置已写入，但更新配置索引失败: data/" .. path, path, snapshot
    end
    return true, "已导出: data/" .. path, path, snapshot
end

function M.backup_current()
    local stamp = now_stamp()
    local path = M.BACKUP_DIR .. "/records_backup_" .. stamp .. ".json"
    local suffix = 1
    while data_path_exists(path) do
        path = M.BACKUP_DIR .. "/records_backup_" .. stamp .. "_" .. string.format("%03d", suffix) .. ".json"
        suffix = suffix + 1
    end

    local snapshot, err = dump_snapshot(path, true)
    if not snapshot then return false, err end
    local marker_ok, marker_err = write_latest_backup_marker(path, stamp)
    if not marker_ok then
        return false, "Backup saved but latest marker failed: " .. tostring(marker_err)
    end
    return true, "Backup saved: data/" .. path, path, snapshot
end

local function normalize_slot_number(raw_slot, fallback_index)
    local slot_number = as_int(raw_slot, nil)
    if slot_number == nil then slot_number = fallback_index end
    if slot_number < 1 or slot_number > SLOT_COUNT then return nil end
    return slot_number
end

local function normalize_input_value(value)
    local n = tonumber(value)
    if n == nil then return nil end
    n = math.floor(n)
    if n < 0 or n > 0xFFFF then return nil end
    return n
end

local function has_importable_input(slot_data)
    return type(slot_data.input_buff) == "table" and #slot_data.input_buff > 0
end

local function should_write_slot(slot_data, options)
    if slot_data.is_valid == true then return true end
    if options.only_import_valid == true then return false end
    return has_importable_input(slot_data)
end

local function is_supported_schema(schema)
    return schema == M.SCHEMA or schema == M.LEGACY_SCHEMA
end

local function normalize_scalar_field_map(source)
    local out = {}
    if type(source) ~= "table" then return out end

    for field_name, field_value in pairs(source) do
        local value_type = type(field_value)
        if type(field_name) == "string"
            and (value_type == "number" or value_type == "string" or value_type == "boolean") then
            out[field_name] = field_value
        end
    end

    return out
end

local function validate_slot_for_import(index, slot_data, slots, options, seen_slots)
    if type(slot_data) ~= "table" then
        return nil, "slot entry " .. tostring(index) .. " is not an object"
    end

    local slot_number = normalize_slot_number(slot_data.slot or slot_data.id, index)
    if not slot_number then
        return nil, "slot entry " .. tostring(index) .. " has invalid slot number"
    end

    if seen_slots[slot_number] then
        return nil, "duplicate slot " .. tostring(slot_number)
    end
    seen_slots[slot_number] = true

    local source_valid = slot_data.is_valid == true
    local write_slot = should_write_slot(slot_data, options)
    local clear_slot = (not source_valid) and options.clear_empty_slots == true

    if not write_slot and not clear_slot then
        return false, nil
    end

    local slot_obj = get_collection_item(slots, slot_number - 1)
    if not slot_obj then
        return nil, "slot " .. tostring(slot_number) .. " not found in game data"
    end

    if clear_slot and not write_slot then
        local input_data = slot_obj:get_field("InputData")
        return {
            kind = "clear",
            slot = slot_number,
            slot_obj = slot_obj,
            input_data = input_data,
            weight = as_int(slot_data.weight, nil),
            fields = normalize_scalar_field_map(slot_data.fields),
            input_fields = normalize_scalar_field_map(slot_data.input_fields),
        }, nil
    end

    if type(slot_data.input_buff) ~= "table" then
        return nil, "slot " .. tostring(slot_number) .. " input_buff is not an array"
    end

    local frame = as_int(slot_data.frame, nil)
    local input_num = as_int(slot_data.input_num, nil)
    local buff_len = #slot_data.input_buff

    if frame == nil then frame = buff_len end
    if input_num == nil then input_num = frame end

    if frame < 0 or input_num < 0 then
        return nil, "slot " .. tostring(slot_number) .. " has negative frame/input_num"
    end

    if frame > buff_len or input_num > buff_len then
        return nil, "slot " .. tostring(slot_number) .. " frame/input_num exceeds input_buff length"
    end

    local input_data = slot_obj:get_field("InputData")
    local buffer = get_buffer(input_data)
    local capacity = get_buffer_length(buffer)

    if not input_data or not buffer then
        return nil, "slot " .. tostring(slot_number) .. " has no InputData.buff"
    end

    if buff_len > capacity then
        return nil, "slot " .. tostring(slot_number)
            .. " input_buff length " .. tostring(buff_len)
            .. " exceeds capacity " .. tostring(capacity)
    end

    local normalized_buff = {}
    for buff_index = 1, buff_len do
        local n = normalize_input_value(slot_data.input_buff[buff_index])
        if n == nil then
            return nil, "slot " .. tostring(slot_number)
                .. " has invalid input value at " .. tostring(buff_index)
        end
        normalized_buff[buff_index] = n
    end

    return {
        kind = "write",
        slot = slot_number,
        slot_obj = slot_obj,
        input_data = input_data,
        buffer = buffer,
        is_valid = slot_data.is_valid == true,
        is_active = slot_data.is_active == true,
        frame = frame,
        weight = as_int(slot_data.weight, 0) or 0,
        input_num = input_num,
        input_buff = normalized_buff,
        fields = normalize_scalar_field_map(slot_data.fields),
        input_fields = normalize_scalar_field_map(slot_data.input_fields),
    }, nil
end

local function build_import_plan(data, slots, options)
    local plan = {}
    local errors = {}
    local seen_slots = {}

    if type(data) ~= "table" then
        return nil, { "Import JSON root is not an object" }
    end

    if not is_supported_schema(data.schema) then
        return nil, { "Schema mismatch: " .. tostring(data.schema) }
    end

    local ctx = M.get_context()
    if options.reject_fighter_mismatch ~= false then
        if as_int(data.fighter_id, nil) ~= as_int(ctx.fighter_id, nil) then
            return nil, {
                "fighter_id mismatch: file=" .. tostring(data.fighter_id)
                    .. " current=" .. tostring(ctx.fighter_id)
            }
        end
    end

    if type(data.slots) ~= "table" then
        return nil, { "slots is not an array" }
    end

    for index, slot_data in ipairs(data.slots) do
        local step, err = validate_slot_for_import(index, slot_data, slots, options, seen_slots)
        if err then
            errors[#errors + 1] = err
        elseif step then
            plan[#plan + 1] = step
        end
    end

    if #errors > 0 then return nil, errors end
    return plan, nil
end

local function build_record_settings_plan(data, record_ctx)
    local plan = {}
    if data.schema == M.LEGACY_SCHEMA or type(data.settings) ~= "table" then return plan end

    local source = data.settings.record
    if type(source) ~= "table" or not record_ctx then return plan end

    plan[#plan + 1] = {
        label = "record setting",
        target = record_ctx.record_setting,
        fields = normalize_scalar_field_map(source.record_setting_fields),
    }
    plan[#plan + 1] = {
        label = "record fighter data",
        target = record_ctx.fighter_data,
        fields = normalize_scalar_field_map(source.fighter_fields),
    }
    return plan
end

local function validate_import_header(data, options)
    if type(data) ~= "table" then
        return false, "Import JSON root is not an object"
    end

    if not is_supported_schema(data.schema) then
        return false, "Schema mismatch: " .. tostring(data.schema)
    end

    if type(data.slots) ~= "table" then
        return false, "slots is not an array"
    end

    local ctx = M.get_context()
    if options.reject_fighter_mismatch ~= false then
        if as_int(data.fighter_id, nil) ~= as_int(ctx.fighter_id, nil) then
            return false, "fighter_id mismatch: file=" .. tostring(data.fighter_id)
                .. " current=" .. tostring(ctx.fighter_id)
        end
    end

    return true, nil
end


local function validate_reversal_scalar(group_key, slot_number, field_name, value, value_type)
    if value == nil or value == JSON_NULL then return nil, nil end
    if value_type == "boolean" then
        if type(value) ~= "boolean" then
            return nil, group_key .. " reversal slot " .. tostring(slot_number)
                .. " " .. field_name .. " is not boolean"
        end
        return value, nil
    end

    local n = as_int(value, nil)
    if n == nil then
        return nil, group_key .. " reversal slot " .. tostring(slot_number)
            .. " " .. field_name .. " is not an integer"
    end
    return n, nil
end

local function normalize_reversal_slot(raw_slot, fallback_index)
    local slot_number = as_int(raw_slot, nil)
    if slot_number == nil then slot_number = fallback_index end
    if slot_number < 1 or slot_number > REVERSAL_SLOT_COUNT then return nil end
    return slot_number
end

local function build_reversal_import_plan(data, reversal_ctx)
    if data.schema == M.LEGACY_SCHEMA then return {}, nil end
    if type(data.reversals) ~= "table" then
        return nil, { "reversals is not an object" }
    end

    local plan = {}
    local errors = {}

    for _, definition in ipairs(REVERSAL_GROUPS) do
        local source_group = data.reversals[definition.key]
        if type(source_group) ~= "table" then
            errors[#errors + 1] = "reversals." .. definition.key .. " is not an array"
        else
            local seen = {}
            for index, source in ipairs(source_group) do
                if type(source) ~= "table" then
                    errors[#errors + 1] = definition.key .. " reversal entry " .. tostring(index)
                        .. " is not an object"
                else
                    local slot_number = normalize_reversal_slot(source.slot or source.index, index)
                    if not slot_number then
                        errors[#errors + 1] = definition.key .. " reversal entry " .. tostring(index)
                            .. " has invalid slot"
                    elseif seen[slot_number] then
                        errors[#errors + 1] = definition.key .. " reversal has duplicate slot "
                            .. tostring(slot_number)
                    else
                        seen[slot_number] = true
                        local target = get_collection_item(reversal_ctx.groups[definition.key], slot_number - 1)
                        if not target then
                            errors[#errors + 1] = definition.key .. " reversal slot "
                                .. tostring(slot_number) .. " is missing in game data"
                        else
                            local active, active_err = validate_reversal_scalar(
                                definition.key, slot_number, "active", source.active, "boolean")
                            local type_value, type_err = validate_reversal_scalar(
                                definition.key, slot_number, "type", source.type, "integer")
                            local skill_index, skill_err = validate_reversal_scalar(
                                definition.key, slot_number, "skill_index", source.skill_index, "integer")
                            local delay_frame, delay_err = validate_reversal_scalar(
                                definition.key, slot_number, "delay_frame", source.delay_frame, "integer")
                            local count, count_err = validate_reversal_scalar(
                                definition.key, slot_number, "count", source.count, "integer")
                            local meaty_frame, meaty_err = validate_reversal_scalar(
                                definition.key, slot_number, "meaty_frame", source.meaty_frame, "integer")

                            local scalar_error = active_err or type_err or skill_err
                                or delay_err or count_err or meaty_err
                            if scalar_error then
                                errors[#errors + 1] = scalar_error
                            else
                                local raw_fields = {}
                                if type(source.fields) == "table" then
                                    for field_name, field_value in pairs(source.fields) do
                                        local field_type = type(field_value)
                                        if type(field_name) == "string"
                                            and (field_type == "number" or field_type == "boolean") then
                                            raw_fields[field_name] = field_value
                                        end
                                    end
                                end

                                plan[#plan + 1] = {
                                    group = definition,
                                    slot = slot_number,
                                    index = slot_number - 1,
                                    collection = reversal_ctx.groups[definition.key],
                                    target = target,
                                    active = active,
                                    type = type_value,
                                    skill_index = skill_index,
                                    delay_frame = delay_frame,
                                    count = count,
                                    meaty_frame = meaty_frame,
                                    fields = raw_fields,
                                }
                            end
                        end
                    end
                end
            end

            for slot_number = 1, REVERSAL_SLOT_COUNT do
                if not seen[slot_number] then
                    errors[#errors + 1] = definition.key .. " reversal is missing slot "
                        .. tostring(slot_number)
                end
            end
        end
    end

    if #errors > 0 then return nil, errors end
    return plan, nil
end

local function apply_import_plan(plan)
    local written = 0
    local cleared = 0

    for _, step in ipairs(plan) do
        for field_name, value in pairs(step.fields or {}) do
            local field_ok, field_err = safe_set_field(step.slot_obj, field_name, value)
            if not field_ok then
                error("record slot " .. tostring(step.slot) .. " field " .. tostring(field_name)
                    .. " failed: " .. tostring(field_err))
            end
        end
        for field_name, value in pairs(step.input_fields or {}) do
            local field_ok, field_err = safe_set_field(step.input_data, field_name, value)
            if not field_ok then
                error("record slot " .. tostring(step.slot) .. " input field "
                    .. tostring(field_name) .. " failed: " .. tostring(field_err))
            end
        end

        if step.kind == "clear" then
            if step.weight ~= nil then step.slot_obj:set_field("Weight", step.weight) end
            step.slot_obj:set_field("IsValid", false)
            step.slot_obj:set_field("IsActive", false)
            step.slot_obj:set_field("Frame", 0)
            local input_data = step.slot_obj:get_field("InputData")
            if input_data then input_data:set_field("Num", 0) end
            cleared = cleared + 1
        elseif step.kind == "write" then
            step.slot_obj:set_field("Weight", step.weight)
            step.slot_obj:set_field("IsActive", step.is_active)
            step.slot_obj:set_field("Frame", step.frame)
            step.input_data:set_field("Num", step.input_num)

            for index, value in ipairs(step.input_buff) do
                step.buffer:call("SetValue", sdk.create_uint16(value), index - 1)
            end

            step.slot_obj:set_field("IsValid", step.is_valid)
            written = written + 1
        end
    end

    return written, cleared
end

local function apply_record_settings_plan(plan)
    local restored = 0
    for _, step in ipairs(plan) do
        for field_name, value in pairs(step.fields or {}) do
            local ok, err = safe_set_field(step.target, field_name, value)
            if not ok then
                error(step.label .. " field " .. tostring(field_name)
                    .. " failed: " .. tostring(err))
            end
            restored = restored + 1
        end
    end
    return restored
end

local function set_first_available_field(obj, names, value)
    if value == nil or value == JSON_NULL then return true, nil end
    local last_err = nil
    for _, name in ipairs(names or {}) do
        if safe_get_field(obj, name) ~= nil then
            local ok, err = safe_set_field(obj, name, value)
            if ok then return true, name end
            last_err = err
        end
    end
    return false, last_err or "no compatible field"
end

local function call_reversal_setter(reversal_ctx, method_name, step, value)
    if value == nil or value == JSON_NULL then return true, nil end
    local ok, err = pcall(function()
        reversal_ctx.reversal_func:call(method_name, reversal_ctx.fighter_id, step.index, value)
    end)
    if ok then return true, nil end
    return false, tostring(err)
end

local function apply_reversal_plan(plan, reversal_ctx)
    if #plan == 0 then return 0, "legacy JSON: reversals skipped" end

    pcall(function() reversal_ctx.reversal_func:call("StopReversal") end)
    local current_group = nil
    local applied = 0
    local warnings = {}

    for _, step in ipairs(plan) do
        if current_group ~= step.group.type then
            local changed, change_err = pcall(function()
                reversal_ctx.reversal_func:call("ChangeReversalType", step.group.type)
            end)
            if not changed then
                warnings[#warnings + 1] = "ChangeReversalType(" .. tostring(step.group.type)
                    .. ") failed: " .. tostring(change_err)
            end
            current_group = step.group.type
        end

        for field_name, value in pairs(step.fields) do
            local ok, err = safe_set_field(step.target, field_name, value)
            if not ok then
                return nil, step.group.key .. " reversal slot " .. tostring(step.slot)
                    .. " raw field " .. tostring(field_name) .. " failed: " .. tostring(err)
            end
        end

        local type_ok, type_err = set_first_available_field(
            step.target, REVERSAL_FIELDS.type, step.type)
        if not type_ok then
            return nil, step.group.key .. " reversal slot " .. tostring(step.slot)
                .. " type failed: " .. tostring(type_err)
        end

        local skill_ok, skill_err = set_first_available_field(
            step.target, REVERSAL_FIELDS.skill_index, step.skill_index)
        if not skill_ok then
            return nil, step.group.key .. " reversal slot " .. tostring(step.slot)
                .. " skill_index failed: " .. tostring(skill_err)
        end

        local canonical_fields = {
            { key = "active", value = step.active, method = "SetReversalActive" },
            { key = "delay_frame", value = step.delay_frame, method = "SetReversalDelayFrame" },
            { key = "count", value = step.count, method = "SetReversalCount" },
            { key = "meaty_frame", value = step.meaty_frame, method = "SetReversalMeatyFrame" },
        }
        for _, canonical in ipairs(canonical_fields) do
            if canonical.value ~= nil and canonical.value ~= JSON_NULL then
                local field_ok, field_err = set_first_available_field(
                    step.target, REVERSAL_FIELDS[canonical.key], canonical.value)
                local method_ok, method_err = call_reversal_setter(
                    reversal_ctx, canonical.method, step, canonical.value)
                if not field_ok and not method_ok then
                    return nil, step.group.key .. " reversal slot " .. tostring(step.slot)
                        .. " " .. canonical.key .. " failed: field=" .. tostring(field_err)
                        .. " method=" .. tostring(method_err)
                end
            end
        end

        local stored, store_err = set_collection_item(step.collection, step.index, step.target)
        if not stored then
            return nil, step.group.key .. " reversal slot " .. tostring(step.slot)
                .. " write-back failed: " .. tostring(store_err)
        end
        applied = applied + 1
    end

    if reversal_ctx.original_type ~= nil then
        local restored, restore_err = pcall(function()
            reversal_ctx.reversal_func:call("ChangeReversalType", reversal_ctx.original_type)
        end)
        if not restored then
            warnings[#warnings + 1] = "restore ReversalType failed: " .. tostring(restore_err)
        end
    end

    return applied, #warnings > 0 and table.concat(warnings, " | ") or "reversal setters applied"
end

local function force_apply(rec_func)
    if not rec_func then return true, "No RecordFunc" end
    local ok, err = pcall(function() rec_func:call("ForceApply") end)
    if ok then return true, "ForceApply OK" end
    return false, tostring(err)
end

local function build_clear_record_plan(slots)
    local plan = {}
    for index = 0, SLOT_COUNT - 1 do
        local slot_obj = get_collection_item(slots, index)
        if not slot_obj then
            return nil, "record slot " .. tostring(index + 1) .. " is missing in game data"
        end
        plan[#plan + 1] = {
            kind = "clear",
            slot = index + 1,
            slot_obj = slot_obj,
            input_data = slot_obj:get_field("InputData"),
            weight = 1,
            fields = {},
            input_fields = {},
        }
    end
    return plan, nil
end

local function build_clear_reversal_plan(reversal_ctx)
    local plan = {}
    for _, definition in ipairs(REVERSAL_GROUPS) do
        local collection = reversal_ctx.groups[definition.key]
        for index = 0, REVERSAL_SLOT_COUNT - 1 do
            local target = get_collection_item(collection, index)
            if not target then
                return nil, definition.key .. " reversal slot "
                    .. tostring(index + 1) .. " is missing in game data"
            end
            plan[#plan + 1] = {
                group = definition,
                slot = index + 1,
                index = index,
                collection = collection,
                target = target,
                active = false,
                type = -1,
                skill_index = -1,
                delay_frame = 0,
                count = 1,
                meaty_frame = 0,
                fields = {
                    IsActive = false,
                    IsValid = false,
                    IsFrame = false,
                    Type = -1,
                    Delay = 0,
                    Count = 1,
                    SkillIndex = -1,
                    Level = 0,
                    Frame = 0,
                },
            }
        end
    end
    return plan, nil
end

function M.clear_current_configuration()
    ensure_dirs()

    local backup_ok, backup_msg, backup_path = M.backup_current()
    if not backup_ok then
        return false, "清空已取消：自动备份失败：" .. tostring(backup_msg)
    end

    local slots, slots_err, ctx, rec_func = get_current_slots()
    if not slots then
        return false, "清空已取消，备份已保留：" .. tostring(slots_err), backup_path
    end

    local reversal_ctx, reversal_err = get_reversal_context(ctx.fighter_id)
    if not reversal_ctx then
        return false, "清空已取消，备份已保留：" .. tostring(reversal_err), backup_path
    end

    local record_plan, record_plan_err = build_clear_record_plan(slots)
    if not record_plan then
        return false, "清空已取消，备份已保留：" .. tostring(record_plan_err), backup_path
    end

    local reversal_plan, reversal_plan_err = build_clear_reversal_plan(reversal_ctx)
    if not reversal_plan then
        return false, "清空已取消，备份已保留：" .. tostring(reversal_plan_err), backup_path
    end

    local ok, record_count_or_err, reversal_count_or_nil, reversal_msg_or_nil = pcall(function()
        local _, record_count = apply_import_plan(record_plan)
        local reversal_count, reversal_msg = apply_reversal_plan(reversal_plan, reversal_ctx)
        if reversal_count == nil then error(reversal_msg) end
        return record_count, reversal_count, reversal_msg
    end)
    if not ok then
        return false, "清空失败，自动备份已保留：" .. tostring(record_count_or_err), backup_path
    end

    local force_ok, force_msg = force_apply(rec_func)
    local result = "已清空 " .. tostring(record_count_or_err or 0)
        .. " 个录像槽和 " .. tostring(reversal_count_or_nil or 0)
        .. " 个反击槽。自动备份：data/" .. tostring(backup_path)
        .. "。" .. tostring(reversal_msg_or_nil or "")
    if not force_ok then
        result = result .. "。ForceApply 失败：" .. tostring(force_msg)
    end
    M._annotations = empty_annotations()
    return true, result, backup_path
end

function M.import_from_file(path, options)
    ensure_dirs()
    options = options or {}

    local data = json.load_file(path or M.IMPORT_PATH)
    if not data then return false, "Import file not found: data/" .. (path or M.IMPORT_PATH) end

    local header_ok, header_err = validate_import_header(data, options)
    if not header_ok then return false, "Import rejected: " .. tostring(header_err) end

    local backup_ok, backup_msg, backup_path = M.backup_current()
    if not backup_ok then return false, "Backup failed before import: " .. tostring(backup_msg) end

    local slots, slots_err, _, rec_func, record_ctx = get_current_slots()
    if not slots then return false, "Import aborted after backup. " .. tostring(slots_err) end

    local plan, plan_errors = build_import_plan(data, slots, options)
    if not plan then
        return false, "Import aborted after backup. " .. table.concat(plan_errors, " | "), backup_path
    end
    local record_settings_plan = build_record_settings_plan(data, record_ctx)


    local reversal_ctx = nil
    if data.schema ~= M.LEGACY_SCHEMA then
        local reversal_err
        reversal_ctx, reversal_err = get_reversal_context(M.get_context().fighter_id)
        if not reversal_ctx then
            return false, "Import aborted after backup. " .. tostring(reversal_err), backup_path
        end
    end

    local reversal_plan, reversal_plan_errors = build_reversal_import_plan(data, reversal_ctx)
    if not reversal_plan then
        return false, "Import aborted after backup. "
            .. table.concat(reversal_plan_errors, " | "), backup_path
    end

    local ok, write_result_or_err, clear_count_or_nil, reversal_count_or_nil,
        reversal_msg_or_nil, record_setting_count_or_nil = pcall(function()
        local record_setting_count = apply_record_settings_plan(record_settings_plan)
        local written, cleared = apply_import_plan(plan)
        local reversal_count, reversal_msg = apply_reversal_plan(reversal_plan, reversal_ctx)
        if reversal_count == nil then error(reversal_msg) end
        return written, cleared, reversal_count, reversal_msg, record_setting_count
    end)
    if not ok then
        return false, "Import crashed after backup: " .. tostring(write_result_or_err), backup_path
    end

    local written = write_result_or_err or 0
    local cleared = clear_count_or_nil or 0
    local reversal_count = reversal_count_or_nil or 0
    local reversal_msg = reversal_msg_or_nil or "reversals skipped"
    local record_setting_count = record_setting_count_or_nil or 0
    local force_msg = "ForceApply skipped"
    if options.force_apply_after_import == true then
        local force_ok, force_err = force_apply(rec_func)
        force_msg = force_ok and "ForceApply OK" or ("ForceApply failed: " .. tostring(force_err))
    end
    M._annotations = normalize_annotations(data.annotations)

    return true,
        "Imported " .. tostring(written) .. " slot(s), cleared " .. tostring(cleared)
            .. ", restored " .. tostring(record_setting_count) .. " record setting field(s)"
            .. ", restored " .. tostring(reversal_count) .. " reversal setting(s)"
            .. ". Backup: data/" .. tostring(backup_path) .. ". " .. force_msg
            .. ". " .. tostring(reversal_msg),
        backup_path,
        type(data.description) == "string" and data.description or ""
end

local function normalize_glob_path(path)
    if type(path) ~= "string" then return nil end
    local normalized = path:gsub("\\", "/")
    local data_prefix = "/data/"
    local prefix_pos = normalized:find(data_prefix, 1, true)
    if prefix_pos then
        normalized = normalized:sub(prefix_pos + #data_prefix)
    end
    normalized = normalized:gsub("^data/", "")
    return normalized
end

write_latest_backup_marker = function(path, timestamp)
    if type(path) ~= "string" or path == "" then return false, "empty backup path" end
    ensure_dirs()

    local normalized = normalize_glob_path(path)
    if not normalized or normalized == "" then return false, "invalid backup path" end

    M._last_backup_path = normalized
    local marker = {
        path = "data/" .. normalized,
        created_at = timestamp or now_stamp(),
    }

    local ok, write_result = pcall(json.dump_file, M.LATEST_BACKUP_PATH, marker)
    if not ok then return false, tostring(write_result) end
    if write_result == false then return false, "json.dump_file returned false" end
    return true, nil
end

local function try_read_backup_path(path, attempted, label)
    local normalized = normalize_glob_path(path)
    if not normalized or normalized == "" then
        attempted[#attempted + 1] = label .. ": empty path"
        return nil
    end

    local ok, data = pcall(json.load_file, normalized)
    if ok and data then return normalized end

    attempted[#attempted + 1] = label .. ": data/" .. normalized
        .. (ok and " unreadable" or (" error=" .. tostring(data)))
    return nil
end

local function read_latest_backup_marker(attempted)
    local ok, marker = pcall(json.load_file, M.LATEST_BACKUP_PATH)
    if not ok then
        attempted[#attempted + 1] = "marker: data/" .. M.LATEST_BACKUP_PATH
            .. " error=" .. tostring(marker)
        return nil
    end

    if type(marker) ~= "table" then
        attempted[#attempted + 1] = "marker: data/" .. M.LATEST_BACKUP_PATH .. " unreadable"
        return nil
    end

    return try_read_backup_path(marker.path, attempted, "marker.path")
end

function M.find_latest_backup()
    local attempted = {}

    if M._last_backup_path then
        local latest = try_read_backup_path(M._last_backup_path, attempted, "memory")
        if latest then return latest, nil end
    else
        attempted[#attempted + 1] = "memory: empty"
    end

    local marker_latest = read_latest_backup_marker(attempted)
    if marker_latest then return marker_latest, nil end

    if not fs or not fs.glob then
        attempted[#attempted + 1] = "glob: fs.glob unavailable"
        return nil, "No backup found. Tried: " .. table.concat(attempted, " | ")
    end

    local files, patterns = glob_data_directory(M.BACKUP_DIR, "records_backup_.*json")
    local pattern = table.concat(patterns, " OR ")

    local candidates = {}
    for _, path in ipairs(files) do
        local normalized = normalize_glob_path(path)
        local filename = normalized and normalized:match("([^/]+)$") or nil
        if filename and filename:match("^records_backup_%d%d%d%d%d%d%d%d_%d%d%d%d%d%d_?%d*%.json$") then
            candidates[#candidates + 1] = normalized
        end
    end

    table.sort(candidates)

    for index = #candidates, 1, -1 do
        local latest = try_read_backup_path(candidates[index], attempted, "glob")
        if latest then return latest, nil end
    end

    if #candidates == 0 then
        attempted[#attempted + 1] = "glob: " .. pattern .. " matched no backup files"
    end

    return nil, "No backup found. Tried: " .. table.concat(attempted, " | ")
end

function M.restore_latest_backup(options)
    local latest, err = M.find_latest_backup()
    if not latest then return false, err end
    local ok, msg, backup_path = M.import_from_file(latest, options)
    if not ok then return false, msg, backup_path end
    return true, "Restored from data/" .. latest .. ". " .. msg, backup_path
end

function M.paths_for_display()
    return {
        configs = "data/" .. M.CONFIG_DIR,
        backups = "data/" .. M.BACKUP_DIR,
        editor = "data/" .. M.EDITOR_PATH,
        legacy = "data/" .. M.LEGACY_EXPORT_PATH,
        config_glob = table.concat(M._last_config_glob_patterns or {}, " OR "),
        config_glob_count = M._last_config_glob_count or 0,
    }
end

return M
