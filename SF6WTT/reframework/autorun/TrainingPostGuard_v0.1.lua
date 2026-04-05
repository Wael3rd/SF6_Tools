local re = re
local sdk = sdk
local imgui = imgui
local draw = draw
local json = json

-- =========================================================
-- TrainingPostGuard (V1.13 - Flicker Fix)
-- =========================================================

local DEPENDANT_ON_MANAGER = true 
local MY_TRAINER_ID = 3

-- =========================================================
-- CONFIGURATION
-- =========================================================
local CONFIG_FILENAME = "TrainingPostGuard_Config.json"
local LOG_FILENAME    = "PostGuard_Stats.txt"

local COLORS = {
    White  = 0xFFDADADA, Green  = 0xFF00FF00, Red    = 0xFF0000FF,
    Grey   = 0x99FFFFFF, DarkGrey = 0xFF888888, Orange = 0xFF00A5FF, 
    Cyan   = 0xFFFFFF00, Yellow = 0xFF00FFFF, 
    Shadow = 0xFF000000, Blue   = 0xFFFFAA00 
}

local UI_THEME = {
    hdr_info    = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_session = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    btn_neutral = { base = 0xFF444444, hover = 0xFF666666, active = 0xFF222222 },
    btn_green   = { base = 0xFF00AA00, hover = 0xFF00CC22, active = 0xFF007700 },
    btn_red     = { base = 0xFF0000CC, hover = 0xFF2222FF, active = 0xFF000099 },
}

local SharedUI = require("func/Training_SharedUI")
local SessionRecap = require("func/Training_SessionRecap")

local user_config = {
    timer_minutes = 1,
    hud_base_size = 20.24,
    hud_auto_scale = true,
    hud_n_global_y = -0.337,
    hud_n_spacing_y = 0.02800000086426735,
    hud_n_spread_score = 0.09000000357627869,
    hud_n_offset_score = 0.0,
    hud_n_offset_total = 0.0,
    hud_n_offset_timer = 0.0,
    hud_n_offset_status_y = 0.0,
    timer_hud_y = -0.46,      
    timer_font_size = 80,     
    timer_offset_x = 0.0,
    
    block_stun_grace = 10,     
    observation_window = 120,
    show_debug = false,
    show_floating = true
}

-- STATES
local STATE_NEUTRAL = 0
local STATE_HURT    = 9
local STATE_BLOCK   = 10
local STATE_DI      = 11 
local STATE_PARRY   = 12
local STATE_ACTIVE  = 13 
local STATE_STARTUP = 7
local STATE_RECOVER = 8

-- PHASES
local PHASE_WAIT_BLOCK   = 0
local PHASE_OBSERVATION  = 1
local PHASE_RESULT       = 2

local session = {
    is_running = false, is_paused = false, is_time_up = false,
    start_ts = os.time(), real_start_time = os.time(), 
    time_rem = 0, last_clock = 0,
    
    -- SCORING VARIABLES
    score = 0,          -- Points
    success_count = 0,  -- Real Success
    total = 0,          -- Total
    
    last_score = 0, score_col = COLORS.White, score_timer = 0,
    
    phase = PHASE_WAIT_BLOCK,
    timer_action = 0,
    
    -- Logic Flags
    p2_has_attacked_ground = false,
    p2_was_in_air = false,
    p2_air_attack_confirmed = false,
    p2_has_di = false,
    p2_throw_tech_detected = false,  -- Flag: a-t-on vu un throw tech ?
    p2_was_in_parry = false,  -- Flag: P2 était en parry
    throw_in_progress = false,  -- Flag: une choppe est en cours
    
    -- Time Up
    time_up_delay = 0,
    
    feedback = { text = "READY", timer = 0, color = COLORS.Grey },
    
    p1_state = 0, p2_state = 0, p1_max_frame = 0, p2_max_frame = 0
}

-- =========================================================
-- TOOLS
-- =========================================================


