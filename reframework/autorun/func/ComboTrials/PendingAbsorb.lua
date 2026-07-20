local PendingAbsorb = {
    name = "ComboTrials.PendingAbsorb"
}

local function frame_diff_result(frame_diff)
    local diff = tonumber(frame_diff)
    if not diff or diff == 0 then return "完美", "ok" end
    if diff < 0 then return string.format("快 %df", math.abs(diff)), "early" end
    return string.format("慢 %df", diff), "late"
end

function PendingAbsorb.effective_timing_frame_diff(state, frame_diff)
    if state and state._demo_timing_ui_baseline == true then return 0 end
    return frame_diff
end

local function fail_reason_result(reason)
    local s = tostring(reason or "")
    local upper = s:upper()
    if upper:find("WRONG MOVE", 1, true) then return "错误", "wrong" end
    if upper:find("MISSED INPUT", 1, true) then return "无输入", "missing" end
    if upper:find("COMBO DROP", 1, true) or upper:find("COMBO DROPPED", 1, true) then return "断连", "drop" end

    local early = upper:match("TOO EARLY%s*%((%d+)F%)")
    if early then return string.format("快 %sf", early), "early" end
    local late = upper:match("TOO LATE%s*%((%d+)F%)")
    if late then return string.format("慢 %sf", late), "late" end

    return "失败", "fail"
end

function PendingAbsorb.set_ui_result(state, step_idx, text, kind)
    if not state or type(state.sequence) ~= "table" then return end
    local idx = tonumber(step_idx)
    if not idx then return end
    if idx < 1 then idx = 1 end
    if idx > #state.sequence then idx = #state.sequence end
    local step = state.sequence[idx]
    if not step then return end
    step.ui_result_text = text
    step.ui_result_kind = kind
end

function PendingAbsorb.set_timing_ui_result(state, step_idx, frame_diff)
    frame_diff = PendingAbsorb.effective_timing_frame_diff(state, frame_diff)
    local text, kind = frame_diff_result(frame_diff)
    PendingAbsorb.set_ui_result(state, step_idx, text, kind)
end

function PendingAbsorb.sync_failure_ui_result(state)
    if not state or type(state.sequence) ~= "table" or #state.sequence == 0 then return end
    local failing = (state.fail_timer and state.fail_timer > 0) or state.manual_reset_pending
    if not failing or not state.fail_reason then return end
    local text, kind = fail_reason_result(state.fail_reason)
    PendingAbsorb.set_ui_result(state, state.current_step or 1, text, kind)
end

function PendingAbsorb.clear(state, reason)
    if state and state._pending_current_absorb then
        state._pending_current_absorb.clear_reason = reason
    end
    if state then
        state._pending_current_absorb = nil
    end
end

local function add_fields(ctx, target, pending, prefix)
    if not target or not pending then return end
    prefix = prefix or "pending"
    target[prefix .. "_step"] = pending.step
    target[prefix .. "_expected_id"] = pending.expected_id
    target[prefix .. "_actual_action_id"] = pending.actual_action_id
    target[prefix .. "_expected_combo"] = pending.expected_combo
    target[prefix .. "_created_combo"] = pending.created_combo
    target[prefix .. "_current_combo"] = ctx.pf.current_combo or 0
    target[prefix .. "_frame_diff"] = pending.frame_diff
    target[prefix .. "_action_instance"] = pending.action_instance
    target[prefix .. "_created_at_frame"] = pending.created_at_frame
    target[prefix .. "_expires_at_frame"] = pending.expires_at_frame
    target[prefix .. "_age_frames"] = ctx.frame - (pending.created_at_frame or ctx.frame)
end

