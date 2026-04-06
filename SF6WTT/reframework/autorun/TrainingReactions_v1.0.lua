local re = re
local sdk = sdk
local imgui = imgui
local draw = draw
local json = json

-- =========================================================
-- ReactionTraining Remastered (V6.10 - Recording Fix)
-- =========================================================

-- =========================================================
-- CONFIGURATION FRAME METER
-- =========================================================
local STATE_NEUTRAL = 0
local STATE_HURT    = 9
local STATE_BLOCK   = 10
local STATE_DI      = 11
local STATE_DR      = 12 

-- ATTACK STATES (TRIGGERS)
local ATTACK_STATES = { 
    [7]=true,   -- Startup
    [8]=false,  -- Recovery
    [13]=true,  -- Active
    [11]=true,  -- Drive Impact
    [12]=false, -- Drive Rush ignored
    [1]=true,   -- Invincible
    [2]=true,
    [3]=true,
    [4]=true
}

-- =========================================================
-- CONFIGURATION & STYLING
-- =========================================================
local CONFIG_FILENAME = "TrainingReactions_Config.json"
local LOG_FILENAME    = "TrainingReactions_SessionStats.txt"

local COLORS = {
    White  = 0xFFDADADA, Green  = 0xFF00FF00, Red    = 0xFF0000FF,
    Grey   = 0x99FFFFFF, DarkGrey = 0xFF888888, Orange = 0xFF00A5FF, 
    Cyan   = 0xFFFFFF00, Yellow = 0xFF00FFFF, 
    Shadow = 0xFF000000, Blue   = 0xFFFFAA00 
}

local UI_THEME = {
    hdr_info    = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_session = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    hdr_slots   = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
    hdr_layout  = { base = 0xFF4DA6FF, hover = 0xFF80BFFF, active = 0xFF0073E6 },
    hdr_debug   = { base = 0xFF9CBC1A, hover = 0xFFAED12B, active = 0xFF8AA814 },
    
    btn_neutral = { base = 0xFF444444, hover = 0xFF666666, active = 0xFF222222 },
    btn_green   = { base = 0xFF00AA00, hover = 0xFF00CC22, active = 0xFF007700 },
    btn_red     = { base = 0xFF0000CC, hover = 0xFF2222FF, active = 0xFF000099 },
}

local SharedUI = require("func/Training_SharedUI")
local SessionRecap = require("func/Training_SessionRecap")

-- FULL CONFIG
local user_config = {
    session_mode = 2, -- 1=timer, 2=trials
    timer_minutes = 3,
    trial_count = 20,
    timer_mode_enabled = false,
    
    hud_base_size = 20.24,
    hud_auto_scale = true,
    hud_n_global_y = -0.33799999952316284,     
    hud_n_spacing_y = 0.028999999165534973,      
    hud_n_spread_score = 0.09000000357627869,   
    
    hud_n_offset_score = 0.0,
    hud_n_offset_total = 0.0,
    hud_n_offset_timer = 0.0,    
    hud_n_offset_status_y = 0.0, 
    
    timer_hud_y = -0.46,
    timer_font_size = 80, 
    timer_offset_x = 0.0,
    
    show_slot_stats = true,
    show_debug_panel = false,
    slot_visibility = { true, true, true, true, true, true, true, true },
    
    playback_mode_auto = true,
    show_floating = true
}

-- =========================================================
-- PLAYBACK CONFIGURATION
-- =========================================================
local playback_loop = {
    active = false,     
    wait_frames = 0     
}

local function call_tm_method(method_name, arg)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    local rec_func = mgr and mgr:call("get_RecordFunc")
    if not rec_func then return end

    local method = rec_func:get_type_definition():get_method(method_name)
    if method then
        local num_params = method:get_num_params()
        if num_params > 0 then
            method:call(rec_func, arg or 0)
        else
            method:call(rec_func)
        end
    end
end

local function set_playback_mode(enable)
    if enable then
        -- START
        if user_config.playback_mode_auto then
            call_tm_method("SetAllPlayActive")
        end
        
        call_tm_method("SetPlay", true) 
        call_tm_method("ForceApply") 
        
        playback_loop.active = true
        playback_loop.wait_frames = 5
    else
        -- STOP 
        playback_loop.active = false
        call_tm_method("Stop", 0) 
        call_tm_method("ForceApply") 
    end
end

-- =========================================================
-- GLOBAL VARIABLES
-- =========================================================
local TEXTS = {
    ready           = "READY",
    waiting         = "WAITING",
    paused          = "PAUSED",
    resumed         = "RESUMED",
    time_up         = "TIME UP!",
    score_label     = "SCORE: ",
    total_label     = "TOTAL: ",
    timer_label     = "TIMER",
    mode_label      = "REACTION DRILLS",
    
    success         = "SUCCESS: INTERRUPT!",
    fail_block      = "FAIL: BLOCKED",
    fail_hit        = "FAIL: GOT HIT",
    fail_whiff      = "FAIL: WHIFF",
    attack_inc      = "ATTACK...",
    
    mode_infinite   = "MODE: INFINITE",
    mode_timed      = "MODE: TIMED",
    started         = "STARTED!",
    stopped_export  = "STOPPED & EXPORTED",
    stats_exported  = "STATS EXPORTED",
    reset_done      = "RESET DONE",
    
    reset_prompt    = nil, -- dynamic, use SharedUI.reset_message()
    pause_overlay   = nil, -- dynamic, use SharedUI.pause_message()
    err_file        = "Err: File Access"
}

