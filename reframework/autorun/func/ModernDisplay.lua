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
-- cdjay's v9 modern_display strings use Chinese button-strength tokens; map them
-- to universal FGC notation (L/M/H) so the Western UI reads cleanly. Chinese
-- byte sequences contain no Lua-pattern magic chars, so literal gsub is safe.
local MODERN_TOKENS = {
    ["任意键"] = "any",   -- any button
    ["弱"] = "L",         -- light
    ["中"] = "M",         -- medium
    ["强"] = "H",         -- heavy
}
local function translate_modern(s)
    for zh, en in pairs(MODERN_TOKENS) do s = s:gsub(zh, en) end
    return s
end

function M.get_motion(char_name, step)
    if type(step) ~= "table" then return nil end
    local map = M.load(char_name)
    if not map then return nil end
    local entry = map[tostring(step.id or "")]
    if type(entry) ~= "table" then return nil end
    local md = entry.modern_display
    if type(md) == "string" and md ~= "" then return translate_modern(md) end
    return nil
end

function M.clear_cache() cache = {} end

return M
