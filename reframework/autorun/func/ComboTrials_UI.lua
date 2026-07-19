-- =========================================================
-- ComboTrials_UI.lua - All ImGui UI code
-- Received shared context via init(). Registers re.on_frame and re.on_draw_ui.
-- =========================================================



local sdk = sdk
local imgui = imgui
local re = re
local json = json
local UIKit = require("func/UIKit")
local i18n = require("func/i18n")
i18n.register("combo_trials_ui", {
    en = {
        hdr_files = "--- COMBO TRIALS (Files & Playback) ---",
        hdr_d2d = "--- D2D VISUALIZER SETTINGS (Overlay) ---",
        hdr_exceptions = "--- EXCEPTION MANAGEMENT ---",
        hdr_debug = "--- DEBUG & SYSTEM INFO ---",
        enable_d2d = "Enable D2D Overlay",
        ignore_auto = "Ignore Automatic Actions (Gray)",
        show_combo_counter = "Show Combo Counter",
        show_modern = "Show Modern Notation (Modern controls)",
        use_bcm = "Use BCM Catalog (disable manual exceptions)",
        progression = "--- Trial Progression ---",
        auto_next = "Auto Next Combo On Success",
        auto_next_tip = "After a manual success: automatically load and start the next combo in the list.\nCompleted combos get a * marker in the dropdown. DEMO finishes never count.",
        auto_retry = "Auto Retry On Fail",
        auto_retry_tip = "After the fail banner: automatically reset the trial.\nDisabled: the trial stops, restart it manually.",
        clear_markers = "CLEAR COMPLETED MARKERS",
        live_log = "--- Live Log (During Record / Trial) ---",
        show_p1 = "Show Player 1",
        show_p2 = "Show Player 2",
        raw_input = "Raw Input",
        mirror = "Mirror",
        live_log_player = "--- LIVE LOG : PLAYER %d ---",
        btn_stop_save = "STOP & SAVE",
        btn_cancel = "CANCEL",
        btn_record_p1 = "RECORD P1",
        btn_record_p2 = "RECORD P2",
        btn_restart_demo = "RESTART DEMO",
        btn_quit_demo = "QUIT DEMO",
        btn_reset = "RESET",
        btn_record = "RECORD",
        btn_stop_trial = "STOP TRIAL",
        btn_demo = "DEMO",
        btn_demo_stun = "DEMO (STUN)",
        btn_start_trial = "START TRIAL",
        btn_start_trial_p1 = "START TRIAL P1",
        btn_stop_trial_p1 = "STOP TRIAL P1",
        btn_start_trial_p2 = "START TRIAL P2", btn_stop_trial_p2 = "STOP TRIAL P2",
        pos_any = "ANY POSITION", pos_exact = "EXACT POSITION", pos_mirror = "MIRROR POSITION", pos_none = "NO RESET",
        exc_show_hud = "Show HUD Overlay",
        exc_ignore = "IGNORE (Hide from log)",
        exc_force = "FORCE DISPLAY",
        exc_hold = "HOLD BUTTON (Charge tracking)",
        exc_validate_partial = "Validate Partial during Trial",
        exc_apply_common = "Apply to all characters (Common)",
        ctrl_filter_label = "Control filter",
        cf_all = "All", cf_classic = "Classic", cf_modern = "Modern", cf_auto = "Auto (current)",
    },
    zh = {
        hdr_files = "--- 连段训练（文件与回放）---",
        hdr_d2d = "--- D2D 可视化设置（叠加层）---",
        hdr_exceptions = "--- 例外管理 ---",
        hdr_debug = "--- 调试与系统信息 ---",
        enable_d2d = "启用 D2D 叠加层",
        ignore_auto = "忽略自动动作（灰色）",
        show_combo_counter = "显示连段计数",
        show_modern = "显示现代记法（现代操作）",
        use_bcm = "使用 BCM 目录（禁用手动例外）",
        progression = "--- 试炼进度 ---",
        auto_next = "成功后自动进入下一连段",
        auto_next_tip = "手动成功后：自动加载并开始列表中的下一个连段。\n已完成的连段在下拉列表中显示 * 标记。演示完成不计入。",
        auto_retry = "失败后自动重试",
        auto_retry_tip = "失败横幅后：自动重置连段。\n关闭时：连段停止，需手动重新开始。",
        clear_markers = "清除完成标记",
        live_log = "--- 实时日志（录制/试炼期间）---",
        show_p1 = "显示玩家 1",
        show_p2 = "显示玩家 2",
        raw_input = "原始输入",
        mirror = "镜像",
        live_log_player = "--- 实时日志：玩家 %d ---",
        btn_stop_save = "停止并保存",
        btn_cancel = "取消",
        btn_record_p1 = "录制 P1",
        btn_record_p2 = "录制 P2",
        btn_restart_demo = "重播演示",
        btn_quit_demo = "退出演示",
        btn_reset = "重置",
        btn_record = "录制",
        btn_stop_trial = "停止训练",
        btn_demo = "演示",
        btn_demo_stun = "演示（晕眩）",
        btn_start_trial = "开始训练",
        btn_start_trial_p1 = "开始训练 P1",
        btn_stop_trial_p1 = "停止训练 P1",
        btn_start_trial_p2 = "开始训练 P2", btn_stop_trial_p2 = "停止训练 P2",
        pos_any = "任意位置", pos_exact = "精确位置", pos_mirror = "镜像位置", pos_none = "不重置",
        exc_show_hud = "显示 HUD 叠加层",
        exc_ignore = "忽略（从日志隐藏）",
        exc_force = "强制显示",
        exc_hold = "蓄力按钮（蓄力追踪）",
        exc_validate_partial = "试炼中验证部分蓄力",
        exc_apply_common = "应用到所有角色（通用）",
        ctrl_filter_label = "操作过滤",
        cf_all = "全部", cf_classic = "经典", cf_modern = "现代", cf_auto = "自动（当前）",
    },
})
local T = i18n.scope("combo_trials_ui")

local M = {}
local ctx

-- Forward declarations resolved in init()
local d2d_cfg, trial_state, players, file_system
local common_exceptions, sf6_menu_state
local load_and_start_trial, start_recording, stop_recording_and_save, cancel_recording
local refresh_combo_list, restore_trial_vital, save_d2d_config, get_exc_filename
local ui_state


local dump_status = ""
local exc_status = ""

local _replay_status_p1 = "waiting"
local _replay_status_p2 = "waiting"
local _replay_save_clock = 0
local _replay_saved_clock = 0
local _replay_save_player = nil
local _replay_saved_fname_p1 = nil
local _replay_saved_fname_p2 = nil
local _prev_is_recording = false

-- Dynamic shortcuts: gamepad (FUNC+DIR) or keyboard (1/2/3/4)
-- Left-to-right positions: L=1, U=2, R=3, D=4 (4-btn) | L=1, R=2 (2-btn)
local SharedUI = require("func/Training_SharedUI")
local CT_KB_MAP = { L = "1", U = "2", R = "3", D = "4", A = "8" }
local function sc(pad_key, kb_override)
    return SharedUI.sc_label(pad_key, kb_override or CT_KB_MAP[pad_key])
end
-- Always returns the pad label (longest) for stable button width calculation
local function sc_max(pad_key)
    local dir_names = { D = "DOWN", U = "UP", R = "RIGHT", L = "LEFT", A = "CROSS" }
    return (SharedUI.get_func_name() or "") .. "+" .. (dir_names[pad_key] or pad_key)
end

-- =========================================================
-- UI THEME AND STYLES (Inspired by Training Hit Confirm)
-- =========================================================
local COLORS = UIKit.COLORS

local UI_THEME = {
    hdr_info    = UIKit.THEME.hdr_gold,
    hdr_session = UIKit.THEME.hdr_purple,
    hdr_rules   = UIKit.THEME.hdr_blue,
    hdr_matrix  = UIKit.THEME.hdr_green,
    btn_neutral = UIKit.THEME.btn_neutral,
    btn_green   = UIKit.THEME.btn_green,
    btn_red     = UIKit.THEME.btn_red,
    btn_orange  = UIKit.THEME.btn_easy,
}