local real_slot_status = {}
for i=1,8 do real_slot_status[i] = { is_valid=false, is_active=false } end

local last_trainer_mode = 0

-- BUTTON MASKS
local BTN_UP     = 1
local BTN_DOWN   = 2
local BTN_LEFT   = 4
local BTN_RIGHT  = 8


-- Session State
local session = {
    is_running = false, is_paused = false, 
    start_ts = os.time(), real_start_time = os.time(), time_rem = 0, last_clock = 0,
    score = 0, total = 0, 
    last_score = 0, score_col = COLORS.White, score_timer = 0,
    status_msg = TEXTS.ready, export_msg = "",
    feedback = { text = TEXTS.waiting, timer = 0, color = COLORS.White },
    slot_stats = {},
    
    -- AUTO TRACKING VARIABLES
    p1_max_frame = 0,
    p2_max_frame = 0,
    p2_is_end_flag = false,
    
    p1_state = 0,
    p2_state = 0,
    is_tracking = false,
    track_timer = 0,
    outcome = "WAITING",
    di_counter_success = false,
    score_processed = false,
    
    is_time_up = false,
    time_up_delay = 0,
    
    -- [NEW] Track P1 Actions
    last_act_id = -1
}
for i=1,8 do session.slot_stats[i] = { attempts=0, success=0 } end

-- GAME STATE INITIALIZATION
local game_state = {
    p1_id = -1, p2_id = -1,
	last_valid_p1 = -1, last_valid_p2 = -1,
    current_slot_index = -1, current_rec_state = 0, last_rec_state = 0
}

-- CHARACTERS
local CHARACTER_NAMES = {
    [1] = "Ryu",        [2] = "Luke",       [3] = "Kimberly",   [4] = "Chun-Li",
    [5] = "Manon",      [6] = "Zangief",    [7] = "JP",         [8] = "Dhalsim",
    [9] = "Cammy",      [10] = "Ken",       [11] = "Dee Jay",   [12] = "Lily",
    [13] = "A.K.I.",    [14] = "Rashid",    [15] = "Blanka",    [16] = "Juri",
    [17] = "Marisa",    [18] = "Guile",     [19] = "Ed",        [20] = "E. Honda",
    [21] = "Jamie",     [22] = "Akuma",     
    [23] = "M. Bison",  [24] = "Terry",     
    [25] = "Sagat",     [26] = "M. Bison",  [27] = "Terry",     [28] = "Mai",
    [29] = "Elena",     [30] = "Viper"
}

-- =========================================================
-- TOOLS & HELPERS
-- =========================================================

local function get_character_name(id) 
    if id == nil or id == -1 then return "Waiting..." end
    return CHARACTER_NAMES[id] or ("ID_" .. tostring(id)) 
end

local function format_duration(s) if not s or s < 0 then s = 0 end return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60)) end

local function styled_button(label, style, text_col)
    imgui.push_style_color(21, style.base); imgui.push_style_color(22, style.hover); imgui.push_style_color(23, style.active)
    if text_col then imgui.push_style_color(0, text_col) end
    local clicked = imgui.button(label)
    if text_col then imgui.pop_style_color(1) end
    imgui.pop_style_color(3)
    return clicked
end

local function styled_header(label, style)
    imgui.push_style_color(24, style.base); imgui.push_style_color(25, style.hover); imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

local function input_int_keyboard(label, value)
    local str_val = tostring(value or 0); local changed, new_str = imgui.input_text(label, str_val)
    if changed then local num = tonumber(new_str); if num then return true, num end end
    return false, value
end



-- [FIXED] GET P1 ACTION ID (via Engine)
local function get_p1_action_id()
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return -1 end
    local player_mgr = gBattle:get_field("Player"):get_data(nil)
    if not player_mgr then return -1 end
    local cPlayer = player_mgr.mcPlayer
    if not cPlayer then return -1 end
    local p1 = cPlayer[0] 
    if not p1 then return -1 end
    local actParam = p1.mpActParam
    if not actParam then return -1 end
    local actPart = actParam.ActionPart
    if not actPart then return -1 end
    local engine = actPart._Engine
    if not engine then return -1 end
    return engine:get_ActionID() or -1
end

-- MEMORY SCANNER
local function update_real_slot_info()
    local status, err = pcall(function()
        local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
        if not mgr then return end
        local rec_func = mgr:call("get_RecordFunc")
        if not rec_func then return end
        local t_data = rec_func:get_field("_tData")
        if not t_data then return end
        local rec_setting = t_data:get_field("RecordSetting")
        if not rec_setting then return end
        local fighter_list = rec_setting:get_field("FighterDataList")
        if not fighter_list then return end

        local target_id = game_state.p2_id
        if target_id == -1 then return end

        local dummy = fighter_list:call("get_Item", target_id) 
        if not dummy then return end
        local record_slots = dummy:get_field("RecordSlots")
        if not record_slots then return end

        for i=0, 7 do
            local slot_obj = record_slots:call("get_Item", i)
            if slot_obj then
                local lua_idx = i + 1
                real_slot_status[lua_idx].is_valid = slot_obj:get_field("IsValid")
                real_slot_status[lua_idx].is_active = slot_obj:get_field("IsActive")
            end
        end
    end)
