-- =========================================================
-- ComboTrials_Hotkeys.lua - Pad (FUNC + D-PAD) and keyboard shortcuts.
-- Receives shared context via init(). Module boundary mirrors
-- SF6_TOOLS_CC for project convergence.
-- =========================================================

local sdk = sdk
local json = json
local reframework = reframework

local M = {}

-- Resolved in init()
local ctx
local trial_state, file_system, players, demo_state, d2d_cfg
local assign_groups, reinject_trial_vital, apply_forced_position
local start_recording, stop_recording_and_save, cancel_recording, load_and_start_trial
local save_d2d_config, ct_ticker, POS_TICKER_NAMES, ComboTrials_D2D
local _td_gamepad

local BTN_UP          = 1
local BTN_DOWN        = 2
local BTN_LEFT        = 4
local BTN_RIGHT       = 8
local BTN_CROSS       = 32  -- Cross (PS) / A (Xbox)  [RDown in via.hid.GamePad]
local last_input_mask = 0
local last_kb_state = { [0x31]=false, [0x32]=false, [0x33]=false, [0x34]=false, [0x38]=false, [0x26]=false, [0x28]=false, [0x0D]=false }

-- VK codes for keys 1,2,3,4,8 (top row) + arrows
local KB_1 = 0x31  -- Position 1: LEFT
local KB_2 = 0x32  -- Position 2: UP (4-btn) or RIGHT (2-btn)
local KB_3 = 0x33  -- Position 3: RIGHT (4-btn only)
local KB_4 = 0x34  -- Position 4: DOWN (4-btn only)
local KB_8 = 0x38  -- A (OPEN/CLOSE COMBO DROPDOWN)
local KB_ARROW_UP   = 0x26  -- Arrow up (dropdown navigation)
local KB_ARROW_DOWN = 0x28  -- Arrow down (dropdown navigation)
local KB_ENTER      = 0x0D  -- Enter (confirm dropdown selection)

-- Detection of last used input device (shared via _G)
if _G.ComboTrials_InputDevice == nil then _G.ComboTrials_InputDevice = "pad" end

local function get_hardware_pad_mask()
    local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
    local gamepad_type = _td_gamepad
    if not gamepad_manager then return 0 end
    local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
    if not devices then return 0 end
    local count = devices:call("get_Count") or 0
    for i = 0, count - 1 do
        local pad = devices:call("get_Item", i)
        if pad then
            local b = pad:call("get_Button") or 0; if b > 0 then return b end
        end
    end
    return 0
end

-- Keyboard reading via reframework API (with safe fallback)
local function _ct_read_key(vk)
    return reframework:is_key_down(vk)
end
local function is_kb_down(vk)
    local ok, result = pcall(_ct_read_key, vk)
    return ok and result
end

local _kb_now = { [KB_1]=false, [KB_2]=false, [KB_3]=false, [KB_4]=false, [KB_8]=false, [KB_ARROW_UP]=false, [KB_ARROW_DOWN]=false, [KB_ENTER]=false }

