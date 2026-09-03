-- ============================================================
-- NativeBottomBar — the mode scripts' bottom bar (TRIALS -/+, RESET, START, REC...) drawn with the game's OWN GUI
-- elements (via.gui Rect / Text) instead of ImGui. Same recipe and rules as NativeTopBar:
--   * pieces = hidden leaves of agents that never show them in training (ui11257/ui11258 texts, MatchWonNumber
--     titles, WinIcon / ProfileName rects), re-parented under BattleHud_Timer/c_main (font slot 8 available there)
--   * every GUI call from LateUpdateBehavior, write-on-change, nothing while paused / a native window is open
--   * the ImGui bar keeps being drawn by the mode script with alpha 0 -> same click zones. To keep them aligned,
--     the mode script asks this module for the button width (imgui_width) when the native bar is available.
--
--   local NativeBottomBar = require("func/NativeBottomBar")
--   NativeBottomBar.set({ { label = "TRIALS - (1)", color = 0xFF0000FF }, ... })   -- <= MAX_BUTTONS, ABGR colors
--   NativeBottomBar.enable(true)     -- the owner mode script calls this every frame it draws its bar
--   NativeBottomBar.available()      -- true when the native pieces are resolved (mode scripts go alpha 0)
--   NativeBottomBar.imgui_width(n, sw, sh)   -- button width in ImGui pixels for n buttons
-- ============================================================
local M = {}

-- EXPERIMENTAL / OFF by default (30/08): the pool of texts that survive the game's own widgets is not large
-- enough yet (see the notes below) — every candidate but one got freed by its widget after a mode change or a
-- script reload and crashed the game on set_Message. Enable with `_G.NativeBottomBar_Experimental = true`.

local HOST_AGENT = "BattleHud_Timer"
local MAX_BUTTONS = 4
local BAR_H = 48                              -- ImGui: sh * 0.0444
local CY = 1080 - BAR_H / 2
local PAD_X, GAP, RIGHT_RESERVE = 19, 4, 44   -- ImGui: 1% padding, 4 px gap, close checkbox on the right
local BTN_H = 30
local COL_BODY = 0xFF5A0A3C                   -- pause-menu purple (same as the top bar)

-- spares: { agent, path (leaf name or list of names) }
-- Rect pool (body + buttons): pieces are gathered as a POOL, not positionally — after a reload they sit parked under
-- the host under generic names, and a piece lost in one session is back in its agent after a game restart.
local RECT_SPECS = { { "BattleHud_ProfileName", { "p_BattleHudProfilePanel_1", "p_PlatformIcon_0", "e_title_bg" } },
                     { "BattleHud_ProfileName", { "p_BattleHudProfilePanel_0", "p_PlatformIcon_0", "e_title_bg" } },
                     { "BattleHud_WinIcon", { "p_WinIcon_1", "c_win2", "e_rect_effect" } }, { "BattleHud_WinIcon", { "p_WinIcon_1", "c_win1", "e_rect_effect" } },
                     { "BattleHud_WinIcon", { "p_WinIcon_0", "c_win2", "e_rect_effect" } }, { "BattleHud_WinIcon", { "p_WinIcon_0", "c_win1", "e_rect_effect" } },
                     { "BattleHud_GimmicSideAttention", { "c_glow", "e_rect_glow_0" } }, { "BattleHud_GimmicSideAttention", { "c_glow", "e_rect_glow_1" } } }
local RECT_NAMES = { e_title_bg = true, e_rect_effect = true, e_rect_glow_0 = true, e_rect_glow_1 = true }
-- Texts: BORROWED only. Created texts (sdk.create_instance) render under the Timer View/c_main but do not survive a
-- script reset (REFramework frees its instances even with add_ref -> dangling child -> set_Message crash, 30/08).
-- Borrow rule measured today: the engine lends at most one text per agent to a foreign parent, and remove() is not
-- allowed on texts. ui11258 (command form) is the exception with three. HitCount's text may be rewritten by the game
-- during combos: labels are re-asserted every second.
local TEXT_SPECS = { { "ui11258", { "c_commandForm", "e_txt_command" } }, { "ui11258", { "c_commandForm", "e_txt_OD" } },
                     { "ui11258", { "c_commandForm", "e_txt_success" } },
                     { "BattleHud_MatchWonNumber", { "p_WonNumberPanel_1", "e_text_title" } } }
