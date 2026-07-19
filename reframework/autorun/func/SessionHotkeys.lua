-- =========================================================
-- SessionHotkeys.lua - Shared hotkey scope for the timer/trials session
-- modules (Hit Confirm, Reactions, Post Guard). They expose the same four
-- actions and are mutually exclusive, so they share ONE scope: the action
-- dispatches to whichever module owns the current training mode.
-- Registered once (module is require-cached); each module registers its
-- command set for its mode. Disabled and unbound by default.
-- =========================================================

local M = {}
local i18n = require("func/i18n")
local RuntimeSafety = require("func/RuntimeSafety")

i18n.register("hk_session", {
    en = {
        title = "HIT CONFIRM|REACTION|POST GUARD",
        decrease_amount = "Decrease Session Amount", increase_amount = "Increase Session Amount",
        reset_or_stop = "Reset / Stop Session", start_or_pause = "Start / Pause Session",
        open_recording_list = "Open Recording List (Reactions)",
    },
    zh = {
        title = "确认 | 反应 | 格挡后",
        decrease_amount = "减少本次训练量", increase_amount = "增加本次训练量",
        reset_or_stop = "重置 / 停止训练", start_or_pause = "开始 / 暂停训练",
        open_recording_list = "打开录像列表（反应）",
    },
})
local function T(k) return i18n.t("hk_session", k) end

-- mode (int) -> { decrease_amount, increase_amount, reset_or_stop, start_or_pause }
local by_mode = {}
local registered = false

local function active_commands()
    return by_mode[_G.CurrentTrainerMode or 0]
end

local function can_use_session()
    if RuntimeSafety and RuntimeSafety.is_training_allowed and not RuntimeSafety.is_training_allowed() then return false end
    return active_commands() ~= nil
end

local function run(name)
    local c = active_commands()
    if c and c[name] then c[name]() end
end

-- Enabled only when the active mode actually provides the command (e.g.
-- open_recording_list exists only in Reactions).
local function can_run(name)
    return function()
        if not can_use_session() then return false end
        local c = active_commands()
        return c ~= nil and c[name] ~= nil
    end
end

-- Registers one module's commands for its training mode and, on first call,
-- registers the shared scope into the framework.
function M.register_module(mode, commands, Hotkeys)
    if type(mode) ~= "number" or type(commands) ~= "table" then return false end
    by_mode[mode] = commands

    if not registered and Hotkeys and Hotkeys.register_scope then
        registered = true
        local function lbl(k) return function() return T(k) end end
        Hotkeys.register_scope("session", {
            title = function() return T("title") end,
            order = 10,
            enabled_default = false,
            actions = {
                { id = "decrease_amount", label = lbl("decrease_amount"), enabled = can_use_session, run = function() run("decrease_amount") end },
                { id = "increase_amount", label = lbl("increase_amount"), enabled = can_use_session, run = function() run("increase_amount") end },
                { id = "reset_or_stop",   label = lbl("reset_or_stop"),   enabled = can_use_session, run = function() run("reset_or_stop") end },
                { id = "start_or_pause",  label = lbl("start_or_pause"),  enabled = can_use_session, run = function() run("start_or_pause") end },
                { id = "open_recording_list", label = lbl("open_recording_list"), enabled = can_run("open_recording_list"), run = function() run("open_recording_list") end },
            },
        })
    end
    return true
end

return M
