local re = re
local sdk = sdk
local imgui = imgui
local json = json
require("func/SharedHooks") -- error registry (_G.safe_load_json)
local GS = require("func/GameState") -- per-frame snapshot (players, act_st, pause)
local UIKit = require("func/UIKit")
local SharedUI = require("func/Training_SharedUI")
local SessionRecap = require("func/Training_SessionRecap")

-- =========================================================
-- TrainingHitConfirm_v7.3 (Heavy DR Cancel Fail Logic)
-- =========================================================

local DR_IDS = { [500]=true, [501]=true, [502]=true, [504]=true, [730]=true, [731]=true, [739]=true, [740]=true, [741]=true, [760]=true, [761]=true }

local _tf_guard_cache_hc = nil
local function _hc_apply_guard_type(guard_val)
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return end
    local tData = tm:get_field("_tData")
    local dd = tData:get_field("GuardSetting"):get_field("DummyData")
    dd.GuardType = guard_val
end
local function _hc_find_tf_guard()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return end
    local entries = tm:get_field("_tfFuncs"):get_field("_entries")
    for i = 0, entries:call("get_Count") - 1 do
        local val = entries:call("get_Item", i):get_field("value")
        if val and val:get_type_definition():get_full_name():find("tf_GuardSetting") then
            _tf_guard_cache_hc = val; return
        end
    end
end
local function _hc_apply_tf_guard()
    _tf_guard_cache_hc:call("bApply")
end
local function hc_set_guard(guard_val)
    pcall(_hc_apply_guard_type, guard_val)
    if not _tf_guard_cache_hc then
        pcall(_hc_find_tf_guard)
    end
    if _tf_guard_cache_hc then pcall(_hc_apply_tf_guard) end
end

local guard_override = { active = false, timer = 0, duration = 40 }

-- =========================================================
-- 0. GLOBAL TEXT VARIABLES (LOCALIZATION)
-- =========================================================
local TEXTS = {
    ready           = "READY",
    waiting         = "WAITING",
    paused          = "PAUSED",
    resumed         = "RESUMED",
    time_up         = "TIME UP!",
    score_label     = "SCORE: ",
    total_label     = "TOTAL: ",
    mode_label      = "HIT CONFIRM",
    hit_pct_label   = "HIT: ",
    blk_pct_label   = "BLOCK: ",
    
    hit_detected    = "HIT DETECTED!",
    blk_detected    = "BLOCK DETECTED...",
    resetting       = "RESETTING...",
    
    success_hit     = "SUCCESS: HIT CONFIRM",
    success_safe    = "BLOCK CONFIRMED",
    safe_generic    = "BLOCK CONFIRMED",
    success_block   = "BLOCK CONFIRMED",
    
    fail_drop       = "FAIL: HIT NOT CONFIRMED",
    fail_unsafe     = "FAIL: UNSAFE CANCEL",
    fail_autopilot  = "FAIL: AUTOPILOT",
    fail_blk_misconfirm = "FAIL: ON BLOCK MISCONFIRM",
    fail_hit        = "HIT FAIL",
    fail_blk_fast   = "BLOCK FAIL (CANCEL TOO FAST)",
    fail_blk_soon   = "BLOCK FAIL (2ND HIT TOO SOON)",
    
    -- NEW SPECIFIC MESSAGES
    fail_gap        = "FAIL: GAP DETECTED AFTER DRC",
    safe_no_gap     = "SAFE: TRUE BLOCKSTRING",
    fail_optimal    = "FAIL: SUBOPTIMAL (NEED HEAVY)",
    perfect_dr      = "SUCCESS: OPTIMAL DRC HIT CONFIRM",
    perfect_dr_light = "SUCCESS: OPTIMAL DRC HIT CONFIRM",
    fail_heavy_dr   = "FAIL: HEAVY DR CANCEL",
    -- (removed attack_ignored)
    fail_combo_drop = "FAIL: GAP IN COMBO AFTER HIT CONFIRMED",
    
    started         = "STARTED!",
    stopped_export  = "STOPPED & EXPORTED",
    stats_exported  = "STATS EXPORTED",
    reset_done      = "RESET DONE",
    
    pause_overlay   = nil, -- dynamic, use SharedUI.pause_message()
    reset_prompt    = nil, -- dynamic, use SharedUI.reset_message()
    
    err_session_file = "Err: Session File",
    err_history_file = "Err: History File"
}

-- =========================================================
-- 0.1 MANAGER DEPENDENCY
-- =========================================================
local DEPENDANT_ON_MANAGER = true 

-- BUTTON MASKS
local BTN_UP     = 1
local BTN_DOWN   = 2
local BTN_LEFT   = 4
local BTN_RIGHT  = 8

local MASK_LIGHT  = 144 -- 16 + 128
local MASK_MEDIUM = 288 -- 32 + 256
local MASK_HEAVY  = 576 -- 64 + 512

local STATE_NEUTRAL = 0
local STATE_HURT    = 9
local STATE_BLOCK   = 10

-- =========================================================
-- 1. CONFIGURATION & STYLING
-- =========================================================
local CONFIG_FILENAME = "TrainingHitConfirm_data/TrainingHitConfirm_Config.json"

local COLORS = UIKit.COLORS

local UI_THEME = {
    hdr_info    = UIKit.THEME.hdr_gold,
    hdr_session = UIKit.THEME.hdr_purple,
    hdr_rules   = UIKit.THEME.hdr_blue,
    hdr_matrix  = UIKit.THEME.hdr_green,
    btn_neutral = UIKit.THEME.btn_neutral,
    btn_green   = UIKit.THEME.btn_green,
    btn_red     = UIKit.THEME.btn_red,
    btn_easy    = UIKit.THEME.btn_easy,
    btn_medium  = UIKit.THEME.btn_medium,
    btn_hard    = UIKit.THEME.btn_hard,
}

local user_config = {
    session_mode = "trials", -- "timer" or "trials"
    timer_minutes = 5,
    trial_count = 20,
    show_matrix_debug = false, 
    show_hit_pct = true,
    show_block_pct = true,
    difficulty = 2, 
    dont_count_blocked = false,
    show_early_detection = true,
    show_status_line = true,
    hud_base_size = 20.24,
    hud_auto_scale = true,
    hud_n_global_y = -0.337,
    hud_n_spacing_y = 0.02800000086426735,
    hud_n_spread_score = 0.09000000357627869,
    hud_n_spread_stats = 0.09000000357627869,
    hud_n_offset_score = 0.0,
    hud_n_offset_total = 0.0,
    hud_n_offset_timer = 0.0,
    hud_n_offset_hit   = 0.0,
    hud_n_offset_blk   = 0.0,
    hud_n_offset_status_y = 0.0,
    timer_hud_y = -0.46,      
    timer_font_size = 80,     
    timer_offset_x = 0.0,
    str_trigger_list = "13", str_success_list = "13", str_break_list = "7,2,1",
    str_dmg_hit_list = "3", str_dmg_block_list = "30",
    str_light_btn_list = "16,128", 
    hit_p2_gauge = 1, success_p1_gauge = 1, persistence_text = 80, persistence_val = 80,
    show_index = true,
    p1 = { frame_type = true, status_type = true, frame_number = false, start_frame = false, end_frame = false, main_gauge = false },
    p2 = { frame_type = true, status_type = true, frame_number = false, start_frame = false, end_frame = false, main_gauge = false },
    show_damage = true, show_hitstop = true, show_status_label = true,
    show_floating = true
}

local work_tables = { trigger = {}, success = {}, dmg_hit = {}, dmg_block = {}, break_list = {}, light_btns = {} }

local session = {
    is_running = false, is_paused = false, 
    start_ts = os.time(), real_start_time = os.time(),time_rem = 0, last_clock = 0,
    score = 0, total = 0, hit_ok = 0, hit_tot = 0, blk_ok = 0, blk_tot = 0,
    last_score = 0, score_col = COLORS.White, score_timer = 0,
    status_msg = TEXTS.ready, export_msg = "",
    is_logging = false, history_list = {}, history_map = {},
    feedback = { text = TEXTS.waiting, timer = 0, color = COLORS.White },
    last_result_was_success = false,
    
    -- Input Buffer Variables
    last_light_input_time = 0, 
    last_medium_input_time = 0, 
    last_heavy_input_time = 0, 
    
    debug_logic = { is_light=false, target_combo=0, actual_combo=0, reason="" },
    detected_type = "NONE"
}

