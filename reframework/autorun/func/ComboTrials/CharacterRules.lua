local json = json

local CharacterRules = {
    name = "ComboTrials.CharacterRules"
}

local EXCEPTION_DIR = "TrainingComboTrials_data/exceptions"
local COMMON_EXCEPTIONS_FILE = EXCEPTION_DIR .. "/Common.json"

function CharacterRules.get_exception_filename(character_name)
    return EXCEPTION_DIR .. "/" .. tostring(character_name or ""):gsub("[^%w_]", "") .. ".json"
end

function CharacterRules.load_common()
    local common_exceptions = {}
    pcall(function()
        local loaded = _G.safe_load_json(COMMON_EXCEPTIONS_FILE)
        if loaded then common_exceptions = loaded end
    end)
    return common_exceptions
end

function CharacterRules.load_for_character(character_name)
    local loaded = json.load_file(CharacterRules.get_exception_filename(character_name))
    if loaded then return loaded end
    return {}
end

function CharacterRules.get_exception(character_rules, common_rules, action_id)
    local id = tostring(action_id)
    local character_exception = character_rules and character_rules[id] or nil
    local common_exception = common_rules and common_rules[id] or nil
    return character_exception or common_exception, character_exception, common_exception
end

function CharacterRules.has_character_exception(character_rules, action_id)
    return character_rules and character_rules[tostring(action_id)] and true or false
end

function CharacterRules.is_action_required(exception)
    if type(exception) ~= "table" then return false end
    return exception.action_required == true
        or exception.no_combo_auto_advance == true
        or exception.require_absorb == true
end

local function absorb_requires_combo(exception)
    if type(exception) ~= "table" then return true end
    if exception.absorb_requires_combo == false then return false end
    return not CharacterRules.is_action_required(exception)
end

local function parse_absorb_ids(exception)
    if not exception or type(exception.absorb_ids) ~= "string" or exception.absorb_ids == "" then
        return nil
    end

    local ids = {}
    for absorb_str in string.gmatch(exception.absorb_ids, "([^,]+)") do
        local absorb_num = tonumber(absorb_str:match("^%s*(.-)%s*$"))
        if absorb_num then ids[absorb_num] = true end
    end
    return ids
end

-- When a BCM catalog is active (strict BCM mode), an install/absorb move is
-- confirmed by walking the catalog's alias chain: actual_id resolves to
-- expected_id.  Same relationship BcmCatalog.is_alias_for owns for display —
-- kept local here to avoid a require cycle (SF6_TOOLS_CC).
local function catalog_absorbs_action(catalog, expected_id, actual_id)
    if type(catalog) ~= "table" or type(catalog.aliases) ~= "table" then return false end
    local id = tostring(actual_id)
    local target = tostring(expected_id)
    local visited = {}
    while catalog.aliases[id] ~= nil and not visited[id] do
        visited[id] = true
        id = tostring(catalog.aliases[id])
        if id == target then return true end
    end
    return false
end

