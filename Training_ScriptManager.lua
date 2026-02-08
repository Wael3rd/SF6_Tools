local re = re
local sdk = sdk
local imgui = imgui

-- ==========================================
-- 1. GESTION DES MODES (TRAINER MANAGER)
-- ==========================================
if _G.CurrentTrainerMode == nil then
    _G.CurrentTrainerMode = 0 
end

-- Gestion de l'input (Manette)
local last_input_mask = 0

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

    local function is_just_pressed(target_id)
        return (active_buttons & target_id) == target_id and (last_input_mask & target_id) ~= target_id
    end

    -- INPUT SWITCH (R3 + L3 ou Select selon config = 16448)
    if is_just_pressed(16448) then
        _G.CurrentTrainerMode = _G.CurrentTrainerMode + 1
        if _G.CurrentTrainerMode > 2 then _G.CurrentTrainerMode = 0 end
    end
    last_input_mask = active_buttons
end

-- ==========================================
-- 2. LOGIQUE DE RESTAURATION UI (NETTOYAGE)
-- ==========================================

-- Cibles spécifiques (copiées du script Reactions pour cibler le symbole Infini)
local ui_targets = {
    BattleHud_Timer = { { "c_main", "c_hud", "c_timer", "c_infinite" } }
}

-- Fonction récursive pour appliquer/retirer l'invisibilité forcé
local function apply_force_invisible(control, path, depth, should_hide)
    local depth = depth or 1
    if depth > #path then 
        -- C'est ici que la magie opère : On force l'état
        control:call("set_ForceInvisible", should_hide)
        
        -- Sécurité : Si on veut afficher (should_hide=false), on force aussi set_Visible(true)
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

-- Fonction globale de gestion de visibilité
local function manage_ui_visibility(scripts_active)
    -- 1. GESTION VIA LE MANAGER (Textes d'info et Widgets globaux)
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
                                        
                                        -- A. Textes d'info (TMAttackInfo) - On cache si scripts actifs
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

                                        -- B. Widget Ticker (Symbole Infini) - On AFFICHE si scripts INACTIFS
                                        -- Si scripts_active est faux (Mode 0), on veut voir le ticker.
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
-- 3. HOOK DE DESSIN (POUR LA RESTAURATION AGRESSIVE)
-- ==========================================
-- Ce hook s'exécute juste avant que le jeu dessine l'UI.
-- C'est le meilleur endroit pour annuler le "ForceInvisible" imposé par les autres scripts.

re.on_pre_gui_draw_element(function(element, context)
    -- Si un script est actif, on laisse le script gérer (on ne fait rien ici)
    if _G.CurrentTrainerMode ~= 0 then return true end

    -- SI MODE 0 (Désactivé) : On force la réapparition des éléments cachés
    local game_object = element:call("get_GameObject")
    if not game_object then return true end
    
    local name = game_object:call("get_Name")
    local paths = ui_targets[name]

    if paths then
        local view = element:call("get_View")
        for _, path in ipairs(paths) do 
            -- should_hide = false -> On veut afficher
            apply_force_invisible(view, path, 1, false) 
        end
    end

    return true
end)

-- ==========================================
-- 4. BOUCLE PRINCIPALE
-- ==========================================
re.on_frame(function()
    handle_input()
    
    -- Si Mode != 0, les scripts sont actifs
    local scripts_active = (_G.CurrentTrainerMode ~= 0)
    
    -- Gestion standard (Textes, Widgets globaux)
    manage_ui_visibility(scripts_active)
end)

-- ==========================================
-- 5. INTERFACE UTILISATEUR
-- ==========================================
re.on_draw_ui(function()
    if imgui.tree_node("Trainer Manager (Chef d'Orchestre)") then
        
        imgui.text("Selectionnez le mode actif :")
        
        local c0, v0 = imgui.checkbox("Desactive (Normal)", _G.CurrentTrainerMode == 0)
        if c0 and v0 then _G.CurrentTrainerMode = 0 end

        local c1, v1 = imgui.checkbox("Reaction Training", _G.CurrentTrainerMode == 1)
        if c1 and v1 then _G.CurrentTrainerMode = 1 end

        local c2, v2 = imgui.checkbox("HitConfirm Training", _G.CurrentTrainerMode == 2)
        if c2 and v2 then _G.CurrentTrainerMode = 2 end
        
        imgui.spacing()
        
        if _G.CurrentTrainerMode ~= 0 then
            imgui.text_colored("ÉTAT: SCRIPTS ACTIFS", 0xFF00FF00)
            imgui.text_colored("UI JEU: CACHÉE", 0xFF0000FF)
        else
            imgui.text_colored("ÉTAT: NORMAL", 0xFFAAAAAA)
            imgui.text_colored("UI JEU: RESTAURÉE", 0xFF00FF00)
        end

        imgui.tree_pop()
    end
end)