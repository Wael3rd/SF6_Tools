local re = re
local sdk = sdk
local imgui = imgui
local draw = draw
local json = json

-- hitconfirm_v3.1
-- Update: Complete UI Design Overhaul.
-- Feature: Custom styling functions for Buttons and Collapsing Headers with Hover/Active states.
-- Feature: 4 distinct elegant color themes for the main headers.
-- Feature: Texts centralized, Timer pauses on Success, Comments translated.

-- =========================================================
-- 0. GLOBAL TEXT VARIABLES (LOCALIZATION)
-- =========================================================
-- All text displayed on screen is defined here for easy editing
local TEXTS = {
    -- HUD Labels
    ready           = "READY",
    waiting         = "WAITING",
    paused          = "PAUSED",
    resumed         = "RESUMED",
    time_up         = "TIME UP!",
    score_label     = "SCORE: ",
    total_label     = "TOTAL: ",
    timer_label     = "TIMER",
    infinite_label  = "INFINITE",
    hit_pct_label   = "HIT: ",
    blk_pct_label   = "BLOCK: ",
    
    -- Status / Feedback Messages
    hit_detected    = "HIT DETECTED!",
    blk_detected    = "BLOCK DETECTED...",
    resetting       = "RESETTING...",
    
    -- Success / Fail States
    success_hit     = "SUCCESS: HIT CONFIRM",
    success_safe    = "SUCCESS: SAFE",
    safe_generic    = "SAFE",
    success_block   = "BLOCK SUCCESS",
    
    fail_drop       = "FAIL: DROP",
    fail_unsafe     = "FAIL: UNSAFE CANCEL",
    fail_autopilot  = "FAIL: AUTOPILOT", -- Hit too soon on block
    fail_hit        = "HIT FAIL",
    fail_blk_fast   = "BLOCK FAIL (CANCEL TOO FAST)",
    fail_blk_soon   = "BLOCK FAIL (2ND HIT TOO SOON)",
    
    -- Notifications
    mode_infinite   = "MODE: INFINITE",
    mode_timed      = "MODE: TIMED",
    started         = "STARTED!",
    stopped_export  = "STOPPED & EXPORTED",
    stats_exported  = "STATS EXPORTED",
    reset_done      = "RESET DONE",
    
    -- Pause Overlay
    pause_overlay   = "PAUSED : PRESS (SELECT OR R3) + RIGHT TO RESUME",
    
    -- Errors
    err_session_file = "Err: Session File",
    err_history_file = "Err: History File"
}

-- =========================================================
-- 0.1 MANAGER DEPENDENCY
-- =========================================================
local DEPENDANT_ON_MANAGER = true 

-- BUTTON MASKS
local BTN_SELECT = 16384
local BTN_R3     = 8192
local BTN_UP     = 1
local BTN_DOWN   = 2
local BTN_LEFT   = 4
local BTN_RIGHT  = 8

-- =========================================================
-- 1. CONFIGURATION & STYLING
-- =========================================================
local CONFIG_FILENAME = "TrainingHitConfirm_Config.json"

local COLORS = {
    White  = 0xFFDADADA, Green  = 0xFF00FF00, Red    = 0xFF0000FF,
    Grey   = 0x99FFFFFF, DarkGrey = 0xFF888888, Orange = 0xFF00A5FF, 
    Cyan   = 0xFFFFFF00, Yellow = 0xFF00FFFF, 
    Shadow = 0xFF000000,
    Blue   = 0xFFFFAA00 
}

COLORS.Easy   = 0xFFFF9933 
COLORS.Medium = 0xFF00FFFF 
COLORS.Hard   = 0xFF0000FF