local detection = {
    p1_list = nil, p2_list = nil,
    active_lines = {}, last_head_index = 0, abs_clock = 0, buffer_capacity = 0, 
    live_dmg = 0, live_hs = 0, live_combo = 0,
    mem_hit = {}, mem_blk = {}, mem_res = {}, mem_dmg = {}, mem_hs = {},
    monitor = { active = false, type = nil, has_reset_hs = false, target_combo = 0, is_medium = false }, 
    
    -- SPECIAL MONITOR FOR DR
    dr_monitor = { active = false, type = nil, context = nil, timer = 0, start_combo = 0, gap_grace = 0, is_heavy = false },
    dr_trace = {},

    lockout = false
}

-- Hot-path helpers for update_detection (file-scope: no per-frame closures)
local function _hc_get_count(list) return list:call("get_Count") end
local function _hc_check_active(idx, buffer_count)
    if idx < 0 or idx >= buffer_count then return false end
    local item1 = detection.p1_list:call("get_Item", idx); local item2 = detection.p2_list:call("get_Item", idx)
    if not item1 or not item2 then return false end
    local ft1 = tonumber(tostring(item1:get_field("FrameType"))) or 0; local ft2 = tonumber(tostring(item2:get_field("FrameType"))) or 0
    return (ft1 ~= 0 or ft2 ~= 0)
end
local function _hc_get_all(item)
    return { ft = tonumber(tostring(item:get_field("FrameType"))) or 0, st = tonumber(tostring(item:get_field("Type"))) or 0, fn = tonumber(tostring(item:get_field("Frame"))) or 0, sf = tonumber(tostring(item:get_field("StartFrame"))) or 0, ef = tonumber(tostring(item:get_field("EndFrame"))) or 0, mg = tonumber(tostring(item:get_field("MainGauge"))) or 0 }
end

-- =========================================================
-- 2. TOOLS & HELPERS
-- =========================================================

local styled_button = UIKit.styled_button
local styled_header = UIKit.styled_header

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
    work_tables.light_btns = parse_list(user_config.str_light_btn_list) 
end

local function is_in(tbl, val)
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

-- [NEW] READ GAME INPUT DIRECTLY (pl_sw_new)
local function read_p1_game_input()
    local p1 = GS.p1
    if not p1 then return 0 end
    local f_sw = p1:get_type_definition():get_field("pl_sw_new")
    if not f_sw then return 0 end
    return f_sw:get_data(p1) or 0
end

-- [NEW] GET P1 ACTION ID
local function get_p1_action_id()
    local p1 = GS.p1
    if not p1 then return -1 end
    local actParam = p1.mpActParam
    if not actParam then return -1 end
    local actPart = actParam.ActionPart
    if not actPart then return -1 end
    local engine = actPart._Engine
    if not engine then return -1 end
    return engine:get_ActionID() or -1
end

local CANCEL_BASE_GROUPS = { [0] = true, [15] = true }

local function _hc_call_get_elements(obj)
    return obj:get_elements()
end
local function _hc_get_items_elements(obj)
    local items = obj:get_field("_items")
    if items then return true, items:get_elements() end
    return false, nil
end
local function get_elements_safe(obj)
    if not obj then return nil end
    local s, arr = pcall(_hc_call_get_elements, obj)
    if s and arr then return arr end
    local s2, found, arr2 = pcall(_hc_get_items_elements, obj)
    if s2 and found then arr = arr2 end
    return arr
end

local function _hc_check_cancelable_impl()
    local p1 = GS.p1
    if not p1 then return false end
    local keys_obj = p1.mpActParam.ActionPart._Engine:get_field("mParam"):get_field("action"):get_field("Keys")
    local groups = get_elements_safe(keys_obj)
    if not groups then return false end
    for _, group in ipairs(groups) do
        local keys = get_elements_safe(group)
        if keys then
            for _, key in ipairs(keys) do
                local td = key:get_type_definition()
                if td and td:get_name() == "TriggerKey" then
                    local tg = tonumber(key:get_field("TriggerGroup") or 0)
                    if not CANCEL_BASE_GROUPS[tg] then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function check_p1_cancelable()
    local ok, cancelable = pcall(_hc_check_cancelable_impl)
    if ok and cancelable then return true end
    return false
end

-- Keep Hardware reader ONLY for menu navigation shortcuts
local function get_hardware_pad_mask()
    local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
    local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
    if not gamepad_manager then return 0 end
    local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
    if not devices then return 0 end
    local count = devices:call("get_Count") or 0
    for i = 0, count - 1 do
        local pad = devices:call("get_Item", i)
        if pad then local b = pad:call("get_Button") or 0; if b > 0 then return b end end
    end
    return 0
end

-- local function format_time(s) if not s or s < 0 then s = 0 end return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60)) end

local function load_conf()
    local data = _G.safe_load_json(CONFIG_FILENAME)
    if data then
        if data.user then 
            for k,v in pairs(data.user) do 
                if k == "p1" or k == "p2" then for subk, subv in pairs(v) do user_config[k][subk] = subv end
                else user_config[k] = v end
            end 
        end
    end
    -- HARD MODE FORCED CONFIG
    user_config.difficulty = 3
    user_config.show_early_detection = false
    user_config.dont_count_blocked = true
    user_config.session_mode = "trials"
    user_config.show_floating = true
    
    if user_config.difficulty == nil then user_config.difficulty = 2 end
    refresh_tables()
end

local function save_conf() json.dump_file(CONFIG_FILENAME, { user = user_config }) end
load_conf()

-- =========================================================
-- LOGIC & EXPORTS
-- =========================================================

local function set_feedback(msg, color, duration)
    session.feedback.text = msg; session.feedback.color = color
    if duration and duration > 0 then session.feedback.timer = duration else session.feedback.timer = 0 end
end

local function reset_session_stats()
    SessionRecap.hide()
    session.score = 0; session.total = 0; session.hit_ok = 0; session.hit_tot = 0; session.blk_ok = 0; session.blk_tot = 0
    session.is_running = false; session.is_paused = false
    session.is_time_up = false 
    session.time_up_delay = 0 
    session.real_start_time = os.time()
    session.last_result_was_success = false
    session.time_rem = user_config.timer_minutes * 60
    session.last_light_input_time = 0
    session.last_medium_input_time = 0
    session.last_heavy_input_time = 0
    session.detected_type = "NONE"
    detection.dr_monitor = { active = false, type = nil, context = nil, timer = 0, start_combo = 0, gap_grace = 0 }
end

local function export_session_stats()
    local filename = "Stats/HitConfirm_SessionStats.txt"
    local file_exists = false
    local f_check = io.open(filename, "r"); if f_check then file_exists = true; f_check:close() end

    local f = io.open(filename, "a+"); if not f then session.export_msg = TEXTS.err_session_file; return end

    if not file_exists then
        f:write("DATE\tTIME\tMODE\tDURATION\tDIFF\tREAL_TOTAL\tTOT_SUCC\tTOT_PCT\tSCORE\tHIT_TOT\tHIT_OK\tHIT_PCT\tBLK_TOT\tBLK_OK\tBLK_PCT\n")
    end

    local now = os.time()
    local date_str = os.date("%Y-%m-%d"); local time_str = os.date("%H:%M")
    local duration = os.difftime(now, session.real_start_time)
    local duration_str = string.format("%02d:%02d", math.floor(duration/60), duration%60)

    local mode_str = user_config.session_mode == "trials"
        and ("TRIALS_" .. user_config.trial_count)
        or ("TIMED_" .. user_config.timer_minutes .. "M")

    local real_total_attempts = session.hit_tot + session.blk_tot
    local total_success = session.hit_ok + session.blk_ok
    
    local h_pct = 0; if session.hit_tot > 0 then h_pct = (session.hit_ok/session.hit_tot)*100 end
    local b_pct = 0; if session.blk_tot > 0 then b_pct = (session.blk_ok/session.blk_tot)*100 end
    local total_pct = 0; if real_total_attempts > 0 then total_pct = (total_success / real_total_attempts) * 100 end

    local line = string.format(
        "%s\t%s\t%s\t%s\t%d\t%d\t%.2f%%\t%d\t%d\t%d\t%.2f%%\t%d\t%d\t%.2f%%\n",
        date_str, time_str, mode_str, duration_str,
        real_total_attempts, total_success, total_pct, session.score,
        session.hit_tot, session.hit_ok, h_pct,
        session.blk_tot, session.blk_ok, b_pct
    )
    f:write(line); f:close(); session.export_msg = "Stats Appended!"
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

