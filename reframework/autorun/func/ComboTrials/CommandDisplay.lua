-- =========================================================
-- func/ComboTrials/CommandDisplay.lua
--
-- Reader for cdjay's unified "xt.command_display.v1" character catalogs
-- (the ac_bcm export). VENDORED VERBATIM from SF6_TOOLS_CC
--   autorun/func/ComboTrials_ImGui.lua  @ 79f1a24
-- so both forks resolve classic/modern notation identically. The blocks
-- below are copied unchanged (constants, trim_string, the strict loader,
-- and the route-evidence resolver); only this header, the module table and
-- the public API at the bottom are ours. Do NOT hand-edit the vendored
-- body -- re-vendor from upstream when cdjay updates the resolver.
--
-- Files live in: reframework/data/TrainingComboTrials_data/command_display/
-- =========================================================

local json = json
local M = { name = "ComboTrials.CommandDisplay" }

-- [vendored] reason constants + runtime-common table (src 163-191)
local COMMAND_DISPLAY_DIR = "TrainingComboTrials_data/command_display/"
local RUNTIME_COMMON_REASON = "sf6_stable_runtime_common_movement_action"
local OFFICIAL_SEMANTIC_REASON = "capcom_official_command_semantics_matched_to_current_bcm_identity"
local COMMUNITY_SEMANTIC_REASON = "verified_community_command_semantics_matched_to_current_bcm_identity"
local VERIFIED_ALIAS_REASON = "ac_verified_equivalent_action_variant"
local TYPE20_DIRECTION_REASON = "ac_type20_verified_directional_air_attack"
local TYPE20_HOLD_REASON = "ac_type20_verified_hold_continuation"
local TYPE20_PHASE_REASON = "ac_type20_verified_multi_input_action_phase"
local CHARGE_CONTEXT_REASON = "bcm_charge_profile_context_proves_modern_held_shortcut"
local AC_CHARGE_CONTEXT_REASON = "ac_full_structure_peer_and_bcm_selector_prove_charge_context"
local SUPER_SHORTCUT_DIRECTION_REASON = "bcm_super_supr_direction_qualifies_easy_shortcut"
local CHARGE_COMPATIBILITY_REASON = "bcm_true_charge_trigger_suppresses_uncharged_compatibility_trigger"
local OFFICIAL_DIRECT_ROUTE_REASON = "capcom_official_exact_action_and_classic_identity_select_unique_direct_route"
local AC_STATE_DIRECTION_REASON = "ac_type20_multi_direction_state_choice"
local AC_STATE_NEUTRAL_REASON = "ac_type1_neutral_branch_beside_multi_direction_state_choices"
local AC_TYPE13_NEUTRAL_REASON = "ac_type13_zero_input_terminal_continuation_with_directional_sibling"
local AC_STATE_RELEASE_REASON = "ac_type20_release_transition_from_verified_direction_state"
local BCM_ZERO_INPUT_TRANSITION_REASON = "bcm_function2_normal_has_no_player_visible_input"
local TARGET_COMBO_REPEAT_REASON = "bcm_turn_around_target_combo_repeats_parent_button"
local STRUCTURAL_TWIN_REASON = "ac_bcm_unique_structural_twin_with_internal_use_super_delta"
local ASSIST_COMBO_REASON = "bcm_assist_combo_recipe_direct_input_sequence"
local RUNTIME_COMMON_ACTIONS = {
    [17] = "66",
    [18] = "44",
    [36] = "8",
    [37] = "9",
    [38] = "7",
    [489] = "DP"
}

-- [vendored] trim_string (src 141-144)
local function trim_string(value)
    local s = tostring(value or "")
    return s:match("^%s*(.-)%s*$") or ""
end

-- [vendored] module cache state + forward decl (src 192-198)
local command_display_cache = {}
local command_display_runtime = {
    cache_status = {},
    seen_refs = setmetatable({}, { __mode = "k" }),
    seen_keys = {}
}
local build_slim_command_display_map

