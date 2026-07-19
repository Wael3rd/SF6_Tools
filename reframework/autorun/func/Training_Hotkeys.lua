-- =========================================================
-- Training_Hotkeys.lua - Shared multi-device hotkey registry.
-- Modules register actions; ScriptManager draws one global menu.
-- Defaults are intentionally disabled and unbound.
-- Core is language-neutral; chrome strings live in the L table (per-language).
-- Ported from SF6_TOOLS_CC for convergence; English chrome.
-- =========================================================

local json = json
local fs = fs
local imgui = imgui
local reframework = reframework
local sdk = sdk

local M = {}

-- Localizable chrome strings routed through the shared i18n registry so the
-- hotkey menu follows the global EN/中文 toggle. `L.key` resolves live.
local i18n = require("func/i18n")
local UIKit = require("func/UIKit")
i18n.register("hotkeys", {
    en = {
        menu_title = "Training Hotkeys",
        menu_hint  = "Bind keyboard and/or controller shortcuts. Disabled and unbound by default.",
        unbound   = "Unbound",
        bind      = "Bind",
        clear     = "Clear",
        bound     = "Bound: ",
        capturing = "Press a key or device button; ESC to cancel.",
        capturing_kb  = "Press a keyboard key; ESC to cancel.",
        capturing_pad = "Press a controller button; ESC to cancel.",
        kb_prefix  = "Keyboard",
        pad_prefix = "Controller",
        pad_mod_label = "Controller modifier (hold)",
        pad_mod_none  = "None (bare buttons)",
        pad_mod_note  = "Hold this button for any controller shortcut to fire.",
        enabled_toggle = "Enabled",
        disabled_note  = "(disabled)",
        debug_probe    = "Device probe (debug)",
        bindings_defined = "BINDINGS DEFINED",
        conflict  = "Conflict: ",
        enable    = "Enable ",
        enable_suffix = " hotkeys",
        probe     = "Device probe: HID=0x%X  game=0x%X  last=%s",
        no_scopes = "No modules registered hotkey actions.",
    },
    zh = {
        menu_title = "训练快捷键",
        menu_hint  = "绑定键盘和/或手柄快捷键。默认关闭且未绑定。",
        unbound   = "未绑定",
        bind      = "绑定",
        clear     = "清除",
        bound     = "当前绑定: ",
        capturing = "请按键或设备按钮；ESC 取消。",
        capturing_kb  = "请按键盘按键；ESC 取消。",
        capturing_pad = "请按手柄按钮；ESC 取消。",
        kb_prefix  = "键盘",
        pad_prefix = "手柄",
        pad_mod_label = "手柄修饰键（按住）",
        pad_mod_none  = "无（直接按键）",
        pad_mod_note  = "按住此键，手柄快捷键才会触发。",
        enabled_toggle = "启用",
        disabled_note  = "（已禁用）",
        debug_probe    = "设备检测（调试）",
        bindings_defined = "个绑定",
        conflict  = "冲突: ",
        enable    = "启用 ",
        enable_suffix = " 快捷键",
        probe     = "设备检测: HID=0x%X  游戏输入=0x%X  最近来源=%s",
        no_scopes = "暂无模块注册快捷键动作。",
    },
})
local L = setmetatable({}, { __index = function(_, k) return i18n.t("hotkeys", k) end })

-- title/label may be a plain string or a function (live i18n resolution)
local function resolve_text(v)
    if type(v) == "function" then
        local ok, r = pcall(v)
        return ok and r or ""
    end
    return v
end

local CONFIG_FILE = "Training_ScriptManager_data/TrainingHotkeys_Config.json"

local MODIFIER_VKS = { 0x10, 0x11, 0x12, 0x5B, 0x5C }
local MOD_SET = {}
for _, vk in ipairs(MODIFIER_VKS) do MOD_SET[vk] = true end

