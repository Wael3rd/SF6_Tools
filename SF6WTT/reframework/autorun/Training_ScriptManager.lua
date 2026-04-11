-- Training_ScriptManager.lua
-- v4.0 : Top floating bar + new cycling order

local re = re
local sdk = sdk
local imgui = imgui
local json = json

-- ==========================================
-- CONFIGURATION & SAVING
-- ==========================================
local CONFIG_FILE = "TrainingManager_Config.json"

local config = {
    func_button = nil, -- No default: must be set by user via CHANGE FUNCTION BUTTON
    switch_key = 0x30, -- Keyboard key for mode switch (default: '0' = VK 0x30)
    btn_colors = { c1 = 0xFFFF0000, c2 = 0xFF00FF00, c3 = 0xFF0000FF, c4 = 0xFFDC00FF },
    btn_alphas = { c1 = 200, c2 = 200, c3 = 200, c4 = 200 },
    -- Top bar colors (ARGB)
    top_colors = { switch = 0xFF0066FF, active = 0xFF01FF00, inactive = 0xFF666666 },
    top_alphas = { switch = 170, active = 170, inactive = 120 },
}

-- ARGB -> ABGR conversion
local function argb_to_abgr(argb)
    local a = (argb >> 24) & 0xFF
    local r = (argb >> 16) & 0xFF
    local g = (argb >> 8) & 0xFF
    local b = argb & 0xFF
    return (a << 24) | (b << 16) | (g << 8) | r
end