function PendingAbsorb.apply_matched_step(ctx, params)
    if not ctx or not params or not params.expected then return false end

    local state = ctx.state
    local expected = params.expected
    local actual_id = params.actual_action_id
    local actual_motion = params.actual_motion or "Unknown"
    local actual_input = params.actual_input or "None"
    local validation_frame = params.frame or ctx.frame
    local combo_count = params.combo_count or 0
    local actual_hp = params.actual_hp
    local action_instance = params.action_instance
    local details = params.match_details

    state._step1_wrong_pending = false
    local actual_delay = 0
    local last_played = state.last_played_frame or validation_frame
    if state.current_step > 1 then
        actual_delay = validation_frame - last_played
    end
    state.last_played_frame = validation_frame
    local raw_frame_diff = ctx.Validator.calculate_frame_diff(actual_delay, expected.delay_from_prev)
    local ui_frame_diff = PendingAbsorb.effective_timing_frame_diff(state, raw_frame_diff)

    if ui_frame_diff < 0 then
        state.floating_info = string.format("%d frames too early", math.abs(ui_frame_diff))
        state.floating_color = 0xFF00FFAD
    elseif ui_frame_diff > 0 then
        state.floating_info = string.format("%d frames too late", ui_frame_diff)
        state.floating_color = 0xFF00A5FF
    else
        state.floating_info = "Perfect timing"
        state.floating_color = 0xFF00FFFF
    end

    if ctx.is_post_hit_setup_step(state.current_step) then
        state.ui_visual_step = state.current_step + 1
    end

    local prev_step = nil
    if state.current_step > 1 then
        prev_step = state.sequence[state.current_step - 1]
    end

    local combo_ok = ctx.Validator.check_combo({
        expected = expected,
        prev_step = prev_step,
        current_combo = combo_count,
        opponent_knocked_down = ctx.pf.opponent_knocked_down
    })
    if details and details.ignore_combo_check == true then
        combo_ok = true
    end
    local hp_ok = ctx.Validator.check_hp(
        expected.expected_hp,
        actual_hp,
        ctx.is_post_hit_setup_step(state.current_step - 1),
        expected
    )

    ctx.DebugTrace.record_validation_debug(state, {
        frame = validation_frame,
        step = state.current_step,
        act_id = actual_id,
        actual_action_id = actual_id,
        motion = actual_motion,
        real_input = actual_input,
        expected_id = expected.id,
        expected_motion = expected.motion,
        current_combo = combo_count,
        combo_count = combo_count,
        previous_expected_combo = prev_step and prev_step.expected_combo or nil,
        previous_previous_expected_combo = state.current_step > 2
            and state.sequence[state.current_step - 2].expected_combo or nil,
        combo_ok = combo_ok,
        hp_ok = hp_ok,
        current_hp = actual_hp,
        expected_hp = expected.expected_hp,
        previous_is_setup = ctx.is_post_hit_setup_step(state.current_step - 1),
        current_is_setup = ctx.is_post_hit_setup_step(state.current_step),
        validation_role = expected.validation_role,
        allow_whiff = expected.allow_whiff,
        ignore_combo_check = expected.ignore_combo_check,
        ignore_hp_check = expected.ignore_hp_check,
        finish_on_action = expected.finish_on_action,
        allow_hit = expected.allow_hit,
        allow_block = expected.allow_block,
        allow_counter = expected.allow_counter,
        raw_frame_diff = raw_frame_diff,
        frame_diff = raw_frame_diff,
        ui_frame_diff = ui_frame_diff,
        demo_timing_ui_baseline = state._demo_timing_ui_baseline == true,
        action_instance = action_instance,
        match_reason = params.match_reason,
        recent_index = details and details.recent_index or nil,
        absorb_ids = details and details.absorb_ids or nil,
        source = details and details.source or nil
    })

    if combo_ok and hp_ok then
        local matched_step = state.current_step
        state.sequence[matched_step].has_hit = false
        state.sequence[matched_step].last_frame_diff = raw_frame_diff
        state.sequence[matched_step].actual_combo = combo_count
        state.sequence[matched_step].action_instance = action_instance
        if action_instance ~= nil then
            state._consumed_action_instances = state._consumed_action_instances or {}
            state._consumed_action_instances[action_instance] = matched_step
            state._last_matched_action_instance = action_instance
        end
        PendingAbsorb.set_timing_ui_result(state, matched_step, raw_frame_diff)
        state.current_step = state.current_step + 1
        PendingAbsorb.clear(state, "step_advanced")

        if ctx.Validator.is_pressure_tail_step(expected)
            and expected.finish_on_action == true
            and matched_step == #state.sequence then
            state.success_timer = ctx.d2d_cfg.fail_display_frames or 120
            state.fail_timer = 0
            state.fail_reason = nil
        end

        local just_validated = state.sequence[state.current_step - 1]
        if not just_validated or just_validated.counter_type == 0 then
            local next_step = state.sequence[state.current_step]
            if next_step and next_step.counter_type then
                ctx.set_dummy_counter_type(next_step.counter_type)
            end
        end

        if expected.is_holdable and expected.charge_status then
            local safe_mask = params.hold_mask
            if not safe_mask or safe_mask == 0 then safe_mask = (params.direct_input or 0) & 0xFFF0 end
            state.active_universal_hold = {
                expected_status = expected.charge_status,
                hold_mask = safe_mask,
                frames = params.hold_frames or 0,
                charge_min = expected.charge_min,
                charge_max = expected.charge_max,
                profile_name = ctx.p_state and ctx.p_state.profile_name or nil,
                expected_action_id = expected.id,
                linked_transition_id = expected.linked_transition_id,
                expected_frames = expected.hold_frames,
                hold_partial_check = expected.hold_partial_check
            }
        end
        return true, matched_step, raw_frame_diff
    end

    PendingAbsorb.clear(state, "matched_step_failed")
    state.fail_timer = ctx.d2d_cfg.fail_display_frames or 20
    if not hp_ok then
        local custom_reason = "WRONG HP (Setup Dropped)"
        local prev = state.sequence[state.current_step - 1]
        if ctx.is_post_hit_setup_step(state.current_step - 1) and prev and prev.last_frame_diff then
            if prev.last_frame_diff > 2 then
                custom_reason = string.format("SETUP TOO LATE (%df)", prev.last_frame_diff)
            elseif prev.last_frame_diff < -2 then
                custom_reason = string.format("SETUP TOO EARLY (%df)", math.abs(prev.last_frame_diff))
            else
                custom_reason = "MEATY TIMING FAILED"
            end
        end
        state.fail_reason = custom_reason
    elseif raw_frame_diff < -2 then
        state.fail_reason = string.format("TOO EARLY (%df)", math.abs(raw_frame_diff))
    elseif raw_frame_diff > 2 then
        state.fail_reason = string.format("TOO LATE (%df)", raw_frame_diff)
    elseif state._hit_grace and state._hit_grace > 0 then
        state.fail_timer = 0
    else
        state.fail_reason = "COMBO DROPPED"
    end
    PendingAbsorb.sync_failure_ui_result(state)

    if state.fail_timer and state.fail_timer > 0 then
        ctx.DebugTrace.log_trial_failure(ctx.file_system, state, ctx.frame, ctx.pf, not hp_ok and "action_hp_setup_validation" or "action_step_validation", {
            expected_motion = expected.motion,
            player_action_id = actual_id,
            player_action_name = ctx.act_id_reverse_enum[actual_id] or "Unknown",
            timeline_frame = state.current_step,
            playback_state = "playing"
        })
    end
    return false, nil, raw_frame_diff
