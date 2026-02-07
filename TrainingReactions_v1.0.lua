local re = re
local sdk = sdk
local imgui = imgui
local draw = draw
local json = json

-- =========================================================
-- ReactionTraining Remastered (V5.0 - FLAGS & LOGIC)
-- =========================================================

-- =========================================================
-- CONFIGURATION FRAME METER
-- =========================================================
local STATE_NEUTRAL = 0
local STATE_HURT    = 9
local STATE_BLOCK   = 10
local STATE_DI      = 11
local STATE_DR      = 12 

-- ETATS D'ATTAQUE (DÉCLENCHEURS)
local ATTACK_STATES = { 
    [7]=true,   -- Startup (Début du coup)
    [8]=false,  -- Recovery (Ce n'est pas un début d'attaque)
    [13]=true,  -- Active
    [11]=true,  -- Drive Impact
    [12]=false, -- Drive Rush ignoré
    [1]=true,   -- Invincible
    [2]=true,
    [3]=true,
    [4]=true
}

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
    infinite_label  = "INFINITE",
    
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
    
    pause_overlay   = "PAUSED : PRESS (SELECT OR R3) + RIGHT TO RESUME",
    err_file        = "Err: File Access"
}

-- Stockage de l'état réel lu en mémoire
local real_slot_status = {}
for i=1,8 do real_slot_status[i] = { is_valid=false, is_active=false } end

local last_trainer_mode = 0

-- BUTTON MASKS
local BTN_SELECT = 16384
local BTN_R3     = 8192
local BTN_UP     = 1
local BTN_DOWN   = 2
local BTN_LEFT   = 4
local BTN_RIGHT  = 8

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

local IMGUI_FLAGS = {
    NoTitleBar = 1, NoResize = 2, NoMove = 4, NoScrollbar = 8, 
    NoMouseInputs = 512, NoNav = 786432, NoBackground = 128
}

local custom_font = { obj = nil, filename = "capcom_goji-udkakugoc80pro-db.ttf", loaded_size = 0, status = "Init..." }
local custom_font_timer = { obj = nil, filename = "SF6_college.ttf", loaded_size = 0, status = "Init..." }
local res_watcher = { last_w = 0, last_h = 0, cooldown = 0 }

-- CONFIGURATION COMPLETE
local user_config = {
    session_mode = 0, 
    timer_minutes = 3,
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
}