-- Build SC_COLORS style table from ARGB color + fill alpha
local function build_sc_color(argb, fill_alpha)
    local abgr = argb_to_abgr(argb)
    local rgb = abgr & 0x00FFFFFF
    return {
        text   = abgr,
        base   = ((fill_alpha & 0xFF) << 24) | rgb,
        hover  = ((math.min(255, fill_alpha + 40) & 0xFF) << 24) | rgb,
        active = ((math.min(255, fill_alpha + 80) & 0xFF) << 24) | rgb,
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
    local data = json.load_file(CONFIG_FILE)
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
-- ==========================================
local function is_in_training_mode()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if tm then
        local tData = tm:get_field("_tData")
        if tData ~= nil then return true end
    end
    return false
end

-- ==========================================
-- 0.1 GUARD CONTROL UTILITIES (SAFE PATTERN)
-- ==========================================
local last_mode_state = 0
local saved_guard_state = 0 -- Par défaut 0, stocke l'état précédent
local is_guard_overridden = false

-- IDs de Garde définis par l'utilisateur
local GUARD_NO = 0
local GUARD_AFTER_FIRST_HIT = 2
local GUARD_ALL = 3
local GUARD_RANDOM = 4

-- Fonction de sécurité pour éviter les crashs
local function call_fresh(target_type, method, ...)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return false end
    
    local obj = nil
    if target_type == "TM" then 
        obj = mgr 
    elseif target_type == "Guard" then 
        local ok, guard = pcall(function() return mgr:call("get_GuardFunc") end)
        if ok and guard then obj = guard end
    end

    if not obj or sdk.to_int64(obj) == 0 then return false end
    
    local args = {...}
    return pcall(function() return obj:call(method, table.unpack(args)) end)
end

-- Fonction pour appliquer la garde proprement
local function set_guard_type(guard_id)
    -- 1. Applique le type au Dummy (ID 1)
    call_fresh("Guard", "ChangeGuardType", 1, guard_id)
    -- 2. Force le rafraichissement
    call_fresh("TM", "set_IsReqRefresh", true)
end

local function update_guard_logic()
    local current_mode = _G.CurrentTrainerMode or 0
    
    -- Si le mode n'a pas changé, on ne fait rien
    if current_mode == last_mode_state then return end

    -- LOGIQUE DE CHANGEMENT
    
    -- Si on passe d'un mode inactif (0) à un mode actif (1, 2, 3), on "sauvegarde" l'état fictif
    -- (Note: Sans fonction get_GuardType fiable, on assume que l'utilisateur commence en No Guard ou veut y revenir)
    if last_mode_state == 0 and current_mode ~= 0 then
        if not is_guard_overridden then
            saved_guard_state = 0 -- On reviendra à 0 par défaut
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


    elseif current_mode == 0 then
        -- >>> DISABLED / COMBO TRIALS >>> RESTAURATION
        if is_guard_overridden then
            set_guard_type(saved_guard_state) -- Retour à 0 (ou l'état sauvegardé)
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

-- Cycling order: DISABLED → HIT CONFIRM → REACTION DRILLS → POST GUARD → CUSTOM COMBO TRIALS → DISABLED
local MODE_CYCLE = { 0, 2, 1, 3, 4 }
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

    -- KEYBOARD BINDING LOGIC (scan all keys)
    if is_kb_binding_mode then
        pcall(function()
            -- Scan common key range (0x08-0x7F covers most useful keys)
            for vk = 0x08, 0x7F do
                if reframework:is_key_down(vk) then
                    config.switch_key = vk
                    save_config()
                    is_kb_binding_mode = false
                    break
                end
            end
        end)
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

    -- SCRIPT SWITCH LOGIC (configurable keyboard key)
    local switch_vk = config.switch_key or 0x30
    local is_kb_0_down = false
    pcall(function() is_kb_0_down = reframework:is_key_down(switch_vk) end)
    local is_kb_0_pressed = is_kb_0_down and not last_kb_0_state

    -- Trigger switch if either Pad combo or Keyboard '0' is pressed
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
    pcall(function() obj:call(method, arg) end)
end

local function manage_ui_visibility(scripts_active)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if mgr then
        local dict = mgr:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")
        
        if entries then
            pcall(function()
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
            end)
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
    
    -- DÉTECTION FLOUE GLOBALE DU HUD
    if name and string.find(name, "BattleHud_Timer") then
        -- 1. Extraction du suffixe pour TOUS les autres scripts
        local suffix = string.match(name, "BattleHud_Timer(.*)")
        if suffix == "" or suffix == nil then suffix = "Default" end
        _G.CurrentHudSuffix = suffix
        
        -- 2. Gestion de la visibilité du symbole infini (Jamais caché en mode 4)
        local hide_infinite = (_G.CurrentTrainerMode == 1 or _G.CurrentTrainerMode == 2 or _G.CurrentTrainerMode == 3)
        
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

local function rebuild_top_colors()
    SWITCH_COLOR  = build_sc_color(config.top_colors.switch, config.top_alphas.switch)
    MODE_ACTIVE   = build_sc_color(config.top_colors.active, config.top_alphas.active)
    MODE_INACTIVE = build_sc_color(config.top_colors.inactive, config.top_alphas.inactive)
end

local top_bar_width = 0.746
local top_bar_height = 0.0444

local MODE_BUTTONS = {
    { id = 0, label = "DISABLED" },
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
    local key_label = vk_name(config.switch_key or 0x30)
    if SharedUI.is_keyboard_mode() or not fn then
        switch_label = "SWITCH (" .. key_label .. ")"
    else
        switch_label = "SWITCH (" .. fn .. " + SQUARE/X)"
    end

    -- Calculate button widths: use longest possible label for stable width
    local switch_max = fn and ("SWITCH (" .. fn .. " + SQUARE/X)") or "SWITCH (BACKSPACE)"
    local switch_w = imgui.calc_text_size(switch_max).x + 20
    local remaining = content_w - switch_w - sp * #MODE_BUTTONS
    local mode_w = remaining / #MODE_BUTTONS

    imgui.set_cursor_pos(Vector2f.new(sw * 0.0075, sh * 0.01))
    if SharedUI.sf6_button(switch_label .. "##sw_top", SWITCH_COLOR, switch_w) then
        cycle_next_mode()
    end

    for _, btn in ipairs(MODE_BUTTONS) do
        imgui.same_line(0, sp)
        local is_active = (_G.CurrentTrainerMode == btn.id)
        local colors = is_active and MODE_ACTIVE or MODE_INACTIVE
        if SharedUI.sf6_button(btn.label .. "##top_" .. btn.id, colors, mode_w) then
            _G.CurrentTrainerMode = btn.id
        end
    end

    SharedUI.end_floating_window_top()
end

-- ==========================================
-- 4. MAIN LOOP
-- ==========================================
local _tsm_replay_delay = 3.00  -- secondes avant de relancer le script après un replay
local _tsm_replay_timer = 0
local _tsm_was_replay = false

local function get_flowmap_id()
    local ok, id = pcall(function()
        local bfm = sdk.get_managed_singleton("app.bFlowManager")
        if not bfm then return nil end
        local work = bfm:get_field("m_flow_work")
        if work and work._FlowMap then return work._FlowMap._ID end
        return nil
    end)
    return ok and id or nil
end

re.on_frame(function()
    SharedUI.clear_rects()

    -- Détection FlowMap
    local fid = get_flowmap_id()
    _G.FlowMapID = fid
    _G.IsInBattleHub = (fid == 9)
    local is_replay = (fid == 10) or (_G.IsInReplay == true)

    -- BattleHub : toujours désactivé
    if _G.IsInBattleHub then
        if _G.CurrentTrainerMode ~= 0 then _G.CurrentTrainerMode = 0 end
        _G.TrainingFloatingBar = nil
        _G.TrainingFloatingBarTop = nil
        _G.TrainingModeActive = false
        _G.TrainingGamePaused = true
        return
    end

    -- Replay : désactiver une seule fois, puis timer, puis désactivé (pas de top bar)
    if is_replay then
        if _tsm_was_replay == false then
            -- Première détection
            _tsm_was_replay = "waiting"
            _tsm_replay_timer = 0
            if _G.CurrentTrainerMode ~= 0 then _G.CurrentTrainerMode = 0 end
            _G.TrainingFloatingBar = nil
            _G.TrainingFloatingBarTop = nil
            _G.TrainingModeActive = false
        end
        if _tsm_was_replay == "waiting" then
            _tsm_replay_timer = _tsm_replay_timer + (1.0 / 60.0)
            if _tsm_replay_timer >= _tsm_replay_delay then
                _tsm_was_replay = "done"
                _G.CurrentTrainerMode = 4
            end
        end
        -- En replay : toujours return, pas de top bar, pas de guard logic
        _G.TrainingFloatingBarTop = nil
        _G.TrainingModeActive = true
        return
    end

    -- Reset quand on quitte le replay
    if _tsm_was_replay ~= false then
        _tsm_was_replay = false
    end
    -- COUPE CIRCUIT ABSOLU : Aucune lecture de manette ou logique hors du training
    if not is_in_training_mode() then
        -- AUTO-RESET : On éteint tous les modes actifs si on sort du mode Training
        if _G.CurrentTrainerMode ~= 0 then
            _G.CurrentTrainerMode = 0
        end
        _G.TrainingFloatingBar = nil
        _G.TrainingFloatingBarTop = nil
        _G.TrainingModeActive = false
        _G.TrainingGamePaused = true
        return
    end
    _G.TrainingModeActive = true

    handle_input()

    -- Clear D2D floating bar when no training mode is active
    if _G.CurrentTrainerMode == 0 then _G.TrainingFloatingBar = nil end

    if is_binding_mode then return end

    -- CHECK AUTOMATIC GUARD SWITCHING
    update_guard_logic()

    -- TOP FLOATING BAR (hide during pause menu)
    local pm = sdk.get_managed_singleton("app.PauseManager")
    local pause_bit = pm and pm:get_field("_CurrentPauseTypeBit")
    local in_pause_menu = pause_bit and (pause_bit ~= 64 and pause_bit ~= 2112)
    _G.TrainingGamePaused = in_pause_menu
    if not in_pause_menu then
        draw_top_floating_bar()
    end

    local scripts_active = (_G.CurrentTrainerMode == 1 or _G.CurrentTrainerMode == 2 or _G.CurrentTrainerMode == 3 or (_G.CurrentTrainerMode == 4 and _G.ComboTrials_HideNativeHUD))
    manage_ui_visibility(scripts_active)
end)

-- ==========================================
-- 5. USER INTERFACE
-- ==========================================
-- Styled headers (same as ComboTrials)
local UI_THEME = {
    hdr_modes   = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_config  = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    hdr_help    = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
}

local function styled_header(label, style)
    imgui.push_style_color(24, style.base)
    imgui.push_style_color(25, style.hover)
    imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

re.on_draw_ui(function()
    -- Publish REFramework menu window rect for overlap detection
    pcall(function()
        local wpos = imgui.get_window_pos()
        local wsz = imgui.get_window_size()
        if wpos and wsz and _G.FloatingRects then
            _G._ref_menu_rect = { x = wpos.x, y = wpos.y, w = wsz.x, h = wsz.y }
        end
    end)

    if imgui.tree_node("TRAINING SCRIPT MANAGER") then

        -- Si on n'est pas en training, on affiche un message d'attente et on bloque l'UI
        if not is_in_training_mode() then
            imgui.text_colored("[!] INACTIF : En attente du Mode Training...", 0xFF00A5FF)
            imgui.tree_pop()
            return
        end

        -- ==========================================
        -- SECTION 1: MODE SELECTION
        -- ==========================================
        if styled_header("--- TRAINING MODES ---", UI_THEME.hdr_modes) then
            local c0, v0 = imgui.checkbox("DISABLED", _G.CurrentTrainerMode == 0)
            if c0 and v0 then _G.CurrentTrainerMode = 0 end

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

                imgui.text_colored("The FUNCTION button is used for all controller shortcuts.", 0xFF888888)
                imgui.text_colored("Inputs are blocked while FUNCTION is held.", 0xFF888888)

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
                    local cur_key = vk_name(config.switch_key or 0x30)
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
                        save_config()
                    end
                    imgui.pop_style_color(5)
                end
                imgui.spacing()
                imgui.text_colored("The SWITCH KEY cycles through training modes.", 0xFF888888)
            end
        end

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


        imgui.tree_pop()
    end
end)