-- =========================================================
-- ComboTrials_Files.lua - Combo JSON loading and list management.
-- Receives shared context via init(); mutates ctx.file_system in place.
-- Module boundary mirrors SF6_TOOLS_CC for project convergence.
-- =========================================================

local json = json
local fs = fs
local sdk = sdk

local M = {}

-- Resolved in init()
local trial_state, file_system, players
local assign_groups, reset_trial_flags, reset_visual_state

-- =========================================================
-- SUBSYSTEM PORT #7 (partial) -- forward-compat schema guard, adopted from
-- SF6_TOOLS_CC HEAD 9b851c5. If a shared combo file was written with a newer
-- _xt_meta.schema than this build understands, warn once (on-screen + console)
-- and still load it best-effort by known fields, instead of breaking silently.
-- Matters for the shared JSON format: when cdjay bumps the schema, our users
-- get a clear message rather than a broken combo.
-- (His sanitize_filename_component and deferred-refresh busy-state were checked
-- and NOT ported: we already have sanitize_ascii_filename_part, and our combo
-- list refreshes only on dropdown-open, so there is no timer-poll to defer.)
-- =========================================================
local XT_SCHEMA_MAX = 2   -- highest _xt_meta.schema this build writes/understands
local schema_warning_paths = {}

local function warn_combo_file_once(path, reason)
    local warnings = file_system and file_system.combo_file_warnings
    if type(warnings) ~= "table" then return end
    local key = tostring(path) .. "|" .. tostring(reason)
    if warnings[key] then return end
    warnings[key] = true
    pcall(print, string.format("[ComboTrials] Combo file issue: %s (%s)", tostring(path), tostring(reason)))
end
M.warn_combo_file_once = warn_combo_file_once

