local M = {}
local sdk = sdk

local _allowed = false
local _can_inject = false
local _training_allowed = false
local _replay_allowed = false
local _frame = 0
local _disable_reason = nil

function M.begin_frame(flow_id, in_training, is_replay, is_battle_hub)
    _frame = _frame + 1
    _allowed = false
    _can_inject = false
    _training_allowed = false
    _replay_allowed = false
    _disable_reason = nil

    if is_battle_hub then _disable_reason = "battle_hub"; return end
    if flow_id == 9 or flow_id == 10 then
        if not is_replay then _disable_reason = "spectate"; return end
    end
end

function M.disable(reason)
    _disable_reason = reason or "disabled"
    _allowed = false
    _can_inject = false
    _training_allowed = false
    _replay_allowed = false
end

function M.allow_training()
    if _disable_reason then return end
    _allowed = true
    _training_allowed = true
    local ok = pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then _can_inject = false; return end
        local tData = tm:get_field("_tData")
        if not tData then _can_inject = false; return end
        local sm = tData:get_field("SelectMenu")
        local ps = tData:get_field("ParameterSetting")
        local gs = tData:get_field("GuardSetting")
        _can_inject = sm ~= nil and ps ~= nil and gs ~= nil
    end)
    if not ok then _can_inject = false end
end

function M.allow_replay()
    if _disable_reason then return end
    _allowed = true
    _replay_allowed = true
    _can_inject = false
end

function M.is_allowed() return _allowed end
function M.can_inject_input() return _can_inject end
function M.is_training_allowed() return _training_allowed end
function M.is_replay_allowed() return _replay_allowed end

function M.clear_runtime_flags()
    _G.TrainingModeActive = false
    _G.CurrentTrainerMode = 0
end

_G.SF6CC_RuntimeSafety = { frame = 0 }

re.on_application_entry("UpdateBehavior", function()
    _G.SF6CC_RuntimeSafety.frame = _frame
end)

return M