end

local function load_conf()
    local data = json.load_file(CONFIG_FILENAME)
    if data then for k,v in pairs(data) do user_config[k] = v end end
    
    if type(user_config.hud_n_global_y) ~= "number" then user_config.hud_n_global_y = -0.35 end
    if type(user_config.hud_n_spacing_y) ~= "number" then user_config.hud_n_spacing_y = 0.05 end
    if type(user_config.hud_n_spread_score) ~= "number" then user_config.hud_n_spread_score = 0.15 end
    
    if type(user_config.timer_font_size) ~= "number" then user_config.timer_font_size = 60 end
    if type(user_config.hud_base_size) ~= "number" then user_config.hud_base_size = 60 end
    
    if user_config.playback_mode_auto == nil then user_config.playback_mode_auto = true end
    
    user_config.timer_mode_enabled = (user_config.session_mode == 1)
end
load_conf()


local function save_conf() 
    json.dump_file(CONFIG_FILENAME, user_config) 
end

-- =========================================================
-- LOGIC & EXPORTS
-- =========================================================

local function set_feedback(msg, color, duration)
    session.feedback.text = msg; session.feedback.color = color
    if duration and duration > 0 then session.feedback.timer = duration else session.feedback.timer = 0 end
end

local function reset_session_stats()
    SessionRecap.hide()
    session.score = 0; session.total = 0; session.is_running = false; session.is_paused = false
    session.real_start_time = os.time()
    
    session.is_time_up = false 
    session.time_up_delay = 0 
    
    set_playback_mode(false)
    
    for i=1,8 do session.slot_stats[i] = { attempts=0, success=0 } end
    
    session.is_tracking = false
    session.track_timer = 0
    session.outcome = "WAITING"
    session.score_processed = false
    session.di_counter_success = false
    session.last_act_id = -1
    
    if user_config.timer_mode_enabled then session.time_rem = user_config.timer_minutes * 60 else session.time_rem = 0 end
end

local function export_log_excel()
    local file = io.open(LOG_FILENAME, "a")
    if not file then session.export_msg = TEXTS.err_file; return end
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local duration = os.difftime(os.time(), session.real_start_time)
    local mode = (user_config.session_mode == 1) and "TIMED" or "INFINITE"
    local p1n = get_character_name(game_state.p1_id)
    local p2n = get_character_name(game_state.p2_id)
    local line = string.format("%s\t%s\t%s\t%s\t%s\t%d\t%d", now, format_duration(duration), mode, p1n, p2n, session.score, session.total)
    file:write(line .. "\n"); file:close()
    session.export_msg = "Stats Exported!"
end

-- =========================================================
-- HOOKS
-- =========================================================

local sdk_cache = {
    BattleMediator = sdk.find_type_definition("app.FBattleMediator")
}

if sdk_cache.BattleMediator then
    local update_method = sdk_cache.BattleMediator:get_method("UpdateGameInfo")
    if update_method then
        sdk.hook(update_method, function(args)
            local mediator = sdk.to_managed_object(args[2])
            if not mediator then return end
            
            local player_type_arr = mediator:get_field("PlayerType")
            if player_type_arr and player_type_arr:call("get_Length") >= 2 then
                local p1_obj = player_type_arr:call("GetValue", 0)
                local p2_obj = player_type_arr:call("GetValue", 1)
                
                local new_p1 = (p1_obj and p1_obj:get_field("value__")) or -1
                local new_p2 = (p2_obj and p2_obj:get_field("value__")) or -1
                
                game_state.p1_id = new_p1
                game_state.p2_id = new_p2
                
                if new_p1 ~= -1 and new_p2 ~= -1 then
                    if new_p1 ~= game_state.last_valid_p1 or new_p2 ~= game_state.last_valid_p2 then
                        reset_session_stats()
                        local msg = string.format("VS: %s", get_character_name(new_p2))
                        set_feedback(msg, COLORS.Cyan, 3.0)
                        game_state.last_valid_p1 = new_p1; game_state.last_valid_p2 = new_p2
                    end
                end
            end
        end, function(retval) return retval end)
    end
end

-- 2. FRAME METER HOOKS
local t_fm = sdk.find_type_definition("app.training.UIWidget_TMFrameMeter")

if t_fm then
    local m_setup = t_fm:get_method("SetUpFrame")
    if m_setup then
        sdk.hook(m_setup, function(args)
            local s = tonumber(tostring(sdk.to_int64(args[4])))
            if s > session.p1_max_frame then session.p1_max_frame = s end
        end, function(r) return r end)
    end

    local m_setdown = t_fm:get_method("SetDownFrame")
    if m_setdown then
        sdk.hook(m_setdown, function(args)
            local s = tonumber(tostring(sdk.to_int64(args[4])))
            local is_end = (sdk.to_int64(args[5]) & 1) == 1
            if s > session.p2_max_frame then session.p2_max_frame = s end
            if is_end then session.p2_is_end_flag = true end
        end, function(r) return r end)
    end