local function warn_newer_schema(path, sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    local schema = type(meta) == "table" and tonumber(meta.schema) or nil
    if not schema or schema <= XT_SCHEMA_MAX then return end
    local key = tostring(path) .. "|" .. tostring(schema)
    if schema_warning_paths[key] then return end
    schema_warning_paths[key] = true
    local msg = string.format("Combo schema %s is newer than supported %s; loading known fields only", schema, XT_SCHEMA_MAX)
    pcall(print, "[ComboTrials] " .. msg)
    if type(_G.show_custom_ticker) == "function" then pcall(_G.show_custom_ticker, msg, 0.3) end
end
M.warn_newer_schema = warn_newer_schema

function M.load_combo_from_file(path)
    if not path then return false end
    local loaded = json.load_file(path)
    if not loaded then
        warn_combo_file_once(path, "JSON load failed")
        return false
    end
    -- #7: forward-compat schema check (warns once, still loads best-effort).
    warn_newer_schema(path, loaded)
    trial_state.sequence = loaded
    assign_groups(trial_state.sequence)
    trial_state.current_step = 1
    trial_state.is_playing = false
    if loaded[1] then
        trial_state.start_pos_p1 = loaded[1].start_pos_p1
        trial_state.start_pos_p2 = loaded[1].start_pos_p2
        trial_state.start_pos_p1_raw = loaded[1].start_pos_p1_raw
        trial_state.start_pos_p2_raw = loaded[1].start_pos_p2_raw
    end
    return true
end

function M.clear_combo_state()
    reset_trial_flags()
    trial_state.sequence = {}
    trial_state.start_pos_p1 = nil
    trial_state.start_pos_p2 = nil
    trial_state.start_pos_p1_raw = nil
    trial_state.start_pos_p2_raw = nil
    trial_state.live_start_pos_p1 = nil
    trial_state.live_start_pos_p2 = nil
    trial_state.live_start_pos_p1_raw = nil
    trial_state.live_start_pos_p2_raw = nil
    reset_visual_state()
    pcall(collectgarbage, "step", 16)
end

-- Combo control-mode filter (SF6_TOOLS_CC parity). "all" = no I/O (default);
-- "classic"/"modern" = only matching combos; "auto" = match current P1 mode.
-- Reads _xt_meta.control_mode lazily, cached per path.
local _control_mode_cache = {}
local function combo_control_mode(path)
    if _control_mode_cache[path] ~= nil then return _control_mode_cache[path] end
    local mode = "classic"
    pcall(function()
        local d = json.load_file(path)
        local m = d and d[1] and d[1]._xt_meta
        if m and (m.control_mode == "modern" or m.control_mode == "classic") then
            mode = m.control_mode
        end
    end)
    _control_mode_cache[path] = mode
    return mode
end

-- Live control type (Classic/Modern) chosen at character select for a player.
-- InputType == 1 means Modern. Reads the training SelectMenu each call.
local function player_control_mode(player_idx)
    local mode = "classic"
    pcall(function()
        local tm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.training.TrainingManager")
        local sm = tm and tm:get_field("_tData") and tm:get_field("_tData"):get_field("SelectMenu")
        local pd = sm and sm.PlayerDatas and sm.PlayerDatas[player_idx or 0]
        if pd and tonumber(pd.InputType) == 1 then mode = "modern" end
    end)
    return mode
end
M.player_control_mode = player_control_mode  -- idx -> "modern"/"classic" (live)

local function current_p1_control_mode()
    return player_control_mode(0)
end

function M.effective_control_filter()
    local f = file_system.combo_control_filter or "all"
    if f == "auto" then return current_p1_control_mode() end
    return f
end

M.combo_control_mode = combo_control_mode  -- act_id file -> "modern"/"classic" (cached)
function M.invalidate_control_cache() _control_mode_cache = {} end

function M.refresh_combo_list(recent_saved_player)
    file_system.saved_combos_display_p1, file_system.saved_combos_paths_p1 = {}, {}
    file_system.saved_combos_display_p2, file_system.saved_combos_paths_p2 = {}, {}
    local _ctrl_filter = M.effective_control_filter()

    local function load_files(player_idx, display_list, path_list)
        if not players[player_idx] then return end
        local char_name = players[player_idx].profile_name
        if char_name == "Unknown" then return end

        if fs.create_dir then
            pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos"); pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/" .. char_name)
        end

        local files = fs.glob("TrainingComboTrials_data\\\\CustomCombos\\\\" .. char_name .. "\\\\.*json")
        if files then
            -- Parse filename to extract sort keys: type (COMBO/OKI), damage, drive, SA
            local function parse_sort_keys(filepath)
                local fname = filepath:match("([^/\\]+)$") or ""
                local is_oki = fname:find("_OKI_") and 1 or 0
                local dmg = tonumber(fname:match("_(%d+)_D")) or 0
                local drive = tonumber(fname:match("_D([%d%.]+)_SA")) or 0
                local sa = tonumber(fname:match("_SA([%d%.]+)")) or 0
                return is_oki, dmg, drive, sa
            end
            -- Sort: COMBO first, then by damage desc, drive desc, SA desc
            table.sort(files, function(a, b)
                local a_oki, a_dmg, a_dr, a_sa = parse_sort_keys(a)
                local b_oki, b_dmg, b_dr, b_sa = parse_sort_keys(b)
                if a_oki ~= b_oki then return a_oki < b_oki end
                if a_dmg ~= b_dmg then return a_dmg > b_dmg end
                if a_dr ~= b_dr then return a_dr > b_dr end
                if a_sa ~= b_sa then return a_sa > b_sa end
                return a < b
            end)
            for _, filepath in ipairs(files) do
                -- control-mode filter (only pays the I/O when a filter is active)
                if _ctrl_filter == "all" or combo_control_mode(filepath) == _ctrl_filter then
                    table.insert(path_list, filepath)
                    table.insert(display_list, filepath:match("([^/\\]+)$") or filepath)
                end
            end
        end
    end

    load_files(0, file_system.saved_combos_display_p1, file_system.saved_combos_paths_p1)
    load_files(1, file_system.saved_combos_display_p2, file_system.saved_combos_paths_p2)

    local target_player = recent_saved_player or 0
    if target_player == 1 and #file_system.saved_combos_paths_p2 == 0 then target_player = 0 end
    if target_player == 0 and #file_system.saved_combos_paths_p1 == 0 then target_player = 1 end

    if not file_system._pending_select_path then
        local path_to_load = nil
        if target_player == 0 and #file_system.saved_combos_paths_p1 > 0 then
            file_system.selected_file_idx_p1 = 1
            path_to_load = file_system.saved_combos_paths_p1[1]
        elseif target_player == 1 and #file_system.saved_combos_paths_p2 > 0 then
            file_system.selected_file_idx_p2 = 1
            path_to_load = file_system.saved_combos_paths_p2[1]
        end
        if not M.load_combo_from_file(path_to_load) then
            M.clear_combo_state()
        end
    end
end

-- =========================================================
-- EXTERNAL CHANGE DETECTION (signature-based, SF6_TOOLS_CC-compatible)
-- Detects combo files added/removed by external writers (mobile import
-- via the tray, manual drops) without rescanning on a timer for everyone:
-- the caller decides when to poll (gated + low frequency).
-- =========================================================
local function glob_combo_paths(char_name)
    if not char_name or char_name == "Unknown" then return {} end
    local files = fs.glob("TrainingComboTrials_data\\\\CustomCombos\\\\" .. char_name .. "\\\\.*json")
    return files or {}
