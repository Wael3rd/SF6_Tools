-- GameState.lua
-- Per-frame snapshot of commonly read game state, published to _G.GameState.
-- One reflection pass per frame instead of every script redoing the
-- gBattle->Player->getPlayer chain and PauseManager lookup (measured: ~45
-- player-chain accesses and ~25 pause checks per frame across the suite).
--
-- Usage: local GS = require("func/GameState")
--   GS.valid          -- snapshot usable this frame (players resolved)
--   GS.p1 / GS.p2     -- nBattle.cPlayer refs (refreshed every frame, may be nil)
--   GS.p1_act_st / GS.p2_act_st -- action state numbers (0 when unknown)
--   GS.pause_bit      -- raw _CurrentPauseTypeBit (64 when unknown)
--   GS.in_pause_menu  -- true when game is in a pause/menu state
--   GS.frame          -- snapshot counter (increments once per frame)
--
-- IMPORTANT: the updater registers re.on_frame at require time. Require this
-- module at file scope, BEFORE registering your own re.on_frame, so the
-- snapshot is refreshed before your callback runs (REFramework runs on_frame
-- callbacks in registration order).

local sdk = sdk
local re = re
require("func/SharedHooks") -- error registry

local GS = _G.GameState
if GS then return GS end

GS = {
    frame = 0,
    valid = false,
    p1 = nil, p2 = nil,
    p1_act_st = 0, p2_act_st = 0,
    pause_bit = 64,
    in_pause_menu = false,
    sP = nil,
}
_G.GameState = GS

local _td_gBattle = sdk.find_type_definition("gBattle")
local _f_player = _td_gBattle and _td_gBattle:get_field("Player")
if not _f_player then
    _G._mod_errors.count = _G._mod_errors.count + 1
    _G._mod_errors.list[#_G._mod_errors.list + 1] = { ctx = "GameState init", err = "gBattle.Player not found — snapshot DEAD", t = os.clock() }
end

local _f_act_st = nil -- field descriptor, cPlayer type is stable across characters

local function _gs_update_players()
    GS.sP = nil
    GS.p1, GS.p2 = nil, nil
    GS.p1_act_st, GS.p2_act_st = 0, 0
    if not _f_player then return end
    local sP = _f_player:get_data(nil)
    if not sP or not sP.mcPlayer then return end
    GS.sP = sP
    local p1 = sP.mcPlayer[0]
    local p2 = sP.mcPlayer[1]
    GS.p1, GS.p2 = p1, p2
    if p1 then
        if not _f_act_st then _f_act_st = p1:get_type_definition():get_field("act_st") end
        if _f_act_st then GS.p1_act_st = tonumber(tostring(_f_act_st:get_data(p1))) or 0 end
    end
    if p2 and _f_act_st then
        GS.p2_act_st = tonumber(tostring(_f_act_st:get_data(p2))) or 0
    end
end

local function _gs_update_pause()
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pb = pm:get_field("_CurrentPauseTypeBit")
        GS.pause_bit = pb or 64
        GS.in_pause_menu = (pb ~= nil) and (pb ~= 64 and pb ~= 2112)
    else
        GS.pause_bit = 64
        GS.in_pause_menu = false
    end
end

re.on_frame(function()
    GS.frame = GS.frame + 1
    local ok = pcall(_gs_update_players)
    if not ok then
        GS.sP = nil; GS.p1 = nil; GS.p2 = nil
        GS.p1_act_st = 0; GS.p2_act_st = 0
    end
    pcall(_gs_update_pause)
    GS.valid = GS.p1 ~= nil
end)

return GS