function CharacterRules.find_recent_absorb_confirmation(character_rules, common_rules, expected, recent_inputs, character_name, catalog)
    if not expected then return { matched = false, block_reason = "missing_expected" } end

    local exception = CharacterRules.get_exception(character_rules, common_rules, expected.id)
    local absorb_ids = parse_absorb_ids(exception)
    -- No early-out on missing absorb_ids: the catalog alias chain can still
    -- confirm an install move even when no exception declares absorb_ids.
    local is_honda = character_name == "EHonda" or character_name == "Honda"

    local expected_combo = tonumber(expected.expected_combo)
    if expected_combo == nil then return { matched = false, block_reason = "missing_expected_combo" } end

    for i = 1, math.min(10, #(recent_inputs or {})) do
        local recent = recent_inputs[i]
        local recent_id = recent and tonumber(recent.id)
        local is_exception_absorb = recent_id and absorb_ids and absorb_ids[recent_id]
        local is_catalog_alias = recent_id and catalog_absorbs_action(catalog, expected.id, recent_id)
        if is_exception_absorb or is_catalog_alias then
            local match_reason = is_catalog_alias and "catalog_alias_recent_absorb"
                or (is_honda and "ehonda_recent_absorb" or "exception_recent_absorb")
            local combo_count = tonumber(recent.combo_count) or 0
            local combo_ok = (not absorb_requires_combo(exception)) or combo_count >= expected_combo
            if combo_ok then
                return {
                    matched = true,
                    actual_action_id = recent_id,
                    match_reason = match_reason,
                    recent_index = i,
                    combo_count = combo_count,
                    start_frame = recent.start_frame,
                    action_instance = recent.action_instance,
                    motion = recent.motion,
                    real_input = recent.real_input,
                    intentional = recent.intentional,
                    expected_id = expected.id,
                    expected_combo = expected_combo,
                    absorb_ids = exception and exception.absorb_ids or nil,
                    source = is_catalog_alias and "catalog_alias" or "exception",
                    ignore_combo_check = not absorb_requires_combo(exception)
                }
            end
            return {
                matched = false,
                block_reason = "combo_not_reached",
                actual_action_id = recent_id,
                recent_index = i,
                combo_count = combo_count,
                expected_combo = expected_combo,
                absorb_ids = exception and exception.absorb_ids or nil
            }
        end
    end

    return { matched = false, block_reason = "absorb_id_not_recent", absorb_ids = exception and exception.absorb_ids or nil }
end

function CharacterRules.match_current_absorb_confirmation(character_rules, common_rules, expected, action_id, combo_count, character_name, catalog)
    if not expected then return { matched = false, block_reason = "missing_expected" } end

    local exception = CharacterRules.get_exception(character_rules, common_rules, expected.id)
    local absorb_ids = parse_absorb_ids(exception)
    local is_honda = character_name == "EHonda" or character_name == "Honda"

    local current_id = tonumber(action_id)
    local is_exception_absorb = current_id and absorb_ids and absorb_ids[current_id]
    local is_catalog_alias = current_id and catalog_absorbs_action(catalog, expected.id, current_id)
    if not current_id or (not is_exception_absorb and not is_catalog_alias) then
        return { matched = false, block_reason = "current_id_not_absorbed", absorb_ids = exception and exception.absorb_ids or nil }
    end
    local match_reason = is_catalog_alias and "catalog_alias_current_absorb"
        or (is_honda and "ehonda_current_absorb" or "exception_current_absorb")

    local expected_combo = tonumber(expected.expected_combo)
    if expected_combo == nil then return { matched = false, block_reason = "missing_expected_combo" } end

    local current_combo = tonumber(combo_count) or 0
    local combo_ok = (not absorb_requires_combo(exception)) or current_combo >= expected_combo
    if not combo_ok then
        return {
            matched = false,
            block_reason = "combo_not_reached",
            actual_action_id = current_id,
            combo_count = current_combo,
            expected_combo = expected_combo,
            absorb_ids = exception and exception.absorb_ids or nil
        }
    end

    return {
        matched = true,
        actual_action_id = current_id,
        match_reason = match_reason,
        combo_count = current_combo,
        expected_id = expected.id,
        expected_combo = expected_combo,
        absorb_ids = exception and exception.absorb_ids or nil,
        source = is_catalog_alias and "catalog_alias" or "current_non_intentional_absorb",
        motion = "Unknown",
        real_input = "None",
        ignore_combo_check = not absorb_requires_combo(exception)
    }
end

function CharacterRules.apply_runtime_overrides(character_name, action_id, exception, log)
    if character_name == "Cammy" and (action_id == 908 or action_id == 922) then
        if #log > 0 and (log[1].id == 652 or log[1].id == 653 or log[1].id == 926) then
            if not exception then exception = {} end
            exception.force = true
            if action_id == 908 then
                exception.override_name = "236+HK"
            elseif action_id == 922 then
                exception.override_name = "623+HK"
            end
        end
    end
    return exception
end

return CharacterRules
