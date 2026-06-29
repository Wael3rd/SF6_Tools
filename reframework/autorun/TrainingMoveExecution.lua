local re = re
local sdk = sdk
local imgui = imgui
local GS = require("func/GameState")
local UIKit = require("func/UIKit")


local TOTAL = 10

local function argb_to_abgr(c)
    local a = (c >> 24) & 0xFF
    local r = (c >> 16) & 0xFF
    local g = (c >> 8) & 0xFF
    local b = c & 0xFF
    return (a << 24) | (b << 16) | (g << 8) | r
end

local function abgr_to_argb(c)
    return argb_to_abgr(c)
end

local config = {
    n_y = -0.340,
    n_box_size = 0.038,
    col_box_empty   = 0xFFD8D8D8,
    col_box_ok      = 0xFF00FF00,
    col_box_perfect = 0xFF00FFFF,
    col_txt_title   = 0xFFFFFFFF,
    col_txt_perfect = 0xFF00FFFF,
    col_txt_ok      = 0xFF00FFFF,
    col_txt_miss    = 0xFF0000FF,
    col_txt_complete = 0xFF00FFFF,
    col_txt_switch  = 0xFF00FFFF,
    col_txt_register = 0xFF00FF00,
    col_txt_sub     = 0xFFFFFFFF,
    col_bg          = 0xFF000000,
    bg_alpha        = 255,
    font_scale      = 1.249,
}

local state = {
    enabled = false,
    dp_ids = {},
    dp_name = nil,
    dp_grace_frames = 60,
    registering = false,
    capturing = false,
    count = 0,
    side = 1,
    completed_sides = 0,
    boxes = {},
    result = nil,
    result_timer = 0,
    last_act_id = -1,
    grace = 0,
    switch_timer = 0,
    last_dir = 0,
    last_btn = 0,
    input_history = {},
}

local function get_dir(dv)
    if not dv then return 5 end
    local u = (dv & 1) ~= 0
    local d = (dv & 2) ~= 0
    local l = (dv & 4) ~= 0
    local r = (dv & 8) ~= 0
    if u and l then return 7 elseif u and r then return 9
    elseif d and l then return 1 elseif d and r then return 3
    elseif u then return 8 elseif d then return 2
    elseif l then return 4 elseif r then return 6 end
    return 5
end

local function is_facing_left(p)
    if not p or not p.BitValue then return false end
    return (p.BitValue & 128) == 128
end

local function has_punch(bv)
    return bv and (bv & (16 | 32 | 64 | 128 | 256 | 512)) ~= 0
end

local function get_act_id(p)
    if not p or not p.mpActParam or not p.mpActParam.ActionPart then return -1 end
    local eng = p.mpActParam.ActionPart._Engine
    if not eng then return -1 end
    return eng:get_ActionID()
end

local DIR_NAMES = {
    [1]="↙", [2]="↓", [3]="↘", [4]="←", [5]="N", [6]="→", [7]="↖", [8]="↑", [9]="↗"
}
local function dir_name(d) return DIR_NAMES[d] or tostring(d) end