-- (BattleHud_HitCount/e_txt_score adopts fine but set_Message on it after adoption throws -> crash; do not use)
local TEXT_SOURCE = { "Resident_Cmn_MatchingStandby", "e_txt_0" }   -- style copied onto every text (slot 8, no outline)

-- ---------- state ----------
local enabled, dirty = false, true
local buttons = {}                -- { {label=, color=}, ... }
local host, P = nil, nil          -- P = { body=, rects={}, texts={} }
local applied = {}
local tick, next_resolve = 0, 0

local keep = 0
function M.enable(b) if b then keep = 3 end end   -- owners call it every frame they draw; expires after 3 ticks
function M.available() return _G.NativeBottomBar_Experimental == true and P ~= nil and #buttons <= P.slots end   -- a mode asking for more buttons than we have keeps its ImGui bar
function M.set(list)
    list = list or {}
    local n = math.min(#list, MAX_BUTTONS)
    local changed = (#buttons ~= n)
    for i = 1, n do
        local b, o = list[i], buttons[i]
        if not o or o.label ~= b.label or o.color ~= b.color then changed = true end
    end
    if changed then
        buttons = {}
        for i = 1, n do buttons[i] = { label = tostring(list[i].label or ""), color = list[i].color or 0xFF666666 } end
        dirty = true
    end
end
-- geometry shared with the ImGui bar (virtual 1920 -> ImGui pixels)
local function button_w(n) return (1920 - 2 * PAD_X - RIGHT_RESERVE - GAP * n) / n end
function M.imgui_width(n, sw, sh) return button_w(n) * (sh / 1080) end
function M.imgui_pad(sw, sh) return PAD_X * (sh / 1080) end

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
local POOL_AGENTS = { HOST_AGENT, "BattleHud_ProfileName", "BattleHud_WinIcon", "BattleHud_GimmicSideAttention", "Resident_Cmn_MatchingStandby", "ui11258", "BattleHud_MatchWonNumber" }
local agent_addr, stale = {}, {}
local function fingerprint()
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

-- Adopt one spare (same protocol as NativeTopBar): reuse if already parked under the host, else move it.
local used = {}
local function take(spec)
    local leaf = type(spec[2]) == "table" and spec[2][#spec[2]] or spec[2]
    local c = nil
    if not stale[spec[1]] then
        local k = host:call("get_Child")
        while k do
            if tostring(k:call("get_Name")) == leaf and not used[k:get_address()] and k:get_type_definition():get_name() == (spec.kind or k:get_type_definition():get_name()) then c = k; break end
            k = k:call("get_Next")
        end
    end
    if not c then
        local m = agent_main(spec[1]); c = m and find_path(m, spec[2])
        if not c then return nil end
        if host:call("addChild", c) ~= true then
            if c:get_type_definition():get_name() ~= "Rect" then return nil end   -- remove() breaks Text/Scale9Grid for good
            pcall(function() c:call("remove") end)
            if host:call("addChild", c) ~= true then return nil end
        end
    end
    used[c:get_address()] = true
    pcall(function() c:call("set_ControlPoint", 5) end)
    pcall(function() c:call("set_MaskType", 0) end)
    if c:get_type_definition():get_name() == "Rect" then   -- glow/effect rects carry per-corner gradients: flatten them
        color_td = color_td or sdk.find_type_definition("via.Color")
        for _, m in ipairs({ "set_ColorLeftTop", "set_ColorRightTop", "set_ColorLeftBottom", "set_ColorRightBottom" }) do
            pcall(function() local col = ValueType.new(color_td); col:set_field("rgba", 0xFFFFFFFF); c:call(m, col) end)
        end
    end
    pcall(function() c:call("set_ForceInvisible", false) end)
    pcall(function() local s = c:call("get_Scale"); s.x = 1; s.y = 1; c:call("set_Scale", s) end)
    c:call("set_Visible", false)
    return c
end

local function valid_text(t) return t ~= nil and pcall(function() return t:call("get_Message") end) end
local function take_text(spec)
    local t = take(spec)                       -- borrowed: parked under the host
    if not valid_text(t) then return nil end
    return t, host
end

local function prepare(c)
    pcall(function() c:call("set_ControlPoint", 5) end)
    pcall(function() c:call("set_MaskType", 0) end)
    if c:get_type_definition():get_name() == "Rect" then   -- glow/effect rects carry per-corner gradients: flatten them
        color_td = color_td or sdk.find_type_definition("via.Color")
        for _, m in ipairs({ "set_ColorLeftTop", "set_ColorRightTop", "set_ColorLeftBottom", "set_ColorRightBottom" }) do
            pcall(function() local col = ValueType.new(color_td); col:set_field("rgba", 0xFFFFFFFF); c:call(m, col) end)
        end
    end
    pcall(function() c:call("set_ForceInvisible", false) end)
    pcall(function() local sc = c:call("get_Scale"); sc.x = 1; sc.y = 1; c:call("set_Scale", sc) end)
    c:call("set_Visible", false)
end
local function collect_rects(n)
    local out = {}
    local k = host:call("get_Child")                     -- 1. parked under the host (previous resolve / reload)
    while k and #out < n do
        if k:get_type_definition():get_name() == "Rect" and RECT_NAMES[tostring(k:call("get_Name"))] and not used[k:get_address()] then
            used[k:get_address()] = true; prepare(k); out[#out + 1] = k
        end
        k = k:call("get_Next")
    end
    for _, spec in ipairs(RECT_SPECS) do                  -- 2. still in their agents
        if #out >= n then break end
        if not stale[spec[1]] then
            local m = agent_main(spec[1]); local c = m and find_path(m, spec[2])
            if c and not used[c:get_address()] then
                local ok = host:call("addChild", c) == true
                if not ok then pcall(function() c:call("remove") end); ok = host:call("addChild", c) == true end
                if ok then used[c:get_address()] = true; prepare(c); out[#out + 1] = c
                else _G.NativeBottomBar_refused = (_G.NativeBottomBar_refused or "") .. spec[1] .. "/" .. spec[2][#spec[2]] .. " " end
            elseif not c then _G.NativeBottomBar_missing = (_G.NativeBottomBar_missing or "") .. spec[1] .. "/" .. spec[2][#spec[2]] .. " " end
        end
    end
    return out
end

local function resolve()
    fingerprint()
    host = agent_main(HOST_AGENT); if not host then return false end
    used = {}
    -- the top bar parks its pieces under the same host: never steal them (they are named differently, but be safe)
    if _G.NativeTopBar_Used then for a, _ in pairs(_G.NativeTopBar_Used) do used[a] = true end end
    local p = { rects = {}, texts = {}, tparents = {} }
    _G.NativeBottomBar_refused, _G.NativeBottomBar_missing = nil, nil
    local rects = collect_rects(MAX_BUTTONS + 1)
    if #rects < 5 then _G.NativeBottomBar_fail = "rects " .. #rects; return false end   -- body + 4 buttons minimum
    p.body = rects[1]
    p.slots = math.min(#rects - 1, #TEXT_SPECS)
    for i = 1, p.slots do p.rects[i] = rects[i + 1] end
    local tsrc_main = agent_main(TEXT_SOURCE[1]); local tsrc = tsrc_main and find_name(tsrc_main, TEXT_SOURCE[2])
    for i = 1, p.slots do
        local t, par = take_text(TEXT_SPECS[i])
        if not t then _G.NativeBottomBar_fail = "text" .. i; return false end
        p.texts[i], p.tparents[i] = t, par
        if tsrc then tsrc:call("copyProperties", t) end
        pcall(function() t:call("set_FontSlot", 8); t:call("set_ControlPoint", 5); t:call("set_MaskType", 0) end)
        t:call("set_Visible", false)
    end
    P = p; applied = {}; stale = {}; _G.NativeBottomBar_fail = nil
    return true
end

local function hide_all()
    if not P then return end
    pcall(function() P.body:call("set_Visible", false) end)
    for i = 1, P.slots do pcall(function() P.rects[i]:call("set_Visible", false); P.texts[i]:call("set_Visible", false) end) end
    applied = {}
end

local host_ox, host_oy = 0, 0
local function apply()
    local show = enabled and #buttons > 0 and #buttons <= P.slots and not _G.IsInReplay
    if not show then if applied.shown ~= false then hide_all(); applied.shown = false end; return end
    local n = #buttons
    local cy, ox = CY - host_oy, -host_ox
    local w = button_w(n)
    set_size(P.body, 1920, BAR_H); set_pos(P.body, 960 + ox, cy); set_color(P.body, COL_BODY); P.body:call("set_Priority", 40)
    for i = 1, P.slots do
        local r, t = P.rects[i], P.texts[i]
        local b = buttons[i]
        if b then
            local cx = PAD_X + (i - 1) * (w + GAP) + w / 2 + ox
            set_size(r, w, BTN_H); set_pos(r, cx, cy); set_color(r, b.color); r:call("set_Priority", 45)
            local pg = safe(function() return P.tparents[i]:call("get_GlobalPosition") end)
            set_pos(t, cx - (pg and pg.x or 0) - ox, cy - (pg and pg.y or 0) + host_oy); t:call("set_Priority", 50)
            if applied["t" .. i] ~= b.label then
                t:call("set_Message", "<color FFFFFF>" .. b.label .. "</color>")
                local fs = t:call("get_FontSize"); fs.w = 20; fs.h = 20; t:call("set_FontSize", fs)
                applied["t" .. i] = b.label
            end
            if applied["v" .. i] ~= true then r:call("set_Visible", true); t:call("set_Visible", true); applied["v" .. i] = true end
        elseif applied["v" .. i] ~= false then
            r:call("set_Visible", false); t:call("set_Visible", false); applied["v" .. i] = false
        end
    end
    if applied.shown ~= true then P.body:call("set_Visible", true); applied.shown = true end
end

local last_show, paused_latch = nil, false
local function game_thread_tick()
    tick = tick + 1
    if not _G.NativeBottomBar_Experimental then return end
    if _G.TrainingGamePaused or _G.NativeOptionsWindowOpen or not _G.TrainingModeActive then
        if P and not paused_latch then pcall(hide_all) end
        paused_latch = true; P = nil; host = nil; applied = {}; used = {}; dirty = true; last_show = nil
        return
    end
    if paused_latch then paused_latch = false; next_resolve = tick + 10 end
    if keep > 0 then keep = keep - 1 end
    local b = keep > 0; if b ~= enabled then enabled = b; dirty = true end
    local show = enabled and #buttons > 0
    if show ~= last_show then last_show = show; dirty = true end
    if not enabled and not P then return end
    if P and tick % 30 == 0 and fingerprint() then P = nil; applied = {}; host = nil; dirty = true; next_resolve = tick + 30 end
    if not P then
        if not show or tick < next_resolve then return end
        next_resolve = tick + 60
        local okr, errr = pcall(resolve); if not okr then _G.NativeBottomBar_err = tostring(errr) end
        if not okr or not P then P = nil; return end
        dirty = true
    end
    if show and host then
        local g = safe(function() return host:call("get_GlobalPosition") end)
        if g and (g.x ~= host_ox or g.y ~= host_oy) then host_ox, host_oy = g.x, g.y; dirty = true end
    end
    if tick % 60 == 0 and P then for i = 1, P.slots do applied["t" .. i] = nil end; dirty = true end   -- re-assert labels (HitCount text is game-written)
    if not dirty then return end
    dirty = false
    local ok = pcall(apply)
    if not ok then P = nil; applied = {}; dirty = true end
end

re.on_pre_application_entry("LateUpdateBehavior", function() pcall(game_thread_tick) end)
re.on_script_reset(function() enabled = false end)

_G.NativeBottomBar = M
return M
