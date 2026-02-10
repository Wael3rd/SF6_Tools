local re = re
local sdk = sdk
local imgui = imgui
local draw = draw
local json = json

-- =========================================================
-- TrainingPostGuard (V1.12 - EXPORT FIX)
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

local IMGUI_FLAGS = {
    NoTitleBar = 1, NoResize = 2, NoMove = 4, NoScrollbar = 8, 
    NoMouseInputs = 512, NoNav = 786432, NoBackground = 128
}

local custom_font = { obj = nil, filename = "capcom_goji-udkakugoc80pro-db.ttf", loaded_size = 0, status = "Init..." }
local custom_font_timer = { obj = nil, filename = "SF6_college.ttf", loaded_size = 0, status = "Init..." }
local res_watcher = { last_w = 0, last_h = 0, cooldown = 0 }

local user_config = {
    timer_minutes = 5,
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
    show_debug = false
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

local function get_dynamic_screen_size()
    local w, h = 1920, 1080 
    if imgui.get_display_size then
        local result = imgui.get_display_size()
        if type(result) == "userdata" then
            local ok, x = pcall(function() return result.x end); local ok2, y = pcall(function() return result.y end)
            if ok and ok2 then w, h = x, y else w = result.w or w; h = result.h or h end
        elseif type(result) == "number" then local w_val, h_val = imgui.get_display_size(); w, h = w_val, h_val end
    end
    if w <= 0 then w = 1920 end; if h <= 0 then h = 1080 end
    return w, h
end

local function try_load_font()
    if not imgui.load_font then return end
    local sw, sh = get_dynamic_screen_size(); local scale_factor = sh / 1080.0
    if scale_factor < 0.1 then scale_factor = 1.0 end
    local target_size = math.floor(user_config.hud_base_size * (user_config.hud_auto_scale and scale_factor or 1.0))
    local font = imgui.load_font(custom_font.filename, target_size)
    if font then custom_font.obj = font; custom_font.loaded_size = target_size end
    local target_size_timer = math.floor(user_config.timer_font_size * (user_config.hud_auto_scale and scale_factor or 1.0))
    local font_t = imgui.load_font(custom_font_timer.filename, target_size_timer)
    if font_t then custom_font_timer.obj = font_t end
end

local function handle_resolution_change()
    local sw, sh = get_dynamic_screen_size()
    if res_watcher.last_w == 0 then res_watcher.last_w = sw; res_watcher.last_h = sh; try_load_font(); return end
    if sw ~= res_watcher.last_w or sh ~= res_watcher.last_h then res_watcher.cooldown = 30; res_watcher.last_w = sw; res_watcher.last_h = sh end
    if res_watcher.cooldown > 0 then res_watcher.cooldown = res_watcher.cooldown - 1; if res_watcher.cooldown == 0 then try_load_font() end end
end

local function format_time(s) if not s or s < 0 then s = 0 end return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60)) end
local function styled_button(label, style, text_col) imgui.push_style_color(21, style.base); imgui.push_style_color(22, style.hover); imgui.push_style_color(23, style.active); if text_col then imgui.push_style_color(0, text_col) end; local clicked = imgui.button(label); if text_col then imgui.pop_style_color(1) end; imgui.pop_style_color(3); return clicked end
local function styled_header(label, style) imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active); local is_open = imgui.collapsing_header(label); imgui.pop_style_color(3); return is_open end

try_load_font()

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
    local info = { catch_flag = false }
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return info end
    local player_mgr = gBattle:get_field("Player"):get_data(nil)
    if not player_mgr then return info end
    local p1 = player_mgr:call("getPlayer", 0) 
    if not p1 then return info end
    
    -- Lecture de catch_flag (true = en train de chopper)
    local catch = p1:get_field("catch_flag")
    if catch then info.catch_flag = (tostring(catch) == "true") end
    
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


local function is_game_in_menu()
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local field = pm:get_type_definition():get_field("_CurrentPauseBit")
        if field then local val = field:get_data(pm); if val and tostring(val) ~= "131072" then return true end end
    end
    return false
end

-- [FIXED EXPORT FUNCTION]
local function export_stats()
    local file = io.open(LOG_FILENAME, "a"); if not file then return end
    if file:seek("end") == 0 then file:write("DATE\tDURATION\tSCORE\tSUCCESS_PCT\tTOTAL\n") end
    
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local duration = os.difftime(os.time(), session.real_start_time)
    
    local pct = 0.0
    if session.total > 0 then 
        pct = (session.success_count / session.total) * 100.0 
    end
    
    -- Correction de la ligne de formatage qui causait le crash
    -- On passe explicitement pct (float) a %.2f et les autres en string/int
    local line = string.format("%s\t%s\t%d\t%.2f%%\t%d", now, format_time(duration), session.score, pct, session.total)
    
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
    session.score = 0; session.total = 0; session.success_count = 0
    session.is_running = false; session.is_paused = false; session.is_time_up = false
    session.time_rem = user_config.timer_minutes * 60
    session.phase = PHASE_WAIT_BLOCK
    session.timer_action = 0
    session.time_up_delay = 0
    
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
    if success then
        session.score = session.score + 1
        session.success_count = session.success_count + 1 
        set_feedback(reason, COLORS.Green, 2.0)
    else
        session.score = session.score - 1
        set_feedback(reason, COLORS.Red, 2.0)
    end
    session.phase = PHASE_RESULT
    session.timer_action = 45 