-- [vendored] strict loader (src 286-738)
local function load_command_display_map(character)
    local key = tostring(character or "")
    key = key:gsub("[^%w_]", "")
    if key == "" or key == "Unknown" then return nil, "invalid_character" end

    if command_display_cache[key] ~= nil then
        return command_display_cache[key] ~= false and command_display_cache[key] or nil,
            command_display_runtime.cache_status[key]
    end

    local path = COMMAND_DISPLAY_DIR .. key .. ".json"
    local ok, loaded = false, nil
    if type(_G.safe_load_json) == "function" then
        ok, loaded = pcall(_G.safe_load_json, path)
    elseif json and json.load_file then
        ok, loaded = pcall(json.load_file, path)
    end

    local meta = ok and type(loaded) == "table" and loaded._meta or nil
    local audit = type(meta) == "table" and meta.audit or nil
    local schema = type(meta) == "table" and tostring(meta.schema or ""):lower() or ""
    local policy = type(meta) == "table" and tostring(meta.strict_policy or ""):lower() or ""
    local has_rebind_audit = type(audit) == "table"
        and (audit.ac_type17_relation_count ~= nil
            or audit.ac_command_entry_rebind_signature_count ~= nil
            or audit.ac_command_entry_rebind_relation_count ~= nil
            or audit.ac_command_entry_rebind_route_count ~= nil)
    local rebind_audit_ok = not has_rebind_audit
    if has_rebind_audit then
        local type17 = tonumber(audit.ac_type17_relation_count)
        local signatures = tonumber(audit.ac_command_entry_rebind_signature_count)
        local relations = tonumber(audit.ac_command_entry_rebind_relation_count)
        local routes = tonumber(audit.ac_command_entry_rebind_route_count)
        rebind_audit_ok = type17 ~= nil and signatures ~= nil and relations ~= nil and routes ~= nil
            and type17 >= signatures and signatures >= relations and routes >= relations and relations >= 0
            and type17 == math.floor(type17) and signatures == math.floor(signatures)
            and relations == math.floor(relations) and routes == math.floor(routes)
            and (meta.rebind_route_count == nil or tonumber(meta.rebind_route_count) == routes)
            and type(meta.ac_command_entry_rebinds) == "table"
            and #meta.ac_command_entry_rebinds == relations
    end
    local has_runtime_common_audit = type(audit) == "table"
        and (audit.runtime_common_action_count ~= nil or audit.runtime_common_route_count ~= nil)
    local runtime_common_audit_ok = not has_runtime_common_audit
    if has_runtime_common_audit then
        local actions = tonumber(audit.runtime_common_action_count)
        local routes = tonumber(audit.runtime_common_route_count)
        runtime_common_audit_ok = actions ~= nil and routes ~= nil and actions >= 0 and routes == actions
            and actions == math.floor(actions) and routes == math.floor(routes)
            and tonumber(meta.runtime_common_route_count) == routes
            and type(meta.runtime_common_actions) == "table"
            and #meta.runtime_common_actions == actions
    end
    local official_routes = type(audit) == "table" and tonumber(audit.official_semantic_route_count) or nil
    local official_bindings = type(audit) == "table" and tonumber(audit.official_semantic_binding_count) or nil
    local official_unresolved = type(audit) == "table" and tonumber(audit.official_semantic_unresolved_count) or nil
    local official_qualified = type(audit) == "table"
        and tonumber(audit.official_semantic_qualified_direct_route_count) or nil
    local official_semantic_audit_ok = official_routes ~= nil and official_bindings ~= nil
        and official_unresolved ~= nil and official_qualified ~= nil
        and official_routes >= 0 and official_bindings >= 0 and official_qualified >= 0
        and official_unresolved >= 0 and official_routes == math.floor(official_routes)
        and official_bindings == math.floor(official_bindings)
        and official_unresolved == math.floor(official_unresolved)
        and official_qualified == math.floor(official_qualified)
        and tonumber(meta.official_semantic_route_count) == official_routes
        and tonumber(meta.official_semantic_qualified_direct_route_count) == official_qualified
        and type(meta.official_semantic_bindings) == "table"
        and #meta.official_semantic_bindings == official_bindings
        and type(meta.official_semantic_unresolved) == "table"
        and #meta.official_semantic_unresolved == official_unresolved
    local community_routes = type(audit) == "table" and tonumber(audit.community_semantic_route_count) or nil
    local community_bindings = type(audit) == "table" and tonumber(audit.community_semantic_binding_count) or nil
    local community_unresolved = type(audit) == "table" and tonumber(audit.community_semantic_unresolved_count) or nil
    local community_qualified = type(audit) == "table"
        and tonumber(audit.community_semantic_qualified_direct_route_count) or nil
    local community_semantic_audit_ok = community_routes ~= nil and community_bindings ~= nil
        and community_unresolved ~= nil and community_qualified ~= nil
        and community_routes >= 0 and community_bindings >= 0 and community_unresolved >= 0
        and community_qualified >= 0 and community_routes == math.floor(community_routes)
        and community_bindings == math.floor(community_bindings)
        and community_unresolved == math.floor(community_unresolved)
        and community_qualified == math.floor(community_qualified)
        and tonumber(meta.community_semantic_route_count) == community_routes
        and tonumber(meta.community_semantic_qualified_direct_route_count) == community_qualified
        and type(meta.community_semantic_bindings) == "table"
        and #meta.community_semantic_bindings == community_bindings
        and type(meta.community_semantic_unresolved) == "table"
        and #meta.community_semantic_unresolved == community_unresolved
    local verified_alias_relations = type(audit) == "table"
        and tonumber(audit.verified_alias_relation_count) or nil
    local verified_alias_routes = type(audit) == "table"
        and tonumber(audit.verified_alias_route_count) or nil
    local verified_alias_audit_ok = verified_alias_relations ~= nil and verified_alias_routes ~= nil
        and verified_alias_relations >= 0 and verified_alias_routes >= verified_alias_relations
        and verified_alias_relations == math.floor(verified_alias_relations)
        and verified_alias_routes == math.floor(verified_alias_routes)
        and tonumber(meta.verified_alias_route_count) == verified_alias_routes
        and type(meta.verified_alias_relations) == "table"
        and #meta.verified_alias_relations == verified_alias_relations
    local type20_relations = type(audit) == "table"
        and tonumber(audit.type20_directional_relation_count) or nil
    local type20_routes = type(audit) == "table"
        and tonumber(audit.type20_directional_route_count) or nil
    local type20_audit_ok = type20_relations ~= nil and type20_routes ~= nil
        and type20_relations >= 0 and type20_routes >= type20_relations
        and tonumber(meta.type20_directional_route_count) == type20_routes
        and type(meta.type20_directional_relations) == "table"
        and #meta.type20_directional_relations == type20_relations
    local type20_hold_relations = type(audit) == "table"
        and tonumber(audit.type20_hold_relation_count) or nil
    local type20_hold_routes = type(audit) == "table"
        and tonumber(audit.type20_hold_route_count) or nil
    local type20_hold_audit_ok = type20_hold_relations ~= nil and type20_hold_routes ~= nil
        and type20_hold_relations >= 0 and type20_hold_routes == type20_hold_relations
        and type20_hold_relations == math.floor(type20_hold_relations)
        and type20_hold_routes == math.floor(type20_hold_routes)
        and tonumber(meta.type20_hold_route_count) == type20_hold_routes
        and type(meta.type20_hold_relations) == "table"
        and #meta.type20_hold_relations == type20_hold_relations
    local type20_phase_relations = type(audit) == "table"
        and tonumber(audit.type20_action_phase_relation_count) or nil
    local type20_phase_routes = type(audit) == "table"
        and tonumber(audit.type20_action_phase_route_count) or nil
    local type20_phase_audit_ok = type20_phase_relations ~= nil and type20_phase_routes ~= nil
        and type20_phase_relations >= 0 and type20_phase_routes >= type20_phase_relations
        and type20_phase_relations == math.floor(type20_phase_relations)
        and type20_phase_routes == math.floor(type20_phase_routes)
        and tonumber(meta.type20_action_phase_route_count) == type20_phase_routes
        and type(meta.type20_action_phase_relations) == "table"
        and #meta.type20_action_phase_relations == type20_phase_relations
    local target_combo_relations = type(audit) == "table"
        and tonumber(audit.target_combo_repeat_relation_count) or nil
    local target_combo_routes = type(audit) == "table"
        and tonumber(audit.target_combo_repeat_route_count) or nil
    local target_combo_audit_ok = target_combo_relations ~= nil and target_combo_routes ~= nil
        and target_combo_relations >= 0 and target_combo_routes >= target_combo_relations
        and tonumber(meta.target_combo_repeat_route_count) == target_combo_routes
        and type(meta.target_combo_repeat_relations) == "table"
        and #meta.target_combo_repeat_relations == target_combo_relations
    local structural_twin_relations = type(audit) == "table"
        and tonumber(audit.structural_twin_relation_count) or nil
    local structural_twin_routes = type(audit) == "table"
        and tonumber(audit.structural_twin_route_count) or nil
    local structural_twin_audit_ok = structural_twin_relations ~= nil and structural_twin_routes ~= nil
        and structural_twin_relations >= 0 and structural_twin_routes >= structural_twin_relations
        and tonumber(meta.structural_twin_route_count) == structural_twin_routes
        and type(meta.structural_twin_relations) == "table"
        and #meta.structural_twin_relations == structural_twin_relations
    local assist_combo_candidates = type(audit) == "table"
        and tonumber(audit.assist_combo_candidate_count) or nil
    local assist_combo_relations = type(audit) == "table"
        and tonumber(audit.assist_combo_relation_count) or nil
    local assist_combo_routes = type(audit) == "table"
        and tonumber(audit.assist_combo_route_count) or nil
    local assist_combo_duplicates = type(audit) == "table"
        and tonumber(audit.assist_combo_duplicate_display_count) or nil
    local assist_combo_normalized = type(audit) == "table"
        and tonumber(audit.assist_combo_normalized_to_existing_count) or nil
    local assist_combo_audit_ok = assist_combo_candidates ~= nil and assist_combo_relations ~= nil
        and assist_combo_routes ~= nil and assist_combo_duplicates ~= nil
        and assist_combo_normalized ~= nil
        and assist_combo_candidates >= 0 and assist_combo_relations >= 0
        and assist_combo_routes == assist_combo_relations
        and assist_combo_duplicates >= 0 and assist_combo_normalized >= 0
        and assist_combo_candidates == assist_combo_relations
            + assist_combo_duplicates + assist_combo_normalized
        and assist_combo_candidates == math.floor(assist_combo_candidates)
        and assist_combo_relations == math.floor(assist_combo_relations)
        and assist_combo_routes == math.floor(assist_combo_routes)
        and assist_combo_duplicates == math.floor(assist_combo_duplicates)
        and assist_combo_normalized == math.floor(assist_combo_normalized)
        and tonumber(meta.assist_combo_route_count) == assist_combo_routes
        and tonumber(meta.assist_combo_normalized_to_existing_count) == assist_combo_normalized
        and type(meta.assist_combo_relations) == "table"
        and #meta.assist_combo_relations == assist_combo_relations
    local paired_sprt_sp_relations = type(audit) == "table"
        and tonumber(audit.paired_sprt_sp_relation_count) or nil
    local paired_sprt_sp_routes = type(audit) == "table"
        and tonumber(audit.paired_sprt_sp_route_count) or nil
    local paired_sprt_sp_audit_ok = paired_sprt_sp_relations ~= nil
        and paired_sprt_sp_routes ~= nil
        and paired_sprt_sp_relations >= 0
        and paired_sprt_sp_routes == paired_sprt_sp_relations
        and paired_sprt_sp_relations == math.floor(paired_sprt_sp_relations)
        and paired_sprt_sp_routes == math.floor(paired_sprt_sp_routes)
        and tonumber(meta.paired_sprt_sp_route_count) == paired_sprt_sp_routes
        and type(meta.paired_sprt_sp_relations) == "table"
        and #meta.paired_sprt_sp_relations == paired_sprt_sp_relations
    local shadowed_supr_count = type(audit) == "table"
        and tonumber(audit.shadowed_supr_route_count) or nil
    local shadowed_supr_audit_ok = shadowed_supr_count ~= nil
        and shadowed_supr_count >= 0
        and shadowed_supr_count == math.floor(shadowed_supr_count)
        and tonumber(meta.shadowed_supr_route_count) == shadowed_supr_count
        and type(meta.shadowed_supr_routes) == "table"
        and #meta.shadowed_supr_routes == shadowed_supr_count
    local hold_transition_aliases = type(audit) == "table"
        and tonumber(audit.hold_transition_type29_alias_suppression_count) or nil
    local hold_transition_actions = type(audit) == "table"
        and tonumber(audit.hold_transition_suppressed_action_count) or nil
    local hold_transition_audit_ok = hold_transition_aliases ~= nil
        and hold_transition_actions ~= nil and hold_transition_aliases >= 0
        and hold_transition_actions >= 0 and hold_transition_actions <= hold_transition_aliases
        and hold_transition_aliases == math.floor(hold_transition_aliases)
        and hold_transition_actions == math.floor(hold_transition_actions)
        and tonumber(meta.hold_transition_type29_alias_suppression_count) == hold_transition_aliases
        and tonumber(meta.hold_transition_suppressed_action_count) == hold_transition_actions
        and type(meta.hold_transition_type29_alias_suppressions) == "table"
        and #meta.hold_transition_type29_alias_suppressions == hold_transition_aliases
    local charge_context_routes = type(audit) == "table"
        and tonumber(audit.charge_context_route_count) or nil
    local super_shortcut_routes = type(audit) == "table"
        and tonumber(audit.super_shortcut_direction_route_count) or nil
    local ac_charge_relations = type(audit) == "table"
        and tonumber(audit.ac_charge_context_relation_count) or nil
    local charge_suppressions = type(audit) == "table"
        and tonumber(audit.charge_compatibility_trigger_suppression_count) or nil
    local charge_context_audit_ok = charge_context_routes ~= nil
        and super_shortcut_routes ~= nil and ac_charge_relations ~= nil
        and charge_suppressions ~= nil
        and charge_context_routes >= 0 and super_shortcut_routes >= 0
        and ac_charge_relations >= 0 and charge_suppressions >= 0
        and charge_context_routes == math.floor(charge_context_routes)
        and super_shortcut_routes == math.floor(super_shortcut_routes)
        and ac_charge_relations == math.floor(ac_charge_relations)
        and charge_suppressions == math.floor(charge_suppressions)
        and tonumber(meta.charge_context_route_count) == charge_context_routes
        and tonumber(meta.super_shortcut_direction_route_count) == super_shortcut_routes
        and tonumber(meta.ac_charge_context_relation_count) == ac_charge_relations
        and type(meta.ac_charge_context_relations) == "table"
        and #meta.ac_charge_context_relations == ac_charge_relations
        and tonumber(meta.charge_compatibility_trigger_suppression_count) == charge_suppressions
        and type(meta.charge_compatibility_trigger_suppressions) == "table"
        and #meta.charge_compatibility_trigger_suppressions == charge_suppressions
    if charge_context_audit_ok then
        for _, relation in ipairs(meta.charge_compatibility_trigger_suppressions) do
            if type(relation) ~= "table" or tonumber(relation.action_id) == nil
                or tonumber(relation.suppressed_trigger_index) == nil
                or type(relation.retained_trigger_indices) ~= "table"
                or #relation.retained_trigger_indices == 0
                or relation.profile ~= "sprt"
                or relation.reason ~= CHARGE_COMPATIBILITY_REASON then
                charge_context_audit_ok = false
                break
            end
        end
    end
    if charge_context_audit_ok then
        for _, relation in ipairs(meta.ac_charge_context_relations) do
            if type(relation) ~= "table" or tonumber(relation.source_action_id) == nil
                or tonumber(relation.target_action_id) == nil
                or tonumber(relation.source_action_id) == tonumber(relation.target_action_id)
                or tonumber(relation.target_trigger_index) == nil
                or type(relation.source_trigger_indices) ~= "table"
                or #relation.source_trigger_indices == 0
                or (relation.profile ~= "easy" and relation.profile ~= "supr")
                or type(relation.direction) ~= "string"
                or relation.direction:match("^[1246789]$") == nil
                or (relation.source_charge_profile ~= "sprt"
                    and relation.source_charge_profile ~= "norm")
                or relation.reason ~= AC_CHARGE_CONTEXT_REASON then
                charge_context_audit_ok = false
                break
            end
        end
    end
    local official_direct_restrictions = type(audit) == "table"
        and tonumber(audit.official_direct_route_restriction_count) or nil
    local state_direction_relations = type(audit) == "table"
        and tonumber(audit.ac_state_direction_relation_count) or nil
    local state_direction_routes = type(audit) == "table"
        and tonumber(audit.ac_state_direction_route_count) or nil
    local state_neutral_relations = type(audit) == "table"
        and tonumber(audit.ac_state_neutral_relation_count) or nil
    local state_neutral_routes = type(audit) == "table"
        and tonumber(audit.ac_state_neutral_route_count) or nil
    local type13_neutral_relations = type(audit) == "table"
        and tonumber(audit.ac_type13_neutral_relation_count) or nil
    local type13_neutral_routes = type(audit) == "table"
        and tonumber(audit.ac_type13_neutral_route_count) or nil
    local internal_suppressions = type(audit) == "table"
        and tonumber(audit.internal_transition_suppression_count) or nil
    local state_choice_audit_ok = official_direct_restrictions ~= nil
        and state_direction_relations ~= nil and state_direction_routes ~= nil
        and state_neutral_relations ~= nil and state_neutral_routes ~= nil
        and type13_neutral_relations ~= nil and type13_neutral_routes ~= nil
        and internal_suppressions ~= nil
        and official_direct_restrictions >= 0
        and state_direction_relations >= 0 and state_direction_routes == state_direction_relations
        and state_neutral_relations >= 0 and state_neutral_routes == state_neutral_relations
        and type13_neutral_relations >= 0 and type13_neutral_routes == type13_neutral_relations
        and internal_suppressions >= 0
        and tonumber(meta.official_direct_route_restriction_count) == official_direct_restrictions
        and type(meta.official_direct_route_restrictions) == "table"
        and #meta.official_direct_route_restrictions == official_direct_restrictions
        and tonumber(meta.ac_state_direction_route_count) == state_direction_routes
        and type(meta.ac_state_direction_relations) == "table"
        and #meta.ac_state_direction_relations == state_direction_relations
        and tonumber(meta.ac_state_neutral_route_count) == state_neutral_routes
        and type(meta.ac_state_neutral_relations) == "table"
        and #meta.ac_state_neutral_relations == state_neutral_relations
        and tonumber(meta.ac_type13_neutral_route_count) == type13_neutral_routes
        and type(meta.ac_type13_neutral_relations) == "table"
        and #meta.ac_type13_neutral_relations == type13_neutral_relations
        and tonumber(meta.internal_transition_suppression_count) == internal_suppressions
        and type(meta.suppressed_internal_transitions) == "table"
        and #meta.suppressed_internal_transitions == internal_suppressions
    local split_command_audit_ok = true
    if schema == "xt.command_display.v1" then
        local split_actions = type(audit) == "table"
            and tonumber(audit.split_command_action_count) or nil
        local followup_count = type(audit) == "table"
            and tonumber(audit.followup_relation_count) or nil
        local overflow_count = type(audit) == "table"
            and tonumber(audit.command_slot_overflow_count) or nil
        split_command_audit_ok = split_actions ~= nil and followup_count ~= nil
            and overflow_count == 0 and split_actions >= 0 and followup_count >= 0
            and split_actions == math.floor(split_actions)
            and followup_count == math.floor(followup_count)
            and tonumber(meta.split_command_action_count) == split_actions
            and tonumber(meta.followup_relation_count) == followup_count
            and type(meta.followup_relations) == "table"
            and #meta.followup_relations == followup_count
        if split_command_audit_ok then
            for _, relation in ipairs(meta.followup_relations) do
                if type(relation) ~= "table" or relation.type ~= "followup"
                    or tonumber(relation.source_action_id) == nil
                    or tonumber(relation.target_action_id) == nil
                    or tonumber(relation.source_action_id) == tonumber(relation.target_action_id)
                    or relation.evidence ~= "capcom_official_followup_context_matches_source_move" then
                    split_command_audit_ok = false
                    break
                end
            end
        end
    end
    local unified_command_audit_ok = true
    if schema == "xt.command_display.v1" then
        local classic_count = 0
        local shared_count = 0
        local action_count = 0
        for action_id, entry in pairs(loaded) do
            if tostring(action_id):match("^%d+$") and type(entry) == "table" then
                action_count = action_count + 1
                local classic = entry.classic_command
                local has_classic = type(classic) == "table"
                    and type(classic.display) == "string" and trim_string(classic.display) ~= ""
                    and type(classic.inputs) == "table" and #classic.inputs > 0
                if has_classic then
                    for _, input in ipairs(classic.inputs) do
                        if type(input) ~= "string" or trim_string(input) == "" then
                            has_classic = false
                            break
                        end
                    end
                elseif classic ~= nil then
                    unified_command_audit_ok = false
                end
                local has_modern = type(entry.simple_command) == "table"
                    or type(entry.motion_command) == "table"
                if has_classic then classic_count = classic_count + 1 end
                if has_classic and has_modern then shared_count = shared_count + 1 end
            end
        end
        unified_command_audit_ok = unified_command_audit_ok
            and tonumber(audit and audit.classic_command_action_count) == classic_count
            and tonumber(audit and audit.shared_command_action_count) == shared_count
            and tonumber(audit and audit.classic_projection_pending_count)
                == tonumber(audit and audit.split_command_action_count) - shared_count
            and tonumber(audit and audit.classic_projection_pending_count) == 0
            and tonumber(audit and audit.command_display_action_count) == action_count
            and type(meta.classic_profile_order) == "table"
            and meta.classic_profile_order[1] == "norm"
            and meta.classic_profile_order[2] == "sprt"
        local projection_count = tonumber(meta.classic_projection_relation_count)
        local projection_relations = meta.classic_projection_relations
        unified_command_audit_ok = unified_command_audit_ok
            and projection_count ~= nil
            and tonumber(audit and audit.classic_projection_relation_count) == projection_count
            and type(projection_relations) == "table"
            and #projection_relations == projection_count
        local projection_reasons = {
            ac_full_structure_unique_classic_projection = true,
            ac_full_structure_bcm_condition_classic_projection = true,
            ac_full_structure_assist_strength_classic_projection = true,
            bcm_unique_condition_classic_projection = true,
        }
        if unified_command_audit_ok then
            for _, relation in ipairs(projection_relations) do
                if type(relation) ~= "table"
                    or tonumber(relation.source_action_id) == nil
                    or tonumber(relation.target_action_id) == nil
                    or tonumber(relation.source_action_id) == tonumber(relation.target_action_id)
                    or type(relation.classic_display) ~= "string"
                    or trim_string(relation.classic_display) == ""
                    or projection_reasons[relation.reason] ~= true then
                    unified_command_audit_ok = false
                    break
                end
            end
        end
    end
    local strict_audit = type(audit) == "table" and audit.strict_route_ownership == true
        and tonumber(audit.owner_missing_count or -1) == 0
        and tonumber(audit.no_evidence_count or -1) == 0
        and tonumber(audit.direct_overridden_count or -1) == 0
        and tonumber(audit.overlay_entry_count or -1) == 0
        and tonumber(audit.community_route_count or -1) == 0
        and tonumber(audit.alias_propagation_count or -1) == 0
        and tonumber(audit.type17_route_count or -1) == 0
        and tonumber(audit.ac_automatic_transition_route_count or -1) == 0
        and tonumber(audit.replaces_profile_route_count or -1) == 0
        and tonumber(audit.non_whitelist_propagation_count or -1) == 0
        and rebind_audit_ok
        and runtime_common_audit_ok
        and official_semantic_audit_ok
        and community_semantic_audit_ok
        and verified_alias_audit_ok
        and type20_audit_ok
        and type20_hold_audit_ok
        and type20_phase_audit_ok
        and target_combo_audit_ok
        and structural_twin_audit_ok
        and assist_combo_audit_ok
        and paired_sprt_sp_audit_ok
        and shadowed_supr_audit_ok
        and hold_transition_audit_ok
        and charge_context_audit_ok
        and state_choice_audit_ok
        and split_command_audit_ok
        and unified_command_audit_ok
    local supported_schema = schema == "xt.command_display.v1"
        and policy == "verified_action_graph_v1"
    if type(meta) == "table"
        and supported_schema
        and (tostring(meta.generated_from or ""):lower() == "ac_bcm"
            or tostring(meta.generated_from or ""):lower() == "ac_bcm+capcom_official_semantics"
            or tostring(meta.generated_from or ""):lower() == "ac_bcm+community_verified_semantics"
            or tostring(meta.generated_from or ""):lower() == "ac_bcm+capcom_official_semantics+community_verified_semantics")
        and tostring(meta.character or "") == key
        and strict_audit then
        local slim = build_slim_command_display_map(loaded)
        loaded = nil
        command_display_cache[key] = slim
        command_display_runtime.cache_status[key] = "loaded"
        return slim, "loaded"
    end

    command_display_cache[key] = false
    command_display_runtime.cache_status[key] = ok and "invalid_schema_or_policy" or "map_load_failed"
    return nil, command_display_runtime.cache_status[key]