local VK_NAMES = {
    [0x08]="BACKSPACE",[0x09]="TAB",[0x0D]="ENTER",[0x10]="SHIFT",[0x11]="CTRL",[0x12]="ALT",
    [0x14]="CAPS",[0x1B]="ESC",[0x20]="SPACE",
    [0x21]="PGUP",[0x22]="PGDN",[0x23]="END",[0x24]="HOME",[0x25]="LEFT",[0x26]="UP",[0x27]="RIGHT",[0x28]="DOWN",
    [0x2D]="INSERT",[0x2E]="DELETE",
    [0x30]="0",[0x31]="1",[0x32]="2",[0x33]="3",[0x34]="4",[0x35]="5",[0x36]="6",[0x37]="7",[0x38]="8",[0x39]="9",
    [0x41]="A",[0x42]="B",[0x43]="C",[0x44]="D",[0x45]="E",[0x46]="F",[0x47]="G",[0x48]="H",[0x49]="I",
    [0x4A]="J",[0x4B]="K",[0x4C]="L",[0x4D]="M",[0x4E]="N",[0x4F]="O",[0x50]="P",[0x51]="Q",[0x52]="R",
    [0x53]="S",[0x54]="T",[0x55]="U",[0x56]="V",[0x57]="W",[0x58]="X",[0x59]="Y",[0x5A]="Z",
    [0x60]="NUM0",[0x61]="NUM1",[0x62]="NUM2",[0x63]="NUM3",[0x64]="NUM4",
    [0x65]="NUM5",[0x66]="NUM6",[0x67]="NUM7",[0x68]="NUM8",[0x69]="NUM9",
    [0x70]="F1",[0x71]="F2",[0x72]="F3",[0x73]="F4",[0x74]="F5",[0x75]="F6",
    [0x76]="F7",[0x77]="F8",[0x78]="F9",[0x79]="F10",[0x7A]="F11",[0x7B]="F12",
    [0xBA]=";",[0xBB]="=",[0xBC]=",",[0xBD]="-",[0xBE]=".",[0xBF]="/",[0xC0]="`",
}

local PAD_BUTTON_NAMES = {
    [1] = "PAD_UP",
    [2] = "PAD_DOWN",
    [4] = "PAD_LEFT",
    [8] = "PAD_RIGHT",
    [16] = "PAD_L3",
    [32] = "PAD_A/CROSS",
    [64] = "PAD_B/CIRCLE",
    [128] = "PAD_X/SQUARE",
    [256] = "PAD_Y/TRIANGLE",
    [512] = "PAD_LB/L1",
    [1024] = "PAD_RB/R1",
    [2048] = "PAD_LT/L2",
    [4096] = "PAD_RT/R2",
    [8192] = "PAD_BACK/SELECT",
    [16384] = "PAD_FUNC",
    [32768] = "PAD_START",
}

local GAME_INPUT_NAMES = {
    [1] = "GAME_8",
    [2] = "GAME_2",
    [4] = "GAME_4",
    [8] = "GAME_6",
    [16] = "GAME_LP",
    [32] = "GAME_MP",
    [64] = "GAME_HP",
    [128] = "GAME_LK",
    [256] = "GAME_MK",
    [512] = "GAME_HK",
    [144] = "GAME_THROW",
    [288] = "GAME_PARRY",
    [576] = "GAME_DI",
}

-- Controller modifier: a pad button that must be HELD alongside any gamepad
-- binding for it to fire (mirrors the legacy FUNC-hold). Default = PAD_FUNC.
-- Set to 0 (Clear in the menu) to allow bare controller buttons.
local DEFAULT_PAD_MOD = 16384

local registry = {}
local scope_order = {}
local config = { scopes = {}, controller_mod = DEFAULT_PAD_MOD }
local loaded = false
local capture = nil
local capture_release_wait = false
local last_down = {}
local debug_state = {
    pad_mask = 0,
    game_mask = 0,
    last_source = "none",
}