end

local function update_logic()
    local dt = 0.016 
    
    -- GESTION SCORE VISUEL
    if session.score ~= session.last_score then session.score_col = (session.score > session.last_score) and COLORS.Green or COLORS.Red; session.score_timer = 30; session.last_score = session.score end
    if session.score_timer > 0 then session.score_timer = session.score_timer - 1; if session.score_timer <= 0 then session.score_col = COLORS.White end end
    
    if is_game_in_menu() then
        if session.is_running and not session.is_paused then session.is_paused = true end
        return 
    end
    
    -- TIME UP LOOP
    if session.is_time_up then 
        session.time_up_delay = (session.time_up_delay or 0) + dt
        if session.time_up_delay < 1.5 then 
             set_feedback("TIME UP! & EXPORTED", COLORS.Red, 0)
        else
             set_feedback("PRESS (FUNC) + LEFT TO RESET", COLORS.Yellow, 0)
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
                evaluate_outcome(true, "SUCCESS: SAFE") 
            elseif p2_act_st == 0 then
                reset_round_silent() 
            end
        end

    elseif session.phase == PHASE_RESULT then
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

    if is_func_held then
        if session.is_time_up then
             if ((active_buttons & BTN_LEFT) == BTN_LEFT) and not ((last_input_mask & BTN_LEFT) == BTN_LEFT) then
                reset_session_stats(); set_feedback("RESET DONE", COLORS.White, 1.0)
            end
            last_input_mask = active_buttons
            return
        end

        if not session.is_running then
             if ((active_buttons & BTN_UP) == BTN_UP) and not ((last_input_mask & BTN_UP) == BTN_UP) then
                user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1)
                session.time_rem = user_config.timer_minutes * 60; set_feedback("TIMER: "..user_config.timer_minutes.." MIN", COLORS.White, 1.0)
             end
             if ((active_buttons & BTN_DOWN) == BTN_DOWN) and not ((last_input_mask & BTN_DOWN) == BTN_DOWN) then
                user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1)
                session.time_rem = user_config.timer_minutes * 60; set_feedback("TIMER: "..user_config.timer_minutes.." MIN", COLORS.White, 1.0)
             end
        end
        if ((active_buttons & BTN_RIGHT) == BTN_RIGHT) and not ((last_input_mask & BTN_RIGHT) == BTN_RIGHT) then
            if not session.is_running then 
                reset_session_stats(); session.is_running = true; set_feedback("SESSION STARTED", COLORS.Green, 1.0)
            else 
                session.is_paused = not session.is_paused 
            end
        end
        if ((active_buttons & BTN_LEFT) == BTN_LEFT) and not ((last_input_mask & BTN_LEFT) == BTN_LEFT) then
            if session.total > 0 then
                export_stats(); reset_session_stats(); set_feedback("STOP & EXPORT DONE", COLORS.Red, 1.5)
            else
                reset_session_stats(); set_feedback("RESET DONE", COLORS.White, 1.0)
            end
        end
    end
    last_input_mask = active_buttons
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
local function draw_text_overlay(text, x, y, color)
    local safe_text = string.gsub(text, "%%", "%%%%"); local outline_color = COLORS.Grey; local outline_thick = 0.1
    imgui.set_cursor_pos(Vector2f.new(x + 0, y + 0)); imgui.text_colored(safe_text, outline_color)
    for dx = -outline_thick, outline_thick do for dy = -outline_thick, outline_thick do if (dx ~= 0 or dy ~= 0) and (math.abs(dx) + math.abs(dy) <= outline_thick) then imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy)); imgui.text_colored(safe_text, outline_color) end end end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe_text, color)
end
local function draw_timer_outline(text, x, y, color)
    local safe_text = string.gsub(text, "%%", "%%%%"); local outline_color = 0xFF000000; local thickness = 2
    for dx = -thickness, thickness, thickness do for dy = -thickness, thickness, thickness do if dx ~= 0 or dy ~= 0 then imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy)); imgui.text_colored(safe_text, outline_color) end end end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe_text, color)
end

