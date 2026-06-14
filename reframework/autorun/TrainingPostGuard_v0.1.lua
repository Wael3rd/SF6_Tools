local re = re
local sdk = sdk
local imgui = imgui
local json = json
require("func/SharedHooks") -- error registry (_G.safe_load_json)
local GS = require("func/GameState") -- per-frame snapshot (players, act_st, pause)
local UIKit = require("func/UIKit")

-- =========================================================
-- TrainingPostGuard (V1.13 - Flicker Fix)
-- =========================================================

local DEPENDANT_ON_MANAGER = true 
local MY_TRAINER_ID = 3

-- =========================================================
-- CONFIGURATION
-- =========================================================
local CONFIG_FILENAME = "TrainingPostGuard_data/TrainingPostGuard_Config.json"
local LOG_FILENAME    = "Stats/PostGuard_Stats.txt"

local COLORS = UIKit.COLORS

local UI_THEME = {
    hdr_info    = UIKit.THEME.hdr_gold,
    hdr_session = UIKit.THEME.hdr_purple,
    btn_neutral = UIKit.THEME.btn_neutral,
    btn_green   = UIKit.THEME.btn_green,
    btn_red     = UIKit.THEME.btn_red,
}

local SharedUI = require("func/Training_SharedUI")
local SessionRecap = require("func/Training_SessionRecap")

local user_config = {
    session_mode = "trials", -- "timer" or "trials"
    timer_minutes = 1,
    trial_count = 20,
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

local function save_conf()
    json.dump_file(CONFIG_FILENAME, user_config)
end

local function load_conf()
    local d = _G.safe_load_json(CONFIG_FILENAME)
    if d then
        for k, v in pairs(d) do
            if user_config[k] ~= nil then user_config[k] = v end
        end
    end
end
load_conf()

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
    p2_throw_tech_detected = false,  -- Flag: have we seen a throw tech?
    p2_was_in_parry = false,  -- Flag: P2 was in parry
    throw_in_progress = false,  -- Flag: a throw is in progress
    _p2_was_di = false,
    
    -- Time Up
    time_up_delay = 0,
    
    feedback = { text = "READY", timer = 0, color = COLORS.Grey },
    
    p1_state = 0, p2_state = 0, p1_max_frame = 0, p2_max_frame = 0
}

-- =========================================================
-- TOOLS
-- =========================================================


local styled_button = UIKit.styled_button
local styled_header = UIKit.styled_header

-- =========================================================
-- GAME MEMORY READERS
-- =========================================================

local function get_act_st(player_index)
    -- Read from the per-frame GameState snapshot (was 1 full gBattle chain per call)
    if player_index == 0 then return GS.p1_act_st end
    return GS.p2_act_st
end

local function get_p1_extended_info()
    local info = { catch_flag = false, trade_dm_flag = false, damage_type = 0, muteki_time = 0 }
    local p1 = GS.p1
    if not p1 then return info end

    local catch = p1:get_field("catch_flag")
    if catch then info.catch_flag = (tostring(catch) == "true") end

    local trade = p1:get_field("trade_dm_flag")
    if trade then info.trade_dm_flag = (tostring(trade) == "true") end

    local dt = p1:get_field("damage_type")
    if dt then info.damage_type = tonumber(tostring(dt)) or 0 end

    local mt = p1:get_field("muteki_time")
    if mt then info.muteki_time = tonumber(tostring(mt)) or 0 end

    return info
end

local function get_p2_extended_info()
    local info = { pose_st = 0, suki_flag = false, catch_muteki = 0, throw_tech_no = 0 }
    local p2 = GS.p2
    if not p2 then return info end
    
    local pose = p2:get_field("pose_st"); if pose then info.pose_st = tonumber(tostring(pose)) end
    local suki = p2:get_field("land_suki_flag"); if suki then info.suki_flag = (tostring(suki) == "true") end
    
    -- Read catch_muteki (3 = being thrown)
    local muteki = p2:get_field("catch_muteki")
    if muteki then info.catch_muteki = tonumber(tostring(muteki)) or 0 end
    
    -- Read throw_tech_no (0 = throw succeeded, >0 = throw tech)
    local tech_no = p2:get_field("throw_tech_no")
    if tech_no then info.throw_tech_no = tonumber(tostring(tech_no)) or 0 end
    
    return info
end