-- UI THEME DEFINITIONS (Format: 0xAABBGGRR)
local UI_THEME = {
    -- HEADERS (4 Elegant Web Colors)
    -- Info: Soft Steel Blue
    hdr_info = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    -- Session: Violet Wisteria
    hdr_session = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    -- Rules: Soft Red
    hdr_rules =   { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
    -- Matrix: Sea Green
    hdr_matrix =  { base = 0xFF9CBC1A, hover = 0xFFAED12B, active = 0xFF8AA814 },
    
    -- BUTTONS (Variations of original colors)
    btn_neutral = { base = 0xFF444444, hover = 0xFF666666, active = 0xFF222222 }, -- Standard Grey
    btn_green   = { base = 0xFF00AA00, hover = 0xFF00CC22, active = 0xFF007700 }, -- Active/Start
    btn_red     = { base = 0xFF0000CC, hover = 0xFF2222FF, active = 0xFF000099 }, -- Stop/Hard
 
	btn_easy    = { base = 0xFFFF8800, hover = 0xFFFFAA33, active = 0xFFCC6600 }, 
    btn_medium  = { base = 0xFF00FFFF, hover = 0xFF66FFFF, active = 0xFF00CCCC }, 
    btn_hard    = { base = 0xFF0000FF, hover = 0xFF4444FF, active = 0xFF0000AA } 
}

local IMGUI_FLAGS = {
    NoTitleBar = 1, NoResize = 2, NoMove = 4, NoScrollbar = 8, 
    NoMouseInputs = 512, NoNav = 786432, NoBackground = 128,
    WindowBorderSize = 4, WindowPadding = 2, WindowBg = 2
}

local custom_font = {
    obj = nil, filename = "capcom_goji-udkakugoc80pro-db.ttf", loaded_size = 0, status = "Init..."
}

local custom_font_timer = { obj = nil, filename = "SF6_college.ttf", loaded_size = 0, status = "Init..." }

local res_watcher = { last_w = 0, last_h = 0, cooldown = 0 }
local last_trainer_mode = 0

local user_config = {
    session_mode = 0, 
    timer_minutes = 3,
    timer_mode_enabled = false, 
    show_timer_hud = true,
    show_matrix_debug = false, 
    show_hit_pct = true,
    show_block_pct = true,
    difficulty = 2, 
    dont_count_blocked = false,
    show_early_detection = true,
    show_status_line = true,
    hud_base_size = 20.24,
    hud_auto_scale = true,
    hud_n_global_y = -0.35,
    hud_n_spacing_y = 0.05,
    hud_n_spread_score = 0.15,
    hud_n_spread_stats = 0.15,
    hud_n_offset_score = 0.0,
    hud_n_offset_total = 0.0,
    hud_n_offset_timer = 0.0,
    hud_n_offset_hit   = 0.0,
    hud_n_offset_blk   = 0.0,
    hud_n_offset_status_y = 0.0,
	-- INDEPENDENT TIMER CONFIGURATION
    -- Y Position: -0.45 is usually top center (replacing Ticker)
    timer_hud_y = -0.45,      
    -- Font size for Timer only
    timer_font_size = 60,     
    -- Horizontal offset if needed
    timer_offset_x = 0.0,
    str_trigger_list = "13", str_success_list = "13", str_break_list = "7",
    str_dmg_hit_list = "3", str_dmg_block_list = "30",
    hit_p2_gauge = 1, success_p1_gauge = 1, persistence_text = 80, persistence_val = 80,
    show_index = true,
    p1 = { frame_type = true, status_type = true, frame_number = false, start_frame = false, end_frame = false, main_gauge = false },
    p2 = { frame_type = true, status_type = true, frame_number = false, start_frame = false, end_frame = false, main_gauge = false },
    show_damage = true, show_hitstop = true, show_status_label = true
}

local work_tables = { trigger = {}, success = {}, dmg_hit = {}, dmg_block = {}, break_list = {} }

local session = {
    is_running = false, is_paused = false, 
    start_ts = os.time(), real_start_time = os.time(),time_rem = 0, last_clock = 0,
    score = 0, total = 0, hit_ok = 0, hit_tot = 0, blk_ok = 0, blk_tot = 0,
    last_score = 0, score_col = COLORS.White, score_timer = 0,
    status_msg = TEXTS.ready, export_msg = "",
    is_logging = false, history_list = {}, history_map = {},
    feedback = { text = TEXTS.waiting, timer = 0, color = COLORS.White },
    last_result_was_success = false -- New flag to pause timer during furies
}

local detection = {
    p1_list = nil, p2_list = nil,
    active_lines = {}, last_head_index = 0, abs_clock = 0, buffer_capacity = 0, 
    live_dmg = 0, live_hs = 0, live_combo = 0,
    mem_hit = {}, mem_blk = {}, mem_res = {}, mem_dmg = {}, mem_hs = {},
    monitor = { active = false, type = nil, has_reset_hs = false, start_combo = 0 },
    lockout = false
}

-- =========================================================
-- 2. TOOLS & HELPERS
-- =========================================================

-- HELPER: Easy Tooltip
local function tooltip(text)
    if imgui.is_item_hovered() then
        imgui.set_tooltip(text)
    end
end

-- HELPER: Styled Button (Auto Push/Pop colors)
local function styled_button(label, style, text_col)
    imgui.push_style_color(21, style.base)   -- Button
    imgui.push_style_color(22, style.hover)  -- ButtonHovered
    imgui.push_style_color(23, style.active) -- ButtonActive
    if text_col then imgui.push_style_color(0, text_col) end -- Text Color
    
    local clicked = imgui.button(label)
    
    if text_col then imgui.pop_style_color(1) end
    imgui.pop_style_color(3)
    return clicked
end

-- HELPER: Styled Collapsing Header
local function styled_header(label, style)
    imgui.push_style_color(24, style.base)   -- Header
    imgui.push_style_color(25, style.hover)  -- HeaderHovered
    imgui.push_style_color(26, style.active) -- HeaderActive
    
    local is_open = imgui.collapsing_header(label)
    
    imgui.pop_style_color(3)
    return is_open
end

local function get_dynamic_screen_size()
    local w, h = 1920, 1080 
    if imgui.get_display_size then
        local result = imgui.get_display_size()
        if type(result) == "userdata" then
            local ok, x = pcall(function() return result.x end); local ok2, y = pcall(function() return result.y end)
            if ok and ok2 then w, h = x, y else w = result.w or w; h = result.h or h end
        elseif type(result) == "number" then
            local w_val, h_val = imgui.get_display_size(); w, h = w_val, h_val
        end
    end
    if w <= 0 then w = 1920 end; if h <= 0 then h = 1080 end
    return w, h
end

local function try_load_font()
    if not imgui.load_font then custom_font.status = "Error: API Missing"; return end
    
    local sw, sh = get_dynamic_screen_size()
    local scale_factor = sh / 1080.0
    if scale_factor < 0.1 then scale_factor = 1.0 end

    -- 1. Main Font (Classic HUD)
    local target_size = math.floor(user_config.hud_base_size * (user_config.hud_auto_scale and scale_factor or 1.0))
    local font = imgui.load_font(custom_font.filename, target_size)
    if font then custom_font.obj = font; custom_font.loaded_size = target_size; custom_font.status = "OK" end

    -- 2. Timer Font (Specific Size)
    local target_size_timer = math.floor(user_config.timer_font_size * (user_config.hud_auto_scale and scale_factor or 1.0))
    local font_t = imgui.load_font(custom_font_timer.filename, target_size_timer)
    if font_t then custom_font_timer.obj = font_t; custom_font_timer.loaded_size = target_size_timer end
end

local function handle_resolution_change()
    local sw, sh = get_dynamic_screen_size()
    if res_watcher.last_w == 0 then res_watcher.last_w = sw; res_watcher.last_h = sh; try_load_font(); return end
    if sw ~= res_watcher.last_w or sh ~= res_watcher.last_h then res_watcher.cooldown = 30; res_watcher.last_w = sw; res_watcher.last_h = sh; custom_font.status = "Resize detected..." end
    if res_watcher.cooldown > 0 then res_watcher.cooldown = res_watcher.cooldown - 1; if res_watcher.cooldown == 0 then try_load_font() end end
end

local function parse_list(str)
    local t = {}
    if not str then return t end
    for s in string.gmatch(str, "([^,]+)") do local n = tonumber(s); if n then table.insert(t, n) end end
    return t
end

local function refresh_tables()
    work_tables.trigger = parse_list(user_config.str_trigger_list)
    work_tables.success = parse_list(user_config.str_success_list)
    work_tables.dmg_hit = parse_list(user_config.str_dmg_hit_list)
    work_tables.dmg_block = parse_list(user_config.str_dmg_block_list)
    work_tables.break_list = parse_list(user_config.str_break_list)
end

local function is_in(tbl, val)
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

local function format_time(s)
    if not s or s < 0 then s = 0 end
    return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60))
end

local function load_conf()
    local data = json.load_file(CONFIG_FILENAME)
    if data then
        if data.user then 
            for k,v in pairs(data.user) do 
                if k == "p1" or k == "p2" then for subk, subv in pairs(v) do user_config[k][subk] = subv end
                else user_config[k] = v end
            end 
        end
    end
    if user_config.difficulty == nil then user_config.difficulty = 2 end
    if user_config.session_mode == nil then user_config.session_mode = 0 end
    user_config.timer_mode_enabled = (user_config.session_mode == 1)
    refresh_tables()
end

local function save_conf() json.dump_file(CONFIG_FILENAME, { user = user_config }) end
load_conf(); try_load_font()

-- =========================================================
-- LOGIC & EXPORTS
-- =========================================================

local function set_feedback(msg, color, duration)
    session.feedback.text = msg; session.feedback.color = color
    if duration and duration > 0 then session.feedback.timer = duration else session.feedback.timer = 0 end
end

local function reset_session_stats()
    session.score = 0; session.total = 0; session.hit_ok = 0; session.hit_tot = 0; session.blk_ok = 0; session.blk_tot = 0
    session.is_running = false; session.is_paused = false
	session.real_start_time = os.time()
    session.last_result_was_success = false -- Reset success state
    if user_config.timer_mode_enabled then session.time_rem = user_config.timer_minutes * 60 else session.time_rem = 0 end
end


