-- ============================================================
-- NativeDialog — the game's own two-column "Control Settings" dialog (app.UIFlowKeyConfig.Menu, agent
-- KeyConfigBattleMenuFG) opened with OUR content: a CATEGORY spin on the left (the dialog's "Button Preset" spin),
-- our ROWS in the scrollable list on the right (the dialog's SettingParam list). Nothing is drawn by us.
-- Dissected 31/08/2026 (docs/CHANTIER_DV_NATIVE.md). Same technique as NativeOptions / NativeShortcuts: the game's
-- flow runs unchanged, our hooks feed it our data while a dialog of ours is up and block its persistence.
--
--   local ND = require("func/NativeDialog")
--   ND.define("dv", "Distance Viewer", pages)   -- pages = NativePauseMenu page objects (items: spin/button/value/label)
--   ND.open("dv")                                -- from a pause-menu row (keep_open = true): the dialog stacks on the menu
--
-- ROWS = CLONES OF THE GAME'S OWN ARRAY (rewritten 31/08 after the crash of the first version). We never fabricate
-- app.UIKeyConfig.SettingParam instances: half-built params (ints only, Name/Icon/Comment left null) made
-- Param.MakeListIndexToParamIndex throw a NullReferenceException inside SetSettingParams, the following
-- UpdateListSetting threw IndexOutOfRange, and the game died a few frames later. Instead we take the array the game
-- itself built (post-hook on GetBattleSettingParams, fallback = the Param.SettingParams field) and hand the flow a
-- CloneSettingParams() copy of it — 20 real, fully built params — one clone per category. Only the four TEXT getters
-- (GetName / GetIcon / GetInputIcon / GetComment) are overridden, never the params' contents.
-- The game keeps its own row filter: of the 20 params only some end up in the list (Param.ListIndexToParamIndex,
-- list row -> param index, unused entries negative). Our items are therefore mapped onto the VISIBLE rows only,
-- rebuilt after InitListSetting and after every category change; a clone param with no item answers "" and never
-- falls through to the original (that would print the player's real control names). The visible-row count is logged
-- (ND._log()) whenever a page has more items than rows, so the real cap can be read off a run.
--
-- Rows are BUTTONS to select (Wael 31/08): Confirm on a "spin" item = next option (cycle), on a "button" item = its
-- action (keep_open = false -> the dialog AND the pause menu close, e.g. teleports); "value"/"label" = text only.
-- The decide is taken over in UIAgent.InputDecide while our list has the focus, so the game never starts its key
-- capture; its saves (SaveSettingParams, SaveOther, Revert/Initialize/Copy, KPI) are skipped while ours is up.
-- Nothing of the player's controller config is read for display or written.
-- ============================================================
-- managed strings handed to the game: the game releases what GetMessage returns, and Lua releases its own ref when
-- the wrapper dies -> two releases for one ref = random text crashes (03/09). One extra ref per string for the game.
local function managed_string(s)                       -- a fresh string per call, one ref for the game
    local m = sdk.create_managed_string(s)
    pcall(function() m:add_ref() end)                      -- Lua's own ref goes away with the wrapper; this one is the game's
    return m
end
local M = {}
local NO = require("func/NativeOptions")

local dialogs = {}          -- name -> { title, pages }
local active = nil          -- dialog shown right now (nil = the game's real dialog / none)
local P = nil               -- its UIFlowKeyConfig.Menu.Param
local handle = nil          -- IUIFlowHandle
local pending = nil         -- name to open at the next game-thread tick
local cat = 0               -- current category index (0-based)
local rows_by_addr = {}     -- SettingParam address -> item (visible rows of the current category only)
local clone_addrs = {}      -- every param address of every clone -> true (blank text when it carries no item)
local arrays = {}           -- category -> cloned SettingParam[], kept alive while open
local src_array = nil       -- the game's own array, source of every clone
local tick = 0
local close_all_req = false
M.debug = true              -- call log (M._log()) until the decide path is confirmed in game
local log = {}
local function dlog(s) if M.debug and #log < 300 then log[#log + 1] = tick .. " " .. s end end
function M._log() return log end
function M._state() return { active = active and active.title, cat = cat, pending = pending, has_P = P ~= nil } end

function M.define(name, title, pages) dialogs[name] = { title = title, pages = pages } end
function M.open(name) if dialogs[name] and not active then pending = name end end
function M.is_open() return active ~= nil end

-- ---------- pcall payloads (no closure allocated per call) ----------
local function m_call(m, obj, ...) return m:call(obj, ...) end
local function o_call(o, name, ...) return o:call(name, ...) end
local function o_get(o, name) return o:get_field(name) end
local function o_set(o, name, v) o:set_field(name, v) end
local function o_index(o, i) return o[i] end
local function o_addr(o) return o:get_address() end
local function o_addref(o) o:add_ref() end
local function o_msg(t, s) t:call("set_Message", s) end
local function o_elem(o, i) return o:get_element(i) end
local function o_dword(o, off) return o:read_dword(off) end

-- ---------- rows ----------
local function opts_of(it)
    local o = it.options
    if type(o) == "function" then local ok, v = pcall(o); o = (ok and type(v) == "table") and v or {} end
    return o or {}
end
local function text_of(t) if type(t) == "function" then local ok, v = pcall(t); return ok and tostring(v or "") or "?" end; return tostring(t or "") end
local function row_title(it) return text_of(it.title) end
local function row_value(it)
    if it.kind ~= "spin" then return "" end
    local o = opts_of(it)[(it.get and it.get() or 0) + 1]
    if type(o) == "function" then local ok, v = pcall(o); o = ok and v or "?" end
    return (o ~= nil) and tostring(o) or ""
end
local function row_decide(it)
    if it.kind == "spin" and it.set then
        local n = #opts_of(it); if n == 0 then return end
        pcall(it.set, ((it.get and it.get() or 0) + 1) % n)
        return "refresh"
    elseif it.kind == "button" and it.on_decide then
        pcall(it.on_decide)
        return it.keep_open and "refresh" or "close_all"
    end
end
local function category_count(d) return math.max(1, #d.pages) end
local function category_title(d, ci) local p = d.pages[ci + 1]; return p and text_of(p.title) or "-" end
local function page_items(d, ci) local p = d.pages[ci + 1]; return (p and p.items) or {} end

-- ---------- type / method handles ----------
local PARAM = sdk.find_type_definition("app.UIFlowKeyConfig.Menu.Param")
local SP = sdk.find_type_definition("app.UIKeyConfig.SettingParam")
local AGENT = sdk.find_type_definition("app.UIAgent")
-- "Name" or "Name(TypeA, TypeB)" or "Name()" -> the matching overload
local function find_method(td, spec)
    if not td then return nil end
    local name, params = spec:match("^([^%(]+)%((.*)%)$")
    if not name then name = spec end
    local want = nil
    if params then want = {}; for p in params:gmatch("[^,]+") do want[#want + 1] = p:match("^%s*(.-)%s*$") end end
    for _, m in ipairs(td:get_methods()) do
        if m:get_name() == name then
            if not want then return m end
            local pts = m:get_param_types()
            if #pts == #want then
                local same = true
                for i, p in ipairs(pts) do if p:get_full_name() ~= want[i] then same = false; break end end
                if same then return m end
            end
        end
    end
    return nil
end
-- resolved once: every call WE initiate goes through these (no overload ambiguity at call time)
local M_CLONE       = find_method(PARAM, "CloneSettingParams(app.UIKeyConfig.SettingParam[])")
local M_SET_PARAMS  = find_method(PARAM, "SetSettingParams(app.UIKeyConfig.SettingParam[])")
local M_UPDATE_LIST = find_method(PARAM, "UpdateListSetting()")
local M_UPDATE_SPIN = find_method(PARAM, "UpdateTextSpinPreset()")
if not (M_CLONE and M_SET_PARAMS and M_UPDATE_LIST and M_UPDATE_SPIN) then dlog("MISSING Param method(s)") end

-- ---------- managed array helpers ----------
local function arr_len(a)
    if not a then return 0 end
    local ok, n = pcall(o_call, a, "get_Length")
    return (ok and type(n) == "number") and n or 0
end
-- System.Int32[] : this build returns nothing usable from Array.GetValue (probe 31/08 -> all nil), so try every
-- route and remember the one that worked. Any value outside a sane range is treated as unreadable.
local int_mode = nil
local function int_ok(v) return type(v) == "number" and v == math.floor(v) and v > -1000000 and v < 1000000 end
local function unbox(o)
    local ok, v = pcall(o_get, o, "mValue"); if ok and int_ok(v) then return v, "mValue" end
    ok, v = pcall(o_get, o, "m_value"); if ok and int_ok(v) then return v, "m_value" end
    ok, v = pcall(o_dword, o, 0x10); if ok and int_ok(v) then return v, "box+0x10" end
    return nil
end
local function arr_int(a, i)
    if not a then return nil end
    local ok, v = pcall(o_index, a, i)
    if ok and int_ok(v) then int_mode = int_mode or "index"; return v end
    if ok and type(v) == "userdata" then local n, how = unbox(v); if n then int_mode = int_mode or ("index/" .. how); return n end end
    ok, v = pcall(o_elem, a, i)
    if ok and int_ok(v) then int_mode = int_mode or "get_element"; return v end
    if ok and type(v) == "userdata" then local n, how = unbox(v); if n then int_mode = int_mode or ("get_element/" .. how); return n end end
    ok, v = pcall(o_call, a, "GetValue", i)
    if ok and int_ok(v) then int_mode = int_mode or "GetValue"; return v end
    if ok and type(v) == "userdata" then local n, how = unbox(v); if n then int_mode = int_mode or ("GetValue/" .. how); return n end end
    ok, v = pcall(o_dword, a, 0x20 + 4 * i)   -- raw element data of a RE Engine array
    if ok and int_ok(v) then int_mode = int_mode or "raw+0x20"; return v end
    return nil
end

-- ---------- clones of the game's array ----------
local function register_clone(arr)
    for i = 0, arr_len(arr) - 1 do
        local ok, sp = pcall(o_call, arr, "GetValue", i)
        if ok and sp then
            local ok2, a = pcall(o_addr, sp)
            if ok2 and a then clone_addrs[a] = true end
        end
    end
end
-- the game's own array: whatever GetBattleSettingParams handed us, else the Param field the flow filled in
local function ensure_source()
    if src_array then return true end
    if not P then return false end
    local ok, a = pcall(o_get, P, "SettingParams")
    if ok and a and arr_len(a) > 0 then
        src_array = a; pcall(o_addref, a)
        dlog("source <- P.SettingParams len=" .. arr_len(a))
        return true
    end
    dlog("no source array")
    return false
end
-- One clone per category, all cloned from the same real array: same contents, so the game's row filter keeps the
-- same rows for every category. Kept alive with add_ref (never released: balancing a ref the flow also holds has
-- cost crashes before; a handful of 20-entry arrays per open is a bounded, deliberate leak).
local function clone_for(ci)
    if arrays[ci] then return arrays[ci] end
    if not (P and M_CLONE and ensure_source()) then return nil end
    local ok, c = pcall(m_call, M_CLONE, P, src_array)
    if not ok or not c then dlog("CloneSettingParams failed: " .. tostring(c)); return nil end
    pcall(o_addref, c)
    register_clone(c)
    arrays[ci] = c
    dlog("clone cat " .. ci .. " len=" .. arr_len(c))
    return c
end

-- ---------- item <-> visible row mapping ----------
-- ListIndexToParamIndex[j] = param index shown on list row j (negative = row unused). Item j+1 goes on row j.
local function remap(why)
    rows_by_addr = {}
    if not (active and P) then return end
    local arr = arrays[cat]
    if not arr then dlog("remap " .. why .. ": no array for cat " .. cat); return end
    local items = page_items(active, cat)
    local alen = arr_len(arr)
    local map = nil
    local okm, m = pcall(o_get, P, "ListIndexToParamIndex")
    if okm then map = m end
    local n = arr_len(map)
    local order, dump, read = {}, {}, 0
    for j = 0, n - 1 do
        local v = arr_int(map, j)
        dump[#dump + 1] = tostring(v)
        if v then read = read + 1 end
        if v and v >= 0 and v < alen then order[#order + 1] = { j, v } end
    end
    if read == 0 then                        -- map unreadable in this build: assume row j -> param j
        for j = 0, math.min(alen, 20) - 1 do order[#order + 1] = { j, j } end
        dlog("remap " .. why .. ": map unreadable [" .. table.concat(dump, ",") .. "] -> identity")
    else
        dlog("remap " .. why .. ": mode=" .. tostring(int_mode) .. " map=" .. table.concat(dump, ","))
    end
    local mapped = 0
    for _, e in ipairs(order) do
        local it = items[e[1] + 1]
        if it then
            local ok, sp = pcall(o_call, arr, "GetValue", e[2])
            if ok and sp then
                local ok2, a = pcall(o_addr, sp)
                if ok2 and a then rows_by_addr[a] = it; mapped = mapped + 1 end
            end
        end
    end
    dlog("remap " .. why .. ": cat " .. cat .. " visible=" .. #order .. " mapped=" .. mapped .. " items=" .. #items)
    if #items > #order then dlog("VISIBLE CAP: cat " .. cat .. " rows=" .. #order .. " items=" .. #items) end
end

-- ---------- hooks ----------
local function hook(td, spec, pre, post)
    local m = find_method(td, spec); if not m then dlog("NO METHOD " .. spec); return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        st.str = nil; st.ret = nil; st.mine = nil
        if pre and pre(args, st) then return sdk.PreHookResult.SKIP_ORIGINAL end
    end, function(rv)
        local st = thread.get_hook_storage()
        if post then post(st, rv) end
        if st.str then return sdk.to_ptr(managed_string(st.str)) end
        if st.ret ~= nil then return sdk.to_ptr(st.ret) end
        return rv
    end)
end
local function this_of(args) local ok, o = pcall(sdk.to_managed_object, args[2]); return ok and o or nil end
local function ours(args) return active ~= nil and P ~= nil and sdk.to_int64(args[2]) == P:get_address() end
local function mine_pre(args, st) if ours(args) then st.mine = true end end

-- row texts: an item's text for a mapped row, "" for any other param of a clone (never the player's real config)
hook(SP, "GetName(app.AppDefine.GameMode)", function(args, st)
    if not active then return end
    local a = sdk.to_int64(args[2]); local it = rows_by_addr[a]
    if it then st.str = row_title(it); return true end
    if clone_addrs[a] then st.str = ""; return true end
end)
hook(SP, "GetIcon()", function(args, st)
    if not active then return end
    local a = sdk.to_int64(args[2])
    if rows_by_addr[a] or clone_addrs[a] then st.str = ""; return true end
end)
hook(SP, "GetInputIcon()", function(args, st)
    if not active then return end
    local a = sdk.to_int64(args[2]); local it = rows_by_addr[a]
    if it then st.str = row_value(it); return true end
    if clone_addrs[a] then st.str = ""; return true end
end)
hook(SP, "GetComment()", function(args, st)
    if not active then return end
    local a = sdk.to_int64(args[2]); local it = rows_by_addr[a]
    if it then st.str = text_of(it.guide); return true end
    if clone_addrs[a] then st.str = ""; return true end
end)

-- The array the flow builds is the array we clone: the original RUNS (post-hook), we only swap the result for our
-- copy. No re-entrancy guard, no argument marshalling, and the game's own construction path stays intact.
local function clone_post(st, rv)
    if not st.mine or not P then return end
    local ok, real = pcall(sdk.to_managed_object, rv)
    if not ok or not real or arr_len(real) == 0 then dlog("GetBattleSettingParams: no array"); return end
    if not src_array then src_array = real; pcall(o_addref, real); dlog("source <- GetBattleSettingParams len=" .. arr_len(real)) end
    local arr = clone_for(cat)
    if arr then dlog("GetBattleSettingParams -> clone cat " .. cat); st.ret = arr end
end
hook(PARAM, "GetBattleSettingParams(System.Int32)", mine_pre, clone_post)
hook(PARAM, "GetBattleSettingParams(System.Int32, app.UIKeyConfig.TargetDevice)", mine_pre, clone_post)

-- The list is filled: install our clone if the getter above never fired, then map our items on the visible rows.
local function init_list_post(st, rv)
    if not st.mine or not P then return end
    if not arrays[cat] then
        local arr = clone_for(cat)
        if not arr then dlog("InitListSetting: no clone"); return end
        local ok1, e1 = pcall(m_call, M_SET_PARAMS, P, arr)
        if not ok1 then dlog("InitListSetting SetSettingParams failed: " .. tostring(e1)); return end
        local ok2, e2 = pcall(m_call, M_UPDATE_LIST, P)
        if not ok2 then dlog("InitListSetting UpdateListSetting failed: " .. tostring(e2)); return end
    end
    remap("InitListSetting")
end
hook(PARAM, "InitListSetting()", mine_pre, init_list_post)

-- the "Button Preset" spin = our category spin
hook(PARAM, "UpdateTextSpinPreset()", function(args, st)
    if not ours(args) then return end
    local ok, t = pcall(o_get, P, "TextSpinPreset")
    if ok and t then pcall(o_msg, t, category_title(active, cat)) end
    return true
end)
-- Category change. Three game calls in a row, each on its own: the crash of 31/08 was a second call made after the
-- first had already thrown, so a failure here stops the sequence dead.
hook(PARAM, "SpinPresetChanged()", function(args, st)
    if not ours(args) then return end
    local n = 0
    local oks, spin = pcall(o_get, P, "PartsSpinPreset")
    if oks and spin then
        local okn, v = pcall(o_get, spin, "_Num")
        if okn and type(v) == "number" then n = v end
    end
    cat = math.max(0, math.min(category_count(active) - 1, n))
    dlog("SpinPresetChanged -> " .. cat)
    local arr = clone_for(cat)
    if not arr then dlog("SpinPresetChanged: no clone for cat " .. cat); return true end
    local ok1, e1 = pcall(m_call, M_SET_PARAMS, P, arr)
    if not ok1 then dlog("SetSettingParams failed: " .. tostring(e1)); return true end
    local ok2, e2 = pcall(m_call, M_UPDATE_LIST, P)
    if not ok2 then dlog("UpdateListSetting failed: " .. tostring(e2)); return true end
    remap("SpinPresetChanged")
    local ok3, e3 = pcall(m_call, M_UPDATE_SPIN, P)
    if not ok3 then dlog("UpdateTextSpinPreset failed: " .. tostring(e3)) end
    return true
end)
-- the other three spins: blank text, changes ignored
for _, n in ipairs({ "UpdateTextSpinMode", "UpdateTextSpinNegativeEdge", "UpdateTextSpinLowStickSensitivity" }) do
    local field = n:gsub("^UpdateText", "Text")
    hook(PARAM, n .. "()", function(args, st)
        if not ours(args) then return end
        local ok, t = pcall(o_get, P, field)
        if ok and t then pcall(o_msg, t, "") end
        return true
    end)
end
for _, n in ipairs({ "SpinModeChanged()", "SpinNegativeEdgeChanged()", "SpinLowStickSensitivityChanged()" }) do
    hook(PARAM, n, function(args, st) if ours(args) then return true end end)
end
-- left list (Edit / Restore / Test / Copy): inert while ours is up
hook(PARAM, "SetLeftListItemId(app.UIKeyConfig.ListItemId)", function(args, st) if ours(args) then dlog("SetLeftListItemId blocked"); return true end end)
-- never bind a key on our rows; never persist anything
hook(PARAM, "CanNotKeyBind()", function(args, st) if ours(args) then st.ret = 1; return true end end)
for _, n in ipairs({ "SaveSettingParams(System.Boolean)", "SaveOther(app.UIFlowKeyConfig.Menu.ChangeFlag)", "PostKpiLogSave()", "PostKpiLogInitialize()", "RevertSettings()", "InitializeSettings()", "CopySettings(System.Int32)" }) do
    hook(PARAM, n, function(args, st) if ours(args) then dlog(n .. " blocked"); return true end end)
end
hook(PARAM, "CheckChanges()", function(args, st) if ours(args) then st.ret = 0; return true end end)
hook(PARAM, "CheckChanges(System.Boolean)", function(args, st) if ours(args) then st.ret = 0; return true end end)
hook(PARAM, "EqualSettings()", function(args, st) if ours(args) then st.ret = 1; return true end end)
hook(PARAM, "CheckChangeNegativeEdgeFlags()", function(args, st) if ours(args) then st.ret = 0; return true end end)
hook(PARAM, "CheckChangeLowStickSensitivityFlags()", function(args, st) if ours(args) then st.ret = 0; return true end end)
-- trace only (confirms the decide path in game)
hook(PARAM, "SoundDecide()", function(args, st) if ours(args) then dlog("SoundDecide") end end)

-- the decide, taken over before the game's flow sees it: right list focused -> our row's action
-- The selected param comes from the game itself (GetSelectedSettingParam); the list index is only a fallback.
local function selected_item()
    if not P then return nil, -1, -1 end
    local it, idx, pidx = nil, -1, -1
    local oks, sp = pcall(o_call, P, "GetSelectedSettingParam")
    if oks and sp then
        local oka, a = pcall(o_addr, sp)
        if oka and a then it = rows_by_addr[a] end
    end
    local okl, list = pcall(o_get, P, "PartsListSetting")
    if okl and list then
        local oki, v = pcall(o_call, list, "get_SelectedIndex")
        if oki and type(v) == "number" then idx = v end
    end
    if not it and idx >= 0 then
        local arr = arrays[cat]
        if arr then
            local okm, map = pcall(o_get, P, "ListIndexToParamIndex")
            local v = (okm and map) and arr_int(map, idx) or nil
            pidx = (v and v >= 0 and v < arr_len(arr)) and v or idx
            local okv, sp2 = pcall(o_call, arr, "GetValue", pidx)
            if okv and sp2 then
                local oka2, a2 = pcall(o_addr, sp2)
                if oka2 and a2 then it = rows_by_addr[a2] end
            end
        end
    end
    return it, idx, pidx
end
hook(AGENT, "InputDecide(app.InputDigitalFlag)", function(args, st)
    if not active or not P then return end
    local oka, agent = pcall(o_get, P, "<Agent>k__BackingField")
    if not oka or not agent or sdk.to_int64(args[2]) ~= agent:get_address() then return end
    local left = -1
    local okf, v = pcall(o_call, P, "GetFocusLeftGroupItemId")
    if okf then
        if type(v) == "number" then left = v else dlog("left focus type=" .. type(v)) end
    end
    dlog("InputDecide left=" .. tostring(left))
    if left ~= -1 and left ~= 4 then return end          -- a left spin has the focus: the game handles it (no-op for us)
    if left == 4 then return true end                     -- left button list: inert
    local it, idx, pidx = selected_item()
    dlog("decide row " .. tostring(idx) .. "/" .. tostring(pidx) .. " -> " .. (it and row_title(it) or "?"))
    if it then
        local r = row_decide(it)
        if r == "refresh" then
            local ok, e = pcall(m_call, M_UPDATE_LIST, P)
            if not ok then dlog("refresh UpdateListSetting failed: " .. tostring(e)) end
        elseif r == "close_all" then close_all_req = true end
    end
    return true
end)

-- title + spin range once the dialog is shown
local function find(c, name, d)
    if not c or d > 8 then return nil end
    if tostring(c:call("get_Name")) == name then return c end
    return find(c:call("get_Child"), name, d + 1) or find(c:call("get_Next"), name, d)
end
local function head_text(a) return find(a:call("get_ControlMain"), "e_text_hdg", 0) end
hook(PARAM, "ShowedObject(app.UIFlowCommon.ShowObject)", function(args, st)
    if not ours(args) then return end
    dlog("ShowedObject")
    local oka, a = pcall(o_get, P, "<Agent>k__BackingField")
    if oka and a then
        local okt, t = pcall(head_text, a)
        if okt and t then pcall(o_msg, t, text_of(active.title)) end
    end
    local oks, spin = pcall(o_get, P, "PartsSpinPreset")
    if oks and spin then
        pcall(o_set, spin, "<MinNum>k__BackingField", 0)
        pcall(o_set, spin, "<MaxNum>k__BackingField", category_count(active) - 1)
        pcall(o_set, spin, "_Num", cat)
    end
    local okp, sps = pcall(o_get, P, "SpinParams")
    if okp and sps then
        for i = 0, arr_len(sps) - 1 do
            local okv, sp = pcall(o_call, sps, "GetValue", i)
            if okv and sp then pcall(o_set, sp, "Disable", i ~= 1) end   -- 1 = Button Preset, our category spin
        end
    end
    local oku, e = pcall(m_call, M_UPDATE_SPIN, P)
    if not oku then dlog("ShowedObject UpdateTextSpinPreset failed: " .. tostring(e)) end
end)
hook(PARAM, "OnEnd()", function(args, st)
    if ours(args) then
        dlog("OnEnd")
        active = nil; P = nil; handle = nil
        rows_by_addr = {}; clone_addrs = {}; arrays = {}; src_array = nil
    end
end)
-- catch the Param the moment the flow creates it (Init runs before everything else)
hook(PARAM, "Init()", function(args, st)
    if pending == nil or active ~= nil then return end
    local p = this_of(args)
    if not p then dlog("Init: no Param, hijack dropped"); pending = nil; return end   -- else `active` would stick forever
    P = p; active = dialogs[pending]; pending = nil; cat = 0
    rows_by_addr = {}; clone_addrs = {}; arrays = {}; src_array = nil
    dlog("Init: hijacked for " .. tostring(active.title))
end)

-- ---------- game thread ----------
local START = find_method(sdk.find_type_definition("app.UIFlowKeyConfig.Menu"),
    "Start(app.AppDefine.GameMode, app.UIKeyConfig.Caller, nBattle.TEAM.ID, app.EConfigInputType, System.Int32, System.Boolean, System.Int32, app.UIKeyConfig.IBattleInputSetting)")
-- GameMode 1, Caller 2 = BattlePause, TEAM 0, input type 0, preset 0, saveInputType FALSE, 0, nil
local function start_flow() return START:call(nil, 1, 2, 0, 0, 0, false, 0, nil) end
local function end_handle(h) if not h:call("get_IsEnd") then h:call("End") end end
local open_at = nil
re.on_pre_application_entry("LateUpdateBehavior", function()
    tick = tick + 1
    if pending and not open_at and not active then
        if not START then dlog("no Start method"); pending = nil; return end
        open_at = tick + 2      -- the pause-menu decide that asked for us is still being processed
    elseif open_at and tick >= open_at then
        open_at = nil
        local ok, h = pcall(start_flow)
        if ok then handle = h; dlog("Start ok") else dlog("Start failed: " .. tostring(h)); pending = nil end
    end
    if close_all_req and active then
        close_all_req = false
        if handle then pcall(end_handle, handle) end
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm then pcall(o_call, tm, "RequestCloseMenu") end
    end
end)

_G.NativeDialog = M
return M