local function _hc_read_frame_adv()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return nil end
    local tc = tm:get_field("_tCommon")
    if not tc then return nil end
    local snap = tc:get_field("SnapShotDatas")
    if not snap then return nil end
    local s0 = snap[0]
    if not s0 then return nil end
    local dd = s0:get_field("_DisplayData")
    if not dd then return nil end
    local fm = dd:get_field("FrameMeterSSData")
    if not fm then return nil end
    local md = fm:get_field("MeterDatas")
    if not md then return nil end
    local m0 = md:call("get_Item", 0)
    if m0 then
        local sf = m0:get_field("StunFrame")
        if sf then
            local num = tonumber(tostring(sf))
            if num then return num
            else
                local extracted = tostring(sf):match("([%-]?%d+)")
                if extracted then return tonumber(extracted) or 99 end
            end
        end
    end
    return nil
end

local function update_detection()
    if session.is_paused or session.is_time_up then return end
    if detection.mem_hit == nil then detection.mem_hit = {} end
    if detection.mem_blk == nil then detection.mem_blk = {} end
    if detection.mem_res == nil then detection.mem_res = {} end
    if detection.mem_dmg == nil then detection.mem_dmg = {} end
    if detection.mem_hs  == nil then detection.mem_hs  = {} end
    detection.live_dmg = 0; detection.live_hs = 0; detection.live_combo = 0
    
    local p2_obj = GS.p2
    if p2_obj then
        local dt = p2_obj:get_field("damage_type"); if dt then detection.live_dmg = tonumber(tostring(dt)) or 0 end
        local hs = p2_obj:get_field("hit_stop"); if hs then detection.live_hs = tonumber(tostring(hs)) or 0 end
    end
    local p1_obj = GS.p1
    if p1_obj then
        local cc = p1_obj:get_field("combo_cnt"); if cc then detection.live_combo = tonumber(tostring(cc)) or 0 end
    end

    -- Frame meter widget lookup: cached, refreshed when missing or every 300 frames
    detection._list_refresh = (detection._list_refresh or 0) - 1
    if detection._list_refresh <= 0 or not detection.p1_list or not detection.p2_list then
        detection._list_refresh = 300
        detection.p1_list = nil; detection.p2_list = nil
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
    end

    if detection.p1_list and detection.p2_list then
        local ok_cnt, buffer_count = pcall(_hc_get_count, detection.p1_list)
        if not ok_cnt then detection.p1_list = nil; detection.p2_list = nil; return end
        if not buffer_count or buffer_count <= 0 then return end
        detection.buffer_capacity = buffer_count
        
        local active_head_index = -1; local next_idx = (detection.last_head_index + 1) % buffer_count

        local is_new_frame = false
        if _hc_check_active(next_idx, buffer_count) then active_head_index = next_idx; detection.abs_clock = detection.abs_clock + 1; is_new_frame = true
        elseif _hc_check_active(detection.last_head_index, buffer_count) then active_head_index = detection.last_head_index
        else
            -- Idle: the old full-buffer backward rescan cost ~3ms per pass (2 get_Item
            -- + 2 get_field + 2 tostring per entry). Replaced by a bounded rotating
            -- scan: max 20 entries per frame, resumes where it left off. Normal
            -- resumption is caught instantly by the next_idx check above.
            if not detection._idle_mode then
                detection._idle_mode = true
                detection._idle_scan_i = buffer_count - 1
                detection.mem_hit = {}; detection.mem_blk = {}; detection.mem_res = {}; detection.mem_dmg = {}; detection.mem_hs = {}; detection.monitor.active = false; detection.abs_clock = 0
            end
            local i = detection._idle_scan_i or (buffer_count - 1)
            local checked = 0
            while i >= 0 and checked < 20 do
                if _hc_check_active(i, buffer_count) then active_head_index = i; break end
                i = i - 1; checked = checked + 1
            end
            if active_head_index == -1 then
                detection._idle_scan_i = (i >= 0) and i or (buffer_count - 1)
            end
        end
        if active_head_index ~= -1 then detection._idle_mode = false end
        detection.last_head_index = active_head_index

        if active_head_index ~= -1 and detection.p1_list then
            local it1 = detection.p1_list:call("get_Item", active_head_index); local it2 = detection.p2_list:call("get_Item", active_head_index)
            if it1 and it2 then
                local p1_data = _hc_get_all(it1); local p2_data = _hc_get_all(it2)
                
                if is_new_frame and session.is_logging then
                    local entry = { clock = detection.abs_clock, p1 = p1_data, p2 = p2_data, dmg = detection.live_dmg, hs = detection.live_hs, cmb = detection.live_combo, status = "", tag = nil }
                    table.insert(session.history_list, entry); session.history_map[detection.abs_clock] = entry
                end

                if detection.live_dmg > 0 then detection.mem_dmg[active_head_index] = { val = detection.live_dmg, time = detection.abs_clock } end
                if detection.live_hs > 0 then detection.mem_hs[active_head_index] = { val = detection.live_hs, time = detection.abs_clock } end

                if guard_override.active then
                    guard_override.timer = guard_override.timer - 1
                    if guard_override.timer <= 0 then
                        hc_set_guard(4)
                        guard_override.active = false
                    end
                end

                if detection.lockout then
                    if session.feedback.timer <= 0 then set_feedback(TEXTS.resetting, COLORS.DarkGrey, 0.1) end
                    if not is_in(work_tables.trigger, p1_data.ft) and not is_in(work_tables.break_list, p1_data.ft) then
                        detection.lockout = false; session.last_result_was_success = false; detection._saw_cancelable = false
                        if session.feedback.timer <= 0 then set_feedback(TEXTS.waiting, COLORS.Grey, 0) end
                    end
                end


                local is_ft_trig = is_in(work_tables.trigger, p1_data.ft)
                local is_dmg_allowed = is_in(work_tables.dmg_hit, detection.live_dmg)
                
                -- LIGHT/MEDIUM/HEAVY BUFFER CHECKS
                local time_since_light = os.clock() - session.last_light_input_time
                local is_light_buffered = (time_since_light < 0.25) 
                
                local time_since_medium = os.clock() - session.last_medium_input_time
                local is_medium_buffered = (time_since_medium < 0.5) -- Extended Buffer for Medium
                
                -- [MOVED] Heavy Buffer check moved here for Logic
                local time_since_heavy = os.clock() - session.last_heavy_input_time
                local is_heavy_buffered = (time_since_heavy < 0.5) 
                
                local required_combo_start = is_light_buffered and 2 or 1
                
                -- Debug Display Logic
                if is_ft_trig then
                    if is_light_buffered then session.detected_type = "LIGHT"
                    elseif is_medium_buffered then session.detected_type = "MEDIUM"
                    else session.detected_type = "HEAVY" end
                end
                
                session.debug_logic.is_light = is_light_buffered
                session.debug_logic.target_combo = required_combo_start
                session.debug_logic.actual_combo = detection.live_combo
                if is_ft_trig and is_dmg_allowed then
                    if detection.live_combo == required_combo_start then session.debug_logic.reason = "MATCH"
                    elseif detection.live_combo < required_combo_start then session.debug_logic.reason = "WAITING COMBO"
                    else session.debug_logic.reason = "PASSED" end
                else
                   session.debug_logic.reason = "NO TRIGGER"
                end
                
                local trig_hit = (is_ft_trig and detection.live_combo == required_combo_start and is_dmg_allowed)
                local is_dmg_blk = is_in(work_tables.dmg_block, detection.live_dmg)
                local trig_blk = (is_ft_trig and p2_data.mg > 0 and is_dmg_blk)
                
                -- =======================================================
                -- MONITOR DR CANCEL START (MEDIUM + HEAVY)
                if _G._hc_logging then
                    if not _G._hc_log_lines then _G._hc_log_lines = {} end
                    table.insert(_G._hc_log_lines, string.format("[%d] lock=%s mon=%s/%s trig_h=%s trig_b=%s combo=%d hs=%d ft1=%d ft2=%d new_act=%s",
                        detection.abs_clock or 0, tostring(detection.lockout), tostring(detection.monitor.active), tostring(detection.monitor.type),
                        tostring(trig_hit), tostring(trig_blk), detection.live_combo or 0, detection.live_hs or 0,
                        p1_data.ft, p2_data.ft, tostring(detection.monitor.saw_new_action)))
                end
                -- =======================================================
                -- [MODIFIED] Now triggers for Heavy on Block too
                if (trig_hit or trig_blk) and (is_medium_buffered or is_heavy_buffered) and not detection.dr_monitor.active then
                    detection.dr_monitor.active = true
                    detection.dr_monitor.type = "WAIT_DR"
                    detection.dr_monitor.context = trig_hit and "HIT" or "BLOCK"
                    detection.dr_monitor.timer = 20 -- Frames to wait for DR cancel
                    detection.dr_monitor.start_combo = detection.live_combo
                    detection.dr_monitor.gap_grace = 0
                    detection.dr_monitor.is_heavy = is_heavy_buffered -- Remember if it was heavy
                    detection.dr_monitor.was_light = is_light_buffered -- Remember if initial hit was light
                end
                

                if trig_hit and not detection.lockout then
                    detection.mem_hit[active_head_index] = detection.abs_clock
                    if session.history_map[detection.abs_clock] then session.history_map[detection.abs_clock].tag = "HIT" end
                    if not detection.monitor.active or detection.monitor.type ~= "HIT" then
                        detection.monitor.active = true; detection.monitor.type = "HIT"; detection.monitor.has_reset_hs = false
                        detection.monitor.target_combo = required_combo_start + 1
                        detection.monitor.peak_combo = detection.live_combo or 0
                        detection.monitor.was_light = is_light_buffered
                        detection.monitor.start_action_id = get_p1_action_id()
                        detection.monitor.saw_new_action = false
                        detection.monitor.is_multihit = false
                        detection.monitor.is_cancelable = false
                        detection._saw_cancelable = check_p1_cancelable()
                        detection.monitor.last_ft = p1_data.ft
                        detection.monitor.saw_recovery = false
                        detection.monitor.saw_recovery_to_startup = false
                        detection.mem_res[active_head_index] = { status = "HIT LANDED", time = detection.abs_clock }
                        update_history_status(detection.abs_clock, "HIT LANDED")
                        if user_config.show_early_detection then 
                            local msg = is_light_buffered and "HIT (LIGHT CHAIN START)!" or TEXTS.hit_detected
                            local col = is_light_buffered and COLORS.Orange or COLORS.Yellow
                            set_feedback(msg, col, 2.0) 
                        end
                    end
                elseif trig_blk and not detection.lockout then
                    if is_light_buffered and not guard_override.active then
                        hc_set_guard(3)
                        guard_override.active = true
                        guard_override.timer = guard_override.duration
                    end
                    -- If a HIT monitor is active and the combo dropped, fail before switching to BLOCK
                    if detection.monitor.active and detection.monitor.type == "HIT" and detection.live_combo == 0 then
                        local did_confirm = (detection.monitor.peak_combo and detection.monitor.peak_combo >= detection.monitor.target_combo) or detection.monitor.saw_new_action or detection.monitor.saw_recovery_to_startup
                        local fail_txt = did_confirm and TEXTS.fail_combo_drop or TEXTS.fail_drop
                        detection.mem_res[active_head_index] = { status = fail_txt, time = detection.abs_clock }; update_history_status(detection.abs_clock, fail_txt)
                        detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                        session.score = session.score - 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                        set_feedback(fail_txt, COLORS.Red, 1.5)
                    end
                    if not detection.lockout and not (detection.monitor.active and detection.monitor.type == "HIT" and detection.live_combo > 0) then
                    detection.mem_blk[active_head_index] = detection.abs_clock
                    if session.history_map[detection.abs_clock] then session.history_map[detection.abs_clock].tag = "BLOCK" end
                    if not detection.monitor.active or detection.monitor.type ~= "BLOCK" then
                        detection.monitor.active = true; detection.monitor.type = "BLOCK"; detection.monitor.has_reset_hs = false
                        detection.monitor.start_action_id = get_p1_action_id()
                        detection.monitor.saw_new_action = false
                        detection.monitor.was_light = is_light_buffered
                        detection._saw_cancelable = check_p1_cancelable()

                        -- MEMORIZE IF THIS IS A MEDIUM HIT
                        detection.monitor.is_medium = is_medium_buffered
                        
                        detection.mem_res[active_head_index] = { status = "BLOCK LANDED", time = detection.abs_clock }
                        update_history_status(detection.abs_clock, "BLOCK LANDED")
                        if user_config.show_early_detection then set_feedback(TEXTS.blk_detected, COLORS.Cyan, 2.0) end
                    end
                    end
                end
                
                -- =======================================================
                -- DR CANCEL MONITOR LOGIC (PARALLEL)
                -- =======================================================
                if detection.dr_monitor.active then
                    if detection.dr_monitor.type == "WAIT_DR" then
                        if DR_IDS[get_p1_action_id()] then
                            -- [NEW] LOGIC: IF HEAVY + BLOCK + DR => FAIL IMMEDIATELY
                            if detection.dr_monitor.context == "BLOCK" and detection.dr_monitor.is_heavy then
                                detection.dr_monitor.active = false; detection.monitor.active = false; detection.lockout = true
                                session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_heavy_dr, time = detection.abs_clock }
                                set_feedback(TEXTS.fail_heavy_dr, COLORS.Red, 2.0)
                            else
                                detection.dr_monitor.type = "EXECUTE"
                                detection.dr_monitor.timer = 120 -- Monitor window
                                detection.dr_monitor.gap_grace = 3 -- Grace period for gap check
                                detection.dr_trace = {}
                            end
                        else
                            detection.dr_monitor.timer = detection.dr_monitor.timer - 1
                            if detection.dr_monitor.timer <= 0 then detection.dr_monitor.active = false end
                        end
                    elseif detection.dr_monitor.type == "EXECUTE" then
                        table.insert(detection.dr_trace, string.format("f%d p1_ft=%d p2_ft=%d hs=%d combo=%d grace=%d",
                            detection.abs_clock, p1_data.ft, p2_data.ft, detection.live_hs, detection.live_combo, detection.dr_monitor.gap_grace))
                        if detection.dr_monitor.context == "BLOCK" then
                            if detection.dr_monitor.gap_grace > 0 then
                                detection.dr_monitor.gap_grace = detection.dr_monitor.gap_grace - 1
                            else
                                if p2_data.ft == 0 then
                                    detection.dr_monitor.active = false; detection.monitor.active = false; detection.lockout = true
                                    session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                    detection.mem_res[active_head_index] = { status = TEXTS.fail_gap, time = detection.abs_clock }
                                    set_feedback(TEXTS.fail_gap, COLORS.Red, 2.0)
                                elseif (p2_data.ft == 10 or p2_data.ft == 9) and detection.live_hs > 0 then
                                    detection.dr_monitor.active = false; detection.monitor.active = false; detection.lockout = true
                                    if p2_data.mg == 1 then
                                        session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                        detection.mem_res[active_head_index] = { status = TEXTS.fail_gap, time = detection.abs_clock }
                                        set_feedback(TEXTS.fail_gap, COLORS.Red, 2.0)
                                    else
                                        detection.mem_res[active_head_index] = { status = TEXTS.safe_no_gap, time = detection.abs_clock }
                                        set_feedback(TEXTS.safe_no_gap, COLORS.White, 2.0)
                                    end
                                end
                            end
                        elseif detection.dr_monitor.context == "HIT" then
                            -- HIT CONTEXT: Check Combo & Button
                            if detection.live_combo > detection.dr_monitor.start_combo then
                                -- Check Buffer instead of live input for robustness
                                local is_heavy_buffered = (os.clock() - session.last_heavy_input_time < 0.4)
                                local is_light_buffered_dr = (os.clock() - session.last_light_input_time < 0.4)
                                -- Accept light after DR if the initial hit was also a light
                                local is_valid = is_heavy_buffered or (detection.dr_monitor.was_light and is_light_buffered_dr)

                                detection.dr_monitor.active = false; detection.monitor.active = false; detection.lockout = true
                                if is_valid then
                                    local dr_msg = (detection.dr_monitor.was_light and not is_heavy_buffered) and TEXTS.perfect_dr_light or TEXTS.perfect_dr
                                    session.score = session.score + 1; session.hit_ok = session.hit_ok + 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                    detection.mem_res[active_head_index] = { status = dr_msg, time = detection.abs_clock }
                                    set_feedback(dr_msg, COLORS.Green, 2.0)
                                else
                                    session.score = session.score - 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                    detection.mem_res[active_head_index] = { status = TEXTS.fail_optimal, time = detection.abs_clock }
                                    set_feedback(TEXTS.fail_optimal, COLORS.Red, 2.0)
                                end
                            elseif p2_data.ft == 0 or detection.live_combo == 0 then
                                detection.dr_monitor.active = false; detection.monitor.active = false; detection.lockout = true
                                session.score = session.score - 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_drop, time = detection.abs_clock }
                                set_feedback(TEXTS.fail_drop, COLORS.Red, 2.0)
                            end
                        end
                    end
                end
                
                -- STANDARD MONITOR (RUNS ONLY IF DR MONITOR IS NOT HANDLING THINGS AND NOT LOCKED OUT)
                if detection.monitor.active and not detection.dr_monitor.active and not detection.lockout then
                    -- Track peak combo reached
                    if detection.monitor.peak_combo and (detection.live_combo or 0) > detection.monitor.peak_combo then
                        detection.monitor.peak_combo = detection.live_combo
                    end
                    -- Track RECOVERY->STARTUP (= new move) -- even with neutral frames in between
                    local cur_ft = p1_data.ft
                    if cur_ft == 8 and not detection.monitor.saw_recovery and not detection._saw_cancelable and not detection.monitor.was_light then
                        detection.monitor.active = false; detection.lockout = true
                        detection.mem_res[active_head_index] = { status = "NON CANCELABLE MOVE", time = detection.abs_clock }
                        update_history_status(detection.abs_clock, "NON CANCELABLE MOVE")
                        set_feedback("NON CANCELABLE MOVE", COLORS.Grey, 1.5)
                    end
                    if cur_ft == 8 then detection.monitor.saw_recovery = true end
                    if detection.monitor.saw_recovery and cur_ft == 7 then
                        detection.monitor.saw_recovery_to_startup = true
                    end
                    -- Multi-hit: same action ID, no RECOVERY->STARTUP, combo increased without new action
                    if not detection.monitor.is_multihit and not detection.monitor.saw_recovery_to_startup
                       and not detection.monitor.saw_new_action and detection.monitor.start_action_id then
                        local cur_id = get_p1_action_id()
                        -- If combo reached or exceeded target with the same action ID -> multi-hit
                        if cur_id == detection.monitor.start_action_id and detection.live_combo >= detection.monitor.target_combo then
                            detection.monitor.is_multihit = true
                            detection.monitor.target_combo = detection.live_combo + 1
                            detection.monitor.has_reset_hs = false
                        -- If a 2nd hitstop appears with the same action ID -> multi-hit
                        elseif cur_id == detection.monitor.start_action_id and detection.monitor.has_reset_hs and detection.live_hs > 0 then
                            detection.monitor.is_multihit = true
                            detection.monitor.target_combo = (detection.live_combo or 0) + 1
                            detection.monitor.has_reset_hs = false
                        end
                    end
                    detection.monitor.last_ft = cur_ft
                    -- Detect if the action ID changed (true cancel)
                    if not detection.monitor.saw_new_action and detection.monitor.start_action_id then
                        local cur_id = get_p1_action_id()
                        if cur_id ~= detection.monitor.start_action_id and cur_id ~= -1 and p1_data.ft ~= 0 then
                            detection.monitor.saw_new_action = true
                            detection.monitor.combo_at_new_action = detection.live_combo or 0
                        end
                    end
                    if detection.live_hs == 0 then detection.monitor.has_reset_hs = true end
                    if detection.monitor.has_reset_hs then
                        if detection.monitor.type == "HIT" then
                            if detection.live_combo >= detection.monitor.target_combo then
                                detection.mem_res[active_head_index] = { status = TEXTS.success_hit, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.success_hit)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = true
                                session.score = session.score + 1; session.hit_ok = session.hit_ok + 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.success_hit, COLORS.Green, 1.5)
                            elseif detection.live_combo == 0 then
                                -- Check if the move should be ignored (not cancelable AND advantage < 4)
                                local frame_adv = 99
                                local fa_ok, fa_val = pcall(_hc_read_frame_adv)
                                if fa_ok and fa_val then frame_adv = fa_val end
                                local did_confirm = (detection.monitor.peak_combo and detection.monitor.peak_combo >= detection.monitor.target_combo) or detection.monitor.saw_new_action or detection.monitor.saw_recovery_to_startup
                                    local fail_txt = did_confirm and TEXTS.fail_combo_drop or TEXTS.fail_drop
                                    detection.mem_res[active_head_index] = { status = fail_txt, time = detection.abs_clock }; update_history_status(detection.abs_clock, fail_txt)
                                    detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                    session.score = session.score - 1; session.hit_tot = session.hit_tot + 1; session.total = session.total + 1
                                    set_feedback(fail_txt, COLORS.Red, 1.5)
                            end
                        end
                        if detection.monitor.type == "BLOCK" then

                            -- IF (Break List Detected) => ON BLOCK MISCONFIRM (only if new action)
                            if is_in(work_tables.break_list, p1_data.ft) and (detection.monitor.saw_new_action or detection.monitor.saw_recovery_to_startup) then
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_blk_misconfirm, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.fail_blk_misconfirm)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.fail_blk_misconfirm, COLORS.Red, 1.5)
                            elseif is_in(work_tables.success, p1_data.ft) and not is_in(work_tables.trigger, p1_data.ft) and detection.live_hs > 0 and (detection.monitor.saw_new_action or detection.monitor.saw_recovery_to_startup) then
                                detection.mem_res[active_head_index] = { status = TEXTS.fail_blk_misconfirm, time = detection.abs_clock }; update_history_status(detection.abs_clock, TEXTS.fail_blk_misconfirm)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                session.score = session.score - 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1
                                set_feedback(TEXTS.fail_blk_misconfirm, COLORS.Red, 1.5)
                            elseif not detection._saw_cancelable and not detection.monitor.was_light and not is_in(work_tables.dmg_block, detection.live_dmg) then
                                detection.monitor.active = false; detection.lockout = true
                                detection.mem_res[active_head_index] = { status = "NON CANCELABLE MOVE", time = detection.abs_clock }
                                update_history_status(detection.abs_clock, "NON CANCELABLE MOVE")
                                set_feedback("NON CANCELABLE MOVE", COLORS.Grey, 1.5)
                            elseif not is_in(work_tables.dmg_block, detection.live_dmg) then
                                local blk_msg = TEXTS.success_block
                                detection.mem_res[active_head_index] = { status = blk_msg, time = detection.abs_clock }; update_history_status(detection.abs_clock, blk_msg)
                                detection.monitor.active = false; detection.lockout = true; session.last_result_was_success = false
                                session.blk_ok = session.blk_ok + 1; session.blk_tot = session.blk_tot + 1; session.total = session.total + 1;
                                if not user_config.dont_count_blocked then session.score = session.score + 1; set_feedback(blk_msg, COLORS.Green, 1.5)
                                else set_feedback(blk_msg, COLORS.White, 1.5) end
                            end
                        end
                    end
                end
            end
        end
    end

    if user_config.show_matrix_debug and detection.p1_list and detection.p2_list then
        detection.active_lines = {}
        local cnt1 = detection.p1_list:call("get_Count"); local cnt2 = detection.p2_list:call("get_Count")
        local max_cnt = math.max(cnt1, cnt2); local limit = 0
        for idx = 0, max_cnt - 1 do
            local function get_hd(list, index)
                local item = list:call("get_Item", index)
                if not item then return {frame_type=0, status_type=0, frame_number=0, start_frame=0, end_frame=0, main_gauge=0} end
                return { frame_type=tonumber(tostring(item:get_field("FrameType"))) or 0, status_type=tonumber(tostring(item:get_field("Type"))) or 0, frame_number=tonumber(tostring(item:get_field("Frame"))) or 0, start_frame=tonumber(tostring(item:get_field("StartFrame"))) or 0, end_frame=tonumber(tostring(item:get_field("EndFrame"))) or 0, main_gauge=tonumber(tostring(item:get_field("MainGauge"))) or 0 }
            end
            local d1 = {frame_type=0}; local d2 = {frame_type=0}
            if idx < cnt1 then d1 = get_hd(detection.p1_list, idx) end; if idx < cnt2 then d2 = get_hd(detection.p2_list, idx) end
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
    local is_game_active = not GS.in_pause_menu
    
    if session.score ~= session.last_score then session.score_col = (session.score > session.last_score) and COLORS.Green or COLORS.Red; session.score_timer = 30; session.last_score = session.score end
    if session.score_timer > 0 then session.score_timer = session.score_timer - 1; if session.score_timer <= 0 then session.score_col = COLORS.White end end
    
    local now = os.clock(); local dt = now - session.last_clock; session.last_clock = now
    
    -- [NEW] Capture Inputs from GAME LOGIC (P1 Only)
    local cur_input_game = read_p1_game_input()
    for _, btn_mask in ipairs(work_tables.light_btns) do
        if (cur_input_game & btn_mask) ~= 0 then session.last_light_input_time = now; break end
    end
    if (cur_input_game & MASK_MEDIUM) ~= 0 then session.last_medium_input_time = now end
    if (cur_input_game & MASK_HEAVY) ~= 0 then session.last_heavy_input_time = now end -- [NEW] Heavy Buffer
    
    -- TIME UP MESSAGE MANAGEMENT
    if session.is_time_up then
        session.time_up_delay = (session.time_up_delay or 0) + dt
        if session.time_up_delay > 1.0 then
            set_feedback(SharedUI.reset_message(), COLORS.Yellow, 0)
        end
        return 
    end

    if session.feedback.timer > 0 then
        session.feedback.timer = session.feedback.timer - dt
        if session.feedback.timer <= 0 then if not detection.lockout then session.feedback.text = TEXTS.waiting; session.feedback.color = COLORS.Grey; session.feedback.timer = 0 end end
    end

    if session.is_running and is_game_active and not session.is_paused then
        if user_config.session_mode == "timer" then
            local is_in_success_anim = detection.lockout and session.last_result_was_success
            if not is_in_success_anim then session.time_rem = session.time_rem - dt end

            if session.time_rem <= 0 then
                session.time_rem = 0
                session.is_running = false
                session.is_time_up = true
                session.time_up_delay = 0

                export_session_stats()
                SessionRecap.show("HIT CONFIRM", "Stats/HitConfirm_SessionStats.txt", "hitconfirm")
                set_feedback("TIME UP! & EXPORTED", COLORS.Red, 0)
            end
        else -- trials mode
            if session.total >= user_config.trial_count then
                session.is_running = false
                session.is_time_up = true
                session.time_up_delay = 0

                export_session_stats()
                SessionRecap.show("HIT CONFIRM", "Stats/HitConfirm_SessionStats.txt", "hitconfirm")
                set_feedback(session.total .. " TRIALS DONE! & EXPORTED", COLORS.Red, 0)
            end
        end
    end
    
    if is_game_active then update_detection() end
