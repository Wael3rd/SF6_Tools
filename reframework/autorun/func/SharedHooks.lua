-- 0_SharedHooks.lua
-- Consolidated hooks for performance: one hook per method, dispatch via _G
-- Named with 0_ prefix to load before other scripts

local sdk = sdk

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

-- =========================================================
-- SHARED HOOK: UpdateGameInfo (was in CT, DL, SB separately)
-- Publishes player character IDs to _G._shared_player_info
-- =========================================================
_G._shared_player_info = { [0] = { id = -1, key = "ESF_000", name = "Unknown" }, [1] = { id = -1, key = "ESF_000", name = "Unknown" } }

if _td_mediator then
    local m = _td_mediator:get_method("UpdateGameInfo")
    if m then
        sdk.hook(m, function(args)
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
_G._shared_input_pre = {}
_G._shared_input_post = {}

local p_id_stack = {}
local _cached_addr = { [0] = nil, [1] = nil }
local _addr_refresh = 0

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

                table.insert(p_id_stack, p_id)
                for _, cb in ipairs(_G._shared_input_pre) do
                    pcall(cb, p_id, args)
                end
            end,
            function(retval)
                local p_id = table.remove(p_id_stack) or -1
                for _, cb in ipairs(_G._shared_input_post) do
                    pcall(cb, p_id, retval)
                end
                return retval
            end
        )
    end
end

-- =========================================================
-- CENTRALIZED GC: one step per frame, smooths out GC pauses
-- =========================================================
re.on_application_entry("UpdateBehavior", function()
    collectgarbage("step", 1)
end)