local function export_stats()
    local file = io.open(LOG_FILENAME, "a"); if not file then return end
    
    -- Add the DETAILS column to the header if the file is empty
    if file:seek("end") == 0 then file:write("DATE\tDURATION\tSCORE\tSUCCESS_PCT\tTOTAL\tDETAILS\n") end
    
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local duration = os.difftime(os.time(), session.real_start_time)
    
    local pct = 0.0
    if session.total > 0 then 
        pct = (session.success_count / session.total) * 100.0 
    end
    
    -- Build the details string (Format: Key=Value|Key=Value...)
    local details_str = ""
    if session.detailed_stats then
        for k, v in pairs(session.detailed_stats) do
            -- Clean up the text to avoid tabs or newlines
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
    
    -- Table to store detailed outcome counts
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
    session._p2_was_di = false
end

local function reset_round_silent()
    reset_round()
    session.feedback.text = "WAITING..."
    session.feedback.color = COLORS.Grey
end

local function evaluate_outcome(success, reason)
    session.total = session.total + 1
    
    -- Increment the counter for this specific reason
    if session.detailed_stats then
        if not session.detailed_stats[reason] then
            session.detailed_stats[reason] = 0
        end
        session.detailed_stats[reason] = session.detailed_stats[reason] + 1
    end

    if success then
        session.score = session.score + 1
        session.success_count = session.success_count + 1 
        set_feedback(reason, COLORS.Green, 0.5) -- Short delay as agreed
    else
        session.score = session.score - 1
        set_feedback(reason, COLORS.Red, 0.5)
    end
    session.phase = PHASE_RESULT
    session.timer_action = 30 -- ~0.5 sec logical pause
end

local function update_logic()
    local dt = 0.016 
    
    -- VISUAL SCORE MANAGEMENT
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

    if user_config.session_mode == "timer" then
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
    else -- trials
        if session.total >= user_config.trial_count then
            if not session.is_time_up then
                session.is_running = false
                session.is_time_up = true
                session.time_up_delay = 0
                export_stats()
                SessionRecap.show("POST GUARD", LOG_FILENAME, "postguard")
            end
            set_feedback(session.total .. " TRIALS DONE! & EXPORTED", COLORS.Red, 0)
            return
        end
    end

    if session.feedback.timer > 0 then
        session.feedback.timer = session.feedback.timer - dt
        if session.feedback.timer <= 0 then session.feedback.text = "WAITING..."; session.feedback.color = COLORS.Grey end
    end
    
    -- =========================================================
    -- READ STATES (ACT_ST & FRAMEDATA)
    -- =========================================================

    -- Update FrameDataState via the Hook
    session.p1_state = session.p1_max_frame -- 13 = Active, 9 = Hurt
    session.p2_state = session.p2_max_frame
    session.p1_max_frame = 0; session.p2_max_frame = 0 
    
    local p1_act_st = get_act_st(0) -- P1 Action (37 = Throwing)
    local p2_act_st = get_act_st(1) -- P2 Action (39 = Parry, 38 = Thrown)
	local p1_mem = get_p1_extended_info()
    local p2_mem = get_p2_extended_info() -- For Tech and Air state

    -- =========================================================
    -- THROW LOGIC (GLOBAL)
    -- =========================================================

    if p2_mem.throw_tech_no > 0 then session.p2_throw_tech_detected = true end

    -- Throw animation
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
    -- GAME PHASES
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

        if session.p2_state == STATE_DI then session._p2_was_di = true end

        local is_perfect_parry = false
        if session._p2_was_di then
            is_perfect_parry = p1_mem.muteki_time > 0
        else
            is_perfect_parry = p1_mem.damage_type == 34 and p1_mem.trade_dm_flag
        end
        if is_perfect_parry then
             evaluate_outcome(true, "SUCCESS: PERFECT PARRY!")
             return
        end
		
        -- [PRIORITY 0] CRITICAL FAIL: GOT HIT
        -- If P1 is hit (State 9), it's an immediate loss.
        -- Exclude DI case (handled below) to show the correct error message.
        if session.p1_state == STATE_HURT and session.p2_state ~= STATE_DI then 
            evaluate_outcome(false, "FAIL: GOT HIT")
            return 
        end

        -- 1. PARRY DETECTION (Flag)
        if p2_act_st == 39 then session.p2_has_parried = true end

        -- 2. CHECK FAIL: HIT INTO PARRY
        -- If P2 Parry (39) AND P1 Active (13) -> Fail
        if p2_act_st == 39 and session.p1_state == STATE_ACTIVE then
            if p1_act_st ~= 37 then -- Unless it's a throw
                evaluate_outcome(false, "FAIL: HIT PARRY!")
                return
            end
        end

        -- 3. CHECK SUCCESS: THROW PUNISH
        if p1_act_st == 37 and p2_act_st == 38 and not session.p2_throw_tech_detected then
             evaluate_outcome(true, "SUCCESS: THROW PUNISH!")
             return
        end

        -- 4. CHECK SUCCESS: PUNISH LANDED (HURT)
        if session.p2_state == STATE_HURT then
             evaluate_outcome(true, "SUCCESS: PUNISH!")
             return
        end

        -- 5. CHECK FAIL: MISSED WHIFF PUNISH (PARRY/DRIVE RUSH LOGIC)
        if session.p2_has_parried then
            -- Only confirm the failure if P2 returned to Neutral (0).
            -- If in Startup (7) or Dash (18) or other, keep waiting.
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
        
        -- 7. TIMEOUT / SAFE / MISSED ANTI-AIR
        -- Standard handling if it was not a Parry
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
	
	-- If we hit into guard again (P2 Block), restart immediately
        if session.p2_state == STATE_BLOCK then
            reset_round() -- Reset variables and return to wait mode
            return        -- Stop here for this frame, next frame will start OBSERVATION
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

