-- ============================================================
-- NativeHud — drive the game's own training HUD text instead of drawing an overlay:
--   * the attack-info panel (3 rows: Damage / Combo Damage / Attack Type)
--   * the round-timer digits (the big number / infinity sign at the top)
-- Same font, size, background and sprites as the game, zero per-frame rendering on our side.
--
-- HARD RULES (each one is a crash we bisected on 29/08/2026 — see memory):
--   1. Every GUI write happens on the game's main thread, from
--      re.on_pre_application_entry("LateUpdateBehavior"). Never from re.on_frame (render
--      thread), never from re.on_script_reset (reset thread), never from rendering entries.
--   2. NO sdk.hook on the HUD widgets. Lua callbacks on UIWidget_TMAttackInfo.SetXText /
--      UIBattleHud_Timer.UpdateBattleHud ran off the main thread and crashed the game
--      (0/3 crashes without them, 3/3 with them).
--   3. Never fight the game for a control it rewrites every frame: the panel SIDE texts are
--      re-pushed each frame by the widget, so we hide them once and use the CENTER texts,
--      which the game only touches on hit/guard events (we re-assert them next tick).
--   4. Write-on-change only; compare against what is really displayed.
--
-- Usage (any mode script; set() only fills a table):
--   local NativeHud = require("func/NativeHud")
--   NativeHud.claim("hitconfirm")                     -- take the HUD
--   NativeHud.set(0, "l", "SCORE: 3", 0xFF00FF00)     -- row 0..2, col "l"/"c"/"r"; l/c/r of a row
--                                                     --   are joined into that row's center text
--   NativeHud.set_timer(29, 0xFF0000FF)               -- 0..99 in the game's digit sprites (+ color)
--   NativeHud.release("hitconfirm")                   -- give everything back
-- ============================================================
local M = {}

local ROWS = 3
local COLS = { "l", "c", "r" }
local FIELD = { l = "LeftText", c = "CenterText", r = "RightText" }
local GAP = "     "                       -- between the l / c / r parts of a row
local GAME_CENTER_COLOR = 0xFFFFFFFF      -- the panel's real center tint (verified live)
local NATIVE_DIGIT_COLOR = 0xFFFFFFFF     -- digit sprites tint (the magenta glow is a separate sprite)

local owner = nil          -- who drives the HUD (nil = the game)
local want = {}            -- [row][col] = { text=, color= }
local panel = nil          -- { [row] = { l=Text, c=Text, r=Text } } resolved controls
local orig = nil           -- [row] = original center message, to restore
local applied = {}         -- [row] = { text=, color= } last written center
local sides_hidden = false
local vis_request = nil    -- Script Manager's "texts visible?" request (applied here, main thread)
local vis_applied = nil
local restore_pending = false
local tick, next_resolve = 0, 0

for r = 0, ROWS - 1 do want[r] = {} end

-- ---------- public ----------
function M.claim(name)
    if owner ~= name then owner = name; applied = {} end
    _G.NativeHud_Owner = owner
end

function M.release(name)
    if owner == nil or (name and owner ~= name) then return end
    owner = nil; _G.NativeHud_Owner = nil
    restore_pending = true
    for r = 0, ROWS - 1 do want[r] = {} end
    M.set_timer(nil)
end

function M.request_text_visible(b) vis_request = b end
function M.owner() return owner end
function M.available() return panel ~= nil end

function M.set(row, col, text, color)
    local w = want[row]; if not w then return end
    local cell = w[col]; if not cell then cell = {}; w[col] = cell end
    cell.text = text or ""; cell.color = color
end

function M.clear() for r = 0, ROWS - 1 do want[r] = {} end end

-- ---------- helpers (main thread only) ----------
local color_td = nil
local function make_color(abgr)
    if not color_td then color_td = sdk.find_type_definition("via.Color") end
    if not color_td then return nil end
    local ok, c = pcall(ValueType.new, color_td)
    if not ok or not c then return nil end
    local oks = pcall(function() c:set_field("rgba", abgr) end)
    return oks and c or nil
end