local function styled_button(label, style, text_col) imgui.push_style_color(21, style.base); imgui.push_style_color(22, style.hover); imgui.push_style_color(23, style.active); if text_col then imgui.push_style_color(0, text_col) end; local clicked = imgui.button(label); if text_col then imgui.pop_style_color(1) end; imgui.pop_style_color(3); return clicked end
local function styled_header(label, style) imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active); local is_open = imgui.collapsing_header(label); imgui.pop_style_color(3); return is_open end

-- =========================================================
-- GAME MEMORY READERS
-- =========================================================

local function get_act_st(player_index)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return 0 end
    local player_mgr = gBattle:get_field("Player"):get_data(nil)
    if not player_mgr then return 0 end
    local player = player_mgr:call("getPlayer", player_index)
    if not player then return 0 end
    
    local t = player:get_type_definition()
    if not t then return 0 end
    local field = t:get_field("act_st")
    if not field then return 0 end
    local val = field:get_data(player)
    return tonumber(tostring(val)) or 0
end

local function get_p1_extended_info()
    local info = { catch_flag = false, trade_dm_flag = false } -- On ajoute le champ par défaut
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return info end
    local player_mgr = gBattle:get_field("Player"):get_data(nil)
    if not player_mgr then return info end
    local p1 = player_mgr:call("getPlayer", 0) 
    if not p1 then return info end
    
    -- Lecture de catch_flag (true = en train de chopper)
    local catch = p1:get_field("catch_flag")
    if catch then info.catch_flag = (tostring(catch) == "true") end
    
    -- NOUVEAU : Lecture du trade_dm_flag
    local trade = p1:get_field("trade_dm_flag")
    if trade then info.trade_dm_flag = (tostring(trade) == "true") end
    
    return info
end

local function get_p2_extended_info()
    local info = { pose_st = 0, suki_flag = false, catch_muteki = 0, throw_tech_no = 0 }
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return info end
    local player_mgr = gBattle:get_field("Player"):get_data(nil)
    if not player_mgr then return info end
    local p2 = player_mgr:call("getPlayer", 1) 
    if not p2 then return info end
    
    local pose = p2:get_field("pose_st"); if pose then info.pose_st = tonumber(tostring(pose)) end
    local suki = p2:get_field("land_suki_flag"); if suki then info.suki_flag = (tostring(suki) == "true") end
    
    -- Lecture de catch_muteki (3 = en train de se faire chopper)
    local muteki = p2:get_field("catch_muteki")
    if muteki then info.catch_muteki = tonumber(tostring(muteki)) or 0 end
    
    -- Lecture de throw_tech_no (0 = choppe réussie, >0 = throw tech)
    local tech_no = p2:get_field("throw_tech_no")
    if tech_no then info.throw_tech_no = tonumber(tostring(tech_no)) or 0 end
    
    return info
end

local function export_stats()
    local file = io.open(LOG_FILENAME, "a"); if not file then return end
    
    -- On ajoute la colonne DETAILS au header si le fichier est vide
    if file:seek("end") == 0 then file:write("DATE\tDURATION\tSCORE\tSUCCESS_PCT\tTOTAL\tDETAILS\n") end
    
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local duration = os.difftime(os.time(), session.real_start_time)
    
    local pct = 0.0
    if session.total > 0 then 
        pct = (session.success_count / session.total) * 100.0 
    end
    
    -- Création de la chaîne de caractères pour les détails (Format: Clé:Valeur|Clé:Valeur...)
    local details_str = ""
    if session.detailed_stats then
        for k, v in pairs(session.detailed_stats) do
            -- On nettoie un peu le texte pour éviter les tabulations ou retours à la ligne
            local clean_key = string.gsub(k, "\t", " ")
            details_str = details_str .. clean_key .. "=" .. v .. "|"
        end
    end
    
	local line = string.format("%s\t%s\t%d\t%.2f%%\t%d\t%s", now, SharedUI.format_time(duration), session.score, pct, session.total, details_str)    
    
	file:write(line .. "\n")
    file:close()
end

-- =========================================================
-- LOGIC
-- =========================================================

local function set_feedback(msg, color, duration)
    session.feedback.text = msg; session.feedback.color = color
    if duration and duration > 0 then session.feedback.timer = duration else session.feedback.timer = 0 end