end

-- =========================================================
-- CORE ENGINE
-- =========================================================

local function is_game_in_menu()
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local field = pm:get_type_definition():get_field("_CurrentPauseBit")
        if field then 
            local val = field:get_data(pm)
            if val and tostring(val) ~= "131072" then return true end 
        end
    end
    return false
end

local function update_slot_stats(is_success)
    if game_state.current_slot_index >= 1 and game_state.current_slot_index <= 8 then
        local stats = session.slot_stats[game_state.current_slot_index]
        if stats then
            stats.attempts = stats.attempts + 1
            if is_success then
                stats.success = stats.success + 1
            end
        end
    end
end

-- =========================================================
-- PLAYBACK MANAGEMENT
-- =========================================================
local function manage_playback()
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    local rec_func = mgr and mgr:call("get_RecordFunc")
    local g_data = rec_func and rec_func:get_field("_gData")

    if not g_data then return end

    local current_state = tonumber(tostring(g_data:get_field("State"))) -- 0=Stop, 5=Play

    -- [FIX] ONLY MANAGE PLAYBACK IF SESSION IS RUNNING
    if session.is_running then
        -- 1. ACTIVE SESSION (PLAYING)
        if not session.is_paused and not session.is_time_up and playback_loop.active then
            
            -- If dummy is stopped
            if current_state == 0 then
                
                -- Wait 5 frames
                if playback_loop.wait_frames > 0 then
                    playback_loop.wait_frames = playback_loop.wait_frames - 1
                else
                    -- Play !
                    call_tm_method("SetPlay", true)
                    call_tm_method("ForceApply")
                    playback_loop.wait_frames = 5
                end
            else
                playback_loop.wait_frames = 5
            end
            
        -- 2. PAUSE / STOP (ONLY ENFORCE STOP IF SESSION IS ACTIVE BUT PAUSED)
        else
            -- Force stop if not stopped
            if current_state ~= 0 then
                call_tm_method("Stop", 0) 
            end
        end
    end
    -- IF SESSION IS NOT RUNNING -> DO NOTHING (Allows Manual Recording)
end