local function set_color(t, abgr)
    local cur = nil
    pcall(function() cur = t:call("get_Color"):get_field("rgba") end)
    if cur ~= abgr then local c = make_color(abgr); if c then t:call("set_Color", c) end end
end

-- The game's own center labels ("Damage" / "Combo Damage" / "Attack Type" in English). Learnt once from a clean
-- panel and kept on disk: after a script reload the panel still shows OUR text, which must never become "original".
local ORIG_FILE = "NativeHud_data/panel_orig.json"
local game_orig = {}
do
    local saved = json.load_file(ORIG_FILE)
    if type(saved) == "table" then for k, v in pairs(saved) do local n = tonumber(k); if n and type(v) == "string" then game_orig[n] = v end end end
end
local function save_orig()
    local out = {}
    for k, v in pairs(game_orig) do out[tostring(k)] = v end
    pcall(json.dump_file, ORIG_FILE, out)
end
local function row_text_of(r)
    local parts = {}
    for _, c in ipairs(COLS) do local cell = want[r] and want[r][c]; if cell and cell.text and cell.text ~= "" then parts[#parts + 1] = cell.text end end
    return table.concat(parts, GAP)
end
local function resolve_panel()
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return nil end
    local dict = mgr:get_field("_ViewUIWigetDict")
    local entries = dict and dict:get_field("_entries")
    if not entries then return nil end
    for i = 0, entries:call("get_Count") - 1 do
        local entry = entries:call("get_Item", i)
        local wl = entry and entry:get_field("value")
        if wl then
            for j = 0, wl:call("get_Count") - 1 do
                local w = wl:call("get_Item", j)
                local td = w and w:get_type_definition()
                if td and string.find(td:get_full_name(), "TMAttackInfo") then
                    local infos = w:get_field("AttackInfos")
                    if infos then
                        local out, o = {}, {}
                        for k = 0, math.min(infos:call("get_Length"), ROWS) - 1 do
                            local line = infos:call("GetValue", k)
                            if line then
                                out[k] = {}
                                for _, c in ipairs(COLS) do out[k][c] = line:get_field(FIELD[c]) end
                                local okm, msg = pcall(function() return tostring(out[k].c:call("get_Message")) end)
                                msg = okm and msg or ""
                                -- keep the game's own text: after a reload the panel may still show what WE wrote
                                if (game_orig[k] == nil or game_orig[k] == "") and msg ~= "" and msg ~= row_text_of(k) and not owner then
                                    game_orig[k] = msg; save_orig()     -- only from a panel nobody of ours is driving
                                end
                                if game_orig[k] == nil then game_orig[k] = "" end
                                o[k] = game_orig[k]
                            end
                        end
                        if out[0] then return out, o end
                    end
                end
            end
        end
    end
    return nil
end

local function row_text(r)
    local parts = {}
    for _, c in ipairs(COLS) do
        local cell = want[r][c]
        if cell and cell.text and cell.text ~= "" then parts[#parts + 1] = cell.text end
    end
    return table.concat(parts, GAP)
end

-- Our ImGui palette's "White" is 0xFFDADADA (light grey); on the game's own text we want the
-- game's pure white, so that value (and nil) map to GAME_CENTER_COLOR. Real tints stay.
local PALETTE_WHITE = 0xFFDADADA
local function native_color(abgr)
    if abgr == nil or abgr == PALETTE_WHITE then return GAME_CENTER_COLOR end
    return abgr
end

local function row_color(r)
    -- the status/verdict color (center cell) wins, else the first tinted cell
    local cc = want[r].c
    if cc and cc.color and native_color(cc.color) ~= GAME_CENTER_COLOR then return cc.color end
    for _, c in ipairs(COLS) do
        local cell = want[r][c]
        if cell and cell.color and native_color(cell.color) ~= GAME_CENTER_COLOR then return cell.color end
    end
    return GAME_CENTER_COLOR
end

-- Proof of life before ANY write: the pause menu / options window tears the battle HUD down before our
-- LateUpdate runs, and pcall does not stop a native AV in set_Message on a freed control (crash 30/08).
local function alive(c) return c ~= nil and sdk.is_managed_object(c:get_address()) end
local function timer_alive(t)
    return t and alive(t.panel) and (t.d1 == nil or alive(t.d1))
end

local function apply_panel()
    for r = 0, ROWS - 1 do
        local row = panel[r]
        if row and row.c then
            if not alive(row.c) then panel = nil; orig = nil; applied = {}; return end   -- HUD rebuilt: re-resolve
            local text, color = row_text(r), row_color(r)
            local cur = tostring(row.c:call("get_Message"))
            if cur ~= text then row.c:call("set_Message", text) end
            pcall(set_color, row.c, color)
            if not sides_hidden then
                if row.l then row.l:call("set_Visible", false) end
                if row.r then row.r:call("set_Visible", false) end
            end
            if vis_applied ~= true then row.c:call("set_Visible", true) end
        end
    end
    sides_hidden = true
    vis_applied = true
end

local function restore_panel()
    if not panel then return end
    for r = 0, ROWS - 1 do
        local row = panel[r]
        if row then
            if row.c and alive(row.c) then
                pcall(function() row.c:call("set_Message", (orig and orig[r]) or "") end)
                pcall(set_color, row.c, GAME_CENTER_COLOR)
            end
            if row.l and alive(row.l) then pcall(function() row.l:call("set_Visible", true) end) end
            if row.r and alive(row.r) then pcall(function() row.r:call("set_Visible", true) end) end
        end
    end
    sides_hidden = false
    applied = {}
end

-- Script Manager visibility (hide the panel texts in script modes without native HUD)
local function apply_visibility()
    if not panel or vis_request == nil then return end
    if panel[0] and panel[0].c and not alive(panel[0].c) then panel = nil; orig = nil; return end
    local v = vis_request
    if vis_applied == v then return end
    for r = 0, ROWS - 1 do
        local row = panel[r]
        if row then for _, c in ipairs(COLS) do if row[c] then row[c]:call("set_Visible", v) end end end
    end
    vis_applied = v
    sides_hidden = false
end

-- ---------- native round timer (digit sprites), no hooks ----------
local timer_value, timer_color = nil, nil
local timer_ctrls = nil        -- { panel=, d1=, d10=, d100=, inf= }
local timer_state = {}         -- last written { v=, color=, shown= }
local timer_orig = nil         -- the game's digit patterns / visibility, captured at first resolve

local function find_ctrl(ctrl, name, depth)
    if not ctrl or (depth or 0) > 30 then return nil end
    local ok, nm = pcall(function() return tostring(ctrl:call("get_Name")) end)
    if ok and nm == name then return ctrl end
    local c = ctrl:call("get_Child"); local r = c and find_ctrl(c, name, (depth or 0) + 1); if r then return r end
    local nx = ctrl:call("get_Next"); return nx and find_ctrl(nx, name, depth) or nil
end

local function resolve_timer()
    local mgr = sdk.get_managed_singleton("app.UIAgentManager")
    if not mgr then return nil end
    local list = mgr:get_field("_Entries")
    for i = 0, list:call("get_Count") - 1 do
        local agent = list:call("get_Item", i).Agent
        local go = agent and agent:call("get_GameObject")
        if go and tostring(go:call("get_Name")) == "BattleHud_Timer" then
            local main = agent:call("get_ControlMain")
            local p = find_ctrl(main, "p_TexNumber_")
            if p then
                local t = { panel = p, d1 = find_ctrl(p, "e_texture_number_001"), d10 = find_ctrl(p, "e_texture_number_010"),
                            d100 = find_ctrl(p, "e_texture_number_100"), inf = find_ctrl(main, "c_infinite") }
                if not timer_orig then   -- the game's digits, learnt once (never our own)
                    timer_orig = {}
                    for _, k in ipairs({ "d1", "d10", "d100" }) do
                        if t[k] then timer_orig[k] = { uv = t[k]:call("get_UVPatternNo"), vis = t[k]:call("get_Visible") } end
                    end
                    timer_orig.panel_vis = p:call("get_Visible")
                end
                return t
            end
        end
    end
    return nil
end

function M.set_timer(n, abgr)    -- integer 0..999 (nil = give the timer back), optional ABGR color
    if n ~= nil then n = math.max(0, math.min(999, math.floor(n))) end
    timer_value, timer_color = n, abgr
end

-- The game's timer is laid out for two digits (tens x=-30, units x=+30, hundreds parked at
-- x=-57 overlapping). For 100..999 we spread the three sprites (-60 / 0 / +60) and shrink the
-- panel (0.8 -> 0.65); below 100 the game's own layout is restored. Verified by screenshot.
local LAYOUT = {
    two   = { scale = 0.8,  d100 = -57, d10 = -30, d1 = 30 },
    three = { scale = 0.65, d100 = -60, d10 = 0,   d1 = 60 },
}
local function set_pos(t, x) local p = t:call("get_Position"); p.x = x; p.y = 0; t:call("set_Position", p) end
local function set_scale(t, v) local sc = t:call("get_Scale"); sc.x = v; sc.y = v; t:call("set_Scale", sc) end
local function apply_layout(t, name)
    if timer_state.layout == name then return end
    local L = LAYOUT[name]
    if t.d100 then pcall(set_pos, t.d100, L.d100) end
    if t.d10 then pcall(set_pos, t.d10, L.d10) end
    if t.d1 then pcall(set_pos, t.d1, L.d1) end
    pcall(set_scale, t.panel, L.scale)
    timer_state.layout = name
end

local function apply_timer()
    if timer_value ~= nil then
        if not timer_ctrls then timer_ctrls = resolve_timer(); if not timer_ctrls then return end end
        local t = timer_ctrls
        if not timer_alive(t) then timer_ctrls = nil; timer_state = {}; return end
        if timer_state.v ~= timer_value then
            local d1, d10, d100 = timer_value % 10, math.floor(timer_value / 10) % 10, math.floor(timer_value / 100)
            apply_layout(t, timer_value >= 100 and "three" or "two")
            if t.d1 then t.d1:call("set_UVPatternNo", d1) end
            if t.d10 then t.d10:call("set_UVPatternNo", d10); t.d10:call("set_Visible", timer_value >= 10) end
            if t.d100 then t.d100:call("set_UVPatternNo", d100); t.d100:call("set_Visible", timer_value >= 100) end
            timer_state.v = timer_value
        end
        local col = timer_color or NATIVE_DIGIT_COLOR
        if timer_state.color ~= col then
            for _, k in ipairs({ "d1", "d10", "d100" }) do if t[k] then pcall(set_color, t[k], col) end end
            timer_state.color = col
        end
        if timer_state.shown ~= true then
            t.panel:call("set_Visible", true)
            if t.inf then t.inf:call("set_ForceInvisible", true) end
            timer_state.shown = true
        end
    elseif timer_state.shown then
        local t = timer_ctrls
        if t and not timer_alive(t) then timer_ctrls = nil; timer_state = {}; return end
        if t then
            for _, k in ipairs({ "d1", "d10", "d100" }) do
                if t[k] then
                    pcall(set_color, t[k], NATIVE_DIGIT_COLOR)
                    local o = timer_orig and timer_orig[k]
                    if o then pcall(function() t[k]:call("set_UVPatternNo", o.uv); t[k]:call("set_Visible", o.vis) end) end
                end
            end
            apply_layout(t, "two")   -- the game's own geometry back
            if not timer_orig and t.d100 then pcall(function() t.d100:call("set_Visible", false) end) end
            t.panel:call("set_Visible", timer_orig and timer_orig.panel_vis or false)
            if t.inf then t.inf:call("set_ForceInvisible", false) end
        end
        timer_state = {}
    end
end

-- ---------- pause menu entry: restore while everything is guaranteed alive ----------
-- The pause menu / options screens tear the battle HUD down BEFORE our LateUpdate tick sees the pause
-- flag; writing at "first paused frame" raced that teardown (AV in set_Message, crashes 30/08 22:10 & 23:40).
-- TrainingManager.OpenMenu is the single entry point, called on the game thread while the HUD is still
-- intact: give the game its texts and digits back right here, then drop every cache.
local function restore_and_drop()
    if panel then pcall(restore_panel) end
    if timer_ctrls and timer_state.shown then local tv = timer_value; timer_value = nil; pcall(apply_timer); timer_value = tv end
    panel = nil; orig = nil; timer_ctrls = nil; timer_state = {}; vis_applied = nil; sides_hidden = false
end
do
    local tm_td = sdk.find_type_definition("app.training.TrainingManager")
    local m = tm_td and tm_td:get_method("OpenMenu(app.training.TrainingManager.MenuType, app.training.BaseParam)")
    if m then sdk.hook(m, function(args) pcall(restore_and_drop) end, function(rv) return rv end) end
end

-- ---------- main-thread tick ----------
-- Any change of the PauseManager type bit (our window's type 8, the real pause menu, dialogs...) makes the
-- game rebuild the battle HUD: every cached control may be freed, and is_managed_object can pass on a
-- reallocated chunk (crash 31/08 00:37 with guards in place). On a bit change: drop everything, write
-- NOTHING, and wait 20 ticks before resolving again.
local pause_mgr, last_bit, bit_settle = nil, nil, 0
local function game_thread_tick()
    tick = tick + 1
    if not pause_mgr then pause_mgr = sdk.get_managed_singleton("app.PauseManager") end
    if pause_mgr then
        local b = pause_mgr:get_field("_CurrentPauseTypeBit")
        if b ~= last_bit then
            if last_bit ~= nil then
                panel = nil; orig = nil; timer_ctrls = nil; timer_state = {}; vis_applied = nil; sides_hidden = false; applied = {}
                bit_settle = tick + 20
            end
            last_bit = b
        end
        if tick < bit_settle then return end
    end
    -- Pause menu / Options screens rebuild the battle HUD (the option HUD window shows a preview HUD): every cached
    -- text may be freed while we are paused -> no GUI call at all until unpaused, then resolve everything again.
    if not _G.TrainingModeActive or _G.TrainingGamePaused or _G.NativeOptionsWindowOpen then
        -- NO GUI writes here. The "controls are still alive on the first paused frame" assumption failed
        -- again (set_Message AV 31/08 08:03, at window open): the cache can be stale before we ever see the
        -- flag. Our window shows no HUD preview (UseBattleHudBG=false) and the real pause menu is covered by
        -- the OpenMenu pre-hook restore, so silently dropping the caches is enough.
        if panel or timer_ctrls then
            panel = nil; orig = nil; timer_ctrls = nil; timer_state = {}; vis_applied = nil; sides_hidden = false; applied = {}
        end
        return
    end
    if not owner and not restore_pending and vis_request == nil then return end
    if not panel then
        if tick < next_resolve then return end
        next_resolve = tick + 60
        local ok, p, o = pcall(resolve_panel)
        if ok and p then panel, orig = p, o else return end
    end
    if restore_pending then
        pcall(restore_panel); restore_pending = false
        -- give the timer back unconditionally: the "shown" flag is lost when the release happened while paused /
        -- with a native window open (c_infinite stayed force-hidden -> no infinity sign, 30/08)
        pcall(function()
            if not timer_ctrls then timer_ctrls = resolve_timer() end
            if timer_ctrls then timer_state.shown = true end
            timer_value = nil
            apply_timer()
        end)
    end
    if owner then
        local ok = pcall(apply_panel)
        if not ok then panel = nil; orig = nil; applied = {} end   -- HUD rebuilt -> re-resolve
        local okt = pcall(apply_timer)
        if not okt then timer_ctrls = nil; timer_state = {} end
    else
        pcall(apply_visibility)
    end
end

re.on_pre_application_entry("LateUpdateBehavior", function() pcall(game_thread_tick) end)

-- NEVER touch GUI objects from re.on_script_reset (reset thread). State just dies; the
-- game re-pushes its own panel values on the next hit and the fresh module resolves anew.
re.on_script_reset(function()
    owner = nil; _G.NativeHud_Owner = nil; timer_value = nil
end)

_G.NativeHud = M  -- live instance for other scripts / agent probes
return M
