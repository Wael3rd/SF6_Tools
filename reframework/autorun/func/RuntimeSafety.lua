local M = {}
local sdk = sdk

local _allowed = false
local _can_inject = false
local _training_allowed = false
local _replay_allowed = false
local _frame = 0
local _disable_reason = nil

-- Online-battle hard gate (adopted from SF6_TOOLS_CC). REFramework stops normal
-- on_frame callbacks during online matches, so the cached _training_allowed flag
-- freezes exactly when it matters. is_training_allowed / can_inject_input read
-- the network battle GameMode FRESH each call and gate off in any online mode,
-- so training features and input injection never run online. Closure-free reads.
local ONLINE_GAME_MODES = {
    [14] = true, -- Ranked Match
    [15] = true, -- Player Match
    [16] = true, -- Cabinet Match
    [17] = true, -- Custom Room Match
    [18] = true, -- Online Training
}
local function _rs_read_online_mode()
    local network = sdk.get_managed_singleton("app.network.NetworkManager")
    local session = network and network:get_field("<Session>k__BackingField")
    local fg      = session and session:get_field("<FGBattle>k__BackingField")
    local rule    = fg and fg:get_field("<BattleRule>k__BackingField")
    local mode    = rule and rule:get_field("GameMode")
    return mode and tonumber(tostring(mode)) or nil
end
local function is_online_battle()
    local ok, mode = pcall(_rs_read_online_mode)
    if not ok then return false end
    return mode ~= nil and ONLINE_GAME_MODES[mode] == true
end
M.is_online_battle = is_online_battle

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
-- Online checked FRESH (not the cached flag) so the gate holds even when
-- on_frame is frozen during the training -> online-match transition.
function M.can_inject_input()
    if is_online_battle() then return false end
    return _can_inject
end
function M.is_training_allowed()
    if is_online_battle() then return false end
    return _training_allowed
end
function M.is_replay_allowed() return _replay_allowed end

function M.clear_runtime_flags()
    _G.TrainingModeActive = false
    _G.CurrentTrainerMode = 0
    _G.TrainingScriptManagerActiveThisFrame = false
    _G.TrainingGamePaused = true
    _G.TrainingFloatingBar = nil
    _G.TrainingFloatingBarTop = nil
    _G.ComboTrialsD2DEnabled = false
    _G.ComboTrials_HideNativeHUD = false
    _G._ct_bar_geometry = nil
    _G.TrainingBarsDrawn = false
    _G._dv_aa_p2_mask = 0
end

_G.SF6CC_RuntimeSafety = { frame = 0 }

re.on_application_entry("UpdateBehavior", function()
    _G.SF6CC_RuntimeSafety.frame = _frame
end)

return M
