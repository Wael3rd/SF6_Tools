local ActionMatcher = {
    name = "ComboTrials.ActionMatcher"
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function ActionMatcher.normalize_motion_token(value)
    local s = tostring(value or ""):upper():gsub("%s+", "")
    -- Legacy exception tables used several equivalent spellings. Normalize
    -- them here so existing combo JSON keeps its motion fallback when newly
    -- generated AC+BCM tables adopt one canonical display form (SF6_TOOLS_CC).
    s = s:gsub("DRIVERUSH", "RAWDR")
    s = s:gsub("LP%+LK", "THROW")
    s = s:gsub("%(THROW%)", "THROW")
    s = s:gsub("%+", "")
    s = s:gsub("^>%s*", "")
    s = s:gsub("%(空挥%)", "")
    s = s:gsub("%(绌烘尌%)", "")
    s = s:gsub("%(WHIFF%)", "")
    s = s:gsub("（空挥）", "")
    s = s:gsub("（绌烘尌）", "")
    s = s:gsub("（WHIFF）", "")
    return s
end

function ActionMatcher.motion_matches_expected(actual_motion, actual_input, expected)
    if not expected then return false end
    local actual_m = ActionMatcher.normalize_motion_token(actual_motion)
    local actual_i = ActionMatcher.normalize_motion_token(actual_input)
    local expected_m = ActionMatcher.normalize_motion_token(expected.motion)
    if actual_m ~= "" and actual_m == expected_m then return true end
    if actual_i ~= "" and actual_i == expected_m then return true end
    if type(expected.motion_aliases) == "table" then
        for _, alias in ipairs(expected.motion_aliases) do
            local a = ActionMatcher.normalize_motion_token(alias)
            if a ~= "" and (actual_m == a or actual_i == a) then return true end
        end
    end
    return false
end

function ActionMatcher.match_expected_action(expected, actual_action_id, actual_motion, actual_input)
    local id_matched = expected and actual_action_id == expected.id
    local motion_matched = expected and ActionMatcher.motion_matches_expected(actual_motion, actual_input, expected)
    return {
        matched = id_matched or motion_matched or false,
        match_reason = id_matched and "id" or (motion_matched and "motion" or "none"),
        expected_id = expected and expected.id or nil,
        actual_action_id = actual_action_id,
        expected_entry = expected,
        actual_entry = {
            id = actual_action_id,
            motion = actual_motion,
            input = actual_input
        }
    }
end

local function list_contains_token(value, token, normalizer)
    if value == nil or token == nil then return false end
    token = normalizer and normalizer(token) or tostring(token)

    if type(value) == "table" then
        for _, item in ipairs(value) do
            local candidate = normalizer and normalizer(item) or tostring(item)
            if candidate == token then return true end
        end
        return false
    end

    for item in tostring(value):gmatch("[^,]+") do
        local candidate = item:match("^%s*(.-)%s*$")
        candidate = normalizer and normalizer(candidate) or candidate
        if candidate == token then return true end
    end
    return false
end

local function motion_has_followup_marker(value)
    local motion = trim(value)
    return motion:sub(1, 1) == ">" or motion:find(">", 1, true) ~= nil
end

function ActionMatcher.is_optional_parent_for_followup(actual_motion, expected_step, actual_action_id, expected_exception)
    if type(actual_motion) ~= "string" or type(expected_step) ~= "table" then return false end
    local expected_motion = trim(expected_step.motion)
    local exception_motion = expected_exception and (
        expected_exception.follow_up_motion or expected_exception.override_name or expected_exception.display_motion
    ) or nil
    if not motion_has_followup_marker(exception_motion or expected_motion) then return false end

    if expected_exception then
        if list_contains_token(expected_exception.optional_parent_ids, tonumber(actual_action_id), tonumber) then
            return true
        end
        if list_contains_token(expected_exception.optional_parent_motions, actual_motion, ActionMatcher.normalize_motion_token) then
            return true
        end
    end

    if expected_motion:sub(1, 1) ~= ">" then return false end
    local motion = actual_motion:match("^%s*(.-)%s*$")
    return motion == "214+P"
end

function ActionMatcher.build_edit_exception(p_state)
    local parsed_prev = nil
    if p_state.edit_ignore_prev_id ~= "" then
        local ids = {}
        for tok in p_state.edit_ignore_prev_id:gmatch("[^,]+") do
            local n = tonumber(tok:match("^%s*(.-)%s*$"))
            if n then ids[#ids+1] = n end
        end
        if #ids == 1 then parsed_prev = ids[1]
        elseif #ids > 1 then parsed_prev = ids end
    end
    return {
        ignore = p_state.edit_ignore,
        force = p_state.edit_force,
        is_holdable = p_state.edit_holdable,
        hold_partial_check = p_state.edit_hold_partial_check,
        absorb_ids = p_state.edit_absorb_ids,
        charge_min = tonumber(p_state.edit_charge_min),
        charge_max = tonumber(p_state.edit_charge_max),
        override_name = (p_state.edit_text ~= "") and p_state.edit_text or nil,
        ignore_prev_id = parsed_prev,
        ignore_prev_frames = tonumber(p_state.edit_ignore_prev_frames) or 5
    }
end

function ActionMatcher.matches_absorb_id(exception, actual_action_id)
    if not exception or not exception.absorb_ids or type(exception.absorb_ids) ~= "string" or exception.absorb_ids == "" then
        return false
    end
    for absorb_str in string.gmatch(exception.absorb_ids, "([^,]+)") do
        local absorb_num = tonumber(absorb_str:match("^%s*(.-)%s*$"))
        if absorb_num and absorb_num == actual_action_id then
            return true
        end
    end
    return false
end

function ActionMatcher.evaluate_ignore_prev(exception, log, frame_count)
    if not (exception and exception.ignore_prev_id) then
        return { ignored = false, reason = nil }
    end
    local check_ids = type(exception.ignore_prev_id) == "table" and exception.ignore_prev_id or { exception.ignore_prev_id }
    for i = 1, math.min(10, #log) do
        local prev_log = log[i]
        for _, cid in ipairs(check_ids) do
            if prev_log.id == cid then
                local frames_since = frame_count - (prev_log.start_frame or frame_count)
                if frames_since <= (exception.ignore_prev_frames or 5) then
                    local id_disp = type(exception.ignore_prev_id) == "table" and table.concat(exception.ignore_prev_id, ",") or tostring(exception.ignore_prev_id)
                    return {
                        ignored = true,
                        reason = "[例外：在 ID " .. id_disp .. " 后忽略]"
                    }
                end
            end
        end
    end
    return { ignored = false, reason = nil }
end

function ActionMatcher.is_force_enabled(exception)
    return exception and exception.force == true
end

function ActionMatcher.is_exception_ignored(exception)
    return exception and exception.ignore == true
end

function ActionMatcher.apply_override_name(motion, exception)
    if exception and exception.override_name and exception.override_name ~= "" then
        return exception.override_name
    end
    return motion
end

function ActionMatcher.hold_partial_check_enabled(exception)
    return (exception and exception.hold_partial_check ~= false) and true or false
end

return ActionMatcher