local function draw_hud()
    local sw, sh = get_dynamic_screen_size()
    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0) 
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    local win_flags = IMGUI_FLAGS.NoTitleBar | IMGUI_FLAGS.NoResize | IMGUI_FLAGS.NoMove | IMGUI_FLAGS.NoScrollbar | IMGUI_FLAGS.NoMouseInputs | IMGUI_FLAGS.NoNav | IMGUI_FLAGS.NoBackground

    if imgui.begin_window("HUD_PostGuard", true, win_flags) then
        if custom_font.obj then imgui.push_font(custom_font.obj) end
        
        local center_x = sw / 2; local center_y = sh / 2
        local top_y = center_y + (user_config.hud_n_global_y * sh)
        
        -- A. TIMER
        local time_show = session.is_running and session.time_rem or (user_config.timer_minutes * 60)
        local t_txt = format_time(time_show)
        
        if custom_font.obj then imgui.pop_font() end; if custom_font_timer.obj then imgui.push_font(custom_font_timer.obj) end
        
        local t_col = COLORS.White
        if session.is_paused then t_col = COLORS.Yellow elseif session.time_rem < 10 and session.is_running then t_col = COLORS.Red end
        if session.is_time_up then t_col = COLORS.Red end

        local w_t = imgui.calc_text_size(t_txt).x
        local timer_y = center_y + (user_config.timer_hud_y * sh)
        local timer_x = center_x - (w_t / 2) + (user_config.timer_offset_x * sw)
        draw_timer_outline(t_txt, timer_x, timer_y, t_col)
        
        if custom_font_timer.obj then imgui.pop_font() end; if custom_font.obj then imgui.push_font(custom_font.obj) end
        
        -- B. SCORE & LABELS
        local spread_score = user_config.hud_n_spread_score * sw
        local off_score = user_config.hud_n_offset_score * sw
        local off_total = user_config.hud_n_offset_total * sw
        local off_timer = user_config.hud_n_offset_timer * sw

        local s_txt = "SCORE: " .. session.score
        local tot_txt = "TOTAL: " .. session.total
        local mode_txt = "POST GUARD"
        
        local w_s = imgui.calc_text_size(s_txt).x
        draw_text_overlay(s_txt, center_x - spread_score - w_s + off_score, top_y, session.score_col)
        
        local w_m = imgui.calc_text_size(mode_txt).x
        local col_m = session.is_paused and COLORS.Yellow or COLORS.White
        draw_text_overlay(mode_txt, center_x - (w_m / 2) + off_timer, top_y, col_m)
        draw_text_overlay(tot_txt, center_x + spread_score + off_total, top_y, COLORS.White)
        
        -- C. PERCENTAGES
        local spacing_y = user_config.hud_n_spacing_y * sh
        local y2 = top_y + spacing_y
        
        local pct = 0
        if session.total > 0 then 
            pct = (session.success_count / session.total) * 100 
        end
        
        local pct_txt = string.format("SUCCESS: %.0f%%", pct)
        local w_p = imgui.calc_text_size(pct_txt).x
        draw_text_overlay(pct_txt, center_x - (w_p / 2), y2, COLORS.White)

-- D. STATUS MESSAGE
        local msg = session.feedback.text
        if session.is_paused then msg = "PAUSED: (FUNC) + RIGHT" end
        if session.is_time_up then msg = session.feedback.text end -- Force Logic Text
        
        local y3 = y2 + spacing_y + (user_config.hud_n_offset_status_y * sh)
        local w_msg = imgui.calc_text_size(msg).x
        local msg_col = session.feedback.color
        
        -- AJOUT : Si c'est en pause, on force la couleur JAUNE
        if session.is_paused then msg_col = COLORS.Yellow end 
        
        draw_text_overlay(msg, center_x - (w_msg / 2), y3, msg_col)

        if custom_font.obj then imgui.pop_font() end
        imgui.end_window()
    end
    imgui.pop_style_var(2); imgui.pop_style_color(1)
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

re.on_draw_ui(function()
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= MY_TRAINER_ID then return end
    if imgui.tree_node("Post Guard Training (v1.12 Final)") then
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
            imgui.text("DURATION:"); imgui.same_line(); 
            if styled_button("-", UI_THEME.btn_neutral) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats() end
            imgui.same_line(); imgui.text(tostring(user_config.timer_minutes) .. " MIN"); imgui.same_line(); 
            if styled_button("+", UI_THEME.btn_neutral) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats() end
            imgui.same_line(250); if styled_button("RESET", UI_THEME.btn_red) then reset_session_stats() end
            imgui.spacing()
            if not session.is_running then if styled_button("START SESSION", UI_THEME.btn_green) then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", COLORS.Green, 1.0) end
            else if styled_button("STOP & EXPORT", UI_THEME.btn_red) then export_stats(); session.is_running = false end; imgui.same_line(); if styled_button(session.is_paused and "RESUME" or "PAUSE", UI_THEME.btn_neutral) then session.is_paused = not session.is_paused end end
        end
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= MY_TRAINER_ID then return end
    handle_resolution_change(); handle_input(); update_logic(); manage_ticker_visibility()
    if not is_game_in_menu() then draw_hud() end
end)