end

local function reset_session_stats()
    SessionRecap.hide()
    session.score = 0; session.total = 0; session.success_count = 0
    session.is_running = false; session.is_paused = false; session.is_time_up = false
    session.time_rem = user_config.timer_minutes * 60
    session.phase = PHASE_WAIT_BLOCK
    session.timer_action = 0
    session.time_up_delay = 0
    
    -- NOUVEAU : Table pour stocker le détail des outcomes
    session.detailed_stats = {} 
    
    session.p2_has_attacked_ground = false
    session.p2_was_in_air = false
    session.p2_air_attack_confirmed = false
    session.p2_has_di = false
    session.p2_throw_tech_detected = false
    session.p2_was_in_parry = false
    session.throw_in_progress = false
    
    session.real_start_time = os.time()
    set_feedback("READY", COLORS.White, 0)
end

local function reset_round()
    session.phase = PHASE_WAIT_BLOCK
    session.timer_action = 0
    session.p2_has_attacked_ground = false
    session.p2_was_in_air = false
    session.p2_air_attack_confirmed = false
    session.p2_has_di = false
    session.p2_throw_tech_detected = false
    session.p2_was_in_parry = false
    session.throw_in_progress = false
end

local function reset_round_silent()
    reset_round()
    session.feedback.text = "WAITING..."
    session.feedback.color = COLORS.Grey
end

local function evaluate_outcome(success, reason)
    session.total = session.total + 1
    
    -- NOUVEAU : On incrémente le compteur pour cette raison spécifique
    if session.detailed_stats then
        if not session.detailed_stats[reason] then
            session.detailed_stats[reason] = 0
        end
        session.detailed_stats[reason] = session.detailed_stats[reason] + 1
    end

    if success then
        session.score = session.score + 1
        session.success_count = session.success_count + 1 
        set_feedback(reason, COLORS.Green, 0.5) -- Délai court comme vu ensemble
    else
        session.score = session.score - 1
        set_feedback(reason, COLORS.Red, 0.5)
    end
    session.phase = PHASE_RESULT
    session.timer_action = 30 -- ~0.5 sec de pause logique
end