local function pg_ticker(msg) if _G.show_custom_ticker then _G.show_custom_ticker(msg, 0.3) end end

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
        local ok, down = pcall(reframework.is_key_down, reframework, k)
        kb_state[k] = ok and down
    end
    local function kb_pressed(k) return kb_state[k] and not last_kb_state[k] end
    local function pad_pressed(btn) return ((active_buttons & btn) == btn) and not ((last_input_mask & btn) == btn) end
    local function is_action(btn, kb) return (is_func_held and pad_pressed(btn)) or kb_pressed(kb) end

    if session.is_time_up then
         if is_action(BTN_LEFT, 0x34) or kb_pressed(0x33) then
            reset_session_stats()
            set_feedback("RESET DONE", COLORS.White, 1.0)
            pg_ticker("SESSION RESET")
        end
    else
        if not session.is_running then
             if is_action(BTN_UP, 0x32) then
                if user_config.session_mode == "trials" then
                    user_config.trial_count = math.min(200, user_config.trial_count + 10)
                    set_feedback(tostring(user_config.trial_count), COLORS.White, 1.0)
                else
                    user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1)
                    session.time_rem = user_config.timer_minutes * 60; set_feedback("TIMER: "..user_config.timer_minutes.." MIN", COLORS.White, 1.0)
                end
                save_conf()
             end
             if is_action(BTN_DOWN, 0x31) then
                if user_config.session_mode == "trials" then
                    user_config.trial_count = math.max(10, user_config.trial_count - 10)
                    set_feedback(tostring(user_config.trial_count), COLORS.White, 1.0)
                else
                    user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1)
                    session.time_rem = user_config.timer_minutes * 60; set_feedback("TIMER: "..user_config.timer_minutes.." MIN", COLORS.White, 1.0)
                end
                save_conf()
             end
        end
        -- POSITION 3 (key 3): START when not running, STOP when running
        local pos3_kb = kb_pressed(0x33)
        local pos3_pad = is_func_held and pad_pressed(BTN_RIGHT)
        local pos4_kb = kb_pressed(0x34)
        local pos4_pad = is_func_held and pad_pressed(BTN_LEFT)

        -- Position 3 (key 3 / FUNC+LEFT): RESET when idle, STOP when running
        if pos3_kb or pos4_pad then
            if session.is_running then
                reset_session_stats(); set_feedback("STOPPED", COLORS.Red, 1.5)
                pg_ticker("SESSION STOPPED")
            else
                reset_session_stats(); set_feedback("RESET DONE", COLORS.White, 1.0)
                pg_ticker("SESSION RESET")
            end
        end
        -- Position 4 (key 4 / FUNC+RIGHT): START when idle, PAUSE when running
        if not session.is_running then
            if pos4_kb or pos3_pad then
                reset_session_stats(); session.is_running = true; set_feedback("SESSION STARTED", COLORS.Green, 1.0)
                pg_ticker("SESSION STARTED")
            end
        else
            if pos4_kb or pos3_pad then
                session.is_paused = not session.is_paused
                pg_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED")
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
    local is_trials = (user_config.session_mode == "trials")
    SharedUI.draw_standard_hud("HUD_PostGuard", user_config, session, "POST GUARD", not is_trials, function(cx, cy, sw, sh)
        if is_trials then
            local lb_off = SharedUI.get_letterbox_offset()
            local center_y = lb_off + sh / 2
            local remaining = math.max(0, user_config.trial_count - session.total)
            local t_txt = session.is_running and tostring(remaining) or tostring(user_config.trial_count)
            local hud_cfg = SharedUI.HUD_CONFIG[_G.CurrentHudSuffix or "Default"] or SharedUI.HUD_CONFIG["Default"]
            SharedUI.pop_main(); SharedUI.push_timer()
            local w_t = imgui.calc_text_size(t_txt).x
            local t_col = SharedUI.COLORS.White
            if session.is_paused then t_col = SharedUI.COLORS.Yellow
            elseif remaining <= 3 and session.is_running then t_col = SharedUI.COLORS.Red end
            if session.is_time_up then t_col = SharedUI.COLORS.Red end
            SharedUI.draw_timer(t_txt, cx - (w_t / 2) + (hud_cfg.x * sw), center_y + (hud_cfg.y * sh), t_col)
            SharedUI.pop_timer(); SharedUI.push_main()
        end
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
    local mode_label = user_config.session_mode == "trials" and "MODE: TRIALS" or "MODE: TIMER"
    if imgui.button(mode_label .. "##dk_mode_pg") then
        user_config.session_mode = user_config.session_mode == "trials" and "timer" or "trials"
        reset_session_stats(); save_conf()
        pg_ticker(user_config.session_mode == "timer" and "TIMER MODE" or "TRIALS MODE")
    end
    imgui.same_line()
    if user_config.session_mode == "trials" then
        if SharedUI.sc_button("TRIALS - (" .. sl("D") .. ")##dk_pg", SC.c1) then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        imgui.same_line()
        if SharedUI.sc_button("TRIALS + (" .. sl("U") .. ")##dk_pg", SC.c2) then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
        imgui.same_line(); imgui.text(tostring(user_config.trial_count) .. " TRIALS")
    else
        if SharedUI.sc_button("TIMER - (" .. sl("D") .. ")##dk_pg", SC.c1) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats() end
        imgui.same_line()
        if SharedUI.sc_button("TIMER + (" .. sl("U") .. ")##dk_pg", SC.c2) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats() end
        imgui.same_line(); imgui.text(tostring(user_config.timer_minutes) .. " MIN")
    end
    imgui.same_line(300)
    if SharedUI.sc_button("RESET (" .. sl("L", "3") .. ")##dk_pg", SC.c3) then reset_session_stats(); pg_ticker("SESSION RESET") end
    imgui.spacing()
    if not session.is_running then
        if SharedUI.sc_button("START SESSION (" .. sl("R", "4") .. ")##dk_pg", SC.c4) then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", COLORS.Green, 1.0); pg_ticker("SESSION STARTED") end
    else
        if SharedUI.sc_button("STOP (" .. sl("L", "3") .. ")##dk_pg", SC.c3) then reset_session_stats(); set_feedback("STOPPED", COLORS.Red, 1.0); pg_ticker("SESSION STOPPED") end
        imgui.same_line()
        if SharedUI.sc_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##dk_pg", SC.c4) then session.is_paused = not session.is_paused; pg_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED") end
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
        "TRIALS - (" .. slm("D") .. ")", "TRIALS + (" .. slm("U") .. ")",
        "RESET (" .. slm("L") .. ")", "STOP (" .. slm("L") .. ")",
        "START (" .. slm("R") .. ")", "PAUSE (" .. slm("R") .. ")"
    }
    local max_w = 0
    for _, t in ipairs(all_labels) do local tw = imgui.calc_text_size(t).x; if tw > max_w then max_w = tw end end
    local cb_size = imgui.calc_text_size("W").y + 6
    local remaining = w_width - (pad_x * 2) - cb_size - 10 - (sp * 4)
    local actual_w = math.max(max_w + 20, remaining / 4)
    imgui.set_cursor_pos(Vector2f.new(pad_x, sh * 0.01))
    if user_config.session_mode == "trials" then
        if SharedUI.sf6_button("TRIALS - (" .. sl("D") .. ")##fl_pg", SC.c1, actual_w) then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        imgui.same_line(0, sp)
        if SharedUI.sf6_button("TRIALS + (" .. sl("U") .. ")##fl_pg", SC.c2, actual_w) then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
    else
        if SharedUI.sf6_button("TIMER - (" .. sl("D") .. ")##fl_pg", SC.c1, actual_w) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats() end
        imgui.same_line(0, sp)
        if SharedUI.sf6_button("TIMER + (" .. sl("U") .. ")##fl_pg", SC.c2, actual_w) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats() end
    end
    imgui.same_line(0, sp)
    if not session.is_running then
        if SharedUI.sf6_button("RESET (" .. sl("L", "3") .. ")##fl_pg", SC.c3, actual_w) then reset_session_stats(); pg_ticker("SESSION RESET") end
    else
        if SharedUI.sf6_button("STOP (" .. sl("L", "3") .. ")##fl_pg", SC.c3, actual_w) then reset_session_stats(); set_feedback("STOPPED", COLORS.Red, 1.0); pg_ticker("SESSION STOPPED") end
    end
    imgui.same_line(0, sp)
    if session.is_running then
        if SharedUI.sf6_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##fl_pg", SC.c4, actual_w) then session.is_paused = not session.is_paused; pg_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED") end
    else
        if SharedUI.sf6_button("START (" .. sl("R", "4") .. ")##fl_pg", SC.c4, actual_w) then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", COLORS.Green, 1.0); pg_ticker("SESSION STARTED") end
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
                imgui.text_colored("Throw Tech Detected: TRUE (throw ignored)", COLORS.Red)
            else
                imgui.text_colored("Throw Tech Detected: FALSE", COLORS.Grey)
            end            imgui.unindent(20)
        end

        if styled_header("--- SESSION ---", UI_THEME.hdr_session) then
            local c_fl, v_fl = imgui.checkbox("FLOATING WINDOW", user_config.show_floating)
            if c_fl then user_config.show_floating = v_fl; save_conf() end

            if user_config.show_floating then
                imgui.text_colored("Session controls are in the floating window.", COLORS.DarkGrey)
            else
                imgui.separator(); imgui.spacing()
                draw_session_buttons_docked()
            end
        end
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if _G.CurrentTrainerMode == 3 then
        if _G._tsm_web_cmd then
            local cmd = _G._tsm_web_cmd; _G._tsm_web_cmd = nil
            if cmd == "start" then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", COLORS.Green, 1.0); pg_ticker("SESSION STARTED") end
            if cmd == "stop" then reset_session_stats(); set_feedback("STOPPED", COLORS.Red, 1.0); pg_ticker("SESSION STOPPED") end
            if cmd == "reset" then reset_session_stats(); pg_ticker("SESSION RESET") end
            if cmd == "pause" then session.is_paused = not session.is_paused; pg_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED") end
            if cmd == "timer_up" then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
            if cmd == "timer_down" then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
            if cmd == "trials_up" then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
            if cmd == "switch_mode" then user_config.session_mode = user_config.session_mode == "timer" and "trials" or "timer"; reset_session_stats(); save_conf(); pg_ticker(user_config.session_mode == "timer" and "TIMER MODE" or "TRIALS MODE") end
            if cmd == "trials_down" then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        end
        _G.TrainingSession_IsRunning = session.is_running
        _G.TrainingSession_IsPaused = session.is_paused
        _G.TrainingSession_Timer = user_config.timer_minutes
        _G.TrainingSession_Trials = user_config.trial_count
        _G.TrainingSession_Mode = user_config.session_mode
    end
    local cur_mode = _G.CurrentTrainerMode or 0
    if DEPENDANT_ON_MANAGER and cur_mode ~= MY_TRAINER_ID then return end
    if not sdk.get_managed_singleton("app.training.TrainingManager") then return end

    local should_update = true
    local should_draw = true

    if GS.in_pause_menu then
        if user_config.session_mode == "timer" and session.is_running and not session.is_paused then
            session.is_paused = true
            session._auto_paused = true
        end
        should_update = false
        should_draw = false
    else
        if session._auto_paused then
            session._auto_paused = false
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

    -- FLOATING SESSION WINDOW (hide during pause menu)
    if user_config.show_floating and not GS.in_pause_menu and not _G._tsm_hide_ui then
        draw_session_floating()
    end
end)