end

-- =========================================================
-- INPUT HANDLING
-- =========================================================
local last_input_mask = 0
local last_kb_state = { [0x31]=false, [0x32]=false, [0x33]=false, [0x34]=false }

local function hc_ticker(msg) if _G.show_custom_ticker then _G.show_custom_ticker(msg, 0.3) end end

local function _hc_is_key_down(k) return reframework:is_key_down(k) end

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
    -- Use Hardware Input for MENU NAVIGATION Only
    local active_buttons = get_hardware_pad_mask()

    local func_btn = _G.TrainingFuncButton or 16384
    local is_func_held = ((active_buttons & func_btn) == func_btn)

    local kb_state = {}
    for _, k in ipairs({0x31, 0x32, 0x33, 0x34}) do
        local ok, down = pcall(_hc_is_key_down, k)
        kb_state[k] = ok and down
    end
    local function kb_pressed(k) return kb_state[k] and not last_kb_state[k] end
    local function pad_pressed(btn) return ((active_buttons & btn) == btn) and not ((last_input_mask & btn) == btn) end
    local function is_action(btn, kb) return (is_func_held and pad_pressed(btn)) or kb_pressed(kb) end

    -- 1. TIMER/TRIALS SETTINGS (UP/DOWN = 2/3)
    if not session.is_running and not session.is_time_up then
        if is_action(BTN_UP, 0x32) then
            if user_config.session_mode == "timer" then
                user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1)
                session.time_rem = user_config.timer_minutes * 60
                set_feedback("TIMER: " .. user_config.timer_minutes .. " MIN", COLORS.White, 1.0)
            else
                user_config.trial_count = math.min(200, user_config.trial_count + 10)
                set_feedback(tostring(user_config.trial_count), COLORS.White, 1.0)
            end
            save_conf()
        end
        if is_action(BTN_DOWN, 0x31) then
            if user_config.session_mode == "timer" then
                user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1)
                session.time_rem = user_config.timer_minutes * 60
                set_feedback("TIMER: " .. user_config.timer_minutes .. " MIN", COLORS.White, 1.0)
            else
                user_config.trial_count = math.max(10, user_config.trial_count - 10)
                set_feedback(tostring(user_config.trial_count), COLORS.White, 1.0)
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
            hc_ticker("SESSION RESET")
        end
    elseif session.is_running then
        if pos3_kb or pos4_pad then
            reset_session_stats()
            set_feedback("STOPPED", COLORS.Red, 1.5)
            hc_ticker("SESSION STOPPED")
        end
    elseif session.is_time_up then
        if pos3_kb or pos4_pad then
            reset_session_stats()
            set_feedback(TEXTS.reset_done, COLORS.White, 1.0)
            hc_ticker("SESSION RESET")
        end
    end

    -- Position 4 (key 4 / FUNC+RIGHT): START when idle, PAUSE when running
    if not session.is_running and not session.is_time_up then
        if pos4_kb or pos3_pad then
            reset_session_stats()
            if user_config.session_mode == "timer" then session.time_rem = user_config.timer_minutes * 60 end
            session.is_running = true; session.is_paused = false
            set_feedback(TEXTS.started, COLORS.Green, 1.0)
            hc_ticker("SESSION STARTED")
        end
    elseif session.is_running then
        if pos4_kb or pos3_pad then
            session.is_paused = not session.is_paused
            set_feedback(session.is_paused and TEXTS.paused or TEXTS.resumed, COLORS.Yellow, 1.0)
            hc_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED")
        end
    end

    last_input_mask = active_buttons
    last_kb_state = kb_state