-- Session State
local session = {
    is_running = false, is_paused = false, 
    start_ts = os.time(), real_start_time = os.time(), time_rem = 0, last_clock = 0,
    score = 0, total = 0, 
    last_score = 0, score_col = COLORS.White, score_timer = 0,
    status_msg = TEXTS.ready, export_msg = "",
    feedback = { text = TEXTS.waiting, timer = 0, color = COLORS.White },
    slot_stats = {},
    
    -- VARIABLES AUTO TRACKING
    p1_max_frame = 0,
    p2_max_frame = 0,
    p2_is_end_flag = false, -- LE FAMEUX FLAG (Arg 5)
    
    p1_state = 0,
    p2_state = 0,
    is_tracking = false,
    track_timer = 0,
    outcome = "WAITING",
    di_counter_success = false,
    score_processed = false
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

-- SCANNER MEMOIRE MANNEQUIN
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
    
    user_config.timer_mode_enabled = (user_config.session_mode == 1)
end
load_conf()

local function try_load_font()
    if not imgui.load_font then return end
    local sw, sh = get_dynamic_screen_size(); local scale_factor = sh / 1080.0
    if scale_factor < 0.1 then scale_factor = 1.0 end
    
    if type(user_config.hud_base_size) ~= "number" then user_config.hud_base_size = 60 end
    if type(user_config.timer_font_size) ~= "number" then user_config.timer_font_size = 60 end

    local target_size = math.floor(user_config.hud_base_size * (user_config.hud_auto_scale and scale_factor or 1.0))
    local font = imgui.load_font(custom_font.filename, target_size)
    if font then custom_font.obj = font; custom_font.loaded_size = target_size end

    local target_size_timer = math.floor(user_config.timer_font_size * (user_config.hud_auto_scale and scale_factor or 1.0))
    local font_t = imgui.load_font(custom_font_timer.filename, target_size_timer)
    if font_t then custom_font_timer.obj = font_t end
end
try_load_font()

local function handle_resolution_change()
    local sw, sh = get_dynamic_screen_size()
    if res_watcher.last_w == 0 then res_watcher.last_w = sw; res_watcher.last_h = sh; try_load_font(); return end
    if sw ~= res_watcher.last_w or sh ~= res_watcher.last_h then res_watcher.cooldown = 30; res_watcher.last_w = sw; res_watcher.last_h = sh end
    if res_watcher.cooldown > 0 then res_watcher.cooldown = res_watcher.cooldown - 1; if res_watcher.cooldown == 0 then try_load_font() end end
end

local function save_conf() json.dump_file(CONFIG_FILENAME, user_config) end

-- =========================================================
-- LOGIC & EXPORTS
-- =========================================================

local function set_feedback(msg, color, duration)
    session.feedback.text = msg; session.feedback.color = color
    if duration and duration > 0 then session.feedback.timer = duration else session.feedback.timer = 0 end
end

local function reset_session_stats()
    session.score = 0; session.total = 0; session.is_running = false; session.is_paused = false
    session.real_start_time = os.time()
    for i=1,8 do session.slot_stats[i] = { attempts=0, success=0 } end
    
    -- Reset Auto-Tracking Logic
    session.is_tracking = false
    session.track_timer = 0
    session.outcome = "WAITING"
    session.score_processed = false
    session.di_counter_success = false
    
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
-- SYSTEME DE HOOKS
-- =========================================================

-- 1. DETECTION ID JOUEURS (Pour scanner les slots)
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

-- 2. FRAME METER HOOKS (AVEC LES FLAGS isEnd)
local t_fm = sdk.find_type_definition("app.training.UIWidget_TMFrameMeter")

if t_fm then
    -- P1 (Toi)
    local m_setup = t_fm:get_method("SetUpFrame")
    if m_setup then
        sdk.hook(m_setup, function(args)
            local s = tonumber(tostring(sdk.to_int64(args[4])))
            if s > session.p1_max_frame then session.p1_max_frame = s end
        end, function(r) return r end)
    end

    -- P2 (Adversaire)
    local m_setdown = t_fm:get_method("SetDownFrame")
    if m_setdown then
        sdk.hook(m_setdown, function(args)
            local s = tonumber(tostring(sdk.to_int64(args[4])))
            
            -- ARGUMENT 5 = LE FLAG "isEnd" (C'est lui qu'on voulait !)
            local is_end = (sdk.to_int64(args[5]) & 1) == 1
            
            if s > session.p2_max_frame then session.p2_max_frame = s end
            
            -- Si le flag isEnd est vrai, on le mémorise pour cette frame
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

local function update_logic()
    local now = os.clock(); local dt = now - session.last_clock; session.last_clock = now
    
    if session.score ~= session.last_score then session.score_col = (session.score > session.last_score) and COLORS.Green or COLORS.Red; session.score_timer = 30; session.last_score = session.score end
    if session.score_timer > 0 then session.score_timer = session.score_timer - 1; if session.score_timer <= 0 then session.score_col = COLORS.White end end
    
    if session.feedback.timer > 0 then
        session.feedback.timer = session.feedback.timer - dt
        if session.feedback.timer <= 0 then 
            if not session.is_tracking then 
                session.feedback.text = TEXTS.waiting; session.feedback.color = COLORS.Grey 
            end 
        end
    end

    local game_paused = is_game_in_menu()

    if session.is_running and not game_paused and user_config.timer_mode_enabled and not session.is_paused then
        session.time_rem = session.time_rem - dt
        if session.time_rem <= 0 then 
            session.time_rem = 0; session.is_running = false; 
            export_log_excel()
            set_feedback(TEXTS.time_up, COLORS.Red, 0) 
        end
    end

    if game_paused or session.is_paused then return end

    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    local rec_func = mgr and mgr:call("get_RecordFunc")
    if rec_func then
        local g_data = rec_func:get_field("_gData")
        if g_data then 
            game_state.current_slot_index = (g_data:get_field("SlotID") or -1) + 1
            game_state.current_rec_state = tonumber(tostring(g_data:get_field("State"))) or 0
            
            if user_config.session_mode == 1 and not session.is_running then
                if game_state.last_rec_state == 0 and game_state.current_rec_state ~= 0 then
                    reset_session_stats()
                    session.is_running = true
                    session.is_paused = false
                    session.time_rem = user_config.timer_minutes * 60
                    set_feedback("AUTO START!", COLORS.Green, 2.0)
                end
            end
            game_state.last_rec_state = game_state.current_rec_state
        end
    end

    -- =========================================================
    -- LOGIQUE FLAGS & STATES (PURE)
    -- =========================================================
    
    -- 1. Récupération des Données
    session.p1_state = session.p1_max_frame
    session.p2_state = session.p2_max_frame
    
    local p2_ended = session.p2_is_end_flag -- Le flag "Fin de coup" officiel
    
    -- Reset pour la prochaine frame
    session.p1_max_frame = 0 
    session.p2_max_frame = 0
    session.p2_is_end_flag = false 
    
    local p1 = session.p1_state
    local p2 = session.p2_state
    
    -- 2. Machine à États
    
    -- CAS A : Début d'une VRAIE attaque
    if not session.is_tracking then
        -- Condition 1: P2 est dans un état d'attaque valide (7, 13, 11...)
        -- Condition 2: P1 n'est PAS déjà en Hit/Block (Protection contre le double compte)
        if ATTACK_STATES[p2] and p2 ~= 0 then
            
            if p1 ~= STATE_HURT and p1 ~= STATE_BLOCK then
                session.is_tracking = true
                session.track_timer = 0
                set_feedback(TEXTS.attack_inc, COLORS.Yellow, 0)
                session.di_counter_success = false
                session.score_processed = false
            end
        end
        
    -- CAS B : Pendant l'attaque
    else
        session.track_timer = session.track_timer + 1

        if not session.score_processed then
            
            -- P2 Interrompu -> SUCCESS
            if p2 == STATE_HURT then
                 set_feedback(TEXTS.success, COLORS.Green, 2.0)
                 session.score = session.score + 1
                 session.total = session.total + 1
                 update_slot_stats(true) 
                 session.score_processed = true
            
            -- P1 Touché -> FAIL
            elseif p1 == STATE_HURT then
                set_feedback(TEXTS.fail_hit, COLORS.Red, 2.0)
                session.score = session.score - 1
                session.total = session.total + 1
                update_slot_stats(false) 
                session.score_processed = true

            -- P1 Bloque -> FAIL
            elseif p1 == STATE_BLOCK then
                set_feedback(TEXTS.fail_block, COLORS.Red, 2.0)
                session.score = session.score - 1
                session.total = session.total + 1
                update_slot_stats(false) 
                session.score_processed = true
                
            -- DI vs DI -> SUCCESS
            elseif p2 == STATE_DI and p1 == STATE_DI then
                set_feedback("DI COUNTER!", COLORS.Green, 2.0)
                session.di_counter_success = true
                session.score_processed = true 
            end
        end
        
        -- FIN DE SEQUENCE
        -- On utilise LE FLAG (Arg 5) ou le retour à 0
        if p2 == STATE_NEUTRAL or p2_ended then
            session.is_tracking = false
            
            -- Filtre anti-glitch (> 2 frames)
            if session.track_timer > 2 then
                if not session.score_processed then
                    if session.di_counter_success then
                        set_feedback("DI COUNTER!", COLORS.Green, 2.0)
                    else
                        -- C'est un WHIFF -> FAIL
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

    local function is_func_combo_pressed(target_mask)
        local is_func_held = ((active_buttons & BTN_SELECT) == BTN_SELECT) or ((active_buttons & BTN_R3) == BTN_R3)
        if not is_func_held then return false end
        return ((active_buttons & target_mask) == target_mask) and not ((last_input_mask & target_mask) == target_mask)
    end

    if is_func_combo_pressed(BTN_UP) then
        user_config.session_mode = (user_config.session_mode == 1) and 2 or 1
        user_config.timer_mode_enabled = (user_config.session_mode == 1)
        reset_session_stats()
        local msg = (user_config.session_mode == 2) and TEXTS.mode_infinite or TEXTS.mode_timed
        set_feedback(msg, COLORS.Cyan, 1.0); save_conf()
    end

    if is_func_combo_pressed(BTN_LEFT) then
        if user_config.session_mode == 1 then
            if not session.is_running then
                session.is_running = true; session.is_paused = false; reset_session_stats(); session.time_rem = user_config.timer_minutes * 60; session.is_running = true; set_feedback(TEXTS.started, COLORS.Green, 1.0)
            else export_log_excel(); reset_session_stats(); set_feedback(TEXTS.stopped_export, COLORS.Red, 1.0) end
        elseif user_config.session_mode == 2 then
            export_log_excel(); set_feedback(TEXTS.stats_exported, COLORS.Green, 1.0)
        end
    end

    if is_func_combo_pressed(BTN_RIGHT) then
        if user_config.session_mode == 1 and session.is_running then
            session.is_paused = not session.is_paused
            set_feedback(session.is_paused and TEXTS.paused or TEXTS.resumed, COLORS.Yellow, 1.0)
        end
    end
    
    if is_func_combo_pressed(BTN_DOWN) then
        user_config.show_debug_panel = not user_config.show_debug_panel
        set_feedback("DEBUG PANEL: " .. (user_config.show_debug_panel and "ON" or "OFF"), COLORS.White, 1.0)
    end

    last_input_mask = active_buttons
end

-- =========================================================
-- HUD DRAWING
-- =========================================================

local function draw_text_overlay(text, x, y, color)
    local safe_text = string.gsub(text, "%%", "%%%%")
    local outline_color = COLORS.Grey 
    local outline_thick = 0.1             
    local shadow_depth = 0              

    imgui.set_cursor_pos(Vector2f.new(x + shadow_depth, y + shadow_depth))
    imgui.text_colored(safe_text, outline_color)

    for dx = -outline_thick, outline_thick do
        for dy = -outline_thick, outline_thick do
            if (dx ~= 0 or dy ~= 0) and (math.abs(dx) + math.abs(dy) <= outline_thick) then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe_text, outline_color)
            end
        end
    end

    imgui.set_cursor_pos(Vector2f.new(x, y))
    imgui.text_colored(safe_text, color)
end

local function draw_timer_outline(text, x, y, color)
    local safe_text = string.gsub(text, "%%", "%%%%"); local outline_color = 0xFF000000; local thickness = 2
    for dx = -thickness, thickness, thickness do for dy = -thickness, thickness, thickness do if dx~=0 or dy~=0 then imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy)); imgui.text_colored(safe_text, outline_color) end end end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe_text, color)
