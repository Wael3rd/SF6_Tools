-- ============================================================
-- NativeTopBar — the Script Manager top bar drawn with the game's OWN GUI elements (via.gui Rect /
-- Scale9Grid / Text) instead of ImGui. Same recipe as NativePopup (memory project_native_windows):
--   * pieces = hidden, never-shown-in-Fighting-Ground leaves of resident agents, re-parented under
--     BattleHud_Timer/c_main (font slot 8 + atlases available there, y 3..47 is free of other GUIs)
--   * addChild return value checked; remove()+addChild only for Rects (it strips Text/Scale9Grid)
--   * every GUI call from LateUpdateBehavior, write-on-change, nothing from re.on_script_reset
-- The ImGui bar keeps being drawn by Training_ScriptManager with alpha 0: same click zones, so the
-- mouse still works; this module only shows the visuals and the active mode.
--
--   local NativeTopBar = require("func/NativeTopBar")
--   NativeTopBar.set_active(mode_id)   -- 0 DISABLED, 5 EXECUTION, 2 HIT CONFIRM, 1 REACTION, 3 POST GUARD, 4 COMBO
--   NativeTopBar.enable(bool)          -- false = everything hidden (pieces stay parked under the host)
-- ============================================================
local M = {}

local HOST_AGENT = "BattleHud_Timer"
local CY = 25                                   -- ImGui bar: frame y 3..47
local FRAME_W, FRAME_H = 1420, 44               -- x 250..1670
local BTN_W, BTN_H, BTN_X0, BTN_PITCH = 192, 30, 360, 200   -- 7 buttons, 14 px margins, 8 px gaps
local COL_BODY, COL_LINE = 0xFF5A0A3C, 0x80FFFFFF          -- pause-menu purple, searching-pill outline
local COL_SWITCH, COL_ACTIVE, COL_INACTIVE = 0xFFFF6600, 0xFF009D01, 0xFF666666   -- = TSM top_colors (ABGR)

local BUTTONS = {   -- id nil = SWITCH
    { id = nil, label = "SWITCH" }, { id = 0, label = "DISABLED" }, { id = 5, label = "EXECUTION" }, { id = 2, label = "HIT CONFIRM" },
    { id = 1, label = "REACTION DRILLS" }, { id = 3, label = "POST GUARD" }, { id = 4, label = "COMBO TRIALS" },
}
-- spares: { agent, path (leaf name or list of names) }
local BODY = { "Resident_Cmn_CertifiedMatch", { "c_SelectItem_3", "e_rect_bar" } }
local LINE = { "Resident_Cmn_MatchingStandby", { "c_bg_BH", "e_scale9grid_line" }, source = { "Resident_Cmn_OnlineStandby", "e_s9g_line" } }
local RECTS = { { "Resident_Cmn_MatchingStandby", "e_bg_cfn" }, { "Resident_Cmn_MatchingStandby", "e_rect_mask" },
                { "Resident_Cmn_MatchingSelect", { "c_bg_BH", "e_bg" } }, { "Resident_Cmn_MatchingSelect", { "c_bg_FG", "e_rect_base" } },
                { "Resident_Cmn_MatchingStandby", { "c_bg_BH", "e_bg" } }, { "Resident_Cmn_MatchingSelect", { "c_bg_BH", "e_bg_cfn" } },
                { "Resident_Cmn_MatchingSelect", { "c_bg_BH", "c_texture_bg", "e_rect_mask" } } }
local TEXTS = { { "BattleHubDailyTournamentCountdown", "e_text_round" }, { "BattleHubAvatarBattleMatchWaiting", "e_text_ready" },
                { "Resident_Cmn_MatchingSelect", "e_txt_wait" },
                { "BattleHud_AccountInfo", { "p_BattleHudAccountInfo_0", "e_txt_cetrified" } }, { "BattleHud_AccountInfo", { "p_BattleHudAccountInfo_0", "e_txt_CM_count" } },
                { "BattleHud_AccountInfo", { "p_BattleHudAccountInfo_0", "e_txt_CM_max" } }, { "BattleHud_AccountInfo", { "p_BattleHudAccountInfo_0", "p_SmallRankIcon_0", "e_txt_num" } } }
local TEXT_SOURCE = { "Resident_Cmn_MatchingStandby", "e_txt_0" }   -- style copied onto every text (slot 8, no outline)

-- ---------- state ----------
local enabled, active, dirty = false, 0, true
local host, P = nil, nil          -- P = { body=, line=, rects={}, texts={} }
local applied = {}                -- write-on-change
local tick, next_resolve = 0, 0

function M.enable(b) b = b and true or false; if enabled ~= b then enabled = b; dirty = true end end
function M.set_active(id) if active ~= id then active = id; dirty = true end end
function M.available() return P ~= nil end