local function export_session_stats()
    local filename = "HitConfirm_SessionStats.txt"
    local f = io.open(filename, "a+") 
    if not f then session.export_msg = TEXTS.err_session_file; return end

    -- 1. Base data calculations
    local now = os.time()
    local date_str = os.date("%Y-%m-%d")
    local time_str = os.date("%H:%M")
    
    -- Duration
    local duration = os.difftime(now, session.real_start_time)
    local duration_str = string.format("%02d:%02d", math.floor(duration/60), duration%60)

    -- Mode and Difficulty
    local mode_str = (user_config.session_mode == 1) and "TIMED" or "INFINITE"
    local diff_str = "MEDIUM"
    if user_config.difficulty == 1 then diff_str = "EASY"
    elseif user_config.difficulty == 3 then diff_str = "HARD" end

    -- 2. CORRECTED CALCULATIONS (Mathematical Total)
    -- We no longer use 'session.total' which might be skewed by difficulty options
    local real_total_attempts = session.hit_tot + session.blk_tot
    local total_success = session.hit_ok + session.blk_ok
    
    -- Percentages
    local h_pct = 0; if session.hit_tot > 0 then h_pct = (session.hit_ok/session.hit_tot)*100 end
    local b_pct = 0; if session.blk_tot > 0 then b_pct = (session.blk_ok/session.blk_tot)*100 end
    local total_pct = 0; if real_total_attempts > 0 then total_pct = (total_success / real_total_attempts) * 100 end

    -- 3. Line Creation
    -- Order: 
    -- DATE | TIME | MODE | DURATION | DIFF | REAL_TOTAL | TOT_SUCC | TOT_% | SCORE | HIT_TOT | HIT_OK | HIT_% | BLK_TOT | BLK_OK | BLK_%
    local line = string.format(
        "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%.2f%%\t%d\t%d\t%d\t%.2f%%\t%d\t%d\t%.2f%%\n",
        date_str, time_str, mode_str, duration_str, diff_str,
        real_total_attempts,  -- HERE: Using real calculated total
        total_success, 
        total_pct,            -- New GLOBAL % column
        session.score,        -- New SCORE column
        session.hit_tot, session.hit_ok, h_pct,
        session.blk_tot, session.blk_ok, b_pct
    )

    f:write(line)
    f:close()
    session.export_msg = "Stats Appended!"
end

local function export_detailed_history()
    local filename = "_FULL_HISTORY_EXPORT.txt"; local f = io.open(filename, "w+")
    if not f then session.export_msg = TEXTS.err_history_file; return end
    f:write("DETAILED MATRIX LOG [" .. os.date("%H:%M:%S") .. "]\n CLOCK  | P1_FT | P1_ST | P1_FR | P2_FT | DMG  | HS   | CMBO | STATUS\n")
    for _, line in ipairs(session.history_list) do
        local r = string.format(" %-6d |  %3s  |  %3s  |  %3s  |  %3s  | %-4s | %-4s | %-4s | ", line.clock, line.p1.ft, line.p1.st, line.p1.fn, line.p2.ft, line.dmg, line.hs, line.cmb)
        local st = ""; if line.status ~= "" then st = "<<< " .. line.status elseif line.tag == "HIT" then st = "<<< HIT LANDED" elseif line.tag == "BLOCK" then st = "<<< BLOCK LANDED" end
        f:write(r .. st .. "\n")
    end
    f:close(); session.export_msg = "Matrix Exported!"
end

local function update_history_status(clock_time, status_txt)
    local entry = session.history_map[clock_time]; if entry then entry.status = status_txt end
end