end

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

re.on_frame(function()
    local cur_mode = _G.CurrentTrainerMode or 0
    if cur_mode == 1 and last_trainer_mode ~= 1 then
        reset_session_stats()
        set_feedback(TEXTS.reset_done, COLORS.White, 1.0)
    end
    last_trainer_mode = cur_mode

    if cur_mode ~= 1 then return end
    
    update_real_slot_info() 
    handle_input()
    update_logic()
    handle_resolution_change()
    manage_ticker_visibility_backup() 
    
    if is_game_in_menu() then return end
    
    local sw, sh = get_dynamic_screen_size()
    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0) 
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    local win_flags = IMGUI_FLAGS.NoTitleBar | IMGUI_FLAGS.NoResize | IMGUI_FLAGS.NoMove | IMGUI_FLAGS.NoScrollbar | IMGUI_FLAGS.NoMouseInputs | IMGUI_FLAGS.NoNav | IMGUI_FLAGS.NoBackground

    if imgui.begin_window("HUD_Reaction", true, win_flags) then
        if custom_font.obj then imgui.push_font(custom_font.obj) end
        
        local center_x = sw / 2
        local center_y = sh / 2
        
        if type(user_config.hud_n_global_y) ~= "number" then user_config.hud_n_global_y = -0.35 end
        local top_y = center_y + (user_config.hud_n_global_y * sh)
        
        if type(user_config.hud_n_spread_score) ~= "number" then user_config.hud_n_spread_score = 0.15 end
        local spread_score_px = user_config.hud_n_spread_score * sw
        
        if type(user_config.hud_n_spacing_y) ~= "number" then user_config.hud_n_spacing_y = 0.05 end
        local spacing_y_px    = user_config.hud_n_spacing_y * sh
        
        local off_score_px = (type(user_config.hud_n_offset_score) == "number" and user_config.hud_n_offset_score or 0.0) * sw
        local off_total_px = (type(user_config.hud_n_offset_total) == "number" and user_config.hud_n_offset_total or 0.0) * sw
        local off_timer_px = (type(user_config.hud_n_offset_timer) == "number" and user_config.hud_n_offset_timer or 0.0) * sw
        local off_status_px = (type(user_config.hud_n_offset_status_y) == "number" and user_config.hud_n_offset_status_y or 0.0) * sh

        if session.is_running and session.is_paused then
            local msg_pause = TEXTS.pause_overlay
            local w_mp = imgui.calc_text_size(msg_pause).x; draw_text_overlay(msg_pause, center_x - w_mp/2, top_y, COLORS.Yellow)
        else
            -- 1. TIMER
            if user_config.session_mode == 1 then
                local time_show = session.is_running and session.time_rem or (user_config.timer_minutes * 60)
                local t_txt = format_duration(time_show)
                if custom_font.obj then imgui.pop_font() end
                if custom_font_timer.obj then imgui.push_font(custom_font_timer.obj) end
                local w_t = imgui.calc_text_size(t_txt).x
                local t_col = COLORS.White
                if session.time_rem < 10 and session.is_running then t_col = COLORS.Red end
                local t_hud_y = (type(user_config.timer_hud_y) == "number" and user_config.timer_hud_y or -0.45)
                local t_off_x = (type(user_config.timer_offset_x) == "number" and user_config.timer_offset_x or 0.0)
                local timer_y_final = center_y + (t_hud_y * sh)
                local timer_x_final = center_x - (w_t / 2) + (t_off_x * sw)
                draw_timer_outline(t_txt, timer_x_final, timer_y_final, t_col)
                if custom_font_timer.obj then imgui.pop_font() end
                if custom_font.obj then imgui.push_font(custom_font.obj) end
            end

            -- 2. SCORE & TOTAL
            local s_txt = TEXTS.score_label .. session.score; local tot_txt = TEXTS.total_label .. session.total
            local t_mode = (user_config.session_mode == 1) and TEXTS.timer_label or TEXTS.infinite_label
            local w_s = imgui.calc_text_size(s_txt).x
            local x_s = center_x - spread_score_px - w_s + off_score_px
            draw_text_overlay(s_txt, x_s, top_y, session.score_col)
            local w_m = imgui.calc_text_size(t_mode).x
            local x_m = center_x - (w_m / 2) + off_timer_px
            draw_text_overlay(t_mode, x_m, top_y, COLORS.White)
            local x_tot = center_x + spread_score_px + off_total_px
            draw_text_overlay(tot_txt, x_tot, top_y, COLORS.White)

            local line_2_y = top_y + spacing_y_px + off_status_px
            local line_3_y = line_2_y + spacing_y_px

            -- 3. SLOT STATS (FIX HUD)
            if user_config.show_slot_stats then
                local slots_str = ""
                local has_visible_slots = false
                
                for i=1,8 do
                    local status = real_slot_status[i]
                    if (status.is_valid and status.is_active) or session.slot_stats[i].attempts > 0 then
                        local s = session.slot_stats[i]
                        local pct = 0
                        if s.attempts > 0 then pct = (s.success / s.attempts) * 100 end
                        
                        slots_str = slots_str .. string.format("S%d:%.0f%%  ", i, pct)
                        has_visible_slots = true
                    end
                end
                
                if not has_visible_slots then
                    slots_str = "WAITING FOR ACTIVE SLOTS..."
                end

                local w_sl = imgui.calc_text_size(slots_str).x
                draw_text_overlay(slots_str, center_x - w_sl/2, line_2_y, COLORS.White)
            end

            -- 4. STATUS MESSAGE
            local msg = session.feedback.text
            local w_msg = imgui.calc_text_size(msg).x
            draw_text_overlay(msg, center_x - w_msg/2, line_3_y, session.feedback.color)
        end
        
        if custom_font.obj then imgui.pop_font() end
        imgui.end_window()
    end
    imgui.pop_style_var(2); imgui.pop_style_color(1)
