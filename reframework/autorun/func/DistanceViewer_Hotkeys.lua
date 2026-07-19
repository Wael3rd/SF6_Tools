-- =========================================================
-- DistanceViewer_Hotkeys.lua - Action registration for distance viewer.
-- Disabled and unbound by default. Labels toggle EN/中文 via i18n.
-- =========================================================

local M = {}
local RuntimeSafety = require("func/RuntimeSafety")
local i18n = require("func/i18n")

i18n.register("hk_distance_viewer", {
    en = {
        title = "Distance Viewer",
        cycle_p1 = "Cycle P1 Display", cycle_p2 = "Cycle P2 Display",
        toggle_window = "Toggle Overlay",
    },
    zh = {
        title = "距离查看器",
        cycle_p1 = "切换 P1 显示", cycle_p2 = "切换 P2 显示",
        toggle_window = "显示 / 隐藏设置窗口",
    },
})
local function T(k) return i18n.t("hk_distance_viewer", k) end

local function can_use_distance_viewer()
    -- Distance Viewer is a standalone overlay: its hotkeys work regardless of
    -- the selected trainer sub-mode (including "Disabled"), subject only to the
    -- runtime-safety gate.
    if RuntimeSafety and RuntimeSafety.is_training_allowed and not RuntimeSafety.is_training_allowed() then return false end
    return true
end

function M.init(commands, Hotkeys)
    if not Hotkeys or not Hotkeys.register_scope then return false end
    commands = commands or {}
    local function lbl(k) return function() return T(k) end end

    Hotkeys.register_scope("distance_viewer", {
        title = function() return T("title") end,
        order = 30,
        enabled_default = false,
        actions = {
            { id = "cycle_p1", label = lbl("cycle_p1"), enabled = can_use_distance_viewer, run = commands.cycle_p1 },
            { id = "cycle_p2", label = lbl("cycle_p2"), enabled = can_use_distance_viewer, run = commands.cycle_p2 },
            { id = "toggle_window", label = lbl("toggle_window"), enabled = can_use_distance_viewer, run = commands.toggle_window },
        },
    })
    return true
end

return M