end

local function update_logic_and_input()
    handle_input()
    update_logic()
end



-- =========================================================
-- [FIXED EVENTS]
-- =========================================================

local function draw_hud_overlay()
    local is_trials = (user_config.session_mode == "trials")
    SharedUI.draw_standard_hud("HUD_Overlay", user_config, session, TEXTS.mode_label, not is_trials, function(cx, cy, sw, sh)
        -- In trials mode, draw trial counter at timer position
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
        local spread_stats_px = (user_config.hud_n_spread_stats or 0.09) * sw
        local off_hit_px   = (user_config.hud_n_offset_hit or 0.0) * sw
        local off_blk_px   = (user_config.hud_n_offset_blk or 0.0) * sw
        local h_txt, b_txt = "", ""
        
        if user_config.show_hit_pct then
            local h = 0; if session.hit_tot > 0 then h = (session.hit_ok/session.hit_tot)*100 end
            h_txt = string.format("%s%.0f%%", TEXTS.hit_pct_label, h)
        end
        if user_config.show_block_pct then
            local b = 0; if session.blk_tot > 0 then b = (session.blk_ok/session.blk_tot)*100 end
            b_txt = string.format("%s%.0f%%", TEXTS.blk_pct_label, b)
        end
        
        if h_txt ~= "" then 
            local wh = imgui.calc_text_size(h_txt).x
            SharedUI.draw_text(h_txt, cx - spread_stats_px - wh + off_hit_px, cy, SharedUI.COLORS.White) 
        end
        if b_txt ~= "" then 
            SharedUI.draw_text(b_txt, cx + spread_stats_px + off_blk_px, cy, SharedUI.COLORS.White) 
        end
    end)