local function update_detection()
    if session.is_paused then return end
    if detection.mem_hit == nil then detection.mem_hit = {} end
    if detection.mem_blk == nil then detection.mem_blk = {} end
    if detection.mem_res == nil then detection.mem_res = {} end
    if detection.mem_dmg == nil then detection.mem_dmg = {} end
    if detection.mem_hs  == nil then detection.mem_hs  = {} end
    detection.active_lines = {}; detection.live_dmg = 0; detection.live_hs = 0; detection.live_combo = 0
    
    local gBattle = sdk.find_type_definition("gBattle")
    if gBattle then
        local p2_obj = gBattle:get_field("Player"):get_data(nil):call("getPlayer", 1)
        if p2_obj then 
            local dt = p2_obj:get_field("damage_type"); if dt then detection.live_dmg = tonumber(tostring(dt)) or 0 end
            local hs = p2_obj:get_field("hit_stop"); if hs then detection.live_hs = tonumber(tostring(hs)) or 0 end
        end
        local p1_obj = gBattle:get_field("Player"):get_data(nil):call("getPlayer", 0)
        if p1_obj then
            local cc = p1_obj:get_field("combo_cnt"); if cc then detection.live_combo = tonumber(tostring(cc)) or 0 end
        end
    end

    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return end
    local dict = mgr:get_field("_ViewUIWigetDict"); local entries = dict and dict:get_field("_entries")
    if not entries then return end

    local count = entries:call("get_Count")
    for i = 0, count - 1 do
        local entry = entries:call("get_Item", i)
        if entry:get_field("key") == 5 then 
            local widget = entry:get_field("value"):call("get_Item", 0)
            local ss = widget:call("get_SSData"); local m_datas = ss:get_field("MeterDatas")
            if m_datas and m_datas:call("get_Count") >= 2 then
                local item_p1 = m_datas:call("get_Item", 0); local item_p2 = m_datas:call("get_Item", 1)
                if item_p1 then detection.p1_list = item_p1:get_field("FrameNumDatas") end
                if item_p2 then detection.p2_list = item_p2:get_field("FrameNumDatas") end
            end
            break
        end
    end

    if detection.p1_list and detection.p2_list then
        local buffer_count = detection.p1_list:call("get_Count")
        if buffer_count <= 0 then return end
        detection.buffer_capacity = buffer_count 
        
        local active_head_index = -1; local next_idx = (detection.last_head_index + 1) % buffer_count
        
        local function check_active(idx)
            if idx < 0 or idx >= buffer_count then return false end
            local item1 = detection.p1_list:call("get_Item", idx); local item2 = detection.p2_list:call("get_Item", idx)
            if not item1 or not item2 then return false end
            local ft1 = tonumber(tostring(item1:get_field("FrameType"))) or 0; local ft2 = tonumber(tostring(item2:get_field("FrameType"))) or 0
            return (ft1 ~= 0 or ft2 ~= 0)
        end

        local is_new_frame = false
        if check_active(next_idx) then active_head_index = next_idx; detection.abs_clock = detection.abs_clock + 1; is_new_frame = true
        elseif check_active(detection.last_head_index) then active_head_index = detection.last_head_index
        else detection.mem_hit = {}; detection.mem_blk = {}; detection.mem_res = {}; detection.mem_dmg = {}; detection.mem_hs = {}; detection.monitor.active = false; detection.abs_clock = 0; for i = buffer_count - 1, 0, -1 do if check_active(i) then active_head_index = i; break end end end
        detection.last_head_index = active_head_index

        if active_head_index ~= -1 and detection.p1_list then
            local it1 = detection.p1_list:call("get_Item", active_head_index); local it2 = detection.p2_list:call("get_Item", active_head_index)
            if it1 and it2 then
                local function get_all(item)
                    return { ft = tonumber(tostring(item:get_field("FrameType"))) or 0, st = tonumber(tostring(item:get_field("Type"))) or 0, fn = tonumber(tostring(item:get_field("Frame"))) or 0, sf = tonumber(tostring(item:get_field("StartFrame"))) or 0, ef = tonumber(tostring(item:get_field("EndFrame"))) or 0, mg = tonumber(tostring(item:get_field("MainGauge"))) or 0 }
                end
                local p1_data = get_all(it1); local p2_data = get_all(it2)
                
                if is_new_frame and session.is_logging then
                    local entry = { clock = detection.abs_clock, p1 = p1_data, p2 = p2_data, dmg = detection.live_dmg, hs = detection.live_hs, cmb = detection.live_combo, status = "", tag = nil }
                    table.insert(session.history_list, entry); session.history_map[detection.abs_clock] = entry
                end

                if detection.live_dmg > 0 then detection.mem_dmg[active_head_index] = { val = detection.live_dmg, time = detection.abs_clock } end
                if detection.live_hs > 0 then detection.mem_hs[active_head_index] = { val = detection.live_hs, time = detection.abs_clock } end

                if detection.lockout then
                    if session.feedback.timer <= 0 then set_feedback(TEXTS.resetting, COLORS.DarkGrey, 0.1) end
                    if not is_in(work_tables.trigger, p1_data.ft) and not is_in(work_tables.break_list, p1_data.ft) then
                        detection.lockout = false; session.last_result_was_success = false -- Lockout released, timer can resume normally
                        if session.feedback.timer <= 0 then set_feedback(TEXTS.waiting, COLORS.Grey, 0) end
                    end
                end

                local is_ft_trig = is_in(work_tables.trigger, p1_data.ft)
                local is_dmg_allowed = is_in(work_tables.dmg_hit, detection.live_dmg)
                local trig_hit = (is_ft_trig and detection.live_combo == 1 and is_dmg_allowed)
                local is_dmg_blk = is_in(work_tables.dmg_block, detection.live_dmg)
                local trig_blk = (is_ft_trig and p2_data.mg > 0 and is_dmg_blk)
                
                if trig_hit and not detection.lockout then
                    detection.mem_hit[active_head_index] = detection.abs_clock
                    if session.history_map[detection.abs_clock] then session.history_map[detection.abs_clock].tag = "HIT" end
                    if not detection.monitor.active or detection.monitor.type ~= "HIT" then
                        detection.monitor.active = true; detection.monitor.type = "HIT"; detection.monitor.has_reset_hs = false
                        detection.mem_res[active_head_index] = { status = "HIT LANDED", time = detection.abs_clock }
                        update_history_status(detection.abs_clock, "HIT LANDED")
                        if user_config.show_early_detection then set_feedback(TEXTS.hit_detected, COLORS.Yellow, 2.0) end
                    end
                elseif trig_blk and not detection.lockout then
                    detection.mem_blk[active_head_index] = detection.abs_clock
                    if session.history_map[detection.abs_clock] then session.history_map[detection.abs_clock].tag = "BLOCK" end
                    if not detection.monitor.active or detection.monitor.type ~= "BLOCK" then
                        detection.monitor.active = true; detection.monitor.type = "BLOCK"; detection.monitor.has_reset_hs = false
                        detection.mem_res[active_head_index] = { status = "BLOCK LANDED", time = detection.abs_clock }
                        update_history_status(detection.abs_clock, "BLOCK LANDED")
                        if user_config.show_early_detection then set_feedback(TEXTS.blk_detected, COLORS.Cyan, 2.0) end
                    end
                end
                
                if detection.monitor.active then
                    if detection.live_hs == 0 then detection.monitor.has_reset_hs = true end
                    if detection.monitor.has_reset_hs then
                        if detection.monitor.type == "HIT" then
                            if detection.live_combo >= 2 then
                                detection.mem_res[active_head_index] = { status = TEXTS.success_hit, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.success_hit)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = true -- Mark success to freeze timer
                                session.score = session.score + 1; session.hit_ok = session.hit_ok + 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.success_hit, COLORS.Green, 1.5)
                            elseif detection.live_combo == 0 then
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_hit, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.fail_hit)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                session.score = session.score - 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.fail_drop, COLORS.Red, 1.5)
                            end
                        end
                        if detection.monitor.type == "BLOCK" then
                            if is_in(work_tables.break_list, p1_data.ft) then
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_blk_fast, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.fail_blk_fast)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.fail_unsafe, COLORS.Red, 1.5)
                            elseif is_in(work_tables.success, p1_data.ft) and not is_in(work_tables.trigger, p1_data.ft) and detection.live_hs > 0 then
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_blk_soon, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.fail_blk_soon)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.fail_autopilot, COLORS.Red, 1.5)
                            elseif not is_in(work_tables.dmg_block, detection.live_dmg) then
                                detection.mem_res[active_head_index] = { status = TEXTS.success_block, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.success_block)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false -- Block success usually doesn't involve long animations like Furies
                                session.blk_ok = session.blk_ok + 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1;
                                if not user_config.dont_count_blocked then session.score = session.score + 1; set_feedback(TEXTS.success_safe, COLORS.Green, 1.5)
                                else set_feedback(TEXTS.safe_generic, COLORS.White, 1.5) end
                            end
                        end
                    end
                end
            end
        end
    end

    if user_config.show_matrix_debug and detection.p1_list and detection.p2_list then
        local cnt1 = detection.p1_list:call("get_Count"); local cnt2 = detection.p2_list:call("get_Count")
        local max_cnt = math.max(cnt1, cnt2); local limit = 0
        for idx = 0, max_cnt - 1 do
            local function get_hd(list, index)
                local item = list:call("get_Item", index)
                if not item then return {frame_type=0, status_type=0, frame_number=0, start_frame=0, end_frame=0, main_gauge=0} end
                return { 
                    frame_type=tonumber(tostring(item:get_field("FrameType"))) or 0, 
                    status_type=tonumber(tostring(item:get_field("Type"))) or 0, 
                    frame_number=tonumber(tostring(item:get_field("Frame"))) or 0, 
                    start_frame=tonumber(tostring(item:get_field("StartFrame"))) or 0, 
                    end_frame=tonumber(tostring(item:get_field("EndFrame"))) or 0, 
                    main_gauge=tonumber(tostring(item:get_field("MainGauge"))) or 0 
                }
            end
            local d1 = {frame_type=0}; local d2 = {frame_type=0}
            if idx < cnt1 then d1 = get_hd(detection.p1_list, idx) end
            if idx < cnt2 then d2 = get_hd(detection.p2_list, idx) end
            if (d1.frame_type and d1.frame_type ~= 0) or (d2.frame_type and d2.frame_type ~= 0) then
                local function chk(store, dur)
                    if not store then return false, 0 end
                    local t = (type(store)=="table") and store.time or store
                    local c = (type(store)=="table") and (store.val or store.status) or true
                    if t == -1 then return false, 0 end
                    local a = detection.abs_clock - t
                    if a >= 0 and a < dur then return true, c end
                    return false, 0
                end
                local is_h = chk(detection.mem_hit[idx], user_config.persistence_text)
                local is_b = chk(detection.mem_blk[idx], user_config.persistence_text)
                local has_r, r_txt = chk(detection.mem_res[idx], user_config.persistence_text)
                local _, val_d = chk(detection.mem_dmg[idx], user_config.persistence_val)
                local _, val_h = chk(detection.mem_hs[idx], user_config.persistence_val)
                table.insert(detection.active_lines, { idx = idx, p1=d1, p2=d2, is_h=is_h, is_b=is_b, res=r_txt, d=val_d, h=val_h })
                limit = limit + 1; if limit > 150 then break end
            end
        end
    end
end

-- =========================================================
-- UPDATE LOGIC
-- =========================================================
local function update_logic()
    local is_game_active = true
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local field = pm:get_type_definition():get_field("_CurrentPauseBit")
        if field then
            local val = field:get_data(pm)
            if val and tostring(val) ~= "131072" then is_game_active = false end
        end
    end
    
    if session.score ~= session.last_score then session.score_col = (session.score > session.last_score) and COLORS.Green or COLORS.Red; session.score_timer = 30; session.last_score = session.score end
    if session.score_timer > 0 then session.score_timer = session.score_timer - 1; if session.score_timer <= 0 then session.score_col = COLORS.White end end
    
    local now = os.clock(); local dt = now - session.last_clock; session.last_clock = now
    
    if session.feedback.timer > 0 then
        session.feedback.timer = session.feedback.timer - dt
        if session.feedback.timer <= 0 then if not detection.lockout then session.feedback.text = TEXTS.waiting; session.feedback.color = COLORS.Grey; session.feedback.timer = 0 end end
    end

    if session.is_running and is_game_active and user_config.timer_mode_enabled and not session.is_paused then
        
        -- PAUSE LOGIC DURING FURIES:
        -- If we are in "Lockout" state AND the last result was a HIT SUCCESS,
        -- we assume an animation (Fury/Super) is playing, so we skip decrementing the timer.
        local is_in_success_anim = detection.lockout and session.last_result_was_success
        
        if not is_in_success_anim then
            session.time_rem = session.time_rem - dt
        end
        
        if session.time_rem <= 0 then session.time_rem = 0; session.is_running = false; session.status_msg = TEXTS.time_up; 
		
		export_session_stats() -- ADDED THIS LINE HERE
		set_feedback(TEXTS.time_up, COLORS.Red, 0) end
    end
    
    if is_game_active then update_detection() end
