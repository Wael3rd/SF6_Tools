local json = json

-- Unified xt.command_display.v1 reader (cdjay's ac_bcm export). When a
-- character has a command_display/ catalog it supersedes the legacy
-- bcm_catalog/ file below for classic notation; the old format stays as a
-- fallback for anything not yet migrated.
local CommandDisplay = require("func/ComboTrials/CommandDisplay")

local BcmCatalog = {
    name = "ComboTrials.BcmCatalog"
}

local CATALOG_DIR = "TrainingComboTrials_data/bcm_catalog/"
local EXPECTED_SCHEMAS = {
    ["sf6cc.bcm-runtime.v1"] = true,
    ["sf6cc.action-runtime.v1"] = true,
    ["sf6cc.action-runtime.v2"] = true
}
local cache = {}

local function safe_character_name(character_name)
    return tostring(character_name or ""):gsub("[^%w_]", "")
end

function BcmCatalog.get_filename(character_name)
    return CATALOG_DIR .. safe_character_name(character_name) .. ".json"
end

function BcmCatalog.load_for_character(character_name)
    local key = safe_character_name(character_name)
    if key == "" or key == "Unknown" then return nil end
    if cache[key] ~= nil then return cache[key] ~= false and cache[key] or nil end

    -- Prefer the unified command_display catalog (slim map, carries _slim=true).
    local unified = CommandDisplay.load_for_character(key)
    if type(unified) == "table" then
        cache[key] = unified
        return unified
    end

    local ok, loaded = pcall(json.load_file, BcmCatalog.get_filename(key))
    if not ok or type(loaded) ~= "table" or not EXPECTED_SCHEMAS[loaded.schema] or type(loaded.actions) ~= "table" then
        cache[key] = false
        return nil
    end
    if loaded.character and safe_character_name(loaded.character) ~= key then
        cache[key] = false
        return nil
    end
    cache[key] = loaded
    return loaded
end

function BcmCatalog.get_classic_display(catalog, action_id)
    -- Unified slim map: delegate to the vendored resolver.
    if type(catalog) == "table" and catalog._slim == true then
        local disp = CommandDisplay.get_command_display(catalog, action_id, "classic")
        if type(disp) == "string" and disp ~= "" then return disp end
        return nil
    end
    if type(catalog) ~= "table" or type(catalog.actions) ~= "table" then return nil end
    local id = tostring(action_id)
    local display = catalog.actions[id]
    if type(display) == "string" and display ~= "" then return display end
    local aliases = catalog.aliases
    local visited = {}
    while type(aliases) == "table" and aliases[id] ~= nil and not visited[id] do
        visited[id] = true
        id = tostring(aliases[id])
        display = catalog.actions[id]
        if type(display) == "string" and display ~= "" then return display end
    end
    return nil
end

-- Returns true when `actual_action_id` is an AC-derived runtime replacement
-- for `target_action_id`.  The compiled catalog owns this relationship, so
-- character exception files do not need to repeat Type-29 branch aliases.
function BcmCatalog.is_alias_for(catalog, actual_action_id, target_action_id)
    if type(catalog) ~= "table" or type(catalog.aliases) ~= "table" then return false end
    local id = tostring(actual_action_id)
    local target = tostring(target_action_id)
    local visited = {}
    while catalog.aliases[id] ~= nil and not visited[id] do
        visited[id] = true
        id = tostring(catalog.aliases[id])
        if id == target then return true end
    end
    return false
end

function BcmCatalog.clear_cache(character_name)
    if character_name then cache[safe_character_name(character_name)] = nil else cache = {} end
end

return BcmCatalog
