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

    -- INPUT SWITCH (R3 + L3 souvent ou Select selon config = 16448)
    if is_just_pressed(16448) then
        _G.CurrentTrainerMode = _G.CurrentTrainerMode + 1
        if _G.CurrentTrainerMode > 2 then _G.CurrentTrainerMode = 0 end
    end
    last_input_mask = active_buttons
end

-- ==========================================
-- 2. LOGIQUE UI HIDER (INTEGRÉE)
-- ==========================================

-- Fonction sécurisée pour éviter les crashs
local function safe_call(obj, method, arg)
    if not obj then return end
    pcall(function() obj:call(method, arg) end)
end

-- Fonction qui applique la visibilité (True ou False)
local function apply_ui_visibility(should_be_visible)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return end

    local dict = mgr:get_field("_ViewUIWigetDict")
    local entries = dict and dict:get_field("_entries")
    if not entries then return end

    -- On utilise pcall pour sécuriser la boucle de recherche
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
                            -- On cherche le widget TMAttackInfo
                            local type_def = widget:get_type_definition()
                            if type_def and string.find(type_def:get_full_name(), "TMAttackInfo") then
                                local attack_infos = widget:get_field("AttackInfos")
                                if attack_infos then
                                    local len = attack_infos:call("get_Length")
                                    for k = 0, len - 1 do
                                        local line = attack_infos:call("GetValue", k)
                                        if line then
                                            -- On traite les 3 zones de texte
                                            local texts = {
                                                line:get_field("LeftText"),
                                                line:get_field("CenterText"),
                                                line:get_field("RightText")
                                            }
                                            for _, txt_obj in ipairs(texts) do
                                                if txt_obj then
                                                    -- C'EST ICI QUE LA MAGIE OPERE
                                                    -- Si HitConfirm est actif, should_be_visible sera false -> Cache
                                                    -- Sinon, should_be_visible sera true -> Affiche
                                                    safe_call(txt_obj, "set_Visible", should_be_visible)
                                                end
                                            end
                                        end
                                    end
                                end
                                return -- Optimisation : on a trouvé, on sort
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ==========================================
-- 3. BOUCLE PRINCIPALE
-- ==========================================
re.on_frame(function()
    handle_input()
    
    -- DÉTECTION DU MODE :
    -- Si Mode == 2 (HitConfirm), on veut que ce soit CACHÉ (Visible = false)
    -- Si Mode != 2, on veut que ce soit VISIBLE (Visible = true)
    local is_hit_confirm_active = (_G.CurrentTrainerMode ~= 0)
    
    -- On applique la visibilité inverse de l'état "Actif"
    -- Actif = Caché (false)
    -- Inactif = Visible (true)
    apply_ui_visibility(not is_hit_confirm_active)
end)

-- ==========================================
-- 4. INTERFACE UTILISATEUR
-- ==========================================
re.on_draw_ui(function()
    if imgui.tree_node("Trainer Manager (Chef d'Orchestre)") then
        
        imgui.text("Selectionnez le mode actif :")
        
        local c0, v0 = imgui.checkbox("Desactive", _G.CurrentTrainerMode == 0)
        if c0 and v0 then _G.CurrentTrainerMode = 0 end

        local c1, v1 = imgui.checkbox("Reaction Training", _G.CurrentTrainerMode == 1)
        if c1 and v1 then _G.CurrentTrainerMode = 1 end

        -- C'est ce mode qui déclenchera le masquage du texte
        local c2, v2 = imgui.checkbox("HitConfirm Training", _G.CurrentTrainerMode == 2)
        if c2 and v2 then _G.CurrentTrainerMode = 2 end
        
        imgui.spacing()
        imgui.text_colored("Input Detecte: " .. tostring(last_input_mask), 0xFFAAAAAA)
        
        -- Petit indicateur visuel pour confirmer l'état
        if _G.CurrentTrainerMode ~= 0 then
            imgui.text_colored("UI TEXTE : CACHÉ", 0xFF0000FF)
        else
            imgui.text_colored("UI TEXTE : VISIBLE", 0xFF00FF00)
        end

        imgui.tree_pop()
    end
end)