local function update_logic()
    local dt = 0.016 
    
    -- GESTION SCORE VISUEL
    if session.score ~= session.last_score then session.score_col = (session.score > session.last_score) and COLORS.Green or COLORS.Red; session.score_timer = 30; session.last_score = session.score end
    if session.score_timer > 0 then session.score_timer = session.score_timer - 1; if session.score_timer <= 0 then session.score_col = COLORS.White end end
    
    -- TIME UP LOOP
    if session.is_time_up then 
        session.time_up_delay = (session.time_up_delay or 0) + dt
        if session.time_up_delay < 1.5 then 
             set_feedback("TIME UP! & EXPORTED", COLORS.Red, 0)
        else
             set_feedback(SharedUI.reset_message(), COLORS.Yellow, 0)
        end
        return 
    end
    
    if not session.is_running or session.is_paused then return end

    session.time_rem = session.time_rem - dt
    if session.time_rem <= 0 then 
        session.time_rem = 0
        if not session.is_time_up then
            session.is_time_up = true 
            session.time_up_delay = 0 
            export_stats()
            SessionRecap.show("POST GUARD", LOG_FILENAME, "postguard")
        end
        set_feedback("TIME UP! & EXPORTED", COLORS.Red, 0)
        return
    end

    if session.feedback.timer > 0 then
        session.feedback.timer = session.feedback.timer - dt
        if session.feedback.timer <= 0 then session.feedback.text = "WAITING..."; session.feedback.color = COLORS.Grey end
    end
    
    -- =========================================================
    -- LECTURE DES ETATS (ACT_ST & FRAMEDATA)
    -- =========================================================
    
    -- Mise à jour des FrameDataState via le Hook
    session.p1_state = session.p1_max_frame -- 13 = Active, 9 = Hurt
    session.p2_state = session.p2_max_frame
    session.p1_max_frame = 0; session.p2_max_frame = 0 
    
    local p1_act_st = get_act_st(0) -- P1 Action (37 = Throwing)
    local p2_act_st = get_act_st(1) -- P2 Action (39 = Parry, 38 = Thrown)
	local p1_mem = get_p1_extended_info()
    local p2_mem = get_p2_extended_info() -- Pour le Tech et l'Air state

    -- =========================================================
    -- LOGIQUE DE CHOPPE (GLOBAL)
    -- =========================================================

    if p2_mem.throw_tech_no > 0 then session.p2_throw_tech_detected = true end

    -- Animation de choppe
    if p1_act_st == 37 and p2_act_st == 38 then
        session.throw_in_progress = true
    end
    
    if session.throw_in_progress then
        if p1_act_st == 0 and p2_act_st == 0 then
            session.throw_in_progress = false
        else
            if not session.p2_throw_tech_detected and session.phase ~= PHASE_RESULT then
                 evaluate_outcome(true, "SUCCESS: THROW CONNECTED!")
            end
            return
        end
    end

    -- =========================================================
    -- PHASES DE JEU
    -- =========================================================

    if session.phase == PHASE_WAIT_BLOCK then
        
        if p1_act_st == 37 and p2_act_st == 38 and not session.p2_throw_tech_detected then
            evaluate_outcome(true, "SUCCESS: THROW (PRE-BLOCK)!")
            return
        end
        
        if session.p2_state == STATE_BLOCK then
            session.phase = PHASE_OBSERVATION
            session.timer_action = 0
            session.p2_has_attacked_ground = false
            session.p2_was_in_air = false
            session.p2_air_attack_confirmed = false
            session.p2_has_di = false
            session.p2_throw_tech_detected = false
            session.p2_has_parried = false 
        end

    elseif session.phase == PHASE_OBSERVATION then
        
		-- [PRIORITÉ ABSOLUE] CHECK DU TRADE
        -- On le met ici pour qu'il passe AVANT le check "FAIL: GOT HIT"
        if p1_mem.trade_dm_flag then
             evaluate_outcome(true, "SUCCESS: PERFECT PARRY!")
             return
        end
		
        -- [PRIORITÉ 0] FAIL CRITIQUE : JE ME SUIS FAIT TOUCHER
        -- Si P1 est touché (State 9), c'est perdu tout de suite.
        -- On exclut le cas du DI (géré plus bas) pour avoir le bon message d'erreur.
        if session.p1_state == STATE_HURT and session.p2_state ~= STATE_DI then 
            evaluate_outcome(false, "FAIL: GOT HIT")
            return 
        end

        -- 1. DETECTION PARRY (Flag)
        if p2_act_st == 39 then session.p2_has_parried = true end

        -- 2. CHECK FAIL : TAPER DANS LE PARRY
        -- Si P2 Parry (39) ET P1 Active (13) -> Fail
        if p2_act_st == 39 and session.p1_state == STATE_ACTIVE then
            if p1_act_st ~= 37 then -- Sauf si c'est une choppe
                evaluate_outcome(false, "FAIL: HIT PARRY!")
                return
            end
        end

        -- 3. CHECK SUCCESS : CHOPPE PUNISH
        if p1_act_st == 37 and p2_act_st == 38 and not session.p2_throw_tech_detected then
             evaluate_outcome(true, "SUCCESS: THROW PUNISH!")
             return
        end

        -- 4. CHECK SUCCESS : PUNITION REUSSIE (HURT)
        if session.p2_state == STATE_HURT then
             evaluate_outcome(true, "SUCCESS: PUNISH!")
             return
        end

        -- 5. CHECK FAIL : WHIFF PUNISH RATÉ (LOGIQUE PARRY/DRIVE RUSH)
        if session.p2_has_parried then
            -- On ne valide l'échec QUE si P2 est revenu au Neutre (0).
            -- S'il est en Startup (7) ou Dash (18) ou autre, on continue d'attendre.
            if p2_act_st == 0 then
                evaluate_outcome(false, "FAIL: MISSED PARRY PUNISH")
                return
            end
        end

        -- 6. DI CHECK
        if session.p2_state == STATE_DI then session.p2_has_di = true end
        if session.p2_has_di then
            if session.p1_state == STATE_DI then evaluate_outcome(true, "SUCCESS: DI COUNTER!"); return
            elseif session.p1_state == STATE_HURT then evaluate_outcome(false, "FAIL: CRUSHED BY DI"); return
            elseif session.p2_state == STATE_NEUTRAL then evaluate_outcome(false, "FAIL: MISSED DI COUNTER"); return end
            return
        end
        
        -- 7. TIMEOUT / SAFE / ANTI-AIR RATÉ
        -- Gestion classique si ce n'était pas un Parry
        if not session.p2_has_parried then
            if p2_mem.pose_st >= 2 then session.p2_was_in_air = true; if p2_mem.suki_flag then session.p2_air_attack_confirmed = true end end
            
            if session.p2_was_in_air and session.p2_state == STATE_NEUTRAL then
                if session.p2_air_attack_confirmed then evaluate_outcome(false, "FAIL: MISSED ANTI-AIR") else reset_round_silent() end
                return
            end
            
            if not session.p2_was_in_air and session.p2_state ~= STATE_NEUTRAL and session.p2_state ~= STATE_BLOCK and session.p2_state ~= STATE_DI then
                 session.p2_has_attacked_ground = true
            end
            if session.p2_has_attacked_ground and session.p2_state == STATE_NEUTRAL then
                 evaluate_outcome(false, "FAIL: MISSED WHIFF PUNISH")
                 return
            end
        end

        session.timer_action = session.timer_action + 1
        if session.timer_action > user_config.observation_window then
            if not session.p2_has_attacked_ground and not session.p2_air_attack_confirmed and not session.p2_has_parried then 
            --    evaluate_outcome(true, "SUCCESS: SAFE") 
            elseif p2_act_st == 0 then
                reset_round_silent() 
            end
        end

    elseif session.phase == PHASE_RESULT then
	
	-- AJOUT : Si on retape dans la garde (P2 Block), on relance tout de suite
        if session.p2_state == STATE_BLOCK then
            reset_round() -- Réinitialise les variables et revient en mode attente
            return        -- On arrête là pour cette frame, la prochaine frame lancera l'OBSERVATION
        end
		
        session.timer_action = session.timer_action - 1
        if session.timer_action <= 0 then
            reset_round()
        end
    end