local function update_logic()
    local now = os.clock(); local dt = now - session.last_clock; session.last_clock = now
    
    if session.score ~= session.last_score then session.score_col = (session.score > session.last_score) and COLORS.Green or COLORS.Red; session.score_timer = 30; session.last_score = session.score end
    if session.score_timer > 0 then session.score_timer = session.score_timer - 1; if session.score_timer <= 0 then session.score_col = COLORS.White end end
    
    if session.is_time_up then
        session.time_up_delay = (session.time_up_delay or 0) + dt
        if session.time_up_delay > 1.0 then
            set_feedback(SharedUI.reset_message(), COLORS.Yellow, 0)
        end
        return 
    end

    if session.feedback.timer > 0 then
        session.feedback.timer = session.feedback.timer - dt
        if session.feedback.timer <= 0 then 
            if not session.is_tracking then 
                session.feedback.text = TEXTS.waiting; session.feedback.color = COLORS.Grey 
            end 
        end
    end

    -- [FIX] Logic Pause is handled in re.on_frame via pause flags
    -- Removed internal is_game_in_menu() call here.

    if session.is_running and not session.is_paused then
        if user_config.timer_mode_enabled then
            session.time_rem = session.time_rem - dt
            if session.time_rem <= 0 then
                session.time_rem = 0
                session.is_running = false
                session.is_time_up = true
                session.time_up_delay = 0
                set_playback_mode(false)
                export_log_excel()
                SessionRecap.show("REACTION DRILLS", LOG_FILENAME, "reactions")
                set_feedback("TIME UP! & EXPORTED", COLORS.Red, 0)
            end
        elseif user_config.session_mode == 2 then
            if session.total >= user_config.trial_count then
                session.is_running = false
                session.is_time_up = true
                session.time_up_delay = 0
                set_playback_mode(false)
                export_log_excel()
                SessionRecap.show("REACTION DRILLS", LOG_FILENAME, "reactions")
                set_feedback(session.total .. " TRIALS DONE! & EXPORTED", COLORS.Red, 0)
            end
        end
    end

    if session.is_paused then return end

    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    local rec_func = mgr and mgr:call("get_RecordFunc")
    if rec_func then
        local g_data = rec_func:get_field("_gData")
        if g_data then 
            game_state.current_slot_index = (g_data:get_field("SlotID") or -1) + 1
            game_state.current_rec_state = tonumber(tostring(g_data:get_field("State"))) or 0
            game_state.last_rec_state = game_state.current_rec_state
        end
    end

    -- =========================================================
    -- LOGIC FLAGS & STATES (PURE)
    -- =========================================================
    
    session.p1_state = session.p1_max_frame
    session.p2_state = session.p2_max_frame
    local p2_ended = session.p2_is_end_flag
    
    session.p1_max_frame = 0 
    session.p2_max_frame = 0
    session.p2_is_end_flag = false 
    
    local p1 = session.p1_state
    local p2 = session.p2_state
    
    -- [NEW V6.6] RESET LOGIC IF NEUTRAL AND NOT TRACKING P2
    if not session.is_tracking and p1 == STATE_NEUTRAL then
        session.score_processed = false
    end
    
    -- [NEW V6.8] CHECK WHIFF DR CANCEL (ID 739) VIA P2 STATE
    local curr_act_id = get_p1_action_id()
    
    if session.is_running and not session.score_processed then
        -- If player transitioned to DR (739)
        if curr_act_id == 739 and session.last_act_id ~= 739 then
             -- ONLY FAIL IF P2 IS NOT HURT AND NOT BLOCK (Whiff)
             if p2 ~= STATE_HURT and p2 ~= STATE_BLOCK then
                 set_feedback("FAIL: UNSAFE DR CANCEL", COLORS.Red, 2.0)
                 session.score = session.score - 1
                 session.total = session.total + 1
                 update_slot_stats(false) 
                 session.score_processed = true
             end
        end
    end
    session.last_act_id = curr_act_id
    
    if not session.is_tracking then
        if ATTACK_STATES[p2] and p2 ~= 0 then
            if p1 ~= STATE_HURT and p1 ~= STATE_BLOCK then
                session.is_tracking = true
                session.track_timer = 0
                set_feedback(TEXTS.attack_inc, COLORS.Yellow, 0)
                session.di_counter_success = false
                session.score_processed = false
            end
        end
    else
        session.track_timer = session.track_timer + 1

        if not session.score_processed then
            if p2 == STATE_HURT then
                 set_feedback(TEXTS.success, COLORS.Green, 2.0)
                 session.score = session.score + 1
                 session.total = session.total + 1
                 update_slot_stats(true) 
                 session.score_processed = true
            elseif p1 == STATE_HURT then
                set_feedback(TEXTS.fail_hit, COLORS.Red, 2.0)
                session.score = session.score - 1
                session.total = session.total + 1
                update_slot_stats(false) 
                session.score_processed = true
            elseif p1 == STATE_BLOCK then
                set_feedback(TEXTS.fail_block, COLORS.Red, 2.0)
                session.score = session.score - 1
                session.total = session.total + 1
                update_slot_stats(false) 
                session.score_processed = true
            elseif p2 == STATE_DI and p1 == STATE_DI then
                set_feedback("DI COUNTER!", COLORS.Green, 2.0)
                session.di_counter_success = true
                session.score_processed = true 
            end
        end
        
        if p2 == STATE_NEUTRAL or p2_ended then
            session.is_tracking = false
            if session.track_timer > 2 then
                if not session.score_processed then
                    if session.di_counter_success then
                        set_feedback("DI COUNTER!", COLORS.Green, 2.0)
                    else
                        set_feedback(TEXTS.fail_whiff, COLORS.Red, 2.0)
                        session.score = session.score - 1
                        session.total = session.total + 1
                        update_slot_stats(false) 
                        session.score_processed = true
                    end
                end
            else
                if not session.score_processed then
                    set_feedback(TEXTS.waiting, COLORS.Grey, 0)
                end
            end
        end
    end
end
-- =========================================================
-- INPUT HANDLING
-- =========================================================
local last_input_mask = 0
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

    -- 1. TIMER/TRIALS SETTINGS (UP/DOWN)
    if not session.is_running and not session.is_time_up then
        if is_action(BTN_UP, 0x32) then
            if user_config.session_mode == 2 then
                user_config.trial_count = math.min(200, user_config.trial_count + 10)
                set_feedback(tostring(user_config.trial_count), COLORS.White, 1.0)
            else
                user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1)
                session.time_rem = user_config.timer_minutes * 60
                set_feedback("TIMER: " .. user_config.timer_minutes .. " MIN", COLORS.White, 1.0)
            end
            save_conf()
        end
        if is_action(BTN_DOWN, 0x31) then
            if user_config.session_mode == 2 then
                user_config.trial_count = math.max(10, user_config.trial_count - 10)
                set_feedback(tostring(user_config.trial_count), COLORS.White, 1.0)
            else
                user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1)
                session.time_rem = user_config.timer_minutes * 60
                set_feedback("TIMER: " .. user_config.timer_minutes .. " MIN", COLORS.White, 1.0)
            end
            save_conf()
        end
    end

    -- POSITION 3 (key 3): START when not running, STOP when running
    -- Pad: BTN_RIGHT=start/pause, BTN_LEFT=stop/reset (unchanged)
    local pos3_kb = kb_pressed(0x33)
    local pos3_pad = is_func_held and pad_pressed(BTN_RIGHT)
    local pos4_kb = kb_pressed(0x34)
    local pos4_pad = is_func_held and pad_pressed(BTN_LEFT)

    -- Position 3 (key 3 / FUNC+LEFT): RESET when idle, STOP when running
    if not session.is_running and not session.is_time_up then
        if pos3_kb or pos4_pad then
            reset_session_stats()
            set_feedback(TEXTS.reset_done, COLORS.White, 1.0)
        end
    elseif session.is_running then
        if pos3_kb or pos4_pad then
            set_playback_mode(false)
            export_log_excel()
            reset_session_stats()
            set_feedback(TEXTS.stopped_export, COLORS.Red, 1.5)
        end
    elseif session.is_time_up then
        if pos3_kb or pos4_pad then
            reset_session_stats()
            set_feedback(TEXTS.reset_done, COLORS.White, 1.0)
        end
    end

    -- Position 4 (key 4 / FUNC+RIGHT): START when idle, PAUSE when running
    if not session.is_running and not session.is_time_up then
        if pos4_kb or pos3_pad then
            reset_session_stats()
            session.time_rem = user_config.timer_minutes * 60
            session.is_running = true
            session.is_paused = false
            set_feedback(TEXTS.started, COLORS.Green, 1.0)
            set_playback_mode(true)
        end
    elseif session.is_running then
        if pos4_kb or pos3_pad then
            session.is_paused = not session.is_paused
            set_feedback(session.is_paused and TEXTS.paused or TEXTS.resumed, COLORS.Yellow, 1.0)
            set_playback_mode(not session.is_paused)
        end
    end

    last_input_mask = active_buttons
    last_kb_state = kb_state