end

-- SESSION BUTTONS — DOCKED
local function draw_session_buttons_docked()
    local sl = SharedUI.sc_label
    local SC = SharedUI.SC_COLORS
    -- Mode toggle
    local mode_label = user_config.session_mode == "timer" and "MODE: TIMER" or "MODE: TRIALS"
    if imgui.button(mode_label .. "##dk_mode") then
        user_config.session_mode = user_config.session_mode == "timer" and "trials" or "timer"
        reset_session_stats(); save_conf()
        hc_ticker(user_config.session_mode == "timer" and "TIMER MODE" or "TRIALS MODE")
    end
    imgui.same_line()
    if user_config.session_mode == "timer" then
        if SharedUI.sc_button("TIMER - (" .. sl("D") .. ")##dk_hc", SC.c1) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
        imgui.same_line()
        if SharedUI.sc_button("TIMER + (" .. sl("U") .. ")##dk_hc", SC.c2) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
        imgui.same_line(); imgui.text(tostring(user_config.timer_minutes) .. " MIN")
    else
        if SharedUI.sc_button("TRIALS - (" .. sl("D") .. ")##dk_hc", SC.c1) then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        imgui.same_line()
        if SharedUI.sc_button("TRIALS + (" .. sl("U") .. ")##dk_hc", SC.c2) then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
        imgui.same_line(); imgui.text(tostring(user_config.trial_count) .. " TRIALS")
    end
    imgui.same_line(300)
    if SharedUI.sc_button("RESET (" .. sl("L", "3") .. ")##dk_hc", SC.c3) then reset_session_stats(); set_feedback(TEXTS.reset_done, COLORS.White, 1.0); hc_ticker("SESSION RESET") end
    imgui.spacing()
    if not session.is_running then
        if SharedUI.sc_button("START SESSION (" .. sl("R", "4") .. ")##dk_hc", SC.c4) then
            reset_session_stats()
            if user_config.session_mode == "timer" then session.time_rem = user_config.timer_minutes * 60 end
            session.is_running = true; session.is_paused = false
            set_feedback(TEXTS.started, COLORS.Green, 1.0)
            hc_ticker("SESSION STARTED")
        end
    else
        if SharedUI.sc_button("STOP (" .. sl("L", "3") .. ")##dk_hc", SC.c3) then reset_session_stats(); set_feedback("STOPPED", COLORS.Red, 1.0); hc_ticker("SESSION STOPPED") end
        imgui.same_line()
        if SharedUI.sc_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##dk_hc", SC.c4) then session.is_paused = not session.is_paused; hc_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED") end
    end