end

-- =========================================================
-- INPUT HANDLING
-- =========================================================
local last_input_mask = 0

local function apply_difficulty(val)
    user_config.difficulty = val
    if val == 1 then user_config.show_early_detection = true; user_config.dont_count_blocked = false 
    elseif val == 2 then user_config.show_early_detection = true; user_config.dont_count_blocked = true 
    elseif val == 3 then user_config.show_early_detection = false; user_config.dont_count_blocked = true end
    reset_session_stats()
    local d_name = "MEDIUM"; local d_color = COLORS.Medium
    if val == 1 then d_name = "EASY" d_color = COLORS.Easy elseif val == 3 then d_name = "HARD" d_color = COLORS.Hard end
    set_feedback("DIFFICULTY: " .. d_name, d_color, 1.0)
    save_conf()
end

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

    local function is_func_combo_pressed(target_mask)
        local is_func_held = ((active_buttons & BTN_SELECT) == BTN_SELECT) or ((active_buttons & BTN_R3) == BTN_R3)
        if not is_func_held then return false end
        local is_target_now = (active_buttons & target_mask) == target_mask
        local was_target_before = (last_input_mask & target_mask) == target_mask
        return is_target_now and not was_target_before
    end

    if is_func_combo_pressed(BTN_UP) then
        user_config.session_mode = (user_config.session_mode == 1) and 2 or 1
        user_config.timer_mode_enabled = (user_config.session_mode == 1)
        reset_session_stats()
        
        -- Logic for color selection
        local msg = (user_config.session_mode == 2) and TEXTS.mode_infinite or TEXTS.mode_timed
        local col = (user_config.session_mode == 2) and COLORS.Cyan or COLORS.Orange
        
        set_feedback(msg, col, 1.0)
        save_conf()
    end

    if is_func_combo_pressed(BTN_DOWN) then
        local next_diff = (user_config.difficulty % 3) + 1
        apply_difficulty(next_diff)
    end

    if is_func_combo_pressed(BTN_LEFT) then
        if user_config.session_mode == 1 then
            if not session.is_running then
                session.is_running = true; session.is_paused = false; reset_session_stats(); session.time_rem = user_config.timer_minutes * 60; session.is_running = true; set_feedback(TEXTS.started, COLORS.Green, 1.0)
            else export_session_stats(); reset_session_stats(); set_feedback(TEXTS.stopped_export, COLORS.Red, 1.0) end
        elseif user_config.session_mode == 2 then
            export_session_stats(); set_feedback(TEXTS.stats_exported, COLORS.Green, 1.0)
        end
    end

    if is_func_combo_pressed(BTN_RIGHT) then
        if user_config.session_mode == 1 and session.is_running then
            session.is_paused = not session.is_paused
            set_feedback(session.is_paused and TEXTS.paused or TEXTS.resumed, COLORS.Yellow, 1.0)
        end
    end

    last_input_mask = active_buttons
end

local function update_logic_and_input()
    handle_input()
    update_logic()
end

local function draw_text_overlay(text, x, y, color)
    local safe_text = string.gsub(text, "%%", "%%%%")
    
    -- === VISUAL STYLE CONFIGURATION ===
    local outline_color = COLORS.Grey -- Black (0xFF000000)
    local outline_thick = 0.1             -- Outline thickness (2px simulates "bold/soft" look)
    local shadow_depth = 0              -- Drop shadow distance

    -- 1. DRAW DROP SHADOW
    -- Draw first, offset to bottom-right
    imgui.set_cursor_pos(Vector2f.new(x + shadow_depth, y + shadow_depth))
    imgui.text_colored(safe_text, outline_color)

    -- 2. DRAW OUTLINE (THICK STROKE)
    -- Loop around center to create thick black border
    for dx = -outline_thick, outline_thick do
        for dy = -outline_thick, outline_thick do
            -- Avoid exact center and optimize circle
            -- math.abs makes outline less "square"
            if (dx ~= 0 or dy ~= 0) and (math.abs(dx) + math.abs(dy) <= outline_thick) then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe_text, outline_color)
            end
        end
    end

    -- 3. DRAW MAIN TEXT
    imgui.set_cursor_pos(Vector2f.new(x, y))
    imgui.text_colored(safe_text, color)
    
    -- 4. "FAKE BOLD" TRICK
    -- Draw text again shifted by 1px to make font thicker
--    imgui.set_cursor_pos(Vector2f.new(x , y + 2))
--    imgui.text_colored(safe_text, color)
end

-- 2. Fonction SPÉCIALE pour le TIMER (Gros contour noir)
local function draw_timer_outline(text, x, y, color)
    local safe_text = string.gsub(text, "%%", "%%%%")
    local outline_color = 0xFF000000 -- Noir pur
    local thickness = 2 -- Epaisseur du contour

    -- On dessine le contour
    for dx = -thickness, thickness, thickness do
        for dy = -thickness, thickness, thickness do
            if dx ~= 0 or dy ~= 0 then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe_text, outline_color)
            end
        end
    end

    -- On dessine le texte par dessus
    imgui.set_cursor_pos(Vector2f.new(x, y))
    imgui.text_colored(safe_text, color)
end

-- Function to find and hide "Infinite Time" widget (UIWidget_TMTicker)
local function manage_ticker_visibility()
    -- Hide ONLY if in Timed Mode (1). 
    -- In Infinite Mode (2), let game show its native icon.
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
                        -- Target specific widget here
                        if type and string.find(type:get_name(), "UIWidget_TMTicker") then
                            widget:call("set_Visible", not should_hide)
                            return -- Optimization: found, stop
                        end
                    end
                end
            end
        end
    end
end