end

-- =========================================================
-- HUD DRAWING
-- =========================================================


local function manage_ticker_visibility_backup()
    local should_hide = (user_config.session_mode == 1)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return end
    local dict = mgr:get_field("_ViewUIWigetDict")
    if not dict then return end
    local entries = dict:get_field("_entries")
    if not entries then return end
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
                        if type and string.find(type:get_name(), "UIWidget_TMTicker") then
                            widget:call("set_Visible", not should_hide)
                            return
                        end
                    end
                end
            end
        end
    end
end

local ui_hide_targets = {
    BattleHud_Timer = { { "c_main", "c_hud", "c_timer", "c_infinite" } }
}

local apply_force_invisible
apply_force_invisible = function(control, path, depth, should_hide)
    local depth = depth or 1
    if depth > #path then control:call("set_ForceInvisible", should_hide); return end
    local child = control:call("get_Child")
    while child do
        local name = child:call("get_Name")
        if name and string.match(name, path[depth]) then apply_force_invisible(child, path, depth + 1, should_hide) end
        child = child:call("get_Next")
    end
end

re.on_pre_gui_draw_element(function(element, context)
if _G.CurrentTrainerMode ~= 1 then return true end
    local game_object = element:call("get_GameObject")
    if not game_object then return true end
    local name = game_object:call("get_Name")
    local paths = ui_hide_targets[name]
    if paths then
        local should_hide = (user_config.session_mode == 1)
        local view = element:call("get_View")
        for _, path in ipairs(paths) do apply_force_invisible(view, path, 1, should_hide) end
    end
    return true
end)

-- Fonction pour dessiner le HUD (Extraite pour clarté, à appeler dans on_frame)
local function draw_hud_overlay()
    local show_timer = (user_config.session_mode == 1)
    
    local is_trials = (user_config.session_mode == 2)
    SharedUI.draw_standard_hud("HUD_Reaction", user_config, session, TEXTS.mode_label, show_timer and not is_trials, function(cx, cy, sw, sh)
        if is_trials then
            local center_y = sh / 2
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
        if user_config.show_slot_stats then
            local slots_str = ""
            local has_visible_slots = false
            for i=1,8 do
                if real_slot_status[i] and real_slot_status[i].is_active then
                    local s = session.slot_stats[i]
                    local pct = 0; if s and s.attempts > 0 then pct = (s.success / s.attempts) * 100 end
                    slots_str = slots_str .. string.format("S%d:%.0f%%  ", i, pct)
                    has_visible_slots = true
                end
            end
            if not has_visible_slots then slots_str = "WAITING FOR ACTIVE SLOTS..." end
            local w_sl = imgui.calc_text_size(slots_str).x
            SharedUI.draw_text(slots_str, cx - w_sl/2, cy, SharedUI.COLORS.White)
        end
    end)
end