local function safe_load_json(path)
    if _G.safe_load_json then return _G.safe_load_json(path) end
    local ok, data = pcall(json.load_file, path)
    return ok and data or nil
end

local function save_config()
    if fs and fs.create_dir then pcall(fs.create_dir, "Training_ScriptManager_data") end
    json.dump_file(CONFIG_FILE, config)
end

local function load_config()
    if loaded then return end
    loaded = true
    local data = safe_load_json(CONFIG_FILE)
    if type(data) == "table" then
        if type(data.scopes) == "table" then config.scopes = data.scopes end
        if type(data.controller_mod) == "number" then config.controller_mod = data.controller_mod end
    end
end

local function ensure_scope_config(scope_id, enabled_default)
    load_config()
    if type(config.scopes[scope_id]) ~= "table" then
        config.scopes[scope_id] = {
            enabled = enabled_default == true,
            bindings = {},
        }
        save_config()
    end
    local scope_cfg = config.scopes[scope_id]
    if type(scope_cfg.bindings) ~= "table" then scope_cfg.bindings = {} end
    if scope_cfg.enabled == nil then scope_cfg.enabled = enabled_default == true end
    return scope_cfg
end

local function read_key(vk)
    if not reframework or not reframework.is_key_down then return false end
    local ok, down = pcall(reframework.is_key_down, reframework, vk)
    return ok and down == true
end

local function read_pad_mask()
    if not sdk or not sdk.get_native_singleton or not sdk.find_type_definition or not sdk.call_native_func then return 0 end
    local ok, mask = pcall(function()
        local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
        local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
        if not gamepad_manager or not gamepad_type then return 0 end
        local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
        if not devices then return 0 end
        local count = devices:call("get_Count") or 0
        local combined = 0
        for i = 0, count - 1 do
            local pad = devices:call("get_Item", i)
            if pad then
                local buttons = pad:call("get_Button") or 0
                if buttons > 0 then combined = combined | buttons end
            end
        end
        return combined
    end)
    return ok and (tonumber(mask) or 0) or 0
end

local function read_game_input_mask()
    local gs = _G.GameState
    local p1 = gs and gs.p1
    if not p1 then return 0 end
    local ok, mask = pcall(function()
        local td = p1:get_type_definition()
        if not td then return 0 end
        local f_input = td:get_field("pl_input_new")
        local f_sw = td:get_field("pl_sw_new")
        local input = (f_input and f_input:get_data(p1)) or 0
        local sw = (f_sw and f_sw:get_data(p1)) or 0
        return (input | sw) & 0xFFFF
    end)
    return ok and (tonumber(mask) or 0) or 0
end

function M.vk_name(vk)
    return VK_NAMES[vk] or string.format("0x%02X", tonumber(vk) or 0)
end