re.on_frame(function()
    if DEPENDANT_ON_MANAGER and (_G.CurrentTrainerMode ~= 2) then return end
    
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local field = pm:get_type_definition():get_field("_CurrentPauseBit")
        if field then
            local val = field:get_data(pm)
            if val and tostring(val) ~= "131072" then 
                if session.is_running and not session.is_paused then session.is_paused = true end
                return 
            end
        end
    end

    local cur_mode = _G.CurrentTrainerMode or 0
    if cur_mode == 2 and last_trainer_mode ~= 2 then reset_session_stats() end
    last_trainer_mode = cur_mode

    update_logic_and_input()
    handle_resolution_change()
    
    local sw, sh = get_dynamic_screen_size()
    
    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0) 
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    
    local win_flags = IMGUI_FLAGS.NoTitleBar | IMGUI_FLAGS.NoResize | IMGUI_FLAGS.NoMove | IMGUI_FLAGS.NoScrollbar | IMGUI_FLAGS.NoMouseInputs | IMGUI_FLAGS.NoNav | IMGUI_FLAGS.NoBackground

    if imgui.begin_window("HUD_Overlay", true, win_flags) then
        if custom_font.obj then imgui.push_font(custom_font.obj) end
        local center_x = sw / 2; local center_y = sh / 2; local top_y = center_y + (user_config.hud_n_global_y * sh)
        
        if session.is_running and session.is_paused then
            local msg_pause = TEXTS.pause_overlay
            local w_mp = imgui.calc_text_size(msg_pause).x; local x_mp = center_x - (w_mp / 2)
            draw_text_overlay(msg_pause, x_mp, top_y, COLORS.Yellow)
        else
            local spread_score_px = user_config.hud_n_spread_score * sw
            local spread_stats_px = user_config.hud_n_spread_stats * sw
            local spacing_y_px    = user_config.hud_n_spacing_y * sh
            local off_score_px = user_config.hud_n_offset_score * sw
            local off_total_px = user_config.hud_n_offset_total * sw
            local off_timer_px = user_config.hud_n_offset_timer * sw
            local off_hit_px   = user_config.hud_n_offset_hit * sw
            local off_blk_px   = user_config.hud_n_offset_blk * sw
            
			manage_ticker_visibility()
			
			-- [4] INDEPENDENT TIMER (Top, replaces Ticker)
            -- We display our timer ONLY in Timed Mode. 
            -- In Infinite Mode, we let the game Ticker (left visible by function above) show.
            if user_config.session_mode == 1 then
                
                -- Prepare text
                local time_to_show = session.time_rem
                if not session.is_running then time_to_show = user_config.timer_minutes * 60 end
                local t_txt = string.format("%s", format_time(time_to_show))
                
                -- Font Change (Timer Font)
                if custom_font.obj then imgui.pop_font() end -- Drop normal font
                if custom_font_timer.obj then imgui.push_font(custom_font_timer.obj) end -- Use big font
                
                -- Position Calc
                local timer_y = center_y + (user_config.timer_hud_y * sh) 
                local w_t = imgui.calc_text_size(t_txt).x
                local x_t = center_x - (w_t / 2) + (user_config.timer_offset_x * sw)
                
                -- Color
                local t_col = COLORS.White
                if user_config.timer_mode_enabled then
                    if session.time_rem < 10 and session.is_running and not session.is_paused then t_col = COLORS.Red 
                    elseif session.is_paused then t_col = COLORS.Yellow end
                end
                
                -- Draw
                draw_timer_outline(t_txt, x_t, timer_y, t_col)
                
                -- Restore normal font
                if custom_font_timer.obj then imgui.pop_font() end
                if custom_font.obj then imgui.push_font(custom_font.obj) end
            end
			
            local s_txt = TEXTS.score_label .. session.score; local t_txt = ""; local tot_txt = TEXTS.total_label .. session.total
            if user_config.timer_mode_enabled then
                local time_to_show = session.time_rem; if not session.is_running then time_to_show = user_config.timer_minutes * 60 end
                t_txt = string.format(TEXTS.timer_label)
            elseif user_config.session_mode == 2 then t_txt = TEXTS.infinite_label end

            local w_s = imgui.calc_text_size(s_txt).x; local x_s = center_x - spread_score_px - w_s + off_score_px
            draw_text_overlay(s_txt, x_s, top_y, session.score_col)

            if t_txt ~= "" then
                local w_t = imgui.calc_text_size(t_txt).x; local x_t = center_x - (w_t / 2) + off_timer_px
                local t_col = COLORS.White
                if user_config.timer_mode_enabled then
                    if session.time_rem < 10 and session.is_running and not session.is_paused then t_col = COLORS.Red elseif session.is_paused then t_col = COLORS.Yellow end
                elseif user_config.session_mode == 2 then t_col = COLORS.White end
                draw_text_overlay(t_txt, x_t, top_y, t_col)
            end

            local w_tot = imgui.calc_text_size(tot_txt).x; local x_tot = center_x + spread_score_px + off_total_px
            draw_text_overlay(tot_txt, x_tot, top_y, COLORS.White)
            
            local y2 = top_y + spacing_y_px; local h_txt = ""; local b_txt = ""
            if user_config.show_hit_pct then
                local h = 0; if session.hit_tot > 0 then h = (session.hit_ok/session.hit_tot)*100 end
                h_txt = string.format("%s%.0f%%", TEXTS.hit_pct_label, h)
            end
            if user_config.show_block_pct then
                local b = 0; if session.blk_tot > 0 then b = (session.blk_ok/session.blk_tot)*100 end
                b_txt = string.format("%s%.0f%%", TEXTS.blk_pct_label, b)
            end
            if h_txt ~= "" then local wh = imgui.calc_text_size(h_txt).x; local xh = center_x - spread_stats_px - wh + off_hit_px; draw_text_overlay(h_txt, xh, y2, COLORS.White) end
            if b_txt ~= "" then local wb = imgui.calc_text_size(b_txt).x; local xb = center_x + spread_stats_px + off_blk_px; draw_text_overlay(b_txt, xb, y2, COLORS.White) end
            
            if user_config.session_mode ~= 0 then
                local diff_txt = "MEDIUM"; if user_config.difficulty == 1 then diff_txt = "EASY" elseif user_config.difficulty == 3 then diff_txt = "HARD" end
                local w_diff = imgui.calc_text_size(diff_txt).x; draw_text_overlay(diff_txt, center_x - w_diff/2, y2, COLORS.White)
            end
            
            if user_config.show_status_line then
                local status_offset_px = user_config.hud_n_offset_status_y * sh; local y3 = y2 + spacing_y_px + status_offset_px
                local msg = session.feedback.text; local w_msg = imgui.calc_text_size(msg).x; local x_msg = center_x - (w_msg / 2)
                draw_text_overlay(msg, x_msg, y3, session.feedback.color)
            end
        end
        if custom_font.obj then imgui.pop_font() end
        imgui.end_window()
    end
    imgui.pop_style_var(2); imgui.pop_style_color(1)
end)