end

-- SESSION BUTTONS — FLOATING (single-line)
local function draw_session_floating()
    local visible, sw, sh = SharedUI.begin_floating_window("Hit Confirm##float")
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
    -- +/- buttons adapt to mode
    if user_config.session_mode == "timer" then
        if SharedUI.sf6_button("TIMER - (" .. sl("D") .. ")##fl_hc", SC.c1, actual_w) then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
        imgui.same_line(0, sp)
        if SharedUI.sf6_button("TIMER + (" .. sl("U") .. ")##fl_hc", SC.c2, actual_w) then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
    else
        if SharedUI.sf6_button("TRIALS - (" .. sl("D") .. ")##fl_hc", SC.c1, actual_w) then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        imgui.same_line(0, sp)
        if SharedUI.sf6_button("TRIALS + (" .. sl("U") .. ")##fl_hc", SC.c2, actual_w) then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
    end
    imgui.same_line(0, sp)
    if not session.is_running then
        if SharedUI.sf6_button("RESET (" .. sl("L", "3") .. ")##fl_hc", SC.c3, actual_w) then reset_session_stats(); set_feedback(TEXTS.reset_done, COLORS.White, 1.0); hc_ticker("SESSION RESET") end
    else
        if SharedUI.sf6_button("STOP (" .. sl("L", "3") .. ")##fl_hc", SC.c3, actual_w) then reset_session_stats(); set_feedback("STOPPED", COLORS.Red, 1.0); hc_ticker("SESSION STOPPED") end
    end
    imgui.same_line(0, sp)
    if session.is_running then
        if SharedUI.sf6_button((session.is_paused and "RESUME" or "PAUSE") .. " (" .. sl("R", "4") .. ")##fl_hc", SC.c4, actual_w) then session.is_paused = not session.is_paused; hc_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED") end
    else
        if SharedUI.sf6_button("START (" .. sl("R", "4") .. ")##fl_hc", SC.c4, actual_w) then
            reset_session_stats()
            if user_config.session_mode == "timer" then
                session.time_rem = user_config.timer_minutes * 60
            end
            session.is_running = true; session.is_paused = false
            set_feedback(TEXTS.started, COLORS.Green, 1.0)
            hc_ticker("SESSION STARTED")
        end
    end
    imgui.same_line(w_width - cb_size - 10 - pad_x)
    local changed, new_val = imgui.checkbox("##close_hc", user_config.show_floating)
    if changed then user_config.show_floating = new_val; save_conf() end
    SharedUI.end_floating_window()
end

re.on_frame(function()
    -- Web bridge: export state & handle commands
    if _G.CurrentTrainerMode == 2 then
        if _G._tsm_web_cmd then
            local cmd = _G._tsm_web_cmd; _G._tsm_web_cmd = nil
            if cmd == "start" then reset_session_stats(); session.is_running = true; set_feedback("HERE WE GO!", 0xFF00FF00, 1.0); hc_ticker("SESSION STARTED") end
            if cmd == "stop" then reset_session_stats(); set_feedback("STOPPED", 0xFF0000FF, 1.0); hc_ticker("SESSION STOPPED") end
            if cmd == "reset" then reset_session_stats(); set_feedback("RESET", 0xFFFFFFFF, 1.0); hc_ticker("SESSION RESET") end
            if cmd == "pause" then session.is_paused = not session.is_paused; hc_ticker(session.is_paused and "SESSION PAUSED" or "SESSION RESUMED") end
            if cmd == "timer_up" then user_config.timer_minutes = math.min(60, user_config.timer_minutes + 1); reset_session_stats(); save_conf() end
            if cmd == "timer_down" then user_config.timer_minutes = math.max(1, user_config.timer_minutes - 1); reset_session_stats(); save_conf() end
            if cmd == "trials_up" then user_config.trial_count = math.min(200, user_config.trial_count + 10); reset_session_stats(); save_conf() end
            if cmd == "switch_mode" then user_config.session_mode = user_config.session_mode == "timer" and "trials" or "timer"; reset_session_stats(); save_conf(); hc_ticker(user_config.session_mode == "timer" and "TIMER MODE" or "TRIALS MODE") end
            if cmd == "trials_down" then user_config.trial_count = math.max(10, user_config.trial_count - 10); reset_session_stats(); save_conf() end
        end
        _G.TrainingSession_IsRunning = session.is_running
        _G.TrainingSession_IsPaused = session.is_paused
        _G.TrainingSession_Timer = user_config.timer_minutes
        _G.TrainingSession_Trials = user_config.trial_count
        _G.TrainingSession_Mode = user_config.session_mode
    end
    -- Hide if not actually in training (e.g. launched ranked from training)
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if DEPENDANT_ON_MANAGER and (_G.CurrentTrainerMode ~= 2) then return end
    if not tm then return end

    detection._live_tn = 0

    local should_update_logic = true
    local should_draw_hud = true

    if GS.in_pause_menu then
        if user_config.session_mode == "timer" and session.is_running and not session.is_paused then
            session.is_paused = true
            session._auto_paused = true
        end
        should_update_logic = false
        should_draw_hud = false
    else
        if session._auto_paused then
            session._auto_paused = false
        end
    end

    local cur_mode = _G.CurrentTrainerMode or 0

    if should_update_logic then
        update_logic_and_input()
    end

    -- [NEW] Only draw the HUD when allowed (hidden during pause menu)
    if should_draw_hud then
        draw_hud_overlay()
    end

    -- FLOATING SESSION WINDOW (hide during pause menu)
    if user_config.show_floating and _G.CurrentTrainerMode == 2 and not GS.in_pause_menu and not _G._tsm_hide_ui then
        draw_session_floating()
    end
end)