end

local function build_probe(ctx, pending, phase)
    local state = ctx.state
    local expected = state.sequence and state.sequence[state.current_step] or nil
    local prev_step = state.current_step and state.current_step > 1
        and state.sequence[state.current_step - 1] or nil
    local probe = {
        phase = phase or "pending_current_absorb_check",
        frame = ctx.frame,
        trial_file = state.current_file or state.current_file_path,
        trial_filename = state.current_file_name,
        character = ctx.p_state and ctx.p_state.profile_name or nil,
        step = state.current_step,
        trial_total = state.sequence and #state.sequence or 0,
        expected_id = expected and expected.id or nil,
        expected_motion = expected and expected.motion or nil,
        expected_combo = expected and expected.expected_combo or nil,
        expected_delay = expected and expected.delay_from_prev or nil,
        previous_verified_step = state.current_step and state.current_step - 1 or nil,
        previous_id = prev_step and prev_step.id or nil,
        previous_motion = prev_step and prev_step.motion or nil,
        previous_expected_combo = prev_step and prev_step.expected_combo or nil,
        previous_has_hit = prev_step and prev_step.has_hit or nil,
        previous_last_frame_diff = prev_step and prev_step.last_frame_diff or nil,
        actual_action_id = pending and pending.actual_action_id or nil,
        actual_motion = pending and pending.actual_motion or nil,
        actual_input = pending and pending.actual_input or nil,
        current_combo = ctx.pf.current_combo or 0,
        combo_count = ctx.pf.current_combo or 0,
        actual_hp = ctx.pf.p_char and ctx.pf.p_char.vital_new or nil,
        frames_since_prev_step = pending and pending.frames_since_prev_step or nil,
        frame_diff = pending and pending.frame_diff or nil,
        action_instance = pending and pending.action_instance or nil,
        opponent_knocked_down = ctx.pf.opponent_knocked_down,
        pending_current_absorb_checked = true
    }
    add_fields(ctx, probe, pending, "pending")
    return probe