end
-- =========================================================
-- INPUT HANDLING
-- =========================================================
local last_input_mask = 0
local BTN_UP, BTN_DOWN, BTN_LEFT, BTN_RIGHT = 1, 2, 4, 8
local last_kb_state = { [0x31]=false, [0x32]=false, [0x33]=false, [0x34]=false }

local function handle_input()
    local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
    local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
    if not gamepad_manager then return end
    local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
    if not devices then return end
    local count = devices:call("get_Count") or 0; local active_buttons = 0
    for i = 0, count - 1 do
        local pad = devices:call("get_Item", i)
        if pad then local b = pad:call("get_Button") or 0; if b > 0 then active_buttons = b; break end end
    end

    local func_btn = _G.TrainingFuncButton or 16384
    local is_func_held = ((active_buttons & func_btn) == func_btn)

    local kb_state = {}
    for _, k in ipairs({0x31, 0x32, 0x33, 0x34}) do
        local ok, down = pcall(function() return reframework:is_key_down(k) end)
        kb_state[k] = ok and down
    end
    local function kb_pressed(k) return kb_state[k] and not last_kb_state[k] end
    local function pad_pressed(btn) return ((active_buttons & btn) == btn) and not ((last_input_mask & btn) == btn) end
    local function is_action(btn, kb) return (is_func_held and pad_pressed(btn)) or kb_pressed(kb) end

    if session.is_time_up then
         if is_action(BTN_LEFT, 0x34) then
            reset_session_stats(); set_feedback("RESET DONE", COLORS.White, 1.0)
        end
    else
        if not session.is_running then
             if is_action(BTN_UP, 0x32) then
                user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1)
                session.time_rem = user_config.timer_minutes * 60; set_feedback("TIMER: "..user_config.timer_minutes.." MIN", COLORS.White, 1.0)
             end
             if is_action(BTN_DOWN, 0x31) then
                user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1)
                session.time_rem = user_config.timer_minutes * 60; set_feedback("TIMER: "..user_config.timer_minutes.." MIN", COLORS.White, 1.0)
             end
        end
        -- POSITION 3 (key 3): START when not running, STOP when running
        local pos3_kb = kb_pressed(0x33)
        local pos3_pad = is_func_held and pad_pressed(BTN_RIGHT)
        local pos4_kb = kb_pressed(0x34)
        local pos4_pad = is_func_held and pad_pressed(BTN_LEFT)

        -- Position 3 (key 3 / FUNC+LEFT): RESET when idle, STOP when running
        if not session.is_running then
            if pos3_kb or pos4_pad then
                reset_session_stats(); set_feedback("RESET DONE", COLORS.White, 1.0)
            end
        else
            if pos3_kb or pos4_pad then
                if session.total > 0 then
                    export_stats(); reset_session_stats(); set_feedback("STOP & EXPORT DONE", COLORS.Red, 1.5)
                else
                    reset_session_stats(); set_feedback("RESET DONE", COLORS.White, 1.0)
                end
            end
        end
        -- Position 4 (key 4 / FUNC+RIGHT): START when idle, PAUSE when running
        if not session.is_running then
            if pos4_kb or pos3_pad then
                reset_session_stats(); session.is_running = true; set_feedback("SESSION STARTED", COLORS.Green, 1.0)
            end
        else
            if pos4_kb or pos3_pad then
                session.is_paused = not session.is_paused
            end
        end
    end

    last_input_mask = active_buttons
    last_kb_state = kb_state