end

function M.build_combo_list_signature()
    local parts = {}
    for player_idx = 0, 1 do
        local p_state = players[player_idx]
        local char_name = p_state and p_state.profile_name or nil
        if char_name and char_name ~= "Unknown" then
            local files = glob_combo_paths(char_name)
            table.sort(files)
            parts[#parts + 1] = char_name .. ":" .. #files .. ":" .. table.concat(files, "|")
        end
    end
    return table.concat(parts, ";;")
end

-- Refresh the lists while keeping each side's current selection (by path).
-- Never loads a different combo than the one currently selected.
function M.refresh_combo_list_preserve_selection()
    local kept = {}
    for player_idx = 0, 1 do
        local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
        local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
        kept[player_idx] = paths and paths[idx] or nil
    end

    local prev_pending = file_system._pending_select_path
    file_system._pending_select_path = kept[0] or kept[1] or true
    M.refresh_combo_list()
    file_system._pending_select_path = prev_pending

    for player_idx = 0, 1 do
        local old_path = kept[player_idx]
        if old_path then
            local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
            local new_idx = nil
            for i, path in ipairs(paths) do
                if path == old_path then new_idx = i break end
            end
            if new_idx then
                if player_idx == 0 then file_system.selected_file_idx_p1 = new_idx
                else file_system.selected_file_idx_p2 = new_idx end
            end
        end
    end
end

-- Returns true when an external change was detected (and the list refreshed)
function M.check_external_changes()
    local sig = M.build_combo_list_signature()
    if file_system._list_signature == nil then
        file_system._list_signature = sig
        return false
    end
    if sig == file_system._list_signature then return false end
    file_system._list_signature = sig
    M.refresh_combo_list_preserve_selection()
    return true
end

-- =========================================================
-- COMPLETED TRIALS TRACKING (runtime sidecar, SF6_TOOLS_CC-compatible)
-- API attached to file_system so main file and UI share it.
-- Sidecar lives OUTSIDE the per-character combo directories.
-- =========================================================
local COMPLETED_TRIALS_FILE = "TrainingComboTrials_data/CompletedTrials.json"

local function attach_completion_api()
    file_system.completed_trials = file_system.completed_trials or {}

    file_system.completed_trial_key = function(path)
        return (tostring(path or ""):gsub("\\", "/")):lower()
    end

    file_system.save_completed_trials = function()
        json.dump_file(COMPLETED_TRIALS_FILE, file_system.completed_trials)
    end

    file_system.is_trial_completed = function(path)
        local key = file_system.completed_trial_key(path)
        return key ~= "" and file_system.completed_trials[key] == true
    end

    file_system.mark_trial_completed = function(path)
        local key = file_system.completed_trial_key(path)
        if key == "" or file_system.completed_trials[key] then return false end
        file_system.completed_trials[key] = true
        file_system.save_completed_trials()
        return true
    end

    file_system.clear_completed_trials = function()
        file_system.completed_trials = {}
        file_system.save_completed_trials()
    end

    pcall(function()
        if type(_G.safe_load_json) ~= "function" then return end
        local loaded = _G.safe_load_json(COMPLETED_TRIALS_FILE)
        if type(loaded) ~= "table" then return end
        for key, value in pairs(loaded) do
            if type(key) == "string" and value then file_system.completed_trials[key] = true end
        end
    end)

    -- Gated diagnostic log (enable with _G.CT_DIAG_LOG = true) — consumed by
    -- ComboTrials/DebugTrace.log_trial_failure, SF6_TOOLS_CC-compatible
    file_system.diag_log = function(message)
        if rawget(_G, "CT_DIAG_LOG") ~= true then return end
        pcall(function()
            local f = io.open("TrainingComboTrials_data/ct_diag.log", "a")
            if f then
                f:write(os.date("%H:%M:%S ") .. tostring(message) .. "\n")
                f:close()
            end
        end)
    end
end

function M.init(context)
    trial_state = context.trial_state
    file_system = context.file_system
    players = context.players
    assign_groups = context.assign_groups
    reset_trial_flags = context.reset_trial_flags
    reset_visual_state = context.reset_visual_state
    -- #7: dedup store for one-time combo-file warnings.
    if type(file_system.combo_file_warnings) ~= "table" then
        file_system.combo_file_warnings = {}
    end
    attach_completion_api()
end

return M
