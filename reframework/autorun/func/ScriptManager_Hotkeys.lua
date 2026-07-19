-- =========================================================
-- ScriptManager_Hotkeys.lua - Global training-mode switch action.
-- Registers a scope into the shared Training_Hotkeys framework.
-- Disabled and unbound by default. Labels toggle EN/中文 via i18n.
-- =========================================================

local M = {}
local i18n = require("func/i18n")

i18n.register("hk_script_manager", {
    en = { title = "Training Mode Switch", cycle_training_mode = "Cycle Training Mode" },
    zh = { title = "训练模式切换", cycle_training_mode = "切换训练模式" },
})
local function T(k) return i18n.t("hk_script_manager", k) end

function M.init(commands, Hotkeys)
    if not Hotkeys or not Hotkeys.register_scope then return false end
    commands = commands or {}
    local function lbl(k) return function() return T(k) end end

    Hotkeys.register_scope("script_manager", {
        title = function() return T("title") end,
        order = 5,
        enabled_default = false,
        actions = {
            -- No `enabled` gate: mode switching is valid from any mode.
            { id = "cycle_training_mode", label = lbl("cycle_training_mode"), run = commands.cycle_training_mode },
        },
    })
    return true
end

return M
