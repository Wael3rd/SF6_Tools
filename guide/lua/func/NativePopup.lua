-- ============================================================
-- NativePopup — on-demand popups built from the game's OWN GUI elements, without removing anything
-- the game shows. Recipe (validated 29/08/2026, see memory project_native_windows):
--   * take leaf elements the engine built but never displays in Fighting Ground (hidden BH/WT skins of
--     the resident matchmaking popups), copy the look of the element we want (source:copyProperties(spare)),
--     re-parent them under a visible host (BattleHud_Timer/c_main) and drive size/pos/color/priority.
--   * sdk.create_instance never renders, duplicate() is unusable from Lua, Panels don't re-register children.
-- HARD RULES: every GUI call from re.on_pre_application_entry("LateUpdateBehavior"); no sdk.hook; never touch
-- GUI from re.on_script_reset; nine-slice height >= 2 x BorderRect margin.
--
-- Usage:
--   local Popup = require("func/NativePopup")
--   Popup.claim("hitconfirm")                       -- take the popup
--   Popup.style("neon")                              -- "neon" (Match Found frame) | "bar" (thin pill frame)
--   Popup.box(960, 600, 800, 92)                     -- center x, top y, width, height (visible body)
--   Popup.line(1, "<color FA586F>Hit Confirm</color> SCORE 12 / 20", 0xFFFF77DD)   -- up to 3 lines
--   Popup.show(true) / Popup.show(false)
--   Popup.release("hitconfirm")                     -- hides everything, pieces stay parked under the host
-- ============================================================
local M = {}
local MAX_LINES = 3

-- ---------- pool: [role] = { spare = {agent, name, size_filter}, source = {agent, name} } ----------
-- spare = hidden, never-shown-in-FG leaf we recycle ; source = element whose look is copied onto it.
local POOL = {
    neon_frame = { spare = { "Resident_Cmn_MatchingStandby", "e_s9g_bg" },            source = { "Resident_Cmn_MatchingStandby", "e_tex_base" } },
    neon_add   = { spare = { "Resident_Cmn_MatchingSelect",  "e_s9g_frame", 1034 },   source = { "Resident_Cmn_MatchingStandby", "e_s9g_add" } },
    neon_glow  = { spare = { "Resident_Cmn_MatchingSelect",  "e_s9g_shadow", 1200 },  source = { "Resident_Cmn_MatchingStandby", "e_s9g_glow" } },
    neon_rect  = { spare = { "Resident_Cmn_MatchingSelect",  "e_bg", 500 } },
    bar_shadow = { spare = { "Resident_Cmn_MatchingStandby", "e_scale9grid_shadow" }, source = { "Resident_Cmn_OnlineStandby", "e_s9g_shadow" } },
    bar_line   = { spare = { "Resident_Cmn_MatchingStandby", "e_scale9grid_line" },   source = { "Resident_Cmn_OnlineStandby", "e_s9g_line" } },
    bar_rect   = { spare = { "Resident_Cmn_MatchingStandby", "e_bg_cfn" } },
    -- texts take the exact style (font slot 8, no outline/glow) of the Match Found popup line
    text1      = { spare = { "BattleHubDailyTournamentCountdown", "e_text_round" }, source = { "Resident_Cmn_MatchingStandby", "e_txt_0" } },
    text2      = { spare = { "BattleHubAvatarBattleMatchWaiting", "e_text_ready" }, source = { "Resident_Cmn_MatchingStandby", "e_txt_0" } },
    text3      = { spare = { "Resident_Cmn_MatchingSelect", "e_txt_wait" },         source = { "Resident_Cmn_MatchingStandby", "e_txt_0" } },
}
local STYLES = {
    neon = { pieces = { "neon_rect", "neon_add", "neon_frame", "neon_glow" }, text_color = 0xFFFF77DD },
    bar  = { pieces = { "bar_shadow", "bar_rect", "bar_line" },               text_color = 0xFFFFFFFF },
}
local HOST_AGENT = "BattleHud_Timer"

-- ---------- state ----------
local owner, want = nil, { style = "neon", x = 960, top = 600, w = 800, h = 92, visible = false, lines = {} }
local pieces = {}          -- role -> control (resolved, re-parented, look copied)
local host = nil
local applied = {}         -- last written values, write-on-change
local dirty, tick, next_resolve = true, 0, 0

