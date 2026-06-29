-- Training_ScriptManager.lua
-- v4.0 : Top floating bar + new cycling order

local re = re
local sdk = sdk
local imgui = imgui
local json = json
require("func/SharedHooks") -- error registry (_G.safe_load_json) + shared hooks
local GS = require("func/GameState")
local UIKit = require("func/UIKit")
local RuntimeSafety = require("func/RuntimeSafety")

-- ==========================================
-- CUSTOM TICKER SYSTEM
-- ==========================================
local _ticker = { mReq = nil, message = {}, queue = {} }
local function _ticker_is_ready()
    local mgr = sdk.get_managed_singleton("app.bFlowManager")
    return mgr and mgr:get_MainFlowID() ~= 1
end
local function _ticker_init_req()
    if _ticker.mReq then return sdk.PreHookResult.CALL_ORIGINAL end
    _ticker.mReq = sdk.create_instance("app.TickerRequestData", true)
    _ticker.mReq:Init(112, nil)
    _ticker.mReq.TickerId = 1
end
local function show_custom_ticker(message, time, category)
    if category == nil then category = 6 end
    if time == nil or time <= 0 then time = 3.5 end
    if not _ticker_is_ready() then
        if #_ticker.queue < 20 then
            table.insert(_ticker.queue, {message, time, category})
        end
        return
    end
    sdk.find_type_definition("app.TickerUtil"):get_method(".cctor"):call(nil)
    if _ticker.mReq then
        _ticker.message[_ticker.mReq.RequestId.mData4L] = message
        _ticker.mReq.Category = category
        _ticker.mReq.DisplaySecond = time
        local manager = sdk.find_type_definition("app.helper.hTicker"):get_method("get_Manager"):call(nil)
        if manager then manager:call("RequestShowTicker(app.TickerRequestData)", _ticker.mReq) end
        _ticker.mReq = nil
    end
end
_G.show_custom_ticker = show_custom_ticker

sdk.hook(sdk.find_type_definition("app.TickerUtil"):get_method(".cctor"), _ticker_init_req)
sdk.hook(sdk.find_type_definition("app.TickerRequestData"):get_method("GetMessage"), function(args)
    for k, v in pairs(_ticker.message) do
        if k == sdk.to_managed_object(args[2]).RequestId.mData4L then
            if type(v) == "function" then
                thread.get_hook_storage()["message"] = v()
            else
                thread.get_hook_storage()["message"] = v
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
end, function(retval)
    local m = thread.get_hook_storage()["message"]
    if m then return sdk.to_ptr(sdk.create_managed_string(m)) end
    return retval
end)
sdk.hook(sdk.find_type_definition("app.bBootFlow"):get_method("UpdatePhaseTransition"), function()
    if #_ticker.queue > 0 then
        for _, v in ipairs(_ticker.queue) do show_custom_ticker(table.unpack(v)) end
        _ticker.queue = {}
    end
end)

-- ==========================================
-- CONFIGURATION & SAVING
-- ==========================================
local CONFIG_FILE = "Training_ScriptManager_data/TrainingManager_Config.json"

local config = {
    func_button = nil, -- No default: must be set by user via CHANGE FUNCTION BUTTON
    switch_key = 0x30, -- Keyboard key for mode switch (default: '0' = VK 0x30)
    switch_modifiers = {}, -- Required modifiers (e.g. {0x11} for Ctrl)
    btn_colors = { c1 = 0xFFFF0000, c2 = 0xFF019D00, c3 = 0xFF0000FF, c4 = 0xFFDC00FF },
    btn_alphas = { c1 = 200, c2 = 200, c3 = 200, c4 = 200 },
    -- Top bar colors (ARGB)
    top_colors = { switch = 0xFF0066FF, active = 0xFF019D00, inactive = 0xFF666666 },
    top_alphas = { switch = 170, active = 170, inactive = 120 },
    hide_btn = { x_pct = 0.4625, y_pct = 0.05, w_pct = 0.075, h_pct = 0.075 },
}

-- ARGB -> ABGR conversion
local argb_to_abgr = UIKit.argb_to_abgr

-- Build SC_COLORS style table from ARGB color + fill alpha
local function build_sc_color(argb, fill_alpha)
    local abgr = argb_to_abgr(argb)
    local rgb = abgr & 0x00FFFFFF
    return {
        text   = abgr,
        base   = (0xFF << 24) | rgb,
        hover  = (0xFF << 24) | rgb,
        active = (0xFF << 24) | rgb,
        border = 0xFFFFFFFF,
    }
end

local function publish_button_colors()
    _G.TrainingSCColors = {
        c1 = build_sc_color(config.btn_colors.c1, config.btn_alphas.c1),
        c2 = build_sc_color(config.btn_colors.c2, config.btn_alphas.c2),
        c3 = build_sc_color(config.btn_colors.c3, config.btn_alphas.c3),
        c4 = build_sc_color(config.btn_colors.c4, config.btn_alphas.c4),
    }
end

-- Load config
local function load_config()
    local data = _G.safe_load_json(CONFIG_FILE)
    if data then
        if data.func_button then config.func_button = data.func_button end
        if data.switch_key then config.switch_key = data.switch_key end
        if data.btn_colors and type(data.btn_colors) == "table" then
            for k, v in pairs(data.btn_colors) do config.btn_colors[k] = v end
        end
        if data.btn_alphas and type(data.btn_alphas) == "table" then
            for k, v in pairs(data.btn_alphas) do config.btn_alphas[k] = v end
        end
        if data.top_colors and type(data.top_colors) == "table" then
            for k, v in pairs(data.top_colors) do config.top_colors[k] = v end
        end
        if data.top_alphas and type(data.top_alphas) == "table" then
            for k, v in pairs(data.top_alphas) do config.top_alphas[k] = v end
        end
    end
    _G.TrainingFuncButton = config.func_button
    publish_button_colors()
end

local function save_config()
    json.dump_file(CONFIG_FILE, config)
    _G.TrainingFuncButton = config.func_button
    publish_button_colors()
end

load_config()

-- ==========================================
-- 0.5. SCENE DETECTION (ABSOLUTE KILLSWITCH)
-- Reads _G.TrainingModeActive if TRCSS set it, otherwise detects locally
-- ==========================================
local _itm_cache = false
local _itm_refresh = 0
local function is_in_training_mode()
    if _G.TrainingModeActive ~= nil then
        return _G.TrainingModeActive == true
    end
    _itm_refresh = _itm_refresh - 1
    if _itm_refresh > 0 then return _itm_cache end
    _itm_refresh = 60
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if tm then
        local tData = tm:get_field("_tData")
        _itm_cache = tData ~= nil
    else
        _itm_cache = false
    end
    return _itm_cache
