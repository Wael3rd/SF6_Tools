-- ============================================================
-- NativePauseMenu — our own rows inside the game's training PAUSE menu (Basic Settings tab), through the game's
-- official API app.training.TrainingManager.AddDynamicMenu(TrainingFuncType.DYNAMIC, TrainingMenuData, Action).
-- Nothing is drawn by us: the game builds the row (spin with arrows, guide text, focus, pad navigation).
--
--   local PM = require("func/NativePauseMenu")
--   PM.spin("Training mode", "Which training script drives the dummy.", { "DISABLED", "HIT CONFIRM" },
--           function() return current_index end,          -- 0-based
--           function(i) ... end)                            -- 0-based, called on the game thread when it changes
--   PM.button("Hit Confirm settings", "Open the Hit Confirm window.", function() NativeOptions.open("Hit Confirm") end)
--   PM.button(title, guide, on_decide, keep_open, in_tab)  -- in_tab = true: the row is ALSO duplicated into our own
--   9th tab "SF6 Tools" of the pause menu (validated 31/08 by Wael: title in the tab strip, page dot, focus, decide).
--
--   PAGES = our own extra tabs (one tab per page, appended after the game's 8 + "SF6 Tools"):
--   local pg = PM.page("Distance Viewer", "Distance Viewer settings.")
--   pg:spin(title, guide, {"A","B"}, get, set, capacity)  -- get -> 0-based index, set(i). options may be a FUNCTION
--                                                     -- returning the current list (evaluated live); capacity = max
--                                                     -- option count then (row built once). Any title may be a
--                                                     -- function: re-evaluated each time the pause menu opens.
--   pg:toggle(title, guide, get, set)                  -- Off/On, booleans
--   pg:number(title, guide, min, max, step, get, set, fmt)  -- real values, shown with fmt (default "%g")
--   pg:button(title, guide, on_decide, keep_open)      -- action on Confirm
--   pg:value(title, guide, fn)                         -- read-only row, fn() -> text (evaluated when the menu lays it out)
--   pg:label(title, guide)                             -- static text row
--   Keep a page <= 13 rows (the game's own tabs never exceed 13; the row pool is 20).
--
-- How the game talks to a DYNAMIC row (measured 30/08/2026): TrainingMenuFunc.ViewUpdate(param, data, i) is called
-- per row (=> we know which of our rows is being processed), then GetOptionText(ftype) / GetOptionIndex(ftype,
-- wanted, ftype) for spins, Function(ftype, param, viewData, value) on decide / change. All DYNAMIC rows share
-- FuncType 345, so the row is identified by its TrainingMenuData address (ViewUpdate / viewData.Data).
-- Texts are fake GUIDs resolved by NativeOptions' hMsg hook.
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
local DYN = 345           -- app.training.TrainingFuncType.DYNAMIC
local TAB = 1             -- TrainingFuncType.STANDARD = the "Basic Settings" tab

local items = {}          -- ordered: { kind, title, guide, options, get, set, on_decide, data (TrainingMenuData), gkey }
local by_guid = {}        -- title-GUID key -> item (AddDynamicMenu CLONES the data: addresses cannot identify our rows)
local msg_off = nil
local function guid_key(d)
    msg_off = msg_off or d:get_type_definition():get_field("_MessageID"):get_offset_from_base()
    return string.format("%016X%016X", d:read_qword(msg_off), d:read_qword(msg_off + 8))
end
local current = nil       -- item being laid out (from ViewUpdate)
local registered = false
local still_there         -- forward (defined below, used by register)

function M.spin(title, guide, options, get, set)
    items[#items + 1] = { kind = "spin", title = title, guide = guide, options = options, get = get, set = set }
end
-- keep_open = true: the pause menu stays up after the decide (for actions that open another game menu on top)
function M.button(title, guide, on_decide, keep_open, in_tab)
    items[#items + 1] = { kind = "button", title = title, guide = guide, on_decide = on_decide, keep_open = keep_open == true, in_tab = in_tab == true }
end

-- ---------- pages: our own tabs of the pause menu ----------
-- A page = one extra TrainingMenuData tab whose _ChildData are our row objects (no AddDynamicMenu: the tab is ours).
-- pages[1] is the built-in "SF6 Tools" tab: it holds the in_tab rows registered above in Basic Settings (same objects).
local TAB_TITLE, TAB_GUIDE = "SF6 Tools", "SF6 Tools training scripts."
local pages = { { title = TAB_TITLE, guide = TAB_GUIDE, items = {}, builtin = true } }
local Page = {}; Page.__index = Page
-- opts.tab = false: the page is only an item container (e.g. a NativeDialog category), no tab is installed
function M.page(title, guide, opts)
    local p = setmetatable({ title = title, guide = guide, items = {}, no_tab = (opts and opts.tab == false) }, Page)
    pages[#pages + 1] = p
    return p
end
-- a button row in our "SF6 Tools" tab only (not in Basic Settings)
function M.tab_button(title, guide, on_decide, keep_open)
    pages[1].items[#pages[1].items + 1] = { kind = "button", title = title, guide = guide, on_decide = on_decide, keep_open = keep_open == true }
end
local function page_item(p, it) p.items[#p.items + 1] = it; return it end
function Page:spin(title, guide, options, get, set, capacity)
    return page_item(self, { kind = "spin", title = title, guide = guide, options = options, get = get, set = set, capacity = capacity })
end
function Page:toggle(title, guide, get, set)
    return page_item(self, { kind = "spin", title = title, guide = guide, options = { "Off", "On" },
        get = function() return get() and 1 or 0 end, set = function(i) set(i == 1) end })
end
function Page:number(title, guide, min, max, step, get, set, fmt)
    local values, names = {}, {}
    local v = min
    while v <= max + 1e-9 do values[#values + 1] = v; names[#names + 1] = string.format(fmt or "%g", v); v = v + step end
    local function index_of(x)   -- closest listed value
        local best, bd = 0, math.huge
        for i, val in ipairs(values) do local d = math.abs(val - (tonumber(x) or min)); if d < bd then best, bd = i - 1, d end end
        return best
    end
    return page_item(self, { kind = "spin", title = title, guide = guide, options = names,
        get = function() return index_of(get()) end, set = function(i) set(values[i + 1]) end })
end
function Page:button(title, guide, on_decide, keep_open)
    return page_item(self, { kind = "button", title = title, guide = guide, on_decide = on_decide, keep_open = keep_open == true })
end
-- read-only value: a one-option spin whose text comes from fn() (GetOptionText is answered live by our hook)
function Page:value(title, guide, fn)
    return page_item(self, { kind = "spin", title = title, guide = guide, options = { fn }, get = function() return 0 end })
end
function Page:label(title, guide)
    return page_item(self, { kind = "button", title = title, guide = guide, keep_open = true })
end

-- ---------- building ----------
local function text_of(t) if type(t) == "function" then local ok, v = pcall(t); return ok and tostring(v or "") or "?" end; return tostring(t or "") end
local function opts_of(item)
    local o = item.options
    if type(o) == "function" then local ok, v = pcall(o); o = (ok and type(v) == "table") and v or {} end
    return o or {}
end
local function make_data(item)
    local d = sdk.create_instance("app.training.TrainingMenuData")
    d._Type = (item.kind == "spin") and 1 or 0          -- ItemType.SPIN / TEXT_ONLY
    d._FuncType = DYN; d.IsEnabled = true; d._Interval = 1; d._Interval_Option = 1
    d._GuidIcon = -1; d._GuidAddIcon = -1; d.VisibleCase = 0
    item.title_guid = NO.message_guid(text_of(item.title))
    item.guide_guid = NO.message_guid(text_of(item.guide))
    NO.set_guid(d, "_MessageID", item.title_guid)
    NO.set_guid(d, "_GuideMessage", item.guide_guid)
    if item.kind == "spin" then
        -- option slots: the texts are answered live by our GetOptionText hook, these are placeholders
        local n = math.max(1, item.capacity or #opts_of(item))
        local arr = sdk.create_managed_array("app.training.TrainingMenuData", n)
        for i = 1, n do
            local o = sdk.create_instance("app.training.TrainingMenuData")
            o._Type = 0; o._FuncType = DYN; o.IsEnabled = true; o._Interval = 1; o._Interval_Option = 1; o._GuidIcon = -1; o._GuidAddIcon = -1
            NO.set_guid(o, "_MessageID", NO.message_guid(""))
            arr:call("SetValue", o, i - 1)
        end
        d._ChildData = arr
    end
    pcall(function() d:add_ref() end)   -- the game keeps it in its arrays: it must outlive this Lua state
    return d
end

-- AddDynamicMenu stores DynamicData{ChildData=clone of our data} in the tab's DynamicChildData list (measured).
-- Rows left by a previous Lua state (script reload) have no hooks answering for them any more: drop them.
local function tab_dynamic_list(tm, tab_index)
    local tab = tm:get_field("_UIData"):call("get_MenuData"):call("GetValue", tab_index)
    return tab and tab:get_field("DynamicChildData")
end
local function purge_stale(tm)
    return pcall(function()
        local arr = tm:get_field("_UIData"):call("get_MenuData")
        for t = 0, arr:call("get_Length") - 1 do
            local dl = tab_dynamic_list(tm, t)
            if dl then
                local i = dl:call("get_Count") - 1
                while i >= 0 do
                    local dd = dl:call("get_Item", i)
                    local cd = dd and dd:get_field("ChildData")
                    if cd and cd:get_field("_FuncType") == DYN and not by_guid[guid_key(cd)] then dl:call("RemoveAt", i) end
                    i = i - 1
                end
            end
        end
    end)
end

local function register()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager"); if not tm then return false end
    local m = tm:get_type_definition():get_method("AddDynamicMenu"); if not m then return false end
    for _, it in ipairs(items) do
        if not it.data then it.data = make_data(it); it.gkey = guid_key(it.data); by_guid[it.gkey] = it end
    end
    purge_stale(tm)                       -- old copies of ours (reload) and never-answered rows
    if still_there() then registered = true; return true end
    for _, it in ipairs(items) do m:call(tm, TAB, it.data, nil) end
    registered = true
    return true
end

-- our rows still registered? (the game may rebuild its dynamic menus)
still_there = function()
    local ok, res = pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local dl = tab_dynamic_list(tm, 0)
        local found = 0
        for i = 0, dl:call("get_Count") - 1 do
            local dd = dl:call("get_Item", i); local cd = dd and dd:get_field("ChildData")
            if cd and cd:get_field("_FuncType") == DYN and by_guid[guid_key(cd)] then found = found + 1 end
        end
        return found >= #items
    end)
    return ok and res
end

-- ---------- hooks (game thread: the menu logic runs in the UI flow update) ----------
local TMF = sdk.find_type_definition("app.training.TrainingMenuFunc")
local function ft(args) return sdk.to_int64(args[3]) & 0xFFFFFFFF end
local function data_item(ptr)
    local ok, d = pcall(sdk.to_managed_object, ptr)
    if ok and d and d:get_field("_FuncType") == DYN then return by_guid[guid_key(d)] end
end
local function hook(name, pre)
    local m = TMF:get_method(name); if not m then return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        if pre(args, st) then return sdk.PreHookResult.SKIP_ORIGINAL end
    end, function(rv)
        local st = thread.get_hook_storage()
        if st.str then return sdk.to_ptr(managed_string(st.str)) end
        if st.ret ~= nil then return sdk.to_ptr(st.ret) end
        return rv
    end)
end
-- ViewUpdate(BaseParam, TrainingMenuData, int): remember which of our rows is being processed
sdk.hook(TMF:get_method("ViewUpdate"), function(args)
    local it = data_item(args[4]); if it then current = it end
end, function(rv) return rv end)
hook("GetIsActive", function(args, st) if ft(args) == DYN then st.ret = 1; return true end end)
hook("IsValueType", function(args, st) if ft(args) == DYN then st.ret = 0; return true end end)
hook("GetVisibleCase", function(args, st) if ft(args) == DYN then st.ret = 0; return true end end)
hook("IsChangedValue", function(args, st) if ft(args) == DYN then st.ret = 0; return true end end)
hook("GetOptionIndex", function(args, st)
    if ft(args) ~= DYN then return end
    local it = current
    local wanted = sdk.to_int64(args[4]) & 0xFFFFFFFF
    if it and it.kind == "spin" then
        local n = math.max(1, #opts_of(it))
        if wanted >= n then wanted = n - 1 end
        local cur = it.get and (it.get() or 0) or 0
        if wanted ~= cur and it.set then pcall(it.set, wanted) end
        st.ret = wanted
    else st.ret = 0 end
    return true
end)
hook("GetOptionText", function(args, st)
    if ft(args) ~= DYN then return end
    local it = current
    if it and it.kind == "spin" then
        local i = (it.get and it.get() or 0) + 1
        local o = opts_of(it)[i]
        if type(o) == "function" then local ok, t = pcall(o); o = ok and t or "?" end
        st.str = (o ~= nil) and tostring(o) or ""
    else st.str = "" end
    return true
end)
hook("GetOptionText2", function(args, st) if ft(args) == DYN then st.str = ""; return true end end)
-- Function(ftype, BaseParam, ViewData, value): decide on a button (1 = the game closes the menu), spin changes are
-- already applied through GetOptionIndex
hook("Function", function(args, st)
    if ft(args) ~= DYN then return end
    local it = nil
    pcall(function() local vd = sdk.to_managed_object(args[5]); local d = vd and vd:get_field("Data"); if d then it = by_guid[guid_key(d)] end end)
    it = it or current
    if it and it.kind == "button" and it.on_decide then pcall(it.on_decide); st.ret = it.keep_open and 0 or 1 else st.ret = 0 end
    return true
end)

-- ---------- our own tabs ----------
-- TrainingPauseMenuUserData._MenuData (TrainingMenuData[8], one per tab, _FuncType 1..8) is replaced by a longer
-- copy with one tab per page appended (FuncType DYNAMIC: our hooks answer for it). Installed with the menu closed
-- (rule 10); tabs left by a previous Lua state (also DYNAMIC, dead rows) are dropped, never stacked; reinstalled if
-- the game rebuilds its menu data. Validated 31/08 with one tab (tab strip, page dot, focus, decide).
local function page_rows(p, tm)
    local rows = {}
    if p.builtin then
        local dl = tab_dynamic_list(tm, TAB - 1)
        if dl then
            for i = 0, dl:call("get_Count") - 1 do
                local dd = dl:call("get_Item", i); local cd = dd and dd:get_field("ChildData")
                local it = cd and cd:get_field("_FuncType") == DYN and by_guid[guid_key(cd)]
                if it and it.in_tab then rows[#rows + 1] = cd end
            end
        end
    end
    for _, it in ipairs(p.items) do   -- the built-in tab's own rows (tab_button) and every other page's rows
        if not it.data then it.data = make_data(it); it.gkey = guid_key(it.data); by_guid[it.gkey] = it end
        rows[#rows + 1] = it.data
    end
    return rows
end
local function has_pages() for _, p in ipairs(pages) do if not p.no_tab and (#p.items > 0 or p.builtin) then return true end end; return false end
local function tabs_present(tm)
    local arr = tm:get_field("_UIData"):call("get_MenuData")
    local n = arr:call("get_Length")
    local want = {}
    for _, p in ipairs(pages) do if p.data then want[#want + 1] = p.data end end
    if #want == 0 then return false end
    if n < 8 + #want then return false end
    for k, d in ipairs(want) do
        local t = arr:call("GetValue", n - #want + k - 1)
        if not t or t:get_address() ~= d:get_address() then return false end
    end
    return true
end
local function install_tabs(tm)
    local ui = tm:get_field("_UIData")
    local arr = ui:call("get_MenuData")
    local n = arr:call("get_Length")
    local tab0 = arr:call("GetValue", 0)
    local empty_src = arr:call("GetValue", 1):get_field("DynamicChildData")
    local new_tabs = {}
    for _, p in ipairs(pages) do
        local rows = p.no_tab and {} or page_rows(p, tm)
        if #rows > 0 then
            local t = sdk.create_instance("app.training.TrainingMenuData")
            t._Type = tab0._Type
            t._FuncType = DYN; t.IsEnabled = true; t._Interval = 1; t._Interval_Option = 1
            t._GuidIcon = -1; t._GuidAddIcon = -1; t.VisibleCase = 0
            pcall(function() t.NextButton = tab0.NextButton; t.PrevButton = tab0.PrevButton end)
            p.title_guid = NO.message_guid(text_of(p.title))
            NO.set_guid(t, "_MessageID", p.title_guid)
            NO.set_guid(t, "_GuideMessage", NO.message_guid(text_of(p.guide)))
            local ra = sdk.create_managed_array("app.training.TrainingMenuData", #rows)
            for i, r in ipairs(rows) do ra:call("SetValue", r, i - 1) end
            t._ChildData = ra
            local empty = empty_src:call("GetRange", 0, 0)   -- an empty List<DynamicData> of the right type
            t.DynamicChildData = empty
            pcall(function() t:add_ref(); ra:add_ref(); empty:add_ref() end)
            p.data = t
            new_tabs[#new_tabs + 1] = t
        else
            p.data = nil
        end
    end
    if #new_tabs == 0 then return false end
    -- keep the game's 8 tabs; drop every DYNAMIC tab left at the end (ours, or a previous Lua state's)
    local keep = n
    while keep > 8 do
        local last = arr:call("GetValue", keep - 1)
        if last and last:get_field("_FuncType") == DYN then keep = keep - 1 else break end
    end
    local na = sdk.create_managed_array("app.training.TrainingMenuData", keep + #new_tabs)
    for i = 0, keep - 1 do na:call("SetValue", arr:call("GetValue", i), i) end
    for k, t in ipairs(new_tabs) do na:call("SetValue", t, keep + k - 1) end
    pcall(function() na:add_ref() end)
    ui._MenuData = na
    return true
end

-- ---------- list view fix ----------
-- The Basic Settings tab has 13 rows; with ours it is 14, and 14 rows end EXACTLY at the scroll view's bottom
-- (UIPartsGroupScroll: _ViewTop 37.5 + _ViewSize.h 805 = 842.5 = bottom of row 13) while the visual mask sits 20 px
-- higher -> the game never scrolls and our row is cut (31/08 screenshot). One row less in the view and the game's
-- own ScrollFocusItem scrolls to it (scroll bar included, verified 31/08); a 13-row tab still fits (782.5 = 782.5).
local VIEW_H_FIX = 745
local view_off = nil
local function fix_list_view()
    local mgr = sdk.get_managed_singleton("app.UIAgentManager")
    local list = mgr and mgr:get_field("_Entries"); if not list then return end
    for i = 0, list:call("get_Count") - 1 do
        local a = list:call("get_Item", i).Agent
        local go = a and a:call("get_GameObject")
        if go and tostring(go:call("get_Name")) == "ui11200" then
            local root = a:get_field("_RootItem")
            if root and root:get_type_definition():get_full_name() == "app.UIPartsGroupScroll" then
                view_off = view_off or root:get_type_definition():get_field("_ViewSize"):get_offset_from_base()
                if root:read_float(view_off + 4) > VIEW_H_FIX then root:write_float(view_off + 4, VIEW_H_FIX) end
            end
            return
        end
    end
end

-- ---------- dynamic titles ----------
-- Titles/guides given as functions are re-evaluated right before the game builds the menu (OpenMenu pre-hook,
-- game thread): the hMsg hook then resolves the GUIDs to the fresh texts. Tab titles too.
local function refresh_dynamic_texts()
    for _, p in ipairs(pages) do
        if p.data and type(p.title) == "function" and p.title_guid then NO.message_text(p.title_guid, text_of(p.title)) end
        for _, it in ipairs(p.items) do
            if it.title_guid and type(it.title) == "function" then NO.message_text(it.title_guid, text_of(it.title)) end
            if it.guide_guid and type(it.guide) == "function" then NO.message_text(it.guide_guid, text_of(it.guide)) end
        end
    end
end
do
    local tm_td = sdk.find_type_definition("app.training.TrainingManager")
    local om = tm_td and tm_td:get_method("OpenMenu(app.training.TrainingManager.MenuType, app.training.BaseParam)")
    if om then sdk.hook(om, function(args) pcall(refresh_dynamic_texts) end, function(rv) return rv end) end
end

-- ---------- game thread ----------
local tick = 0
local active_since = nil
re.on_pre_application_entry("LateUpdateBehavior", function()
    tick = tick + 1
    if #items == 0 and not has_pages() then return end
    if not _G.TrainingModeActive then active_since = nil; return end
    active_since = active_since or tick
    if #items > 0 and not registered then
        if tick % 60 == 5 and (tick - active_since) > 300 and not _G.TrainingGamePaused then pcall(register) end
        return
    end
    if _G.TrainingGamePaused and tick % 5 == 0 then pcall(fix_list_view) end   -- the menu rebuilds its list on open / tab switch
    if tick % 60 == 20 and not _G.TrainingGamePaused and (tick - active_since) > 300 then
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm then
            local ok, present = pcall(tabs_present, tm)
            if ok and not present then pcall(install_tabs, tm) end
        end
    end
    if #items > 0 and tick % 180 == 0 and _G.TrainingModeActive and not _G.TrainingGamePaused and not still_there() then registered = false end
end)

_G.NativePauseMenu = M
return M
