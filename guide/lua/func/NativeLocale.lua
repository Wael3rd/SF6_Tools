-- NativeLocale.lua -- strings of the native menus (colour editor, Drive Impact colour menu) in the GAME's language.
--
--   local L = require("func/NativeLocale")
--   L("root.save")                       -> "SAVE" / "ENREGISTRER" / "保存" ...
--   L("status.saved_as", "MC 3")         -> string.format on the localized template
--   L.lang()                             -> current code ("en", "fr", "ja", "zh-Hans" ...)
--
-- Source: data/SF6_ColorSpinExtra_data/locale.json ({ "<code>": { key = text } }); English is the fallback for a
-- missing language or key. The language is the game's text language (via.Language, re-read every ~1 s so an
-- Options change applies live). The text is drawn by the game's own font, so every game language has its glyphs.
-- Different from func/i18n.lua (EN/ZH toggle of the ImGui UI, chosen in our config): this one has no setting of
-- its own -- it simply follows the game.
local M = {}
local FILE = "SF6_ColorSpinExtra_data/locale.json"

-- via.Language enum (checked in-game 03/09): 0 Japanese 1 English 2 French 3 Italian 4 German 5 Spanish 6 Russian
-- 7 Polish 8 Dutch 9 Portuguese 10 PortugueseBr 11 Korean 12 TraditionalChinese 13 SimplifiedChinese ... 21 Arabic
-- ... 32 LatinAmericanSpanish. Read through via.SystemService.get_Language() (returned 2 in French).
local CODES = { [0] = "ja", [1] = "en", [2] = "fr", [3] = "it", [4] = "de", [5] = "es", [6] = "ru", [7] = "pl",
    [8] = "nl", [9] = "pt", [10] = "pt", [11] = "ko", [12] = "zh-Hant", [13] = "zh-Hans", [21] = "ar", [32] = "es-419" }
-- a language without its own block borrows a close one before English
local NEAR = { ["es-419"] = "es", ["zh-Hant"] = "zh-Hans", ["pt"] = "es" }

local tables = nil
local lang = "en"
local last_probe = -1000
local frame = 0

local function load_tables()
    local ok, data = pcall(json.load_file, FILE)
    tables = (ok and type(data) == "table") and data or {}
    if type(tables.en) ~= "table" then tables.en = {} end
end

-- the game's text language: via.SystemService.get_Language() (static, checked 03/09); keeps the last value on failure
local lang_m = nil
local function probe_lang()
    if lang_m == nil then
        local ok, td = pcall(sdk.find_type_definition, "via.SystemService")
        lang_m = (ok and td and td:get_method("get_Language")) or false
    end
    if not lang_m then return end
    local ok, v = pcall(lang_m.call, lang_m, nil)
    if ok and v ~= nil then
        local code = CODES[tonumber(tostring(v)) or -1]
        if code then lang = code end
    end
end

function M.lang()
    if not tables then load_tables() end
    return lang
end
function M.reload() load_tables() end
function M.set(code) lang = code end             -- manual override (tests); the probe overwrites it a second later

local function lookup(key)
    if not tables then load_tables() end
    local t = tables[lang]
    local v = t and t[key]
    if v == nil and NEAR[lang] then t = tables[NEAR[lang]]; v = t and t[key] end
    if v == nil then v = tables.en[key] end
    return v
end

local function L(key, ...)
    local v = lookup(key)
    if v == nil then return key end              -- missing everywhere: the key itself (visible = easy to spot)
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, v, ...)
        if ok then return s end
    end
    return v
end

-- keep the language in step with the game (Options -> Language), once a second
re.on_pre_application_entry("LateUpdateBehavior", function()
    frame = frame + 1
    if frame - last_probe >= 60 then last_probe = frame; pcall(probe_lang) end
end)
re.on_script_reset(function() tables = nil end)

setmetatable(M, { __call = function(_, key, ...) return L(key, ...) end })
M.get = L
_G.SF6_NativeLocale = M
return M
