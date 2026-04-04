-- Training_ScriptManager.lua
-- v3.0 : Mappings de Garde Corrigés (0, 3, 4)

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
    btn_colors = { c1 = 0xFFFF0000, c2 = 0xFF00FF00, c3 = 0xFF0000FF, c4 = 0xFFDC00FF },
    btn_alphas = { c1 = 200, c2 = 200, c3 = 200, c4 = 200 },
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
        if data.btn_colors and type(data.btn_colors) == "table" then
            for k, v in pairs(data.btn_colors) do config.btn_colors[k] = v end
        end
        if data.btn_alphas and type(data.btn_alphas) == "table" then
            for k, v in pairs(data.btn_alphas) do config.btn_alphas[k] = v end
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
-- 0. ONBOARDING MESSAGE (first entry only)
-- ==========================================
local onboard_timer = 10 * 60  -- 10 seconds at 60fps
local onboard_ever_entered = false  -- true once user enters any mode
local onboard_font = nil
local onboard_font_attempted = false

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

-- Input Management (Gamepad & Keyboard)
local last_input_mask = 0
local is_binding_mode = false 
local last_kb_0_state = false -- NEW: State tracker for the '0' key

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

    -- SCRIPT SWITCH LOGIC (FUNCTION + SQUARE on Pad)
    local func_btn = _G.TrainingFuncButton
    local is_func_held = false
    if func_btn and func_btn > 0 then
        is_func_held = (active_buttons & func_btn) == func_btn
    end
    _G.TrainingFuncHeld = is_func_held
    local is_switch_pressed = (active_buttons & BTN_SQUARE) == BTN_SQUARE and (last_input_mask & BTN_SQUARE) ~= BTN_SQUARE

    -- SCRIPT SWITCH LOGIC (KEYBOARD '0' Key - VK Code 0x30)
    local is_kb_0_down = false
    pcall(function() is_kb_0_down = reframework:is_key_down(0x30) end)
    local is_kb_0_pressed = is_kb_0_down and not last_kb_0_state

    -- Trigger switch if either Pad combo or Keyboard '0' is pressed
    if (is_func_held and is_switch_pressed) or is_kb_0_pressed then
        _G.CurrentTrainerMode = _G.CurrentTrainerMode + 1
        if _G.CurrentTrainerMode > 4 then _G.CurrentTrainerMode = 0 end
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
-- 4. MAIN LOOP
-- ==========================================
re.on_frame(function()
    -- COUPE CIRCUIT ABSOLU : Aucune lecture de manette ou logique hors du training
    if not is_in_training_mode() then
        -- AUTO-RESET : On éteint tous les modes actifs si on sort du mode Training
        if _G.CurrentTrainerMode ~= 0 then
            _G.CurrentTrainerMode = 0
        end
        _G.TrainingFloatingBar = nil
        return
    end

    handle_input()

    -- Clear D2D floating bar when no training mode is active
    if _G.CurrentTrainerMode == 0 then _G.TrainingFloatingBar = nil end

    -- Track if user ever entered a mode (to hide onboarding permanently)
    if _G.CurrentTrainerMode ~= 0 then onboard_ever_entered = true end

    -- Onboarding message (disabled mode, first time only, 10 seconds)
    if _G.CurrentTrainerMode == 0 and not onboard_ever_entered and onboard_timer > 0 then
        onboard_timer = onboard_timer - 1
        local sw, sh = 1920, 1080
        pcall(function()
            local ds = imgui.get_display_size()
            if ds then sw = ds.x; sh = ds.y end
        end)

        -- Load font once
        if not onboard_font_attempted then
            onboard_font_attempted = true
            local font_scale = sh / 1080.0
            pcall(function() onboard_font = imgui.load_font("SF6_college.ttf", math.max(10, math.floor(22 * font_scale))) end)
        end

        -- Draw message at top (mirrored position of bottom bar)
        local bar_h = sh * 0.0444
        imgui.push_style_color(2, 0x00000000)
        imgui.push_style_color(5, 0x00000000)
        imgui.set_next_window_size(Vector2f.new(sw, bar_h), 1)
        imgui.set_next_window_pos(Vector2f.new(0, 0), 1)
        if imgui.begin_window("##onboard_msg", true, 15) then
            local w = imgui.get_window_size()

            if onboard_font then imgui.push_font(onboard_font) end
            local msg = "CLICK ON THE TIMER TO SWITCH TRAINING MODES"
            local tw = imgui.calc_text_size(msg).x
            local th = imgui.calc_text_size(msg).y
            imgui.set_cursor_pos(Vector2f.new((w.x - tw) / 2, (w.y - th) / 2))
            imgui.text_colored(msg, 0xFFFFFFFF)
            if onboard_font then imgui.pop_font() end

            imgui.end_window()
        end
        imgui.pop_style_color(2)

        -- Draw timer click zone highlight
        local tz_x1 = sw * 0.430
        local tz_y1 = sh * 0.04
        local tz_w = sw * 0.140
        local tz_h = sh * 0.084
        imgui.push_style_color(2, 0x00000000)
        imgui.push_style_color(5, 0xAAFF00FF)
        imgui.push_style_var(3, 2.0)
        imgui.set_next_window_size(Vector2f.new(tz_w, tz_h), 1)
        imgui.set_next_window_pos(Vector2f.new(tz_x1, tz_y1), 1)
        if imgui.begin_window("##onboard_zone", true, 15) then
            imgui.end_window()
        end
        imgui.pop_style_var(1)
        imgui.pop_style_color(2)
    end

    -- [LEFT-CLICK ON TIMER: CYCLE TRAINING MODE]
    local imgui_hovered = false
    pcall(function() imgui_hovered = imgui.is_window_hovered(8) end)
    if imgui.is_mouse_clicked(0) and not imgui_hovered then
        local sw, sh = 1920, 1080
        pcall(function()
            local ds = imgui.get_display_size()
            if ds then sw = ds.x; sh = ds.y end
        end)
        local m = imgui.get_mouse()
        local tz_x1 = sw * 0.430
        local tz_y1 = sh * 0.045
        local tz_x2 = tz_x1 + sw * 0.140
        local tz_y2 = tz_y1 + sh * 0.084
        if m.x >= tz_x1 and m.x <= tz_x2 and m.y >= tz_y1 and m.y <= tz_y2 then
            _G.CurrentTrainerMode = _G.CurrentTrainerMode + 1
            if _G.CurrentTrainerMode > 4 then _G.CurrentTrainerMode = 0 end
        end
    end

    if is_binding_mode then return end
    
    -- CHECK AUTOMATIC GUARD SWITCHING
    update_guard_logic()

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

            local c1, v1 = imgui.checkbox("REACTION DRILLS", _G.CurrentTrainerMode == 1)
            if c1 and v1 then _G.CurrentTrainerMode = 1 end

            local c2, v2 = imgui.checkbox("HIT CONFIRM", _G.CurrentTrainerMode == 2)
            if c2 and v2 then _G.CurrentTrainerMode = 2 end

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
            end
        end

        -- ==========================================
        -- SECTION 3: HELP & SHORTCUTS
        -- ==========================================
        if styled_header("--- HELP & SHORTCUTS ---", UI_THEME.hdr_help) then
            local SharedUI = require("func/Training_SharedUI")
            local fn = SharedUI.get_func_name()

            imgui.text_colored("HOW TO SWITCH MODES", 0xFF00FFFF)
            imgui.text("  Click on the in-game Timer")
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