local M = {}
local sdk = sdk

local _allowed = false
local _can_inject = false
local _training_allowed = false
local _replay_allowed = false
local _frame = 0
local _disable_reason = nil

-- Native training-context validation (adopted from SF6_TOOLS_CC): catches the
-- matchmaking-transition case where _tData still exists but the training UI
-- widgets are gone. FAIL-OPEN: if the check errors or the native fields differ
-- on this build, we return true (never gate the whole suite off by mistake).
local _ntc_cache = { frame = -1, value = true }
local function has_training_ui_widgets(tm)
    -- returns true (allowed) / false (definitely not training) / nil (unknown)
    if not tm then return nil end
    local ok, result = pcall(function()
        local dict = tm:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")
        if not entries then return nil end
        local count = entries:call("get_Count")
        if not count then return nil end
        if count <= 0 then return false end
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            local widgets = entry and entry:get_field("value")
            local w_count = widgets and widgets:call("get_Count")
            if w_count and w_count > 0 then
                for j = 0, w_count - 1 do
                    local widget = widgets:call("get_Item", j)
                    local td = widget and widget:get_type_definition()
                    local name = td and td:get_full_name()
                    if name and (name:find("Training") or name:find("TM")) then
                        return true
                    end
                end
            end
        end
        return false
    end)
    if not ok then return nil end
    return result
end

-- Cached per frame. true = native training confirmed OR unknown (fail-open).
local function native_context_ok()
    if _ntc_cache.frame == _frame then return _ntc_cache.value end
    local value = true
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local w = has_training_ui_widgets(tm)
        if w == false then value = false end  -- only gate on a DEFINITIVE false
    end)
    _ntc_cache.frame = _frame
    _ntc_cache.value = value
    return value
end
M.native_context_ok = native_context_ok

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
    -- Gate on the native context ONLY when it returns a definitive negative
    -- (matchmaking transition). Unknown/error -> fail open (allowed).
    if not native_context_ok() then
        _disable_reason = "unsafe_training_context"
        _allowed = false
        _training_allowed = false
        _can_inject = false
        return
    end
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