end

function PendingAbsorb.check(ctx, phase)
    local state = ctx.state
    local pending = state and state._pending_current_absorb or nil
    if not pending then return false end

    local probe = build_probe(ctx, pending, phase)
    local expected = state.sequence and state.sequence[state.current_step] or nil
    local clear_reason = nil
    local current_combo = ctx.pf.current_combo or 0
    local current_hp = ctx.pf.p_char and ctx.pf.p_char.vital_new or pending.actual_hp

    if not state.is_playing or ctx.p_idx ~= state.playing_player then
        clear_reason = "trial_not_playing"
    elseif state.manual_reset_pending then
        clear_reason = "manual_reset"
    elseif state.success_timer and state.success_timer > 0 then
        clear_reason = "success"
    elseif state.fail_timer and state.fail_timer > 0 then
        clear_reason = "fail"
    elseif ctx.p_state and pending.character and ctx.p_state.profile_name ~= pending.character then
        clear_reason = "character_changed"
    elseif state.current_step ~= pending.step then
        clear_reason = "step_changed"
    elseif not expected then
        clear_reason = "missing_expected"
    elseif expected.id ~= pending.expected_id then
        clear_reason = "expected_changed"
    elseif pending.action_instance and ctx.p_state and ctx.p_state.current_action_instance
        and pending.action_instance ~= ctx.p_state.current_action_instance then
        clear_reason = "action_instance_changed"
    elseif pending.expires_at_frame and ctx.frame > pending.expires_at_frame then
        clear_reason = "expired"
    elseif math.abs(pending.frame_diff or 999) > 2 then
        clear_reason = "timing_window"
    end

    if clear_reason then
        probe.pending_current_absorb_cleared = true
        probe.pending_clear_reason = clear_reason
        probe.pending_reject_reason = clear_reason
        ctx.DebugTrace.record_match_probe(state, probe)
        PendingAbsorb.clear(state, clear_reason)
        return false
    end

    if pending.ignore_combo_check ~= true and current_combo < (pending.expected_combo or 0) then
        probe.pending_reject_reason = "combo_not_reached"
        ctx.DebugTrace.record_match_probe(state, probe)
        return false
    end

    local prev_step = pending.step > 1 and state.sequence[pending.step - 1] or nil
    local combo_ok = ctx.Validator.check_combo({
        expected = expected,
        prev_step = prev_step,
        current_combo = current_combo,
        opponent_knocked_down = ctx.pf.opponent_knocked_down
    })
    if pending.ignore_combo_check == true then
        combo_ok = true
    end
    local hp_ok = ctx.Validator.check_hp(
        expected.expected_hp,
        current_hp,
        ctx.is_post_hit_setup_step(pending.step - 1),
        expected
    )
    probe.pending_combo_ok = combo_ok
    probe.pending_hp_ok = hp_ok

    if not combo_ok then
        probe.pending_reject_reason = "combo_check"
        ctx.DebugTrace.record_match_probe(state, probe)
        return false
    end
    if not hp_ok then
        probe.pending_reject_reason = "hp_check"
        ctx.DebugTrace.record_match_probe(state, probe)
        return false
    end

    local confirmed = PendingAbsorb.apply_matched_step(ctx, {
        expected = expected,
        actual_action_id = pending.actual_action_id,
        actual_motion = pending.actual_motion or "Unknown",
        actual_input = pending.actual_input or "None",
        frame = pending.frame,
        combo_count = current_combo,
        actual_hp = current_hp,
        match_reason = "ehonda_pending_current_absorb",
        match_details = {
            actual_action_id = pending.actual_action_id,
            match_reason = "ehonda_pending_current_absorb",
            combo_count = current_combo,
            start_frame = pending.frame,
            motion = pending.actual_motion,
            real_input = pending.actual_input,
            expected_id = pending.expected_id,
            expected_combo = pending.expected_combo,
            absorb_ids = pending.absorb_ids,
            ignore_combo_check = pending.ignore_combo_check,
            source = "current_absorb_pending",
            action_instance = pending.action_instance,
            pending_age_frames = ctx.frame - (pending.created_at_frame or ctx.frame)
        }
    })
    probe.pending_current_absorb_confirmed = confirmed
    probe.pending_post_step = state.current_step
    if not confirmed then
        probe.pending_reject_reason = "apply_failed"
    end
    ctx.DebugTrace.record_match_probe(state, probe)
    return confirmed
