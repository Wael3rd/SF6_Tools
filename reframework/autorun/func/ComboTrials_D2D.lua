-- =========================================================
-- ComboTrials_D2D.lua -- D2D overlay rendering (icons, trial box)
-- Receives shared context (ctx) from the main file.
-- =========================================================

local d2d = d2d
local sdk = sdk
local imgui = imgui

local M = {}
local ModernDisplay = require("func/ModernDisplay")

-- Shared context (set by init)
local ctx -- { d2d_cfg, trial_state, players, sf6_menu_state }

local assets = { font = nil, last_pixel_size = -1, imgs = {} }
local d2d_anim = { active_y = nil }

local image_files = {
    ["1"] = "1.png",
    ["2"] = "2.png",
    ["3"] = "3.png",
    ["4"] = "4.png",
    ["5"] = "5.png",
    ["6"] = "6.png",
    ["7"] = "7.png",
    ["8"] = "8.png",
    ["9"] = "9.png",
    ["lp"] = "lp.png",
    ["mp"] = "mp.png",
    ["hp"] = "hp.png",
    ["lk"] = "lk.png",
    ["mk"] = "mk.png",
    ["hk"] = "hk.png",
    ["p"] = "P.png",
    ["k"] = "K.png",
    ["360"] = "360.png",
    ["4_hold"] = "4_HOLD.png",
    ["2_hold"] = "2_HOLD.png",
    ["6_hold"] = "6_HOLD.png",
    ["hcb"] = "HCB.png",
    ["hcf"] = "HCF.png",
    ["throw"] = "THROW.png",
    ["arrow"] = "arrow.png",
    ["arrow_success"] = "arrow_green.png",
    ["arrow_fail"] = "arrow_red.png",
    ["followup"] = "FollowUp.png",
    ["validfollowup"] = "validfollowup.png",
    ["cartouche"] = "cartouche.png",
    ["hold"] = "hold.png",
    ["plus"] = "PLUS.png",
    ["parry"] = "parry.png",
    ["dr"] = "dr.png",
    ["drc"] = "drc.png",
    ["rev"] = "rev.png",
    ["di"] = "DI.png",
    -- Modern-control button icons (SF6_TOOLS_CC). Assist "any"/neutral has no
    -- asset (modern_n.png absent upstream) so it stays as text.
    ["modern_l"] = "modern_l.png",
    ["modern_m"] = "modern_m.png",
    ["modern_h"] = "modern_h.png",
    ["modern_sp"] = "modern_sp.png",
    ["modern_auto"] = "modern_auto.png"
}

-- =========================================================
-- RAW INPUT SYSTEM (InputVisualiser-style integrated)
-- =========================================================
local raw_state = { history_p1 = {}, history_p2 = {} }

local function raw_get_numpad(dir_val)
    local u = (dir_val & 1) ~= 0
    local d = (dir_val & 2) ~= 0
    local r = (dir_val & 8) ~= 0
    local l = (dir_val & 4) ~= 0
    if u and l then return "7" elseif u and r then return "9" elseif d and l then return "1"
    elseif d and r then return "3" elseif u then return "8" elseif d then return "2"
    elseif l then return "4" elseif r then return "6" end
    return "5"
end

-- Modern-control button layout (probed in-game): the physical Modern buttons
-- set DISTINCT bits in pl_sw_new, but on Classic bit positions, so the classic
-- reader mislabels them. Remap by bit. Assist has no icon -> text "AS".
local MODERN_BTN_ORDER = {
    { 0x10,  "modern_l"  },  -- Light  (classic LP bit)
    { 0x80,  "modern_m"  },  -- Medium (classic LK bit)
    { 0x100, "modern_h"  },  -- Heavy  (classic MK bit)
    { 0x20,  "modern_sp" },  -- Special(classic MP bit)
    { 0x200, "modern_as" },  -- Assist (classic HK bit) -- no icon, text fallback
}

local function raw_get_buttons(val, is_modern)
    local list = {}
    if is_modern then
        for _, pair in ipairs(MODERN_BTN_ORDER) do
            if (val & pair[1]) ~= 0 then table.insert(list, pair[2]) end
        end
        return list
    end
    if (val & 16) ~= 0  then table.insert(list, "lp") end
    if (val & 32) ~= 0  then table.insert(list, "mp") end
    if (val & 64) ~= 0  then table.insert(list, "hp") end
    if (val & 128) ~= 0 then table.insert(list, "lk") end
    if (val & 256) ~= 0 then table.insert(list, "mk") end
    if (val & 512) ~= 0 then table.insert(list, "hk") end
    return list
end

-- Per-player Modern control detection (InputType==1), cached ~1x/sec since the
-- control type is fixed for a session (matches the combo-display auto-detect).
local _raw_pmode, _raw_pmode_tick = {}, 0
local function player_is_modern(idx)
    _raw_pmode_tick = _raw_pmode_tick + 1
    if _raw_pmode[idx] == nil or (_raw_pmode_tick % 120) == 0 then
        local modern = false
        pcall(function()
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            local sm = tm and tm:get_field("_tData") and tm:get_field("_tData"):get_field("SelectMenu")
            local pd = sm and sm.PlayerDatas and sm.PlayerDatas[idx]
            if pd and tonumber(pd.InputType) == 1 then modern = true end
        end)
        _raw_pmode[idx] = modern
    end
    return _raw_pmode[idx]
end

local function raw_update_history(history, d, b, max_size)
    local top = history[1]
    if top and (d == top.dir) and (b == top.btn) and top.active then
        top.frames = top.frames + 1
    else
        table.insert(history, 1, { dir = d, btn = b, frames = 1, active = true })
        while #history > max_size do table.remove(history) end
    end
end

local function _ctd_raw_read_inputs_inner(p_idx, history, max_size)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return end
    local mgr = gBattle:get_field("Player"):get_data(nil)
    if not mgr then return end
    local p = mgr:call("getPlayer", p_idx)
    if not p then return end
    local d = p:get_type_definition():get_field("pl_input_new"):get_data(p) or 0
    local b = p:get_type_definition():get_field("pl_sw_new"):get_data(p) or 0
    raw_update_history(history, d, b, max_size)
end

local function raw_read_inputs(p_idx, history, max_size)
    pcall(_ctd_raw_read_inputs_inner, p_idx, history, max_size)
end

-- Helper: apply mirror transform to position and flip
local function apply_mirror(pos, flip)
    return { x = 1.0 - pos.x, y = pos.y }, not flip