end

-- [vendored] route-evidence resolver + slim map + queries (src 740-1532)
local function get_player_visible_transition_motion(step)
    if type(step) ~= "table" then return nil end
    local motion = trim_string(step.motion)
    if motion == "" then return nil end
    if step.player_input_transition == true or step._ct_player_input_transition == true then return motion end
    local upper = motion:upper()
    if motion:match("^>") and (upper:find("FEINT", 1, true)
        or upper:find("CANCEL", 1, true)
        or motion:find("取消", 1, true)
        or motion:find("假动作", 1, true)) then
        return motion
    end
    return nil
end

local function get_modern_display_motion(modern_map, step)
    if type(modern_map) ~= "table" or type(step) ~= "table" then return nil, "map_unavailable" end
    local step_id = tonumber(step.id)
    if modern_map._slim == true then
        local resolved = modern_map[tostring(step.id or "")]
        if type(resolved) ~= "table" then return nil, "action_id_missing" end
        if resolved.status == "suppress_transition" then
            local player_transition = get_player_visible_transition_motion(step)
            if player_transition then return player_transition, "player_input_transition" end
        end
        return resolved.commands or resolved.motion, resolved.status or "route_unverified"
    end
    local entry = modern_map[tostring(step.id or "")]
    if type(entry) ~= "table" or type(entry.routes) ~= "table" then return nil, "action_id_missing" end
    if entry.suppress_display == true then
        local player_transition = get_player_visible_transition_motion(step)
        if player_transition then return player_transition, "player_input_transition" end
        local evidence = entry.transition_evidence
        local declared = false
        local internal_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.suppressed_internal_transitions or nil
        if type(evidence) == "table" and type(internal_declarations) == "table"
            and entry.ownership == "internal_state_transition" and #entry.routes == 0
            and step_id ~= nil and tonumber(evidence.target_action_id) == step_id then
            for _, relation in ipairs(internal_declarations) do
                local same = type(relation) == "table"
                    and tostring(relation.kind or "") == tostring(evidence.kind or "")
                    and tonumber(relation.target_action_id) == step_id
                    and tostring(relation.reason or "") == tostring(evidence.reason or "")
                if same and evidence.kind == "ac_state_direction_release" then
                    same = tonumber(relation.branch_type) == 20
                        and tonumber(relation.param00) == 0
                        and tonumber(relation.direction_mask) == tonumber(evidence.direction_mask)
                        and relation.reason == AC_STATE_RELEASE_REASON
                elseif same and evidence.kind == "bcm_zero_input_transition" then
                    same = tonumber(relation.function_id) == 2
                        and type(relation.trigger_indices) == "table"
                        and #relation.trigger_indices > 0
                        and relation.reason == BCM_ZERO_INPUT_TRANSITION_REASON
                else
                    same = false
                end
                if same then declared = true; break end
            end
        end
        if declared then return nil, "suppress_transition" end
        local declarations = type(modern_map._meta) == "table"
            and modern_map._meta.hold_transition_type29_alias_suppressions or nil
        if type(evidence) == "table" and type(declarations) == "table"
            and entry.ownership == "automatic_hold_transition" and #entry.routes == 0
            and step_id ~= nil and tonumber(evidence.target_action_id) == step_id
            and tonumber(evidence.selected_source_action_id) ~= nil
            and type(evidence.incoming_source_action_ids) == "table"
            and #evidence.incoming_source_action_ids > 1
            and evidence.reason == "type29_target_is_reached_from_verified_hold_continuation" then
            for _, relation in ipairs(declarations) do
                if type(relation) == "table" and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.selected_source_action_id) == tonumber(evidence.selected_source_action_id)
                    and relation.reason == evidence.reason
                    and type(relation.incoming_source_action_ids) == "table"
                    and #relation.incoming_source_action_ids == #evidence.incoming_source_action_ids then
                    local same_sources = true
                    for index, source_id in ipairs(evidence.incoming_source_action_ids) do
                        if tonumber(relation.incoming_source_action_ids[index]) ~= tonumber(source_id) then
                            same_sources = false
                            break
                        end
                    end
                    if same_sources then declared = true; break end
                end
            end
        end
        if declared then return nil, "suppress_transition" end
        return nil, "invalid_suppress_transition"
    end
    local displays, seen = {}, {}
    for _, route in ipairs(entry.routes) do
        local source = type(route) == "table" and tostring(route.source or "") or ""
        local route_character = type(route) == "table" and tostring(route.character or "") or ""
        local map_character = type(modern_map._meta) == "table" and tostring(modern_map._meta.character or "") or ""
        local charge_direction = type(route) == "table"
            and tostring(route.charge_context_direction or "") or ""
        local charge_manual_direction = type(route) == "table"
            and tostring(route.charge_context_manual_direction or "") or ""
        local charge_relation = type(route) == "table"
            and tostring(route.charge_context_relation or "") or ""
        local charge_source_action = type(route) == "table"
            and tonumber(route.charge_context_source_action_id) or nil
        local charge_owner_action = type(route) == "table"
            and tonumber(route.owner_action_id) or nil
        local charge_source_triggers = type(route) == "table"
            and route.charge_context_source_trigger_indices or nil
        local charge_reason_ok = type(route) == "table" and (
            charge_relation == "same_trigger_bcm"
                and charge_source_action == charge_owner_action
                and route.charge_context_reason == CHARGE_CONTEXT_REASON
            or charge_relation == "ac_full_structure_peer"
                and charge_source_action ~= nil
                and charge_source_action ~= charge_owner_action
                and route.charge_context_reason == AC_CHARGE_CONTEXT_REASON)
        local charge_context_ok = type(route) == "table"
            and (route.charge_context_evidence ~= true
                or ((route.charge_context_profile == "sprt"
                    or route.charge_context_profile == "norm")
                    and charge_direction:match("^[1246789]$") ~= nil
                    and charge_manual_direction:match("^[1246789]$") ~= nil
                    and (route.charge_context_direction_profile == "sprt"
                        or route.charge_context_direction_profile == "norm"
                        or route.charge_context_direction_profile == "supr")
                    and tonumber(route.charge_context_command_no) ~= nil
                    and tonumber(route.charge_context_command_no) >= 0
                    and tonumber(route.charge_context_command_index) ~= nil
                    and tonumber(route.charge_context_command_index) >= 0
                    and type(route.charge_context_notation) == "string"
                    and route.charge_context_notation:find(
                        "[" .. charge_manual_direction .. "]", 1, true) ~= nil
                    and type(charge_source_triggers) == "table"
                    and #charge_source_triggers > 0
                    and charge_reason_ok
                    and type(route.display) == "string"
                    and route.display:find("[" .. charge_direction .. "]", 1, true) ~= nil))
        local super_shortcut_direction = type(route) == "table"
            and tostring(route.super_shortcut_direction or "") or ""
        local super_shortcut_ok = type(route) == "table"
            and (route.super_shortcut_direction_evidence ~= true
                or (route.super_shortcut_direction_profile == "supr"
                    and super_shortcut_direction:match("^[1246789]$") ~= nil
                    and type(route.super_shortcut_direction_notation) == "string"
                    and route.super_shortcut_direction_reason
                        == SUPER_SHORTCUT_DIRECTION_REASON))
        local direct_ok = (source == "bcm_profile" or source == "bcm_common_semantic")
            and route.direct_evidence == true and route.inheritance_evidence == false
            and route.rebind_evidence ~= true and route.rebind_reason == nil
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and route.confidence == "direct_structural" and route_character == map_character
        local ac_path = type(route) == "table" and route.ac_path or nil
        local inherited_ok = source == "ac_type63_throw"
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence ~= true and route.rebind_reason == nil
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and tonumber(route.ac_relation_type) == 63
            and tonumber(route.owner_action_id) ~= nil
            and tonumber(route.inherited_from_action_id) ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path]) == step_id
            and route.confidence == "verified_inherited" and route_character == map_character
            and tostring(route.visible_button or ""):upper() == "THROW"
        local rebind_owner = type(route) == "table" and tonumber(route.bcm_owner_action_id) or nil
        local declared_rebind = false
        local declared_rebinds = type(modern_map._meta) == "table"
            and modern_map._meta.ac_command_entry_rebinds or nil
        if type(declared_rebinds) == "table" then
            for _, relation in ipairs(declared_rebinds) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == rebind_owner
                    and tonumber(relation.target_action_id) == step_id
                    and relation.reason == "ac_type17_command_entry_rebind_from_verified_bcm_owner" then
                    declared_rebind = true
                    break
                end
            end
        end
        local rebind_ok = source == "ac_command_entry_rebind"
            and route.direct_evidence == false and route.inheritance_evidence == false
            and route.rebind_evidence == true
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and entry.ownership == "rebind" and declared_rebind
            and step_id ~= nil and rebind_owner ~= nil and rebind_owner ~= step_id
            and tonumber(route.owner_action_id) == rebind_owner
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.ac_relation_type) == 17
            and type(ac_path) == "table" and #ac_path == 2
            and tonumber(ac_path[1]) == rebind_owner and tonumber(ac_path[2]) == step_id
            and route.inherited_from_action_id == nil
            and route.confidence == "verified_rebind" and route_character == map_character
            and route.rebind_reason == "ac_type17_command_entry_rebind_from_verified_bcm_owner"
            and route.inheritance_reason == nil
            and tonumber(route.ac_attr) == 0 and tonumber(route.ac_frame) == 0
            and tonumber(route.ac_param00) == 9 and tonumber(route.ac_param01) == 120
            and tonumber(route.ac_param02) == 0 and tonumber(route.ac_param03) == 0
            and tonumber(route.ac_param04) == 0 and tonumber(route.ac_param05) == 0
            and tonumber(route.ac_trigger_id) == -1
            and tonumber(route.trigger_index) ~= nil
            and (route.profile == "easy" or route.profile == "supr" or route.profile == "sprt")
            and tonumber(route.command_no) ~= nil and tonumber(route.command_index) ~= nil
            and type(route.raw_direction_inputs) == "table"
            and tonumber(route.raw_button_mask) ~= nil and tonumber(route.raw_button_condition) ~= nil
            and tonumber(route.raw_dc_exc_flags) ~= nil
            and type(route.visible_direction) == "string" and route.visible_direction ~= ""
            and type(route.visible_button) == "string" and route.visible_button ~= ""
            and type(route.button_candidates) == "table" and tonumber(route.required_button_count) ~= nil
        local expected_common = step_id ~= nil and RUNTIME_COMMON_ACTIONS[step_id] or nil
        local declared_common = false
        local declared_common_actions = type(modern_map._meta) == "table"
            and modern_map._meta.runtime_common_actions or nil
        if expected_common and type(declared_common_actions) == "table" then
            for _, common in ipairs(declared_common_actions) do
                if type(common) == "table" and tonumber(common.action_id) == step_id
                    and tostring(common.display or "") == expected_common
                    and common.reason == RUNTIME_COMMON_REASON then
                    declared_common = true
                    break
                end
            end
        end
        local runtime_common_ok = source == "runtime_common_action"
            and route.direct_evidence == false and route.inheritance_evidence == false
            and route.rebind_evidence == false and route.runtime_common_evidence == true
            and route.rebind_reason == nil and route.inheritance_reason == nil
            and route.runtime_common_reason == RUNTIME_COMMON_REASON
            and entry.ownership == "runtime_common" and declared_common
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.bcm_owner_action_id == nil
            and route.ac_relation_type == nil and type(ac_path) == "table" and #ac_path == 0
            and route.inherited_from_action_id == nil
            and route.confidence == "verified_runtime_common" and route_character == map_character
            and route.profile == "runtime_common" and tonumber(route.trigger_index) == -1
            and tonumber(route.command_no) == -1 and tonumber(route.command_index) == -1
            and type(route.raw_direction_inputs) == "table" and #route.raw_direction_inputs == 0
            and tonumber(route.raw_button_mask) == 0 and tonumber(route.raw_button_condition) == 0
            and tonumber(route.raw_dc_exc_flags) == 0
            and tostring(route.visible_direction or "") == expected_common
            and route.visible_button == nil and type(route.button_candidates) == "table"
            and #route.button_candidates == 0 and tonumber(route.required_button_count) == 0
        local declared_official = false
        local declared_official_bindings = type(modern_map._meta) == "table"
            and modern_map._meta.official_semantic_bindings or nil
        if type(declared_official_bindings) == "table" then
            for _, binding in ipairs(declared_official_bindings) do
                if type(binding) == "table" and tonumber(binding.target_action_id) == step_id
                    and tostring(binding.display or "") == tostring(route.display or "")
                    and binding.reason == OFFICIAL_SEMANTIC_REASON then
                    declared_official = true
                    break
                end
            end
        end
        local official_semantic_ok = source == "official_semantic_bcm_rebind"
            and route.direct_evidence == false and route.inheritance_evidence == false
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == true
            and route.official_semantic_reason == OFFICIAL_SEMANTIC_REASON
            and route.rebind_reason == nil and route.inheritance_reason == nil
            and route.runtime_common_reason == nil
            and declared_official and step_id ~= nil
            and tonumber(route.owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == step_id
            and route.ac_relation_type == nil and type(ac_path) == "table" and #ac_path == 0
            and route.inherited_from_action_id == nil
            and route.confidence == "verified_official_semantic_bcm_identity"
            and route_character == map_character and route.profile == "norm_identity"
            and tonumber(route.official_action_id_hint) ~= nil
            and tonumber(route.official_action_id_distance) ~= nil
            and tonumber(route.official_action_id_distance) >= 0
            and (route.official_action_id_hint_kind == "capcom_action_id"
                or route.official_action_id_hint_kind == "derived_current_bcm_identity")
            and ((route.official_action_id_hint_kind == "capcom_action_id"
                    and route.official_semantic_row_id == nil)
                or (route.official_action_id_hint_kind == "derived_current_bcm_identity"
                    and type(route.official_semantic_row_id) == "string"
                    and route.official_semantic_row_id ~= ""))
            and type(route.official_classic_display) == "string"
            and type(route.official_modern_display) == "string"
        local alias_source = type(route) == "table" and tonumber(route.inherited_from_action_id) or nil
        local alias_type = type(route) == "table" and tonumber(route.ac_relation_type) or nil
        local declared_alias = false
        local declared_aliases = type(modern_map._meta) == "table"
            and modern_map._meta.verified_alias_relations or nil
        if type(declared_aliases) == "table" then
            for _, relation in ipairs(declared_aliases) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == alias_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == alias_type
                    and relation.reason == VERIFIED_ALIAS_REASON then
                    declared_alias = true
                    break
                end
            end
        end
        local verified_alias_ok = source == "ac_verified_alias_variant"
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false
            and route.community_semantic_evidence == false
            and route.rebind_reason == nil and route.runtime_common_reason == nil
            and route.official_semantic_reason == nil and route.community_semantic_reason == nil
            and route.inheritance_reason == VERIFIED_ALIAS_REASON
            and entry.ownership == "verified_alias" and declared_alias
            and step_id ~= nil and (alias_type == 29 or alias_type == 35)
            and alias_source ~= nil and tonumber(route.owner_action_id) ~= nil
            and tonumber(route.display_action_id) == step_id
            and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == alias_source
            and tonumber(ac_path[#ac_path]) == step_id
            and route.confidence == "verified_inherited_alias"
            and route_character == map_character
        local inherited_source = type(route) == "table" and tonumber(route.inherited_from_action_id) or nil
        local declared_type20 = false
        local type20_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_directional_relations or nil
        if type(type20_declarations) == "table" then
            for _, relation in ipairs(type20_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and tostring(relation.direction or "") == tostring(route.visible_direction or "")
                    and tostring(relation.button or "") == tostring(route.visible_button or "")
                    and relation.reason == TYPE20_DIRECTION_REASON then
                    declared_type20 = true
                    break
                end
            end
        end
        local type20_ok = source == "ac_type20_directional_air_attack"
            and entry.ownership == "type20_directional" and declared_type20
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_DIRECTION_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_inherited_directional_attack"
            and route_character == map_character
            and tostring(route.display or "") == "空中 " .. tostring(route.visible_direction)
                .. " + " .. tostring(route.visible_button)
        local declared_type20_hold = false
        local type20_hold_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_hold_relations or nil
        if type(type20_hold_declarations) == "table" then
            for _, relation in ipairs(type20_hold_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and tonumber(relation.param00) == 1 and tonumber(relation.param02) == 0
                    and tonumber(relation.param03) == 1
                    and tonumber(relation.source_loop_count) == 0
                    and tonumber(relation.target_loop_count) == -1
                    and tostring(relation.button or "") == tostring(route.visible_button or "")
                    and relation.reason == TYPE20_HOLD_REASON then
                    declared_type20_hold = true
                    break
                end
            end
        end
        local type20_hold_ok = source == "ac_type20_hold_continuation"
            and entry.ownership == "type20_hold_continuation" and declared_type20_hold
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_HOLD_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.owner_action_id) ~= nil
            and tonumber(route.bcm_owner_action_id) == tonumber(route.owner_action_id)
            and route.confidence == "verified_inherited_hold_continuation"
            and route_character == map_character
            and tostring(route.display or "") == "> " .. tostring(route.visible_button)
            and tonumber(route.ac_param00) == 1 and tonumber(route.ac_param02) == 0
            and tonumber(route.ac_param03) == 1
            and tonumber(route.source_loop_count) == 0 and tonumber(route.target_loop_count) == -1
        local declared_type20_phase = false
        local type20_phase_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_action_phase_relations or nil
        local phase_signature_ok = false
        if type(route.ac_phase_signatures) == "table" and #route.ac_phase_signatures == 4 then
            local signatures = {}
            for _, signature in ipairs(route.ac_phase_signatures) do
                if type(signature) == "table" then
                    signatures[string.format("%s:%s:%s:%s", tostring(signature.param00),
                        tostring(signature.param01), tostring(signature.param02),
                        tostring(signature.param03))] = true
                end
            end
            phase_signature_ok = signatures["0:8:0:1"] == true
                and signatures["0:32:0:2"] == true
                and signatures["0:8192:0:3"] == true
                and signatures["1:8192:0:3"] == true
        end
        if type(type20_phase_declarations) == "table" and phase_signature_ok then
            for _, relation in ipairs(type20_phase_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and relation.reason == TYPE20_PHASE_REASON
                    and type(relation.signatures) == "table" and #relation.signatures == 4 then
                    declared_type20_phase = true
                    break
                end
            end
        end
        local type20_phase_ok = source == "ac_type20_action_phase"
            and entry.ownership == "type20_action_phase" and declared_type20_phase
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_PHASE_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_inherited_action_phase"
            and route_character == map_character and phase_signature_ok
        local state_relation_list = nil
        local state_reason = nil
        local state_confidence = nil
        local state_ownership = nil
        local state_expected_type = nil
        if source == "ac_type20_state_direction" then
            state_relation_list = type(modern_map._meta) == "table"
                and modern_map._meta.ac_state_direction_relations or nil
            state_reason = AC_STATE_DIRECTION_REASON
            state_confidence = "verified_ac_state_direction"
            state_ownership = "ac_state_direction"
            state_expected_type = 20
        elseif source == "ac_type1_state_neutral" then
            state_relation_list = type(modern_map._meta) == "table"
                and modern_map._meta.ac_state_neutral_relations or nil
            state_reason = AC_STATE_NEUTRAL_REASON
            state_confidence = "verified_ac_state_neutral"
            state_ownership = "ac_state_neutral"
            state_expected_type = 1
        elseif source == "ac_type13_neutral_continuation" then
            state_relation_list = type(modern_map._meta) == "table"
                and modern_map._meta.ac_type13_neutral_relations or nil
            state_reason = AC_TYPE13_NEUTRAL_REASON
            state_confidence = "verified_ac_type13_neutral"
            state_ownership = "ac_type13_neutral"
            state_expected_type = 13
        end
        local declared_state_choice = false
        if type(state_relation_list) == "table" then
            for _, relation in ipairs(state_relation_list) do
                if type(relation) == "table" and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == state_expected_type
                    and relation.reason == state_reason
                    and type(relation.source_action_ids) == "table"
                    and #relation.source_action_ids > 0 then
                    for _, source_id in ipairs(relation.source_action_ids) do
                        if tonumber(source_id) == inherited_source then
                            declared_state_choice = true
                            break
                        end
                    end
                end
                if declared_state_choice then break end
            end
        end
        local state_choice_ok = state_relation_list ~= nil and declared_state_choice
            and entry.ownership == state_ownership
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == state_reason
            and tonumber(route.ac_relation_type) == state_expected_type
            and inherited_source ~= nil and step_id ~= nil
            and type(ac_path) == "table" and #ac_path == 2
            and tonumber(ac_path[1]) == inherited_source and tonumber(ac_path[2]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.bcm_owner_action_id == nil
            and route.confidence == state_confidence and route_character == map_character
            and type(route.state_choice_source_action_ids) == "table"
            and #route.state_choice_source_action_ids > 0
            and ((source == "ac_type20_state_direction"
                    and tostring(route.display or ""):match("^[2468]$") ~= nil
                    and tonumber(route.state_choice_direction_mask) ~= nil)
                or ((source == "ac_type1_state_neutral"
                        or source == "ac_type13_neutral_continuation")
                    and route.display == "N"))
        local declared_target_combo = false
        local target_combo_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.target_combo_repeat_relations or nil
        if type(target_combo_declarations) == "table" then
            for _, relation in ipairs(target_combo_declarations) do
                if type(relation) == "table" and tonumber(relation.parent_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.trigger_index) == tonumber(route.trigger_index)
                    and tostring(relation.button or "") == tostring(route.visible_button or "")
                    and relation.evidence == "bcm-turn-around"
                    and relation.reason == TARGET_COMBO_REPEAT_REASON then
                    declared_target_combo = true
                    break
                end
            end
        end
        local target_combo_ok = source == "bcm_target_combo_repeat"
            and entry.ownership == "target_combo_repeat" and declared_target_combo
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TARGET_COMBO_REPEAT_REASON
            and route.ac_relation_type == nil and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path == 2
            and tonumber(ac_path[1]) == inherited_source and tonumber(ac_path[2]) == step_id
            and tonumber(route.owner_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_bcm_target_combo_repeat"
            and route_character == map_character
            and tostring(route.display or "") == "> " .. tostring(route.visible_button)
        local declared_structural_twin = false
        local structural_twin_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.structural_twin_relations or nil
        if type(structural_twin_declarations) == "table" then
            for _, relation in ipairs(structural_twin_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.source_trigger_index) == tonumber(route.trigger_index)
                    and relation.ignored_condition_delta == "use_super:true->false"
                    and relation.reason == STRUCTURAL_TWIN_REASON then
                    declared_structural_twin = true
                    break
                end
            end
        end
        local structural_twin_ok = source == "ac_bcm_structural_twin"
            and entry.ownership == "structural_twin" and declared_structural_twin
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == STRUCTURAL_TWIN_REASON
            and route.ac_relation_type == nil and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_unique_structural_twin"
            and route_character == map_character
        local declared_assist_combo = false
        local assist_combo_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.assist_combo_relations or nil
        if type(assist_combo_declarations) == "table" then
            for _, relation in ipairs(assist_combo_declarations) do
                if type(relation) == "table" and tonumber(relation.action_id) == step_id
                    and tostring(relation.display or "") == tostring(route.display or "")
                    and tostring(relation.assist_strength or "") == tostring(route.assist_strength or "")
                    and tostring(relation.input_stage or "") == tostring(route.assist_input_stage or "")
                    and relation.reason == ASSIST_COMBO_REASON then
                    declared_assist_combo = true
                    break
                end
            end
        end
        local assist_occurrences_ok = type(route.assist_recipe_occurrences) == "table"
            and #route.assist_recipe_occurrences > 0
        local assist_trigger_declared = false
        if assist_occurrences_ok then
            for _, occurrence in ipairs(route.assist_recipe_occurrences) do
                if type(occurrence) ~= "table" or tonumber(occurrence.array_index) == nil
                    or tonumber(occurrence.trigger_id) == nil
                    or tonumber(occurrence.trigger_id) < 0 then
                    assist_occurrences_ok = false
                    break
                end
                if tonumber(occurrence.trigger_id) == tonumber(route.trigger_index) then
                    assist_trigger_declared = true
                end
            end
        end
        local assist_expected_display = route.assist_input_stage == "first"
            and ("AUTO + " .. tostring(route.assist_strength or ""))
            or ("> " .. tostring(route.assist_strength or ""))
        local assist_combo_ok = source == "bcm_assist_combo_recipe"
            and declared_assist_combo and assist_occurrences_ok and assist_trigger_declared
            and route.direct_evidence == true and route.inheritance_evidence == false
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.assist_combo_evidence == true
            and route.assist_combo_reason == ASSIST_COMBO_REASON
            and route.inheritance_reason == nil and route.rebind_reason == nil
            and route.runtime_common_reason == nil and route.official_semantic_reason == nil
            and route.community_semantic_reason == nil
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == step_id
            and route.ac_relation_type == nil and type(ac_path) == "table" and #ac_path == 0
            and route.inherited_from_action_id == nil
            and route.confidence == "direct_assist_combo_recipe"
            and route_character == map_character and route.profile == "assist_combo"
            and tonumber(route.command_no) == -1 and tonumber(route.command_index) == -1
            and type(route.raw_direction_inputs) == "table" and #route.raw_direction_inputs == 0
            and tonumber(route.raw_button_mask) == 0 and tonumber(route.raw_button_condition) == 0
            and tonumber(route.raw_dc_exc_flags) == 0 and tonumber(route.raw_ng_key_flags) == 0
            and (route.assist_strength == "弱" or route.assist_strength == "中"
                or route.assist_strength == "强")
            and (route.assist_input_stage == "first" or route.assist_input_stage == "repeat")
            and tostring(route.display or "") == assist_expected_display
        local display = type(route) == "table" and route.display or nil
        if charge_context_ok and super_shortcut_ok
            and (direct_ok or inherited_ok or rebind_ok or runtime_common_ok or official_semantic_ok
                or verified_alias_ok or type20_ok or type20_hold_ok or type20_phase_ok
                or state_choice_ok
                or target_combo_ok or structural_twin_ok
                or assist_combo_ok)
            and type(display) == "string" and display ~= "" and not seen[display] then
            seen[display] = true
            table.insert(displays, display)
        end
    end
    if #displays == 0 then return nil, "route_unverified" end
    return table.concat(displays, "/"), "strict_route"
end

local function resolve_classic_common_semantic(entry, classic, motion, status)
    if status == "suppress_transition" or type(entry) ~= "table" then return classic end
    if trim_string(classic):upper() ~= "NORMAL" then return classic end

    local has_drive_parry_route = false
    for _, route in ipairs(type(entry.routes) == "table" and entry.routes or {}) do
        if type(route) == "table" and route.source == "bcm_common_semantic"
            and trim_string(route.display):upper() == "DP" then
            has_drive_parry_route = true
            break
        end
    end
    if not has_drive_parry_route then return classic end

    for variant in tostring(motion or ""):gmatch("[^/|]+") do
        if trim_string(variant):upper() == "DP" then return "PARRY" end
    end
    return classic
end

-- 指令映射包含大量生成期审计与路由证据。加载时先用完整数据完成严格校验和
-- 路由解析，随后只保留运行时实际需要的 action id、显示文本与解析状态，避免
-- 多个约 490KB 的角色表长期驻留并触发周期性 GC 卡顿。
build_slim_command_display_map = function(loaded)
    local slim = { _slim = true }
    for action_id, entry in pairs(loaded) do
        if type(entry) == "table" and tostring(action_id):match("^%d+$") then
            local motion, status = get_modern_display_motion(loaded, { id = action_id })
            do
                local function read_classic(command)
                    if type(command) ~= "table" or type(command.display) ~= "string"
                        or trim_string(command.display) == "" or type(command.inputs) ~= "table"
                        or #command.inputs == 0 then return nil end
                    for _, input in ipairs(command.inputs) do
                        if type(input) ~= "string" or trim_string(input) == "" then return nil end
                    end
                    return trim_string(command.display)
                end
                local classic = read_classic(entry.classic_command)
                classic = resolve_classic_common_semantic(entry, classic, motion, status)
                if status == "suppress_transition" then
                    slim[tostring(action_id)] = { classic = classic, motion = nil, status = status }
                else
                    local relation = type(entry.relation) == "table" and entry.relation or nil
                    local strip_followup = relation and relation.type == "followup"
                    local verified_inputs = {}
                    for variant in tostring(motion or ""):gmatch("[^/|]+") do
                        local value = trim_string(variant)
                        if strip_followup then value = value:gsub("^>%s*", "") end
                        if value ~= "" then verified_inputs[value] = true end
                    end
                    local function read_command(command)
                        if type(command) ~= "table" or type(command.display) ~= "string"
                            or trim_string(command.display) == "" or type(command.inputs) ~= "table"
                            or #command.inputs == 0 then return nil end
                        for _, input in ipairs(command.inputs) do
                            if type(input) ~= "string" or not verified_inputs[trim_string(input)] then
                                return nil
                            end
                        end
                        return trim_string(command.display)
                    end
                    local simple = read_command(entry.simple_command)
                    local manual = read_command(entry.motion_command)
                    local relation_ok = relation == nil or (relation.type == "followup"
                        and tonumber(relation.source_action_id) ~= nil
                        and relation.evidence == "capcom_official_followup_context_matches_source_move")
                    if (simple or manual or classic) and relation_ok then
                        slim[tostring(action_id)] = {
                            classic = classic,
                            simple = simple,
                            motion = manual,
                            relation = relation and {
                                type = relation.type,
                                source_action_id = tonumber(relation.source_action_id)
                            } or nil,
                            status = status
                        }
                    else
                        slim[tostring(action_id)] = { motion = nil, status = "invalid_split_commands" }
                    end
                end
            end
        end
    end
    do
        local function resolve(action_id, slot, stack)
            local key = tostring(action_id or "")
            local item = slim[key]
            if type(item) ~= "table" then return nil end
            local local_motion = item[slot]
                or (slot == "simple" and item.motion or item.simple)
            if type(local_motion) ~= "string" or local_motion == "" then return nil end
            if type(item.relation) ~= "table" then return local_motion end
            if stack[key] then return nil end
            stack[key] = true
            local parent = resolve(item.relation.source_action_id, slot, stack)
            stack[key] = nil
            if not parent then return nil end
            return parent .. " > " .. local_motion
        end
        for action_id, item in pairs(slim) do
            if tostring(action_id):match("^%d+$") and type(item) == "table" then
                local simple = resolve(action_id, "simple", {})
                local manual = resolve(action_id, "motion", {})
                if simple or manual then
                    item.commands = {
                        simple = simple or manual,
                        motion = manual or simple
                    }
                    item.commands.all = item.commands.simple == item.commands.motion
                        and item.commands.simple
                        or (item.commands.simple .. "/" .. item.commands.motion)
                elseif not item.classic then
                    item.status = "invalid_followup_relation"
                end
                item.simple = nil
                item.motion = nil
                item.relation = nil
            end
        end
    end
    return slim
end

local function get_classic_display_motion(command_map, step)
    if type(command_map) ~= "table" or type(step) ~= "table" or command_map._slim ~= true then
        return nil, "map_unavailable"
    end
    local resolved = command_map[tostring(step.id or "")]
    if type(resolved) ~= "table" then return nil, "action_id_missing" end
    if resolved.status == "suppress_transition" then
        local player_transition = get_player_visible_transition_motion(step)
        if player_transition then return player_transition, "player_input_transition" end
        return nil, resolved.status
    end
    local recorded_motion = trim_string(step.motion)
    local contextual_motion = recorded_motion:match("^>") ~= nil
        or recorded_motion:upper():match("^J%.") ~= nil
        or recorded_motion:upper():find("[AIR]", 1, true) ~= nil
        or recorded_motion:find("空中", 1, true) ~= nil
        or recorded_motion:match("%b()") ~= nil
    -- The generated table describes the action's standalone command. A saved
    -- trial can carry stricter contextual input (cancel shortcut, aerial state,
    -- timing/hold annotation). Replacing that text changes the trial semantics,
    -- so preserve it and use the generated command only for plain actions.
    if recorded_motion ~= "" and contextual_motion then return recorded_motion, "recorded_context" end
    if type(resolved.classic) == "string" and resolved.classic ~= "" then
        return resolved.classic, resolved.status or "loaded"
    end
    return nil, resolved.status or "command_unavailable"
end

local function get_command_display(command_map, action_id, mode)
    if type(command_map) ~= "table" or command_map._slim ~= true then
        return nil, "map_unavailable"
    end
    local resolved = command_map[tostring(action_id or "")]
    if type(resolved) ~= "table" then return nil, "action_id_missing" end
    if resolved.status == "suppress_transition" then return nil, resolved.status end
    if mode == "classic" then return resolved.classic, resolved.status or "loaded" end
    local commands = resolved.commands
    if type(commands) ~= "table" then return nil, resolved.status or "command_unavailable" end
    if mode ~= "motion" and mode ~= "all" then mode = "simple" end
    return commands[mode] or commands.simple or commands.motion or commands.all,
        resolved.status or "loaded"
end

-- =========================================================
-- Public API (ours)
-- =========================================================
M.load_for_character         = load_command_display_map
M.get_command_display        = get_command_display
M.get_classic_display_motion = get_classic_display_motion

return M