end

-- =========================================================
-- VISIBILITY & UI CLEANUP
-- =========================================================

local ui_hide_targets = { BattleHud_Timer = { { "c_main", "c_hud", "c_timer", "c_infinite" } } }
local function apply_force_invisible(control, path, depth, should_hide)
    local depth = depth or 1; if depth > #path then control:call("set_ForceInvisible", should_hide); return end
    local child = control:call("get_Child")
    while child do local name = child:call("get_Name"); if name and string.match(name, path[depth]) then apply_force_invisible(child, path, depth + 1, should_hide) end; child = child:call("get_Next") end
end

local function manage_ticker_visibility()
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager"); if not mgr then return end
    local dict = mgr:get_field("_ViewUIWigetDict"); if not dict then return end
    local entries = dict:get_field("_entries"); if not entries then return end
    local count = entries:call("get_Count")
    for i = 0, count - 1 do
        local entry = entries:call("get_Item", i)
        if entry then
            local widget_list = entry:get_field("value")
            if widget_list then
                local w_cnt = widget_list:call("get_Count")
                for j = 0, w_cnt - 1 do
                    local widget = widget_list:call("get_Item", j)
                    if widget then
                        local type = widget:get_type_definition()
                        if type and string.find(type:get_name(), "UIWidget_TMTicker") then widget:call("set_Visible", false); return end
                    end
                end
            end
        end
    end
end

re.on_pre_gui_draw_element(function(element, context)
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= MY_TRAINER_ID then return true end
    local game_object = element:call("get_GameObject"); if not game_object then return true end
    local name = game_object:call("get_Name"); local paths = ui_hide_targets[name]
    if paths then local view = element:call("get_View"); for _, path in ipairs(paths) do apply_force_invisible(view, path, 1, true) end end
    return true
end)

-- =========================================================
-- HUD
-- =========================================================


local function draw_hud()
    SharedUI.draw_standard_hud("HUD_PostGuard", user_config, session, "POST GUARD", true, function(cx, cy, sw, sh)
        local pct = 0
        if session.total > 0 then pct = (session.success_count / session.total) * 100 end
        
        local pct_txt = string.format("SUCCESS: %.0f%%", pct)
        local w_p = imgui.calc_text_size(pct_txt).x
        SharedUI.draw_text(pct_txt, cx - (w_p / 2), cy, SharedUI.COLORS.White)
    end)
end