re.on_draw_ui(function()
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= 2 then return end

    if imgui.tree_node("Hit Confirm Trainer (V17 Persistent)") then
        
        -- HEADER 1: HELP & INFO
        if styled_header("--- HELP & INFO ---", UI_THEME.hdr_info) then
            imgui.text("QUICK GUIDE:"); imgui.text("[INSERT]: Open/Close menu."); imgui.text("1. Choose a MODE (Timed / Infinite)."); imgui.text("2. Choose a DIFFICULTY (Easy/Medium/Hard)."); imgui.text("3. Press START (Timed) or start playing (Infinite).")
            imgui.separator(); imgui.text_colored("SHORTCUTS (Hold SELECT or R3):", COLORS.Cyan)
            imgui.text("- (Func) + UP : Switch Mode (Timed/Infinite)"); imgui.text("- (Func) + DOWN : Switch Difficulty"); imgui.text("- (Func) + LEFT : Start / Stop / Export"); imgui.text("- (Func) + RIGHT : Pause / Resume")
            imgui.separator(); imgui.text_colored("DIFFICULTIES:", COLORS.Orange)
            imgui.text_colored("- EASY:   ", COLORS.Easy); imgui.same_line(); imgui.text("Visual aid ON, Blocks counted (+1 score).")
            imgui.text_colored("- MEDIUM: ", COLORS.Medium); imgui.same_line(); imgui.text("Visual aid ON, Blocks ignored (Safe/No score).")
            imgui.text_colored("- HARD:   ", COLORS.Hard); imgui.same_line(); imgui.text("No visual aid, Blocks counted.")
            
            imgui.separator(); imgui.text_colored("DETECTION RULES EXPLAINED:", COLORS.Orange)
            imgui.text("- Trigger Moves: IDs of moves that start detection (e.g. cr.MK).")
            imgui.text("- Confirm Moves: IDs of moves accepted as valid follow-ups (e.g. Special Move).")
            imgui.text("- Break List: IDs that are considered 'unsafe cancels' or sequence breaks.")
            imgui.text("- Damage Type List: IDs defining the reaction type (Hit/Block/Knockdown). Not damage amount.")
            
            imgui.separator(); imgui.text_colored("MATRIX DEBUG EXPLAINED:", COLORS.Orange)
            imgui.text("- Use 'Start Logging' to record frame data into a file.")
            imgui.text("- Matrix Columns flags control what data appears in the debug window below.")
        end

        -- HEADER 2: SESSION CONFIG
        if styled_header("--- SESSION CONFIGURATION ---", UI_THEME.hdr_session) then
            imgui.text("MODE:"); imgui.same_line()
            
            if user_config.session_mode == 1 then 
                if styled_button("TIMED", UI_THEME.btn_green) then 
                    user_config.session_mode = 1; user_config.timer_mode_enabled = true; reset_session_stats(); save_conf() 
                end
            else
                if styled_button("TIMED", UI_THEME.btn_neutral) then 
                    user_config.session_mode = 1; user_config.timer_mode_enabled = true; reset_session_stats(); save_conf() 
                end
            end
            tooltip("Session with a countdown. Stops automatically.")
            
            imgui.same_line()
            
            if user_config.session_mode == 2 then 
                if styled_button("INFINITE", UI_THEME.btn_green) then 
                    user_config.session_mode = 2; user_config.timer_mode_enabled = false; reset_session_stats(); session.is_running = true; session.is_paused = false; save_conf() 
                end
            else
                if styled_button("INFINITE", UI_THEME.btn_neutral) then 
                    user_config.session_mode = 2; user_config.timer_mode_enabled = false; reset_session_stats(); session.is_running = true; session.is_paused = false; save_conf() 
                end
            end
            tooltip("Endless session. Manual stop required.")
            
            imgui.separator()
            
            if user_config.session_mode == 1 then
                imgui.text("DURATION:"); imgui.same_line(); 
                if styled_button("-##min", UI_THEME.btn_neutral) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
                tooltip("Decrease timer duration.")
                imgui.same_line(); imgui.text(tostring(user_config.timer_minutes)); imgui.same_line(); 
                if styled_button("+##min", UI_THEME.btn_neutral) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
                tooltip("Increase timer duration.")
                imgui.same_line(); imgui.text("MINUTES")
                -- [MODIF] RESET BUTTON ON THE LEFT
                if styled_button("RESET", UI_THEME.btn_red) then 
                    reset_session_stats()
                    set_feedback(TEXTS.reset_done, COLORS.White, 1.0)
                end
                tooltip("Reset timer and scores to zero.")

                imgui.same_line()
                if not session.is_running then
                    if styled_button("START", UI_THEME.btn_green) then session.is_running = true; session.is_paused = false; reset_session_stats(); session.time_rem = user_config.timer_minutes * 60; session.is_running = true; set_feedback(TEXTS.started, COLORS.Green, 1.0) end
                    tooltip("Begin the training session.")
                else
                    if styled_button("STOP & EXPORT", UI_THEME.btn_red) then export_session_stats(); reset_session_stats(); set_feedback(TEXTS.stopped_export, COLORS.Red, 1.0) end
                    tooltip("End session and save stats to file.")
                    imgui.same_line(); 
                    if styled_button(session.is_paused and "RESUME" or "PAUSE", UI_THEME.btn_neutral) then session.is_paused = not session.is_paused end
                    tooltip("Toggle pause state.")
                end
            elseif user_config.session_mode == 2 then
                if styled_button("RESET", UI_THEME.btn_red) then reset_session_stats(); session.is_running = true end
                tooltip("Reset score and timer.")
                imgui.same_line(); 
                if styled_button("EXPORT", UI_THEME.btn_green) then export_session_stats(); set_feedback(TEXTS.stats_exported, COLORS.Green, 1.0) end
                tooltip("Save current stats to file.")
            end
            
            if user_config.session_mode ~= 0 then
                imgui.separator(); imgui.text("Difficulty Preset:")
                
                -- EASY
                if user_config.difficulty == 1 then
                    if styled_button("EASY", UI_THEME.btn_easy) then apply_difficulty(1) end
                else
                    if styled_button("EASY", UI_THEME.btn_neutral) then apply_difficulty(1) end
                end
                tooltip("Visual Aid: ON\nBlock Score: Counted (+1)")
                
                imgui.same_line()
                
                -- MEDIUM (Special handling for Black Text on Yellow)
                if user_config.difficulty == 2 then
                    if styled_button("MEDIUM", UI_THEME.btn_medium, COLORS.Shadow) then apply_difficulty(2) end
                else
                    if styled_button("MEDIUM", UI_THEME.btn_neutral) then apply_difficulty(2) end
                end
                tooltip("Visual Aid: ON\nBlock Score: Ignored (0)")
                
                imgui.same_line()
                
                -- HARD
                if user_config.difficulty == 3 then
                    if styled_button("HARD", UI_THEME.btn_hard) then apply_difficulty(3) end
                else
                    if styled_button("HARD", UI_THEME.btn_neutral) then apply_difficulty(3) end
                end
                tooltip("Visual Aid: OFF\nBlock Score: Counted (+1)")
            end
        end

        imgui.separator()
        -- HEADER 3: DETECTION RULES
        if styled_header("--- DETECTION RULES ---", UI_THEME.hdr_rules) then
            local chg1, v1 = imgui.input_text("Trigger Moves (ID)", user_config.str_trigger_list); if chg1 then user_config.str_trigger_list = v1; refresh_tables(); save_conf() end
            tooltip("Move IDs that initiate the hit confirm check (e.g., cr.MK ID).")
            local chg2, v2 = imgui.input_text("Confirm Moves (ID)", user_config.str_success_list); if chg2 then user_config.str_success_list = v2; refresh_tables(); save_conf() end
            tooltip("Move IDs accepted as valid follow-ups (Special/Super moves).")
            local chgBrk, vBrk = imgui.input_text("Break List (Reset)", user_config.str_break_list); if chgBrk then user_config.str_break_list = vBrk; refresh_tables(); save_conf() end
            tooltip("Move IDs that cancel the sequence prematurely (e.g., unexpected Drive Rush).")
            local chg3, v3 = imgui.input_text("Hit Damage Type List", user_config.str_dmg_hit_list); if chg3 then user_config.str_dmg_hit_list = v3; refresh_tables(); save_conf() end
            tooltip("IDs representing valid HIT reactions (e.g. Normal Hit, Punish Counter).")
            local chg4, v4 = imgui.input_text("Block Damage Type List", user_config.str_dmg_block_list); if chg4 then user_config.str_dmg_block_list = v4; refresh_tables(); save_conf() end
            tooltip("IDs representing valid BLOCK reactions (e.g. Stand Block, Crouch Block).")
            imgui.text_colored("IDs & DMG separated by comma (ex: 13, 14)", 0xFF888888)
        end
        
        imgui.separator()
        -- HEADER 4: MATRIX CONFIG
        if styled_header("--- MATRIX COLUMNS CONFIG ---", UI_THEME.hdr_matrix) then
            if styled_button(session.is_logging and "STOP & EXPORT HISTORY (V3)" or "START LOGGING (MATRIX)", UI_THEME.btn_neutral) then
                if session.is_logging then export_detailed_history(); session.is_logging = false else session.is_logging = true; session.history_list = {}; session.history_map = {} end
            end
            tooltip("Record frame data to _FULL_HISTORY_EXPORT.txt.")
            if session.export_msg ~= "" then imgui.same_line(); imgui.text(session.export_msg) end

            imgui.separator()
            local cd, vd = imgui.checkbox("Show Matrix Debug", user_config.show_matrix_debug); if cd then user_config.show_matrix_debug = vd; save_conf() end
            tooltip("Show the real-time data table below.")
            local c_idx, v_idx = imgui.checkbox("Index", user_config.show_index); if c_idx then user_config.show_index = v_idx; save_conf() end
            tooltip("Frame counter / Row ID.")
            
            local function dual_cfg(lbl, k, tip)
                imgui.text(lbl .. ":"); tooltip(tip)
                imgui.same_line(150); local cp1, vp1 = imgui.checkbox("P1##"..k, user_config.p1[k]); if cp1 then user_config.p1[k] = vp1; save_conf() end
                tooltip("Show " .. lbl .. " for Player 1")
                imgui.same_line(220); local cp2, vp2 = imgui.checkbox("P2##"..k, user_config.p2[k]); if cp2 then user_config.p2[k] = vp2; save_conf() end
                tooltip("Show " .. lbl .. " for Player 2")
            end
            dual_cfg("Frame Type", "frame_type", "Internal flag defining the action state (Attacking, Idle, etc.).")
            dual_cfg("Status Type", "status_type", "Secondary flag for specific character states.")
            dual_cfg("Frame Num", "frame_number", "Current animation frame number.")
            dual_cfg("Start Frame", "start_frame", "Start frame of the current move.")
            dual_cfg("End Frame", "end_frame", "End frame of the current move.")
            dual_cfg("Main Gauge", "main_gauge", "Bitflags indicating Start/End of Startup, Active, Recovery, or Under Attack state.")
            
            local c_d, v_d = imgui.checkbox("Damage", user_config.show_damage); if c_d then user_config.show_damage = v_d; save_conf() end
            tooltip("Damage value received on this frame.")
            local c_h, v_h = imgui.checkbox("Hitstop", user_config.show_hitstop); if c_h then user_config.show_hitstop = v_h; save_conf() end
            tooltip("Freeze frames applied on impact.")
            local c_s, v_s = imgui.checkbox("Status", user_config.show_status_label); if c_s then user_config.show_status_label = v_s; save_conf() end
            tooltip("Logic result (HIT LANDED, BLOCK SUCCESS, etc.).")
        end
        imgui.tree_pop()
    end
    
    if user_config.show_matrix_debug then
        imgui.set_next_window_size(Vector2f.new(1000, 600), 1 << 2)
        if imgui.begin_window("Diagnostic Matrix (V3)", true, 0) then
            imgui.text(string.format("DMG: %d | HS: %d | CLOCK: %d", detection.live_dmg, detection.live_hs, detection.abs_clock))
            imgui.same_line(); imgui.text_colored(string.format(" | COMBO: %d", detection.live_combo), COLORS.Yellow)
            if detection.monitor.active then imgui.text_colored("MONITOR ACTIVE: " .. (detection.monitor.type or "?"), COLORS.Green) end
            if detection.lockout then imgui.same_line(); imgui.text_colored("[LOCKED]", COLORS.Red) end
            imgui.separator()
            local h = ""; if user_config.show_index then h = h .. "IDX | " end
            local cols = {{k="frame_type", l="FT"}, {k="status_type", l="TYP"}, {k="frame_number", l="FRM"}, {k="start_frame", l="STR"}, {k="end_frame", l="END"}, {k="main_gauge", l="GAU"}}
            for _, c in ipairs(cols) do if user_config.p1[c.k] then h = h .. "P1_"..c.l.." | " end; if user_config.p2[c.k] then h = h .. "P2_"..c.l.." | " end end
            if user_config.show_damage then h = h .. "DMG | " end; if user_config.show_hitstop then h = h .. "HS  | " end; if user_config.show_status_label then h = h .. "STATUS" end
            imgui.text(h); imgui.separator()
            imgui.begin_child_window("scroller", Vector2f.new(0, -5), true, 0)
            for _, line in ipairs(detection.active_lines) do
                local r = ""; if user_config.show_index then r = r .. string.format("[%03d] | ", line.idx) end
                for _, c in ipairs(cols) do if user_config.p1[c.k] then r = r .. string.format(" %2s   | ", (line.p1[c.k]~=0 and line.p1[c.k] or "-")) end; if user_config.p2[c.k] then r = r .. string.format(" %2s   | ", (line.p2[c.k]~=0 and line.p2[c.k] or "-")) end end
                if user_config.show_damage then r = r .. string.format(" %-3s | ", (line.d~=0 and line.d or "-")) end; if user_config.show_hitstop then r = r .. string.format(" %-3s | ", (line.h~=0 and line.h or "-")) end
                if user_config.show_status_label then if line.res ~= "" then r = r .. "<<< " .. line.res elseif line.is_h then r = r .. "<<< HIT LANDED" elseif line.is_b then r = r .. "<<< BLOCK LANDED" end end
                local col = COLORS.White
                if string.find(line.res, "SUCCESS") then col = COLORS.Green elseif string.find(line.res, "FAIL") then col = COLORS.Red elseif line.is_h then col = COLORS.Yellow elseif line.is_b then col = COLORS.Cyan elseif line.idx == detection.last_head_index then col = COLORS.Orange else if line.idx%2==0 then col = 0xFFDDDDDD else col = 0xFFFFFFFF end end
                imgui.text_colored(r, col)
            end
            imgui.end_child_window(); imgui.end_window()
        end
    end
end)

