-- ============================================================
-- NativeOptions — mod settings inside the game's OWN Options menu (Pause > Options > General > "SF6 Tools").
-- No via.gui element is created: we add app.Option.OptionSettingUnit entries to app.OptionManager.UnitLists and
-- the game builds the rows itself (toggles, spin texts, sliders, sub menus, the over-the-fight HUD window).
-- Technique by mfyk (optionmanip, shared 2026, public use allowed) — cleaned up, persistence + callbacks added.
--
--   local Opt = require("func/NativeOptions")
--   local g = Opt.group("Hit Confirm", "Hit Confirm trainer settings")
--   g:toggle("native_hud", "Use game panel", "Write stats into the game's panel", true, function(v) ... end)
--   g:choice("session_mode", "Session mode", "…", { "Trials", "Timer" }, 1, cb)   -- 1-based index in cb
--   g:slider("block_rate", "Block rate", "…", 0, 100, 50, cb)
--   g:get("block_rate")  /  g:set("block_rate", 30)
--   Opt.open("Hit Confirm")   -- opens that group's native window right now, over the fight (bottom bar / hotkey)
-- Persistence belongs to the caller (the default passed in is what the menu shows; the game never saves our TypeIds).
-- Callbacks fire on the game thread (LateUpdateBehavior) the moment the value read back from the unit changes --
-- "like the bars" (31/08): the old ImGui top/bottom bars acted at the click, in click order, and so does this
-- window (slider = callback right away, START = do_start after them). Two things need the LIVE fight and run 10
-- ticks after it is back: the mode switch itself (its side effects -- guard + position refresh = a training reset
-- with a screen fade, HUD owner change -- freeze under the held pause: black screen 31/08 09:30) and entries built
-- with { deferred = true } (RSM recording import).
-- ============================================================
local M = {}
local ROOT_TITLE, ROOT_DESC = "SF6 Tools", "Settings for the SF6 training scripts."

-- ---------- enums ----------
local function enum(name)
    local t = {}
    for _, f in ipairs(sdk.find_type_definition(name):get_fields()) do
        if f:is_static() then local ok, v = pcall(f.get_data, f, nil); if ok then t[f:get_name()] = v end end
    end
    return t
end
local InputType, EventType, DataType, TabType

-- ---------- text: fake GUIDs resolved by a hook on hMsg.GetMessage ----------
local guid_text = {}          -- "guid string" -> text
local function message_guid(str)
    local g = sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    guid_text[g:call("ToString()")] = str
    return g
end
-- Managed strings handed to the game: GetMessage's caller releases what it gets, and Lua releases its own ref when
-- the wrapper dies -> two releases for one ref = random text crashes (03/09: setTextMessage / formatTextMessage /
-- Array.Clear...). A fresh string per call with one extra ref for the game (sharing one string made it worse).
local function managed_string(s)
    local m = sdk.create_managed_string(s)
    pcall(function() m:add_ref() end)
    return m
end
sdk.hook(sdk.find_type_definition("app.helper.hMsg"):get_method("GetMessage(System.Guid)"), function(args)
    local s = guid_text[sdk.to_valuetype(args[2], "System.Guid"):call("ToString()")]
    if s then thread.get_hook_storage()[1] = s; return sdk.PreHookResult.SKIP_ORIGINAL end
end, function(retval)
    local s = thread.get_hook_storage()[1]
    if s then return sdk.to_ptr(managed_string(s)) end
    return retval
end)

-- This REFramework build refuses `obj.GuidField = guid` (nested ValueType layout): write the 16 bytes directly.
local function set_guid(obj, field, guid)
    local off = obj:get_type_definition():get_field(field):get_offset_from_base()
    obj:write_qword(off, guid:read_qword(0)); obj:write_qword(off + 8, guid:read_qword(8))
end