-- =========================================================
-- MENU & FRAMES
-- =========================================================
local t_fm = sdk.find_type_definition("app.training.UIWidget_TMFrameMeter")
if t_fm then
    local m_setup = t_fm:get_method("SetUpFrame")
    if m_setup then sdk.hook(m_setup, function(args) local s = tonumber(tostring(sdk.to_int64(args[4]))); if session and s > session.p1_max_frame then session.p1_max_frame = s end end, function(r) return r end) end
    local m_setdown = t_fm:get_method("SetDownFrame")
    if m_setdown then sdk.hook(m_setdown, function(args) local s = tonumber(tostring(sdk.to_int64(args[4]))); if session and s > session.p2_max_frame then session.p2_max_frame = s end end, function(r) return r end) end
end

-- SESSION BUTTONS — DOCKED
local function draw_session_buttons_docked()
    local sl = SharedUI.sc_label
    local SC = SharedUI.SC_COLORS
    if SharedUI.sc_button("TIMER - (" .. sl("D") .. ")##dk_pg", SC.c1) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats() end
    imgui.same_line()
    if SharedUI.sc_button("TIMER + (" .. sl("U") .. ")##dk_pg", SC.c2) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats() end
    imgui.same_line(); imgui.text(tostring(user_config.timer_minutes) .. " MIN"); imgui.same_line(300)
    if SharedUI.sc_button("RESET (" .. sl("L", "3") .. ")##dk_pg", SC.c3) then reset_session_stats() end
    imgui.spacing()
    if not session.is_running then
        if SharedUI.sc_button("START SESSION (" .. sl("R", "4") .. ")##dk_pg", SC.c4) then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", COLORS.Green, 1.0) end
    else
        if SharedUI.sc_button("STOP & EXPORT (" .. sl("L", "3") .. ")##dk_pg", SC.c3) then export_stats(); session.is_running = false end
        imgui.same_line()
        if SharedUI.sc_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##dk_pg", SC.c4) then session.is_paused = not session.is_paused end
    end
end

-- SESSION BUTTONS — FLOATING (single-line)
local function draw_session_floating()
    local visible, sw, sh = SharedUI.begin_floating_window("Post Guard##float")
    if not visible then user_config.show_floating = false; save_conf(); SharedUI.end_floating_window(); return end
    local sl = SharedUI.sc_label
    local SC = SharedUI.SC_COLORS
    local w_width = imgui.get_window_size().x
    local sp = 4 * (sh / 1080.0)
    local pad_x = sw * 0.01
    SharedUI.draw_floating_bg()
    local slm = SharedUI.sc_label_max
    local all_labels = {
        "TIMER - (" .. slm("D") .. ")", "TIMER + (" .. slm("U") .. ")",
        "RESET (" .. slm("L") .. ")", "STOP (" .. slm("L") .. ")",
        "START (" .. slm("R") .. ")", "PAUSE (" .. slm("R") .. ")"
    }
    local max_w = 0
    for _, t in ipairs(all_labels) do local tw = imgui.calc_text_size(t).x; if tw > max_w then max_w = tw end end
    local cb_size = imgui.calc_text_size("W").y + 6
    local remaining = w_width - (pad_x * 2) - cb_size - 10 - (sp * 4)
    local actual_w = math.max(max_w + 20, remaining / 4)
    imgui.set_cursor_pos(Vector2f.new(pad_x, sh * 0.01))
    if SharedUI.sf6_button("TIMER - (" .. sl("D") .. ")##fl_pg", SC.c1, actual_w) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats() end
    imgui.same_line(0, sp)
    if SharedUI.sf6_button("TIMER + (" .. sl("U") .. ")##fl_pg", SC.c2, actual_w) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats() end
    imgui.same_line(0, sp)
    if not session.is_running then
        if SharedUI.sf6_button("RESET (" .. sl("L", "3") .. ")##fl_pg", SC.c3, actual_w) then reset_session_stats() end
    else
        if SharedUI.sf6_button("STOP (" .. sl("L", "3") .. ")##fl_pg", SC.c3, actual_w) then export_stats(); session.is_running = false end
    end
    imgui.same_line(0, sp)
    if session.is_running then
        if SharedUI.sf6_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##fl_pg", SC.c4, actual_w) then session.is_paused = not session.is_paused end
    else
        if SharedUI.sf6_button("START (" .. sl("R", "4") .. ")##fl_pg", SC.c4, actual_w) then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", COLORS.Green, 1.0) end
    end
    imgui.same_line(w_width - cb_size - 10 - pad_x)
    local changed, new_val = imgui.checkbox("##close_pg", user_config.show_floating)
    if changed then user_config.show_floating = new_val; save_conf() end
    SharedUI.end_floating_window()