local function bitmask_name(mask, names, prefix)
    mask = tonumber(mask) or 0
    if mask <= 0 then return prefix .. "_NONE" end
    if names[mask] then return names[mask] end

    local parts = {}
    local remaining = mask
    local bit = 1
    while remaining > 0 and bit <= 0x40000000 do
        if (mask & bit) ~= 0 then
            parts[#parts + 1] = names[bit] or string.format("%s_0x%X", prefix, bit)
            remaining = remaining & ~bit
        end
        bit = bit << 1
    end
    return #parts > 0 and table.concat(parts, " + ") or string.format("%s_0x%X", prefix, mask)
end

function M.pad_button_name(mask)
    return bitmask_name(mask, PAD_BUTTON_NAMES, "PAD")
end

function M.game_input_name(mask)
    return bitmask_name(mask, GAME_INPUT_NAMES, "GAME")
end

local function sort_mods(mods)
    table.sort(mods, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    return mods
end

local function binding_device(binding)
    if type(binding) ~= "table" then return nil end
    if binding.device then return binding.device end
    if binding.vk then return "keyboard" end
    if binding.button then return "gamepad" end
    if binding.input then return "game_input" end
    return nil
end

function M.combo_name(binding)
    if type(binding) ~= "table" then return L.unbound end
    local device = binding_device(binding)
    if device == "gamepad" then
        local mod = tonumber(config.controller_mod) or 0
        local btn = tonumber(binding.button) or 0
        if mod > 0 and (btn & mod) ~= mod then
            return M.pad_button_name(mod) .. " + " .. M.pad_button_name(btn)
        end
        return M.pad_button_name(btn)
    end
    if device == "game_input" then
        return M.game_input_name(binding.input)
    end
    if not binding.vk then return L.unbound end
    local parts = {}
    for _, m in ipairs(binding.mods or {}) do parts[#parts + 1] = M.vk_name(m) end
    parts[#parts + 1] = M.vk_name(binding.vk)
    return table.concat(parts, " + ")
end

local function binding_key(binding)
    if type(binding) ~= "table" then return nil end
    local device = binding_device(binding)
    if device == "gamepad" then
        local button = tonumber(binding.button) or 0
        return button > 0 and ("gamepad|" .. tostring(button)) or nil
    end
    if device == "game_input" then
        local input = tonumber(binding.input) or 0
        return input > 0 and ("game_input|" .. tostring(input)) or nil
    end
    if not binding.vk then return nil end
    local mods = {}
    for _, m in ipairs(binding.mods or {}) do mods[#mods + 1] = tonumber(m) or m end
    sort_mods(mods)
    return "keyboard|" .. table.concat(mods, "+") .. "|" .. tostring(binding.vk)
end

-- A binding container holds up to two bindings for one action:
--   { keyboard = <binding|nil>, controller = <binding|nil> }
-- Legacy configs stored a single flat binding; normalize converts those to
-- the container shape (read-only; migration is persisted on the next bind/clear).
local function normalize_container(b)
    if type(b) ~= "table" then return {} end
    if b.keyboard ~= nil or b.controller ~= nil then return b end
    local dev = binding_device(b)
    if dev == "keyboard" then return { keyboard = b }
    elseif dev == "gamepad" or dev == "game_input" then return { controller = b } end
    return {}
end

local function binding_down(binding, pad_mask, game_mask)
    if type(binding) ~= "table" then return false end
    local device = binding_device(binding)
    if device == "gamepad" then
        local button = tonumber(binding.button) or 0
        if button <= 0 then return false end
        -- Require the global controller modifier (FUNC by default) to be held,
        -- so bare gameplay directions never trigger shortcuts.
        local mod = tonumber(config.controller_mod) or 0
        local required = button | mod
        return ((pad_mask or 0) & required) == required
    end
    if device == "game_input" then
        local input = tonumber(binding.input) or 0
        if input <= 0 then return false end
        return ((game_mask or 0) & input) == input
    end
    if not binding.vk then return false end
    if not read_key(binding.vk) then return false end
    local required = {}
    for _, m in ipairs(binding.mods or {}) do
        required[m] = true
        if not read_key(m) then return false end
    end
    for _, m in ipairs(MODIFIER_VKS) do
        if not required[m] and read_key(m) then return false end
    end
    return true
end

-- slot: "keyboard" scans only the keyboard; "controller" scans only pad /
-- game_input. This lets one action carry a keyboard AND a controller binding.
local function scan_binding(pad_mask, game_mask, slot)
    if read_key(0x1B) then return "cancel" end
    slot = slot or "keyboard"

    if slot == "controller" then
        pad_mask = pad_mask or 0
        local pad_baseline = (capture and capture.pad_baseline) or 0
        if capture and pad_mask == 0 and pad_baseline ~= 0 then
            capture.pad_baseline = 0
            pad_baseline = 0
        end
        local new_pad_mask = pad_mask & ~pad_baseline
        if new_pad_mask > 0 then
            return { device = "gamepad", button = new_pad_mask }
        end

        game_mask = game_mask or 0
        local game_baseline = (capture and capture.game_baseline) or 0
        if capture and game_mask == 0 and game_baseline ~= 0 then
            capture.game_baseline = 0
            game_baseline = 0
        end
        local new_game_mask = game_mask & ~game_baseline
        if new_game_mask > 0 then
            return { device = "game_input", input = new_game_mask }
        end
        return nil
    end

    -- keyboard slot
    local mods = {}
    for _, mk in ipairs(MODIFIER_VKS) do
        if read_key(mk) then mods[#mods + 1] = mk end
    end
    for vk = 0x08, 0xC0 do
        if not MOD_SET[vk] and read_key(vk) then
            return { device = "keyboard", vk = vk, mods = sort_mods(mods) }
        end
    end
    return nil
end

local function any_binding_key_down(pad_mask, game_mask)
    if (pad_mask or 0) > 0 then return true end
    if (game_mask or 0) > 0 then return true end
    for vk = 0x08, 0xC0 do
        if read_key(vk) then return true end
    end
    return false
end

function M.register_scope(scope_id, spec)
    if type(scope_id) ~= "string" or scope_id == "" then return false end
    spec = spec or {}
    local scope = registry[scope_id]
    if not scope then
        scope = {
            id = scope_id,
            title = spec.title or scope_id,
            order = spec.order or (#scope_order + 1),
            actions = {},
            action_order = {},
            enabled_default = spec.enabled_default == true,
        }
        registry[scope_id] = scope
        scope_order[#scope_order + 1] = scope_id
    else
        scope.title = spec.title or scope.title
        scope.order = spec.order or scope.order
        scope.enabled_default = spec.enabled_default == true
    end

    ensure_scope_config(scope_id, scope.enabled_default)

    for _, action in ipairs(spec.actions or {}) do
        if type(action) == "table" and type(action.id) == "string" then
            if not scope.actions[action.id] then
                scope.action_order[#scope.action_order + 1] = action.id
            end
            scope.actions[action.id] = action
        end
    end
    table.sort(scope_order, function(a, b)
        return (registry[a].order or 0) < (registry[b].order or 0)
    end)
    return true
end

function M.is_scope_enabled(scope_id)
    local scope_cfg = config.scopes[scope_id]
    return type(scope_cfg) == "table" and scope_cfg.enabled == true
end

function M.get_binding(scope_id, action_id, slot)
    local scope_cfg = config.scopes[scope_id]
    if type(scope_cfg) ~= "table" or type(scope_cfg.bindings) ~= "table" then return nil end
    local container = normalize_container(scope_cfg.bindings[action_id])
    return container[slot or "keyboard"]
end

function M.get_label(scope_id, action_id, slot)
    return M.combo_name(M.get_binding(scope_id, action_id, slot))
end

local SLOTS = { "keyboard", "controller" }

-- Reports actions whose keyboard OR controller binding collides with either of
-- this action's bindings. A keyboard bind and a controller bind never collide
-- with each other (different device namespaces in binding_key).
local function find_conflicts(scope_id, action_id)
    local scope_cfg = config.scopes[scope_id]
    if type(scope_cfg) ~= "table" then return nil end
    local mine = normalize_container(scope_cfg.bindings and scope_cfg.bindings[action_id])
    local targets = {}
    for _, sl in ipairs(SLOTS) do
        local k = binding_key(mine[sl])
        if k then targets[k] = true end
    end
    if not next(targets) then return nil end
    local hits = {}
    for _, sid in ipairs(scope_order) do
        local scope = registry[sid]
        local other_cfg = config.scopes[sid]
        if scope and other_cfg and type(other_cfg.bindings) == "table" then
            for _, aid in ipairs(scope.action_order) do
                if not (sid == scope_id and aid == action_id) then
                    local other = normalize_container(other_cfg.bindings[aid])
                    local clash = false
                    for _, sl in ipairs(SLOTS) do
                        local k = binding_key(other[sl])
                        if k and targets[k] then clash = true break end
                    end
                    if clash then
                        local action = scope.actions[aid]
                        hits[#hits + 1] = (resolve_text(scope.title) or sid) .. " / " .. (resolve_text(action and action.label) or aid)
                    end
                end
            end
        end
    end
    return #hits > 0 and table.concat(hits, ", ") or nil
end

-- Layout columns (pixels from the row start), tuned for the REFramework menu.
local COL_BINDING = 96   -- where the binding value starts
local COL_BUTTONS = 260  -- minimum x for the Bind/Clear buttons

-- One aligned sub-row for a single device slot:
--   "  <prefix>      <binding>                    [Bind] [Clear]"
-- Bound = cyan, unbound = grey, capturing = orange. Buttons right-aligned.
local function draw_bind_line(scope, scope_cfg, action_id, slot, prefix)
    local container = normalize_container(scope_cfg.bindings[action_id])
    local binding = container[slot]
    local cap = capture and capture.scope_id == scope.id
        and capture.action_id == action_id and capture.slot == slot
    local start = imgui.get_cursor_pos()
    local win_w = imgui.get_window_size().x

    -- device prefix
    imgui.text_colored("  " .. prefix, 0xFFB0B0B0)

    -- binding value at a fixed column
    imgui.set_cursor_pos(Vector2f.new(start.x + COL_BINDING, start.y))
    if cap then
        imgui.text_colored(slot == "controller" and L.capturing_pad or L.capturing_kb, 0xFF00A5FF)
        return
    end
    local bound = binding ~= nil
    imgui.text_colored(bound and M.combo_name(binding) or L.unbound, bound and 0xFF00FFFF or 0xFF808080)

    -- right-aligned Bind / Clear
    local bw = imgui.calc_text_size(L.bind).x + 16
    local cw = imgui.calc_text_size(L.clear).x + 16
    local bx = math.max(start.x + COL_BUTTONS, win_w - bw - cw - 28)
    imgui.set_cursor_pos(Vector2f.new(bx, start.y))
    if imgui.button(L.bind .. "##hk_bind_" .. scope.id .. "_" .. action_id .. "_" .. slot) then
        capture = {
            scope_id = scope.id,
            action_id = action_id,
            slot = slot,
            pad_baseline = read_pad_mask(),
            game_baseline = read_game_input_mask(),
        }
    end
    imgui.same_line(0, 4)
    if imgui.button(L.clear .. "##hk_clear_" .. scope.id .. "_" .. action_id .. "_" .. slot) then
        container[slot] = nil
        scope_cfg.bindings[action_id] = container
        save_config()
    end
end

-- Number of actions in a scope that have at least one binding.
local function count_bound(scope, scope_cfg)
    if not scope_cfg or type(scope_cfg.bindings) ~= "table" then return 0 end
    local n = 0
    for _, aid in ipairs(scope.action_order) do
        local c = normalize_container(scope_cfg.bindings[aid])
        if c.keyboard or c.controller then n = n + 1 end
    end
    return n
end

function M.is_input_blocked()
    return capture ~= nil or capture_release_wait
end

function M.update(suspended)
    load_config()

    if suspended then
        _G.TrainingFuncHeld = false
        _G.TrainingPadMask = 0
        _G.TrainingGameInputMask = 0
        return
    end
    local pad_mask = read_pad_mask()
    local game_mask = read_game_input_mask()
    debug_state.pad_mask = pad_mask
    debug_state.game_mask = game_mask

    -- Publish input state for consumers. _G.TrainingFuncHeld = modifier held
    -- (ComboTrials suppresses P1 inputs with it during a trial). PadMask is the
    -- raw HID button mask (incl. D-pad / arcade stick); GameInputMask is the
    -- processed game input. Dropdowns use these for controller navigation.
    local _mod = tonumber(config.controller_mod) or 0
    _G.TrainingFuncButton = (_mod > 0) and _mod or nil
    _G.TrainingFuncHeld = (_mod > 0) and ((pad_mask & _mod) == _mod) or false
    _G.TrainingPadMask = pad_mask
    _G.TrainingGameInputMask = game_mask

    if capture_release_wait then
        if not any_binding_key_down(pad_mask, game_mask) then capture_release_wait = false end
        return
    end

    if capture then
        -- Capturing the global controller modifier (a single pad button).
        if capture.kind == "pad_mod" then
            local binding = scan_binding(pad_mask, game_mask, "controller")
            if binding == "cancel" then
                capture = nil
                capture_release_wait = true
                return
            elseif type(binding) == "table" and binding.device == "gamepad" then
                config.controller_mod = tonumber(binding.button) or 0
                save_config()
                capture = nil
                capture_release_wait = true
                return
            end
            return
        end
        local binding = scan_binding(pad_mask, game_mask, capture.slot)
        if binding == "cancel" then
            capture = nil
            capture_release_wait = true
            return
        elseif type(binding) == "table" then
            debug_state.last_source = binding.device or "unknown"
            local scope_cfg = ensure_scope_config(capture.scope_id, false)
            local container = normalize_container(scope_cfg.bindings[capture.action_id])
            container[capture.slot or "keyboard"] = binding
            scope_cfg.bindings[capture.action_id] = container
            save_config()
            capture = nil
            capture_release_wait = true
            return
        end
        return
    end

    for _, scope_id in ipairs(scope_order) do
        local scope = registry[scope_id]
        local scope_cfg = config.scopes[scope_id]
        if scope and scope_cfg and scope_cfg.enabled == true then
            for _, action_id in ipairs(scope.action_order) do
                local action = scope.actions[action_id]
                local container = normalize_container(scope_cfg.bindings and scope_cfg.bindings[action_id])
                -- Fire on either device; per-slot edge tracking so keyboard and
                -- controller each trigger once on their own press.
                for _, sl in ipairs(SLOTS) do
                    local binding = container[sl]
                    local key = scope_id .. "." .. action_id .. "." .. sl
                    local is_down = binding_down(binding, pad_mask, game_mask)
                    if is_down and not last_down[key] then
                        local allowed = true
                        if type(action.enabled) == "function" then
                            local ok, result = pcall(action.enabled)
                            allowed = ok and result ~= false
                        end
                        if allowed and type(action.run) == "function" then pcall(action.run) end
                    end
                    last_down[key] = is_down
                end
            end
        end
    end
end

local function draw_scope(scope)
    local scope_cfg = ensure_scope_config(scope.id, scope.enabled_default)

    local changed, enabled = imgui.checkbox(L.enabled_toggle .. "##hk_enabled_" .. scope.id, scope_cfg.enabled == true)
    if changed then
        scope_cfg.enabled = enabled == true
        save_config()
    end
    if not scope_cfg.enabled then
        imgui.same_line(0, 10)
        imgui.text_colored(L.disabled_note, 0xFF808080)
    end
    imgui.spacing()

    for _, action_id in ipairs(scope.action_order) do
        local action = scope.actions[action_id]
        if action then
            imgui.text_colored(resolve_text(action.label) or action_id, 0xFFFFFFFF)
            draw_bind_line(scope, scope_cfg, action_id, "keyboard", L.kb_prefix)
            draw_bind_line(scope, scope_cfg, action_id, "controller", L.pad_prefix)

            local conflict = find_conflicts(scope.id, action_id)
            if conflict then
                imgui.text_colored("  ! " .. L.conflict .. conflict, 0xFF0000FF)
            end
            imgui.spacing()
        end
    end
end

-- Header color per scope (matches the styled sub-headers used across scripts).
local SCOPE_HDR_STYLE = {
    script_manager  = UIKit.THEME.hdr_gold,
    session         = UIKit.THEME.hdr_skyblue,
    combo_trials    = UIKit.THEME.hdr_purple,
    distance_viewer = UIKit.THEME.hdr_green,
}

function M.draw_menu()
    load_config()
    if #scope_order == 0 then
        imgui.text_colored(L.no_scopes, 0xFF888888)
        return
    end

    -- Global controller modifier (hold) — must be held for any pad binding to fire.
    -- Label on its own line; value + buttons on the next line (no overlap).
    imgui.text_colored(L.pad_mod_label, 0xFFFFFFFF)
    do
        local start = imgui.get_cursor_pos()
        local win_w = imgui.get_window_size().x
        local mod = tonumber(config.controller_mod) or 0
        imgui.text_colored("  " .. (mod > 0 and M.pad_button_name(mod) or L.pad_mod_none), mod > 0 and 0xFF00FFFF or 0xFF808080)
        if capture and capture.kind == "pad_mod" then
            imgui.set_cursor_pos(Vector2f.new(start.x + COL_BUTTONS, start.y))
            imgui.text_colored(L.capturing_pad, 0xFF00A5FF)
        else
            local bw = imgui.calc_text_size(L.bind).x + 16
            local cw = imgui.calc_text_size(L.clear).x + 16
            imgui.set_cursor_pos(Vector2f.new(math.max(start.x + COL_BUTTONS, win_w - bw - cw - 28), start.y))
            if imgui.button(L.bind .. "##hk_padmod_bind") then
                capture = { kind = "pad_mod", pad_baseline = read_pad_mask(), game_baseline = read_game_input_mask() }
            end
            imgui.same_line(0, 4)
            if imgui.button(L.clear .. "##hk_padmod_clear") then
                config.controller_mod = 0
                save_config()
            end
        end
    end
    imgui.text_colored(L.pad_mod_note, 0xFF808080)
    imgui.spacing()
    imgui.separator()
    imgui.spacing()

    for _, scope_id in ipairs(scope_order) do
        local scope = registry[scope_id]
        if scope then
            local bound = count_bound(scope, config.scopes[scope_id])
            local total = #scope.action_order
            local title = resolve_text(scope.title) or scope_id
            local style = SCOPE_HDR_STYLE[scope_id] or UIKit.THEME.hdr_blue

            -- Header label is STABLE (title only): including the changing count
            -- would alter the header id and collapse it on every bind. The count
            -- is drawn separately, right-aligned on the header row.
            local start = imgui.get_cursor_pos()
            local open = UIKit.styled_header(title .. "##hk_scope_" .. scope_id, style)
            local after = imgui.get_cursor_pos()

            local count_str = string.format("%d/%d %s", bound, total, L.bindings_defined)
            local win_w = imgui.get_window_size().x
            local cwid = imgui.calc_text_size(count_str).x
            imgui.set_cursor_pos(Vector2f.new(math.max(start.x + 12, win_w - cwid - 40), start.y + 3))
            imgui.text_colored(count_str, 0xFFCFCFCF)
            imgui.set_cursor_pos(after)

            if open then
                imgui.spacing()
                draw_scope(scope)
                imgui.spacing()
            end
        end
    end

    -- Device probe (debug) — collapsed at the bottom.
    imgui.spacing()
    imgui.separator()
    if imgui.tree_node(L.debug_probe .. "##hk_debug") then
        imgui.text_colored(string.format(
            L.probe,
            debug_state.pad_mask or 0,
            debug_state.game_mask or 0,
            debug_state.last_source or "none"
        ), 0xFF888888)
        imgui.tree_pop()
    end
end

-- Independent top-level menu in the REFramework "Script Generated UI", so the
-- hotkey config is not buried inside the Script Manager submenu. Input reading
-- (M.update) is still driven by Script Manager, where the training-context
-- killswitch and replay handling live.
if re and re.on_draw_ui then
    re.on_draw_ui(function()
        if imgui.tree_node("TRAINING HOTKEYS") then
            imgui.text_colored(L.menu_hint, 0xFF888888)
            imgui.separator()
            M.draw_menu()
            imgui.tree_pop()
        end
    end)
end

return M