end)

-- =========================================================
-- MENU UI
-- =========================================================

re.on_draw_ui(function()
    if _G.CurrentTrainerMode ~= 1 then return end

    if imgui.tree_node("Reaction Trainer Remastered (V5.0 - Logic)") then
        
        if styled_header("--- HELP & INFO ---", UI_THEME.hdr_info) then
            imgui.text("SHORTCUTS (Hold SELECT or R3):")
            imgui.text("- + UP : Switch Mode (Timed/Infinite)"); imgui.text("- + LEFT : Start / Stop / Export")
            imgui.text("- + RIGHT : Pause / Resume"); imgui.text("- + DOWN : Toggle Debug Panel")
        end

        if styled_header("--- SESSION CONFIGURATION ---", UI_THEME.hdr_session) then
            imgui.text("MODE:"); imgui.same_line()
            local btn_timed_style = (user_config.session_mode == 1) and UI_THEME.btn_green or UI_THEME.btn_neutral
            if styled_button("TIMED", btn_timed_style) then 
                user_config.session_mode = 1; user_config.timer_mode_enabled = true; reset_session_stats(); save_conf() 
            end
            imgui.same_line()
            local btn_inf_style = (user_config.session_mode == 2) and UI_THEME.btn_green or UI_THEME.btn_neutral
            if styled_button("INFINITE", btn_inf_style) then 
                user_config.session_mode = 2; user_config.timer_mode_enabled = false; reset_session_stats(); session.is_running = true; session.is_paused = false; save_conf() 
            end
            
            imgui.separator()
            if user_config.session_mode == 1 then
                imgui.text("DURATION:"); imgui.same_line(); 
                if styled_button("-", UI_THEME.btn_neutral) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
                imgui.same_line(); imgui.text(tostring(user_config.timer_minutes) .. " min"); imgui.same_line(); 
                if styled_button("+", UI_THEME.btn_neutral) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
                
                imgui.same_line(250)
                if styled_button("RESET", UI_THEME.btn_red) then reset_session_stats(); set_feedback(TEXTS.reset_done, COLORS.White, 1.0) end
                
                imgui.spacing()
                if not session.is_running then
                    if styled_button("START SESSION", UI_THEME.btn_green) then 
                        session.is_running = true; session.is_paused = false; reset_session_stats(); 
                        session.time_rem = user_config.timer_minutes * 60; session.is_running = true; set_feedback(TEXTS.started, COLORS.Green, 1.0) 
                    end
                else
                    if styled_button("STOP & EXPORT", UI_THEME.btn_red) then export_log_excel(); reset_session_stats(); set_feedback(TEXTS.stopped_export, COLORS.Red, 1.0) end
                    imgui.same_line(); 
                    if styled_button(session.is_paused and "RESUME" or "PAUSE", UI_THEME.btn_neutral) then session.is_paused = not session.is_paused end
                end
            else
                if styled_button("RESET SCORES", UI_THEME.btn_red) then reset_session_stats(); session.is_running = true end
                imgui.same_line();
                if styled_button("EXPORT LOG", UI_THEME.btn_green) then export_log_excel(); set_feedback(TEXTS.stats_exported, COLORS.Green, 1.0) end
            end
        end

		if styled_header("--- SLOTS & MATCHUPS ---", UI_THEME.hdr_slots) then
            imgui.text_colored("AUTOMATIC TRACKING ACTIVE", COLORS.Green)
            imgui.text("No manual configuration needed.")
            imgui.text("Slot stats are updated automatically based on active slot.")
            
            local c_st, v_st = imgui.checkbox("Show Slot Percentages on HUD", user_config.show_slot_stats); if c_st then user_config.show_slot_stats = v_st; save_conf() end
        end
        
        if styled_header("--- UI LAYOUT ADJUSTMENTS ---", UI_THEME.hdr_layout) then
            local chg = false; local v
            local c_main, v_main = input_int_keyboard("Main Text Size", user_config.hud_base_size)
            if c_main then user_config.hud_base_size = v_main; save_conf(); try_load_font() end
            local c_time, v_time = input_int_keyboard("Timer Font Size", user_config.timer_font_size)
            if c_time then user_config.timer_font_size = v_time; save_conf(); try_load_font() end

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
            imgui.text("P2 ID: " .. game_state.p2_id)
            imgui.text("Flag End: " .. tostring(session.p2_is_end_flag))
        end
        
        imgui.tree_pop()
    end

    if user_config.show_debug_panel then
        imgui.begin_window("Debug Overlay", true, 0)
        imgui.text("Auto Logic Active")
        imgui.text("Tracking: " .. tostring(session.is_tracking))
        imgui.end_window()
    end
end)