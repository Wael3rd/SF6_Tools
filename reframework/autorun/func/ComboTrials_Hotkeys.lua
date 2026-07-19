-- =========================================================
-- ComboTrials_Hotkeys.lua - Action registration for combo trials.
-- Registers a scope into the shared Training_Hotkeys framework.
-- Disabled and unbound by default. Labels toggle EN/中文 via i18n.
-- =========================================================

local M = {}
local RuntimeSafety = require("func/RuntimeSafety")
local i18n = require("func/i18n")

i18n.register("hk_combo_trials", {
    en = {
        title = "Combo Trials",
        -- Contextual slot base names (live action appended in the menu)
        slot_1 = "Slot 1", slot_2 = "Slot 2", slot_3 = "Slot 3", slot_4 = "Slot 4",
        slot_open = "Open Combo File List",
        slot_idle = "—",
        nav_up = "Menu Up", nav_down = "Menu Down", menu_select = "Select",
        -- Sub-action names used to build the live slot label
        record_p1 = "Record P1", record_p2 = "Record P2",
        save_recording = "Stop & Save", cancel_recording = "Cancel",
        start_trial = "Start Trial", reset_trial = "Reset Trial", stop_trial = "Stop Trial",
        start_demo = "Auto Demo", restart_demo = "Restart Demo", quit_demo = "Quit Demo",
        switch_position = "Cycle Position",
    },
    zh = {
        title = "连段训练",
        slot_1 = "槽位 1", slot_2 = "槽位 2", slot_3 = "槽位 3", slot_4 = "槽位 4",
        slot_open = "打开连段文件列表",
        slot_idle = "—",
        nav_up = "菜单上", nav_down = "菜单下", menu_select = "选择",
        record_p1 = "录制 P1", record_p2 = "录制 P2",
        save_recording = "停止并保存", cancel_recording = "取消",
        start_trial = "开始连段训练", reset_trial = "重置连段", stop_trial = "停止连段训练",
        start_demo = "自动演示连段", restart_demo = "重播演示", quit_demo = "退出演示",
        switch_position = "切换位置",
    },
})
local function T(k) return i18n.t("hk_combo_trials", k) end

local function can_use_combo_trials()
    if RuntimeSafety and RuntimeSafety.is_training_allowed and not RuntimeSafety.is_training_allowed() then return false end
    if _G.CurrentTrainerMode ~= 4 then return false end
    if _G._ct_bar_collapsed then return false end
    return true
end

-- Maps ct_context() state -> the sub-action i18n key the slot fires there.
-- The "dropdown" state (combo file list open) repurposes slot 2/4 for menu
-- navigation, matching the legacy FUNC+D-PAD behaviour.
local SLOT_CONTEXT = {
    slot_1 = { demo = "restart_demo", recording = "save_recording", playing = "reset_trial", replay_idle = "record_p1", idle = "record_p1" },
    slot_2 = { dropdown = "nav_up", demo = "quit_demo", recording = "cancel_recording", playing = "stop_trial", replay_idle = "record_p2", idle = "start_trial" },
    slot_3 = { playing = "switch_position", idle = "switch_position" },
    slot_4 = { dropdown = "nav_down", playing = "start_demo" },
}

-- Current combo-trials context, derived from live state the module exposes on
-- ctx. Drives both slot dispatch and the live bindings-menu label. All hotkey
-- logic lives here, not in the main module.
local function ct_context(ctx)
    -- Combo file list open: slots switch to menu navigation.
    if _G.ComboTrials_DropdownOpen then return "dropdown" end
    local ds, ts = ctx.demo_state, ctx.trial_state
    if ds and ds.is_playing then return "demo" end
    if ts and ts.is_recording then return "recording" end
    if ts and ts.is_playing then return "playing" end
    if _G.IsInReplay or _G.IsInBattleHub then return "replay_idle" end
    return "idle"
end

-- Each slot fires the primitive command valid in the current context,
-- reproducing the legacy single-button-per-slot behaviour. When the combo
-- file list is open, slot 2/4 navigate and the Open key confirms.
local function build_slots(commands, ctx)
    local function ctxt() return ct_context(ctx) end
    local function run(name) if commands[name] then commands[name]() end end
    return {
        slot_1 = function()
            local c = ctxt()
            if     c == "dropdown"  then return  -- inert during menu nav
            elseif c == "demo"      then run("restart_demo")
            elseif c == "recording" then run("save_recording")
            elseif c == "playing"   then run("reset_trial")
            else                         run("record_p1") end  -- idle / replay_idle
        end,
        slot_2 = function()
            local c = ctxt()
            if     c == "dropdown"    then _G.ComboTrials_DropdownNavUp = true
            elseif c == "demo"        then run("quit_demo")
            elseif c == "recording"   then run("cancel_recording")
            elseif c == "playing"     then run("stop_trial")
            elseif c == "replay_idle" then run("record_p2")
            else                           run("start_trial") end  -- idle
        end,
        slot_3 = function()
            local c = ctxt()
            if c == "playing" or c == "idle" then run("switch_position") end
        end,
        slot_4 = function()
            local c = ctxt()
            if     c == "dropdown" then _G.ComboTrials_DropdownNavDown = true
            elseif c == "playing"  then run("start_demo") end
        end,
        -- Open key: opens the list, or confirms the highlight when already open.
        slot_open = function()
            if _G.ComboTrials_DropdownOpen then
                _G.ComboTrials_DropdownSelect = true
            else
                run("open_combo_dropdown")
            end
        end,
    }
end

function M.init(ctx, Hotkeys)
    if not Hotkeys or not Hotkeys.register_scope then return false end
    local commands = ctx.commands or {}
    local slots = build_slots(commands, ctx)

    -- Live slot label: "Slot N: <action valid in the current context>".
    -- Shown in the bindings menu so the user sees what the key does right now.
    local function slot_label(slot_key)
        local map = SLOT_CONTEXT[slot_key]
        return function()
            local c = ct_context(ctx)
            local akey = map[c]
            if akey then return T(slot_key) .. ": " .. T(akey) end
            return T(slot_key) .. ": " .. T("slot_idle")
        end
    end

    -- Open key label: "Select" while the list is open, else "Open Combo File List".
    local function open_label()
        if _G.ComboTrials_DropdownOpen then
            return T("slot_open") .. ": " .. T("menu_select")
        end
        return T("slot_open")
    end

    Hotkeys.register_scope("combo_trials", {
        title = function() return T("title") end,
        order = 20,
        enabled_default = false,
        actions = {
            { id = "slot_1", label = slot_label("slot_1"), enabled = can_use_combo_trials, run = slots.slot_1 },
            { id = "slot_2", label = slot_label("slot_2"), enabled = can_use_combo_trials, run = slots.slot_2 },
            { id = "slot_3", label = slot_label("slot_3"), enabled = can_use_combo_trials, run = slots.slot_3 },
            { id = "slot_4", label = slot_label("slot_4"), enabled = can_use_combo_trials, run = slots.slot_4 },
            { id = "open_combo_dropdown", label = open_label, enabled = can_use_combo_trials, run = slots.slot_open },
        },
    })
    return true
end

return M