function M.handle_combo_shortcuts()
    if _G.FlowMapID ~= 10 and not _G.IsInReplay and _G.CurrentTrainerMode ~= 4 then return end
    if _G._ct_bar_collapsed then return end

    local active_buttons = get_hardware_pad_mask()
    local func_btn = _G.TrainingFuncButton or 16384
    local is_func_held = ((active_buttons & func_btn) == func_btn)

    local function is_pressed(target_mask)
        if not is_func_held then return false end
        return ((active_buttons & target_mask) == target_mask) and not ((last_input_mask & target_mask) == target_mask)
    end

    -- Keyboard reading: keys 1,2,3,4,8 + arrows (front-edge)
    _kb_now[KB_1] = is_kb_down(KB_1)
    _kb_now[KB_2] = is_kb_down(KB_2)
    _kb_now[KB_3] = is_kb_down(KB_3)
    _kb_now[KB_4] = is_kb_down(KB_4)
    _kb_now[KB_8] = is_kb_down(KB_8)
    _kb_now[KB_ARROW_UP] = is_kb_down(KB_ARROW_UP)
    _kb_now[KB_ARROW_DOWN] = is_kb_down(KB_ARROW_DOWN)
    _kb_now[KB_ENTER] = is_kb_down(KB_ENTER)
    local kb_now = _kb_now
    local function kb_pressed(vk)
        return kb_now[vk] and not last_kb_state[vk]
    end

    -- Detect active input device
    if is_func_held and active_buttons > func_btn then
        _G.ComboTrials_InputDevice = "pad"
    end
    for _, vk in ipairs({KB_1, KB_2, KB_3, KB_4, KB_8}) do
        if kb_now[vk] then _G.ComboTrials_InputDevice = "kb" end
    end
    if kb_now[KB_ARROW_UP] or kb_now[KB_ARROW_DOWN] then
        _G.ComboTrials_InputDevice = "kb"
    end

    -- =============================================
    -- DROPDOWN NAVIGATION MODE: blocks all other shortcuts
    -- =============================================
    if _G.ComboTrials_DropdownOpen then
        if is_pressed(BTN_UP) or kb_pressed(KB_ARROW_UP) then
            _G.ComboTrials_DropdownNavUp = true
        end
        if is_pressed(BTN_DOWN) or kb_pressed(KB_ARROW_DOWN) then
            _G.ComboTrials_DropdownNavDown = true
        end
        if is_pressed(BTN_CROSS) or kb_pressed(KB_8) or kb_pressed(KB_ENTER) then
            _G.ComboTrials_DropdownSelect = true
        end
        last_input_mask = active_buttons
        for k, v in pairs(kb_now) do last_kb_state[k] = v end
        return
    end

    local is_demo_active = (demo_state and demo_state.is_playing)

    -- =============================================
    -- Positional shortcuts (left to right):
    --   4 buttons: LEFT/1, UP/2, RIGHT/3, DOWN/4
    --   2 buttons: LEFT/1, RIGHT/2
    -- =============================================

    if is_demo_active then
        -- ===== DEMO: 2 buttons (LEFT/1 = restart, RIGHT/2 = quit) =====
        if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
            if ctx.start_demo then ctx.start_demo() end
        end
        if is_pressed(BTN_RIGHT) or kb_pressed(KB_2) then
            if ctx.stop_demo then ctx.stop_demo() end
            -- trial_state.is_playing stays true so we return to the trial
        end

    elseif trial_state.is_recording then
        -- ===== RECORDING: 2 buttons (LEFT/1 = save, RIGHT/2 = cancel) =====
        if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
            _G.ComboTrials_ReplaySavePlayer = trial_state.recording_player
            stop_recording_and_save(); ct_ticker("RECORDING SAVED")
        end
        if is_pressed(BTN_RIGHT) or kb_pressed(KB_2) then
            _G.ComboTrials_ReplayCancelPlayer = trial_state.recording_player
            cancel_recording(); ct_ticker("RECORDING CANCELLED")
        end

    elseif trial_state.is_playing then
        -- ===== PLAYING: 4 buttons (LEFT/1=reset, UP/2=stop, RIGHT/3=demo, DOWN/4=switch pos) =====
        if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
            -- RESET: reload the sequence without leaving the trial
            local curr_player = trial_state.playing_player
            local paths = (curr_player == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
            local idx = (curr_player == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
            if #paths > 0 then
                local loaded = json.load_file(paths[idx])
                if loaded then
                    trial_state.sequence = loaded
                    assign_groups(trial_state.sequence)
                end
            end
            trial_state.is_playing = true
            trial_state.current_step = 1
            trial_state._step1_wrong_pending = false
            trial_state.success_timer = 0
            trial_state.fail_timer = 0
            trial_state.fail_reason = nil
            trial_state.active_universal_hold = nil
            for _, item in ipairs(trial_state.sequence) do
                item.actual_combo = 0
                item.has_hit = false
                item.last_frame_diff = nil
            end

            players[curr_player].log = {}
            players[curr_player].input_history_queue = {}

            trial_state._first_hit_landed = false
            trial_state._reset_grace = 15
            reinject_trial_vital()
            apply_forced_position()
            trial_state._pending_reinject_settings = true
            ComboTrials_D2D.reset_anim()
            ComboTrials_D2D.reset_raw()
        end
        if is_pressed(BTN_UP) or kb_pressed(KB_2) then
            trial_state.is_playing = false
        end
        if is_pressed(BTN_RIGHT) or kb_pressed(KB_3) then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            save_d2d_config()
            apply_forced_position()
            ct_ticker("POSITION: " .. (POS_TICKER_NAMES[d2d_cfg.forced_position_idx] or ""))
            -- Mini-reset to properly reposition after switching pos
            trial_state.current_step = 1
            trial_state._step1_wrong_pending = false
            trial_state.success_timer = 0
            trial_state.fail_timer = 0
            trial_state.fail_reason = nil
            trial_state.active_universal_hold = nil
            for _, item in ipairs(trial_state.sequence) do
                item.actual_combo = 0
                item.has_hit = false
                item.last_frame_diff = nil
            end
            if ctx.reset_visuals then ctx.reset_visuals() end
        end
        if is_pressed(BTN_DOWN) or kb_pressed(KB_4) then
            local _can_demo = true
            local _hp = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].has_piyo
            local _hr = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].raw_inputs
            if _hp and not _hr and not _G._allow_stun_demo then _can_demo = false end
            if _can_demo and ctx.start_demo then ctx.start_demo() end
        end

    else
        if _G.IsInReplay or _G.IsInBattleHub then
            -- ===== REPLAY/SPECTATE IDLE: 2 buttons (LEFT/1=rec P1, RIGHT/2=rec P2) =====
            if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
                _G.ComboTrials_ReplaySavePlayer = 0
                start_recording(0)
            end
            if is_pressed(BTN_RIGHT) or kb_pressed(KB_2) then
                _G.ComboTrials_ReplaySavePlayer = 1
                start_recording(1)
            end
        else
            -- ===== IDLE: 3 buttons (LEFT/1=record, UP/2=start trial, RIGHT/3=switch pos) =====
            if is_pressed(BTN_LEFT) or kb_pressed(KB_1) then
                start_recording(0); ct_ticker("RECORDING")
            end
            if is_pressed(BTN_UP) or kb_pressed(KB_2) then
                load_and_start_trial(0); ct_ticker("TRIAL STARTED")
            end
            if is_pressed(BTN_RIGHT) or kb_pressed(KB_3) then
                d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
                if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
                save_d2d_config()
                ct_ticker("POSITION: " .. (POS_TICKER_NAMES[d2d_cfg.forced_position_idx] or ""))
            end
        end
    end

    -- FUNC + CROSS (A) / Key 8: OPEN COMBO FILES DROPDOWN
    if is_pressed(BTN_CROSS) or kb_pressed(KB_8) then
        if not trial_state.is_recording then
            _G.ComboTrials_OpenDropdown = true
        end
    end

    last_input_mask = active_buttons
    for k, v in pairs(kb_now) do last_kb_state[k] = v end
end

function M.init(context, deps)
    ctx = context
    trial_state = deps.trial_state
    file_system = deps.file_system
    players = deps.players
    demo_state = deps.demo_state
    d2d_cfg = deps.d2d_cfg
    assign_groups = deps.assign_groups
    reinject_trial_vital = deps.reinject_trial_vital
    apply_forced_position = deps.apply_forced_position
    start_recording = deps.start_recording
    stop_recording_and_save = deps.stop_recording_and_save
    cancel_recording = deps.cancel_recording
    load_and_start_trial = deps.load_and_start_trial
    save_d2d_config = deps.save_d2d_config
    ct_ticker = deps.ct_ticker
    POS_TICKER_NAMES = deps.POS_TICKER_NAMES
    ComboTrials_D2D = deps.ComboTrials_D2D
    _td_gamepad = deps._td_gamepad
end

return M