end

re.on_draw_ui(function()
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= MY_TRAINER_ID then return end
    if imgui.tree_node("Post Guard Training (v1.13 Flicker Fix)") then
        if styled_header("--- INFO ---", UI_THEME.hdr_info) then imgui.text("Hit the guard to start observation.\nPunish if attack, Wait if nothing.\nCOUNTER DI if you see it!") end

        imgui.separator()
        local c_dbg, v_dbg = imgui.checkbox("Show Debug Info", user_config.show_debug)
        if c_dbg then user_config.show_debug = v_dbg end
        if user_config.show_debug then
            imgui.indent(20); imgui.text_colored("--- DEBUG ---", COLORS.Orange)

            imgui.text(string.format("P1 State: %d", session.p1_state))
            imgui.text(string.format("P2 State: %d", session.p2_state))
            if session.p2_state == STATE_PARRY then
                imgui.text_colored("P2 PARRY ACTIF !", COLORS.Orange)
            end

            imgui.text("Phase: " .. session.phase .. " | Time: " .. session.timer_action)
            imgui.text("Score: " .. session.score .. " | Succ: " .. session.success_count)
            local info = get_p2_extended_info()
            imgui.text("Pose: " .. tostring(info.pose_st) .. (info.pose_st >= 2 and " (AIR)" or " (GROUND)"))
            if info.suki_flag then imgui.text_colored("Suki: TRUE", COLORS.Green) else imgui.text_colored("Suki: FALSE", COLORS.Grey) end
            imgui.text("Was Air: " .. tostring(session.p2_was_in_air)); imgui.text("Air Atk: " .. tostring(session.p2_air_attack_confirmed))
local debug_p2_mem = get_p2_extended_info()

            imgui.text("Phase: " .. session.phase)
            imgui.text("Catch Muteki: " .. tostring(debug_p2_mem.catch_muteki) .. " | Throw Tech No: " .. tostring(debug_p2_mem.throw_tech_no))
            if session.p2_throw_tech_detected then
                imgui.text_colored("Throw Tech Detected: TRUE (choppe ignorée)", COLORS.Red)
            else
                imgui.text_colored("Throw Tech Detected: FALSE", COLORS.Grey)
            end            imgui.unindent(20)
        end

        if styled_header("--- SESSION ---", UI_THEME.hdr_session) then
            local c_fl, v_fl = imgui.checkbox("Detacher en fenetre flottante", user_config.show_floating)
            if c_fl then user_config.show_floating = v_fl; save_conf() end

            if user_config.show_floating then
                imgui.text_colored("Cette section est actuellement detachee en fenetre flottante.", COLORS.DarkGrey)
            else
                imgui.separator(); imgui.spacing()
                draw_session_buttons_docked()
            end
        end
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= MY_TRAINER_ID then return end
    
    local should_update = true
    local should_draw = true

    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pause_bit = pm:get_field("_CurrentPauseTypeBit")
        if pause_bit and (pause_bit ~= 64 and pause_bit ~= 2112) then
            -- Pause Menu / System
            if session.is_running and not session.is_paused then session.is_paused = true end
            should_update = false
            should_draw = false
        end
    end
    
    if should_update then
        handle_input()
        update_logic()
        manage_ticker_visibility()
    end
    
    if should_draw then
        draw_hud()
    end

    -- FLOATING SESSION WINDOW
    if should_draw and user_config.show_floating then
        draw_session_floating()
    end
end)