-- ---------- registry ----------
local groups = {}             -- ordered list of group objects
local known_ids = {}          -- TypeId -> entry (so the game's Load/Reset are skipped for ours)
local next_id = nil
local function new_id()
    if not next_id then
        local max = 0
        for _, f in ipairs(sdk.find_type_definition("app.Option.ValueType"):get_fields()) do
            if f:is_static() then local ok, v = pcall(f.get_data, f, nil); if ok and type(v) == "number" and v < 2100000000 and v > max then max = v end end
        end
        next_id = (max > 100000) and (math.ceil((max + 1) / 10) * 10 + 100000) or 100000
        next_id = next_id + (os.time() % 5000) * 100   -- fresh ids per load: the UI caches widget kinds by TypeId across script reloads
    end
    next_id = next_id + 1
    return next_id
end

-- value <-> game int
local function to_int(e)
    if e.kind == "toggle" then return e.value and 1 or 0 end
    if e.kind == "choice" then return (e.value or 1) - 1 end
    return e.value or 0
end
local function from_int(e, n)
    if e.kind == "toggle" then return n ~= 0 end
    if e.kind == "choice" then return n + 1 end
    return n
end

local Group = {}; Group.__index = Group
function M.remove_group(g)
    for i, x in ipairs(groups) do if x == g then table.remove(groups, i); break end end
end
function M.group(title, desc, opts)
    local g = setmetatable({ title = title, desc = desc, entries = {}, by_key = {}, mode = opts and opts.mode, key = opts and opts.key }, Group)
    groups[#groups + 1] = g
    return g
end
-- The composite "SF6 Tools" window: a "Training mode" spin on top, then the entries of the group whose `mode`
-- matches the current mode. Changing the spin switches the mode and rebuilds/reopens the window on the new content.
local mode_sel = nil     -- { names=, ids=, get=, set= }
local COMPOSITE = "SF6 Tools"
function M.set_mode_selector(names, ids, get, set) mode_sel = { names = names, ids = ids, get = get, set = set } end
local function current_mode_index()   -- 1-based index into mode_sel.ids
    if not mode_sel then return 1 end
    local cur = mode_sel.get()
    for i, id in ipairs(mode_sel.ids) do if id == cur then return i end end
    return 1
end
local function add_entry(g, e)
    g.entries[#g.entries + 1] = e; g.by_key[e.key] = e
    return e
end
-- toggle: value true/false
function Group:toggle(key, title, desc, default, cb, opts)
    return add_entry(self, { kind = "toggle", key = key, title = title, desc = desc, value = default and true or false, cb = cb, options = { (_G.SF6_NativeLocale and _G.SF6_NativeLocale("toggle.off")) or "Off", (_G.SF6_NativeLocale and _G.SF6_NativeLocale("toggle.on")) or "On" }, deferred = opts and opts.deferred, getter = opts and opts.getter })
end
-- choice: value = 1-based index into options
function Group:choice(key, title, desc, options, default, cb, opts)
    return add_entry(self, { kind = "choice", key = key, title = title, desc = desc, value = default or 1, cb = cb, options = options, deferred = opts and opts.deferred, getter = opts and opts.getter })
end
-- radio: like choice but flagged for the game's popup list (DecideEventType.OpenRadioButton). NOT WORKING (30/08): the
-- row renders but confirming it only drops the focus, no popup agent appears (the popup is tied to native TypeIds).
-- Kept for a later attempt; use choice() (SpinText) for lists. options may be a function returning the list
-- (evaluated when the menu is built, e.g. a file list).
function Group:radio(key, title, desc, options, default, cb)
    self.has_radio = true   -- the radio popup only opens from the Options screen itself, not from the HUD window
    return add_entry(self, { kind = "choice", radio = true, key = key, title = title, desc = desc, value = default or 1, cb = cb, options = options })
end
-- button: a full-width row like the dialog's own "Restore Default Settings" (DecideEventType.SettingReset);
-- our hook on FlowEvent_ResetCurrentUnits runs cb instead of the game's reset when the focused row is ours.
function Group:button(key, title, desc, cb, refresh)
    -- title may be a function (evaluated at every build): with refresh=true the window is rebuilt/reopened
    -- after the press, so a state button (Session START/STOP) relabels itself.
    return add_entry(self, { kind = "button", key = key, title = title, desc = desc, cb = cb, refresh = refresh })
end
local function entry_title(g, e)
    local t = (type(e.title) == "function") and e.title() or e.title
    e.built_title = t
    if g and g.has_radio then return g.title .. " - " .. t end
    return t
end
-- slider: integer value in [min, max]
function Group:slider(key, title, desc, min, max, default, cb, opts)
    return add_entry(self, { kind = "slider", key = key, title = title, desc = desc, value = default or min, cb = cb, min = min, max = max, deferred = opts and opts.deferred, getter = opts and opts.getter })
end
function Group:get(key) local e = self.by_key[key]; return e and e.value end
function Group:set(key, v)
    local e = self.by_key[key]; if not e then return end
    e.value = v; e.last_int = to_int(e)
    if e.unit then pcall(function() e.unit:call("SetValue", to_int(e), false) end) end
end

-- ---------- building the units ----------
local built = false
local parent_list, root_unit, empty_guids, empty_settings
local composite_unit, mode_entry, composite_mirrors = nil, nil, {}
local display_mode_idx = nil   -- mode shown by the spin (content of the window) until the real switch runs on the live fight
local pending_mode_id = nil    -- mode id to apply once the fight is back (nil = none)
local live_since = nil         -- tick the fight came back (no pause, no window)

local ids_by_key = {}            -- logical key -> TypeId, stable across rebuilds (stacked dialogs keep resolving)
local function new_setting(key)
    local d = sdk.create_instance("app.Option.OptionSettingUnit"); pcall(function() d:add_ref() end)   -- held: the GC collects an unreferenced instance (MakeUnitData NullReference, 03/09)
    if key then
        if not ids_by_key[key] then ids_by_key[key] = new_id() end
        d.TypeId = ids_by_key[key]
    else
        d.TypeId = new_id()
    end
    return d
end
local function make_unit(desc, description, value_messages)
    local unit = desc:call("MakeUnitData")
    local s = unit:call("get_Setting")
    set_guid(s, "DescriptionMessage", message_guid(description or ""))
    s.ValueMessageList = empty_guids:call("MemberwiseClone")
    s.ChildUnitList = empty_settings:call("MemberwiseClone")
    for _, msg in ipairs(value_messages or {}) do s.ValueMessageList:call("Add", message_guid(msg)) end
    return unit
end
local function attach(parent, child)
    parent:call("get_ChildUnits"):call("Add", child)
    parent:call("get_Setting").ChildUnitList:call("Add", child:call("get_Setting"))
end

-- Rows a previous Lua state may have added to the training pause menu (NativePauseMenu experiment): without their
-- hooks they would be blank and unsafe -> remove every DYNAMIC (345) row from every tab.
local function purge_pause_menu_rows()
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager"); if not tm then return end
        local arr = tm:get_field("_UIData"):call("get_MenuData")
        for t = 0, arr:call("get_Length") - 1 do
            local dl = arr:call("GetValue", t):get_field("DynamicChildData")
            if dl then
                local i = dl:call("get_Count") - 1
                while i >= 0 do
                    local dd = dl:call("get_Item", i); local cd = dd and dd:get_field("ChildData")
                    if cd and cd:get_field("_FuncType") == 345 then dl:call("RemoveAt", i) end
                    i = i - 1
                end
            end
        end
    end)
end

local function build()
    local mgr = sdk.get_managed_singleton("app.OptionManager"); if not mgr then return false end
    if not _G.TrainingGamePaused and not _G.NativePauseMenu then purge_pause_menu_rows() end   -- NativePauseMenu manages its own rows
    InputType, EventType, DataType, TabType = enum("app.Option.UnitInputType"), enum("app.Option.DecideEventType"), enum("app.Option.SettingDataType"), enum("app.Option.TabType")
    parent_list = mgr.UnitLists:call("get_Item", TabType.General)
    local first = parent_list:call("get_Item", 0):call("get_Setting")
    empty_guids = first.ValueMessageList:call("GetRange", 0, 0)
    empty_settings = first.ChildUnitList:call("GetRange", 0, 0)

    local rd = new_setting("__root")
    set_guid(rd, "TitleMessage", message_guid(ROOT_TITLE))
    rd.InputType = InputType.Button_Type1; rd.EventType = EventType.OpenSubMenu
    root_unit = make_unit(rd, ROOT_DESC)
    parent_list:call("Add", root_unit)

    for _, g in ipairs(groups) do
        -- A group with a radio list is laid flat in the SF6 Tools column: the popup only opens from a list unit
        -- (like the Language tab), not from the HUD window, and a sub-menu inside a sub-menu does not open.
        if g.has_radio then
            g.unit = root_unit
        else
            local gd = new_setting("g:" .. tostring(g.key or g.title))
            local gtitle = (type(g.title) == "function") and g.title() or g.title
            g.built_title = gtitle
            set_guid(gd, "TitleMessage", message_guid(gtitle))
            gd.InputType = InputType.Button_Type1; gd.EventType = EventType.OpenBattleHudSetting   -- HUD window over the fight
            g.unit = make_unit(gd, g.desc); attach(root_unit, g.unit)
        end
        local ordered = {}
        for _, e in ipairs(g.entries) do if e.kind ~= "button" then ordered[#ordered + 1] = e end end
        for _, e in ipairs(g.entries) do if e.kind == "button" then ordered[#ordered + 1] = e end end   -- buttons at the bottom
        for _, e in ipairs(ordered) do
            local d = new_setting("e:" .. tostring(g.key or g.title) .. "/" .. tostring(e.key))
            set_guid(d, "TitleMessage", message_guid(entry_title(g, e)))
            if e.kind == "button" then
                d.InputType = InputType.Button_Type2; d.EventType = EventType.SettingReset   -- exactly the Restore-row pattern (Type2 = centered button)
                e.type_id = d.TypeId; known_ids[d.TypeId] = e
                e.unit = make_unit(d, e.desc); attach(g.unit, e.unit)
            else
            d._DataType = DataType.Value
            if type(e.options) == "function" then e.options_fn = e.options end
            if e.options_fn then e.options = e.options_fn() or {}; if #e.options == 0 then e.options = { "-" } end end   -- dynamic lists (files...)
            if e.radio then
                d.InputType = InputType.Button_Type0; d.EventType = EventType.OpenRadioButton   -- the game's popup list
            else
                d.InputType = (e.kind == "slider") and InputType.Slider or InputType.SpinText
            end
            e.type_id = d.TypeId; known_ids[d.TypeId] = e
            local u = make_unit(d, e.desc, e.options)
            attach(g.unit, u)
            local vs = sdk.create_instance("app.Option.OptionValueSetting"); pcall(function() vs:add_ref() end)   -- held: the GC collects an unreferenced instance (MakeUnitData NullReference, 03/09)
            vs.TypeId = d.TypeId
            vs.MinValue = e.min or 0; vs.MaxValue = e.max or (#e.options - 1); vs.InitValue = to_int(e)
            u:call("set_PrevValue", vs.InitValue); u:call("set_ValueSetting", vs)
            u.ValueData = vs:call("MakeValueData")
            e.unit = u; e.last_int = vs.InitValue
            end
        end
    end
    -- composite window
    if mode_sel then
        local cd = new_setting("__composite")
        set_guid(cd, "TitleMessage", message_guid(COMPOSITE))
        cd.InputType = InputType.Button_Type1; cd.EventType = EventType.OpenBattleHudSetting
        composite_unit = make_unit(cd, "Training script settings."); attach(root_unit, composite_unit)
        -- mode spin
        local md = new_setting("__mode")
        set_guid(md, "TitleMessage", message_guid("Training mode"))
        md._DataType = DataType.Value; md.InputType = InputType.SpinText
        mode_entry = { kind = "choice", key = "__mode", title = "Training mode", options = mode_sel.names, value = display_mode_idx or current_mode_index(), immediate = true }
        mode_entry.type_id = md.TypeId; known_ids[md.TypeId] = mode_entry
        local mu = make_unit(md, "Which training script drives the session.", mode_sel.names)
        attach(composite_unit, mu)
        local mvs = sdk.create_instance("app.Option.OptionValueSetting"); pcall(function() mvs:add_ref() end)   -- held: the GC collects an unreferenced instance (MakeUnitData NullReference, 03/09)
        mvs.TypeId = md.TypeId; mvs.MinValue = 0; mvs.MaxValue = #mode_sel.names - 1; mvs.InitValue = mode_entry.value - 1
        mu:call("set_PrevValue", mvs.InitValue); mu:call("set_ValueSetting", mvs); mu.ValueData = mvs:call("MakeValueData")
        mode_entry.unit = mu; mode_entry.last_int = mvs.InitValue
        -- entries of the current mode's group, as fresh units mirroring the same entries
        local cur_id = mode_sel.ids[mode_entry.value]
        composite_mirrors = {}
        for _, g in ipairs(groups) do
            if g.mode == cur_id then
                local ordered = {}
                for _, e in ipairs(g.entries) do if e.kind ~= "button" then ordered[#ordered + 1] = e end end
                for _, e in ipairs(g.entries) do if e.kind == "button" then ordered[#ordered + 1] = e end end   -- buttons at the bottom
                for _, e in ipairs(ordered) do
                    local d = new_setting("m:" .. tostring(g.key or g.title) .. "/" .. tostring(e.key))
                    set_guid(d, "TitleMessage", message_guid(entry_title(nil, e)))
                    if e.kind == "button" then
                        d.InputType = InputType.Button_Type2; d.EventType = EventType.SettingReset
                        known_ids[d.TypeId] = e
                        attach(composite_unit, make_unit(d, e.desc))
                    else
                    d._DataType = DataType.Value
                    d.InputType = (e.kind == "slider") and InputType.Slider or InputType.SpinText
                    local mirror = { entry = e, type_id = d.TypeId }
                    known_ids[d.TypeId] = mirror
                    local u = make_unit(d, e.desc, e.options)
                    attach(composite_unit, u)
                    local vs = sdk.create_instance("app.Option.OptionValueSetting"); pcall(function() vs:add_ref() end)   -- held: the GC collects an unreferenced instance (MakeUnitData NullReference, 03/09)
                    vs.TypeId = d.TypeId; vs.MinValue = e.min or 0; vs.MaxValue = e.max or (#e.options - 1); vs.InitValue = to_int(e)
                    u:call("set_PrevValue", vs.InitValue); u:call("set_ValueSetting", vs); u.ValueData = vs:call("MakeValueData")
                    mirror.unit = u; mirror.last_int = vs.InitValue
                    composite_mirrors[#composite_mirrors + 1] = mirror
                    end
                end
            end
        end
    end
    built = true
    return true
end

-- Our button rows: the dialog treats them as "Restore Default Settings" (SettingReset). When the focused unit is
-- one of ours, run its callback instead of the game's reset.
local button_queue = {}
local pending_focus = nil       -- row index to focus when the next page is built (SetupDispUnits pre-hook)
local old_handle, old_end_at = nil, nil   -- seamless page change (menus): previous dialog ended once the new one is up
local dialog_stack, param_stack = {}, {}  -- parents kept alive under the current dialog (menus): Esc pops instantly
local old_parent = nil                     -- replace + pop: the parent underneath, ended together with the replaced dialog
local old_queue = {}                       -- replaced dialogs still waiting for their End (fast repeated replaces: none is lost)
local bg_param_td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")
if bg_param_td then
    local m = bg_param_td:get_method("FlowEvent_ResetCurrentUnits")
    if m then
        sdk.hook(m, function(args)
            local ok, entry = pcall(function()
                local param = sdk.to_managed_object(args[2])
                local u = param:call("GetFocusUnit")
                return u and known_ids[u:call("get_Setting").TypeId]
            end)
            if ok and entry and entry.kind == "button" then
                button_queue[#button_queue + 1] = entry
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(rv) return rv end)
    end
    -- Earlier interception (traced 30/08): the FSM calls GetFocusDecideEventType exactly ONCE, at the decide press.
    -- For our buttons we return Invalid (0) so the FSM does nothing -- no "Revert settings?" popup -- and we queue
    -- the callback right here. The FlowEvent_ResetCurrentUnits hook above stays as a safety net.
    local md = bg_param_td:get_method("GetFocusDecideEventType")
    if md then
        sdk.hook(md, function(args)
            thread.get_hook_storage()["no_decide_this"] = args[2]
        end, function(rv)
            if (sdk.to_int64(rv) & 0xFF) == 1 then   -- DecideEventType.SettingReset
                local ok, entry = pcall(function()
                    local param = sdk.to_managed_object(thread.get_hook_storage()["no_decide_this"])
                    local u = param:call("GetFocusUnit")
                    return u and known_ids[u:call("get_Setting").TypeId]
                end)
                if ok and entry and entry.kind == "button" then
                    button_queue[#button_queue + 1] = entry
                    return sdk.to_ptr(0)   -- DecideEventType.Invalid: the FSM does nothing
                end
            end
            return rv
        end)
    end
end

-- Hide the dialog's own "Restore Default Settings" row on OUR pages (it is a no-op there: our ids skip
-- ResetEvent). SetupDispUnits builds the visible page (FlowEvent_OpenSelectedGroupPage never fires for
-- this dialog -- verified 31/08); foreign dialogs (real Options windows) keep their row.
-- Our dialogs skip the screen fade (ImmediateFade): the fade was the only part of the End+Start
-- transition that needed unpaused frames (frozen fade = the 30-31/08 black screens).
local created_m = bg_param_td and bg_param_td:get_method("CreatedObject")
if created_m then
    sdk.hook(created_m, function(args)
        if _G.NativeOptionsWindowOpen then
            pcall(function()
                local param = sdk.to_managed_object(args[2])
                param:set_field("<ImmediateFade>k__BackingField", true)
                thread.get_hook_storage()["no_created_param"] = param
            end)
        end
    end, function(rv)
        local param = thread.get_hook_storage()["no_created_param"]
        if param then
            if param_stack.replace_pending then param_stack.replace_pending = nil; table.remove(param_stack) end
            if param_stack.pop_parent then param_stack.pop_parent = nil; table.remove(param_stack) end
            param_stack[#param_stack + 1] = param
            M.current_param = param
        end
        if param and M.on_dialog_created then pcall(M.on_dialog_created, param) end
        return rv
    end)
end

local setup_m = bg_param_td and bg_param_td:get_method("SetupDispUnits")
if setup_m then
    sdk.hook(setup_m, function(args)
        thread.get_hook_storage()["no_setup_this"] = args[2]
        if pending_focus and _G.NativeOptionsWindowOpen then           -- cursor back on the row we came from
            local n = pending_focus; pending_focus = nil
            pcall(function() sdk.to_managed_object(args[3]):set_field("FocusIndex", n) end)
        end
    end, function(rv)
        pcall(function()
            local param = sdk.to_managed_object(thread.get_hook_storage()["no_setup_this"])
            local parts = param:get_field("OptionUnits")
            if not parts then return end
            local ours, reset_parts = false, {}
            for i = 0, parts:call("get_Length") - 1 do
                local part = parts:call("GetValue", i)
                local ud = part and part:get_field("UnitData")
                if ud then
                    local ok, setting = pcall(function() return ud:call("get_Setting") end)
                    if ok and setting then
                        local entry = known_ids[setting.TypeId]
                        if entry then
                            ours = true
                        elseif setting.EventType == 1 then reset_parts[#reset_parts + 1] = part end   -- SettingReset
                    end
                end
            end
            if ours then
                for _, part in ipairs(reset_parts) do
                    local c = part:call("get_Control")
                    if c then c:call("set_ForceInvisible", true) end
                    pcall(function() part:call("SetDisable", true) end)
                end
                if M.on_page_setup then                                -- caller: rows of the page just built (entry -> part)
                    local map = {}
                    for i = 0, parts:call("get_Length") - 1 do
                        local part = parts:call("GetValue", i)
                        local ud = part and part:get_field("UnitData")
                        local okS, st = pcall(function() return ud and ud:call("get_Setting") end)
                        local e = okS and st and known_ids[st.TypeId]
                        if e then map[e.entry or e] = part end
                    end
                    pcall(M.on_page_setup, param, map)
                end
            end
        end)
        return rv
    end)
end

-- Cursor: the hidden "Restore Default Settings" row must not be focusable on our pages -- the list asks
-- Param.CheckCanSelect(index) while moving, answer false for that row so the cursor skips it (and wraps).
local can_select_m = bg_param_td and bg_param_td:get_method("CheckCanSelect")
if can_select_m then
    sdk.hook(can_select_m, function(args)
        local st = thread.get_hook_storage()
        st["no_cs_this"] = args[2]; st["no_cs_index"] = sdk.to_int64(args[3]) & 0xFFFFFFFF
    end, function(rv)
        if not _G.NativeOptionsWindowOpen then return rv end
        local st = thread.get_hook_storage()
        local ok, block = pcall(function()
            local param = sdk.to_managed_object(st["no_cs_this"])
            if not param or param:get_type_definition():get_full_name() ~= "app.UIFlowOptionBGDialog.Param" then return false end
            local parts = param:get_field("OptionUnits")
            local idx = st["no_cs_index"]
            if not parts or idx < 0 or idx >= parts:call("get_Length") then return false end
            local part = parts:call("GetValue", idx)
            local ud = part and part:get_field("UnitData")
            local setting = ud and ud:call("get_Setting")
            -- the game's own reset row: SettingReset event AND not one of our ids (our buttons are SettingReset too)
            if not setting or setting.EventType ~= 1 or known_ids[setting.TypeId] then return false end
            local ours = false
            for i = 0, parts:call("get_Length") - 1 do                          -- our page? (any of our ids)
                local p2 = parts:call("GetValue", i)
                local ud2 = p2 and p2:get_field("UnitData")
                local s2 = ud2 and ud2:call("get_Setting")
                if s2 and known_ids[s2.TypeId] then ours = true; break end
            end
            if not ours then return false end
            local fu = param:call("GetFocusUnit")                                -- never forbid the focused row (no dead end)
            if fu and fu:call("get_Setting").TypeId == setting.TypeId then return false end
            return true
        end)
        if ok and block then return sdk.to_ptr(0) end
        return rv
    end)
end

-- the game must not load/reset our ids from its save data
local function skip_ours(args)
    local ok, id = pcall(function() return sdk.to_managed_object(args[2]):call("get_Setting").TypeId end)
    if ok and known_ids[id] then return sdk.PreHookResult.SKIP_ORIGINAL end
end
local vu = sdk.find_type_definition("app.Option.OptionValueUnit")
sdk.hook(vu:get_method("LoadValueEvent"), skip_ours)
sdk.hook(vu:get_method("ResetEvent"), skip_ours)

-- Dynamic lists: re-evaluated only when the window is about to open (never on a timer: file lists cost a fs.glob).
local function rebuild()
    if root_unit and parent_list then pcall(function() parent_list:call("Remove", root_unit) end) end
    root_unit = nil; built = false; known_ids = {}; composite_unit = nil; mode_entry = nil; composite_mirrors = {}
    for _, g in ipairs(groups) do g.unit = nil; for _, e in ipairs(g.entries) do e.unit = nil end end
end
M.rebuild = rebuild
local function lists_changed()
    for _, g in ipairs(groups) do
        if type(g.title) == "function" then
            local ok, t = pcall(g.title)
            if ok and g.built_title ~= nil and t ~= g.built_title then return true end
        end
        for _, e in ipairs(g.entries) do
            if e.options_fn then
                local ok, new = pcall(e.options_fn); new = (ok and new) or {}
                if #new == 0 then new = { "-" } end
                if #new ~= #e.options then return true end
                for i = 1, #new do if new[i] ~= e.options[i] then return true end end
            end
            if type(e.title) == "function" then   -- state changed elsewhere (hotkey): stale label
                local ok, t = pcall(e.title)
                if ok and e.built_title ~= nil and t ~= e.built_title then return true end
            end
        end
    end
    return false
end
local function refresh_values()
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.entries) do
            if e.getter and e.unit then
                local ok, v = pcall(e.getter)
                if ok and v ~= nil and v ~= e.value then
                    e.value = v
                    local ni = to_int(e)
                    e.last_int = ni
                    pcall(function() e.unit:call("SetValue", ni, false) end)
                end
            end
        end
    end
end

-- ---------- open a group's window directly from the fight (no Pause > Options) ----------
-- app.UIFlowOptionBGDialog.Start(SettingData{TopUnit = group unit}, false) is what the Options screen does for
-- DecideEventType.OpenBattleHudSetting. Called from the game thread only. The game is NOT paused while the
-- window is up: _G.NativeOptionsWindowOpen tells the native HUD modules to stay silent (the battle HUD is rebuilt).
local open_request = nil
local deferred_open = nil     -- title/key queued by open_after_unpause (waits for both flags false for 5 ticks)
local deferred_stable = 0
local open_at, open_started, reopen_wait = nil, nil, nil   -- reopen_wait: End sent, waiting for the old dialog to vanish
local reopen_title = nil   -- group to reopen on (nil = the composite window)
local rehold_wait = nil   -- reopen done, waiting for the new dialog to be fully up before re-pausing
-- The Esc/Start that closes our dialog also reaches the training pause menu. TrainingManager.OpenMenu is the
-- single entry point of that menu (game thread): refuse it while our window is up and for a few frames after.
local closed_tick = -1000
local tick = 0
local tm_td = sdk.find_type_definition("app.training.TrainingManager")
local open_menu = tm_td and tm_td:get_method("OpenMenu(app.training.TrainingManager.MenuType, app.training.BaseParam)")
if open_menu then
    sdk.hook(open_menu, function(args)
        if _G.NativeOptionsWindowOpen or (tick - closed_tick) < 20 then return sdk.PreHookResult.SKIP_ORIGINAL end
    end, function(rv) return rv end)
end
function M.open(title)
    -- Mutual exclusion with the real pause menu: the shortcut is IGNORED (not deferred) while paused,
    -- otherwise the window would pop up right when leaving the pause menu.
    if _G.TrainingGamePaused or _G.NativeOptionsWindowOpen then return end
    open_request = title
end
-- Same window from a menu screen (character select, fighter settings...): no fight to pause, no training gate.
local menu_mode = false
function M.open_menu(title, focus_index)
    if _G.NativeOptionsWindowOpen then return end
    menu_mode = true
    open_request = title
    pending_focus = focus_index
end
-- Navigate to another group of the open window (same path as a button callback returning { open = key }).
local seamless_open   -- (defined with the tick below)
function M.navigate(key, rebuild_tree, focus_index, now, push, pop)
    if not _G.NativeOptionsWindowOpen then return end
    pending_focus = focus_index
    if now and menu_mode and seamless_open then seamless_open(key, rebuild_tree, push, pop); return end
    button_queue[#button_queue + 1] = { cb = function() return { open = key, rebuild = rebuild_tree, push = push, pop = pop } end }
end
function M.ensure_built()
    if not built then rebuild(); pcall(build) end
    return built
end
-- Queue an open that waits until both TrainingGamePaused and NativeOptionsWindowOpen are false for 5 ticks.
-- Used by pause-menu buttons that close the menu first (keep_open=false) and need the window to open once the fight is back.
function M.open_after_unpause(title)
    deferred_open = title
    deferred_stable = 0
end
local function agent_present(name)
    local mgr = sdk.get_managed_singleton("app.UIAgentManager")
    local list = mgr and mgr:get_field("_Entries"); if not list then return false end
    for i = 0, list:call("get_Count") - 1 do
        local agent = list:call("get_Item", i).Agent
        local go = agent and agent:call("get_GameObject")
        if go and tostring(go:call("get_Name")) == name then return true end
    end
    return false
end
-- Freeze the fight while our window is up. requestPause signature is (bool start, PauseType) --
-- verified 30/08: (true, type) engages, (false, type) releases, _CurrentPauseTypeBit gains/loses the bit.
-- The real training pause menu holds type 8 BATTLE_MENU_PAUSE (sampled 31/08: bit 64 -> 320 in the menu):
-- that is the one that freezes the fight. Type 1 DIAOLG_PAUSE engages but pauses only dialog-scope objects;
-- type 11 BATTLE_TRAINING_PAUSE is refused outside the menu. pause_held guards double-requests across reopens.
local PAUSE_TYPE = 8
local pause_held = false
local function hold_pause(on)
    if menu_mode and on then return end                       -- menus: nothing to freeze
    if on == pause_held then return end
    local mgr = sdk.get_managed_singleton("app.PauseManager")
    if mgr and pcall(function() mgr:call("requestPause", on, PAUSE_TYPE) end) then pause_held = on end
end
-- "Like the bars" (31/08): a changed value acts right away, in click order, exactly as the old ImGui bottom bar
-- did -- a START pressed after a slider change starts with the new value instead of being reset by a callback
-- that fires after the window closes. Only { deferred = true } entries wait for the unpause (RSM import).
local function fire_entry(e)
    if e.deferred then e.pending_cb = true; return end
    if e.cb then pcall(e.cb, e.value) end
end

local dialog_handle = nil          -- app.UIFlowManager.Handle of the open dialog (End() closes it)
local function end_dialog()
    if dialog_handle then
        pcall(function() if not dialog_handle:call("get_IsEnd") then dialog_handle:call("End") end end)
        dialog_handle = nil
    end
    if old_handle then
        local h = old_handle; old_handle = nil; old_end_at = nil
        pcall(function() if not h:call("get_IsEnd") then h:call("End") end end)
    end
    if old_parent then local hp = old_parent; old_parent = nil; pcall(function() if not hp:call("get_IsEnd") then hp:call("End") end end) end
    for _, q in ipairs(old_queue) do pcall(function() if not q.h:call("get_IsEnd") then q.h:call("End") end end) end
    old_queue = {}
    for i = #dialog_stack, 1, -1 do
        local h = dialog_stack[i]; dialog_stack[i] = nil
        pcall(function() if not h:call("get_IsEnd") then h:call("End") end end)
    end
    param_stack = {}
end
function M.close() end_dialog() end
-- (M.back = End() on the focused top dialog crashed the game in UIPartsItem.UpdateFocus, 03/09: only dialogs that
-- are NOT focused any more may be ended by us -> "replace + pop" below: a new dialog takes the focus first)
local function start_dialog(unit)
    if dialog_handle then                                          -- only the current one (the stacked parents stay)
        pcall(function() if not dialog_handle:call("get_IsEnd") then dialog_handle:call("End") end end)
        dialog_handle = nil
    end
    local sd = sdk.create_instance("app.UIFlowOptionBGDialog.SettingData"); pcall(function() sd:add_ref() end)   -- held: the GC collects an unreferenced instance (MakeUnitData NullReference, 03/09)
    sd.TopUnit = unit; sd.SupportMode = 32; sd.UseBattleHudBG = false; sd.PlayerIndex = 0
    local m = sdk.find_type_definition("app.UIFlowOptionBGDialog"):get_method("Start(app.UIFlowOptionBGDialog.SettingData, System.Boolean)")
    if m then dialog_handle = m:call(nil, sd, false) end
end
local function do_open(title)
    if title == COMPOSITE and composite_unit then start_dialog(composite_unit); return end
    for _, g in ipairs(groups) do
        if (g.key == title or g.title == title or g.built_title == title) and g.unit and g.unit ~= root_unit then
            start_dialog(g.unit)
            return
        end
    end
end

-- seamless page change (menus): the new dialog is started ON TOP of the old one, which is ended a few ticks
-- later (no pause to juggle; the old page keeps its units until it is gone)
seamless_open = function(key, rebuild_tree, push, pop)
    local old = dialog_handle; dialog_handle = nil
    if rebuild_tree or not built then rebuild(); pcall(build) end
    if built then
        pcall(do_open, key); open_started = tick
        if old then
            if push then dialog_stack[#dialog_stack + 1] = old        -- parent stays alive underneath
            else
                if old_handle then old_queue[#old_queue + 1] = { h = old_handle, at = old_end_at } end   -- previous replace still pending
                if old_parent then old_queue[#old_queue + 1] = { h = old_parent, at = old_end_at }; old_parent = nil end
                old_handle = old; old_end_at = tick + 8; param_stack.replace_pending = true
                if pop and #dialog_stack > 0 then                     -- the new page replaces the parent too (confirm -> root)
                    old_parent = table.remove(dialog_stack); param_stack.pop_parent = true
                end
            end
        end
    end
end

-- ---------- game thread: build once the manager exists, then poll for changes ----------
re.on_pre_application_entry("LateUpdateBehavior", function()
    tick = tick + 1
    if not built then
        if tick % 60 == 1 and #groups > 0 then pcall(build) end
        return
    end
    -- Deferred open (from pause-menu buttons): wait for both flags to be false for 5 stable ticks
    if deferred_open then
        if not _G.TrainingGamePaused and not _G.NativeOptionsWindowOpen then
            deferred_stable = deferred_stable + 1
            if deferred_stable >= 5 then
                open_request = deferred_open
                deferred_open = nil
                deferred_stable = 0
            end
        else
            deferred_stable = 0
        end
    end
    -- Two-phase open: raise the flag first so NativeHud/NativeTopBar give the HUD back while its controls are
    -- still alive (the window re-uses that HUD as its preview), then start the dialog two frames later.
    if open_request and _G.TrainingGamePaused and not menu_mode and not _G.NativeOptionsWindowOpen then open_request = nil end   -- pause won the race: drop
    if open_request and (menu_mode or not _G.TrainingGamePaused) and not _G.NativeOptionsWindowOpen and (_G.TrainingModeActive or menu_mode) then
        -- dynamic lists (RSM files = fs.glob, ~260 ms) are only re-read here, right before the window shows
        if lists_changed() then rebuild(); pcall(build) end
        refresh_values()
        _G.NativeOptionsWindowOpen = true; open_at = tick + 3
    elseif open_at and tick >= open_at then
        local t = open_request; open_request = nil; open_at = nil; open_started = tick
        pcall(do_open, t)
        hold_pause(true)
    elseif reopen_wait then
        -- Wait for the old dialog to vanish, pause still held (ImmediateFade makes this instant).
        -- Safety net: if it will not die after 30 ticks, release the pause so a frozen fade can finish.
        local elapsed = tick - reopen_wait
        if elapsed > 90 or not agent_present("OptionDialog") then
            reopen_wait = nil; open_started = tick
            pcall(do_open, reopen_title or COMPOSITE); reopen_title = nil
            rehold_wait = tick
        elseif elapsed == 30 then
            hold_pause(false)
        end
    elseif rehold_wait then
        -- Make sure the pause is held once the new dialog is up (no-op when it was never released).
        if ((tick - rehold_wait) >= 5 and agent_present("OptionDialog")) or (tick - rehold_wait) > 60 then
            rehold_wait = nil
            if _G.NativeOptionsWindowOpen then hold_pause(true) end
        end
    end
    if old_handle and old_end_at and tick >= old_end_at then
        local h = old_handle; old_handle = nil; old_end_at = nil
        pcall(function() if not h:call("get_IsEnd") then h:call("End") end end)
        if old_parent then local hp = old_parent; old_parent = nil; pcall(function() if not hp:call("get_IsEnd") then hp:call("End") end end) end
    end
    if #old_queue > 0 then
        local keep = {}
        for _, q in ipairs(old_queue) do
            if tick >= (q.at or 0) then pcall(function() if not q.h:call("get_IsEnd") then q.h:call("End") end end) else keep[#keep + 1] = q end
        end
        old_queue = keep
    end
    if #button_queue > 0 then
        local q = button_queue; button_queue = {}
        local want_refresh, want_close, want_open, want_rebuild, want_push, want_pop = false, false, nil, false, false, false
        for _, e in ipairs(q) do
            local ret = nil
            if e.cb then local okc, rc = pcall(e.cb); if okc then ret = rc end end
            if ret == "close" then want_close = true
            elseif type(ret) == "table" and ret.open then want_open = ret.open; if ret.rebuild then want_rebuild = true end; if ret.push then want_push = true end; if ret.pop then want_pop = true end
            elseif e.refresh then want_refresh = true end
        end
        if want_close then   -- the action wants the window gone (Session START): close, rebuild for the next open
            end_dialog(); hold_pause(false); rebuild(); pcall(build)
        elseif want_open then   -- navigate to another page (colour editor): same window, other group
            local was_open = _G.NativeOptionsWindowOpen
            if was_open and menu_mode then
                seamless_open(want_open, want_rebuild, want_push, want_pop)
            else
                end_dialog()
                if want_rebuild or not built then rebuild(); pcall(build) end   -- rebuild = group definitions changed (titles)
                if was_open and built then reopen_title = want_open; reopen_wait = tick end
            end
        elseif want_refresh then   -- dynamic titles: rebuild and reopen on the new labels
            local was_open = _G.NativeOptionsWindowOpen
            end_dialog()
            rebuild(); pcall(build)
            if was_open and built then reopen_wait = tick end
        end
    end
    -- Mode switch on the LIVE fight only, 10 ticks after it is back (NativeHud has re-acquired its texts by then):
    -- the same _G.CurrentTrainerMode = id the top bar's click did, in the same context (a running fight).
    if _G.TrainingGamePaused or _G.NativeOptionsWindowOpen then live_since = nil else live_since = live_since or tick end
    if pending_mode_id ~= nil and live_since and (tick - live_since) >= 10 then
        local id = pending_mode_id; pending_mode_id = nil; display_mode_idx = nil
        if mode_sel and mode_sel.get() ~= id then pcall(mode_sel.set, id) end
    end
    if menu_mode and _G.NativeOptionsWindowOpen and dialog_handle and #dialog_stack > 0 and not old_handle then
        local okE, ended = pcall(function() return dialog_handle:call("get_IsEnd") end)
        if okE and ended then                                      -- the game closed the top page (Esc / B): the parent is up
            dialog_handle = table.remove(dialog_stack)
            table.remove(param_stack); M.current_param = param_stack[#param_stack]
            if M.on_page_popped then pcall(M.on_page_popped, M.current_param) end
        end
    end
    if tick % 10 ~= 0 then return end
    if _G.NativeOptionsWindowOpen and not open_at and not reopen_wait and not old_handle and (tick - (open_started or 0)) > 10 then
        local ended = dialog_handle and (pcall(function() return dialog_handle:call("get_IsEnd") end)) and dialog_handle:call("get_IsEnd")
        if ended or not agent_present("OptionDialog") then
            _G.NativeOptionsWindowOpen = false; closed_tick = tick; dialog_handle = nil
            hold_pause(false); menu_mode = false; param_stack = {}
        end
    end
    -- composite window: mode spin (immediate) and mirrored entries
    if mode_entry and not _G.NativeOptionsWindowOpen and pending_mode_id == nil and current_mode_index() ~= mode_entry.value then
        rebuild(); pcall(build); return   -- the mode changed elsewhere (top bar, hotkey): refresh the window content
    end
    if mode_entry and mode_entry.unit then
        local ok, n = pcall(function() return mode_entry.unit:call("get_Value") end)
        if ok and n ~= mode_entry.last_int then
            mode_entry.last_int = n; mode_entry.value = n + 1
            display_mode_idx = n + 1               -- the window shows the new mode's settings right away...
            pending_mode_id = mode_sel.ids[n + 1]  -- ...the real switch runs on the live fight (see the tick above)
            -- new content: rebuild the tree now and reopen the window on it. With ImmediateFade the
            -- whole End+Start transition runs under the held pause (no game blip); a 30-tick fallback
            -- releases the pause if the old dialog will not die (frozen fade safety net).
            local was_open = _G.NativeOptionsWindowOpen
            end_dialog()
            rebuild(); pcall(build)
            if was_open and built then reopen_wait = tick end
            return
        end
    end
    for _, mr in ipairs(composite_mirrors) do
        local ok, n = pcall(function() return mr.unit:call("get_Value") end)
        if ok and n ~= mr.last_int then
            mr.last_int = n
            local e = mr.entry
            e.value = from_int(e, n); e.last_int = n
            if e.unit then pcall(function() e.unit:call("SetValue", n, false) end) end
            fire_entry(e)
        end
    end
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.entries) do
            local ok, n = pcall(function() return e.unit:call("get_Value") end)
            if ok and n ~= e.last_int then
                e.last_int = n; e.value = from_int(e, n)
                fire_entry(e)
            end
            if e.pending_cb and not _G.TrainingGamePaused and not _G.NativeOptionsWindowOpen then   -- deferred entries only
                e.pending_cb = false
                if e.cb then pcall(e.cb, e.value) end
            end
        end
    end
end)
re.on_script_reset(function()
    if root_unit and parent_list then pcall(function() parent_list:call("Remove", root_unit) end) end
    end_dialog()                                               -- never leave an orphan dialog behind a fresh Lua state
end)

M._debug = function()
    local out = { built = built, tick = tick, root = root_unit and "yes" or "no", changed = (pcall(lists_changed)) and tostring(lists_changed()) or "err" }
    for _, g in ipairs(groups) do for _, e in ipairs(g.entries) do out[g.title .. "/" .. e.key] = { n = e.options and #e.options or -1, fn = e.options_fn and true or false, unit = e.unit and true or false } end end
    return out
end
-- via.gui.Control of the row currently bound to an entry (nil when the entry is not on the visible page)
-- the entry under the cursor of the open dialog (nil when the focus is not one of ours)
function M.parent_param() return param_stack[#param_stack - 1] end   -- the page underneath the current one (menus)
function M.focused_entry()
    local param = M.current_param
    if not param then return nil end
    local ok, e = pcall(function()
        local u = param:call("GetFocusUnit")
        local x = u and known_ids[u:call("get_Setting").TypeId]
        return x and (x.entry or x) or nil
    end)
    return ok and e or nil
end
-- the UIPartsOptionUnit bound to an entry on the visible page (nil when not shown)
function M.row_part(entry)
    local param = M.current_param
    if not param or not entry or not entry.type_id then return nil end
    local ok, part = pcall(function()
        local parts = param:get_field("OptionUnits")
        if not parts then return nil end
        for i = 0, parts:call("get_Length") - 1 do
            local part = parts:call("GetValue", i)
            local ud = part and part:get_field("UnitData")
            local setting = ud and ud:call("get_Setting")
            if setting and setting.TypeId == entry.type_id then return part end
        end
        return nil
    end)
    return ok and part or nil
end
function M.transitioning() return false end
M.param_alive = function() return true end
function M.row_control(entry, param)
    param = param or M.current_param
    if not param or not entry or not entry.type_id then return nil end
    local ok, ctrl = pcall(function()
        local parts = param:get_field("OptionUnits")
        if not parts then return nil end
        for i = 0, parts:call("get_Length") - 1 do
            local part = parts:call("GetValue", i)
            local ud = part and part:get_field("UnitData")
            local setting = ud and ud:call("get_Setting")
            if setting and setting.TypeId == entry.type_id then return part:call("get_Control") end
        end
        return nil
    end)
    return ok and ctrl or nil
end
M.message_guid = message_guid   -- fake GUID resolved to text by the hMsg hook (other native menus reuse it)
M.message_text = function(guid, str) guid_text[guid:call("ToString()")] = str end   -- retext an existing GUID (dynamic titles)
M.set_guid = set_guid
M.COMPOSITE = COMPOSITE
_G.NativeOptions = M
return M