end

-- ==========================================
-- 0.1 GUARD CONTROL UTILITIES (SAFE PATTERN)
-- ==========================================
local last_mode_state = 0
local saved_guard_state = 0 -- Default 0, stores the previous state
local is_guard_overridden = false

-- Guard IDs
local GUARD_NO = 0
local GUARD_AFTER_FIRST_HIT = 2
local GUARD_ALL = 3
local GUARD_RANDOM = 4

-- Safety function to avoid crashes
local function _tsm_get_guard_func(mgr) return mgr:call("get_GuardFunc") end
local function _tsm_call_obj(obj, method, ...) return obj:call(method, ...) end

local function call_fresh(target_type, method, ...)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return false end

    local obj = nil
    if target_type == "TM" then
        obj = mgr
    elseif target_type == "Guard" then
        local ok, guard = pcall(_tsm_get_guard_func, mgr)
        if ok and guard then obj = guard end
    end

    if not obj or sdk.to_int64(obj) == 0 then return false end

    return pcall(_tsm_call_obj, obj, method, ...)
end

-- Apply guard type cleanly
local function set_guard_type(guard_id)
    -- 1. Apply the guard type to the Dummy (ID 1)
    call_fresh("Guard", "ChangeGuardType", 1, guard_id)
    -- 2. Force refresh
    call_fresh("TM", "set_IsReqRefresh", true)
end

local function update_guard_logic()
    local current_mode = _G.CurrentTrainerMode or 0
    
    -- If mode hasn't changed, do nothing
    if current_mode == last_mode_state then return end

    -- CHANGE LOGIC

    -- When switching from inactive (0) to active mode (1, 2, 3), save the guard state
    -- (Note: Without a reliable get_GuardType, we assume the user starts in No Guard or wants to return to it)
    if last_mode_state == 0 and current_mode ~= 0 then
        if not is_guard_overridden then
            saved_guard_state = 0 -- Will revert to 0 by default
            is_guard_overridden = true
        end
    end

    if current_mode == 1 then
        -- >>> REACTION DRILLS >>> NO GUARD (0)
        set_guard_type(GUARD_NO)

    elseif current_mode == 2 then
        -- >>> HIT CONFIRM >>> RANDOM GUARD (4)
        set_guard_type(GUARD_RANDOM)

    elseif current_mode == 3 then
        -- >>> POST GUARD >>> ALL GUARD (3)
        set_guard_type(GUARD_ALL)

    elseif current_mode == 4 then
        -- >>> COMBO TRIALS >>> GUARD_AFTER_FIRST_HIT (2)
        set_guard_type(GUARD_AFTER_FIRST_HIT)

    elseif current_mode == 5 then
        -- >>> EXECUTION >>> NO GUARD (0)
        set_guard_type(GUARD_NO)


    elseif current_mode == 0 then
        -- >>> DISABLED / COMBO TRIALS >>> RESTORE
        if is_guard_overridden then
            set_guard_type(saved_guard_state) -- Revert to 0 (or saved state)
            is_guard_overridden = false
        end
    end

    last_mode_state = current_mode
end

-- ==========================================
-- 1. MODE MANAGEMENT (TRAINER MANAGER)
-- ==========================================
if _G.CurrentTrainerMode == nil then
    _G.CurrentTrainerMode = 0
end

local _tsm_last_mode = _G.CurrentTrainerMode
local TSM_MODE_NAMES = {
    [0] = "DISABLED",
    [1] = "REACTION DRILLS",
    [2] = "HIT CONFIRM",
    [3] = "POST GUARD",
    [4] = "COMBO TRIALS",
    [5] = "EXECUTION",
}

local MODE_CYCLE = { 0, 5, 2, 1, 3, 4 }
local MODE_CYCLE_INDEX = {} -- reverse lookup: mode_id → position in cycle
for i, m in ipairs(MODE_CYCLE) do MODE_CYCLE_INDEX[m] = i end

local function cycle_next_mode()
    local cur = _G.CurrentTrainerMode or 0
    local idx = MODE_CYCLE_INDEX[cur] or 1
    idx = idx + 1
    if idx > #MODE_CYCLE then idx = 1 end
    _G.CurrentTrainerMode = MODE_CYCLE[idx]
end

-- Input Management (Gamepad & Keyboard)
local last_input_mask = 0
local is_binding_mode = false
local is_kb_binding_mode = false
local last_kb_0_state = false

-- CORRECTED: 64 = X (Xbox) / Square (PS)
local BTN_SQUARE = 64

-- Hoisted to file scope to avoid per-frame closure/table allocations (hot path)
local _TSM_MODIFIER_VKS = {0x10, 0x11, 0x12, 0x5B, 0x5C}
local _TSM_MOD_SET = {}
for _, mk in ipairs(_TSM_MODIFIER_VKS) do _TSM_MOD_SET[mk] = true end