-- =========================================================
-- [VISUAL FIX] ADVANCED MASKING SYSTEM (Pre-GUI Draw)
-- =========================================================

-- 1. Target: The internal path to the Infinite symbol
local ui_hide_targets = {
    BattleHud_Timer = { 
        { "c_main", "c_hud", "c_timer", "c_infinite" } 
    }
}

-- 2. Recursive function to apply forced invisibility
local apply_force_invisible
apply_force_invisible = function(control, path, depth, should_hide)
    local depth = depth or 1
    
    -- If we are at the end of the path (on the final object)
    if depth > #path then
        -- TRUE = Force Invisible / FALSE = Let game manage it
        control:call("set_ForceInvisible", should_hide)
        return
    end

    -- Descend in hierarchy
    local child = control:call("get_Child")
    while child do
        local name = child:call("get_Name")
        if name and string.match(name, path[depth]) then
            apply_force_invisible(child, path, depth + 1, should_hide)
        end
        child = child:call("get_Next")
    end
end

-- 3. The Hook (Runs just before UI drawing)
re.on_pre_gui_draw_element(function(element, context)
if _G.CurrentTrainerMode ~= 2 then return true end
    local game_object = element:call("get_GameObject")
    if not game_object then return true end
    
    local name = game_object:call("get_Name")
    local paths = ui_hide_targets[name]

    if paths then
        -- Condition : We hide ONLY if in TIMED mode (1)
        -- Make sure 'user_config' is accessible here (defined higher in script)
        local should_hide = (user_config.session_mode == 1)
        
        local view = element:call("get_View")
        for _, path in ipairs(paths) do
            apply_force_invisible(view, path, 1, should_hide)
        end
    end

    return true
end)