-- =========================================================
-- SESSION BUTTONS — DOCKED (menu REFramework)
-- =========================================================
local function draw_session_buttons_docked()
    local sl = SharedUI.sc_label
    local SC = SharedUI.SC_COLORS

    local mode_label = user_config.session_mode == 2 and "MODE: TRIALS" or "MODE: TIMER"
    if imgui.button(mode_label .. "##dk_mode_r") then
        user_config.session_mode = user_config.session_mode == 2 and 1 or 2
        user_config.timer_mode_enabled = (user_config.session_mode == 1)
        reset_session_stats(); save_conf()
    end
    imgui.same_line()
    if user_config.session_mode == 2 then
        if SharedUI.sc_button("TRIALS - (" .. sl("D") .. ")##dk_r", SC.c1) then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        imgui.same_line()
        if SharedUI.sc_button("TRIALS + (" .. sl("U") .. ")##dk_r", SC.c2) then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
        imgui.same_line(); imgui.text(tostring(user_config.trial_count) .. " TRIALS")
    else
        if SharedUI.sc_button("TIMER - (" .. sl("D") .. ")##dk_r", SC.c1) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
        imgui.same_line()
        if SharedUI.sc_button("TIMER + (" .. sl("U") .. ")##dk_r", SC.c2) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
        imgui.same_line(); imgui.text(tostring(user_config.timer_minutes) .. " min")
    end
    imgui.same_line(300)
    if SharedUI.sc_button("RESET (" .. sl("L", "3") .. ")##dk_r", SC.c3) then reset_session_stats(); set_feedback(TEXTS.reset_done, COLORS.White, 1.0) end

    imgui.spacing()
    if not session.is_running then
        if SharedUI.sc_button("START SESSION (" .. sl("R", "4") .. ")##dk_r", SC.c4) then
            reset_session_stats()
            if user_config.session_mode ~= 2 then session.time_rem = user_config.timer_minutes * 60 end
            session.is_running = true; session.is_paused = false
            set_feedback(TEXTS.started, COLORS.Green, 1.0)
            set_playback_mode(true)
        end
    else
        if SharedUI.sc_button("STOP & EXPORT (" .. sl("L", "3") .. ")##dk_r", SC.c3) then
            set_playback_mode(false); export_log_excel(); reset_session_stats(); set_feedback(TEXTS.stopped_export, COLORS.Red, 1.0)
        end
        imgui.same_line()
        if SharedUI.sc_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##dk_r", SC.c4) then
            session.is_paused = not session.is_paused; set_playback_mode(not session.is_paused)
        end
    end
end

-- =========================================================
-- SESSION BUTTONS — FLOATING (single-line, ComboTrials style)
-- =========================================================
local function draw_session_floating()
    local visible, sw, sh = SharedUI.begin_floating_window("Reaction Drills##float")
    if not visible then
        user_config.show_floating = false; save_conf()
        SharedUI.end_floating_window(); return
    end
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
    if user_config.session_mode == 2 then
        if SharedUI.sf6_button("TRIALS - (" .. sl("D") .. ")##fl_r", SC.c1, actual_w) then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        imgui.same_line(0, sp)
        if SharedUI.sf6_button("TRIALS + (" .. sl("U") .. ")##fl_r", SC.c2, actual_w) then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
    else
        if SharedUI.sf6_button("TIMER - (" .. sl("D") .. ")##fl_r", SC.c1, actual_w) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
        imgui.same_line(0, sp)
        if SharedUI.sf6_button("TIMER + (" .. sl("U") .. ")##fl_r", SC.c2, actual_w) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
    end
    imgui.same_line(0, sp)
    if not session.is_running then
        if SharedUI.sf6_button("RESET (" .. sl("L", "3") .. ")##fl_r", SC.c3, actual_w) then reset_session_stats(); set_feedback(TEXTS.reset_done, COLORS.White, 1.0) end
    else
        if SharedUI.sf6_button("STOP (" .. sl("L", "3") .. ")##fl_r", SC.c3, actual_w) then
            set_playback_mode(false); export_log_excel(); reset_session_stats(); set_feedback(TEXTS.stopped_export, COLORS.Red, 1.0)
        end
    end
    imgui.same_line(0, sp)
    if session.is_running then
        if SharedUI.sf6_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##fl_r", SC.c4, actual_w) then
            session.is_paused = not session.is_paused; set_playback_mode(not session.is_paused)
        end
    else
        if SharedUI.sf6_button("START (" .. sl("R", "4") .. ")##fl_r", SC.c4, actual_w) then
            reset_session_stats()
            if user_config.session_mode ~= 2 then session.time_rem = user_config.timer_minutes * 60 end
            session.is_running = true; session.is_paused = false
            set_feedback(TEXTS.started, COLORS.Green, 1.0); set_playback_mode(true)
        end
    end
    imgui.same_line(w_width - cb_size - 10 - pad_x)
    local changed, new_val = imgui.checkbox("##close_react", user_config.show_floating)
    if changed then user_config.show_floating = new_val; save_conf() end
    SharedUI.end_floating_window()
end

re.on_frame(function()
    local cur_mode = _G.CurrentTrainerMode or 0
    if cur_mode == 1 and last_trainer_mode ~= 1 then
        reset_session_stats()
        set_feedback(TEXTS.reset_done, COLORS.White, 1.0)
    end
    last_trainer_mode = cur_mode

    if cur_mode ~= 1 then return end
    if not sdk.get_managed_singleton("app.training.TrainingManager") then return end

    local should_update_logic = true
    local should_draw_hud = true

    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pause_bit = pm:get_field("_CurrentPauseTypeBit")
        -- Si pause active ou état non standard (différent de 64 et 2112)
        if pause_bit and (pause_bit ~= 64 and pause_bit ~= 2112) then
            if session.is_running and not session.is_paused then
                session.is_paused = true
                session._auto_paused = true
                set_playback_mode(false) -- AUTO PAUSE
            end
            should_update_logic = false
            should_draw_hud = false
        else
            -- Menu closed: auto-unpause if it was auto-paused
            if session._auto_paused and session.is_paused then
                session.is_paused = false
                session._auto_paused = false
                set_playback_mode(true)
            end
        end
    end
    
    if should_update_logic then
        update_real_slot_info() 
        handle_input()
        manage_playback()
        update_logic()
        manage_ticker_visibility_backup()
    end
    
    if should_draw_hud then
        draw_hud_overlay()
    end

    -- FLOATING SESSION WINDOW
    if should_draw_hud and user_config.show_floating then
        draw_session_floating()
    end
end)