-- Shortcut-openable and navigable combo dropdown (replaces imgui.combo for ##FilesP1)
local _dropdown_highlight_idx = nil
local _dropdown_scroll_needed = false

-- Native navigation for the dropdown (keyboard arrows + Enter, and controller
-- D-pad/left-stick with FUNC held), so the list can be browsed without binding
-- any hotkey. All edge-detected via a shared state table.
local _dropdown_kb_state = {}
local function _dropdown_bool_edge(down, key)
    down = down == true
    local prev = _dropdown_kb_state[key]
    _dropdown_kb_state[key] = down
    return down and not prev
end
local function _dropdown_kb_edge(vk, key)
    local ok, down = pcall(reframework.is_key_down, reframework, vk)
    return _dropdown_bool_edge(ok and down == true, key)
end

-- Up/down from the controller: HID button mask (D-pad / arcade stick) OR the
-- processed game input. Both published by the framework each frame.
-- bit 0x1 = up, bit 0x2 = down.
local function _dropdown_pad_updown()
    local m = (_G.TrainingPadMask or 0) | (_G.TrainingGameInputMask or 0)
    return (m & 1) ~= 0, (m & 2) ~= 0
end

local function combo_openable(label, current_idx, items, force_open, btn_width, completion_paths)
    local popup_id = label .. "_popup"
    local preview = (items and items[current_idx]) or "---"

    -- Completed-trial markers (SF6_TOOLS_CC progression feature)
    local mark_completed = nil
    if completion_paths and file_system and file_system.is_trial_completed then
        mark_completed = function(i)
            return completion_paths[i] and file_system.is_trial_completed(completion_paths[i])
        end
        if mark_completed(current_idx) then preview = "* " .. preview end
    end

    -- Capture button screen position before drawing it
    local win_pos = imgui.get_window_pos()
    local cursor_pos = imgui.get_cursor_pos()
    local btn_screen_x = win_pos.x + cursor_pos.x
    local btn_screen_y = win_pos.y + cursor_pos.y

    -- Full-width button with down arrow
    local w = btn_width or -1
    local clicked = imgui.button(preview .. "  \xe2\x96\xbc" .. label, Vector2f.new(w, 0))

    local should_open = force_open or clicked
    if should_open then
        -- Estimate popup height: item count * line height, capped
        local line_h = imgui.calc_text_size("W").y + 6
        local max_visible = 10
        local visible_count = math.min(#items, max_visible)
        local popup_h = (visible_count * line_h) + 8

        -- Position the popup just above the button, left-aligned
        imgui.set_next_window_pos(Vector2f.new(btn_screen_x, btn_screen_y - popup_h), 1)

        imgui.open_popup(popup_id)
        _dropdown_highlight_idx = current_idx
        _dropdown_scroll_needed = true
        if force_open then _G.ComboTrials_OpenDropdown = false end
    end

    -- Native navigation while the list is open (independent of hotkey binds).
    if _G.ComboTrials_DropdownOpen then
        -- Keyboard: arrows + Enter.
        if _dropdown_kb_edge(0x26, "up")    then _G.ComboTrials_DropdownNavUp = true end
        if _dropdown_kb_edge(0x28, "down")  then _G.ComboTrials_DropdownNavDown = true end
        if _dropdown_kb_edge(0x0D, "enter") then _G.ComboTrials_DropdownSelect = true end
        -- Controller: FUNC + D-pad/left-stick up/down.
        if _G.TrainingFuncHeld then
            local up, down = _dropdown_pad_updown()
            if _dropdown_bool_edge(up, "pad_up")     then _G.ComboTrials_DropdownNavUp = true end
            if _dropdown_bool_edge(down, "pad_down") then _G.ComboTrials_DropdownNavDown = true end
        else
            _dropdown_kb_state.pad_up = false
            _dropdown_kb_state.pad_down = false
        end
    end

    -- Shortcut navigation (flags set by the input handler)
    if _G.ComboTrials_DropdownNavUp then
        _G.ComboTrials_DropdownNavUp = false
        if _dropdown_highlight_idx and _dropdown_highlight_idx > 1 then
            _dropdown_highlight_idx = _dropdown_highlight_idx - 1
            _dropdown_scroll_needed = true
        end
    end
    if _G.ComboTrials_DropdownNavDown then
        _G.ComboTrials_DropdownNavDown = false
        if _dropdown_highlight_idx and _dropdown_highlight_idx < #items then
            _dropdown_highlight_idx = _dropdown_highlight_idx + 1
            _dropdown_scroll_needed = true
        end
    end

    local changed = false
    local new_idx = current_idx

    if imgui.begin_popup(popup_id) then
        _G.ComboTrials_DropdownOpen = true

        -- Shortcut selection (func+Cross/A or key 8)
        if _G.ComboTrials_DropdownSelect then
            _G.ComboTrials_DropdownSelect = false
            if _dropdown_highlight_idx then
                new_idx = _dropdown_highlight_idx
                changed = (new_idx ~= current_idx)
            end
            imgui.close_current_popup()
        end

        for i = 1, #items do
            local is_highlighted = (i == _dropdown_highlight_idx)
            local item_label = items[i]
            if mark_completed and mark_completed(i) then item_label = "* " .. item_label end
            if imgui.menu_item(item_label, "", is_highlighted, true) then
                new_idx = i
                changed = true
            end
            -- Scroll to highlighted item
            if is_highlighted and _dropdown_scroll_needed then
                pcall(imgui.set_scroll_here_y)
                _dropdown_scroll_needed = false
            end
        end
        imgui.end_popup()
    else
        _G.ComboTrials_DropdownOpen = false
        _dropdown_highlight_idx = nil
    end

    return changed, new_idx
end

local styled_button = UIKit.styled_button
local styled_header = UIKit.styled_header

-- Alphanumeric sort function for exceptions
local function sort_ids(dict)
    local keys = {}
    for k in pairs(dict) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        local num_a, num_b = tonumber(a), tonumber(b)
        if num_a and num_b then return num_a < num_b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- =========================================================
-- SHARED FUNCTION: TAB 1 CONTENT
-- =========================================================
local show_trial_overlay = true

local sf6_btn_font = nil
local custom_ui_font = nil
local hud_overlay_font = nil
local font_attempted = false

-- =========================================================
-- BUTTON FUNCTION (Chameleon: Neon or Native)
-- =========================================================
-- Dynamic colors from Training Script Manager (_G.TrainingSCColors)
-- Fallbacks in case ScriptManager hasn't loaded yet
local SC_FALLBACKS = {
    c1 = { text = 0xFF4444FF, base = 0x784444FF, hover = 0xA04444FF, active = 0xC84444FF, border = 0xFFFFFFFF },
    c2 = { text = 0xFF44FF44, base = 0x7844FF44, hover = 0xA044FF44, active = 0xC844FF44, border = 0xFFFFFFFF },
    c3 = { text = 0xFFFF4444, base = 0x78FF4444, hover = 0xA0FF4444, active = 0xC8FF4444, border = 0xFFFFFFFF },
    c4 = { text = 0xFF00A5FF, base = 0x7800A5FF, hover = 0xA000A5FF, active = 0xC800A5FF, border = 0xFFFFFFFF },
}
local function get_sc(key) local g = _G.TrainingSCColors; return (g and g[key]) or SC_FALLBACKS[key] end

-- P1=c1(red), TRIAL=c2(green), P2=c3(blue), SWITCH=c4(orange)
-- These are now functions, called at render time to get live colors
local function P1_COLORS()     return get_sc("c1") end
local function TRIAL_COLORS()  return get_sc("c2") end
local function P2_COLORS()     return get_sc("c3") end
local function SWITCH_COLORS() return get_sc("c4") end

local function styled_sf6_button(label, is_active, width, is_floating, is_disabled, color_override)
    width = width or 0
    -- Resolve color_override: call it if it's a function
    local co = color_override
    if type(co) == "function" then co = co() end

    -- DOCKED MODE (Native Debug Menu)
    if not is_floating then
        if co then
            imgui.push_style_color(5,  co.text)
            imgui.push_style_color(21, co.base)
            imgui.push_style_color(22, co.hover)
            imgui.push_style_color(23, co.active)
            imgui.push_style_color(0,  co.border)
            local clicked = imgui.button(label, Vector2f.new(width, 0))
            imgui.pop_style_color(5)
            return clicked
        else
            local style = is_active and UI_THEME.btn_green or UI_THEME.btn_neutral
            imgui.push_style_color(21, style.base)
            imgui.push_style_color(22, style.hover)
            imgui.push_style_color(23, style.active)
            local clicked = imgui.button(label, Vector2f.new(width, 0))
            imgui.pop_style_color(3)
            return clicked
        end
    end

    -- FLOATING MODE (SF6 Neon)
    if sf6_btn_font then imgui.push_font(sf6_btn_font) end

    if co then
        imgui.push_style_color(5, co.text)
        imgui.push_style_color(21, co.base)
        imgui.push_style_color(22, co.hover)
        imgui.push_style_color(23, co.active)
        imgui.push_style_color(0, co.border)
    elseif is_active then
        if label:upper():match("RECORD") or label:upper():match("SAVE") then
            imgui.push_style_color(5, 0xFFFFFFFF)
            imgui.push_style_color(21, 0xFF2222AA)
            imgui.push_style_color(22, 0xFF3333DD)
            imgui.push_style_color(23, 0xFF5555FF)
            imgui.push_style_color(0, 0xFFAAAAFF)
        else
            imgui.push_style_color(5, 0xFFFFFFFF)
            imgui.push_style_color(21, 0xFF228B22)
            imgui.push_style_color(22, 0xFF32CD32)
            imgui.push_style_color(23, 0xFF55FF55)
            imgui.push_style_color(0, 0xFFAAFFAA)
        end
    elseif is_disabled then
        imgui.push_style_color(5, 0xFFEEEEEE)
        imgui.push_style_color(21, 0xFF333333)
        imgui.push_style_color(22, 0xFF555555)
        imgui.push_style_color(23, 0xFF777777)
        imgui.push_style_color(0, 0xFF777777)
    else
        imgui.push_style_color(5, 0xFFFF33CC)
        imgui.push_style_color(21, 0xFF330055)
        imgui.push_style_color(22, 0xFF660088)
        imgui.push_style_color(23, 0xFF8822AA)
        imgui.push_style_color(0, 0xFFDDDDDD)
    end

    local clicked = imgui.button(label, Vector2f.new(width, 0))

    imgui.pop_style_color(5)
    if sf6_btn_font then imgui.pop_font() end
    return clicked
end

-- Utility function to calculate the width of the longest button
local function get_max_text_width(texts, is_floating)
    local use_custom = is_floating and sf6_btn_font
    if use_custom then imgui.push_font(sf6_btn_font) end
    local max_w = 0
    for _, text in ipairs(texts) do
        local w = imgui.calc_text_size(text).x
        if w > max_w then max_w = w end
    end
    if use_custom then imgui.pop_font() end
    return max_w + (use_custom and 30 or 15) -- Margins adjusted per mode
end



-- =========================================================
-- SWITCH POS LABEL (shows current state → next state)
-- =========================================================
local POS_LABELS = { function() return T("pos_any") end, function() return T("pos_exact") end, function() return T("pos_mirror") end }
local function switch_pos_label()
    local cur = d2d_cfg.forced_position_idx or 1
    local v = POS_LABELS[cur]
    if type(v) == "function" then return v() end
    return v or T("pos_none")
end

-- =========================================================
-- SINGLE LINE MODE
-- =========================================================
local function draw_single_line_content()
    local sw, sh = ctx.cached_sw, ctx.cached_sh
    local w_width = imgui.get_window_size().x
    local win_h = imgui.get_window_size().y
    local sp = 4 * (sh / 1080.0)
    local pad_x = sw * 0.01
    local pad_y = sh * 0.01

    -- Widths excluding P2 buttons
    local rec_btn_w_base = get_max_text_width({ T("btn_stop_save"), T("btn_cancel"), T("btn_record_p1"), T("btn_record_p2"), T("btn_reset"), T("btn_demo") }, true)
    local play_btn_w_base = get_max_text_width({ T("btn_start_trial_p1"), T("btn_stop_trial_p1"), T("pos_mirror") }, true)

    local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)

    local arrow_margin = 0

    -- Dynamic layout: buttons = fixed text size, dropdown = remaining space
    local usable_w = w_width - (pad_x * 2) - (sp * 5)

    -- 1. Buttons take their natural text width (all same size, based on longest label)
    local actual_btn_w = absolute_btn_w

    -- 2. Dropdown keeps same size, buttons expand to fill
    local dd_w = usable_w - (actual_btn_w * 4)
    local training_btn_w = (usable_w - dd_w) / 3

    local dynamic_rec_w = actual_btn_w
    local is_demo_active_early = (ctx.demo_state and ctx.demo_state.is_playing)
    local is_replay_mode = (_G.IsInReplay == true) or (_G.FlowMapID == 10) or (_G.IsInBattleHub == true)
    if trial_state.is_recording or is_demo_active_early or is_replay_mode then
        -- In record/demo/replay/spectate mode, distribute the massive 4-button space into 2
        dynamic_rec_w = (actual_btn_w * 4 + sp * 2) / 2
    end
    -- Fixed width for replay: always based on idle layout
    -- dd_P1 + sp + btn + sp + btn + sp + dd_P2 = usable_w
    local replay_btn_w = actual_btn_w
    local replay_dd_w = (usable_w - (replay_btn_w * 2) - (sp * 3)) / 2
    if replay_dd_w < 50 then replay_dd_w = 50 end

    -- No progress_bar background (causes ghost in ranked mode)

    imgui.set_cursor_pos(Vector2f.new(pad_x + arrow_margin, pad_y))

    local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
    local is_replay_rec_p1 = (trial_state.is_recording and trial_state.recording_player == 0 and is_replay_mode)
    local is_replay_rec_p2 = (trial_state.is_recording and trial_state.recording_player == 1 and is_replay_mode)

    -- Helper: draw a dropdown
    local function draw_dd(id, display_list, selected_idx, width, on_change)
        if #display_list == 0 then
            imgui.push_item_width(width)
            imgui.combo("##Empty" .. id, 1, { "No files" })
            imgui.pop_item_width()
        else
            local changed, new_idx = combo_openable("##" .. id, selected_idx or 1, display_list, false, width)
            if changed then on_change(new_idx) end
        end
    end

    -- === STATUS ENGINE (shared by replay and training) ===

    -- Pick up cancel flag from shortcut handler
    if _G.ComboTrials_ReplayCancelPlayer ~= nil then
        local cp = _G.ComboTrials_ReplayCancelPlayer
        _G.ComboTrials_ReplayCancelPlayer = nil
        if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
        _replay_saved_clock = os.clock()
    end

    -- Pick up save flag from shortcut handler
    if _G.ComboTrials_ReplaySavePlayer ~= nil then
        _replay_save_player = _G.ComboTrials_ReplaySavePlayer
        _G.ComboTrials_ReplaySavePlayer = nil
    end
    if _G.ComboTrials_ReplayCanceled ~= nil then
        local cp = _G.ComboTrials_ReplayCanceled
        _G.ComboTrials_ReplayCanceled = nil
        if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
        _replay_saved_clock = os.clock()
    end

    -- Detect recording stop (transition is_recording true->false), skip if canceled
    if _prev_is_recording and not trial_state.is_recording then
        local cur_st = (_replay_save_player == 0) and _replay_status_p1 or _replay_status_p2
        if cur_st ~= "canceled" then
            _replay_save_clock = os.clock()
            _replay_saved_clock = 0
            if _replay_save_player == 0 then _replay_status_p1 = "saving"
            elseif _replay_save_player == 1 then _replay_status_p2 = "saving" end
        end
    end
    _prev_is_recording = trial_state.is_recording

    -- Update saving/saved animation
    local now = os.clock()
    for _, pi in ipairs({0, 1}) do
        local st = (pi == 0) and _replay_status_p1 or _replay_status_p2
        if st == "saving" and _replay_save_clock > 0 then
            local elapsed = now - _replay_save_clock
            if elapsed >= 1.0 then
                if pi == 0 then _replay_status_p1 = "saved" else _replay_status_p2 = "saved" end
                _replay_saved_clock = now
                local fn = _G.ComboTrials_LastSavedFilename
                if fn then
                    fn = fn:gsub("%.json$", "")
                    if pi == 0 then _replay_saved_fname_p1 = fn else _replay_saved_fname_p2 = fn end
                    _G.ComboTrials_LastSavedFilename = nil
                end
            end
        elseif st == "saved" and _replay_saved_clock > 0 then
            if now - _replay_saved_clock >= 3.0 then
                if pi == 0 then _replay_status_p1 = "waiting" else _replay_status_p2 = "waiting" end
            end
        elseif st == "canceled" and _replay_saved_clock > 0 then
            if now - _replay_saved_clock >= 1.0 then
                if pi == 0 then _replay_status_p1 = "waiting" else _replay_status_p2 = "waiting" end
            end
        end
    end

    -- Update status based on current recording state
    if trial_state.is_recording then
        if trial_state.recording_player == 0 then _replay_status_p1 = "recording"
        elseif trial_state.recording_player == 1 then _replay_status_p2 = "recording" end
    end

    -- Render status label helper
    local function replay_status_label(player_idx, width)
        local st = (player_idx == 0) and _replay_status_p1 or _replay_status_p2
        local label, color
        if st == "waiting" then
            label = "WAITING FOR P" .. (player_idx + 1) .. " RECORDING"
            color = COLORS.DarkGrey
        elseif st == "recording" then
            label = "RECORDING STARTED"
            color = COLORS.Red
        elseif st == "saving" then
            local dots_count = math.floor((now - _replay_save_clock) / 0.333) % 3 + 1
            label = "SAVING RECORDING" .. string.rep(".", dots_count)
            color = COLORS.Orange
        elseif st == "saved" then
            local fn = (player_idx == 0) and _replay_saved_fname_p1 or _replay_saved_fname_p2
            if fn then
                label = "SAVED AS " .. fn
            else
                label = "RECORDING SAVED !"
            end
            color = COLORS.Green
        elseif st == "canceled" then
            label = "RECORDING CANCELED"
            color = COLORS.Orange
        else
            label = "---"
            color = COLORS.DarkGrey
        end
        imgui.push_style_color(0, color)
        imgui.button(label .. "##status_p" .. player_idx, Vector2f.new(width, 0))
        imgui.pop_style_color(1)
    end

    if is_replay_mode then
        -- === REPLAY : status P1 | btn | btn | status P2 ===
        replay_status_label(0, replay_dd_w)
        imgui.same_line(0, sp)
        if trial_state.is_recording then
            if styled_sf6_button(T("btn_stop_save"), true, replay_btn_w, true, false, TRIAL_COLORS) then _replay_save_player = trial_state.recording_player; stop_recording_and_save() end
            imgui.same_line(0, sp)
            if styled_sf6_button(T("btn_cancel"), false, replay_btn_w, true, false, P1_COLORS) then
                local cp = trial_state.recording_player
                cancel_recording()
                if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
                _replay_saved_clock = os.clock()
            end
        else
            if styled_sf6_button(T("btn_record_p1"), false, replay_btn_w, true, false, P1_COLORS) then _replay_save_player = 0; start_recording(0) end
            imgui.same_line(0, sp)
            if styled_sf6_button(T("btn_record_p2"), false, replay_btn_w, true, false, P2_COLORS) then _replay_save_player = 1; start_recording(1) end
        end
        imgui.same_line(0, sp)
        replay_status_label(1, replay_dd_w)
    elseif trial_state.is_recording or (_replay_status_p1 ~= "waiting" and not is_replay_mode) then
        -- === TRAINING RECORD (or post-record animation) ===
        if trial_state.is_recording then
            _replay_status_p1 = "recording"
            _replay_save_player = trial_state.recording_player or 0
        end

        replay_status_label(0, dd_w)
        imgui.same_line(0, sp)
        if trial_state.is_recording then
            if styled_sf6_button(T("btn_stop_save"), true, dynamic_rec_w, true, false, TRIAL_COLORS) then _replay_save_player = trial_state.recording_player; stop_recording_and_save() end
            imgui.same_line(0, sp)
            if styled_sf6_button(T("btn_cancel"), false, dynamic_rec_w, true, false, P1_COLORS) then
                local cp = trial_state.recording_player
                cancel_recording()
                if cp == 0 then _replay_status_p1 = "canceled" else _replay_status_p2 = "canceled" end
                _replay_saved_clock = os.clock()
            end
        end
    elseif is_demo_active then
        -- === DEMO ===
        if #file_system.saved_combos_display_p1 == 0 then
            imgui.push_item_width(dd_w)
            imgui.combo("##EmptyP1", 1, { "No P1 files" })
            imgui.pop_item_width()
        else
            local should_open = (_G.ComboTrials_OpenDropdown == true)
            local f1_changed, new_idx1 = combo_openable("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1, should_open, dd_w, file_system.saved_combos_paths_p1)
            if f1_changed then
                file_system.selected_file_idx_p1 = new_idx1
                load_and_start_trial(0)
            end
        end
        imgui.same_line(0, sp)
        if styled_sf6_button(T("btn_restart_demo"), false, dynamic_rec_w, true, false, TRIAL_COLORS) then
            if ctx.start_demo then ctx.start_demo() end
        end
        imgui.same_line(0, sp)
        if styled_sf6_button(T("btn_quit_demo"), false, dynamic_rec_w, true, false, P1_COLORS) then
            if ctx.stop_demo then ctx.stop_demo() end
        end
    else
        -- Normal / Playing mode: P1 dropdown + 3 buttons
        if #file_system.saved_combos_display_p1 == 0 then
            imgui.push_item_width(dd_w)
            imgui.combo("##EmptyP1", 1, { "No P1 files" })
            imgui.pop_item_width()
        else
            local should_open = (_G.ComboTrials_OpenDropdown == true)
            local f1_changed, new_idx1 = combo_openable("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1, should_open, dd_w, file_system.saved_combos_paths_p1)
            if f1_changed then
                file_system.selected_file_idx_p1 = new_idx1
                load_and_start_trial(0)
            end
        end
        imgui.same_line(0, sp)
        local btn_w = trial_state.is_playing and actual_btn_w or training_btn_w
        if trial_state.is_playing then
            if styled_sf6_button(T("btn_reset"), false, btn_w, true, false, P1_COLORS) then
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                ctx.apply_forced_position()
            end
        else
            if styled_sf6_button(T("btn_record"), false, btn_w, true, false, P1_COLORS) then start_recording(0) end
        end

        imgui.same_line(0, sp)
        if trial_state.is_playing then
            if styled_sf6_button(T("btn_stop_trial"), true, btn_w, true, false, TRIAL_COLORS) then
                trial_state.is_playing = false
            end
        elseif not trial_state.is_recording then
            local is_p1_active = (trial_state.is_playing and trial_state.playing_player == 0)
            if styled_sf6_button(is_p1_active and T("btn_stop_trial") or T("btn_start_trial"), is_p1_active, btn_w, true, false, TRIAL_COLORS) then
                if is_p1_active then trial_state.is_playing = false
                else load_and_start_trial(0) end
            end
        end

        imgui.same_line(0, sp)
        if trial_state.is_playing then
            if styled_sf6_button(switch_pos_label(), false, btn_w, true, false, SWITCH_COLORS) then
                d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
                if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
                ctx.save_d2d_config()
                ctx.apply_forced_position()
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                if ctx.reset_visuals then ctx.reset_visuals() end
            end
            imgui.same_line(0, sp)
            local has_piyo = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].has_piyo
            local has_raw = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].raw_inputs
            if has_piyo and not has_raw and not _G._allow_stun_demo then
                imgui.push_style_color(21, 0xFF444444)
                imgui.push_style_color(22, 0xFF444444)
                imgui.push_style_color(23, 0xFF444444)
                styled_sf6_button(T("btn_demo_stun"), false, btn_w, true, false, { base = 0x78444444, hover = 0x78444444, active = 0x78444444, text = 0xFF888888, border = 0xFF666666 })
                imgui.pop_style_color(3)
            else
                if styled_sf6_button(T("btn_demo"), false, btn_w, true, false, P2_COLORS) then
                    if ctx.start_demo then ctx.start_demo() end
                end
            end
        else
            if styled_sf6_button(switch_pos_label(), false, btn_w, true, false, SWITCH_COLORS) then
                d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
                if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
                ctx.save_d2d_config()
            end
        end

    end
end

local function draw_combo_trials_content(is_floating)
    local sw, sh = ctx.cached_sw, ctx.cached_sh
    local size = imgui.get_window_size()
    local w_width = (size.x > 50) and size.x or (sw * 0.44)

    local rec_btn_w_base = get_max_text_width({ T("btn_stop_save"), T("btn_cancel"), T("btn_record_p1"), T("btn_record_p2"), T("btn_reset"), T("btn_demo") }, is_floating)
    local play_btn_w_base = get_max_text_width({ T("btn_start_trial_p1"), T("btn_stop_trial_p1"), T("pos_mirror") }, is_floating)

    local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)
    local spacing_cols = 20 * (sh / 1080.0)
    local spacing_x = 8.0

    local min_inline_w = 150 + (absolute_btn_w * 2) + (spacing_cols * 3)
    local mode_all_inline = w_width >= min_inline_w
    local mode_all_stacked = w_width < (absolute_btn_w * 1.5)
    local mode_col2_3_inline = not mode_all_inline and not mode_all_stacked

    local rec_btn_w = absolute_btn_w
    local play_btn_w = absolute_btn_w

    local col3_x, col2_x, col1_w

    if mode_all_inline then
        if trial_state.is_recording then
            -- Record mode: Column 3 empty, Column 2 takes all remaining space
            col1_w = math.max(150, (w_width - (spacing_cols * 3)) / 3)
            col2_x = col1_w + spacing_cols
            col3_x = w_width -- Ignored
            rec_btn_w = w_width - col2_x - spacing_cols
        else
            col3_x = math.max(w_width - play_btn_w - spacing_cols, 10)
            col2_x = math.max(col3_x - rec_btn_w - spacing_cols, 10)
            col1_w = math.max(col2_x - spacing_cols, 150)
        end
    else
        col1_w = w_width - (40 * (sh / 1080.0))
        if mode_col2_3_inline then
            if trial_state.is_recording then
                -- Make recording buttons dynamically fill the entire column width
                rec_btn_w = col1_w
            else
                local half_w = (col1_w - spacing_x) / 2
                rec_btn_w = half_w
                play_btn_w = half_w
            end
        elseif mode_all_stacked then
            rec_btn_w = col1_w
            play_btn_w = col1_w
        end
    end

    -- =====================================
    -- Column 1: MANAGEMENT
    -- =====================================
    imgui.begin_group()
    if not is_floating then imgui.text_colored("1. MANAGEMENT", COLORS.Cyan) end

    -- DROPDOWN COMBO FILES (full width)
    if #file_system.saved_combos_display_p1 == 0 then
        imgui.push_item_width(col1_w)
        imgui.combo("##EmptyP1", 1, { "No P1 files" })
        imgui.pop_item_width()
    else
        local should_open = (_G.ComboTrials_OpenDropdown == true)
        local f1_changed, new_idx1 = combo_openable("##FilesP1", file_system.selected_file_idx_p1, file_system.saved_combos_display_p1, should_open, col1_w, file_system.saved_combos_paths_p1)
        if f1_changed then
            file_system.selected_file_idx_p1 = new_idx1
            load_and_start_trial(0)
        end
    end

    imgui.end_group()

    -- =====================================
    -- Column 2: RECORDING
    -- =====================================
    if mode_all_inline then imgui.same_line(col2_x) else imgui.spacing(); imgui.separator(); imgui.spacing() end

    imgui.begin_group()
    if not is_floating then imgui.text_colored("2. RECORDING", COLORS.White) end
    
    local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
    if trial_state.is_playing or is_demo_active then
        if styled_sf6_button(T("btn_reset"), false, rec_btn_w, is_floating) then
            if is_demo_active then
                if ctx.start_demo then ctx.start_demo() end
            else
                ctx.reset_trial_steps_and_load(trial_state.playing_player)
                ctx.apply_forced_position()
            end
        end
        if mode_all_stacked then imgui.spacing() end
        local has_piyo2 = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].has_piyo
        local has_raw2 = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].raw_inputs
        if has_piyo2 and not has_raw2 and not is_demo_active and not _G._allow_stun_demo then
            imgui.push_style_color(21, 0xFF444444)
            imgui.push_style_color(22, 0xFF444444)
            imgui.push_style_color(23, 0xFF444444)
            styled_sf6_button(T("btn_demo_stun"), false, rec_btn_w, is_floating, false, { base = 0x78444444, hover = 0x78444444, active = 0x78444444, text = 0xFF888888, border = 0xFF666666 })
            imgui.pop_style_color(3)
        elseif styled_sf6_button(T("btn_demo"), is_demo_active, rec_btn_w, is_floating, false, P2_COLORS) then
            if is_demo_active then
                if ctx.stop_demo then ctx.stop_demo() end
            else
                if ctx.start_demo then ctx.start_demo() end
            end
        end
    elseif trial_state.is_recording then
        if styled_sf6_button(T("btn_stop_save"), true, rec_btn_w, is_floating, false, TRIAL_COLORS) then
            stop_recording_and_save()
        end

        -- Always force stacking with spacing in windowed mode
        imgui.spacing()

        if styled_sf6_button(T("btn_cancel"), false, rec_btn_w, is_floating, false, P1_COLORS) then
            cancel_recording()
        end
    else
        if styled_sf6_button(T("btn_record_p1"), false, rec_btn_w, is_floating, false, P1_COLORS) then
            start_recording(0)
        end
        if mode_all_stacked then imgui.spacing() end
        if styled_sf6_button(T("btn_record_p2"), false, rec_btn_w, is_floating, false, P2_COLORS) then
            start_recording(1)
        end
    end
    imgui.end_group()

    -- =====================================
    -- Column 3: PLAYBACK
    -- =====================================
    if mode_all_stacked then imgui.spacing(); imgui.separator(); imgui.spacing()
    elseif mode_col2_3_inline then imgui.same_line(0, spacing_x)
    else imgui.same_line(col3_x) end

    imgui.begin_group()
    if not is_floating then imgui.text_colored("3. PLAYBACK (TRIAL)", COLORS.White) end

    if trial_state.is_playing or is_demo_active then
        if styled_sf6_button(T("btn_stop_trial"), true, play_btn_w, is_floating, false, TRIAL_COLORS) then
            trial_state.is_playing = false
            if ctx.stop_demo then ctx.stop_demo() end
        end
    elseif not trial_state.is_recording then
        local is_p1_active = (trial_state.is_playing and trial_state.playing_player == 0)
        if styled_sf6_button(is_p1_active and T("btn_stop_trial_p1") or T("btn_start_trial_p1"), is_p1_active, play_btn_w, is_floating, false, TRIAL_COLORS) then
            if is_p1_active then trial_state.is_playing = false
            else load_and_start_trial(0) end
        end
    end
    
    if mode_all_stacked then imgui.spacing() end
    
    -- SWITCH POS (Hidden during recording)
    if not trial_state.is_recording then
        if styled_sf6_button(switch_pos_label(), false, play_btn_w, is_floating, false, SWITCH_COLORS) then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            ctx.save_d2d_config()
            
            local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
            -- Only physically apply position if a trial or demo is active
            if is_demo_active or trial_state.is_playing then
                ctx.apply_forced_position()
                if is_demo_active then
                    if ctx.start_demo then ctx.start_demo() end
                else
                    if ctx.reset_trial_steps_and_load then ctx.reset_trial_steps_and_load(trial_state.playing_player) end
                end
                if ctx.reset_visuals then ctx.reset_visuals() end
            end
        end
    end
    imgui.end_group()
    imgui.spacing()