function M.claim(name) if owner ~= name then owner = name; applied = {}; dirty = true end; _G.NativePopup_Owner = owner end
function M.release(name)
    if owner == nil or (name and owner ~= name) then return end
    owner = nil; _G.NativePopup_Owner = nil; want.visible = false; want.lines = {}; dirty = true
end
function M.owner() return owner end
function M.style(s) if STYLES[s] and want.style ~= s then want.style = s; applied = {}; dirty = true end end
function M.box(x, top, w, h) want.x, want.top, want.w, want.h = x, top, w, h; dirty = true end
function M.line(i, text, color)
    if i < 1 or i > MAX_LINES then return end
    local l = want.lines[i]; if not l then l = {}; want.lines[i] = l end
    if l.text ~= text or l.color ~= color then l.text, l.color = text, color; dirty = true end
end
function M.show(b) if want.visible ~= (b and true or false) then want.visible = b and true or false; dirty = true end end
function M.available() return host ~= nil and pieces.text1 ~= nil end

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
local function find_leaf(ctrl, name, w_filter, depth)
    if not ctrl or (depth or 0) > 40 then return nil end
    if safe(function() return tostring(ctrl:call("get_Name")) end) == name then
        if not w_filter then return ctrl end
        local s = safe(function() return ctrl:call("get_Size") end)
        if s and math.floor(s.w) == w_filter then return ctrl end
    end
    local c = ctrl:call("get_Child"); local r = c and find_leaf(c, name, w_filter, (depth or 0) + 1); if r then return r end
    local nx = ctrl:call("get_Next"); return nx and find_leaf(nx, name, w_filter, depth) or nil
end
local color_td
local function set_color(c, abgr)
    local cur = safe(function() return c:call("get_Color"):get_field("rgba") end)
    if cur == abgr then return end
    color_td = color_td or sdk.find_type_definition("via.Color")
    local col = ValueType.new(color_td); col:set_field("rgba", abgr); c:call("set_Color", col)
end
local function set_pos(c, x, y) local p = c:call("get_Position"); if p.x ~= x or p.y ~= y then p.x = x; p.y = y; p.z = 0; c:call("set_Position", p) end end
local function set_size(c, w, h) local s = c:call("get_Size"); if s.w ~= w or s.h ~= h then s.w = w; s.h = h; c:call("set_Size", s) end end

-- Resolve one role: adopt a piece already parked under the host (survives script reset), else move the spare.
local function resolve_role(role)
    local spec = POOL[role]
    local c = find_leaf(host:call("get_Child"), spec.spare[2], spec.spare[3], 0)
    if not c then
        local src_main = agent_main(spec.spare[1]); if not src_main then return nil end
        c = find_leaf(src_main, spec.spare[2], spec.spare[3]); if not c then return nil end
        -- addChild may return false (element refused while attached elsewhere). remove() then addChild fixes it
        -- but remove() strips Text/Scale9Grid of their font/atlas registration -> only ever do that for Rects.
        if host:call("addChild", c) ~= true then
            if c:get_type_definition():get_name() ~= "Rect" then return nil end
            pcall(function() c:call("remove") end)
            if host:call("addChild", c) ~= true then return nil end
        end
    end
    pcall(function() c:call("set_MaskType", 0) end)         -- a borrowed mask would clip the whole host
    if spec.source then   -- (re)copy the look every resolve, adopted pieces included
        local sm = agent_main(spec.source[1]); local s = sm and find_leaf(sm, spec.source[2])
        if s then s:call("copyProperties", c) end              -- SOURCE -> TARGET (never the other way round)
    end
    pcall(function() c:call("set_ForceInvisible", false) end)
    pcall(function() c:call("set_ControlPoint", 5) end)        -- centre anchor for every piece
    c:call("set_Visible", false)
    return c
end

local function resolve_all()
    host = agent_main(HOST_AGENT); if not host then return false end
    for role in pairs(POOL) do if not pieces[role] then pieces[role] = resolve_role(role) end end
    return pieces.text1 ~= nil
end