-- ---------- helpers (main thread only) ----------
local function safe(fn) local ok, v = pcall(fn); return ok and v or nil end
local function agent_main(name)
    local mgr = sdk.get_managed_singleton("app.UIAgentManager")
    local list = mgr and mgr:get_field("_Entries"); if not list then return nil end
    for i = 0, list:call("get_Count") - 1 do
        local agent = list:call("get_Item", i).Agent
        local go = agent and agent:call("get_GameObject")
        if go and tostring(go:call("get_Name")) == name then return agent:call("get_ControlMain") end
    end
end
-- Every GUI we borrow from: if one of them is rebuilt (Restore Default Settings, character change...), the leaves we
-- moved out of it are freed by the engine -> writing to them is an AV (crash 30/08). We fingerprint the ControlMain
-- addresses and drop everything (without touching the old pieces) as soon as one changes.
local POOL_AGENTS = { HOST_AGENT, "Resident_Cmn_CertifiedMatch", "Resident_Cmn_MatchingStandby", "Resident_Cmn_OnlineStandby",
                      "Resident_Cmn_MatchingSelect", "BattleHubDailyTournamentCountdown", "BattleHubAvatarBattleMatchWaiting", "BattleHud_AccountInfo" }
local agent_addr = {}
local stale = {}                  -- agent name -> true: its pieces parked under the host must not be reused
local function fingerprint()      -- returns true when something changed
    local changed = false
    for _, nm in ipairs(POOL_AGENTS) do
        local m = agent_main(nm); local a = m and m:get_address() or 0
        if agent_addr[nm] ~= nil and agent_addr[nm] ~= a then changed = true; stale[nm] = true end
        agent_addr[nm] = a
    end
    return changed
end
local function find_name(ctrl, name, depth)
    if not ctrl or (depth or 0) > 40 then return nil end
    if safe(function() return tostring(ctrl:call("get_Name")) end) == name then return ctrl end
    local c = ctrl:call("get_Child"); local r = c and find_name(c, name, (depth or 0) + 1); if r then return r end
    local nx = ctrl:call("get_Next"); return nx and find_name(nx, name, depth) or nil
end
local function find_path(ctrl, path)
    if type(path) == "string" then return find_name(ctrl, path) end
    local cur = ctrl
    for _, nm in ipairs(path) do cur = cur and find_name(cur, nm); if not cur then return nil end end
    return cur
end
local color_td
local function set_color(c, abgr)
    if safe(function() return c:call("get_Color"):get_field("rgba") end) == abgr then return end
    color_td = color_td or sdk.find_type_definition("via.Color")
    local col = ValueType.new(color_td); col:set_field("rgba", abgr); c:call("set_Color", col)
end
local function set_pos(c, x, y) local p = c:call("get_Position"); if p.x ~= x or p.y ~= y then p.x = x; p.y = y; p.z = 0; c:call("set_Position", p) end end
local function set_size(c, w, h) local s = c:call("get_Size"); if s.w ~= w or s.h ~= h then s.w = w; s.h = h; c:call("set_Size", s) end end