-- =========================================================
-- MENU UI
-- =========================================================

re.on_draw_ui(function()
    if _G.CurrentTrainerMode ~= 1 then return end

    if imgui.tree_node("Reaction Trainer Remastered (V6.10 - Recording Fix)") then

        if styled_header("--- SESSION CONFIGURATION ---", UI_THEME.hdr_session) then
                local c_fl, v_fl = imgui.checkbox("Detacher en fenetre flottante", user_config.show_floating)
                if c_fl then user_config.show_floating = v_fl; save_conf() end

                if user_config.show_floating then
                    imgui.text_colored("Cette section est actuellement detachee en fenetre flottante.", COLORS.DarkGrey)
                else
                    imgui.separator(); imgui.spacing()
                    draw_session_buttons_docked()
                end
        end

		if styled_header("--- SLOTS & MATCHUPS ---", UI_THEME.hdr_slots) then
            imgui.text_colored("INSTANT LOOP ACTIVE", COLORS.Green)
            imgui.text("Playback restarts immediately after action ends.")
            
            -- TOGGLE AUTO / MANUAL
            imgui.separator()
            local c_auto, v_auto = imgui.checkbox("Auto-Activate All Slots", user_config.playback_mode_auto)
            if c_auto then user_config.playback_mode_auto = v_auto; save_conf() end
            
            if user_config.playback_mode_auto then
                imgui.text_colored("Mode: AUTO", COLORS.Cyan)
                imgui.text("Script forces all filled slots to ACTIVE on start.")
            else
                imgui.text_colored("Mode: MANUAL", COLORS.Orange)
                imgui.text("Script ONLY presses Play. You must select slots in-game.")
            end
            
            imgui.separator()
            local c_st, v_st = imgui.checkbox("Show Slot Percentages on HUD", user_config.show_slot_stats); if c_st then user_config.show_slot_stats = v_st; save_conf() end
        end
        
        if styled_header("--- UI LAYOUT ADJUSTMENTS ---", UI_THEME.hdr_layout) then
            local chg = false; local v
			local c_main, v_main = input_int_keyboard("Main Text Size", user_config.hud_base_size)
            if c_main then user_config.hud_base_size = v_main; save_conf(); SharedUI.update_fonts(user_config) end
            local c_time, v_time = input_int_keyboard("Timer Font Size", user_config.timer_font_size)
            if c_time then user_config.timer_font_size = v_time; save_conf(); SharedUI.update_fonts(user_config) end
            imgui.separator()
            chg, v = imgui.slider_float("Global Y Pos", user_config.hud_n_global_y, -1.0, 1.0); if chg then user_config.hud_n_global_y = v; save_conf() end
            chg, v = imgui.slider_float("Line Spacing", user_config.hud_n_spacing_y, 0.0, 0.2); if chg then user_config.hud_n_spacing_y = v; save_conf() end
            imgui.separator()
            chg, v = imgui.slider_float("Score Spread", user_config.hud_n_spread_score, 0.0, 0.5); if chg then user_config.hud_n_spread_score = v; save_conf() end
            chg, v = imgui.slider_float("Score X", user_config.hud_n_offset_score, -0.5, 0.5); if chg then user_config.hud_n_offset_score = v; save_conf() end
            chg, v = imgui.slider_float("Total X", user_config.hud_n_offset_total, -0.5, 0.5); if chg then user_config.hud_n_offset_total = v; save_conf() end
            chg, v = imgui.slider_float("Label X", user_config.hud_n_offset_timer, -0.2, 0.2); if chg then user_config.hud_n_offset_timer = v; save_conf() end
            chg, v = imgui.slider_float("Status Y", user_config.hud_n_offset_status_y, -0.2, 0.2); if chg then user_config.hud_n_offset_status_y = v; save_conf() end
            imgui.separator()
            chg, v = imgui.slider_float("Timer Y", user_config.timer_hud_y, -1.0, 1.0); if chg then user_config.timer_hud_y = v; save_conf() end
            chg, v = imgui.slider_float("Timer X", user_config.timer_offset_x, -0.5, 0.5); if chg then user_config.timer_offset_x = v; save_conf() end
        end
        
        if styled_header("--- DEBUG PANEL ---", UI_THEME.hdr_debug) then
            local cd, vd = imgui.checkbox("Enable Overlay", user_config.show_debug_panel); if cd then user_config.show_debug_panel = vd; save_conf() end
            imgui.text("P1 State: " .. session.p1_state)
            imgui.text("P2 State: " .. session.p2_state)
            imgui.text("Active Slot: " .. game_state.current_slot_index)
            imgui.text("Last P1 Act: " .. session.last_act_id)
        end
        
        imgui.tree_pop()
    end

    if user_config.show_debug_panel then
        imgui.begin_window("Debug Overlay", true, 0)
        imgui.text("Auto Logic Active")
        imgui.text("Wait frames: " .. playback_loop.wait_frames)
        imgui.end_window()
    end
end)