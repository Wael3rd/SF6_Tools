-- ============================================================
-- NativeShortcuts — a SEPARATE "Shortcut Settings"-style menu (the game's own UI, app.UIFlowShortcutSetting) that
-- mirrors the REFramework Training Hotkeys menu: every scope/action as a row (On/Off + FUNC+button / key), with
-- OUR OWN FUNC button. Bindings are written into the Training Hotkeys framework (keyboard + controller slots and
-- the controller modifier), which does the detection — the game's shortcut engine never polls our rows.
--
-- How (measured 30/08/2026): app.ShortcutSetting (singleton) draws its menu from
--   _SettingUserData.Data : ShortcutSettingData[]                  definitions (type, texts, defaults)
--   SettingSaveData.ItemDataList : List<ShortcutSettingItemSaveData> state (IsActive, Button, Key, IsFunc)
-- and Start(playerIndex) opens the menu on those lists. While our menu is open we SWAP both lists for ours
-- (a Function row of type 1 = our own FUNC selector, then one row per action, types 100+), block the game's
-- shortcut saves, and put the originals back when the menu ends. Our rows' state lives in
-- data/SF6_NativeShortcuts.json and is pushed into Training_Hotkeys after each visit.
-- ============================================================
local M = {}
local NO = require("func/NativeOptions")
local BASE_TYPE = 100
local FUNC_TYPE = 1                       -- app.ShortcutSettingData.EShortcutType.Function: the menu's FUNC selector row
local SAVE = "SF6_NativeShortcuts.json"

local hotkeys = nil
local actions = {}                        -- { scope_id, action_id, label(), scope_title() }
local rows = {}                           -- built once: { type, data, item, action | nil (FUNC) }
local func_item = nil
local saved = json.load_file(SAVE) or {}  -- key -> { active, button, key, func }
local built = false
local swapped = nil                       -- { data=, items= } originals while our menu is open
local open_request = false
local tick = 0

function M.use_hotkeys(H) hotkeys = H end
function M.open() open_request = true end
function M.is_open() return swapped ~= nil end

local function key_of(a) return a.scope_id .. "/" .. a.action_id end
local function label_of(a) local ok, s = pcall(function() return a.scope_title() .. ": " .. a.label() end); return ok and s or key_of(a) end

-- ---------- build our lists ----------
local function new_data(t, title, guide, key_input)
    local d = sdk.create_instance("app.ShortcutSettingData")
    d.ShortCutType = t
    NO.set_guid(d, "ItemMessage", NO.message_guid(title))
    NO.set_guid(d, "GuideMessage", NO.message_guid(guide))
    d.DefaultButton = 0; d.DefaultKey = 0; d.IsDefaultFunc = true; d.IsKeyInput = key_input and true or false
    d.IsDefaultActive = false; d.ForceEventBits = 0
    pcall(function() d:add_ref() end)
    return d
end
local function new_item(d, t)
    local it = sdk.create_instance("app.ShortcutSaveData.ShortcutSettingItemSaveData")
    pcall(function() it:add_ref() end)
    it:call("Reset", d)
    it.ShortCutType = t
    return it
end
local function restore_state(row, key)
    local s = saved[key]; if not s then return end
    pcall(function()
        row.item.IsActive = s.active == true; row.item.IsFunc = s.func ~= false
        row.item.Button = s.button or 0; row.item.Key = s.key or 0
    end)
end

local function build()
    if built then return true end
    if not (hotkeys and hotkeys.list_actions) then return false end
    actions = hotkeys.list_actions()
    if #actions == 0 then return false end
    rows = {}
    -- our FUNC selector (mirrors the framework's controller modifier)
    local fd = new_data(FUNC_TYPE, "SF6 Tools Function Button", "The modifier held with a button for every SF6 Tools controller shortcut.", false)
    func_item = new_item(fd, FUNC_TYPE)
    pcall(function() func_item.IsFunc = false; func_item.Button = hotkeys.get_controller_mod and hotkeys.get_controller_mod() or 16384 end)
    rows[#rows + 1] = { type = FUNC_TYPE, data = fd, item = func_item }
    for i, a in ipairs(actions) do
        local t = BASE_TYPE + i - 1
        local d = new_data(t, label_of(a), "SF6 Tools: " .. label_of(a), true)
        local it = new_item(d, t)
        local row = { type = t, data = d, item = it, action = a }
        restore_state(row, key_of(a))
        -- first time: seed from the framework's current bindings
        if not saved[key_of(a)] and hotkeys.get_binding then
            local c = hotkeys.get_binding(a.scope_id, a.action_id, "controller")
            local k = hotkeys.get_binding(a.scope_id, a.action_id, "keyboard")
            pcall(function()
                if c and tonumber(c.button) then it.Button = tonumber(c.button); it.IsFunc = true; it.IsActive = true end
                if k and tonumber(k.vk) then it.Key = tonumber(k.vk); it.IsActive = true end
            end)
        end
        rows[#rows + 1] = row
    end
    built = true
    return true
end

-- ---------- push the menu's result into the hotkeys framework ----------
local function apply_to_hotkeys()
    if not hotkeys then return end
    pcall(function()
        local fb = func_item and tonumber(func_item:get_field("Button")) or nil
        if fb and hotkeys.set_controller_mod then hotkeys.set_controller_mod(fb) end
        for _, row in ipairs(rows) do
            if row.action then
                local it = row.item
                local active = it:get_field("IsActive") == true
                local btn, key = tonumber(it:get_field("Button")) or 0, tonumber(it:get_field("Key")) or 0
                saved[key_of(row.action)] = { active = active, func = it:get_field("IsFunc") == true, button = btn, key = key }
                if hotkeys.set_binding then
                    hotkeys.set_binding(row.action.scope_id, row.action.action_id, "controller", (active and btn > 0) and { device = "gamepad", button = btn } or nil)
                    hotkeys.set_binding(row.action.scope_id, row.action.action_id, "keyboard", (active and key > 0) and { device = "keyboard", vk = key, mods = {} } or nil)
                end
                if active and hotkeys.enable_scope then hotkeys.enable_scope(row.action.scope_id, true) end
            end
        end
        json.dump_file(SAVE, saved)
    end)
end

-- ---------- open / close (swap the engine's lists) ----------
local function engine() return sdk.get_managed_singleton("app.ShortcutSetting") end
local function do_open()
    local sc = engine(); if not sc then return false end
    local ud = sc:get_field("<_SettingUserData>k__BackingField"); local sd = sc:call("get_SettingSaveData")
    if not (ud and sd) then return false end
    local orig_data, orig_items = ud:get_field("Data"), sd:get_field("ItemDataList")
    if not (orig_data and orig_items) then return false end
    local arr = sdk.create_managed_array("app.ShortcutSettingData", #rows)
    local list = orig_items:call("GetRange", 0, 0)     -- an empty list of the right generic type
    for i, row in ipairs(rows) do arr:call("SetValue", row.data, i - 1); list:call("Add", row.item) end
    swapped = { ud = ud, sd = sd, data = orig_data, items = orig_items }
    ud.Data = arr; sd.ItemDataList = list
    local ok = sc:call("Start", 0)
    if ok ~= true then ud.Data = orig_data; sd.ItemDataList = orig_items; swapped = nil; return false end
    return true
end
local function do_close()
    if not swapped then return end
    pcall(function() swapped.ud.Data = swapped.data; swapped.sd.ItemDataList = swapped.items end)
    swapped = nil
    apply_to_hotkeys()
end

-- While our lists are swapped in, the game must not write its shortcut save (it would keep our rows / our FUNC).
local sd_td = sdk.find_type_definition("app.ShortcutSaveData")
if sd_td then
    for _, sig in ipairs({ "Save(app.ShortcutSaveData.ShortcutSettingSaveData)" }) do
        local m = sd_td:get_method(sig)
        if m then sdk.hook(m, function(args) if swapped then return sdk.PreHookResult.SKIP_ORIGINAL end end, function(rv) return rv end) end
    end
end
local ss_td = sdk.find_type_definition("app.ShortcutSetting")
if ss_td then
    for _, sig in ipairs({ "Save(System.Int32)", "SaveExternal(app.ShortcutSaveData.ShortcutSettingSaveData)" }) do
        local m = ss_td:get_method(sig)
        if m then sdk.hook(m, function(args) if swapped then return sdk.PreHookResult.SKIP_ORIGINAL end end, function(rv) return rv end) end
    end
end

-- ---------- game thread ----------
re.on_pre_application_entry("LateUpdateBehavior", function()
    tick = tick + 1
    if open_request and not swapped then
        open_request = false
        if _G.TrainingModeActive and build() then pcall(do_open) end
    end
    if swapped and tick % 10 == 0 then
        local sc = engine()
        local opening = sc and (pcall(function() return sc:call("get_IsOpening") end)) and sc:call("get_IsOpening")
        if not opening then do_close() end
    end
end)
re.on_script_reset(function() if swapped then pcall(function() swapped.ud.Data = swapped.data; swapped.sd.ItemDataList = swapped.items end) end end)

_G.NativeShortcuts = M
return M
