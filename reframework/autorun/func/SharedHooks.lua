-- 0_SharedHooks.lua
-- Consolidated hooks for performance: one hook per method, dispatch via _G
-- Named with 0_ prefix to load before other scripts

local sdk = sdk
local RuntimeSafety = require("func/RuntimeSafety")

-- =========================================================
-- SHARED ERROR REGISTRY: central logging for swallowed errors
-- Scripts use _G.safe_call(context, fn, ...) instead of bare
-- pcall when a failure should be visible to the user.
-- Errors are listed in the REFramework menu (Training Suite > Script Errors).
-- =========================================================
if not _G._mod_errors then
    _G._mod_errors = { list = {}, count = 0, config_failures = {} }
end

_G.safe_call = function(context, fn, ...)
    local ok, r1, r2, r3 = pcall(fn, ...)
    if not ok then
        local e = _G._mod_errors
        e.count = e.count + 1
        e.list[#e.list + 1] = { ctx = context, err = tostring(r1), t = os.clock() }
        if #e.list > 50 then table.remove(e.list, 1) end
        pcall(log.warn, "[SF6Mods] " .. context .. ": " .. tostring(r1))
    end
    return ok, r1, r2, r3
end

-- json.load_file returns nil for both "file missing" (normal on first run)
-- and "malformed JSON" (user broke it by hand-editing). This distinguishes
-- the two and records corrupt configs so the UI can warn instead of
-- silently resetting to defaults. Only for one-shot config loads — do NOT
-- use on per-frame bridge polling (the miss probe opens the file).
_G.safe_load_json = function(path)
    local data = json.load_file(path)
    if data then return data end
    local ok, f = pcall(io.open, path, "r")
    if ok and f then
        f:close()
        local e = _G._mod_errors
        if not e.config_failures[path] then
            e.config_failures[path] = true
            e.count = e.count + 1
            e.list[#e.list + 1] = { ctx = "corrupt config: " .. path, err = "invalid JSON (defaults applied)", t = os.clock() }
            pcall(log.warn, "[SF6Mods] corrupt config: " .. path)
        end
    end
    return nil
end

local _td_gBattle = sdk.find_type_definition("gBattle")
local _td_mediator = sdk.find_type_definition("app.FBattleMediator")
local _f_playerType = _td_mediator and _td_mediator:get_field("PlayerType")
if not _td_mediator or not _f_playerType then
    _G._mod_errors.count = _G._mod_errors.count + 1
    _G._mod_errors.list[#_G._mod_errors.list + 1] = { ctx = "SharedHooks init", err = "app.FBattleMediator not found — character detection DEAD", t = os.clock() }
end

local function _sh_get_enum_value(p)
    return p:get_type_definition():get_field("value__"):get_data(p)
end

local function _sh_get_player_singleton()
    if not _td_gBattle then return nil end
    return _td_gBattle:get_field("Player"):get_data(nil)
end

local function _sh_clear_array(t)
    if not t then return end
    for k in pairs(t) do
        t[k] = nil
    end
end

local function _sh_reset_player_info()
    _G._shared_player_info = _G._shared_player_info or {}
    for k in pairs(_G._shared_player_info) do
        if k ~= 0 and k ~= 1 then
            _G._shared_player_info[k] = nil
        end
    end
    for i = 0, 1 do
        local info = _G._shared_player_info[i]
        if type(info) ~= "table" then
            info = {}
            _G._shared_player_info[i] = info
        else
            _sh_clear_array(info)
        end
        info.id = -1
        info.key = "ESF_000"
        info.name = "Unknown"
    end
end

-- =========================================================
-- GENERATION COUNTER: prevents stale hooks after Reset Scripts
-- =========================================================
local _shared_hooks_generation = (_G._shared_hooks_generation or 0) + 1
_G._shared_hooks_generation = _shared_hooks_generation

local function _sh_is_current_generation()
    return _G._shared_hooks_generation == _shared_hooks_generation
end

-- =========================================================
-- SHARED HOOK: UpdateGameInfo (was in CT, DL, SB separately)
-- Publishes player character IDs to _G._shared_player_info
-- =========================================================
_sh_reset_player_info()

if _td_mediator then
    local m = _td_mediator:get_method("UpdateGameInfo")
    if m then
        sdk.hook(m, function(args)
            if not _sh_is_current_generation() then return end
            local ok, mgr = pcall(sdk.to_managed_object, args[2])
            if not ok or not mgr then return end
            local ok2, pt = pcall(_f_playerType.get_data, _f_playerType, mgr)
            if not ok2 or not pt then return end
            local ok3, plen = pcall(pt.call, pt, "get_Length")
            if not ok3 or not plen or plen < 2 then return end
            for i = 0, 1 do
                local ok4, p = pcall(pt.call, pt, "GetValue", i)
                if ok4 and p then
                    local ok5, pid = pcall(_sh_get_enum_value, p)
                    if ok5 and pid then
                        _G._shared_player_info[i].id = pid
                        _G._shared_player_info[i].key = string.format("ESF_%03d", pid)
                        local ok6, ns = pcall(p.call, p, "ToString")
                        _G._shared_player_info[i].name = (ok6 and ns) or "Unknown"
                    end
                end
            end
        end, function(retval) return retval end)
    end
end

-- =========================================================
-- SHARED HOOK: pl_input_sub (was in CT and DV separately)
-- Dispatches to registered callbacks via _G._shared_input_pre/post
-- =========================================================
_G._shared_input_pre = _G._shared_input_pre or {}
_G._shared_input_post = _G._shared_input_post or {}
_sh_clear_array(_G._shared_input_pre)
_sh_clear_array(_G._shared_input_post)

local p_id_stack = {}
local p_id_stack_top = 0
local _cached_addr = { [0] = nil, [1] = nil }
local _addr_refresh = 0
local _dv_p2_input_owned = false
local _dv_last_release_frame = nil

-- =========================================================
-- P2 INPUT MASK: centralized write with RuntimeSafety gate
-- =========================================================
local function get_p2_player()
    local ok, sP = pcall(_sh_get_player_singleton)
    if not ok or not sP or not sP.mcPlayer then return nil end
    return sP.mcPlayer[1]
end

local function _sh_read_rl_dir(p2)
    return p2:get_field("rl_dir")
end

local function _sh_write_p2_fields(p2, mask)
    p2:set_field("pl_input_new", mask)
    p2:set_field("pl_sw_new", mask)
end

local function write_p2_input_mask(mask)
    if not RuntimeSafety.can_inject_input() then return false end
    local p2 = get_p2_player()
    if not p2 then return false end
    local final_mask = mask or 0
    local ok_rl, facing_reversed = pcall(_sh_read_rl_dir, p2)
    if final_mask ~= 0 and ok_rl and facing_reversed then
        local has_right = (final_mask & 4) ~= 0
        local has_left  = (final_mask & 8) ~= 0
        final_mask = final_mask & ~12
        if has_right then final_mask = final_mask | 8 end
        if has_left  then final_mask = final_mask | 4 end
    end
    local ok = pcall(_sh_write_p2_fields, p2, final_mask)
    return ok == true
end

local function decrement_dv_release_frames(release_frames)
    if release_frames <= 0 then return end
    local rs = _G.SF6CC_RuntimeSafety
    local frame = rs and rs.frame
    if frame == nil then
        _G._dv_aa_release_frames = math.max(0, release_frames - 1)
        return
    end
    if frame == _dv_last_release_frame then return end
    _dv_last_release_frame = frame
    _G._dv_aa_release_frames = math.max(0, release_frames - 1)
end

local function finalize_distance_viewer_p2_input(p_id)
    if p_id ~= 1 then return end
    local dv_heartbeat = _G._dv_aa_heartbeat or 0
    local heartbeat_stale = dv_heartbeat > 0 and (os.clock() - dv_heartbeat) > 0.5
    local release_frames = _G._dv_aa_release_frames or 0
    local desired_mask = _G._dv_aa_p2_mask or 0
    local can_inject = RuntimeSafety.can_inject_input()
    local can_apply = can_inject
        and _G.SF6_DistanceViewer_Enabled == true
        and _G.SF6_DistanceViewer_AutoActivate_Enabled == true
        and _G._dv_aa_enabled == true
        and not heartbeat_stale
        and release_frames <= 0
        and desired_mask > 0

    if can_apply then
        if write_p2_input_mask(desired_mask) then
            _dv_p2_input_owned = true
        end
        return
    end

    if not can_inject then
        _G._dv_aa_p2_mask = 0
        _G._dv_aa_enabled = false
        _G._dv_aa_release_frames = 0
        return
    end

    local should_release = release_frames > 0
        or (_dv_p2_input_owned and _G.SF6_DistanceViewer_Enabled ~= true)
        or (_dv_p2_input_owned and _G.SF6_DistanceViewer_AutoActivate_Enabled ~= true)
        or (_dv_p2_input_owned and _G._dv_aa_enabled ~= true)
        or (_dv_p2_input_owned and heartbeat_stale)
    if not should_release then return end

    if _dv_p2_input_owned then
        write_p2_input_mask(0)
    end
    _G._dv_aa_p2_mask = 0
    _G._dv_aa_enabled = false
    if release_frames > 0 then
        decrement_dv_release_frames(release_frames)
        if release_frames <= 1 then
            _dv_p2_input_owned = false
        end
    else
        _dv_p2_input_owned = false
    end
end

local function distance_viewer_input_finalizer(p_id, retval)
    finalize_distance_viewer_p2_input(p_id)
end

local function ensure_distance_viewer_finalizer_tail()
    if not _G._shared_input_post then return end
    for i = #_G._shared_input_post, 1, -1 do
        if _G._shared_input_post[i] == distance_viewer_input_finalizer then
            table.remove(_G._shared_input_post, i)
        end
    end
end

_G._dv_ensure_shared_input_finalizer_tail = ensure_distance_viewer_finalizer_tail
ensure_distance_viewer_finalizer_tail()

local function reset_distance_viewer_p2_input()
    if _dv_p2_input_owned and RuntimeSafety.can_inject_input() then
        write_p2_input_mask(0)
    end
    _dv_p2_input_owned = false
    _G.SF6_DistanceViewer_AutoActivate_Enabled = false
    _G._dv_aa_enabled = false
    _G._dv_aa_p2_mask = 0
    _G._dv_aa_release_frames = 0
    _G._dv_aa_heartbeat = 0
    _G._dv_aa_frame = 0
    _G._dv_aa_last_had_input = false
end

-- =========================================================
-- pl_input_sub HOOK
-- =========================================================
local cplayer_type = sdk.find_type_definition("nBattle.cPlayer")
if not cplayer_type or not cplayer_type:get_method("pl_input_sub") then
    _G._mod_errors.count = _G._mod_errors.count + 1
    _G._mod_errors.list[#_G._mod_errors.list + 1] = { ctx = "SharedHooks init", err = "pl_input_sub hook not installed — input injection DEAD (AA, sequencer, trials)", t = os.clock() }
end
if cplayer_type then
    local method = cplayer_type:get_method("pl_input_sub")
    if method then
        sdk.hook(method,
            function(args)
                if not _sh_is_current_generation() then return end
                local hook_addr = sdk.to_int64(args[2])
                local p_id = -1

                _addr_refresh = _addr_refresh + 1
                if _addr_refresh >= 120 or not _cached_addr[0] then
                    _addr_refresh = 0
                    local ok, sP = pcall(_sh_get_player_singleton)
                    if ok and sP and sP.mcPlayer then
                        for i = 0, 1 do
                            if sP.mcPlayer[i] then
                                local aok, addr = pcall(sP.mcPlayer[i].get_address, sP.mcPlayer[i])
                                _cached_addr[i] = aok and addr or nil
                            end
                        end
                    end
                end

                if hook_addr == _cached_addr[0] then p_id = 0
                elseif hook_addr == _cached_addr[1] then p_id = 1 end

                p_id_stack_top = p_id_stack_top + 1
                p_id_stack[p_id_stack_top] = p_id
                if RuntimeSafety.can_inject_input() then
                    for _, cb in ipairs(_G._shared_input_pre) do
                        pcall(cb, p_id, args)
                    end
                end
            end,
            function(retval)
                if not _sh_is_current_generation() then return retval end
                local p_id = p_id_stack[p_id_stack_top] or -1
                p_id_stack[p_id_stack_top] = nil
                if p_id_stack_top > 0 then p_id_stack_top = p_id_stack_top - 1 end
                if RuntimeSafety.can_inject_input() then
                    for _, cb in ipairs(_G._shared_input_post) do
                        pcall(cb, p_id, retval)
                    end
                end
                finalize_distance_viewer_p2_input(p_id)
                return retval
            end
        )
    end
end

-- =========================================================
-- CENTRALIZED GC: one step per frame, smooths out GC pauses
-- =========================================================
re.on_application_entry("UpdateBehavior", function()
    if not _sh_is_current_generation() then return end
    finalize_distance_viewer_p2_input(1)
    collectgarbage("step", 1)
end)

-- =========================================================
-- SCRIPT RESET CLEANUP
-- =========================================================
local function reset_shared_hook_runtime()
    _sh_clear_array(_G._shared_input_pre)
    _sh_clear_array(_G._shared_input_post)
    _sh_clear_array(p_id_stack)
    p_id_stack_top = 0
    _cached_addr[0] = nil
    _cached_addr[1] = nil
    _addr_refresh = 0
    _sh_reset_player_info()
    _dv_p2_input_owned = false
    _dv_last_release_frame = nil
    _G._dv_ensure_shared_input_finalizer_tail = nil
    _G._dv_shared_input_post = nil
end

if re.on_script_reset then
    re.on_script_reset(function()
        reset_distance_viewer_p2_input()
        _G._shared_hooks_generation = (_G._shared_hooks_generation or _shared_hooks_generation) + 1
        reset_shared_hook_runtime()
    end)
end