end

-- =========================================================
-- STANDALONE FLOATING WINDOW RENDERING (In re.on_frame)
-- =========================================================
-- sf6_menu_state is received from ctx in init()

local function _ctui_get_x(v) return v.x end
local function _ctui_get_y(v) return v.y end

local function get_imgui_screen_size()
    local result = imgui.get_display_size()
    local w, h = 0, 0
    if type(result) == "userdata" then
        local ok, x = pcall(_ctui_get_x, result)
        local ok2, y = pcall(_ctui_get_y, result)
        if ok and ok2 then
            w = x; h = y
        else
            w = result.w or 0; h = result.h or 0
        end
    elseif type(result) == "number" then
        w, h = imgui.get_display_size()
    end
    return w, h
end

local ui_dirty = false
local ui_save_timer = 0
local last_sw, last_sh = 0, 0
local res_cooldown = 0
local force_float_resize = 0

local _was_bars_drawn = true

local function _ctui_flush_trial_display()
    local ts = ctx and ctx.trial_state
    if ts then
        ts.is_playing = false
        ts.sequence = {}
        ts.current_step = 1
    end
end

re.on_frame(function()
    -- Detect return from ranked: flush combo display
    local bars_now = _G.TrainingBarsDrawn
    if bars_now and not _was_bars_drawn then
        pcall(_ctui_flush_trial_display)
    end
    _was_bars_drawn = bars_now

    -- Scene gate (SF6_TOOLS_CC fix): TrainingModeActive catches the case where
    -- a match found from training leaves CurrentTrainerMode stale at 4
    local in_replay_ctx = (_G.FlowMapID == 10) or _G.IsInReplay
    local in_training_ctx = (_G.CurrentTrainerMode == 4) and (_G.TrainingModeActive ~= false)
    if not in_replay_ctx and not in_training_ctx then
        sf6_menu_state.active = false
        _G.ComboTrials_HideNativeHUD = false
        _G.ComboTrialsD2DEnabled = false
        _G.ComboTrials_D2D_Beat = false
        return
    end

    local is_game_active = false
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local b = pm:get_field("_CurrentPauseTypeBit")
        if b == 64 or b == 2112 then is_game_active = true end
    end
    _G.ComboTrialsD2DEnabled = is_game_active
    -- Per-frame beat consumed by the D2D callback (Distance-Viewer-style
    -- self-clearing). No beat set (on_frame paused/gated) => D2D draws nothing.
    -- Also set in replay so the collapse arrows keep drawing there.
    _G.ComboTrials_D2D_Beat = (is_game_active == true) or (in_replay_ctx == true)

    -- Use exact ImGui API for window positioning
    local sw, sh = get_imgui_screen_size()
    if sw == nil or sh == nil or sw <= 0 or sh <= 0 then return end

    -- DETECTION AND COOLDOWN
    local res_changed = false
    if last_sw ~= sw or last_sh ~= sh then
        if last_sw ~= 0 then
            res_changed = true
            res_cooldown = 5 -- Freeze position for 5 frames
        end
        last_sw = sw
        last_sh = sh
    end

    if res_cooldown > 0 then res_cooldown = res_cooldown - 1 end
    local is_resizing = (res_changed or res_cooldown > 0)

    if not d2d_cfg.float_pos then d2d_cfg.float_pos = { x = 0.0, y = 0.2 } end
    if not d2d_cfg.float_size then d2d_cfg.float_size = { w = 1.0, h = 0.20 } end
    -- Force full screen width
    d2d_cfg.float_pos.x = 0.0
    d2d_cfg.float_size.w = 1.0

    -- FONT RELOAD (Only on the exact frame of change)
    if not font_attempted or res_changed then
        local font_scale = sh / 1080.0
        pcall(function()
            custom_ui_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf",
                math.max(10, math.floor(20 * font_scale)))
        end)
        pcall(function() sf6_btn_font = imgui.load_font("SF6_college.ttf", math.max(10, math.floor(22 * font_scale))) end)
        local hud_size = math.max(10, math.floor((d2d_cfg.hud_font_size or 20) * font_scale))
        pcall(function() hud_overlay_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf", hud_size) end)
        font_attempted = true
    end

    -- =========================================================
    -- HUD OVERLAY: Combo Stats on native lines (HitConfirm pattern)
    -- =========================================================
    -- Determine whether to show our HUD or let the game display native info
    local show_our_hud = false
    local line1, line2, line3 = "", "", ""
    local col1, col2, col3 = 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF

    if is_game_active and d2d_cfg.hud_show then
        -- Shared logic to determine line 1 (Trial Title) and its color (IMGUI ABGR format)
        if trial_state.success_timer > 0 then
            line1 = "!!! SUCCESS !!!"; col1 = 0xFF00FF00
            show_our_hud = true
        elseif trial_state.is_playing and trial_state.fail_timer and trial_state.fail_timer > 0 then
            line1 = "[ " .. (trial_state.fail_reason or "FAILED") .. " ]"
            col1 = (trial_state.fail_reason and string.match(trial_state.fail_reason, "TOO")) and 0xFF0000FF or
                0xFF00A5FF
            show_our_hud = true
        elseif trial_state.is_recording then
            line1 = "[ RECORDING P" .. tostring(trial_state.recording_player + 1) .. " ]"; col1 = 0xFF5555FF
            show_our_hud = true
        elseif trial_state.is_playing then
            local is_demo_active = (ctx.demo_state and ctx.demo_state.is_playing)
            local demo_countdown = (is_demo_active and ctx.demo_state.countdown) and math.ceil(ctx.demo_state.countdown / 20) or 0

            if demo_countdown > 0 then
                line1 = "[ DEMO STARTING ]"
                col1 = 0xFFFFFF00 -- Cyan
            else
                local total_steps = #trial_state.sequence
                if total_steps > 0 then
                    -- Use delayed visual step
                    local display_step = trial_state.ui_visual_step or 1
                    local current = math.min(display_step, total_steps)
                    line1 = string.format("[ ACTION %d / %d ]", current, total_steps)
                else
                    line1 = "[ TRIAL FOR P" .. tostring(trial_state.playing_player + 1) .. " ]"
                end

                if trial_state.floating_info then
                    line1 = line1 .. "  |  " .. trial_state.floating_info
                    col1 = trial_state.floating_color or 0xFF00FFFF
                else
                    col1 = 0xFF00FFFF -- Yellow by default
                end
            end
            show_our_hud = true
        end

        if trial_state.is_recording and trial_state._rec_gauges then
            -- RECORDING MODE: Live display of current deltas
            local rg    = trial_state._rec_gauges
            local dmg   = math.max(0, (rg.victim_hp or 0) - (rg.min_victim_hp or rg.victim_hp or 0))
            local dr    = math.max(0, (rg.attacker_drive or 0) - (rg.min_atk_drive or rg.attacker_drive or 0))
            local sa    = math.max(0, (rg.attacker_super or 0) - (rg.min_atk_super or rg.attacker_super or 0))

            -- Line 2: Live damage
            line2       = string.format("DAMAGE: %d", dmg)

            -- Line 3: Live drive & super
            local parts = {}
            if dr > 0 then table.insert(parts, string.format("DRIVE: -%.1f", dr / 10000)) end
            if sa > 0 then table.insert(parts, string.format("SUPER: -%.1f", sa / 10000)) end
            line3 = #parts > 0 and table.concat(parts, "     ") or ""
        elseif trial_state.is_playing and #trial_state.sequence > 0 and trial_state.sequence[1] then
            -- TRIAL MODE / LOADED SEQUENCE: Display saved stats
            local cs = trial_state.sequence[1].combo_stats

            if cs then
                line2 = cs.damage and cs.damage > 0 and string.format("DAMAGE: %d", cs.damage) or "DAMAGE: ---"

                local parts = {}
                if cs.drive_used and cs.drive_used > 0 then
                    table.insert(parts, string.format("DRIVE: -%.1f", cs.drive_used / 10000))
                end
                if cs.super_used and cs.super_used > 0 then
                    table.insert(parts, string.format("SUPER: -%.1f", cs.super_used / 10000))
                end
                line3 = #parts > 0 and table.concat(parts, "     ") or ""
            else
                line2 = "DAMAGE: ---"
            end
        end
        -- else: neither recording nor trial -> show_our_hud stays false -> native info visible
    end

    -- Global flag read by Training_ScriptManager to hide/show native info
    _G.ComboTrials_HideNativeHUD = show_our_hud

    if show_our_hud then
        imgui.push_style_color(2, 0)
        imgui.set_next_window_pos(Vector2f.new(0, 0))
        imgui.set_next_window_size(Vector2f.new(sw, sh))

        local hud_flags = 1 | 2 | 4 | 8 | 128 | 512 | 2048

        if imgui.begin_window("ComboTrials_HUD", true, hud_flags) then
            if hud_overlay_font then imgui.push_font(hud_overlay_font) end

            local cx = sw / 2
            local game_h = sw * 9 / 16
            local lb_off = (sh > game_h) and ((sh - game_h) / 2) or 0
            local cy = lb_off + game_h / 2
            local line1_y = cy + (d2d_cfg.hud_global_y * game_h)
            local line2_y = line1_y + (d2d_cfg.hud_spacing_y * game_h)
            local line3_y = line2_y + (d2d_cfg.hud_spacing_y * game_h)

            local outline_color = 0xFF444444
            local outline_thick = 0.1

            local function draw_centered(text, y, color)
                if text == "" then return end
                local safe = string.gsub(text, "%%", "%%%%")
                local w = imgui.calc_text_size(safe).x
                local x = cx - (w / 2)
                for dx = -outline_thick, outline_thick do
                    for dy = -outline_thick, outline_thick do
                        if dx ~= 0 or dy ~= 0 then
                            imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                            imgui.text_colored(safe, outline_color)
                        end
                    end
                end
                imgui.set_cursor_pos(Vector2f.new(x, y))
                imgui.text_colored(safe, color)
            end

            draw_centered(line1, line1_y, col1)
            draw_centered(line2, line2_y, col2)
            draw_centered(line3, line3_y, col3)

            if hud_overlay_font then imgui.pop_font() end
            imgui.end_window()
        end
        imgui.pop_style_color(1)
    end

    if not is_game_active then sf6_menu_state.active = false end
    if show_trial_overlay and is_game_active then
        sf6_menu_state.active = true

        -- Collapse toggle (replay only)
        local is_replay_ctx = (_G.IsInReplay == true) or (_G.IsInBattleHub == true)
        if _G._ct_bar_collapsed == nil then _G._ct_bar_collapsed = false end
        if not is_replay_ctx then _G._ct_bar_collapsed = false end

        if not d2d_cfg.bar_width_pct then d2d_cfg.bar_width_pct = 1.0 end
        local target_w = sw * d2d_cfg.bar_width_pct
        local target_h = sh * 0.0444
        local target_x = (sw - target_w) * 0.5

        -- Publish geometry for D2D arrows (replay only)
        if is_replay_ctx then
            _G._ct_bar_geometry = { x = target_x, y = sh - target_h, w = target_w, h = target_h }
        else
            _G._ct_bar_geometry = nil
        end

        if _G._tsm_hide_ui or (_G._ct_bar_collapsed and is_replay_ctx) then
            _G.TrainingBarsDrawn = true
            sf6_menu_state.active = false
            return
        end

        imgui.push_style_color(2, 0xFC800024)   -- WindowBg (dark purple)
        imgui.push_style_color(5, 0xFFEF51EF)   -- Border (neon pink)
        imgui.push_style_color(7, 0x00000000)   -- FrameBg transparent
        imgui.push_style_color(8, 0x00000000)   -- TitleBg transparent
        imgui.push_style_var(4, 1.0)            -- WindowBorderSize
        imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))

        imgui.set_next_window_size(Vector2f.new(target_w, target_h), 1)
        imgui.set_next_window_pos(Vector2f.new(target_x, sh - target_h), 1)

        if custom_ui_font then imgui.push_font(custom_ui_font) end

        local visible = imgui.begin_window("ComboTrialsFloating", true, 15)

        local pos = imgui.get_window_pos()
        local size = imgui.get_window_size()
        _G.TrainingBarsDrawn = true

        -- SAVE BLOCKED DURING COOLDOWN (Prevents coordinate corruption)
        if size.x > 0 and size.y > 0 and not is_resizing then
            local norm_x = pos.x / sw
            local norm_y = pos.y / sh
            local norm_w = size.x / sw
            local norm_h = size.y / sh

            if math.abs(norm_x - d2d_cfg.float_pos.x) > 0.001 or math.abs(norm_y - d2d_cfg.float_pos.y) > 0.001 or
                math.abs(norm_w - d2d_cfg.float_size.w) > 0.001 or math.abs(norm_h - d2d_cfg.float_size.h) > 0.001 then
                d2d_cfg.float_pos.x = norm_x
                d2d_cfg.float_pos.y = norm_y
                d2d_cfg.float_size.w = norm_w
                d2d_cfg.float_size.h = norm_h
                ui_dirty = true
            end
        end

        sf6_menu_state.x = pos.x
        sf6_menu_state.y = pos.y
        sf6_menu_state.w = size.x
        sf6_menu_state.h = size.y

        if visible then
            local w_width = size.x

            -- Calculate single-line threshold
            local rec_btn_w_check = get_max_text_width({ T("btn_stop_save"), T("btn_cancel"), T("btn_record_p1"), T("btn_record_p2") }, true)
            local play_btn_w_check = get_max_text_width({ T("btn_start_trial_p1"), T("btn_stop_trial_p1"), T("btn_start_trial_p2"), T("btn_stop_trial_p2") }, true)
            local min_single_line_w = 200 + (rec_btn_w_check + play_btn_w_check) * 2 + 150 * (sh / 1080.0)

            if w_width >= min_single_line_w then
                -- SINGLE LINE: No header, everything directly on the dark area
                draw_single_line_content()
            else
                -- NORMAL MODE: Header + standard content
                -- Calculate exact actual width to synchronize header transition with UI layout
                local rec_btn_w_base = get_max_text_width({ T("btn_stop_save"), T("btn_cancel"), T("btn_record_p1"), T("btn_record_p2"), T("btn_reset"), T("btn_demo") }, true)
                local play_btn_w_base = get_max_text_width({ T("btn_start_trial_p1"), T("btn_stop_trial_p1"), T("pos_mirror") }, true)
                local absolute_btn_w = math.max(rec_btn_w_base, play_btn_w_base)
                local spacing_cols = 20 * (sh / 1080.0)

                local min_inline_w = 150 + (absolute_btn_w * 2) + (spacing_cols * 3)
                local mode_all_inline = w_width >= min_inline_w
                local mode_all_stacked = w_width < (absolute_btn_w * 1.5)
                local mode_col2_3_inline = not mode_all_inline and not mode_all_stacked

                local header_txt = "COMBO TRIALS : REPLAY & RECORDING SETTINGS"
                if mode_all_stacked then
                    header_txt = "COMBO TRIALS"
                elseif mode_col2_3_inline then
                    header_txt = "COMBO TRIALS SETTINGS"
                end

                local cb_width = 35 * (sh / 1080.0)
                local cb_x = w_width - cb_width / 4 - (sw * 0.015)

                local txt_size = imgui.calc_text_size(header_txt)
                local txt_w = txt_size.x
                local txt_h = txt_size.y

                local header_box_h = txt_h + (sh * 0.02)
                local title_x = (w_width - txt_w) / 2

                if (title_x + txt_w) > (cb_x - 15) then
                    title_x = (cb_x - txt_w) / 2
                    if title_x < 5 then title_x = 5 end
                end

                local items_y = (header_box_h - txt_h) / 2
                imgui.set_cursor_pos(Vector2f.new(title_x, items_y))
                imgui.text_colored(header_txt, 0xFFFFFFFF)

                imgui.set_cursor_pos(Vector2f.new(cb_x - 15, 0))
                imgui.push_style_color(7, 0xFF58002C)
                local mask_size = Vector2f.new(w_width, header_box_h)
                if not pcall(imgui.progress_bar, 0.0, mask_size) then
                    pcall(imgui.progress_bar, 0.0, mask_size, "")
                end
                imgui.pop_style_color(1)

                imgui.set_cursor_pos(Vector2f.new(cb_x, items_y))
                local changed, new_val = imgui.checkbox("##close_float", show_trial_overlay)
                if changed then show_trial_overlay = new_val end

                imgui.set_cursor_pos(Vector2f.new(0, header_box_h))
                imgui.spacing(); imgui.separator(); imgui.spacing()

                draw_combo_trials_content(true)
            end
        end

        imgui.end_window()

        if custom_ui_font then imgui.pop_font() end
        imgui.pop_style_color(4)
		imgui.pop_style_var(2)  -- WindowPadding + WindowBorderSize
    else
        sf6_menu_state.active = false
    end

    if ui_dirty then
        ui_save_timer = ui_save_timer + 1
        if ui_save_timer > 60 then
            save_d2d_config()
            ui_dirty = false
            ui_save_timer = 0
        end
    end