re.on_draw_ui(function()
    if DEPENDANT_ON_MANAGER and _G.CurrentTrainerMode ~= 2 then return end

    if imgui.tree_node("Hit Confirm Trainer (V7.3 Heavy DR Fail)") then

        if styled_header("--- SESSION CONFIGURATION ---", UI_THEME.hdr_session) then
            local c_fl, v_fl = imgui.checkbox("FLOATING WINDOW", user_config.show_floating)
            if c_fl then user_config.show_floating = v_fl; save_conf() end

            if user_config.show_floating then
                imgui.text_colored("Session controls are in the floating window.", COLORS.DarkGrey)
            else
                imgui.separator(); imgui.spacing()
                draw_session_buttons_docked()
            end
        end

        imgui.separator()
        if styled_header("--- DETECTION RULES ---", UI_THEME.hdr_rules) then
            local chg1, v1 = imgui.input_text("Trigger Moves (ID)", user_config.str_trigger_list); if chg1 then user_config.str_trigger_list = v1; refresh_tables(); save_conf() end
            local chg2, v2 = imgui.input_text("Confirm Moves (ID)", user_config.str_success_list); if chg2 then user_config.str_success_list = v2; refresh_tables(); save_conf() end
            local chgBrk, vBrk = imgui.input_text("Break List (Reset)", user_config.str_break_list); if chgBrk then user_config.str_break_list = vBrk; refresh_tables(); save_conf() end
            local chg3, v3 = imgui.input_text("Hit Damage Type List", user_config.str_dmg_hit_list); if chg3 then user_config.str_dmg_hit_list = v3; refresh_tables(); save_conf() end
            
            -- [NEW] Light Button Config Input
            local chgBtn, vBtn = imgui.input_text("Light Buttons (Bitmask)", user_config.str_light_btn_list); 
            if chgBtn then user_config.str_light_btn_list = vBtn; refresh_tables(); save_conf() end
            if imgui.is_item_hovered() then imgui.set_tooltip("16=LP (X/Square), 128=LK (A/Cross)") end
            
            local chg4, v4 = imgui.input_text("Block Damage Type List", user_config.str_dmg_block_list); if chg4 then user_config.str_dmg_block_list = v4; refresh_tables(); save_conf() end
        end
        
        imgui.separator()
        if styled_header("--- MATRIX COLUMNS CONFIG ---", UI_THEME.hdr_matrix) then
            if styled_button(session.is_logging and "STOP & EXPORT HISTORY (V3)" or "START LOGGING (MATRIX)", UI_THEME.btn_neutral) then
                if session.is_logging then export_detailed_history(); session.is_logging = false else session.is_logging = true; session.history_list = {}; session.history_map = {} end
            end
            if session.export_msg ~= "" then imgui.same_line(); imgui.text(session.export_msg) end

            imgui.separator()
            local cd, vd = imgui.checkbox("Show Matrix Debug", user_config.show_matrix_debug); if cd then user_config.show_matrix_debug = vd; save_conf() end
        end
        imgui.tree_pop()
    end
    
    if user_config.show_matrix_debug then
        imgui.set_next_window_size(Vector2f.new(1000, 600), 1 << 2)
        if imgui.begin_window("Diagnostic Matrix (V3)", true, 0) then
            
            -- [NEW] Debug Logic Monitor (TOP)
            imgui.text_colored("--- LOGIC MONITOR ---", COLORS.Orange)
            local log_txt = "DETECTED: " .. (session.debug_logic.is_light and "LIGHT (BUFFERED)" or "HEAVY/NORMAL")
            log_txt = log_txt .. " | TARGET COMBO: " .. session.debug_logic.target_combo
            log_txt = log_txt .. " | LIVE COMBO: " .. session.debug_logic.actual_combo
            log_txt = log_txt .. " | STATUS: " .. session.debug_logic.reason
            imgui.text(log_txt)
            
            if detection.dr_monitor.active then
                imgui.text_colored(string.format("DR MONITOR: %s (%s) Timer: %d Grace: %d", detection.dr_monitor.type, detection.dr_monitor.context, detection.dr_monitor.timer, detection.dr_monitor.gap_grace), COLORS.Cyan)
            end
            local go_info = guard_override.active and string.format("GUARD OVERRIDE: ON (%d frames left)", guard_override.timer) or "GUARD OVERRIDE: OFF"
            imgui.text_colored(go_info, guard_override.active and COLORS.Yellow or COLORS.Grey)
            if imgui.button("DUMP DR TRACE") and #detection.dr_trace > 0 then
                local lines = { "=== DR TRACE DUMP ===" }
                for _, l in ipairs(detection.dr_trace) do lines[#lines + 1] = l end
                lines[#lines + 1] = "=== MATRIX SNAPSHOT ==="
                for _, line in ipairs(detection.active_lines) do
                    local r = string.format("[%03d] p1_ft=%s p1_gau=%s p2_ft=%s p2_gau=%s dmg=%s hs=%s", line.idx, tostring(line.p1.frame_type), tostring(line.p1.main_gauge), tostring(line.p2.frame_type), tostring(line.p2.main_gauge), tostring(line.d), tostring(line.h))
                    if line.res ~= "" then r = r .. " <<< " .. line.res
                    elseif line.is_h then r = r .. " <<< HIT"
                    elseif line.is_b then r = r .. " <<< BLOCK" end
                    lines[#lines + 1] = r
                end
                json.dump_file("HitConfirm_DR_Trace.json", lines)
            end
            imgui.same_line(); imgui.text(string.format("(%d frames traced)", #detection.dr_trace))

            imgui.separator()

            imgui.text(string.format("DMG: %d | HS: %d | CLOCK: %d", detection.live_dmg, detection.live_hs, detection.abs_clock))
            imgui.same_line(); imgui.text_colored(string.format(" | COMBO: %d | TN: %d", detection.live_combo, detection._live_tn or 0), COLORS.Yellow)
            if detection.monitor.active then 
                imgui.text_colored("MONITOR ACTIVE: " .. (detection.monitor.type or "?"), COLORS.Green) 
                imgui.same_line(); imgui.text(string.format("(Target: >= %d)", detection.monitor.target_combo))
            end
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

local ui_hide_targets = { BattleHud_Timer = { { "c_main", "c_hud", "c_timer", "c_infinite" } } }
local apply_force_invisible; apply_force_invisible = function(control, path, depth, should_hide)
    local depth = depth or 1
    if depth > #path then control:call("set_ForceInvisible", should_hide); return end
    local child = control:call("get_Child")
    while child do
        local name = child:call("get_Name")
        if name and string.match(name, path[depth]) then apply_force_invisible(child, path, depth + 1, should_hide) end
        child = child:call("get_Next")
    end
end