local function hide_all() for _, c in pairs(pieces) do pcall(function() c:call("set_Visible", false) end) end; applied = {} end

local function apply()
    local st = STYLES[want.style]
    local cx, top, w, h = want.x, want.top, want.w, want.h
    local cy = top + h / 2
    if not want.visible or not owner then hide_all(); return end
    -- pieces of the other style off
    for role, c in pairs(pieces) do
        local used = false
        for _, r in ipairs(st.pieces) do if r == role then used = true end end
        if not used and not role:find("^text") then pcall(function() c:call("set_Visible", false) end) end
    end
    if want.style == "neon" then
        -- geometry of the real Match Found popup: rect 785x92 inside a 900x204 frame (margins 64), glow 900x200 low
        local fw, fh = w + 115, math.max(h + 112, 130)
        local P = pieces
        if P.neon_rect  then set_size(P.neon_rect, w, h);   set_pos(P.neon_rect, cx, cy);  set_color(P.neon_rect, 0xE6000000); P.neon_rect:call("set_Priority", 20) end
        -- real popup draw order (c_bg_FG children): rect, frame, glow, then the additive purple layer ON TOP
        if P.neon_frame then set_size(P.neon_frame, fw, fh); set_pos(P.neon_frame, cx, cy); set_color(P.neon_frame, 0xFFFFFFFF); P.neon_frame:call("set_Priority", 21) end
        if P.neon_glow  then set_size(P.neon_glow, fw, 200); set_pos(P.neon_glow, cx, cy + h / 2 + 10); set_color(P.neon_glow, 0x4FB51E8F); P.neon_glow:call("set_Priority", 22) end
        if P.neon_add   then set_size(P.neon_add, fw, fh);  set_pos(P.neon_add, cx, cy);   set_color(P.neon_add, 0xFF820061);  P.neon_add:call("set_Priority", 23) end
    else
        local P = pieces
        if P.bar_shadow then set_size(P.bar_shadow, w + 50, h + 50); set_pos(P.bar_shadow, cx, cy); set_color(P.bar_shadow, 0x33000000); P.bar_shadow:call("set_Priority", 20) end
        if P.bar_rect   then set_size(P.bar_rect, w, h);             set_pos(P.bar_rect, cx, cy);   set_color(P.bar_rect, 0xF2141414);   P.bar_rect:call("set_Priority", 21) end
        if P.bar_line   then set_size(P.bar_line, w - 2, h - 2);     set_pos(P.bar_line, cx, cy);   set_color(P.bar_line, 0x80FFFFFF);   P.bar_line:call("set_Priority", 22) end
    end
    for _, r in ipairs(st.pieces) do if pieces[r] then pieces[r]:call("set_Visible", true) end end
    -- text lines, stacked and centred in the body
    local n = 0
    for i = 1, MAX_LINES do if want.lines[i] and want.lines[i].text and want.lines[i].text ~= "" then n = i end end
    for i = 1, MAX_LINES do
        local t = pieces["text" .. i]
        if t then
            local l = want.lines[i]
            if i <= n and l and l.text and l.text ~= "" then
                local ly = top + h * (i - 0.5) / n
                set_pos(t, cx, ly)
                if applied["t" .. i] ~= l.text then t:call("set_Message", l.text); applied["t" .. i] = l.text end
                set_color(t, l.color or st.text_color)
                t:call("set_Priority", 30); t:call("set_Visible", true)
            else
                t:call("set_Visible", false)
            end
        end
    end
end

local function game_thread_tick()
    tick = tick + 1
    if not owner and not dirty then return end
    if not M.available() then
        if tick < next_resolve then return end
        next_resolve = tick + 60
        if not pcall(resolve_all) or not M.available() then return end
        applied = {}
    end
    if not dirty then return end
    dirty = false
    local ok = pcall(apply)
    if not ok then pieces = {}; host = nil; applied = {}; dirty = true end   -- HUD rebuilt -> re-resolve
end

re.on_pre_application_entry("LateUpdateBehavior", function() pcall(game_thread_tick) end)
re.on_script_reset(function() owner = nil; _G.NativePopup_Owner = nil end)   -- no GUI from the reset thread

_G.NativePopup = M
return M