local function _tsm_scan_kb_binding()
    local mods_held = {}
    for _, mk in ipairs(_TSM_MODIFIER_VKS) do
        if reframework:is_key_down(mk) then mods_held[#mods_held + 1] = mk end
    end

    for vk = 0x08, 0x7F do
        if not _TSM_MOD_SET[vk] and reframework:is_key_down(vk) then
            config.switch_key = vk
            config.switch_modifiers = mods_held
            save_config()
            is_kb_binding_mode = false
            break
        end
    end
end

local function _tsm_vk_in_list(list, vk)
    for _, m in ipairs(list) do
        if m == vk then return true end
    end
    return false
end

local function _tsm_check_kb_switch(switch_vk, switch_mods)
    if not reframework:is_key_down(switch_vk) then return false end
    for _, m in ipairs(switch_mods) do
        if not reframework:is_key_down(m) then return false end
    end
    for _, m in ipairs(_TSM_MODIFIER_VKS) do
        if not _tsm_vk_in_list(switch_mods, m) and reframework:is_key_down(m) then return false end
    end
    return true
end

local function handle_input()
    local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
    local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
    if not gamepad_manager then return end

    local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
    if not devices then return end

    local count = devices:call("get_Count") or 0
    local active_buttons = 0
    
    for i = 0, count - 1 do
        local pad = devices:call("get_Item", i)
        if pad then
            local b = pad:call("get_Button") or 0
            if b > 0 then active_buttons = b; break end
        end
    end

    -- BINDING LOGIC (If clicked in UI)
    if is_binding_mode then
        if active_buttons ~= 0 and last_input_mask == 0 then
            config.func_button = active_buttons
            save_config()
            is_binding_mode = false
        end
        last_input_mask = active_buttons
        return
    end

    -- KEYBOARD BINDING LOGIC (scan all keys, capture modifiers)
    if is_kb_binding_mode then
        pcall(_tsm_scan_kb_binding)
        if is_kb_binding_mode then return end -- still waiting for a key
    end

    -- SCRIPT SWITCH LOGIC (FUNCTION + SQUARE on Pad)
    local func_btn = _G.TrainingFuncButton
    local is_func_held = false
    if func_btn and func_btn > 0 then
        is_func_held = (active_buttons & func_btn) == func_btn
    end
    _G.TrainingFuncHeld = is_func_held
    local is_switch_pressed = (active_buttons & BTN_SQUARE) == BTN_SQUARE and (last_input_mask & BTN_SQUARE) ~= BTN_SQUARE

    -- SCRIPT SWITCH LOGIC (configurable keyboard key + modifiers)
    local switch_vk = config.switch_key or 0x30
    local switch_mods = config.switch_modifiers or {}
    local ok_kb, kb_down = pcall(_tsm_check_kb_switch, switch_vk, switch_mods)
    local is_kb_0_down = ok_kb and kb_down == true
    local is_kb_0_pressed = is_kb_0_down and not last_kb_0_state

    -- Trigger switch if either Pad combo or Keyboard key is pressed
    if (is_func_held and is_switch_pressed) or is_kb_0_pressed then
        cycle_next_mode()
    end

    last_input_mask = active_buttons
    last_kb_0_state = is_kb_0_down
end

-- ==========================================
-- 2. UI RESTORATION & HUD TRACKING LOGIC
-- ==========================================
_G.CurrentHudSuffix = "Default"

local function apply_infinite_visibility(control, should_hide)
    if not control then return end
    local name = control:call("get_Name")
    if name and string.match(name:lower(), "infinite") then
        -- We only force it invisible when needed. 
        -- We do NOT force it visible, letting the native game logic handle the ticking timer.
        control:call("set_ForceInvisible", should_hide)
    end
    local child = control:call("get_Child")
    while child do
        apply_infinite_visibility(child, should_hide)
        child = child:call("get_Next")
    end
end

local function safe_call(obj, method, arg)
    if not obj then return end
    pcall(obj.call, obj, method, arg)
end

local function _tsm_apply_widget_visibility(entries, scripts_active)
    local count = entries:call("get_Count")
    for i = 0, count - 1 do
        local entry = entries:call("get_Item", i)
        if entry then
            local widget_list = entry:get_field("value")
            if widget_list then
                local w_count = widget_list:call("get_Count")
                for j = 0, w_count - 1 do
                    local widget = widget_list:call("get_Item", j)
                    if widget then
                        local type_def = widget:get_type_definition()
                        if type_def then
                            local full_name = type_def:get_full_name()
                            if string.find(full_name, "TMAttackInfo") then
                                local attack_infos = widget:get_field("AttackInfos")
                                if attack_infos then
                                    local len = attack_infos:call("get_Length")
                                    for k = 0, len - 1 do
                                        local line = attack_infos:call("GetValue", k)
                                        if line then
                                            local texts = { line:get_field("LeftText"), line:get_field("CenterText"), line:get_field("RightText") }
                                            for _, txt_obj in ipairs(texts) do
                                                if txt_obj then safe_call(txt_obj, "set_Visible", not scripts_active) end
                                            end
                                        end
                                    end
                                end
                            end
                            if string.find(full_name, "UIWidget_TMTicker") then
                                if not scripts_active then
                                    safe_call(widget, "set_Visible", true)
                                    safe_call(widget, "set_ForceInvisible", false)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local _tsm_ui_vis_last = nil
local _tsm_ui_vis_wait = 0
local TSM_UI_VIS_INTERVAL = 60

local function manage_ui_visibility(scripts_active)
    if _tsm_ui_vis_last == scripts_active and _tsm_ui_vis_wait > 0 then
        _tsm_ui_vis_wait = _tsm_ui_vis_wait - 1
        return
    end
    _tsm_ui_vis_last = scripts_active
    _tsm_ui_vis_wait = TSM_UI_VIS_INTERVAL

    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if mgr then
        local dict = mgr:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")

        if entries then
            pcall(_tsm_apply_widget_visibility, entries, scripts_active)
        end
    end
end

-- ==========================================
-- 3. DRAW HOOK (MASTER HUD TRACKER)
-- ==========================================
re.on_pre_gui_draw_element(function(element, context)
    if not is_in_training_mode() then return true end

    local game_object = element:call("get_GameObject")
    if not game_object then return true end
    
    local name = game_object:call("get_Name")
    
    -- GLOBAL FUZZY HUD DETECTION
    if name and string.find(name, "BattleHud_Timer") then
        -- 1. Extract suffix for ALL other scripts
        local suffix = string.match(name, "BattleHud_Timer(.*)")
        if suffix == "" or suffix == nil then suffix = "Default" end
        _G.CurrentHudSuffix = suffix
        
        -- 2. Manage infinite symbol visibility (Never hidden in mode 4)
        local hide_infinite = (_G.CurrentTrainerMode == 1 or _G.CurrentTrainerMode == 2 or _G.CurrentTrainerMode == 3 or _G.CurrentTrainerMode == 5)
        
        local view = element:call("get_View")
        apply_infinite_visibility(view, hide_infinite)
    end

    return true
end)

-- ==========================================
-- 3.5 TOP FLOATING BAR (mode switcher)
-- ==========================================
local SharedUI = require("func/Training_SharedUI")

-- Top bar button colors (rebuilt from config)
local SWITCH_COLOR  = build_sc_color(config.top_colors.switch, config.top_alphas.switch)
local MODE_ACTIVE   = build_sc_color(config.top_colors.active, config.top_alphas.active)
local MODE_INACTIVE = build_sc_color(config.top_colors.inactive, config.top_alphas.inactive)

local top_bar_width = 0.74
local top_bar_height = 0.0444

local MODE_BUTTONS = {
    { id = 0, label = "DISABLED" },
    { id = 5, label = "EXECUTION" },
    { id = 2, label = "HIT CONFIRM" },
    { id = 1, label = "REACTION DRILLS" },
    { id = 3, label = "POST GUARD" },
    { id = 4, label = "CUSTOM COMBO TRIALS" },
}

local VK_NAMES = {
    [0x08]="BACKSPACE",[0x09]="TAB",[0x0D]="ENTER",[0x10]="SHIFT",[0x11]="CTRL",[0x12]="ALT",
    [0x14]="CAPS",[0x1B]="ESC",[0x20]="SPACE",
    [0x21]="PGUP",[0x22]="PGDN",[0x23]="END",[0x24]="HOME",[0x25]="LEFT",[0x26]="UP",[0x27]="RIGHT",[0x28]="DOWN",
    [0x2D]="INSERT",[0x2E]="DELETE",
    [0x30]="0",[0x31]="1",[0x32]="2",[0x33]="3",[0x34]="4",[0x35]="5",[0x36]="6",[0x37]="7",[0x38]="8",[0x39]="9",
    [0x41]="A",[0x42]="B",[0x43]="C",[0x44]="D",[0x45]="E",[0x46]="F",[0x47]="G",[0x48]="H",[0x49]="I",
    [0x4A]="J",[0x4B]="K",[0x4C]="L",[0x4D]="M",[0x4E]="N",[0x4F]="O",[0x50]="P",[0x51]="Q",[0x52]="R",
    [0x53]="S",[0x54]="T",[0x55]="U",[0x56]="V",[0x57]="W",[0x58]="X",[0x59]="Y",[0x5A]="Z",
    [0x60]="NUM0",[0x61]="NUM1",[0x62]="NUM2",[0x63]="NUM3",[0x64]="NUM4",
    [0x65]="NUM5",[0x66]="NUM6",[0x67]="NUM7",[0x68]="NUM8",[0x69]="NUM9",
    [0x70]="F1",[0x71]="F2",[0x72]="F3",[0x73]="F4",[0x74]="F5",[0x75]="F6",
    [0x76]="F7",[0x77]="F8",[0x78]="F9",[0x79]="F10",[0x7A]="F11",[0x7B]="F12",
    [0xBA]=";",[0xBB]="=",[0xBC]=",",[0xBD]="-",[0xBE]=".",[0xBF]="/",[0xC0]="`",
}
local function vk_name(vk)
    return VK_NAMES[vk] or string.format("0x%02X", vk)
end

local function combo_name(vk, mods)
    local parts = {}
    if mods then
        for _, m in ipairs(mods) do parts[#parts + 1] = vk_name(m) end
    end
    parts[#parts + 1] = vk_name(vk)
    return table.concat(parts, " + ")
end

local function draw_top_floating_bar()
    local visible, sw, sh = SharedUI.begin_floating_window_top("TrainingModeSwitch##top", top_bar_width, top_bar_height)
    if not visible then
        SharedUI.end_floating_window_top(); return
    end
    SharedUI.draw_floating_bg_top()

    local sp = 4 * (sh / 1080.0)
    local content_w = imgui.get_window_size().x - sw * 0.02  -- subtract WindowPadding (left+right)

    -- Build switch label with dynamic shortcut (keyboard vs controller)
    local switch_label
    local fn = SharedUI.get_func_name()
    local key_label = combo_name(config.switch_key or 0x30, config.switch_modifiers)
    if SharedUI.is_keyboard_mode() or not fn then
        switch_label = "SWITCH (" .. key_label .. ")"
    else
        switch_label = "SWITCH (" .. fn .. " + SQUARE/X)"
    end

    -- Calculate button widths: all 6 buttons equal width
    local total_buttons = 1 + #MODE_BUTTONS
    local btn_w = (content_w - sp * (total_buttons - 1)) / total_buttons

    imgui.set_cursor_pos(Vector2f.new(sw * 0.0075, sh * 0.01))
    if SharedUI.sf6_button(switch_label .. "##sw_top", SWITCH_COLOR, btn_w) then
        cycle_next_mode()
    end

    for _, btn in ipairs(MODE_BUTTONS) do
        imgui.same_line(0, sp)
        local is_active = (_G.CurrentTrainerMode == btn.id)
        local colors = is_active and MODE_ACTIVE or MODE_INACTIVE
        if SharedUI.sf6_button(btn.label .. "##top_" .. btn.id, colors, btn_w) then
            _G.CurrentTrainerMode = btn.id
        end
    end

    SharedUI.end_floating_window_top()
end

-- ==========================================
-- 4. MAIN LOOP
-- ==========================================
local _tsm_replay_delay = 3.00  -- seconds before reactivating the script after a replay
local _tsm_replay_timer = 0
local _tsm_was_replay = false

local function _tsm_read_flowmap_id()
    local bfm = sdk.get_managed_singleton("app.bFlowManager")
    if not bfm then return nil end
    local work = bfm:get_field("m_flow_work")
    if work and work._FlowMap then return work._FlowMap._ID end
    return nil
end

local function get_flowmap_id()
    local ok, id = pcall(_tsm_read_flowmap_id)
    return ok and id or nil
end

-- ==========================================
-- REPLAY DETECTION HOOKS
-- ==========================================
pcall(function()
    local t_emote = sdk.find_type_definition("app.esports.bBattleFighterEmoteFlow")
    if t_emote then
        local m_setup = t_emote:get_method("setup")
        if m_setup then
            sdk.hook(m_setup, function(args)
                local obj = sdk.to_managed_object(args[2])
                if obj and obj.mInputType == 3 then
                    _G.IsInReplay = true
                end
            end, function(r) return r end)
        end
    end
    local t_flow = sdk.find_type_definition("app.battle.bBattleFlow")
    if t_flow then
        local m_end = t_flow:get_method("endReplay")
        if m_end then
            sdk.hook(m_end, function(args)
                _G.IsInReplay = false
            end, function(r) return r end)
        end
    end
end)

-- Hoisted to file scope to avoid per-frame closure allocations (hot path)
local function _tsm_update_hide_rect()
    local sw, sh = SharedUI.get_screen_size()
    local lb_off = SharedUI.get_letterbox_offset()
    local hb = config.hide_btn
    _G._tsm_hide_rect.x = sw * hb.x_pct
    _G._tsm_hide_rect.y = lb_off + (sh - lb_off * 2) * hb.y_pct
    _G._tsm_hide_rect.w = sw * hb.w_pct
    _G._tsm_hide_rect.h = (sh - lb_off * 2) * hb.h_pct
end

local function _tsm_dump_webstate_inactive()
end

local _tsm_last_fingerprint = ""

local function _tsm_build_fingerprint()
    return tostring(_G.CurrentTrainerMode or 0)
        .. "|" .. tostring(_G.ComboTrials_CurrentFile or "")
        .. "|" .. tostring(_G.ComboTrials_CurrentStep or 0)
        .. "|" .. tostring(_G.ComboTrials_TotalSteps or 0)
        .. "|" .. tostring(_G.ComboTrials_IsPlaying or false)
        .. "|" .. tostring(_G.ComboTrials_IsRecording or false)
        .. "|" .. tostring(_G.ComboTrials_IsDemo or false)
        .. "|" .. tostring(_G.ComboTrials_FileIdx or 1)
        .. "|" .. tostring(_G.ComboTrials_PositionIdx or 1)
        .. "|" .. tostring(_G.TrainingSession_IsRunning or false)
        .. "|" .. tostring(_G.TrainingSession_IsPaused or false)
        .. "|" .. tostring(_G.TrainingSession_Timer or 0)
        .. "|" .. tostring(_G.TrainingSession_Trials or 0)
        .. "|" .. tostring(_G.TrainingSession_Mode or 2)
        .. "|" .. tostring(_G.TrainingSession_BlockRate or 50)
        .. "|" .. tostring(_G._exec_status or "")
        .. "|" .. tostring(_G._exec_registering or false)
        .. "|" .. tostring(_G._exec_count or 0)
        .. "|" .. tostring(_G._exec_side or 1)
        .. "|" .. tostring(_G._exec_sel_motion or "")
        .. "|" .. tostring(_G._exec_sel_buttons or "")
        .. "|" .. tostring(_G._exec_boxes or "0000000000")
        .. "|" .. tostring(_G._tsm_hide_ui or false)
        .. "|" .. tostring(_G.TrainingModeActive or false)
end

local function _tsm_write_state_io()
    json.dump_file("SF6_TrainingRemoteControl_data/TSM_WebState.json", {
        mode = _G.CurrentTrainerMode or 0,
        trial_file = _G.ComboTrials_CurrentFile or "",
        trial_step = _G.ComboTrials_CurrentStep or 0,
        trial_total = _G.ComboTrials_TotalSteps or 0,
        trial_playing = _G.ComboTrials_IsPlaying or false,
        trial_recording = _G.ComboTrials_IsRecording or false,
        trial_demo = _G.ComboTrials_IsDemo or false,
        trial_files = _G.ComboTrials_FileList or {},
        trial_file_idx = _G.ComboTrials_FileIdx or 1,
        trial_position = _G.ComboTrials_PositionIdx or 1,
        is_running = _G.TrainingSession_IsRunning or false,
        is_paused = _G.TrainingSession_IsPaused or false,
        timer = _G.TrainingSession_Timer or 0,
        trials = _G.TrainingSession_Trials or 0,
        session_mode = _G.TrainingSession_Mode or 2,
        block_rate = _G.TrainingSession_BlockRate or 50,
        exec_status = _G._exec_status or "",
        exec_registering = _G._exec_registering or false,
        exec_count = _G._exec_count or 0,
        exec_side = _G._exec_side or 1,
        exec_sel_motion = _G._exec_sel_motion or "",
        exec_sel_buttons = _G._exec_sel_buttons or "",
        exec_boxes = _G._exec_boxes or "0000000000",
        hide_ui = _G._tsm_hide_ui or false,
        sf6_running = true,
        training_active = _G.TrainingModeActive or false,
    })
end

local function _tsm_read_bridge_io()
    local f = io.open("SF6_TrainingRemoteControl_data/TSM_WebBridge.json", "r")
    if not f then return end
    local raw = f:read("*a")
    f:close()
    if not raw or #raw < 5 then return end

    local ts = raw:match('"_web_timestamp":%s*([%d%.]+)')
    if not ts then return end
    ts = tonumber(ts)
    if _G._tsm_bridge_ts and ts <= _G._tsm_bridge_ts then return end
    _G._tsm_bridge_ts = ts

    if not _G.TrainingModeActive then return end

    local mode_val = raw:match('"mode":%s*(%d+)')
    if mode_val then _G.CurrentTrainerMode = tonumber(mode_val) end

    local cmd = raw:match('"cmd":%s*"([^"]*)"')
    if cmd and cmd ~= "" then
        if cmd == "hide_ui" then
            _G._tsm_hide_ui = not _G._tsm_hide_ui
        else
            _G._tsm_web_cmd = cmd
            _G._tsm_web_cmd_value = raw:match('"value":%s*"?([^",}]*)"?')
            _G._tsm_web_cmd_data = { cmd = cmd, value = _G._tsm_web_cmd_value }
        end
        local fw = io.open("SF6_TrainingRemoteControl_data/TSM_WebBridge.json", "w")
        if fw then fw:write('{"_web_timestamp":' .. string.format("%.7f", ts) .. '}'); fw:close() end
    end

    local tp_dist = raw:match('"teleport":%s*{%s*"distance":%s*([%d%.%-eE]+)')
    if tp_dist and _G._dv_teleport then
        pcall(_G._dv_teleport, tonumber(tp_dist))
        local fw = io.open("SF6_TrainingRemoteControl_data/TSM_WebBridge.json", "w")
        if fw then fw:write('{"_web_timestamp":' .. string.format("%.7f", ts) .. '}'); fw:close() end
    end
end

local function _tsm_web_bridge_tick()
    _tsm_write_state_io()
    _tsm_read_bridge_io()
end

re.on_frame(function()
    SharedUI.clear_rects()
    _G.TrainingBarsDrawn = false

    -- Mode change ticker
    local cur_mode = _G.CurrentTrainerMode or 0
    if cur_mode ~= _tsm_last_mode then
        local name = TSM_MODE_NAMES[cur_mode]
        if name and cur_mode ~= 0 and _G.show_custom_ticker then
            _G.show_custom_ticker(name .. " STARTED", 0.3)
        end
        _tsm_last_mode = cur_mode
    end

    -- FlowMap detection
    local fid = get_flowmap_id()
    _G.FlowMapID = fid
    _G.IsInBattleHub = (fid == 9)
    local is_replay = (fid == 10) or (_G.IsInReplay == true)
    RuntimeSafety.begin_frame(fid, is_in_training_mode(), is_replay, _G.IsInBattleHub)

    -- HIDE UI BUTTON (works in training + replay)
    if not _G._tsm_hide_flash then _G._tsm_hide_flash = 0 end
    if not _G._tsm_hide_rect then _G._tsm_hide_rect = { x = 0, y = 0, w = 0, h = 0 } end
    pcall(_tsm_update_hide_rect)
    if not _G._tsm_hide_cooldown then _G._tsm_hide_cooldown = 0 end
    if _G._tsm_hide_cooldown > 0 then _G._tsm_hide_cooldown = _G._tsm_hide_cooldown - 1 end
    if not _G.IsInBattleHub and _G._tsm_hide_cooldown == 0 and imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m then
            local r = _G._tsm_hide_rect
            if r.w > 0 and m.x >= r.x and m.x <= r.x + r.w and m.y >= r.y and m.y <= r.y + r.h then
                _G._tsm_hide_ui = not _G._tsm_hide_ui
                _G._tsm_hide_flash = 10
                _G._tsm_hide_cooldown = 3
            end
        end
    end

    -- BattleHub: always disabled
    if _G.IsInBattleHub then
        if _G.CurrentTrainerMode ~= 0 then _G.CurrentTrainerMode = 0 end
        _G.TrainingGamePaused = true
        RuntimeSafety.disable("battle_hub")
        return
    end

    -- Replay: disable once, then timer, then disabled (no top bar)
    if is_replay then
        if _tsm_was_replay == false then
            -- First detection
            _tsm_was_replay = "waiting"
            _tsm_replay_timer = 0
            if _G.CurrentTrainerMode ~= 0 then _G.CurrentTrainerMode = 0 end
            _G.TrainingFloatingBar = nil
            _G.TrainingFloatingBarTop = nil
        end
        if _tsm_was_replay == "waiting" then
            _tsm_replay_timer = _tsm_replay_timer + (1.0 / 60.0)
            if _tsm_replay_timer >= _tsm_replay_delay then
                _tsm_was_replay = "done"
                _G.CurrentTrainerMode = 4
            end
        end
        -- In replay: always return, no top bar, no guard logic
        _G.TrainingFloatingBarTop = nil
        return
    end

    -- Reset when leaving replay
    if _tsm_was_replay ~= false then
        _tsm_was_replay = false
    end
    -- ABSOLUTE KILLSWITCH: No gamepad reading or logic outside training
    _G.TrainingModeActive = is_in_training_mode()
    if _G.TrainingModeActive then RuntimeSafety.allow_training() end
    if not _G.TrainingModeActive then
        -- AUTO-RESET: Disable all active modes when leaving Training Mode
        if _G.CurrentTrainerMode ~= 0 then
            _G.CurrentTrainerMode = 0
        end
        _G.TrainingGamePaused = true
        return
    end

    handle_input()

    -- Clear D2D floating bar when no training mode is active
    if _G.CurrentTrainerMode == 0 then
        _G.TrainingFloatingBar = nil
        if _G._tsm_last_mode and _G._tsm_last_mode ~= 0 then
            pcall(function()
                local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
                local rec = mgr and mgr:call("get_RecordFunc")
                if rec then
                    local m1 = rec:get_type_definition():get_method("SetPlay")
                    if m1 then m1:call(rec, false) end
                end
                local p2_id = _G._rsm_p2_id or -1
                if p2_id ~= -1 and rec then
                    local fl = rec:get_field("_tData"):get_field("RecordSetting"):get_field("FighterDataList")
                    local slots = fl:call("get_Item", p2_id):get_field("RecordSlots")
                    for i = 0, 7 do
                        local s = slots:call("get_Item", i)
                        if s then s:set_field("IsActive", false) end
                    end
                end
            end)
        end
    end
    if _G._tsm_last_mode and _G._tsm_last_mode ~= _G.CurrentTrainerMode then
        pcall(function()
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            if not tm then return end
            local tData = tm:get_field("_tData")
            if not tData then return end
            local sm = tData:get_field("SelectMenu")
            if not sm then return end
            sm.StartLocation = 3
            sm.PlayerDatas[0].ManualPosX = -150
            sm.PlayerDatas[1].ManualPosX = 150
            tm:call("set_IsReqRefresh", true)
        end)
    end
    _G._tsm_last_mode = _G.CurrentTrainerMode

    if is_binding_mode then return end

    -- CHECK AUTOMATIC GUARD SWITCHING
    update_guard_logic()

    -- TOP FLOATING BAR (hide during pause menu)
    _G.TrainingGamePaused = GS.in_pause_menu
    if not GS.in_pause_menu and not _G._tsm_hide_ui then
        draw_top_floating_bar()
    elseif _G._tsm_hide_ui then
        _G.TrainingBarsDrawn = true
    end


    local scripts_active = (_G.CurrentTrainerMode == 1 or _G.CurrentTrainerMode == 2 or _G.CurrentTrainerMode == 3 or (_G.CurrentTrainerMode == 4 and _G.ComboTrials_HideNativeHUD) or _G.CurrentTrainerMode == 5)
    manage_ui_visibility(scripts_active)

    if _G._remote_control_loaded then
        if not _G._web_frame then _G._web_frame = 0 end
        _G._web_frame = _G._web_frame + 1
        local wf = _G._web_frame
        local web_interval = (_G.CurrentTrainerMode == 5) and 2 or 60
        if wf % web_interval == 0 then
            local fp = _tsm_build_fingerprint()
            if fp ~= _tsm_last_fingerprint then
                _tsm_last_fingerprint = fp
                pcall(_tsm_write_state_io)
            end
        end
        if wf % 60 == 5 then
            pcall(_tsm_read_bridge_io)
        end
    end
end)

-- ==========================================
-- 5. USER INTERFACE
-- ==========================================
-- Styled headers
local UI_THEME = {
    hdr_modes   = UIKit.THEME.hdr_gold,
    hdr_config  = UIKit.THEME.hdr_purple,
    hdr_help    = UIKit.THEME.hdr_blue,
}

local styled_header = UIKit.styled_header

re.on_draw_ui(function()
    -- Publish REFramework menu window rect for overlap detection
    local wpos = imgui.get_window_pos()
    local wsz = imgui.get_window_size()
    if wpos and wsz and _G.FloatingRects then
        _G._ref_menu_rect = { x = wpos.x, y = wpos.y, w = wsz.x, h = wsz.y }
    end

    -- SCRIPT ERRORS PANEL (error registry from SharedHooks)
    local _errs = _G._mod_errors
    if _errs and _errs.count > 0 then
        imgui.text_colored(string.format("[!] %d script error(s)", _errs.count), 0xFF0000FF)
        imgui.same_line()
        if imgui.tree_node("details##mod_errors") then
            for i = #_errs.list, math.max(1, #_errs.list - 14), -1 do
                local e = _errs.list[i]
                imgui.text_colored(string.format("[%.0fs] %s", e.t, e.ctx), 0xFF00A5FF)
                imgui.text("    " .. e.err)
            end
            if imgui.button("Clear##mod_errors") then
                _errs.list = {}; _errs.count = 0; _errs.config_failures = {}
            end
            imgui.tree_pop()
        end
    end

    local _has_errors = _errs and _errs.count > 0
    if _has_errors then imgui.push_style_color(0, 0xFF0000FF) end
    local _tsm_open = imgui.tree_node("TRAINING SCRIPT MANAGER" .. (_has_errors and " [!]" or ""))
    if _has_errors then imgui.pop_style_color(1) end
    if _tsm_open then

        -- If not in training, show a waiting message and block the UI
        if not is_in_training_mode() then
            imgui.text_colored("[!] INACTIVE: Waiting for Training Mode...", 0xFF00A5FF)
            imgui.tree_pop()
            return
        end

        -- ==========================================
        -- SECTION 1: MODE SELECTION
        -- ==========================================
        if styled_header("--- TRAINING MODES ---", UI_THEME.hdr_modes) then
            local c0, v0 = imgui.checkbox("DISABLED", _G.CurrentTrainerMode == 0)
            if c0 and v0 then _G.CurrentTrainerMode = 0 end

            local c5, v5 = imgui.checkbox("EXECUTION", _G.CurrentTrainerMode == 5)
            if c5 and v5 then _G.CurrentTrainerMode = 5 end

            local c2, v2 = imgui.checkbox("HIT CONFIRM", _G.CurrentTrainerMode == 2)
            if c2 and v2 then _G.CurrentTrainerMode = 2 end

            local c1, v1 = imgui.checkbox("REACTION DRILLS", _G.CurrentTrainerMode == 1)
            if c1 and v1 then _G.CurrentTrainerMode = 1 end

            local c3, v3 = imgui.checkbox("POST GUARD", _G.CurrentTrainerMode == 3)
            if c3 and v3 then _G.CurrentTrainerMode = 3 end

            local c4, v4 = imgui.checkbox("CUSTOM COMBO TRIALS", _G.CurrentTrainerMode == 4)
            if c4 and v4 then _G.CurrentTrainerMode = 4 end
        end

        -- ==========================================
        -- SECTION 2: CONTROLLER CONFIG
        -- ==========================================
        if styled_header("--- CONTROLLER CONFIG ---", UI_THEME.hdr_config) then
            if is_binding_mode then
                imgui.spacing()
                imgui.push_style_color(5, 0xFF00FFFF)
                imgui.push_style_color(21, 0xFF005555)
                imgui.push_style_color(22, 0xFF007777)
                imgui.push_style_color(23, 0xFF009999)
                imgui.push_style_color(0, 0xFF00FFFF)
                imgui.button(">>> PRESS ANY BUTTON ON YOUR CONTROLLER... <<<", Vector2f.new(-1, 40))
                imgui.pop_style_color(5)
                imgui.spacing()
            else
                local btn_name = "NOT SET"
                if config.func_button then
                    btn_name = "ID: " .. tostring(config.func_button)
                    if config.func_button == 16384 then btn_name = "SELECT / BACK" end
                    if config.func_button == 8192 then btn_name = "R3 / RS" end
                    if config.func_button == 4096 then btn_name = "L3 / LS" end
                end

                imgui.spacing()
                imgui.push_style_color(5, 0xFFFFFFFF)
                imgui.push_style_color(21, 0xFFCC6600)
                imgui.push_style_color(22, 0xFFFF8800)
                imgui.push_style_color(23, 0xFFFFAA33)
                imgui.push_style_color(0, 0xFFFFCC66)
                if config.func_button then
                    -- Two buttons side by side: CHANGE + RESET
                    local avail = imgui.get_window_size().x - 40
                    local reset_w = 80
                    if imgui.button("CHANGE FUNCTION BUTTON  [" .. btn_name .. "]", Vector2f.new(avail - reset_w - 8, 35)) then
                        is_binding_mode = true
                        last_input_mask = 0
                    end
                    imgui.pop_style_color(5)
                    imgui.same_line(0, 8)
                    imgui.push_style_color(5, 0xFFFFFFFF)
                    imgui.push_style_color(21, 0xFF0000AA)
                    imgui.push_style_color(22, 0xFF0000DD)
                    imgui.push_style_color(23, 0xFF0000FF)
                    imgui.push_style_color(0, 0xFFAAAAFF)
                    if imgui.button("RESET##func_reset", Vector2f.new(reset_w, 35)) then
                        config.func_button = nil
                        save_config()
                    end
                    imgui.pop_style_color(5)
                else
                    if imgui.button("CHANGE FUNCTION BUTTON  [" .. btn_name .. "]", Vector2f.new(-1, 35)) then
                        is_binding_mode = true
                        last_input_mask = 0
                    end
                    imgui.pop_style_color(5)
                end
                imgui.spacing()

                if config.func_button then
                    imgui.text_colored("The FUNCTION button is used for all controller shortcuts.", 0xFF888888)
                    imgui.text_colored("Inputs are blocked while FUNCTION is held.", 0xFF888888)
                else
                    imgui.text_colored("No function button set. Set one to use controller shortcuts.", 0xFFFF8800)
                    imgui.text_colored("(FUNC + SQUARE = switch mode, FUNC + arrows = adjust timers)", 0xFF888888)
                end

                imgui.spacing()
                imgui.separator()
                imgui.spacing()

                -- Keyboard switch key binding
                if is_kb_binding_mode then
                    imgui.push_style_color(5, 0xFF00FFFF)
                    imgui.push_style_color(21, 0xFF005555)
                    imgui.push_style_color(22, 0xFF007777)
                    imgui.push_style_color(23, 0xFF009999)
                    imgui.push_style_color(0, 0xFF00FFFF)
                    imgui.button(">>> PRESS ANY KEY... <<<", Vector2f.new(-1, 35))
                    imgui.pop_style_color(5)
                else
                    local cur_key = combo_name(config.switch_key or 0x30, config.switch_modifiers)
                    imgui.push_style_color(5, 0xFFFFFFFF)
                    imgui.push_style_color(21, 0xFF006644)
                    imgui.push_style_color(22, 0xFF008866)
                    imgui.push_style_color(23, 0xFF00AA88)
                    imgui.push_style_color(0, 0xFF66FFCC)
                    local avail = imgui.get_window_size().x - 40
                    local reset_w = 80
                    if imgui.button("CHANGE SWITCH KEY  [" .. cur_key .. "]", Vector2f.new(avail - reset_w - 8, 35)) then
                        is_kb_binding_mode = true
                    end
                    imgui.pop_style_color(5)
                    imgui.same_line(0, 8)
                    imgui.push_style_color(5, 0xFFFFFFFF)
                    imgui.push_style_color(21, 0xFF0000AA)
                    imgui.push_style_color(22, 0xFF0000DD)
                    imgui.push_style_color(23, 0xFF0000FF)
                    imgui.push_style_color(0, 0xFFAAAAFF)
                    if imgui.button("RESET##kb_reset", Vector2f.new(reset_w, 35)) then
                        config.switch_key = 0x30
                        config.switch_modifiers = {}
                        save_config()
                    end
                    imgui.pop_style_color(5)
                end
                imgui.spacing()
                imgui.text_colored("The SWITCH KEY cycles through training modes.", 0xFF888888)
            end
        end

        -- ==========================================
        -- SECTION 2.5: HIDE UI BUTTON
        -- ==========================================
        -- SECTION 3: HELP & SHORTCUTS
        -- ==========================================
        if styled_header("--- HELP & SHORTCUTS ---", UI_THEME.hdr_help) then
            local fn = SharedUI.get_func_name()

            imgui.text_colored("HOW TO SWITCH MODES", 0xFF00FFFF)
            imgui.text("  Top bar: Click SWITCH or any mode button")
            imgui.text("  Keyboard: Press [0]")
            if fn then
                imgui.text("  Controller: [" .. fn .. "] + [Square / X]")
            end
            imgui.spacing()

            imgui.separator()
            imgui.text_colored("SHARED SHORTCUTS (Reaction / Hit Confirm / Post Guard)", 0xFF00FFFF)
            imgui.text("  Keyboard 1 : Timer -")
            imgui.text("  Keyboard 2 : Timer +")
            imgui.text("  Keyboard 3 : Reset (idle) / Stop (running)")
            imgui.text("  Keyboard 4 : Start (idle) / Pause (running)")
            if fn then
                imgui.text("  " .. fn .. "+DOWN  : Timer -")
                imgui.text("  " .. fn .. "+UP    : Timer +")
                imgui.text("  " .. fn .. "+LEFT  : Reset (idle) / Stop (running)")
                imgui.text("  " .. fn .. "+RIGHT : Start (idle) / Pause (running)")
            end
            imgui.spacing()

            imgui.separator()
            imgui.text_colored("COMBO TRIALS SHORTCUTS", 0xFF00FFFF)
            imgui.text("  Keyboard 1 : Record P1 / Stop & Save")
            imgui.text("  Keyboard 2 : Start Trial P1 / Stop Trial")
            imgui.text("  Keyboard 3 : Record P2")
            imgui.text("  Keyboard 4 : Switch Position Mode")
            if fn then
                imgui.text("  " .. fn .. "+LEFT  : Record P1 / Stop & Save")
                imgui.text("  " .. fn .. "+UP    : Start Trial P1 / Stop Trial")
                imgui.text("  " .. fn .. "+DOWN  : Record P2")
                imgui.text("  " .. fn .. "+RIGHT : Switch Position Mode")
            end
            imgui.spacing()

            imgui.separator()
            imgui.text_colored("WHAT EACH MODE DOES", 0xFF00FFFF)
            imgui.spacing()

            imgui.text_colored("REACTION DRILLS", 0xFF00FF00)
            imgui.text("  The dummy plays back random recordings.")
            imgui.text("  React to what you see and punish accordingly.")
            imgui.text("  Tracks your success rate over timed sessions.")
            imgui.spacing()

            imgui.text_colored("HIT CONFIRM", 0xFF00FF00)
            imgui.text("  Practice confirming hits into combos.")
            imgui.text("  Dummy uses random guard: if it hits, combo.")
            imgui.text("  If blocked, stay safe. Tracks your accuracy.")
            imgui.spacing()

            imgui.text_colored("POST GUARD", 0xFF00FF00)
            imgui.text("  You attack into the dummy's guard.")
            imgui.text("  The dummy reacts after blocking.")
            imgui.text("  Practice dealing with post-guard situations.")
            imgui.spacing()

            imgui.text_colored("CUSTOM COMBO TRIALS", 0xFF00FF00)
            imgui.text("  Record and practice your own combos.")
            imgui.text("  Save combos with damage/drive/SA stats.")
            imgui.text("  Replay with exact position, mirror, or free mode.")
        end


        imgui.separator()
        if not _G._hc_logging then
            if imgui.button("START HC LOG") then _G._hc_logging = true; _G._hc_log_lines = {} end
        else
            if imgui.button("STOP & SAVE LOG") then
                _G._hc_logging = false
                if _G._hc_log_lines then
                    local f = io.open("Stats/HitConfirm_Debug.txt", "w")
                    if f then f:write(table.concat(_G._hc_log_lines, "\n")); f:close() end
                end
            end
            imgui.same_line(); imgui.text(#(_G._hc_log_lines or {}) .. " lines")
        end
        imgui.tree_pop()
    end
end)

-- SESSION RECAP DISABLED FOR PERF — uncomment to re-enable
-- local SessionRecap = require("func/Training_SessionRecap")

-- D2D DISABLED — hide flash now uses nothing (visual feedback removed)
-- if d2d and d2d.register then
--     d2d.register(function() end, function()
--         if SessionRecap and SessionRecap.d2d_draw then
--             SessionRecap.d2d_draw()
--         end
--     end)
-- end