end)

-- =========================================================
-- GLOBAL UI MENU DRAWING
-- =========================================================
local function _ctui_draw_live_positions()
    local gB = sdk.find_type_definition("gBattle")
    if not gB then return end
    local sP = gB:get_field("Player"):get_data(nil)
    if not sP or not sP.mcPlayer then return end
    local p1x = sP.mcPlayer[0].pos.x.v or 0
    local p2x = sP.mcPlayer[1].pos.x.v or 0
    imgui.indent(20)
    imgui.text(string.format("P1: %d  (%.2f cm)", p1x, p1x / 65536.0))
    imgui.text(string.format("P2: %d  (%.2f cm)", p2x, p2x / 65536.0))
    imgui.unindent(20)
end

local function draw_combo_trials_menu_ui()
    if _G.CurrentTrainerMode ~= 4 or _G.TrainingModeActive == false then return end
    if imgui.tree_node("TRAINING COMBO TRIALS") then
        local p_state = players[ui_state.viewed_player]
        imgui.spacing()

        -- ==========================================
        -- TAB 1: GLOBAL COMBO TRIAL (Shared P1/P2)
        -- ==========================================
        if styled_header(T("hdr_files"), UI_THEME.hdr_info) then
            -- Combo control-mode filter (Classic/Modern/Auto)
            do
                local FILTER_VALUES = { "all", "classic", "modern", "auto" }
                local FILTER_KEYS = { "cf_all", "cf_classic", "cf_modern", "cf_auto" }
                local cur = file_system.combo_control_filter or "all"
                local cur_idx = 1
                for i, v in ipairs(FILTER_VALUES) do if v == cur then cur_idx = i break end end
                local labels = {}
                for i, k in ipairs(FILTER_KEYS) do labels[i] = T(k) end
                imgui.text(T("ctrl_filter_label") .. ":")
                imgui.same_line()
                imgui.push_item_width(160)
                local fch, fnew = imgui.combo("##ctrl_filter", cur_idx, labels)
                imgui.pop_item_width()
                if fch and FILTER_VALUES[fnew] ~= cur then
                    file_system.combo_control_filter = FILTER_VALUES[fnew]
                    if refresh_combo_list then refresh_combo_list() end
                end
            end
            local changed, new_val = imgui.checkbox("Detacher en fenetre flottante", show_trial_overlay)
            if changed then show_trial_overlay = new_val end

            if not show_trial_overlay then
                imgui.separator()
                imgui.spacing()
                draw_combo_trials_content(false)
            else
                imgui.separator()
                imgui.text_colored("Cette section est actuellement detachee en fenetre flottante.", COLORS.DarkGrey)
                imgui.spacing()
            end
            local asd_c, asd_v = imgui.checkbox("Allow DEMO for stun combos", _G._allow_stun_demo or false)
            if asd_c then _G._allow_stun_demo = asd_v end
        end


        -- ==========================================
        -- TAB 2: D2D VISUALIZER
        -- ==========================================
        if styled_header(T("hdr_d2d"), UI_THEME.hdr_matrix) then
            local changed = false
            local c, v

            c, v = imgui.checkbox(T("enable_d2d"), d2d_cfg.enabled); if c then
                d2d_cfg.enabled = v; changed = true
            end
            c, v = imgui.checkbox(T("ignore_auto"), d2d_cfg.ignore_auto); if c then
                d2d_cfg.ignore_auto = v; changed = true
            end

            if d2d_cfg.ghost_filter_frames == nil then d2d_cfg.ghost_filter_frames = 4 end
            c, v = imgui.drag_int("Ghost Input Filter (Frames)", d2d_cfg.ghost_filter_frames, 1, 0, 10); if c then
                d2d_cfg.ghost_filter_frames = v; changed = true
            end
            if imgui.is_item_hovered() then
                imgui.set_tooltip(
                    "Ignores overlapping fast inputs that last less than X frames.\nHelps prevent '214+P' registering as a wrong move right before '214+PP'.\nSet to 0 to disable. Recommended: 3-4.")
            end


            c, v = imgui.checkbox(T("show_combo_counter"), d2d_cfg.show_combo_count); if c then
                d2d_cfg.show_combo_count = v; changed = true
            end
            c, v = imgui.checkbox(T("show_modern"), d2d_cfg.show_modern_notation or false); if c then
                d2d_cfg.show_modern_notation = v; changed = true
            end
            c, v = imgui.checkbox(T("use_bcm"), d2d_cfg.use_bcm_catalog or false); if c then
                d2d_cfg.use_bcm_catalog = v; _G.ComboTrials_UseBcmCatalog = v; changed = true
            end
            imgui.spacing()

            imgui.text_colored(T("progression"), COLORS.Cyan)
            c, v = imgui.checkbox(T("auto_next"), d2d_cfg.auto_next_trial ~= false); if c then
                d2d_cfg.auto_next_trial = v; changed = true
            end
            if imgui.is_item_hovered() then
                imgui.set_tooltip(T("auto_next_tip"))
            end
            c, v = imgui.checkbox(T("auto_retry"), d2d_cfg.auto_retry_on_fail ~= false); if c then
                d2d_cfg.auto_retry_on_fail = v; changed = true
            end
            if imgui.is_item_hovered() then
                imgui.set_tooltip(T("auto_retry_tip"))
            end
            if file_system.clear_completed_trials and styled_button(T("clear_markers"), UI_THEME.btn_neutral) then
                file_system.clear_completed_trials()
            end
            imgui.spacing()

            imgui.text_colored(T("live_log"), COLORS.Cyan)

            c, v = imgui.checkbox(T("show_p1") .. "##trial", d2d_cfg.show_p1); if c then d2d_cfg.show_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox(T("raw_input") .. "##trial_p1", d2d_cfg.raw_p1 or false); if c then d2d_cfg.raw_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox(T("mirror") .. "##trial_p1", d2d_cfg.mirror_p1 or false); if c then d2d_cfg.mirror_p1 = v; changed = true end
            if not d2d_cfg.raw_pos_p1 then d2d_cfg.raw_pos_p1 = { x = 0.050, y = 0.350 } end
            local tp1 = d2d_cfg.raw_p1 and d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
            local tp1_lbl = d2d_cfg.raw_p1 and "Raw " or ""
            c, v = imgui.drag_float(tp1_lbl .. "P1 X##trial", tp1.x, 0.005, 0.0, 1.0); if c then tp1.x = v; changed = true end
            c, v = imgui.drag_float(tp1_lbl .. "P1 Y##trial", tp1.y, 0.005, 0.0, 1.0); if c then tp1.y = v; changed = true end
            if d2d_cfg.mirror_p1 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - tp1.x) .. ")", 0xFFAAAAAA) end

            c, v = imgui.checkbox(T("show_p2") .. "##trial", d2d_cfg.show_p2); if c then d2d_cfg.show_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox(T("raw_input") .. "##trial_p2", d2d_cfg.raw_p2 or false); if c then d2d_cfg.raw_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox(T("mirror") .. "##trial_p2", d2d_cfg.mirror_p2 or false); if c then d2d_cfg.mirror_p2 = v; changed = true end
            if not d2d_cfg.raw_pos_p2 then d2d_cfg.raw_pos_p2 = { x = 0.850, y = 0.350 } end
            local tp2 = d2d_cfg.raw_p2 and d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
            local tp2_lbl = d2d_cfg.raw_p2 and "Raw " or ""
            c, v = imgui.drag_float(tp2_lbl .. "P2 X##trial", tp2.x, 0.005, 0.0, 1.0); if c then tp2.x = v; changed = true end
            c, v = imgui.drag_float(tp2_lbl .. "P2 Y##trial", tp2.y, 0.005, 0.0, 1.0); if c then tp2.y = v; changed = true end
            if d2d_cfg.mirror_p2 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - tp2.x) .. ")", 0xFFAAAAAA) end

            local t_raw_any = d2d_cfg.raw_p1 or d2d_cfg.raw_p2
            local t_max_key = t_raw_any and "raw_max_history" or "max_history"
            local t_max_lbl = t_raw_any and "Raw Max History##trial" or "Max History##trial"
            if not d2d_cfg.raw_max_history then d2d_cfg.raw_max_history = 19 end
            local c_max, v_max = imgui.drag_int(t_max_lbl, d2d_cfg[t_max_key] or 10, 1, 1, 30); if c_max then
                d2d_cfg[t_max_key] = v_max; changed = true
            end
            imgui.spacing()

            imgui.text_colored("--- Live Log (Idle / No Trial) ---", COLORS.Cyan)

            c, v = imgui.checkbox("Show Player 1##idle", d2d_cfg.idle_show_p1); if c then d2d_cfg.idle_show_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Raw Input##idle_p1", d2d_cfg.idle_raw_p1 or false); if c then d2d_cfg.idle_raw_p1 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Mirror##idle_p1", d2d_cfg.idle_mirror_p1 or false); if c then d2d_cfg.idle_mirror_p1 = v; changed = true end
            if not d2d_cfg.idle_raw_p1 then
                c, v = imgui.drag_float("P1 X##idle", d2d_cfg.idle_pos_p1.x, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p1.x = v; changed = true end
                c, v = imgui.drag_float("P1 Y##idle", d2d_cfg.idle_pos_p1.y, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p1.y = v; changed = true end
                if d2d_cfg.idle_mirror_p1 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - d2d_cfg.idle_pos_p1.x) .. ")", 0xFFAAAAAA) end
            else
                imgui.text_colored("  (Position from Trial Raw P1)", 0xFFAAAAAA)
                if d2d_cfg.idle_mirror_p1 then
                    local src = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
                    imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - (src.x or 0.050)) .. ")", 0xFFAAAAAA)
                end
            end

            c, v = imgui.checkbox("Show Player 2##idle", d2d_cfg.idle_show_p2); if c then d2d_cfg.idle_show_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Raw Input##idle_p2", d2d_cfg.idle_raw_p2 or false); if c then d2d_cfg.idle_raw_p2 = v; changed = true end
            imgui.same_line()
            c, v = imgui.checkbox("Mirror##idle_p2", d2d_cfg.idle_mirror_p2 or false); if c then d2d_cfg.idle_mirror_p2 = v; changed = true end
            if not d2d_cfg.idle_raw_p2 then
                c, v = imgui.drag_float("P2 X##idle", d2d_cfg.idle_pos_p2.x, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p2.x = v; changed = true end
                c, v = imgui.drag_float("P2 Y##idle", d2d_cfg.idle_pos_p2.y, 0.005, 0.0, 1.0); if c then d2d_cfg.idle_pos_p2.y = v; changed = true end
                if d2d_cfg.idle_mirror_p2 then imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - d2d_cfg.idle_pos_p2.x) .. ")", 0xFFAAAAAA) end
            else
                imgui.text_colored("  (Position from Trial Raw P2)", 0xFFAAAAAA)
                if d2d_cfg.idle_mirror_p2 then
                    local src = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
                    imgui.text_colored("  (Mirrored: X=" .. string.format("%.3f", 1.0 - (src.x or 0.850)) .. ")", 0xFFAAAAAA)
                end
            end

            local i_raw_any = d2d_cfg.idle_raw_p1 or d2d_cfg.idle_raw_p2
            local i_max_key = i_raw_any and "idle_raw_max_history" or "idle_max_history"
            local i_max_lbl = i_raw_any and "Raw Max History##idle" or "Max History##idle"
            if not d2d_cfg.idle_raw_max_history then d2d_cfg.idle_raw_max_history = 19 end
            local c_imax, v_imax = imgui.drag_int(i_max_lbl, d2d_cfg[i_max_key] or 10, 1, 1, 30); if c_imax then
                d2d_cfg[i_max_key] = v_imax; changed = true
            end

            -- Raw Input Settings (shown only when at least one raw checkbox is active)
            local any_raw = (d2d_cfg.raw_p1 or d2d_cfg.raw_p2 or d2d_cfg.idle_raw_p1 or d2d_cfg.idle_raw_p2)
            if any_raw then
                imgui.spacing()
                imgui.text_colored("--- Raw Input Display Settings ---", COLORS.Cyan)
                if not d2d_cfg.raw then d2d_cfg.raw = {} end
                local rc = d2d_cfg.raw
                c, v = imgui.drag_float("Raw Icon Size", rc.icon_size or 0.030, 0.001, 0.01, 0.1, "%.3f"); if c then rc.icon_size = v; changed = true end
                c, v = imgui.drag_float("Raw Font Size", rc.font_size or 0.028, 0.001, 0.01, 0.1, "%.3f"); if c then rc.font_size = v; changed = true end
                c, v = imgui.drag_float("Raw Row Spacing", rc.spacing_y or 0.040, 0.001, 0.01, 0.1, "%.3f"); if c then rc.spacing_y = v; changed = true end
                c, v = imgui.drag_float("Raw Text Y Offset", rc.text_y_offset or 0.002, 0.0005, -0.02, 0.02, "%.4f"); if c then rc.text_y_offset = v; changed = true end
                c, v = imgui.drag_float("Raw Frame Col", rc.col_frame or 0.000, 0.005, -0.2, 0.5, "%.3f"); if c then rc.col_frame = v; changed = true end
                c, v = imgui.drag_float("Raw Dir Col", rc.col_dir or 0.050, 0.005, -0.2, 0.5, "%.3f"); if c then rc.col_dir = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 1", rc.slot1 or 0.100, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot1 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 2", rc.slot2 or 0.140, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot2 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 3", rc.slot3 or 0.180, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot3 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 4", rc.slot4 or 0.220, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot4 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 5", rc.slot5 or 0.260, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot5 = v; changed = true end
                c, v = imgui.drag_float("Raw Slot 6", rc.slot6 or 0.300, 0.005, 0.0, 0.5, "%.3f"); if c then rc.slot6 = v; changed = true end
            end

            -- NEW: Trial Box Position & Height
            imgui.separator()

            imgui.text_colored("--- Trial Box Position & Height ---", COLORS.Cyan)
            c, v = imgui.drag_float("Trial P1 X", d2d_cfg.pos_trial_p1.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p1.x = v; changed = true
            end
            c, v = imgui.drag_float("Trial P1 Y", d2d_cfg.pos_trial_p1.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p1.y = v; changed = true
            end
            c, v = imgui.drag_float("Trial P2 X", d2d_cfg.pos_trial_p2.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p2.x = v; changed = true
            end
            c, v = imgui.drag_float("Trial P2 Y", d2d_cfg.pos_trial_p2.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_p2.y = v; changed = true
            end
            c, v = imgui.drag_float("Trial Box Height", d2d_cfg.cartouche_height, 0.01, 0.1, 3.0); if c then
                d2d_cfg.cartouche_height = v; changed = true
            end
            c, v = imgui.drag_float("Trial Box Width", d2d_cfg.cartouche_width, 0.005, 0.1, 1.0); if c then
                d2d_cfg.cartouche_width = v; changed = true
            end
            c, v = imgui.drag_float("Cartouche Offset X", d2d_cfg.cartouche_offset_x, 0.001, -0.1, 0.1); if c then
                d2d_cfg.cartouche_offset_x = v; changed = true
            end
            c, v = imgui.drag_float("Cartouche Offset Y", d2d_cfg.cartouche_offset_y, 0.001, -0.1, 0.1); if c then
                d2d_cfg.cartouche_offset_y = v; changed = true
            end
            if not d2d_cfg.bar_img_offset_x then d2d_cfg.bar_img_offset_x = 0 end
            c, v = imgui.drag_float("Bar Image Offset X", d2d_cfg.bar_img_offset_x, 0.001, -0.2, 0.2); if c then
                d2d_cfg.bar_img_offset_x = v; changed = true
            end
            if not d2d_cfg.bar_img_offset_y then d2d_cfg.bar_img_offset_y = 0 end
            c, v = imgui.drag_float("Bar Image Offset Y", d2d_cfg.bar_img_offset_y, 0.001, -0.2, 0.2); if c then
                d2d_cfg.bar_img_offset_y = v; changed = true
            end
            c, v = imgui.drag_int("Visible Trial Lines", d2d_cfg.trial_visible_steps, 1, 1, 30); if c then
                d2d_cfg.trial_visible_steps = v; changed = true
            end
            if not d2d_cfg.bar_width_pct then d2d_cfg.bar_width_pct = 1.0 end
            c, v = imgui.drag_float("Bottom Bar Width", d2d_cfg.bar_width_pct, 0.01, 0.3, 1.0, "%.2f"); if c then
                d2d_cfg.bar_width_pct = v; changed = true
            end

            imgui.separator()
            imgui.text_colored("--- Bar Image Debug ---", 0xFF00FFFF)

            if not d2d_cfg.done_bar_height then d2d_cfg.done_bar_height = 1.0 end
            c, v = imgui.drag_float("Done Bar Height", d2d_cfg.done_bar_height, 0.01, 0.1, 3.0); if c then
                d2d_cfg.done_bar_height = v; changed = true
            end
            if not d2d_cfg.done_bar_offset_x then d2d_cfg.done_bar_offset_x = 0 end
            c, v = imgui.drag_float("Done Bar Offset X", d2d_cfg.done_bar_offset_x, 0.001, -0.2, 0.2); if c then
                d2d_cfg.done_bar_offset_x = v; changed = true
            end
            if not d2d_cfg.done_bar_offset_y then d2d_cfg.done_bar_offset_y = 0 end
            c, v = imgui.drag_float("Done Bar Offset Y", d2d_cfg.done_bar_offset_y, 0.001, -0.2, 0.2); if c then
                d2d_cfg.done_bar_offset_y = v; changed = true
            end
            if not d2d_cfg.overlay_height then d2d_cfg.overlay_height = 1.0 end
            c, v = imgui.drag_float("Overlay Height", d2d_cfg.overlay_height, 0.01, 0.1, 3.0); if c then
                d2d_cfg.overlay_height = v; changed = true
            end
            if not d2d_cfg.overlay_offset_y then d2d_cfg.overlay_offset_y = 0 end
            c, v = imgui.drag_float("Overlay Offset Y", d2d_cfg.overlay_offset_y, 0.001, -0.1, 0.1); if c then
                d2d_cfg.overlay_offset_y = v; changed = true
            end

            imgui.text_colored("--- Preview Bar Type ---", 0xFF00FFFF)
            if not _G._ct_debug then _G._ct_debug = {} end
            local modes = {"OFF", "ACTIVE", "DONE", "FAIL", "SUCCESS", "RECORDING", "OVERLAY"}
            local cur = _G._ct_debug.preview_mode or 1
            for i, name in ipairs(modes) do
                if imgui.button(name .. "##bar_preview") then
                    _G._ct_debug.preview_mode = i
                end
                if i < #modes then imgui.same_line() end
            end
            imgui.text("Current preview: " .. modes[_G._ct_debug.preview_mode or 1])

            imgui.separator()


            c, v = imgui.drag_float("Trial Title Position X", d2d_cfg.pos_trial_header.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_header.x = v; changed = true
            end
            c, v = imgui.drag_float("Trial Title Position Y", d2d_cfg.pos_trial_header.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_trial_header.y = v; changed = true
            end
            c, v = imgui.drag_float("Combo Stats Position X", d2d_cfg.pos_combo_stats.x, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_combo_stats.x = v; changed = true
            end
            c, v = imgui.drag_float("Combo Stats Position Y", d2d_cfg.pos_combo_stats.y, 0.005, 0.0, 1.0); if c then
                d2d_cfg.pos_combo_stats.y = v; changed = true
            end
            imgui.separator()

            imgui.text_colored("HUD Overlay (Native Lines)", 0xFFFFAA00)
            c, v = imgui.checkbox(T("exc_show_hud"), d2d_cfg.hud_show); if c then
                d2d_cfg.hud_show = v; changed = true
            end
            c, v = imgui.drag_float("HUD Global Y", d2d_cfg.hud_global_y, 0.001, -0.5, 0.0); if c then
                d2d_cfg.hud_global_y = v; changed = true
            end
            c, v = imgui.drag_float("HUD Line Spacing Y", d2d_cfg.hud_spacing_y, 0.001, 0.01, 0.1); if c then
                d2d_cfg.hud_spacing_y = v; changed = true
            end
            c, v = imgui.drag_float("HUD Font Size", d2d_cfg.hud_font_size, 0.5, 10, 60); if c then
                d2d_cfg.hud_font_size = v; changed = true; font_attempted = false
            end
            imgui.separator()
            c, v = imgui.drag_float("Icon Size", d2d_cfg.icon_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.icon_size = v; changed = true
            end
            c, v = imgui.drag_float("Special Icons Scale (DR/DI...)", d2d_cfg.special_icon_scale, 0.01, 1.0, 3.0, "x%.2f"); if c then
                d2d_cfg.special_icon_scale = v; changed = true
            end
            c, v = imgui.drag_float("Font Size", d2d_cfg.font_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.font_size = v; changed = true
            end
            c, v = imgui.drag_float("Spacing X", d2d_cfg.spacing_x, 0.001, 0.01, 0.1); if c then
                d2d_cfg.spacing_x = v; changed = true
            end
            c, v = imgui.drag_float("Spacing Y", d2d_cfg.spacing_y, 0.001, 0.01, 0.1); if c then
                d2d_cfg.spacing_y = v; changed = true
            end
            c, v = imgui.drag_float("Text Y Offset", d2d_cfg.text_y_offset, 0.001, -0.05, 0.05); if c then
                d2d_cfg.text_y_offset = v; changed = true
            end

            imgui.separator()
            imgui.text_colored("--- Animated Arrow ---", COLORS.Cyan)
            c, v = imgui.drag_float("Arrow Size", d2d_cfg.arrow_size, 0.001, 0.01, 0.1); if c then
                d2d_cfg.arrow_size = v; changed = true
            end
            c, v = imgui.drag_float("Arrow X Offset", d2d_cfg.offset_x_arrow, 0.001, -0.1, 0.1); if c then
                d2d_cfg.offset_x_arrow = v; changed = true
            end
            c, v = imgui.drag_float("Arrow Y Offset", d2d_cfg.offset_y_arrow, 0.001, -0.1, 0.1); if c then
                d2d_cfg.offset_y_arrow = v; changed = true
            end
            c, v = imgui.drag_int("Fail Display Time (frames)", d2d_cfg.fail_display_frames, 1, 0, 300); if c then
                d2d_cfg.fail_display_frames = v; changed = true
            end

            imgui.separator()

            if changed then ui_dirty = true; ui_save_timer = 0 end
            imgui.spacing()
        end

        -- ==========================================
        -- TAB 3: EXCEPTION EDITOR MENU
        -- ==========================================
        if styled_header(T("hdr_exceptions"), UI_THEME.hdr_session) then
            -- THE EDITOR ONLY APPEARS WHEN "MANAGE" IS CLICKED
            if p_state.editing_id ~= -1 then
                imgui.text_colored("=== EXCEPTION SETTINGS : ID " .. p_state.editing_id .. " ===", COLORS.Cyan)
                imgui.text_colored("(Settings apply immediately in-game for testing)", COLORS.DarkGrey)
                imgui.spacing()

                local c1, n1 = imgui.checkbox(T("exc_ignore"), p_state.edit_ignore)
                if c1 then
                    p_state.edit_ignore = n1; if n1 then p_state.edit_force = false end
                end

                imgui.same_line()
                local c2, n2 = imgui.checkbox(T("exc_force"), p_state.edit_force)
                if c2 then
                    p_state.edit_force = n2; if n2 then p_state.edit_ignore = false end
                end

                local ch, nh = imgui.checkbox(T("exc_hold"), p_state.edit_holdable)
                if ch then p_state.edit_holdable = nh end

                if p_state.edit_holdable then
                    imgui.indent(20)

                    if p_state.edit_hold_partial_check == nil then p_state.edit_hold_partial_check = true end
                    local chpc, nhpc = imgui.checkbox(T("exc_validate_partial"), p_state.edit_hold_partial_check)
                    if chpc then p_state.edit_hold_partial_check = nhpc end
                    if imgui.is_item_hovered() then
                        imgui.set_tooltip("If unchecked, Instant vs Partial mismatches are tolerated.\nMaxed / PERFECT / FAKE / LATE are ALWAYS enforced.")
                    end

                    local changed_link, new_link = imgui.input_text("Absorb Next IDs (ex: 502,503)", p_state.edit_absorb_ids or "")
                    if changed_link then p_state.edit_absorb_ids = new_link end
                    imgui.spacing()

                    if p_state.profile_name == "Luke" then
                        imgui.text_colored("Luke Charge Profile (Leave empty for Auto Detect):", COLORS.Green)

                        local changed_min, new_min = imgui.input_text("Instant / Partial Limit (frames)",
                            p_state.edit_charge_min or "")
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_pmin, new_pmin = imgui.input_text("Perfect Start (frames)",
                            p_state.edit_perfect_min or "")
                        if changed_pmin then p_state.edit_perfect_min = new_pmin end

                        local changed_pmax, new_pmax = imgui.input_text("Perfect End (frames)",
                            p_state.edit_perfect_max or "")
                        if changed_pmax then p_state.edit_perfect_max = new_pmax end
                    elseif p_state.profile_name == "JP" then
                        imgui.text_colored("JP Mode Active: Exceeding the threshold equals a FAKE.", COLORS.Blue)
                        local changed_min, new_min = imgui.input_text("Instant / Partial Limit (frames)",
                            p_state.edit_charge_min or "")
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_max, new_max = imgui.input_text("FAKE Cancel Threshold (frames)",
                            p_state.edit_charge_max or "")
                        if changed_max then p_state.edit_charge_max = new_max end
                    else
                        imgui.text_colored("Charge Settings (Leave Max empty to auto-fill):", COLORS.Blue)
                        local changed_min, new_min = imgui.input_text("Instant / Partial Limit (frames)",
                            p_state.edit_charge_min)
                        if changed_min then p_state.edit_charge_min = new_min end

                        local changed_max, new_max = imgui.input_text("Maxed Threshold (frames)", p_state
                            .edit_charge_max)
                        if changed_max then p_state.edit_charge_max = new_max end
                    end

                    imgui.unindent(20)
                end

                imgui.spacing()
                local ct, nt = imgui.input_text("New Name (Leave empty to keep native)", p_state.edit_text)
                if ct then p_state.edit_text = nt end

                imgui.spacing()
                local cc, nc = imgui.checkbox(T("exc_apply_common"), p_state.edit_is_common)
                if cc then p_state.edit_is_common = nc end

                imgui.text_colored("--- SPECIAL CONDITIONS ---", COLORS.Blue)
                local ci, ni = imgui.input_text("Ignore if previous Action ID...##ig_id_" .. p_state.editing_id,
                    p_state.edit_ignore_prev_id)
                if ci then p_state.edit_ignore_prev_id = ni end
                local cf, nf = imgui.input_text("... within the last X frames##ig_fr_" .. p_state.editing_id,
                    p_state.edit_ignore_prev_frames)
                if cf then p_state.edit_ignore_prev_frames = nf end
                imgui.spacing()

                imgui.spacing()
                if styled_button("APPLY AND SAVE", UI_THEME.btn_green) then
                    local id_s = tostring(p_state.editing_id)
                    local parsed_min = tonumber(p_state.edit_charge_min)
                    local parsed_max = tonumber(p_state.edit_charge_max)

                    local _parsed_prev = nil
                    if p_state.edit_ignore_prev_id ~= "" then
                        local ids = {}
                        for tok in p_state.edit_ignore_prev_id:gmatch("[^,]+") do
                            local n = tonumber(tok:match("^%s*(.-)%s*$"))
                            if n then ids[#ids+1] = n end
                        end
                        if #ids == 1 then _parsed_prev = ids[1]
                        elseif #ids > 1 then _parsed_prev = ids end
                    end
                    local new_exc = {
                        ignore = p_state.edit_ignore,
                        force = p_state.edit_force,
                        is_holdable = p_state.edit_holdable,
                        hold_partial_check = p_state.edit_hold_partial_check,
                        absorb_ids = p_state.edit_absorb_ids,
                        charge_min = parsed_min,
                        charge_max = parsed_max,
                        perfect_min = tonumber(p_state.edit_perfect_min),
                        perfect_max = tonumber(p_state.edit_perfect_max),
                        override_name = (p_state.edit_text ~= "") and p_state.edit_text or nil,
                        ignore_prev_id = _parsed_prev,
                        ignore_prev_frames = tonumber(p_state.edit_ignore_prev_frames) or 5
                    }

                    pcall(function() if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end end)

                    if p_state.edit_is_common then
                        common_exceptions[id_s] = new_exc
                        p_state.exceptions[id_s] = nil

                        local s1 = json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions)
                        local s2 = json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)

                        if s1 and s2 then
                            exc_status = "✅ Common Exception SAVED."
                        else
                            exc_status = "❌ FATAL ERROR: Cannot write file!"
                        end
                    else
                        p_state.exceptions[id_s] = new_exc

                        local s1 = json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)

                        if s1 then
                            exc_status = "✅ Specific Exception SAVED."
                        else
                            exc_status = "❌ FATAL ERROR: Cannot write file!"
                        end
                    end

                    local new_log = {}
                    for _, l in ipairs(p_state.log) do
                        local keep = true
                        if l.id == p_state.editing_id then
                            if new_exc.ignore then
                                keep = false
                            elseif new_exc.force then
                                l.intentional = true
                            end

                            if new_exc.override_name then
                                l.motion = new_exc.override_name
                            else
                                l.motion = l.name
                            end

                            l.is_holdable = new_exc.is_holdable
                            l.charge_min = new_exc.charge_min
                            l.charge_max = new_exc.charge_max
                        end
                        if keep then table.insert(new_log, l) end
                    end
                    p_state.log = new_log

                    for _, step in ipairs(trial_state.sequence) do
                        if step.id == p_state.editing_id then
                            if new_exc.override_name then
                                step.motion = new_exc.override_name
                            else
                                step.motion = step.name or "Unknown"
                            end
                        end
                    end
                    p_state.editing_id = -1
                end

                imgui.same_line()
                if styled_button("CANCEL", UI_THEME.btn_red) then p_state.editing_id = -1 end
                imgui.separator()
            end

            -- LIST OF SAVED EXCEPTIONS (ASCENDING SORT)
            if imgui.tree_node("Active Exceptions (" .. p_state.profile_name .. ")") then
                if exc_status ~= "" then imgui.text_colored(exc_status, COLORS.Yellow) end

                imgui.text_colored("--- SPECIFIC ---", COLORS.Green)
                local spec_keys = sort_ids(p_state.exceptions)

                if #spec_keys == 0 then
                    imgui.text_colored("None", COLORS.DarkGrey)
                else
                    for _, id_str in ipairs(spec_keys) do
                        local exc = p_state.exceptions[id_str]
                        local desc = ""
                        if exc.ignore then desc = desc .. "[IGNORE] " end
                        if exc.force then desc = desc .. "[FORCE] " end
                        if exc.is_holdable then
                            if p_state.profile_name == "Luke" then
                                local min_s = exc.perfect_min and (exc.perfect_min .. "f") or "Auto"
                                local max_s = exc.perfect_max and (exc.perfect_max .. "f") or "Auto"
                                desc = desc .. "[HOLD(Luke Perfect: " .. min_s .. "-" .. max_s .. ")] "
                            elseif p_state.profile_name == "JP" then
                                local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                                local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                                desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. " FAKE)] "
                            else
                                local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                                local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                                desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. ")] "
                            end
                        end
                        if exc.override_name then desc = desc .. "[NAME: " .. exc.override_name .. "] " end
                        if exc.ignore_prev_id then
                            local id_disp = type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id)
                            desc = desc ..
                                "[IGN IF ID " .. id_disp .. " < " .. (exc.ignore_prev_frames or 5) .. "f]"
                        end

                        imgui.text("ID " .. id_str .. " -> " .. desc)
                        imgui.same_line(450)
                        if styled_button("Edit##spec_" .. id_str, UI_THEME.btn_neutral) then
                            p_state.editing_id = tonumber(id_str)
                            p_state.edit_is_common = false
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_perfect_min = exc.perfect_min and tostring(exc.perfect_min) or ""
                            p_state.edit_perfect_max = exc.perfect_max and tostring(exc.perfect_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = not exc.ignore_prev_id and "" or (type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id))
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        end
                        imgui.same_line()
                        if styled_button("Delete##delspec_" .. id_str, UI_THEME.btn_red) then
                            p_state.exceptions[id_str] = nil
                            pcall(function() if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end end)
                            json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                            exc_status = "🗑️ Specific Exception deleted from disk."
                        end
                    end
                end

                imgui.spacing()
                imgui.text_colored("--- COMMON ---", COLORS.Cyan)
                local com_keys = sort_ids(common_exceptions)

                if #com_keys == 0 then
                    imgui.text_colored("None", COLORS.DarkGrey)
                else
                    for _, id_str in ipairs(com_keys) do
                        local exc = common_exceptions[id_str]
                        local desc = ""
                        if exc.ignore then desc = desc .. "[IGNORE] " end
                        if exc.force then desc = desc .. "[FORCE] " end
                        if exc.is_holdable then
                            local min_s = exc.charge_min and (exc.charge_min .. "f") or "?"
                            local max_s = exc.charge_max and (exc.charge_max .. "f") or "?"
                            desc = desc .. "[HOLD(" .. min_s .. "-" .. max_s .. ")] "
                        end
                        if exc.override_name then desc = desc .. "[NAME: " .. exc.override_name .. "]" end

                        imgui.text("ID " .. id_str .. " -> " .. desc)
                        imgui.same_line(450)
                        if styled_button("Edit##com_" .. id_str, UI_THEME.btn_neutral) then
                            p_state.editing_id = tonumber(id_str)
                            p_state.edit_is_common = true
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_perfect_min = exc.perfect_min and tostring(exc.perfect_min) or ""
                            p_state.edit_perfect_max = exc.perfect_max and tostring(exc.perfect_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = not exc.ignore_prev_id and "" or (type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id))
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        end
                        imgui.same_line()
                        if styled_button("Delete##delcom_" .. id_str, UI_THEME.btn_red) then
                            common_exceptions[id_str] = nil
                            pcall(function() if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end end)
                            json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions)
                            exc_status = "🗑️ Common Exception deleted from disk."
                        end
                    end
                end
                imgui.tree_pop()
            end

            imgui.spacing()
        end

        -- ==========================================
        -- TAB 4: LIVE LOG
        -- ==========================================
        if styled_header(T("live_log_player", ui_state.viewed_player + 1), UI_THEME.hdr_rules) then
            -- PLAYER SELECTOR (Forces refresh on change)
            if styled_button(ui_state.viewed_player == 0 and "LOGGING P1 (" .. players[0].profile_name .. ")" or "WATCH LOG P1 (" .. players[0].profile_name .. ")", ui_state.viewed_player == 0 and UI_THEME.btn_green or UI_THEME.btn_neutral) then
                if ui_state.viewed_player ~= 0 then
                    ui_state.viewed_player = 0; refresh_combo_list()
                end
            end
            imgui.same_line()
            if styled_button(ui_state.viewed_player == 1 and "LOGGING P2 (" .. players[1].profile_name .. ")" or "WATCH LOG P2 (" .. players[1].profile_name .. ")", ui_state.viewed_player == 1 and UI_THEME.btn_green or UI_THEME.btn_neutral) then
                if ui_state.viewed_player ~= 1 then
                    ui_state.viewed_player = 1; refresh_combo_list()
                end
            end
            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            local c_deep, n_deep = imgui.checkbox("Enable 'Deep Action Scanner' (Adds C# DNA to each hit in JSON Dump)",
                p_state.enable_deep_logging)
            if c_deep then p_state.enable_deep_logging = n_deep end
            if p_state.enable_deep_logging then
                imgui.text_colored("   /!\\ Deep Scan analyzes code massively.", COLORS.Blue)
                imgui.text_colored("       Use only for research sessions.", COLORS.Blue)
            end

            imgui.spacing()
            if styled_button("Clear Log", UI_THEME.btn_red) then p_state.log = {} end
            imgui.same_line()
            if styled_button("Dump Log to JSON", UI_THEME.btn_neutral) then
                json.dump_file("Final_Log_Dump_P" .. tostring(ui_state.viewed_player + 1) .. ".json", p_state.log)
                dump_status = "Full log saved."
            end

            if dump_status ~= "" then imgui.text_colored(dump_status, COLORS.Green) end
            imgui.spacing(); imgui.separator(); imgui.spacing()

            if #p_state.log == 0 then
                imgui.text_colored("Waiting for actions...", COLORS.Blue)
            else
                for i, log in ipairs(p_state.log) do
                    if log.intentional then
                        local charge_str = ""
                        if log.is_holdable then
                            local trans_str = ""
                            if not log.is_holding and log.transition_id and log.transition_id > 50 then
                                trans_str =
                                    " -> ID " .. log.transition_id
                            end
                            charge_str = string.format(" (%d%s)", log.hold_frames, trans_str)
                        end

                        local combo_str = ""
                        if log.combo_count ~= nil then
                            combo_str = string.format(" [Combo: %d]", log.combo_count)
                        end

                        -- Translated keywords: VRAI INPUT -> REAL INPUT, Reel -> Raw
                        local left_col = string.format("REAL INPUT  | %s (ID: %d)%s%s", log.motion, log.id, charge_str,
                            combo_str)
                        local right_col = string.format("Raw: %s (%s)", log.real_input, log.frame_diff)

                        local line_color = COLORS.White
                        if log.is_holdable then
                            local live_status = log.charge_status or ""
                            -- Real-time calculation for the text UI
                            if log.is_holding then
                                if log.charge_min and log.hold_frames <= log.charge_min then
                                    live_status = "Instant"
                                elseif log.charge_max and log.hold_frames >= log.charge_max then
                                    live_status = "Maxed"
                                else
                                    live_status = "Partial"
                                end
                            end

                            if live_status:match("Partial") then
                                line_color = COLORS.Orange
                            elseif live_status:match("Maxed") or live_status == "PERFECT!" or live_status == "FAKE" then
                                line_color = COLORS.Yellow
                            end
                        end

                        imgui.text_colored(left_col, line_color)

                        imgui.same_line(450)
                        imgui.text_colored("-> " .. right_col, COLORS.Cyan)
                    else
                        if log.is_ignored then
                            local line = string.format("IGNORED   | %s (ID: %d) %s", log.name, log.id, log.ignore_reason)
                            imgui.text_colored(line, COLORS.DarkGrey)
                        else
                            local line = string.format("AUTOMATIC | %s (ID: %d)", log.name, log.id)
                            if log.real_input and log.real_input ~= "None" and log.real_input ~= "Ghost" then
                                line = line .. "  -> Raw: " .. log.real_input
                            end
                            imgui.text_colored(line, COLORS.DarkGrey)
                        end
                    end

                    imgui.same_line(750)
                    if styled_button("Manage##edit_" .. log.id .. "_" .. i, UI_THEME.btn_orange) then
                        p_state.editing_id = log.id
                        local exc_char = p_state.exceptions[tostring(log.id)]
                        local exc_com = common_exceptions[tostring(log.id)]
                        local exc = exc_char or exc_com

                        if exc_char then
                            p_state.edit_is_common = false
                        elseif exc_com then
                            p_state.edit_is_common = true
                        else
                            p_state.edit_is_common = false
                        end

                        if exc then
                            p_state.edit_ignore = exc.ignore or false
                            p_state.edit_force = exc.force or false
                            p_state.edit_holdable = exc.is_holdable or false
                            p_state.edit_hold_partial_check = (exc.hold_partial_check ~= false)
                            p_state.edit_absorb_ids = exc.absorb_ids or ""
                            p_state.edit_charge_min = exc.charge_min and tostring(exc.charge_min) or ""
                            p_state.edit_charge_max = exc.charge_max and tostring(exc.charge_max) or ""
                            p_state.edit_text = exc.override_name or ""
                            p_state.edit_ignore_prev_id = not exc.ignore_prev_id and "" or (type(exc.ignore_prev_id) == "table" and table.concat(exc.ignore_prev_id, ",") or tostring(exc.ignore_prev_id))
                            p_state.edit_ignore_prev_frames = exc.ignore_prev_frames and tostring(exc.ignore_prev_frames) or
                                "5"
                        else
                            p_state.edit_ignore = false
                            p_state.edit_force = false
                            p_state.edit_holdable = false
                            p_state.edit_hold_partial_check = true
                            p_state.edit_absorb_ids = ""
                            p_state.edit_charge_min = ""
                            p_state.edit_charge_max = ""
                            p_state.edit_text = log.motion or log.name
                            p_state.edit_ignore_prev_id = ""
                            p_state.edit_ignore_prev_frames = "5"
                        end
                    end
                end
            end
        end

        imgui.spacing()

        -- ==========================================
        -- TAB 5: DEBUG & SYSTEM INFO
        -- ==========================================
        if styled_header(T("hdr_debug"), UI_THEME.hdr_rules) then
            local di_delay = _G._demo_post_di_delay_ms or 0
            local di_changed, di_val = imgui.input_text("DEMO Post-DI Delay (ms)", tostring(di_delay))
            if di_changed then local n = tonumber(di_val); if n then _G._demo_post_di_delay_ms = math.floor(n) end end
            local ds = ctx.demo_state
            if ds then
                local idx = ds._di_step_idx
                imgui.text_colored("DI step_idx: " .. tostring(idx or "nil") .. "  playing: " .. tostring(ds.is_playing) .. "  triggered: " .. tostring(ds._di_triggered), 0xFF00FFFF)
                if idx and ctx.trial_state.sequence and ctx.trial_state.sequence[idx] then
                    local step = ctx.trial_state.sequence[idx]
                    imgui.text_colored("  motion: " .. tostring(step.motion) .. "  has_hit: " .. tostring(step.has_hit) .. "  current_step: " .. tostring(ctx.trial_state.current_step), 0xFF00FFFF)
                end
                if ds._di_triggered then
                    local rem_ms = math.floor((ds._di_delay_remaining or 0) * 16.67)
                    imgui.text_colored("DI DETECTED! delay_rem=" .. rem_ms .. "ms", 0xFF00FF00)
                    if _G._di_skip_debug then imgui.text_colored(_G._di_skip_debug, 0xFF00FFFF) end
                end
            end
            if ctx.trial_state.sequence then
                local di_found = false
                for si, step in ipairs(ctx.trial_state.sequence) do
                    if step.motion then
                        local m = step.motion:upper()
                        if m == "DI" or m:find("HPHK") then
                            imgui.text_colored("Sequence has DI at step " .. si .. ": " .. step.motion, 0xFF00FF00)
                            di_found = true
                            break
                        end
                    end
                end
                if not di_found then
                    imgui.text_colored("No DI step in sequence", 0xFF0000FF)
                end
            end
            imgui.spacing()
            imgui.text_colored("Detected Native Game Resolution:", 0xFF00FFFF)
            local res_w = ctx.cached_sw or last_sw or 0
            local res_h = ctx.cached_sh or last_sh or 0
            imgui.indent(20)
            imgui.text(string.format("%d px width  x  %d px height", res_w, res_h))
            imgui.unindent(20)
            imgui.spacing()

            -- LIVE POSITIONS
            imgui.text_colored("Live Positions (raw sfix):", 0xFF00FFFF)
            pcall(_ctui_draw_live_positions)
            imgui.text_colored("Saved Trial Positions:", 0xFF00FFFF)
            imgui.indent(20)
            imgui.text(string.format("start_pos_p1_raw: %s", tostring(trial_state.start_pos_p1_raw)))
            imgui.text(string.format("start_pos_p2_raw: %s", tostring(trial_state.start_pos_p2_raw)))
            imgui.text(string.format("exact_inject_r1: %s", tostring(trial_state.exact_inject_r1)))
            imgui.text(string.format("exact_inject_r2: %s", tostring(trial_state.exact_inject_r2)))
            imgui.text(string.format("pending_exact_pos: %s", tostring(trial_state.pending_exact_pos)))
            imgui.text(string.format("forced_position_idx: %d", d2d_cfg.forced_position_idx))
            imgui.unindent(20)
            imgui.spacing()

            if trial_state.sequence and #trial_state.sequence > 0 then
                imgui.text_colored("Sequence Steps:", 0xFF00FFFF)
                imgui.indent(20)
                local pose_names = { [0] = "Stand", [1] = "Crouch", [2] = "Air", [3] = "Down" }
                for si, step in ipairs(trial_state.sequence) do
                    local vp = step.victim_pose
                    local vp_str = vp and (pose_names[vp] or ("Air(" .. vp .. ")")) or "?"
                    local ct_str = ""
                    if step.counter_type == 1 then ct_str = " CH"
                    elseif step.counter_type == 2 then ct_str = " PC" end
                    imgui.text(string.format("#%d  %s  (ID:%d)  combo:%d  dmg:%s  victim:%s%s",
                        si, step.motion or "?", step.id or 0,
                        step.expected_combo or 0,
                        tostring(step.damage_at_step or "-"),
                        vp_str, ct_str))
                end
                imgui.unindent(20)
                imgui.spacing()
            end

            -- FAIL DUMP BUTTON (Only appears if a fail is in memory)
            --[[
            if ctx.trial_state and ctx.trial_state.last_fail_dump then
                imgui.separator()
                imgui.spacing()
                imgui.text_colored("Last Failed Trial!", COLORS.Red)
                if styled_button("Dump Fail Data to JSON", UI_THEME.btn_red) then
                    if ctx.dump_last_fail then
                        local path = ctx.dump_last_fail()
                        if path then
                            print("[ComboTrials] Fail dump saved to: " .. path)
                        end
                    end
                end
                imgui.spacing()
            end
            ]]--
        end

        -- IMPORTANT : Closes the tree_node and the if block
        imgui.tree_pop()
    end
end

-- Register in floating window hub + keep standard menu entry
if _G.FloatingScriptUI then
    _G.FloatingScriptUI.register("TRAINING COMBO TRIALS", draw_combo_trials_menu_ui)
end
re.on_draw_ui(draw_combo_trials_menu_ui)

-- =========================================================
-- Public API
-- =========================================================
function M.init(shared_ctx)
    ctx = shared_ctx
    d2d_cfg = ctx.d2d_cfg
    trial_state = ctx.trial_state
    players = ctx.players
    file_system = ctx.file_system
    common_exceptions = ctx.common_exceptions
    sf6_menu_state = ctx.sf6_menu_state
    load_and_start_trial = ctx.load_and_start_trial
    start_recording = ctx.start_recording
    stop_recording_and_save = ctx.stop_recording_and_save
    cancel_recording = ctx.cancel_recording
    refresh_combo_list = ctx.refresh_combo_list
    restore_trial_vital = ctx.restore_trial_vital
    save_d2d_config = ctx.save_d2d_config
    get_exc_filename = ctx.get_exc_filename
    ui_state = ctx.ui_state
end

return M