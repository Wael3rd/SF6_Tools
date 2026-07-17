-- =========================================================
-- ModernDisplay.lua - Modern-control notation lookup for combo steps.
-- Loads per-character mapping data (data/TrainingComboTrials_data/
-- modern_display/<Char>.json), caches it, and resolves a step's Modern
-- notation from its action id. Data shared with SF6_TOOLS_CC
-- (schema xt.modern_display.v1).
-- =========================================================

local json = json

local M = {}
local DIR = "TrainingComboTrials_data/modern_display/"
local cache = {}  -- char_name -> map table | false (not found)

-- Loads and caches the mapping for a character. Returns the map or nil.
function M.load(char_name)
    if not char_name or char_name == "" or char_name == "Unknown" then return nil end
    local hit = cache[char_name]
    if hit ~= nil then return hit ~= false and hit or nil end
    local loaded = nil
    pcall(function() loaded = json.load_file(DIR .. char_name .. ".json") end)
    if type(loaded) == "table" then
        cache[char_name] = loaded
        return loaded
    end
    cache[char_name] = false
    return nil
end

-- Extracts the character name from a combo file path
-- (.../CustomCombos/<Char>/<file>.json)
function M.char_from_path(path)
    if type(path) ~= "string" then return nil end
    return path:match("CustomCombos[/\\]([^/\\]+)[/\\]")
end

-- Returns the Modern-control notation for a step, or nil if none/absent.
function M.get_motion(char_name, step)
    if type(step) ~= "table" then return nil end
    local map = M.load(char_name)
    if not map then return nil end
    local entry = map[tostring(step.id or "")]
    if type(entry) ~= "table" then return nil end
    local md = entry.modern_display
    if type(md) == "string" and md ~= "" then return md end
    return nil
end

function M.clear_cache() cache = {} end

return M