end

-- =========================================================
-- Follow-up group helpers
-- =========================================================
local function build_display_lines(sequence)
    local lines = {}
    for i, step in ipairs(sequence) do
        local gid = step.group_id or i
        if #lines == 0 or lines[#lines].group_id ~= gid then
            table.insert(lines, { group_id = gid, first = i, last = i, steps = { step } })
        else
            lines[#lines].last = i
            table.insert(lines[#lines].steps, step)
        end
    end
    return lines
end

-- Modern-control notation active? Manual toggle, or auto for a Modern-recorded
-- combo. Shared by the combo display, the single-step path, and the input log.
local function modern_display_active()
    return (ctx and ctx.d2d_cfg and (ctx.d2d_cfg.show_modern_notation or _G.ComboTrials_CurrentIsModern)) and true or false
end

-- Character to resolve Modern notation for the combo display.
local function combo_modern_char()
    if not modern_display_active() then return nil end
    local ts = ctx and ctx.trial_state
    local players = ctx and ctx.players
    local function player_char(idx)
        local p = players and players[idx or 0]
        if p and p.profile_name and p.profile_name ~= "Unknown" then return p.profile_name end
        return nil
    end
    -- During recording the combo file doesn't exist yet (CurrentPath may be a
    -- stale previous selection), so use the active player's character directly.
    if ts and ts.is_recording then
        local c = player_char(ts.recording_player or 0)
        if c then return c end
    end
    -- Playback: the saved combo file's character.
    local ok, r = pcall(ModernDisplay.char_from_path, _G.ComboTrials_CurrentPath)
    if ok and r then return r end
    -- General fallback to the playing character.
    return ts and player_char(ts.playing_player or 0) or nil
end

-- Return a display item for `step` with its Modern notation resolved for
-- `char`, or the step unchanged when Modern is off / no char / no mapping.
-- Never mutates the original step (shallow-copies only when it changes).
local function with_modern_motion(step, char)
    if not step or not char or not modern_display_active() then return step end
    local ok, mm = pcall(ModernDisplay.get_motion, char, step)
    if not ok or not mm or mm == (step.motion or "") then return step end
    local copy = {}
    for k, v in pairs(step) do copy[k] = v end
    copy.motion = mm
    return copy
end

local function merge_group_log_item(steps)
    local motions = {}

    -- Count holdable steps
    local holdable_count = 0
    for _, s in ipairs(steps) do
        if s.is_holdable then holdable_count = holdable_count + 1 end
    end

    local first_holdable_done = false
    local _md_char = nil
    -- Modern notation: manual toggle OR the combo was recorded in Modern (auto).
    if ctx and ctx.d2d_cfg and (ctx.d2d_cfg.show_modern_notation or _G.ComboTrials_CurrentIsModern) then
        local ok, r = pcall(ModernDisplay.char_from_path, _G.ComboTrials_CurrentPath)
        _md_char = ok and r or nil
    end
    for _, s in ipairs(steps) do
        local m = s.motion or ""
        -- Modern-control notation (opt-in): replace with Modern display when
        -- a mapping exists for this step; falls back to the classic motion.
        if _md_char then
            local ok, mm = pcall(ModernDisplay.get_motion, _md_char, s)
            if ok and mm then m = mm end
        end
        -- For follow-ups: ensure > is BEFORE [AIR]/J. (not reversed)
        m = m:gsub("^(%[AIR%])%s*(>)", "%2%1")
        m = m:gsub("^(J%.)%s*(>)", "%2%1")
        if s.is_holdable then
            if holdable_count > 3 then
                -- Only display the first holdable with "(xN)", ignore the rest
                if not first_holdable_done then
                    first_holdable_done = true
                    table.insert(motions, m)
                end
                -- subsequent ones: not added
            else
                -- 3 or fewer: individual hold on each step
                local frames = s.hold_frames
                if frames and frames > 0 then
                    m = m .. " (Hold " .. frames .. ")"
                else
                    m = m .. " (Hold)"
                end
                table.insert(motions, m)
            end
        else
            table.insert(motions, m)
        end
    end

    local first = steps[1]
    local last  = steps[#steps]
    local all_hit = true
    for _, s in ipairs(steps) do if not s.has_hit then all_hit = false; break end end

    return {
        motion         = table.concat(motions, " "),
        is_holdable    = false,  -- handled inline in the motion
        hold_repeat    = holdable_count > 3 and holdable_count or nil,
        expected_combo = last.expected_combo,
        actual_combo   = last.actual_combo,
        has_hit        = all_hit,
        combo_stats    = first.combo_stats,
        facing_left    = first.facing_left,
    }
end

-- =========================================================
-- parse_motion_to_icons
-- =========================================================
local function parse_motion_to_icons(log_entry, trial_mode, should_flip, reverse_layout)
    local d2d_cfg = ctx.d2d_cfg
    local is_modern = (ctx and ctx.d2d_cfg and (ctx.d2d_cfg.show_modern_notation or _G.ComboTrials_CurrentIsModern)) and true or false
    local motion_tokens = {}
    local s = log_entry.motion or ""

    -- Convert to uppercase IMMEDIATELY so that j. becomes J.
    s = s:upper()

    -- 1. Inline normalization of aerial state (J. -> [AIR], keeps each [AIR] at its position)
    s = s:gsub("J%.", "[AIR]")
    s = s:gsub("%[AIR%]%s*", "[AIR] ")

    -- 2. Command inversion (Visual Only) for P2
    if should_flip then
        -- Protect content inside parentheses (plain text, e.g. "(4 Medals)")
        -- Markers without digits so they are not affected by the swap
        local paren_store = {}
        s = s:gsub("(%b())", function(match)
            table.insert(paren_store, match)
            return "##P" .. string.char(64 + #paren_store) .. "##"
        end)

        -- Protect full circle motions
        s = s:gsub("720", "{C2}")
        s = s:gsub("360", "{C1}")
        s = s:gsub("5252", "{D2}")

        -- Swap left and right (1<->3, 4<->6, 7<->9)
        local swap = { ["1"] = "3", ["3"] = "1", ["4"] = "6", ["6"] = "4", ["7"] = "9", ["9"] = "7" }
        s = s:gsub("%d", function(c) return swap[c] or c end)

        -- Restore circle motions
        s = s:gsub("{C2}", "720")
        s = s:gsub("{C1}", "360")
        s = s:gsub("{D2}", "5252")

        -- Restore parentheses intact
        s = s:gsub("##P(.)##", function(c)
            return paren_store[string.byte(c) - 64]
        end)
    end

    local text_blocks = {}
    local text_idx = 0

    s = s:gsub("%(THROW%)", "{throw}")
    s = s:gsub("THROW", "{throw}")
    s = s:gsub("LP%+LK", "{throw}")

    s = s:gsub("FORWARD DASH", "{6}{6}")
    s = s:gsub("BACK DASH", "{4}{4}")
    s = s:gsub("5252", "{2}{2}")
    s = s:gsub("720", "{360}{360}")

    -- Auto-translate to icons (Parry and Drive Rush)
    s = s:gsub("MP%+MK %(PARRY%)", "{parry}") -- Intercept native game text
    s = s:gsub("%(PARRY_JUST_[LMH]%)", "{parry}")
    s = s:gsub("PARRY_JUST_[LMH]", "{parry}")
    s = s:gsub("%(PARRY_HIT_[LMH]%)", "{parry}")
    s = s:gsub("PARRY_HIT_[LMH]", "{parry}")
    s = s:gsub("%(PARRY%)", "{parry}")
    s = s:gsub("PARRY", "{parry}")

    s = s:gsub("HP%+HK", "{di}") -- Replace raw button combo
    s = s:gsub("DI", "{di}")     -- Replace DI keyword
    s = s:gsub("%(DI%)", "")     -- Remove leftover (DI)

    s = s:gsub("%(REVERSAL%)", "{rev}")
    s = s:gsub("REVERSAL", "{rev}")

    s = s:gsub("DRIVE RUSH CANCEL", "{drc}")
    s = s:gsub("%(DRC%)", "{drc}")
    s = s:gsub("DRC", "{drc}")

    s = s:gsub("RAW DR", "{dr}")
    s = s:gsub("DRIVE RUSH", "{dr}")
    s = s:gsub("%(DR%)", "{dr}")

    -- Break the parenthesis trap for follow-ups
    s = s:gsub("%(>%)", "{followup}")
    s = s:gsub("%(> (.-)%)", "{followup} %1")
    s = s:gsub(">", "{followup}")

    s = s:gsub("%(HOLD%)", "{hold}")
    s = s:gsub("%(HOLD (.-)%)", "{hold} (%1)")
    s = s:gsub("HOLD", "{hold}")

    s = s:gsub("63214", "{hcb}")
    s = s:gsub("41236", "{hcf}")
    s = s:gsub("%[4%]", "{4_hold}")
    s = s:gsub("%[2%]", "{2_hold}")
    s = s:gsub("%[6%]", "{6_hold}")
    s = s:gsub("360", "{360}")

    s = s:gsub("(%b())", function(match)
        text_idx = text_idx + 1
        text_blocks[text_idx] = match
        return string.format("{txt_%d}", text_idx)
    end)

    -- Modern-control button icons (opt-in). Convert bare strength tokens to
    -- icon markers; frontier patterns keep classic LP/MP/HP untouched.
    if is_modern then
        s = s:gsub("DP", "{parry}")   -- DP = Drive Parry in Modern shorthand
        s = s:gsub("AUTO", "{modern_auto}")
        s = s:gsub("%f[%a]SP%f[%A]", "{modern_sp}")
        s = s:gsub("%f[%a]L%f[%A]", "{modern_l}")
        s = s:gsub("%f[%a]M%f[%A]", "{modern_m}")
        s = s:gsub("%f[%a]H%f[%A]", "{modern_h}")
    end

    s = s:gsub("%f[%a]PPP%f[%A]", "{p}{p}{p}")
    s = s:gsub("%f[%a]PP%f[%A]", "{p}{p}")
    s = s:gsub("%f[%a]KKK%f[%A]", "{k}{k}{k}")
    s = s:gsub("%f[%a]KK%f[%A]", "{k}{k}")
    s = s:gsub("%f[%a]LP%f[%A]", "{lp}")
    s = s:gsub("%f[%a]MP%f[%A]", "{mp}")
    s = s:gsub("%f[%a]HP%f[%A]", "{hp}")
    s = s:gsub("%f[%a]LK%f[%A]", "{lk}")
    s = s:gsub("%f[%a]MK%f[%A]", "{mk}")
    s = s:gsub("%f[%a]HK%f[%A]", "{hk}")
    s = s:gsub("%f[%a]P%f[%A]", "{p}")
    s = s:gsub("%f[%a]K%f[%A]", "{k}")

    local i = 1
    local current_text = ""

    local function flush_text()
        if current_text ~= "" then
            local trimmed = current_text:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(motion_tokens, { type = "text", val = trimmed }) end
            current_text = ""
        end
    end

    while i <= #s do
        local c = s:sub(i, i)
        if c == "{" then
            flush_text()
            local end_idx = s:find("}", i)
            if end_idx then
                local tok = s:sub(i + 1, end_idx - 1)
                if tok:sub(1, 4) == "txt_" then
                    local idx = tonumber(tok:sub(5))
                    table.insert(motion_tokens, { type = "text", val = text_blocks[idx] })
                else
                    table.insert(motion_tokens, { type = "img", val = tok:lower() })
                end
                i = end_idx + 1
            else
                i = i + 1
            end
        elseif c:match("%d") then
            flush_text()
            if c ~= "0" then table.insert(motion_tokens, { type = "img", val = c }) end
            i = i + 1
        elseif c == "+" then
            flush_text()
            i = i + 1
        else
            current_text = current_text .. c
            i = i + 1
        end
    end
    flush_text()

    -- NEW: Auto-insert PLUS icon between directions and attack buttons
    local is_btn = { p = true, k = true, lp = true, mp = true, hp = true, lk = true, mk = true, hk = true, throw = true,
        modern_l = true, modern_m = true, modern_h = true, modern_sp = true, modern_auto = true }
    local processed_tokens = {}
    for _, tok in ipairs(motion_tokens) do
        if #processed_tokens > 0 then
            local prev = processed_tokens[#processed_tokens]
            if tok.type == "img" and is_btn[tok.val] then
                if prev.type == "img" and not is_btn[prev.val] and prev.val ~= "plus" and prev.val ~= "followup" and prev.val ~= "validfollowup" then
                    table.insert(processed_tokens, { type = "img", val = "plus" })
                end
            end
        end
        table.insert(processed_tokens, tok)
    end
    motion_tokens = processed_tokens

    -- Swap validated followups -> validfollowup
    if log_entry.validated_followups and log_entry.validated_followups > 0 then
        local swapped = 0
        for _, tok in ipairs(motion_tokens) do
            if swapped >= log_entry.validated_followups then break end
            if tok.type == "img" and tok.val == "followup" then
                tok.val = "validfollowup"
                swapped = swapped + 1
            end
        end
    end

    -- 3. Hold status handling
    local hold_tokens = {}
    if log_entry.hold_repeat then
        -- Repeated hold case (>3): hold icon + "(xN)"
        table.insert(hold_tokens, { type = "img",  val = "hold" })
        table.insert(hold_tokens, { type = "text", val = "(x" .. log_entry.hold_repeat .. ")", col = 0xFFFFFFFF })
    elseif log_entry.is_holdable then
        local frames = log_entry.hold_frames or 0
        local status = log_entry.charge_status or "Charging"

        -- Universal Math Logic: Independent of engine's is_holding flag
        if log_entry.charge_min and log_entry.charge_max then
            if frames <= log_entry.charge_min then
                status = "Instant"
            elseif frames >= log_entry.charge_max then
                status = "Maxed"
            else
                status = "Partial"
            end
        elseif log_entry.charge_min then
            if frames <= log_entry.charge_min then
                status = "Instant"
            else
                status = "Partial"
            end
        end

        -- Preserve specific engine statuses like perfect timing
        if log_entry.charge_status == "PERFECT!" or log_entry.charge_status == "FAKE" or log_entry.charge_status == "Maxed" or log_entry.charge_status == "LATE" then
            status = log_entry.charge_status
        end

        local col = 0xFFFFFFFF -- White (Instant default)
        local show_icon = false

        if status == "Instant" then
            col = 0xFFFFFFFF
            show_icon = false
        elseif status:match("Partial") then
            col = 0xFFFFA500 -- Orange
            show_icon = true
        elseif status:match("Maxed") or status == "PERFECT!" or status == "FAKE" then
            col = 0xFFFFFF00 -- Yellow
            show_icon = true
        elseif status == "LATE" then
            col = 0xFFFF0000 -- Red
            show_icon = true
        elseif status == "Lv1" then
            col = 0xFF00AAFF  -- Orange (ABGR)
            show_icon = true
        elseif status == "Lv2" then
            col = 0xFF00FFFF  -- Yellow (ABGR)
            show_icon = true
        else
            if frames > 0 then show_icon = true end
        end

        -- Always show frames, but hide the yellow icon if Instant
        local charge_str = ""
        if frames > 0 then
            charge_str = string.format("(%d)", frames)
        else
            charge_str = "(Hold)"
        end

        if show_icon then table.insert(hold_tokens, { type = "img", val = "hold" }) end
        table.insert(hold_tokens, { type = "text", val = charge_str, col = col })
    end

    -- 4. Combo counter management
    local combo_token = nil
    if d2d_cfg.show_combo_count then
        if trial_mode == "playing" then
            if log_entry.expected_combo ~= nil and log_entry.expected_combo > 0 then
                local actual = log_entry.actual_combo or 0
                local col = (actual >= log_entry.expected_combo) and 0xFF00FF00 or 0xFF888888
                combo_token = {
                    type = "text",
                    val = string.format("[Combo: %d / %d]", actual, log_entry.expected_combo),
                    col = col
                }
            end
        elseif trial_mode == "recording" or trial_mode == "saved" then
            if log_entry.expected_combo ~= nil and log_entry.expected_combo > 0 then
                combo_token = { type = "text", val = string.format("[Combo: %d]", log_entry.expected_combo), col = 0xFF00FF00 }
            end
        elseif trial_mode == "log" then
            if log_entry.combo_count ~= nil and log_entry.combo_count > 0 then
                combo_token = { type = "text", val = string.format("[Combo: %d]", log_entry.combo_count), col = 0xFF00FF00 }
            end
        end
    end

    -- 5. ASSEMBLY (Inline: each [AIR] and (XXX) stays at its natural position)
    local final_tokens = {}
    if reverse_layout then
        if combo_token then
            table.insert(final_tokens, { type = "text", val = combo_token.val .. " ", col = combo_token.col })
        end

        for _, t in ipairs(motion_tokens) do table.insert(final_tokens, t) end

        if #hold_tokens > 0 then table.insert(final_tokens, { type = "text", val = " " }) end
        for _, t in ipairs(hold_tokens) do
            if t.type == "text" then
                table.insert(final_tokens, { type = "text", val = t.val .. " ", col = t.col })
            else
                table.insert(final_tokens, t)
            end
        end
    else
        for _, t in ipairs(motion_tokens) do table.insert(final_tokens, t) end

        if #hold_tokens > 0 then table.insert(final_tokens, { type = "text", val = " " }) end
        for _, t in ipairs(hold_tokens) do table.insert(final_tokens, t) end

        if combo_token then
            table.insert(final_tokens, { type = "text", val = " " .. combo_token.val, col = combo_token.col })
        end
    end

    -- Tag (CH) or (PC) per step
    local ct = log_entry.counter_type
    if ct == 1 then
        table.insert(final_tokens, { type = "text", val = " (CH)", col = 0xFFFFFFFF })
    elseif ct == 2 then
        table.insert(final_tokens, { type = "text", val = " (PC)", col = 0xFFFFFFFF })
    end

    return final_tokens
end

-- =========================================================
-- get_d2d_logs
-- =========================================================
local function get_d2d_logs(p_log, max_count)
    local limit = max_count or ctx.d2d_cfg.max_history
    local draw_logs = {}
    for _, log in ipairs(p_log) do
        local is_gray = not log.intentional
        if not (ctx.d2d_cfg.ignore_auto and is_gray) then
            table.insert(draw_logs, log)
            if #draw_logs >= limit then break end
        end
    end
    return draw_logs
end

-- =========================================================
-- draw_parsed_line
-- =========================================================
local function draw_parsed_line(tokens, base_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, align_right,
                                color_override)
    -- Wide badge icons scaled up for readability. modern_sp/modern_auto are the
    -- same wide-badge shape as parry/di, so they get the same scale (the square
    -- modern_l/m/h already fill the box at 1.0).
    local special_icons = { dr = true, drc = true, parry = true, rev = true, di = true,
        modern_sp = true, modern_auto = true }
    local line_elements = {}
    local total_w = 0

    for _, tok in ipairs(tokens) do
        if tok.type == "img" then
            if assets.imgs[tok.val] then
                local scale = (special_icons[tok.val] and ctx.d2d_cfg.special_icon_scale or 1.0)
                local current_w = icon_w * scale
                table.insert(line_elements, { type = "img", val = tok.val, w = current_w, scale = scale })
                total_w = total_w + current_w + spacing_x
            end
        elseif tok.type == "text" then
            local text_to_draw = tok.val
            if tok.val:match("{hold}") then
                table.insert(line_elements, { type = "img", val = "hold", w = icon_w, scale = 1.0 })
                total_w = total_w + icon_w + spacing_x
                text_to_draw = tok.val:gsub("{hold}%s*", "")
            end
            local w = 0
            if assets.font then w, _ = assets.font:measure(text_to_draw) end
            table.insert(line_elements, { type = "text", val = text_to_draw, w = w, col = tok.col })
            total_w = total_w + w + spacing_x
        end
    end
    if total_w > 0 then total_w = total_w - spacing_x end

    local cur_x = base_x
    if align_right then cur_x = base_x - total_w end

    for _, elem in ipairs(line_elements) do
        if elem.type == "img" then
            local img = assets.imgs[elem.val]
            if img then
                local current_h = icon_h * elem.scale
                local offset_y = (current_h - icon_h) / 2
                d2d.image(img, cur_x, y - offset_y, elem.w, current_h)
            end
            cur_x = cur_x + elem.w + spacing_x
        elseif elem.type == "text" then
            if assets.font then
                local text_color = color_override or elem.col or 0xFFFFFFFF
                d2d.text(assets.font, elem.val, cur_x + 2, y + final_text_y_offset + 2, 0xFF000000)
                d2d.text(assets.font, elem.val, cur_x, y + final_text_y_offset, text_color)
            end
            cur_x = cur_x + elem.w + spacing_x
        end
    end
    return total_w
end

-- =========================================================
-- d2d_init & d2d_draw
-- =========================================================
local _img_arrow_down = nil
local _img_arrow_up = nil

local function d2d_init()
    local folder = "buttonsAndArrows/"
    for k, filename in pairs(image_files) do
        assets.imgs[k] = d2d.Image.new(folder .. filename)
    end
    _img_arrow_down = d2d.Image.new("ui_icons/chevron_down_ios.png")
    _img_arrow_up = d2d.Image.new("ui_icons/chevron_up_ios.png")
    assets.imgs["done_bar"] = d2d.Image.new("done-bar.png")
    assets.imgs["active_bar"] = d2d.Image.new("active-bar.png")
    assets.imgs["fail_bar"] = d2d.Image.new("fail-bar.png")
    assets.imgs["success_bar"] = d2d.Image.new("success-bar.png")
end

local function draw_bar_toggle_arrows()
    if not ((_G.IsInReplay == true) or (_G.FlowMapID == 10) or (_G.IsInBattleHub == true)) then return end
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pb = pm:get_field("_CurrentPauseTypeBit")
        if pb ~= 64 and pb ~= 2112 then return end
    end
    local geo = _G._ct_bar_geometry
    if not geo then return end

    local sw, sh = d2d.surface_size()
    local collapsed = (_G._ct_bar_collapsed == true)
    local icon_sz = math.floor(sh * 0.022)
    local margin_x = math.floor(sw * 0.008)
    local arrow_y = sh - icon_sz - math.floor(sh * 0.012)

    local lx = margin_x
    local rx = sw - margin_x - icon_sz

    local img = collapsed and _img_arrow_up or _img_arrow_down
    if img then
        d2d.image(img, lx, arrow_y, icon_sz, icon_sz)
        d2d.image(img, rx, arrow_y, icon_sz, icon_sz)
    end

    -- Click detection
    if imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m then
            local pad = 10
            if (m.x >= lx - pad and m.x <= lx + icon_sz + pad and m.y >= arrow_y - pad and m.y <= arrow_y + icon_sz + pad) or
               (m.x >= rx - pad and m.x <= rx + icon_sz + pad and m.y >= arrow_y - pad and m.y <= arrow_y + icon_sz + pad) then
                _G._ct_bar_collapsed = not _G._ct_bar_collapsed
            end
        end
    end
end

local function d2d_draw_inner()
    local d2d_cfg = ctx and ctx.d2d_cfg
    local trial_state = ctx and ctx.trial_state
    local players = ctx and ctx.players

    local should_draw = d2d_cfg and d2d_cfg.enabled

    local sw, sh = d2d.surface_size()

    -- The d2d_draw wrapper only calls this when on_frame set the per-frame beat
    -- (same self-clearing pattern as Distance Viewer's queue), so a paused
    -- on_frame on the VS/match screen means no draw. NO early returns below.
    if should_draw and _G.TrainingBarsDrawn and _G.CurrentTrainerMode == 4 then

    ctx.cached_sw, ctx.cached_sh = sw, sh

    -- SF6 NEON MENU BACKGROUND: handled by NeonBarQueue from ComboTrials_UI on_frame only


    local pixel_font_h = d2d_cfg.font_size * sh
    if math.abs(assets.last_pixel_size - pixel_font_h) > 1.0 or assets.font == nil then
        assets.font = d2d.Font.new("capcom_goji-udkakugoc80pro-db.ttf", math.floor(pixel_font_h))
        assets.last_pixel_size = pixel_font_h
    end

    local icon_h = d2d_cfg.icon_size * sh
    local icon_w = icon_h
    local spacing_y = d2d_cfg.spacing_y * sh
    local spacing_x = d2d_cfg.spacing_x * sh

    local base_text_y = (icon_h - pixel_font_h) / 2
    local final_text_y_offset = base_text_y + (d2d_cfg.text_y_offset * sh)

    local function draw_player_icons(p_idx, base_x, base_y, align_right, max_count, reverse_layout)
        local logs_to_draw = get_d2d_logs(players[p_idx].log, max_count)
        local _log_char = players[p_idx] and players[p_idx].profile_name or nil
        for i, log in ipairs(logs_to_draw) do
            local y = base_y + (i - 1) * spacing_y
            local should_flip = log.facing_left or false
            local tokens = parse_motion_to_icons(with_modern_motion(log, _log_char), "log", should_flip, reverse_layout)
            draw_parsed_line(tokens, base_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, align_right, nil)
        end
    end

    -- RAW INPUT DRAW (InputVisualiser-style, uses d2d_cfg.raw.* settings)
    local function draw_raw_player(history, base_x, base_y, is_right_side, max_count, player_idx)
        local rc = d2d_cfg.raw or {}
        local r_icon = (rc.icon_size or 0.030) * sh
        local r_spacing_y = (rc.spacing_y or 0.040) * sh
        local r_text_y = (rc.text_y_offset or 0.002) * sh
        local mirror = is_right_side and -1.0 or 1.0
        local raw_modern = player_is_modern(player_idx or 0)

        local r_font = assets.font
        local ref_w = 0
        if r_font then ref_w, _ = r_font:measure("99") end

        local slots = {
            rc.col_frame or 0.000, rc.col_dir or 0.050,
            rc.slot1 or 0.100, rc.slot2 or 0.140, rc.slot3 or 0.180,
            rc.slot4 or 0.220, rc.slot5 or 0.260, rc.slot6 or 0.300
        }

        for i, entry in ipairs(history) do
            if i > max_count then break end
            if entry.active then
                local y = base_y + (i - 1) * r_spacing_y

                if r_font then
                    local txt = tostring(entry.frames > 99 and 99 or entry.frames)
                    local w, _ = r_font:measure(txt)
                    local off_x = slots[1] * sh * mirror
                    local anchor_x = base_x + off_x
                    local fx = is_right_side and (anchor_x + (ref_w - w)) or (anchor_x - w)
                    d2d.text(r_font, txt, fx + 2, y + r_text_y + 2, 0xFF000000)
                    d2d.text(r_font, txt, fx, y + r_text_y, 0xFFFFFFFF)
                end

                local dir_str = raw_get_numpad(entry.dir)
                local img_dir = assets.imgs[dir_str]
                if img_dir then
                    local off_x = slots[2] * sh * mirror
                    local fx = base_x + off_x
                    if is_right_side then fx = fx - r_icon end
                    d2d.image(img_dir, fx, y, r_icon, r_icon)
                end

                if entry.btn >= 16 then
                    local files = raw_get_buttons(entry.btn, raw_modern)
                    for idx, fname in ipairs(files) do
                        if slots[idx + 2] then
                            local off_x = slots[idx + 2] * sh * mirror
                            local fx = base_x + off_x
                            if is_right_side then fx = fx - r_icon end
                            local img_btn = assets.imgs[fname]
                            if img_btn then
                                d2d.image(img_btn, fx, y, r_icon, r_icon)
                            elseif fname == "modern_as" and r_font then
                                -- Assist has no icon; draw "AS" text in the slot.
                                d2d.text(r_font, "AS", fx + 2, y + r_text_y + 2, 0xFF000000)
                                d2d.text(r_font, "AS", fx, y + r_text_y, 0xFFFFFFFF)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Who is active in the trial?
    local target_trial_p = -1
    if trial_state.is_recording then
        target_trial_p = trial_state.recording_player
    elseif trial_state.is_playing then
        target_trial_p = trial_state.playing_player
    end

    local in_trial = (trial_state.is_recording or trial_state.is_playing)

    -- Resolve per-mode config
    local live_show_p1, live_show_p2, live_max
    local live_raw_p1, live_raw_p2, live_raw_max
    local live_mirror_p1, live_mirror_p2
    local base_pos_p1, base_pos_p2
    local base_raw_pos_p1, base_raw_pos_p2

    if in_trial then
        live_show_p1 = d2d_cfg.show_p1;       live_show_p2 = d2d_cfg.show_p2
        live_raw_p1  = d2d_cfg.raw_p1 or false; live_raw_p2 = d2d_cfg.raw_p2 or false
        live_mirror_p1 = d2d_cfg.mirror_p1 or false; live_mirror_p2 = d2d_cfg.mirror_p2 or false
        base_pos_p1  = d2d_cfg.pos_p1;        base_pos_p2 = d2d_cfg.pos_p2
        base_raw_pos_p1 = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
        base_raw_pos_p2 = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
        live_max     = d2d_cfg.max_history
        live_raw_max = d2d_cfg.raw_max_history or 19
    else
        live_show_p1 = d2d_cfg.idle_show_p1;   live_show_p2 = d2d_cfg.idle_show_p2
        live_raw_p1  = d2d_cfg.idle_raw_p1 or false; live_raw_p2 = d2d_cfg.idle_raw_p2 or false
        live_mirror_p1 = d2d_cfg.idle_mirror_p1 or false; live_mirror_p2 = d2d_cfg.idle_mirror_p2 or false
        base_pos_p1  = d2d_cfg.idle_pos_p1;   base_pos_p2 = d2d_cfg.idle_pos_p2
        base_raw_pos_p1 = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1  -- idle raw uses trial raw positions as base
        base_raw_pos_p2 = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
        live_max     = d2d_cfg.idle_max_history
        live_raw_max = d2d_cfg.idle_raw_max_history or 19
    end

    -- NON-RAW : base alignment (P1=left in trial, P2=always right)
    local nr_align_p1 = in_trial
    local nr_align_p2 = true

    -- Apply mirror to non-raw
    local nr_pos_p1, nr_pos_p2 = base_pos_p1, base_pos_p2
    if live_mirror_p1 then nr_pos_p1, nr_align_p1 = apply_mirror(base_pos_p1, nr_align_p1) end
    if live_mirror_p2 then nr_pos_p2, nr_align_p2 = apply_mirror(base_pos_p2, nr_align_p2) end

    -- RAW : base flip (P1=left, P2=right)
    local raw_flip_p1 = false
    local raw_flip_p2 = true
    local raw_pos_p1, raw_pos_p2 = base_raw_pos_p1, base_raw_pos_p2

    -- Apply mirror to raw
    if live_mirror_p1 then raw_pos_p1, raw_flip_p1 = apply_mirror(base_raw_pos_p1, raw_flip_p1) end
    if live_mirror_p2 then raw_pos_p2, raw_flip_p2 = apply_mirror(base_raw_pos_p2, raw_flip_p2) end

    -- Read raw inputs
    if live_show_p1 and live_raw_p1 then raw_read_inputs(0, raw_state.history_p1, live_raw_max) end
    if live_show_p2 and live_raw_p2 then raw_read_inputs(1, raw_state.history_p2, live_raw_max) end

    -- DRAW P1
    if live_show_p1 then
        if live_raw_p1 then
            draw_raw_player(raw_state.history_p1, raw_pos_p1.x * sw, raw_pos_p1.y * sh, raw_flip_p1, live_raw_max, 0)
        else
            draw_player_icons(0, nr_pos_p1.x * sw, nr_pos_p1.y * sh, nr_align_p1, live_max, in_trial)
        end
    end
    -- DRAW P2
    if live_show_p2 then
        if live_raw_p2 then
            draw_raw_player(raw_state.history_p2, raw_pos_p2.x * sw, raw_pos_p2.y * sh, raw_flip_p2, live_raw_max, 1)
        else
            draw_player_icons(1, nr_pos_p2.x * sw, nr_pos_p2.y * sh, nr_align_p2, live_max, true)
        end
    end

    -- TRIAL HEADER (Removed as it's now handled by the UI HUD Overlay)

    -- TRIAL CARTOUCHE (Scrolling sequence display)
    if target_trial_p ~= -1 then
        local trial_x = (d2d_cfg.pos_trial_p1 and d2d_cfg.pos_trial_p1.x or d2d_cfg.pos_p1.x) * sw
        local trial_y = (d2d_cfg.pos_trial_p1 and d2d_cfg.pos_trial_p1.y or d2d_cfg.pos_p1.y) * sh
        local is_aligned_right = false
        local visible = d2d_cfg.trial_visible_steps
        local cartouche_w = d2d_cfg.cartouche_width * sw

        local mode = "saved"
        if trial_state.is_recording then
            mode = "recording"
        elseif trial_state.is_playing then
            mode = "playing"
        end

        local is_succ = (trial_state.success_timer > 0)
        local padding_y = spacing_y * 0.15
        local rect_x = is_aligned_right and (trial_x - cartouche_w + spacing_x * 2) or (trial_x - spacing_x * 2)
        local target_anim_y = nil
        local active_bg_h = spacing_y * (d2d_cfg.cartouche_height or 1.0)
        local done_bg_h = spacing_y * (d2d_cfg.done_bar_height or 1.0)
        local overlay_h = spacing_y * (d2d_cfg.overlay_height or 1.0)
        local d_off_x = (d2d_cfg.done_bar_offset_x or 0) * sw
        local d_off_y = (d2d_cfg.done_bar_offset_y or 0) * sh
        local ov_off_y = (d2d_cfg.overlay_offset_y or 0) * sh
        local dbg = _G._ct_debug or {}
        local preview = dbg.preview_mode or 1
        local c_off_x = (d2d_cfg.cartouche_offset_x or 0) * sw
        local c_off_y = (d2d_cfg.cartouche_offset_y or 0) * sh
        local b_off_x = (d2d_cfg.bar_img_offset_x or 0) * sw
        local b_off_y = (d2d_cfg.bar_img_offset_y or 0) * sh
        local final_rect_x = rect_x + c_off_x

        -- Build display lines (follow-up groups)
        local display_lines = build_display_lines(trial_state.sequence)
        local n_lines = #display_lines

        -- Find the active display_line (the one containing current_step)
        local raw_visual_dl = 1
        for dl_idx, dl in ipairs(display_lines) do
            if trial_state.current_step >= dl.first and trial_state.current_step <= dl.last then
                raw_visual_dl = dl_idx
                break
            end
            if trial_state.current_step > dl.last then
                raw_visual_dl = dl_idx + 1
            end
        end
        if raw_visual_dl > n_lines then raw_visual_dl = n_lines end

        -- VISUAL FREEZE: Wait for button release (LILY ONLY)
        local visual_dl = raw_visual_dl
        

        -- Scroll
        local start_idx = 1
        if mode == "recording" then
            start_idx = math.max(1, n_lines - math.floor(visible / 2))
        else
            start_idx = math.max(1, visual_dl - math.floor(visible / 2))
            if start_idx + visible - 1 > n_lines then
                start_idx = math.max(1, n_lines - visible + 1)
            end
        end

        -- Animation target Y
        if mode == "playing" and n_lines > 0 then
            target_anim_y = trial_y + (visual_dl - start_idx) * spacing_y
        elseif mode == "recording" and n_lines > 0 then
            target_anim_y = trial_y + (n_lines - start_idx) * spacing_y
        end

        -- Completed step backgrounds (or preview mode)
        local preview_imgs = {nil, assets.imgs["active_bar"], assets.imgs["done_bar"], assets.imgs["fail_bar"], assets.imgs["success_bar"], assets.imgs["success_bar"], nil}
        local preview_heights = {0, active_bg_h, done_bg_h, active_bg_h, active_bg_h, active_bg_h, overlay_h}

        if preview > 1 then
            for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
                local cur_y_pos = trial_y + (dl_idx - start_idx) * spacing_y
                local sy = cur_y_pos - padding_y + c_off_y
                local p_img = preview_imgs[preview]
                local p_h = preview_heights[preview]
                if preview == 7 then
                    d2d.fill_rect(final_rect_x, sy + ov_off_y + 3, cartouche_w, p_h - 6, d2d_cfg.colors.bg_overlay or 0x85000000)
                elseif p_img then
                    local ox = (preview == 3) and d_off_x or b_off_x
                    local oy = (preview == 3) and d_off_y or b_off_y
                    d2d.image(p_img, final_rect_x + ox, sy + oy, cartouche_w, p_h)
                end
            end
        elseif mode == "playing" then
            for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
                local cur_y_pos = trial_y + (dl_idx - start_idx) * spacing_y
                if is_succ or (dl_idx < visual_dl) then
                    local sy = cur_y_pos - padding_y + c_off_y
                    if assets.imgs["done_bar"] then
                        d2d.image(assets.imgs["done_bar"], final_rect_x + d_off_x, sy + d_off_y, cartouche_w, done_bg_h)
                    else
                        d2d.fill_rect(final_rect_x, sy, cartouche_w, done_bg_h, d2d_cfg.colors.bg_success)
                        d2d.fill_rect(final_rect_x, sy, cartouche_w, 1, d2d_cfg.colors.bg_success_line)
                        d2d.fill_rect(final_rect_x, sy + done_bg_h - 1, cartouche_w, 1, d2d_cfg.colors.bg_success_line)
                    end
                end
            end
        end

        -- Animated cursor
        if target_anim_y then
            local is_fail_or_reset = (trial_state.fail_timer and trial_state.fail_timer > 0)
            if is_fail_or_reset then
                -- Teleport cartouche to step 1 instantly during fail/reload
                local reset_y = trial_y + (1 - start_idx) * spacing_y
                d2d_anim.active_y = reset_y
                target_anim_y = reset_y
            elseif not d2d_anim.active_y or math.abs(d2d_anim.active_y - target_anim_y) > (spacing_y * 3) then
                d2d_anim.active_y = target_anim_y
            end
            d2d_anim.active_y = d2d_anim.active_y + (target_anim_y - d2d_anim.active_y) * 0.15

            local is_fail_state = (trial_state.fail_timer and trial_state.fail_timer > 0)
            if dbg.force_fail then is_fail_state = true end
            if dbg.force_success then is_succ = true end
            local bar_img = nil
            local bar_visible = true
            if mode == "recording" then
                bar_img = assets.imgs["success_bar"]
                if dbg.show_recording == false then bar_visible = false end
            elseif is_succ then
                bar_img = assets.imgs["success_bar"]
                if dbg.show_success == false then bar_visible = false end
            elseif is_fail_state then
                bar_img = assets.imgs["fail_bar"]
                if dbg.show_fail == false then bar_visible = false end
            else
                bar_img = assets.imgs["active_bar"]
                if dbg.show_active == false then bar_visible = false end
            end

            local sy = d2d_anim.active_y - padding_y + c_off_y
            if preview > 1 or not bar_visible then
            elseif bar_img then
                d2d.image(bar_img, final_rect_x + b_off_x, sy + b_off_y, cartouche_w, active_bg_h)
            else
                local bg_c, li_c = d2d_cfg.colors.bg_active, d2d_cfg.colors.bg_active_line
                if mode == "recording" then
                    bg_c = 0x90FF0000; li_c = 0xFFFF0000
                elseif is_succ then
                    bg_c = 0x80004400; li_c = 0xFF00FF00
                elseif is_fail_state then
                    bg_c = d2d_cfg.colors.bg_fail; li_c = d2d_cfg.colors.bg_fail_line
                end
                d2d.fill_rect(final_rect_x, sy, cartouche_w, active_bg_h, bg_c)
                d2d.fill_rect(final_rect_x, sy, cartouche_w, 3, li_c)
                d2d.fill_rect(final_rect_x, sy + active_bg_h - 3, cartouche_w, 3, li_c)
            end
        else
            d2d_anim.active_y = nil
        end

        -- Draw text and icons for each visible display line
        for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
            local dl = display_lines[dl_idx]
            -- Single-step groups bypass merge_group_log_item, so resolve their
            -- Modern notation here too (merge already handles multi-step groups).
            local log_item = (#dl.steps > 1) and merge_group_log_item(dl.steps)
                or with_modern_motion(dl.steps[1], combo_modern_char())

            -- Number of validated follow-ups in this group (to swap followup -> validfollowup)
            if mode == "playing" and #dl.steps > 1 then
                log_item.validated_followups = math.max(0, math.min(trial_state.current_step - dl.first, #dl.steps - 1))
            end
            local y = trial_y + (dl_idx - start_idx) * spacing_y

            local current_should_flip = false
            if mode == "recording" then
                current_should_flip = log_item.facing_left or false
            else
                local step_facing_left = log_item.facing_left or false
                local init_facing_left = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].facing_left or false
                current_should_flip = (trial_state.flip_inputs ~= step_facing_left) ~= init_facing_left
            end

            local tokens = parse_motion_to_icons(log_item, mode, current_should_flip, true)
            draw_parsed_line(tokens, trial_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, is_aligned_right, nil)

            -- Smart overlay (pink for success, dark for fail)
            if trial_state.is_playing and not is_succ then
                local is_fail_state = (trial_state.fail_timer and trial_state.fail_timer > 0)
                local draw_overlay, overlay_col = false, 0
                if dl_idx < visual_dl then
                    draw_overlay = true; overlay_col = d2d_cfg.colors.bg_overlay_success or 0x40D050B0
                elseif dl_idx == visual_dl and is_fail_state then
                    draw_overlay = true; overlay_col = d2d_cfg.colors.bg_overlay or 0x85000000
                end
                if draw_overlay and preview <= 1 then
                    d2d.fill_rect(final_rect_x, y - padding_y + c_off_y + ov_off_y + 3, cartouche_w, overlay_h - 6, overlay_col)
                end
            end
        end

        -- Arrow disabled: bar images have arrows built-in
        -- if trial_state.is_playing and d2d_anim.active_y then
        --     local arrow_tex = "arrow"
        --     if trial_state.success_timer > 0 then arrow_tex = "arrow_success"
        --     elseif trial_state.fail_timer and trial_state.fail_timer > 0 then arrow_tex = "arrow_fail" end
        --     if assets.imgs[arrow_tex] then
        --         local arr_w = d2d_cfg.arrow_size * sh
        --         local arr_x = is_aligned_right and (trial_x - (d2d_cfg.offset_x_arrow * sw)) or (trial_x + (d2d_cfg.offset_x_arrow * sw))
        --         local arr_y = d2d_anim.active_y + (spacing_y - arr_w) / 2 + (d2d_cfg.offset_y_arrow * sh)
        --         d2d.image(assets.imgs[arrow_tex], arr_x, arr_y, arr_w, arr_w)
        --     end
        -- end
    end

    -- Custom mouse cursor
    if assets.imgs["cursor"] and (reframework:is_draw_ui() or (ctx.sf6_menu_state and ctx.sf6_menu_state.active)) then
        local mp = imgui.get_mouse()
        if mp then d2d.image(assets.imgs["cursor"], mp.x, mp.y, 32, 32) end
    end

    end -- close "if should_draw and not is_paused and CurrentTrainerMode == 4"

    draw_bar_toggle_arrows()
end

-- =========================================================
-- Public API
-- =========================================================
local function d2d_draw()
    -- Self-clearing beat (same pattern as Distance Viewer's queue): on_frame sets
    -- it each frame it wants the overlay; this callback consumes it. If on_frame
    -- pauses (VS / match-load transition), the beat stays false and nothing draws
    -- — so the overlay can't freeze on the VS screen.
    if not _G.ComboTrials_D2D_Beat then return end
    _G.ComboTrials_D2D_Beat = false
    pcall(d2d_draw_inner)
end

function M.init(shared_ctx)
    ctx = shared_ctx
    d2d.register(d2d_init, d2d_draw)
end

function M.reset_anim()
    d2d_anim.active_y = nil
end

function M.reset_raw()
    raw_state.history_p1 = {}
    raw_state.history_p2 = {}
end

return M