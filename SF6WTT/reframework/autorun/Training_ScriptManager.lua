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
    func_button = 16384 -- Default: Select (Back)
}

-- Load config
local function load_config()
    local data = json.load_file(CONFIG_FILE)
    if data and data.func_button then
        config.func_button = data.func_button
    end
    -- Update Global variable so other scripts can see it
    _G.TrainingFuncButton = config.func_button
end

local function save_config()
    json.dump_file(CONFIG_FILE, config)
    _G.TrainingFuncButton = config.func_button
end

load_config()

-- ==========================================
-- 0. GUARD CONTROL UTILITIES (SAFE PATTERN)
-- ==========================================
local last_mode_state = 0
local saved_guard_state = 0 -- Par défaut 0, stocke l'état précédent
local is_guard_overridden = false

-- IDs de Garde définis par l'utilisateur
local GUARD_NO = 0
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

    elseif current_mode == 0 then
        -- >>> DISABLED >>> RESTAURATION
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

-- Input Management (Gamepad)
local last_input_mask = 0
local is_binding_mode = false 

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

    -- SCRIPT SWITCH LOGIC (FUNCTION + SQUARE)
    local func_btn = _G.TrainingFuncButton or 16384
    local is_func_held = (active_buttons & func_btn) == func_btn
    local is_switch_pressed = (active_buttons & BTN_SQUARE) == BTN_SQUARE and (last_input_mask & BTN_SQUARE) ~= BTN_SQUARE

    if is_func_held and is_switch_pressed then
        _G.CurrentTrainerMode = _G.CurrentTrainerMode + 1
        if _G.CurrentTrainerMode > 3 then _G.CurrentTrainerMode = 0 end
    end
    
    last_input_mask = active_buttons
end

-- ==========================================
-- 2. UI RESTORATION LOGIC (CLEANUP)
-- ==========================================
local ui_targets = {
    BattleHud_Timer = { { "c_main", "c_hud", "c_timer", "c_infinite" } }
}

local function apply_force_invisible(control, path, depth, should_hide)
    local depth = depth or 1
    if depth > #path then 
        control:call("set_ForceInvisible", should_hide)
        if not should_hide then control:call("set_Visible", true) end
        return 
    end

    local child = control:call("get_Child")
    while child do
        local name = child:call("get_Name")
        if name and string.match(name, path[depth]) then 
            apply_force_invisible(child, path, depth + 1, should_hide) 
        end
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
-- 3. DRAW HOOK
-- ==========================================
re.on_pre_gui_draw_element(function(element, context)
    if _G.CurrentTrainerMode ~= 0 then return true end
    local game_object = element:call("get_GameObject")
    if not game_object then return true end
    
    local name = game_object:call("get_Name")
    local paths = ui_targets[name]

    if paths then
        local view = element:call("get_View")
        for _, path in ipairs(paths) do 
            apply_force_invisible(view, path, 1, false) 
        end
    end

    return true
end)

-- ==========================================
-- 4. MAIN LOOP
-- ==========================================
re.on_frame(function()
    handle_input()
    
    if is_binding_mode then return end
    
    -- CHECK AUTOMATIC GUARD SWITCHING
    update_guard_logic()

    local scripts_active = (_G.CurrentTrainerMode ~= 0)
    manage_ui_visibility(scripts_active)
end)

-- ==========================================
-- 5. USER INTERFACE
-- ==========================================
re.on_draw_ui(function()
    if imgui.tree_node("Trainer Manager (Main Controller)") then
        
        imgui.text("Select active mode:")
        
        local c0, v0 = imgui.checkbox("Disabled (Normal)", _G.CurrentTrainerMode == 0)
        if c0 and v0 then _G.CurrentTrainerMode = 0 end

        local c1, v1 = imgui.checkbox("Reaction Drills (No Guard)", _G.CurrentTrainerMode == 1)
        if c1 and v1 then _G.CurrentTrainerMode = 1 end

        local c2, v2 = imgui.checkbox("HitConfirm (Random Guard)", _G.CurrentTrainerMode == 2)
        if c2 and v2 then _G.CurrentTrainerMode = 2 end


        local c3, v3 = imgui.checkbox("Post Guard (All Guard)", _G.CurrentTrainerMode == 3)
        if c3 and v3 then _G.CurrentTrainerMode = 3 end
        
        imgui.spacing()
        imgui.separator()
        
        -- BUTTON CONFIG
        imgui.text("Shortcut Configuration:")
        if is_binding_mode then
            imgui.text_colored(">>> PRESS ANY BUTTON... <<<", 0xFF00FFFF)
        else
            local btn_name = "ID: " .. tostring(config.func_button)
            if config.func_button == 16384 then btn_name = "SELECT / BACK" end
            if config.func_button == 8192 then btn_name = "R3 / RS" end
            if config.func_button == 4096 then btn_name = "L3 / LS" end
            
            imgui.text("Current Function Button: " .. btn_name)
            if imgui.button("CHANGE FUNCTION BUTTON") then
                is_binding_mode = true
                last_input_mask = 0 
            end
        end
        imgui.text_colored("Mode Switch Shortcut: [Function] + [Square / X]", 0xFF00FF00)
        
        imgui.separator()
        
        if _G.CurrentTrainerMode ~= 0 then
            imgui.text_colored("STATUS: SCRIPTS ACTIVE", 0xFF00FF00)
            if _G.CurrentTrainerMode == 1 then imgui.text("(No Guard [0] Active)") end
            if _G.CurrentTrainerMode == 2 then imgui.text("(Random Guard [4] Active)") end
            if _G.CurrentTrainerMode == 3 then imgui.text("(All Guard [3] Active)") end
        else
            imgui.text_colored("STATUS: NORMAL (Guard Restored)", 0xFFAAAAAA)
        end

        imgui.tree_pop()
    end
end)