-- Adopt one spare: already parked under the host (after a script reset) -> reuse; else move it from its agent.
local used = {}
local function take(spec)
    local leaf = type(spec[2]) == "table" and spec[2][#spec[2]] or spec[2]
    local c = nil
    if not stale[spec[1]] then
        local k = host:call("get_Child")
        while k do
            if tostring(k:call("get_Name")) == leaf and not used[k:get_address()] then c = k; break end
            k = k:call("get_Next")
        end
    end
    if not c then
        local m = agent_main(spec[1]); c = m and find_path(m, spec[2])
        if not c then return nil end
        if host:call("addChild", c) ~= true then
            if c:get_type_definition():get_name() ~= "Rect" then return nil end
            pcall(function() c:call("remove") end)                    -- Rects survive remove(); Text/Scale9Grid do not
            if host:call("addChild", c) ~= true then return nil end
        end
    end
    used[c:get_address()] = true
    if spec.source then
        local sm = agent_main(spec.source[1]); local s = sm and find_name(sm, spec.source[2])
        if s then s:call("copyProperties", c) end
    end
    pcall(function() c:call("set_ControlPoint", 5) end)
    pcall(function() c:call("set_MaskType", 0) end)                 -- a mask piece would clip the whole host
    pcall(function() c:call("set_ForceInvisible", false) end)
    c:call("set_Visible", false)
    return c
end

local function resolve()
    fingerprint()
    host = agent_main(HOST_AGENT); if not host then return false end
    used = {}
    local p = { rects = {}, texts = {} }
    p.body = take(BODY); p.line = take(LINE)
    if not (p.body and p.line) then return false end
    local tsrc_main = agent_main(TEXT_SOURCE[1]); local tsrc = tsrc_main and find_name(tsrc_main, TEXT_SOURCE[2])
    for i = 1, #BUTTONS do
        p.rects[i] = take(RECTS[i]); p.texts[i] = take(TEXTS[i])
        if not (p.rects[i] and p.texts[i]) then return false end
        if tsrc then tsrc:call("copyProperties", p.texts[i]) end
        pcall(function() p.texts[i]:call("set_ControlPoint", 5) end)   -- copyProperties brings e_txt_0's cp 9 (bottom): re-centre
    end
    P = p; applied = {}; stale = {}
    _G.NativeTopBar_Used = used   -- NativeBottomBar shares the host: never re-adopt these
    return true
end

local function hide_all()
    if not P then return end
    for _, c in ipairs({ P.body, P.line }) do pcall(function() c:call("set_Visible", false) end) end
    for i = 1, #BUTTONS do pcall(function() P.rects[i]:call("set_Visible", false); P.texts[i]:call("set_Visible", false) end) end
    applied = {}
end

local host_ox, host_oy = 0, 0   -- the Timer widget moves its c_main (e.g. when the round timer shows): compensate
local function apply()
    local show = enabled and _G.TrainingModeActive and not _G.TrainingGamePaused and not _G.IsInReplay
    if not show then if applied.shown ~= false then hide_all(); applied.shown = false end; return end
    local cy, ox = CY - host_oy, -host_ox
    set_size(P.body, FRAME_W, FRAME_H); set_pos(P.body, 960 + ox, cy); set_color(P.body, COL_BODY); P.body:call("set_Priority", 40)
    set_size(P.line, FRAME_W, FRAME_H); set_pos(P.line, 960 + ox, cy); set_color(P.line, COL_LINE); P.line:call("set_Priority", 41)
    for i, b in ipairs(BUTTONS) do
        local cx = BTN_X0 + (i - 1) * BTN_PITCH + ox
        local col = (b.id == nil) and COL_SWITCH or ((b.id == active) and COL_ACTIVE or COL_INACTIVE)
        local r, t = P.rects[i], P.texts[i]
        set_size(r, BTN_W, BTN_H); set_pos(r, cx, cy); set_color(r, col); r:call("set_Priority", 45)
        set_pos(t, cx, cy); t:call("set_Priority", 50)
        if applied["t" .. i] ~= b.label then
            t:call("set_Message", "<color FFFFFF>" .. b.label .. "</color>")
            local fs = t:call("get_FontSize"); fs.w = 20; fs.h = 20; t:call("set_FontSize", fs)
            applied["t" .. i] = b.label
        end
    end
    if applied.shown ~= true then
        P.body:call("set_Visible", true); P.line:call("set_Visible", true)
        for i = 1, #BUTTONS do P.rects[i]:call("set_Visible", true); P.texts[i]:call("set_Visible", true) end
        applied.shown = true
    end
end

local last_show = nil
local paused_latch = false
local function game_thread_tick()
    tick = tick + 1
    if _G.TrainingBarsHidden then   -- 30/08: bars removed (SF6 Tools window instead) -> hide once, never resolve
        if P and not paused_latch then pcall(hide_all) end
        paused_latch = true; P = nil; host = nil; applied = {}; used = {}; enabled = false
        return
    end
    -- Pause menu / Options screens rebuild the battle HUD (crashes 30/08: set_Message on freed texts). On the first
    -- paused frame the pieces are still alive: hide them once, then forget them and stay silent until unpaused.
    if _G.TrainingGamePaused or _G.NativeOptionsWindowOpen or not _G.TrainingModeActive then
        if P and not paused_latch then pcall(hide_all) end
        paused_latch = true; P = nil; host = nil; applied = {}; used = {}; dirty = true; last_show = nil
        return
    end
    if paused_latch then paused_latch = false; next_resolve = tick + 10 end
    local show = enabled and not _G.IsInReplay
    if show ~= last_show then last_show = show; dirty = true end
    if not enabled and not P then return end
    if P and tick % 30 == 0 and fingerprint() then P = nil; applied = {}; host = nil; dirty = true; next_resolve = tick + 30 end
    if not P then
        if not show or tick < next_resolve then return end
        next_resolve = tick + 60
        if not pcall(resolve) or not P then P = nil; return end
        dirty = true
    end
    if show and host then   -- one read per frame: follow the host's own offset
        local g = safe(function() return host:call("get_GlobalPosition") end)
        if g and (g.x ~= host_ox or g.y ~= host_oy) then host_ox, host_oy = g.x, g.y; dirty = true end
    end
    if not dirty then return end
    dirty = false
    local ok = pcall(apply)
    if not ok then P = nil; applied = {}; dirty = true end   -- HUD rebuilt (character change...) -> re-resolve
end

re.on_pre_application_entry("LateUpdateBehavior", function() pcall(game_thread_tick) end)
re.on_script_reset(function() enabled = false end)   -- no GUI from the reset thread; pieces are re-adopted next resolve

_G.NativeTopBar = M
return M