local function check_perfect(hist)
    if #hist < 2 then return false, "not enough inputs" end
    local patterns = {
        -- DP (both sides)
        { name="DP", steps={ {6}, {2}, {3, true} } },
        { name="DP", steps={ {6}, {3}, {6, true} } },
        { name="DP", steps={ {6}, {3, true} } },
        { name="DP", steps={ {4}, {2}, {1, true} } },
        { name="DP", steps={ {4}, {1}, {4, true} } },
        { name="DP", steps={ {4}, {1, true} } },
        -- QCF (both sides)
        { name="QCF", steps={ {2}, {3}, {6, true} } },
        { name="QCF", steps={ {2}, {3, true} } },
        { name="QCF", steps={ {2}, {1}, {4, true} } },
        { name="QCF", steps={ {2}, {1, true} } },
        -- HCF (both sides) — must be before QCF/QCB to match first
        { name="HCF", steps={ {4}, {1}, {2}, {3}, {6, true} } },
        { name="HCF", steps={ {8}, {9}, {2}, {1}, {4, true} } },
        -- HCB (both sides)
        { name="HCB", steps={ {6}, {3}, {2}, {1}, {4, true} } },
        { name="HCB", steps={ {4}, {1}, {2}, {3}, {6, true} } },
        -- QCB (both sides)
        { name="QCB", steps={ {2}, {1}, {4, true} } },
        { name="QCB", steps={ {2}, {1, true} } },
        { name="QCB", steps={ {2}, {3}, {6, true} } },
        { name="QCB", steps={ {2}, {3, true} } },
    }
    for _, pat in ipairs(patterns) do
        local len = #pat.steps
        if #hist >= len then
            local match = true
            for pi = 1, len do
                local e = hist[#hist - len + pi]
                local expected = pat.steps[pi]
                if e.dir ~= expected[1] then match = false; break end
                if expected[2] and not e.punch then match = false; break end
            end
            if match then
                local detail = ""
                local perfect = true
                local slow = {}
                for pi = 1, len do
                    local e = hist[#hist - len + pi]
                    local p = e.punch and "P" or ""
                    detail = detail .. dir_name(e.dir) .. p .. "(" .. e.frames .. "f)"
                    if pi < len then detail = detail .. " " end
                    if pi < len and e.frames > 1 then
                        perfect = false
                        slow[#slow + 1] = dir_name(e.dir) .. " " .. e.frames .. "f"
                    end
                end
                if not perfect then detail = detail .. " — " .. table.concat(slow, ", ") end
                return perfect, detail
            end
        end
    end
    -- Generic fallback (360, etc.): find the last punch, check all dirs before it
    for scan = #hist, 1, -1 do
        if hist[scan].punch then
            local start = math.max(1, scan - 6)
            if hist[start].dir == 5 then start = start + 1 end
            local detail = ""
            local perfect = true
            local slow = {}
            for pi = start, scan do
                local e = hist[pi]
                local p = e.punch and "P" or ""
                detail = detail .. dir_name(e.dir) .. p .. "(" .. e.frames .. "f)"
                if pi < scan then detail = detail .. " " end
                if pi < scan and e.frames > 1 then
                    perfect = false
                    slow[#slow + 1] = dir_name(e.dir) .. " " .. e.frames .. "f"
                end
            end
            if not perfect then detail = detail .. " — " .. table.concat(slow, ", ") end
            return perfect, detail
        end
    end
    local dump = "Parasite Input Detected — "
    for i = math.max(1, #hist - 6), #hist do
        local e = hist[i]
        local p = e.punch and "P" or ""
        dump = dump .. dir_name(e.dir) .. p .. "(" .. e.frames .. "f) "
    end
    return false, dump
end

local function set_positions(p1x, p2x)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local sm = tData:get_field("SelectMenu")
        if not sm or not sm.PlayerDatas then return end
        sm.StartLocation = 3
        sm.PlayerDatas[0].ManualPosX = p1x
        sm.PlayerDatas[1].ManualPosX = p2x
        tm._IsReqRefresh = true
    end)
end

local function _dp_set_attack_info(hide)
    pcall(function()
        local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
        if not mgr then return end
        local dict = mgr:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if not entry then goto next_entry end
            local wl = entry:get_field("value")
            if not wl then goto next_entry end
            local wc = wl:call("get_Count")
            for j = 0, wc - 1 do
                local w = wl:call("get_Item", j)
                if w and w:get_type_definition() and w:get_type_definition():get_full_name():find("TMAttackInfo") then
                    pcall(w.call, w, "set_Visible", not hide)
                    local infos = w:get_field("AttackInfos")
                    if infos then
                        local len = infos:call("get_Length")
                        for k = 0, len - 1 do
                            local line = infos:call("GetValue", k)
                            if line then
                                for _, fname in ipairs({"LeftText", "CenterText", "RightText", "InfoPanel"}) do
                                    local obj = line:get_field(fname)
                                    if obj then pcall(obj.call, obj, "set_Visible", not hide) end
                                end
                            end
                        end
                    end
                end
            end
            ::next_entry::
        end
    end)
end

local function swap_positions()
    if state.side == 1 then
        set_positions(150, -150)
    else
        set_positions(-150, 150)
    end
end

local MOTIONS = {
    { label = "QCF",    dirs = { 2, 2|8, 8 } },
    { label = "QCB",    dirs = { 2, 2|4, 4 } },
    { label = "HCF",    dirs = { 4, 2|4, 2, 2|8, 8 } },
    { label = "HCB",    dirs = { 8, 2|8, 2, 2|4, 4 } },
    { label = "SRK",    dirs = { 8, 2, 2|8 } },
    { label = "360",    dirs = { 8, 2|8, 2, 2|4, 4, 1|4, 1 } },
    { label = "QCFx2",  dirs = { 2, 2|8, 8, 2, 2|8, 8 } },
    { label = "QCBx2",  dirs = { 2, 2|4, 4, 2, 2|4, 4 } },
    { label = "720",    dirs = { 8, 2|8, 2, 2|4, 4, 1|4, 1, 1|8, 8, 2, 4 } },
}
local BUTTONS = {
    { label = "LP", mask = 16 },
    { label = "MP", mask = 32 },
    { label = "HP", mask = 64 },
    { label = "LK", mask = 128 },
    { label = "MK", mask = 256 },
    { label = "HK", mask = 512 },
}

local _sel_motion = nil
local _sel_buttons = {}

local function get_combined_btn_mask()
    local mask = 0
    for i, _ in pairs(_sel_buttons) do mask = mask | BUTTONS[i].mask end
    return mask
end

local function build_inject_seq(motion, btn_mask)
    local seq = { {f=3, m=0} }
    for i, d in ipairs(motion.dirs) do
        local m = d
        if i == #motion.dirs then m = m | btn_mask end
        seq[#seq + 1] = {f=1, m=m}
    end
    seq[#seq].f = 3
    seq[#seq + 1] = {f=5, m=0}
    return seq
end

local _inject = { active = false, seq = nil, step = 1, frame = 0 }
local _td_gBattle = sdk.find_type_definition("gBattle")

table.insert(_G._shared_input_post, function(p_id, retval)
    if p_id ~= 0 or not _inject.active then return end
    local step = _inject.seq[_inject.step]
    if not step then _inject.active = false; return end

    pcall(function()
        local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[0]
        if not p1 then return end
        local dir_mask = step.m & 0xF
        local btn_mask = step.m & 0xFFF0
        if not p1:get_field("rl_dir") then
            local has_right = (dir_mask & 4) ~= 0
            local has_left  = (dir_mask & 8) ~= 0
            dir_mask = dir_mask & ~12
            if has_right then dir_mask = dir_mask | 8 end
            if has_left  then dir_mask = dir_mask | 4 end
        end
        local combined = dir_mask | btn_mask
        p1:set_field("pl_input_new", (p1:get_field("pl_input_new") or 0) | combined)
        p1:set_field("pl_sw_new", (p1:get_field("pl_sw_new") or 0) | combined)
    end)

    _inject.frame = _inject.frame + 1
    if _inject.frame >= step.f then
        _inject.step = _inject.step + 1
        _inject.frame = 0
        if _inject.step > #_inject.seq then _inject.active = false end
    end
end)

local function reset_challenge()
    state.count = 0
    state.boxes = {}
    state.result = nil
    state.result_timer = 0
    state.input_history = {}
    state.last_act_id = -1
end

re.on_frame(function()
    local active = _G.CurrentTrainerMode == 5
    if active and not state._was_active then
        reset_challenge()
        state.side = 1
        state.registering = true
        state.capturing = false
        state._move_label = nil
        state.dp_ids = {}
        state.dp_name = nil
        _sel_motion = nil
        _sel_buttons = {}
        set_positions(-150, 150)
        _dp_set_attack_info(true)
    elseif not active and state._was_active then
        _dp_set_attack_info(false)
        state.registering = false
        state.capturing = false
        state.dp_ids = {}
        state._move_label = nil
        _sel_motion = nil
        _sel_buttons = {}
    end
    state._was_active = active
    if not active then return end
    if not GS.valid or not GS.p1 then return end

    local active_result = (state.result and state.result_timer > 0) and state.result or nil
    _G._exec_status = active_result or (state._move_label and ("PERFORM " .. state._move_label) or "REGISTER SPECIAL")
    _G._exec_registering = state.registering or state.capturing
    _G._exec_count = state.count
    local boxes_str = ""
    for i = 1, 10 do boxes_str = boxes_str .. (state.boxes[i] or 0) end
    _G._exec_boxes = boxes_str
    _G._exec_side = state.side
    _G._exec_sel_motion = _sel_motion and MOTIONS[_sel_motion].label or ""
    local btn_names = {}
    for i, b in ipairs(BUTTONS) do if _sel_buttons[i] then btn_names[#btn_names + 1] = b.label end end
    _G._exec_sel_buttons = table.concat(btn_names, "+")

    if _G._tsm_web_cmd == "exec_play" then
        local data = _G._tsm_web_cmd_data
        _G._tsm_web_cmd = nil
        _G._tsm_web_cmd_data = nil
        if data then
            local mot_name = data.motion or ""
            local btn_str = data.buttons or ""
            local mot = nil
            for i, m in ipairs(MOTIONS) do
                if m.label == mot_name then mot = i; _sel_motion = i; break end
            end
            _sel_buttons = {}
            local btn_mask = 0
            for bp in btn_str:gmatch("[^+]+") do
                for i, b in ipairs(BUTTONS) do
                    if b.label == bp then _sel_buttons[i] = true; btn_mask = btn_mask | b.mask end
                end
            end
            if btn_mask > 0 then
                state._move_label = mot_name ~= "" and (mot_name .. " " .. btn_str) or btn_str
                state.registering = false
                state.capturing = true
                state._capture_saw_action = false
                state._capture_idle = 0
                state.dp_ids = {}
                state.dp_name = nil
                reset_challenge()
                if mot then
                    _inject.seq = build_inject_seq(MOTIONS[mot], btn_mask)
                else
                    _inject.seq = { {f=3, m=0}, {f=3, m=btn_mask}, {f=5, m=0} }
                end
                _inject.step = 1
                _inject.frame = 0
                _inject.active = true
            end
        end
    end

    if _G._tsm_web_cmd == "exec_sel_motion" then
        local val = tostring(_G._tsm_web_cmd_value or "")
        _G._tsm_web_cmd = nil
        _sel_motion = nil
        for i, m in ipairs(MOTIONS) do
            if m.label == val then _sel_motion = i; break end
        end
    end

    if _G._tsm_web_cmd == "exec_sel_buttons" then
        local val = tostring(_G._tsm_web_cmd_value or "")
        _G._tsm_web_cmd = nil
        _sel_buttons = {}
        for bp in val:gmatch("[^+]+") do
            for i, b in ipairs(BUTTONS) do
                if b.label == bp then _sel_buttons[i] = true end
            end
        end
    end

    if _G._tsm_web_cmd == "exec_register" then
        _G._tsm_web_cmd = nil
        state.registering = true
        state.dp_ids = {}
        state.dp_name = nil
        state._move_label = nil
        _sel_motion = nil
        _sel_buttons = {}
        reset_challenge()
        state.side = 1
    end

    _dp_set_attack_info(true)

    local p1 = GS.p1
    local f_in = p1:get_type_definition():get_field("pl_input_new")
    local f_sw = p1:get_type_definition():get_field("pl_sw_new")
    local dv = (f_in and f_in:get_data(p1)) or 0
    local bv = (f_sw and f_sw:get_data(p1)) or 0
    local dir = get_dir(dv)
    local cur_act = get_act_id(p1)

    if dir ~= state.last_dir or (has_punch(bv) ~= has_punch(state.last_btn)) then
        local entry = { dir = dir, punch = has_punch(bv), frames = 1 }
        state.input_history[#state.input_history + 1] = entry
        if #state.input_history > 10 then table.remove(state.input_history, 1) end
    else
        if #state.input_history > 0 then
            state.input_history[#state.input_history].frames = state.input_history[#state.input_history].frames + 1
        end
    end

    local in_hitstop = false
    local _hs_ok, _hs_val = pcall(p1.get_field, p1, "hit_stop")
    if _hs_ok and _hs_val and tonumber(tostring(_hs_val)) > 0 then in_hitstop = true end
    if state.grace > 0 and not in_hitstop then state.grace = state.grace - 1 end
    if state.switch_timer > 0 then
        state.switch_timer = state.switch_timer - 1
        if state.switch_timer == 0 then
            swap_positions()
            state.side = state.side == 1 and 2 or 1
            state.count = 0
            state.boxes = {}
            state.input_history = {}
        end
    end

    local p1_act_st = GS.p1_act_st or 0
    state._dbg_act_st = p1_act_st

    local meaty = 0
    if not state._meaty_cache_ctr then state._meaty_cache_ctr = 0; state._meaty_cache_val = 0 end
    state._meaty_cache_ctr = state._meaty_cache_ctr - 1
    if state._meaty_cache_ctr <= 0 then
        state._meaty_cache_ctr = 30
        pcall(function()
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            local md = tm._tCommon.SnapShotDatas[0]._DisplayData.FrameMeterSSData.MeterDatas:call("get_Item", 0)
            local raw = tostring(md:get_field("MeatyFrame") or "")
            state._meaty_cache_val = tonumber(raw:match("(%d+)")) or 0
        end)
    end
    meaty = state._meaty_cache_val
    state._dbg_meaty = meaty

    if state.capturing then
        if cur_act ~= state.last_act_id then

        end
        if cur_act ~= state.last_act_id and cur_act > 50 and not state.dp_ids[cur_act] then
            state.dp_ids[cur_act] = true
            if state.dp_name and state.dp_name ~= "" then
                state.dp_name = state.dp_name .. "," .. cur_act
            else
                state.dp_name = tostring(cur_act)
            end
            state._capture_saw_action = true
            state._capture_idle = 0
        end
        if state._capture_saw_action and p1_act_st == 0 then
            state._capture_idle = (state._capture_idle or 0) + 1
        else
            state._capture_idle = 0
        end
        local done = (state._capture_saw_action and meaty > 0) or (state._capture_saw_action and state._capture_idle >= 3)
        if done then
            state.capturing = false
            state.registering = false
            if meaty > 0 then state.dp_grace_frames = meaty end
            state.result = "SPECIAL REGISTERED [" .. (state.dp_name or "?") .. "] (grace " .. meaty .. "F)"
            state.result_timer = 90
            state.grace = meaty
        end
    end

    if cur_act ~= state.last_act_id and cur_act > 50 and state.grace == 0 and not state.capturing then
        if next(state.dp_ids) and state.dp_ids[cur_act] then
            local perfect, detail = check_perfect(state.input_history)
            state.last_detail = (perfect and "PERFECT: " or "OK: ") .. detail
            state.count = state.count + 1
            state.boxes[state.count] = perfect and 2 or 1
            state.result = perfect and "PERFECT" or "OK"
            state.result_timer = state.dp_grace_frames
            state.grace = state.dp_grace_frames

            if state.count >= TOTAL then
                state.result = "SWITCH SIDE!"
                state.result_timer = 120
                state.switch_timer = 120
                state.grace = 130
            end
        elseif next(state.dp_ids) and state.count > 0 then
            state.last_detail = "FAIL: act_id=" .. cur_act .. " (expected: " .. (state.dp_name or "?") .. ")"
            reset_challenge()
            state.result = "FAIL - COUNTER RESET"
            state.result_timer = state.dp_grace_frames
        end
    end

    state.last_act_id = cur_act
    state.last_dir = dir
    state.last_btn = bv

    if state.result_timer > 0 and not in_hitstop then state.result_timer = state.result_timer - 1 end
end)

re.on_frame(function()
    if _G.CurrentTrainerMode ~= 5 then return end

    local sw, sh = 1920, 1080
    if imgui.get_display_size then
        local r = imgui.get_display_size()
        if type(r) == "userdata" then
            pcall(function() sw = r.x; sh = r.y end)
        end
    end

    local box_size = sh * config.n_box_size
    local gap = box_size * 0.3
    local total_w = TOTAL * box_size + (TOTAL - 1) * gap
    local start_x = (sw - total_w) / 2
    local center_y = sh / 2 + sh * config.n_y

    local _dp_font = nil
    pcall(function()
        _dp_font = imgui.load_font("capcom_goji-udkakugoc80pro-db.ttf", math.max(10, math.floor(18 * config.font_scale * (sh / 1080.0))))
    end)
    if _dp_font then imgui.push_font(_dp_font) end
    local text_h = imgui.calc_text_size("X").y
    local spacing = sh * 0.006
    local is_reg = (state.registering or state.capturing) and not next(state.dp_ids)
    local row_h = text_h + spacing
    local win_h
    if is_reg then
        win_h = spacing + text_h + spacing + row_h + row_h + row_h + spacing
    else
        win_h = spacing + text_h + spacing + box_size + spacing + text_h + spacing
    end
    local win_w = math.max(total_w + spacing * 2, is_reg and (sw * 0.5) or 0)
    local win_x = (sw - win_w) / 2

    local bg_rgb = config.col_bg & 0x00FFFFFF
    local bg_with_alpha = (config.bg_alpha << 24) | bg_rgb
    imgui.push_style_color(2, bg_with_alpha)
    imgui.push_style_color(5, 0x00000000)
    imgui.push_style_color(7, 0x00000000)
    imgui.push_style_color(8, 0x00000000)
    imgui.push_style_var(4, 0.0)

    imgui.set_next_window_size(Vector2f.new(win_w, win_h))
    imgui.set_next_window_pos(Vector2f.new(win_x, center_y))
    if imgui.begin_window("MoveExecution##overlay", true, 15) then

        local side_label = state.side == 1 and "P1 SIDE" or "P2 SIDE"
        local title, title_col
        if state.result and state.result_timer > 0 then
            title = state.result
            if title == "PERFECT" then title_col = config.col_txt_perfect
            elseif title == "OK" then title_col = config.col_box_ok
            elseif title:find("FAIL") then title_col = config.col_txt_miss
            elseif title == "COMPLETE!" then title_col = config.col_txt_complete
            elseif title == "SWITCH SIDE!" then title_col = config.col_txt_switch
            elseif title:find("REGISTERED") then title_col = config.col_txt_register
            else title_col = config.col_txt_title end
        elseif state.registering or state.capturing then
            title = "REGISTER SPECIAL"
            title_col = config.col_txt_switch
        elseif next(state.dp_ids) then
            local move_name = state._move_label or "SPECIAL MOVE"
            title = "PERFORM " .. move_name .. " - " .. side_label
            title_col = config.col_txt_title
        else
            title = "REGISTER SPECIAL"
            title_col = config.col_txt_switch
        end
        local title_w = imgui.calc_text_size(title).x
        imgui.set_cursor_pos(Vector2f.new((win_w - title_w) / 2, spacing))
        imgui.text_colored(title, title_col)

        if not state.registering and not state.capturing and imgui.is_mouse_clicked(0) then
            local m = imgui.get_mouse()
            if m and m.y >= center_y and m.y <= center_y + win_h and m.x >= win_x and m.x <= win_x + win_w then
                state.registering = true
                state.dp_ids = {}
                state.dp_name = nil
                state._move_label = nil
                _sel_motion = nil
                _sel_buttons = {}
                reset_challenge()
                state.side = 1
                state.completed_sides = 0
            end
        end

        local boxes_bottom = spacing + text_h + spacing + box_size + spacing

        if not is_reg then
        for i = 1, TOTAL do
            local bx = start_x + (i - 1) * (box_size + gap)
            local col = config.col_box_empty
            if state.boxes[i] == 2 then col = config.col_box_perfect
            elseif state.boxes[i] == 1 then col = config.col_box_ok end

            local box_x = spacing + (i - 1) * (box_size + gap)
            imgui.set_cursor_pos(Vector2f.new(box_x, spacing + text_h + spacing))
            imgui.push_style_color(21, col)
            imgui.push_style_color(22, col)
            imgui.push_style_color(23, col)
            imgui.button("##dp_box_" .. i, Vector2f.new(box_size, box_size))
            imgui.pop_style_color(3)
        end

        local sub = "CLICK THE ZONE TO REGISTER A SPECIAL"
        local sub_col = config.col_txt_sub
        if state.last_detail then
            if state.last_detail:find("^PERFECT") then
                local reason = state.last_detail:match("^%u+: (.+)")
                sub = reason or "PERFECT INPUT"
                sub_col = config.col_box_perfect
            elseif state.last_detail:find("^OK") then
                local reason = state.last_detail:match(" — (.+)") or state.last_detail:match("^%u+: (.+)")
                sub = reason or state.last_detail
                sub_col = config.col_box_ok
            elseif state.last_detail:find("^FAIL") then
                sub = state.last_detail:match("^%u+: (.+)") or state.last_detail
                sub_col = config.col_txt_miss
            end
        end
        local sub_w = imgui.calc_text_size(sub).x
        imgui.set_cursor_pos(Vector2f.new((win_w - sub_w) / 2, boxes_bottom))
        imgui.text_colored(sub, sub_col)
        end -- not is_reg

        if is_reg then
            local row_y = spacing + text_h + spacing
            local mot_w = (win_w - spacing * 2) / #MOTIONS - 2
            for i, mot in ipairs(MOTIONS) do
                local mx = spacing + (i - 1) * (mot_w + 2)
                imgui.set_cursor_pos(Vector2f.new(mx, row_y))
                local sel = (_sel_motion == i)
                if sel then imgui.push_style_color(21, 0xFF00AA00) end
                if imgui.button(mot.label .. "##ov_mot", Vector2f.new(mot_w, 0)) then
                    if sel then _sel_motion = nil else _sel_motion = i end
                end
                if sel then imgui.pop_style_color(1) end
            end
            local btn_y = row_y + row_h
            local btn_w = (win_w - spacing * 2) / #BUTTONS - 2
            local btns_total_w = #BUTTONS * (btn_w + 2) - 2
            local btns_start_x = (win_w - btns_total_w) / 2
            for i, btn in ipairs(BUTTONS) do
                local bx = btns_start_x + (i - 1) * (btn_w + 2)
                imgui.set_cursor_pos(Vector2f.new(bx, btn_y))
                local sel = _sel_buttons[i]
                if sel then imgui.push_style_color(21, 0xFF00AA00) end
                if imgui.button(btn.label .. "##ov_btn", Vector2f.new(btn_w, 0)) then
                    if sel then _sel_buttons[i] = nil else _sel_buttons[i] = true end
                end
                if sel then imgui.pop_style_color(1) end
            end
            local btn_mask = get_combined_btn_mask()
            local play_y = btn_y + row_h
            local play_w = win_w - spacing * 2
            imgui.set_cursor_pos(Vector2f.new(spacing, play_y))
            local can_play = btn_mask > 0
            if can_play then
                imgui.push_style_color(21, 0xFF00AA00)
                imgui.push_style_color(22, 0xFF00CC00)
                imgui.push_style_color(23, 0xFF008800)
            else
                imgui.push_style_color(21, 0xFF444444)
                imgui.push_style_color(22, 0xFF444444)
                imgui.push_style_color(23, 0xFF444444)
            end
            if imgui.button("PLAY##ov_play", Vector2f.new(play_w, 0)) and can_play then
                local btn_names = {}
                for i, btn in ipairs(BUTTONS) do if _sel_buttons[i] then btn_names[#btn_names+1] = btn.label end end
                local mot_name = _sel_motion and MOTIONS[_sel_motion].label or ""
                state._move_label = mot_name ~= "" and (mot_name .. " " .. table.concat(btn_names, "+")) or table.concat(btn_names, "+")
                state.registering = false
                state.capturing = true
                state._capture_saw_action = false
                state._capture_idle = 0
                state.dp_ids = {}
                state.dp_name = nil

                reset_challenge()
                if _sel_motion then
                    _inject.seq = build_inject_seq(MOTIONS[_sel_motion], btn_mask)
                else
                    _inject.seq = { {f=3, m=0}, {f=3, m=btn_mask}, {f=5, m=0} }
                end
                _inject.step = 1
                _inject.frame = 0
                _inject.active = true
            end
            imgui.pop_style_color(3)
        end

        imgui.end_window()
    end
    imgui.pop_style_var(1)
    imgui.pop_style_color(4)
    if _dp_font then imgui.pop_font() end
end)

re.on_draw_ui(function()
    if _G.CurrentTrainerMode ~= 5 then return end
    if imgui.tree_node("MOVE EXECUTION DRILL") then
        imgui.text("Side: " .. (state.side == 1 and "P1" or "P2"))
        imgui.text("Count: " .. state.count .. " / " .. TOTAL)
        if next(state.dp_ids) then
            imgui.text("Action IDs: " .. (state.dp_name or "..."))
        end
        if state.last_detail then
            imgui.text(state.last_detail)
        end
        imgui.tree_pop()
    end
end)