end

function PendingAbsorb.store(ctx, expected, current_absorb, match_probe, actual_hp)
    local state = ctx.state
    if not expected or not current_absorb or current_absorb.block_reason ~= "combo_not_reached" then return false end
    if current_absorb.ignore_combo_check ~= true
        and ctx.p_state.profile_name ~= "EHonda" and ctx.p_state.profile_name ~= "Honda" then return false end
    if state.success_timer and state.success_timer > 0 then return false end
    if state.fail_timer and state.fail_timer > 0 then return false end
    if state.manual_reset_pending then return false end
    if state.current_step ~= match_probe.step then return false end
    if math.abs(match_probe.frame_diff or 999) > 2 then
        match_probe.pending_reject_reason = "timing_window"
        return false
    end

    local existing = state._pending_current_absorb
    if existing and existing.step ~= state.current_step then
        match_probe.pending_reject_reason = "different_pending_step"
        return false
    end

    local next_step = state.sequence and state.sequence[state.current_step + 1] or nil
    local window = 60
    if next_step and next_step.delay_from_prev then
        window = math.min((tonumber(next_step.delay_from_prev) or 0) + 4, 60)
        if window < 4 then window = 4 end
    end

    state._pending_current_absorb = {
        step = state.current_step,
        character = ctx.p_state.profile_name,
        expected_id = expected.id,
        expected_motion = expected.motion,
        expected_combo = tonumber(expected.expected_combo) or 0,
        actual_action_id = current_absorb.actual_action_id,
        actual_motion = match_probe.actual_motion,
        actual_input = match_probe.actual_input,
        frame = match_probe.frame,
        frames_since_prev_step = match_probe.frames_since_prev_step,
        expected_delay = match_probe.expected_delay,
        frame_diff = match_probe.frame_diff,
        actual_hp = actual_hp,
        absorb_ids = current_absorb.absorb_ids,
        ignore_combo_check = current_absorb.ignore_combo_check == true,
        action_instance = match_probe.action_instance,
        created_combo = match_probe.current_combo or 0,
        created_at_frame = ctx.frame,
        expires_at_frame = ctx.frame + window,
        reject_reason = "combo_not_reached",
        source = "current_absorb_pending"
    }

    match_probe.pending_current_absorb_created = true
    match_probe.pending_current_absorb_overwritten = existing ~= nil
    add_fields(ctx, match_probe, state._pending_current_absorb, "pending")
    return true
end

return PendingAbsorb
